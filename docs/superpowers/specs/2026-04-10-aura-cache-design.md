# Aura Cache Design

**Goal:** Eliminate redundant `C_UnitAuras.GetUnitAuras` calls across aura elements by caching results per `(unit, filter)` pair within each UNIT_AURA event cycle.

**Problem:** Currently, 9 aura elements each independently call `C_UnitAuras.GetUnitAuras` on every UNIT_AURA event. For a single unit, this means 4 identical `HELPFUL` queries (Buffs, Defensives, Externals, MissingBuffs) and 2-4 `HARMFUL`-variant queries (Debuffs, Dispellable, CrowdControl, LossOfControl). Each call allocates a new result table, leading to ~0.03MB growth per buff cast vs Cell's ~0.01MB.

**Approach:** A thin, generation-counter-based cache module that deduplicates `GetUnitAuras` calls within the same event frame. Elements swap one line — the API call — and keep all their iteration, filtering, and rendering logic untouched.

## Module

New file: `Core/AuraCache.lua`

Exposes a single function:

```lua
F.AuraCache.GetUnitAuras(unit, filter) -> table
```

Drop-in replacement for `C_UnitAuras.GetUnitAuras(unit, filter)`. Returns the same table the API would. Elements change only which function they call, not how they consume the result.

## Internals

### Data Structures

```lua
local generation = {}  -- generation[unit] = number, bumped on each UNIT_AURA for that unit
local cache = {}       -- cache[key] = { gen = number, result = table }
                       -- key = unit .. '\0' .. filter
```

### Generation Counter

A lightweight raw frame (not oUF) registers for `UNIT_AURA`. On each event, it increments `generation[unit]`. Because this is a raw frame event handler, it fires before oUF dispatches the event to element Update functions.

### Cache Lookup

When an element calls `F.AuraCache.GetUnitAuras(unit, filter)`:

1. Build cache key: `unit .. '\0' .. filter`
2. Check if `cache[key].gen == generation[unit]` — if so, return `cache[key].result`
3. On cache miss: call `C_UnitAuras.GetUnitAuras(unit, filter)`, store in `cache[key]` with current generation, return result

### Memory

- Cache entries: `(active units) × (unique filters)` — roughly 10-15 entries in a raid
- Result tables are the API's own tables (no copies) — no extra allocation
- Cache entry tables are reused across generations (overwrite `.gen` and `.result`, don't create new tables)
- No periodic wipe needed — generation counter handles staleness naturally
- Stale entries for units that leave the group sit idle at negligible cost

## Elements to Migrate

Each element changes exactly one line — the `GetUnitAuras` call:

```lua
-- Before:
local rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')

-- After:
local rawAuras = F.AuraCache.GetUnitAuras(unit, 'HELPFUL')
```

| Element | File | Filter(s) |
|---------|------|-----------|
| Buffs | Elements/Auras/Buffs.lua | `HELPFUL` or `HELPFUL\|RAID_IN_COMBAT` |
| Defensives | Elements/Auras/Defensives.lua | `HELPFUL` |
| Externals | Elements/Auras/Externals.lua | `HELPFUL` |
| MissingBuffs | Elements/Auras/MissingBuffs.lua | `HELPFUL` |
| Debuffs | Elements/Auras/Debuffs.lua | `HARMFUL` (+ variant filters) |
| Dispellable | Elements/Auras/Dispellable.lua | `HARMFUL\|RAID_PLAYER_DISPELLABLE` or `HARMFUL` |
| CrowdControl | Elements/Status/CrowdControl.lua | `HARMFUL\|CROWD_CONTROL\|PLAYER` |
| LossOfControl | Elements/Status/LossOfControl.lua | `HARMFUL\|CROWD_CONTROL` |

### Not in Scope

- **PrivateAuras** — uses `AddPrivateAuraAnchor`, no Lua-level bulk queries
- **BorderIcon / Icon** — use per-instance APIs (`GetAuraDispelTypeColor`, `GetAuraDuration`) on already-identified auras, not bulk queries. These are cheap single-aura lookups with nothing to deduplicate.

## TOC Loading Order

`Core/AuraCache.lua` loads after `Core/SecretValues.lua` and before any Element files, so `F.AuraCache` is available when elements initialize.

## Expected Impact

- ~5-7 `GetUnitAuras` calls per unit per UNIT_AURA event reduced to ~2 (one per unique filter actually used)
- Per-event table allocations cut by ~60-70%
- Expected memory growth per buff cast: ~0.03MB → ~0.01MB (matching Cell)

## Implementation Constraints

- **Do not modify element rendering logic.** Each element's iteration, filtering, classification, and rendering code stays untouched. The only change per element is swapping the `C_UnitAuras.GetUnitAuras` call to `F.AuraCache.GetUnitAuras`.
- **Do not refactor, reorganize, or "improve" surrounding code.** No adding comments, no renaming variables, no restructuring files. One-line swap per element, nothing else.
- **Do not change how elements register for or handle UNIT_AURA events.** oUF's element dispatch stays as-is.

## Future Considerations

A deeper refactor (Cell-style central dispatch with incremental updates via `updateInfo`) could eliminate even the remaining 2 calls per event, but would require restructuring how oUF elements receive aura data. That is out of scope for this change.
