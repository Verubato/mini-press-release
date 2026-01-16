---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
local verticalSpacing = mini.VerticalSpacing
local horizontalSpacing = mini.HorizontalSpacing
local rowHeight = 22
local firstColumnWidth = 200
local secondColumnWidth = 80
---@type Db
local db
---@class Db
local dbDefaults = {
	Version = 2,
	KeyboardEnabled = true,
	MouseEnabled = true,
	Exclusions = {},
	Inclusions = {},
}
---@class Config
local M = {
	DbDefaults = dbDefaults,
}
addon.Config = M

local function GetAndUpgradeDb()
	local vars = mini:GetSavedVars(dbDefaults)

	while vars.Version ~= dbDefaults.Version do
		if not vars.Version or vars.Version == 1 then
			vars.KeyboardEnabled = vars.Enabled
			vars.MouseEnabled = vars.Enabled

			vars.Version = 2
		end
	end

	return vars
end

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
	-- for some reason the edit box is off by 4 units
	capture:SetPoint("TOPLEFT", container, "TOPLEFT", 4, 0)
	capture:SetAutoFocus(false)
	capture:SetText(placeholder)
	capture:SetCursorPosition(0)
	capture:EnableMouse(true)

	local pendingKey

	local function SetPendingKey(keyString)
		pendingKey = keyString

		if keyString then
			capture:SetText(keyString)
		else
			capture:SetText(placeholder)
		end

		capture:SetCursorPosition(0)
	end

	capture:SetScript("OnEditFocusGained", function()
		capture:SetText("")
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
		end
	end)

	capture:SetScript("OnKeyUp", function()
		if pendingKey then
			capture:SetText(pendingKey)
		else
			capture:SetText(placeholder)
		end
	end)

	capture:SetScript("OnMouseDown", function(_, button)
		if not button then
			return
		end

		-- exclude left as it's used to focus the box.
		if button == "LeftButton" then
			return
		end

		local normalised = NormaliseBindingKey(button)

		if normalised then
			SetPendingKey(normalised)
		end
	end)

	local addBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
	addBtn:SetSize(buttonWidth, 26)
	addBtn:SetPoint("LEFT", capture, "RIGHT", horizontalSpacing, 0)
	addBtn:SetText("Add")

	addBtn:SetScript("OnClick", function()
		if not pendingKey then
			return
		end

		onKeySelected(pendingKey)
		SetPendingKey(nil)
	end)

	return container
end

local function CreateInclusions(parent)
	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(firstColumnWidth + secondColumnWidth + horizontalSpacing * 2, 200)

	local description = mini:TextBlock({
		Parent = container,
		Lines = {
			"A set of keybindings to include.",
			"Note if you set both inclusions and exclusions, then only inclusions will be used.",
		},
	})

	description:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

	local list = mini:List({
		Parent = container,
		RowWidth = firstColumnWidth + secondColumnWidth + horizontalSpacing,
		RowHeight = rowHeight,
		OnRemove = function(key)
			db.Inclusions[key] = nil
			addon:Refresh()
		end,
	})

	local capture = CreateCaptureZone(container, firstColumnWidth, secondColumnWidth, function(keyString)
		db.Inclusions = db.Inclusions or {}
		db.Inclusions[keyString] = true

		local keys = {}
		for k in pairs(db.Inclusions) do
			table.insert(keys, k)
		end

		list:SetItems(keys)
		addon:Refresh()
	end)

	capture:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -verticalSpacing / 2)

	list.ScrollFrame:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 4, -verticalSpacing)

	local keys = {}
	for k in pairs(db.Inclusions) do
		table.insert(keys, k)
	end

	list:SetItems(keys)

	return container
end

local function CreateExclusions(parent)
	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(firstColumnWidth + secondColumnWidth + horizontalSpacing * 2, 200)

	local description = mini:TextLine({
		Parent = container,
		Text = "A set of keybindings to exclude.",
	})

	description:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

	local list = mini:List({
		Parent = container,
		RowWidth = firstColumnWidth + secondColumnWidth + horizontalSpacing,
		RowHeight = rowHeight,
		OnRemove = function(key)
			db.Exclusions[key] = nil
			addon:Refresh()
		end,
	})

	local capture = CreateCaptureZone(container, firstColumnWidth, secondColumnWidth, function(keyString)
		db.Exclusions = db.Exclusions or {}
		db.Exclusions[keyString] = true

		local keys = {}
		for k in pairs(db.Exclusions) do
			table.insert(keys, k)
		end

		list:SetItems(keys)
		addon:Refresh()
	end)

	capture:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -verticalSpacing / 2)

	list.ScrollFrame:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 4, -verticalSpacing)

	local keys = {}
	for k in pairs(db.Exclusions) do
		table.insert(keys, k)
	end

	list:SetItems(keys)

	return container
end

function M:Init()
	db = GetAndUpgradeDb()

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

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
			return db.KeyboardEnabled
		end,
		SetValue = function(enabled)
			if InCombatLockdown() then
				mini:NotifyCombatLockdown()
				return
			end

			db.KeyboardEnabled = enabled

			addon:Refresh()
		end,
	})

	kbEnabledChkBox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -verticalSpacing)

	local mouseEnabledChkBox = mini:Checkbox({
		Parent = panel,
		LabelText = "Mouse Enabled",
		Tooltip = "Whether to enable/disable the mouse functionality.",
		GetValue = function()
			return db.MouseEnabled
		end,
		SetValue = function(enabled)
			if InCombatLockdown() then
				mini:NotifyCombatLockdown()
				return
			end

			db.MouseEnabled = enabled

			addon:Refresh()
		end,
	})

	mouseEnabledChkBox:SetPoint("LEFT", kbEnabledChkBox.Text, "RIGHT", horizontalSpacing, 0)

	local inclusionsDivider = mini:Divider({
		Text = "Inclusions",
		Parent = panel,
	})

	inclusionsDivider:SetPoint("TOP", mouseEnabledChkBox, "BOTTOM", 0, -verticalSpacing)
	inclusionsDivider:SetPoint("LEFT", panel, "LEFT", 0, 0)
	inclusionsDivider:SetPoint("RIGHT", panel, "RIGHT", -horizontalSpacing, 0)

	local inclusions = CreateInclusions(panel)

	inclusions:SetPoint("TOPLEFT", inclusionsDivider, "BOTTOMLEFT", 0, -verticalSpacing / 2)

	local exclusionsDivider = mini:Divider({
		Text = "Exclusions",
		Parent = panel,
	})

	exclusionsDivider:SetPoint("TOP", inclusions, "BOTTOM", 0, -verticalSpacing)
	exclusionsDivider:SetPoint("LEFT", panel, "LEFT", 0, 0)
	exclusionsDivider:SetPoint("RIGHT", panel, "RIGHT", -horizontalSpacing, 0)

	local exclusions = CreateExclusions(panel)

	exclusions:SetPoint("TOPLEFT", exclusionsDivider, "BOTTOMLEFT", 0, -verticalSpacing / 2)

	mini:RegisterSlashCommand(category, panel, {
		"/minipr",
		"/mpr",
	})
end
