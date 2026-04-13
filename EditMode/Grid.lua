local addonName, Framed = ...
local F = Framed

local EditMode = F.EditMode

-- ============================================================
-- Grid — Single square grid overlay for edit mode.
-- Regular lines form squares, proportional division lines are
-- highlighted (these are the snap positions for alignment
-- guides during drag).
-- ============================================================

local GRID_COLOR        = { 1, 1, 1, 0.10 }                   -- minor grid lines
local DIVISION_COLOR    = { 1, 1, 1, 0.22 }                   -- major division lines (quarter marks)
local CENTER_LINE_COLOR = { 0.784, 0.271, 0.980, 0.35 }       -- purple center lines

-- All visible grid lines in sixteenths (must match AlignmentGuides.lua DIVISIONS)
-- Every line is a snap target. Quarter marks (0.25, 0.5, 0.75) are drawn brighter.
local DIVISIONS = {
	0.0625, 0.125, 0.1875, 0.25, 0.3125, 0.375, 0.4375, 0.5,
	0.5625, 0.625, 0.6875, 0.75, 0.8125, 0.875, 0.9375,
}

-- Quarter marks get the brighter color
local QUARTER_MARKS = { [0.25] = true, [0.5] = true, [0.75] = true }

local gridFrame = nil
local activeTextures = {}
local texturePool = {}

local function AcquireTexture()
	local tex = table.remove(texturePool)
	if(not tex) then
		tex = gridFrame:CreateTexture(nil, 'ARTWORK')
	end
	tex:Show()
	return tex
end

local function ClearGrid()
	for _, tex in next, activeTextures do
		tex:Hide()
		tex:ClearAllPoints()
		texturePool[#texturePool + 1] = tex
	end
	activeTextures = {}
end

local function RenderGrid()
	ClearGrid()
	if(not gridFrame) then return end

	local w = UIParent:GetWidth()
	local h = UIParent:GetHeight()
	local idx = 0

	-- ── Grid lines (every snap position is visible) ─────────────
	-- Quarter marks are brighter, minor lines are fainter.
	for _, frac in next, DIVISIONS do
		if(math.abs(frac - 0.5) > 0.01) then
			local color = QUARTER_MARKS[frac] and DIVISION_COLOR or GRID_COLOR

			idx = idx + 1
			local tex = AcquireTexture()
			tex:SetColorTexture(color[1], color[2], color[3], color[4])
			tex:SetWidth(1)
			tex:SetPoint('TOP', gridFrame, 'TOPLEFT', w * frac, 0)
			tex:SetPoint('BOTTOM', gridFrame, 'BOTTOMLEFT', w * frac, 0)
			activeTextures[idx] = tex

			idx = idx + 1
			tex = AcquireTexture()
			tex:SetColorTexture(color[1], color[2], color[3], color[4])
			tex:SetHeight(1)
			tex:SetPoint('LEFT', gridFrame, 'BOTTOMLEFT', 0, h * frac)
			tex:SetPoint('RIGHT', gridFrame, 'BOTTOMRIGHT', 0, h * frac)
			activeTextures[idx] = tex
		end
	end

	-- ── Center lines (purple, strongest) ─────────────────────────
	idx = idx + 1
	local tex = AcquireTexture()
	tex:SetColorTexture(CENTER_LINE_COLOR[1], CENTER_LINE_COLOR[2], CENTER_LINE_COLOR[3], CENTER_LINE_COLOR[4])
	tex:SetWidth(1)
	tex:SetPoint('TOP', gridFrame, 'TOPLEFT', w / 2, 0)
	tex:SetPoint('BOTTOM', gridFrame, 'BOTTOMLEFT', w / 2, 0)
	activeTextures[idx] = tex

	idx = idx + 1
	tex = AcquireTexture()
	tex:SetColorTexture(CENTER_LINE_COLOR[1], CENTER_LINE_COLOR[2], CENTER_LINE_COLOR[3], CENTER_LINE_COLOR[4])
	tex:SetHeight(1)
	tex:SetPoint('LEFT', gridFrame, 'BOTTOMLEFT', 0, h / 2)
	tex:SetPoint('RIGHT', gridFrame, 'BOTTOMRIGHT', 0, h / 2)
	activeTextures[idx] = tex
end

local function BuildGridFrame()
	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	gridFrame = CreateFrame('Frame', nil, overlay)
	gridFrame:SetAllPoints(overlay)
	gridFrame:SetFrameLevel(overlay:GetFrameLevel() + 2)

	RenderGrid()
	gridFrame:Show()
end

local function DestroyGridFrame()
	ClearGrid()
	texturePool = {}
	if(gridFrame) then
		gridFrame:Hide()
		gridFrame:SetParent(EditMode._trashFrame)
		gridFrame = nil
	end
end

-- ============================================================
-- Snap Logic
-- ============================================================

local SNAP_THRESHOLD = 8

--- Snap a frame's position so its nearest edge aligns with a division line.
--- x, y are CENTER offsets from UIParent CENTER.
--- @param x number  Center X offset
--- @param y number  Center Y offset
--- @param frameW number  Frame width
--- @param frameH number  Frame height
--- @return number, number  Snapped x, y
function EditMode.SnapToGrid(x, y, frameW, frameH)
	if(not EditMode.IsGridSnapEnabled() or not frameW or not frameH) then return x, y end

	local uiW = UIParent:GetWidth()
	local uiH = UIParent:GetHeight()
	local halfW = frameW / 2
	local halfH = frameH / 2

	-- Convert center offset to absolute position (from left/bottom)
	local absX = uiW / 2 + x
	local absY = uiH / 2 + y

	-- Frame edges in absolute coordinates
	local edgesX = { absX - halfW, absX, absX + halfW }  -- left, center, right
	local edgesY = { absY + halfH, absY, absY - halfH }  -- top, center, bottom

	-- Find nearest division per axis
	local bestDistX, bestSnapX = SNAP_THRESHOLD, nil
	local bestEdgeIdxX = nil
	for _, frac in next, DIVISIONS do
		local divPos = uiW * frac
		for ei, edge in next, edgesX do
			local d = math.abs(edge - divPos)
			if(d < bestDistX) then
				bestDistX = d
				bestSnapX = divPos
				bestEdgeIdxX = ei
			end
		end
	end

	local bestDistY, bestSnapY = SNAP_THRESHOLD, nil
	local bestEdgeIdxY = nil
	for _, frac in next, DIVISIONS do
		local divPos = uiH * frac
		for ei, edge in next, edgesY do
			local d = math.abs(edge - divPos)
			if(d < bestDistY) then
				bestDistY = d
				bestSnapY = divPos
				bestEdgeIdxY = ei
			end
		end
	end

	-- Adjust center position so the snapped edge lands on the division
	if(bestSnapX) then
		if(bestEdgeIdxX == 1) then      -- left edge
			absX = bestSnapX + halfW
		elseif(bestEdgeIdxX == 2) then  -- center
			absX = bestSnapX
		else                             -- right edge
			absX = bestSnapX - halfW
		end
	end

	if(bestSnapY) then
		if(bestEdgeIdxY == 1) then      -- top edge
			absY = bestSnapY - halfH
		elseif(bestEdgeIdxY == 2) then  -- center
			absY = bestSnapY
		else                             -- bottom edge
			absY = bestSnapY + halfH
		end
	end

	-- Convert back to center offset
	return absX - uiW / 2, absY - uiH / 2
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_ENTERED', function()
	BuildGridFrame()
end, 'Grid')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyGridFrame()
end, 'Grid')

F.EventBus:Register('EDIT_MODE_GRID_SNAP_CHANGED', function(enabled)
	-- Grid is always visible; this event only toggles snap behavior
end, 'Grid')
