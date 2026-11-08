-- Styles for the Retrofit tab (retrofit_window.script.tl). The game loads a mod's .css.lua files with its own
-- (gui/main/*.css.lua, built with gui/main/stylesheetutil.lua). Inline style sheets only take a fixed size; a class rule
-- can set a minimum. Copied from Station Retrofits' retrofit_card.css.lua (same author), where it is tested in game.
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = {}
	local a = ssu.makeAdder(result)

	-- The "<", ">" and ">|" buttons all one width, so the cards' buttons line up from card to card. A minimum, not a fixed
	-- width: at a larger font setting a label widens its button instead of being cut off. The minimum is the content's: the
	-- entity window adds its buttons' padding, 3 above and below and 4 at the sides ("R::EntityWindowContent Button",
	-- gui/entity_window/entity_window.css.lua). In the station window 28 gave buttons about 36 wide.
	a("Button!depot-retrofits-step", { minSize = { 28, -1 } })

	return result
end
