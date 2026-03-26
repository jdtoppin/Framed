# Targeted Spells Redesign

## Overview

Replace the CLEU-based TargetedSpells element with a `UNIT_SPELLCAST_*` + nameplate approach. `CombatLogGetCurrentEventInfo` is nil on WoW 12.0+ clients, making the current implementation non-functional. The new design uses a centralized cast tracker (modeled on Cell's `Indicators/TargetedSpells.lua`) that listens for spellcast events on nameplates, target, and focus, then resolves cast targets via `UnitIsUnit(source.."target", groupUnit)`.

**Minimum client:** 12.0.1 (`## Interface: 120001`).

**Reference implementation:** [Cell's TargetedSpells](https://github.com/jdtoppin/Cell/blob/master/Indicators/TargetedSpells.lua)

## Goals

- Replace CLEU-based cast detection with `UNIT_SPELLCAST_*` events
- Support Midnight secret values via `SetAlphaFromBoolean` display path
- Use `C_Spell.IsSpellImportant` for server-side spell filtering (no Lua spell ID tables)
- Maintain oUF element contract (Enable/Disable/Update/ForceUpdate) with centralized tracker firing ForceUpdate on registered frames
- No changes to existing settings panel or config keys

## Non-Goals

- No user-configurable spell ID list (secret spellIds make Lua lookups unreliable in instanced content)
- No `showAllSpells` toggle — filtering is handled by `C_Spell.IsSpellImportant`
- No cast grouping / stacking (Cell groups duplicate spells with a count; we show each cast individually)
- No changes to display modes (Icons/BorderGlow/Both), glow system, or icon rendering
- No changes to Setup function signature or config shape

---

## Section 1: Centralized Cast Tracker

A new file `Core/CastTracker.lua` — a module-level singleton that owns all spellcast event listening and target resolution.

### Events

| Event | Purpose |
|---|---|
| `UNIT_SPELLCAST_START` | Enemy begins casting |
| `UNIT_SPELLCAST_STOP` | Cast ends normally |
| `UNIT_SPELLCAST_DELAYED` | Cast delayed (recheck) |
| `UNIT_SPELLCAST_FAILED` | Cast failed |
| `UNIT_SPELLCAST_INTERRUPTED` | Cast interrupted |
| `UNIT_SPELLCAST_CHANNEL_START` | Channel begins |
| `UNIT_SPELLCAST_CHANNEL_STOP` | Channel ends |
| `UNIT_SPELLCAST_CHANNEL_UPDATE` | Channel updated (recheck) |
| `PLAYER_TARGET_CHANGED` | Recheck target's cast |
| `NAME_PLATE_UNIT_ADDED` | New nameplate — check for active cast |
| `NAME_PLATE_UNIT_REMOVED` | Nameplate gone — clean up cast entry |
| `ENCOUNTER_END` | Reset all state |
| `PLAYER_REGEN_ENABLED` | Reset all state |
| `PLAYER_ENTERING_WORLD` | Reset all state (instance transitions, loading screens) |

**Source unit filtering:** Ignore `sourceUnit` values starting with `"soft"` (soft-target units) to avoid spurious cast tracking.

### Cast State

`casts` table keyed by `sourceUnit` string (e.g., `"nameplate3"`, `"target"`). GUIDs are avoided because they can be secret on Midnight.

Each entry:

```lua
{
    startTime      = number,       -- cast start (seconds)
    endTime        = number,       -- cast end (seconds)
    icon           = number,       -- spell texture
    isChanneling   = boolean,      -- channel vs cast
    sourceUnit     = string,       -- e.g., "nameplate3"
    spellId        = any,          -- may be secret
    isImportant    = boolean,      -- C_Spell.IsSpellImportant result (may be derived from secret)
    targetUnit     = string|nil,   -- resolved group unit (non-secret path only)
    recheck        = number,       -- recheck counter (0-6)
}
```

### Target Resolution

Two paths:

**Non-secret path:** `SafeUnitIsUnit(source.."target", groupUnit)` returns normal booleans. Iterate player, pet, group members, group pets. Store resolved `targetUnit` in the cast entry.

**Secret path:** `UnitIsUnit` returns secret values. Set `useSecretPath = true`. Don't resolve `targetUnit` — the element's display layer uses `SetAlphaFromBoolean(UnitIsUnit(cast.sourceUnit.."target", unit))` to let the C-level API handle visibility.

`SafeUnitIsUnit` helper:

```lua
local function SafeUnitIsUnit(a, b)
    local result = UnitIsUnit(a, b)
    if(not F.IsValueNonSecret(result)) then return false end
    return result
end
```

Secret path detection (in `GetTargetUnitID_Safe`): when `UnitExists(source.."target")` is true but `UnitIsUnit` returns a secret value, flip to secret path.

### Recheck Timer

OnUpdate frame at 0.1s interval, up to 6 rechecks (0.6s total). Caster's target can change mid-cast. On each tick:
- Non-secret path: re-resolve target, update if changed
- Secret path: re-call `CheckUnitCast` to refresh state and broadcast ForceUpdate

### Spell Filtering

`C_Spell.IsSpellImportant(spellId)` — C-level API, accepts secret spellIds. Used as a priority signal, not a hard filter.

- **All display modes:** All enemy casts targeting group members are tracked. `isImportant` casts sort before non-important casts. If `IsSpellImportant` has poor coverage, icons still show — they just won't be priority-sorted.
- **Border/Both modes:** Glow shows for any enemy cast targeting a group member regardless of importance.
- **Icons mode:** Shows all tracked casts (important sort first).

When `C_Spell.IsSpellImportant` returns a secret boolean, treat as important (safe assumption for enemy casts in instanced content).

No Lua spell ID tables. No user-configurable spell list.

### Cast Sort Order

Casts sorted by `isImportant` descending (important first), then `startTime` ascending (earliest cast first).

### API

```lua
F.CastTracker:Enable()                  -- Start listening (called once globally)
F.CastTracker:Disable()                 -- Stop listening
F.CastTracker:Register(frame)           -- Element Enable calls this
F.CastTracker:Unregister(frame)         -- Element Disable calls this
F.CastTracker:GetCastsOnUnit(unit)      -- Returns sorted cast list (non-secret path)
F.CastTracker:GetAllActiveCasts()       -- Returns all active casts (secret path)
F.CastTracker:IsSecretPath()            -- Whether secret display path is active
```

When casts change, the tracker iterates registered frames. For each frame, it accesses `frame.FramedTargetedSpells` and calls `element.ForceUpdate(element)` if the element exists.

### State Reset

On `ENCOUNTER_END`, `PLAYER_REGEN_ENABLED`, and `PLAYER_ENTERING_WORLD`: wipe all cast state, reset `useSecretPath = false`, ForceUpdate all registered frames (which will hide indicators).

---

## Section 2: oUF Element Redesign

`Elements/Auras/TargetedSpells.lua` becomes a thin display layer. All CLEU logic is deleted: `makeCLEUHandler`, `_cleuFrame`, `_activeSourceGUID`, `_activeSpellId`.

### Update Function

Two display paths based on `F.CastTracker:IsSecretPath()`:

**Non-secret path:**
1. `F.CastTracker:GetCastsOnUnit(self.unit)` returns sorted casts targeting this unit
2. For each cast (up to `maxDisplayed`): set icon texture, cooldown, show BorderIcon
3. Show glow if any casts are active and display mode includes glow
4. Hide unused pool entries

**Secret path:**
1. `F.CastTracker:GetAllActiveCasts()` returns all active casts
2. For each cast (up to `maxDisplayed`): set icon texture, cooldown normally, call `:Show()` on the icon frame
3. Use `SetAlphaFromBoolean(UnitIsUnit(cast.sourceUnit.."target", unit))` on each shown icon frame — C-level sets alpha to 1 (targeting this unit) or 0 (not targeting). The frame must be `:Show()`n first — `SetAlphaFromBoolean` only controls alpha, not visibility.
4. Glow: start glow effect, call `:Show()` on the glow parent frame, then `SetAlphaFromBoolean` with the first cast's targeting check

### Enable

```lua
local function Enable(self, unit)
    local element = self.FramedTargetedSpells
    if(not element) then return end

    element.__owner     = self
    element.ForceUpdate = ForceUpdate

    F.CastTracker:Register(self)

    return true
end
```

No event registration. The tracker owns all events.

### Disable

```lua
local function Disable(self)
    local element = self.FramedTargetedSpells
    if(not element) then return end

    F.CastTracker:Unregister(self)
    -- hideAll: hide all BorderIcon pool entries, stop glow, reset glow frame alpha
    hideAll(element)
end
```

### ForceUpdate

Standard: `Update(element.__owner, 'ForceUpdate', element.__owner.unit)`.

### Setup

No changes to the Setup function signature. Same config keys: `displayMode`, `iconSize`, `maxDisplayed`, `frameLevel`, `anchor`, `glow` (type, color, config). The `_cleuFrame` field is removed from the container table.

---

## Section 3: Secret Value Handling

| Value | Status on Midnight | Handling |
|---|---|---|
| `UnitIsUnit(a, b)` result | May be secret | `SafeUnitIsUnit` returns false; secret path uses `SetAlphaFromBoolean` |
| `spellId` | May be secret | `F.IsValueNonSecret` before Lua table ops; `C_Spell.GetSpellTexture(spellId)` and `C_Spell.IsSpellImportant(spellId)` accept secrets |
| `startTimeMS`, `endTimeMS` | May be secret | Fallback to `GetTime()` / `GetTime() + 3` when secret |
| `SetAlphaFromBoolean(secretBool)` | C-level, accepts secrets | Sets frame alpha 1 (true) or 0 (false) without Lua boolean test |
| `UnitExists(unit)` | Returns normal boolean | Safe for detecting if a target exists before testing `UnitIsUnit` |
| `UnitIsEnemy(a, b)` | Returns normal boolean | Safe for filtering to enemy casters |

Secret path detection: `GetTargetUnitID_Safe` checks `UnitExists(source.."target")` first. If the unit exists but `UnitIsUnit` returns a secret, flip `useSecretPath = true`. Once set, stays true until combat/encounter reset.

---

## Section 4: File Structure & TOC

- **New:** `Core/CastTracker.lua`
- **Modified:** `Elements/Auras/TargetedSpells.lua` (gut CLEU, consume tracker)
- **TOC:** Add `Core\CastTracker.lua` before `Elements\Auras\TargetedSpells.lua`
- **No changes to:** `Settings/Panels/TargetedSpells.lua`, config keys, display mode constants, glow system, BorderIcon creation
