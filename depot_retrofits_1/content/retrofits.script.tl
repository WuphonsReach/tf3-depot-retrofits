-- The game script: buying a level. The Retrofit tab in the building's window (retrofit_window.script.tl) sends a buy event;
-- this script checks it (the construction runs our wrapper, the level the tab saw is still the stored one, below 15, within
-- the company rank, enough money; a rank that cannot be read refuses the buy) and rebuilds the construction with the new
-- level, once the game has said it would build the rebuild (rebuild_check.tl; a blocked one is refused). Once the rebuild has landed (the stored levels are the ones bought) it books the price as depot construction under
-- the depot's carrier; a rebuild that never lands costs nothing. It logs each
-- buy and its outcome; at logLevel "full" (settings.tl) also the building before, and after 1 game hour, 1 day, 7 days and
-- 30 days with the values the formulas in levels.tl predict and the pollution and noise in dB at the building (the later checks
-- show the map's averaged pollution settling). Log lines start with "DEPOT_RETROFITS".
--
-- The random levelling that tested the formulas across a whole save (probe 0.4) is in git history; its results are in
-- docs/design/findings.md.

local stateVersion = 6 -- a state from an older version (the probes used 1 to 4; 5 kept all five levels per pending buy) is set aside, not continued

-- wrapperRef is copied in mod.script.tl, buyEvent in retrofit_window.script.tl; keep the copies equal.
local wrapperRef = "depot_retrofits_1::/construction.script@update"
local buyEvent = "depotRetrofitsBuy"

-- Clock units: a game day at calendar speed 1x is 4,000, a game year 1,461,000.
local dayClock = 4000
local buyCheckOffsets = { 200, dayClock, 7 * dayClock, 30 * dayClock }
-- A buy is charged when its rebuild lands: the stored level in its tree is at least the one bought, so a later buy landing first
-- also counts. Until then a second buy for the same building is refused. A rebuild that has not landed after a game day is given
-- up, uncharged; at the fastest speed that is about a second, and game time stops while the game is paused.
-- The pending buy keeps only its tree and level: in a run of quick buys, two recorded with all five levels were found holding
-- the levels from before the buy, so they never matched and went uncharged (docs/design/findings.md).
local buyPendingClock = dayClock

local record Snapshot
	pool : number
	radius : number
	maintained : integer
	upkeepScript : number -- the construction's MAINTENANCE_COST, the update script's value
	upkeepCharged : number -- calcMaintenanceForSubconstruction, what the game charges
	noisePower : number
	pollutionPower : number
	-- The emission grid at the building in dB, live and averaged (the map and its cursor number show the averaged pollution)
	pollutionDb : number
	pollutionDbAverage : number
	noiseDb : number
	noiseDbAverage : number
	-- The pollution grid's global wind (m/s); it blows the pollution field downwind, so a reading depends on it
	windX : number
	windY : number
	emissionError : string
	levels : {string : integer}
end

local record Expected
	pool : number
	radius : number
	upkeepScript : number
	upkeepCharged : number
end

local record Buy
	construction : Engine.Entity
	tree : string
	from : integer
end

local record Watch
	construction : Engine.Entity
	depot : Engine.Entity
	label : string
	startedAt : number
	checksDone : integer
	from : {string : integer}
	to : {string : integer}
	before : Snapshot
end

local record Pending
	construction : Engine.Entity
	tree : string
	level : integer
	untilT : number
	price : integer -- charged when the rebuild lands
	fileName : string
	carrier : string -- the finance row's carrier, "ROAD", "RAIL", "TRAM", "WATER" or "AIR"
	label : string
end

local record RetrofitState
	version : integer
	buys : {Buy}
	watches : {Watch}
	pending : {Pending}
end

local say = function(text : string)
	log.message("DEPOT_RETROFITS " .. text)
end

local levelsLoaded, levelsModule = pcall(ug_require, "depot_retrofits_1::/levels.tl")
local levels = levelsLoaded and (levelsModule as DepotRetrofitsLevels) or nil
-- Without it update does nothing (no buy is taken), so the reason goes to the log.
if not levelsLoaded then say("gameScript levels unavailable error=" .. tostring(levelsModule)) end

-- settings.tl's logLevel: "full" adds the snapshots and the checks after each buy, which are read only then, and the queued
-- lines. Guarded: without the file the log stays at "summary".
local settingsLoaded, settingsModule = pcall(ug_require, "depot_retrofits_1::/settings.tl")
local logFull = settingsLoaded and type(settingsModule) == "table" and (settingsModule as {string:any}).logLevel == "full"

-- Without it the rank is unknown and every buy is refused.
local rankLoaded, rankModule = pcall(ug_require, "depot_retrofits_1::/company_rank.tl")
local companyRank = rankLoaded and (rankModule as DepotRetrofitsRank) or nil

-- Without it a rebuild is sent unchecked, as in 1.0: one the game refuses then never lands and is not charged.
local checkLoaded, checkModule = pcall(ug_require, "depot_retrofits_1::/rebuild_check.tl")
local rebuildCheck = checkLoaded and (checkModule as DepotRetrofitsRebuildCheck) or nil

-- Module variables do not persist across saves; this only keeps the load line to one per session.
local loadLogged = false

local exists = function(entity : Engine.Entity) : boolean
	if entity == nil then return false end
	local ok, result = pcall(api.engine.entityExists, entity)
	return ok and result == true
end

local now = function() : number
	local gameTime : Engine.Component.GameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
	return gameTime.gameTime
end

local balanceOf = function() : number
	local ok, value = pcall(api.engine.util.finance.getPlayersBalance, api.engine.util.getPlayer())
	return ok and tonumber(value) or nil
end

-- The claimed rank (what the company window shows as reached) and the earned rank; nil when unknown.
local readRank = function() : integer, integer, string
	if companyRank == nil then return nil, nil, "unknown moduleError=" .. tostring(rankModule) end
	return companyRank.read(api.engine.util.getPlayer())
end

local describeRank = function() : string
	local level, potential, source = readRank()
	return "rank=" .. tostring(level) .. " earnedRank=" .. tostring(potential) .. " rankSource=" .. source
end

-- The construction's params as a plain table (the replace proposal takes a full set).
local constructionParams = function(construction : Engine.Component.Construction) : {string:any}
	local source : {string:any} = nil
	if construction.params_native ~= nil then
		local ok, asTable = pcall(construction.params_native.asTable, construction.params_native)
		if ok and asTable ~= nil then source = asTable as {string:any} end
	end
	if source == nil then source = (construction.params as table) as {string:any} end
	local params : {string:any} = {}
	for key, value in pairs(source or {}) do params[key] = value end
	return params
end

local getConstruction = function(construction : Engine.Entity) : Engine.Component.Construction
	if not exists(construction) then return nil end
	return api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
end

-- The construction's depot. Maintenance buildings in a save begun on a pre-release build list none in `depots` (all 13
-- seen in the mod.io save "333", road, rail and water, built 1904 to 1998; its depots list theirs), so the fallback is the
-- first subconstruction with a vehicle depot, which is how the base construction window finds its tabs
-- (gui/entity_window/make_entity_window.tl). The same function is in retrofit_window.script.tl: keep the copies equal.
local firstDepot = function(construction : Engine.Entity) : Engine.Entity
	local con = api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	if con == nil then return nil end
	if con.depots and con.depots[1] then return con.depots[1] end
	for _, sub in ipairs(con.subconstructions or {}) do
		if api.engine.getComponent(sub, api.type.ComponentType.VEHICLE_DEPOT) ~= nil then return sub end
	end
	return nil
end

local storedLevels = function(construction : Engine.Entity) : {string : integer}
	local con = getConstruction(construction)
	return con and levels.read(constructionParams(con)) or nil
end

-- true when the construction's definition runs our wrapper; nil when the definition cannot be read.
local isWrapped = function(con : Engine.Component.Construction) : boolean
	local ok, ref = pcall(function() : string
		return api.res.constructionRep.findAndGet(con.fileName).updateScript.fileName
	end)
	if not ok then return nil end
	return ref == wrapperRef
end

local upkeepOf = function(entity : Engine.Entity) : number
	local value : number = nil
	pcall(function() : string
		local cost = api.engine.getComponent(entity, api.type.ComponentType.MAINTENANCE_COST) as Engine.Component.MaintenanceCost
		value = cost and cost.maintenanceCost or nil
		return nil
	end)
	return value
end

local chargedUpkeepOf = function(depot : Engine.Entity) : number
	local ok, value = pcall(api.engine.util.maintenance.calcMaintenanceForSubconstruction, depot)
	return ok and tonumber(value) or nil
end

-- The grid's value in dB at a point, as the pollution layer's cursor number reads it (gui/main/game_tooltips.tl).
local emissionDb = function(position : Vec3f, average : boolean, kind : Engine.Component.EmissionGrid.Type) : number
	local power = api.engine.system.emissionGridSystem.getInterpolatedEmission(api.type.Vec2f.new(position.x, position.y), average, kind)
	return api.util.powerToDecibel(power)
end

local readEmissionDb = function(snap : Snapshot, emitter : Engine.Component.EmissionEmitter)
	if emitter == nil or emitter.position == nil then return end
	local ok, err = pcall(function() : string
		local pollution = api.type.EmissionGrid.Type.Pollution
		local noise = api.type.EmissionGrid.Type.Noise
		snap.pollutionDb = emissionDb(emitter.position, false, pollution)
		snap.pollutionDbAverage = emissionDb(emitter.position, true, pollution)
		snap.noiseDb = emissionDb(emitter.position, false, noise)
		snap.noiseDbAverage = emissionDb(emitter.position, true, noise)
		local grid = api.engine.getComponent(api.engine.system.emissionGridSystem.getEmissionGridEntity(false),
			api.type.ComponentType.EMISSION_GRID) as Engine.Component.EmissionGrid
		if grid ~= nil and grid.wind ~= nil then
			snap.windX = grid.wind.x
			snap.windY = grid.wind.y
		end
		return nil
	end)
	if not ok then snap.emissionError = tostring(err) end
end

local readSnapshot = function(depot : Engine.Entity, construction : Engine.Entity) : Snapshot
	local snap : Snapshot = {}
	if exists(depot) then
		local vd : Engine.Component.VehicleDepot = api.engine.getComponent(depot, api.type.ComponentType.VEHICLE_DEPOT)
		if vd ~= nil then
			snap.pool = vd.maintenancePool
			snap.radius = vd.catchmentArea and vd.catchmentArea.radius
		end
		local ok, list = pcall(api.engine.system.transportVehicleSystem.getVehiclesForMaintenanceStation, depot)
		snap.maintained = ok and type(list) == "table" and #list or nil
		snap.upkeepCharged = chargedUpkeepOf(depot)
		local emitter = api.engine.getComponent(depot, api.type.ComponentType.EMISSION_EMITTER) as Engine.Component.EmissionEmitter
		snap.noisePower = emitter and emitter.noisePower
		snap.pollutionPower = emitter and emitter.pollutionPower
		readEmissionDb(snap, emitter)
	end
	snap.upkeepScript = exists(construction) and upkeepOf(construction) or nil
	snap.levels = storedLevels(construction)
	return snap
end

local sameLevels = function(a : {string : integer}, b : {string : integer}) : boolean
	if a == nil or b == nil then return false end
	for _, tree in ipairs(levels.trees) do
		if a[tree] ~= b[tree] then return false end
	end
	return true
end

local formatDb = function(value : number) : string
	return value ~= nil and string.format("%.2f", value) or "nil"
end

local describeSnapshot = function(s : Snapshot) : string
	return "pool=" .. tostring(s.pool) .. " radius=" .. tostring(s.radius) .. " maintained=" .. tostring(s.maintained)
		.. " upkeepScript=" .. tostring(s.upkeepScript) .. " upkeepCharged=" .. tostring(s.upkeepCharged)
		.. " noisePower=" .. tostring(s.noisePower) .. " pollutionPower=" .. tostring(s.pollutionPower)
		-- live/average
		.. " pollutionDb=" .. formatDb(s.pollutionDb) .. "/" .. formatDb(s.pollutionDbAverage)
		.. " noiseDb=" .. formatDb(s.noiseDb) .. "/" .. formatDb(s.noiseDbAverage)
		.. " wind=" .. formatDb(s.windX) .. "," .. formatDb(s.windY)
		.. (s.emissionError and (" emissionError=" .. s.emissionError) or "")
		.. " stored=" .. levels.describe(s.levels)
end

-- What the building should read after going from one set of levels to another, from what it read before.
local expectedAfter = function(before : Snapshot, from : {string : integer}, to : {string : integer}) : Expected
	local e : Expected = {}
	local base = levels.basePool(before.pool, from.vehicles)
	e.pool = base and levels.pool(base, to.vehicles) or nil
	if before.radius ~= nil then
		e.radius = levels.radius(levels.baseRadius(before.radius, from.radius), to.radius)
	end
	local ratio = levels.upkeepFactor(to) / levels.upkeepFactor(from)
	local baseUpkeep = levels.baseUpkeep(before.upkeepScript, from)
	e.upkeepScript = baseUpkeep and levels.levelledUpkeep(baseUpkeep, to)
		or (before.upkeepScript and math.floor(before.upkeepScript * ratio + 0.5) or nil)
	e.upkeepCharged = before.upkeepCharged and before.upkeepCharged * ratio or nil
	return e
end

local near = function(a : number, b : number, tolerance : number) : boolean
	return a ~= nil and b ~= nil and math.abs(a - b) <= tolerance
end

-- "match=pool:yes,radius:yes,upkeep:yes,levels:yes" with the expected values.
local compare = function(snap : Snapshot, e : Expected, to : {string : integer}) : string
	local pool = snap.pool ~= nil and snap.pool == e.pool
	local radius = near(snap.radius, e.radius, 0.01)
	-- The script's upkeep from a building that already had levels went through two roundings.
	local upkeep = near(snap.upkeepScript, e.upkeepScript, 2)
	local stored = sameLevels(snap.levels, to)
	local yn = function(b : boolean) : string return b and "yes" or "no" end
	return "match=pool:" .. yn(pool) .. ",radius:" .. yn(radius) .. ",upkeep:" .. yn(upkeep) .. ",levels:" .. yn(stored)
		.. " expPool=" .. tostring(e.pool) .. " expRadius=" .. tostring(e.radius) .. " expUpkeepScript=" .. tostring(e.upkeepScript)
		.. " expUpkeepCharged=" .. tostring(e.upkeepCharged)
end

-- Sends the rebuild once the game has said it would build it. A blocked rebuild is not sent: the game would refuse it ("Collision"
-- where something built around the building since is in its way), so the buy is refused at once instead of waiting out the
-- pending deadline. When the check itself fails the rebuild is sent unchecked. The second result is the reason, or the check's outcome.
local sendRebuild = function(construction : Engine.Entity, values : {string : integer}) : boolean, string
	local con = getConstruction(construction)
	if con == nil then return false, "noConstruction" end
	local params = constructionParams(con)
	levels.store(params, values)
	local proposal : Proposal = nil
	local checked = "unchecked moduleError=" .. tostring(checkModule)
	if rebuildCheck ~= nil then
		local clear, reason : boolean, string
		proposal, clear, reason = rebuildCheck.check(construction, params)
		if clear == false then return false, "blocked " .. reason end
		checked = clear and "clear" or ("unchecked " .. reason)
	end
	if proposal == nil then
		local ok, made = pcall(api.engine.util.proposal.createProposalReplaceConstruction, construction, params)
		if not ok or made == nil then return false, "noProposal error=" .. tostring(made) end
		proposal = made
	end
	local sent, err = pcall(function() : string
		api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, false, false))
		return nil
	end)
	if not sent then return false, "sendError error=" .. tostring(err) end
	return true, checked
end

-- The carrier the construction's file names: "TRAM", "RAIL", "WATER" or "ROAD" (the base depots' folders).
local pathCarrier = function(fileName : string) : string
	local lower = (fileName or ""):lower()
	if lower:find("tram", 1, true) then return "TRAM" end
	if lower:find("/rail/", 1, true) then return "RAIL" end
	if lower:find("/water/", 1, true) then return "WATER" end
	return "ROAD"
end

-- In this order, so a depot whose modes give road and another carrier is booked under the other one.
local carrierNames = { "RAIL", "WATER", "AIR", "TRAM", "ROAD" }

-- The carriers of a depot's transport modes, the way the base depot list filters depots by carrier
-- (areCarriersContainedInTransportModes in gui/statistics/statistics_react_util.tl, the categories in statistic_depots.tl).
-- Its carrier field is not used: read against the same enum, it gave no carrier on any of 21 buildings (why was not logged).
local depotCarrier = function(depot : Engine.Entity) : string
	local vd = api.engine.getComponent(depot, api.type.ComponentType.VEHICLE_DEPOT) as Engine.Component.VehicleDepot
	if vd == nil or vd.transportModes == nil then return nil end
	local modes : {TransportMode} = {}
	for mode, on in pairs(vd.transportModes) do
		if on then modes[#modes + 1] = mode end
	end
	local carriers = api.engine.util.transport.transportModesToCarriers(modes)
	for _, name in ipairs(carrierNames) do
		for _, carrier in ipairs(carriers or {}) do
			if carrier == api.type["enum"].Carrier[name] then return name end
		end
	end
	return nil
end

-- The finance row's carrier and where it came from. The depot's decides, since mod depots sit outside the base folders (the
-- Boathouse mod's maintenance building is under assets/); without it, the file does, and the source says why.
local carrierFor = function(depot : Engine.Entity, fileName : string) : string, string
	local ok, fromDepot = pcall(depotCarrier, depot)
	if not ok then return pathCarrier(fileName), "path error=" .. tostring(fromDepot) end
	if fromDepot == nil then return pathCarrier(fileName), "path noDepotCarrier" end
	return fromDepot, "depot"
end

local journalCarrier = function(name : string) : JournalEntry.Carrier
	local c = api.type.JournalEntry.Carrier
	local byName : {string : JournalEntry.Carrier} = { ROAD = c.ROAD, RAIL = c.RAIL, TRAM = c.TRAM, WATER = c.WATER, AIR = c.AIR }
	return byName[name] or c.ROAD
end

-- Books a level's price as depot construction.
local bookPrice = function(amount : integer, carrier : string) : string
	local entry = api.type.JournalEntry.new()
	entry.amount = -amount
	entry.time = -1 -- the engine fills in the time
	entry.category.type = api.type.JournalEntry.Type.CONSTRUCTION
	entry.category.construction = api.type.JournalEntry.Construction.DEPOT
	entry.category.carrier = journalCarrier(carrier)
	api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), entry, api.type.Vec3f.new(0, 0, 0)))
	return nil
end

local landed = function(p : Pending, stored : {string : integer}) : boolean
	return stored ~= nil and (stored[p.tree] or 0) >= p.level
end

local stillPending = function(p : Pending, t : number) : boolean
	return t < p.untilT and not landed(p, storedLevels(p.construction))
end

local isPending = function(retrofit : RetrofitState, construction : Engine.Entity, t : number) : boolean
	for _, p in ipairs(retrofit.pending or {}) do
		if p.construction == construction and stillPending(p, t) then return true end
	end
	return false
end

-- Returns the reason a buy was refused, or nil when it was carried out.
local processBuy = function(retrofit : RetrofitState, buy : Buy, t : number) : string
	if levels.paramKeys[buy.tree] == nil then return "unknownTree" end
	local con = getConstruction(buy.construction)
	if con == nil then return "noConstruction" end
	if isWrapped(con) == false then return "notWrapped fileName=" .. tostring(con.fileName) end
	local depot = firstDepot(buy.construction)
	if not exists(depot) then return "noDepot" end
	local from = levels.read(constructionParams(con))
	if from[buy.tree] ~= buy.from then return "stale stored=" .. tostring(from[buy.tree]) end
	if buy.from >= levels.maxLevel then return "maxLevel" end
	if isPending(retrofit, buy.construction, t) then return "pending" end
	local rank, _, rankSource = readRank()
	if rank == nil then return "rankUnknown rankSource=" .. rankSource end
	if buy.from + 1 > rank then return "rank rank=" .. tostring(rank) end
	local charged = chargedUpkeepOf(depot)
	if charged == nil then return "noUpkeep" end
	local price = levels.levelPrice(levels.buildPrice(charged, from), buy.tree, buy.from + 1)
	local balance = balanceOf()
	if balance ~= nil and balance < price then return "noMoney balance=" .. tostring(balance) .. " price=" .. tostring(price) end

	local to = levels.withLevel(from, buy.tree, buy.from + 1)
	local before = logFull and readSnapshot(depot, buy.construction) or nil
	local ran, result = sendRebuild(buy.construction, to)
	if not ran then return result:sub(1, 7) == "blocked" and result or ("rebuild " .. result) end
	local label = buy.tree .. tostring(buy.from + 1)
	local carrier, carrierSource = carrierFor(depot, con.fileName)
	say("buy sent construction=" .. tostring(buy.construction) .. " depot=" .. tostring(depot) .. " tree=" .. buy.tree
		.. " level=" .. tostring(buy.from + 1) .. " price=" .. tostring(price) .. " balanceBefore=" .. tostring(balance)
		.. " rank=" .. tostring(rank) .. " rankSource=" .. rankSource .. " carrier=" .. carrier .. " carrierSource=" .. carrierSource
		.. " rebuildCheck=" .. result .. " from=" .. levels.describe(from) .. " to=" .. levels.describe(to)
		.. (before ~= nil and (" " .. describeSnapshot(before)) or ""))
	retrofit.pending = retrofit.pending or {}
	table.insert(retrofit.pending, { construction = buy.construction, tree = buy.tree, level = buy.from + 1,
		untilT = t + buyPendingClock, price = price, fileName = con.fileName, carrier = carrier, label = label })
	if before ~= nil then
		retrofit.watches = retrofit.watches or {}
		table.insert(retrofit.watches, { construction = buy.construction, depot = depot, label = label,
			startedAt = t, checksDone = 0, from = from, to = to, before = before })
	end
	return nil
end

local processWatches = function(retrofit : RetrofitState, t : number) : boolean
	local changed = false
	local kept : {Watch} = {}
	for _, watch in ipairs(retrofit.watches or {}) do
		local n = watch.checksDone + 1
		if t >= watch.startedAt + buyCheckOffsets[n] then
			watch.checksDone = n
			changed = true
			local snap = readSnapshot(watch.depot, watch.construction)
			say("buy after check=" .. tostring(n) .. " construction=" .. tostring(watch.construction) .. " bought=" .. watch.label
				.. " balance=" .. tostring(balanceOf()) .. " " .. describeSnapshot(snap) .. " maintainedBefore=" .. tostring(watch.before.maintained)
				.. " pollutionDbBefore=" .. formatDb(watch.before.pollutionDb) .. "/" .. formatDb(watch.before.pollutionDbAverage)
				.. " " .. compare(snap, expectedAfter(watch.before, watch.from, watch.to), watch.to))
		end
		if watch.checksDone < #buyCheckOffsets then kept[#kept + 1] = watch end
	end
	retrofit.watches = kept
	return changed
end

-- Charges each buy whose rebuild has landed and gives up the ones that did not land in time; true when the list changed.
local processPending = function(retrofit : RetrofitState, t : number) : boolean
	local changed = false
	local pending : {Pending} = {}
	for _, p in ipairs(retrofit.pending or {}) do
		local stored = storedLevels(p.construction)
		if landed(p, stored) then
			changed = true
			if p.price ~= nil then
				local balance = balanceOf()
				-- A pending buy saved before the carrier was kept falls back to the file's.
				local carrier = p.carrier or pathCarrier(p.fileName)
				local okCharge, chargeErr = pcall(bookPrice, p.price, carrier)
				say("buy charged construction=" .. tostring(p.construction) .. " bought=" .. tostring(p.label) .. " price=" .. tostring(p.price)
					.. " carrier=" .. carrier .. " charged=" .. tostring(okCharge) .. " chargeError=" .. tostring(chargeErr)
					.. " balanceBefore=" .. tostring(balance))
			end
		elseif t >= p.untilT then
			changed = true
			say("buy notLanded construction=" .. tostring(p.construction) .. " bought=" .. tostring(p.label) .. " price=" .. tostring(p.price)
				.. " stored=" .. levels.describe(stored) .. " expected=" .. tostring(p.tree) .. ">=" .. tostring(p.level) .. " charged=false")
		else
			pending[#pending + 1] = p
		end
	end
	retrofit.pending = pending
	return changed
end

local loadState = function(state : GameScriptState<RetrofitState>) : RetrofitState
	local retrofit = state:get() or {}
	if retrofit.version ~= stateVersion then
		if next(retrofit as table) ~= nil then
			say("oldStateReset version=" .. tostring(retrofit.version))
		end
		retrofit = { version = stateVersion }
		state:set(retrofit)
	end
	return retrofit
end

local retrofitScript : GameScript<RetrofitState> = {
	update = function(_userParams : table, state : GameScriptState<RetrofitState>, _dt : number) : any
		if levels == nil then return end
		if not state:hasEventSubscriptions() then
			state:subscribeToEvent(buyEvent)
		end
		local retrofit = loadState(state)
		local t = now()
		if not loadLogged then
			loadLogged = true
			say("gameScript loaded t=" .. tostring(t) .. " " .. describeRank() .. " rebuildCheck=" .. tostring(rebuildCheck ~= nil))
		end

		-- One buy per update; the queue is saved first, so a buy that fails is not retried.
		if retrofit.buys ~= nil and #retrofit.buys > 0 then
			local buy = table.remove(retrofit.buys, 1)
			state:set(retrofit)
			local ok, refused = pcall(processBuy, retrofit, buy, t)
			if not ok or refused ~= nil then
				say("buy refused construction=" .. tostring(buy.construction) .. " tree=" .. tostring(buy.tree) .. " from=" .. tostring(buy.from)
					.. " reason=" .. tostring(ok and refused or ("error " .. tostring(refused))))
			end
			state:set(retrofit)
		end
		local okPending, charged = pcall(processPending, retrofit, t)
		if not okPending then
			-- Dropped, so a failing charge is not retried (and possibly booked) on every update.
			say("buy pendingError error=" .. tostring(charged) .. " dropped=" .. tostring(retrofit.pending and #retrofit.pending))
			retrofit.pending = {}
			state:set(retrofit)
		elseif charged then
			state:set(retrofit)
		end
		local okWatch, watched = pcall(processWatches, retrofit, t)
		if not okWatch then
			say("buy watchError error=" .. tostring(watched))
			retrofit.watches = {}
			state:set(retrofit)
		elseif watched then
			state:set(retrofit)
		end
	end,
	-- Queued here and carried out in update: sendCommand cannot be called from handleEvent.
	handleEvent = function(_userParams : table, state : GameScriptState<RetrofitState>, src : string, id : string, name : string, param : any) : any
		if name ~= buyEvent then return end
		local p = (type(param) == "table" and param or {}) as {string : any}
		local buy : Buy = {
			construction = math.floor(tonumber(p.construction) or -1) as Engine.Entity,
			tree = tostring(p.tree),
			from = math.floor(tonumber(p.from) or -1),
		}
		local retrofit = loadState(state)
		retrofit.buys = retrofit.buys or {}
		table.insert(retrofit.buys, buy)
		state:set(retrofit)
		if logFull then
			say("buy queued src=" .. tostring(src) .. " id=" .. tostring(id) .. " construction=" .. tostring(buy.construction)
				.. " tree=" .. buy.tree .. " from=" .. tostring(buy.from) .. " queued=" .. tostring(#retrofit.buys))
		end
	end,
}

return retrofitScript
