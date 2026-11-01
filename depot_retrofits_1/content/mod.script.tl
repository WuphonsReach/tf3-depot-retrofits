-- runFn registers a loadConstruction modifier that wraps the update script of every construction that builds a depot or a
-- maintenance building. The wrapper (construction.script.tl) runs the original script and applies the building's levels.
-- A loadModule modifier wraps the update script of every module under a depots folder the same way, so the levels also count
-- what a modular depot's modules add (the Roundhouse mod's stalls each add a vehicle).
-- Each wrapped construction declares one param per level tree (keys in levels.tl), with an availability year past the end of
-- the calendar, which keeps them out of the build menu: a new building starts at level 0, and the game script stores levels
-- with a rebuild. Each wrapped construction keeps its own params and the original script's reference in its updateScript
-- params, so the wrapper knows what to call. Log lines start with "DEPOT_RETROFITS".

local modVersion = "1.1-dev"

-- wrapperRef is copied in retrofits.script.tl, captureKey in construction.script.tl; keep the copies equal.
local wrapperRef = "depot_retrofits_1::/construction.script@update"
local captureKey = "depotRetrofits"

local moduleWrapperRef = "depot_retrofits_1::/construction.script@updateModule"

-- The building window with the Retrofit tab (retrofit_window.script.tl); set only where the construction has none of its own.
local windowRef = "depot_retrofits_1::/retrofit_window.script@entityWindowFn"

-- The game's date card goes up to the year 5000; a level param available from 9999 never shows in the build menu.
local hiddenYear = 9999

local record ScriptHook
	fileName : string
	params : {string:any}
end

local record Template
	configureHudIconsScript : ScriptHook
end

local record ParamDef
	key : string
	name : string
	tooltip : string
	values : {string}
	yearFrom : integer
	yearTo : integer
	defaultIndex : integer
	uiType : string
	postConstructionModifiable : boolean
end

local record Definition
	isIndustry : boolean
	constructionType : string
	updateScript : ScriptHook
	entityWindowScript : ScriptHook
	configureHudIconsScript : ScriptHook
	constructionTemplates : {Template}
	edgeObject : table
	params : {ParamDef}
end

local record ModuleDefinition
	updateScript : ScriptHook
	metadata : {string:any}
end

local record DepotRetrofitsMod
	runFn : function(table, table, {string : {string : integer}})
end

local say = function(text : string)
	if log ~= nil then
		log.message("DEPOT_RETROFITS " .. text)
	else
		print("DEPOT_RETROFITS " .. text)
	end
end

-- settings.tl's logLevel: "full" adds the wrap lines. Guarded: without the file the log stays at "summary".
local settingsLoaded, settingsModule = pcall(ug_require, "depot_retrofits_1::/settings.tl")
local logFull = settingsLoaded and type(settingsModule) == "table" and (settingsModule as {string:any}).logLevel == "full"

-- Guarded: without the levels module nothing is wrapped, and the log says why.
local levelsLoaded, levelsModule = pcall(ug_require, "depot_retrofits_1::/levels.tl")
local levels = levelsLoaded and (levelsModule as DepotRetrofitsLevels) or nil

-- Base depot .con files name their update script relative to their own folder ("rail_depot.script@updateFn"); the wrapper
-- lives in this mod, so it needs the absolute form ("::/depots/rail/rail_depot.script@updateFn"). nil when the owner's name
-- has no "::" namespace part: then the reference cannot be resolved safely and the construction is left alone.
local resolveRef = function(ref : string, owner : string) : string
	if ref:find("::", 1, true) then return ref end
	local sep = owner:find("::", 1, true)
	if not sep then return nil end
	local namespace = owner:sub(1, sep - 1)
	local path = (owner:sub(sep + 2):gsub("\\", "/"))
	if ref:sub(1, 1) == "/" then return namespace .. "::" .. ref end
	local folder = (path:match("^(.*)/[^/]*$") or ""):gsub("^/+", "")
	if folder == "" then return namespace .. "::/" .. ref end
	return namespace .. "::/" .. folder .. "/" .. ref
end

local namesDepotHud = function(ref : ScriptHook) : boolean
	return ref ~= nil and type(ref.fileName) == "string" and ref.fileName:find("configureDepotHudIconsFn", 1, true) ~= nil
end

-- The depot values of the engine's ConstructionType (api/tealdef/api/type.d.tl). Base depots do not set constructionType;
-- mod depots often do, such as the Boathouse mod's maintenance building, which has neither of the other two markers.
local depotTypes : {string : boolean} = { STREET_DEPOT = true, RAIL_DEPOT = true, WATER_DEPOT = true }

-- "hud" when the construction (or one of its templates) uses the base game's depot HUD icons, "type" when it declares a depot
-- constructionType, "path" when its file sits in a depots folder (the Roundhouse mod's depot has no HUD marker), nil otherwise.
local depotMarker = function(fileName : string, definition : Definition) : string
	if namesDepotHud(definition.configureHudIconsScript) then return "hud" end
	if type(definition.constructionTemplates) == "table" then
		for _, template in ipairs(definition.constructionTemplates) do
			if type(template) == "table" and namesDepotHud(template.configureHudIconsScript) then return "hud" end
		end
	end
	if type(definition.constructionType) == "string" and depotTypes[definition.constructionType] then return "type" end
	local lower = fileName:lower():gsub("\\", "/")
	if lower:find("/depots/", 1, true) then return "path" end
	return nil
end

local levelValues = function() : {string}
	local values : {string} = {}
	for level = 0, levels.maxLevel do values[#values + 1] = tostring(level) end
	return values
end

local levelParam = function(tree : string) : ParamDef
	return {
		key = levels.paramKeys[tree],
		name = "Retrofit level: " .. levels.names[tree],
		tooltip = "Bought in the building's window; not offered when placing a building.",
		values = levelValues(),
		defaultIndex = 1,
		yearFrom = hiddenYear,
		yearTo = 0,
		uiType = "ComboBox",
		postConstructionModifiable = false,
	}
end

local wrapConstruction = function(fileName : string, definition : Definition) : Definition
	if type(definition) ~= "table" or definition.isIndustry then return definition end
	local name = type(fileName) == "string" and fileName or ""
	local marker = depotMarker(name, definition)
	local script = definition.updateScript
	if not marker then
		local lower = name:lower()
		if lower:find("depot", 1, true) or lower:find("maint", 1, true) then
			say("skip fileName=" .. name .. " reason=noMarker constructionType=" .. tostring(definition.constructionType))
		end
		return definition
	end
	-- The base path signals name the depot HUD icons too (infrastructure/signal/signal_path_a.con.lua); they are edge objects.
	if definition.edgeObject ~= nil then
		say("skip fileName=" .. name .. " reason=edgeObject marker=" .. marker)
		return definition
	end
	if script == nil or type(script.fileName) ~= "string" or script.fileName == "" then
		say("skip fileName=" .. name .. " reason=noUpdateScript marker=" .. marker)
		return definition
	end
	if script.fileName == wrapperRef or (type(script.params) == "table" and script.params[captureKey] ~= nil) then
		say("skip fileName=" .. name .. " reason=alreadyWrapped")
		return definition
	end
	local resolved = resolveRef(script.fileName, name)
	if not resolved then
		say("skip fileName=" .. name .. " reason=unresolvable ref=" .. script.fileName)
		return definition
	end

	-- The original capture params stay at the top level, where the original script reads them (road maintenance reads its
	-- radius there); our entry sits beside them under captureKey.
	local capture : {string:any} = {}
	if type(script.params) == "table" then
		for key, value in pairs(script.params) do capture[key] = value end
	end
	capture[captureKey] = { fileName = resolved, ref = script.fileName, owner = name }
	definition.updateScript = { fileName = wrapperRef, params = capture }

	if type(definition.params) ~= "table" then definition.params = {} end
	for _, tree in ipairs(levels.trees) do
		table.insert(definition.params, levelParam(tree))
	end

	local window = definition.entityWindowScript
	local windowSet = window == nil or type(window.fileName) ~= "string" or window.fileName == ""
	if windowSet then definition.entityWindowScript = { fileName = windowRef, params = {} } end

	if logFull then
		say("wrap fileName=" .. name .. " marker=" .. marker .. " ref=" .. script.fileName .. " resolved=" .. resolved
			.. " window=" .. (windowSet and "retrofit" or ("own:" .. tostring(window.fileName))))
	end
	return definition
end

-- Modules are told apart by their folder only: the Roundhouse mod's sit beside its depot under depots/, and a station's modules
-- are left alone. The wrapper levels a module only inside a construction that has levels, so a module used elsewhere is
-- unchanged.
local wrapModule = function(fileName : string, definition : ModuleDefinition) : ModuleDefinition
	if type(definition) ~= "table" then return definition end
	local name = type(fileName) == "string" and fileName or ""
	if not (name:lower():gsub("\\", "/")):find("/depots/", 1, true) then return definition end
	local script = definition.updateScript
	if script == nil or type(script.fileName) ~= "string" or script.fileName == "" then
		say("skipModule fileName=" .. name .. " reason=noUpdateScript")
		return definition
	end
	if script.fileName == moduleWrapperRef or (type(script.params) == "table" and script.params[captureKey] ~= nil) then
		say("skipModule fileName=" .. name .. " reason=alreadyWrapped")
		return definition
	end
	local resolved = resolveRef(script.fileName, name)
	if not resolved then
		say("skipModule fileName=" .. name .. " reason=unresolvable ref=" .. script.fileName)
		return definition
	end
	local capture : {string:any} = {}
	if type(script.params) == "table" then
		for key, value in pairs(script.params) do capture[key] = value end
	end
	capture[captureKey] = { fileName = resolved, ref = script.fileName, owner = name }
	definition.updateScript = { fileName = moduleWrapperRef, params = capture }
	if logFull then
		local upkeep = type(definition.metadata) == "table" and definition.metadata.maintenanceCost or nil
		say("wrapModule fileName=" .. name .. " ref=" .. script.fileName .. " resolved=" .. resolved .. " upkeep=" .. tostring(upkeep))
	end
	return definition
end

local mod : DepotRetrofitsMod = {
	runFn = function(_captureParams : table, _settings : table, _allModParams : {string : {string : integer}})
		say("version " .. modVersion .. " logLevel=" .. (logFull and "full" or "summary") .. " levels=" .. tostring(levelsLoaded)
			.. (levelsLoaded and "" or (" error=" .. tostring(levelsModule)))
			.. (settingsLoaded and "" or (" settingsError=" .. tostring(settingsModule))))
		if levels == nil then return end
		addModifier("loadConstruction", function(fileName : string, definition : Definition) : Definition
			local ok, result = pcall(wrapConstruction, fileName, definition)
			if ok then return result as Definition end
			say("wrapError fileName=" .. tostring(fileName) .. " error=" .. tostring(result))
			return definition
		end)
		-- Guarded: "loadModule" is the name TF2 used; the base game registers no module modifier, so whether TF3 calls it shows
		-- only as wrapModule lines in the log.
		local registered, registerError = pcall(addModifier, "loadModule", function(fileName : string, definition : ModuleDefinition) : ModuleDefinition
			local ok, result = pcall(wrapModule, fileName, definition)
			if ok then return result as ModuleDefinition end
			say("wrapModuleError fileName=" .. tostring(fileName) .. " error=" .. tostring(result))
			return definition
		end)
		if not registered then say("loadModule unavailable error=" .. tostring(registerError)) end
	end,
}

return mod
