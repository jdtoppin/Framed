local addonName, Framed = ...

local Constants = {}
Framed.Constants = Constants

-- ============================================================
-- Color Palette (default accent is cyan, user-configurable)
-- ============================================================
Constants.Colors = {
    background  = { 0.05, 0.05, 0.05, 1 },       -- #0d0d0d
    panel       = { 0.10, 0.10, 0.10, 0.85 },     -- #1a1a1a
    widget      = { 0.15, 0.15, 0.15, 1 },         -- #262626
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
    SOLO          = "Solo",
    PARTY         = "Party",
    RAID          = "Raid",
    MYTHIC_RAID   = "MythicRaid",
    WORLD_RAID    = "WorldRaid",
    BATTLEGROUND  = "Battleground",
    ARENA         = "Arena",
}

-- Detection priority order (most specific first)
Constants.ContentTypePriority = {
    Constants.ContentType.ARENA,
    Constants.ContentType.BATTLEGROUND,
    Constants.ContentType.MYTHIC_RAID,
    Constants.ContentType.RAID,
    Constants.ContentType.WORLD_RAID,
    Constants.ContentType.PARTY,
    Constants.ContentType.SOLO,
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
    ENCOUNTER_ONLY = "EncounterOnly",   -- isBossAura only
    RAID           = "Raid",            -- isRaid (includes boss + trash)
}

-- ============================================================
-- Indicator Rendering Types
-- ============================================================
Constants.IndicatorType = {
    ICON      = "Icon",
    ICONS     = "Icons",
    FRAME_BAR = "FrameBar",
    BAR       = "Bar",
    BORDER    = "Border",
    COLOR     = "Color",
    OVERLAY   = "Overlay",
    GLOW      = "Glow",
}

-- ============================================================
-- Glow Variants
-- ============================================================
Constants.GlowType = {
    PROC  = "Proc",
    PIXEL = "Pixel",
    SOFT  = "Soft",
}

-- ============================================================
-- Icon Display Types
-- ============================================================
Constants.IconDisplay = {
    SPELL_ICON    = "SpellIcon",
    COLORED_SQUARE = "ColoredSquare",
}
