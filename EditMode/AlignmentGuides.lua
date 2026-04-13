local addonName, Framed = ...
local F = Framed

local EditMode = F.EditMode

-- ============================================================
-- AlignmentGuides — Red lines during drag for proportional
-- screen divisions and frame-to-frame edge alignment.
-- ============================================================

local GUIDE_COLOR     = { 0.8, 0.1, 0.1, 0.8 }
local GUIDE_THICKNESS = 1
local SNAP_THRESHOLD  = 8   -- pixels proximity to show guide
local FADE_SPEED      = 0.15

-- Proportional screen divisions (fraction of width/height).
-- Center (0.5) is the strongest; thirds and quarters are secondary.
-- All visible grid lines in sixteenths (must match Grid.lua DIVISIONS)
local DIVISIONS = {
	0.0625, 0.125, 0.1875, 0.25, 0.3125, 0.375, 0.4375, 0.5,
	0.5625, 0.625, 0.6875, 0.75, 0.8125, 0.875, 0.9375,
}

local guideFrame = nil

-- Two proportional guides: nearest horizontal and nearest vertical division
local propGuideH = nil
local propGuideV = nil

-- Dynamic edge guides (frame-to-frame alignment)
local edgeGuides = {}
local EDGE_GUIDE_POOL_SIZE = 8

-- ============================================================
-- Helpers
-- ============================================================

--- Collect screen bounds for all visible frames except the one being dragged.
--- @param excludeFrame Frame
--- @return table[]
local function GetOtherFrameBounds(excludeFrame)
	local bounds = {}
	for _, def in next, EditMode.FRAME_KEYS do
		local frame = def.getter()
		if(frame and frame ~= excludeFrame and frame:IsVisible()) then
			local left = frame:GetLeft()
			local right = frame:GetRight()
			local top = frame:GetTop()
			local bottom = frame:GetBottom()
			if(left and right and top and bottom) then
				bounds[#bounds + 1] = {
					left   = left,
					right  = right,
					top    = top,
					bottom = bottom,
				}
			end
		end
	end
	return bounds
end

local function CreateGuide(parent, isHorizontal)
	local tex = parent:CreateTexture(nil, 'OVERLAY')
	tex:SetColorTexture(GUIDE_COLOR[1], GUIDE_COLOR[2], GUIDE_COLOR[3], GUIDE_COLOR[4])
	tex:SetAlpha(0)
	tex._targetAlpha = 0
	tex._isHorizontal = isHorizontal
	return tex
end

--- Position a horizontal guide at an absolute Y screen coordinate.
local function PositionHGuide(guide, absY)
	guide:ClearAllPoints()
	guide:SetHeight(GUIDE_THICKNESS)
	guide:SetPoint('LEFT', guideFrame, 'BOTTOMLEFT', 0, absY)
	guide:SetPoint('RIGHT', guideFrame, 'BOTTOMRIGHT', 0, absY)
end

--- Position a vertical guide at an absolute X screen coordinate.
local function PositionVGuide(guide, absX)
	guide:ClearAllPoints()
	guide:SetWidth(GUIDE_THICKNESS)
	guide:SetPoint('TOP', guideFrame, 'TOPLEFT', absX, 0)
	guide:SetPoint('BOTTOM', guideFrame, 'BOTTOMLEFT', absX, 0)
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

-- ============================================================
-- Build / Destroy
-- ============================================================

local function BuildGuideFrame()
	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	guideFrame = CreateFrame('Frame', nil, overlay)
	guideFrame:SetAllPoints(overlay)
	guideFrame:SetFrameLevel(overlay:GetFrameLevel() + 40)
	guideFrame:Hide()

	-- Create proportional division guides (one per axis)
	propGuideH = CreateGuide(guideFrame, true)
	propGuideV = CreateGuide(guideFrame, false)

	-- OnUpdate for smooth fade
	guideFrame:SetScript('OnUpdate', function(self, dt)
		FadeGuide(propGuideH, propGuideH._targetAlpha, dt)
		FadeGuide(propGuideV, propGuideV._targetAlpha, dt)
		for _, guide in next, edgeGuides do
			FadeGuide(guide, guide._targetAlpha, dt)
		end
	end)
end

local function DestroyGuideFrame()
	if(guideFrame) then
		guideFrame:Hide()
		guideFrame:SetParent(EditMode._trashFrame)
		guideFrame = nil
	end
	propGuideH = nil
	propGuideV = nil
	edgeGuides = {}
end

-- ============================================================
-- Public API (called by drag handlers)
-- ============================================================

--- Update alignment guides based on the dragging frame's bounds.
--- Shows the nearest proportional screen division per axis (like Blizzard EditMode)
--- and frame-to-frame edge alignment guides.
--- @param dragFrame Frame|nil  The frame being dragged (used for edge detection, may be nil)
--- @param bounds table  { left, right, top, bottom, cx, cy } in UIParent coordinates
function EditMode.UpdateAlignmentGuides(dragFrame, bounds)
	if(not guideFrame) then return end
	guideFrame:Show()

	-- Use UIParent dimensions (matches guideFrame coordinate space)
	local uiW = UIParent:GetWidth()
	local uiH = UIParent:GetHeight()

	local left   = bounds.left
	local right  = bounds.right
	local top    = bounds.top
	local bottom = bounds.bottom
	local cx     = bounds.cx
	local cy     = bounds.cy

	-- ── Proportional screen division guides ──────────────────
	-- Find the closest division line per axis (nearest to any frame edge or center).
	local framePtsX = { left, cx, right }
	local framePtsY = { bottom, cy, top }

	local bestDistV, bestPosV = SNAP_THRESHOLD, nil
	local bestDistH, bestPosH = SNAP_THRESHOLD, nil

	for _, frac in next, DIVISIONS do
		local divX = uiW * frac
		for _, px in next, framePtsX do
			local d = math.abs(px - divX)
			if(d < bestDistV) then
				bestDistV = d
				bestPosV = divX
			end
		end

		local divY = uiH * frac
		for _, py in next, framePtsY do
			local d = math.abs(py - divY)
			if(d < bestDistH) then
				bestDistH = d
				bestPosH = divY
			end
		end
	end

	if(bestPosV) then
		propGuideV._targetAlpha = GUIDE_COLOR[4]
		PositionVGuide(propGuideV, bestPosV)
	else
		propGuideV._targetAlpha = 0
	end

	if(bestPosH) then
		propGuideH._targetAlpha = GUIDE_COLOR[4]
		PositionHGuide(propGuideH, bestPosH)
	else
		propGuideH._targetAlpha = 0
	end

	-- ── Edge alignment with other visible frames ────────────
	local otherBounds = GetOtherFrameBounds(dragFrame)
	local edgeIdx = 0

	local dragEdges = {
		{ val = left,   isH = false },
		{ val = right,  isH = false },
		{ val = top,    isH = true  },
		{ val = bottom, isH = true  },
	}

	for _, de in next, dragEdges do
		for _, ob in next, otherBounds do
			local otherEdges
			if(de.isH) then
				otherEdges = { ob.top, ob.bottom }
			else
				otherEdges = { ob.left, ob.right }
			end

			for _, oe in next, otherEdges do
				if(math.abs(de.val - oe) < SNAP_THRESHOLD) then
					edgeIdx = edgeIdx + 1
					if(edgeIdx > EDGE_GUIDE_POOL_SIZE) then break end

					if(not edgeGuides[edgeIdx]) then
						edgeGuides[edgeIdx] = CreateGuide(guideFrame, de.isH)
					end

					local guide = edgeGuides[edgeIdx]
					guide._isHorizontal = de.isH
					guide._targetAlpha = GUIDE_COLOR[4]

					if(de.isH) then
						PositionHGuide(guide, oe)
					else
						PositionVGuide(guide, oe)
					end
				end
			end
			if(edgeIdx > EDGE_GUIDE_POOL_SIZE) then break end
		end
		if(edgeIdx > EDGE_GUIDE_POOL_SIZE) then break end
	end

	-- Fade out unused edge guides
	for i = edgeIdx + 1, #edgeGuides do
		edgeGuides[i]._targetAlpha = 0
	end
end

--- Hide all alignment guides (called on drag stop).
function EditMode.HideAlignmentGuides()
	if(not guideFrame) then return end
	-- Immediately snap all guides to invisible and hide the frame
	if(propGuideH) then propGuideH._targetAlpha = 0; propGuideH:SetAlpha(0) end
	if(propGuideV) then propGuideV._targetAlpha = 0; propGuideV:SetAlpha(0) end
	for _, guide in next, edgeGuides do
		guide._targetAlpha = 0
		guide:SetAlpha(0)
	end
	guideFrame:Hide()
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
