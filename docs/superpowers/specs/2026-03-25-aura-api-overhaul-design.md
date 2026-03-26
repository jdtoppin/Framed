# Aura API Overhaul Design

## Overview

Migrate all aura elements from the legacy `C_UnitAuras.GetAuraDataByIndex` loop pattern to the new `C_UnitAuras.GetUnitAuras` API introduced in WoW 12.0.1. This eliminates manual iteration, leverages server-side filtering and sorting, and adopts new semantic filter strings (`CROWD_CONTROL`, `RAID_PLAYER_DISPELLABLE`, `BIG_DEFENSIVE`, `EXTERNAL_DEFENSIVE`, etc.).

**Minimum client:** 12.0.1 (`## Interface: 120001`). No feature detection or fallback for older clients.

## Goals

- Replace all `GetAuraDataByIndex` while-loops with single `GetUnitAuras` calls
- Use new filter strings to push filtering to the server where possible
- Retain Lua-side logic only where the API cannot express the filter (registry priority, CC type classification, source checks)
- Add visibility mode and source-based color differentiation to Defensives and Externals
- Delete `Data/DefensiveSpells.lua` — spell ID tables replaced by API filters

## Non-Goals

- No changes to oUF element registration pattern (Enable/Disable/Update/ForceUpdate)
- No shared aura cache between elements — each element fetches independently
- No changes to the buff indicator system's matching logic (just the iteration method)
- MissingBuffs element is excluded from this migration — it checks for the *absence* of specific raid buffs, not aura filtering. It will be addressed in a separate pass if needed.

---

## Section 1: New API Surface

### `C_UnitAuras.GetUnitAuras(unit, filter, maxCount, sortRule, sortDirection)`

Returns a filtered, sorted array of `AuraData` in a single call.

**Parameters:**
- `unit` — unit token
- `filter` — pipe-delimited string (e.g. `'HARMFUL|CROWD_CONTROL'`)
- `maxCount` — optional limit on results
- `sortRule` — `Enum.UnitAuraSortRule` (Default, BigDefensive, Expiration, ExpirationOnly, Name, NameOnly)
- `sortDirection` — `Enum.UnitAuraSortDirection` (Ascending, Descending)

### New Filter Strings

| Filter | Scope | Combinable with |
|---|---|---|
| `CROWD_CONTROL` | CC debuffs (stun, fear, silence, etc.) | `HARMFUL` |
| `RAID_PLAYER_DISPELLABLE` | Debuffs the current player can dispel | `HARMFUL` |
| `RAID_IN_COMBAT` | Raid-relevant debuffs during combat | `HARMFUL` |
| `BIG_DEFENSIVE` | Major personal defensives | `HELPFUL`, `PLAYER` |
| `EXTERNAL_DEFENSIVE` | Externals (Pain Suppression, BoP, etc.) | `HELPFUL`, `PLAYER` |
| `IMPORTANT` | Server-flagged important auras | `HELPFUL`, `HARMFUL` |
| `RAID` | Raid-frame-relevant (includes dungeon/M+) | `HELPFUL`, `HARMFUL`, `PLAYER` |
| `PLAYER` | Cast by the querying player | Combinable with most filters |

---

## Section 2: Buffs Element

**Current:** `GetAuraDataByIndex` with `HELPFUL`, iterates all buffs, matches each against indicator spell lists.

**New:** `GetUnitAuras('HELPFUL')` returns all helpful auras in one array. Same indicator matching logic in Lua — the API doesn't know about our indicator definitions.

**No changes** to indicator spell matching, priority, or display logic. Only the iteration method changes.

---

## Section 3: Debuffs & RaidDebuffs

### Debuffs (pooled harmful display)

**Current:** `GetAuraDataByIndex` + `HARMFUL`, Lua `table.sort` by `isBossAura` then duration, optional `onlyDispellableByMe` post-filter via `F.CanPlayerDispel()`.

**New:**
- Base: `GetUnitAuras('HARMFUL', maxCount, Enum.UnitAuraSortRule.Default)`
- With dispellable filter: `GetUnitAuras('HARMFUL|RAID_PLAYER_DISPELLABLE', maxCount, Enum.UnitAuraSortRule.Default)`
- `F.CanPlayerDispel()` retained for the `onlyDispellableByMe` toggle (option to use either Lua filter or API filter — API preferred when the toggle maps directly to `RAID_PLAYER_DISPELLABLE`)

### RaidDebuffs (registry-filtered)

**Current:** `GetAuraDataByIndex` + `HARMFUL`, checks each aura against `F.Data.RaidDebuffs` registry for priority tier, applies flag filters, user custom overrides.

**New:**
- `GetUnitAuras('HARMFUL|RAID')` — server pre-filters to raid-relevant debuffs (includes dungeon/M+ content)
- Registry priority matching, flag filtering, and user custom overrides remain in Lua — the API cannot express these
- Smaller input set to iterate (only raid-relevant, not all harmful)

### Dispellable (highest-priority single debuff)

**Current:** `GetAuraDataByIndex` + `HARMFUL`, `F.CanPlayerDispel()` per aura, priority ranking (Magic > Curse > Disease > Poison > Physical), Physical/bleed debuffs pass for healer awareness even when `onlyDispellableByMe` is enabled.

**New:** `GetUnitAuras('HARMFUL|RAID_PLAYER_DISPELLABLE')` — server filters to player-dispellable debuffs. **Lua-side priority selection retained** — the server sort order does not match our `DISPEL_PRIORITY` ranking (Magic > Curse > Disease > Poison), so we fetch all matches and pick the highest-priority one in Lua.

**Physical/bleed handling:** `RAID_PLAYER_DISPELLABLE` excludes Physical debuffs since the player cannot dispel them. To preserve the "healer awareness" behavior, issue a supplementary `GetUnitAuras('HARMFUL|RAID', maxCount)` query and check for Physical debuffs. If a Physical debuff outranks all dispellable results, display it instead. This is a config toggle (`showPhysicalDebuffs`, default true).

---

## Section 4: Crowd Control Elements

### LossOfControl (CC on friendly units)

**Current:** Hardcoded ~50 CC spell ID table with type classification (Stun, MC, Fear, Silence, Root). `GetAuraDataByIndex` + `HARMFUL`, spell ID lookup.

**New:**
- `GetUnitAuras('HARMFUL|CROWD_CONTROL', 1)` — server identifies CC auras
- **Keep CC type lookup table** — the API tells us *that* it's CC but not *what kind*. We need the type for display colors (red for stun, purple for MC, etc.)
- Table becomes a type classifier only (no longer used for filtering)

### CrowdControl (player-cast CC on enemies)

**Current:** `C_Spell.IsSpellCrowdControl()` with fallback table, filters for player-cast.

**New:**
- `GetUnitAuras('HARMFUL|CROWD_CONTROL|PLAYER')` — server filters to player-cast CC auras only. Uses `|PLAYER` suffix consistent with Defensives/Externals pattern, and avoids touching potentially-secret `sourceUnit` field.
- `C_Spell.IsSpellCrowdControl()` fallback table no longer needed for filtering

---

## Section 5: Externals & Defensives

Both elements adopt the same pattern: show all auras by default, with visibility mode control and source-based color differentiation (matching Cell's approach).

### Filter Strategy

| Element | Classification filter | Source check filter |
|---|---|---|
| **Defensives** | `'HELPFUL\|BIG_DEFENSIVE'` | `'HELPFUL\|BIG_DEFENSIVE\|PLAYER'` |
| **Externals** | `'HELPFUL\|EXTERNAL_DEFENSIVE'` | `'HELPFUL\|EXTERNAL_DEFENSIVE\|PLAYER'` |

### Visibility Mode

Per-element dropdown with three options:

| Mode | Primary filter | Source check | Behavior |
|---|---|---|---|
| **All** (default) | Base filter | `\|PLAYER` check | Show all, color by source |
| **Player Only** | Base filter + `\|PLAYER` | Not needed | Only player-cast auras |
| **Others Only** | Base filter | `\|PLAYER` check | Exclude auras matching `\|PLAYER` |

### Source Color Differentiation

Two color pickers per element:
- `playerColor` — default green `{0, 0.8, 0}` — border color for player-cast auras
- `otherColor` — default yellow `{1, 0.85, 0}` — border color for other-cast auras

For secret auras, `sourceUnit` may be secret — use the `|PLAYER` filter suffix instead of checking `sourceUnit` directly. Apply this approach universally for consistency.

### Existing Settings Retained

All current settings remain unchanged:
- Icon size, max displayed, frame level, anchor picker
- The visibility mode dropdown and color pickers are additions, not replacements

### Data File Deletion

`Data/DefensiveSpells.lua` is deleted. Both `ExternalSpellIDs` and `DefensiveSpellIDs` tables are replaced entirely by server-side `EXTERNAL_DEFENSIVE` and `BIG_DEFENSIVE` filters.

---

## Section 6: oUF Integration & Element Lifecycle

The oUF element pattern is unchanged:

1. `oUF:AddElement(name, Update, Enable, Disable)` — registration
2. `Enable` hooks `UNIT_AURA` event
3. `Update` runs the aura query and updates display

Changes within `Update` functions only:
- **Replace iteration loops** with single `GetUnitAuras` calls
- **No shared aura cache** — each element fetches independently (oUF element-per-concern model)
- **`maxCount` optimization** — elements displaying one aura (Dispellable) or few (Defensives/Externals) pass small `maxCount`
- **Sort rules** — elements like Debuffs use `Enum.UnitAuraSortRule.Default` instead of Lua `table.sort`
- **Secret value handling** — same `F.IsValueNonSecret()` pattern, fewer Lua filtering touchpoints overall

**Empty results:** `GetUnitAuras` returns an empty table (not nil) when no auras match. Elements should iterate the result with `for _, aura in next, auras do` — an empty table naturally produces zero iterations.

No changes to Enable, Disable, ForceUpdate, or element registration.

---

## Section 7: TOC & File Structure

- **Delete:** `Data/DefensiveSpells.lua`
- **TOC:** Remove `Data\DefensiveSpells.lua` entry, bump `## Interface:` to `120001`
- **No new files** — all changes are modifications to existing files in `Elements/Auras/`, `Elements/Status/`, and their corresponding settings panels
- **Settings panels:** Defensives and Externals panels gain visibility mode dropdown + two color pickers

---

## Section 8: Migration Summary

| Element | Old Pattern | New Pattern |
|---|---|---|
| **Buffs** | `GetAuraDataByIndex` + HELPFUL, per-indicator spell lookup | `GetUnitAuras('HELPFUL')`, same indicator matching |
| **Debuffs** | `GetAuraDataByIndex` + HARMFUL, Lua sort by boss/duration | `GetUnitAuras('HARMFUL', max, SortRule.Default)` |
| **RaidDebuffs** | `GetAuraDataByIndex` + HARMFUL, registry priority filter | `GetUnitAuras('HARMFUL\|RAID')`, registry in Lua |
| **Dispellable** | `GetAuraDataByIndex` + HARMFUL, `F.CanPlayerDispel()` | `GetUnitAuras('HARMFUL\|RAID_PLAYER_DISPELLABLE')`, Lua priority select |
| **Externals** | `GetAuraDataByIndex` + HELPFUL, spell ID table, source check | `GetUnitAuras('HELPFUL\|EXTERNAL_DEFENSIVE')` + `\|PLAYER` for color |
| **Defensives** | `GetAuraDataByIndex` + HELPFUL, spell ID table, source check | `GetUnitAuras('HELPFUL\|BIG_DEFENSIVE')` + `\|PLAYER` for color |
| **LossOfControl** | `GetAuraDataByIndex` + HARMFUL, CC spell ID table | `GetUnitAuras('HARMFUL\|CROWD_CONTROL', 1)`, keep type lookup |
| **CrowdControl** | `GetAuraDataByIndex` + HARMFUL, `IsSpellCrowdControl()` | `GetUnitAuras('HARMFUL\|CROWD_CONTROL\|PLAYER')` |
