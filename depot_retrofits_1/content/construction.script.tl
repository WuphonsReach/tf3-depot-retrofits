-- The update script of every wrapped depot construction (see mod.script.tl). It runs the construction's original update
-- script, then applies the building's levels (read from the construction params, formulas in levels.tl) to each
-- subconstruction that builds a depot: maintenance pool, catchment radius, noise and pollution in both emission states, and
-- the construction's upkeep. A building with no level params (placed before the mod, or new) is left as the original script
-- made it.

-- Shared with mod.script.tl and levels_card.script.tl; keep the copies equal.
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

local utilLoaded, utilModule = pcall(ug_require, "::/scripts/util.tl")
local util = utilLoaded and (utilModule as Util) or nil
if not utilLoaded then say("wrapper util unavailable error=" .. tostring(utilModule)) end

local levelsLoaded, levelsModule = pcall(ug_require, "depot_retrofits_1::/levels.tl")
local levels = levelsLoaded and (levelsModule as DepotRetrofitsLevels) or nil
if not levelsLoaded then say("wrapper levels unavailable error=" .. tostring(levelsModule)) end

local originals : {string : function({string:any}, {string:any}) : Result} = {}
local missing : {string : boolean} = {}
local plainLines = 0
local levelledLines = 0

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

-- "radius/vehicles/pollution/noise/upkeep".
local describeLevels = function(values : {string : integer}) : string
	local parts : {string} = {}
	for _, tree in ipairs(levels.trees) do parts[#parts + 1] = tostring(values[tree]) end
	return table.concat(parts, "/")
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

local applyLevels = function(result : Result, params : {string:any}, own : Own) : string
	local values = levels.read(params)
	local levelled = false
	for _, tree in ipairs(levels.trees) do
		if values[tree] > 0 then levelled = true end
	end
	local upkeepBefore = result.maintenanceCost
	if levelled and type(upkeepBefore) == "number" then
		result.maintenanceCost = math.floor(upkeepBefore * levels.upkeepFactor(values) + 0.5)
	end
	local noiseScale, pollutionScale = levels.emissionFactor(values.noise), levels.emissionFactor(values.pollution)
	local found = 0
	for index, sub in ipairs(result.subconstructions or {}) do
		local depot = type(sub) == "table" and sub.depot or nil
		if type(depot) == "table" then
			found = found + 1
			local poolBefore, radiusBefore = depot.maintenancePool, depot.catchmentArea and depot.catchmentArea.radius
			local emissionsBefore = describeEmissions(sub)
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
			if (levelled and levelledLines < maxLevelledLines) or (not levelled and plainLines < maxPlainLines) then
				if levelled then levelledLines = levelledLines + 1 else plainLines = plainLines + 1 end
				say("wrapper ref=" .. tostring(own.ref) .. " owner=" .. tostring(own.owner) .. " sub=" .. tostring(index)
					.. " levels=" .. describeLevels(values)
					.. " poolBefore=" .. tostring(poolBefore) .. " poolAfter=" .. tostring(depot.maintenancePool)
					.. " radiusBefore=" .. tostring(radiusBefore)
					.. " radiusAfter=" .. tostring(depot.catchmentArea and depot.catchmentArea.radius)
					.. " emissionsBefore=" .. emissionsBefore .. " emissionsAfter=" .. describeEmissions(sub)
					.. " upkeepBefore=" .. tostring(upkeepBefore) .. " upkeepAfter=" .. tostring(result.maintenanceCost)
					.. " cost=" .. tostring(result.cost))
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
	if levels == nil then return result end
	-- Guarded: an error here must not stop the depot from being built as the original script made it.
	local ok, err = pcall(applyLevels, result, params or {}, own)
	if not ok then say("wrapper applyError ref=" .. tostring(own.ref) .. " error=" .. tostring(err)) end
	return result
end

return wrapper
