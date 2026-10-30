-- The game script: buying a level. The Retrofit tab in the building's window (retrofit_window.script.tl) sends a buy event;
-- this script checks it (the construction runs our wrapper, the level the tab saw is still the stored one, below 15, within
-- the company rank, enough money) and rebuilds the construction with the new level. Once the rebuild has landed (the stored
-- levels are the ones bought) it books the price as depot construction; a rebuild that never lands costs nothing. It logs the
-- building before, and after 1 game hour and 1 game day with the values the formulas in levels.tl predict. Log lines start
-- with "DEPOT_RETROFITS".
--
-- The random levelling that tested the formulas across a whole save (probe 0.4) is in git history; its results are in
-- docs/design/findings.md.

local stateVersion = 5 -- a state from an older version (the probes used 1 to 4) is set aside, not continued

-- wrapperRef is copied in mod.script.tl, buyEvent in retrofit_window.script.tl; keep the copies equal.
local wrapperRef = "depot_retrofits_1::/construction.script@update"
local buyEvent = "depotRetrofitsBuy"

-- Clock units: a game day at calendar speed 1x is 4,000, a game year 1,461,000.
local dayClock = 4000
local buyCheckOffsets = { 200, dayClock }
-- A buy is charged when its rebuild lands (the stored levels are the ones bought); until then a second buy for the same building
-- is refused. A rebuild that has not landed after this long in game time is given up, uncharged. Game time stops while the game
-- is paused, so landing is the normal way out.
local buyPendingClock = 400

local record Snapshot
	pool : number
	radius : number
	maintained : integer
	upkeepScript : number -- the construction's MAINTENANCE_COST, the update script's value
	upkeepCharged : number -- calcMaintenanceForSubconstruction, what the game charges
	noisePower : number
	pollutionPower : number
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
	to : {string : integer}
	untilT : number
	price : integer -- charged when the rebuild lands; nil in a state saved before charging moved here (already charged)
	fileName : string
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

local progressionLoaded, progressionModule = pcall(ug_require, "::/game_mechanics/company/company_progression_util.tl")
local progression = progressionLoaded and (progressionModule as CompanyProgressionUtil) or nil

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

-- The claimed rank (what the company window shows as reached) and the earned rank; nil when unreadable.
local readRank = function() : integer, integer, string
	if progression == nil then return nil, nil, "unavailable error=" .. tostring(progressionModule) end
	local ok, company = pcall(progression.getCompanyProgressionState, api.engine.util.getPlayer())
	if not ok or company == nil then return nil, nil, "unread error=" .. tostring(company) end
	return company.level, company.potentialLevel, "ok"
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

local describeSnapshot = function(s : Snapshot) : string
	return "pool=" .. tostring(s.pool) .. " radius=" .. tostring(s.radius) .. " maintained=" .. tostring(s.maintained)
		.. " upkeepScript=" .. tostring(s.upkeepScript) .. " upkeepCharged=" .. tostring(s.upkeepCharged)
		.. " noisePower=" .. tostring(s.noisePower) .. " pollutionPower=" .. tostring(s.pollutionPower)
		.. " stored=" .. levels.describe(s.levels)
end

-- What the building should read after going from one set of levels to another, from what it read before.
local expectedAfter = function(before : Snapshot, from : {string : integer}, to : {string : integer}) : Expected
	local e : Expected = {}
	local base = levels.basePool(before.pool, from.vehicles)
	e.pool = base and levels.pool(base, to.vehicles) or nil
	if before.radius ~= nil then
		e.radius = before.radius / levels.radius(1, from.radius) * levels.radius(1, to.radius)
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

local sendRebuild = function(construction : Engine.Entity, values : {string : integer}) : boolean, string
	local con = getConstruction(construction)
	if con == nil then return false, "noConstruction" end
	local params = constructionParams(con)
	levels.store(params, values)
	local ok, proposal = pcall(api.engine.util.proposal.createProposalReplaceConstruction, construction, params)
	if not ok or proposal == nil then return false, "noProposal error=" .. tostring(proposal) end
	local sent, err = pcall(function() : string
		api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, false, false))
		return nil
	end)
	if not sent then return false, "sendError error=" .. tostring(err) end
	return true, "sent"
end

local carrierFor = function(fileName : string) : JournalEntry.Carrier
	local lower = (fileName or ""):lower()
	if lower:find("tram", 1, true) then return api.type.JournalEntry.Carrier.TRAM end
	if lower:find("/rail/", 1, true) then return api.type.JournalEntry.Carrier.RAIL end
	if lower:find("/water/", 1, true) then return api.type.JournalEntry.Carrier.WATER end
	return api.type.JournalEntry.Carrier.ROAD
end

-- Books a level's price as depot construction.
local bookPrice = function(amount : integer, fileName : string) : string
	local entry = api.type.JournalEntry.new()
	entry.amount = -amount
	entry.time = -1 -- the engine fills in the time
	entry.category.type = api.type.JournalEntry.Type.CONSTRUCTION
	entry.category.construction = api.type.JournalEntry.Construction.DEPOT
	entry.category.carrier = carrierFor(fileName)
	api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), entry, api.type.Vec3f.new(0, 0, 0)))
	return nil
end

local stillPending = function(p : Pending, t : number) : boolean
	return t < p.untilT and not sameLevels(storedLevels(p.construction), p.to)
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
	local depot = con.depots and con.depots[1]
	if not exists(depot) then return "noDepot" end
	local from = levels.read(constructionParams(con))
	if from[buy.tree] ~= buy.from then return "stale stored=" .. tostring(from[buy.tree]) end
	if buy.from >= levels.maxLevel then return "maxLevel" end
	if isPending(retrofit, buy.construction, t) then return "pending" end
	local rank, _, rankSource = readRank()
	if rank ~= nil and buy.from + 1 > rank then return "rank rank=" .. tostring(rank) end
	local charged = chargedUpkeepOf(depot)
	if charged == nil then return "noUpkeep" end
	local price = levels.levelPrice(levels.buildPrice(charged, from), buy.tree, buy.from + 1)
	local balance = balanceOf()
	if balance ~= nil and balance < price then return "noMoney balance=" .. tostring(balance) .. " price=" .. tostring(price) end

	local to = levels.withLevel(from, buy.tree, buy.from + 1)
	local before = readSnapshot(depot, buy.construction)
	local ran, result = sendRebuild(buy.construction, to)
	if not ran then return "rebuild " .. result end
	local label = buy.tree .. tostring(buy.from + 1)
	say("buy sent construction=" .. tostring(buy.construction) .. " depot=" .. tostring(depot) .. " tree=" .. buy.tree
		.. " level=" .. tostring(buy.from + 1) .. " price=" .. tostring(price) .. " balanceBefore=" .. tostring(balance)
		.. " rank=" .. tostring(rank) .. " rankSource=" .. rankSource .. " from=" .. levels.describe(from) .. " to=" .. levels.describe(to)
		.. " " .. describeSnapshot(before))
	retrofit.pending = retrofit.pending or {}
	table.insert(retrofit.pending, { construction = buy.construction, to = to, untilT = t + buyPendingClock, price = price,
		fileName = con.fileName, label = label })
	retrofit.watches = retrofit.watches or {}
	table.insert(retrofit.watches, { construction = buy.construction, depot = depot, label = label,
		startedAt = t, checksDone = 0, from = from, to = to, before = before })
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
		if sameLevels(stored, p.to) then
			changed = true
			if p.price ~= nil then
				local balance = balanceOf()
				local okCharge, chargeErr = pcall(bookPrice, p.price, p.fileName)
				say("buy charged construction=" .. tostring(p.construction) .. " bought=" .. tostring(p.label) .. " price=" .. tostring(p.price)
					.. " charged=" .. tostring(okCharge) .. " chargeError=" .. tostring(chargeErr) .. " balanceBefore=" .. tostring(balance))
			end
		elseif t >= p.untilT then
			changed = true
			say("buy notLanded construction=" .. tostring(p.construction) .. " bought=" .. tostring(p.label) .. " price=" .. tostring(p.price)
				.. " stored=" .. levels.describe(stored) .. " expected=" .. levels.describe(p.to) .. " charged=false")
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
			say("gameScript loaded t=" .. tostring(t) .. " " .. describeRank())
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
		say("buy queued src=" .. tostring(src) .. " id=" .. tostring(id) .. " construction=" .. tostring(buy.construction)
			.. " tree=" .. buy.tree .. " from=" .. tostring(buy.from) .. " queued=" .. tostring(#retrofit.buys))
	end,
}

return retrofitScript
