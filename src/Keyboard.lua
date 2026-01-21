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

local function HasHousing()
	return type(C_HouseEditor) == "table" and type(C_HouseEditor.IsHouseEditorActive) == "function"
end

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

local function ConfigureButton(buttonName, bindingKey)
	local btn = _G[buttonName]

	if not btn then
		return
	end

	local primaryKey, secondaryKey = GetBindingKey(bindingKey)

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

	if addon.HasBartender then
		local binds = addon.BartenderBinds
		for i = 1, binds.Count do
			local buttonName = binds.Prefix .. i
			local bindKey = string.format("CLICK %s:LeftButton", buttonName)

			ConfigureButton(buttonName, bindKey)
		end
	end

	-- attempt blizzard bindings in any case
	for _, bind in ipairs(addon.BlizzardBinds) do
		for i = 1, maxBarButtons do
			local buttonName = bind.Prefix .. i
			local bindKey = bind.Bind .. i

			ConfigureButton(buttonName, bindKey)
		end
	end
end

function M:Init()
	charDb = mini:GetCharacterSavedVars()

	binderFrame = CreateFrame("Frame")
	eventsFrame = CreateFrame("Frame")

	eventsFrame:RegisterEvent("PLAYER_LOGIN")
	eventsFrame:RegisterEvent("UPDATE_BINDINGS")

	if HasHousing() then
		eventsFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
	end

	eventsFrame:SetScript("OnEvent", OnEvent)

	initialised = true
end
