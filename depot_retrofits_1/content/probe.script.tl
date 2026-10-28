-- Rebuild probe. Once per save, a game day after the load, it rebuilds three buildings with the same replace proposal a level
-- purchase will use: the busiest depot and the busiest maintenance building with all five probe params set to 2 (pool x2,
-- radius x1.5, noise x0.5, pollution x0.25, upkeep x2, applied by construction.script.tl), and the next busiest building of
-- either kind as a control, with its params unchanged. Right after, it books two small test charges, one as depot
-- construction and one as infrastructure maintenance, to show where a level's price and upkeep would land in the finances.
-- Before and after, it logs per building whether the construction and depot entities survive, pool, radius, upkeep,
-- emissions, and where the vehicles it maintained before are now maintained and whether they kept their line; and one line
-- with every depot's usage. The after-state is logged eleven times, up to a game year later. On every later load of a save
-- made afterwards, it logs the three buildings again, to show whether loading regenerates them. The state remembers the run,
-- so it is not repeated. Log lines start with "DEPOT_RETROFITS".

-- Shared with mod.script.tl and construction.script.tl; keep the copies equal.
local poolParam = "depotRetrofitsProbePool"
local radiusParam = "depotRetrofitsProbeRadius"
local noiseParam = "depotRetrofitsProbeNoise"
local pollutionParam = "depotRetrofitsProbePollution"
local upkeepParam = "depotRetrofitsProbeUpkeep"
local probeParams = { poolParam, radiusParam, noiseParam, pollutionParam, upkeepParam }
local probeValue = 2

-- Clock units: a game year is 1,461,000.
local dayClock = 4000
local monthClock = 121750
local startDelay = dayClock
local checkOffsets = { 200, dayClock, 2 * dayClock, 4 * dayClock, 7 * dayClock, 14 * dayClock, monthClock, 2 * monthClock,
	3 * monthClock, 6 * monthClock, 12 * monthClock }
local testCharge = 1000
local maxInventoryLines = 80
local maxVehicleIds = 60
local maxLoadLogs = 20
local stateVersion = 2 -- a state from an older probe is set aside, not continued

local record Target
	kind : string -- "depot" or "maintenance"
	role : string -- "scaled" or "control"
	construction : Engine.Entity
	depot : Engine.Entity
	fileName : string
	vehicles : {Engine.Entity} -- maintained by the depot before the rebuild
	lines : {Engine.Entity} -- each vehicle's line before the rebuild, same order (0 for none)
end

local record ProbeState
	version : integer
	firstSeen : number
	phase : string -- nil before the rebuild, then "sent", then "done"
	sentAt : number
	checksDone : integer
	targets : {Target}
	depotsBefore : {Engine.Entity}
	loadLogs : integer
end

local record DepotInfo
	depot : Engine.Entity
	construction : Engine.Entity
	kind : string
	fileName : string
	pool : integer
	radius : number
	maxPoolUsage : number
	averagePoolUsage : number
	maintained : {Engine.Entity}
	inDepot : integer
	going : integer
	assigned : integer
	raw : string
	upkeepConstruction : string
	upkeepDepot : string
	upkeepCalc : string
	noisePower : string
	pollutionPower : string
end

-- Module variables do not survive a load, so this marks the first update after each load.
local loadSeen = false

local say = function(text : string)
	log.message("DEPOT_RETROFITS " .. text)
end

local exists = function(entity : Engine.Entity) : boolean
	if entity == nil then return false end
	local ok, result = pcall(api.engine.entityExists, entity)
	return ok and result == true
end

local now = function() : number
	local gameTime : Engine.Component.GameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
	return gameTime.gameTime
end

local balance = function() : string
	local ok, value = pcall(api.engine.util.finance.getPlayersBalance, api.engine.util.getPlayer())
	return ok and tostring(value) or "err"
end

local idList = function(entities : {Engine.Entity}) : string
	local parts : {string} = {}
	for i, entity in ipairs(entities) do
		if i > maxVehicleIds then
			parts[#parts + 1] = "..."
			break
		end
		parts[#parts + 1] = tostring(entity)
	end
	return table.concat(parts, ",")
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

local paramKeys = function(params : {string:any}) : string
	local keys : {string} = {}
	for key in pairs(params) do keys[#keys + 1] = tostring(key) end
	table.sort(keys)
	return table.concat(keys, ",")
end

-- The five probe params as "pool/radius/noise/pollution/upkeep".
local rawValues = function(params : {string:any}) : string
	local parts : {string} = {}
	for _, key in ipairs(probeParams) do parts[#parts + 1] = tostring(params[key]) end
	return table.concat(parts, "/")
end

local constructionForDepot = function(depot : Engine.Entity) : Engine.Entity
	local ok, construction = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForDepot, depot)
	if ok and exists(construction) then return construction end
	ok, construction = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction, depot)
	if ok and exists(construction) then return construction end
	return nil
end

local transportVehicle = function(vehicle : Engine.Entity) : Engine.Component.TransportVehicle
	return api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
end

-- Vehicles per maintenance station, from each vehicle's own record.
local assignedCounts = function() : {Engine.Entity : integer}, integer
	local counts : {Engine.Entity : integer} = {}
	local total = 0
	local ok, err = pcall(function() : string
		api.engine.forEachEntityWithComponent(function(vehicle : Engine.Entity)
			total = total + 1
			local tv = transportVehicle(vehicle)
			local station = tv and tv.maintenanceStation
			if station ~= nil then counts[station] = (counts[station] or 0) + 1 end
		end, api.type.ComponentType.TRANSPORT_VEHICLE)
		return nil
	end)
	if not ok then say("probe assignedUnavailable error=" .. tostring(err)) end
	return counts, total
end

local listOrEmpty = function(fn : function(Engine.Entity) : {Engine.Entity}, entity : Engine.Entity) : {Engine.Entity}
	local ok, list = pcall(fn, entity)
	if ok and type(list) == "table" then return list end
	return {}
end

local upkeepOf = function(entity : Engine.Entity) : string
	if entity == nil then return "nil" end
	local cost : Engine.Component.MaintenanceCost = nil
	local ok = pcall(function() : string
		cost = api.engine.getComponent(entity, api.type.ComponentType.MAINTENANCE_COST) as Engine.Component.MaintenanceCost
		return nil
	end)
	if not ok then return "err" end
	return cost and tostring(cost.maintenanceCost) or "none"
end

local readDepot = function(depot : Engine.Entity, assigned : {Engine.Entity : integer}) : DepotInfo
	local vd : Engine.Component.VehicleDepot = api.engine.getComponent(depot, api.type.ComponentType.VEHICLE_DEPOT)
	if vd == nil then return nil end
	local tvs = api.engine.system.transportVehicleSystem
	local info : DepotInfo = {
		depot = depot,
		kind = (#(vd.inNodes or {}) + #(vd.outNodes or {})) > 0 and "depot" or "maintenance",
		pool = vd.maintenancePool,
		radius = vd.catchmentArea and vd.catchmentArea.radius,
		maxPoolUsage = vd.maxPoolUsage,
		averagePoolUsage = vd.averagePoolUsage,
		maintained = listOrEmpty(tvs.getVehiclesForMaintenanceStation, depot),
		inDepot = #listOrEmpty(tvs.getDepotVehicles, depot),
		going = #listOrEmpty(tvs.getGoingToDepotVehicles, depot),
		assigned = assigned[depot] or 0,
		upkeepDepot = upkeepOf(depot),
	}
	local okCalc, calc = pcall(api.engine.util.maintenance.calcMaintenanceForSubconstruction, depot)
	info.upkeepCalc = okCalc and tostring(calc) or "err"
	local emitter = api.engine.getComponent(depot, api.type.ComponentType.EMISSION_EMITTER) as Engine.Component.EmissionEmitter
	info.noisePower = emitter and tostring(emitter.noisePower) or "none"
	info.pollutionPower = emitter and tostring(emitter.pollutionPower) or "none"
	info.construction = constructionForDepot(depot)
	info.upkeepConstruction = upkeepOf(info.construction)
	if info.construction ~= nil then
		local con : Engine.Component.Construction = api.engine.getComponent(info.construction, api.type.ComponentType.CONSTRUCTION)
		if con ~= nil then
			info.fileName = tostring(con.fileName)
			info.raw = rawValues(constructionParams(con))
		end
	end
	return info
end

local describe = function(info : DepotInfo) : string
	return "depot=" .. tostring(info.depot) .. " construction=" .. tostring(info.construction) .. " kind=" .. info.kind
		.. " fileName=" .. tostring(info.fileName) .. " pool=" .. tostring(info.pool) .. " radius=" .. tostring(info.radius)
		.. " maintained=" .. tostring(#info.maintained) .. " assigned=" .. tostring(info.assigned)
		.. " inDepot=" .. tostring(info.inDepot) .. " going=" .. tostring(info.going)
		.. " maxPoolUsage=" .. tostring(info.maxPoolUsage) .. " averagePoolUsage=" .. tostring(info.averagePoolUsage)
		.. " upkeepConstruction=" .. info.upkeepConstruction .. " upkeepDepot=" .. info.upkeepDepot
		.. " upkeepCalc=" .. info.upkeepCalc .. " noisePower=" .. info.noisePower .. " pollutionPower=" .. info.pollutionPower
		.. " raw=" .. tostring(info.raw)
end

local allDepots = function() : {Engine.Entity}
	local depots : {Engine.Entity} = {}
	local ok, err = pcall(function() : string
		api.engine.forEachEntityWithComponent(function(entity : Engine.Entity)
			depots[#depots + 1] = entity
		end, api.type.ComponentType.VEHICLE_DEPOT)
		return nil
	end)
	if not ok then say("probe depotsUnavailable error=" .. tostring(err)) end
	table.sort(depots)
	return depots
end

local ownedDepots = function() : {Engine.Entity : boolean}
	local owned : {Engine.Entity : boolean} = {}
	local ok, list = pcall(api.engine.getEntitiesWithComponent, api.type.ComponentType.VEHICLE_DEPOT,
		{ requireOwnedByPlayer = api.engine.util.getPlayer() })
	if ok and type(list) == "table" then
		for _, entity in ipairs(list) do owned[entity] = true end
	else
		say("probe ownedUnavailable error=" .. tostring(list))
	end
	return owned
end

local busier = function(a : DepotInfo, b : DepotInfo) : boolean
	if #a.maintained ~= #b.maintained then return #a.maintained > #b.maintained end
	if a.assigned ~= b.assigned then return a.assigned > b.assigned end
	return a.depot < b.depot
end

-- Every depot's usage on one line: "depot:maintained/pool".
local networkLine = function(label : string, infos : {DepotInfo}) : string
	local parts : {string} = {}
	for _, info in ipairs(infos) do
		parts[#parts + 1] = tostring(info.depot) .. ":" .. tostring(#info.maintained) .. "/" .. tostring(info.pool)
	end
	return "probe network label=" .. label .. " depots=" .. table.concat(parts, ",")
end

-- Logs every depot and returns the player's depots, busiest first (all depots if none are found as owned).
local inventory = function(label : string) : {DepotInfo}, {Engine.Entity}
	local assigned, vehicles = assignedCounts()
	local depots = allDepots()
	local owned = ownedDepots()
	local ownedCount = 0
	for _ in pairs(owned) do ownedCount = ownedCount + 1 end
	say("probe inventory label=" .. label .. " depots=" .. tostring(#depots) .. " owned=" .. tostring(ownedCount)
		.. " vehicles=" .. tostring(vehicles) .. " t=" .. tostring(now()))
	local eligible : {DepotInfo} = {}
	local lines = 0
	for _, depot in ipairs(depots) do
		local ok, info = pcall(readDepot, depot, assigned)
		if not ok then
			say("probe readError depot=" .. tostring(depot) .. " error=" .. tostring(info))
		elseif info ~= nil then
			if lines < maxInventoryLines then
				lines = lines + 1
				say("probe depot label=" .. label .. " owned=" .. tostring(owned[depot] == true) .. " " .. describe(info))
			end
			if info.construction ~= nil and (ownedCount == 0 or owned[depot] == true) then
				eligible[#eligible + 1] = info
			end
		end
	end
	table.sort(eligible, busier)
	return eligible, depots
end

local carrierFor = function(fileName : string) : JournalEntry.Carrier
	local carriers = api.type.JournalEntry.Carrier
	local name = (fileName or ""):lower()
	if name:find("tram", 1, true) then return carriers.TRAM end
	if name:find("/road/", 1, true) then return carriers.ROAD end
	if name:find("/rail/", 1, true) then return carriers.RAIL end
	if name:find("/water/", 1, true) then return carriers.WATER end
	return carriers.OTHER
end

-- Books one test charge; "construction" lands as depot construction, "maintenance" as infrastructure maintenance.
local bookCharge = function(category : string, carrier : JournalEntry.Carrier) : string
	local entry = api.type.JournalEntry.new()
	entry.amount = -testCharge
	entry.time = -1 -- the engine fills in the time
	if category == "construction" then
		entry.category.type = api.type.JournalEntry.Type.CONSTRUCTION
		entry.category.construction = api.type.JournalEntry.Construction.DEPOT
	else
		entry.category.type = api.type.JournalEntry.Type.MAINTENANCE
		entry.category.maintenance = api.type.JournalEntry.Maintenance.INFRASTRUCTURE
	end
	entry.category.carrier = carrier
	api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), entry, api.type.Vec3f.new(0, 0, 0)))
	return nil
end

local sendRebuild = function(target : Target) : string
	local con : Engine.Component.Construction = api.engine.getComponent(target.construction, api.type.ComponentType.CONSTRUCTION)
	if con == nil then
		say("probe rebuildSkipped kind=" .. target.kind .. " role=" .. target.role .. " reason=noConstruction construction="
			.. tostring(target.construction))
		return nil
	end
	local params = constructionParams(con)
	say("probe params kind=" .. target.kind .. " role=" .. target.role .. " construction=" .. tostring(target.construction)
		.. " keys=" .. paramKeys(params) .. " raw=" .. rawValues(params))
	if target.role == "scaled" then
		for _, key in ipairs(probeParams) do params[key] = probeValue end
	end
	local ok, proposal = pcall(api.engine.util.proposal.createProposalReplaceConstruction, target.construction, params)
	if not ok or proposal == nil then
		say("probe rebuildSkipped kind=" .. target.kind .. " role=" .. target.role .. " reason=noProposal error=" .. tostring(proposal))
		return nil
	end
	local sent, err = pcall(function() : string
		api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, false, false))
		return nil
	end)
	say("probe rebuildSent kind=" .. target.kind .. " role=" .. target.role .. " construction=" .. tostring(target.construction)
		.. " depot=" .. tostring(target.depot) .. " sent=" .. tostring(sent) .. " error=" .. tostring(err)
		.. " balance=" .. balance())
	return nil
end

local addTarget = function(targets : {Target}, info : DepotInfo, role : string)
	local lines : {Engine.Entity} = {}
	for i, vehicle in ipairs(info.maintained) do
		local tv = transportVehicle(vehicle)
		lines[i] = tv and tv.line or 0
	end
	say("probe before kind=" .. info.kind .. " role=" .. role .. " " .. describe(info) .. " vehicles=" .. idList(info.maintained)
		.. " lines=" .. idList(lines))
	table.insert(targets, {
		kind = info.kind,
		role = role,
		construction = info.construction,
		depot = info.depot,
		fileName = info.fileName,
		vehicles = info.maintained,
		lines = lines,
	})
end

local start = function(state : GameScriptState<ProbeState>, probe : ProbeState, t : number) : string
	local eligible, depots = inventory("before")
	say(networkLine("before", eligible))
	probe.targets = {}
	local picked : {Engine.Entity : boolean} = {}
	for _, kind in ipairs({ "depot", "maintenance" }) do
		local found = false
		for _, info in ipairs(eligible) do
			if info.kind == kind then
				addTarget(probe.targets, info, "scaled")
				picked[info.depot] = true
				found = true
				break
			end
		end
		if not found then say("probe noTarget kind=" .. kind) end
	end
	for _, info in ipairs(eligible) do
		if not picked[info.depot] then
			addTarget(probe.targets, info, "control")
			break
		end
	end
	-- The state is saved before anything is sent: a failure must not repeat on every update.
	probe.phase = "sent"
	probe.sentAt = t
	probe.checksDone = 0
	probe.depotsBefore = depots
	state:set(probe)
	say("probe balanceBefore=" .. balance())
	-- Each step on its own guard: a failure in one must not stop the others.
	for _, target in ipairs(probe.targets) do
		local ok, err = pcall(sendRebuild, target)
		if not ok then say("probe rebuildError kind=" .. target.kind .. " role=" .. target.role .. " error=" .. tostring(err)) end
	end
	local carrier = carrierFor(probe.targets[1] and probe.targets[1].fileName)
	for _, category in ipairs({ "construction", "maintenance" }) do
		local ok, err = pcall(bookCharge, category, carrier)
		say("probe charge category=" .. category .. " amount=-" .. tostring(testCharge) .. " sent=" .. tostring(ok)
			.. " error=" .. tostring(err) .. " balance=" .. balance())
	end
	return nil
end

-- The depot that stands for the target now: the old depot if it still exists, else the depot of the old construction, else a
-- depot that did not exist before the rebuild, of the same kind and construction file.
local currentDepot = function(target : Target, infos : {Engine.Entity : DepotInfo}, before : {Engine.Entity : boolean}) : DepotInfo, string, integer
	if exists(target.depot) and infos[target.depot] ~= nil then return infos[target.depot], "sameDepot", 1 end
	if exists(target.construction) then
		local con : Engine.Component.Construction = api.engine.getComponent(target.construction, api.type.ComponentType.CONSTRUCTION)
		for _, depot in ipairs(con and con.depots or {}) do
			if infos[depot] ~= nil then return infos[depot], "sameConstruction", 1 end
		end
	end
	local match : DepotInfo = nil
	local candidates = 0
	for depot, info in pairs(infos) do
		if not before[depot] and info.kind == target.kind and info.fileName == target.fileName then
			candidates = candidates + 1
			if match == nil or depot > match.depot then match = info end
		end
	end
	return match, match and "newDepot" or "notFound", candidates
end

-- Where the target's former vehicles are maintained now, and whether they kept their line.
local followVehicles = function(target : Target, info : DepotInfo) : string
	local kept, keptAssigned, onOldDepot, dangling, elsewhere, unassigned, gone = 0, 0, 0, 0, 0, 0, 0
	local lineKept, lineChanged = 0, 0
	local stations : {Engine.Entity : integer} = {}
	local maintainedNow : {Engine.Entity : boolean} = {}
	for _, vehicle in ipairs(info and info.maintained or {}) do maintainedNow[vehicle] = true end
	for i, vehicle in ipairs(target.vehicles or {}) do
		if not exists(vehicle) then
			gone = gone + 1
		else
			if maintainedNow[vehicle] then kept = kept + 1 end
			local tv = transportVehicle(vehicle)
			local station = tv and tv.maintenanceStation
			if station == nil then
				unassigned = unassigned + 1
			elseif info ~= nil and station == info.depot then
				keptAssigned = keptAssigned + 1
			elseif station == target.depot then
				onOldDepot = onOldDepot + 1 -- the old depot id, while another depot now stands for the target
			elseif not exists(station) then
				dangling = dangling + 1
			else
				elsewhere = elsewhere + 1
				stations[station] = (stations[station] or 0) + 1
			end
			if (tv and tv.line or 0) == ((target.lines or {})[i] or 0) then lineKept = lineKept + 1 else lineChanged = lineChanged + 1 end
		end
	end
	local parts : {string} = {}
	for station, count in pairs(stations) do parts[#parts + 1] = tostring(station) .. ":" .. tostring(count) end
	table.sort(parts)
	return "vehiclesBefore=" .. tostring(#(target.vehicles or {})) .. " stillMaintained=" .. tostring(kept)
		.. " stillAssigned=" .. tostring(keptAssigned) .. " onOldDepot=" .. tostring(onOldDepot) .. " dangling=" .. tostring(dangling)
		.. " assignedElsewhere=" .. tostring(elsewhere) .. " unassigned=" .. tostring(unassigned) .. " vehiclesGone=" .. tostring(gone)
		.. " lineKept=" .. tostring(lineKept) .. " lineChanged=" .. tostring(lineChanged)
		.. " elsewhereAt=" .. (#parts > 0 and table.concat(parts, ",") or "none")
end

local readAll = function(assigned : {Engine.Entity : integer}) : {Engine.Entity : DepotInfo}, {DepotInfo}
	local infos : {Engine.Entity : DepotInfo} = {}
	local list : {DepotInfo} = {}
	for _, depot in ipairs(allDepots()) do
		local ok, info = pcall(readDepot, depot, assigned)
		if ok and info ~= nil then
			infos[depot] = info
			list[#list + 1] = info
		end
	end
	return infos, list
end

local check = function(probe : ProbeState, n : integer) : string
	local before : {Engine.Entity : boolean} = {}
	for _, depot in ipairs(probe.depotsBefore or {}) do before[depot] = true end
	local infos, list = readAll((assignedCounts()))
	local newDepots = 0
	for _, info in ipairs(list) do
		if not before[info.depot] then
			newDepots = newDepots + 1
			say("probe newDepot check=" .. tostring(n) .. " " .. describe(info))
		end
	end
	say("probe check=" .. tostring(n) .. " t=" .. tostring(now()) .. " sinceSent=" .. tostring(now() - probe.sentAt)
		.. " newDepots=" .. tostring(newDepots) .. " balance=" .. balance())
	for _, target in ipairs(probe.targets or {}) do
		local info, how, candidates = currentDepot(target, infos, before)
		say("probe after check=" .. tostring(n) .. " kind=" .. target.kind .. " role=" .. target.role
			.. " oldConstruction=" .. tostring(target.construction) .. " oldConstructionExists=" .. tostring(exists(target.construction))
			.. " oldDepot=" .. tostring(target.depot) .. " oldDepotExists=" .. tostring(exists(target.depot))
			.. " found=" .. how .. " candidates=" .. tostring(candidates) .. " " .. followVehicles(target, info)
			.. (info and (" " .. describe(info) .. " vehicles=" .. idList(info.maintained)) or ""))
	end
	say(networkLine("check" .. tostring(n), list))
	return nil
end

-- After a load: the three buildings as they stand, to compare with the last check before the save.
local loadCheck = function(probe : ProbeState) : string
	local infos = readAll((assignedCounts()))
	say("probe reload t=" .. tostring(now()) .. " phase=" .. tostring(probe.phase) .. " checksDone=" .. tostring(probe.checksDone)
		.. " balance=" .. balance())
	for _, target in ipairs(probe.targets or {}) do
		local info = infos[target.depot]
		say("probe reload kind=" .. target.kind .. " role=" .. target.role .. " depotExists=" .. tostring(exists(target.depot))
			.. (info and (" " .. describe(info)) or ""))
	end
	return nil
end

local probeScript : GameScript<ProbeState> = {
	update = function(_userParams : table, state : GameScriptState<ProbeState>, _dt : number) : any
		local probe = state:get() or {}
		if probe.version ~= stateVersion then
			if next(probe as table) ~= nil then
				say("probe oldStateReset version=" .. tostring(probe.version) .. " phase=" .. tostring(probe.phase))
			end
			probe = { version = stateVersion }
			state:set(probe)
		end
		if not loadSeen then
			loadSeen = true
			-- Capped in the state as well, in case module variables reset more often than on a load.
			if probe.targets ~= nil and (probe.loadLogs or 0) < maxLoadLogs then
				probe.loadLogs = (probe.loadLogs or 0) + 1
				state:set(probe)
				local ok, err = pcall(loadCheck, probe)
				if not ok then say("probe reloadError error=" .. tostring(err)) end
			end
		end
		if probe.phase == "done" then return end
		local t = now()
		if probe.firstSeen == nil then
			probe.firstSeen = t
			state:set(probe)
			say("probe loaded t=" .. tostring(t) .. " phase=" .. tostring(probe.phase) .. " startAt=" .. tostring(t + startDelay))
		end
		if probe.phase == nil then
			if t < probe.firstSeen + startDelay then return end
			local ok, err = pcall(start, state, probe, t)
			if not ok then
				-- Before the rebuild was sent, stop for good: the error would otherwise repeat on every update. After it was sent,
				-- the checks still run.
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
	handleEvent = function(_userParams : table, _state : GameScriptState<ProbeState>, _src : string, _id : string, _name : string, _param : any) : any
	end,
}

return probeScript
