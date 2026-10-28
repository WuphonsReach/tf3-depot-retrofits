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
	-- Sum of the radius, vehicles, pollution and noise levels (the ones that raise upkeep).
	otherLevels : function(levels : {string : integer}) : integer

	pool : function(basePool : number, level : integer) : integer
	radius : function(baseRadius : number, level : integer) : number
	emissionFactor : function(level : integer) : number
	upkeepFactor : function(levels : {string : integer}) : number

	-- The building's build price at today's prices, from the upkeep the game charges for it now and its current levels.
	buildPrice : function(chargedUpkeep : number, levels : {string : integer}) : number
	-- The price of level n of any tree, rounded to whole money.
	levelPrice : function(buildPrice : number, level : integer) : integer
end
