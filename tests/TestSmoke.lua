-- Loads the whole addon into a mocked client and drives it through login.
-- The shared body lives in build/Lua/SmokeTest.lua.

local fw = require("TestFramework")
local smoke = require("SmokeTest")
local harness = require("AddonHarness")
local WowMock = require("WowMock")

---The section rule is built by the framework and never handed back to the addon, so a test
---finds it the way a player sees it, by its label.
---@param text string
---@return boolean
local function HasDivider(text)
	for _, frame in ipairs(WowMock.Frames) do
		if frame.Label and frame.Label.GetText and frame.Label:GetText() == text then
			return true
		end
	end

	return false
end

smoke.Run("MiniPressRelease", {
	extra = function(context)
		fw.eq(context.Addon.Framework.CustomStyling, true, "custom styling on")
		fw.eq(context.Addon.Framework.CustomStylingOverrides.Button, false, "stock buttons")
		fw.truthy(HasDivider("SETTINGS"), "the settings section rule under the header")
		fw.truthy(HasDivider("KEYBINDINGS"), "the keybindings section rule above the grid")
	end,
})

fw.describe("MiniPressRelease - keybinding list styling", function()
	fw.it("builds the inclusions and exclusions lists with the styled rows", function()
		-- Seeded before Load, so WowMock's preserve-on-install keeps it as the addon's own
		-- saved variables rather than the empty defaults a cold login would create.
		_G["MiniPressReleaseCharDB"] = {
			Inclusions = { A = true },
			Exclusions = { B = true },
		}

		local context = harness.Load("MiniPressRelease")
		harness.Login(context)

		local styledRows = 0

		for _, frame in ipairs(WowMock.Frames) do
			if frame.Field and frame.Remove then
				styledRows = styledRows + 1
			end
		end

		fw.eq(styledRows, 2, "one styled row per list")
	end)
end)
