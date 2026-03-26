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
		iconSize     = 14,
		maxDisplayed = 3,
		orientation  = 'RIGHT',
		anchor       = { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 },
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
		onlyDispellableByMe  = false,
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
		buffs         = { indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs       = debuffConfig(debuffSize, debuffMax),
		lossOfControl = {},
		crowdControl  = {},
	}
end

-- Minimal auras for simple units (targettarget, pet)
function F.AuraDefaults.Minimal()
	return {
		buffs         = { indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs       = debuffConfig(14, 3),
		lossOfControl = {},
		crowdControl  = {},
	}
end

-- Group auras (party/raid) — full indicator set
function F.AuraDefaults.Group(sizes)
	local s = sizes or {}
	local icon     = s.iconSize or 14
	local big      = s.bigIconSize or 18
	local rd       = s.raidDebuffIcon or icon
	local rdBig    = s.raidDebuffBigIcon or big
	local ext      = s.externalsIcon or icon
	local def      = s.defensivesIcon or icon
	local extMax   = s.externalsMax or 2
	local defMax   = s.defensivesMax or 2
	local debMax   = s.debuffMax or 3
	local rdMax    = s.raidDebuffMax or 1
	local tsIcon   = s.targetedSpellsIcon or icon
	local dispIcon = s.dispellableIcon or icon

	return {
		buffs = { indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = {
			enabled              = true,
			iconSize             = icon,
			bigIconSize          = big,
			maxDisplayed         = debMax,
			showDuration         = true,
			showAnimation        = true,
			orientation          = 'RIGHT',
			anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
			frameLevel           = 5,
			onlyDispellableByMe  = false,
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
			anchor         = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel     = 6,
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		targetedSpells = {
			enabled       = true,
			displayMode   = 'Both',
			iconSize      = tsIcon,
			borderColor   = { 1, 0, 0, 1 },
			maxDisplayed  = 1,
			anchor        = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel    = 8,
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
			anchor               = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel           = 7,
		},
		externals = {
			enabled        = true,
			iconSize       = ext,
			maxDisplayed   = extMax,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'TOPRIGHT', nil, 'TOPRIGHT', -2, -2 },
			frameLevel     = 5,
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		defensives = {
			enabled        = true,
			iconSize       = def,
			maxDisplayed   = defMax,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 },
			frameLevel     = 5,
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		missingBuffs  = { iconSize = s.missingBuffsIcon or 12 },
		privateAuras  = { iconSize = s.privateAurasIcon or 14 },
		lossOfControl = {},
		crowdControl  = {},
	}
end

-- Arena enemy auras — debuffs + dispellable (from old arenaEnemyBase)
function F.AuraDefaults.Arena()
	return {
		buffs = { indicators = { ['My Buffs'] = defaultBuffIndicator() } },
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
			onlyDispellableByMe  = false,
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
		lossOfControl = {},
		crowdControl  = {},
	}
end

-- Boss auras — buffs + debuffs + raidDebuffs
function F.AuraDefaults.Boss()
	return {
		buffs   = { indicators = { ['My Buffs'] = defaultBuffIndicator() } },
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
		lossOfControl = {},
		crowdControl  = {},
	}
end
