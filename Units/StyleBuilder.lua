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
-- Returns config for the given unitType. Checks F.Config:Get('layouts')
-- first; falls back to built-in presets; falls back to DEFAULT_CONFIG.
-- ============================================================

function F.StyleBuilder.GetConfig(unitType)
	-- User-saved layout config takes priority
	local layouts = F.Config:Get('layouts')
	if(layouts and layouts[unitType]) then
		return layouts[unitType]
	end

	-- Built-in preset for this unit type
	if(F.StyleBuilder.Presets[unitType]) then
		return F.StyleBuilder.Presets[unitType]
	end

	-- Generic fallback
	return F.DeepCopy(DEFAULT_CONFIG)
end

-- ============================================================
-- Apply
-- Composes all Phase 3A elements onto an oUF frame.
-- @param self   Frame   The oUF unit frame
-- @param unit   string  Unit token (e.g., 'player', 'party1')
-- @param config table   Config returned by GetConfig (or a custom table)
-- ============================================================

function F.StyleBuilder.Apply(self, unit, config)

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
		F.Elements.TargetHighlight.Setup(self)
	end

	if(config.mouseoverHighlight) then
		F.Elements.MouseoverHighlight.Setup(self)
	end

	-- --------------------------------------------------------
	-- 7. Aura elements
	-- --------------------------------------------------------

	if(config.buffs and F.Elements.Buffs) then
		F.Elements.Buffs.Setup(self, config.buffs)
	end
	if(config.debuffs and F.Elements.Debuffs) then
		F.Elements.Debuffs.Setup(self, config.debuffs)
	end
	if(config.raidDebuffs and F.Elements.RaidDebuffs) then
		F.Elements.RaidDebuffs.Setup(self, config.raidDebuffs)
	end
	if(config.dispellable and F.Elements.Dispellable) then
		F.Elements.Dispellable.Setup(self, config.dispellable)
	end
	if(config.missingBuffs and F.Elements.MissingBuffs) then
		F.Elements.MissingBuffs.Setup(self, config.missingBuffs)
	end
	if(config.targetedSpells and F.Elements.TargetedSpells) then
		F.Elements.TargetedSpells.Setup(self, config.targetedSpells)
	end
	if(config.privateAuras and F.Elements.PrivateAuras) then
		F.Elements.PrivateAuras.Setup(self, config.privateAuras)
	end

	-- Externals (optional)
	if(config.externals and F.Elements.Externals) then
		F.Elements.Externals.Setup(self, config.externals)
	end

	-- Defensives (optional)
	if(config.defensives and F.Elements.Defensives) then
		F.Elements.Defensives.Setup(self, config.defensives)
	end

	-- --------------------------------------------------------
	-- 8. Register with pixel updater
	-- --------------------------------------------------------

	Widgets.AddToPixelUpdater_Auto(self)
end
