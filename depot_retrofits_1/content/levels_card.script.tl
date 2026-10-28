-- The levels card in the depot and maintenance building window. Every vehicle depot (depots and maintenance buildings alike)
-- opens the base game's maintenance station window, which shows the cards registered for its extension point
-- (gui/entity_window/maintenance_station/maintenance_station_eow.script.tl in gui.zip); gui/depot_retrofits_levels.res.lua
-- registers this one. It shows the company rank and each tree's level, with a button that buys the next level: the button
-- sends a buy event to the game script (probe.script.tl), which checks it, charges the price and rebuilds the building.
-- Prices follow levels.tl from the upkeep the game charges for the building now. Log lines start with "DEPOT_RETROFITS".

-- Shared with mod.script.tl, construction.script.tl and probe.script.tl; keep the copies equal.
local wrapperRef = "depot_retrofits_1::/construction.script@update"
local buyEventId = "DepotRetrofits"
local buyEvent = "depotRetrofitsBuy"

local maxShownLines = 60

local record CardState
	construction : Engine.Entity
	depot : Engine.Entity
	levels : {string : integer}
	rank : integer
	earnedRank : integer
	chargedUpkeep : number
	buildPrice : number
	pool : number
	radius : number
	maintained : integer
	key : string -- every field above as text; the card redraws when it changes
end

local record LevelsCard
	LevelsPlugin : Recipe<MaintenanceStationEow.MaintenanceStationWidgetPluginParams>
	condition : function(MaintenanceStationEow.MaintenanceStationWidgetPluginParams) : boolean
end

local say = function(text : string)
	if log ~= nil then
		log.message("DEPOT_RETROFITS " .. text)
	else
		print("DEPOT_RETROFITS " .. text)
	end
end

-- Every load guarded: a module that does not resolve leaves the card out (condition false), never the window.
local loadModule = function(path : string) : any
	local ok, result = pcall(ug_require, path)
	if not ok or result == nil then
		say("card loadFailed path=" .. path .. " error=" .. tostring(result))
		return nil
	end
	return result
end

local react = loadModule("::/gui/main/react.lua") as React
local builtin = loadModule("::/gui/main/builtin.lua") as Builtin
local engineReact = loadModule("::/gui/main/engine_react_util.tl") as EngineReactUtil
local contentCard = loadModule("::/gui/main/content_card.tl") as ContentCard
local eow = loadModule("::/gui/entity_window/maintenance_station/maintenance_station_eow.script.tl") as MaintenanceStationEow
local levels = loadModule("depot_retrofits_1::/levels.tl") as DepotRetrofitsLevels
local progression = loadModule("::/game_mechanics/company/company_progression_util.tl") as CompanyProgressionUtil
local ready = react ~= nil and builtin ~= nil and engineReact ~= nil and contentCard ~= nil and eow ~= nil and levels ~= nil
say("card loaded ready=" .. tostring(ready) .. " progression=" .. tostring(progression ~= nil))

local shownLines = 0
local shownKeys : {string : boolean} = {}

local money = function(amount : number) : string
	if amount == nil then return "?" end
	local digits = tostring(math.floor(amount + 0.5))
	local sign = ""
	if digits:sub(1, 1) == "-" then sign, digits = "-", digits:sub(2) end
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return sign .. "$" .. grouped
end

local constructionParams = function(construction : Engine.Component.Construction) : {string:any}
	if construction.params_native ~= nil then
		local ok, asTable = pcall(construction.params_native.asTable, construction.params_native)
		if ok and asTable ~= nil then return asTable as {string:any} end
	end
	return (construction.params as table) as {string:any}
end

local readCard = function(depot : Engine.Entity, construction : Engine.Entity) : CardState
	local s : CardState = { depot = depot, construction = construction }
	local con = api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	s.levels = levels.read(con and constructionParams(con) or {})
	if progression ~= nil then
		local ok, company = pcall(progression.getCompanyProgressionState, api.engine.util.getPlayer())
		if ok and company ~= nil then s.rank, s.earnedRank = company.level, company.potentialLevel end
	end
	local okUpkeep, charged = pcall(api.engine.util.maintenance.calcMaintenanceForSubconstruction, depot)
	s.chargedUpkeep = okUpkeep and tonumber(charged) or nil
	s.buildPrice = s.chargedUpkeep and levels.buildPrice(s.chargedUpkeep, s.levels) or nil
	local vd = api.engine.getComponent(depot, api.type.ComponentType.VEHICLE_DEPOT) as Engine.Component.VehicleDepot
	s.pool = vd and vd.maintenancePool
	s.radius = vd and vd.catchmentArea and vd.catchmentArea.radius
	local okList, list = pcall(api.engine.system.transportVehicleSystem.getVehiclesForMaintenanceStation, depot)
	s.maintained = okList and type(list) == "table" and #list or nil
	local parts : {string} = {}
	for _, tree in ipairs(levels.trees) do parts[#parts + 1] = tostring(s.levels[tree]) end
	s.key = table.concat(parts, "/") .. " rank=" .. tostring(s.rank) .. "/" .. tostring(s.earnedRank)
		.. " upkeep=" .. tostring(s.chargedUpkeep) .. " pool=" .. tostring(s.pool) .. " radius=" .. tostring(s.radius)
		.. " maintained=" .. tostring(s.maintained)
	return s
end

local effectText = function(tree : string, level : integer) : string
	if level == 0 then return "no change" end
	local percent = tostring(5 * level) .. "%"
	if tree == "radius" then return "+" .. percent end
	if tree == "vehicles" then return "+" .. tostring(10 * level) .. "%, min +" .. tostring(level) end
	if tree == "upkeep" then return "-" .. percent .. " of total" end
	return "-" .. percent
end

local text = function(value : string, class? : string) : TreeNodeId
	return builtin.TextView{ meta = { class = class or "font-scale-body" }, text = value }
end

local logShown = function(s : CardState)
	if shownLines >= maxShownLines or shownKeys[tostring(s.construction) .. " " .. s.key] then return end
	shownKeys[tostring(s.construction) .. " " .. s.key] = true
	shownLines = shownLines + 1
	local prices : {string} = {}
	for _, tree in ipairs(levels.trees) do
		local level = s.levels[tree]
		prices[#prices + 1] = level < levels.maxLevel and s.buildPrice and tostring(levels.levelPrice(s.buildPrice, level + 1)) or "-"
	end
	say("card shown construction=" .. tostring(s.construction) .. " depot=" .. tostring(s.depot) .. " levels=" .. s.key
		.. " buildPrice=" .. tostring(s.buildPrice) .. " nextPrices=" .. table.concat(prices, "/"))
end

local buyButton = function(s : CardState, tree : string, waiting : ReactStateT<{string : integer}>) : TreeNodeId
	local level = s.levels[tree]
	if level >= levels.maxLevel then return text("Highest level") end
	local nextLevel = level + 1
	local label : string
	local enabled = false
	local price = s.buildPrice and levels.levelPrice(s.buildPrice, nextLevel) or nil
	if waiting:old()[tree] == level then
		label = "Buying level " .. tostring(nextLevel) .. "..."
	elseif price == nil then
		label = "Price unknown"
	elseif s.rank ~= nil and nextLevel > s.rank then
		label = "Needs rank " .. tostring(nextLevel)
	else
		label = "Level " .. tostring(nextLevel) .. ": " .. money(price)
		enabled = true
	end
	return builtin.Button{
		-- "primary" is the class the base game's dialog buttons use (gui/line_vehicle_mgmt/feedback_list_util.tl).
		meta = { class = "primary", enabled = enabled, localKey = "depot_retrofits_buy_" .. tree },
		content = text(label),
		onClick = function()
			if not enabled then return end
			say("card buy construction=" .. tostring(s.construction) .. " tree=" .. tree .. " from=" .. tostring(level)
				.. " shownPrice=" .. tostring(price))
			api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", buyEventId, buyEvent,
				{ construction = s.construction, tree = tree, from = level }))
			local marked : {string : integer} = {}
			for key, value in pairs(waiting:old()) do marked[key] = value end
			marked[tree] = level
			waiting:set(marked)
		end,
	}
end

local cardBody = function(s : CardState, waiting : ReactStateT<{string : integer}>) : TreeNodeId
	local rows : {TreeNodeId} = {}
	rows[#rows + 1] = text("Company rank " .. tostring(s.rank or "?") .. (s.earnedRank and s.earnedRank ~= s.rank
		and (" (rank " .. tostring(s.earnedRank) .. " earned, not yet claimed)") or "")
		.. ". A tree's highest level is the company rank.")
	for _, tree in ipairs(levels.trees) do
		rows[#rows + 1] = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				text(levels.names[tree] .. " " .. tostring(s.levels[tree]) .. "/" .. tostring(levels.maxLevel)
					.. (s.levels[tree] > 0 and (" (" .. effectText(tree, s.levels[tree]) .. ")") or "")),
				buyButton(s, tree, waiting),
			},
		}
	end
	rows[#rows + 1] = text("Now: radius " .. (s.radius and string.format("%d m", math.floor(s.radius + 0.5)) or "?")
		.. ", " .. tostring(s.maintained or "?") .. " of " .. tostring(s.pool or "?") .. " vehicles, upkeep "
		.. money(s.chargedUpkeep) .. " a year (" .. string.format("%.2f", levels.upkeepFactor(s.levels)) .. " x base).")
	rows[#rows + 1] = text("Buying a level rebuilds the building; the game then reassigns the vehicles it maintained.")
	return builtin.Component{
		layout = builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = rows },
	}
end

local card : LevelsCard = {}

-- The window's own state.constructionEntity is set only when entity_window_util.isConstructionModifiableEngine allows it
-- (maintenance_station.tl), and the card did not show in game for road depots and maintenance buildings, so the
-- construction is looked up from the depot here.
local constructionOf = function(depot : Engine.Entity) : Engine.Entity
	local ok, construction = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction, depot)
	if ok and construction ~= nil and construction >= 0 then return construction end
	return nil
end

local maxConditionLines = 40
local conditionLines = 0

function card.condition(params : MaintenanceStationEow.MaintenanceStationWidgetPluginParams) : boolean
	local construction = ready and constructionOf(params.entityId) or nil
	local result, reason = false, "ok"
	if not ready then
		reason = "notReady"
	elseif params.ownershipState ~= "Player" then
		reason = "owner=" .. tostring(params.ownershipState)
	elseif construction == nil then
		reason = "noConstruction"
	else
		local ok, wrapped = pcall(function() : boolean
			local con = api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
			return con ~= nil and api.res.constructionRep.findAndGet(con.fileName).updateScript.fileName == wrapperRef
		end)
		result = ok and wrapped == true
		if not ok then reason = "error " .. tostring(wrapped) elseif not wrapped then reason = "notWrapped" end
	end
	if conditionLines < maxConditionLines then
		conditionLines = conditionLines + 1
		say("card condition depot=" .. tostring(params.entityId) .. " construction=" .. tostring(construction)
			.. " show=" .. tostring(result) .. " reason=" .. reason)
	end
	return result
end

if ready then
	card.LevelsPlugin = react.RegisterPluginRecipe(eow.MaintenanceStationEowExtensionPoint, "DepotRetrofitsLevelsPlugin",
		function(params : MaintenanceStationEow.MaintenanceStationWidgetPluginParams) : TreeNodeId
			local depot = params.entityId
			local construction = constructionOf(depot)
			local state = engineReact.useStepState(function() : CardState
				return readCard(depot, construction)
			end, nil, function(a : CardState, b : CardState) : boolean
				return a ~= nil and b ~= nil and a.key == b.key
			end)
			local waiting = react.useState({}) as ReactStateT<{string : integer}>
			local s = state:old()
			local ok, body = pcall(function() : TreeNodeId
				logShown(s)
				return cardBody(s, waiting)
			end)
			if not ok then
				say("card error construction=" .. tostring(construction) .. " error=" .. tostring(body))
				body = text("Depot Retrofits: the levels could not be shown (see the game log).")
			end
			return builtin.BoxLayout{
				child = contentCard.ContentCard{
					title = "Retrofit",
					initialCalloutTextPermanent = "",
					extraChildrenPermanent = { body },
					gameCtx = params.gameCtx,
					showOnRightSide = params.showCalloutOnRightSide,
				},
			}
		end)
end

return card
