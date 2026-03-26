local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.StyleBuilder = {}

-- ============================================================
-- Default Config Template
-- ============================================================

local DEFAULT_CONFIG = {
	width  = 200,
	height = 40,
	health = {
		colorMode     = 'class',
		smooth        = true,
		showText      = false,
		textFormat    = 'none',
		healPrediction = true,
	},
	power = {
		height   = 2,
		showText = false,
	},
	name = {
		colorMode = 'class',
		truncate  = 12,
		fontSize  = C.Font.sizeNormal,
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
	p.statusIcons.combat = true
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
	p.missingBuffs = { iconSize = 12 }
	p.privateAuras = { iconSize = 16 }
	F.StyleBuilder.Presets['party'] = p
end

-- raid — compact, health text (percent), role icon
do
	local p = F.DeepCopy(DEFAULT_CONFIG)
	p.width  = 72
	p.height = 36
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

	-- Fall back to built-in preset config fields.
	-- Presets define aura configs directly as top-level keys (e.g., preset.buffs,
	-- preset.debuffs) rather than under a nested .auras table.
	local preset = F.StyleBuilder.Presets[unitType]
	if(preset and preset[auraType]) then
		return preset[auraType]
	end

	return {}
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
	--    Power bar sits at the bottom; health fills the rest.
	-- --------------------------------------------------------

	local powerHeight  = config.power and config.power.height or 0
	local healthHeight = config.height - powerHeight

	-- --------------------------------------------------------
	-- 4. Core element setup
	-- --------------------------------------------------------

	-- Health bar — anchored to TOPLEFT, fills frame minus power strip
	F.Elements.Health.Setup(self, config.width, healthHeight, config.health)
	self.Health._wrapper:SetPoint('TOPLEFT', self, 'TOPLEFT', 0, 0)

	-- Power bar — anchored immediately below health bar
	F.Elements.Power.Setup(self, config.width, powerHeight, config.power)
	self.Power._wrapper:ClearAllPoints()
	self.Power._wrapper:SetPoint('TOPLEFT', self, 'TOPLEFT', 0, -healthHeight)

	-- Name text — centered on the health bar region
	local nameCfg = F.DeepCopy(config.name)
	nameCfg.anchor = { 'CENTER', self.Health, 'CENTER', 0, 0 }
	F.Elements.Name.Setup(self, nameCfg)

	-- Range — alpha fade when unit is out of range
	F.Elements.Range.Setup(self, config.range)

	-- Threat indicator (optional)
	if(config.threat) then
		F.Elements.Threat.Setup(self, config.threat)
	end

	-- Castbar (optional)
	if(config.castbar) then
		local cbCfg   = config.castbar
		local cbWidth  = config.width
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

	-- Absorbs / heal prediction overlay (when healPrediction is enabled)
	if(config.health and config.health.healPrediction ~= false) then
		F.Elements.Absorbs.Setup(self, self.Health, {})
	end

	-- --------------------------------------------------------
	-- 5. Status icons
	-- --------------------------------------------------------

	local icons = config.statusIcons
	if(icons) then
		if(icons.role) then
			F.Elements.RoleIcon.Setup(self, {
				size  = 12,
				point = { 'TOPLEFT', self, 'TOPLEFT', 2, -2 },
			})
		end

		if(icons.leader) then
			-- Offset leader icon right of role icon so they don't overlap
			local leaderOffsetX = (icons.role) and 16 or 2
			F.Elements.LeaderIcon.Setup(self, {
				size  = 12,
				point = { 'TOPLEFT', self, 'TOPLEFT', leaderOffsetX, -2 },
			})
		end

		if(icons.readyCheck) then
			F.Elements.ReadyCheck.Setup(self, {
				size  = 16,
				point = { 'CENTER', self, 'CENTER', 0, 0 },
			})
		end

		if(icons.raidIcon) then
			F.Elements.RaidIcon.Setup(self, {
				size  = 16,
				point = { 'TOP', self, 'TOP', 0, -2 },
			})
		end

		if(icons.combat) then
			F.Elements.CombatIcon.Setup(self, {
				size  = 12,
				point = { 'TOPRIGHT', self, 'TOPRIGHT', -2, -2 },
			})
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
