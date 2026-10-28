-- The building window of every wrapped depot and maintenance building (mod.script.tl names it as the construction's
-- entityWindowScript). It returns the base construction window with the depot's own tab, as the game would show it, plus a
-- Retrofit tab, the way the base Cleaning Plant adds its tab (game_mechanics/emission/pollution_cleanup_facility_hud.script.tl).
-- The Retrofit tab shows each tree's level, what the next level changes, and a button that buys it: the button sends a buy
-- event to the game script (retrofits.script.tl), which checks it, charges the price and rebuilds the building. Prices follow
-- levels.tl from the upkeep the game charges for the building now. Log lines start with "DEPOT_RETROFITS".

-- Shared with mod.script.tl, construction.script.tl and retrofits.script.tl; keep the copies equal.
local buyEventId = "DepotRetrofits"
local buyEvent = "depotRetrofitsBuy"

local maxShownLines = 60
local tabSortKey = 12500 -- after the depot's own tab (12000 in gui/entity_window/make_entity_window.tl)

local record TabState
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
	key : string -- every field above as text; the tab redraws when it changes
end

local type WindowFn = function(captureParams : any, entity : Engine.Entity, tag : string, gameCtx : GameContext,
	isMapEditor : boolean, isSandboxMode : boolean,
	setActionFnAndProxy : {function(actionFn? : (function() : TreeNodeId), key2? : string), any},
	entityRevisionCloseConditionAndProxy : ({(function() : boolean), any})) : ViewManager.MakeEntityWindowResult

local record RetrofitWindow
	entityWindowFn : WindowFn
end

local say = function(text : string)
	if log ~= nil then
		log.message("DEPOT_RETROFITS " .. text)
	else
		print("DEPOT_RETROFITS " .. text)
	end
end

-- Every load guarded: without one of these the window opens without the Retrofit tab, and the log says why.
local loadModule = function(path : string) : any
	local ok, result = pcall(ug_require, path)
	if not ok or result == nil then
		say("window loadFailed path=" .. path .. " error=" .. tostring(result))
		return nil
	end
	return result
end

local makeEntityWindow = loadModule("::/gui/entity_window/make_entity_window.tl") as ViewManager.MakeEntityWindowContentFn
local react = loadModule("::/gui/main/react.lua") as React
local builtin = loadModule("::/gui/main/builtin.lua") as Builtin
local engineReact = loadModule("::/gui/main/engine_react_util.tl") as EngineReactUtil
local contentCard = loadModule("::/gui/main/content_card.tl") as ContentCard
local levels = loadModule("depot_retrofits_1::/levels.tl") as DepotRetrofitsLevels
local progression = loadModule("::/game_mechanics/company/company_progression_util.tl") as CompanyProgressionUtil
local ready = react ~= nil and builtin ~= nil and engineReact ~= nil and contentCard ~= nil and levels ~= nil
say("window loaded ready=" .. tostring(ready) .. " constructionWindow=" .. tostring(makeEntityWindow ~= nil)
	.. " progression=" .. tostring(progression ~= nil))

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

local firstDepot = function(construction : Engine.Entity) : Engine.Entity
	local con = api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	return con and con.depots and con.depots[1] or nil
end

local readTab = function(construction : Engine.Entity) : TabState
	local depot = firstDepot(construction)
	local s : TabState = { depot = depot, construction = construction }
	local con = api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	s.levels = levels.read(con and constructionParams(con) or {})
	if progression ~= nil then
		local ok, company = pcall(progression.getCompanyProgressionState, api.engine.util.getPlayer())
		if ok and company ~= nil then s.rank, s.earnedRank = company.level, company.potentialLevel end
	end
	if depot ~= nil then
		local okUpkeep, charged = pcall(api.engine.util.maintenance.calcMaintenanceForSubconstruction, depot)
		s.chargedUpkeep = okUpkeep and tonumber(charged) or nil
		local vd = api.engine.getComponent(depot, api.type.ComponentType.VEHICLE_DEPOT) as Engine.Component.VehicleDepot
		s.pool = vd and vd.maintenancePool
		s.radius = vd and vd.catchmentArea and vd.catchmentArea.radius
		local okList, list = pcall(api.engine.system.transportVehicleSystem.getVehiclesForMaintenanceStation, depot)
		s.maintained = okList and type(list) == "table" and #list or nil
	end
	s.buildPrice = s.chargedUpkeep and levels.buildPrice(s.chargedUpkeep, s.levels) or nil
	local parts : {string} = {}
	for _, tree in ipairs(levels.trees) do parts[#parts + 1] = tostring(s.levels[tree]) end
	s.key = table.concat(parts, "/") .. " rank=" .. tostring(s.rank) .. "/" .. tostring(s.earnedRank)
		.. " upkeep=" .. tostring(s.chargedUpkeep) .. " pool=" .. tostring(s.pool) .. " radius=" .. tostring(s.radius)
		.. " maintained=" .. tostring(s.maintained)
	return s
end

local text = function(value : string, class? : string) : TreeNodeId
	return builtin.TextView{ meta = { class = class or "font-scale-body" }, text = value }
end

local withLevel = function(values : {string : integer}, tree : string, level : integer) : {string : integer}
	local result : {string : integer} = {}
	for _, t in ipairs(levels.trees) do result[t] = values[t] end
	result[tree] = level
	return result
end

-- What the tree's value is at a level, from what the building reads now.
local valueAt = function(s : TabState, tree : string, level : integer) : string
	local now = s.levels[tree]
	if tree == "radius" then
		if s.radius == nil then return "?" end
		return string.format("%d m", math.floor(levels.radius(s.radius / levels.radius(1, now), level) + 0.5))
	elseif tree == "vehicles" then
		local base = levels.basePool(s.pool, now)
		return base and tostring(levels.pool(base, level)) or "?"
	end
	local cut = level == 0 and "0%" or ("-" .. tostring(5 * level) .. "%")
	return tree == "upkeep" and (cut .. " of total") or cut
end

local logShown = function(s : TabState)
	if shownLines >= maxShownLines or shownKeys[tostring(s.construction) .. " " .. s.key] then return end
	shownKeys[tostring(s.construction) .. " " .. s.key] = true
	shownLines = shownLines + 1
	local prices : {string} = {}
	for _, tree in ipairs(levels.trees) do
		local level = s.levels[tree]
		prices[#prices + 1] = level < levels.maxLevel and s.buildPrice and tostring(levels.levelPrice(s.buildPrice, level + 1)) or "-"
	end
	say("window shown construction=" .. tostring(s.construction) .. " depot=" .. tostring(s.depot) .. " levels=" .. s.key
		.. " buildPrice=" .. tostring(s.buildPrice) .. " nextPrices=" .. table.concat(prices, "/"))
end

local buyButton = function(s : TabState, tree : string, waiting : ReactStateT<{string : integer}>) : TreeNodeId
	local level = s.levels[tree]
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
		label = "Level " .. tostring(nextLevel) .. "  " .. money(price)
		enabled = true
	end
	return builtin.Button{
		-- "primary" is the class the base game's dialog buttons use (gui/line_vehicle_mgmt/feedback_list_util.tl).
		meta = { class = "primary", enabled = enabled, localKey = "depot_retrofits_buy_" .. tree },
		content = text(label),
		onClick = function()
			if not enabled then return end
			say("window buy construction=" .. tostring(s.construction) .. " tree=" .. tree .. " from=" .. tostring(level)
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

-- A row with one item at the left edge and one at the right; the base windows push items apart with the
-- "horizontal-spacer" class (gui_react_util.makeHorizontalSpacer in gui/main/gui_react_util.tl).
local spreadRow = function(left : TreeNodeId, right : TreeNodeId) : TreeNodeId
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { left, builtin.Component{ meta = { class = "horizontal-spacer" } }, right },
	}
end

local card = function(title : string, rows : {TreeNodeId}, gameCtx : GameContext) : TreeNodeId
	return contentCard.ContentCard{
		title = title,
		initialCalloutTextPermanent = "",
		extraChildrenPermanent = {
			builtin.Component{ layout = builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = rows } },
		},
		gameCtx = gameCtx,
		showOnRightSide = false,
	}
end

-- One card per tree. First row: the level at the left, the value now and after the next level at the right. Second row:
-- the upkeep the next level brings at the left, the buy button at the right.
local treeCard = function(s : TabState, tree : string, waiting : ReactStateT<{string : integer}>, gameCtx : GameContext) : TreeNodeId
	local level = s.levels[tree]
	local levelText = text("Level " .. tostring(level) .. " / " .. tostring(levels.maxLevel), "font-scale-headline")
	if level >= levels.maxLevel then
		return card(levels.names[tree], {
			spreadRow(levelText, text(valueAt(s, tree, level))),
			spreadRow(text("Highest level", "font-scale-annotation"), builtin.Component{}),
		}, gameCtx)
	end
	local upkeepText = "Upkeep unknown"
	if s.chargedUpkeep ~= nil then
		local nextUpkeep = s.chargedUpkeep / levels.upkeepFactor(s.levels) * levels.upkeepFactor(withLevel(s.levels, tree, level + 1))
		upkeepText = "Upkeep " .. money(s.chargedUpkeep) .. " -> " .. money(nextUpkeep) .. " a year"
	end
	return card(levels.names[tree], {
		spreadRow(levelText, text(valueAt(s, tree, level) .. "  ->  " .. valueAt(s, tree, level + 1))),
		spreadRow(text(upkeepText, "font-scale-annotation"), buyButton(s, tree, waiting)),
	}, gameCtx)
end

local tabBody = function(s : TabState, waiting : ReactStateT<{string : integer}>, gameCtx : GameContext) : TreeNodeId
	local rank = tostring(s.rank or "?")
	local rankNote = (s.earnedRank and s.earnedRank ~= s.rank) and ("rank " .. tostring(s.earnedRank) .. " earned, claim it to buy higher") or ("levels up to " .. rank)
	local rows : {TreeNodeId} = {
		card("Retrofit", {
			spreadRow(text("Company rank " .. rank, "font-scale-headline"), text(rankNote, "font-scale-annotation")),
			spreadRow(text("Radius"), text(s.radius and string.format("%d m", math.floor(s.radius + 0.5)) or "?")),
			spreadRow(text("Vehicles"), text(tostring(s.maintained or "?") .. " / " .. tostring(s.pool or "?"))),
			spreadRow(text("Upkeep"), text(money(s.chargedUpkeep) .. " a year (" .. string.format("%.2f", levels.upkeepFactor(s.levels)) .. " x base)")),
			text("Buying a level rebuilds the building; the game then reassigns the vehicles it maintained.", "font-scale-annotation"),
		}, gameCtx),
	}
	for _, tree in ipairs(levels.trees) do rows[#rows + 1] = treeCard(s, tree, waiting, gameCtx) end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = rows }
end

local RetrofitTab : Recipe<IEntityWindowParam> = nil
if ready then
	RetrofitTab = react.RegisterRecipe("DepotRetrofitsTab", function(params : IEntityWindowParam) : TreeNodeId
		local construction = params.keyEntity
		local state = engineReact.useStepState(function() : TabState
			return readTab(construction)
		end, nil, function(a : TabState, b : TabState) : boolean
			return a ~= nil and b ~= nil and a.key == b.key
		end)
		local waiting = react.useState({}) as ReactStateT<{string : integer}>
		local s = state:old()
		local ok, body = pcall(function() : TreeNodeId
			logShown(s)
			return tabBody(s, waiting, params.gameCtx)
		end)
		if not ok then
			say("window error construction=" .. tostring(construction) .. " error=" .. tostring(body))
			body = text("Depot Retrofits: the levels could not be shown (see the game log).")
		end
		return body
	end)
end

local isPlayerOwned = function(entity : Engine.Entity) : boolean
	local owned = api.engine.getComponent(entity, api.type.ComponentType.PLAYER_OWNED) as Engine.Component.PlayerOwned
	return owned ~= nil and owned.player == api.engine.util.getPlayer()
end

local window : RetrofitWindow = {}

window.entityWindowFn = function(_captureParams : any, entity : Engine.Entity, tag : string, gameCtx : GameContext,
		isMapEditor : boolean, isSandboxMode : boolean,
		setActionFnAndProxy : {function(actionFn? : (function() : TreeNodeId), key2? : string), any},
		entityRevisionCloseConditionAndProxy : ({(function() : boolean), any})) : ViewManager.MakeEntityWindowResult
	if makeEntityWindow == nil then error("DEPOT_RETROFITS the base construction window could not be loaded") end
	local actionFnAndProxy = makeEntityWindow.makeSetActionFnWithCombinedKey(makeEntityWindow.ConstructionWindow, setActionFnAndProxy)
	local depot = firstDepot(entity)
	local okOwned, owned = pcall(isPlayerOwned, entity)
	local customTabs : {ConstructionWindowParam.ConData} = {}
	local show = ready and depot ~= nil and okOwned and owned
	if show then
		table.insert(customTabs, {
			entity = entity,
			name = "Retrofit",
			description = "Retrofit",
			subconstructionIndex = -1,
			sortKey = tabSortKey,
			customTabData = {
				recipe = RetrofitTab,
				param = {
					meta = { tag = tag .. "retrofit" },
					keyEntity = entity,
					gameCtx = gameCtx,
					isMapEditor = isMapEditor,
					isSandboxMode = isSandboxMode,
				} as IEntityWindowParam,
				autoCloseCondition = entityRevisionCloseConditionAndProxy[1],
				autoCloseCondition_compareProxy = entityRevisionCloseConditionAndProxy[2],
				fallbackTitle = "Retrofit",
			},
		})
	end
	-- The game calls this many times while one window opens (about 60 in the first second), so log each building once.
	local openKey = "open " .. tostring(entity) .. " " .. tostring(show)
	if shownLines < maxShownLines and not shownKeys[openKey] then
		shownKeys[openKey] = true
		shownLines = shownLines + 1
		say("window open construction=" .. tostring(entity) .. " depot=" .. tostring(depot) .. " retrofitTab=" .. tostring(show)
			.. " owned=" .. tostring(okOwned and owned))
	end
	return {
		recipe = makeEntityWindow.ConstructionWindow,
		param = {
			meta = { tag = tag .. "con" },
			keyEntity = entity,
			gameCtx = gameCtx,
			isMapEditor = isMapEditor,
			isSandboxMode = isSandboxMode,
			setActionFn = actionFnAndProxy.fn,
			setActionFn_compareProxy = actionFnAndProxy.proxy,
			customTabs = customTabs,
			initialSubconstruction = depot,
		} as ConstructionWindowParam,
		fallbackTitle = "Depot",
		replacedEntity = entity,
		autoCloseCondition = entityRevisionCloseConditionAndProxy[1],
		autoCloseCondition_compareProxy = entityRevisionCloseConditionAndProxy[2],
	}
end

return window
