local addonName, Framed = ...
local F = Framed

-- ============================================================
-- Aura default builders for PresetDefaults
-- Consumed by Presets/Defaults.lua via F.AuraDefaults
-- ============================================================

F.AuraDefaults = {}

-- ============================================================
-- Shared font configs
-- ============================================================

local function stackFont()
	return { size = 10, outline = 'OUTLINE', shadow = false,
	         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
	         color = { 1, 1, 1, 1 } }
end

local function durationFont()
	return { size = 10, outline = 'OUTLINE', shadow = false }
end

-- ============================================================
-- Default buff indicator (shipped on every unit type)
-- ============================================================

local function defaultBuffIndicator()
	return {
		name         = 'My Buffs',
		type         = 'Icons',
		enabled      = true,
		spells       = {},
		castBy       = 'me',
		iconWidth    = 14,
		iconHeight   = 14,
		maxDisplayed = 3,
		orientation  = 'RIGHT',
		showCooldown  = true,
		showStacks    = true,
		durationMode  = 'Never',
		durationFont  = durationFont(),
		stackFont     = stackFont(),
		glowType      = 'None',
		glowColor     = { 1, 1, 1, 1 },
		glowConfig    = {},
		numPerLine    = 0,
		spacingX      = 1,
		spacingY      = 1,
		anchor       = { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 },
		frameLevel   = 5,
	}
end

-- ============================================================
-- Debuff config builder
-- ============================================================

local function debuffConfig(iconSize, maxDisplayed)
	return {
		enabled              = true,
		iconSize             = iconSize or 14,
		bigIconSize          = 18,
		maxDisplayed         = maxDisplayed or 6,
		showDuration         = true,
		showAnimation        = true,
		orientation          = 'RIGHT',
		anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
		frameLevel           = 5,
		filterMode           = 'all',
		stackFont            = stackFont(),
		durationFont         = durationFont(),
	}
end

-- ============================================================
-- Aura sets by unit category
-- ============================================================

-- Solo/boss units: buffs + debuffs only
function F.AuraDefaults.Solo(debuffSize, debuffMax)
	return {
		buffs = { enabled = true, buffFilterMode = 'raidCombat', indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = debuffConfig(debuffSize or 14, debuffMax or 6),
		lossOfControl = {
			enabled    = false,
			iconSize   = 22,
			anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel = 30,
			types      = { 'stun', 'incapacitate', 'disorient', 'fear', 'silence', 'root' },
		},
		crowdControl = {
			enabled    = false,
			iconSize   = 22,
			anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel = 20,
			spells     = {},
		},
	}
end

-- Minimal auras for simple units (targettarget, pet)
function F.AuraDefaults.Minimal()
	return {
		buffs = { enabled = true, buffFilterMode = 'raidCombat', indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = debuffConfig(14, 3),
		lossOfControl = {
			enabled    = false,
			iconSize   = 22,
			anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel = 30,
			types      = { 'stun', 'incapacitate', 'disorient', 'fear', 'silence', 'root' },
		},
		crowdControl = {
			enabled    = false,
			iconSize   = 22,
			anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel = 20,
			spells     = {},
		},
	}
end

-- Group auras (party/raid) — full indicator set
function F.AuraDefaults.Group(sizes)
	local s = sizes or {}
	local icon     = s.iconSize or 14
	local big      = s.bigIconSize or 18
	local rd       = s.raidDebuffIcon or 22
	local rdBig    = s.raidDebuffBigIcon or big
	local ext      = s.externalsIcon or 12
	local def      = s.defensivesIcon or 12
	local extMax   = s.externalsMax or 2
	local defMax   = s.defensivesMax or 2
	local debMax   = s.debuffMax or 3
	local rdMax    = s.raidDebuffMax or 1
	local tsIcon   = s.targetedSpellsIcon or 20
	local dispIcon = s.dispellableIcon or 12

	return {
		buffs = {
			enabled = true,
			buffFilterMode = 'raidCombat',
			indicators = { ['My Buffs'] = defaultBuffIndicator() },
		},
		debuffs = {
			enabled              = true,
			iconSize             = 13,
			bigIconSize          = big,
			maxDisplayed         = debMax,
			showDuration         = true,
			showAnimation        = true,
			orientation          = 'RIGHT',
			anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 1, 4 },
			frameLevel           = 5,
			filterMode           = 'all',
			stackFont            = stackFont(),
			durationFont         = durationFont(),
		},
		raidDebuffs = {
			enabled        = true,
			iconSize       = rd,
			bigIconSize    = rdBig,
			maxDisplayed   = rdMax,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'CENTER', nil, 'CENTER', 0, 3 },
			frameLevel     = 20,
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		targetedSpells = {
			enabled       = true,
			displayMode   = 'Both',
			iconSize      = tsIcon,
			borderColor   = { 1, 0, 0, 1 },
			maxDisplayed  = 1,
			anchor        = { 'CENTER', nil, 'CENTER', 0, 6 },
			frameLevel    = 50,
			glow          = {
				type      = 'Pixel',
				color     = { 1, 0, 0, 1 },
				lines     = 8,
				frequency = 0.25,
				length    = 4,
				thickness = 2,
			},
		},
		dispellable = {
			enabled              = true,
			onlyDispellableByMe  = false,
			highlightType        = 'gradient_half',
			iconSize             = dispIcon,
			anchor               = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', 0, 4 },
			frameLevel           = 15,
		},
		externals = {
			enabled        = true,
			iconSize       = ext,
			maxDisplayed   = extMax,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'DOWN',
			anchor         = { 'RIGHT', nil, 'RIGHT', 2, 5 },
			frameLevel     = 10,
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		defensives = {
			enabled        = true,
			iconSize       = def,
			maxDisplayed   = defMax,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'DOWN',
			anchor         = { 'LEFT', nil, 'LEFT', -2, 5 },
			frameLevel     = 10,
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		missingBuffs = {
			enabled       = false,
			iconSize      = s.missingBuffsIcon or 12,
			frameLevel    = 10,
			anchor        = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 16 },
			growDirection  = 'RIGHT',
			spacing       = 1,
			glowType      = 'Pixel',
			glowColor     = { 1, 0.8, 0, 1 },
		},
		privateAuras = {
			enabled        = true,
			iconSize       = s.privateAurasIcon or 16,
			showDispelType = true,
			anchor         = { 'TOP', nil, 'TOP', 0, -3 },
			frameLevel     = 25,
		},
		lossOfControl = {
			enabled    = false,
			iconSize   = 22,
			anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel = 30,
			types      = { 'stun', 'incapacitate', 'disorient', 'fear', 'silence', 'root' },
		},
		crowdControl = {
			enabled    = false,
			iconSize   = 22,
			anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel = 20,
			spells     = {},
		},
	}
end

-- Arena enemy auras — debuffs + dispellable (from old arenaEnemyBase)
function F.AuraDefaults.Arena()
	return {
		buffs = { enabled = true, buffFilterMode = 'raidCombat', indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = {
			enabled              = true,
			iconSize             = 14,
			bigIconSize          = 18,
			maxDisplayed         = 4,
			showDuration         = true,
			showAnimation        = true,
			orientation          = 'RIGHT',
			anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
			frameLevel           = 5,
			filterMode           = 'all',
			stackFont            = stackFont(),
			durationFont         = durationFont(),
		},
		dispellable = {
			enabled              = true,
			onlyDispellableByMe  = false,
			highlightType        = 'gradient_half',
			iconSize             = 14,
			anchor               = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel           = 7,
		},
		lossOfControl = {
			enabled    = false,
			iconSize   = 22,
			anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel = 30,
			types      = { 'stun', 'incapacitate', 'disorient', 'fear', 'silence', 'root' },
		},
		crowdControl = {
			enabled    = false,
			iconSize   = 22,
			anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel = 20,
			spells     = {},
		},
	}
end

-- Boss auras — buffs + debuffs + raidDebuffs
function F.AuraDefaults.Boss()
	return {
		buffs   = { enabled = true, buffFilterMode = 'raidCombat', indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = debuffConfig(14, 4),
		raidDebuffs = {
			enabled        = true,
			iconSize       = 14,
			bigIconSize    = 18,
			maxDisplayed   = 1,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel     = 6,
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		lossOfControl = {
			enabled    = false,
			iconSize   = 22,
			anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel = 30,
			types      = { 'stun', 'incapacitate', 'disorient', 'fear', 'silence', 'root' },
		},
		crowdControl = {
			enabled    = false,
			iconSize   = 22,
			anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel = 20,
			spells     = {},
		},
	}
end
