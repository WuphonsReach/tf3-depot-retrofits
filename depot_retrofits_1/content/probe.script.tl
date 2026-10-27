-- Rebuild probe. Once per save, a game day after the load, it rebuilds the busiest depot and the busiest maintenance building
-- with both probe params set to 2 (pool x2, radius x1.5, applied by construction.script.tl), using the same replace proposal a
-- level purchase will use. Before and after, it logs whether the construction and depot entities survive, the pool and radius,
-- and which of the vehicles the depot maintained before are still maintained by it. The after-state is logged five times, up to
-- two game months later. The state remembers that the probe ran, so a save made afterwards does not run it again. Log lines
-- start with "DEPOT_RETROFITS".

-- Shared with mod.script.tl and construction.script.tl; keep the copies equal.
local poolParam = "depotRetrofitsProbePool"
local radiusParam = "depotRetrofitsProbeRadius"
local probeValue = 2

-- Clock units: a game year is 1,461,000.
local dayClock = 4000
local monthClock = 121750
local startDelay = dayClock
local checkOffsets = { 200, dayClock, 7 * dayClock, monthClock, 2 * monthClock }
local maxInventoryLines = 80
local maxVehicleIds = 60

local record Target
	kind : string -- "depot" or "maintenance"
	construction : Engine.Entity
	depot : Engine.Entity
	fileName : string
	vehicles : {Engine.Entity} -- maintained by the depot before the rebuild
end

local record ProbeState
	firstSeen : number
	phase : string -- nil before the rebuild, then "sent", then "done"
	sentAt : number
	checksDone : integer
	targets : {Target}
	depotsBefore : {Engine.Entity}
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
	rawPool : string
	rawRadius : string
end

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

local constructionForDepot = function(depot : Engine.Entity) : Engine.Entity
	local ok, construction = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForDepot, depot)
	if ok and exists(construction) then return construction end
	ok, construction = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction, depot)
	if ok and exists(construction) then return construction end
	return nil
end

-- Vehicles per maintenance station, from each vehicle's own record.
local assignedCounts = function() : {Engine.Entity : integer}, integer
	local counts : {Engine.Entity : integer} = {}
	local total = 0
	local ok, err = pcall(function() : string
		api.engine.forEachEntityWithComponent(function(vehicle : Engine.Entity)
			total = total + 1
			local tv : Engine.Component.TransportVehicle = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
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
	}
	info.construction = constructionForDepot(depot)
	if info.construction ~= nil then
		local con : Engine.Component.Construction = api.engine.getComponent(info.construction, api.type.ComponentType.CONSTRUCTION)
		if con ~= nil then
			info.fileName = tostring(con.fileName)
			local params = constructionParams(con)
			info.rawPool = tostring(params[poolParam])
			info.rawRadius = tostring(params[radiusParam])
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
		.. " rawPool=" .. tostring(info.rawPool) .. " rawRadius=" .. tostring(info.rawRadius)
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

-- Logs every depot and picks the busiest depot and maintenance building (most vehicles maintained, then most assigned).
local inventory = function(label : string) : {string : DepotInfo}, {Engine.Entity}
	local assigned, vehicles = assignedCounts()
	local depots = allDepots()
	local owned = ownedDepots()
	local ownedCount = 0
	for _ in pairs(owned) do ownedCount = ownedCount + 1 end
	say("probe inventory label=" .. label .. " depots=" .. tostring(#depots) .. " owned=" .. tostring(ownedCount)
		.. " vehicles=" .. tostring(vehicles) .. " t=" .. tostring(now()))
	local best : {string : DepotInfo} = {}
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
			-- With no owned depots found (the filter may not apply to depot entities), every depot competes.
			local eligible = ownedCount == 0 or owned[depot] == true
			local current = best[info.kind]
			if eligible and info.construction ~= nil and (current == nil or #info.maintained > #current.maintained
				or (#info.maintained == #current.maintained and info.assigned > current.assigned)) then
				best[info.kind] = info
			end
		end
	end
	return best, depots
end

local sendRebuild = function(target : Target) : string
	local con : Engine.Component.Construction = api.engine.getComponent(target.construction, api.type.ComponentType.CONSTRUCTION)
	if con == nil then
		say("probe rebuildSkipped kind=" .. target.kind .. " reason=noConstruction construction=" .. tostring(target.construction))
		return nil
	end
	local params = constructionParams(con)
	say("probe params kind=" .. target.kind .. " construction=" .. tostring(target.construction) .. " keys=" .. paramKeys(params)
		.. " rawPool=" .. tostring(params[poolParam]) .. " rawRadius=" .. tostring(params[radiusParam]))
	params[poolParam] = probeValue
	params[radiusParam] = probeValue
	local ok, proposal = pcall(api.engine.util.proposal.createProposalReplaceConstruction, target.construction, params)
	if not ok or proposal == nil then
		say("probe rebuildSkipped kind=" .. target.kind .. " reason=noProposal error=" .. tostring(proposal))
		return nil
	end
	local sent, err = pcall(function() : string
		api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, false, false))
		return nil
	end)
	say("probe rebuildSent kind=" .. target.kind .. " construction=" .. tostring(target.construction)
		.. " depot=" .. tostring(target.depot) .. " sent=" .. tostring(sent) .. " error=" .. tostring(err)
		.. " balance=" .. balance())
	return nil
end

local start = function(state : GameScriptState<ProbeState>, probe : ProbeState, t : number) : string
	local best, depots = inventory("before")
	probe.targets = {}
	for _, kind in ipairs({ "depot", "maintenance" }) do
		local info = best[kind]
		if info == nil then
			say("probe noTarget kind=" .. kind)
		else
			say("probe before kind=" .. kind .. " " .. describe(info) .. " vehicles=" .. idList(info.maintained))
			table.insert(probe.targets, {
				kind = kind,
				construction = info.construction,
				depot = info.depot,
				fileName = info.fileName,
				vehicles = info.maintained,
			})
		end
	end
	-- The state is saved before anything is sent: a failure must not repeat on every update.
	probe.phase = "sent"
	probe.sentAt = t
	probe.checksDone = 0
	probe.depotsBefore = depots
	state:set(probe)
	say("probe balanceBefore=" .. balance())
	-- Each target on its own guard: a failure on the first must not stop the second.
	for _, target in ipairs(probe.targets) do
		local ok, err = pcall(sendRebuild, target)
		if not ok then say("probe rebuildError kind=" .. target.kind .. " error=" .. tostring(err)) end
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

local check = function(probe : ProbeState, n : integer) : string
	local before : {Engine.Entity : boolean} = {}
	for _, depot in ipairs(probe.depotsBefore or {}) do before[depot] = true end
	local assigned = assignedCounts()
	local infos : {Engine.Entity : DepotInfo} = {}
	local newDepots = 0
	for _, depot in ipairs(allDepots()) do
		local ok, info = pcall(readDepot, depot, assigned)
		if ok and info ~= nil then
			infos[depot] = info
			if not before[depot] then
				newDepots = newDepots + 1
				say("probe newDepot check=" .. tostring(n) .. " " .. describe(info))
			end
		end
	end
	say("probe check=" .. tostring(n) .. " t=" .. tostring(now()) .. " sinceSent=" .. tostring(now() - probe.sentAt)
		.. " newDepots=" .. tostring(newDepots) .. " balance=" .. balance())
	for _, target in ipairs(probe.targets or {}) do
		local info, how, candidates = currentDepot(target, infos, before)
		local kept, keptAssigned, onOldDepot, dangling, elsewhere, unassigned, gone = 0, 0, 0, 0, 0, 0, 0
		local maintainedNow : {Engine.Entity : boolean} = {}
		for _, vehicle in ipairs(info and info.maintained or {}) do maintainedNow[vehicle] = true end
		for _, vehicle in ipairs(target.vehicles or {}) do
			if not exists(vehicle) then
				gone = gone + 1
			else
				if maintainedNow[vehicle] then kept = kept + 1 end
				local tv : Engine.Component.TransportVehicle = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
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
				end
			end
		end
		say("probe after check=" .. tostring(n) .. " kind=" .. target.kind
			.. " oldConstruction=" .. tostring(target.construction) .. " oldConstructionExists=" .. tostring(exists(target.construction))
			.. " oldDepot=" .. tostring(target.depot) .. " oldDepotExists=" .. tostring(exists(target.depot))
			.. " found=" .. how .. " candidates=" .. tostring(candidates)
			.. " vehiclesBefore=" .. tostring(#(target.vehicles or {})) .. " stillMaintained=" .. tostring(kept)
			.. " stillAssigned=" .. tostring(keptAssigned) .. " onOldDepot=" .. tostring(onOldDepot) .. " dangling=" .. tostring(dangling)
			.. " assignedElsewhere=" .. tostring(elsewhere) .. " unassigned=" .. tostring(unassigned) .. " vehiclesGone=" .. tostring(gone)
			.. (info and (" " .. describe(info) .. " vehicles=" .. idList(info.maintained)) or ""))
	end
	return nil
end

local probeScript : GameScript<ProbeState> = {
	update = function(_userParams : table, state : GameScriptState<ProbeState>, _dt : number) : any
		local probe = state:get() or {}
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
