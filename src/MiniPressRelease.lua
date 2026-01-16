local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework
---@type Db
local db
local maxBarButtons = 12
local eventsFrame
local bars = {
	{ Prefix = "ActionButton", Bind = "ACTIONBUTTON" },
	{ Prefix = "MultiBarBottomLeftButton", Bind = "MULTIACTIONBAR1BUTTON" },
	{ Prefix = "MultiBarBottomRightButton", Bind = "MULTIACTIONBAR2BUTTON" },
	{ Prefix = "MultiBarRightButton", Bind = "MULTIACTIONBAR3BUTTON" },
	{ Prefix = "MultiBarLeftButton", Bind = "MULTIACTIONBAR4BUTTON" },
	{ Prefix = "MultiBar5Button", Bind = "MULTIACTIONBAR5BUTTON" },
	{ Prefix = "MultiBar6Button", Bind = "MULTIACTIONBAR6BUTTON" },
	{ Prefix = "MultiBar7Button", Bind = "MULTIACTIONBAR7BUTTON" },
}
local binderFrame
local proxyButtons = {}

local function IsExcludedKey(key)
	if not db.Exclusions then
		return
	end

	return db.Exclusions[key] == true
end

local function GetOrCreateProxy(buttonName)
	local proxy = proxyButtons[buttonName]

	if proxy then
		return proxy
	end

	local name = addonName .. "_" .. buttonName

	proxy = CreateFrame("Button", name, nil, "SecureActionButtonTemplate")
	proxy:RegisterForClicks("AnyDown", "AnyUp")
	proxy:SetAttribute("type", "click")
	proxy:SetAttribute("typerelease", "click")
	proxy:SetAttribute("pressAndHoldAction", "1")

	proxyButtons[buttonName] = proxy
	return proxy
end

local function ConfigureButton(prefix, bindPrefix, id)
	local buttonName = prefix .. id
	local btn = _G[buttonName]

	if not btn then
		return
	end

	local bindingAction = bindPrefix .. id
	local primaryKey, secondaryKey = GetBindingKey(bindingAction)

	if not primaryKey and not secondaryKey then
		return
	end

	local proxy = GetOrCreateProxy(buttonName)
	proxy:SetAttribute("clickbutton", btn)

	if primaryKey and not IsExcludedKey(primaryKey) then
		SetOverrideBindingClick(binderFrame, true, primaryKey, proxy:GetName())
	end

	if secondaryKey and not IsExcludedKey(secondaryKey) then
		SetOverrideBindingClick(binderFrame, true, secondaryKey, proxy:GetName())
	end
end

function addon:Refresh()
	if InCombatLockdown() then
		mini:NotifyCombatLockdown()
		return
	end

	-- clear previous bindings
	ClearOverrideBindings(binderFrame)

	if not db.Enabled then
		return
	end

	for _, bar in ipairs(bars) do
		for i = 1, maxBarButtons do
			ConfigureButton(bar.Prefix, bar.Bind, i)
		end
	end
end

local function OnAddonLoaded()
	addon.Config:Init()

	db = mini:GetSavedVars()

	binderFrame = CreateFrame("Frame")

	eventsFrame = CreateFrame("Frame")
	eventsFrame:RegisterEvent("PLAYER_LOGIN")
	eventsFrame:RegisterEvent("UPDATE_BINDINGS")

	eventsFrame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" then
			-- bindings should have been loaded by now, apply our overrides
			addon:Refresh()
		elseif event == "UPDATE_BINDINGS" then
			-- user has updated a keybinding, re-apply overrides
			addon:Refresh()
		end
	end)
end

mini:WaitForAddonLoad(OnAddonLoaded)
