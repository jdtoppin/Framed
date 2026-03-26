local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode

-- ============================================================
-- Grid — Visual grid rendering for edit mode
-- ============================================================

local GRID_SPACING = C.Spacing.base  -- 4px
local LINE_SPACING = GRID_SPACING * 4  -- 16px visual grid; snap stays at 4px
local GRID_COLOR   = { 1, 1, 1, 0.06 }
local DOT_SIZE     = 1

local gridFrame = nil
local gridStyle = 'lines'   -- 'lines' or 'dots'
local activeTextures = {}   -- currently visible textures
local texturePool = {}      -- recycled hidden textures

--- Get a texture from the pool or create a new one.
local function AcquireTexture()
	local tex = table.remove(texturePool)
	if(not tex) then
		tex = gridFrame:CreateTexture(nil, 'ARTWORK')
	end
	tex:Show()
	return tex
end

--- Return all active textures to the pool.
local function ClearGrid()
	for _, tex in next, activeTextures do
		tex:Hide()
		tex:ClearAllPoints()
		texturePool[#texturePool + 1] = tex
	end
	activeTextures = {}
end

local function RenderLines()
	ClearGrid()
	if(not gridFrame) then return end

	local w = GetScreenWidth()
	local h = GetScreenHeight()
	local idx = 0

	-- Vertical lines
	for x = LINE_SPACING, w, LINE_SPACING do
		idx = idx + 1
		local tex = AcquireTexture()
		tex:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
		tex:SetWidth(1)
		tex:SetPoint('TOP', gridFrame, 'TOPLEFT', x, 0)
		tex:SetPoint('BOTTOM', gridFrame, 'BOTTOMLEFT', x, 0)
		activeTextures[idx] = tex
	end

	-- Horizontal lines
	for y = LINE_SPACING, h, LINE_SPACING do
		idx = idx + 1
		local tex = AcquireTexture()
		tex:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
		tex:SetHeight(1)
		tex:SetPoint('LEFT', gridFrame, 'TOPLEFT', 0, -y)
		tex:SetPoint('RIGHT', gridFrame, 'TOPRIGHT', 0, -y)
		activeTextures[idx] = tex
	end
end

local function RenderDots()
	ClearGrid()
	if(not gridFrame) then return end

	local w = GetScreenWidth()
	local h = GetScreenHeight()
	local idx = 0
	-- Larger spacing for dots to reduce texture count
	local spacing = GRID_SPACING * 8

	for x = spacing, w, spacing do
		for y = spacing, h, spacing do
			idx = idx + 1
			local tex = AcquireTexture()
			tex:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4] * 2)
			tex:SetSize(DOT_SIZE, DOT_SIZE)
			tex:SetPoint('CENTER', gridFrame, 'TOPLEFT', x, -y)
			activeTextures[idx] = tex
		end
	end
end

local function RenderGrid()
	if(gridStyle == 'dots') then
		RenderDots()
	else
		RenderLines()
	end
end

local function BuildGridFrame()
	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	gridFrame = CreateFrame('Frame', nil, overlay)
	gridFrame:SetAllPoints(overlay)
	gridFrame:SetFrameLevel(overlay:GetFrameLevel() + 2)

	-- Only show grid if snap is enabled
	if(EditMode.IsGridSnapEnabled()) then
		RenderGrid()
		gridFrame:Show()
	else
		gridFrame:Hide()
	end
end

local function DestroyGridFrame()
	ClearGrid()
	if(gridFrame) then
		gridFrame:Hide()
		gridFrame:SetParent(EditMode._trashFrame)
		gridFrame = nil
	end
end

-- ============================================================
-- Snap Logic
-- ============================================================

--- Snap coordinates to the grid.
--- @param x number
--- @param y number
--- @return number, number
function EditMode.SnapToGrid(x, y)
	if(not EditMode.IsGridSnapEnabled()) then return x, y end
	return Widgets.Round(x / GRID_SPACING) * GRID_SPACING,
	       Widgets.Round(y / GRID_SPACING) * GRID_SPACING
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
	if(not gridFrame) then return end
	if(enabled) then
		RenderGrid()
		gridFrame:Show()
	else
		ClearGrid()
		gridFrame:Hide()
	end
end, 'Grid')

F.EventBus:Register('EDIT_MODE_GRID_STYLE_CHANGED', function(style)
	gridStyle = style
	if(gridFrame and gridFrame:IsShown()) then
		RenderGrid()
	end
end, 'Grid')
