local addonName, Framed = ...
local F = Framed

local Constants = {}
F.Constants = Constants

-- ============================================================
-- Color Palette (default accent is cyan, user-configurable)
-- ============================================================
Constants.Colors = {
	background  = { 0.05, 0.05, 0.05, 1 },       -- #0d0d0d
	panel       = { 0.06, 0.06, 0.06, 0.95 },     -- #0f0f0f
	widget      = { 0.15, 0.15, 0.15, 1 },         -- #262626
	card        = { 0.12, 0.12, 0.12, 1 },         -- #1f1f1f
	cardBorder  = { 0.18, 0.18, 0.18, 1 },         -- #2e2e2e
	border      = { 0, 0, 0, 1 },                  -- #000000
	highlight   = { 1, 1, 1, 0.25 },               -- white @ 25%

	-- Accent defaults (overridden by user config at runtime)
	accent      = { 0, 0.8, 1, 1 },                -- #00ccff
	accentDim   = { 0, 0.8, 1, 0.3 },              -- accent @ 30%
	accentHover = { 0, 0.8, 1, 0.6 },              -- accent @ 60%

	-- Text
	textActive   = { 1, 1, 1, 1 },
	textNormal   = { 0.8, 0.8, 0.8, 1 },
	textSecondary = { 0.5, 0.5, 0.5, 1 },
	textDisabled = { 0.35, 0.35, 0.35, 1 },
}

-- Dispel type colors (3-value RGB — alpha applied at call site)
-- Physical/bleed included for healer awareness
Constants.Colors.dispel = {
	Magic    = { 0.2, 0.6, 1   },
	Curse    = { 0.6, 0,   1   },
	Disease  = { 0.6, 0.4, 0   },
	Poison   = { 0,   0.6, 0.1 },
	Physical = { 0.8, 0,   0   },
}

-- ============================================================
-- Spacing (4px base unit)
-- ============================================================
Constants.Spacing = {
	base   = 4,
	tight  = 8,
	normal = 12,
	loose  = 16,
}

-- ============================================================
-- Typography
-- ============================================================
Constants.Font = {
	sizeTitle  = 14,
	sizeNormal = 13,
	sizeSmall  = 11,
}

-- ============================================================
-- Animation
-- ============================================================
Constants.Animation = {
	durationFast = 0.10,
	durationNormal = 0.15,
}

-- ============================================================
-- Content Types (for layout auto-switching)
-- ============================================================
Constants.ContentType = {
	SOLO         = 'solo',
	PARTY        = 'party',
	RAID         = 'raid',
	MYTHIC_RAID  = 'mythicRaid',
	WORLD_RAID   = 'worldRaid',
	BATTLEGROUND = 'battleground',
	ARENA        = 'arena',
}

-- Priority order for content detection (most specific first)
Constants.ContentTypePriority = {
	Constants.ContentType.ARENA,
	Constants.ContentType.BATTLEGROUND,
	Constants.ContentType.MYTHIC_RAID,
	Constants.ContentType.RAID,
	Constants.ContentType.WORLD_RAID,
	Constants.ContentType.PARTY,
	Constants.ContentType.SOLO,
}

-- Preset definitions: name → { isBase, fallback, groupKey, groupLabel }
-- groupKey is the unitConfigs/auras key for group frames
-- groupLabel is the sidebar display name
Constants.PresetInfo = {
	['Solo']          = { isBase = true,  fallback = nil,    groupKey = nil,     groupLabel = nil },
	['Party']         = { isBase = true,  fallback = nil,    groupKey = 'party', groupLabel = 'Party Frames' },
	['Raid']          = { isBase = true,  fallback = nil,    groupKey = 'raid',  groupLabel = 'Raid Frames' },
	['Arena']         = { isBase = true,  fallback = nil,    groupKey = 'arena', groupLabel = 'Arena Frames' },
	['Mythic Raid']   = { isBase = false, fallback = 'Raid', groupKey = 'raid',  groupLabel = 'Raid Frames' },
	['World Raid']    = { isBase = false, fallback = 'Raid', groupKey = 'raid',  groupLabel = 'Raid Frames' },
	['Battleground']  = { isBase = false, fallback = 'Raid', groupKey = 'raid',  groupLabel = 'Raid Frames' },
}

-- Ordered list of preset names for UI display
Constants.PresetOrder = {
	'Solo', 'Party', 'Raid', 'Arena',
	'Mythic Raid', 'World Raid', 'Battleground',
}

-- ============================================================
-- Raid Debuff Priority Levels
-- ============================================================
Constants.DebuffPriority = {
	TRIVIAL   = 1,
	LOW       = 2,
	NORMAL    = 3,
	IMPORTANT = 4,
	CRITICAL  = 5,
	SURVIVAL  = 6,
}

-- ============================================================
-- Raid Debuff Filter Modes
-- ============================================================
Constants.DebuffFilterMode = {
	ENCOUNTER_ONLY = 'EncounterOnly',   -- isBossAura only
	RAID           = 'Raid',            -- isRaid (includes boss + trash)
}

-- ============================================================
-- Indicator Rendering Types
-- ============================================================
Constants.IndicatorType = {
	ICON      = 'Icon',
	ICONS     = 'Icons',
	BAR       = 'Bar',
	BARS      = 'Bars',
	BORDER    = 'Border',
	RECTANGLE = 'Rectangle',
	OVERLAY   = 'Overlay',
}

-- ============================================================
-- Border / Glow Mode
-- ============================================================
Constants.BorderGlowMode = {
	BORDER = 'Border',
	GLOW   = 'Glow',
}

-- ============================================================
-- Glow Variants
-- ============================================================
Constants.GlowType = {
	PROC  = 'Proc',
	PIXEL = 'Pixel',
	SOFT  = 'Soft',
	SHINE = 'Shine',
}

-- ============================================================
-- Cast-By Filter (indicator spell filtering)
-- ============================================================
Constants.CastFilter = {
	ANYONE = 'anyone',
	ME     = 'me',
	OTHERS = 'others',
}

-- ============================================================
-- Dispel Highlight Types
-- ============================================================
Constants.HighlightType = {
	GRADIENT_FULL  = 'gradient_full',
	GRADIENT_HALF  = 'gradient_half',
	SOLID_CURRENT  = 'solid_current',
	SOLID_ENTIRE   = 'solid_entire',
}

-- ============================================================
-- Icon Display Types
-- ============================================================
Constants.IconDisplay = {
	SPELL_ICON    = 'SpellIcon',
	COLORED_SQUARE = 'ColoredSquare',
}
