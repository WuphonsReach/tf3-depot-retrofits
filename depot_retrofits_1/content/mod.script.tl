-- runFn registers a loadConstruction modifier that wraps the update script of every construction that builds a depot or a
-- maintenance building. The wrapper (construction.script.tl) runs the original script and then scales the depot's
-- maintenance pool and radius from two probe params. The params are not modifiable after construction but do show in the
-- build menu (the game has no hidden param); leave them at "Base" when placing a depot, or the probe's before-state is already
-- scaled. Each wrapped construction keeps its own params and the original script's reference in its updateScript params, so
-- the wrapper knows what to call. Log lines start with "DEPOT_RETROFITS".

local modVersion = "0.1-probe"

-- Shared with construction.script.tl and probe.script.tl; keep the copies equal.
local wrapperRef = "depot_retrofits_1::/construction.script@update"
local captureKey = "depotRetrofits"
local poolParam = "depotRetrofitsProbePool"
local radiusParam = "depotRetrofitsProbeRadius"

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
	defaultIndex : integer
	uiType : string
	postConstructionModifiable : boolean
end

local record Definition
	isIndustry : boolean
	updateScript : ScriptHook
	configureHudIconsScript : ScriptHook
	constructionTemplates : {Template}
	params : {ParamDef}
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

-- "hud" when the construction (or one of its templates) uses the base game's depot HUD icons, "path" when its file sits in a
-- depots folder (the Roundhouse mod's depot has no HUD marker), nil otherwise.
local depotMarker = function(fileName : string, definition : Definition) : string
	if namesDepotHud(definition.configureHudIconsScript) then return "hud" end
	if type(definition.constructionTemplates) == "table" then
		for _, template in ipairs(definition.constructionTemplates) do
			if type(template) == "table" and namesDepotHud(template.configureHudIconsScript) then return "hud" end
		end
	end
	local lower = fileName:lower():gsub("\\", "/")
	if lower:find("/depots/", 1, true) then return "path" end
	return nil
end

local probeParam = function(key : string, name : string, values : {string}) : ParamDef
	return {
		key = key,
		name = name,
		tooltip = "Depot Retrofits test value, set by the mod's probe.",
		values = values,
		defaultIndex = 1,
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
			say("skip fileName=" .. name .. " reason=noMarker")
		end
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

	-- Declared so they are kept through every rebuild. Values are 1-based: 1 is the default, 2 is the probe value.
	if type(definition.params) ~= "table" then definition.params = {} end
	table.insert(definition.params, probeParam(poolParam, "Retrofit probe: vehicles maintained", { "Base", "x2" }))
	table.insert(definition.params, probeParam(radiusParam, "Retrofit probe: maintenance radius", { "Base", "x1.5" }))

	say("wrap fileName=" .. name .. " marker=" .. marker .. " ref=" .. script.fileName .. " resolved=" .. resolved)
	return definition
end

local mod : DepotRetrofitsMod = {
	runFn = function(_captureParams : table, _settings : table, _allModParams : {string : {string : integer}})
		say("version " .. modVersion)
		addModifier("loadConstruction", function(fileName : string, definition : Definition) : Definition
			local ok, result = pcall(wrapConstruction, fileName, definition)
			if ok then return result as Definition end
			say("wrapError fileName=" .. tostring(fileName) .. " error=" .. tostring(result))
			return definition
		end)
	end,
}

return mod
