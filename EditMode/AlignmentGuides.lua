local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode

-- ============================================================
-- AlignmentGuides — Red lines during drag for center/edge snap
-- ============================================================

local GUIDE_COLOR     = { 0.8, 0.1, 0.1, 0.8 }
local GUIDE_THICKNESS = 1
local SNAP_THRESHOLD  = 8   -- pixels proximity to show guide
local FADE_SPEED      = 0.15

local guideFrame = nil
local guides = {
	centerH = nil,  -- horizontal center line
	centerV = nil,  -- vertical center line
}
local edgeGuides = {}  -- dynamic edge alignment lines

local function CreateGuide(parent, isHorizontal)
	local tex = parent:CreateTexture(nil, 'OVERLAY')
	tex:SetColorTexture(GUIDE_COLOR[1], GUIDE_COLOR[2], GUIDE_COLOR[3], 0)
	if(isHorizontal) then
		tex:SetHeight(GUIDE_THICKNESS)
		tex:SetPoint('LEFT', parent, 'LEFT', 0, 0)
		tex:SetPoint('RIGHT', parent, 'RIGHT', 0, 0)
	else
		tex:SetWidth(GUIDE_THICKNESS)
		tex:SetPoint('TOP', parent, 'TOP', 0, 0)
		tex:SetPoint('BOTTOM', parent, 'BOTTOM', 0, 0)
	end
	tex._targetAlpha = 0
	tex._isHorizontal = isHorizontal
	return tex
end

local function SetGuidePosition(guide, offset)
	guide:ClearAllPoints()
	if(guide._isHorizontal) then
		guide:SetHeight(GUIDE_THICKNESS)
		guide:SetPoint('LEFT', guideFrame, 'LEFT', 0, 0)
		guide:SetPoint('RIGHT', guideFrame, 'RIGHT', 0, 0)
		guide:SetPoint('TOP', guideFrame, 'CENTER', 0, offset)
	else
		guide:SetWidth(GUIDE_THICKNESS)
		guide:SetPoint('TOP', guideFrame, 'TOP', 0, 0)
		guide:SetPoint('BOTTOM', guideFrame, 'BOTTOM', 0, 0)
		guide:SetPoint('LEFT', guideFrame, 'CENTER', offset, 0)
	end
end

local function FadeGuide(guide, targetAlpha, dt)
	local current = guide:GetAlpha()
	if(math.abs(current - targetAlpha) < 0.01) then
		guide:SetAlpha(targetAlpha)
		return
	end
	local step = dt / FADE_SPEED
	if(targetAlpha > current) then
		guide:SetAlpha(math.min(current + step, targetAlpha))
	else
		guide:SetAlpha(math.max(current - step, targetAlpha))
	end
end

local function BuildGuideFrame()
	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	guideFrame = CreateFrame('Frame', nil, overlay)
	guideFrame:SetAllPoints(overlay)
	guideFrame:SetFrameLevel(overlay:GetFrameLevel() + 40)
	guideFrame:Hide()

	guides.centerH = CreateGuide(guideFrame, true)
	guides.centerV = CreateGuide(guideFrame, false)

	-- OnUpdate for smooth fade
	guideFrame:SetScript('OnUpdate', function(self, dt)
		for _, guide in next, guides do
			FadeGuide(guide, guide._targetAlpha, dt)
		end
		for _, guide in next, edgeGuides do
			FadeGuide(guide, guide._targetAlpha, dt)
		end
	end)
end

local function DestroyGuideFrame()
	if(guideFrame) then
		guideFrame:Hide()
		guideFrame:SetParent(nil)
		guideFrame = nil
	end
	guides = { centerH = nil, centerV = nil }
	edgeGuides = {}
end

-- ============================================================
-- Public API (called by drag handlers)
-- ============================================================

--- Update alignment guides based on the dragging frame's position.
--- Call this from the onMove callback during a frame drag.
--- @param dragFrame Frame  The frame being dragged
function EditMode.UpdateAlignmentGuides(dragFrame)
	if(not guideFrame) then return end
	guideFrame:Show()

	local screenW = GetScreenWidth()
	local screenH = GetScreenHeight()
	local screenCX = screenW / 2
	local screenCY = screenH / 2

	-- Dragging frame bounds
	local left = dragFrame:GetLeft() or 0
	local right = dragFrame:GetRight() or 0
	local top = dragFrame:GetTop() or 0
	local bottom = dragFrame:GetBottom() or 0
	local cx = (left + right) / 2
	local cy = (top + bottom) / 2

	-- Center vertical guide (frame center X near screen center X)
	if(math.abs(cx - screenCX) < SNAP_THRESHOLD) then
		guides.centerV._targetAlpha = GUIDE_COLOR[4]
		SetGuidePosition(guides.centerV, 0)
	else
		guides.centerV._targetAlpha = 0
	end

	-- Center horizontal guide (frame center Y near screen center Y)
	if(math.abs(cy - screenCY) < SNAP_THRESHOLD) then
		guides.centerH._targetAlpha = GUIDE_COLOR[4]
		SetGuidePosition(guides.centerH, 0)
	else
		guides.centerH._targetAlpha = 0
	end

	-- Edge alignment with other frames (future: iterate other frame positions)
	-- For now, center guides only. Edge guides will be added when more frames are
	-- integrated into the drag system.
end

--- Hide all alignment guides (called on drag stop).
function EditMode.HideAlignmentGuides()
	if(not guideFrame) then return end
	for _, guide in next, guides do
		guide._targetAlpha = 0
	end
	for _, guide in next, edgeGuides do
		guide._targetAlpha = 0
	end
	-- Hide the frame after fade completes
	C_Timer.After(FADE_SPEED + 0.05, function()
		if(guideFrame) then guideFrame:Hide() end
	end)
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_ENTERED', function()
	BuildGuideFrame()
end, 'AlignmentGuides')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyGuideFrame()
end, 'AlignmentGuides')
