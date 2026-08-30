-- CursorHasAnything(), ApplyCursorState() and GetActionForButton() are all file-local to
-- src/Mouse.lua. tests/Helpers/Env.lua logs in with MouseEnabled on, so ApplyBlizzard() has
-- already drawn an overlay over ActionButton1; these drive the addon's own CURSOR_CHANGED
-- handling and the overlay's own OnEnter script, and read back what changed on the overlay or
-- the tooltip as proof.

local fw = require("TestFramework")
local Env = require("Env")

fw.describe("MiniPressRelease - CursorHasAnything sources", function()
	local env
	local overlay

	fw.before_each(function()
		env = Env.Build()
		overlay = env.Overlay("ActionButton1")
	end)

	fw.it("an overlay starts with its mouse enabled", function()
		fw.truthy(overlay:IsMouseEnabled(), "nothing has been picked up yet")
	end)

	fw.it("notices something already on the cursor via GetCursorInfo", function()
		env.SetCursorInfo(true)
		env.CursorChanged()
		env.RunDeferredCheck()

		fw.falsy(overlay:IsMouseEnabled(), "the overlay steps aside for the drag")
	end)

	fw.it("notices an item picked up via CursorHasItem", function()
		env.SetCursorSource("CursorHasItem", true)
		env.CursorChanged()
		env.RunDeferredCheck()

		fw.falsy(overlay:IsMouseEnabled(), "the overlay steps aside for the drag")
	end)

	fw.it("notices a spell picked up via CursorHasSpell", function()
		env.SetCursorSource("CursorHasSpell", true)
		env.CursorChanged()
		env.RunDeferredCheck()

		fw.falsy(overlay:IsMouseEnabled(), "the overlay steps aside for the drag")
	end)

	fw.it("notices a macro picked up via CursorHasMacro", function()
		env.SetCursorSource("CursorHasMacro", true)
		env.CursorChanged()
		env.RunDeferredCheck()

		fw.falsy(overlay:IsMouseEnabled(), "the overlay steps aside for the drag")
	end)

	fw.it("notices money picked up via CursorHasMoney", function()
		env.SetCursorSource("CursorHasMoney", true)
		env.CursorChanged()
		env.RunDeferredCheck()

		fw.falsy(overlay:IsMouseEnabled(), "the overlay steps aside for the drag")
	end)
end)

fw.describe("MiniPressRelease - the overlay enable/disable state machine", function()
	local env
	local overlay

	fw.before_each(function()
		env = Env.Build()
		overlay = env.Overlay("ActionButton1")
	end)

	-- QueueCursorCheck() waits a frame before calling ApplyCursorState(), so the overlay must
	-- still read as enabled right after the event fires and only flip once the timer drains.
	fw.it("leaves the overlay enabled until the deferred check actually runs", function()
		env.SetCursorInfo(true)
		env.CursorChanged()

		fw.truthy(overlay:IsMouseEnabled(), "the check hasn't run yet")

		env.RunDeferredCheck()

		fw.falsy(overlay:IsMouseEnabled(), "now it has")
	end)

	fw.it("re-enables the overlay once the cursor is released", function()
		env.SetCursorInfo(true)
		env.CursorChanged()
		env.RunDeferredCheck()

		fw.falsy(overlay:IsMouseEnabled(), "disabled while something is on the cursor")

		env.SetCursorInfo(false)
		env.CursorChanged()
		env.RunDeferredCheck()

		fw.truthy(overlay:IsMouseEnabled(), "re-enabled once the cursor is empty again")
	end)
end)

fw.describe("MiniPressRelease - GetActionForButton", function()
	local env
	local overlay
	local button

	fw.before_each(function()
		env = Env.Build()
		overlay = env.Overlay("ActionButton1")
		button = _G["ActionButton1"]
	end)

	---Triggers the overlay's OnEnter, which reads GetActionForButton(button) to fill the tooltip.
	local function Hover()
		overlay:GetScript("OnEnter")()
	end

	fw.it("prefers the button's own action property over its action attribute", function()
		button.action = 5
		button:SetAttribute("action", 9)

		Hover()

		fw.eq(_G.GameTooltip.LastAction, 5, "the property wins over the attribute")
	end)

	fw.it("falls back to the action attribute when the property isn't a number", function()
		button.action = nil
		button:SetAttribute("action", 9)

		Hover()

		fw.eq(_G.GameTooltip.LastAction, 9, "the attribute is read once the property is gone")
	end)

	fw.it("hides the tooltip instead of showing an action when neither is a number", function()
		button.action = nil
		button:SetAttribute("action", nil)

		_G.GameTooltip:Show()
		Hover()

		fw.falsy(_G.GameTooltip:IsShown(), "nothing to show, so the tooltip hides")
	end)
end)
