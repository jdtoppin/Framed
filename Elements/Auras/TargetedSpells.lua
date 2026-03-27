local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.TargetedSpells = {}

-- ============================================================
-- Display mode constants
-- ============================================================

local DisplayMode = {
	BOTH        = 'Both',
	ICONS       = 'Icons',
	BORDER_GLOW = 'BorderGlow',
}

-- ============================================================
-- Backward compatibility: map old lowercase values to new
-- ============================================================

local legacyDisplayModeMap = {
	['icon']   = DisplayMode.ICONS,
	['border'] = DisplayMode.BORDER_GLOW,
	['both']   = DisplayMode.BOTH,
}

local UnitIsUnit = UnitIsUnit

-- ============================================================
-- Helpers
-- ============================================================

--- Hide all indicators on the element — pool entries + glow.
--- @param element table
local function hideAll(element)
	local pool = element._pool
	if(pool) then
		for _, bi in next, pool do
			bi:Clear()
			bi._frame:SetAlpha(1)
		end
	end
	if(element._glow) then
		element._glow:Stop()
	end
	-- Reset glow frame alpha in case SetAlphaFromBoolean was used
	if(element._glowFrame) then
		element._glowFrame:SetAlpha(1)
		element._glowFrame:Show()
	end
end

--- Display casts on this element (non-secret path).
--- @param element table
--- @param castList table  Sorted casts from CastTracker
local function showCasts(element, castList)
	local displayMode = element._displayMode
	local maxDisplayed = element._maxDisplayed or 1
	local count = math.min(#castList, maxDisplayed)
	local pool = element._pool

	-- Icons display
	if(displayMode == DisplayMode.ICONS or displayMode == DisplayMode.BOTH) then
		for i = 1, count do
			local cast = castList[i]
			local bi = pool[i]
			if(bi) then
				local duration = cast.endTime - cast.startTime
				bi.cooldown:SetReverse(not cast.isChanneling)
				bi:SetAura(cast.spellId, cast.icon, duration, cast.endTime, 0, nil)
				local bc = element._borderColor
				if(bc) then
					bi:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
				end
				bi:Show()
			end
		end
		-- Hide unused pool entries
		for i = count + 1, #pool do
			pool[i]:Clear()
		end
	end

	-- Glow display
	if(count > 0 and (displayMode == DisplayMode.BORDER_GLOW or displayMode == DisplayMode.BOTH)) then
		if(element._glow) then
			element._glow:Start(element._glowColor, element._glowType, element._glowConfig)
		end
	elseif(element._glow) then
		element._glow:Stop()
	end
end

--- Display casts on this element (secret path — uses SetAlphaFromBoolean).
--- @param element table
--- @param castList table  All active casts from CastTracker
--- @param unit string  This frame's unit token
local function showCastsSecret(element, castList, unit)
	local displayMode = element._displayMode
	local maxDisplayed = element._maxDisplayed or 1
	local count = math.min(#castList, maxDisplayed)
	local pool = element._pool

	-- Icons display
	if(displayMode == DisplayMode.ICONS or displayMode == DisplayMode.BOTH) then
		for i = 1, count do
			local cast = castList[i]
			local bi = pool[i]
			if(bi) then
				local duration = cast.endTime - cast.startTime
				bi.cooldown:SetReverse(not cast.isChanneling)
				bi:SetAura(cast.spellId, cast.icon, duration, cast.endTime, 0, nil)
				local bc = element._borderColor
				if(bc) then
					bi:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
				end
				bi:Show()
				-- Show if the caster is targeting this unit
				local targeting = UnitIsUnit(cast.sourceUnit .. 'target', unit)
				if(F.IsValueNonSecret(targeting)) then
					bi._frame:SetAlpha(targeting and 1 or 0)
				else
					bi._frame:SetAlpha(1)
				end
			end
		end
		-- Hide unused pool entries
		for i = count + 1, #pool do
			pool[i]:Clear()
			pool[i]._frame:SetAlpha(1)
		end
	end

	-- Glow display
	if(count > 0 and (displayMode == DisplayMode.BORDER_GLOW or displayMode == DisplayMode.BOTH)) then
		if(element._glow) then
			element._glow:Start(element._glowColor, element._glowType, element._glowConfig)
		end
		-- Use SetAlphaFromBoolean on the glow frame
		if(element._glowFrame) then
			element._glowFrame:Show()
			element._glowFrame:SetAlphaFromBoolean(UnitIsUnit(castList[1].sourceUnit .. 'target', unit), 1, 0)
		end
	elseif(element._glow) then
		element._glow:Stop()
		if(element._glowFrame) then
			element._glowFrame:SetAlpha(1)
		end
	end
end

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedTargetedSpells
	if(not element) then return end

	if(not unit) then unit = self.unit end
	if(not unit) then return end

	if(F.CastTracker:IsSecretPath()) then
		local allCasts = F.CastTracker:GetAllActiveCasts()
		if(#allCasts == 0) then
			hideAll(element)
		else
			showCastsSecret(element, allCasts, unit)
		end
	else
		local unitCasts = F.CastTracker:GetCastsOnUnit(unit)
		if(#unitCasts == 0) then
			hideAll(element)
		else
			showCasts(element, unitCasts)
		end
	end
end

-- ============================================================
-- ForceUpdate
-- ============================================================

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

-- ============================================================
-- Enable / Disable
-- ============================================================

local function Enable(self, unit)
	local element = self.FramedTargetedSpells
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	F.CastTracker:Register(self)

	return true
end

local function Disable(self)
	local element = self.FramedTargetedSpells
	if(not element) then return end

	F.CastTracker:Unregister(self)
	hideAll(element)
end

-- ============================================================
-- Rebuild
-- ============================================================

local function Rebuild(element, config)
	if(element._pool) then
		for _, bi in next, element._pool do
			bi:Clear()
			if(bi.Destroy) then bi:Destroy() end
		end
	end
	if(element._glow) then element._glow:Stop() end

	local displayMode  = config.displayMode  or DisplayMode.BOTH
	displayMode = legacyDisplayModeMap[displayMode] or displayMode
	local iconSize     = config.iconSize     or 16
	local maxDisplayed = config.maxDisplayed or 1
	local borderColor  = config.borderColor  or { 1, 0, 0, 1 }

	element._displayMode  = displayMode
	element._maxDisplayed = maxDisplayed
	element._borderColor  = borderColor

	local anchor = config.anchor or { 'CENTER', nil, 'CENTER', 0, 0 }

	element._pool = {}
	if(displayMode == DisplayMode.ICONS or displayMode == DisplayMode.BOTH) then
		for i = 1, maxDisplayed do
			local bi = F.Indicators.BorderIcon.Create(element.__owner, iconSize, {
				borderColor = borderColor,
			})
			local offset = (i - 1) * (iconSize + 2)
			bi:SetPoint(anchor[1], element.__owner, anchor[3] or anchor[1], (anchor[4] or 0) + offset, anchor[5] or 0)
			element._pool[i] = bi
		end
	end

	if(displayMode == DisplayMode.BORDER_GLOW or displayMode == DisplayMode.BOTH) then
		local glowConfig = config.glow or {}
		if(element._glowFrame) then
			element._glow = F.Indicators.Glow.Create(element._glowFrame, {
				glowType = glowConfig.type,
				color    = glowConfig.color,
			})
		end
		element._glowType   = glowConfig.type
		element._glowColor  = glowConfig.color
		element._glowConfig = glowConfig
	end

	element:ForceUpdate()
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedTargetedSpells', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create a TargetedSpells element on a unit frame.
--- Shows BorderIcons and/or Glow when enemies are casting at this unit.
--- Uses F.CastTracker for cast detection (not CLEU).
--- Assigns result to self.FramedTargetedSpells, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: displayMode, iconSize, borderColor, anchor,
---                       frameLevel, maxDisplayed, glow = { type, color, lines, frequency, length, thickness }
function F.Elements.TargetedSpells.Setup(self, config)
	config = config or {}

	-- Backward compat: map old lowercase display mode strings to new PascalCase values
	local rawMode = config.displayMode or DisplayMode.BOTH
	local displayMode = legacyDisplayModeMap[rawMode] or rawMode

	local iconSize     = config.iconSize     or 16
	local maxDisplayed = config.maxDisplayed  or 1
	local anchor       = config.anchor       or { 'CENTER', self, 'CENTER', 0, 0 }
	local frameLevel   = config.frameLevel   or nil

	-- Border color for the BorderIcon border
	local borderColor = config.borderColor

	-- Glow subtable
	local glowCfg   = config.glow or {}
	local glowType  = glowCfg.type  or C.GlowType.PROC
	local glowColor = glowCfg.color or C.Colors.accent
	local glowConfig = nil
	if(glowCfg.lines or glowCfg.frequency or glowCfg.length or glowCfg.thickness) then
		glowConfig = {
			lines     = glowCfg.lines,
			frequency = glowCfg.frequency,
			length    = glowCfg.length,
			thickness = glowCfg.thickness,
		}
	end

	-- Create BorderIcon pool
	local pool = {}
	if(displayMode == DisplayMode.ICONS or displayMode == DisplayMode.BOTH) then
		for i = 1, maxDisplayed do
			local biConfig = {
				showCooldown = true,
				showStacks   = false,
				showDuration = false,
				borderColor  = borderColor,
			}
			if(frameLevel) then
				biConfig.frameLevel = frameLevel
			end
			local bi = F.Indicators.BorderIcon.Create(self, iconSize, biConfig)
			local a = anchor
			local offset = (i - 1) * (iconSize + 2)
			bi:SetPoint(a[1], nil, a[3], (a[4] or 0) + offset, a[5] or 0)
			pool[i] = bi
		end
	end

	-- Create glow
	local glow, glowFrame
	if(displayMode == DisplayMode.BORDER_GLOW or displayMode == DisplayMode.BOTH) then
		-- Glow needs a dedicated wrapper frame for SetAlphaFromBoolean on secret path.
		-- Glow.Create applies glow effects to the parent frame directly (_parent),
		-- so we create a wrapper frame that the glow attaches to, and we control
		-- that wrapper's alpha via SetAlphaFromBoolean.
		glowFrame = CreateFrame('Frame', nil, self)
		glowFrame:SetAllPoints(self)
		glowFrame:SetFrameLevel(self:GetFrameLevel() + (frameLevel or 10))
		local glowCreateConfig = {
			glowType = glowType,
			color    = glowColor,
		}
		glow = F.Indicators.Glow.Create(glowFrame, glowCreateConfig)
	end

	local container = {
		_pool         = pool,
		_glow         = glow,
		_glowFrame    = glowFrame,
		_displayMode  = displayMode,
		_maxDisplayed = maxDisplayed,
		_borderColor  = borderColor,
		_glowColor    = glowColor,
		_glowType     = glowType,
		_glowConfig   = glowConfig,
		Rebuild       = Rebuild,
	}

	self.FramedTargetedSpells = container
end
