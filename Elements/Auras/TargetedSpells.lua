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
			bi:SetAlpha(1)
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
				-- C-level: set alpha 1 if targeting this unit, 0 otherwise
				bi:SetAlphaFromBoolean(UnitIsUnit(cast.sourceUnit .. 'target', unit), 1, 0)
			end
		end
		-- Hide unused pool entries
		for i = count + 1, #pool do
			pool[i]:Clear()
			pool[i]:SetAlpha(1)
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

	-- CLEU fires without a unit argument so it cannot be registered through
	-- oUF's standard RegisterEvent. Use a dedicated listener frame instead.
	if(not element._cleuFrame) then
		local cleuFrame = CreateFrame('Frame')
		cleuFrame:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
		cleuFrame:SetScript('OnEvent', makeCLEUHandler(self))
		element._cleuFrame = cleuFrame
	end

	return true
end

local function Disable(self)
	local element = self.FramedTargetedSpells
	if(not element) then return end

	-- Tear down the CLEU listener
	if(element._cleuFrame) then
		element._cleuFrame:UnregisterAllEvents()
		element._cleuFrame:SetScript('OnEvent', nil)
		element._cleuFrame = nil
	end

	element._activeSourceGUID = nil
	element._activeSpellId    = nil
	hideSpell(element)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedTargetedSpells', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create a TargetedSpells element on a unit frame.
--- Shows a BorderIcon and/or Glow when an enemy is casting a spell at this unit.
--- Assigns result to self.FramedTargetedSpells, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: displayMode, iconSize, borderColor, anchor,
---                       frameLevel, maxDisplayed, glow = { type, color, lines, frequency, length, thickness }
function F.Elements.TargetedSpells.Setup(self, config)
	config = config or {}

	-- Backward compat: map old lowercase display mode strings to new PascalCase values
	local rawMode = config.displayMode or DisplayMode.BOTH
	local displayMode = legacyDisplayModeMap[rawMode] or rawMode

	local iconSize   = config.iconSize   or 16
	local anchor     = config.anchor     or { 'CENTER', self, 'CENTER', 0, 0 }
	local frameLevel = config.frameLevel or nil

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

	local borderIcon, glow

	if(displayMode == DisplayMode.ICONS or displayMode == DisplayMode.BOTH) then
		local biConfig = {
			showCooldown = false,
			showStacks   = false,
			showDuration = false,
			borderColor  = borderColor,
		}
		if(frameLevel) then
			biConfig.frameLevel = frameLevel
		end
		borderIcon = F.Indicators.BorderIcon.Create(self, iconSize, biConfig)
		local a = anchor
		borderIcon:SetPoint(a[1], a[2], a[3], a[4] or 0, a[5] or 0)
	end

	if(displayMode == DisplayMode.BORDER_GLOW or displayMode == DisplayMode.BOTH) then
		local glowCreateConfig = {
			glowType = glowType,
			color    = glowColor,
		}
		glow = F.Indicators.Glow.Create(self, glowCreateConfig)
	end

	local container = {
		_borderIcon       = borderIcon,
		_glow             = glow,
		_displayMode      = displayMode,
		_borderColor      = borderColor,
		_glowColor        = glowColor,
		_glowType         = glowType,
		_glowConfig       = glowConfig,
		_activeSourceGUID = nil,
		_activeSpellId    = nil,
		_cleuFrame        = nil,
	}

	self.FramedTargetedSpells = container
end
