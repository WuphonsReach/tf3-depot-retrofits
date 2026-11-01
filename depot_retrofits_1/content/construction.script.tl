-- The update script of every wrapped depot construction (see mod.script.tl). It runs the construction's original update
-- script, then applies the building's levels (read from the construction params, formulas in levels.tl) to each
-- subconstruction that builds a depot: maintenance pool, catchment radius, noise and pollution in both emission states, and
-- the construction's upkeep. A building with no level params (placed before the mod, or new) is left as the original script
-- made it.
--
-- Modular depots (the Roundhouse mod's) add to the building after this script: the game adds each module's upkeep (its
-- metadata.maintenanceCost) and runs each module's update script, which may add to the pool. So the levels count the
-- modules' upkeep in here (params.modules carries their metadata), and updateModule wraps the update script of every module
-- under a depots folder and re-levels what the module added to the pool, radius or upkeep.

-- Copied in mod.script.tl; keep the copies equal.
local captureKey = "depotRetrofits"

-- The wrapper runs for every preview while the player places a depot, so the calls without levels are logged only at first.
local maxPlainLines = 40
local maxLevelledLines = 400

local record Own
	fileName : string -- the original update script, absolute
	ref : string -- as the .con file names it
	owner : string -- the .con file
end

local record Catchment
	radius : number
end

local record DepotTable
	maintenancePool : number
	catchmentArea : Catchment
end

local record EmissionState
	noise : number
	pollution : number
end

local record SubMetadata
	emissions : {EmissionState}
end

local record Subconstruction
	depot : DepotTable
	metadata : SubMetadata
end

local record Result
	subconstructions : {Subconstruction}
	cost : number
	maintenanceCost : number
end

local say = function(text : string)
	if log ~= nil then
		log.message("DEPOT_RETROFITS " .. text)
	else
		print("DEPOT_RETROFITS " .. text)
	end
end

-- settings.tl's logLevel: "full" adds the before/after lines. Guarded: without the file the log stays at "summary".
local settingsLoaded, settingsModule = pcall(ug_require, "depot_retrofits_1::/settings.tl")
local logFull = settingsLoaded and type(settingsModule) == "table" and (settingsModule as {string:any}).logLevel == "full"

local utilLoaded, utilModule = pcall(ug_require, "::/scripts/util.tl")
local util = utilLoaded and (utilModule as Util) or nil
if not utilLoaded then say("wrapper util unavailable error=" .. tostring(utilModule)) end

local levelsLoaded, levelsModule = pcall(ug_require, "depot_retrofits_1::/levels.tl")
local levels = levelsLoaded and (levelsModule as DepotRetrofitsLevels) or nil
if not levelsLoaded then say("wrapper levels unavailable error=" .. tostring(levelsModule)) end

-- A construction's update script, and a module's (base modules take the same arguments,
-- stations/street/modular_street_station/modules.script.lua).
local type ConstructionFn = function({string:any}, {string:any}) : Result
local type ModuleFn = function({string:any}, Result, any, any, any, any, {string:any}) : any

local originals : {string : function} = {}
local missing : {string : boolean} = {}
-- The pool each depot subconstruction had before the levels, by result table and subconstruction index, so a module's wrapper
-- can level what the module adds without working the base back out of the levelled pool. Weak keys: a result is dropped
-- once the game is done with it. Used only when the game hands the modules the same table the construction's script returned
-- (not verified); otherwise relevelModule falls back to levels.basePool.
local basePools : {Result : {integer : number}} = setmetatable({}, { __mode = "k" })
local plainLines = 0
local levelledLines = 0
local moduleLines = 0
local maxModuleLines = 400

local loadOriginal = function(own : Own) : function
	local cached = originals[own.fileName]
	if cached then return cached end
	if util == nil or missing[own.fileName] then return nil end
	local ok, fn = pcall(util.useFn, own.fileName)
	if not ok or fn == nil then
		-- Remembered, so the failed load and its log line are not repeated on every preview.
		missing[own.fileName] = true
		say("wrapper originalMissing ref=" .. tostring(own.ref) .. " resolved=" .. tostring(own.fileName)
			.. " owner=" .. tostring(own.owner) .. " error=" .. tostring(fn))
		return nil
	end
	originals[own.fileName] = fn
	return fn
end

-- The capture params the original script expects: ours left out.
local originalCaptureOf = function(capture : {string:any}) : {string:any}
	local originalCapture : {string:any} = {}
	for key, value in pairs(capture) do
		if key ~= captureKey then originalCapture[key] = value end
	end
	return originalCapture
end

-- "noise/pollution" per emission state, comma separated.
local describeEmissions = function(sub : Subconstruction) : string
	local emissions = sub.metadata and sub.metadata.emissions
	if type(emissions) ~= "table" then return "none" end
	local parts : {string} = {}
	for _, state in ipairs(emissions) do
		parts[#parts + 1] = tostring(state.noise) .. "/" .. tostring(state.pollution)
	end
	return table.concat(parts, ",")
end

-- The upkeep the game adds for the construction's modules: each module's metadata.maintenanceCost (the base modular street
-- station reads module metadata from params.modules the same way, stations/street/modular_street_station/modular_terminal.script.lua).
local moduleUpkeep = function(params : {string:any}) : number
	local modules = params.modules
	if type(modules) ~= "table" then return 0 end
	local sum = 0.0
	for _, entry in pairs(modules as {any:any}) do
		local metadata = type(entry) == "table" and (entry as {string:any}).metadata or nil
		local cost = type(metadata) == "table" and (metadata as {string:any}).maintenanceCost or nil
		if type(cost) == "number" then sum = sum + (cost as number) end
	end
	return sum
end

local isLevelled = function(values : {string : integer}) : boolean
	for _, tree in ipairs(levels.trees) do
		if values[tree] > 0 then return true end
	end
	return false
end

local applyLevels = function(result : Result, params : {string:any}, own : Own) : string
	local values = levels.read(params)
	local levelled = isLevelled(values)
	local upkeepBefore = result.maintenanceCost
	local modulesUpkeep = moduleUpkeep(params)
	if levelled and type(upkeepBefore) == "number" then
		-- The factor applies to the whole building, modules included: the modules' share is taken off this script's upkeep,
		-- since the game adds it unchanged afterwards. Kept at 0 or more: only a building made mostly of modules, at high
		-- upkeep levels, could go below.
		local total = levels.levelledUpkeep(upkeepBefore + modulesUpkeep, values)
		result.maintenanceCost = math.max(0, total - modulesUpkeep)
		if logFull and total - modulesUpkeep < 0 then
			say("wrapper upkeepClamped ref=" .. tostring(own.ref) .. " upkeep=" .. tostring(upkeepBefore)
				.. " moduleUpkeep=" .. tostring(modulesUpkeep) .. " total=" .. tostring(total))
		end
	end
	local noiseScale, pollutionScale = levels.emissionFactor(values.noise), levels.emissionFactor(values.pollution)
	local found = 0
	local pools : {integer : number} = {}
	basePools[result] = pools
	for index, sub in ipairs(result.subconstructions or {}) do
		local depot = type(sub) == "table" and sub.depot or nil
		if type(depot) == "table" then
			found = found + 1
			local poolBefore, radiusBefore = depot.maintenancePool, depot.catchmentArea and depot.catchmentArea.radius
			-- Worked out only for a line that will be logged: this runs for every preview while a depot is placed.
			local logThis = logFull and ((levelled and levelledLines < maxLevelledLines) or (not levelled and plainLines < maxPlainLines))
			local emissionsBefore = logThis and describeEmissions(sub) or nil
			if type(poolBefore) == "number" then pools[index] = poolBefore end
			if values.vehicles > 0 and type(poolBefore) == "number" then
				depot.maintenancePool = levels.pool(poolBefore, values.vehicles)
			end
			if values.radius > 0 and type(radiusBefore) == "number" then
				depot.catchmentArea.radius = levels.radius(radiusBefore, values.radius)
			end
			local emissions = sub.metadata and sub.metadata.emissions
			if (values.noise > 0 or values.pollution > 0) and type(emissions) == "table" then
				for _, state in ipairs(emissions) do
					if type(state.noise) == "number" then state.noise = state.noise * noiseScale end
					if type(state.pollution) == "number" then state.pollution = state.pollution * pollutionScale end
				end
			end
			if logThis then
				if levelled then levelledLines = levelledLines + 1 else plainLines = plainLines + 1 end
				say("wrapper ref=" .. tostring(own.ref) .. " owner=" .. tostring(own.owner) .. " sub=" .. tostring(index)
					.. " levels=" .. levels.describe(values)
					.. " poolBefore=" .. tostring(poolBefore) .. " poolAfter=" .. tostring(depot.maintenancePool)
					.. " radiusBefore=" .. tostring(radiusBefore)
					.. " radiusAfter=" .. tostring(depot.catchmentArea and depot.catchmentArea.radius)
					.. " emissionsBefore=" .. tostring(emissionsBefore) .. " emissionsAfter=" .. describeEmissions(sub)
					.. " upkeepBefore=" .. tostring(upkeepBefore) .. " upkeepAfter=" .. tostring(result.maintenanceCost)
					.. " moduleUpkeep=" .. tostring(modulesUpkeep) .. " cost=" .. tostring(result.cost))
			end
		end
	end
	if found == 0 and plainLines < maxPlainLines then
		plainLines = plainLines + 1
		say("wrapper noDepotTable ref=" .. tostring(own.ref) .. " owner=" .. tostring(own.owner)
			.. " subconstructions=" .. tostring(result.subconstructions and #result.subconstructions))
	end
	return nil
end

local record DepotSnapshot
	pool : number
	radius : number
end

local snapshotDepots = function(result : Result) : {integer : DepotSnapshot}
	local snapshots : {integer : DepotSnapshot} = {}
	for index, sub in ipairs(result.subconstructions or {}) do
		local depot = type(sub) == "table" and sub.depot or nil
		if type(depot) == "table" then
			snapshots[index] = { pool = depot.maintenancePool, radius = depot.catchmentArea and depot.catchmentArea.radius }
		end
	end
	return snapshots
end

-- What a module added is levelled as if the building had had it from the start: the pool from the base pool before the module
-- plus the module's vehicles (so the vehicles tree counts every stall), the radius from the base radius plus what the module
-- added, and the upkeep by its factor.
local relevelModule = function(result : Result, values : {string : integer}, before : {integer : DepotSnapshot},
		upkeepBefore : number, own : Own, slotId : any) : string
	local changes : {string} = {}
	local recorded = basePools[result]
	for index, sub in ipairs(result.subconstructions or {}) do
		local depot = type(sub) == "table" and sub.depot or nil
		local snap = before[index]
		if type(depot) == "table" and snap == nil then
			changes[#changes + 1] = "newDepot sub=" .. tostring(index)
		elseif type(depot) == "table" then
			local pool = depot.maintenancePool
			if values.vehicles > 0 and type(pool) == "number" and type(snap.pool) == "number" and pool ~= snap.pool then
				local base : number = recorded and recorded[index]
				local source = "recorded"
				if base == nil then base, source = levels.basePool(snap.pool, values.vehicles), "inverted" end
				if base ~= nil then
					local added = pool - snap.pool
					depot.maintenancePool = levels.pool(base + added, values.vehicles)
					if recorded ~= nil then recorded[index] = base + added end
					changes[#changes + 1] = "sub=" .. tostring(index) .. " pool=" .. tostring(snap.pool) .. "+" .. tostring(added)
						.. "->" .. tostring(depot.maintenancePool) .. " base=" .. tostring(base + added) .. " baseSource=" .. source
				else
					changes[#changes + 1] = "sub=" .. tostring(index) .. " poolUnknownBase=" .. tostring(snap.pool)
				end
			end
			local radius = depot.catchmentArea and depot.catchmentArea.radius
			if values.radius > 0 and type(radius) == "number" and type(snap.radius) == "number" and radius ~= snap.radius then
				depot.catchmentArea.radius = levels.radius(levels.baseRadius(snap.radius, values.radius) + radius - snap.radius,
					values.radius)
				changes[#changes + 1] = "sub=" .. tostring(index) .. " radius=" .. tostring(snap.radius) .. "+"
					.. tostring(radius - snap.radius) .. "->" .. tostring(depot.catchmentArea.radius)
			end
		end
	end
	local upkeep = result.maintenanceCost
	if type(upkeep) == "number" and type(upkeepBefore) == "number" and upkeep ~= upkeepBefore then
		result.maintenanceCost = upkeepBefore + math.floor((upkeep - upkeepBefore) * levels.upkeepFactor(values) + 0.5)
		changes[#changes + 1] = "upkeep=" .. tostring(upkeepBefore) .. "+" .. tostring(upkeep - upkeepBefore) .. "->"
			.. tostring(result.maintenanceCost)
	end
	if logFull and #changes > 0 and moduleLines < maxModuleLines then
		moduleLines = moduleLines + 1
		say("module ref=" .. tostring(own.ref) .. " slot=" .. tostring(slotId) .. " levels=" .. levels.describe(values) .. " "
			.. table.concat(changes, " "))
	end
	return nil
end

local wrapper = {}

function wrapper.update(capture : {string:any}, params : {string:any}) : Result
	local own = capture[captureKey] as Own
	local original = loadOriginal(own) as ConstructionFn
	if original == nil then
		error("DEPOT_RETROFITS original update script not found: " .. tostring(own and own.fileName))
	end
	local result = original(originalCaptureOf(capture), params)
	if levels == nil then return result end
	-- Guarded: an error here must not stop the depot from being built as the original script made it.
	local ok, err = pcall(applyLevels, result, params or {}, own)
	if not ok then say("wrapper applyError ref=" .. tostring(own.ref) .. " error=" .. tostring(err)) end
	return result
end

-- The update script of every wrapped module (mod.script.tl wraps the modules under a depots folder). The game calls it once per
-- built module after the construction's update script, with the construction's params last.
function wrapper.updateModule(capture : {string:any}, result : Result, transform : any, tag : any, slotId : any, addModel : any,
		params : {string:any}) : any
	local own = capture[captureKey] as Own
	local original = loadOriginal(own) as ModuleFn
	if original == nil then
		error("DEPOT_RETROFITS original module script not found: " .. tostring(own and own.fileName))
	end
	local originalCapture = originalCaptureOf(capture)
	if levels == nil or type(result) ~= "table" then
		return original(originalCapture, result, transform, tag, slotId, addModel, params)
	end
	local values = levels.read(params or {})
	if not isLevelled(values) then
		return original(originalCapture, result, transform, tag, slotId, addModel, params)
	end
	local before = snapshotDepots(result)
	local upkeepBefore = result.maintenanceCost
	local returned = original(originalCapture, result, transform, tag, slotId, addModel, params)
	-- Guarded like the construction's: the module is kept as its own script made it.
	local ok, err = pcall(relevelModule, result, values, before, upkeepBefore, own, slotId)
	if not ok then say("module applyError ref=" .. tostring(own.ref) .. " error=" .. tostring(err)) end
	return returned
end

return wrapper
