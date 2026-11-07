-- Synthetic tests for the TRM: Industry Emissions fix (docs/compatibility.md), run outside the game by
-- tools/test_wrapper_load.py, which first turns the mod's .tl files into Lua with `tl gen`.
--
-- What is real: the generated mod.script.tl (its loadConstruction and loadModule modifiers), construction.script.tl and
-- levels.tl, the mod's construction_wrapper.script.lua, and runsWrapper cut out of the generated retrofits.script.tl.
-- What is a stand-in: ug_require, the engine's script loader and base util.useFn (both load "x.script@fn" as x.script.lua
-- with data(), or else as the module x.script.tl), a base depot script, a module script, and a TRM-like wrapper written
-- here from TRM's described behaviour: it adds ".lua" to the reference it wraps, loads that with ug_require, calls the
-- global data(), runs the function and halves pollution and noise. None of TRM's code is used.
--
-- Usage: lua5.1 tools/wrapper_load_test.lua <generated lua folder> <mod content folder>

local genDir, contentDir = arg[1], arg[2]
assert(genDir and contentDir, "usage: wrapper_load_test.lua <generated lua folder> <mod content folder>")

local passed, failed = 0, 0
local function check(name, ok, detail)
	if ok then
		passed = passed + 1
		print("PASS  " .. name)
	else
		failed = failed + 1
		print("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
	end
end
local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-9 end

local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text
end

-- Files by the name a script asks for. A value is Lua source (run like a file) or a module value (returned as it is).
local virtual = {}
local generatedOverride = {} -- generated module name -> replacement source

local function sourceOf(path)
	if virtual[path] ~= nil then return virtual[path] end
	local mod, rel = path:match("^([%w_]*)::/(.*)$")
	if mod ~= "depot_retrofits_1" then return nil end
	local tlName = rel:match("^(.*)%.tl$")
	if tlName then return generatedOverride[tlName] or readFile(genDir .. "/" .. tlName .. ".lua") end
	if rel:match("%.lua$") then return readFile(contentDir .. "/" .. rel) end
	return nil
end
local function exists(path) return sourceOf(path) ~= nil end

-- ug_require: runs a file once per "Lua state" and returns what it returned (cached, like require).
local requireCache = {}
local function resetState()
	requireCache = {}
	data = nil
end
function ug_require(path)
	local cached = requireCache[path]
	if cached ~= nil then return cached end
	local source = sourceOf(path)
	if source == nil then error("module not found: " .. path, 2) end
	local value
	if type(source) == "string" then
		local chunk = assert(loadstring(source, "@" .. path))
		value = chunk()
		if value == nil then value = true end
	else
		value = source
	end
	requireCache[path] = value
	return value
end

-- The engine's loader for "mod::/x.script@fn". sharedCache: true loads x.script.lua through ug_require (so a second load is
-- served from the cache), false runs the file afresh.
local engine = { sharedCache = false }
local function loadScriptFn(ref)
	local modulePath, fnName = ref:match("^(.-)@(.*)$")
	assert(modulePath, "no @ in " .. ref)
	local luaPath = modulePath .. ".lua"
	if exists(luaPath) then
		if engine.sharedCache then
			ug_require(luaPath)
		else
			local source = sourceOf(luaPath)
			assert(loadstring(source, "@" .. luaPath))()
		end
		assert(type(data) == "function", luaPath .. " defined no data()")
		return data()[fnName]
	end
	local module = ug_require(modulePath .. ".tl")
	return module[fnName]
end

virtual["::/scripts/util.tl"] = { useFn = loadScriptFn }
virtual["depot_retrofits_1::/settings.tl"] = { logLevel = "summary" }

-- A base depot script: one depot subconstruction with two emission states.
virtual["::/depots/road/road_depot.script.lua"] = [[
function data()
	return {
		updateFn = function(capture, params)
			BASE_CAPTURE_SEEN = capture
			return {
				subconstructions = { {
					depot = { maintenancePool = 10, catchmentArea = { radius = 400 } },
					metadata = { emissions = { { noise = 100, pollution = 200 }, { noise = 300, pollution = 400 } } },
				} },
				cost = 50000,
				maintenanceCost = 37500,
			}
		end,
	}
end
]]

-- A Roundhouse-like modular depot: pool 1, the stalls add the rest.
virtual["::/depots/rail/roundhouse/roundhouse.script.lua"] = [[
function data()
	return {
		updateFn = function(capture, params)
			return {
				subconstructions = { { depot = { maintenancePool = 1, catchmentArea = { radius = 800 } } } },
				cost = 100000,
				maintenanceCost = 60000,
			}
		end,
	}
end
]]

-- A module script that adds one vehicle (like a Roundhouse stall).
virtual["::/depots/rail/roundhouse/stall.script.lua"] = [[
function data()
	return {
		updateFn = function(capture, result, transform, tag, slotId, addModel, params)
			local depot = result.subconstructions[1].depot
			depot.maintenancePool = depot.maintenancePool + 1
		end,
	}
end
]]

-- The TRM-like wrapper: see the header.
virtual["trm::/build.script.lua"] = [[
local originals = {}
function data()
	return {
		updateFn = function(capture, params)
			local path, fnName = capture.beOriginalScript, capture.beOriginalFn
			local original = originals[path]
			if original == nil then
				ug_require(path)
				if type(data) ~= "function" then error("TRM-like: " .. path .. " defined no data()") end
				original = data()
				originals[path] = original
			end
			local fn = original[fnName]
			if type(fn) ~= "function" then error("TRM-like: " .. path .. " has no function " .. tostring(fnName)) end
			local result = fn(capture, params)
			for _, sub in ipairs(result.subconstructions or {}) do
				local list = sub.metadata and sub.metadata.emissions
				for _, e in ipairs(list or {}) do
					e.pollution = e.pollution * capture.beFactor
					e.noise = e.noise * capture.beFactor
				end
			end
			return result
		end,
	}
end
]]

local function trmModifier(fileName, def)
	local ref = def.updateScript.fileName
	local modulePath, fnName = ref:match("^(.-)@(.*)$")
	local path
	if modulePath:match("^[%w_]*::") then
		path = modulePath .. ".lua"
	elseif modulePath:sub(1, 1) == "/" then
		path = "::" .. modulePath .. ".lua"
	else
		path = (fileName:match("^(.*)/[^/]*$") or "") .. "/" .. modulePath .. ".lua"
	end
	def.updateScript.params = def.updateScript.params or {}
	local params = def.updateScript.params
	params.beOriginalScript, params.beOriginalFn, params.beFactor = path, fnName, 0.5
	def.updateScript.fileName = "trm::/build.script@updateFn"
	return def
end

-- The mod's own modifiers, from the generated mod.script.tl. mod.script.tl is loaded under another name each time (the
-- cache is per state), and overrideRef swaps the wrapper reference for the 1.2 one, to show the bug the fix removes.
local function modModifiers(overrideRef)
	local modifiers = {}
	addModifier = function(name, fn) modifiers[name] = fn end
	local name = "mod.script"
	if overrideRef then
		local source = readFile(genDir .. "/mod.script.lua")
		generatedOverride["mod.script.old"] = source:gsub("construction_wrapper%.script@", "construction.script@")
		name = "mod.script.old"
	end
	local mod = ug_require("depot_retrofits_1::/" .. name .. ".tl")
	mod.runFn({}, {}, {})
	return modifiers
end

-- runsWrapper and the copies it reads, cut out of the generated game script.
local function loadRunsWrapper()
	local source = readFile(genDir .. "/retrofits.script.lua")
	local body = source:match("\n(local runsWrapper = function%(script%).-\nend)\n")
	local wrapperRef = source:match('\nlocal wrapperRef = "([^"]+)"')
	local captureKey = source:match('\nlocal captureKey = "([^"]+)"')
	assert(body and wrapperRef and captureKey, "runsWrapper, wrapperRef or captureKey not found in retrofits.script.lua")
	local chunk = assert(loadstring("local wrapperRef, captureKey = ...\n" .. body .. "\nreturn runsWrapper"))
	return chunk(wrapperRef, captureKey), wrapperRef
end

local function depotDefinition()
	return { updateScript = { fileName = "road_depot.script@updateFn", params = {} }, params = {} }
end

local levels -- the real levels module, loaded in each state
local function levelParams()
	local params = {}
	levels.store(params, { radius = 3, vehicles = 5, pollution = 15, noise = 10, upkeep = 4 })
	return params, levels.read(params)
end

-- Places a road depot: the modifiers in the given order, then one build through the engine's loader.
local function build(order, opts)
	opts = opts or {}
	resetState()
	engine.sharedCache = opts.sharedCache or false
	levels = ug_require("depot_retrofits_1::/levels.tl")
	local ours = modModifiers(opts.oldRef)
	local def = depotDefinition()
	local conName = "::/depots/road/road_depot.con"
	for _, who in ipairs(order) do
		if who == "us" then def = ours.loadConstruction(conName, def) else def = trmModifier(conName, def) end
	end
	if opts.before then opts.before() end
	local params, values = levelParams()
	BASE_CAPTURE_SEEN = nil
	local ok, result = pcall(function()
		return loadScriptFn(def.updateScript.fileName)(def.updateScript.params, params)
	end)
	return ok, result, def, values
end

local function checkBuild(label, ok, result, values, trmFactor)
	check(label .. ": the depot builds", ok, not ok and result or nil)
	if not ok then return end
	local sub = result.subconstructions[1]
	local e = sub.metadata.emissions
	local pf, nf = levels.emissionFactor(values.pollution) * trmFactor, levels.emissionFactor(values.noise) * trmFactor
	check(label .. ": pollution has both reductions", near(e[1].pollution, 200 * pf) and near(e[2].pollution, 400 * pf),
		e[1].pollution .. "/" .. e[2].pollution)
	check(label .. ": noise has both reductions", near(e[1].noise, 100 * nf) and near(e[2].noise, 300 * nf),
		e[1].noise .. "/" .. e[2].noise)
	check(label .. ": pool levelled", sub.depot.maintenancePool == levels.pool(10, values.vehicles), sub.depot.maintenancePool)
	check(label .. ": radius levelled", near(sub.depot.catchmentArea.radius, levels.radius(400, values.radius)),
		sub.depot.catchmentArea.radius)
	check(label .. ": upkeep levelled", result.maintenanceCost == levels.levelledUpkeep(37500, values), result.maintenanceCost)
	check(label .. ": the base script did not get our capture entry",
		type(BASE_CAPTURE_SEEN) == "table" and BASE_CAPTURE_SEEN.depotRetrofits == nil)
end

local runsWrapper, wrapperRef = loadRunsWrapper()

print("-- 1.2 wrapper reference (the reported bug)")
do
	local ok, err = build({ "us", "trm" }, { oldRef = true })
	check("1.2, TRM after us: placing fails as reported", not ok and tostring(err):find("construction.script.lua", 1, true) ~= nil,
		ok and "built" or err)
	local ok2, result2, _, values2 = build({ "trm", "us" }, { oldRef = true })
	checkBuild("1.2, TRM before us", ok2, result2, values2, 0.5)
end

print("-- the fix, part 1: the .lua wrapper")
for _, shared in ipairs({ false, true }) do
	local mode = shared and " (engine and ug_require share a cache)" or ""
	local ok, result, def, values = build({ "us", "trm" }, { sharedCache = shared })
	checkBuild("TRM after us" .. mode, ok, result, values, 0.5)
	check("TRM after us" .. mode .. ": TRM keeps our capture entry", def.updateScript.params.depotRetrofits ~= nil)
	local ok2, result2, _, values2 = build({ "trm", "us" }, { sharedCache = shared })
	checkBuild("TRM before us" .. mode, ok2, result2, values2, 0.5)
	local ok3, result3, _, values3 = build({ "us" }, { sharedCache = shared })
	checkBuild("no TRM" .. mode, ok3, result3, values3, 1)
end

print("-- update and updateModule come from the one wrapper module")
do
	resetState()
	levels = ug_require("depot_retrofits_1::/levels.tl")
	local ours = modModifiers()
	local wrapper = ug_require("depot_retrofits_1::/construction.script.tl")
	local updateFn = loadScriptFn("depot_retrofits_1::/construction_wrapper.script@update")
	local moduleFn = loadScriptFn("depot_retrofits_1::/construction_wrapper.script@updateModule")
	check("the .lua hands update to construction.script.tl", updateFn == wrapper.update)
	check("the .lua hands updateModule to construction.script.tl", moduleFn == wrapper.updateModule)

	local module = ours.loadModule("::/depots/rail/roundhouse/stall.module",
		{ updateScript = { fileName = "stall.script@updateFn", params = {} } })
	check("modules are wrapped through the .lua", module.updateScript.fileName == "depot_retrofits_1::/construction_wrapper.script@updateModule",
		module.updateScript.fileName)
	-- A Roundhouse-like depot (pool 1) built through the wrapper, then one stall (+1 vehicle) on the same result.
	local con = ours.loadConstruction("::/depots/rail/roundhouse/roundhouse.con",
		{ updateScript = { fileName = "roundhouse.script@updateFn", params = {} }, params = {} })
	local params = {}
	levels.store(params, { radius = 0, vehicles = 5, pollution = 0, noise = 0, upkeep = 0 })
	local values = levels.read(params)
	local ok, result = pcall(loadScriptFn(con.updateScript.fileName), con.updateScript.params, params)
	check("a Roundhouse-like depot builds through the .lua", ok, not ok and result or nil)
	if ok then
		check("its pool is levelled", result.subconstructions[1].depot.maintenancePool == levels.pool(1, values.vehicles),
			result.subconstructions[1].depot.maintenancePool)
		local okModule, err = pcall(moduleFn, module.updateScript.params, result, nil, nil, 1, nil, params)
		check("a stall module runs through the .lua", okModule, err)
		check("the stall's vehicle is levelled with the base", result.subconstructions[1].depot.maintenancePool == levels.pool(2, values.vehicles),
			result.subconstructions[1].depot.maintenancePool .. " vs " .. levels.pool(2, values.vehicles))
	end
end

print("-- the fix, part 2: runsWrapper (isWrapped)")
do
	check("names our wrapper", runsWrapper({ fileName = wrapperRef, params = {} }) == true)
	check("TRM outermost, our capture kept",
		runsWrapper({ fileName = "trm::/build.script@updateFn", params = { depotRetrofits = { fileName = "x" }, beFactor = 0.5 } }) == true)
	check("another mod's construction", runsWrapper({ fileName = "other::/x.script@updateFn", params = { foo = 1 } }) == false)
	check("no params", runsWrapper({ fileName = "other::/x.script@updateFn" }) == false)
	check("no update script: unknown", runsWrapper(nil) == nil)
	check("params not a table: unknown", runsWrapper({ fileName = "other::/x.script@updateFn", params = 5 }) == nil)
	local _, _, def = build({ "us", "trm" })
	check("the definition TRM leaves after us counts as wrapped", runsWrapper(def.updateScript) == true)
	local old = def.updateScript.fileName == wrapperRef
	check("(the 1.2 check, a name match only, would have refused it)", old == false)
end

print("-- the known risk: a cached load hands TRM another file's data()")
do
	-- Not a pass or fail of ours: it shows the condition under which the fix does not help. If our .lua is already in
	-- ug_require's cache in a Lua state (the engine shares that cache and loaded it for a depot TRM does not wrap, such as
	-- one from another mod, or another mod loaded it), and another file has defined the global data() since (TRM's own
	-- wrapper does, when the engine loads it), TRM's ug_require of our file runs nothing and its data() call gets the
	-- wrong table. Only the game can tell whether its loader and ug_require share a cache (TODO.md, in-game test).
	local ok, err = build({ "us", "trm" }, {
		sharedCache = true,
		before = function()
			ug_require("depot_retrofits_1::/construction_wrapper.script.lua")
			ug_require("trm::/build.script.lua")
		end,
	})
	print("INFO  our .lua cached, then TRM's wrapper loaded: " .. (ok and "builds" or ("fails: " .. tostring(err))))
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
