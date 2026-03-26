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

local CURSORS = {
	TOPLEFT     = 'UI_RESIZE_TOPLEFT',
	TOP         = 'UI_RESIZE_TOP',
	TOPRIGHT    = 'UI_RESIZE_TOPRIGHT',
	LEFT        = 'UI_RESIZE_LEFT',
	RIGHT       = 'UI_RESIZE_RIGHT',
	BOTTOMLEFT  = 'UI_RESIZE_BOTTOMLEFT',
	BOTTOM      = 'UI_RESIZE_BOTTOM',
	BOTTOMRIGHT = 'UI_RESIZE_BOTTOMRIGHT',
}

local function DestroyHandles()
	for _, handle in next, handles do
		handle:Hide()
		handle:SetParent(nil)
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
		local scale = targetFrame:GetEffectiveScale()
		local sx, sy = GetCursorPosition()
		local startW = targetFrame:GetWidth()
		local startH = targetFrame:GetHeight()
		local startX = sx / scale
		local startY = sy / scale

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
			elseif(point == 'LEFT' or point == 'TOPLEFT' or point == 'BOTTOMLEFT') then
				newW = math.max(20, startW - dx)
			end
			if(point == 'TOP' or point == 'TOPLEFT' or point == 'TOPRIGHT') then
				newH = math.max(16, startH + dy)
			elseif(point == 'BOTTOM' or point == 'BOTTOMLEFT' or point == 'BOTTOMRIGHT') then
				newH = math.max(16, startH - dy)
			end

			-- Snap to grid if enabled
			if(EditMode.IsGridSnapEnabled()) then
				newW = Widgets.Round(newW / C.Spacing.base) * C.Spacing.base
				newH = Widgets.Round(newH / C.Spacing.base) * C.Spacing.base
			end

			targetFrame:SetSize(newW, newH)

			-- Update edit cache
			EditCache.Set(frameKey, 'width', Widgets.Round(newW))
			EditCache.Set(frameKey, 'height', Widgets.Round(newH))

			-- Fire event for live settings panel update
			F.EventBus:Fire('EDIT_MODE_FRAME_RESIZED', frameKey, newW, newH)
		end)
	end)

	handle:SetScript('OnDragStop', function(self)
		self:SetScript('OnUpdate', nil)
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
