-- Param probe (0.3). Once per save, a game day after the load, it rebuilds the three busiest player buildings, each with one
-- variant of a level param set to 6 (level 5): one declared with an availability year far in the future, one declared with a
-- single value, and one not declared at all. Before and after, it reads the construction's stored params back, to show
-- which variant a rebuild keeps (the wrapper's log shows which variant reaches the update script). It also books two test
-- charges with distinctive amounts, depot construction and infrastructure maintenance, and logs the finance table's rows
-- before and after, to show where a level's price and upkeep land. Depots placed during the run are logged at each check
-- with their params. The state remembers the run, so it is not repeated. Log lines start with "DEPOT_RETROFITS".

-- Shared with mod.script.tl and construction.script.tl; keep the copies equal.
local futureParam = "depotRetrofitsFutureLevel"
local singleParam = "depotRetrofitsSingleLevel"
local undeclaredParam = "depotRetrofitsUndeclaredLevel"
local variants = { futureParam, singleParam, undeclaredParam }
local testValue = 6

-- Clock units: a game year is 1,461,000.
local dayClock = 4000
local monthClock = 121750
local startDelay = dayClock
local checkOffsets = { 200, dayClock, 7 * dayClock, monthClock }
local constructionCharge = 12345
local maintenanceCharge = 23456
local stateVersion = 3 -- a state from an older probe is set aside, not continued

local record Target
	variant : string
	construction : Engine.Entity
	depot : Engine.Entity
end

local record ProbeState
	version : integer
	firstSeen : number
	phase : string -- nil before the rebuild, then "sent", then "done"
	sentAt : number
	checksDone : integer
	targets : {Target}
	depotsBefore : {Engine.Entity}
end

local record Candidate
	depot : Engine.Entity
	construction : Engine.Entity
	maintained : integer
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

-- The stored params of a construction: its keys and the three variants as "future/single/undeclared".
local storedParams = function(construction : Engine.Entity) : string
	if not exists(construction) then return "construction=gone" end
	local con : Engine.Component.Construction = api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION)
	if con == nil then return "construction=noComponent" end
	local params = constructionParams(con)
	local values : {string} = {}
	for _, key in ipairs(variants) do values[#values + 1] = tostring(params[key]) end
	return "fileName=" .. tostring(con.fileName) .. " stored=" .. table.concat(values, "/") .. " keys=" .. paramKeys(params)
end

local constructionForDepot = function(depot : Engine.Entity) : Engine.Entity
	local ok, construction = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForDepot, depot)
	if ok and exists(construction) then return construction end
	ok, construction = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction, depot)
	if ok and exists(construction) then return construction end
	return nil
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

local poolOf = function(depot : Engine.Entity) : string
	local vd : Engine.Component.VehicleDepot = api.engine.getComponent(depot, api.type.ComponentType.VEHICLE_DEPOT)
	return vd and tostring(vd.maintenancePool) or "none"
end

-- The finance table's investment and "other" rows (construction, upkeep, subsidies), one list of per-year amounts per row,
-- as the game's own finance window computes them. Copied from the Best Before probe.
local describeFinance = function() : string
	local config = api.type.ChartConfig.new()
	config.interval = 1461000 -- one clock year of game clock units (not a calendar year)
	config.count = 4
	config.minCount = 4
	config.yStepScale = 1.0
	local ok, data = pcall(api.engine.util.finance.computeFinanceTable, api.engine.util.getPlayer(), config)
	if not ok then return "unavailable" end
	local parts : {string} = {}
	local amounts = function(values : {integer}) : string
		local text : {string} = {}
		for _, v in ipairs(values) do text[#text + 1] = tostring(v) end
		return table.concat(text, ",")
	end
	data:foreach_investment(function(key : integer, values : {integer})
		local kind = data:unfoldKey(key)
		parts[#parts + 1] = "investment[" .. tostring(kind[1]) .. "/" .. tostring(kind[2]) .. "/" .. tostring(kind[3]) .. "]=" .. amounts(values)
	end)
	data:foreach_other(function(other : JournalEntry.Other, values : {integer})
		parts[#parts + 1] = "other[" .. tostring(other) .. "]=" .. amounts(values)
	end)
	return table.concat(parts, " ")
end

local logFinance = function(label : string)
	local ok, text = pcall(describeFinance)
	say("probe finance label=" .. label .. " balance=" .. balance() .. " rows=" .. tostring(ok and text or ("error " .. tostring(text))))
end

-- Books one test charge; "construction" as depot construction, "maintenance" as infrastructure maintenance, both road.
local bookCharge = function(category : string, amount : integer) : string
	local entry = api.type.JournalEntry.new()
	entry.amount = -amount
	entry.time = -1 -- the engine fills in the time
	if category == "construction" then
		entry.category.type = api.type.JournalEntry.Type.CONSTRUCTION
		entry.category.construction = api.type.JournalEntry.Construction.DEPOT
	else
		entry.category.type = api.type.JournalEntry.Type.MAINTENANCE
		entry.category.maintenance = api.type.JournalEntry.Maintenance.INFRASTRUCTURE
	end
	entry.category.carrier = api.type.JournalEntry.Carrier.ROAD
	api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), entry, api.type.Vec3f.new(0, 0, 0)))
	return nil
end

local sendRebuild = function(target : Target) : string
	local con : Engine.Component.Construction = api.engine.getComponent(target.construction, api.type.ComponentType.CONSTRUCTION)
	if con == nil then
		say("probe rebuildSkipped variant=" .. target.variant .. " reason=noConstruction")
		return nil
	end
	local params = constructionParams(con)
	params[target.variant] = testValue
	local ok, proposal = pcall(api.engine.util.proposal.createProposalReplaceConstruction, target.construction, params)
	if not ok or proposal == nil then
		say("probe rebuildSkipped variant=" .. target.variant .. " reason=noProposal error=" .. tostring(proposal))
		return nil
	end
	local sent, err = pcall(function() : string
		api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, false, false))
		return nil
	end)
	say("probe rebuildSent variant=" .. target.variant .. " construction=" .. tostring(target.construction)
		.. " depot=" .. tostring(target.depot) .. " value=" .. tostring(testValue) .. " sent=" .. tostring(sent)
		.. " error=" .. tostring(err))
	return nil
end

local start = function(state : GameScriptState<ProbeState>, probe : ProbeState, t : number) : string
	local depots = allDepots()
	local owned : {Engine.Entity : boolean} = {}
	local okOwned, list = pcall(api.engine.getEntitiesWithComponent, api.type.ComponentType.VEHICLE_DEPOT,
		{ requireOwnedByPlayer = api.engine.util.getPlayer() })
	if okOwned and type(list) == "table" then
		for _, entity in ipairs(list) do owned[entity] = true end
	end
	local candidates : {Candidate} = {}
	for _, depot in ipairs(depots) do
		local construction = constructionForDepot(depot)
		if owned[depot] and construction ~= nil then
			local okList, maintained = pcall(api.engine.system.transportVehicleSystem.getVehiclesForMaintenanceStation, depot)
			candidates[#candidates + 1] = { depot = depot, construction = construction,
				maintained = okList and type(maintained) == "table" and #maintained or 0 }
		end
	end
	table.sort(candidates, function(a : Candidate, b : Candidate) : boolean
		if a.maintained ~= b.maintained then return a.maintained > b.maintained end
		return a.depot < b.depot
	end)
	say("probe inventory depots=" .. tostring(#depots) .. " candidates=" .. tostring(#candidates) .. " t=" .. tostring(t))
	probe.targets = {}
	for i, variant in ipairs(variants) do
		local c = candidates[i]
		if c == nil then
			say("probe noTarget variant=" .. variant)
		else
			say("probe before variant=" .. variant .. " depot=" .. tostring(c.depot) .. " construction=" .. tostring(c.construction)
				.. " maintained=" .. tostring(c.maintained) .. " pool=" .. poolOf(c.depot) .. " " .. storedParams(c.construction))
			table.insert(probe.targets, { variant = variant, construction = c.construction, depot = c.depot })
		end
	end
	-- The state is saved before anything is sent: a failure must not repeat on every update.
	probe.phase = "sent"
	probe.sentAt = t
	probe.checksDone = 0
	probe.depotsBefore = depots
	state:set(probe)
	logFinance("before")
	-- Each step on its own guard: a failure in one must not stop the others.
	for _, target in ipairs(probe.targets) do
		local ok, err = pcall(sendRebuild, target)
		if not ok then say("probe rebuildError variant=" .. target.variant .. " error=" .. tostring(err)) end
	end
	for _, charge in ipairs({ { "construction", constructionCharge }, { "maintenance", maintenanceCharge } }) do
		local category, amount = charge[1] as string, charge[2] as integer
		local ok, err = pcall(bookCharge, category, amount)
		say("probe charge category=" .. category .. " amount=-" .. tostring(amount) .. " sent=" .. tostring(ok)
			.. " error=" .. tostring(err))
	end
	return nil
end

local check = function(probe : ProbeState, n : integer) : string
	say("probe check=" .. tostring(n) .. " t=" .. tostring(now()) .. " sinceSent=" .. tostring(now() - probe.sentAt))
	if n <= 2 then logFinance("check" .. tostring(n)) end
	for _, target in ipairs(probe.targets or {}) do
		say("probe after check=" .. tostring(n) .. " variant=" .. target.variant .. " construction=" .. tostring(target.construction)
			.. " depot=" .. tostring(target.depot) .. " depotExists=" .. tostring(exists(target.depot))
			.. " pool=" .. (exists(target.depot) and poolOf(target.depot) or "gone") .. " " .. storedParams(target.construction))
	end
	local before : {Engine.Entity : boolean} = {}
	for _, depot in ipairs(probe.depotsBefore or {}) do before[depot] = true end
	for _, depot in ipairs(allDepots()) do
		if not before[depot] then
			say("probe newDepot check=" .. tostring(n) .. " depot=" .. tostring(depot) .. " pool=" .. poolOf(depot) .. " "
				.. storedParams(constructionForDepot(depot)))
		end
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
