# AuraState Classified Entry Pool Design

**Issue:** #144
**Related:** #155 (measurements that validated this target)
**Date:** 2026-04-22

## Goal

Eliminate per-update allocation of classified aura wrappers (`{ aura, flags }`) and their nested `flags` tables in `AuraState`, the dominant contributor to Framed's 80–93% share of the LFR memory yoyo measured in #155. Do so without reintroducing any of the three failure modes that killed the 0.7.20 pool (`7f21fb4` → `9d3cc54`).

## Non-Goals

Explicit single-PR scope. The following are tracked separately:

- **Item 2 from #155 ranked list:** Reduce `FullRefresh` call frequency. Deferred until post-pool re-measurement.
- **Item 3 from #155 ranked list:** Avoid `{ GetAuraSlots(...) }` varargs-pack allocation. Deferred for the same reason.
- **Pool changes to any other data structure** (`_helpfulMatches`, `_helpfulViews`, element-owned `iconsAurasPool`, etc.). Those paths are already allocation-free after the B1–B5 migrations (per #144 "what's already captured").

Bundling any of these in the same PR would muddy the before/after MemDiag attribution on the core change.

## Context

### What allocates today

`Core/AuraState.lua:18-42` — the `classify()` helper:

```lua
local function classify(unit, aura, isHelpful)
    local id = aura.auraInstanceID
    local prefix = isHelpful and 'HELPFUL' or 'HARMFUL'

    local flags = {
        isHelpful         = aura.isHelpful         or false,
        ...
    }
    flags.isExternalDefensive = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|EXTERNAL_DEFENSIVE') == false
    ...
    return { aura = aura, flags = flags }
end
```

Every call allocates two tables: the wrapper and the flags table (11 fields, all booleans).

### Call sites

Three entry points into `classify()`:

1. `AuraState:GetHelpfulClassified()` — line 395, called when the classified view list is dirty and a given ID isn't already in `_helpfulClassifiedById`.
2. `AuraState:GetHarmfulClassified()` — line 416, symmetric.
3. `AuraState:GetClassifiedByInstanceID()` — lines 433 and 445, covers one-shot classification lookups for a specific instance ID.

### Release points

Four methods drop classified entries today:

- `AuraState:InvalidateHelpfulClassified(id)` — line 119: `self._helpfulClassifiedById[id] = nil`
- `AuraState:InvalidateHarmfulClassified(id)` — line 123: symmetric
- `AuraState:ResetHelpfulClassified()` — line 111: `wipe(self._helpfulClassifiedById)`
- `AuraState:ResetHarmfulClassified()` — line 115: symmetric

All four currently drop references directly; GC reclaims the wrapper and flags.

### Why the 0.7.20 pool broke

Per #144 background, three compounding mistakes:

1. Copied secret fields (`duration`, `expirationTime`, `applications`, `sourceUnit`, `dispelName`) into Framed-owned tables. `wipe()` clears fields but preserves table identity, so reuse served one frame's secret data to another frame's consumer.
2. Module-level pool shared across frames. Entry `[5]` on `raid3` was the same Lua table reused next tick on `raid14`.
3. Sort comparator with a module upvalue — safe only if aura updates don't nest.

This design avoids all three.

## Design

### Pool shape

One paired free list per `AuraState` instance:

```lua
self._classifiedFreeList = {}
```

Entries on this list are `{ aura = nil, flags = {...} }` wrappers. The flags table identity stays attached to its wrapper across acquire/release cycles (flags is never pooled separately). Helpful and harmful entries share the same free list — they are structurally identical, and splitting by direction adds code with no benefit.

### Acquire

A single helper replaces inline `{ aura = aura, flags = flags }` construction:

```lua
local function acquireClassified(pool, unit, aura, isHelpful)
    local entry = pool[#pool]
    if entry then
        pool[#pool] = nil
        wipe(entry.flags)
    else
        entry = { flags = {} }
    end
    entry.aura = aura
    -- fill all 11 flags fields into entry.flags (body of existing classify())
    return entry
end
```

Called from all three classify sites. The wipe at acquire time satisfies the "fully cleared before reuse" guardrail lazily — entries released at end of session aren't wiped unnecessarily, and the wipe lives next to the refill, keeping mutation clustered.

### Release

The four methods that currently drop entries must route through a release helper:

```lua
local function releaseClassified(pool, entry)
    entry.aura = nil
    pool[#pool + 1] = entry
end
```

- `InvalidateHelpfulClassified(id)` / `InvalidateHarmfulClassified(id)`: if an entry existed, release it before nil-ing the table slot.
- `ResetHelpfulClassified()` / `ResetHarmfulClassified()`: iterate entries and release each before calling `wipe()` on the by-ID table.

### Scope

Per-`AuraState` instance. `F.AuraState.Create(owner)` initializes `self._classifiedFreeList = {}`. No module-level state, no cross-frame sharing.

### Growth bound

No explicit cap. Natural ceiling is bounded by game physics: ~40 auras/unit × ~25 frames ≈ 1000 entries × ~150 B ≈ ~150 KB absolute worst case across a session. Observability (below) will verify real growth stays well below this. If future measurement shows pathological retention, a hard cap (e.g., 64 per free list) can be added in ~5 lines.

### Observability

Two surfaces:

**Per-frame, on-demand** — extend `/framed aurastate [unit]` output to include:

```
  classified free list: <N> entries (<M> B est.)
```

**Aggregate** — add a weak-keyed instance registry:

```lua
F.AuraState._instances = setmetatable({}, { __mode = 'k' })

function F.AuraState.Create(owner)
    local inst = setmetatable({...}, AuraState)
    F.AuraState._instances[inst] = true
    return inst
end
```

`/framed memusage` iterates the registry and prints one aggregate line:

```
  aurastate free lists: <total> entries across <N> instances
```

The weak keys ensure that frames which get GC'd don't hold instances alive through the registry.

## Aliasing Risk and the Audit Gate

The guardrails below prevent `AuraState`'s internal state from leaking secret payload data, but they don't prevent a different class of bug: **a consumer that stashes an `entry` or `entry.flags` reference past an `Invalidate*Classified` call will observe silent reuse** (a stashed ref points at the same wrapper, which now holds a different aura's data after re-acquire). This is not a taint issue — it's a correctness issue (ghost auras, wrong-aura display).

The pool is correct only if no consumer stashes classified entries across UNIT_AURA. Therefore:

**Audit gate (Task 0 in the implementation plan):** before introducing the pool, audit every caller of `GetHelpfulClassified`, `GetHarmfulClassified`, and `GetClassifiedByInstanceID`:

- `Elements/Auras/Buffs.lua`
- `Elements/Auras/Debuffs.lua`
- `Elements/Auras/Externals.lua`
- `Elements/Auras/Defensives.lua`
- `Elements/Auras/Dispellable.lua`
- `Elements/Auras/PrivateAuras.lua`
- `Elements/Auras/MissingBuffs.lua`
- `Elements/Indicators/Icons.lua`
- `Elements/Indicators/Bars.lua`
- Any other grep hit on those three method names

Any consumer found to stash `entry` or `entry.flags` beyond the immediate iteration call stack must be fixed to extract the fields it needs inline before control returns. Pool merge is gated on audit pass.

## Implementation Guardrails

(Carried over verbatim from #144 with the aliasing addition.)

- All classified-entry acquire/release goes through dedicated helpers. No inline `{ aura = aura, flags = flags }` construction.
- `ResetHelpfulClassified`, `ResetHarmfulClassified`, `InvalidateHelpfulClassified`, and `InvalidateHarmfulClassified` release entries to the pool instead of just nil-ing them.
- `entry.aura` and `entry.flags` are fully cleared before reuse (wipe at acquire time).
- Pool is per-`AuraState` instance. Never promote to module scope.
- Pool wrappers hold `auraData` references, never copy secret payload fields into Framed-owned tables.
- Consumer audit must pass before merge (see above).

## Test Gate

Replay the 0.7.20 failure mode in a representative environment:

- 20-man raid pull with MPlusQOL, AbilityTimeline, and WeakAuras loaded
- No `attempt to compare number with nil` or nil text errors from external addons
- No ghost aura presentation when auras are added, updated, removed, or reassigned across units

Plus the new observability surfaces:

- `/framed aurastate target` during combat shows free list size climbing and plateauing, not growing unboundedly
- `/framed memusage` before and after several LFR pulls shows aggregate free list size bounded by natural ceiling

Plus a MemDiag A/B:

- Pre-change `/framed memdiag 30` in LFR
- Post-change `/framed memdiag 30` in comparable LFR
- Expected: `AuraState:*` rows (`ApplyUpdateInfo`, `GetHelpfulClassified`, `GetHarmfulClassified`, `GetClassifiedByInstanceID`) drop materially in per-call KB allocation
- `event:UNIT_AURA` bucket total (which nests AuraState) drops by a comparable amount
- Total `collectgarbage('count')` delta over the 30 s window drops toward the non-Framed baseline

Merge criteria: all three test gates pass, audit task in plan is checked off.

## References

- #144 — original scope definition
- #155 — measurement evidence + ranked fix list
- #159 — MemDiag tooling used for before/after measurement
- 0.7.20 incident: `7f21fb4` (pool introduction), `9d3cc54` (revert)
- `Core/AuraState.lua` — current implementation
