---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
---@type CharDb
local charDb
local maxBarButtons = 12
local eventsFrame
local binderFrame
local proxyButtons = {}
local secureHeader = CreateFrame("Frame", nil, nil, "SecureHandlerBaseTemplate")
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

-- Patches a Bartender4 button so it fires when our proxy sends a down=false click.
-- Bartender4 registers its secondary bar buttons for AnyDown only, so they silently
-- drop the down=false programmatic click that our proxy forwards.  Setting typerelease
-- makes the button also respond to AnyUp (down=false) events.
-- SecureHandlerWrapScript keeps Bartender4 from stripping the attribute later.
local function SetupBartenderButton(btn)
	if btn._mprConfigured then
		return
	end
	btn._mprConfigured = true

	local actionType = btn._state_type or btn:GetAttribute("type") or "action"
	btn:SetAttribute("pressAndHoldAction", true)
	btn:SetAttribute("typerelease", actionType)

	SecureHandlerWrapScript(
		btn,
		"OnAttributeChanged",
		secureHeader,
		[[
		if name == "pressandholdaction" then
			if not self:GetAttribute("pressAndHoldAction") then
				self:SetAttribute("pressAndHoldAction", true)
				self:SetAttribute("typerelease", self:GetAttribute("type") or "action")
			end
		end
		]]
	)
end

local function ConfigureButton(buttonName, bindingKey, actionSlot)
	local btn = _G[buttonName]

	if not btn then
		return
	end

	local primaryKey, secondaryKey = GetBindingKey(bindingKey)

	if not primaryKey and not secondaryKey then
		return
	end

	if type(actionSlot) == "number" then
		SetupBartenderButton(btn)
	end

	local proxy = GetOrCreateProxy(buttonName)
	proxy:SetAttribute("type", "click")
	proxy:SetAttribute("typerelease", "click")
	proxy:SetAttribute("clickbutton", btn)

	proxy:SetScript("OnMouseDown", function()
		btn:SetButtonState("PUSHED")
	end)

	proxy:SetScript("OnMouseUp", function()
		btn:SetButtonState("NORMAL")
	end)

	if primaryKey and addon:IsKeyIncluded(primaryKey) then
		SetOverrideBindingClick(binderFrame, true, primaryKey, proxy:GetName())
	end

	if secondaryKey and addon:IsKeyIncluded(secondaryKey) then
		SetOverrideBindingClick(binderFrame, true, secondaryKey, proxy:GetName())
	end
end

-- Builds a map of BT4 button name → {key, ...} by resolving every registered
-- binding through C_KeyBindings.GetBindingByKey, which (unlike GetBindingKey)
-- can see override bindings that Bartender4 sets via SetOverrideBindingClick.
local function BuildBartenderBindings()
	local result = {}
	local seen = {}

	local function ProcessKey(key)
		if not key or seen[key] then
			return
		end
		seen[key] = true

		local command = C_KeyBindings.GetBindingByKey(key)
		if not command then
			return
		end

		-- Only interested in CLICK overrides targeting BT4 buttons,
		-- e.g. "CLICK BT4Button27:LeftButton"
		local btnName = command:match("^CLICK (BT4Button%d+):")
		if not btnName then
			return
		end

		result[btnName] = result[btnName] or {}
		table.insert(result[btnName], key)
	end

	for i = 1, GetNumBindings() do
		local _, _, key1, key2 = GetBinding(i)
		ProcessKey(key1)
		ProcessKey(key2)
	end

	return result
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

	-- Snapshot BT4 bindings now, before the Blizzard section sets any override
	-- bindings on binderFrame.  C_KeyBindings.GetBindingByKey sees the last
	-- SetOverrideBindingClick winner for a key; if we let the Blizzard pass run
	-- first it would shadow BT4's override bindings and BuildBartenderBindings
	-- would find nothing for shared keys.
	local bt4Bindings = addon.HasBartender and BuildBartenderBindings() or nil

	-- Process Blizzard bindings first so Bartender4 can override them below
	for _, bind in ipairs(addon.BlizzardBinds) do
		for i = 1, maxBarButtons do
			local buttonName = bind.Prefix .. i
			local bindKey = bind.Bind .. i

			ConfigureButton(buttonName, bindKey)
		end
	end

	-- Bartender4: configure BT4 buttons after the Blizzard pass so that BT4
	-- proxies take priority over any hidden Blizzard buttons sharing the same binding.
	if bt4Bindings then
		for buttonName, keys in pairs(bt4Bindings) do
			local btn = _G[buttonName]
			if btn then
				SetupBartenderButton(btn)

				local proxy = GetOrCreateProxy(buttonName)
				proxy:SetAttribute("type", "click")
				proxy:SetAttribute("typerelease", "click")
				proxy:SetAttribute("clickbutton", btn)

				proxy:SetScript("OnMouseDown", function()
					btn:SetButtonState("PUSHED")
				end)

				proxy:SetScript("OnMouseUp", function()
					btn:SetButtonState("NORMAL")
				end)

				for _, key in ipairs(keys) do
					if addon:IsKeyIncluded(key) then
						SetOverrideBindingClick(binderFrame, true, key, proxy:GetName())
					end
				end
			end
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
