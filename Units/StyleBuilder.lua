local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.StyleBuilder = {}

-- ============================================================
-- Status Icon Default Positions / Sizes
-- Shared between StyleBuilder (layout) and Settings UI (defaults).
-- ============================================================

local ICON_DEFAULTS = {
	role       = { point = 'TOPLEFT',     x = 2,   y = -2, size = 12 },
	leader     = { point = 'TOPLEFT',     x = 16,  y = -2, size = 12 },
	readyCheck = { point = 'CENTER',      x = 0,   y = 0,  size = 16 },
	raidIcon   = { point = 'TOP',         x = 0,   y = -2, size = 16 },
	combat     = { point = 'TOPRIGHT',    x = -2,  y = -2, size = 12 },
	resting    = { point = 'BOTTOMLEFT',  x = 2,   y = 2,  size = 12 },
	phase      = { point = 'CENTER',      x = 0,   y = 0,  size = 16 },
	resurrect  = { point = 'CENTER',      x = 0,   y = 0,  size = 16 },
	summon     = { point = 'CENTER',      x = 0,   y = 0,  size = 16 },
	raidRole   = { point = 'BOTTOMRIGHT', x = -2,  y = 2,  size = 12 },
	pvp        = { point = 'BOTTOMLEFT',  x = 2,   y = 2,  size = 16 },
}

F.StyleBuilder.ICON_DEFAULTS = ICON_DEFAULTS

-- ============================================================
-- Default Config Template
-- ============================================================

local DEFAULT_CONFIG = {
	width  = 200,
	height = 40,
	health = {
		colorMode          = 'class',
		colorThreat        = false,
		smooth             = true,
		customColor        = { 0.2, 0.8, 0.2 },
		gradientColor1     = { 0.2, 0.8, 0.2 },
		gradientThreshold1 = 95,
		gradientColor2     = { 0.9, 0.6, 0.1 },
		gradientThreshold2 = 50,
		gradientColor3     = { 0.8, 0.1, 0.1 },
		gradientThreshold3 = 5,
		lossColorMode      = 'dark',
		lossCustomColor    = { 0.15, 0.15, 0.15 },
		lossGradientColor1     = { 0.1, 0.4, 0.1 },
		lossGradientThreshold1 = 95,
		lossGradientColor2     = { 0.4, 0.25, 0.05 },
		lossGradientThreshold2 = 50,
		lossGradientColor3     = { 0.4, 0.05, 0.05 },
		lossGradientThreshold3 = 5,
		showText           = false,
		textFormat         = 'percent',
		textColorMode      = 'white',
		fontSize           = C.Font.sizeSmall,
		textAnchor         = 'CENTER',
		textAnchorX        = 0,
		textAnchorY        = 0,
		outline            = '',
		shadow             = true,
		attachedToName     = false,
		healPrediction     = true,
		healPredictionMode = 'all',
		damageAbsorb       = true,
		healAbsorb         = true,
		overAbsorb         = true,
	},
	power = {
		height         = 2,
		showText       = false,
		textFormat     = 'current',
		textColorMode  = 'white',
		fontSize       = C.Font.sizeSmall,
		textAnchor     = 'CENTER',
		textAnchorX    = 0,
		textAnchorY    = 0,
		outline        = '',
		shadow         = true,
	},
	name = {
		colorMode = 'class',
		fontSize  = C.Font.sizeNormal,
		anchor    = 'CENTER',
		anchorX   = 0,
		anchorY   = 0,
		outline   = '',
		shadow    = true,
	},
	castbar         = nil,
	portrait        = nil,
	threat          = { aggroBlink = false },
	range           = { outsideAlpha = 0.4 },
	statusIcons = {
		role       = true,
		leader     = true,
		readyCheck = true,
		raidIcon   = true,
		combat     = false,
		resting    = false,
		phase      = true,
		resurrect  = true,
		summon     = true,
		raidRole   = true,
		pvp        = false,
	},
	statusText          = true,
	targetHighlight     = true,
	mouseoverHighlight  = true,
}

-- ============================================================
-- Unit-Type Presets
-- ============================================================

F.StyleBuilder.Presets = {}

-- player — full UI: castbar, portrait, combat icon
do
	local p = F.DeepCopy(DEFAULT_CONFIG)
	p.castbar = {
		height   = 16,
		showIcon = true,
		showText = true,
		showTime = true,
	}
	p.portrait = { type = '2D' }
	p.statusIcons.combat  = true
	p.statusIcons.resting = true
	p.buffs = {
		enabled    = true,
		indicators = {},
	}
	p.debuffs = {
		enabled              = true,
		iconSize             = 14,
		bigIconSize          = 18,
		maxDisplayed         = 6,
		showDuration         = true,
		showAnimation        = true,
		orientation          = 'RIGHT',
		anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
		frameLevel           = 5,
		onlyDispellableByMe  = false,
		stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
		                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
		                         color = { 1, 1, 1, 1 } },
		durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
	}
	F.StyleBuilder.Presets['player'] = p
end

-- target — castbar, portrait
do
	local p = F.DeepCopy(DEFAULT_CONFIG)
	p.castbar = {
		height   = 16,
		showIcon = true,
		showText = true,
		showTime = true,
	}
	p.portrait = { type = '2D' }
	p.buffs = {
		enabled    = true,
		indicators = {},
	}
	p.debuffs = {
		enabled              = true,
		iconSize             = 14,
		bigIconSize          = 18,
		maxDisplayed         = 6,
		showDuration         = true,
		showAnimation        = true,
		orientation          = 'RIGHT',
		anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
		frameLevel           = 5,
		onlyDispellableByMe  = false,
		stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
		                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
		                         color = { 1, 1, 1, 1 } },
		durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
	}
	F.StyleBuilder.Presets['target'] = p
end

-- targettarget — minimal, no castbar/portrait
do
	local p = F.DeepCopy(DEFAULT_CONFIG)
	p.width  = 120
	p.height = 24
	p.castbar  = nil
	p.portrait = nil
	F.StyleBuilder.Presets['targettarget'] = p
end

-- focus — castbar
do
	local p = F.DeepCopy(DEFAULT_CONFIG)
	p.width  = 150
	p.height = 30
	p.castbar = {
		height   = 14,
		showIcon = true,
		showText = true,
		showTime = true,
	}
	p.buffs = {
		enabled    = true,
		indicators = {},
	}
	p.debuffs = {
		enabled              = true,
		iconSize             = 14,
		bigIconSize          = 18,
		maxDisplayed         = 6,
		showDuration         = true,
		showAnimation        = true,
		orientation          = 'RIGHT',
		anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
		frameLevel           = 5,
		onlyDispellableByMe  = false,
		stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
		                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
		                         color = { 1, 1, 1, 1 } },
		durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
	}
	F.StyleBuilder.Presets['focus'] = p
end

-- pet — minimal, no castbar/portrait
do
	local p = F.DeepCopy(DEFAULT_CONFIG)
	p.width  = 120
	p.height = 24
	p.castbar  = nil
	p.portrait = nil
	F.StyleBuilder.Presets['pet'] = p
end

-- party — health text (percent), role icon
do
	local p = F.DeepCopy(DEFAULT_CONFIG)
	p.width  = 120
	p.height = 36
	p.name.fontSize     = C.Font.sizeSmall
	p.health.showText   = true
	p.health.textFormat = 'percent'
	p.statusIcons.role  = true
	p.buffs = {
		enabled    = true,
		indicators = {},
	}
	p.debuffs = {
		enabled              = true,
		iconSize             = 16,
		bigIconSize          = 22,
		maxDisplayed         = 3,
		showDuration         = true,
		showAnimation        = true,
		orientation          = 'RIGHT',
		anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
		frameLevel           = 5,
		onlyDispellableByMe  = false,
		stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
		                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
		                         color = { 1, 1, 1, 1 } },
		durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
	}
	p.raidDebuffs = {
		enabled        = true,
		iconSize       = 16,
		bigIconSize    = 20,
		maxDisplayed   = 1,
		showDuration   = true,
		showAnimation  = true,
		orientation    = 'RIGHT',
		anchor         = { 'CENTER', nil, 'CENTER', 0, 0 },
		frameLevel     = 6,
		stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
		                   anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
		                   color = { 1, 1, 1, 1 } },
		durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
	}
	p.dispellable = {
		enabled              = true,
		onlyDispellableByMe  = false,
		highlightType        = 'gradient_half',
		iconSize             = 16,
		anchor               = { 'CENTER', nil, 'CENTER', 0, 0 },
		frameLevel           = 7,
	}
	p.missingBuffs = {
		iconSize      = 12,
		frameLevel    = 5,
		anchor        = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 2 },
		growDirection  = 'RIGHT',
		spacing       = 1,
		glowType      = 'Pixel',
		glowColor     = { 1, 0.8, 0, 1 },
	}
	p.privateAuras = { iconSize = 16 }
	F.StyleBuilder.Presets['party'] = p
end

-- raid — compact, health text (percent), role icon
do
	local p = F.DeepCopy(DEFAULT_CONFIG)
	p.width  = 72
	p.height = 36
	p.name.fontSize     = C.Font.sizeSmall
	p.health.showText   = true
	p.health.textFormat = 'percent'
	p.statusIcons.role  = true
	p.castbar  = nil
	p.portrait = nil
	p.buffs = {
		enabled    = true,
		indicators = {},
	}
	p.debuffs = {
		enabled              = true,
		iconSize             = 14,
		bigIconSize          = 18,
		maxDisplayed         = 1,
		showDuration         = true,
		showAnimation        = true,
		orientation          = 'RIGHT',
		anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
		frameLevel           = 5,
		onlyDispellableByMe  = false,
		stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
		                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
		                         color = { 1, 1, 1, 1 } },
		durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
	}
	p.raidDebuffs = {
		enabled        = true,
		iconSize       = 14,
		bigIconSize    = 18,
		maxDisplayed   = 1,
		showDuration   = true,
		showAnimation  = true,
		orientation    = 'RIGHT',
		anchor         = { 'CENTER', nil, 'CENTER', 0, 0 },
		frameLevel     = 6,
		stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
		                   anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
		                   color = { 1, 1, 1, 1 } },
		durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
	}
	p.dispellable = {
		enabled              = true,
		onlyDispellableByMe  = false,
		highlightType        = 'gradient_half',
		iconSize             = 14,
		anchor               = { 'CENTER', nil, 'CENTER', 0, 0 },
		frameLevel           = 7,
	}
	p.privateAuras = { iconSize = 14 }
	F.StyleBuilder.Presets['raid'] = p
end

-- boss — castbar, health text
do
	local p = F.DeepCopy(DEFAULT_CONFIG)
	p.width  = 150
	p.height = 30
	p.health.showText   = true
	p.health.textFormat = 'current'
	p.castbar = {
		height   = 14,
		showIcon = true,
		showText = true,
		showTime = true,
	}
	p.buffs = {
		enabled    = true,
		indicators = {},
	}
	p.debuffs = {
		enabled              = true,
		iconSize             = 14,
		bigIconSize          = 18,
		maxDisplayed         = 4,
		showDuration         = true,
		showAnimation        = true,
		orientation          = 'RIGHT',
		anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
		frameLevel           = 5,
		onlyDispellableByMe  = false,
		stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
		                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
		                         color = { 1, 1, 1, 1 } },
		durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
	}
	F.StyleBuilder.Presets['boss'] = p
end

-- arena — castbar, health text
do
	local p = F.DeepCopy(DEFAULT_CONFIG)
	p.width  = 150
	p.height = 30
	p.health.showText   = true
	p.health.textFormat = 'current'
	p.castbar = {
		height   = 14,
		showIcon = true,
		showText = true,
		showTime = true,
	}
	p.debuffs = {
		enabled              = true,
		iconSize             = 14,
		bigIconSize          = 18,
		maxDisplayed         = 4,
		showDuration         = true,
		showAnimation        = true,
		orientation          = 'RIGHT',
		anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
		frameLevel           = 5,
		onlyDispellableByMe  = false,
		stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
		                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
		                         color = { 1, 1, 1, 1 } },
		durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
	}
	p.dispellable = {
		enabled              = true,
		onlyDispellableByMe  = false,
		highlightType        = 'gradient_half',
		iconSize             = 14,
		anchor               = { 'CENTER', nil, 'CENTER', 0, 0 },
		frameLevel           = 7,
	}
	F.StyleBuilder.Presets['arena'] = p
end

-- ============================================================
-- Power Color Overrides
-- Blizzard's PowerBarColor.MANA is pure blue (0,0,1) which has
-- very low perceived luminance and is nearly invisible on thin
-- bars. Override with a lighter, more visible blue.
-- ============================================================

do
	local oUF = F.oUF
	if(oUF and oUF.colors and oUF.colors.power) then
		local manaColor = oUF:CreateColor(0.0, 0.44, 0.87)
		oUF.colors.power.MANA = manaColor
		oUF.colors.power[Enum.PowerType.Mana or 0] = manaColor
	end
end

-- ============================================================
-- GetConfig
-- Returns the effective unit config for a unit type.
-- Uses the runtime active preset (from AutoSwitch), with derived fallback.
-- ============================================================

function F.StyleBuilder.GetConfig(unitType)
	local presetName = F.AutoSwitch.GetCurrentPreset()
	local _, presetData = F.AutoSwitch.ResolvePreset(presetName)

	if(presetData and presetData.unitConfigs and presetData.unitConfigs[unitType]) then
		return presetData.unitConfigs[unitType]
	end

	-- Current preset doesn't have this unitType (e.g. 'Solo' has no party config).
	-- Find the canonical preset that owns it via PresetInfo.groupKey so user
	-- customisations saved under that preset are still respected on reload.
	for name, info in next, C.PresetInfo do
		if(info.groupKey == unitType) then
			local _, groupData = F.AutoSwitch.ResolvePreset(name)
			if(groupData and groupData.unitConfigs and groupData.unitConfigs[unitType]) then
				return groupData.unitConfigs[unitType]
			end
			break
		end
	end

	-- Fall back to built-in preset
	if(F.StyleBuilder.Presets[unitType]) then
		return F.StyleBuilder.Presets[unitType]
	end

	return DEFAULT_CONFIG
end

-- ============================================================
-- GetAuraConfig
-- Returns the effective aura config for a unit type and aura type.
-- @param unitType  string  e.g. 'player', 'party', 'raid'
-- @param auraType  string  e.g. 'buffs', 'debuffs', 'raidDebuffs'
-- ============================================================

function F.StyleBuilder.GetAuraConfig(unitType, auraType)
	local presetName = F.AutoSwitch.GetCurrentPreset()
	local _, presetData = F.AutoSwitch.ResolvePreset(presetName)

	if(presetData and presetData.auras and presetData.auras[unitType]) then
		return presetData.auras[unitType][auraType] or {}
	end

	-- Current preset doesn't have auras for this unitType — check canonical preset
	for name, info in next, C.PresetInfo do
		if(info.groupKey == unitType) then
			local _, groupData = F.AutoSwitch.ResolvePreset(name)
			if(groupData and groupData.auras and groupData.auras[unitType]) then
				return groupData.auras[unitType][auraType] or {}
			end
			break
		end
	end

	-- Fall back to built-in preset config fields.
	-- Presets define aura configs directly as top-level keys (e.g., preset.buffs,
	-- preset.debuffs) rather than under a nested .auras table.
	local preset = F.StyleBuilder.Presets[unitType]
	if(preset and preset[auraType]) then
		return preset[auraType]
	end

	return {}
end

--- Iterate all oUF frames matching a unit type.
--- @param unitType string  'player'|'party'|'raid'|'arena'|'boss'
--- @param callback function(frame)
function F.StyleBuilder.ForEachFrame(unitType, callback)
	local oUF = F.oUF
	for _, frame in next, oUF.objects do
		if(frame._framedUnitType == unitType) then
			callback(frame)
		end
	end
end

-- ============================================================
-- Apply
-- Composes all Phase 3A elements onto an oUF frame.
-- @param self      Frame   The oUF unit frame
-- @param unit      string  Unit token (e.g., 'player', 'party1')
-- @param config    table   Config returned by GetConfig (or a custom table)
-- @param unitType  string  Unit type key (e.g., 'player', 'party', 'raid')
-- ============================================================

function F.StyleBuilder.Apply(self, unit, config, unitType)

	-- Store unit type for live config lookups
	self._framedUnitType = unitType

	-- Register for all mouse button clicks (WoW 10.0+ defaults to LeftButtonUp only)
	self:RegisterForClicks('AnyUp')

	-- --------------------------------------------------------
	-- 1. Size the frame
	-- --------------------------------------------------------

	Widgets.SetSize(self, config.width, config.height)

	-- --------------------------------------------------------
	-- 2. Dark background texture
	-- --------------------------------------------------------

	local bg = self:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(self)
	bg:SetTexture([[Interface\BUTTONS\WHITE8x8]])
	local bgC = C.Colors.background
	bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

	-- --------------------------------------------------------
	-- 3. Calculate health / power bar heights
	-- --------------------------------------------------------

	local powerHeight  = config.power and config.power.height or 0
	local healthHeight = config.height - powerHeight
	local powerPosition = config.power and config.power.position or 'bottom'

	-- --------------------------------------------------------
	-- 4. Core element setup
	-- --------------------------------------------------------

	-- Health bar
	F.Elements.Health.Setup(self, config.width, healthHeight, config.health)

	-- Power bar
	F.Elements.Power.Setup(self, config.width, powerHeight, config.power)
	self.Power._wrapper:ClearAllPoints()

	if(powerPosition == 'top') then
		self.Health._wrapper:SetPoint('TOPLEFT', self, 'TOPLEFT', 0, -powerHeight)
		self.Power._wrapper:SetPoint('TOPLEFT', self, 'TOPLEFT', 0, 0)
	else
		self.Health._wrapper:SetPoint('TOPLEFT', self, 'TOPLEFT', 0, 0)
		self.Power._wrapper:SetPoint('TOPLEFT', self.Health._wrapper, 'BOTTOMLEFT', 0, 0)
	end

	-- Name text — positioned on the health bar region (default: center)
	local nameCfg = F.DeepCopy(config.name)
	local nameAnchorPt = nameCfg.anchor or 'CENTER'
	local nameAnchorX  = nameCfg.anchorX or 0
	local nameAnchorY  = nameCfg.anchorY or 0
	nameCfg.anchor = { nameAnchorPt, self.Health._wrapper, nameAnchorPt, nameAnchorX, nameAnchorY }
	F.Elements.Name.Setup(self, nameCfg)

	-- Health text attached to name — anchor health text to right of name
	if(config.health and config.health.attachedToName and self.Name and self.Health and self.Health.text) then
		self.Health.text:ClearAllPoints()
		self.Health.text:SetPoint('LEFT', self.Name, 'RIGHT', 2, 0)
	end

	-- Range — alpha fade when unit is out of range
	F.Elements.Range.Setup(self, config.range)

	-- Threat indicator (optional)
	if(config.threat) then
		F.Elements.Threat.Setup(self, config.threat)
	end

	-- Castbar (optional)
	if(config.castbar) then
		local cbCfg   = config.castbar
		local cbWidth  = (cbCfg.sizeMode == 'detached' and cbCfg.width) or config.width
		local cbHeight = cbCfg.height or 16
		F.Elements.Castbar.Setup(self, cbWidth, cbHeight, cbCfg)
		-- Position the castbar below the unit frame by default
		self.Castbar._wrapper:ClearAllPoints()
		self.Castbar._wrapper:SetPoint('TOP', self, 'BOTTOM', 0, -(C.Spacing.base))
	end

	-- Portrait (optional)
	if(config.portrait) then
		local portraitSize = config.height
		F.Elements.Portrait.Setup(self, portraitSize, portraitSize, config.portrait)
		-- Default position: to the left of the unit frame
		if(self.Portrait) then
			self.Portrait:ClearAllPoints()
			self.Portrait:SetPoint('TOPRIGHT', self, 'TOPLEFT', -(C.Spacing.base), 0)
		end
	end

	-- Health prediction is now handled entirely by Health.lua's Setup
	-- via the healPrediction, damageAbsorb, healAbsorb, overAbsorb config keys.

	-- --------------------------------------------------------
	-- 5. Status icons
	-- --------------------------------------------------------

	-- Icon overlay frame: sits above health/power wrappers so icon
	-- textures aren't hidden behind child frames of the unit frame.
	if(not self._iconOverlay) then
		local overlay = CreateFrame('Frame', nil, self)
		overlay:SetAllPoints(self)
		overlay:SetFrameLevel(self:GetFrameLevel() + 6)
		self._iconOverlay = overlay
	end

	local icons = config.statusIcons
	if(icons) then
		-- Helper: build point/size from per-icon config with ICON_DEFAULTS fallback
		local function iconCfg(key)
			local d = ICON_DEFAULTS[key]
			local pt = icons[key .. 'Point'] or d.point
			local x  = icons[key .. 'X']     or d.x
			local y  = icons[key .. 'Y']     or d.y
			local sz = icons[key .. 'Size']  or d.size
			return { size = sz, point = { pt, self, pt, x, y } }
		end

		if(icons.role) then
			F.Elements.RoleIcon.Setup(self, iconCfg('role'))
		end

		if(icons.leader) then
			F.Elements.LeaderIcon.Setup(self, iconCfg('leader'))
		end

		if(icons.readyCheck) then
			F.Elements.ReadyCheck.Setup(self, iconCfg('readyCheck'))
		end

		if(icons.raidIcon) then
			F.Elements.RaidIcon.Setup(self, iconCfg('raidIcon'))
		end

		if(icons.combat) then
			F.Elements.CombatIcon.Setup(self, iconCfg('combat'))
		end

		if(icons.resting) then
			F.Elements.RestingIcon.Setup(self, iconCfg('resting'))
		end

		if(icons.phase) then
			F.Elements.PhaseIcon.Setup(self, iconCfg('phase'))
		end

		if(icons.resurrect) then
			F.Elements.ResurrectIcon.Setup(self, iconCfg('resurrect'))
		end

		if(icons.summon) then
			F.Elements.SummonIcon.Setup(self, iconCfg('summon'))
		end

		if(icons.raidRole) then
			F.Elements.RaidRoleIcon.Setup(self, iconCfg('raidRole'))
		end

		if(icons.pvp) then
			F.Elements.PvPIcon.Setup(self, iconCfg('pvp'))
		end
	end

	-- --------------------------------------------------------
	-- 6. Status overlays
	-- --------------------------------------------------------

	if(config.statusText) then
		F.Elements.StatusText.Setup(self)
	end

	if(config.targetHighlight) then
		local thColor = F.Config and F.Config:Get('general.targetHighlightColor')
		local thWidth = F.Config and F.Config:Get('general.targetHighlightWidth')
		F.Elements.TargetHighlight.Setup(self, {
			color     = thColor,
			thickness = thWidth,
		})
	end

	if(config.mouseoverHighlight) then
		local moColor = F.Config and F.Config:Get('general.mouseoverHighlightColor')
		local moWidth = F.Config and F.Config:Get('general.mouseoverHighlightWidth')
		F.Elements.MouseoverHighlight.Setup(self, {
			color     = moColor,
			thickness = moWidth,
		})
	end

	-- --------------------------------------------------------
	-- 7. Aura elements (sourced from preset.auras[unitType])
	-- --------------------------------------------------------

	local buffsConfig = F.StyleBuilder.GetAuraConfig(unitType, 'buffs')
	if(buffsConfig and buffsConfig.enabled and F.Elements.Buffs) then
		F.Elements.Buffs.Setup(self, buffsConfig)
	end

	local debuffsConfig = F.StyleBuilder.GetAuraConfig(unitType, 'debuffs')
	if(debuffsConfig and debuffsConfig.enabled and F.Elements.Debuffs) then
		F.Elements.Debuffs.Setup(self, debuffsConfig)
	end

	local raidDebuffsConfig = F.StyleBuilder.GetAuraConfig(unitType, 'raidDebuffs')
	if(raidDebuffsConfig and raidDebuffsConfig.enabled and F.Elements.RaidDebuffs) then
		F.Elements.RaidDebuffs.Setup(self, raidDebuffsConfig)
	end

	local dispellableConfig = F.StyleBuilder.GetAuraConfig(unitType, 'dispellable')
	if(dispellableConfig and dispellableConfig.enabled and F.Elements.Dispellable) then
		F.Elements.Dispellable.Setup(self, dispellableConfig)
	end

	local missingBuffsConfig = F.StyleBuilder.GetAuraConfig(unitType, 'missingBuffs')
	if(missingBuffsConfig and next(missingBuffsConfig) and F.Elements.MissingBuffs) then
		F.Elements.MissingBuffs.Setup(self, missingBuffsConfig)
	end

	local targetedSpellsConfig = F.StyleBuilder.GetAuraConfig(unitType, 'targetedSpells')
	if(targetedSpellsConfig and targetedSpellsConfig.enabled and F.Elements.TargetedSpells) then
		F.Elements.TargetedSpells.Setup(self, targetedSpellsConfig)
	end

	local privateAurasConfig = F.StyleBuilder.GetAuraConfig(unitType, 'privateAuras')
	if(privateAurasConfig and next(privateAurasConfig) and F.Elements.PrivateAuras) then
		F.Elements.PrivateAuras.Setup(self, privateAurasConfig)
	end

	-- Externals (optional)
	local externalsConfig = F.StyleBuilder.GetAuraConfig(unitType, 'externals')
	if(externalsConfig and externalsConfig.enabled and F.Elements.Externals) then
		F.Elements.Externals.Setup(self, externalsConfig)
	end

	-- Defensives (optional)
	local defensivesConfig = F.StyleBuilder.GetAuraConfig(unitType, 'defensives')
	if(defensivesConfig and defensivesConfig.enabled and F.Elements.Defensives) then
		F.Elements.Defensives.Setup(self, defensivesConfig)
	end

	-- Loss of Control
	local locConfig = F.StyleBuilder.GetAuraConfig(unitType, 'lossOfControl')
	if(locConfig and locConfig.enabled) then
		F.Elements.LossOfControl.Setup(self, locConfig)
	end

	-- Crowd Control
	local ccConfig = F.StyleBuilder.GetAuraConfig(unitType, 'crowdControl')
	if(ccConfig and ccConfig.enabled) then
		F.Elements.CrowdControl.Setup(self, ccConfig)
	end

	-- --------------------------------------------------------
	-- 8. Register with pixel updater
	-- --------------------------------------------------------

	Widgets.AddToPixelUpdater_Auto(self)
end

-- ============================================================
-- Live config updates for highlight appearance
-- ============================================================

local HIGHLIGHT_TARGET_KEYS = {
	['general.targetHighlightColor'] = true,
	['general.targetHighlightWidth'] = true,
}
local HIGHLIGHT_MOUSEOVER_KEYS = {
	['general.mouseoverHighlightColor'] = true,
	['general.mouseoverHighlightWidth'] = true,
}

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local isTarget = HIGHLIGHT_TARGET_KEYS[path]
	local isMouseover = HIGHLIGHT_MOUSEOVER_KEYS[path]
	if(not isTarget and not isMouseover) then return end

	local oUF = F.oUF
	if(not oUF or not oUF.objects) then return end

	for _, frame in next, oUF.objects do
		if(isTarget and frame.FramedTargetHighlight) then
			F.Elements.TargetHighlight.UpdateAppearance(frame.FramedTargetHighlight)
		end
		if(isMouseover and frame.FramedMouseoverHighlight) then
			F.Elements.MouseoverHighlight.UpdateAppearance(frame.FramedMouseoverHighlight)
		end
	end
end, 'StyleBuilder.HighlightConfig')

-- ============================================================
-- Live config updates for text properties (font size, anchor)
-- ============================================================

F.EventBus:Register('CONFIG_CHANGED', function(path, value)
	-- Match: presets.<preset>.unitConfigs.<unitType>.<section>.<key>
	local editPreset, unitType, remainder = path:match('presets%.([^.]+)%.unitConfigs%.([^.]+)%.(.+)')
	if(not unitType) then
		unitType, remainder = path:match('unitConfigs%.([^.]+)%.(.+)')
	end
	if(not unitType) then return end

	-- Only apply when editing the active preset
	if(editPreset and editPreset ~= F.AutoSwitch.GetCurrentPreset()) then return end

	local oUF = F.oUF
	if(not oUF or not oUF.objects) then return end

	local fontPath = F.Media.GetActiveFont()

	for _, frame in next, oUF.objects do
		if(frame._framedUnitType == unitType) then

			-- ── Name text ────────────────────────────────
			if(remainder == 'name.fontSize' and frame.Name) then
				local _, _, flags = frame.Name:GetFont()
				frame.Name:SetFont(fontPath, value, flags or '')
				frame.Name._fontSize = value
			elseif(remainder == 'name.anchor' and frame.Name and frame.Health) then
				local anchor = frame.Health._wrapper or frame.Health
				frame.Name:ClearAllPoints()
				local x = frame.Name._anchorX or 0
				local y = frame.Name._anchorY or 0
				frame.Name:SetPoint(value, anchor, value, x, y)
				frame.Name._anchorPoint = value
				-- Re-anchor health text if attached
				if(frame.Health._attachedToName and frame.Health.text) then
					frame.Health.text:ClearAllPoints()
					frame.Health.text:SetPoint('LEFT', frame.Name, 'RIGHT', 2, 0)
				end
			elseif(remainder == 'name.anchorX' and frame.Name and frame.Health) then
				local anchor = frame.Health._wrapper or frame.Health
				frame.Name._anchorX = value
				local pt = frame.Name._anchorPoint or 'CENTER'
				local y  = frame.Name._anchorY or 0
				frame.Name:ClearAllPoints()
				frame.Name:SetPoint(pt, anchor, pt, value, y)
			elseif(remainder == 'name.anchorY' and frame.Name and frame.Health) then
				local anchor = frame.Health._wrapper or frame.Health
				frame.Name._anchorY = value
				local pt = frame.Name._anchorPoint or 'CENTER'
				local x  = frame.Name._anchorX or 0
				frame.Name:ClearAllPoints()
				frame.Name:SetPoint(pt, anchor, pt, x, value)
			elseif(remainder == 'name.colorMode' and frame.Name) then
				-- Update name color mode and recolor immediately
				frame.Name._config.colorMode = value
				local unit = frame:GetAttribute('unit')
				if(value == 'white') then
					local tc = C.Colors.textActive
					frame.Name:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
				elseif(value == 'dark') then
					frame.Name:SetTextColor(0.25, 0.25, 0.25, 1)
				elseif(value == 'custom') then
					local cc = frame.Name._config.customColor or { 1, 1, 1 }
					frame.Name:SetTextColor(cc[1], cc[2], cc[3], cc[4] or 1)
				elseif(value == 'class' and unit) then
					local _, class = UnitClass(unit)
					if(class) then
						local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
						if(classColor) then
							frame.Name:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
						end
					end
				end
			elseif(remainder == 'name.customColor' and frame.Name) then
				frame.Name._config.customColor = value
				if(frame.Name._config.colorMode == 'custom') then
					frame.Name:SetTextColor(value[1], value[2], value[3], value[4] or 1)
				end
			elseif(remainder == 'name.outline' and frame.Name) then
				local _, size = frame.Name:GetFont()
				frame.Name:SetFont(fontPath, size or C.Font.sizeNormal, value or '')
				frame.Name._fontFlags = value or ''
			elseif(remainder == 'name.shadow' and frame.Name) then
				if(value) then
					frame.Name:SetShadowOffset(1, -1)
				else
					frame.Name:SetShadowOffset(0, 0)
				end

			-- ── Health text ──────────────────────────────
			elseif(remainder == 'health.fontSize' and frame.Health and frame.Health.text) then
				local _, _, flags = frame.Health.text:GetFont()
				frame.Health.text:SetFont(fontPath, value, flags or '')
				frame.Health.text._fontSize = value
			elseif(remainder == 'health.textAnchor' and frame.Health and frame.Health.text and not frame.Health._attachedToName) then
				local anchor = frame.Health._wrapper or frame.Health
				local x = frame.Health.text._anchorX or 0
				local y = frame.Health.text._anchorY or 0
				frame.Health.text:ClearAllPoints()
				frame.Health.text:SetPoint(value, anchor, value, x, y)
				frame.Health.text._anchorPoint = value
			elseif(remainder == 'health.textAnchorX' and frame.Health and frame.Health.text and not frame.Health._attachedToName) then
				local anchor = frame.Health._wrapper or frame.Health
				frame.Health.text._anchorX = value
				local pt = frame.Health.text._anchorPoint or 'CENTER'
				local y  = frame.Health.text._anchorY or 0
				frame.Health.text:ClearAllPoints()
				frame.Health.text:SetPoint(pt, anchor, pt, value, y)
			elseif(remainder == 'health.textAnchorY' and frame.Health and frame.Health.text and not frame.Health._attachedToName) then
				local anchor = frame.Health._wrapper or frame.Health
				frame.Health.text._anchorY = value
				local pt = frame.Health.text._anchorPoint or 'CENTER'
				local x  = frame.Health.text._anchorX or 0
				frame.Health.text:ClearAllPoints()
				frame.Health.text:SetPoint(pt, anchor, pt, x, value)
			elseif(remainder == 'health.outline' and frame.Health and frame.Health.text) then
				local _, size = frame.Health.text:GetFont()
				frame.Health.text:SetFont(fontPath, size or C.Font.sizeSmall, value or '')
				frame.Health.text._fontFlags = value or ''
			elseif(remainder == 'health.shadow' and frame.Health and frame.Health.text) then
				if(value) then
					frame.Health.text:SetShadowOffset(1, -1)
				else
					frame.Health.text:SetShadowOffset(0, 0)
				end
			elseif(remainder == 'health.textColorMode' and frame.Health) then
				frame.Health._textColorMode = value
				if(frame.Health.text) then
					if(value == 'class') then
						local unit = frame:GetAttribute('unit')
						if(unit) then
							local _, class = UnitClass(unit)
							if(class) then
								local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
								if(classColor) then
									frame.Health.text:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
								end
							end
						end
					elseif(value == 'dark') then
						frame.Health.text:SetTextColor(0.25, 0.25, 0.25, 1)
					elseif(value == 'custom') then
						local cc = frame.Health._textCustomColor or { 1, 1, 1 }
						frame.Health.text:SetTextColor(cc[1], cc[2], cc[3], 1)
					else
						local tc = C.Colors.textActive
						frame.Health.text:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
					end
				end
			elseif(remainder == 'health.textCustomColor' and frame.Health) then
				frame.Health._textCustomColor = value
				if(frame.Health.text and frame.Health._textColorMode == 'custom') then
					frame.Health.text:SetTextColor(value[1], value[2], value[3], 1)
				end

			-- ── Power text ───────────────────────────────
			elseif(remainder == 'power.fontSize' and frame.Power and frame.Power.text) then
				local _, _, flags = frame.Power.text:GetFont()
				frame.Power.text:SetFont(fontPath, value, flags or '')
				frame.Power.text._fontSize = value
			elseif(remainder == 'power.textAnchor' and frame.Power and frame.Power.text) then
				local anchor = frame.Power._wrapper or frame.Power
				local x = frame.Power.text._anchorX or 0
				local y = frame.Power.text._anchorY or 0
				frame.Power.text:ClearAllPoints()
				frame.Power.text:SetPoint(value, anchor, value, x, y)
				frame.Power.text._anchorPoint = value
			elseif(remainder == 'power.textAnchorX' and frame.Power and frame.Power.text) then
				local anchor = frame.Power._wrapper or frame.Power
				frame.Power.text._anchorX = value
				local pt = frame.Power.text._anchorPoint or 'CENTER'
				local y  = frame.Power.text._anchorY or 0
				frame.Power.text:ClearAllPoints()
				frame.Power.text:SetPoint(pt, anchor, pt, value, y)
			elseif(remainder == 'power.textAnchorY' and frame.Power and frame.Power.text) then
				local anchor = frame.Power._wrapper or frame.Power
				frame.Power.text._anchorY = value
				local pt = frame.Power.text._anchorPoint or 'CENTER'
				local x  = frame.Power.text._anchorX or 0
				frame.Power.text:ClearAllPoints()
				frame.Power.text:SetPoint(pt, anchor, pt, x, value)
			elseif(remainder == 'power.outline' and frame.Power and frame.Power.text) then
				local _, size = frame.Power.text:GetFont()
				frame.Power.text:SetFont(fontPath, size or C.Font.sizeSmall, value or '')
				frame.Power.text._fontFlags = value or ''
			elseif(remainder == 'power.shadow' and frame.Power and frame.Power.text) then
				if(value) then
					frame.Power.text:SetShadowOffset(1, -1)
				else
					frame.Power.text:SetShadowOffset(0, 0)
				end
			elseif(remainder == 'power.textColorMode' and frame.Power) then
				frame.Power._textColorMode = value
				if(frame.Power.text) then
					if(value == 'class') then
						local unit = frame:GetAttribute('unit')
						if(unit) then
							local _, class = UnitClass(unit)
							if(class) then
								local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
								if(classColor) then
									frame.Power.text:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
								end
							end
						end
					elseif(value == 'dark') then
						frame.Power.text:SetTextColor(0.25, 0.25, 0.25, 1)
					elseif(value == 'custom') then
						local cc = frame.Power._textCustomColor or { 1, 1, 1 }
						frame.Power.text:SetTextColor(cc[1], cc[2], cc[3], 1)
					else
						local tc = C.Colors.textActive
						frame.Power.text:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
					end
				end
			elseif(remainder == 'power.textCustomColor' and frame.Power) then
				frame.Power._textCustomColor = value
				if(frame.Power.text and frame.Power._textColorMode == 'custom') then
					frame.Power.text:SetTextColor(value[1], value[2], value[3], 1)
				end
			end
		end
	end
end, 'StyleBuilder.TextConfig')

-- ============================================================
-- Live config updates for health bar / loss color modes
-- ============================================================

local HEALTH_COLOR_KEYS = {
	['health.colorMode']          = true,
	['health.colorThreat']        = true,
	['health.customColor']        = true,
	['health.gradientColor1']     = true,
	['health.gradientColor2']     = true,
	['health.gradientColor3']     = true,
	['health.gradientThreshold1'] = true,
	['health.gradientThreshold2'] = true,
	['health.gradientThreshold3'] = true,
	['health.lossColorMode']          = true,
	['health.lossCustomColor']        = true,
	['health.lossGradientColor1']     = true,
	['health.lossGradientColor2']     = true,
	['health.lossGradientColor3']     = true,
	['health.lossGradientThreshold1'] = true,
	['health.lossGradientThreshold2'] = true,
	['health.lossGradientThreshold3'] = true,
}

--- Rebuild the colorSmooth curve on a frame from its current config.
local function rebuildHealthCurve(frame, cfg)
	if(not rawget(frame, 'colors')) then
		frame.colors = setmetatable({}, { __index = F.oUF.colors })
	end
	if(not rawget(frame.colors, 'health')) then
		frame.colors.health = F.oUF:CreateColor(0.2, 0.8, 0.2)
	end
	frame.colors.health:SetCurve({
		[(cfg.gradientThreshold3 or 5)  / 100] = CreateColor(unpack(cfg.gradientColor3 or { 0.8, 0.1, 0.1 })),
		[(cfg.gradientThreshold2 or 50) / 100] = CreateColor(unpack(cfg.gradientColor2 or { 0.9, 0.6, 0.1 })),
		[(cfg.gradientThreshold1 or 95) / 100] = CreateColor(unpack(cfg.gradientColor1 or { 0.2, 0.8, 0.2 })),
	})
end

F.EventBus:Register('CONFIG_CHANGED', function(path, value)
	local editPreset, unitType, remainder = path:match('presets%.([^.]+)%.unitConfigs%.([^.]+)%.(.+)')
	if(not unitType) then
		unitType, remainder = path:match('unitConfigs%.([^.]+)%.(.+)')
	end
	if(not unitType or not HEALTH_COLOR_KEYS[remainder]) then return end

	-- Only apply when editing the active preset
	if(editPreset and editPreset ~= F.AutoSwitch.GetCurrentPreset()) then return end

	local oUF = F.oUF
	if(not oUF or not oUF.objects) then return end

	for _, frame in next, oUF.objects do
		if(frame._framedUnitType == unitType and frame.Health) then
			local health = frame.Health

			if(remainder == 'health.colorThreat') then
				health.colorThreat = value
			elseif(remainder == 'health.colorMode') then
				-- Update mutable state for PostUpdate
				health._colorMode = value

				-- Reset all color flags
				health.colorClass  = false
				health.colorSmooth = false
				health.UpdateColor = nil  -- restore oUF default

				if(value == 'class') then
					health.colorClass = true
				elseif(value == 'gradient') then
					health.colorSmooth = true
					-- Rebuild curve from current config
					local cfg = F.StyleBuilder.GetConfig(unitType)
					rebuildHealthCurve(frame, cfg.health or {})
				else
					-- dark / custom — no oUF concept
					health.UpdateColor = function() end
				end
			elseif(remainder == 'health.customColor') then
				health._customColor = value
			elseif(remainder == 'health.lossColorMode') then
				health._lossColorMode = value
			elseif(remainder == 'health.lossCustomColor') then
				health._lossCustomColor = value
			elseif(remainder:match('^health%.lossGradient')) then
				-- Loss gradient color/threshold changed — update mutable state
				local field = remainder:match('^health%.(.+)$')
				if(field) then
					health['_' .. field] = value
				end
			elseif(remainder:match('^health%.gradient')) then
				-- Gradient color/threshold changed — rebuild the curve
				if(health.colorSmooth) then
					local cfg = F.StyleBuilder.GetConfig(unitType)
					rebuildHealthCurve(frame, cfg.health or {})
				end
			end

			-- Force oUF to re-run Health:Update → PostUpdate with new config
			local unit = frame.unit or frame:GetAttribute('unit')
			if(unit) then
				health:ForceUpdate()
			end
		end
	end
end, 'StyleBuilder.HealthColorConfig')

-- ============================================================
-- Live config updates for aura elements
-- ============================================================

local AURA_ELEMENT_MAP = {
	debuffs        = 'FramedDebuffs',
	externals      = 'FramedExternals',
	defensives     = 'FramedDefensives',
	raidDebuffs    = 'FramedRaidDebuffs',
	dispellable    = 'FramedDispellable',
	targetedSpells = 'FramedTargetedSpells',
}

-- Structural BorderIcon config keys — if these change, wipe and recreate pool
local STRUCTURAL_KEYS = {
	showStacks   = true,
	showDuration = true,
	showCooldown = true,
	frameLevel   = true,
}

--- Wipe and clear all BorderIcon pool entries so they are recreated
--- with fresh config on the next Update call.
local function wipePool(element)
	if(not element._pool) then return end
	for _, bi in next, element._pool do
		bi:Clear()
	end
	wipe(element._pool)
end

--- Reposition a container frame from an anchor config table.
local function repositionContainer(element, anchor)
	if(not element._container or not anchor) then return end
	element._container:ClearAllPoints()
	Widgets.SetPoint(element._container, anchor[1], nil, anchor[3], anchor[4] or 0, anchor[5] or 0)
end

F.EventBus:Register('CONFIG_CHANGED', function(path)
	-- Match: presets.<preset>.auras.<unitType>.<auraType>[.<subKey>]
	local editPreset, unitType, remainder = path:match('^presets%.([^.]+)%.auras%.([^.]+)%.(.+)$')
	-- Only apply when editing the active preset
	if(editPreset and editPreset ~= F.AutoSwitch.GetCurrentPreset()) then return end
	if(not unitType or not remainder) then return end

	-- Extract aura type (first segment) and optional sub-key
	local auraType = remainder:match('^([^.]+)')
	if(not auraType) then return end

	local elementKey = AURA_ELEMENT_MAP[auraType]
	if(not elementKey) then return end

	local oUF = F.oUF
	if(not oUF or not oUF.objects) then return end

	-- Fetch fresh config once
	local newConfig = F.StyleBuilder.GetAuraConfig(unitType, auraType)
	if(not newConfig) then return end

	-- Determine if this is a structural change (sub-key after auraType)
	local subKey = remainder:match('^[^.]+%.(.+)$')
	local isStructural = subKey and STRUCTURAL_KEYS[subKey]

	for _, frame in next, oUF.objects do
		if(frame._framedUnitType == unitType) then
			local element = frame[elementKey]
			if(not element) then break end

			-- ── _config-based elements (Debuffs, Externals, Defensives, RaidDebuffs) ──
			if(element._config) then
				element._config = newConfig

				-- Reposition container if anchor changed
				if(not subKey or subKey == 'anchor') then
					repositionContainer(element, newConfig.anchor)
				end

				-- Structural change → wipe pool so new entries get fresh config
				if(isStructural) then
					wipePool(element)
				end

				if(element.ForceUpdate) then
					element:ForceUpdate()
				end

			-- ── Dispellable (individual properties) ──
			elseif(elementKey == 'FramedDispellable') then
				element._onlyDispellableByMe = newConfig.onlyDispellableByMe or false
				element._showPhysicalDebuffs = newConfig.showPhysicalDebuffs ~= false
				element._highlightType       = newConfig.highlightType or C.HighlightType.GRADIENT_FULL

				-- Resize icon
				if(element._borderIcon and newConfig.iconSize) then
					element._borderIcon:SetSize(newConfig.iconSize)
				end

				-- Reposition icon
				if(newConfig.anchor and element._borderIcon) then
					element._borderIcon:ClearAllPoints()
					element._borderIcon:SetPoint(unpack(newConfig.anchor))
				end

				if(element.ForceUpdate) then
					element:ForceUpdate()
				end

			-- ── TargetedSpells (individual properties) ──
			elseif(elementKey == 'FramedTargetedSpells') then
				element._maxDisplayed = newConfig.maxDisplayed or 1
				element._borderColor  = newConfig.borderColor

				-- Glow properties
				local glowCfg = newConfig.glow or {}
				element._glowColor = glowCfg.color or C.Colors.accent
				element._glowType  = glowCfg.type or C.GlowType.PROC
				if(glowCfg.lines or glowCfg.frequency or glowCfg.length or glowCfg.thickness
					or glowCfg.particles or glowCfg.scale) then
					element._glowConfig = {
						lines     = glowCfg.lines,
						frequency = glowCfg.frequency,
						length    = glowCfg.length,
						thickness = glowCfg.thickness,
						particles = glowCfg.particles,
						scale     = glowCfg.scale,
					}
				else
					element._glowConfig = nil
				end

				-- Resize pool icons
				if(newConfig.iconSize and element._pool) then
					for _, bi in next, element._pool do
						bi:SetSize(newConfig.iconSize)
					end
				end

				-- Update glow type if changed
				if(element._glow) then
					element._glow:SetGlowType(element._glowType)
				end

				if(element.ForceUpdate) then
					element:ForceUpdate()
				end
			end
		end
	end
end, 'StyleBuilder.AuraConfig')
