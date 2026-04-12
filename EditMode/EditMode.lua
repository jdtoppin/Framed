local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditCache = F.EditCache

F.EditMode = {}
local EditMode = F.EditMode

-- ============================================================
-- Constants
-- ============================================================

local BORDER_SIZE     = 1
local DIM_ALPHA       = 0.85
local BORDER_RED      = { 0.8, 0.1, 0.1, 1 }
local BORDER_GREEN    = { 0.1, 0.8, 0.2, 1 }

-- ============================================================
-- State
-- ============================================================

local isActive         = false
local selectedFrameKey = nil
local overlay          = nil
local sessionPresetOverride = nil   -- nil = auto-detect, string = manual choice

-- Hidden frame for safe disposal (SetParent(nil) is unsafe in WoW)
local trashFrame = CreateFrame('Frame')
trashFrame:Hide()
EditMode._trashFrame = trashFrame

-- ============================================================
-- Frame Key Definitions
-- ============================================================

local FRAME_KEYS = {
	{ key = 'player',       label = 'Player',           isGroup = false, getter = function() return F.Units.Player and F.Units.Player.frame end },
	{ key = 'target',       label = 'Target',           isGroup = false, getter = function() return F.Units.Target and F.Units.Target.frame end },
	{ key = 'targettarget', label = 'Target of Target', isGroup = false, getter = function() return F.Units.TargetTarget and F.Units.TargetTarget.frame end },
	{ key = 'focus',        label = 'Focus',            isGroup = false, getter = function() return F.Units.Focus and F.Units.Focus.frame end },
	{ key = 'pet',          label = 'Pet',              isGroup = false, getter = function() return F.Units.Pet and F.Units.Pet.frame end },
	{ key = 'party',        label = 'Party Frames',     isGroup = true,  getter = function() return F.Units.Party and F.Units.Party.header end },
	{ key = 'raid',         label = 'Raid Frames',      isGroup = true,  getter = function() return F.Units.Raid and F.Units.Raid.header end },
	{ key = 'boss',         label = 'Boss Frames',      isGroup = true,  getter = function() return F.Units.Boss and F.Units.Boss.frames and F.Units.Boss.frames[1] end },
	{ key = 'arena',        label = 'Arena Frames',     isGroup = true,  getter = function() return F.Units.Arena and F.Units.Arena.frames and F.Units.Arena.frames[1] end },
}

EditMode.FRAME_KEYS = FRAME_KEYS

-- ============================================================
-- Frame State Snapshot (for discard/restore)
-- ============================================================

local function SaveCurrentFrameState()
	local state = {}
	for _, def in next, FRAME_KEYS do
		local frame = def.getter()
		if(frame) then
			local point, relativeTo, relPoint, x, y = frame:GetPoint()
			if(point) then
				local relName = relativeTo and relativeTo:GetName() or 'UIParent'
				state[def.key] = {
					point    = point,
					relName  = relName,
					relPoint = relPoint,
					x        = x,
					y        = y,
					width    = frame:GetWidth(),
					height   = frame:GetHeight(),
				}
			end
		end
	end
	EditCache.SavePreEditPositions(state)
end

local function RestoreFrameState()
	local state = EditCache.GetPreEditPositions()
	for _, def in next, FRAME_KEYS do
		local saved = state[def.key]
		if(saved) then
			local frame = def.getter()
			if(frame) then
				frame:ClearAllPoints()
				local relFrame = (saved.relName == 'UIParent') and UIParent or _G[saved.relName]
				Widgets.SetPoint(frame, saved.point, relFrame, saved.relPoint, saved.x, saved.y)
				Widgets.SetSize(frame, saved.width, saved.height)
			end
		end
	end
end

-- ============================================================
-- Overlay Construction (lazy)
-- ============================================================

local function BuildOverlay()
	overlay = CreateFrame('Frame', 'FramedEditModeOverlay', UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata('FULLSCREEN_DIALOG')
	overlay:SetFrameLevel(1)
	overlay:EnableMouse(false)
	overlay:Hide()

	-- Background click-catcher: sits above the dim fill but below catchers/TopBar.
	-- Catches clicks on empty overlay space to deselect the current frame.
	local bgCatcher = CreateFrame('Button', nil, overlay)
	bgCatcher:SetAllPoints(overlay)
	bgCatcher:SetFrameLevel(overlay:GetFrameLevel() + 5)
	bgCatcher:RegisterForClicks('AnyDown')
	bgCatcher:SetScript('OnClick', function()
		if(selectedFrameKey) then
			EditMode.SetSelectedFrameKey(nil)
		end
	end)
	overlay._bgCatcher = bgCatcher

	-- Dark fill
	local dimTex = overlay:CreateTexture(nil, 'BACKGROUND')
	dimTex:SetAllPoints(overlay)
	dimTex:SetColorTexture(0, 0, 0, DIM_ALPHA)
	overlay._dimTex = dimTex

	-- Red border (4 edge textures)
	local borders = {}
	local edges = {
		{ 'TOPLEFT', 'TOPRIGHT', 'TOPLEFT', 'TOPRIGHT', nil, BORDER_SIZE },       -- top
		{ 'BOTTOMLEFT', 'BOTTOMRIGHT', 'BOTTOMLEFT', 'BOTTOMRIGHT', nil, BORDER_SIZE }, -- bottom
		{ 'TOPLEFT', 'BOTTOMLEFT', 'TOPLEFT', 'BOTTOMLEFT', BORDER_SIZE, nil },   -- left
		{ 'TOPRIGHT', 'BOTTOMRIGHT', 'TOPRIGHT', 'BOTTOMRIGHT', BORDER_SIZE, nil }, -- right
	}
	for _, e in next, edges do
		local tex = overlay:CreateTexture(nil, 'OVERLAY')
		tex:SetPoint(e[1], overlay, e[3], 0, 0)
		tex:SetPoint(e[2], overlay, e[4], 0, 0)
		if(e[5]) then tex:SetWidth(e[5]) end
		if(e[6]) then tex:SetHeight(e[6]) end
		tex:SetColorTexture(BORDER_RED[1], BORDER_RED[2], BORDER_RED[3], BORDER_RED[4])
		borders[#borders + 1] = tex
	end
	overlay._borders = borders

	-- Keyboard: Escape triggers cancel, propagate all other keys
	overlay:EnableKeyboard(true)
	overlay:SetScript('OnKeyDown', function(self, key)
		if(key == 'ESCAPE') then
			self:SetPropagateKeyboardInput(false)
			EditMode.RequestCancel()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)
end

--- Flash the border to a color then fade out.
local function FlashBorder(color, callback)
	if(not overlay or not overlay._borders) then
		if(callback) then callback() end
		return
	end
	for _, tex in next, overlay._borders do
		tex:SetColorTexture(color[1], color[2], color[3], color[4])
	end
	-- Brief hold then fade
	C_Timer.After(0.3, function()
		if(callback) then callback() end
	end)
end

--- Reset border to red.
local function ResetBorderColor()
	if(not overlay or not overlay._borders) then return end
	for _, tex in next, overlay._borders do
		tex:SetColorTexture(BORDER_RED[1], BORDER_RED[2], BORDER_RED[3], BORDER_RED[4])
	end
end

-- ============================================================
-- Session Preset Management
-- ============================================================

--- Get the preset to use. Returns manual override if set, else auto-detect.
--- @return string presetName
function EditMode.GetSessionPreset()
	return sessionPresetOverride or F.Settings.GetEditingPreset()
end

--- Set a manual preset override for the session.
--- @param presetName string
function EditMode.SetSessionPreset(presetName)
	sessionPresetOverride = presetName
end

-- Combat frame created early so Enter/Exit can reference it
local combatFrame = CreateFrame('Frame')

-- ============================================================
-- Public API
-- ============================================================

--- Enter edit mode.
function EditMode.Enter()
	if(InCombatLockdown()) then
		if(DEFAULT_CHAT_FRAME) then
			DEFAULT_CHAT_FRAME:AddMessage('|cff00ccffFramed|r: Cannot enter Edit Mode during combat.')
		end
		return
	end

	if(isActive) then return end
	isActive = true
	combatFrame:RegisterEvent('PLAYER_REGEN_DISABLED')
	combatFrame:RegisterEvent('PLAYER_REGEN_ENABLED')

	-- Close sidebar if open
	F.Settings.Hide()

	-- Sync editing preset to the actually active preset so EditCache
	-- reads/writes the same data LiveUpdate used to position frames.
	-- Clears any stale sidebar selection or prior session override.
	sessionPresetOverride = nil
	local activePreset = F.AutoSwitch.GetCurrentPreset()
	F.Settings.SetEditingPreset(activePreset)

	SaveCurrentFrameState()
	EditCache.Activate()

	if(not overlay) then
		BuildOverlay()
	end

	ResetBorderColor()

	-- Build sub-components (TopBar, ClickCatchers, Grid will hook in here)
	F.EventBus:Fire('EDIT_MODE_ENTERED')

	Widgets.FadeIn(overlay)
	overlay:EnableKeyboard(true)
end

--- Perform save: commit cache, flash green, exit.
--- @param returnToMenu boolean  If true, reopen sidebar after exit
function EditMode.Save(returnToMenu)
	if(not isActive) then return end

	EditCache.Commit()

	FlashBorder(BORDER_GREEN, function()
		EditMode.Exit(returnToMenu)
	end)
end

--- Perform discard: clear cache, restore frame state, exit.
--- @param returnToMenu boolean  If true, reopen sidebar after exit
function EditMode.Discard(returnToMenu)
	if(not isActive) then return end

	-- Capture preset name before exit (Exit may reopen Settings which
	-- could sync editingPreset to a different value)
	local presetName = F.Settings.GetEditingPreset()

	-- Collect modified frame keys before clearing cache
	local modifiedKeys = {}
	for _, def in next, FRAME_KEYS do
		if(EditCache.HasEdits(def.key)) then
			modifiedKeys[#modifiedKeys + 1] = def.key
		end
	end

	EditCache.Discard()
	RestoreFrameState()
	EditMode.Exit(returnToMenu)

	-- Force LiveUpdate to re-read from real config for all modified frames
	for _, frameKey in next, modifiedKeys do
		local basePath = 'presets.' .. presetName .. '.unitConfigs.' .. frameKey
		F.EventBus:Fire('CONFIG_CHANGED', basePath .. '.width')
		F.EventBus:Fire('CONFIG_CHANGED', basePath .. '.height')
		F.EventBus:Fire('CONFIG_CHANGED', basePath .. '.position.x')
	end
end

--- Exit edit mode (internal, called after save or discard).
--- @param returnToMenu boolean
function EditMode.Exit(returnToMenu)
	isActive = false
	combatFrame:UnregisterAllEvents()
	selectedFrameKey = nil
	sessionPresetOverride = nil

	EditCache.Deactivate()

	F.EventBus:Fire('EDIT_MODE_EXITED')

	Widgets.FadeOut(overlay, nil, function()
		overlay:EnableKeyboard(false)
	end)

	if(returnToMenu) then
		F.Settings.Show()
	end
end

--- Request cancel (called by Escape or Cancel button).
--- Shows the cancel confirmation dialog if there are unsaved edits.
function EditMode.RequestCancel()
	if(not isActive) then return end
	if(EditCache.HasAnyEdits()) then
		F.EventBus:Fire('EDIT_MODE_SHOW_CANCEL_DIALOG')
	else
		-- No changes — exit and return to settings menu
		EditMode.Discard(true)
	end
end

--- Request save (called by Save button).
--- Shows the save confirmation dialog.
function EditMode.RequestSave()
	if(not isActive) then return end
	F.EventBus:Fire('EDIT_MODE_SHOW_SAVE_DIALOG')
end

--- Get the currently selected frame key.
--- @return string|nil
function EditMode.GetSelectedFrameKey()
	return selectedFrameKey
end

--- Set the selected frame key.
--- @param key string|nil
function EditMode.SetSelectedFrameKey(key)
	selectedFrameKey = key
	F.EventBus:Fire('EDIT_MODE_FRAME_SELECTED', key)
end

--- Query whether edit mode is active.
--- @return boolean
function EditMode.IsActive()
	return isActive
end

--- Get the overlay frame.
--- @return Frame|nil
function EditMode.GetOverlay()
	return overlay
end

-- ============================================================
-- Preset Switch in Edit Mode
-- ============================================================

--- Reposition all frames to the new preset's saved positions and
--- update the pre-edit snapshot so discard restores correctly.
---
--- Not every frame key exists in every preset: the Raid preset has no
--- `party` unitConfig, Party has no `raid`, Solo has neither group.
--- For frames the target preset doesn't own, we leave the live frame
--- exactly where it is — moving it to the (nil → 0, 0) fallback would
--- snap it to the top-left corner, and there's no correct destination
--- because the preset has no opinion about it.
local function ApplyPresetPositions()
	local presetName = F.Settings.GetEditingPreset()
	for _, def in next, FRAME_KEYS do
		local hasConfig = F.Config:Get('presets.' .. presetName .. '.unitConfigs.' .. def.key)
		if(hasConfig) then
			local frame = def.getter()
			if(frame) then
				local x = EditCache.Get(def.key, 'position.x')
				local y = EditCache.Get(def.key, 'position.y')
				local w = EditCache.Get(def.key, 'width')
				local h = EditCache.Get(def.key, 'height')
				if(x and y) then
					frame:ClearAllPoints()
					if(def.isGroup) then
						Widgets.SetPoint(frame, 'TOPLEFT', UIParent, 'TOPLEFT', x, y)
					else
						Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)
					end
				end
				if(w and h) then
					Widgets.SetSize(frame, w, h)
				end
			end
		end
	end
	-- Update pre-edit snapshot so discard restores to these positions
	SaveCurrentFrameState()
end

F.EventBus:Register('EDIT_MODE_PRESET_SWITCHED', function(presetName)
	ApplyPresetPositions()
	-- Re-select current frame to rebuild InlinePanel with new preset data
	local selKey = EditMode.GetSelectedFrameKey()
	if(selKey) then
		EditMode.SetSelectedFrameKey(selKey)
	end
end, 'EditMode.PresetSwitch')

-- ============================================================
-- Combat Protection
-- ============================================================

combatFrame:SetScript('OnEvent', function(self, event)
	if(not isActive) then return end

	if(event == 'PLAYER_REGEN_DISABLED') then
		-- Restore any in-progress drag to last saved position
		-- (solo frames only — group frames aren't directly dragged)
		local selKey = EditMode.GetSelectedFrameKey()
		if(selKey) then
			for _, def in next, EditMode.FRAME_KEYS do
				if(def.key == selKey and not def.isGroup) then
					local frame = def.getter()
					if(frame) then
						local x = EditCache.Get(selKey, 'position.x') or 0
						local y = EditCache.Get(selKey, 'position.y') or 0
						frame:ClearAllPoints()
						Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)
					end
					break
				end
			end
		end
		-- Hide overlay
		if(overlay and overlay:IsShown()) then
			overlay:Hide()
		end
	elseif(event == 'PLAYER_REGEN_ENABLED') then
		-- Re-show overlay
		if(isActive and overlay) then
			overlay:Show()
		end
	end
end)
