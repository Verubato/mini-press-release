---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
local verticalSpacing = mini.VerticalSpacing
local horizontalSpacing = mini.VerticalSpacing
---@type Db
local db
---@class Db
local dbDefaults = {
	Version = 2,
	KeyboardEnabled = true,
	MouseEnabled = true,
	Exclusions = {},
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

local function CreateExclusions(parent)
	local rowHeight = 22
	local buttonWidth = 80
	local firstColumnWidth = 200
	local secondColumnWidth = buttonWidth
	local placeholder = "Click then press a key"

	local frame = CreateFrame("Frame", nil, parent)
	-- + 40 for the scroll bar itself
	frame:SetSize(firstColumnWidth + secondColumnWidth + horizontalSpacing * 2 + 40, 400)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetText("Excluded Bindings")

	local capture = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	capture:SetSize(firstColumnWidth, 30)
	capture:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -verticalSpacing)
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

	local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	addBtn:SetSize(buttonWidth, 26)
	addBtn:SetPoint("LEFT", capture, "RIGHT", horizontalSpacing, 0)
	addBtn:SetText("Add")

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 0, -verticalSpacing)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local rows = {}

	local function GetSortedExclusions()
		local keys = {}
		for k in pairs(db.Exclusions or {}) do
			table.insert(keys, k)
		end
		table.sort(keys)
		return keys
	end

	local function RefreshList()
		for _, row in ipairs(rows) do
			row:Hide()
		end

		local keys = GetSortedExclusions()
		local y = -2

		for i, key in ipairs(keys) do
			local row = rows[i]

			if not row then
				row = CreateFrame("Button", nil, content)
				row:SetSize(firstColumnWidth + secondColumnWidth + horizontalSpacing, rowHeight)

				row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				row.Text:SetPoint("LEFT", 0, 0)

				row.Remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
				row.Remove:SetSize(buttonWidth, rowHeight - 2)
				row.Remove:SetPoint("RIGHT", 0, 0)
				row.Remove:SetText("Remove")

				rows[i] = row
			end

			row:SetPoint("TOPLEFT", 0, y)
			row.Text:SetText(key)
			row:Show()

			row.Remove:SetScript("OnClick", function()
				db.Exclusions[key] = nil
				RefreshList()
				addon:Refresh()
			end)

			y = y - rowHeight
		end

		-- Expand content height for scroll
		content:SetHeight(math.max(1, -y + 10))
	end

	addBtn:SetScript("OnClick", function()
		if not pendingKey then
			return
		end

		db.Exclusions = db.Exclusions or {}
		db.Exclusions[pendingKey] = true

		SetPendingKey(nil)
		RefreshList()

		addon:Refresh()
	end)

	RefreshList()

	return frame
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

	local description = panel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetText("Increase your chance at landing spells.")

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

	local exclusions = CreateExclusions(panel)

	exclusions:SetPoint("TOP", kbEnabledChkBox, "BOTTOM", 0, -verticalSpacing)
	exclusions:SetPoint("LEFT", title, "LEFT", 0, 0)

	mini:RegisterSlashCommand(category, panel, {
		"/minipr",
		"/mpr",
	})
end
