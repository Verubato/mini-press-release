---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
local verticalSpacing = mini.VerticalSpacing
local horizontalSpacing = mini.HorizontalSpacing
local firstColumnWidth = 200
local secondColumnWidth = 100
local CAPTURE_BOX_WIDTH = 180
local CAPTURE_BUTTON_WIDTH = 70
local CAPTURE_GAP = 10
-- The flattened field's border draws 6px left of the box's own frame.
local CAPTURE_FIELD_INSET = 6
-- The capture zone and the description line share a right edge.
local CAPTURE_ZONE_WIDTH = CAPTURE_FIELD_INSET + CAPTURE_BOX_WIDTH + CAPTURE_GAP + CAPTURE_BUTTON_WIDTH
local CAPTURE_HEIGHT = 30
local CHIP_HEIGHT = 20
local CHIP_TEXT_INSET = 8
local CHIP_REMOVE_SIZE = 14
local CHIP_REMOVE_GAP = 4
local CHIP_GAP_X = 6
local CHIP_GAP_Y = 6
-- The group loot pass art is a red cross on every client this addon supports.
local CHIP_REMOVE_TEXTURE = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local CHIP_REMOVE_TEXTURE_PUSHED = "Interface\\Buttons\\UI-GroupLoot-Pass-Down"
local CHIP_REMOVE_TEXTURE_HIGHLIGHT = "Interface\\Buttons\\UI-GroupLoot-Pass-Highlight"
local FILTER_MODES = { "off", "include", "exclude" }
local FILTER_MODE_TEXT = {
	off = "Off",
	include = "Include Mode",
	exclude = "Exclude Mode",
}
---@type CharDb
local charDb
---@class CharDb
local charDbDefaults = {
	Version = 1,
	KeyboardEnabled = true,
	MouseEnabled = false,
	InclusionsEnabled = false,
	ExclusionsEnabled = false,
	Inclusions = {},
	Exclusions = {},
}
---@class Config
local M = {
	DbDefaults = charDbDefaults,
}
addon.Config = M

local function NormaliseBindingKey(key)
	if not key or key == "" then
		return nil
	end

	key = key:upper()

	-- ignore pure modifier presses
	if
		key == "LSHIFT"
		or key == "RSHIFT"
		or key == "LCTRL"
		or key == "RCTRL"
		or key == "LALT"
		or key == "RALT"
		or key == "LMETA"
		or key == "RMETA"
		or key == "ENTER"
		or key == "BACKSPACE"
	then
		return nil
	end

	local parts = {}

	if IsControlKeyDown() then
		table.insert(parts, "CTRL")
	end

	if IsAltKeyDown() then
		table.insert(parts, "ALT")
	end

	if IsShiftKeyDown() then
		table.insert(parts, "SHIFT")
	end

	table.insert(parts, key)

	return table.concat(parts, "-")
end

local function CreateCaptureZone(parent, onKeySelected)
	local placeholder = "Click then press a key"
	local container = CreateFrame("Frame", nil, parent)
	local capture = CreateFrame("EditBox", nil, container, "InputBoxTemplate")

	container:SetSize(CAPTURE_ZONE_WIDTH, CAPTURE_HEIGHT)

	mini:FlattenEditBox(capture)
	capture:SetSize(CAPTURE_BOX_WIDTH, CAPTURE_HEIGHT)
	capture:SetPoint("TOPLEFT", container, "TOPLEFT", CAPTURE_FIELD_INSET, 0)
	capture:SetAutoFocus(false)
	capture:EnableMouse(true)

	local pendingKey
	local addBtn

	local function SetDisplay(text)
		if text then
			capture:SetText(text)
			capture:SetTextColor(1, 1, 1, 1)
		else
			capture:SetText(placeholder)
			capture:SetTextColor(0.5, 0.5, 0.5, 1)
		end

		capture:SetCursorPosition(0)
		capture:HighlightText(0, 0)
	end

	local function SetPendingKey(keyString)
		pendingKey = keyString
		SetDisplay(keyString)
		addBtn:SetEnabled(pendingKey ~= nil)
	end

	-- don't allow user-typed characters to appear
	capture:SetScript("OnChar", function()
		capture:SetText("")
		capture:SetCursorPosition(0)
		capture:HighlightText(0, 0)
	end)

	capture:SetScript("OnEditFocusGained", function()
		-- blank while listening
		capture:SetText("")
		capture:SetCursorPosition(0)
		capture:HighlightText(0, 0)
	end)

	capture:SetScript("OnEditFocusLost", function()
		SetDisplay(pendingKey)
	end)

	capture:SetScript("OnEscapePressed", function()
		capture:ClearFocus()
	end)

	capture:SetScript("OnEnterPressed", function()
		capture:ClearFocus()
	end)

	capture:SetScript("OnKeyDown", function(_, key)
		local normalised = NormaliseBindingKey(key)

		if normalised then
			SetPendingKey(normalised)
			return
		end

		pendingKey = nil
		addBtn:SetEnabled(false)
		capture:SetText("")
		capture:SetCursorPosition(0)
		capture:HighlightText(0, 0)
	end)

	capture:SetScript("OnKeyUp", function()
		if pendingKey then
			capture:SetText(pendingKey)
		else
			capture:SetText("")
		end
		capture:SetCursorPosition(0)
		capture:HighlightText(0, 0)
	end)

	capture:SetScript("OnMouseDown", function(_, button)
		if not button then
			return
		end

		-- left click is just to focus/listen
		if button == "LeftButton" then
			capture:SetFocus()
			return
		end

		local normalised = NormaliseBindingKey(button)
		if normalised then
			SetPendingKey(normalised)
		end
	end)

	addBtn = mini:Button({
		Parent = container,
		Text = "Add",
		Width = CAPTURE_BUTTON_WIDTH,
		Height = 26,
		OnClick = function()
			if not pendingKey then
				return
			end

			onKeySelected(pendingKey)
			SetPendingKey(nil)
			capture:ClearFocus()
		end,
	})

	addBtn:SetPoint("LEFT", capture, "RIGHT", CAPTURE_GAP, 0)

	-- Add is dead until there is something to add.
	SetPendingKey(nil)

	return container
end

---Builds one chip carrying the key text and a red cross that removes it.
---@param parent table
---@param onRemove fun(key: string)
---@return table chip
local function CreateChip(parent, onRemove)
	local chip = CreateFrame("Frame", nil, parent)
	chip:SetHeight(CHIP_HEIGHT)

	local field = mini.GUI.RoundedField(chip, CHIP_HEIGHT, "BACKGROUND")
	field.Fill:SetColor(mini.GUI.FieldIdle.r, mini.GUI.FieldIdle.g, mini.GUI.FieldIdle.b, 0.9)
	field.Border:SetColor(mini.GUI.LineIdle.r, mini.GUI.LineIdle.g, mini.GUI.LineIdle.b, 1)
	chip.Field = field

	chip.Remove = CreateFrame("Button", nil, chip)
	chip.Remove:SetSize(CHIP_REMOVE_SIZE, CHIP_REMOVE_SIZE)
	chip.Remove:SetPoint("RIGHT", chip, "RIGHT", -CHIP_TEXT_INSET, 0)
	chip.Remove:SetNormalTexture(CHIP_REMOVE_TEXTURE)
	chip.Remove:SetPushedTexture(CHIP_REMOVE_TEXTURE_PUSHED)
	chip.Remove:SetHighlightTexture(CHIP_REMOVE_TEXTURE_HIGHLIGHT, "ADD")

	-- Every chip is the same width, so the label centres in whatever room the widest key left.
	chip.Text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	chip.Text:SetJustifyH("CENTER")
	-- The longest key is given exactly its own width, so a rounding shortfall would wrap it.
	chip.Text:SetWordWrap(false)
	chip.Text:SetPoint("LEFT", chip, "LEFT", CHIP_TEXT_INSET, 0)
	chip.Text:SetPoint("RIGHT", chip.Remove, "LEFT", -CHIP_REMOVE_GAP, 0)

	chip.Remove:SetScript("OnClick", function()
		onRemove(chip.Key)
	end)

	return chip
end

---@param chip table
---@param key string
local function SetChipKey(chip, key)
	chip.Key = key
	chip.Text:SetText(key)
end

---@param chip table
---@return number the width this chip would need to hold its own key
local function ChipNaturalWidth(chip)
	return CHIP_TEXT_INSET + chip.Text:GetStringWidth() + CHIP_REMOVE_GAP + CHIP_REMOVE_SIZE + CHIP_TEXT_INSET
end

---@param set table<string, boolean>
---@return string[]
local function CollectKeys(set)
	local keys = {}

	for key in pairs(set) do
		table.insert(keys, key)
	end

	return keys
end

---@param parent table
---@param dbKey string charDb field holding the key set, "Inclusions" or "Exclusions"
---@param description string
---@return FilterList
local function CreateFilterList(parent, dbKey, description)
	local container = CreateFrame("Frame", nil, parent)
	-- The chips flow across the panel's own width.
	container:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

	local descriptionLine = mini:TextLine({
		Parent = container,
		Text = description,
		Width = CAPTURE_ZONE_WIDTH,
	})

	descriptionLine:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

	local chips = {}
	local Refresh

	local capture = CreateCaptureZone(container, function(keyString)
		charDb[dbKey] = charDb[dbKey] or {}
		charDb[dbKey][keyString] = true

		Refresh()
		addon:Refresh()
	end)

	capture:SetPoint("TOPLEFT", descriptionLine, "BOTTOMLEFT", 0, -verticalSpacing / 2)

	local emptyLine = mini:TextLine({
		Parent = container,
		Text = "No keys added yet.",
		Width = CAPTURE_ZONE_WIDTH,
	})

	emptyLine:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 0, -verticalSpacing)

	local function RemoveKey(key)
		charDb[dbKey][key] = nil
		Refresh()
		addon:Refresh()
	end

	---Lays out one chip per key, wrapping to a new line once the next one would run past
	---the available width.
	---@param keys string[]
	---@param availableWidth number
	local function ReflowChips(keys, availableWidth)
		local x, line = 0, 0
		local chipWidth = 0

		for i, key in ipairs(keys) do
			if not chips[i] then
				chips[i] = CreateChip(container, RemoveKey)
			end

			SetChipKey(chips[i], key)
			chipWidth = math.max(chipWidth, ChipNaturalWidth(chips[i]))
		end

		for i = 1, #keys do
			local chip = chips[i]

			chip:SetWidth(chipWidth)

			if x > 0 and x + chipWidth > availableWidth then
				x, line = 0, line + 1
			end

			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", x, -verticalSpacing - line * (CHIP_HEIGHT + CHIP_GAP_Y))
			chip:Show()

			x = x + chipWidth + CHIP_GAP_X
		end

		for i = #keys + 1, #chips do
			chips[i]:Hide()
		end
	end

	Refresh = function()
		local keys = CollectKeys(charDb[dbKey])
		table.sort(keys)

		emptyLine:SetShown(#keys == 0)

		-- The panel has no width yet while its controls are being built.
		local availableWidth = container:GetWidth()

		if availableWidth > 0 then
			ReflowChips(keys, availableWidth)
		end
	end

	-- The re-flow needs the panel's width, which only arrives on the first resize.
	container:SetScript("OnSizeChanged", Refresh)

	Refresh()

	return { Container = container, Refresh = Refresh }
end

function M:Init()
	-- A styled button clashes with the stock Blizzard art around it in the settings screen.
	mini:SetCustomStyling(true, { Button = false })

	charDb = mini:GetCharacterSavedVars(charDbDefaults)

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	local inclusions, exclusions, RefreshFilters

	local col2X = firstColumnWidth + horizontalSpacing
	local header = mini:PanelHeader({
		Parent = panel,
		Description = "Increase your chance at landing spells.",
		Gap = 8,
		Divider = true,
		Reset = {
			OnAccept = function()
				-- mini:ResetSavedVars only clears the account-wide <AddonName>DB, not this
				-- addon's per-character table, so reset it here instead.
				wipe(charDb)
				mini:CopyTable(charDbDefaults, charDb)
				RefreshFilters()
			end,
		},
	})

	local kbEnabledChkBox = mini:Checkbox({
		Parent = panel,
		LabelText = "Keyboard Enabled",
		Tooltip = "Whether to enable/disable the keyboard functionality.",
		GetValue = function()
			return charDb.KeyboardEnabled
		end,
		SetValue = function(enabled)
			if InCombatLockdown() then
				mini:NotifyCombatLockdown()
				return
			end

			charDb.KeyboardEnabled = enabled

			addon:Refresh()
		end,
	})

	kbEnabledChkBox:SetPoint("TOPLEFT", header.Anchor, "BOTTOMLEFT", -4, -verticalSpacing)

	local mouseEnabledChkBox = mini:Checkbox({
		Parent = panel,
		LabelText = "Mouse Enabled",
		Tooltip = "Whether to enable/disable the mouse functionality.",
		GetValue = function()
			return charDb.MouseEnabled
		end,
		SetValue = function(enabled)
			if InCombatLockdown() then
				mini:NotifyCombatLockdown()
				return
			end

			if addon.HasBartender and enabled then
				mini:ShowDialog({
					Text = "Sorry, mouse mode doesn't work with Bartender.",
				})

				return
			end

			charDb.MouseEnabled = enabled

			addon:Refresh()
		end,
	})

	mouseEnabledChkBox:SetPoint("TOPLEFT", kbEnabledChkBox, "TOPLEFT", col2X, 0)

	local keybindingsDivider = mini:Divider({
		Parent = panel,
		Text = "Keybindings",
	})

	keybindingsDivider:SetPoint("TOPLEFT", kbEnabledChkBox, "BOTTOMLEFT", 0, -verticalSpacing)
	keybindingsDivider:SetPoint("RIGHT", panel, "RIGHT", 0, 0)

	local filterModeDropdown = mini:Dropdown({
		Parent = panel,
		LabelText = "Filter Mode",
		Items = FILTER_MODES,
		Width = firstColumnWidth + secondColumnWidth,
		GetValue = function()
			if charDb.InclusionsEnabled then
				return "include"
			end

			if charDb.ExclusionsEnabled then
				return "exclude"
			end

			return "off"
		end,
		SetValue = function(mode)
			charDb.InclusionsEnabled = mode == "include"
			charDb.ExclusionsEnabled = mode == "exclude"

			RefreshFilters()
			addon:Refresh()
		end,
		GetText = function(mode)
			return FILTER_MODE_TEXT[mode]
		end,
	})

	filterModeDropdown.Label:SetPoint("TOPLEFT", keybindingsDivider, "BOTTOMLEFT", 0, -verticalSpacing)

	-- filterModeDropdown's control sits centred on its label and is taller, so anchoring to
	-- the label needs this much extra drop to still clear the control.
	local dropdownClearance = (filterModeDropdown:GetHeight() - filterModeDropdown.Label:GetStringHeight()) / 2

	local offLine = mini:TextLine({
		Parent = panel,
		Text = "Every bound key gets the down and up behaviour.",
		Width = CAPTURE_ZONE_WIDTH,
	})

	offLine:SetPoint("TOPLEFT", filterModeDropdown.Label, "BOTTOMLEFT", 0, -verticalSpacing - dropdownClearance)

	inclusions = CreateFilterList(panel, "Inclusions", "A set of keybindings to include.")
	inclusions.Container:SetPoint("TOPLEFT", filterModeDropdown.Label, "BOTTOMLEFT", 0, -verticalSpacing - dropdownClearance)

	exclusions = CreateFilterList(panel, "Exclusions", "A set of keybindings to exclude.")
	exclusions.Container:SetPoint("TOPLEFT", filterModeDropdown.Label, "BOTTOMLEFT", 0, -verticalSpacing - dropdownClearance)

	RefreshFilters = function()
		local mode = "off"

		if charDb.InclusionsEnabled then
			mode = "include"
		elseif charDb.ExclusionsEnabled then
			mode = "exclude"
		end

		offLine:SetShown(mode == "off")
		inclusions.Container:SetShown(mode == "include")
		exclusions.Container:SetShown(mode == "exclude")

		-- Both lists stay in step with the saved keys even while hidden, so switching a mode
		-- back on never shows chips left over from before a reset.
		inclusions.Refresh()
		exclusions.Refresh()
	end

	panel:SetScript("OnShow", function()
		-- settings may have been changed elsewhere
		panel:MiniRefresh()
		RefreshFilters()
	end)

	RefreshFilters()

	mini:RegisterSlashCommand(category, panel, {
		"/minipressrelease",
		"/minipr",
		"/mpr",
	})
end

---@class FilterList
---@field Container table
---@field Refresh fun()
