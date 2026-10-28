-- The update script of every wrapped depot construction (see mod.script.tl). It runs the construction's original update
-- script, then scales each subconstruction that builds a depot, from the probe params: value 2 of the pool param doubles the
-- maintenance pool, of the radius param makes the radius 1.5 times as wide, of the noise param halves the noise in both
-- emission states, of the pollution param quarters the pollution, and of the upkeep param doubles the construction's upkeep.
-- Anything else (the default 1, or no value on a construction built before the mod) leaves the value as the original script
-- made it.

-- Shared with mod.script.tl and probe.script.tl; keep the copies equal.
local captureKey = "depotRetrofits"
local poolParam = "depotRetrofitsProbePool"
local radiusParam = "depotRetrofitsProbeRadius"
local noiseParam = "depotRetrofitsProbeNoise"
local pollutionParam = "depotRetrofitsProbePollution"
local upkeepParam = "depotRetrofitsProbeUpkeep"

local poolFactor = 2.0
local radiusFactor = 1.5
local noiseFactor = 0.5
local pollutionFactor = 0.25
local upkeepFactor = 2.0

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

local utilLoaded, utilModule = pcall(ug_require, "::/scripts/util.tl")
local util = utilLoaded and (utilModule as Util) or nil
if not utilLoaded then say("wrapper util unavailable error=" .. tostring(utilModule)) end

local originals : {string : function({string:any}, {string:any}) : Result} = {}
local missing : {string : boolean} = {}
local plainLines = 0
local changedLines = 0

local factorFor = function(raw : any, factor : number) : number
	return tonumber(raw) == 2 and factor or 1.0
end

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

local applyProbe = function(result : Result, params : {string:any}, own : Own) : string
	local poolScale, radiusScale = factorFor(params[poolParam], poolFactor), factorFor(params[radiusParam], radiusFactor)
	local noiseScale, pollutionScale = factorFor(params[noiseParam], noiseFactor), factorFor(params[pollutionParam], pollutionFactor)
	local upkeepScale = factorFor(params[upkeepParam], upkeepFactor)
	local changed = poolScale ~= 1.0 or radiusScale ~= 1.0 or noiseScale ~= 1.0 or pollutionScale ~= 1.0 or upkeepScale ~= 1.0
	local upkeepBefore = result.maintenanceCost
	if upkeepScale ~= 1.0 and type(upkeepBefore) == "number" then
		result.maintenanceCost = math.floor(upkeepBefore * upkeepScale + 0.5)
	end
	local found = 0
	for index, sub in ipairs(result.subconstructions or {}) do
		local depot = type(sub) == "table" and sub.depot or nil
		if type(depot) == "table" then
			found = found + 1
			local poolBefore, radiusBefore = depot.maintenancePool, depot.catchmentArea and depot.catchmentArea.radius
			local emissionsBefore = describeEmissions(sub)
			if poolScale ~= 1.0 and type(poolBefore) == "number" then
				depot.maintenancePool = math.floor(poolBefore * poolScale + 0.5)
			end
			if radiusScale ~= 1.0 and type(radiusBefore) == "number" then
				depot.catchmentArea.radius = radiusBefore * radiusScale
			end
			local emissions = sub.metadata and sub.metadata.emissions
			if (noiseScale ~= 1.0 or pollutionScale ~= 1.0) and type(emissions) == "table" then
				for _, state in ipairs(emissions) do
					if type(state.noise) == "number" then state.noise = state.noise * noiseScale end
					if type(state.pollution) == "number" then state.pollution = state.pollution * pollutionScale end
				end
			end
			if (changed and changedLines < maxChangedLines) or (not changed and plainLines < maxPlainLines) then
				if changed then changedLines = changedLines + 1 else plainLines = plainLines + 1 end
				say("wrapper ref=" .. tostring(own.ref) .. " owner=" .. tostring(own.owner) .. " sub=" .. tostring(index)
					.. " rawPool=" .. tostring(params[poolParam]) .. " rawRadius=" .. tostring(params[radiusParam])
					.. " rawNoise=" .. tostring(params[noiseParam]) .. " rawPollution=" .. tostring(params[pollutionParam])
					.. " rawUpkeep=" .. tostring(params[upkeepParam])
					.. " poolBefore=" .. tostring(poolBefore) .. " poolAfter=" .. tostring(depot.maintenancePool)
					.. " radiusBefore=" .. tostring(radiusBefore)
					.. " radiusAfter=" .. tostring(depot.catchmentArea and depot.catchmentArea.radius)
					.. " emissionsBefore=" .. emissionsBefore .. " emissionsAfter=" .. describeEmissions(sub)
					.. " upkeepBefore=" .. tostring(upkeepBefore) .. " upkeepAfter=" .. tostring(result.maintenanceCost)
					.. " cost=" .. tostring(result.cost)
					.. (changed and (" paramKeys=" .. paramKeys(params)) or ""))
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
	-- The scaling is guarded: an error here must not stop the depot from being built as the original script made it.
	local ok, err = pcall(applyProbe, result, params or {}, own)
	if not ok then say("wrapper applyError ref=" .. tostring(own.ref) .. " error=" .. tostring(err)) end
	return result
end

return wrapper
