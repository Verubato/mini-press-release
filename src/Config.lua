---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
local verticalSpacing = mini.VerticalSpacing
local horizontalSpacing = mini.HorizontalSpacing
local rowHeight = 22
local firstColumnWidth = 200
local secondColumnWidth = 100
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

local function CreateCaptureZone(parent, editBoxWidth, buttonWidth, onKeySelected)
	local placeholder = "Click then press a key"
	local container = CreateFrame("Frame", nil, parent)
	local capture = CreateFrame("EditBox", nil, container, "InputBoxTemplate")

	container:SetSize(editBoxWidth + buttonWidth + horizontalSpacing, 30)

	capture:SetSize(editBoxWidth, 30)
	-- InputBoxTemplate has a built-in left inset of 4
	capture:SetPoint("TOPLEFT", container, "TOPLEFT", 4, 0)
	capture:SetAutoFocus(false)
	capture:SetText(placeholder)
	capture:SetCursorPosition(0)
	capture:EnableMouse(true)

	local pendingKey

	local function SetDisplay(text)
		capture:SetText(text or placeholder)
		capture:SetCursorPosition(0)
		capture:HighlightText(0, 0)
	end

	local function SetPendingKey(keyString)
		pendingKey = keyString
		SetDisplay(keyString)
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
		else
			pendingKey = nil
			capture:SetText("")
			capture:SetCursorPosition(0)
			capture:HighlightText(0, 0)
		end
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

	local addBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
	addBtn:SetSize(buttonWidth, 26)
	addBtn:SetPoint("LEFT", capture, "RIGHT", horizontalSpacing - 4, 0)
	addBtn:SetText("Add")

	addBtn:SetScript("OnClick", function()
		if not pendingKey then
			return
		end

		onKeySelected(pendingKey)
		SetPendingKey(nil)
		capture:ClearFocus()
	end)

	return container
end

local function CreateInclusions(parent)
	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(firstColumnWidth + secondColumnWidth + horizontalSpacing * 2, 400)

	local description = mini:TextLine({
		Parent = container,
		Text = "A set of keybindings to include.",
	})

	description:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

	local list = mini:List({
		Parent = container,
		RowWidth = firstColumnWidth + secondColumnWidth + horizontalSpacing,
		RowHeight = rowHeight,
		RemoveButtonWidth = secondColumnWidth,
		OnRemove = function(key)
			charDb.Inclusions[key] = nil
			addon:Refresh()
		end,
	})

	local capture = CreateCaptureZone(container, firstColumnWidth, secondColumnWidth, function(keyString)
		charDb.Inclusions = charDb.Inclusions or {}
		charDb.Inclusions[keyString] = true

		local keys = {}
		for k in pairs(charDb.Inclusions) do
			table.insert(keys, k)
		end

		list:SetItems(keys)
		addon:Refresh()
	end)

	capture:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -verticalSpacing / 2)

	list.ScrollFrame:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 0, -verticalSpacing)

	local keys = {}
	for k in pairs(charDb.Inclusions) do
		table.insert(keys, k)
	end

	list:SetItems(keys)

	return container
end

local function CreateExclusions(parent)
	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(firstColumnWidth + secondColumnWidth + horizontalSpacing * 2, 400)

	local description = mini:TextLine({
		Parent = container,
		Text = "A set of keybindings to exclude.",
	})

	description:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

	local list = mini:List({
		Parent = container,
		RowWidth = firstColumnWidth + secondColumnWidth + horizontalSpacing,
		RowHeight = rowHeight,
		RemoveButtonWidth = secondColumnWidth,
		OnRemove = function(key)
			charDb.Exclusions[key] = nil
			addon:Refresh()
		end,
	})

	local capture = CreateCaptureZone(container, firstColumnWidth, secondColumnWidth, function(keyString)
		charDb.Exclusions = charDb.Exclusions or {}
		charDb.Exclusions[keyString] = true

		local keys = {}
		for k in pairs(charDb.Exclusions) do
			table.insert(keys, k)
		end

		list:SetItems(keys)
		addon:Refresh()
	end)

	capture:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -verticalSpacing / 2)

	list.ScrollFrame:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 0, -verticalSpacing)

	local keys = {}
	for k in pairs(charDb.Exclusions) do
		table.insert(keys, k)
	end

	list:SetItems(keys)

	return container
end

function M:Init()
	charDb = mini:GetCharacterSavedVars(charDbDefaults)

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	local col2X = firstColumnWidth + horizontalSpacing
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, -verticalSpacing)
	title:SetText(string.format("%s - %s", addonName, version))

	local description = mini:TextLine({
		Parent = panel,
		Text = "Increase your chance at landing spells.",
	})

	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

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

	kbEnabledChkBox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", -4, -verticalSpacing)

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

	local inclusions = CreateInclusions(panel)
	local exclusions = CreateExclusions(panel)

	local function RefreshFilters()
		if charDb.InclusionsEnabled then
			inclusions:Show()
		else
			inclusions:Hide()
		end

		if charDb.ExclusionsEnabled then
			exclusions:Show()
		else
			exclusions:Hide()
		end

		addon:Refresh()
	end

	local exclusionsEnabled
	local inclusionsEnabled

	inclusionsEnabled = mini:Checkbox({
		Parent = panel,
		LabelText = "Include Mode",
		GetValue = function()
			return charDb.InclusionsEnabled
		end,
		SetValue = function(value)
			charDb.InclusionsEnabled = value

			if value then
				charDb.ExclusionsEnabled = false
				exclusionsEnabled:MiniRefresh()
			end

			RefreshFilters()
		end,
	})

	inclusionsEnabled:SetPoint("TOPLEFT", kbEnabledChkBox, "BOTTOMLEFT", 0, -verticalSpacing / 2)

	exclusionsEnabled = mini:Checkbox({
		Parent = panel,
		LabelText = "Exclude Mode",
		GetValue = function()
			return charDb.ExclusionsEnabled
		end,
		SetValue = function(value)
			charDb.ExclusionsEnabled = value

			if value then
				charDb.InclusionsEnabled = false
				inclusionsEnabled:MiniRefresh()
			end

			RefreshFilters()
		end,
	})

	exclusionsEnabled:SetPoint("TOPLEFT", inclusionsEnabled, "TOPLEFT", col2X, 0)
	inclusions:SetPoint("TOPLEFT", inclusionsEnabled, "BOTTOMLEFT", 4, -verticalSpacing / 2)
	exclusions:SetPoint("TOPLEFT", inclusionsEnabled, "BOTTOMLEFT", 4, -verticalSpacing / 2)

	panel:SetScript("OnShow", function()
		-- settings may have been changed elsewhere
		panel:MiniRefresh()
	end)

	RefreshFilters()

	mini:RegisterSlashCommand(category, panel, {
		"/minipressrelease",
		"/minipr",
		"/mpr",
	})
end
