---@type string, Addon
local _, addon = ...
local mini = addon.Framework
local eventsFrame
local overlays = {}
local maxButtonsCount = 12
local initialised = false
local cursorHoldingAction = false
local cursorCheckQueued
---@type CharDb
local charDb
---@class MouseModule
local M = {}
addon.Mouse = M

local function CursorHasAnything()
	local infoType = GetCursorInfo()
	if infoType then
		return true
	end

	return (CursorHasItem and CursorHasItem())
		or (CursorHasSpell and CursorHasSpell())
		or (CursorHasMacro and CursorHasMacro())
		or (CursorHasMoney and CursorHasMoney())
end

local function ApplyCursorState()
	cursorHoldingAction = CursorHasAnything()

	-- if the cursor is holding a spell/action, they might be dragging it onto action bars
	-- disable our overlays in this case otherwise it has the behaviour of dropping the spell on mouse down
	-- then immediately picking the spell back up on mouse up
	for _, overlay in pairs(overlays) do
		overlay:EnableMouse(not cursorHoldingAction)
	end
end

local function QueueCursorCheck()
	if cursorCheckQueued then
		return
	end

	cursorCheckQueued = true

	-- we need to wait a frame for blizzard to update it's internal state about the cursor state
	-- this solves a bug where you drag a spell onto an existing spell which places the previous spell onto the cursor
	-- and without waiting the cursor state reports nothing is on it
	C_Timer.After(0, function()
		cursorCheckQueued = false
		ApplyCursorState()
	end)
end

local function HideTooltip()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

---Returns the action slot for the specified secure button.
---@return number|nil
local function GetActionForButton(button)
	local action = button.action

	if type(action) == "number" then
		return action
	end

	action = button:GetAttribute("action")

	if type(action) == "number" then
		return action
	end

	return nil
end

---Shows the gametooltip for the spell/action of the secure button.
---@param overlay any
local function ShowTooltip(overlay)
	if not GameTooltip then
		return
	end

	if GameTooltip_SetDefaultAnchor then
		-- use the default anchor position where possible
		GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
	else
		GameTooltip:SetOwner(overlay, "ANCHOR_RIGHT")
	end

	local prefix = overlay.Prefix
	local id = overlay.Id
	local button = overlay.Button

	if prefix == "PetActionButton" then
		GameTooltip:SetPetAction(id)
		GameTooltip:Show()
		return
	end

	if prefix == "ShapeshiftButton" then
		GameTooltip:SetShapeshift(id)
		GameTooltip:Show()
		return
	end

	if prefix == "PossessButton" then
		if GameTooltip.SetPossession then
			GameTooltip:SetPossession(id)
			GameTooltip:Show()
			return
		end
	end

	local actionSlot = GetActionForButton(button)

	if actionSlot then
		GameTooltip:SetAction(actionSlot)
		GameTooltip:Show()
		return
	end

	GameTooltip:Hide()
end

local function ApplyHoverVisuals(button, isOver)
	if button.LockHighlight and button.UnlockHighlight then
		if isOver then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end

	local hl = button.GetHighlightTexture and button:GetHighlightTexture()
	if hl then
		if isOver then
			hl:Show()
		else
			hl:Hide()
		end
	end

	if button.hoverTexture then
		if isOver then
			button.hoverTexture:Show()
		else
			button.hoverTexture:Hide()
		end
	end
end

---Creates the overlay button ontop of the existing button.
---@param button table
---@param prefix string
---@param id number
---@return table|nil
local function EnsureOverlay(button, prefix, id)
	local existing = overlays[button]

	if existing then
		return existing
	end

	local name = button:GetName()

	if not name then
		return nil
	end

	local overlay = CreateFrame("Button", name .. "MouseDownOverlay", button, "SecureActionButtonTemplate")
	overlay:SetAllPoints(button)
	overlay:SetFrameLevel(button:GetFrameLevel() + 10)
	overlay:EnableMouse(true)
	-- listen for down and up
	overlay:RegisterForClicks("AnyDown", "AnyUp")
	-- trigger clicks on down and up
	overlay:SetAttribute("pressAndHoldAction", "1")
	overlay:SetAttribute("type", "click")
	overlay:SetAttribute("typerelease", "click")
	-- link to the underlying action button
	overlay:SetAttribute("clickbutton", button)
	overlay:Show()

	overlay.Button = button
	overlay.Prefix = prefix
	overlay.Id = id

	overlay:SetScript("OnEnter", function()
		ApplyHoverVisuals(button, true)
		ShowTooltip(overlay)
	end)

	overlay:SetScript("OnLeave", function()
		ApplyHoverVisuals(button, false)
		HideTooltip()
	end)

	overlays[button] = overlay
	return overlay
end

local function OnEvent(_, event)
	if event == "CURSOR_CHANGED" then
		QueueCursorCheck()
		return
	end

	M:Refresh()
end

function M:Refresh()
	if not initialised then
		return
	end

	if InCombatLockdown() then
		return
	end

	if not charDb.MouseEnabled then
		for _, overlay in pairs(overlays) do
			overlay:Hide()
		end

		return
	end

	for _, bind in ipairs(addon.Binds) do
		for i = 1, maxButtonsCount do
			local btn = _G[bind.Prefix .. i]
			local overlay = btn and EnsureOverlay(btn, bind.Prefix, i)

			if overlay then
				local binding = bind.Bind .. i
				local primaryKey, secondaryKey = GetBindingKey(binding)
				local included = (not primaryKey or addon:IsKeyIncluded(primaryKey))
					or (not secondaryKey or addon:IsKeyIncluded(secondaryKey))

				if included then
					overlay:Show()
				else
					overlay:Hide()
				end
			end
		end
	end
end

function M:Init()
	charDb = mini:GetCharacterSavedVars()

	eventsFrame = CreateFrame("Frame")
	eventsFrame:RegisterEvent("PLAYER_LOGIN")
	eventsFrame:RegisterEvent("UPDATE_BINDINGS")
	eventsFrame:RegisterEvent("CURSOR_CHANGED")

	eventsFrame:SetScript("OnEvent", OnEvent)

	initialised = true
end
