local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- AnchorPicker — 3x3 anchor grid with X/Y offset inputs
-- and a mini frame preview dot.
-- ============================================================

-- Grid layout constants
local BUTTON_SIZE  = 16   -- px per anchor button
local BUTTON_GAP   = 2    -- px gap between buttons
local GRID_COLS    = 3
local GRID_ROWS    = 3
local SLIDER_H     = 26   -- matches B.SLIDER_H (labelH + track + gap)
local PREVIEW_W    = 40
local PREVIEW_H    = 30
local DOT_SIZE     = 4
local SECTION_GAP  = 6    -- vertical gap between grid and offset row

-- 3x3 grid order: row-major, top-left to bottom-right
local ANCHOR_GRID = {
	'TOPLEFT',    'TOP',    'TOPRIGHT',
	'LEFT',       'CENTER', 'RIGHT',
	'BOTTOMLEFT', 'BOTTOM', 'BOTTOMRIGHT',
}

-- Abbreviated labels drawn inside each button
local ANCHOR_LABELS = {
	TOPLEFT     = 'TL',
	TOP         = 'T',
	TOPRIGHT    = 'TR',
	LEFT        = 'L',
	CENTER      = 'C',
	RIGHT       = 'R',
	BOTTOMLEFT  = 'BL',
	BOTTOM      = 'B',
	BOTTOMRIGHT = 'BR',
}

-- Relative dot position within the preview (0-1 range, origin = top-left)
local ANCHOR_PREVIEW_POS = {
	TOPLEFT     = { 0,    1    },
	TOP         = { 0.5,  1    },
	TOPRIGHT    = { 1,    1    },
	LEFT        = { 0,    0.5  },
	CENTER      = { 0.5,  0.5  },
	RIGHT       = { 1,    0.5  },
	BOTTOMLEFT  = { 0,    0    },
	BOTTOM      = { 0.5,  0    },
	BOTTOMRIGHT = { 1,    0    },
}

local BLACK = { 0, 0, 0, 1 }

-- ============================================================
-- Anchor button helpers
-- ============================================================

local function ApplyButtonSelected(btn, selected)
	if(selected) then
		local a = C.Colors.accent
		btn:SetBackdropColor(a[1] * 0.3, a[2] * 0.3, a[3] * 0.3, 1)
		btn:SetBackdropBorderColor(1, 1, 1, 1)
		if(btn._label) then
			btn._label:SetTextColor(1, 1, 1, 1)
		end
	else
		local w = C.Colors.widget
		btn:SetBackdropColor(w[1], w[2], w[3], w[4] or 1)
		btn:SetBackdropBorderColor(0, 0, 0, 1)
		if(btn._label) then
			local ts = C.Colors.textSecondary
			btn._label:SetTextColor(ts[1], ts[2], ts[3], ts[4] or 1)
		end
	end
end

local function CreateAnchorButton(parent, point)
	local btn = CreateFrame('Button', nil, parent, 'BackdropTemplate')
	btn._bgColor     = C.Colors.widget
	btn._borderColor = BLACK
	btn.point        = point

	Widgets.ApplyBackdrop(btn, C.Colors.widget, BLACK)
	Widgets.SetSize(btn, BUTTON_SIZE, BUTTON_SIZE)
	btn:EnableMouse(true)

	local lbl = Widgets.CreateFontString(btn, 8, C.Colors.textSecondary)
	lbl:SetPoint('CENTER', btn, 'CENTER', 0, 0)
	lbl:SetText(ANCHOR_LABELS[point] or '?')
	btn._label = lbl

	btn:SetScript('OnEnter', function(self)
		if(not self._selected) then
			Widgets.SetBackdropHighlight(self, true)
		end
	end)

	btn:SetScript('OnLeave', function(self)
		if(not self._selected) then
			Widgets.SetBackdropHighlight(self, false)
		end
	end)

	ApplyButtonSelected(btn, false)
	return btn
end

-- ============================================================
-- Preview dot update
-- ============================================================

local function UpdatePreviewDot(picker)
	local pos = ANCHOR_PREVIEW_POS[picker._point]
	if(not pos or not picker._previewDot) then return end

	local previewFrame = picker._previewFrame
	local dot          = picker._previewDot

	-- Position dot relative to preview interior (1px inset for border)
	local insetW = PREVIEW_W - 2
	local insetH = PREVIEW_H - 2

	local dotX = 1 + pos[1] * (insetW - DOT_SIZE)
	local dotY = -(1 + (1 - pos[2]) * (insetH - DOT_SIZE))

	dot:ClearAllPoints()
	dot:SetPoint('TOPLEFT', previewFrame, 'TOPLEFT', dotX, dotY)
end

-- ============================================================
-- Public constructor
-- ============================================================

--- Create an anchor picker widget.
--- @param parent Frame   Parent frame
--- @param width  number  Total logical width (defaults to 120)
--- @return Frame picker  Widget with AnchorPicker API
function Widgets.CreateAnchorPicker(parent, width)
	width = width or 120

	-- Grid pixel span
	local gridSpan = GRID_COLS * BUTTON_SIZE + (GRID_COLS - 1) * BUTTON_GAP

	-- Total height: grid rows + gap + two sliders
	local gridH    = GRID_ROWS * BUTTON_SIZE + (GRID_ROWS - 1) * BUTTON_GAP
	local totalH   = gridH + SECTION_GAP + SLIDER_H + SECTION_GAP + SLIDER_H

	local picker = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(picker, width, totalH)
	Widgets.ApplyBaseMixin(picker)

	picker._point   = 'CENTER'
	picker._offsetX = 0
	picker._offsetY = 0
	picker._buttons = {}

	-- --------------------------------------------------------
	-- 3x3 grid of anchor buttons
	-- --------------------------------------------------------
	local gridFrame = CreateFrame('Frame', nil, picker)
	gridFrame:SetPoint('TOPLEFT', picker, 'TOPLEFT', 0, 0)
	gridFrame:SetSize(gridSpan, gridH)
	picker._gridFrame = gridFrame

	for i, point in next, ANCHOR_GRID do
		local col = (i - 1) % GRID_COLS          -- 0-based
		local row = math.floor((i - 1) / GRID_COLS)  -- 0-based

		local btn = CreateAnchorButton(gridFrame, point)
		local bx  = col * (BUTTON_SIZE + BUTTON_GAP)
		local by  = -(row * (BUTTON_SIZE + BUTTON_GAP))
		btn:SetPoint('TOPLEFT', gridFrame, 'TOPLEFT', bx, by)

		btn:SetScript('OnClick', function(self)
			picker:_SelectPoint(self.point)
			picker:_FireChanged()
		end)

		picker._buttons[point] = btn
	end

	-- --------------------------------------------------------
	-- Mini preview (right of grid, vertically centered)
	-- --------------------------------------------------------
	local previewFrame = CreateFrame('Frame', nil, picker, 'BackdropTemplate')
	Widgets.ApplyBackdrop(previewFrame, C.Colors.background, C.Colors.border)
	previewFrame:SetSize(PREVIEW_W, PREVIEW_H)
	-- Vertically center preview alongside the grid
	previewFrame:SetPoint('TOPLEFT', gridFrame, 'TOPRIGHT',
		SECTION_GAP, -math.floor((gridH - PREVIEW_H) / 2))
	picker._previewFrame = previewFrame

	local dot = previewFrame:CreateTexture(nil, 'OVERLAY')
	dot:SetSize(DOT_SIZE, DOT_SIZE)
	dot:SetColorTexture(
		C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
	picker._previewDot = dot

	-- --------------------------------------------------------
	-- X / Y offset sliders (below grid)
	-- --------------------------------------------------------
	local sliderW = width
	local offsetsY = -(gridH + SECTION_GAP)

	local xSlider = Widgets.CreateSlider(picker, 'X Offset', sliderW, -50, 50, 1)
	xSlider:SetPoint('TOPLEFT', picker, 'TOPLEFT', 0, offsetsY)
	xSlider:SetValue(0)
	picker._xSlider = xSlider

	local ySlider = Widgets.CreateSlider(picker, 'Y Offset', sliderW, -50, 50, 1)
	ySlider:SetPoint('TOPLEFT', picker, 'TOPLEFT', 0, offsetsY - SLIDER_H - SECTION_GAP)
	ySlider:SetValue(0)
	picker._ySlider = ySlider

	-- Wire offset callbacks
	xSlider:SetAfterValueChanged(function(value)
		picker._offsetX = value
		picker:_FireChanged()
	end)

	ySlider:SetAfterValueChanged(function(value)
		picker._offsetY = value
		picker:_FireChanged()
	end)

	-- --------------------------------------------------------
	-- Internal helpers
	-- --------------------------------------------------------

	function picker:_SelectPoint(point)
		-- Deselect previous
		local prev = self._buttons[self._point]
		if(prev) then
			prev._selected = false
			ApplyButtonSelected(prev, false)
		end
		-- Select new
		self._point = point
		local cur = self._buttons[point]
		if(cur) then
			cur._selected = true
			ApplyButtonSelected(cur, true)
		end
		UpdatePreviewDot(self)
	end

	function picker:_FireChanged()
		if(self._onChanged) then
			self._onChanged(self._point, self._offsetX, self._offsetY)
		end
	end

	-- --------------------------------------------------------
	-- Public API
	-- --------------------------------------------------------

	--- Set the current anchor point and offsets.
	--- Updates grid selection and offset inputs without firing the callback.
	--- @param point string   WoW anchor point string
	--- @param x     number   X offset
	--- @param y     number   Y offset
	function picker:SetAnchor(point, x, y)
		self:_SelectPoint(point or 'CENTER')
		self._offsetX = x or 0
		self._offsetY = y or 0
		self._xSlider:SetValue(self._offsetX)
		self._ySlider:SetValue(self._offsetY)
	end

	--- Get the current anchor point and offsets.
	--- @return string point, number x, number y
	function picker:GetAnchor()
		return self._point, self._offsetX, self._offsetY
	end

	--- Register a callback fired when anchor or offsets change.
	--- @param func function  Called with (point, x, y)
	function picker:SetOnChanged(func)
		self._onChanged = func
	end

	-- --------------------------------------------------------
	-- Initialise to CENTER with no offset
	-- --------------------------------------------------------
	picker:SetAnchor('CENTER', 0, 0)

	return picker
end
