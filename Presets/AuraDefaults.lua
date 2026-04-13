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
	return { size = 10, outline = 'OUTLINE', shadow = false, anchor = 'CENTER', xOffset = 0, yOffset = 0 }
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
		displayType  = 'SpellIcon',
		color        = { 1, 1, 1, 1 },
		iconWidth    = 14,
		iconHeight   = 14,
		maxDisplayed = 3,
		orientation  = 'RIGHT',
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
-- Debuff indicator config builder
-- ============================================================

local function debuffIndicator(opts)
	opts = opts or {}
	return {
		enabled       = opts.enabled ~= false,
		filterMode    = opts.filterMode or 'all',
		iconSize      = opts.iconSize or 14,
		bigIconSize   = opts.bigIconSize or 18,
		maxDisplayed  = opts.maxDisplayed or 6,
		showDuration  = true,
		showAnimation = true,
		orientation   = opts.orientation or 'RIGHT',
		anchor        = opts.anchor or { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
		frameLevel    = opts.frameLevel or 5,
		stackFont     = stackFont(),
		durationFont  = durationFont(),
	}
end

-- Debuffs config with named indicators
local function debuffConfig(iconSize, maxDisplayed)
	return {
		enabled    = true,
		indicators = {
			['General Debuffs'] = debuffIndicator({
				iconSize     = iconSize or 14,
				maxDisplayed = maxDisplayed or 6,
			}),
		},
	}
end

-- ============================================================
-- Aura sets by unit category
-- ============================================================

-- Solo units: buffs + debuffs + defensives/externals (disabled by default)
function F.AuraDefaults.Solo(debuffSize, debuffMax)
	return {
		buffs = { enabled = true, buffFilterMode = 'raidCombat', indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = debuffConfig(debuffSize or 14, debuffMax or 6),
		externals = {
			enabled        = false,
			iconSize       = 14,
			maxDisplayed   = 2,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'DOWN',
			anchor         = { 'RIGHT', nil, 'RIGHT', 2, 5 },
			frameLevel     = 10,
			visibilityMode = 'all',
			playerColor    = { 0, 0.8, 0 },
			otherColor     = { 1, 0.85, 0 },
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		defensives = {
			enabled        = false,
			iconSize       = 14,
			maxDisplayed   = 2,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'DOWN',
			anchor         = { 'LEFT', nil, 'LEFT', -2, 5 },
			frameLevel     = 10,
			visibilityMode = 'all',
			playerColor    = { 0, 0.8, 0 },
			otherColor     = { 1, 0.85, 0 },
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		dispellable = {
			enabled              = false,
			onlyDispellableByMe  = false,
			highlightType        = 'gradient_half',
			highlightAlpha       = 0.8,
			iconSize             = 12,
			anchor               = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', 0, 4 },
			frameLevel           = 15,
		},
		targetedSpells = {
			enabled       = false,
			displayMode   = 'Both',
			iconSize      = 20,
			borderColor   = { 1, 0, 0, 1 },
			maxDisplayed  = 1,
			showDuration  = true,
			durationFont  = durationFont(),
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
		privateAuras = {
			enabled        = false,
			iconSize       = 16,
			maxDisplayed   = 3,
			orientation    = 'RIGHT',
			showDispelType = true,
			anchor         = { 'TOP', nil, 'TOP', 0, -3 },
			frameLevel     = 25,
		},
		missingBuffs = {
			enabled       = false,
			iconSize      = 12,
			frameLevel    = 10,
			anchor        = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 16 },
			growDirection = 'LEFT',
			spacing       = 1,
			glowType      = 'Pixel',
			glowColor     = { 1, 0.8, 0, 1 },
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

-- Minimal auras for simple units (targettarget, pet)
function F.AuraDefaults.Minimal()
	return {
		buffs = { enabled = true, buffFilterMode = 'raidCombat', indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = debuffConfig(14, 3),
		externals = {
			enabled        = false,
			iconSize       = 12,
			maxDisplayed   = 2,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'DOWN',
			anchor         = { 'RIGHT', nil, 'RIGHT', 2, 5 },
			frameLevel     = 10,
			visibilityMode = 'all',
			playerColor    = { 0, 0.8, 0 },
			otherColor     = { 1, 0.85, 0 },
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		defensives = {
			enabled        = false,
			iconSize       = 12,
			maxDisplayed   = 2,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'DOWN',
			anchor         = { 'LEFT', nil, 'LEFT', -2, 5 },
			frameLevel     = 10,
			visibilityMode = 'all',
			playerColor    = { 0, 0.8, 0 },
			otherColor     = { 1, 0.85, 0 },
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		dispellable = {
			enabled              = false,
			onlyDispellableByMe  = false,
			highlightType        = 'gradient_half',
			highlightAlpha       = 0.8,
			iconSize             = 10,
			anchor               = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', 0, 4 },
			frameLevel           = 15,
		},
		targetedSpells = {
			enabled       = false,
			displayMode   = 'Both',
			iconSize      = 18,
			borderColor   = { 1, 0, 0, 1 },
			maxDisplayed  = 1,
			showDuration  = true,
			durationFont  = durationFont(),
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
		privateAuras = {
			enabled        = false,
			iconSize       = 14,
			maxDisplayed   = 3,
			orientation    = 'RIGHT',
			showDispelType = true,
			anchor         = { 'TOP', nil, 'TOP', 0, -3 },
			frameLevel     = 25,
		},
		missingBuffs = {
			enabled       = false,
			iconSize      = 12,
			frameLevel    = 10,
			anchor        = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 16 },
			growDirection = 'LEFT',
			spacing       = 1,
			glowType      = 'Pixel',
			glowColor     = { 1, 0.8, 0, 1 },
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

-- Group auras (party/raid) — full indicator set
function F.AuraDefaults.Group(sizes)
	local s = sizes or {}
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
	local dispIcon = s.dispellableIcon or 10

	return {
		buffs = {
			enabled = true,
			buffFilterMode = 'raidCombat',
			indicators = { ['My Buffs'] = defaultBuffIndicator() },
		},
		debuffs = {
			enabled    = true,
			indicators = {
				['General Debuffs'] = debuffIndicator({
					iconSize     = 13,
					bigIconSize  = big,
					maxDisplayed = debMax,
					anchor       = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 1, 4 },
				}),
				['Raid Debuffs'] = debuffIndicator({
					filterMode   = 'raid',
					iconSize     = rd,
					bigIconSize  = rdBig,
					maxDisplayed = rdMax,
					anchor       = { 'CENTER', nil, 'CENTER', 0, 3 },
					frameLevel   = 20,
				}),
			},
		},
		targetedSpells = {
			enabled       = true,
			displayMode   = 'Both',
			iconSize      = tsIcon,
			borderColor   = { 1, 0, 0, 1 },
			maxDisplayed  = 1,
			showDuration  = true,
			durationFont  = durationFont(),
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
			highlightAlpha       = 0.8,
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
			visibilityMode = 'all',
			playerColor    = { 0, 0.8, 0 },
			otherColor     = { 1, 0.85, 0 },
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
			visibilityMode = 'all',
			playerColor    = { 0, 0.8, 0 },
			otherColor     = { 1, 0.85, 0 },
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		missingBuffs = {
			enabled       = false,
			iconSize      = s.missingBuffsIcon or 12,
			frameLevel    = 10,
			anchor        = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 16 },
			growDirection  = 'LEFT',
			spacing       = 1,
			glowType      = 'Pixel',
			glowColor     = { 1, 0.8, 0, 1 },
		},
		privateAuras = {
			enabled        = true,
			iconSize       = s.privateAurasIcon or 16,
			maxDisplayed   = 3,
			orientation    = 'RIGHT',
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
			enabled    = true,
			indicators = {
				['General Debuffs'] = debuffIndicator({
					maxDisplayed = 4,
				}),
			},
		},
		dispellable = {
			enabled              = true,
			onlyDispellableByMe  = false,
			highlightType        = 'gradient_half',
			highlightAlpha       = 0.8,
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

-- Boss auras — buffs + debuffs with raid indicator
function F.AuraDefaults.Boss()
	return {
		buffs = { enabled = true, buffFilterMode = 'raidCombat', indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = {
			enabled    = true,
			indicators = {
				['General Debuffs'] = debuffIndicator({
					maxDisplayed = 4,
				}),
				['Raid Debuffs'] = debuffIndicator({
					filterMode   = 'raid',
					maxDisplayed = 1,
					anchor       = { 'CENTER', nil, 'CENTER', 0, 0 },
					frameLevel   = 6,
				}),
			},
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
