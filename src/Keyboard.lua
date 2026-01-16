---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
---@type Db
local db
local maxBarButtons = 12
local eventsFrame
local binderFrame
local proxyButtons = {}
---@class KeyboardModule
local M = {}
addon.Keyboard = M

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

	if primaryKey and addon:IsKeyIncluded(primaryKey) then
		SetOverrideBindingClick(binderFrame, true, primaryKey, proxy:GetName())
	end

	if secondaryKey and addon:IsKeyIncluded(secondaryKey) then
		SetOverrideBindingClick(binderFrame, true, secondaryKey, proxy:GetName())
	end
end

local function OnEvent()
	if InCombatLockdown() then
		return
	end

	M:Refresh()
end

function M:Refresh()
	-- clear previous bindings
	ClearOverrideBindings(binderFrame)

	if not db.KeyboardEnabled then
		return
	end

	for _, bind in ipairs(addon.Binds) do
		for i = 1, maxBarButtons do
			ConfigureButton(bind.Prefix, bind.Bind, i)
		end
	end
end

function M:Init()
	db = mini:GetSavedVars()

	binderFrame = CreateFrame("Frame")
	eventsFrame = CreateFrame("Frame")

	eventsFrame:RegisterEvent("PLAYER_LOGIN")
	eventsFrame:RegisterEvent("UPDATE_BINDINGS")
	eventsFrame:SetScript("OnEvent", OnEvent)
end
