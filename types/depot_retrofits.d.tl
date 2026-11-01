-- The type of the shared levels module (depot_retrofits_1/content/levels.tl), for type checking only; the mod does not ship
-- this file. Each script loads the module with ug_require and casts it to this record.

global record DepotRetrofitsLevels
	maxLevel : integer
	trees : {string} -- the five trees in display order
	paramKeys : {string : string} -- tree -> construction param key
	names : {string : string} -- tree -> display name

	-- The levels stored in a construction's params, 0 for a tree with no param (a building placed before the mod, or new).
	read : function(params : {string : any}) : {string : integer}
	-- Writes the levels into a params table, in the stored form (1-based index into "0".."15").
	store : function(params : {string : any}, levels : {string : integer})
	-- "radius/vehicles/pollution/noise/upkeep", as the log lines write levels; "nil" for nil.
	describe : function(levels : {string : integer}) : string
	-- A copy of the levels with one tree at another level.
	withLevel : function(levels : {string : integer}, tree : string, level : integer) : {string : integer}

	pool : function(basePool : number, level : integer) : integer
	basePool : function(pool : number, level : integer) : integer
	radius : function(baseRadius : number, level : integer) : number
	baseRadius : function(radius : number, level : integer) : number
	emissionFactor : function(level : integer) : number
	upkeepFactor : function(levels : {string : integer}) : number
	-- The update script's upkeep at some levels, in whole dollars, from the upkeep before any level.
	levelledUpkeep : function(baseUpkeep : number, levels : {string : integer}) : integer
	-- The whole-dollar upkeep before the levels behind a stored upkeep (the roundest when several give it); nil when none does.
	baseUpkeep : function(scriptUpkeep : number, levels : {string : integer}) : integer

	-- The building's build price at today's prices, from the upkeep the game charges for it now and its current levels.
	buildPrice : function(chargedUpkeep : number, levels : {string : integer}) : number
	-- The price of level n of a tree, rounded to whole money.
	levelPrice : function(buildPrice : number, tree : string, level : integer) : integer
end

-- The type of the company rank module (depot_retrofits_1/content/company_rank.tl).
global record DepotRetrofitsRank
	-- The claimed rank, the earned rank and where they were read ("util", "state ..."); nil, nil and "unknown ..." when neither
	-- read works.
	read : function(player : Engine.Entity) : integer, integer, string
end

