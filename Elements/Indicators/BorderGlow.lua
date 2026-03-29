local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.Indicators = F.Indicators or {}
F.Indicators.BorderGlow = {}

-- ============================================================
-- LibCustomGlow — optional dependency
-- Safe access: nil if the library is not embedded.
-- ============================================================

local LCG = LibStub and LibStub('LibCustomGlow-1.0', true)

-- ============================================================
-- OnUpdate handler for duration-based fade
-- ============================================================
-- Fades the active frame alpha from 1.0 → 0.1 over the aura's full duration.

local FADE_UPDATE_INTERVAL = 0.1

local function Fade_OnUpdate(frame, elapsed)
	local bg = frame._bgRef
	if(not bg or not bg._start) then
		frame:SetScript('OnUpdate', nil)
		return
	end

	bg._elapsed = (bg._elapsed or 0) + elapsed
	if(bg._elapsed < FADE_UPDATE_INTERVAL) then return end
	bg._elapsed = 0

	local remain = bg._duration - (GetTime() - bg._start)
	if(remain < 0) then remain = 0 end
	frame:SetAlpha(remain / bg._duration * 0.9 + 0.1)
end

-- ============================================================
-- Internal LCG helpers
-- ============================================================

--- Start the appropriate LCG glow variant on `parent`.
--- @param parent Frame
--- @param glowType string C.GlowType variant string
--- @param color table {r,g,b,a}
--- @param glowConfig? table optional per-type config (lines, frequency, length, thickness)
local function LCG_Start(parent, glowType, color, glowConfig)
	if(glowType == C.GlowType.PIXEL) then
		local cfg = glowConfig or {}
		LCG.PixelGlow_Start(parent, color, cfg.lines, cfg.frequency, cfg.length, cfg.thickness, nil, nil)
	elseif(glowType == C.GlowType.SOFT) then
		local cfg = glowConfig or {}
		LCG.AutoCastGlow_Start(parent, color, cfg.particles, cfg.frequency, cfg.scale)
	elseif(glowType == C.GlowType.SHINE) then
		local cfg = glowConfig or {}
		LCG.ButtonGlow_Start(parent, color, cfg.frequency)
	else
		-- Default: Proc / ButtonGlow
		local cfg = glowConfig or {}
		LCG.ButtonGlow_Start(parent, color, cfg.frequency)
	end
end

--- Stop the appropriate LCG glow variant on `parent`.
--- @param parent Frame
--- @param glowType string C.GlowType variant string
local function LCG_Stop(parent, glowType)
	if(glowType == C.GlowType.PIXEL) then
		LCG.PixelGlow_Stop(parent)
	elseif(glowType == C.GlowType.SOFT) then
		LCG.AutoCastGlow_Stop(parent)
	elseif(glowType == C.GlowType.SHINE) then
		LCG.ButtonGlow_Stop(parent)
	else
		LCG.ButtonGlow_Stop(parent)
	end
end

-- ============================================================
-- BorderGlow methods
-- ============================================================

local BorderGlowMethods = {}

--- Set border color on all four edges and show them (Border mode).
--- In Glow mode, stores the color for use on next Start() call.
--- @param r number
--- @param g number
--- @param b number
--- @param a? number
function BorderGlowMethods:SetColor(r, g, b, a)
	if(self._mode == 'Glow') then
		self._color = { r, g, b, a or 1 }
		return
	end

	-- Border mode
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

--- Start the LCG glow effect (Glow mode only).
--- @param color? table {r,g,b,a} — defaults to stored _color
--- @param glowType? string C.GlowType variant — defaults to stored _glowType
--- @param glowConfig? table optional per-type config (lines, frequency, length, thickness)
function BorderGlowMethods:Start(color, glowType, glowConfig)
	if(self._mode ~= 'Glow') then return end

	color    = color    or self._color
	glowType = glowType or self._glowType

	-- Stop previous glow if already active (type may have changed)
	if(self._glowActive) then
		self:_StopCurrentGlow()
	end

	self._color      = color
	self._glowType   = glowType
	self._glowConfig = glowConfig

	if(LCG) then
		LCG_Start(self._glowFrame, glowType, color, glowConfig)
	end

	self._glowActive = true
end

--- Stop the LCG glow effect (Glow mode only).
function BorderGlowMethods:Stop()
	if(self._mode ~= 'Glow') then return end
	if(not self._glowActive) then return end

	self:_StopCurrentGlow()
	self._glowActive = false
end

--- Internal: stop whatever LCG variant is currently running.
function BorderGlowMethods:_StopCurrentGlow()
	if(LCG) then
		LCG_Stop(self._glowFrame, self._glowType)
	end
end

--- Start duration-based fade from 1.0 → 0.1 over the aura lifetime.
--- @param duration number Total aura duration in seconds
--- @param expirationTime number Absolute expiration from GetTime()
function BorderGlowMethods:SetCooldown(duration, expirationTime)
	local fadeFrame = (self._mode == 'Glow') and self._glowFrame or self._overlay

	if(not self._fadeOut or not duration or duration <= 0) then
		fadeFrame:SetScript('OnUpdate', nil)
		self._start    = nil
		self._duration = nil
		fadeFrame:SetAlpha(1)
		return
	end

	self._start    = expirationTime - duration
	self._duration = duration
	self._elapsed  = FADE_UPDATE_INTERVAL  -- update immediately on first tick
	fadeFrame:SetScript('OnUpdate', Fade_OnUpdate)
end

--- Set border thickness in pixels and re-anchor edges (Border mode only).
--- @param px number Thickness (default 2)
function BorderGlowMethods:SetThickness(px)
	if(self._mode ~= 'Border') then return end

	px = px or 2
	self._thickness = px

	local top    = self._top
	local bottom = self._bottom
	local left   = self._left
	local right  = self._right
	local parent = self._parent

	-- Top edge: full width, `px` pixels tall, anchored to top
	top:SetPoint('TOPLEFT',  parent, 'TOPLEFT',  0, 0)
	top:SetPoint('TOPRIGHT', parent, 'TOPRIGHT',  0, 0)
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

--- Hide everything, stop fade, stop glow.
function BorderGlowMethods:Clear()
	if(self._mode == 'Glow') then
		if(self._glowActive) then
			self:_StopCurrentGlow()
			self._glowActive = false
		end
		self._glowFrame:SetScript('OnUpdate', nil)
		self._start    = nil
		self._duration = nil
		self._glowFrame:SetAlpha(1)
	else
		-- Border mode
		self._overlay:SetScript('OnUpdate', nil)
		self._start    = nil
		self._duration = nil
		self._overlay:SetAlpha(1)
		self._top:Hide()
		self._bottom:Hide()
		self._left:Hide()
		self._right:Hide()
	end
end

--- Show border edges (Border mode only).
function BorderGlowMethods:Show()
	if(self._mode ~= 'Border') then return end
	self._top:Show()
	self._bottom:Show()
	self._left:Show()
	self._right:Show()
end

--- Hide everything (alias for Clear).
function BorderGlowMethods:Hide()
	self:Clear()
end

--- Return whether the border is shown or glow is active.
--- @return boolean
function BorderGlowMethods:IsActive()
	if(self._mode == 'Glow') then
		return self._glowActive
	end
	-- Border mode: active if any edge is shown
	return self._top:IsShown() or false
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a BorderGlow indicator supporting Border and Glow rendering modes.
--- Border mode: four OVERLAY edge textures on an overlay frame.
--- Glow mode: LibCustomGlow effects attached to a dedicated glow frame.
--- Both modes share duration-based fade logic via Fade_OnUpdate.
--- @param parent Frame The frame to border or glow
--- @param config? table {
---   borderGlowMode = 'Border'|'Glow',
---   borderThickness = number,
---   fadeOut = boolean,
---   color = {r,g,b,a},
---   glowType = C.GlowType,
---   glowColor = {r,g,b,a},
--- }
--- @return table borderGlow
function F.Indicators.BorderGlow.Create(parent, config)
	config = config or {}

	local mode      = config.borderGlowMode or 'Border'
	local fadeOut   = config.fadeOut or false
	local thickness = config.borderThickness or 2

	local frameLevel = parent:GetFrameLevel() + 10

	local bg = {
		_mode      = mode,
		_parent    = parent,
		_fadeOut   = fadeOut,
		_thickness = thickness,
	}

	if(mode == 'Glow') then
		-- Glow mode: dedicated frame for LCG effects and fade
		local glowFrame = CreateFrame('Frame', nil, parent)
		glowFrame:SetAllPoints(parent)
		glowFrame:SetFrameLevel(frameLevel)
		glowFrame._bgRef = bg

		bg._glowFrame  = glowFrame
		bg._glowType   = config.glowType or C.GlowType.PROC
		bg._color      = config.glowColor or C.Colors.accent
		bg._glowActive = false
	else
		-- Border mode: overlay frame with four edge textures
		local overlay = CreateFrame('Frame', nil, parent)
		overlay:SetAllPoints(parent)
		overlay:SetFrameLevel(frameLevel)
		overlay._bgRef = bg

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

		bg._overlay = overlay
		bg._top     = top
		bg._bottom  = bottom
		bg._left    = left
		bg._right   = right

		if(config.color) then
			local c = config.color
			bg._top:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
			bg._bottom:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
			bg._left:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
			bg._right:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
		end
	end

	for k, v in next, BorderGlowMethods do
		bg[k] = v
	end

	if(mode == 'Border') then
		bg:SetThickness(thickness)
	end

	return bg
end
