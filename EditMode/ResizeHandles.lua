local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode
local EditCache = F.EditCache

-- ============================================================
-- ResizeHandles — Edge/corner drag handles for frame resizing
-- ============================================================

local HANDLE_SIZE    = 8
local HANDLE_COLOR   = { C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 0.6 }
local HANDLE_HOVER   = { 1, 1, 1, 0.8 }

local handles = {}

local HANDLE_POINTS = {
	'TOPLEFT', 'TOP', 'TOPRIGHT',
	'LEFT', 'RIGHT',
	'BOTTOMLEFT', 'BOTTOM', 'BOTTOMRIGHT',
}



local function DestroyHandles()
	for _, handle in next, handles do
		handle:Hide()
		handle:SetParent(EditMode._trashFrame)
	end
	handles = {}
end

local function CreateHandle(parent, point, targetFrame, frameKey)
	local handle = CreateFrame('Button', nil, parent)
	handle:SetSize(HANDLE_SIZE, HANDLE_SIZE)
	handle:SetPoint('CENTER', targetFrame, point, 0, 0)
	handle:SetFrameLevel(parent:GetFrameLevel() + 60)

	local tex = handle:CreateTexture(nil, 'OVERLAY')
	tex:SetAllPoints(handle)
	tex:SetColorTexture(HANDLE_COLOR[1], HANDLE_COLOR[2], HANDLE_COLOR[3], HANDLE_COLOR[4])
	handle._tex = tex


	-- Tooltip
	handle:SetScript('OnEnter', function(self)
		self._tex:SetColorTexture(HANDLE_HOVER[1], HANDLE_HOVER[2], HANDLE_HOVER[3], HANDLE_HOVER[4])
		GameTooltip:SetOwner(self, 'ANCHOR_CURSOR')
		GameTooltip:AddLine('Drag to resize', 1, 1, 1)
		GameTooltip:Show()
	end)

	handle:SetScript('OnLeave', function(self)
		self._tex:SetColorTexture(HANDLE_COLOR[1], HANDLE_COLOR[2], HANDLE_COLOR[3], HANDLE_COLOR[4])
		GameTooltip:Hide()
	end)

	-- Resize dragging
	handle:EnableMouse(true)
	handle:RegisterForDrag('LeftButton')

	handle:SetScript('OnDragStart', function(self)
		self._tex:SetColorTexture(HANDLE_HOVER[1], HANDLE_HOVER[2], HANDLE_HOVER[3], HANDLE_HOVER[4])
		local scale = targetFrame:GetEffectiveScale()
		local sx, sy = GetCursorPosition()
		local startW = targetFrame:GetWidth()
		local startH = targetFrame:GetHeight()
		local startX = sx / scale
		local startY = sy / scale

		-- Capture initial frame position for anchor compensation
		local _, _, _, frameStartX, frameStartY = targetFrame:GetPoint(1)
		frameStartX = frameStartX or 0
		frameStartY = frameStartY or 0

		local resizesLeft = (point == 'LEFT' or point == 'TOPLEFT' or point == 'BOTTOMLEFT')
		local resizesTop  = (point == 'TOP' or point == 'TOPLEFT' or point == 'TOPRIGHT')

		-- Only run OnUpdate during active drag
		self:SetScript('OnUpdate', function(s)
			local cx, cy = GetCursorPosition()
			cx = cx / scale
			cy = cy / scale

			local dx = cx - startX
			local dy = cy - startY
			local newW = startW
			local newH = startH

			-- Determine resize direction based on handle point
			if(point == 'RIGHT' or point == 'TOPRIGHT' or point == 'BOTTOMRIGHT') then
				newW = math.max(20, startW + dx)
			elseif(resizesLeft) then
				newW = math.max(20, startW - dx)
			end
			if(resizesTop) then
				newH = math.max(16, startH + dy)
			elseif(point == 'BOTTOM' or point == 'BOTTOMLEFT' or point == 'BOTTOMRIGHT') then
				newH = math.max(16, startH - dy)
			end

			-- Round to nearest pixel (1px step)
			newW = Widgets.Round(newW)
			newH = Widgets.Round(newH)

			targetFrame:SetSize(newW, newH)

			-- Compensate anchor position when resizing from top/left edges
			-- so the opposite edge stays fixed visually
			local offsetX = frameStartX
			local offsetY = frameStartY

			-- Frames are CENTER-anchored during edit mode drag,
			-- so center shifts by half the size delta
			local anchorPoint = select(1, targetFrame:GetPoint(1))
			local isCenter = (anchorPoint == 'CENTER')

			if(resizesLeft) then
				local delta = newW - startW
				offsetX = frameStartX - (isCenter and delta / 2 or delta)
			end
			if(resizesTop) then
				local delta = newH - startH
				offsetY = frameStartY + (isCenter and delta / 2 or delta)
			end

			if(resizesLeft or resizesTop) then
				local curAnchorPoint, anchorTo, anchorRelPoint = targetFrame:GetPoint(1)
				targetFrame:ClearAllPoints()
				Widgets.SetPoint(targetFrame, curAnchorPoint, anchorTo, anchorRelPoint, offsetX, offsetY)
			end

			-- Update edit cache
			EditCache.Set(frameKey, 'width', Widgets.Round(newW))
			EditCache.Set(frameKey, 'height', Widgets.Round(newH))

			if(resizesLeft or resizesTop) then
				EditCache.Set(frameKey, 'position.x', Widgets.Round(offsetX))
				EditCache.Set(frameKey, 'position.y', Widgets.Round(offsetY))
			end

			-- Fire event for live settings panel update
			F.EventBus:Fire('EDIT_MODE_FRAME_RESIZED', frameKey, newW, newH)
		end)
	end)

	handle:SetScript('OnDragStop', function(self)
		self:SetScript('OnUpdate', nil)
		self._tex:SetColorTexture(HANDLE_COLOR[1], HANDLE_COLOR[2], HANDLE_COLOR[3], HANDLE_COLOR[4])
	end)

	return handle
end

local function CreateHandlesForFrame(overlay, targetFrame, frameKey)
	DestroyHandles()
	for _, point in next, HANDLE_POINTS do
		handles[#handles + 1] = CreateHandle(overlay, point, targetFrame, frameKey)
	end
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
	DestroyHandles()
	if(not frameKey) then return end

	-- Only show resize handles for non-group frames
	for _, def in next, EditMode.FRAME_KEYS do
		if(def.key == frameKey and not def.isGroup) then
			local frame = def.getter()
			local overlay = EditMode.GetOverlay()
			if(frame and overlay) then
				CreateHandlesForFrame(overlay, frame, frameKey)
			end
			break
		end
	end
end, 'ResizeHandles')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyHandles()
end, 'ResizeHandles')

-- Sync real frame when width/height/position changes via sliders
F.EventBus:Register('EDIT_CACHE_VALUE_CHANGED', function(frameKey, configPath, value)
	-- Pinned routes every edit-cache change through its own APIs:
	-- position.x/y → ApplyPosition (anchor parents all slots)
	-- anchorPoint / width / height / columns / spacing → Layout
	-- (Layout's `if(f.unit) then f:Show() end` guard keeps unassigned
	-- frames hidden, so we don't need Refresh's anchor:Hide/Show wrapper
	-- — which itself produces a brief frames-gone flash on width changes.)
	-- GetConfig overlays EditCache so Layout sees the live values.
	if(frameKey == 'pinned') then
		if(not F.Units.Pinned) then return end
		local pinnedAnchor = F.Units.Pinned.anchor

		if(configPath == 'position.x' or configPath == 'position.y') then
			-- ApplyPosition alone — the anchor parents all 9 slots, so moving
			-- the anchor is enough. Calling Layout here re-Shows unassigned
			-- frames (Layout's unconditional f:Show) and they briefly render
			-- their stale 'player' seed state before anything hides them.
			F.Units.Pinned.ApplyPosition()
			return
		end
		if(configPath == 'anchorPoint') then
			-- Layout alone. Tokens unchanged, so Resolve would early-return
			-- per slot anyway; skipping Refresh's anchor:Hide/Show wrapper
			-- avoids a visible gap. Layout's f.unit guard keeps unassigned
			-- frames hidden.
			F.Units.Pinned.Layout()
			return
		end

		local dimensionChange = (configPath == 'width' or configPath == 'height'
			or configPath == 'columns' or configPath == 'spacing')
		if(not dimensionChange) then return end

		-- Snapshot bg size before Layout so we can compute delta for resize-
		-- anchor compensation. Mirrors the party/raid groupResizeShift pattern:
		-- grid bounds grow, but the chosen pivot corner/edge stays visually
		-- fixed. Without this, bg always grows from TOPLEFT regardless of the
		-- user's Resize Anchor setting.
		local oldBgW = (pinnedAnchor and pinnedAnchor._width)  or (pinnedAnchor and pinnedAnchor:GetWidth())  or 0
		local oldBgH = (pinnedAnchor and pinnedAnchor._height) or (pinnedAnchor and pinnedAnchor:GetHeight()) or 0

		F.Units.Pinned.Layout()

		local newBgW = (pinnedAnchor and pinnedAnchor._width)  or (pinnedAnchor and pinnedAnchor:GetWidth())  or 0
		local newBgH = (pinnedAnchor and pinnedAnchor._height) or (pinnedAnchor and pinnedAnchor:GetHeight()) or 0
		local dw = newBgW - oldBgW
		local dh = newBgH - oldBgH
		if(dw == 0 and dh == 0) then return end

		local resizeAnchor = F.EditCache.Get('pinned', 'position.anchor') or 'TOPLEFT'
		if(resizeAnchor == 'TOPLEFT') then return end

		local Shared = F.LiveUpdate and F.LiveUpdate.FrameConfigShared
		if(not Shared or not Shared.groupResizeShift) then return end

		local dx, dy = Shared.groupResizeShift('TOPLEFT', resizeAnchor, dw, dh)
		if(dx == 0 and dy == 0) then return end

		local curX = F.EditCache.Get('pinned', 'position.x') or 0
		local curY = F.EditCache.Get('pinned', 'position.y') or 0
		F.EditCache.Set('pinned', 'position.x', Widgets.Round(curX + dx))
		F.EditCache.Set('pinned', 'position.y', Widgets.Round(curY + dy))
		return
	end

	local isSize = (configPath == 'width' or configPath == 'height')
	local isPos = (configPath == 'position.x' or configPath == 'position.y')
	if(not isSize and not isPos) then return end

	for _, def in next, EditMode.FRAME_KEYS do
		if(def.key == frameKey) then
			local frame = def.getter()
			if(not frame) then break end

			if(isSize) then
				local w = EditCache.Get(frameKey, 'width') or frame:GetWidth()
				local h = EditCache.Get(frameKey, 'height') or frame:GetHeight()
				frame:SetSize(w, h)
			elseif(isPos) then
				local x = EditCache.Get(frameKey, 'position.x') or 0
				local y = EditCache.Get(frameKey, 'position.y') or 0

				-- Clamp so frame stays on screen
				local w = frame:GetWidth()
				local h = frame:GetHeight()
				local fScale = frame:GetEffectiveScale()
				local uiScale = UIParent:GetEffectiveScale()
				local scaleRatio = fScale / uiScale
				local uiW = UIParent:GetWidth()
				local uiH = UIParent:GetHeight()

				-- Group frames use TOPLEFT anchor (matching LiveUpdate and
				-- edit-mode drag), solo frames use CENTER.
				frame:ClearAllPoints()
				if(def.isGroup) then
					local maxX = (uiW - w * scaleRatio) / scaleRatio
					local minY = -(uiH - h * scaleRatio) / scaleRatio
					x = math.max(0, math.min(maxX, x))
					y = math.min(0, math.max(minY, y))
					Widgets.SetPoint(frame, 'TOPLEFT', UIParent, 'TOPLEFT', x, y)
				else
					local halfFW = w / 2 * scaleRatio
					local halfFH = h / 2 * scaleRatio
					local uiHalfW = uiW / 2
					local uiHalfH = uiH / 2
					x = math.max(-(uiHalfW - halfFW) / scaleRatio, math.min((uiHalfW - halfFW) / scaleRatio, x))
					y = math.max(-(uiHalfH - halfFH) / scaleRatio, math.min((uiHalfH - halfFH) / scaleRatio, y))
					Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)
				end
			end
			break
		end
	end
end, 'ResizeHandles.cacheChanged')
