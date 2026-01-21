---@type string, Addon
local _, addon = ...
local mini = addon.Framework
---@type CharDb
local charDb

local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
addon.HasBartender = IsAddOnLoaded("Bartender4")

---@class BlizzardBinds
addon.BlizzardBinds = {
	{ Prefix = "ActionButton", Bind = "ACTIONBUTTON" },
	{ Prefix = "MultiBarBottomLeftButton", Bind = "MULTIACTIONBAR1BUTTON" },
	{ Prefix = "MultiBarBottomRightButton", Bind = "MULTIACTIONBAR2BUTTON" },
	{ Prefix = "MultiBarRightButton", Bind = "MULTIACTIONBAR3BUTTON" },
	{ Prefix = "MultiBarLeftButton", Bind = "MULTIACTIONBAR4BUTTON" },
	{ Prefix = "MultiBar5Button", Bind = "MULTIACTIONBAR5BUTTON" },
	{ Prefix = "MultiBar6Button", Bind = "MULTIACTIONBAR6BUTTON" },
	{ Prefix = "MultiBar7Button", Bind = "MULTIACTIONBAR7BUTTON" },
}

---@class BartenderBinds
addon.BartenderBinds = {
	Prefix = "BT4Button",
	Count = 180,
}

function addon:IsKeyIncluded(key)
	if charDb.InclusionsEnabled then
		return charDb.Inclusions[key] == true
	end

	if charDb.ExclusionsEnabled then
		return charDb.Exclusions[key] ~= true
	end

	return true
end

function addon:Refresh()
	if InCombatLockdown() then
		mini:NotifyCombatLockdown()
		return
	end

	addon.Keyboard:Refresh()
	addon.Mouse:Refresh()
end

local function OnAddonLoaded()
	addon.Config:Init()

	charDb = mini:GetCharacterSavedVars()

	addon.Keyboard:Init()
	addon.Mouse:Init()
end

mini:WaitForAddonLoad(OnAddonLoaded)

---@class Addon
---@field HasBartender boolean
---@field IsKeyIncluded fun(self: table, key: string): boolean
---@field Refresh fun(self: table)
---@field BlizzardBinds BlizzardBinds
---@field BartenderBinds BartenderBinds
---@field Framework MiniFramework
---@field Config Config
---@field Mouse MouseModule
---@field Keyboard KeyboardModule
