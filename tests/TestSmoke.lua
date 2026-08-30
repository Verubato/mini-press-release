-- Loads the whole addon into a mocked client and drives it through login.
-- The shared body lives in build/Lua/SmokeTest.lua.

local fw = require("TestFramework")
local smoke = require("SmokeTest")
local harness = require("AddonHarness")
local WowMock = require("WowMock")

-- Mirrors mini.VerticalSpacing in src/Config.lua.
local VERTICAL_SPACING = 16
-- Mirror CHIP_HEIGHT and CHIP_GAP_Y in src/Config.lua.
local CHIP_HEIGHT = 20
local CHIP_GAP_Y = 6

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

---@return number chips belonging to any filter list that are currently shown
local function ShownChipCount()
	local count = 0

	for _, frame in ipairs(WowMock.Frames) do
		if frame.Key ~= nil and frame.Remove and frame:IsShown() then
			count = count + 1
		end
	end

	return count
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

---@param frame table
---@param text string
---@return table? the region parented directly to frame carrying this text
local function FindRegion(frame, text)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetText and region:GetText() == text then
			return region
		end
	end
end

---@param frame table
---@return table? relativeTo, number? x, number? y the frame's own TOPLEFT point
local function TopLeftPoint(frame)
	for i = 1, frame:GetNumPoints() do
		local point, relativeTo, _, x, y = frame:GetPoint(i)

		if point == "TOPLEFT" then
			return relativeTo, x, y
		end
	end
end

---Every filter list control is anchored by its left edge to the label naming it.
---@param label table
---@return table?
local function FindControlFor(label)
	for _, frame in ipairs(WowMock.Frames) do
		for i = 1, frame:GetNumPoints() do
			local point, relativeTo = frame:GetPoint(i)

			if point == "LEFT" and relativeTo == label then
				return frame
			end
		end
	end
end

---@return table[] every keybinding chip currently drawn, in any filter list
local function AllChips()
	local chips = {}

	for _, frame in ipairs(WowMock.Frames) do
		if frame.Key ~= nil and frame.Remove and frame:IsShown() then
			chips[#chips + 1] = frame
		end
	end

	return chips
end

---@param key string
---@return table? the chip drawn for this key, if one is currently drawn
local function FindChip(key)
	for _, chip in ipairs(AllChips()) do
		if chip.Key == key then
			return chip
		end
	end
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

		fw.eq(ShownChipCount(), 1, "the pending inclusion shows as a chip before the reset")

		local resetBtn = FindButton("Reset to Defaults")
		fw.not_nil(resetBtn, "reset button exists")

		AcceptConfirm(function()
			resetBtn:Click()
		end)

		fw.eq(db.KeyboardEnabled, context.Addon.Config.DbDefaults.KeyboardEnabled, "reset restored KeyboardEnabled")
		fw.is_nil(db.Inclusions["Z"], "reset restored Inclusions")

		-- Turning Include Mode back on must not bring back the chip the reset just cleared.
		db.InclusionsEnabled = true
		panel:Hide()
		panel:Show()

		fw.eq(ShownChipCount(), 0, "no chips survive a reset once the mode is switched back on")
	end,
})

fw.describe("MiniPressRelease - keybinding chips", function()
	---@param charDb table
	local function LoginWith(charDb)
		-- Seeded before Load, so WowMock's preserve-on-install keeps it as the addon's own
		-- saved variables rather than the empty defaults a cold login would create.
		_G["MiniPressReleaseCharDB"] = charDb

		local context = harness.Load("MiniPressRelease")
		harness.Login(context)
	end

	fw.it("builds one chip per bound key, in the inclusions and exclusions lists", function()
		LoginWith({ Inclusions = { A = true }, Exclusions = { B = true } })

		fw.eq(#AllChips(), 2, "one chip per list")
	end)

	fw.it("draws a chip carrying an added key's text", function()
		LoginWith({ Inclusions = { ["CTRL-1"] = true }, Exclusions = {} })

		local chip = FindChip("CTRL-1")

		fw.not_nil(chip, "a chip for the bound key")
		fw.eq(chip.Text:GetText(), "CTRL-1", "the chip shows the key's text")
	end)

	fw.it("removes a key when its chip's x is clicked", function()
		LoginWith({ Inclusions = { ["CTRL-1"] = true }, Exclusions = {} })

		local chip = FindChip("CTRL-1")
		fw.not_nil(chip, "a chip for the bound key")

		chip.Remove:Click()

		local db = _G["MiniPressReleaseCharDB"]
		fw.is_nil(db.Inclusions["CTRL-1"], "the key is gone from the saved variables")
		fw.is_nil(FindChip("CTRL-1"), "the chip stops being drawn")
	end)

	fw.it("shows the empty-state line when no keys are bound", function()
		LoginWith({ Inclusions = {}, Exclusions = {} })

		local container = ContainerFor("A set of keybindings to include.")
		local empty = FindRegion(container, "No keys added yet.")

		fw.not_nil(empty, "the empty-state line exists")
		fw.truthy(empty:IsShown(), "it shows when no keys are bound")
	end)

	fw.it("hides the empty-state line once a key is bound", function()
		LoginWith({ Inclusions = { ["CTRL-1"] = true }, Exclusions = {} })

		local container = ContainerFor("A set of keybindings to include.")
		local empty = FindRegion(container, "No keys added yet.")

		fw.not_nil(empty, "the empty-state line exists")
		fw.falsy(empty:IsShown(), "it hides once a key is bound")
	end)

	fw.it("wraps a chip that will not fit onto the next line, back at the left edge", function()
		---@param keys string[]
		---@return table[] the chips drawn for these keys, in the order they were laid out
		local function ChipsFor(keys)
			local inclusions = {}

			for _, key in ipairs(keys) do
				inclusions[key] = true
			end

			LoginWith({ Inclusions = inclusions, Exclusions = {} })

			return AllChips()
		end

		---@param chip table
		---@return number x, number y
		local function OffsetOf(chip)
			local _, x, y = TopLeftPoint(chip)

			return x, y
		end

		-- Each key is one narrow letter, so two fit the mock's default container width.
		local chips = ChipsFor({ "A", "B", "C", "D" })
		fw.eq(#chips, 4, "one chip per bound key")

		local firstX, firstY = OffsetOf(chips[1])
		local secondX, secondY = OffsetOf(chips[2])
		local thirdX, thirdY = OffsetOf(chips[3])
		local fourthX, fourthY = OffsetOf(chips[4])

		fw.eq(secondY, firstY, "the second chip stays on the first line")
		fw.truthy(secondX > firstX, "the second chip sits right of the first")

		fw.eq(thirdX, firstX, "the third chip wraps back to the left edge")
		fw.eq(thirdY, firstY - (CHIP_HEIGHT + CHIP_GAP_Y), "the third chip drops one line, not up or two")

		fw.eq(fourthY, thirdY, "the fourth chip stays on the second line")
		fw.truthy(fourthX > thirdX, "the fourth chip sits right of the third")
	end)
end)

fw.describe("MiniPressRelease - the filter mode", function()
	---@param charDb table
	local function LoginWith(charDb)
		_G["MiniPressReleaseCharDB"] = charDb

		local context = harness.Load("MiniPressRelease")

		harness.Login(context)
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

	fw.it("anchors the off line and both filter lists to the Filter Mode label, not its control", function()
		LoginWith({ Inclusions = {}, Exclusions = {} })

		local panel = FindPanel("MiniPressRelease")
		fw.not_nil(panel, "the settings panel")

		local label = FindRegion(panel, "Filter Mode")
		fw.not_nil(label, "the Filter Mode label")

		local dropdown = FindControlFor(label)
		fw.not_nil(dropdown, "the Filter Mode dropdown control")

		local offLine = FindRegion(panel, "Every bound key gets the down and up behaviour.")
		local inclusionsContainer = ContainerFor("A set of keybindings to include.")
		local exclusionsContainer = ContainerFor("A set of keybindings to exclude.")

		fw.not_nil(offLine, "the off line")
		fw.not_nil(inclusionsContainer, "the inclusions list")
		fw.not_nil(exclusionsContainer, "the exclusions list")

		local offRelativeTo, _, offY = TopLeftPoint(offLine)
		local inclusionsRelativeTo, _, inclusionsY = TopLeftPoint(inclusionsContainer)
		local exclusionsRelativeTo, _, exclusionsY = TopLeftPoint(exclusionsContainer)

		fw.eq(offRelativeTo, label, "the off line anchors to the label")
		fw.eq(inclusionsRelativeTo, label, "the inclusions list anchors to the label")
		fw.eq(exclusionsRelativeTo, label, "the exclusions list anchors to the label")

		-- The dropdown control is taller than its label and centred on it, so a passing test
		-- on a mock where the two heights matched would prove nothing about the drop.
		local dropdownClearance = (dropdown:GetHeight() - label:GetStringHeight()) / 2
		fw.truthy(dropdownClearance > 0, "the control is genuinely taller than its label")

		local expectedY = -VERTICAL_SPACING - dropdownClearance

		fw.eq(offY, expectedY, "the off line clears the dropdown control")
		fw.eq(inclusionsY, expectedY, "the inclusions list clears the dropdown control")
		fw.eq(exclusionsY, expectedY, "the exclusions list clears the dropdown control")
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
