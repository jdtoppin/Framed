local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

F.EditMode = {}
local EditMode = F.EditMode

-- ============================================================
-- Constants
-- ============================================================

local TOP_BAR_WIDTH  = 480
local TOP_BAR_HEIGHT = 40
local HANDLE_ALPHA   = 0.6
local BUTTON_WIDTH   = 90
local BUTTON_HEIGHT  = 22

-- ============================================================
-- State
-- ============================================================

local isActive       = false
local savedPositions = {}
local gridSnap       = true

-- overlay and handle frames (created lazily)
local overlay    = nil
local topBar     = nil
local handles    = {}

-- ============================================================
-- Frame key definitions
-- ============================================================

local FRAME_KEYS = {
	{ key = 'player',       label = 'Player',        getter = function() return F.Units.Player and F.Units.Player.frame end },
	{ key = 'target',       label = 'Target',        getter = function() return F.Units.Target and F.Units.Target.frame end },
	{ key = 'targettarget', label = 'Target of Target', getter = function() return F.Units.TargetTarget and F.Units.TargetTarget.frame end },
	{ key = 'focus',        label = 'Focus',         getter = function() return F.Units.Focus and F.Units.Focus.frame end },
	{ key = 'pet',          label = 'Pet',           getter = function() return F.Units.Pet and F.Units.Pet.frame end },
	{ key = 'party',        label = 'Party Frames',  getter = function() return F.Units.Party and F.Units.Party.header end },
	{ key = 'raid',         label = 'Raid Frames',   getter = function() return F.Units.Raid and F.Units.Raid.header end },
	{ key = 'boss',         label = 'Boss Frames',   getter = function() return F.Units.Boss and F.Units.Boss.frames and F.Units.Boss.frames[1] end },
	{ key = 'arena',        label = 'Arena Frames',  getter = function() return F.Units.Arena and F.Units.Arena.frames and F.Units.Arena.frames[1] end },
}

-- ============================================================
-- Grid snap
-- ============================================================

local function SnapToGrid(x, y)
	if(not gridSnap) then return x, y end
	local grid = C.Spacing.base  -- 4px
	return Widgets.Round(x / grid) * grid, Widgets.Round(y / grid) * grid
end

-- ============================================================
-- Position save / restore / persist
-- ============================================================

local function SaveCurrentPositions()
	savedPositions = {}
	for _, def in next, FRAME_KEYS do
		local frame = def.getter()
		if(frame) then
			local point, relativeTo, relPoint, x, y = frame:GetPoint()
			if(point) then
				savedPositions[def.key] = { point, relativeTo, relPoint, x, y }
			end
		end
	end
end

local function RestorePositions()
	for _, def in next, FRAME_KEYS do
		local saved = savedPositions[def.key]
		if(saved) then
			local frame = def.getter()
			if(frame) then
				frame:ClearAllPoints()
				frame:SetPoint(saved[1], saved[2], saved[3], saved[4], saved[5])
			end
		end
	end
end

local function PersistPositions()
	local presetName = F.Settings.GetEditingPreset()
	for _, def in next, FRAME_KEYS do
		local frame = def.getter()
		if(frame) then
			local point, relativeTo, relPoint, x, y = frame:GetPoint()
			if(point) then
				local relName = relativeTo and relativeTo:GetName() or 'UIParent'
				F.Config:Set(
					'presets.' .. presetName .. '.positions.' .. def.key,
					{ point, relName, relPoint, x, y })
			end
		end
	end
end

-- ============================================================
-- Handle management
-- ============================================================

local function DestroyHandles()
	for _, handle in next, handles do
		handle:Hide()
		handle:SetParent(nil)
	end
	handles = {}
end

local function CreateHandleForFrame(targetFrame, label)
	local handle = CreateFrame('Frame', nil, UIParent, 'BackdropTemplate')
	handle:SetFrameStrata('HIGH')
	handle:SetFrameLevel(100)

	-- Match size and position of the target frame
	handle:SetAllPoints(targetFrame)

	-- Solid accent border at 50% alpha (simulates dashed border)
	local accent = C.Colors.accent
	handle:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	handle:SetBackdropColor(accent[1], accent[2], accent[3], 0.08)
	handle:SetBackdropBorderColor(accent[1], accent[2], accent[3], HANDLE_ALPHA)

	-- Label at top of handle
	local fs = handle:CreateFontString(nil, 'OVERLAY')
	fs:SetFont(F.Media.GetActiveFont(), C.Font.sizeSmall, '')
	fs:SetShadowOffset(1, -1)
	fs:SetTextColor(accent[1], accent[2], accent[3], 1)
	fs:SetPoint('TOP', handle, 'TOP', 0, -C.Spacing.base)
	fs:SetText(label)

	return handle
end

local function CreateHandles()
	DestroyHandles()
	for _, def in next, FRAME_KEYS do
		local frame = def.getter()
		if(frame and frame:IsShown()) then
			local handle = CreateHandleForFrame(frame, def.label)
			handles[#handles + 1] = handle

			-- Wire up dragging on the underlying frame
			local key = def.key
			Widgets.MakeDraggable(frame,
				nil,
				function(dragFrame, x, y)
					local snappedX, snappedY = SnapToGrid(x, y)
					if(snappedX ~= x or snappedY ~= y) then
						local point, relativeTo, relPoint = dragFrame:GetPoint()
						dragFrame:ClearAllPoints()
						dragFrame:SetPoint(point, relativeTo, relPoint, snappedX, snappedY)
					end
					-- Keep handle in sync
					handle:ClearAllPoints()
					handle:SetAllPoints(dragFrame)
				end,
				true)
		end
	end
end

-- ============================================================
-- Overlay UI construction (lazy)
-- ============================================================

local function BuildOverlay()
	-- Invisible full-screen catch frame for Escape key
	overlay = CreateFrame('Frame', 'FramedEditModeOverlay', UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata('HIGH')
	overlay:SetFrameLevel(90)
	overlay:EnableMouse(false)   -- pass-through; individual handles are interactive
	overlay:Hide()

	overlay:SetPropagateKeyboardInput(false)
	overlay:EnableKeyboard(true)
	overlay:SetScript('OnKeyDown', function(self, key)
		if(key == 'ESCAPE') then
			EditMode.Cancel()
		end
	end)

	-- Top bar: centered at top of screen
	topBar = Widgets.CreateBorderedFrame(overlay, TOP_BAR_WIDTH, TOP_BAR_HEIGHT, C.Colors.panel, C.Colors.border)
	topBar:SetFrameStrata('HIGH')
	topBar:SetFrameLevel(110)
	topBar:SetPoint('TOP', UIParent, 'TOP', 0, -C.Spacing.tight)

	-- "Edit Mode" label
	local titleText = Widgets.CreateFontString(topBar, C.Font.sizeTitle, C.Colors.accent)
	titleText:SetPoint('LEFT', topBar, 'LEFT', C.Spacing.normal, 0)
	titleText:SetText('Edit Mode')
	topBar.__titleText = titleText

	-- Cancel button (rightmost)
	local cancelBtn = Widgets.CreateButton(topBar, 'Cancel', 'widget', BUTTON_WIDTH, BUTTON_HEIGHT)
	cancelBtn:SetPoint('RIGHT', topBar, 'RIGHT', -C.Spacing.normal, 0)
	cancelBtn:SetOnClick(function()
		EditMode.Cancel()
	end)

	-- Save button (left of Cancel)
	local saveBtn = Widgets.CreateButton(topBar, 'Save', 'accent', BUTTON_WIDTH, BUTTON_HEIGHT)
	saveBtn:SetPoint('RIGHT', cancelBtn, 'LEFT', -C.Spacing.base, 0)
	saveBtn:SetOnClick(function()
		EditMode.Save()
	end)

	-- Grid Snap toggle button (left of Save)
	local snapBtn = Widgets.CreateButton(topBar, 'Grid Snap', 'widget', BUTTON_WIDTH, BUTTON_HEIGHT)
	snapBtn:SetPoint('RIGHT', saveBtn, 'LEFT', -C.Spacing.base, 0)

	local function UpdateSnapButton()
		if(gridSnap) then
			local accent = C.Colors.accent
			snapBtn:SetBackdropColor(C.Colors.accentDim[1], C.Colors.accentDim[2], C.Colors.accentDim[3], C.Colors.accentDim[4] or 1)
			snapBtn:SetBackdropBorderColor(accent[1], accent[2], accent[3], accent[4] or 1)
			snapBtn._label:SetTextColor(1, 1, 1, 1)
		else
			local s = snapBtn._scheme
			snapBtn:SetBackdropColor(s.bg[1], s.bg[2], s.bg[3], s.bg[4] or 1)
			local bc = s.border
			snapBtn:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
			local tc = s.textColor
			snapBtn._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
	end

	snapBtn:SetOnClick(function()
		gridSnap = not gridSnap
		UpdateSnapButton()
	end)

	-- Initialise snap button to reflect default state
	UpdateSnapButton()
end

-- ============================================================
-- Public API
-- ============================================================

--- Enter Edit Mode: show overlay, save positions, create handles.
--- No-op in combat (protected frames cannot be moved in combat).
function EditMode.Enter()
	if(InCombatLockdown()) then
		if(DEFAULT_CHAT_FRAME) then
			DEFAULT_CHAT_FRAME:AddMessage('|cff00ccffFramed|r: Cannot enter Edit Mode during combat.')
		end
		return
	end

	if(isActive) then return end
	isActive = true

	SaveCurrentPositions()

	if(not overlay) then
		BuildOverlay()
	end

	-- Update the label to reflect the currently editing preset
	if(topBar and topBar.__titleText) then
		local presetName = F.Settings.GetEditingPreset()
		topBar.__titleText:SetText('Edit Mode: ' .. presetName .. ' Frame Preset')
	end

	-- Reset grid snap label state in case it drifted
	CreateHandles()

	Widgets.FadeIn(overlay)
	overlay:EnableKeyboard(true)
end

--- Save: persist positions, exit overlay.
function EditMode.Save()
	if(not isActive) then return end

	PersistPositions()

	isActive = false
	DestroyHandles()
	Widgets.FadeOut(overlay)
	overlay:EnableKeyboard(false)
end

--- Cancel: restore original positions, exit overlay.
function EditMode.Cancel()
	if(not isActive) then return end

	RestorePositions()

	isActive = false
	DestroyHandles()
	Widgets.FadeOut(overlay)
	overlay:EnableKeyboard(false)
end

--- Query whether Edit Mode is currently active.
--- @return boolean
function EditMode.IsActive()
	return isActive
end
