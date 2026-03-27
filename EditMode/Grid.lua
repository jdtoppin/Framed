local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode

-- ============================================================
-- Grid — Visual grid rendering for edit mode
-- ============================================================

local GRID_SPACING = C.Spacing.base           -- 4px snap resolution
local LINE_SPACING = 100                       -- 100px visual grid (matches Blizzard default)
local GRID_COLOR        = { 1, 1, 1, 0.15 }   -- normal grid lines
local CENTER_LINE_COLOR = { 0.784, 0.271, 0.980, 0.35 }  -- purple center lines
local DOT_SIZE     = 2
local DOT_SPACING  = 50                        -- dot grid spacing

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
	local cx = w / 2
	local cy = h / 2
	local idx = 0

	-- Center vertical line
	idx = idx + 1
	local tex = AcquireTexture()
	tex:SetColorTexture(CENTER_LINE_COLOR[1], CENTER_LINE_COLOR[2], CENTER_LINE_COLOR[3], CENTER_LINE_COLOR[4])
	tex:SetWidth(1)
	tex:SetPoint('TOP', gridFrame, 'TOPLEFT', cx, 0)
	tex:SetPoint('BOTTOM', gridFrame, 'BOTTOMLEFT', cx, 0)
	activeTextures[idx] = tex

	-- Center horizontal line
	idx = idx + 1
	tex = AcquireTexture()
	tex:SetColorTexture(CENTER_LINE_COLOR[1], CENTER_LINE_COLOR[2], CENTER_LINE_COLOR[3], CENTER_LINE_COLOR[4])
	tex:SetHeight(1)
	tex:SetPoint('LEFT', gridFrame, 'TOPLEFT', 0, -cy)
	tex:SetPoint('RIGHT', gridFrame, 'TOPRIGHT', 0, -cy)
	activeTextures[idx] = tex

	-- Vertical lines outward from center
	local halfV = math.floor((w / LINE_SPACING) / 2)
	for i = 1, halfV do
		local offset = i * LINE_SPACING
		-- Right of center
		idx = idx + 1
		tex = AcquireTexture()
		tex:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
		tex:SetWidth(1)
		tex:SetPoint('TOP', gridFrame, 'TOPLEFT', cx + offset, 0)
		tex:SetPoint('BOTTOM', gridFrame, 'BOTTOMLEFT', cx + offset, 0)
		activeTextures[idx] = tex
		-- Left of center
		idx = idx + 1
		tex = AcquireTexture()
		tex:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
		tex:SetWidth(1)
		tex:SetPoint('TOP', gridFrame, 'TOPLEFT', cx - offset, 0)
		tex:SetPoint('BOTTOM', gridFrame, 'BOTTOMLEFT', cx - offset, 0)
		activeTextures[idx] = tex
	end

	-- Horizontal lines outward from center
	local halfH = math.floor((h / LINE_SPACING) / 2)
	for i = 1, halfH do
		local offset = i * LINE_SPACING
		-- Below center
		idx = idx + 1
		tex = AcquireTexture()
		tex:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
		tex:SetHeight(1)
		tex:SetPoint('LEFT', gridFrame, 'TOPLEFT', 0, -(cy + offset))
		tex:SetPoint('RIGHT', gridFrame, 'TOPRIGHT', 0, -(cy + offset))
		activeTextures[idx] = tex
		-- Above center
		idx = idx + 1
		tex = AcquireTexture()
		tex:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
		tex:SetHeight(1)
		tex:SetPoint('LEFT', gridFrame, 'TOPLEFT', 0, -(cy - offset))
		tex:SetPoint('RIGHT', gridFrame, 'TOPRIGHT', 0, -(cy - offset))
		activeTextures[idx] = tex
	end
end

local MAX_DOT_TEXTURES = 2000  -- cap to avoid GPU pressure at high resolutions

local function RenderDots()
	ClearGrid()
	if(not gridFrame) then return end

	local w = GetScreenWidth()
	local h = GetScreenHeight()
	local idx = 0

	for x = DOT_SPACING, w, DOT_SPACING do
		for y = DOT_SPACING, h, DOT_SPACING do
			idx = idx + 1
			if(idx > MAX_DOT_TEXTURES) then return end
			local tex = AcquireTexture()
			tex:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
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
	texturePool = {}  -- release pool references (textures are parented to gridFrame)
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
