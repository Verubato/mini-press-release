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

---The confirmation dialog is a frame the framework owns, so a test reaches it by its button label.
---@param label string
---@return table?
local function FindButton(label)
	for _, frame in ipairs(WowMock.Frames) do
		if frame.GetText and frame:GetText() == label and frame.Click then
			return frame
		end
	end

	return nil
end

---The settings panel is a frame the framework owns, so a test reaches it by its own name.
---@param name string
---@return table?
local function FindPanel(name)
	for _, frame in ipairs(WowMock.Frames) do
		if frame.name == name then
			return frame
		end
	end

	return nil
end

---@return number rows belonging to any filter list that are currently shown
local function ShownStyledRowCount()
	local count = 0

	for _, frame in ipairs(WowMock.Frames) do
		if frame.Field and frame.Remove and frame:IsShown() then
			count = count + 1
		end
	end

	return count
end

---The client does nothing with a prompt in the mock, so a test stands in for it.
---@param open fun()
local function AcceptConfirm(open)
	local seen
	local real = StaticPopup_Show

	StaticPopup_Show = function(which, _, _, data)
		seen = { Which = which, Data = data }
	end

	local ok, err = pcall(open)

	StaticPopup_Show = real

	if not ok then
		error(err, 0)
	end

	if not seen then
		error("no confirmation was opened")
	end

	StaticPopupDialogs[seen.Which].OnAccept(nil, seen.Data)
end

smoke.Run("MiniPressRelease", {
	extra = function(context)
		fw.eq(context.Addon.Framework.CustomStyling, true, "custom styling on")
		fw.eq(context.Addon.Framework.CustomStylingOverrides.Button, false, "stock buttons")
		fw.truthy(HasDivider("SETTINGS"), "the settings section rule under the header")
		fw.truthy(HasDivider("KEYBINDINGS"), "the keybindings section rule above the grid")

		local db = _G["MiniPressReleaseCharDB"]
		db.KeyboardEnabled = false
		db.Inclusions["Z"] = true
		db.InclusionsEnabled = true

		local panel = FindPanel("MiniPressRelease")
		fw.not_nil(panel, "the settings panel exists")

		-- Reopening the panel is what puts a filter list in step with the saved keys.
		panel:Hide()
		panel:Show()

		fw.eq(ShownStyledRowCount(), 1, "the pending inclusion shows as a row before the reset")

		local resetBtn = FindButton("Reset to Defaults")
		fw.not_nil(resetBtn, "reset button exists")

		AcceptConfirm(function()
			resetBtn:Click()
		end)

		fw.eq(db.KeyboardEnabled, context.Addon.Config.DbDefaults.KeyboardEnabled, "reset restored KeyboardEnabled")
		fw.is_nil(db.Inclusions["Z"], "reset restored Inclusions")

		-- Turning Include Mode back on must not bring back the row the reset just cleared.
		db.InclusionsEnabled = true
		panel:Hide()
		panel:Show()

		fw.eq(ShownStyledRowCount(), 0, "no rows survive a reset once the mode is switched back on")
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

	---@param count number
	---@return number the inclusions container's own height
	local function InclusionsHeight(count)
		local inclusions = {}

		for i = 1, count do
			inclusions["K" .. i] = true
		end

		_G["MiniPressReleaseCharDB"] = { Inclusions = inclusions, Exclusions = {} }

		local context = harness.Load("MiniPressRelease")
		harness.Login(context)

		for _, frame in ipairs(WowMock.Frames) do
			if frame.Field and frame.Remove then
				-- Three parents up from a row: the list's scroll child, its scroll frame, and
				-- the container mini:List's viewport is sized to.
				return frame:GetParent():GetParent():GetParent():GetHeight()
			end
		end

		error("no styled row found for " .. count .. " keys")
	end

	fw.it("sizes the container to its rows, clamped at ten", function()
		local short = InclusionsHeight(3)
		local atCap = InclusionsHeight(10)
		local pastCap = InclusionsHeight(12)

		fw.truthy(short < atCap, "three rows is shorter than the capped height")
		fw.eq(pastCap, atCap, "twelve rows stops growing once the cap is reached")
	end)
end)

fw.describe("MiniPressRelease - the filter mode", function()
	---@param charDb table
	local function LoginWith(charDb)
		_G["MiniPressReleaseCharDB"] = charDb

		local context = harness.Load("MiniPressRelease")

		harness.Login(context)
	end

	---A filter list is only reachable through the description line the widget parented to it.
	---@param text string
	---@return table?
	local function ContainerFor(text)
		for _, frame in ipairs(WowMock.Frames) do
			for _, region in ipairs({ frame:GetRegions() }) do
				if region.GetText and region:GetText() == text then
					return frame
				end
			end
		end
	end

	---@return boolean? inclusions, boolean? exclusions
	local function ShownBodies()
		local inclusions = ContainerFor("A set of keybindings to include.")
		local exclusions = ContainerFor("A set of keybindings to exclude.")

		return inclusions and inclusions:IsShown(), exclusions and exclusions:IsShown()
	end

	fw.it("shows neither list when no mode is on", function()
		LoginWith({ Inclusions = {}, Exclusions = {} })

		local inclusions, exclusions = ShownBodies()

		fw.falsy(inclusions, "the inclusions list stays hidden")
		fw.falsy(exclusions, "the exclusions list stays hidden")
	end)

	fw.it("shows only the inclusions list in include mode", function()
		LoginWith({ Inclusions = {}, Exclusions = {}, InclusionsEnabled = true })

		local inclusions, exclusions = ShownBodies()

		fw.truthy(inclusions, "the inclusions list shows")
		fw.falsy(exclusions, "the exclusions list stays hidden")
	end)

	fw.it("shows only the exclusions list in exclude mode", function()
		LoginWith({ Inclusions = {}, Exclusions = {}, ExclusionsEnabled = true })

		local inclusions, exclusions = ShownBodies()

		fw.falsy(inclusions, "the inclusions list stays hidden")
		fw.truthy(exclusions, "the exclusions list shows")
	end)

	fw.it("says nothing about combat when the panel opens mid fight", function()
		LoginWith({ Inclusions = {}, Exclusions = {} })

		local panel = FindPanel("MiniPressRelease")

		fw.not_nil(panel, "the settings panel")

		local realCombat, realPrint = _G.InCombatLockdown, _G.print
		local printed = 0

		_G.InCombatLockdown = function()
			return true
		end

		_G.print = function()
			printed = printed + 1
		end

		local ok, err = pcall(panel:GetScript("OnShow"))

		_G.InCombatLockdown, _G.print = realCombat, realPrint

		if not ok then
			error(err, 0)
		end

		fw.eq(printed, 0, "opening the panel changes nothing, so it warns about nothing")
	end)
end)
