-- The update script of every wrapped depot construction (see mod.script.tl). It runs the construction's original update
-- script and logs the three level param variants it receives, with the depot's pool, so the probe log shows which variant
-- reaches the script on a rebuild and on a new placement. It changes nothing.

-- Shared with mod.script.tl and probe.script.tl; keep the copies equal.
local captureKey = "depotRetrofits"
local futureParam = "depotRetrofitsFutureLevel"
local singleParam = "depotRetrofitsSingleLevel"
local undeclaredParam = "depotRetrofitsUndeclaredLevel"

-- The wrapper runs for every preview while the player places a depot, so the unchanged calls are logged only at first.
local maxPlainLines = 40
local maxChangedLines = 200

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

local record Subconstruction
	depot : DepotTable
end

local record Result
	subconstructions : {Subconstruction}
end

local say = function(text : string)
	if log ~= nil then
		log.message("DEPOT_RETROFITS " .. text)
	else
		print("DEPOT_RETROFITS " .. text)
	end
end

local utilLoaded, utilModule = pcall(ug_require, "::/scripts/util.tl")
local util = utilLoaded and (utilModule as Util) or nil
if not utilLoaded then say("wrapper util unavailable error=" .. tostring(utilModule)) end

local originals : {string : function({string:any}, {string:any}) : Result} = {}
local missing : {string : boolean} = {}
local plainLines = 0
local changedLines = 0

local loadOriginal = function(own : Own) : function({string:any}, {string:any}) : Result
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
	local original = fn as function({string:any}, {string:any}) : Result
	originals[own.fileName] = original
	return original
end

local paramKeys = function(params : {string:any}) : string
	local keys : {string} = {}
	for key in pairs(params) do keys[#keys + 1] = tostring(key) end
	table.sort(keys)
	return table.concat(keys, ",")
end

local logParams = function(result : Result, params : {string:any}, own : Own) : string
	local future, single, undeclared = params[futureParam], params[singleParam], params[undeclaredParam]
	local changed = (future ~= nil and future ~= 1) or (single ~= nil and single ~= 1) or undeclared ~= nil
	if changed and changedLines >= maxChangedLines then return nil end
	if not changed and plainLines >= maxPlainLines then return nil end
	if changed then changedLines = changedLines + 1 else plainLines = plainLines + 1 end
	local pools : {string} = {}
	for _, sub in ipairs(result.subconstructions or {}) do
		if type(sub) == "table" and type(sub.depot) == "table" then pools[#pools + 1] = tostring(sub.depot.maintenancePool) end
	end
	say("wrapper ref=" .. tostring(own.ref) .. " owner=" .. tostring(own.owner) .. " rawFuture=" .. tostring(future)
		.. " rawSingle=" .. tostring(single) .. " rawUndeclared=" .. tostring(undeclared) .. " pool=" .. table.concat(pools, ",")
		.. " paramKeys=" .. paramKeys(params))
	return nil
end

local wrapper = {}

function wrapper.update(capture : {string:any}, params : {string:any}) : Result
	local own = capture[captureKey] as Own
	local original = loadOriginal(own)
	if original == nil then
		error("DEPOT_RETROFITS original update script not found: " .. tostring(own and own.fileName))
	end
	local originalCapture : {string:any} = {}
	for key, value in pairs(capture) do
		if key ~= captureKey then originalCapture[key] = value end
	end
	local result = original(originalCapture, params)
	-- Guarded: an error here must not stop the depot from being built as the original script made it.
	local ok, err = pcall(logParams, result, params or {}, own)
	if not ok then say("wrapper logError ref=" .. tostring(own.ref) .. " error=" .. tostring(err)) end
	return result
end

return wrapper
