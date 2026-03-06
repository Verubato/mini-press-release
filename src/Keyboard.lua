---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
---@type CharDb
local charDb
local eventsFrame
local binderFrame
local proxyButtons = {}
local secureHeader = CreateFrame("Frame", nil, nil, "SecureHandlerBaseTemplate")
local initialised

-- Maps Blizzard binding-name prefixes to their action frame-name prefixes,
-- e.g. C_KeyBindings.GetBindingByKey returns "MULTIACTIONBAR1BUTTON3" which
-- resolves to frame "MultiBarBottomLeftButton3".
local blizzBindToFrame = {
	ACTIONBUTTON          = "ActionButton",
	MULTIACTIONBAR1BUTTON = "MultiBarBottomLeftButton",
	MULTIACTIONBAR2BUTTON = "MultiBarBottomRightButton",
	MULTIACTIONBAR3BUTTON = "MultiBarRightButton",
	MULTIACTIONBAR4BUTTON = "MultiBarLeftButton",
	MULTIACTIONBAR5BUTTON = "MultiBar5Button",
	MULTIACTIONBAR6BUTTON = "MultiBar6Button",
	MULTIACTIONBAR7BUTTON = "MultiBar7Button",
}

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

-- Builds a map of action-frame name → {key, ...} for all action bar buttons by
-- resolving every registered binding key through C_KeyBindings.GetBindingByKey,
-- which (unlike GetBindingKey) sees override bindings set by addons like Bartender4.
local function BuildAllBindings()
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

		local btnName
		if command:match("^CLICK ") then
			-- Override binding: "CLICK BT4Button27:LeftButton" → "BT4Button27"
			btnName = command:match("^CLICK (.-):") or command:match("^CLICK (.-)$")
		else
			-- Registered binding: "MULTIACTIONBAR1BUTTON3" → "MultiBarBottomLeftButton3"
			local base, id = command:match("^(.-)(%d+)$")
			if base and id then
				local frame = blizzBindToFrame[base:upper()]
				if frame then
					btnName = frame .. id
				end
			end
		end

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

local function OnEvent(_, event)
	if InCombatLockdown() then
		return
	end

	print("Received event: " .. event)
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

	if C_ActionBar and C_ActionBar.HasVehicleActionBar and C_ActionBar.HasVehicleActionBar() then
		-- vehicle action bar shown
		return
	end

	-- Build the full binding map before setting any overrides of our own, so that
	-- C_KeyBindings.GetBindingByKey resolves addon overrides (e.g. Bartender4) correctly.
	local allBindings = BuildAllBindings()

	for buttonName, keys in pairs(allBindings) do
		local btn = _G[buttonName]
		if btn then
			-- Filter to included keys first.  SetupBartenderButton patches the
			-- button to fire on release, so we must not call it when every key
			-- for that button is excluded.
			local includedKeys = {}
			for _, key in ipairs(keys) do
				if addon:IsKeyIncluded(key) then
					table.insert(includedKeys, key)
				end
			end

			if #includedKeys > 0 then
				if buttonName:match("^BT4Button%d+$") then
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

				for _, key in ipairs(includedKeys) do
					SetOverrideBindingClick(binderFrame, true, key, proxy:GetName())
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
	eventsFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
	eventsFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")

	if HasHousing() then
		eventsFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
	end

	eventsFrame:SetScript("OnEvent", OnEvent)

	initialised = true
end
