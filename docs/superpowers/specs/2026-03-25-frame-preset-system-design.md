# Frame Preset System Design

## Overview

Replace the current "layout" concept with **Frame Presets** — complete configuration bundles scoped to content types (Solo, Party, Raid, Arena, etc.). Each preset owns its unit frame configs (including group frames), aura configs (per unit type), and edit mode positions. The settings UI restructures around preset selection as the top-level control.

## Terminology

- **Frame Preset** (or just "preset") — A complete configuration bundle for a content context. Replaces "layout" throughout the codebase.
- **Base preset** — One of the 4 core presets (Solo, Party, Raid, Arena) that have no fallback.
- **Derived preset** — One of the 3 specialized presets (Mythic Raid, World Raid, Battleground) that fall back to a base preset when uncustomized.
- **Scoped settings** — Settings that belong to a preset (unit frames, group frames, auras, positions). Contrast with global settings (appearance, click casting, profiles).

## Default Presets

Seven presets ship by default:

| Preset | Type | Fallback | Group Frame Label | Group Unit Key |
|--------|------|----------|-------------------|----------------|
| Solo | Base | — | (hidden) | — |
| Party | Base | — | Party Frames | `party` |
| Raid | Base | — | Raid Frames | `raid` |
| Arena | Base | — | Arena Frames | `arena` |
| Mythic Raid | Derived | Raid | Raid Frames | `raid` |
| World Raid | Derived | Raid | Raid Frames | `raid` |
| Battleground | Derived | Raid | Raid Frames | `raid` |

Derived presets use their fallback's config until the user makes their first change, which flips `customized = true`. A "Reset to Default" action reverts to uncustomized state. The `customized` flag only exists on derived presets — base presets have no fallback and are always used directly.

## Sidebar Structure

```
GLOBAL                              (section, order=1)
  Appearance
  Click Casting
  Profiles
─────────────────────────
FRAME PRESETS                       (section, order=2)
  ▸ Frame Presets                   ← nav item, opens preset management panel
─────────────────────────
PRESET SCOPED                       (section, order=3)
  Editing: Solo Frame Preset        ← non-interactive accent label, updates dynamically
  FRAMES                            ← visual sub-heading
    Player
    Target
    Target of Target
    Focus
    Pet
    Boss
    Party Frames                    ← label adapts per preset; hidden for Solo
  AURAS                             ← visual sub-heading
    Buffs
    Debuffs
    Raid Debuffs
    Externals
    Defensives
    Missing Buffs
    Targeted Spells
    Dispels
    Private Auras
    Loss of Control
    Crowd Control
─────────────────────────
BOTTOM                              (section, order=99)
  About
```

### Framework section definitions

| Section ID | Label | Order |
|------------|-------|-------|
| `GLOBAL` | `GLOBAL` | 1 |
| `FRAME_PRESETS` | `FRAME PRESETS` | 2 |
| `PRESET_SCOPED` | _(no label — uses "Editing: X" instead)_ | 3 |
| `BOTTOM` | _(empty)_ | 99 |

Replaces the previous sections: `GENERAL`, `UNIT_FRAMES`, `GROUP_FRAMES`, `AURAS`.

### Key sidebar behaviors

- FRAMES and AURAS are visual sub-headings within the PRESET_SCOPED zone, not clickable items.
- The group frame item's label changes based on the active preset: hidden for Solo, "Party Frames" for Party, "Raid Frames" for Raid/Mythic Raid/World Raid/Battleground, "Arena Frames" for Arena.
- Boss frames are per-preset (boss encounters vary by content) and always visible. All presets include a boss unitConfig with sensible defaults.
- The "Editing: X Frame Preset" label updates whenever the user selects a different preset. This fires `EDITING_PRESET_CHANGED` on EventBus so all visible scoped panels can refresh.

## Frame Presets Panel

Clicking "Frame Presets" in the sidebar opens the preset management panel.

### Preset List

Rows for all 7 presets, similar to the indicator list pattern:

- Each row shows: preset name, status tag ("base" or "uses: Raid" / "customized"), and a [Select] button.
- The currently selected preset row shows accent highlight and "Editing" state.
- Row hover highlights persist when hovering child buttons.

### Actions

- **Copy Settings From...** — Dropdown to pick a source preset + "Copy" button. Confirmation dialog: "Copy all settings from Raid to Mythic Raid? This will overwrite current settings." Copies everything: unitConfigs, auras, and positions. If copying to a derived preset, flips `customized = true`. If the source is an uncustomized derived preset, copies the fallback's data.
- **Reset to Default** — Resets the selected preset to its default config and sets `customized = false`. Confirmation dialog. Only available for derived presets.

### Auto-Switch

Below the preset list, a mapping of content types to presets:

| Content Type | Preset Dropdown |
|---|---|
| Solo Content | [Solo Frame Preset ▼] |
| Party Content | [Party Frame Preset ▼] |
| Raid Content | [Raid Frame Preset ▼] |
| Mythic Raid Content | [Mythic Raid Preset ▼] |
| World Raid Content | [World Raid Preset ▼] |
| Battleground Content | [Battleground Preset ▼] |
| Arena Content | [Arena Frame Preset ▼] |

Content type keys use camelCase enum values (`ContentType.SOLO = 'solo'`, `ContentType.MYTHIC_RAID = 'mythicRaid'`, etc.) to avoid collision with preset display names.

### Spec Overrides

Collapsible per-spec sections. Each spec expands to show content type → preset dropdown overrides:

```
▸ Restoration
    Party Content         [Party Preset       ▼]
    Raid Content          [Raid Preset        ▼]
    Mythic Raid Content   [Use default        ▼]
    ...
▸ Guardian              (collapsed)
▸ Balance               (collapsed)
▸ Feral                 (collapsed)
```

"Use default" means fall through to the auto-switch mapping. Only overrides where a specific preset is selected are stored. Spec list is populated from the current character's class.

Stored as: `FramedCharDB.specOverrides[specID][contentType] = presetName`

This replaces the old flat format (`contentType:specID` concatenated keys). Old format is dead code to be removed.

## Aura Scoping

Auras are scoped **per preset AND per unit type**. The full path is:

**Preset → Unit Type → Aura Type → Config**

Auras are stored in a dedicated `auras` subtree within each preset, NOT inside `unitConfigs`. All element setup code and settings panels must read auras from `preset.auras[unitType]` instead of `unitConfigs[unitType].buffs` etc. This is a breaking change from the current structure where aura configs live inside unitConfigs.

### Aura Panel UI

Each aura panel (Buffs, Debuffs, etc.) shows a unit type dropdown at the top:

```
┌──────────────────────────────────────┐
│ Configure for: [Party Frames     ▼]  │
│                                      │
│ [Copy to...]                         │
│                                      │
│ (aura-specific settings/CRUD)        │
└──────────────────────────────────────┘
```

The dropdown lists all unit types relevant to the active preset: Player, Target, Target of Target, Focus, Pet, Boss, and the group frame type (Party Frames / Raid Frames / Arena Frames — hidden for Solo).

Default selection is the most relevant unit for the preset: group frames for Party/Raid/Arena, Player for Solo.

### Copy To

"Copy to..." opens a dialog with checkboxes for each unit type within the same preset:

```
┌─ Copy Buff Settings ──────────────────┐
│ Copy Player's buff settings to:       │
│                                       │
│ [✓] Target                            │
│ [✓] Target of Target                  │
│ [ ] Focus                             │
│ [ ] Pet                               │
│ [ ] Boss                              │
│ [✓] Party Frames                      │
│                                       │
│        [Cancel]  [Copy]               │
└───────────────────────────────────────┘
```

Copy overwrites the target units' config entirely for that aura type (no merge).

### Scoped Page Banner

All preset-scoped pages (Frames and Auras) show a subtle banner at the top: "These settings apply to: Party Frame Preset" in accent color.

## Data Architecture

### FramedDB.presets

```lua
FramedDB.presets = {
    ["Solo"] = {
        isBase = true,
        -- no 'customized' or 'fallback' on base presets
        positions = {},         -- edit mode frame positions
        unitConfigs = {
            player = { width, height, health, power, name, castbar, portrait, ... },
            target = { ... },
            targettarget = { ... },
            focus = { ... },
            pet = { ... },
            boss = { ... },
            -- no group frame key for Solo
        },
        auras = {
            player = {
                buffs = { indicators = { ["My Buffs"] = {...} } },
                debuffs = { ... },
                raidDebuffs = { ... },
                externals = { ... },
                defensives = { ... },
                missingBuffs = { ... },
                targetedSpells = { ... },
                dispellable = { ... },
                privateAuras = { ... },
                lossOfControl = {},     -- ships empty, user configures
                crowdControl = {},      -- ships empty, user configures
            },
            target = { ... },
            targettarget = { ... },
            focus = { ... },
            pet = { ... },
            boss = { ... },
        },
    },
    ["Party"] = {
        isBase = true,
        positions = {},
        unitConfigs = {
            player = { ... },
            target = { ... },
            targettarget = { ... },
            focus = { ... },
            pet = { ... },
            boss = { ... },
            party = { ... },    -- group frames stored as typed unitConfig key
        },
        auras = {
            player = { ... },
            target = { ... },
            party = { ... },    -- group frame auras use same key as unitConfigs
            boss = { ... },
            ...
        },
    },
    ["Raid"] = {
        isBase = true,
        positions = {},
        unitConfigs = {
            player = { ... },
            target = { ... },
            boss = { ... },
            raid = { ... },     -- raid group frame config
            ...
        },
        auras = {
            player = { ... },
            raid = { ... },
            boss = { ... },
            ...
        },
    },
    ["Arena"] = {
        isBase = true,
        positions = {},
        unitConfigs = {
            player = { ... },
            target = { ... },
            boss = { ... },
            arena = { ... },    -- arena frame config
            ...
        },
        auras = {
            player = { ... },
            arena = { ... },
            boss = { ... },
            ...
        },
    },
    ["Mythic Raid"] = {
        customized = false,
        fallback = "Raid",
        positions = {},
        unitConfigs = { ... },  -- populated from Raid defaults, overwritten on first edit
        auras = { ... },
    },
    ["World Raid"] = { customized = false, fallback = "Raid", ... },
    ["Battleground"] = { customized = false, fallback = "Raid", ... },
}
```

### Key data structure decisions

- **No `groupConfig` field.** Group frames use typed keys in `unitConfigs`: `party`, `raid`, or `arena`. Each preset type knows which key to use based on its group frame label mapping.
- **Auras live in `preset.auras`, NOT in `unitConfigs`.** This is a breaking change. All code that currently reads `unitConfigs[unitType].buffs` or `.debuffs` must change to read from `preset.auras[unitType].buffs`.
- **`customized` and `fallback` only exist on derived presets.** Base presets have `isBase = true` and no fallback logic.
- **Boss unitConfig exists on all presets** with sensible defaults (width, height, health bar, etc.).
- **`lossOfControl` and `crowdControl`** ship as empty tables `{}` in aura configs. Users configure them manually if desired.

### Default Aura Config

Every unit type within every preset ships with a default buff indicator:

```lua
{
    name = "My Buffs",
    type = "Icons",
    enabled = true,
    spells = {},            -- empty = track all helpful auras
    castBy = "me",          -- filters to player-cast only
    iconSize = 14,
    maxDisplayed = 3,
    orientation = "RIGHT",
    anchor = { "TOPLEFT", nil, "TOPLEFT", 2, -2 },
}
```

Other aura types (debuffs, raidDebuffs, externals, etc.) retain their current default configs from the existing layout defaults, restructured into the `auras` subtree.

### FramedCharDB changes

```lua
FramedCharDB = {
    autoSwitch = {
        ['solo'] = "Solo",
        ['party'] = "Party",
        ['raid'] = "Raid",
        ['mythicRaid'] = "Mythic Raid",
        ['worldRaid'] = "World Raid",
        ['battleground'] = "Battleground",
        ['arena'] = "Arena",
    },
    specOverrides = {
        -- [specID] = { [contentType] = presetName }
        -- e.g. [105] = { ['party'] = "Party", ['raid'] = "Raid" }
    },
    tourState = { ... },
}
```

- `editModePositions` removed from FramedCharDB — positions now live in each preset.
- Content type keys are camelCase strings to distinguish from preset display names.
- Old `specOverrides` flat format (`contentType:specID`) is dead code — remove entirely.

### accountDefaults changes

`Config.lua`'s `accountDefaults` replaces `layouts = {}` with `presets = { ... }` containing the full default preset structure. `PresetDefaults.EnsureDefaults()` (renamed from `LayoutDefaults.EnsureDefaults()`) populates the complete preset data on first run.

## Config Resolution Chain

### Auto-switch (runtime)

1. Detect content type (solo, party, raid, arena, etc.)
2. Check spec override: `FramedCharDB.specOverrides[activeSpecID][contentType]`
3. Else use `FramedCharDB.autoSwitch[contentType]`
4. Load preset. If `customized == false` and `fallback` exists, load the fallback preset instead.
5. Apply unitConfigs, auras, and positions.

### StyleBuilder.GetConfig(unitType)

1. Get active preset from `F.AutoSwitch.GetCurrentPreset()`
2. Load `FramedDB.presets[presetName]`
3. If not customized and has fallback, load fallback preset
4. Return `preset.unitConfigs[unitType]`

### Aura element setup

1. Get active preset (same resolution as above)
2. Read `preset.auras[unitType][auraType]`
3. Pass config to element Setup function

### Settings UI reads/writes

All settings panels use `F.Settings.GetEditingPreset()` (not the auto-switch active preset) to determine which preset to read/write. This allows editing presets you're not currently in.

When `SetEditingPreset()` is called, it fires `EDITING_PRESET_CHANGED` on EventBus. All built scoped panels must listen for this event and refresh their content.

When any scoped config value is written to a derived preset, the write handler checks `customized` and flips it to `true` if still `false`.

## Edit Mode

Edit Mode respects the "Editing: X" preset selection from settings, not the auto-switch active preset. When entering Edit Mode:

- Label shown: "Edit Mode: X Frame Preset"
- Preview frames reflect the selected preset's config
- Positions save to `FramedDB.presets[editingPreset].positions`
- The user can set up frame positions for any preset regardless of current content type

## Codebase Renames

| Old | New |
|-----|-----|
| `FramedDB.layouts` | `FramedDB.presets` |
| `GetEditingLayout()` | `GetEditingPreset()` |
| `SetEditingLayout()` | `SetEditingPreset()` |
| `AutoSwitch.GetCurrentLayout()` | `AutoSwitch.GetCurrentPreset()` |
| `layouts.X.unitConfigs` config paths | `presets.X.unitConfigs` |
| Sections: UNIT_FRAMES, GROUP_FRAMES, AURAS | PRESET_SCOPED |
| Sections: GENERAL | GLOBAL |
| "Layouts" panel | "Frame Presets" panel |
| `LayoutManager` | `PresetManager` |
| `LayoutDefaults` | `PresetDefaults` |
| `LAYOUT_CHANGED` event | `PRESET_CHANGED` event |
| _(new)_ | `EDITING_PRESET_CHANGED` event |

## Migration

No migration code needed — only one user (developer) has the addon installed. Clean install with new `accountDefaults` defining the full preset structure. Old `FramedDB` can be deleted manually if needed.

## Future Enhancements

- **Cross-preset aura copy** — Copy aura settings from one preset to another (e.g., Party debuffs → Raid debuffs). Currently "Copy to..." only works within the same preset across unit types.
- **Sync presets** — Keep multiple presets in sync for users who want identical settings across content types.
- **Import/Export presets** — Part of Phase 7, adapted to work with the preset structure.
- **Custom presets** — Allow users to create additional presets beyond the 7 defaults (e.g., "Mythic+ Push" vs "Mythic+ Farm").
