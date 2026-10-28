-- The five level trees and the formulas of docs/design/spec.md, shared by every script of the mod (each loads it with ug_require
-- under pcall). Pure functions: no game API calls, so it loads the same in the mod, construction, game and GUI scripts.

local levels : DepotRetrofitsLevels = {
	maxLevel = 15,
	trees = { "radius", "vehicles", "pollution", "noise", "upkeep" },
	paramKeys = {
		radius = "depotRetrofitsRadius",
		vehicles = "depotRetrofitsVehicles",
		pollution = "depotRetrofitsPollution",
		noise = "depotRetrofitsNoise",
		upkeep = "depotRetrofitsUpkeep",
	},
	names = {
		radius = "Maintenance radius",
		vehicles = "Vehicles maintained",
		pollution = "Pollution",
		noise = "Noise",
		upkeep = "Upkeep",
	},
}

local radiusStep = 0.05
local vehiclesStep = 0.10
local emissionStep = 0.05
local upkeepPerOtherLevel = 0.25
local upkeepStep = 0.05
local firstLevelShare = 0.10 -- level 1 costs this share of the build price
local priceGrowth = 1.35 -- each further level costs this much more than the one before
local buildPricePerUpkeep = 6 -- every base depot and maintenance building costs 6 times its yearly upkeep to build

local round = function(x : number) : integer
	return math.floor(x + 0.5)
end

-- Construction params are 1-based indexes into the declared values, so the stored 1 is level 0 and 16 is level 15.
function levels.read(params : {string : any}) : {string : integer}
	local result : {string : integer} = {}
	for _, tree in ipairs(levels.trees) do
		local raw = params and tonumber(params[levels.paramKeys[tree]])
		local level = raw and (math.floor(raw) - 1) or 0
		result[tree] = math.max(0, math.min(levels.maxLevel, level))
	end
	return result
end

function levels.store(params : {string : any}, values : {string : integer})
	for _, tree in ipairs(levels.trees) do
		params[levels.paramKeys[tree]] = (values[tree] or 0) + 1
	end
end

function levels.otherLevels(values : {string : integer}) : integer
	return (values.radius or 0) + (values.vehicles or 0) + (values.pollution or 0) + (values.noise or 0)
end

-- At least one more vehicle per level, so small pools (rail depots hold 6) still grow.
function levels.pool(basePool : number, level : integer) : integer
	return math.max(round(basePool * (1 + vehiclesStep * level)), round(basePool) + level)
end

-- The base pool behind a pool built at a vehicles level (the smallest that gives it); nil when none does.
function levels.basePool(pool : number, level : integer) : integer
	if pool == nil then return nil end
	if level == 0 then return round(pool) end
	for base = 1, math.floor(pool) do
		if levels.pool(base, level) == pool then return base end
	end
	return nil
end

function levels.radius(baseRadius : number, level : integer) : number
	return baseRadius * (1 + radiusStep * level)
end

function levels.emissionFactor(level : integer) : number
	return 1 - emissionStep * level
end

function levels.upkeepFactor(values : {string : integer}) : number
	return (1 + upkeepPerOtherLevel * levels.otherLevels(values)) * (1 - upkeepStep * (values.upkeep or 0))
end

-- Rounded to $100: the game charges a whole-dollar upkeep, so undoing the levels' factor leaves up to about $12 of noise (at upkeep
-- level 15), which showed as a $10,124 price instead of $10,125. Every base depot's build price is a whole $100.
function levels.buildPrice(chargedUpkeep : number, values : {string : integer}) : number
	return 100 * round(buildPricePerUpkeep * chargedUpkeep / levels.upkeepFactor(values) / 100)
end

function levels.levelPrice(buildPrice : number, level : integer) : integer
	return round(firstLevelShare * buildPrice * priceGrowth ^ (level - 1))
end

return levels
