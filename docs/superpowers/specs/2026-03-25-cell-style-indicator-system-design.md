# Cell-Style Indicator System Design

## Summary

Redesign Framed's aura indicator pages to follow Cell's indicator creator pattern. Buffs get full CRUD with per-indicator settings and a healer spell import popup. Debuffs, Raid Debuffs, Externals, and Defensives share a BorderIcon renderer with a common settings builder. Targeted Spells get Icons + Border Glow modes. Dispels get an always-present icon plus a configurable highlight overlay. All panels gain frame level control.

## Goals

- Match Cell's border icon visual quality for debuff-style indicators
- Give healers full control over buff tracking with named, typed indicators
- Keep settings DRY via shared builders
- Apply settings without `/reload` via existing EventBus + LiveUpdate pipeline
- Respect Framed's existing file structure and panel registration system

## Non-Goals

- Custom spell lists for externals/defensives (Blizzard pre-defined logic)
- Changing Missing Buffs or Private Auras (already appropriate)
- Cell's full 30+ built-in indicator system (Framed keeps it scoped per aura category)

---

## 1. Data Model

### 1.0 Config Path Architecture

Framed stores aura config **per-unit-type** within each layout, under `unitConfigs`:

```
layouts.<layoutName>.unitConfigs.<unitType>.buffs
layouts.<layoutName>.unitConfigs.<unitType>.debuffs
layouts.<layoutName>.unitConfigs.<unitType>.raidDebuffs
layouts.<layoutName>.unitConfigs.<unitType>.dispellable
```

This is the existing pattern (see `Layouts/Defaults.lua`). The new indicator system **preserves this per-unit-type scoping**. This means party frames and raid frames can have different debuff settings within the same layout.

All config paths in this spec are relative to `layouts.<layoutName>.unitConfigs.<unitType>`. For example, `buffs.indicators[]` means `layouts.<layoutName>.unitConfigs.<unitType>.buffs.indicators[]`.

Settings panels read/write using `F.Settings.GetEditingLayout()` for the layout name and the panel's `unitType` context for the unit type, following the existing `FrameSettingsBuilder` pattern.

### 1.1 Buffs — Full CRUD Indicator Array

Stored at `unitConfigs.<unitType>.buffs`:

```lua
{
  enabled    = true,          -- global enable/disable for all buff indicators
  indicators = {
    [1] = {
      name           = "My Rejuv",
      type           = "Icons",           -- C.IndicatorType: Bar|Border|Color|FrameBar|Glow|Icon|Icons|Overlay
      enabled        = true,
      auras          = { 774, 155777 },   -- spell IDs
      castBy         = "me",              -- "me" | "others" | "anyone"
      iconSize       = 14,
      maxIcons       = 3,
      displayType    = "SpellIcon",       -- C.IconDisplay: SpellIcon | ColoredSquare
      numPerLine     = 5,
      spacingX       = 2,
      spacingY       = 2,
      growDirection   = "RIGHT",          -- RIGHT | LEFT | DOWN | UP
      anchor         = { "TOPLEFT", nil, "TOPLEFT", 2, -2 },
      showStacks     = true,
      showDuration   = true,
      glowType       = "None",           -- None | Proc | Pixel | Soft | Shine
      glowColor      = { 0.95, 0.95, 0.32, 1 },
      frameLevel     = 5,
      stackFont      = {
        size    = 10,
        outline = "OUTLINE",
        shadow  = false,
        anchor  = "BOTTOMRIGHT",
        xOffset = 0,
        yOffset = 0,
        color   = { 1, 1, 1, 1 },
      },
      durationFont   = {
        size    = 10,
        outline = "OUTLINE",
        shadow  = false,
      },
    },
    [2] = { ... },
  },
}
```

**Notes:**
- `enabled` at the top level is a global toggle for all buff indicators on this unit type
- `displayType` only applies to Icon/Icons types
- ColoredSquare uses vertical depletion animation (StatusBar) instead of cooldown swipe
- Settings that don't apply to a given `type` are ignored (e.g., `maxIcons` irrelevant for Bar)
- `numPerLine`, `spacingX`, `spacingY` are handled by the multi-indicator dispatch in `Buffs.lua`, not the Icons primitive — `Icons.lua` gains grid layout support (see Section 2.2)
- Empty indicators array by default; populated via manual creation or healer spell import
- `durationFont` is intentionally restricted to `size`, `outline`, `shadow` — Blizzard limits what can be customized on duration text (no positional or color overrides). `stackFont` has the full set.

### 1.2 Debuffs / Raid Debuffs / Externals / Defensives — Shared BorderIcon Schema

Stored at `unitConfigs.<unitType>.debuffs` (and similarly for `raidDebuffs`, `externals`, `defensives`):

```lua
{
  enabled              = true,
  iconSize             = 16,
  bigIconSize          = 22,            -- debuffs/raidDebuffs only
  maxDisplayed         = 3,
  showDuration         = true,
  showAnimation        = true,          -- fadeOut on expiry
  orientation          = "RIGHT",       -- growth direction
  anchor               = { "BOTTOMLEFT", nil, "BOTTOMLEFT", 2, 2 },
  frameLevel           = 5,
  onlyDispellableByMe  = false,         -- debuffs only
  stackFont            = {
    size    = 10,
    outline = "OUTLINE",
    shadow  = false,
    anchor  = "BOTTOMRIGHT",
    xOffset = 0,
    yOffset = 0,
    color   = { 1, 1, 1, 1 },
  },
  durationFont         = {
    size    = 10,
    outline = "OUTLINE",
    shadow  = false,
  },
}
```

**Notes:**
- Border color derived automatically from dispel type for debuffs (Magic=blue, Curse=purple, Disease=brown, Poison=green)
- `bigIconSize` only present for debuffs and raidDebuffs (boss-cast or high-priority debuffs render larger)
- `onlyDispellableByMe` only present for debuffs
- Externals and defensives use identical schema minus `bigIconSize` and `onlyDispellableByMe`
- `durationFont` intentionally restricted (size, outline, shadow only) — see Section 1.1 notes

### 1.3 Targeted Spells — Three-Mode Display

Stored at `unitConfigs.<unitType>.targetedSpells`:

```lua
{
  enabled       = true,
  displayMode   = "Both",              -- "Icons" | "BorderGlow" | "Both"
  iconSize      = 16,
  borderColor   = { 1, 0, 0, 1 },
  maxDisplayed  = 1,
  anchor        = { "CENTER", nil, "CENTER", 0, 0 },
  frameLevel    = 8,
  glow          = {
    type      = "Pixel",               -- Pixel | Proc | Soft | Shine
    color     = { 1, 0, 0, 1 },
    lines     = 8,
    frequency = 0.25,
    length    = 4,
    thickness = 2,
  },
}
```

**Notes:**
- `displayMode` values are new — the existing code uses lowercase `'icon'`/`'border'`/`'both'`. This is an intentional rename to match Framed's PascalCase convention for enum-like config values. The existing `DisplayMode` local table in `TargetedSpells.lua` will be updated to match.

### 1.4 Dispels — Icon + Highlight Overlay

Stored at `unitConfigs.<unitType>.dispellable`:

```lua
{
  enabled              = true,
  onlyDispellableByMe  = false,
  highlightType        = "gradient_half",  -- gradient_full | gradient_half | solid_current | solid_entire
  iconSize             = 16,
  anchor               = { "CENTER", nil, "CENTER", 0, 0 },
  frameLevel           = 7,
}
```

**Notes:**
- Icon is always displayed (not controlled by highlight type)
- `onlyDispellableByMe` appears at top of panel — filters dispellable types only; Physical/bleed debuffs always show for healer awareness
- Highlight type controls the overlay effect on the frame, not the icon
- Dispel priority: Magic(1) > Curse(2) > Disease(3) > Poison(4) > Physical/Bleed(5)

---

## 2. File Structure

### 2.1 New Files

| File | Purpose |
|------|---------|
| `Elements/Indicators/BorderIcon.lua` | BorderIcon renderer: BackdropTemplate + icon + cooldown + border color + stacks/duration |
| `Elements/Auras/Externals.lua` | Externals aura element — displays external defensive cooldowns using BorderIcon pool |
| `Elements/Auras/Defensives.lua` | Defensives aura element — displays personal defensive cooldowns using BorderIcon pool |
| `Settings/Builders/BorderIconSettings.lua` | Shared settings UI factory for debuffs/raidDebuffs/externals/defensives panels |
| `Settings/Builders/IndicatorCRUD.lua` | CRUD UI factory for Buffs panel: create/edit/delete indicators + import popup |

**Note:** The `Settings/Builders/` directory is new. It sits alongside the existing `Settings/Panels/` and `Settings/FrameSettingsBuilder.lua`. The pattern is similar to `FrameSettingsBuilder` — reusable UI factories — but scoped to indicator-specific settings.

### 2.2 Modified Files

| File | Changes |
|------|---------|
| `Core/Constants.lua` | Add `GlowType.SHINE`, `HighlightType` enum, `Colors.dispel` table |
| `Elements/Indicators/Icon.lua` | Add vertical depletion mode for `ColoredSquare` display type |
| `Elements/Indicators/Icons.lua` | Add grid layout support: `numPerLine`, `spacingX`, `spacingY` parameters |
| `Elements/Indicators/Glow.lua` | Add Shine glow type |
| `Elements/Auras/Buffs.lua` | Rewrite: multi-indicator dispatch from `indicators[]` array |
| `Elements/Auras/Debuffs.lua` | Rewrite: BorderIcon renderer, dispel-type coloring |
| `Elements/Auras/RaidDebuffs.lua` | Rewrite: BorderIcon renderer |
| `Elements/Auras/TargetedSpells.lua` | Update: BorderIcon + BorderGlow modes, Shine glow, rename displayMode values |
| `Elements/Auras/Dispellable.lua` | Rewrite: always-on BorderIcon + 4 highlight overlay types |
| `Settings/Panels/Buffs.lua` | Rewrite: full CRUD via IndicatorCRUD builder |
| `Settings/Panels/Debuffs.lua` | Rewrite: BorderIconSettings builder + onlyDispellableByMe |
| `Settings/Panels/RaidDebuffs.lua` | Rewrite: BorderIconSettings builder |
| `Settings/Panels/TargetedSpells.lua` | Rewrite: Icons/BorderGlow/Both + glow settings |
| `Settings/Panels/Dispels.lua` | Rewrite: highlight type + icon settings + onlyDispellableByMe |
| `Settings/Panels/Externals.lua` | Rewrite: BorderIconSettings builder, remove spell list |
| `Settings/Panels/Defensives.lua` | Rewrite: BorderIconSettings builder, remove spell list |
| `Layouts/Defaults.lua` | Update unit config base functions with new aura config schema |
| `Framed.toc` | Add new files to load order |

---

## 3. Rendering Layer

### 3.1 BorderIcon Renderer (`Elements/Indicators/BorderIcon.lua`)

Adapts Cell's `CreateAura_BorderIcon()` pattern:

```
+-------------------------+  <-- BackdropTemplate frame (border color = dispel type or config)
| +---------------------+ |
| |                     | |  <-- Inner icon texture (spell icon, inset by border thickness)
| |    [Cooldown]       | |  <-- CooldownFrame overlay (swipe animation)
| |                     | |
| +---------------------+ |
|           3  00:05      |  <-- Stack count (FontString) + Duration (FontString)
+-------------------------+
```

**API** (method-table pattern, consistent with existing `Icon.lua` and `Glow.lua`):
- `F.Indicators.BorderIcon.Create(parent, size, config)` — returns indicator object
- `indicator:SetAura(spellId, duration, expirationTime, count, dispelType)` — updates display
- `indicator:SetBorderColor(r, g, b, a)` — manual border color override
- `indicator:Clear()` — hides indicator
- `indicator:SetSize(size)` — resize

**Note:** `BorderIcon` is an internal renderer, not an end-user-selectable indicator type. It is not added to `C.IndicatorType`. It is used by debuffs, raid debuffs, targeted spells, externals, defensives, and dispels — but not available in the Buffs CRUD type dropdown.

**Behavior:**
- Border color from dispel type lookup (`C.Colors.dispel[dispelType]`) or config `borderColor`
- Stack/duration font configurable via config table
- Frame level set via `indicator:SetFrameLevel(config.frameLevel)`
- Secret-value safe: uses `F.IsValueNonSecret()` before displaying spell data
- `dispelName` is checked via `F.IsValueNonSecret()` before using it as a table key for color lookup. If secret, falls back to a default border color.

### 3.2 Vertical Depletion for ColoredSquare (`Elements/Indicators/Icon.lua`)

When `displayType == 'ColoredSquare'`:
- Replace CooldownFrame with a vertical StatusBar
- StatusBar fills from top, depletes downward over the aura's duration
- Color derived from debuff type or a configured color
- OnUpdate handler decrements value based on remaining time
- Icons.lua inherits this behavior since it pools Icon instances

### 3.3 Grid Layout for Icons (`Elements/Indicators/Icons.lua`)

Extend `Icons.lua` to support grid layouts:
- New config fields: `numPerLine` (default: unlimited/single row), `spacingX`, `spacingY`
- When `numPerLine` is set, icons wrap to next row/column after reaching the limit
- Positioning calculated from `growDirection` + `numPerLine` + spacing values
- Backward compatible: existing callers that don't pass `numPerLine` get single-row behavior

### 3.4 Shine Glow Type (`Elements/Indicators/Glow.lua`)

Add `SHINE` to the glow dispatch:
- Uses LibCustomGlow's `ButtonGlow` variant with shine parameters if available
- Fallback: Proc glow with modified alpha pulse

### 3.5 Dispel Highlight Overlays (`Elements/Auras/Dispellable.lua`)

Four overlay modes, each using a texture on the appropriate parent:

| Type | Parent | Behavior |
|------|--------|----------|
| `gradient_full` | Health bar | Full-height gradient texture (dispel color top -> transparent bottom) |
| `gradient_half` | Health bar | Half-height gradient on upper portion of health bar |
| `solid_current` | Health bar | Solid color overlay clipped to current health width |
| `solid_entire` | Unit frame | Solid color overlay covering entire frame |

Color always matches highest-priority dispel type.

---

## 4. Rendering Pipelines

### 4.1 Buffs — Multi-Indicator Dispatch

```
UNIT_AURA fires
  -> Check global buffs.enabled flag
  -> Iterate helpful auras on the unit
  -> For each enabled indicator in unitConfigs.<unitType>.buffs.indicators[]:
      -> Filter by castBy (me/others/anyone)
         castBy resolution: compare auraData.sourceUnit via UnitIsUnit(sourceUnit, 'player')
         Note: sourceUnit may be secret — use F.IsValueNonSecret() before comparison;
         if secret and castBy ~= 'anyone', skip the aura
      -> Filter by spell ID membership in indicator.auras[]
         Note: spellId checked via F.IsValueNonSecret() before use as table key
      -> Dispatch matched auras to the indicator's renderer via type lookup:
         Icon/Icons/Bar/FrameBar/Border/Color/Overlay/Glow
  -> Clear any indicators with no matches
```

Renderer dispatch table:
```lua
local RENDERERS = {
  [C.IndicatorType.ICON]      = F.Indicators.Icon,
  [C.IndicatorType.ICONS]     = F.Indicators.Icons,
  [C.IndicatorType.BAR]       = F.Indicators.Bar,
  [C.IndicatorType.FRAME_BAR] = F.Indicators.FrameBar,
  [C.IndicatorType.BORDER]    = F.Indicators.Border,
  [C.IndicatorType.COLOR]     = F.Indicators.Color,
  [C.IndicatorType.OVERLAY]   = F.Indicators.Overlay,
  [C.IndicatorType.GLOW]      = F.Indicators.Glow,
}
```

Each indicator gets its own frame/widget created at Setup time. Renderer resolved by `indicator.type`.

### 4.2 Debuffs / Raid Debuffs / Externals / Defensives — BorderIcon Pool

```
UNIT_AURA fires
  -> Iterate harmful auras (helpful for externals/defensives)
  -> Blizzard logic determines qualifying auras
  -> For debuffs: color border by dispel type (checked via F.IsValueNonSecret())
  -> Sort by priority or duration
  -> Render up to maxDisplayed using BorderIcon pool
  -> "Big" debuffs (boss-cast or high-priority) use bigIconSize
  -> Apply onlyDispellableByMe filter if enabled (debuffs only)
```

### 4.3 Targeted Spells — Icons + Border Glow

```
COMBAT_LOG_EVENT_UNFILTERED fires
  -> Detect SPELL_CAST_START targeting this unit
  -> Based on displayMode:
     "Icons":      Show BorderIcon with spell icon + configured border color
     "BorderGlow": Show glow around unit frame (Pixel/Proc/Soft/Shine)
     "Both":       Show both simultaneously
  -> On SPELL_CAST_STOP/FAILED/SUCCESS: clear
```

### 4.4 Dispels — Icon + Highlight Overlay

```
UNIT_AURA fires
  -> Iterate harmful auras, find dispellable ones + bleeds (Physical debuffs)
  -> Apply onlyDispellableByMe filter if enabled (bleeds always pass — shown for healer awareness)
  -> Priority: Magic(1) > Curse(2) > Disease(3) > Poison(4) > Physical/Bleed(5)
  -> Always show: BorderIcon of highest-priority debuff (dispellable or bleed)
  -> Apply highlight overlay based on highlightType config
  -> Color both icon border and overlay by debuff type (including Physical = red)
```

### 4.5 LiveUpdate Integration

All aura elements respond to `CONFIG_CHANGED` via EventBus:
1. Element reads new config from `F.StyleBuilder.GetConfig()` or direct config path
2. Recreates/reconfigures renderer instances (pool resize, anchor changes, etc.)
3. Triggers `UpdateAllElements('ConfigChanged')` to re-evaluate current auras
4. Settings apply without `/reload`

---

## 5. Settings UI

### 5.1 Buffs Panel — Full CRUD

Built by `IndicatorCRUD.lua`:

```
[Import Healer Spells]

-- Create Indicator --
Type: [Icons v]   Name: [________]  [Create]

-- Indicators --
[x] My Rejuv          Icons    [Edit] [Del]
[x] Druid HoTs        Icons    [Edit] [Del]
[ ] Paladin Buffs     FrameBar [Edit] [Del]

-- Settings (My Rejuv) --
Cast By:        [Me v]
Spell List:     [774, 155777] [+ Add] [- Remove]
Icon Size:      [===14===]
Max Icons:      [===3====]
Display Type:   [Spell Icon v]
Per Line:       [===5====]
Spacing X/Y:    [==2==] [==2==]
Growth:         [Right v]
Anchor Point:   [TOPLEFT v]
Relative Point: [TOPLEFT v]
X/Y Offset:     [==2==] [==-2==]
Frame Level:    [===5====]
Show Stacks:    [x]  Show Duration: [x]
Glow Type:      [None v]
Stack Font...   Duration Font...
```

- Selecting an indicator in the list populates settings below
- Settings section adapts to indicator type (Icon/Icons show display type + grid settings, Bar shows width/height, etc.)
- Edit selects, Del removes with confirmation
- Type dropdown: Bar, Border, Color, FrameBar, Glow, Icon, Icons, Overlay

### 5.2 Import Healer Spells Popup

```
+--------------------------------------+
| Import Healer Spells                 |
|                                      |
| [Select All] [Deselect All]          |
|                                      |
| -- Druid --------------------------  |
| [x] (icon) Rejuvenation             |
| [x] (icon) Lifebloom                |
| [ ] (icon) Wild Growth               |
| ...                                  |
| -- Paladin ------------------------  |
| [x] (icon) Beacon of Light          |
| ...                                  |
| -- Custom -------------------------  |
| Spell ID: [________] [Add]          |
|                                      |
|           [Import Selected]          |
+--------------------------------------+
```

- Grouped by class with spell icons resolved via `C_Spell.GetSpellInfo`
- Select All / Deselect All toggles at top
- Custom add section at bottom for unlisted spells
- Imports selected spell IDs into the currently selected indicator's `auras[]` array

### 5.3 Healer Spell List

Stored as constant in `Settings/Builders/IndicatorCRUD.lua`, grouped by class:

```lua
local HEALER_SPELLS = {
  DRUID   = { 774, 155777, 8936, 48438, 33763, ... },
  PALADIN = { 53563, 156910, 200025, ... },
  PRIEST  = { 139, 17, 41635, 194384, ... },
  SHAMAN  = { 61295, 73920, ... },
  MONK    = { 119611, 116849, 124682, ... },
  EVOKER  = { 355941, 376788, 364343, ... },
}
```

### 5.4 BorderIcon Settings — Shared Builder

Built by `BorderIconSettings.lua`, used by Debuffs, Raid Debuffs, Externals, Defensives:

```
[x] Only show dispellable by me     (debuffs only, shown at top)

-- Display --
Icon Size:       [===16===]
Big Icon Size:   [===22===]           (debuffs/raidDebuffs only)
Max Displayed:   [===3====]
Show Duration:   [x]
Show Animation:  [x]
Orientation:     [Right v]
Frame Level:     [===5====]

-- Position --
Anchor Point:    [BOTTOMLEFT v]
Relative Point:  [BOTTOMLEFT v]
X/Y Offset:      [==2==] [==2==]

-- Stack Font --
Font: [Friz v] Size: [==10==] Outline: [OUTLINE v]
Shadow: [ ]  Color: [White]
Anchor: [BOTTOMRIGHT v] X/Y: [==0==] [==0==]

-- Duration Font --
Font: [Friz v] Size: [==10==] Outline: [OUTLINE v]
Shadow: [ ]
```

Builder accepts options to control optional sections:
```lua
BorderIconSettings.Create(parent, width, {
  showDispellableByMe = true,   -- debuffs
  showBigIconSize     = true,   -- debuffs/raidDebuffs
  unitType            = 'party',
  configKey           = 'debuffs',
})
```

Config path resolved internally: `layouts.<editingLayout>.unitConfigs.<unitType>.<configKey>.<field>`

### 5.5 Targeted Spells Panel

```
Display Mode:    [Both v]

-- Icon Settings --              (shown when Icons or Both)
Icon Size:       [===16===]
Border Color:    [Red]
Max Displayed:   [===1====]
Anchor Point:    [CENTER v]
Frame Level:     [===8====]

-- Border Glow Settings --       (shown when BorderGlow or Both)
Glow Type:       [Pixel v]
Color:           [Red]
Lines:           [===8====]
Frequency:       [===0.25=]
Length:           [===4====]
Thickness:       [===2====]
```

### 5.6 Dispels Panel

```
[x] Only show dispellable by me

-- Highlight --
Type: [Gradient - Health Bar (Half) v]

-- Icon --
Size:           [===16===]
Anchor Point:   [CENTER v]
Relative Point: [CENTER v]
X/Y Offset:     [==0==] [==0==]
Frame Level:    [===7====]
```

Highlight type dropdown options:
- Gradient - Health Bar (Full)
- Gradient - Health Bar (Half)
- Solid - Health Bar (Current)
- Solid - Entire Frame

---

## 6. Constants & Defaults

### 6.1 New Constants (`Core/Constants.lua`)

```lua
-- GlowType: add Shine
Constants.GlowType.SHINE = 'Shine'

-- HighlightType: new enum
Constants.HighlightType = {
  GRADIENT_FULL    = 'gradient_full',
  GRADIENT_HALF    = 'gradient_half',
  SOLID_CURRENT    = 'solid_current',
  SOLID_ENTIRE     = 'solid_entire',
}

-- Dispel type colors (centralized — replaces per-file DISPEL_COLORS locals)
-- Uses 3-value RGB to match existing Icon.lua and Dispellable.lua conventions.
-- Alpha is applied at the call site based on context.
-- Physical/bleed included for healer awareness (not dispellable, but always shown).
Constants.Colors.dispel = {
  Magic    = { 0.2, 0.6, 1   },
  Curse    = { 0.6, 0,   1   },
  Disease  = { 0.6, 0.4, 0   },
  Poison   = { 0,   0.6, 0.1 },
  Physical = { 0.8, 0,   0   },
}
```

**Note:** Dispel colors use 3-value RGB (no alpha) to match the existing convention in `Icon.lua:13-19` and `Dispellable.lua:22-27`. These per-file locals will be replaced with references to `C.Colors.dispel`.

### 6.2 Layout Defaults (`Layouts/Defaults.lua`)

The existing base functions (`partyBase()`, `raidBase()`, etc.) are updated to include the new aura config fields under their existing `unitConfigs` structure. The old flat keys (`buffs = { maxIcons = 6, ... }`) are replaced with the new schema.

Example for `partyBase()`:

```lua
local function partyBase()
  return {
    width    = 120,
    height   = 36,
    showSelf = true,
    -- ... existing health, power, name, threat, range, statusIcons ...
    buffs = {
      enabled    = true,
      indicators = {},  -- empty until user creates or imports
    },
    debuffs = {
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
    },
    raidDebuffs = {
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
    },
    targetedSpells = {
      enabled       = true,
      displayMode   = 'Both',
      iconSize      = 16,
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
      iconSize             = 16,
      anchor               = { 'CENTER', nil, 'CENTER', 0, 0 },
      frameLevel           = 7,
    },
    externals = {
      enabled        = true,
      iconSize       = 16,
      maxDisplayed   = 2,
      showDuration   = true,
      showAnimation  = true,
      orientation    = 'RIGHT',
      anchor         = { 'TOPRIGHT', nil, 'TOPRIGHT', -2, -2 },
      frameLevel     = 5,
      stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
                         color = { 1, 1, 1, 1 } },
      durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
    },
    defensives = {
      enabled        = true,
      iconSize       = 16,
      maxDisplayed   = 2,
      showDuration   = true,
      showAnimation  = true,
      orientation    = 'RIGHT',
      anchor         = { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 },
      frameLevel     = 5,
      stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
                         color = { 1, 1, 1, 1 } },
      durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
    },
    missingBuffs = { iconSize = 12 },
    privateAuras = { iconSize = 16 },
    -- ... existing statusText, targetHighlight, mouseoverHighlight ...
  }
end
```

Unit types that don't use certain aura categories simply omit them (e.g., `playerBase()` won't have `raidDebuffs` or `dispellable`). The rendering elements check for `nil` config and no-op.

---

## 7. TOC Load Order

New files inserted into `Framed.toc`:

```
# After existing Indicators (Icon, Icons, FrameBar, Bar, Border, Color, Overlay, Glow)
Elements/Indicators/BorderIcon.lua

# New aura elements (after existing aura files)
Elements/Auras/Externals.lua
Elements/Auras/Defensives.lua

# Settings builders (before Settings/Panels/)
Settings/Builders/BorderIconSettings.lua
Settings/Builders/IndicatorCRUD.lua
```

Builders must load before panels that use them. BorderIcon must load before aura elements that reference it.

---

## 8. Secret Value Handling

All rendering follows Framed's secret value conventions:
- `F.IsValueNonSecret()` checked before displaying spell ID, duration, stack count
- `F.IsValueNonSecret()` checked on `dispelName` before using as table key for color lookup — falls back to default border color if secret
- `F.IsValueNonSecret()` checked on `sourceUnit` before `castBy` comparison — if secret and `castBy ~= 'anyone'`, aura is skipped
- BorderIcon passes secrets to C-level APIs (`SetValue()`, `SetMinMaxValues()`) where accepted
- Vertical depletion StatusBar uses `SetValue()` which accepts secrets
- No `pcall`, no sanitization, no per-file wrappers
- Derive `isHarmful` from filter string, not secret aura fields

---

## 9. Migration

The new aura config schema replaces the old flat keys (e.g., `buffs = { maxIcons = 6 }` becomes `buffs = { enabled = true, indicators = {} }`). Since `EnsureDefaults()` only populates missing layouts (never overwrites existing ones), users with existing configs will retain their old format.

To handle this gracefully:
- Each aura element's Setup function checks for both old and new config shapes
- If it receives old-format config (e.g., `{ maxIcons = 6 }` without `indicators`), it falls back to legacy behavior
- This avoids a forced `/reload` or data loss on addon update
- Over time, as users modify settings via the new panels, their config naturally migrates to the new format
