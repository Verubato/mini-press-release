local addonName, addon = ...
local mini = addon.Framework

local charDb
local eventsFrame
local initialised

-- Proxy buttons intercept key presses and forward them to the real action buttons,
-- allowing the addon to control bindings without taint.
local proxyButtons = {}

-- Attribute names are the same every refresh, so build each one once instead of
-- concatenating a fresh string per binding and handing the collector the garbage.
local attributeNames = { key = {}, normal = {}, override = {} }

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

---@class Keyboard
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
local function GetOrCreateProxy(proxyKey, visualButton, override)
	local proxy = proxyButtons[proxyKey]

	if proxy then
		return proxy
	end

	local name = addonName .. "_" .. proxyKey

	proxy = CreateFrame("Button", name, nil, "SecureActionButtonTemplate")
	proxy:RegisterForClicks("AnyDown", "AnyUp")

	proxy:SetAttribute("type", "click")

	if not override then
		proxy:SetAttribute("typerelease", "click")
		proxy:SetAttribute("pressAndHoldAction", true)
	end

	if visualButton then
		proxy:SetScript("OnMouseDown", function()
			visualButton:SetButtonState("PUSHED")
		end)

		proxy:SetScript("OnMouseUp", function()
			visualButton:SetButtonState("NORMAL")
		end)

		-- Only reset on key-up (down=false). When an action fails (e.g. spell on cooldown),
		-- pressAndHoldAction does not defer PostClick, so it fires immediately on key-down
		-- and would kill the PUSHED state before it's visible.
		proxy:SetScript("PostClick", function(_, _, down)
			if not down then
				visualButton:SetButtonState("NORMAL")
			end
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

-- Resolves a binding command to the action button frame name it drives, plus whether that
-- button belongs to an addon. Returns nil for commands that aren't action buttons at all.
local function ResolveCommand(command)
	if not command then
		return nil
	end

	if command:find("^CLICK ") then
		-- Addon button bindings use the format "CLICK FrameName:button".
		local name = command:match("^CLICK (.-):") or command:match("^CLICK (.-)$")

		-- A malformed "CLICK :LeftButton" captures an empty name, which is truthy.
		if not name or name == "" then
			return nil
		end

		return name, true
	end

	-- Blizzard action bar bindings use the format "ACTIONBUTTONn".
	local base, id = command:match("^(.-)(%d+)$")

	if not base then
		return nil
	end

	local frame = blizzBindToFrame[base:upper()]

	if not frame then
		return nil
	end

	return frame .. id, false
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

		-- A key can be listed under one command yet owned by another, so ask which
		-- command actually holds it rather than trusting the entry we came from.
		local btnName, isAddonButton = ResolveCommand(C_KeyBindings.GetBindingByKey(key))

		if not btnName then
			return
		end

		result[btnName] = result[btnName] or {}
		table.insert(result[btnName], key)

		if isAddonButton then
			addonButtons[btnName] = true
		end
	end

	local function ProcessKeys(...)
		for k = 1, select("#", ...) do
			ProcessKey((select(k, ...)))
		end
	end

	for i = 1, GetNumBindings() do
		local command = GetBinding(i)

		-- The reverse lookup in ProcessKey is the expensive part and there are thousands
		-- of bindings, so skip commands that can't be action buttons. A key whose real
		-- owner is an action button is always listed under that owner's entry too.
		if ResolveCommand(command) then
			-- GetBinding returns every key after the category, and a command can hold more
			-- than the two the binding UI offers.
			ProcessKeys(select(3, GetBinding(i)))
		end
	end

	return result, addonButtons
end

local function SetBindingAttribute(kind, index, value)
	local names = attributeNames[kind]
	local name = names[index]

	if not name then
		name = "mpr_" .. kind .. index
		names[index] = name
	end

	-- Every write is a protected call, and most refreshes rebuild the same bindings.
	if binderFrame:GetAttribute(name) ~= value then
		binderFrame:SetAttribute(name, value)
	end
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
					local overrideProxy = GetOrCreateProxy(buttonName .. "_override", overrideBtn, true)
					overrideProxy:SetAttribute("clickbutton", overrideBtn)
					overrideProxyName = overrideProxy:GetName()
				end

				-- Store each key and its proxy names as numbered attributes so the
				-- secure snippet can read them without direct Lua table access.
				for _, key in ipairs(includedKeys) do
					bindingIndex = bindingIndex + 1

					SetBindingAttribute("key", bindingIndex, key)
					SetBindingAttribute("normal", bindingIndex, normalProxy:GetName())
					SetBindingAttribute("override", bindingIndex, overrideProxyName)
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
