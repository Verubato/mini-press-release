local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework
---@type Db
local db
---@class Db
local dbDefaults = {
	Enabled = true,
}
local M = {
	DbDefaults = dbDefaults,
}
addon.Config = M

function M:Init()
	db = mini:GetSavedVars(dbDefaults)

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	local verticalSpacing = mini.VerticalSpacing
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, -verticalSpacing)
	title:SetText(string.format("%s - %s", addonName, version))

	local description = panel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetText("Increase your chance at landing spells.")

	local enabledChkBox = mini:Checkbox({
		Parent = panel,
		LabelText = "Enabled",
		Tooltip = "Whether to enable/disable the addon functionality.",
		GetValue = function()
			return db.Enabled
		end,
		SetValue = function(enabled)
			if InCombatLockdown() then
				mini:NotifyCombatLockdown()
				return
			end

			db.Enabled = enabled

			addon:Run()
		end,
	})

	enabledChkBox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -verticalSpacing)

	mini:RegisterSlashCommand(category, panel, {
		"/miniahk",
		"/mahk",
	})
end
