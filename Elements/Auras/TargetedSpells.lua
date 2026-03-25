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

-- ============================================================
-- Helpers
-- ============================================================

--- Show the active incoming spell on the element's indicators.
--- @param element table
--- @param spellId number
--- @param iconTexture number|string|nil
local function showSpell(element, spellId, iconTexture)
	local displayMode = element._displayMode

	if(displayMode == DisplayMode.ICONS or displayMode == DisplayMode.BOTH) then
		if(element._borderIcon) then
			element._borderIcon:SetAura(spellId, iconTexture, 0, 0, 0, nil)
			-- Apply configured border color
			local bc = element._borderColor
			if(bc) then
				element._borderIcon:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
			end
			element._borderIcon:Show()
		end
	end

	if(displayMode == DisplayMode.BORDER_GLOW or displayMode == DisplayMode.BOTH) then
		if(element._glow) then
			element._glow:Start(element._glowColor, element._glowType, element._glowConfig)
		end
	end
end

--- Hide all indicators on the element.
--- @param element table
local function hideSpell(element)
	if(element._borderIcon) then
		element._borderIcon:Clear()
	end
	if(element._glow) then
		element._glow:Stop()
	end
end

-- ============================================================
-- Update (called by UNIT_AURA for re-validation; CLEU does
-- the real work via the listener frame)
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedTargetedSpells
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	-- If we had an active targeted spell, re-validate the source is still alive.
	-- If no active spell, nothing to do.
	if(not element._activeSourceGUID) then return end

	-- Source unit checks are not reliable from aura events; let CLEU manage state.
end

-- ============================================================
-- ForceUpdate
-- ============================================================

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

-- ============================================================
-- CLEU listener builder
-- ============================================================

--- Build and return the CLEU OnEvent handler closure for this element.
--- Closes over `ownerFrame` (the oUF unit frame).
--- @param ownerFrame Frame
--- @return function
local function makeCLEUHandler(ownerFrame)
	return function()
		local element = ownerFrame.FramedTargetedSpells
		if(not element) then return end

		local unit = ownerFrame.unit
		if(not unit) then return end

		local destGUID = UnitGUID(unit)
		if(not destGUID) then return end

		local _, subEvent, _, sourceGUID, _, _, _,
		      eventDestGUID, _, _, _, spellId, _, _ = CombatLogGetCurrentEventInfo()

		if(subEvent == 'SPELL_CAST_START') then
			if(eventDestGUID == destGUID) then
				-- Spell now targeting our unit
				local iconTexture = nil
				if(C_Spell and C_Spell.GetSpellInfo) then
					local info = C_Spell.GetSpellInfo(spellId)
					if(info) then iconTexture = info.iconID end
				elseif(GetSpellInfo) then
					local _, _, icon = GetSpellInfo(spellId)
					iconTexture = icon
				end
				element._activeSourceGUID = sourceGUID
				element._activeSpellId    = spellId
				showSpell(element, spellId, iconTexture)
			end
		elseif(subEvent == 'SPELL_CAST_STOP'
			or subEvent == 'SPELL_CAST_FAILED'
			or subEvent == 'SPELL_CAST_SUCCESS') then
			-- Clear if this is from the same source that was targeting us
			if(sourceGUID == element._activeSourceGUID) then
				element._activeSourceGUID = nil
				element._activeSpellId    = nil
				hideSpell(element)
			end
		end
	end
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
