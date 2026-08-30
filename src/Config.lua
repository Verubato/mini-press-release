---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
local verticalSpacing = mini.VerticalSpacing
local horizontalSpacing = mini.HorizontalSpacing
local rowHeight = 22
local firstColumnWidth = 200
local secondColumnWidth = 100
local CAPTURE_BOX_WIDTH = 180
local CAPTURE_BUTTON_WIDTH = 70
local CAPTURE_GAP = 10
-- The flattened field's border draws 6px left of the box's own frame.
local CAPTURE_FIELD_INSET = 6
-- The capture zone and the list rows share a right edge.
local LIST_ROW_WIDTH = CAPTURE_FIELD_INSET + CAPTURE_BOX_WIDTH + CAPTURE_GAP + CAPTURE_BUTTON_WIDTH
local REMOVE_BUTTON_WIDTH = 70
local CAPTURE_HEIGHT = 30
local MAX_VISIBLE_ROWS = 10
-- mini:List leaves a 2px styled gap between rows.
local LIST_ROW_STEP = rowHeight + 2
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

	container:SetSize(LIST_ROW_WIDTH, CAPTURE_HEIGHT)

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
	-- Height is set by Resize, which is the only thing that knows how many rows there are.
	container:SetWidth(LIST_ROW_WIDTH)

	local descriptionLine = mini:TextLine({
		Parent = container,
		Text = description,
		Width = LIST_ROW_WIDTH,
	})

	descriptionLine:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

	local list = mini:List({
		Parent = container,
		RowWidth = LIST_ROW_WIDTH,
		RowHeight = rowHeight,
		RemoveButtonWidth = REMOVE_BUTTON_WIDTH,
		OnRemove = function(key)
			charDb[dbKey][key] = nil
			addon:Refresh()
		end,
	})

	local capture = CreateCaptureZone(container, function(keyString)
		charDb[dbKey] = charDb[dbKey] or {}
		charDb[dbKey][keyString] = true

		list:SetItems(CollectKeys(charDb[dbKey]))
		addon:Refresh()
	end)

	capture:SetPoint("TOPLEFT", descriptionLine, "BOTTOMLEFT", 0, -verticalSpacing / 2)
	list.ScrollFrame:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 0, -verticalSpacing)

	local emptyLine = mini:TextLine({
		Parent = container,
		Text = "No keys added yet.",
		Width = LIST_ROW_WIDTH,
	})

	emptyLine:SetPoint("TOPLEFT", list.ScrollFrame, "TOPLEFT", 0, 0)

	-- Sizing the container sizes the list viewport, because mini:List pins its scroll frame to
	-- the container's bottom right.
	local function Resize()
		local body = next(charDb[dbKey]) == nil
			and emptyLine:GetStringHeight()
			or math.min(list.Content:GetHeight(), MAX_VISIBLE_ROWS * LIST_ROW_STEP)

		container:SetHeight(descriptionLine:GetStringHeight()
			+ verticalSpacing / 2
			+ CAPTURE_HEIGHT
			+ verticalSpacing
			+ body)
	end

	local function Refresh()
		list:SetItems(CollectKeys(charDb[dbKey]))

		local empty = next(charDb[dbKey]) == nil
		emptyLine:SetShown(empty)
		list.ScrollFrame:SetShown(not empty)

		Resize()
	end

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

	local offLine = mini:TextLine({
		Parent = panel,
		Text = "Every bound key gets the down and up behaviour.",
		Width = LIST_ROW_WIDTH,
	})

	-- A dropdown is taller than its label and sits centred on it, so the body below clears
	-- the control rather than the label.
	offLine:SetPoint("TOPLEFT", filterModeDropdown, "BOTTOMLEFT", 0, -verticalSpacing)

	inclusions = CreateFilterList(panel, "Inclusions", "A set of keybindings to include.")
	inclusions.Container:SetPoint("TOPLEFT", filterModeDropdown, "BOTTOMLEFT", 0, -verticalSpacing)

	exclusions = CreateFilterList(panel, "Exclusions", "A set of keybindings to exclude.")
	exclusions.Container:SetPoint("TOPLEFT", filterModeDropdown, "BOTTOMLEFT", 0, -verticalSpacing)

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
		-- back on never shows rows left over from before a reset.
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
