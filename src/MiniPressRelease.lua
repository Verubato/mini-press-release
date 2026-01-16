---@type string, Addon
local _, addon = ...
local mini = addon.Framework
---@type Db
local db

---@class Binds
addon.Binds = {
	{ Prefix = "ActionButton", Bind = "ACTIONBUTTON" },
	{ Prefix = "MultiBarBottomLeftButton", Bind = "MULTIACTIONBAR1BUTTON" },
	{ Prefix = "MultiBarBottomRightButton", Bind = "MULTIACTIONBAR2BUTTON" },
	{ Prefix = "MultiBarRightButton", Bind = "MULTIACTIONBAR3BUTTON" },
	{ Prefix = "MultiBarLeftButton", Bind = "MULTIACTIONBAR4BUTTON" },
	{ Prefix = "MultiBar5Button", Bind = "MULTIACTIONBAR5BUTTON" },
	{ Prefix = "MultiBar6Button", Bind = "MULTIACTIONBAR6BUTTON" },
	{ Prefix = "MultiBar7Button", Bind = "MULTIACTIONBAR7BUTTON" },
}

function addon:IsKeyIncluded(key)
	if db.Inclusions and next(db.Inclusions) then
		return db.Inclusions[key] == true
	end

	return db.Exclusions[key] ~= true
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

	db = mini:GetSavedVars()

	addon.Keyboard:Init()
	addon.Mouse:Init()
end

mini:WaitForAddonLoad(OnAddonLoaded)

---@class Addon
---@field IsKeyIncluded fun(self: table, key: string): boolean
---@field Refresh fun(self: table)
---@field Binds Binds
---@field Framework MiniFramework
---@field Config Config
---@field Mouse MouseModule
---@field Keyboard KeyboardModule
