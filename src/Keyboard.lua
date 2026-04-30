local addonName, addon = ...
local mini = addon.Framework

local charDb
local eventsFrame
local initialised

-- Proxy buttons intercept key presses and forward them to the real action buttons,
-- allowing the addon to control bindings without taint.
local proxyButtons = {}

-- Uses SecureHandlerStateTemplate so it can set bindings in combat via secure attribute callbacks.
local binderFrame = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")

-- Runs inside the secure environment (no Lua API access). Reads stored attributes to
-- (re)apply all bindings, choosing the override-bar proxy or normal proxy per key.
local SECURE_APPLY_BINDINGS = [[
	local state = self:GetAttribute("mpr_override_state") or "normal"
	local useOverride = state == "override"
	local count = self:GetAttribute("mpr_count") or 0

	self:ClearBindings()

	for i = 1, count do
		local key = self:GetAttribute("mpr_key" .. i)
		local normal = self:GetAttribute("mpr_normal" .. i)
		local override = self:GetAttribute("mpr_override" .. i)

		if override == "" then
			override = nil
		end

		local btn = normal

		if useOverride and override then
			btn = override
		end

		if key and btn then
			self:SetBindingClick(true, key, btn, "LeftButton")
		end
	end
]]

-- Fired by the state driver when the override bar activates or deactivates.
-- Records the new state then re-applies all bindings so the right proxy is used.
local SECURE_ONSTATE_OVERRIDEBUTTON = [[
	self:SetAttribute("mpr_override_state", newstate)
]] .. SECURE_APPLY_BINDINGS

-- Maps Blizzard binding command prefixes to their action button frame names.
local blizzBindToFrame = {
	ACTIONBUTTON = "ActionButton",
	MULTIACTIONBAR1BUTTON = "MultiBarBottomLeftButton",
	MULTIACTIONBAR2BUTTON = "MultiBarBottomRightButton",
	MULTIACTIONBAR3BUTTON = "MultiBarRightButton",
	MULTIACTIONBAR4BUTTON = "MultiBarLeftButton",
	MULTIACTIONBAR5BUTTON = "MultiBar5Button",
	MULTIACTIONBAR6BUTTON = "MultiBar6Button",
	MULTIACTIONBAR7BUTTON = "MultiBar7Button",
}

local M = {}
addon.Keyboard = M

-- The housing (house editor) API may not exist on all game versions.
local function HasHousing()
	return type(C_HouseEditor) == "table"
		and type(C_HouseEditor.IsHouseEditorActive) == "function"
end

-- Bindings should be suppressed while the house editor is open to avoid conflicts.
local function IsHouseEditorOpen()
	if not HasHousing() then
		return false
	end

	return C_HouseEditor.IsHouseEditorActive()
end

-- Returns a cached SecureActionButton that forwards clicks to the real button.
-- If visualButton is provided, the proxy mirrors its pushed/normal visual state.
local function GetOrCreateProxy(proxyKey, visualButton)
	local proxy = proxyButtons[proxyKey]

	if proxy then
		return proxy
	end

	local name = addonName .. "_" .. proxyKey

	proxy = CreateFrame("Button", name, nil, "SecureActionButtonTemplate")
	proxy:RegisterForClicks("AnyDown", "AnyUp")

	proxy:SetAttribute("type", "click")
	proxy:SetAttribute("typerelease", "click")
	proxy:SetAttribute("pressAndHoldAction", "1")

	if visualButton then
		proxy:SetScript("OnMouseDown", function()
			visualButton:SetButtonState("PUSHED")
		end)

		proxy:SetScript("OnMouseUp", function()
			visualButton:SetButtonState("NORMAL")
		end)

		proxy:SetScript("PostClick", function()
			visualButton:SetButtonState("NORMAL")
		end)
	end

	proxyButtons[proxyKey] = proxy
	return proxy
end

-- Addon action buttons need one-time configuration so the addon's type/typerelease
-- attributes are not overwritten by the secure environment or the button itself.
local function SetupAddonButton(btn)
	if btn._mprConfigured then
		return
	end

	btn._mprConfigured = true

	local actionType = btn._state_type or btn:GetAttribute("type") or "action"

	btn:SetAttribute("mpr_typerelease", actionType)
	btn:SetAttribute("pressAndHoldAction", true)
	btn:SetAttribute("typerelease", actionType)

	-- Guard against other code resetting pressAndHoldAction or typerelease on this button.
	SecureHandlerWrapScript(btn, "OnAttributeChanged", binderFrame,
		[[
			if name == "pressandholdaction" or name == "typerelease" then
				if not self:GetAttribute("pressAndHoldAction") then
					self:SetAttribute("pressAndHoldAction", true)
				end

				local intended = self:GetAttribute("mpr_typerelease")
				if intended and self:GetAttribute("typerelease") ~= intended then
					self:SetAttribute("typerelease", intended)
				end
			end
		]]
	)
end

-- Scans every Blizzard binding and resolves each bound key to an action button name.
-- Returns two tables: all bindings (buttonName -> {keys}), and which buttons are addon buttons.
local function BuildAllBindings()
	local result = {}
	local addonButtons = {}
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
		local isAddonButton = false

		if command:match("^CLICK ") then
			-- Addon button bindings use the format "CLICK FrameName:button".
			btnName = command:match("^CLICK (.-):") or command:match("^CLICK (.-)$")
			isAddonButton = true
		else
			-- Blizzard action bar bindings use the format "ACTIONBUTTONn".
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

		if isAddonButton then
			addonButtons[btnName] = true
		end
	end

	for i = 1, GetNumBindings() do
		local _, _, key1, key2 = GetBinding(i)

		ProcessKey(key1)
		ProcessKey(key2)
	end

	return result, addonButtons
end

local function OnEvent()
	M:Refresh()
end

-- Rebuilds all override bindings. Called on login, binding changes, and combat state changes.
-- Always clears existing override bindings first, even when the feature is disabled,
-- so stale bindings are never left behind.
function M:Refresh()
	if not initialised or InCombatLockdown() then
		return
	end

	ClearOverrideBindings(binderFrame)

	-- Always tear down the state driver so it can't re-apply stale bindings,
	-- regardless of whether the feature is enabled.
	UnregisterStateDriver(binderFrame, "overridebutton")

	binderFrame:SetAttribute("_onstate-overridebutton", nil)
	binderFrame:SetAttribute("mpr_override_state", "normal")
	binderFrame:SetAttribute("mpr_count", 0)

	if not charDb.KeyboardEnabled then
		return
	end

	if IsHouseEditorOpen() then
		return
	end

	local allBindings, addonButtons = BuildAllBindings()
	local bindingIndex = 0

	for buttonName, keys in pairs(allBindings) do
		local btn = _G[buttonName]

		if btn then
			local includedKeys = {}

			for _, key in ipairs(keys) do
				if addon:IsKeyIncluded(key) then
					table.insert(includedKeys, key)
				end
			end

			if #includedKeys > 0 then
				if addonButtons[buttonName] then
					SetupAddonButton(btn)
				end

				local normalProxy = GetOrCreateProxy(buttonName .. "_normal", btn)
				normalProxy:SetAttribute("clickbutton", btn)

				local overrideProxyName = ""

				-- ActionButton1–6 have matching OverrideActionBar buttons that should
				-- be used instead when the override bar (vehicle/possess) is active.
				local actionBtnNum = tonumber(buttonName:match("^ActionButton(%d+)$"))
				local overrideBtn = actionBtnNum and _G["OverrideActionBarButton" .. actionBtnNum]

				if actionBtnNum and actionBtnNum <= 6 and overrideBtn then
					local overrideProxy = GetOrCreateProxy(buttonName .. "_override", overrideBtn)
					overrideProxy:SetAttribute("clickbutton", overrideBtn)
					overrideProxyName = overrideProxy:GetName()
				end

				-- Store each key and its proxy names as numbered attributes so the
				-- secure snippet can read them without direct Lua table access.
				for _, key in ipairs(includedKeys) do
					bindingIndex = bindingIndex + 1

					binderFrame:SetAttribute("mpr_key" .. bindingIndex, key)
					binderFrame:SetAttribute("mpr_normal" .. bindingIndex, normalProxy:GetName())
					binderFrame:SetAttribute("mpr_override" .. bindingIndex, overrideProxyName)
				end
			end
		end
	end

	binderFrame:SetAttribute("mpr_count", bindingIndex)

	if bindingIndex > 0 then
		-- Register the state driver so the secure handler switches proxies automatically
		-- when the player enters or leaves an override bar (vehicle, possess, etc.).
		binderFrame:SetAttribute("_onstate-overridebutton", SECURE_ONSTATE_OVERRIDEBUTTON)
		RegisterStateDriver(binderFrame, "overridebutton", "[overridebar] override; [vehicleui] override; normal")
		binderFrame:Execute(SECURE_APPLY_BINDINGS)
	end
end

function M:Init()
	charDb = mini:GetCharacterSavedVars()

	eventsFrame = CreateFrame("Frame")
	eventsFrame:RegisterEvent("PLAYER_LOGIN")
	eventsFrame:RegisterEvent("UPDATE_BINDINGS")

	if HasHousing() then
		eventsFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
	end

	eventsFrame:SetScript("OnEvent", OnEvent)

	initialised = true
end
