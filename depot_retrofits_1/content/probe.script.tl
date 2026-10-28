-- Levels probe (0.4). Two jobs, both logged with the "DEPOT_RETROFITS" prefix:
--
-- 1. Random levels. Once per save, a game day after the load, it gives the player's wrapped depots and maintenance buildings
--    levels by rebuilding them: every fourth building (by depot id) is a control and is left alone, the first of the others
--    gets every tree at 15, the second every tree but upkeep at 15, the rest a random level per tree (seeded by the
--    construction id, so a rerun gives the same levels). Only buildings without levels are picked. Before, and at checks
--    after 1 game hour, 1 day, 7 days and 1 month, it logs each building's pool, radius, upkeep, emitter power and vehicles,
--    with the values the formulas in levels.tl predict and whether they match. No money is charged for these.
-- 2. Buying a level. The levels card in the building's window (levels_card.script.tl) sends a buy event; this script checks
--    it (the level the card saw is still the stored one, below 15, within the company rank, enough money), rebuilds the
--    construction with the new level, books the price as depot construction, and logs the building before and after.
--
-- The company rank is logged at the load and at every check.

local stateVersion = 4 -- a state from an older probe is set aside, not continued

-- Shared with mod.script.tl, construction.script.tl and levels_card.script.tl; keep the copies equal.
local wrapperRef = "depot_retrofits_1::/construction.script@update"
local buyEvent = "depotRetrofitsBuy"

-- Clock units: a game day at calendar speed 1x is 4,000, a game year 1,461,000.
local dayClock = 4000
local monthClock = 121750
local startDelay = dayClock
local checkOffsets = { 200, dayClock, 7 * dayClock, monthClock }
local buyCheckOffsets = { 200, dayClock }
local buyPendingClock = 400 -- a second buy for the same building within this time is refused (the first rebuild is pending)
local maxTargets = 30
local controlEvery = 4

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

local record Target
	construction : Engine.Entity
	depot : Engine.Entity
	fileName : string
	role : string -- "control", "max", "noUpkeepTree" or "random"
	levels : {string : integer}
	before : Snapshot
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
	untilT : number
end

local record ProbeState
	version : integer
	firstSeen : number
	phase : string -- nil before the random rebuilds, then "sent", then "done"
	sentAt : number
	checksDone : integer
	targets : {Target}
	buys : {Buy}
	watches : {Watch}
	pending : {Pending}
end

local say = function(text : string)
	log.message("DEPOT_RETROFITS " .. text)
end

local levelsLoaded, levelsModule = pcall(ug_require, "depot_retrofits_1::/levels.tl")
local levels = levelsLoaded and (levelsModule as DepotRetrofitsLevels) or nil

local progressionLoaded, progressionModule = pcall(ug_require, "::/game_mechanics/company/company_progression_util.tl")
local progression = progressionLoaded and (progressionModule as CompanyProgressionUtil) or nil

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

local constructionForDepot = function(depot : Engine.Entity) : Engine.Entity
	local ok, construction = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForDepot, depot)
	if ok and exists(construction) then return construction end
	ok, construction = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction, depot)
	if ok and exists(construction) then return construction end
	return nil
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

-- "radius/vehicles/pollution/noise/upkeep".
local describeLevels = function(values : {string : integer}) : string
	if values == nil then return "nil" end
	local parts : {string} = {}
	for _, tree in ipairs(levels.trees) do parts[#parts + 1] = tostring(values[tree]) end
	return table.concat(parts, "/")
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
		.. " stored=" .. describeLevels(s.levels)
end

-- The base pool behind a pool built at a vehicles level (the smallest that gives it).
local basePool = function(pool : number, level : integer) : integer
	if pool == nil then return nil end
	if level == 0 then return math.floor(pool + 0.5) end
	for base = 1, math.floor(pool) do
		if levels.pool(base, level) == pool then return base end
	end
	return nil
end

-- What the building should read after going from one set of levels to another, from what it read before.
local expectedAfter = function(before : Snapshot, from : {string : integer}, to : {string : integer}) : Expected
	local e : Expected = {}
	local base = basePool(before.pool, from.vehicles)
	e.pool = base and levels.pool(base, to.vehicles) or nil
	if before.radius ~= nil then
		e.radius = before.radius / levels.radius(1, from.radius) * levels.radius(1, to.radius)
	end
	local ratio = levels.upkeepFactor(to) / levels.upkeepFactor(from)
	e.upkeepScript = before.upkeepScript and math.floor(before.upkeepScript * ratio + 0.5) or nil
	e.upkeepCharged = before.upkeepCharged and before.upkeepCharged * ratio or nil
	return e
end

local near = function(a : number, b : number, tolerance : number) : boolean
	return a ~= nil and b ~= nil and math.abs(a - b) <= tolerance
end

-- "match=pool:yes,radius:yes,upkeep:yes,levels:yes" with the expected values, and whether all matched.
local compare = function(snap : Snapshot, e : Expected, to : {string : integer}) : string, boolean
	local pool = snap.pool ~= nil and snap.pool == e.pool
	local radius = near(snap.radius, e.radius, 0.01)
	-- The script's upkeep from a building that already had levels went through two roundings.
	local upkeep = near(snap.upkeepScript, e.upkeepScript, 2)
	local stored = sameLevels(snap.levels, to)
	local yn = function(b : boolean) : string return b and "yes" or "no" end
	return "match=pool:" .. yn(pool) .. ",radius:" .. yn(radius) .. ",upkeep:" .. yn(upkeep) .. ",levels:" .. yn(stored)
		.. " expPool=" .. tostring(e.pool) .. " expRadius=" .. tostring(e.radius) .. " expUpkeepScript=" .. tostring(e.upkeepScript)
		.. " expUpkeepCharged=" .. tostring(e.upkeepCharged), pool and radius and upkeep and stored
end

local zeroLevels = function() : {string : integer}
	local result : {string : integer} = {}
	for _, tree in ipairs(levels.trees) do result[tree] = 0 end
	return result
end

local allLevels = function(level : integer, upkeep : integer) : {string : integer}
	local result : {string : integer} = {}
	for _, tree in ipairs(levels.trees) do result[tree] = level end
	result.upkeep = upkeep
	return result
end

-- Park-Miller generator, seeded by the construction id, so a rerun on the same save gives the same levels.
local randomLevels = function(seed : integer) : {string : integer}
	local x = (math.floor(seed) % 2147483646) + 1
	local result : {string : integer} = {}
	for _, tree in ipairs(levels.trees) do
		x = (x * 16807) % 2147483647
		result[tree] = math.floor(x) % (levels.maxLevel + 1)
	end
	return result
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

-- Random levels -------------------------------------------------------------------------------------------------------------

local pickTargets = function() : {Target}
	local okOwned, owned = pcall(api.engine.getEntitiesWithComponent, api.type.ComponentType.VEHICLE_DEPOT,
		{ requireOwnedByPlayer = api.engine.util.getPlayer() })
	if not okOwned or type(owned) ~= "table" then
		say("probe ownedUnavailable error=" .. tostring(owned))
		return {}
	end
	local depots : {Engine.Entity} = {}
	for _, depot in ipairs(owned as {Engine.Entity}) do depots[#depots + 1] = depot end
	table.sort(depots)
	local seen : {Engine.Entity : boolean} = {}
	local targets : {Target} = {}
	local eligible = 0
	for _, depot in ipairs(depots) do
		local construction = constructionForDepot(depot)
		local con = construction and getConstruction(construction)
		if con == nil then
			say("probe skip depot=" .. tostring(depot) .. " reason=noConstruction")
		elseif not seen[construction] then
			seen[construction] = true
			local wrapped = isWrapped(con)
			local stored = levels.read(constructionParams(con))
			local where = "probe skip depot=" .. tostring(depot) .. " construction=" .. tostring(construction)
			if wrapped == false then
				say(where .. " reason=notWrapped fileName=" .. tostring(con.fileName))
			elseif not sameLevels(stored, zeroLevels()) then
				say(where .. " reason=alreadyLevelled stored=" .. describeLevels(stored))
			elseif #targets >= maxTargets then
				say(where .. " reason=cap")
			else
				eligible = eligible + 1
				local target : Target = { construction = construction, depot = depot, fileName = tostring(con.fileName) }
				if eligible % controlEvery == 0 then
					target.role, target.levels = "control", zeroLevels()
				else
					local levelled = eligible - math.floor(eligible / controlEvery)
					if levelled == 1 then
						target.role, target.levels = "max", allLevels(levels.maxLevel, levels.maxLevel)
					elseif levelled == 2 then
						target.role, target.levels = "noUpkeepTree", allLevels(levels.maxLevel, 0)
					else
						target.role, target.levels = "random", randomLevels(construction)
					end
				end
				target.before = readSnapshot(depot, construction)
				targets[#targets + 1] = target
			end
		end
	end
	say("probe inventory owned=" .. tostring(#depots) .. " targets=" .. tostring(#targets) .. " wrappedRead="
		.. tostring(#targets == 0 or isWrapped(getConstruction(targets[1].construction)) ~= nil))
	return targets
end

local start = function(state : GameScriptState<ProbeState>, probe : ProbeState, t : number) : string
	probe.targets = pickTargets()
	for _, target in ipairs(probe.targets) do
		local charged = target.before.upkeepCharged
		say("probe before role=" .. target.role .. " construction=" .. tostring(target.construction) .. " depot=" .. tostring(target.depot)
			.. " fileName=" .. target.fileName .. " levels=" .. describeLevels(target.levels) .. " " .. describeSnapshot(target.before)
			.. " buildPrice=" .. tostring(charged and levels.buildPrice(charged, zeroLevels())))
	end
	-- The state is saved before anything is sent: a failure must not repeat on every update.
	probe.phase = "sent"
	probe.sentAt = t
	probe.checksDone = 0
	state:set(probe)
	local sent = 0
	for _, target in ipairs(probe.targets) do
		if target.role ~= "control" then
			local ok, ran, result = pcall(sendRebuild, target.construction, target.levels)
			if ok and ran then sent = sent + 1 end
			say("probe rebuild role=" .. target.role .. " construction=" .. tostring(target.construction)
				.. " levels=" .. describeLevels(target.levels) .. " result=" .. tostring(ok and result or ("error " .. tostring(ran))))
		end
	end
	say("probe rebuildsSent count=" .. tostring(sent) .. " " .. describeRank())
	return nil
end

local check = function(probe : ProbeState, n : integer) : string
	local t = now()
	say("probe check=" .. tostring(n) .. " t=" .. tostring(t) .. " sinceSent=" .. tostring(t - probe.sentAt) .. " " .. describeRank())
	local matched, levelled, controls = 0, 0, 0
	for _, target in ipairs(probe.targets or {}) do
		local snap = readSnapshot(target.depot, target.construction)
		local text, all = compare(snap, expectedAfter(target.before, zeroLevels(), target.levels), target.levels)
		if target.role == "control" then
			controls = controls + 1
		else
			levelled = levelled + 1
			if all then matched = matched + 1 end
		end
		say("probe after check=" .. tostring(n) .. " role=" .. target.role .. " construction=" .. tostring(target.construction)
			.. " depot=" .. tostring(target.depot) .. " levels=" .. describeLevels(target.levels) .. " " .. describeSnapshot(snap)
			.. " maintainedBefore=" .. tostring(target.before.maintained) .. " " .. text)
	end
	say("probe summary check=" .. tostring(n) .. " levelled=" .. tostring(levelled) .. " matched=" .. tostring(matched)
		.. " controls=" .. tostring(controls))
	return nil
end

-- Buying a level -----------------------------------------------------------------------------------------------------------

local isPending = function(probe : ProbeState, construction : Engine.Entity, t : number) : boolean
	for _, p in ipairs(probe.pending or {}) do
		if p.construction == construction and t < p.untilT then return true end
	end
	return false
end

-- Returns the reason a buy was refused, or nil when it was carried out.
local processBuy = function(probe : ProbeState, buy : Buy, t : number) : string
	if levels.paramKeys[buy.tree] == nil then return "unknownTree" end
	local con = getConstruction(buy.construction)
	if con == nil then return "noConstruction" end
	local depot = con.depots and con.depots[1]
	if not exists(depot) then return "noDepot" end
	local from = levels.read(constructionParams(con))
	if from[buy.tree] ~= buy.from then return "stale stored=" .. tostring(from[buy.tree]) end
	if buy.from >= levels.maxLevel then return "maxLevel" end
	if isPending(probe, buy.construction, t) then return "pending" end
	local rank, _, rankSource = readRank()
	if rank ~= nil and buy.from + 1 > rank then return "rank rank=" .. tostring(rank) end
	local charged = chargedUpkeepOf(depot)
	if charged == nil then return "noUpkeep" end
	local price = levels.levelPrice(levels.buildPrice(charged, from), buy.from + 1)
	local balance = balanceOf()
	if balance ~= nil and balance < price then return "noMoney balance=" .. tostring(balance) .. " price=" .. tostring(price) end

	local to : {string : integer} = {}
	for _, tree in ipairs(levels.trees) do to[tree] = from[tree] end
	to[buy.tree] = buy.from + 1
	local before = readSnapshot(depot, buy.construction)
	local ran, result = sendRebuild(buy.construction, to)
	if not ran then return "rebuild " .. result end
	local okCharge, chargeErr = pcall(bookPrice, price, con.fileName)
	say("buy done construction=" .. tostring(buy.construction) .. " depot=" .. tostring(depot) .. " tree=" .. buy.tree
		.. " level=" .. tostring(buy.from + 1) .. " price=" .. tostring(price) .. " charged=" .. tostring(okCharge)
		.. " chargeError=" .. tostring(chargeErr) .. " balanceBefore=" .. tostring(balance) .. " rank=" .. tostring(rank)
		.. " rankSource=" .. rankSource .. " from=" .. describeLevels(from) .. " to=" .. describeLevels(to) .. " " .. describeSnapshot(before))
	probe.pending = probe.pending or {}
	table.insert(probe.pending, { construction = buy.construction, untilT = t + buyPendingClock })
	probe.watches = probe.watches or {}
	table.insert(probe.watches, { construction = buy.construction, depot = depot, label = buy.tree .. tostring(buy.from + 1),
		startedAt = t, checksDone = 0, from = from, to = to, before = before })
	return nil
end

local processWatches = function(probe : ProbeState, t : number) : boolean
	local changed = false
	local kept : {Watch} = {}
	for _, watch in ipairs(probe.watches or {}) do
		local n = watch.checksDone + 1
		if t >= watch.startedAt + buyCheckOffsets[n] then
			watch.checksDone = n
			changed = true
			local snap = readSnapshot(watch.depot, watch.construction)
			local text = compare(snap, expectedAfter(watch.before, watch.from, watch.to), watch.to)
			say("buy after check=" .. tostring(n) .. " construction=" .. tostring(watch.construction) .. " bought=" .. watch.label
				.. " balance=" .. tostring(balanceOf()) .. " " .. describeSnapshot(snap) .. " maintainedBefore=" .. tostring(watch.before.maintained)
				.. " " .. text)
		end
		if watch.checksDone < #buyCheckOffsets then kept[#kept + 1] = watch end
	end
	probe.watches = kept
	local pending : {Pending} = {}
	for _, p in ipairs(probe.pending or {}) do
		if t < p.untilT then pending[#pending + 1] = p else changed = true end
	end
	probe.pending = pending
	return changed
end

local loadProbe = function(state : GameScriptState<ProbeState>) : ProbeState
	local probe = state:get() or {}
	if probe.version ~= stateVersion then
		if next(probe as table) ~= nil then
			say("probe oldStateReset version=" .. tostring(probe.version) .. " phase=" .. tostring(probe.phase))
		end
		probe = { version = stateVersion }
		state:set(probe)
	end
	return probe
end

local probeScript : GameScript<ProbeState> = {
	update = function(_userParams : table, state : GameScriptState<ProbeState>, _dt : number) : any
		if levels == nil then return end
		if not state:hasEventSubscriptions() then
			state:subscribeToEvent(buyEvent)
		end
		local probe = loadProbe(state)
		local t = now()
		if probe.firstSeen == nil then
			probe.firstSeen = t
			state:set(probe)
			say("probe loaded t=" .. tostring(t) .. " phase=" .. tostring(probe.phase) .. " startAt=" .. tostring(t + startDelay)
				.. " " .. describeRank())
		end

		-- One buy per update; the queue is saved first, so a buy that fails is not retried.
		if probe.buys ~= nil and #probe.buys > 0 then
			local buy = table.remove(probe.buys, 1)
			state:set(probe)
			local ok, refused = pcall(processBuy, probe, buy, t)
			if not ok or refused ~= nil then
				say("buy refused construction=" .. tostring(buy.construction) .. " tree=" .. tostring(buy.tree) .. " from=" .. tostring(buy.from)
					.. " reason=" .. tostring(ok and refused or ("error " .. tostring(refused))))
			end
			state:set(probe)
		end
		local okWatch, watched = pcall(processWatches, probe, t)
		if not okWatch then
			say("buy watchError error=" .. tostring(watched))
			probe.watches = {}
			state:set(probe)
		elseif watched then
			state:set(probe)
		end

		if probe.phase == "done" then return end
		if probe.phase == nil then
			if t < probe.firstSeen + startDelay then return end
			local ok, err = pcall(start, state, probe, t)
			if not ok then
				-- Before the rebuilds were sent, stop for good: the error would otherwise repeat on every update. After they were
				-- sent, the checks still run.
				if probe.phase == nil then probe.phase = "done" end
				state:set(probe)
				say("probe startError phase=" .. tostring(probe.phase) .. " error=" .. tostring(err))
			end
			return
		end
		local n = (probe.checksDone or 0) + 1
		if n > #checkOffsets or t < probe.sentAt + checkOffsets[n] then return end
		probe.checksDone = n
		if n == #checkOffsets then probe.phase = "done" end
		state:set(probe)
		local ok, err = pcall(check, probe, n)
		if not ok then say("probe checkError check=" .. tostring(n) .. " error=" .. tostring(err)) end
		if probe.phase == "done" then say("probe done") end
	end,
	-- Queued here and carried out in update: sendCommand cannot be called from handleEvent.
	handleEvent = function(_userParams : table, state : GameScriptState<ProbeState>, src : string, id : string, name : string, param : any) : any
		if name ~= buyEvent then return end
		local p = (type(param) == "table" and param or {}) as {string : any}
		local buy : Buy = {
			construction = math.floor(tonumber(p.construction) or -1) as Engine.Entity,
			tree = tostring(p.tree),
			from = math.floor(tonumber(p.from) or -1),
		}
		local probe = loadProbe(state)
		probe.buys = probe.buys or {}
		table.insert(probe.buys, buy)
		state:set(probe)
		say("buy queued src=" .. tostring(src) .. " id=" .. tostring(id) .. " construction=" .. tostring(buy.construction)
			.. " tree=" .. buy.tree .. " from=" .. tostring(buy.from) .. " queued=" .. tostring(#probe.buys))
	end,
}

return probeScript
