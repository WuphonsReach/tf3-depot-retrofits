-- The building window of every wrapped depot and maintenance building (mod.script.tl names it as the construction's
-- entityWindowScript). It returns the base construction window with the depot's own tab, as the game would show it, plus a
-- Retrofit tab, the way the base Cleaning Plant adds its tab (game_mechanics/emission/pollution_cleanup_facility_hud.script.tl).
-- The Retrofit tab shows each tree's level, what the next level changes, and a button that buys it: the button sends a buy
-- event to the game script (retrofits.script.tl), which checks it, charges the price and rebuilds the building. Prices follow
-- levels.tl from the upkeep the game charges for the building now. Log lines start with "DEPOT_RETROFITS".

local buyEventId = "DepotRetrofits"
-- Copied in retrofits.script.tl; keep the copies equal.
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
	accumulated : number -- the MAINTENANCE_COST accumulated costs, which the game's upkeep footer adds to the upkeep
	scriptUpkeep : number -- the MAINTENANCE_COST upkeep, the update script's value with the levels applied
	upkeepScale : number -- what the footer multiplies scriptUpkeep by
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
-- Optional: without it the tab has no scroll container and no upkeep footer.
local entityWindowUtil = loadModule("::/gui/entity_window/entity_window_util.tl") as EntityWindowUtil
-- Optional: without it each card shows its level as text instead of a row of marks.
local styleutil = loadModule("::/gui/main/styleutil.tl") as StyleUtil
local ready = react ~= nil and builtin ~= nil and engineReact ~= nil and contentCard ~= nil and levels ~= nil
say("window loaded ready=" .. tostring(ready) .. " constructionWindow=" .. tostring(makeEntityWindow ~= nil)
	.. " progression=" .. tostring(progression ~= nil) .. " entityWindowUtil=" .. tostring(entityWindowUtil ~= nil)
	.. " styleutil=" .. tostring(styleutil ~= nil))

-- Stock icons: the upkeep symbol of the game's own upkeep footer (gui/entity_window/entity_window_util.tl, MaintenanceBar), the
-- shopping cart of the vehicle store's buy button (gui/line_vehicle_mgmt/vehicle_store_window.tl), and in front of each
-- tree's level the symbol of what it changes: the depot tab's pool-usage tools (entity_window_util.tl), the vehicle window's
-- pollution and noise (gui/entity_window/vehicle/vehicle.tl) and the upkeep symbol. The game has no radius icon; the line
-- manager's standard-priority dot stands in for the circle the game draws on the map.
local upkeepIcon = "::/gui/entity_window/icons/symbol_dollar_gear.tga"
local buyIcon = "::/gui/line_vehicle_mgmt/icons/symbol_shopping_cart.tga"
local treeIcons : {string : string} = {
	radius = "::/gui/entity_window/icons/prio_standard.tga",
	vehicles = "::/gui/entity_window/icons/symbol_tools.tga",
	pollution = "::/gui/entity_window/icons/symbol_pollution.tga",
	noise = "::/gui/entity_window/icons/symbol_noise.tga",
	upkeep = upkeepIcon,
}

-- The level row: one box per level, drawn as the map layers draw their legend swatches (gui/layers/layer_terrain.tl). White for
-- a level bought and grey for one the company rank allows (the game's NeutralLightest and NeutralMedium,
-- gui/main/default_colors.gres.lua); above the rank a grey just lighter than the card (#282f36), so those boxes recede.
local boxColors : {string : {number}} = {
	bought = { 1, 1, 1, 1 },
	open = { 0.502, 0.502, 0.502, 1 },
	locked = { 0.251, 0.251, 0.251, 1 },
}
local drawnStyles : {string : StyleSheet} = nil

local buyTooltip = "Buy the next level. The building is rebuilt, and the game reassigns its vehicles."
-- On the line with the percentages: the map shows a level as a few decibels, averaged over minutes, so it barely moves
-- (docs/design/findings.md). Kept within the base game's longest tooltips, about 130 characters; tooltips wrap at 800 px.
local effectTooltips : {string : string} = {
	pollution = "Cuts the building's own pollution; vehicles keep theirs. The map catches up over minutes; level 15 is about 3 of its 12 steps.",
	noise = "Cuts the building's own noise; vehicles keep theirs. The map catches up over minutes; level 15 is about 3 of its 12 steps.",
}

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

-- The factor the game's upkeep footer multiplies a construction's upkeep by (MaintenanceBar in
-- gui/entity_window/entity_window_util.tl): the base config's infrastructureMaintenanceScale, times the year's cost multiplier
-- for a construction whose costs follow the years. The tab reads it on every step, so the parts that do not change within a
-- year are kept: the scale, whether each construction file follows the years, and each year's multiplier.
local maintenanceScale : number = nil
local followsYears : {string : boolean} = {}
local yearMultipliers : {integer : number} = {}
local footerScale = function(con : Engine.Component.Construction) : number
	local baseConfig : BaseConfig = nil
	if maintenanceScale == nil then
		baseConfig = api.res.getBaseConfig()
		maintenanceScale = baseConfig.costs["infrastructureMaintenanceScale"] or 1
	end
	local follows = followsYears[con.fileName]
	if follows == nil then
		local desc = api.res.constructionRep.get(api.res.constructionRep.find(con.fileName))
		follows = desc ~= nil and desc.costsYearProgression == true
		followsYears[con.fileName] = follows
	end
	if not follows then return maintenanceScale end
	local gameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	local year = api.engine.util.getCalendarDate(gameTime.gameTime).year
	local multiplier = yearMultipliers[year]
	if multiplier == nil then
		baseConfig = baseConfig or api.res.getBaseConfig()
		multiplier = api.engine.util.construction.getCostMultiplierForYear(baseConfig.treeCostYearMultipliers, year)
		yearMultipliers[year] = multiplier
	end
	return maintenanceScale * multiplier
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
	-- The accumulated costs summed the way the footer sums them (each entry rounded), 0 when unreadable; and the upkeep.
	local okCost, accumulated, scriptUpkeep = pcall(function() : number, number
		local cost = api.engine.getComponent(construction, api.type.ComponentType.MAINTENANCE_COST) as Engine.Component.MaintenanceCost
		local sum = 0
		if cost ~= nil and cost.accumulatedCost ~= nil then
			for _, value in pairs(cost.accumulatedCost) do sum = sum + math.floor(value + 0.5) end
		end
		return sum, cost and cost.maintenanceCost or nil
	end)
	s.accumulated = okCost and accumulated or 0
	s.scriptUpkeep = okCost and scriptUpkeep or nil
	local okScale, scale = pcall(footerScale, con)
	s.upkeepScale = con ~= nil and okScale and scale or nil
	s.buildPrice = s.chargedUpkeep and levels.buildPrice(s.chargedUpkeep, s.levels) or nil
	s.key = levels.describe(s.levels) .. " rank=" .. tostring(s.rank) .. "/" .. tostring(s.earnedRank)
		.. " upkeep=" .. tostring(s.chargedUpkeep) .. " pool=" .. tostring(s.pool) .. " radius=" .. tostring(s.radius)
		.. " maintained=" .. tostring(s.maintained) .. " accumulated=" .. tostring(s.accumulated)
		.. " upkeepScript=" .. tostring(s.scriptUpkeep) .. " upkeepScale=" .. tostring(s.upkeepScale)
	return s
end

-- One text size everywhere in the tab, for now.
local text = function(value : string, tooltip? : string) : TreeNodeId
	return builtin.TextView{ meta = { class = "font-scale-body", tooltip = tooltip }, text = value }
end

-- 20 x 20, the size of the footer's upkeep icon ("text-icon-size-hack" in gui/main/default.css.lua).
local icon = function(path : string, tooltip? : string) : TreeNodeId
	return builtin.ImageView{
		meta = { class = "text-icon-size-hack", tooltip = tooltip },
		path = path,
		scaling = builtin.type.ImageViewScaling.AutoFit,
	}
end

local iconText = function(path : string, value : string, tooltip? : string) : TreeNodeId
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = { icon(path, tooltip), text(value) } }
end

-- The sized pieces the tab draws (the level boxes, the gaps between them, the height of a summary row, the gap between a tree
-- card's rows), built once on the first
-- draw. An empty table after a failure, so a failure is logged once and the tab falls back to text and default spacing.
local getDrawnStyles = function() : {string : StyleSheet}
	if drawnStyles == nil and styleutil ~= nil then
		local ok, styles = pcall(function() : {string : StyleSheet}
			local result : {string : StyleSheet} = {
				gap = styleutil.makeStyle{ size = { 3, 16 } },
				rowHeight = styleutil.makeStyle{ size = { 0, 24 } },
				rowGap = styleutil.makeStyle{ size = { 0, 6 } },
			}
			for state, color in pairs(boxColors) do
				result[state] = styleutil.makeStyle{ backgroundColor = color, size = { 9, 16 } }
			end
			return result
		end)
		if not ok then say("window drawnStylesFailed error=" .. tostring(styles)) end
		drawnStyles = ok and styles or {}
	end
	return drawnStyles ~= nil and drawnStyles.gap ~= nil and drawnStyles or nil
end

-- The tree's symbol, then the boxes; the tooltip gives the level as a number.
local levelRow = function(s : TabState, tree : string) : TreeNodeId
	local level = s.levels[tree]
	-- The level over the highest the company rank allows now, "Level 4/7 (max 15)"; the 15 shows only while the rank is lower.
	local limit = s.rank ~= nil and math.min(s.rank, levels.maxLevel) or levels.maxLevel
	local label = "Level " .. tostring(level) .. "/" .. tostring(limit)
		.. (limit < levels.maxLevel and (" (max " .. tostring(levels.maxLevel) .. ")") or "")
	local styles = getDrawnStyles()
	if styles == nil then return iconText(treeIcons[tree], label) end
	local children : {TreeNodeId} = { icon(treeIcons[tree]) }
	for n = 1, levels.maxLevel do
		local style = n <= level and styles.bought or (s.rank ~= nil and n > s.rank) and styles.locked or styles.open
		children[#children + 1] = builtin.Component{ meta = { styleSheet = styles.gap } }
		children[#children + 1] = builtin.Component{ meta = { styleSheet = style } }
	end
	return builtin.Component{
		meta = { tooltip = label },
		layout = builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children },
	}
end

local perYear = function(amount : number) : string
	return money(amount) .. "/" .. _("Year")
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
	return level == 0 and "0%" or ("-" .. tostring(5 * level) .. "%")
end

-- What the next level changes, "400 m -> 420 m"; the upkeep tree cuts the total upkeep, the other trees' increases included.
local effect = function(s : TabState, tree : string, level : integer, nextLevel? : integer) : string
	local result = valueAt(s, tree, level)
	if nextLevel ~= nil then result = result .. " -> " .. valueAt(s, tree, nextLevel) end
	return tree == "upkeep" and (result .. " of total") or result
end

local logShown = function(s : TabState)
	-- The accumulated costs grow every second while vehicles are serviced; a change there alone is not logged.
	local logKey = tostring(s.construction) .. " " .. s.key:gsub(" accumulated=%S+", "")
	if shownLines >= maxShownLines or shownKeys[logKey] then return end
	shownKeys[logKey] = true
	shownLines = shownLines + 1
	local prices : {string} = {}
	for _, tree in ipairs(levels.trees) do
		local level = s.levels[tree]
		prices[#prices + 1] = level < levels.maxLevel and s.buildPrice and tostring(levels.levelPrice(s.buildPrice, tree, level + 1)) or "-"
	end
	say("window shown construction=" .. tostring(s.construction) .. " depot=" .. tostring(s.depot) .. " state=" .. s.key
		.. " buildPrice=" .. tostring(s.buildPrice) .. " nextPrices=" .. table.concat(prices, "/"))
end

-- The stock shopping cart and the price; the reason a level cannot be bought yet replaces the price, and the tooltip says more.
-- No "buying" state: the rebuild lands within a second, paused or not, and the tab redraws with the new level. A second click
-- before that sends the old level, which the game script refuses as stale, so nothing is charged twice.
local buyButton = function(s : TabState, tree : string) : TreeNodeId
	local level = s.levels[tree]
	local nextLevel = level + 1
	local label, tooltip : string, string
	local enabled = false
	local price = s.buildPrice and levels.levelPrice(s.buildPrice, tree, nextLevel) or nil
	if price == nil then
		label, tooltip = "?", "Price unknown"
	elseif s.rank ~= nil and nextLevel > s.rank then
		label, tooltip = "Rank " .. tostring(nextLevel), "Needs company rank " .. tostring(nextLevel)
	else
		label, tooltip = money(price), buyTooltip
		enabled = true
	end
	return builtin.Button{
		-- "primary" is the class the base game's dialog buttons use (gui/line_vehicle_mgmt/feedback_list_util.tl); its disabled
		-- style greys the icon and the text (gui/main/default.css.lua).
		meta = { class = "primary", enabled = enabled, tooltip = tooltip, localKey = "depot_retrofits_buy_" .. tree },
		content = builtin.Component{ layout = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = { icon(buyIcon), text(label) },
		} },
		onClick = function()
			if not enabled then return end
			say("window buy construction=" .. tostring(s.construction) .. " tree=" .. tree .. " from=" .. tostring(level)
				.. " shownPrice=" .. tostring(price))
			api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", buyEventId, buyEvent,
				{ construction = s.construction, tree = tree, from = level }))
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

-- A summary row, as far apart as the tree cards' rows (24 pixels, set there by the icons and the buy buttons): an empty piece
-- of that height at the left edge holds the row open.
local summaryRow = function(left : string, right : string) : TreeNodeId
	local styles = getDrawnStyles()
	if styles == nil then return spreadRow(text(left), text(right)) end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Component{ meta = { styleSheet = styles.rowHeight } },
			text(left),
			builtin.Component{ meta = { class = "horizontal-spacer" } },
			text(right),
		},
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

-- One card per tree. First row: the level row at the left, the upkeep after the next level at the right.
-- Second row: what the next level changes at the left, the buy button at the right. The upkeep counts what the game's upkeep
-- footer counts.
-- The upkeep the game will charge at other levels, rounded as the footer rounds it: the update script's upkeep at those levels
-- (construction.script.tl rounds it to whole dollars) times the footer's scale. That upkeep is worked out the wrapper's way,
-- from the whole-dollar upkeep before the levels: scaling the stored upkeep by the ratio of the factors carries its rounding
-- along and was off by $1 before the scale. calcMaintenanceForSubconstruction drops the half dollar the footer rounds up
-- (101,562 for 101,562.50), so it is only the fallback.
local upkeepAfter = function(s : TabState, values : {string : integer}) : number
	if s.scriptUpkeep ~= nil and s.upkeepScale ~= nil then
		local base = levels.baseUpkeep(s.scriptUpkeep, s.levels)
		local scriptUpkeep = base ~= nil and levels.levelledUpkeep(base, values)
			or math.floor(s.scriptUpkeep / levels.upkeepFactor(s.levels) * levels.upkeepFactor(values) + 0.5)
		return math.floor(scriptUpkeep * s.upkeepScale + 0.5)
	elseif s.chargedUpkeep ~= nil then
		return s.chargedUpkeep / levels.upkeepFactor(s.levels) * levels.upkeepFactor(values)
	end
	return nil
end

-- A tree card's two rows, 6 pixels apart so the upkeep figure does not touch the buy button below it.
local twoRows = function(first : TreeNodeId, second : TreeNodeId) : {TreeNodeId}
	local styles = getDrawnStyles()
	if styles == nil then return { first, second } end
	return { first, builtin.Component{ meta = { styleSheet = styles.rowGap } }, second }
end

local treeCard = function(s : TabState, tree : string, gameCtx : GameContext) : TreeNodeId
	local level = s.levels[tree]
	local levelText = levelRow(s, tree)
	if level >= levels.maxLevel then
		return card(levels.names[tree], twoRows(
			spreadRow(levelText, text("Highest level")),
			spreadRow(text(effect(s, tree, level), effectTooltips[tree]), builtin.Component{})
		), gameCtx)
	end
	-- Build only the node that is shown: a recipe called but left out of the tree costs the game log a "Preserved props"
	-- warning on every redraw.
	local nextUpkeep : TreeNodeId
	local charged = upkeepAfter(s, levels.withLevel(s.levels, tree, level + 1))
	if charged ~= nil then
		nextUpkeep = iconText(upkeepIcon, perYear(charged + s.accumulated), "Upkeep after level " .. tostring(level + 1))
	else
		nextUpkeep = text("?")
	end
	return card(levels.names[tree], twoRows(
		spreadRow(levelText, nextUpkeep),
		spreadRow(text(effect(s, tree, level, level + 1), effectTooltips[tree]), buyButton(s, tree))
	), gameCtx)
end

-- The cards scroll and the game's own upkeep footer sits below them, as in the depot's tab
-- (gui/entity_window/maintenance_station/maintenance_station.tl).
local tabBody = function(s : TabState, gameCtx : GameContext) : TreeNodeId
	local rankNote = (s.earnedRank and s.rank and s.earnedRank > s.rank)
		and ("Rank " .. tostring(s.earnedRank) .. " earned: claim it to buy higher levels") or ""
	local cards : {TreeNodeId} = {
		card("Summary", {
			summaryRow("Company rank " .. tostring(s.rank or "?"), rankNote),
			summaryRow("Radius", s.radius and string.format("%d m", math.floor(s.radius + 0.5)) or "?"),
			summaryRow("Vehicles", tostring(s.maintained or "?") .. "/" .. tostring(s.pool or "?")),
		}, gameCtx),
	}
	for _, tree in ipairs(levels.trees) do cards[#cards + 1] = treeCard(s, tree, gameCtx) end
	if entityWindowUtil == nil then
		return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = cards }
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			entityWindowUtil.ContentWidgetScrollContainer(cards, true),
			entityWindowUtil.MaintenanceBar{
				entity = s.construction,
				maintenancePeriodText = _("Year"),
				initialCalloutText = "",
				gameCtx = gameCtx,
				showOnRightSide = false,
			},
		},
	}
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
		local s = state:old()
		local ok, body = pcall(function() : TreeNodeId
			logShown(s)
			return tabBody(s, params.gameCtx)
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
