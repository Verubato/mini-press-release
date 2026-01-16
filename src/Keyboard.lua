---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
---@type CharDb
local charDb
local maxBarButtons = 12
local eventsFrame
local binderFrame
local proxyButtons = {}
local initialised
---@class KeyboardModule
local M = {}
addon.Keyboard = M

local function IsHouseEditorOpen()
	if not C_HouseEditor or not C_HouseEditor.IsHouseEditorActive then
		return false
	end

	return C_HouseEditor.IsHouseEditorActive()
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

	if primaryKey and addon:IsKeyIncluded(primaryKey) then
		SetOverrideBindingClick(binderFrame, true, primaryKey, proxy:GetName())
	end

	if secondaryKey and addon:IsKeyIncluded(secondaryKey) then
		SetOverrideBindingClick(binderFrame, true, secondaryKey, proxy:GetName())
	end

	proxy:SetScript("OnMouseDown", function()
		btn:SetButtonState("PUSHED")
	end)

	proxy:SetScript("OnMouseUp", function()
		btn:SetButtonState("NORMAL")
	end)
end

local function OnEvent()
	if InCombatLockdown() then
		return
	end

	M:Refresh()
end

function M:Refresh()
	if not initialised then
		return
	end

	-- clear previous bindings
	ClearOverrideBindings(binderFrame)

	if not charDb.KeyboardEnabled then
		return
	end

	if IsHouseEditorOpen() then
		-- housing editor shows a new action bar
		-- and if we override keybindings the user won't be able to press 1-5 with the housing action bar
		-- so don't run when the housing edit is open
		return
	end

	for _, bind in ipairs(addon.Binds) do
		for i = 1, maxBarButtons do
			ConfigureButton(bind.Prefix, bind.Bind, i)
		end
	end
end

function M:Init()
	charDb = mini:GetCharacterSavedVars()

	binderFrame = CreateFrame("Frame")
	eventsFrame = CreateFrame("Frame")

	eventsFrame:RegisterEvent("PLAYER_LOGIN")
	eventsFrame:RegisterEvent("UPDATE_BINDINGS")

	-- fired when the action bar changes, e.g. entering a vehicle or housing
	eventsFrame:RegisterEvent("ACTION_BAR_SLOT_CHANGED")
	eventsFrame:SetScript("OnEvent", OnEvent)

	initialised = true
end
