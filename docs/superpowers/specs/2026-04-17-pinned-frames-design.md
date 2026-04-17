# Pinned Frames Design Spec

**Date:** 2026-04-17
**Issue:** #72
**Status:** Approved

## Summary

Pinned frames let users watch specific group members via a custom set of standalone unit frames outside the normal party/raid topology. Each pin tracks a player by name — if the roster reshuffles, the pin follows the player. Inspired by Cell's Spotlight feature, adapted to Framed's oUF architecture with a simpler interaction model.

## Motivation

Raid and party layouts cover the roster, but there's no slot for "I want dedicated frames for these specific people." Common use cases:

- Healer pinning both tanks for constant visibility
- Caller pinning the main kick target
- PvP player pinning focus target + arena targets
- Any role wanting to watch specific group members regardless of roster order

Framed already covers target, focus, boss, arena, and other unit types with dedicated frames. Pinned frames fill the remaining gap: **watching specific people in your group by name**.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Naming | Pinned | Clear action verb, no WoW vocabulary conflicts |
| Style model | Shared style, per-slot position | Matches party/raid pattern; keeps config simple |
| Max slots | 9 | 3x3 grid covers all real use cases |
| Layout | Fixed group with configurable columns | One drag handle; columns slider gives 1x9, 3x3, 9x1, 2x4, etc. |
| Preset scoping | Per-preset, disabled in Solo | Pins are a group content tool |
| Tracking model | Name-based | Pin follows the player, not the raid slot |
| Dropdown UX | Role-grouped with class colors | Intuitive; no abstract "raid17" tokens |
| Assignment UX | Right-click on frame + settings card | Day-to-day assignment on the frame, bulk config in settings |
| Static tokens | focus, focustarget only | All other unit types have dedicated frames |
| Duplicate prevention | Filter assigned names from dropdown | Simpler than Cell's "clear previous slot" approach |

## Data Model

Per-preset config under `unitConfigs.pinned`:

```lua
pinned = {
    enabled = true,
    count = 3,
    columns = 3,
    width = 160,
    height = 40,
    spacing = 2,
    -- standard shared frame config: health, power, name, statusIcons, etc.
    slots = {
        [1] = { type = 'name', value = 'Bigshield' },
        [2] = { type = 'nametarget', value = 'Bigshield' },
        [3] = { type = 'unit', value = 'focustarget' },
        -- [4]-[9] nil = unassigned
    },
    position = { x = 0, y = 0, anchor = 'CENTER' },
}
```

### Slot assignment types

- `type = 'name'` — tracks a player by name. Roster resolution on `GROUP_ROSTER_UPDATE` scans group members, resolves name to current unit token (e.g., `'raid7'`), and calls `SetAttribute('unit', token)`.
- `type = 'nametarget'` — tracks a player's target. Resolves the player name to a unit token, then appends `'target'` (e.g., `'raid7target'`). Useful for healers watching what their tank is targeting. Requires `refreshOnUpdate` since there is no event for derived target changes.
- `type = 'unit'` — direct unit token (`'focus'`, `'focustarget'`). No resolution needed. `'focustarget'` requires `refreshOnUpdate`.
- `nil` — unassigned. Frame hidden in combat, placeholder shown on hover out of combat.

### Defaults

Added to `Presets/Defaults.lua` as a `pinnedConfig()` function. Solo preset gets no `pinned` block (feature disabled). All group presets (Party, Raid, Arena, and derived presets) include pinned defaults with `enabled = false` so users opt in.

## Frame Spawning

All 9 frames are pre-spawned once at addon load via `oUF:Spawn()`, regardless of `count`. Frames beyond the active count stay hidden. This avoids creating/destroying frames at runtime.

```lua
oUF:Spawn('player', 'FramedPinned1')
oUF:Spawn('player', 'FramedPinned2')
-- ...
oUF:Spawn('player', 'FramedPinned9')
```

Frames spawn with `'player'` as a throwaway initial unit, then immediately reassigned via `SetAttribute('unit', ...)`. `RegisterUnitWatch` (called internally by oUF's `Spawn`) handles show/hide when the unit exists or doesn't — no custom visibility code needed.

### Performance

Only frames with a valid, existing unit fire element updates. Empty or unresolved slots cost zero — `RegisterUnitWatch` keeps them hidden and oUF skips updates for hidden frames.

### The `frame.unit` mirror

When swapping the unit attribute, `frame.unit` must be mirrored to the new value. `SetAttribute('unit', token)` updates the secure state, but oUF elements read `self.unit` directly for `UNIT_*` event handling. Both must stay in sync.

## Unit Resolution

### Name-based resolution

A resolver function runs on:

- `GROUP_ROSTER_UPDATE` — roster changes, joins, leaves, role changes
- `PLAYER_REGEN_ENABLED` — flush any combat-deferred assignments
- Pin assignment change — immediate resolution if out of combat

The resolver scans the group roster for each `type = 'name'` slot:

1. Iterate group members (`IsInRaid()` ? `'raid'..i` : `'party'..i`)
2. Match `UnitName(token)` against the stored name
3. If found: `SetAttribute('unit', token)`, mirror `frame.unit`
4. If not found: set unit to nil, frame hides via `RegisterUnitWatch`

Pin assignments persist in config even when the player isn't found, so pins auto-recover on rejoin.

### Name-target resolution

For `type = 'nametarget'` slots, the resolver first finds the player by name (same as `type = 'name'`), then appends `'target'` to the resolved token (e.g., `'raid7'` becomes `'raid7target'`). The frame is flagged with `refreshOnUpdate = true` since WoW fires no event for derived target changes — it must poll on `OnUpdate`.

### Static token resolution

For `type = 'unit'` slots (`'focus'`, `'focustarget'`), the token is used directly — no roster scanning. These work even outside groups. `'focustarget'` is flagged with `refreshOnUpdate = true` for the same reason as name-targets — no event for the focus target's target changing.

### Combat deferral

If the resolver fires during `InCombatLockdown()`, assignments are queued in a `pendingAssignments` table and flushed on `PLAYER_REGEN_ENABLED`. Frames show stale data briefly but won't taint.

## Grid Layout

Frames are arranged in a grid anchored from a single parent frame (`F.Units.Pinned.anchor`). Layout is calculated from `count`, `columns`, `width`, `height`, and `spacing`.

- **Rows** derived: `ceil(count / columns)`
- **Slot position**: row = `ceil(index / columns)`, col = `((index - 1) % columns) + 1`
- Slot 1 is top-left, slot 9 is bottom-right
- Gaps appear when pins are inactive — no collapsing or reflow

### Example configurations

| count | columns | Result |
|-------|---------|--------|
| 9 | 3 | 3x3 grid |
| 9 | 1 | 9x1 vertical stack |
| 9 | 9 | 1x9 horizontal strip |
| 8 | 2 | 2-wide, 4 rows |
| 8 | 4 | 4-wide, 2 rows |
| 5 | 3 | 3 top row, 2 bottom row |

## EditMode Integration

### Frame registry

Single entry in `FRAME_KEYS`:

```lua
{ key = 'pinned', label = 'Pinned Frames', isGroup = true,
  getter = function() return F.Units.Pinned and F.Units.Pinned.anchor end }
```

One drag handle moves the entire grid. In edit mode, all 9 slots render as preview frames (even unassigned ones) so the full grid footprint is visible for positioning.

### Inline settings panel

Clicking a pinned frame in edit mode opens the standard inline settings panel with shared style controls (width, height, spacing, columns, elements). Per-slot unit assignment is also accessible here.

### LiveUpdate

A `FrameConfigPinned.lua` handler listens for `unitConfigs.pinned.*` changes on `CONFIG_CHANGED` and updates layout, count, columns, and slot assignments in real time.

## Dropdown & Interaction

### Role-grouped dropdown

Built dynamically on each open by scanning the current roster. Structure:

```
-- Unit References --------
   Focus
   Focus Target
-- Tanks ------------------
   Bigshield           (class-colored)
     Bigshield's Target (class-colored, indented)
   Darkguard           (class-colored)
     Darkguard's Target (class-colored, indented)
-- Healers ----------------
   Moodibs             (class-colored)
     Moodibs's Target   (class-colored, indented)
-- DPS --------------------
   Zapmaster           (class-colored)
     Zapmaster's Target (class-colored, indented)
   ...
-- None -------------------
   (Unassign)
```

- Group headers (Unit References, Tanks, Healers, DPS, None) are non-selectable
- Player names are colored by class
- Each player name has an indented "Name's Target" sub-option beneath it
- Selecting a name stores `{ type = 'name', value = 'PlayerName' }`
- Selecting a name's target stores `{ type = 'nametarget', value = 'PlayerName' }`
- Selecting Focus/Focus Target stores `{ type = 'unit', value = 'focus'/'focustarget' }`
- Selecting Unassign sets the slot to `nil`
- **Duplicate prevention:** Players already assigned to another slot (by name or nametarget) are filtered out of the dropdown. Unassign frees the name for reuse.
- Role/spec changes update grouping next time the dropdown opens (dropdown rebuilds from live roster)

### Frame interaction

**Out of combat, non-edit-mode:**

- Hovering the pinned frame grid area reveals empty slot placeholders (dashed border or subtle "+" indicator)
- Left-click empty placeholder: opens dropdown
- Right-click assigned pin: opens dropdown to reassign/unassign
- Left-click assigned pin: normal WoW unit targeting

**In combat:**

- Assigned pins behave as normal secure unit frames (targeting, context menu, all standard WoW interactions)
- Pin assignment UI (dropdown, placeholders) is disabled — `SetAttribute` is blocked during lockdown
- Any assignment changes are queued and applied on `PLAYER_REGEN_ENABLED`

## Aura Configuration

Pinned frames integrate into the existing aura settings system as a first-class unit type. An `auras.pinned` section is added to `Presets/AuraDefaults.lua` with defaults matching the party/raid aura config (buffs, debuffs, dispellable, defensives, externals, etc.).

In the Auras settings panel, "Pinned Frames" appears as a selectable unit type alongside Player, Target, Party, Raid, etc. It auto-hides in Solo preset (same behavior as Party/Raid). Aura config is shared across all pinned slots, consistent with the shared-style model.

## Slot Identity Label

Each pinned frame displays a small secondary label showing the pin assignment context. This is dimmed text positioned above or below the name element:

- `type = 'name'` — no label needed; the name element already shows the player name
- `type = 'nametarget'` — label shows the source player's name (e.g., `Bigshield's Target`) so the pin is distinguishable from a direct name pin
- `type = 'unit'` — label shows the token in player-friendly form (e.g., `Focus Target`)

The label is part of the shared style (always shown when applicable, no per-slot toggle).

## Cross-Realm Name Handling

Player names are stored and matched using full name-realm format for cross-realm players (e.g., `'Bigshield-Stormrage'`). For same-realm players, the short name is sufficient.

- `UnitName(unit)` returns `name, realm` — the resolver concatenates with `'-'` when realm is non-nil
- The dropdown displays the full name-realm for cross-realm players, short name for same-realm
- Stored `value` in slot config uses the same format the resolver matches against

## OnUpdate Throttle

Frames flagged with `refreshOnUpdate` (`focustarget` and `nametarget` slots) use a throttled `OnUpdate` handler. The handler checks at most every **0.2 seconds** whether the derived unit has changed (via `UnitGUID` comparison against the last known value). If the GUID changes, element updates are triggered. This keeps CPU cost negligible even with multiple polling slots active.

## Settings Card

**"Pinned Frames"** registered as a `PRESET_SCOPED` panel in the settings sidebar.

### Layout

1. **Preview** — single representative frame with fake unit data (standard `FrameSettingsBuilder` preview card)
2. **Enable/Disable toggle** — top of card; disables all controls below when off
3. **Slot count slider** — 1 to 9
4. **Columns slider** — 1 to `count` (clamped dynamically)
5. **Spacing slider** — gap between frames
6. **Per-slot assignment list** — one row per active slot showing current assignment (class-colored name, "Focus Target", or "Unassigned"), each with the role-grouped dropdown
7. **Shared frame styling** — standard `FrameSettingsBuilder` cards (health, power, name, status icons, etc.)

## Edge Cases

### Player leaves group
Roster resolution finds no match → unit set to nil → frame hides. Assignment persists in config; auto-recovers if they rejoin.

### Preset switch
Loading a new preset triggers full re-resolution of that preset's pin assignments. Immediate if out of combat, deferred if in combat.

### Empty group
No roster to populate → all name-based pins hidden. Focus/focustarget pins still function (not roster-dependent).

### Slot count reduced
Dropping from 9 to 3 hides slots 4-9 immediately. Assignments persist; bumping back restores them.

### Role/spec change
Pin stays on the player (name-tracked, not role-tracked). Dropdown reflects updated role grouping on next open. `GROUP_ROSTER_UPDATE` fires on role changes, keeping the unit token valid.

### Feature disabled
`enabled = false` — no frames shown, no hover zone, no interaction. Settings card controls grayed out below the toggle.

## File Surface

| File | Action | Description |
|------|--------|-------------|
| `Units/Pinned.lua` | New | Style function, frame pool, resolver, combat deferral, grid layout, interaction handlers |
| `Settings/Panels/Pinned.lua` | New | Panel registration for sidebar |
| `Settings/Cards/Pinned.lua` | New | Custom per-slot assignment list card |
| `Presets/Defaults.lua` | Modify | Add `pinnedConfig()`, register in group presets |
| `Presets/AuraDefaults.lua` | Modify | Add `pinned` aura defaults section |
| `EditMode/EditMode.lua` | Modify | Add `pinned` entry to `FRAME_KEYS` |
| `Units/LiveUpdate/FrameConfigPinned.lua` | New | `CONFIG_CHANGED` handler for runtime updates |
| `Framed.toc` | Modify | Register new files in load order |
| `Init.lua` | Modify | Add `F.Units.Pinned.Spawn()` call in `oUF:Factory` |

## Estimated Size

- `Units/Pinned.lua`: ~400 lines (spawning, resolver, combat deferral, grid layout, interaction, refreshOnUpdate, slot identity label)
- `Settings/Panels/Pinned.lua`: ~15 lines
- `Settings/Cards/Pinned.lua`: ~180 lines (slot assignment list with role-grouped dropdown, duplicate filtering)
- `Units/LiveUpdate/FrameConfigPinned.lua`: ~80 lines
- Modifications to existing files: ~50 lines (Defaults, AuraDefaults, EditMode, TOC, Init)
- **Total: ~725 lines**
