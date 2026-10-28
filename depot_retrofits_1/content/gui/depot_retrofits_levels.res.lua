-- Registers the levels card (levels_card.script.tl) in the window every depot and maintenance building opens, after the
-- base game's maintenance pool card (order 20) and before its balance card (30).
function data()
	return {
		type = "react-plugin ::MaintenanceStationEowExtensionPoint",
		data = {
			filePath = "depot_retrofits_1::/levels_card.script@LevelsPlugin",
			condition = "depot_retrofits_1::/levels_card.script@condition",
			order = 25,
		},
	}
end
