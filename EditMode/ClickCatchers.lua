local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode
local EditCache = F.EditCache

-- ============================================================
-- ClickCatchers — transparent overlays on unit frames for
-- direct grab-and-drag in edit mode. Releasing a drag (or
-- clicking without dragging) selects the frame and opens
-- the inline settings panel.
-- ============================================================

local catchers = {}
local DIM_OVERLAY_ALPHA = 0.7

local function DestroyCatchers()
	for _, catcher in next, catchers do
		catcher:Hide()
		catcher:SetParent(EditMode._trashFrame)
	end
	catchers = {}
end

-- ── Visual state helpers ─────────────────────────────────────

local function ApplyDefaultVisuals(catcher, def)
	catcher._label:SetText(def.label)
	catcher._dimTex:SetAlpha(DIM_OVERLAY_ALPHA)
	local tn = C.Colors.textNormal
	catcher._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)
	local ac = C.Colors.accent
	catcher:SetBackdropBorderColor(ac[1], ac[2], ac[3], 0.6)
end

local function ApplySelectedVisuals(catcher)
	catcher._label:SetText('')
	catcher._dimTex:SetAlpha(0)
	catcher:SetBackdropBorderColor(0, 0, 0, 0)
end

-- ── Catcher creation ─────────────────────────────────────────

local function CreateCatcher(def, overlay)
	local frame = def.getter()
	if(not frame) then return end

	local frameKey = def.key
	local catcher = CreateFrame('Button', nil, overlay, 'BackdropTemplate')
	catcher:SetFrameLevel(overlay:GetFrameLevel() + 10)
	catcher:SetAllPoints(frame)
	catcher._frameKey = frameKey
	catcher._isGroup = def.isGroup
	catcher._def = def

	-- 1px accent border so frames stand out against the dim overlay
	local accent = C.Colors.accent
	catcher:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = 1 })
	catcher:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)

	-- Dark accent overlay
	local dimTex = catcher:CreateTexture(nil, 'ARTWORK')
	dimTex:SetAllPoints(catcher)
	dimTex:SetColorTexture(accent[1] * 0.15, accent[2] * 0.15, accent[3] * 0.15, DIM_OVERLAY_ALPHA)
	catcher._dimTex = dimTex

	-- Frame label
	local label = Widgets.CreateFontString(catcher, C.Font.sizeSmall, C.Colors.textNormal)
	label:SetPoint('CENTER', catcher, 'CENTER', 0, 0)
	label:SetText(def.label)
	catcher._label = label

	-- Hover highlight
	catcher:SetScript('OnEnter', function(self)
		if(EditMode.GetSelectedFrameKey() == self._frameKey) then return end
		self._dimTex:SetAlpha(DIM_OVERLAY_ALPHA * 0.5)
		self._label:SetTextColor(1, 1, 1, 1)
		self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
	end)
	catcher:SetScript('OnLeave', function(self)
		if(EditMode.GetSelectedFrameKey() == self._frameKey) then return end
		self._dimTex:SetAlpha(DIM_OVERLAY_ALPHA)
		local tn = C.Colors.textNormal
		self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)
		self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)
	end)

	-- Click without drag → select
	catcher:SetScript('OnClick', function(self)
		EditMode.SetSelectedFrameKey(self._frameKey)
	end)

	-- ── Drag: immediately draggable ──────────────────────────
	catcher:RegisterForDrag('LeftButton')

	-- Capture true click position before drag threshold moves cursor
	catcher:SetScript('OnMouseDown', function(self)
		self._mouseDownX, self._mouseDownY = GetCursorPosition()
	end)

	catcher:SetScript('OnDragStart', function(self)
		-- Switch to selected visuals during drag
		ApplySelectedVisuals(self)

		-- ElvUI-style: track click offset from frame center in frame-space.
		-- GetCenter() and GetCursorPosition()/fScale are both in frame-space
		-- (1 unit = fScale screen pixels). Since fScale differs from uiScale,
		-- UIParent center must be converted to frame-space before subtracting.
		local fScale = frame:GetEffectiveScale()
		local uiScale = UIParent:GetEffectiveScale()
		local fCX, fCY = frame:GetCenter()
		-- Use original click position (captured in OnMouseDown before drag threshold)
		-- to avoid the offset caused by cursor moving before OnDragStart fires
		local clickX = self._mouseDownX or GetCursorPosition()
		local clickY = self._mouseDownY or select(2, GetCursorPosition())
		-- Click offset in frame-space (both terms in frame-space)
		self._clickOffX = fCX - clickX / fScale
		self._clickOffY = fCY - clickY / fScale
		self._frameW = frame:GetWidth()
		self._frameH = frame:GetHeight()
		self._isDragging = true

		F.EventBus:Fire('EDIT_MODE_DRAG_STARTED', frameKey)

		-- UIParent center in frame-space (convert from UIParent-space → screen px → frame-space)
		local uiCX, uiCY = UIParent:GetCenter()
		local uiCenterX = uiCX * uiScale / fScale
		local uiCenterY = uiCY * uiScale / fScale
		-- Scale ratio for converting frame-space → UIParent-space (alignment guides)
		local scaleRatio = fScale / uiScale
		self:SetScript('OnUpdate', function(s)
			local cx, cy = GetCursorPosition()
			-- Frame center in frame-space = cursor in frame-space + click offset
			local newCX = cx / fScale + s._clickOffX
			local newCY = cy / fScale + s._clickOffY
			-- SetPoint offset = frame center minus UIParent center (both in frame-space)
			local newX = newCX - uiCenterX
			local newY = newCY - uiCenterY

			-- Store last computed position for OnDragStop
			s._lastX = newX
			s._lastY = newY

			-- Move frame to follow cursor (raw SetPoint to avoid pixel-rounding drift)
			frame:ClearAllPoints()
			frame:SetPoint('CENTER', UIParent, 'CENTER', newX, newY)

			-- NOTE: Do NOT re-anchor catcher here — WoW's drag system
			-- fights with SetAllPoints during drag, causing compounding drift.

			-- Update alignment guides (convert frame-space → UIParent-space)
			local uiHalfW = UIParent:GetWidth() / 2
			local uiHalfH = UIParent:GetHeight() / 2
			local centerX = uiHalfW + newX * scaleRatio
			local centerY = uiHalfH + newY * scaleRatio
			local halfW = s._frameW / 2 * scaleRatio
			local halfH = s._frameH / 2 * scaleRatio
			EditMode.UpdateAlignmentGuides(nil, {
				left   = centerX - halfW,
				right  = centerX + halfW,
				top    = centerY + halfH,
				bottom = centerY - halfH,
				cx     = centerX,
				cy     = centerY,
			})
		end)
	end)

	catcher:SetScript('OnDragStop', function(self)
		self:SetScript('OnUpdate', nil)
		self._isDragging = false

		-- _lastX/_lastY are in frame-space (SetPoint offset units).
		-- SnapToGrid uses UIParent:GetWidth() internally (UIParent-space),
		-- so convert to UIParent-space for snap, then back to frame-space.
		local fScale = frame:GetEffectiveScale()
		local uiScale = UIParent:GetEffectiveScale()
		local ratio = fScale / uiScale
		local rawX = self._lastX or 0
		local rawY = self._lastY or 0
		local snapX, snapY = EditMode.SnapToGrid(rawX * ratio, rawY * ratio, self._frameW * ratio, self._frameH * ratio)
		-- Convert back to frame-space
		local x = snapX / ratio
		local y = snapY / ratio

		-- Reposition if snap adjusted the values
		if(x ~= rawX or y ~= rawY) then
			frame:ClearAllPoints()
			Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)
		end

		-- Re-anchor catcher to frame (wasn't re-anchored during drag)
		self:ClearAllPoints()
		self:SetAllPoints(frame)

		-- Save to edit cache (frame-space values, matching Widgets.SetPoint)
		EditCache.Set(frameKey, 'position.x', x)
		EditCache.Set(frameKey, 'position.y', y)

		EditMode.HideAlignmentGuides()
		F.EventBus:Fire('EDIT_MODE_DRAG_STOPPED', frameKey)

		-- Select frame on release (opens inline panel)
		EditMode.SetSelectedFrameKey(frameKey)
	end)

	catchers[frameKey] = catcher
	return catcher
end

local function CreateAllCatchers()
	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	DestroyCatchers()
	for _, def in next, EditMode.FRAME_KEYS do
		CreateCatcher(def, overlay)
	end
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_ENTERED', function()
	CreateAllCatchers()
end, 'ClickCatchers')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyCatchers()
end, 'ClickCatchers')

F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
	local overlay = EditMode.GetOverlay()
	for _, catcher in next, catchers do
		if(catcher._frameKey == frameKey) then
			ApplySelectedVisuals(catcher)
			-- Lower below preview (preview container is at overlay+8)
			catcher:SetFrameLevel(overlay:GetFrameLevel() + 6)
		else
			ApplyDefaultVisuals(catcher, catcher._def)
			-- Keep above preview so unselected frames stay clickable
			catcher:SetFrameLevel(overlay:GetFrameLevel() + 10)
		end
		catcher:Show()
	end
end, 'ClickCatchers')
