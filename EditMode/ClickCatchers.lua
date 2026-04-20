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

--- Clamp frame position so all edges stay on screen.
--- @param x number Offset X (frame-space)
--- @param y number Offset Y (frame-space)
--- @param frameW number Frame width (frame-space)
--- @param frameH number Frame height (frame-space)
--- @param scaleRatio number fScale / uiScale
--- @param isGroup boolean True for TOPLEFT-anchored group frames
--- @return number, number Clamped x, y
local function clampToScreen(x, y, frameW, frameH, scaleRatio, isGroup)
	local uiW = UIParent:GetWidth()
	local uiH = UIParent:GetHeight()

	if(isGroup) then
		-- TOPLEFT anchor: x >= 0 (left), x + frameW*scaleRatio <= uiW (right)
		-- y <= 0 (top), y - frameH*scaleRatio >= -uiH (bottom)
		local maxX = (uiW - frameW * scaleRatio) / scaleRatio
		local minY = -(uiH - frameH * scaleRatio) / scaleRatio
		x = math.max(0, math.min(maxX, x))
		y = math.min(0, math.max(minY, y))
	else
		-- CENTER anchor: center ± half frame must stay within screen
		local halfFW = frameW / 2 * scaleRatio
		local halfFH = frameH / 2 * scaleRatio
		local uiHalfW = uiW / 2
		local uiHalfH = uiH / 2
		local minX = -(uiHalfW - halfFW) / scaleRatio
		local maxX = (uiHalfW - halfFW) / scaleRatio
		local minY = -(uiHalfH - halfFH) / scaleRatio
		local maxY = (uiHalfH - halfFH) / scaleRatio
		x = math.max(minX, math.min(maxX, x))
		y = math.max(minY, math.min(maxY, y))
	end

	return x, y
end

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

-- ── Group layout helpers ─────────────────────────────────────

-- Delegates to PreviewManager so the catcher outline stays pixel-aligned
-- with the actual preview layout, regardless of sort mode.
local function getGroupBounds(config, frameKey)
	return F.PreviewManager.GetGroupBounds(config, frameKey)
end

-- ── Catcher creation ─────────────────────────────────────────

local function CreateCatcher(def, overlay)
	local frame = def.getter()
	local frameKey = def.key

	-- For group frames, read config to calculate layout bounds
	if(def.isGroup) then
		local preset = F.Settings.GetEditingPreset()
		local config = F.Config:Get('presets.' .. preset .. '.unitConfigs.' .. frameKey)
		if(not config) then return end

		local totalW = getGroupBounds(config, frameKey)
		local anchor = config.anchorPoint
		if(not totalW or not anchor) then
			-- Missing layout config — fall back to real frame if available
			if(not frame) then return end
		end
	elseif(not frame) then
		return
	end

	local catcher = CreateFrame('Button', nil, overlay, 'BackdropTemplate')
	catcher:SetFrameLevel(overlay:GetFrameLevel() + 10)

	if(def.isGroup) then
		local preset = F.Settings.GetEditingPreset()
		local config = F.Config:Get('presets.' .. preset .. '.unitConfigs.' .. frameKey)
		local totalW, totalH = getGroupBounds(config, frameKey)
		local anchor = config.anchorPoint
		if(totalW and anchor) then
			-- Apply same SetScale as preview frames so position and size
			-- render in the same coordinate space
			local targetScale = frame and frame:GetEffectiveScale() or UIParent:GetEffectiveScale()
			local parentScale = catcher:GetParent():GetEffectiveScale()
			if(parentScale > 0) then
				catcher:SetScale(targetScale / parentScale)
			end
			catcher:SetSize(totalW, totalH)
			-- Anchor to real frame so catcher follows during drag
			if(frame) then
				catcher:SetPoint(anchor, frame, anchor, 0, 0)
			else
				local posAnchor = (config.position and config.position.anchor) or 'CENTER'
				local posX = (config.position and config.position.x) or 0
				local posY = (config.position and config.position.y) or 0
				catcher:SetPoint(anchor, UIParent, posAnchor, posX, posY)
			end
		else
			catcher:SetAllPoints(frame)
		end
	else
		catcher:SetAllPoints(frame)
	end

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
		-- Select the frame first so PreviewManager builds its preview before
		-- the catcher goes invisible. Without this, a first-drag (click+drag
		-- without any prior click-release) shows nothing moving — the catcher
		-- hides itself via ApplySelectedVisuals, but no preview exists to take
		-- its place and the real frame is occluded by the dim overlay. Select
		-- happens on OnClick (click-release) and OnDragStop, neither of which
		-- fires before the first OnUpdate of a first-drag.
		if(EditMode.GetSelectedFrameKey() ~= self._frameKey) then
			EditMode.SetSelectedFrameKey(self._frameKey)
		end
		-- Switch to selected visuals during drag
		ApplySelectedVisuals(self)

		-- Track click offset from frame reference point in frame-space.
		-- Group frames use TOPLEFT (matching LiveUpdate); solo use CENTER.
		local fScale = frame:GetEffectiveScale()
		local uiScale = UIParent:GetEffectiveScale()
		local isGroupDrag = self._isGroup
		self._isGroupDrag = isGroupDrag

		-- Reference point: frame's top-left for groups, center for solo
		local fRefX, fRefY
		if(isGroupDrag) then
			fRefX, fRefY = frame:GetLeft(), frame:GetTop()
		else
			fRefX, fRefY = frame:GetCenter()
		end

		-- Use original click position (captured in OnMouseDown before drag threshold)
		local clickX = self._mouseDownX or GetCursorPosition()
		local clickY = self._mouseDownY or select(2, GetCursorPosition())
		-- Click offset in frame-space
		self._clickOffX = fRefX - clickX / fScale
		self._clickOffY = fRefY - clickY / fScale
		self._frameW = frame:GetWidth()
		self._frameH = frame:GetHeight()
		self._isDragging = true

		F.EventBus:Fire('EDIT_MODE_DRAG_STARTED', frameKey)

		-- UIParent reference point in frame-space:
		-- TOPLEFT = (0, top) for groups, CENTER for solo
		local uiRefX, uiRefY
		if(isGroupDrag) then
			uiRefX = 0
			uiRefY = UIParent:GetTop() * uiScale / fScale
		else
			local uiCX, uiCY = UIParent:GetCenter()
			uiRefX = uiCX * uiScale / fScale
			uiRefY = uiCY * uiScale / fScale
		end
		-- Scale ratio for converting frame-space → UIParent-space (alignment guides)
		local scaleRatio = fScale / uiScale
		local dragAnchor = isGroupDrag and 'TOPLEFT' or 'CENTER'
		local dragRelPoint = isGroupDrag and 'TOPLEFT' or 'CENTER'
		self:SetScript('OnUpdate', function(s)
			local cx, cy = GetCursorPosition()
			-- Frame ref in frame-space = cursor in frame-space + click offset
			local newRefX = cx / fScale + s._clickOffX
			local newRefY = cy / fScale + s._clickOffY
			-- SetPoint offset = frame ref minus UIParent ref (both in frame-space)
			local newX = newRefX - uiRefX
			local newY = newRefY - uiRefY

			-- Live snap: convert to UIParent-space, snap, convert back
			local snapX, snapY = EditMode.SnapToGrid(newX * scaleRatio, newY * scaleRatio, s._frameW * scaleRatio, s._frameH * scaleRatio)
			newX = snapX / scaleRatio
			newY = snapY / scaleRatio

			-- Clamp so frame stays on screen
			newX, newY = clampToScreen(newX, newY, s._frameW, s._frameH, scaleRatio, isGroupDrag)

			-- Store last computed position for OnDragStop
			s._lastX = newX
			s._lastY = newY

			-- Move frame to follow cursor (raw SetPoint to avoid pixel-rounding drift)
			frame:ClearAllPoints()
			frame:SetPoint(dragAnchor, UIParent, dragRelPoint, newX, newY)

			-- NOTE: Do NOT re-anchor catcher here — WoW's drag system
			-- fights with SetAllPoints during drag, causing compounding drift.

			-- Live position update for sliders
			F.EventBus:Fire('EDIT_MODE_DRAGGING', frameKey, Widgets.Round(newX), Widgets.Round(newY))

			-- Update alignment guides (convert frame-space → UIParent-space)
			local uiHalfW = UIParent:GetWidth() / 2
			local uiHalfH = UIParent:GetHeight() / 2
			local centerX, centerY
			if(isGroupDrag) then
				-- TOPLEFT offset → screen center
				centerX = newX * scaleRatio + s._frameW / 2 * scaleRatio
				centerY = UIParent:GetHeight() + newY * scaleRatio - s._frameH / 2 * scaleRatio
			else
				centerX = uiHalfW + newX * scaleRatio
				centerY = uiHalfH + newY * scaleRatio
			end
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

		-- Snap already applied during drag — use final position directly
		local x = self._lastX or 0
		local y = self._lastY or 0

		-- Re-anchor catcher to frame
		self:ClearAllPoints()
		if(self._isGroup and frame) then
			-- Keep explicit size for group catchers; just re-anchor the point
			local cfg = F.Config:Get('presets.' .. F.Settings.GetEditingPreset() .. '.unitConfigs.' .. frameKey)
			local anchor = cfg and cfg.anchorPoint
			if(anchor) then
				self:SetPoint(anchor, frame, anchor, 0, 0)
			else
				self:SetAllPoints(frame)
			end
		else
			self:SetAllPoints(frame)
		end

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
	-- Only create catchers for frames that exist in the current preset
	local presetName = F.Settings.GetEditingPreset()
	local unitConfigs = F.Config:Get('presets.' .. presetName .. '.unitConfigs')
	for _, def in next, EditMode.FRAME_KEYS do
		if(unitConfigs and unitConfigs[def.key]) then
			CreateCatcher(def, overlay)
		end
	end
end

-- ============================================================
-- Public API
-- ============================================================

function EditMode.GetCatcher(frameKey)
	return catchers[frameKey]
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

F.EventBus:Register('EDIT_MODE_PRESET_SWITCHED', function()
	CreateAllCatchers()
end, 'ClickCatchers')

F.EventBus:Register('EDIT_MODE_PREVIEW_COUNT_CHANGED', function()
	CreateAllCatchers()
	-- Re-apply selected visuals for the current selection
	local selKey = EditMode.GetSelectedFrameKey()
	if(selKey) then
		F.EventBus:Fire('EDIT_MODE_FRAME_SELECTED', selKey)
	end
end, 'ClickCatchers.previewCount')

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
