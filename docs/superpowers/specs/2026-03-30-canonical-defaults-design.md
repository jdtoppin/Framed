# Canonical Defaults — Design Spec

## Problem

Default config values are scattered across ~30 files as `or` fallback patterns:

- Element Setup: `config.size = config.size or 12`
- LiveUpdate handlers: `config.health.colorMode or 'class'`
- Settings cards: `getConfig('width') or 200`
- StyleBuilder: duplicate `DEFAULT_CONFIG` table
- Unit spawn files: `(pos and pos.x) or 0`

~150 instances across ~80 unique config keys. The same key (e.g., `castbar.height`) is hardcoded in up to 6 places. If a default needs to change, every location must be found and updated. When `Presets/Defaults.lua` doesn't cover a key, code silently falls back to these scattered values, and Settings UI shows `0` or `nil` instead of the real default.

## Solution

**Approach A: Complete defaults in Presets/Defaults.lua + strip all `or` chains.**

One source of truth. Every config key gets an explicit value in SavedVariables at first load. All `or fallback` patterns are removed. If a value is nil, it's a bug — not a "use default" signal.

## Architecture

### Canonical Defaults Table

**`Presets/Defaults.lua`** — the existing per-unit-type config functions (`playerConfig()`, `targetConfig()`, `partyConfig()`, etc.) get expanded from ~15 keys each to ~80 keys each. Every key that any code reads must exist here.

Keys being added (currently missing from defaults):

- **Health:** `customColor`, `gradientHigh`/`Mid`/`Low` + thresholds, `lossColorMode`, `lossCustomColor`, `lossGradient*`, `textColorMode`, `textAnchor`, `textAnchorX`, `textAnchorY`, `textFormat`, `fontSize`, `outline`, `shadow`, `healPredictionMode`, `healPredictionColor`, `damageAbsorbColor`, `healAbsorbColor`, `overAbsorbColor`
- **Power:** `position`, `textColorMode`, `textAnchor`, `textAnchorX`, `textAnchorY`, `textFormat`, `fontSize`, `outline`, `shadow`
- **Name:** `anchor`, `anchorX`, `anchorY`, `outline`, `shadow`
- **Castbar:** `sizeMode`, `width`, `backgroundMode`
- **Status Icons:** Per-icon `point`, `x`, `y`, `size` (currently in `StyleBuilder.ICON_DEFAULTS`, gets folded in under `statusIcons.role.size`, `statusIcons.role.point`, etc.)
- **Status Text:** `fontSize`, `outline`, `shadow`, `anchor`, `anchorX`, `anchorY`

**`StyleBuilder.DEFAULT_CONFIG`** — deleted. Redundant once defaults are complete.

**`StyleBuilder.ICON_DEFAULTS`** — folded into per-unit-type preset defaults under `statusIcons.*`. Deleted as a separate table.

### Account Defaults

**`Core/Config.lua` `accountDefaults.general`** — expanded to include every appearance/general setting key:

- Existing: `accentColor`, `uiScale`, `wizardCompleted`, `tooltipEnabled`, `tooltipHideInCombat`, `tooltipAnchor`, `tooltipOffsetX`, `tooltipOffsetY`, `targetHighlightColor`, `targetHighlightWidth`, `mouseoverHighlightColor`, `mouseoverHighlightWidth`
- Add any missing appearance keys that settings cards currently default with `or`
- Add: `pinnedCards = {}`, `pinnedAppearanceCards = {}`

### Character Defaults

**`Core/Config.lua` `charDefaults`** — already has `autoSwitch`, `specOverrides`, `tourState`. Add:

- `lastPanel = nil` — last active sidebar panel id, restored on settings open
- `lastEditingPreset = nil` — last selected preset name in sidebar
- `lastEditingUnitType = nil` — last selected unit type in aura dropdowns

These start as nil (no previous state) and get written via `Config:SetChar()` when the user navigates. On settings open, the code checks these before falling back to auto-detected values.

### Initialization Flow

**First load** (FramedDB is nil):
1. `Config:Initialize()` creates FramedDB from `accountDefaults`
2. `EnsureDefaults()` writes complete preset tables (unitConfigs + auras) into `FramedDB.presets`
3. Every key has an explicit value in SavedVariables

**Subsequent loads** (FramedDB exists):
1. `mergeDefaults()` backfills any new keys added in newer versions
2. `EnsureDefaults()` backfills any new preset-level keys
3. Existing user values are never overwritten

**Clean wipe** (`/framed reset all`):
1. Backs up FramedDB to FramedBackupDB
2. Sets FramedDB = nil, reloads
3. Triggers first-load path — complete fresh defaults

**Onboarding wizard** (future scope, not this refactor):
- Runs after initialization
- Overwrites specific keys with layout-specific values (e.g., "Healer" gets larger raid debuffs)
- Separate task — this refactor ensures the base defaults are complete

### Strip All `or` Fallback Chains

Every `or defaultValue` pattern is removed:

| Location | Count | Example |
|----------|-------|---------|
| `Units/LiveUpdate/FrameConfig.lua` | ~60 | `config.health.colorMode or 'class'` → `config.health.colorMode` |
| `Settings/Cards/*.lua` (14 files) | ~50 | `getConfig('width') or 200` → `getConfig('width')` |
| `Elements/Status/*.lua` (12 files) | ~12 | `config.size or 12` → `config.size` |
| `Units/*.lua` (spawn files) | ~10 | `(pos and pos.x) or 0` → `pos.x` |
| `Units/StyleBuilder.lua` | ~20 | Delete DEFAULT_CONFIG, strip remaining `or` patterns |
| `Settings/Panels/*.lua` (aura panels) | ~10 | `get('anchor') or { 'BOTTOMRIGHT', ... }` → `get('anchor')` |

**If a value is nil after this refactor, it's a bug.** In most cases WoW's Lua will error immediately (`SetWidth(nil)`, `SetTextColor(nil)`), making missing defaults visible during testing rather than silently hidden.

## Scope

### In Scope

- **Frame unitConfigs** — health, power, name, castbar, shields, position, dimensions (main focus)
- **Status icons** — fold ICON_DEFAULTS into preset defaults
- **Appearance/general settings** — expand accountDefaults
- **Aura settings panels** — scattered anchor/spell defaults in Settings/Panels
- **Pinned cards state** — explicit empty tables in accountDefaults
- **Last-visited settings state** — new charDefaults keys
- **Spec overrides** — already correct (empty table default)

### Out of Scope

- **Aura defaults (AuraDefaults.lua builders)** — already centralized and correct
- **Click Casting** — already centralized in ClickCasting/Defaults.lua
- **Core/Config.lua read/write engine** — just plumbing, no defaults in it
- **Widgets/** — UI building blocks, no defaults in them
- **EditMode** — consumer of config values, works correctly once SavedVariables are populated
- **Onboarding wizard layout presets** — future task, builds on top of this work

### Files Modified

| File | Change |
|------|--------|
| `Presets/Defaults.lua` | Expand config functions to ~80 keys each |
| `Units/StyleBuilder.lua` | Delete `DEFAULT_CONFIG`, fold `ICON_DEFAULTS` into preset defaults, strip `or` patterns |
| `Units/LiveUpdate/FrameConfig.lua` | Strip ~60 `or` fallbacks |
| `Settings/Cards/*.lua` (14 files) | Strip ~50 `or` fallbacks |
| `Elements/Status/*.lua` (12 files) | Strip `or` fallbacks, read from config directly |
| `Units/*.lua` (spawn files) | Strip position/size `or` fallbacks |
| `Settings/Panels/*.lua` (aura panels) | Strip scattered anchor/spell defaults |
| `Core/Config.lua` | Expand `accountDefaults.general`, add `charDefaults` keys |
| `Settings/Framework.lua` | Restore last-visited panel/preset/unitType from charDefaults |

### Files Not Touched

- `Presets/AuraDefaults.lua` — already correct
- `ClickCasting/` — already correct
- `Core/EventBus.lua` — plumbing
- `Widgets/*.lua` — plumbing
- `EditMode/*.lua` — consumer only

## Testing

After each batch of changes:
1. `/framed reset all` + `/reload`
2. Verify frames render at correct positions with correct sizes
3. Open settings — all sliders/dropdowns should show real values, not 0 or nil
4. Change settings — values persist across `/reload`
5. Enter edit mode — drag frames, save, verify positions match in settings
6. Switch presets in sidebar — values update correctly per preset
