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
	rank : integer -- nil when unknown: then no level can be bought
	earnedRank : integer
	rankSource : string
	chargedUpkeep : number
	buildPrice : number
	affordable : {string : boolean} -- per tree, whether the balance covers the next level; nil when unreadable
	pool : number
	radius : number
	maintained : integer
	accumulated : number -- the MAINTENANCE_COST accumulated costs, which the game's upkeep footer adds to the upkeep
	scriptUpkeep : number -- the MAINTENANCE_COST upkeep, the update script's value with the levels applied
	upkeepScale : number -- what the footer multiplies scriptUpkeep by
	refused : boolean -- true when the game did not rebuild the building for its last buy (see readRefused); nil otherwise
	blocked : boolean -- true when the proposal viewer says the game would refuse the rebuild; nil when clear or not answered
	viewer : boolean -- whether the proposal viewer is wanted in the action area now
	recheck : integer -- while blocked, which 2-second period it is: a new one places a new viewer; nil otherwise
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

-- settings.tl's logLevel: "full" adds the shown, open and buy lines. Guarded: without the file the log stays at "summary".
local settingsLoaded, settingsModule = pcall(ug_require, "depot_retrofits_1::/settings.tl")
local logFull = settingsLoaded and type(settingsModule) == "table" and (settingsModule as {string:any}).logLevel == "full"

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
-- Without it the rank is unknown and every buy button is greyed out, as the game script refuses every buy then.
local companyRank = loadModule("depot_retrofits_1::/company_rank.tl") as DepotRetrofitsRank
-- Optional: without it the tab has no scroll container and no upkeep footer.
local entityWindowUtil = loadModule("::/gui/entity_window/entity_window_util.tl") as EntityWindowUtil
-- Optional: without it each card shows its level as text instead of a row of marks.
local styleutil = loadModule("::/gui/main/styleutil.tl") as StyleUtil
local ready = react ~= nil and builtin ~= nil and engineReact ~= nil and contentCard ~= nil and levels ~= nil
say("window loaded ready=" .. tostring(ready) .. " constructionWindow=" .. tostring(makeEntityWindow ~= nil)
	.. " companyRank=" .. tostring(companyRank ~= nil) .. " entityWindowUtil=" .. tostring(entityWindowUtil ~= nil)
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
-- (docs/design/findings.md). A plain tooltip does not wrap (in game it ran as one line the width of the window), so the
-- lines are broken by hand, as the base game does, one sentence a line.
local effectTooltips : {string : string} = {
	pollution = "The pollution overlay map uses a decibel scale and averages over a few minutes of play.\n"
		.. "At the full 75% reduction in pollution, the pollution map will show a reduction of only 2-3 steps.\n"
		.. "Vehicle pollution is not affected and will still increase the pollution in the area.",
	noise = "The noise overlay map uses a decibel scale and averages over a few minutes of play.\n"
		.. "At the full 75% reduction in noise, the noise map will show a reduction of only 2-3 steps.\n"
		.. "Vehicle noise is not affected and will still increase the noise in the area.",
}

local shownLines = 0
local shownKeys : {string : boolean} = {}
-- The open lines have their own cap, so a long buying session cannot hide why a window left out the Retrofit tab.
local maxOpenLines = 60
local openLines = 0

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

-- The construction's depot. Maintenance buildings in a save begun on a pre-release build list none in `depots` (all 13
-- seen in the mod.io save "333", road, rail and water, built 1904 to 1998; its depots list theirs), so the fallback is the
-- first subconstruction with a vehicle depot, which is how the base construction window finds its tabs
-- (gui/entity_window/make_entity_window.tl). The same function is in retrofits.script.tl: keep the copies equal.
local firstDepot = function(construction : Engine.Entity) : Engine.Entity
	local con = api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	if con == nil then return nil end
	if con.depots and con.depots[1] then return con.depots[1] end
	for _, sub in ipairs(con.subconstructions or {}) do
		if api.engine.getComponent(sub, api.type.ComponentType.VEHICLE_DEPOT) ~= nil then return sub end
	end
	return nil
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

-- Whether the game would build the rebuild is asked of the game's own proposal viewer (the Verdict below). When it has not
-- answered, or answered clear and the game refuses anyway, the buy is simply tried: the click sends the buy and the tab
-- remembers the levels it showed. When they have not changed a few seconds later, the game did not rebuild the building
-- (nothing is charged then), and the tab says so until a rebuild lands. The game script gives up waiting a little sooner
-- (retrofits.script.tl), so a buy sent again is not refused as pending. Kept per building for the session, so the warning is
-- still there when the window is opened again.
-- The proposal viewer's last answer for the tab's building: clear when the game would build the rebuild with the levels shown.
-- Kept per open tab, so each opening asks afresh.
local record Verdict
	levels : string
	clear : boolean
	reason : string
end

local record Try
	levels : string -- levels.describe of the levels the tab showed at the click
	at : number -- clockNow() at the click
end
local tries : {Engine.Entity : Try} = {}
-- Each open tab's way to its action area, so a click can take the viewer away before the rebuild lands.
local record ActionArea
	setActionFn : function(actionFn? : (function() : TreeNodeId), key2? : string)
	placedRef : ReactRefT<string>
end
local actionAreas : {Engine.Entity : ActionArea} = {}
local refused : {Engine.Entity : string} = {} -- the levels when the rebuild was found refused; cleared once they change
local blockedRecheckSeconds = 2
local blockedRecheckSteps = 120
local refusedAfterSeconds = 4
local refusedAfterSteps = 240
local stepCount = 0
-- Real time in whole seconds. Not os.clock: that is the process's processor time, summed over the game's threads, and ran
-- about 5 times faster than real time in game. The tab's step count where os.time is not available.
local clockNow = function() : number, boolean
	local ok, seconds = pcall(os.time)
	if ok and type(seconds) == "number" then return seconds, true end
	return stepCount, false
end

-- Whether the building's last buy was refused by the game: the levels did not change within the wait after the click.
local readRefused = function(construction : Engine.Entity, current : string, verdictRef : ReactRefT<Verdict>) : boolean
	stepCount = stepCount + 1
	local try = tries[construction]
	if try ~= nil then
		local now, isClock = clockNow()
		if try.levels ~= current then
			tries[construction] = nil
			-- The game has just rebuilt it, so it needs no asking: the viewer stays away and the next click shows no flicker.
			if verdictRef ~= nil then verdictRef:set({ levels = current, clear = true, reason = "landed" }) end
		elseif now - try.at >= (isClock and refusedAfterSeconds or refusedAfterSteps) then
			tries[construction] = nil
			refused[construction] = current
			-- Ask the viewer again, so what is in the way shows in red.
			if verdictRef ~= nil then verdictRef:set(nil) end
			say("window notRebuilt construction=" .. tostring(construction) .. " levels=" .. current
				.. " waited=" .. tostring(now - try.at) .. " clock=" .. tostring(isClock))
		end
	end
	if refused[construction] ~= nil and refused[construction] ~= current then refused[construction] = nil end
	return refused[construction] ~= nil
end

local readTab = function(construction : Engine.Entity, verdictRef : ReactRefT<Verdict>) : TabState
	local depot = firstDepot(construction)
	local s : TabState = { depot = depot, construction = construction }
	local con = api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	s.levels = levels.read(con and constructionParams(con) or {})
	local current = levels.describe(s.levels)
	local okRefused, wasRefused = pcall(readRefused, construction, current, verdictRef)
	s.refused = okRefused and wasRefused or nil
	local verdict = verdictRef ~= nil and verdictRef:get() or nil
	if verdict ~= nil and verdict.levels ~= current then verdict = nil end
	s.blocked = verdict ~= nil and verdict.clear == false or nil
	-- The viewer is placed while its answer is wanted: not yet given, or blocked. Never while a buy is on its way: once the
	-- rebuild lands, a viewer still holding the old proposal flashes the building red ("Construction Not Possible").
	s.viewer = tries[construction] == nil and (verdict == nil or verdict.clear == false)
	-- A viewer answers once: with the house next door bulldozed it still said blocked, paused and running, until the window
	-- was opened again (docs/design/findings.md). So while blocked a new one is placed every 2 seconds, paused or not.
	if s.blocked then
		local now, isClock = clockNow()
		s.recheck = math.floor(now / (isClock and blockedRecheckSeconds or blockedRecheckSteps))
	end
	if companyRank ~= nil then
		s.rank, s.earnedRank, s.rankSource = companyRank.read(api.engine.util.getPlayer())
	else
		s.rankSource = "unknown moduleUnavailable"
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
	-- Kept as one yes/no per tree, not the balance itself, so the tab redraws only when one of them changes.
	local okBalance, balance = pcall(api.engine.util.finance.getPlayersBalance, api.engine.util.getPlayer())
	local afford = "?"
	if okBalance and tonumber(balance) ~= nil and s.buildPrice ~= nil then
		s.affordable = {}
		local marks : {string} = {}
		for _, tree in ipairs(levels.trees) do
			local level = s.levels[tree]
			s.affordable[tree] = level >= levels.maxLevel or tonumber(balance) >= levels.levelPrice(s.buildPrice, tree, level + 1)
			marks[#marks + 1] = s.affordable[tree] and "y" or "n"
		end
		afford = table.concat(marks)
	end
	s.key = levels.describe(s.levels) .. " rank=" .. tostring(s.rank) .. "/" .. tostring(s.earnedRank)
		.. " rankSource=" .. tostring(s.rankSource) .. " affordable=" .. afford
		.. " upkeep=" .. tostring(s.chargedUpkeep) .. " pool=" .. tostring(s.pool) .. " radius=" .. tostring(s.radius)
		.. " maintained=" .. tostring(s.maintained) .. " accumulated=" .. tostring(s.accumulated)
		.. " upkeepScript=" .. tostring(s.scriptUpkeep) .. " upkeepScale=" .. tostring(s.upkeepScale)
		.. " refused=" .. tostring(s.refused) .. " blocked=" .. tostring(s.blocked) .. " viewer=" .. tostring(s.viewer) .. " recheck=" .. tostring(s.recheck)
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

-- The "Blocked" and "Not rebuilt" banners, drawn as the yellow caution cards at the top of the town and line windows
-- (entity_window_util.NotificationWidget in gui/entity_window/entity_window_util.tl): the card surface tinted with the
-- caution colour at the game's high transparency, the icon on a solid caution tile (the colours and sizes are in
-- game_mechanics/notifications/gui/notifications.css.lua; Caution is #FFC40C, gui/main/color_internal.lua). That CSS
-- matches the base recipe's name, so the banner sets the same values inline; the outline class is not tied to a recipe.
-- Built once on the first draw, apart from the drawn styles, so a failure here leaves the level boxes alone; an empty table
-- after a failure, and the banner falls back to plain lines.
local bannerStyles : {string : StyleSheet} = nil
local caution = { 1, 0.769, 0.047 }
local bannerIcon = "::/game_mechanics/notifications/gui/icons/building_industry_bulldozer.tga"
local blockedLines = {
	"Blocked: what is shown in red is in the way.",
	"Pause and clear it; reconnect roads afterwards.",
	"The buy buttons come back once the way is clear.",
}
local refusedLines = {
	"Not rebuilt: a building or a road is in the way.",
	"Nothing was charged. Pause, clear it and buy again.",
	"A road can be cut off and reconnected afterwards.",
}

local getBannerStyles = function() : {string : StyleSheet}
	if bannerStyles == nil and styleutil ~= nil then
		local ok, styles = pcall(function() : {string : StyleSheet}
			local ninePatch = function(fileName : string) : NinePatch
				local patch = api.gui.NinePatch.new()
				patch.fileName = fileName
				patch.horizontal = { 0, 6, 26, 32 }
				patch.vertical = { 0, 6, 26, 32 }
				return patch
			end
			local card = styleutil.makeStyle{
				backgroundImage1 = ninePatch("::/gui/entity_window/design/card_surface.tga"),
				backgroundColor1 = { caution[1], caution[2], caution[3], 0.25 },
			}
			card.padding = api.type.Vec4f.new(8, 10, 8, 10)
			local tile = styleutil.makeStyle{
				backgroundImage1 = ninePatch("::/game_mechanics/notifications/gui/design/notification_surface.tga"),
				backgroundColor1 = { caution[1], caution[2], caution[3], 1 },
				color = { 1, 1, 1, 1 },
				size = { 32, 32 },
			}
			tile.padding = api.type.Vec4f.new(4, 4, 4, 4)
			return {
				card = card,
				tile = tile,
				iconGap = styleutil.makeStyle{ size = { 10, 0 } },
				below = styleutil.makeStyle{ size = { 0, 8 } },
			}
		end)
		if not ok then say("window bannerStylesFailed error=" .. tostring(styles)) end
		bannerStyles = ok and styles or {}
	end
	return bannerStyles ~= nil and bannerStyles.card ~= nil and bannerStyles or nil
end

-- Above the scrolling cards, so it shows whatever the scroll. "Blocked" while the viewer says so (greyed buttons show no
-- tooltip, so the reason and the way out are here); "Not rebuilt" after a buy the game refused, until a rebuild lands.
local banner = function(bannerLines : {string}) : TreeNodeId
	local lines : {TreeNodeId} = {}
	for _, line in ipairs(bannerLines) do
		lines[#lines + 1] = builtin.TextView{ meta = { class = "font-scale-body" }, text = line, tooltipWhenClipped = line }
	end
	local styles = getBannerStyles()
	if styles == nil then
		return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = lines }
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.Component{
				meta = { class = "notification-entity-window-card-outline" },
				layout = builtin.BoxLayout{ children = {
					builtin.Component{
						meta = { styleSheet = styles.card },
						layout = builtin.BoxLayout{
							orientation = builtin.type.Orientation.Horizontal,
							children = {
								builtin.ImageView{
									meta = { styleSheet = styles.tile },
									path = bannerIcon,
									scaling = builtin.type.ImageViewScaling.AutoFit,
								},
								builtin.Component{ meta = { styleSheet = styles.iconGap } },
								builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = lines },
							},
						},
					},
				} },
			},
			builtin.Component{ meta = { styleSheet = styles.below } },
		},
	}
end

-- The tree's symbol, then the boxes; the tooltip gives the level as a number.
local levelRow = function(s : TabState, tree : string) : TreeNodeId
	local level = s.levels[tree]
	-- The level over the highest the company rank allows now, "Level 4/7 (max 15)"; the 15 shows only while the rank is lower.
	-- With the rank unknown, "Level 4/? (max 15)", and every level not bought is drawn as locked.
	local limit = s.rank ~= nil and math.min(s.rank, levels.maxLevel) or nil
	local label = "Level " .. tostring(level) .. "/" .. (limit and tostring(limit) or "?")
		.. ((limit == nil or limit < levels.maxLevel) and (" (max " .. tostring(levels.maxLevel) .. ")") or "")
	local styles = getDrawnStyles()
	if styles == nil then return iconText(treeIcons[tree], label) end
	local children : {TreeNodeId} = { icon(treeIcons[tree]) }
	for n = 1, levels.maxLevel do
		local style = n <= level and styles.bought or (s.rank == nil or n > s.rank) and styles.locked or styles.open
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
		return string.format("%d m", math.floor(levels.radius(levels.baseRadius(s.radius, now), level) + 0.5))
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
	if not logFull then return end
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

-- The stock shopping cart and the price; a rank too low (or unknown) replaces the price. Short of money the price stays and the
-- button is greyed out, as the game script refuses the buy.
-- The game shows no tooltip on a disabled button, so only an enabled button's tooltip is ever seen (docs/design/findings.md).
-- No "buying" state: the rebuild lands within a second, paused or not, and the tab redraws with the new level. A second click
-- before that sends the old level, which the game script refuses as stale, so nothing is charged twice. A rebuild the game
-- refuses shows as the yellow warning a few seconds later (readRefused); the buttons stay, so the buy can be sent again.
local buyButton = function(s : TabState, tree : string) : TreeNodeId
	local level = s.levels[tree]
	local nextLevel = level + 1
	local label, tooltip : string, string
	local enabled = false
	local price = s.buildPrice and levels.levelPrice(s.buildPrice, tree, nextLevel) or nil
	if price == nil then
		label, tooltip = "?", "Price unknown"
	elseif s.blocked then
		label, tooltip = "Blocked", "Something is in the way: the game cannot rebuild this building"
	elseif s.rank == nil then
		label, tooltip = "Rank ?", "The company rank could not be read, so no level can be bought (see the game log)"
	elseif nextLevel > s.rank then
		label, tooltip = "Rank " .. tostring(nextLevel), "Needs company rank " .. tostring(nextLevel)
	elseif s.affordable ~= nil and not s.affordable[tree] then
		label, tooltip = money(price), "Not enough money"
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
			local now = clockNow()
			tries[s.construction] = { levels = levels.describe(s.levels), at = now }
			local area = actionAreas[s.construction]
			if area ~= nil and area.placedRef:get() ~= "none" then
				area.placedRef:set("none")
				pcall(area.setActionFn, nil)
			end
			if logFull then
				say("window buy construction=" .. tostring(s.construction) .. " tree=" .. tree .. " from=" .. tostring(level)
					.. " shownPrice=" .. tostring(price))
			end
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
	local summary : {TreeNodeId} = {
		summaryRow("Company rank " .. tostring(s.rank or "?"), rankNote),
		summaryRow("Radius", s.radius and string.format("%d m", math.floor(s.radius + 0.5)) or "?"),
		summaryRow("Vehicles", tostring(s.maintained or "?") .. "/" .. tostring(s.pool or "?")),
	}
	local cards : {TreeNodeId} = { card("Summary", summary, gameCtx) }
	for _, tree in ipairs(levels.trees) do cards[#cards + 1] = treeCard(s, tree, gameCtx) end
	local children : {TreeNodeId} = {}
	if s.blocked then
		children[#children + 1] = banner(blockedLines)
	elseif s.refused then
		children[#children + 1] = banner(refusedLines)
	end
	if entityWindowUtil == nil then
		for _, node in ipairs(cards) do children[#children + 1] = node end
		return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
	end
	children[#children + 1] = entityWindowUtil.ContentWidgetScrollContainer(cards, true)
	children[#children + 1] = entityWindowUtil.MaintenanceBar{
		entity = s.construction,
		maintenancePeriodText = _("Year"),
		initialCalloutText = "",
		gameCtx = gameCtx,
		showOnRightSide = false,
	}
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
end

-- The game's own proposal viewer, as the base bridge and tunnel window uses it (gui/entity_window/bridge_and_tunnel.tl),
-- given the real rebuild (createProposalReplaceConstruction) with the levels unchanged. Its answer is the tab's Verdict: no
-- error messages means the game would build it, as the base windows judge it. It also shows what is in the way in red. It
-- agreed with the game on every building tested, where the stand-in check (rebuild_check.tl) did not (docs/design/findings.md).
-- It goes into the window's action area through setActionFn, inside an ActionDescriptor, as the bridge window places it:
-- among the tab's own widgets it stopped the game ("Assertion `!IsTransformWithContext(node.recipeId)'").
local record Viewer
	levels : string
	proposal : Proposal
	error : string
	id : integer -- in the viewer's proposalId, so a viewer placed again works out its answer afresh
end
local viewerLogged : {string : boolean} = {}
local viewersMade = 0

local describeProposalData = function(data : ProposalData) : string
	local errorState = data.errorState
	local entities : {string} = {}
	if data.collisionInfo ~= nil then
		for _, c in ipairs(data.collisionInfo.collisionEntities or {}) do entities[#entities + 1] = tostring(c.entity) end
	end
	return "critical=" .. tostring(errorState and errorState.critical)
		.. " messages=" .. table.concat(errorState and errorState.messages or {}, ";")
		.. " warnings=" .. table.concat(errorState and errorState.warnings or {}, ";")
		.. " collisionEntities=" .. table.concat(entities, ",") .. " costs=" .. tostring(data.costs)
end

local makeViewer = function(construction : Engine.Entity, current : string) : Viewer
	local con = api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	if con == nil then return { levels = current, error = "noConstruction" } end
	local ok, made = pcall(api.engine.util.proposal.createProposalReplaceConstruction, construction, constructionParams(con))
	viewersMade = viewersMade + 1
	local viewer : Viewer = { levels = current, proposal = ok and made or nil, error = (not ok or made == nil) and tostring(made) or nil,
		id = viewersMade }
	if logFull or viewer.error ~= nil then
		say("window viewer placed construction=" .. tostring(construction) .. " levels=" .. current
			.. " proposal=" .. tostring(viewer.proposal ~= nil) .. " error=" .. tostring(viewer.error))
	end
	return viewer
end

local viewerNode = function(construction : Engine.Entity, viewer : Viewer, verdictRef : ReactRefT<Verdict>) : TreeNodeId
	return builtin.ActionDescriptor{ horizontalPromptList = true, children = { builtin.ProposalViewer{
		proposal = viewer.proposal,
		onCreateProposalData = function(data : ProposalData, _proposal : Proposal)
			local messages = data.errorState and data.errorState.messages or {}
			local ok, line = pcall(describeProposalData, data)
			local reason = ok and line or ("describeError=" .. tostring(line))
			verdictRef:set({ levels = viewer.levels, clear = #messages == 0, reason = reason })
			-- A clear answer after a refused buy means the way has been cleared since: the "Not rebuilt" warning goes too.
			if #messages == 0 and refused[construction] == viewer.levels then refused[construction] = nil end
			if logFull then
				local logLine = "window viewer construction=" .. tostring(construction) .. " levels=" .. viewer.levels .. " " .. reason
				if not viewerLogged[logLine] then
					viewerLogged[logLine] = true
					say(logLine)
				end
			end
		end,
		entityForRefundableContext = api.engine.util.getPlayer(),
		proposalId = "depot_retrofits_rebuild," .. tostring(construction) .. "," .. viewer.levels .. "," .. tostring(viewer.id),
	} } }
end

local RetrofitTab : Recipe<IEntityWindowParam> = nil
if ready then
	RetrofitTab = react.RegisterRecipe("DepotRetrofitsTab", function(params : IEntityWindowParam) : TreeNodeId
		local construction = params.keyEntity
		local verdictRef = react.useRef(nil as Verdict)
		local placedRef = react.useRef(nil as string) -- what the action area holds: the viewer's levels, "none", or nil at first
		local state = engineReact.useStepState(function() : TabState
			return readTab(construction, verdictRef)
		end, nil, function(a : TabState, b : TabState) : boolean
			return a ~= nil and b ~= nil and a.key == b.key
		end)
		local s = state:old()
		local ok, body = pcall(function() : TreeNodeId
			logShown(s)
			-- The action area changes only when what it should hold changes, so the viewer is not placed again on every draw.
			if params.setActionFn ~= nil then
				actionAreas[construction] = { setActionFn = params.setActionFn, placedRef = placedRef }
				local current = levels.describe(s.levels)
				local want = s.viewer and (current .. "#" .. tostring(s.recheck)) or "none"
				if placedRef:get() ~= want then
					placedRef:set(want)
					local okPlace, placeError : boolean, any = pcall(function()
						if want == "none" then
							params.setActionFn(nil)
							return
						end
						-- A fresh proposal each time, so the viewer answers about the world as it is now.
						local viewer = makeViewer(construction, current)
						if viewer.proposal == nil then
							params.setActionFn(nil)
						else
							params.setActionFn(function() : TreeNodeId return viewerNode(construction, viewer, verdictRef) end)
						end
					end)
					if not okPlace then say("window viewerError construction=" .. tostring(construction) .. " error=" .. tostring(placeError)) end
				end
			end
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
	-- The proposal viewer's way into the window's action area, keyed to the tab.
	local tabAction = show and makeEntityWindow.makeSetActionFnWithCombinedKey(RetrofitTab, setActionFnAndProxy) or nil
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
					setActionFn = tabAction and tabAction.fn,
					setActionFn_compareProxy = tabAction and tabAction.proxy,
				} as IEntityWindowParam,
				autoCloseCondition = entityRevisionCloseConditionAndProxy[1],
				autoCloseCondition_compareProxy = entityRevisionCloseConditionAndProxy[2],
				fallbackTitle = "Retrofit",
			},
		})
	end
	-- The game calls this many times while one window opens (about 60 in the first second), so log each building once.
	local openKey = "open " .. tostring(entity) .. " " .. tostring(show)
	if logFull and openLines < maxOpenLines and not shownKeys[openKey] then
		shownKeys[openKey] = true
		openLines = openLines + 1
		local okCon, con : boolean, any = pcall(api.engine.getComponent, entity, api.type.ComponentType.CONSTRUCTION)
		local c = okCon and con as Engine.Component.Construction or nil
		local fileName : string = c and c.fileName or "?"
		local depots : string = c and c.depots and tostring(#c.depots) or "nil"
		local timeBuilt : string = c and tostring(c.timeBuilt) or "?"
		say("window open construction=" .. tostring(entity) .. " depot=" .. tostring(depot) .. " retrofitTab=" .. tostring(show)
			.. " ready=" .. tostring(ready) .. " owned=" .. tostring(okOwned and owned) .. " depots=" .. depots
			.. " timeBuilt=" .. timeBuilt .. " fileName=" .. tostring(fileName))
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
