local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Border = {}

-- ============================================================
-- OnUpdate handler for duration-based fade
-- ============================================================
-- Fades overlay alpha from 1.0 → 0.1 over the aura's full duration.

local FADE_UPDATE_INTERVAL = 0.1

local function Border_OnUpdate(overlay, elapsed)
	local border = overlay._borderRef
	if(not border or not border._start) then
		overlay:SetScript('OnUpdate', nil)
		return
	end

	border._elapsed = (border._elapsed or 0) + elapsed
	if(border._elapsed < FADE_UPDATE_INTERVAL) then return end
	border._elapsed = 0

	local remain = border._duration - (GetTime() - border._start)
	if(remain < 0) then remain = 0 end
	overlay:SetAlpha(remain / border._duration * 0.9 + 0.1)
end

-- ============================================================
-- Border methods
-- ============================================================
-- Uses four individual edge textures at OVERLAY layer so this
-- border is independent of any backdrop the parent may have.

local BorderMethods = {}

--- Set border color on all four edges and show them.
--- @param r number
--- @param g number
--- @param b number
--- @param a? number
function BorderMethods:SetColor(r, g, b, a)
	a = a or 1
	self._top:SetColorTexture(r, g, b, a)
	self._bottom:SetColorTexture(r, g, b, a)
	self._left:SetColorTexture(r, g, b, a)
	self._right:SetColorTexture(r, g, b, a)
	self._top:Show()
	self._bottom:Show()
	self._left:Show()
	self._right:Show()
end

--- Start duration-based fade from 1.0 → 0.1 over the aura lifetime.
--- @param duration number Total aura duration in seconds
--- @param expirationTime number Absolute expiration from GetTime()
function BorderMethods:SetCooldown(duration, expirationTime)
	if(not self._fadeOut or not duration or duration <= 0) then
		self._overlay:SetScript('OnUpdate', nil)
		self._start = nil
		self._duration = nil
		self._overlay:SetAlpha(1)
		return
	end

	self._start    = expirationTime - duration
	self._duration = duration
	self._elapsed  = FADE_UPDATE_INTERVAL  -- update immediately on first tick
	self._overlay:SetScript('OnUpdate', Border_OnUpdate)
end

--- Set border thickness in pixels and re-anchor edges.
--- @param px number Thickness (default 2)
function BorderMethods:SetThickness(px)
	px = px or 2
	self._thickness = px

	local top    = self._top
	local bottom = self._bottom
	local left   = self._left
	local right  = self._right
	local parent = self._parent

	-- Top edge: full width, `px` pixels tall, anchored to top
	top:SetPoint('TOPLEFT',  parent, 'TOPLEFT',  0,   0)
	top:SetPoint('TOPRIGHT', parent, 'TOPRIGHT',  0,   0)
	top:SetHeight(px)

	-- Bottom edge: full width, `px` pixels tall, anchored to bottom
	bottom:SetPoint('BOTTOMLEFT',  parent, 'BOTTOMLEFT',  0, 0)
	bottom:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', 0, 0)
	bottom:SetHeight(px)

	-- Left edge: inset between top/bottom edges, `px` pixels wide
	left:SetPoint('TOPLEFT',    parent, 'TOPLEFT',    0, -px)
	left:SetPoint('BOTTOMLEFT', parent, 'BOTTOMLEFT', 0,  px)
	left:SetWidth(px)

	-- Right edge: inset between top/bottom edges, `px` pixels wide
	right:SetPoint('TOPRIGHT',    parent, 'TOPRIGHT',    0, -px)
	right:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', 0,  px)
	right:SetWidth(px)
end

--- Hide all edges and stop any fade.
function BorderMethods:Clear()
	self._overlay:SetScript('OnUpdate', nil)
	self._start = nil
	self._duration = nil
	self._overlay:SetAlpha(1)
	self._top:Hide()
	self._bottom:Hide()
	self._left:Hide()
	self._right:Hide()
end

--- Show all edges (restores visibility without changing color).
function BorderMethods:Show()
	self._top:Show()
	self._bottom:Show()
	self._left:Show()
	self._right:Show()
end

--- Hide all edges (alias for Clear without the reset semantics).
function BorderMethods:Hide()
	self:Clear()
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a Border indicator: four OVERLAY edge textures on `parent`.
--- All edges are hidden by default; call SetColor to show them.
--- @param parent Frame The frame to border
--- @param config? table { borderThickness = number, fadeOut = boolean }
--- @return table border
function F.Indicators.Border.Create(parent, config)
	config = config or {}
	local thickness = config.borderThickness or 2
	local fadeOut   = config.fadeOut or false

	-- Overlay frame at a high level so border draws above child frames
	local overlay = CreateFrame('Frame', nil, parent)
	overlay:SetAllPoints(parent)
	overlay:SetFrameLevel(parent:GetFrameLevel() + 10)

	local function MakeEdge()
		local t = overlay:CreateTexture(nil, 'OVERLAY')
		t:SetColorTexture(1, 1, 1, 1)
		t:Hide()
		return t
	end

	local top    = MakeEdge()
	local bottom = MakeEdge()
	local left   = MakeEdge()
	local right  = MakeEdge()

	local border = {
		_parent    = overlay,
		_overlay   = overlay,
		_top       = top,
		_bottom    = bottom,
		_left      = left,
		_right     = right,
		_thickness = thickness,
		_fadeOut   = fadeOut,
	}

	overlay._borderRef = border

	for k, v in next, BorderMethods do
		border[k] = v
	end

	border:SetThickness(thickness)
	return border
end
