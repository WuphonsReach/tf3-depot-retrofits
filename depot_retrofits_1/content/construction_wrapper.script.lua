-- The script reference every wrapped depot names (mod.script.tl, wrapperRef and moduleWrapperRef). It hands each call to the
-- wrapper in construction.script.tl. The reference names this .lua file, which defines the global data() as the base game's
-- construction scripts do, so that a mod wrapping ours can load it either way: through base util.useFn, or by loading the
-- file itself and calling data() (TRM: Industry Emissions does that, see docs/compatibility.md). Both functions come from the
-- one module, so update and updateModule share its state.

local loaded, wrapper = pcall(ug_require, "depot_retrofits_1::/construction.script.tl")

local failed = function()
	error("DEPOT_RETROFITS wrapper not loaded: " .. tostring(wrapper))
end

function data()
	if not loaded or type(wrapper) ~= "table" then
		return { update = failed, updateModule = failed }
	end
	return { update = wrapper.update, updateModule = wrapper.updateModule }
end
