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
-- Each level adds this share of the base upkeep. Pollution and noise add less, since they do not change what the building
-- does (a wider radius or a larger pool can mean fewer buildings). Pollution adds least: the town's rating spreads it over the
-- whole town area, so it takes many buildings to show. Noise counts where people are.
local upkeepPerLevel : {string : number} = { radius = 0.15, vehicles = 0.15, pollution = 0.05, noise = 0.10 }
local upkeepStep = 0.05
-- Level 1 costs this share of the build price. The upkeep tree starts higher, since it pays for itself; pollution and noise
-- start lower, for the same reason that they add less upkeep.
local firstLevelShare : {string : number} = { radius = 0.15, vehicles = 0.15, pollution = 0.08, noise = 0.12, upkeep = 0.25 }
local priceGrowth = 1.15 -- each further level costs this much more than the one before
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

-- "radius/vehicles/pollution/noise/upkeep", the form every log line uses; "nil" for no levels.
function levels.describe(values : {string : integer}) : string
	if values == nil then return "nil" end
	local parts : {string} = {}
	for _, tree in ipairs(levels.trees) do parts[#parts + 1] = tostring(values[tree]) end
	return table.concat(parts, "/")
end

-- A copy of the levels with one tree at another level.
function levels.withLevel(values : {string : integer}, tree : string, level : integer) : {string : integer}
	local result : {string : integer} = {}
	for _, t in ipairs(levels.trees) do result[t] = values[t] end
	result[tree] = level
	return result
end

-- At least one more vehicle per level, so small pools (rail depots hold 6) still grow.
function levels.pool(basePool : number, level : integer) : integer
	return math.max(round(basePool * (1 + vehiclesStep * level)), round(basePool) + level)
end

-- The base pool behind a pool built at a vehicles level; nil when none gives it. The pool grows with the base, so at most one
-- does. The base can be 0: a modular depot whose vehicles all come from its modules has none before them.
function levels.basePool(pool : number, level : integer) : integer
	if pool == nil then return nil end
	if level == 0 then return round(pool) end
	for base = 0, math.floor(pool) do
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

-- Summed in the fixed order of levels.trees, so every script gets the same floating-point factor.
function levels.upkeepFactor(values : {string : integer}) : number
	local added = 0.0
	for _, tree in ipairs(levels.trees) do
		added = added + (upkeepPerLevel[tree] or 0) * (values[tree] or 0)
	end
	return (1 + added) * (1 - upkeepStep * (values.upkeep or 0))
end

-- The update script's upkeep at some levels, rounded to whole dollars as construction.script.tl stores it. Every script that
-- works out an upkeep goes through here, so the floating-point product is the same everywhere (60,850 × 2.85 is 173,422.4999…).
function levels.levelledUpkeep(baseUpkeep : number, values : {string : integer}) : integer
	return round(baseUpkeep * levels.upkeepFactor(values))
end

local trailingZeros = function(n : integer) : integer
	if n == 0 then return 99 end
	local count = 0
	while n % 10 == 0 do
		n = math.floor(n / 10)
		count = count + 1
	end
	return count
end

-- The whole-dollar upkeep before the levels behind a stored upkeep; nil when none gives it. Below a factor of 1 (upkeep levels
-- with few others) two or more do, as 0.95 × 60,050 and 0.95 × 60,051 both round to 57,048: the roundest is taken, since every
-- base depot's upkeep and every Roundhouse module's is a multiple of $50.
function levels.baseUpkeep(scriptUpkeep : number, values : {string : integer}) : integer
	if scriptUpkeep == nil then return nil end
	local guess = scriptUpkeep / levels.upkeepFactor(values)
	local best : integer = nil
	local bestZeros, bestDistance = -1, math.huge
	for base = math.max(0, math.floor(guess) - 4), math.ceil(guess) + 4 do
		if levels.levelledUpkeep(base, values) == scriptUpkeep then
			local zeros, distance = trailingZeros(base), math.abs(base - guess)
			if zeros > bestZeros or (zeros == bestZeros and distance < bestDistance) then
				best, bestZeros, bestDistance = base, zeros, distance
			end
		end
	end
	return best
end

-- Rounded to $100: the game charges a whole-dollar upkeep, so undoing the levels' factor leaves up to about $12 of noise (at upkeep
-- level 15), which showed as a $10,124 price instead of $10,125. Every base depot's build price is a whole $100.
function levels.buildPrice(chargedUpkeep : number, values : {string : integer}) : number
	return 100 * round(buildPricePerUpkeep * chargedUpkeep / levels.upkeepFactor(values) / 100)
end

function levels.levelPrice(buildPrice : number, tree : string, level : integer) : integer
	return round(firstLevelShare[tree] * buildPrice * priceGrowth ^ (level - 1))
end

return levels
