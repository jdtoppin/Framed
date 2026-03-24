local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Glow = {}

-- ============================================================
-- LibCustomGlow — optional dependency
-- Safe access: nil if the library is not embedded.
-- ============================================================

local LCG = LibStub and LibStub('LibCustomGlow-1.0', true)

-- ============================================================
-- Internal helpers
-- ============================================================

--- Start the appropriate LCG glow variant on `parent`.
--- @param parent Frame
--- @param glowType string C.GlowType variant string
--- @param color table {r,g,b,a}
local function LCG_Start(parent, glowType, color)
	if(glowType == C.GlowType.PIXEL) then
		LCG.PixelGlow_Start(parent, color, nil, nil, nil, nil, nil, nil)
	elseif(glowType == C.GlowType.SOFT) then
		LCG.AutoCastGlow_Start(parent, color)
	else
		-- Default: Proc / ButtonGlow
		LCG.ButtonGlow_Start(parent, color)
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
	else
		LCG.ButtonGlow_Stop(parent)
	end
end

-- ============================================================
-- Glow methods
-- ============================================================

local GlowMethods = {}

--- Start the glow effect.
--- @param color? table {r,g,b,a} — defaults to config color
--- @param glowType? string C.GlowType variant — defaults to stored type
function GlowMethods:Start(color, glowType)
	color    = color    or self._color
	glowType = glowType or self._glowType

	-- Stop previous glow if already active (type may have changed)
	if(self._active) then
		self:_StopCurrent()
	end

	self._color    = color
	self._glowType = glowType

	if(LCG) then
		LCG_Start(self._parent, glowType, color)
	else
		-- Fallback: accent-colored border via Border indicator
		if(self._fallbackBorder) then
			self._fallbackBorder:SetColor(
				color[1] or 0,
				color[2] or 0.8,
				color[3] or 1,
				color[4] or 1)
		end
	end

	self._active = true
end

--- Stop the active glow effect.
function GlowMethods:Stop()
	if(not self._active) then return end
	self:_StopCurrent()
	self._active = false
end

--- Internal: stop whatever variant is currently running.
function GlowMethods:_StopCurrent()
	if(LCG) then
		LCG_Stop(self._parent, self._glowType)
	else
		if(self._fallbackBorder) then
			self._fallbackBorder:Clear()
		end
	end
end

--- Change the glow variant. If currently active, restarts with the new type.
--- @param glowType string C.GlowType variant string
function GlowMethods:SetGlowType(glowType)
	local wasActive = self._active
	local color = self._color

	if(wasActive) then
		self:Stop()
	end

	self._glowType = glowType

	if(wasActive) then
		self:Start(color, glowType)
	end
end

--- Return whether the glow is currently running.
--- @return boolean
function GlowMethods:IsActive()
	return self._active
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a Glow indicator backed by LibCustomGlow (or a border fallback).
--- @param parent Frame The frame to apply the glow to
--- @param config table { glowType = C.GlowType, color = {r,g,b,a} }
--- @return table glow
function F.Indicators.Glow.Create(parent, config)
	config = config or {}
	local glowType = config.glowType or C.GlowType.PROC
	local color    = config.color    or C.Colors.accent

	-- Build a Border indicator as the LCG fallback
	local fallbackBorder
	if(not LCG and F.Indicators.Border) then
		fallbackBorder = F.Indicators.Border.Create(parent)
	end

	local glow = {
		_parent         = parent,
		_glowType       = glowType,
		_color          = color,
		_active         = false,
		_fallbackBorder = fallbackBorder,
	}

	for k, v in next, GlowMethods do
		glow[k] = v
	end

	return glow
end
