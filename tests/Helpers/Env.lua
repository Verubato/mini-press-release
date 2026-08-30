-- Loads MiniPressRelease into a mocked client with MouseEnabled on, so ApplyBlizzard() has
-- already built an overlay for every pre-created action bar button. CursorHasAnything(),
-- ApplyCursorState() and GetActionForButton() are all file-local to src/Mouse.lua, so every
-- test drives them the way the addon itself does: firing CURSOR_CHANGED (which queues its
-- check a frame later, via C_Timer.After(0,...), so a test has to drain WowMock's timers to see
-- the result) or invoking an overlay's own OnEnter script, then reading back what changed on the
-- overlay or the tooltip.

local harness = require("AddonHarness")
local WowMock = require("WowMock")

local M = {}

---The mock leaves every cursor-content API nil on purpose (see build/Lua/WowMock.lua's "unknown
---globals stay nil" design), and never resets a global it doesn't own between builds, so a
---fresh env always clears them itself rather than trusting the previous test left them alone.
local function ClearCursorSources()
	_G.GetCursorInfo = function()
		return nil
	end

	_G.CursorHasItem = nil
	_G.CursorHasSpell = nil
	_G.CursorHasMacro = nil
	_G.CursorHasMoney = nil
end

---@param env table
---@param context table
local function InstallOverrides(env, context)
	env.Context = context
	env.Addon = context.Addon

	ClearCursorSources()

	---Makes GetCursorInfo report something is on the cursor, or nothing.
	function env.SetCursorInfo(hasSomething)
		_G.GetCursorInfo = function()
			return hasSomething and "item" or nil
		end
	end

	---Stubs one of the optional cursor-content globals the mock never defines.
	---@param name string "CursorHasItem", "CursorHasSpell", "CursorHasMacro" or "CursorHasMoney"
	function env.SetCursorSource(name, hasSomething)
		_G[name] = hasSomething and function()
			return true
		end or nil
	end

	env.ClearCursorSources = ClearCursorSources

	-- The mock's GameTooltip has no SetAction (see build/Lua/WowMock.lua), so this stubs it
	-- locally to record what the addon asked the tooltip to show.
	_G.GameTooltip.SetAction = function(tooltip, actionSlot)
		tooltip.LastAction = actionSlot
	end

	---@param buttonName string e.g. "ActionButton1"
	---@return table? overlay the SecureActionButtonTemplate MiniPressRelease drew over it
	function env.Overlay(buttonName)
		return _G[buttonName .. "MouseDownOverlay"]
	end

	---Fires CURSOR_CHANGED, the event QueueCursorCheck() reacts to.
	function env.CursorChanged()
		WowMock.FireEvent("CURSOR_CHANGED")
	end

	---Runs the check QueueCursorCheck() deferred by a frame with C_Timer.After(0, ...).
	function env.RunDeferredCheck()
		WowMock.RunTimers()
	end
end

---Logs in with the mouse feature on, so Mouse:Init() registers CURSOR_CHANGED and login's
---PLAYER_LOGIN event already ran ApplyBlizzard() once, building an overlay for ActionButton1.
---@return table env
function M.Build()
	_G["MiniPressReleaseCharDB"] = {
		KeyboardEnabled = true,
		MouseEnabled = true,
		InclusionsEnabled = false,
		ExclusionsEnabled = false,
		Inclusions = {},
		Exclusions = {},
	}

	local context = harness.Load("MiniPressRelease")
	local env = {}

	InstallOverrides(env, context)
	harness.Login(context)

	return env
end

return M
