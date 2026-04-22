# AuraState FullRefresh Varargs-Pack Elimination Design

**Issue:** #155 (item 3 from ranked fix list)
**Related:** #144 / PR #160 (classified entry pool — established per-instance pooling pattern this reuses)
**Date:** 2026-04-22

## Goal

Eliminate per-`FullRefresh` varargs-pack allocation in `AuraState` by reusing per-instance scratch tables. This targets item 3 from the #155 ranked fix list (deferred from #144 to keep the classified-entry-pool PR's MemDiag attribution clean).

Baseline measurement (pre-#160 memdiag, 30 s LFR window): `AuraState:FullRefresh` allocated ~66 MB across the window — the single largest contributor to the UNIT_AURA bucket and the dominant source of Framed's share of the LFR memory yoyo. The two `{ GetAuraSlots(unit, 'HELPFUL') }` / `{ GetAuraSlots(unit, 'HARMFUL') }` varargs packs at `Core/AuraState.lua:244` and `:252` are the full cost — every FullRefresh call allocates and discards two tables holding the continuation token plus up to ~40 integer slot IDs.

## Non-Goals

Explicitly out of scope for this PR:

- **`Elements/Status/StatusText.lua:80` drink scan.** Uses the same `{ C_UnitAuras.GetAuraSlots(unit, 'HELPFUL') }` idiom, but is OOC-only (`InCombatLockdown()` guard). Cold path, separate issue. (User noted a suspicion it may still fire in combat under feign-death — flagged as a separate investigation.)
- **`Libs/oUF/elements/auras.lua` call sites.** Embedded oUF is off-limits per the `feedback_no_ouf_mods` convention — fixes must hoist to the Framed layer.
- **Item 2 from #155 — reducing `FullRefresh` call frequency.** Separate future PR. Bundling would muddy the before/after MemDiag attribution of this change.
- **Any new diagnostic command.** `/framed memdiag` and `/framed memusage` (already in place) produce the signal we need.

## Context

### What allocates today

`Core/AuraState.lua:244-258`:

```lua
local helpfulResults = { GetAuraSlots(unit, 'HELPFUL') }
for i = 2, #helpfulResults do
    local aura = GetAuraDataBySlot(unit, helpfulResults[i])
    if(aura and aura.auraInstanceID) then
        self._helpfulById[aura.auraInstanceID] = aura
    end
end

local harmfulResults = { GetAuraSlots(unit, 'HARMFUL') }
for i = 2, #harmfulResults do
    local aura = GetAuraDataBySlot(unit, harmfulResults[i])
    if(aura and aura.auraInstanceID) then
        self._harmfulById[aura.auraInstanceID] = aura
    end
end
```

The `{ ... }` varargs-pack idiom creates a fresh table per call. Two packs per `FullRefresh`, one per unit that fires UNIT_AURA; across 53 tracked units in a 20-man LFR pull this is the dominant allocation source.

### Why not a module-shared scratch table

The 0.7.20 classified-wrapper pool revert (`7f21fb4` → `9d3cc54`) failed specifically because module-level shared state served one frame's data to another frame's consumer mid-iteration. Applying the same mistake to the slots scratch would produce identical ghost-aura pathologies. Per-instance scratch is the correct pattern and matches the approach locked in by #144.

## Design

### Data — per-instance scratch fields

Add two fields to `F.AuraState.Create`, parallel to the `_classifiedFreeList` field added in #144:

```lua
_helpfulSlots = {},
_harmfulSlots = {},
```

Bounded size: ≤40 auras/unit × ~20 B/slot ≈ ~800 B per scratch × 2 × 53 instances ≈ ~85 KB peak retained. The tradeoff is ~85 KB of persistent memory in exchange for eliminating ~66 MB of allocation churn per 30 s window — three orders of magnitude. No growth bound needed; size is capped by game physics (aura count per unit).

### Helper — `fillSlots`

Module-local function in `Core/AuraState.lua`:

```lua
-- Pack GetAuraSlots varargs into `tbl` without allocating. Returns the count,
-- which callers use as the iteration bound (position 1 is the continuation
-- token; real slot IDs start at index 2).
local function fillSlots(tbl, ...)
    wipe(tbl)
    local n = select('#', ...)
    for i = 1, n do
        tbl[i] = select(i, ...)
    end
    return n
end
```

- The leading `wipe` is defensive: clears stale entries from a previous `FullRefresh` where the aura count was higher. Iteration uses the returned `n`, not `#tbl`, so the wipe is insurance against future code that might use length-operator ambiguity.
- `select(i, ...)` in a loop is formally O(N²) but N ≤ 40 → ≤1,600 internal operations → single-digit microseconds per call. Not worth optimizing.
- Returns count `n` so callers use it as the iteration bound.

### Call-site rewrite

In `AuraState:FullRefresh` (lines 244–258):

```lua
-- before
local helpfulResults = { GetAuraSlots(unit, 'HELPFUL') }
for i = 2, #helpfulResults do
    local aura = GetAuraDataBySlot(unit, helpfulResults[i])
    if(aura and aura.auraInstanceID) then
        self._helpfulById[aura.auraInstanceID] = aura
    end
end

-- after
local nHelpful = fillSlots(self._helpfulSlots, GetAuraSlots(unit, 'HELPFUL'))
for i = 2, nHelpful do
    local aura = GetAuraDataBySlot(unit, self._helpfulSlots[i])
    if(aura and aura.auraInstanceID) then
        self._helpfulById[aura.auraInstanceID] = aura
    end
end
```

Symmetric for `HARMFUL`. No behavioral change — same iteration bounds, same data flow, just no allocation.

### Scope

Per-`AuraState` instance. No module-level state, no cross-frame sharing. Matches the #144 pattern exactly.

### Observability

None added. The change is small, the measurement approach is already in place from #144, and an A/B on `AuraState:FullRefresh` bytes-per-call is the definitive signal. A `/framed scratch` equivalent command would report bounded per-instance sizes with no actionable meaning.

## Risk Analysis

**Re-entry.** `GetAuraSlots` and `GetAuraDataBySlot` are pure C getters with no Lua callbacks. `FullRefresh` cannot recursively call itself or another `FullRefresh` on the same instance during its execution. Per-instance scratch eliminates cross-instance re-entry concerns regardless — even if some future code path triggered re-entry on a *different* instance, each instance has its own scratch.

**Hole semantics.** The leading `wipe` before fill guarantees no stale indices. We iterate using the returned `n` (not `#tbl`), so Lua's length-operator ambiguity on tables with holes is irrelevant even without the wipe.

**Secret values.** `GetAuraSlots` returns integer slot IDs — non-secret. `GetAuraDataBySlot` is where secrets enter the system, and that call path is unchanged by this PR. No new secret-value handling required.

**Ghost-aura class of bug (from #144 audit gate).** Not applicable here. The scratch table holds integer slot IDs, not classified-wrapper references. Downstream consumers receive `auraData` (from `GetAuraDataBySlot`) directly and don't stash references to the scratch itself. The only way a stale slot ID could matter is if iteration read past `n`, which we explicitly bound.

## Test Gate

Parallels #144's validation approach:

- **MemDiag A/B.** Pre-change `/framed memdiag 30` in LFR; post-change `/framed memdiag 30` in comparable LFR. Expected: `AuraState:FullRefresh` bytes-per-call collapses from ~31 KB/call to near-zero; `event:UNIT_AURA` bucket total drops by a comparable amount; total `collectgarbage('count')` delta over the 30 s window drops materially toward the non-Framed baseline.
- **Ghost-aura stress.** Target-swap, let buffs expire, re-target — verify no stale aura state carried across refreshes. Scratch tables are overwritten every call plus defensively wiped, so this should be a no-op check.
- **Zero-aura unit.** Point target at a dummy with no auras, confirm no Lua errors. `select('#', ...) = 1` (just the continuation token), loop at `for i = 2, 1` runs zero times, wipe clears any residual.
- **Regression replay.** Reload with WeakAuras/MPlusQOL/AbilityTimeline loaded, combat entry/exit, target chains. Zero `BugSack` errors. No `attempt to compare number with nil` or nil-text errors from external addons.

Merge criteria: MemDiag A/B shows the expected collapse, zero regression errors across the replay, ghost-aura and zero-aura checks pass.

## References

- #155 — measurement evidence + ranked fix list
- #144 / PR #160 — classified entry pool (established per-instance pooling pattern, confirmed MemDiag methodology)
- #159 — MemDiag tooling
- 0.7.20 incident: `7f21fb4` (pool introduction), `9d3cc54` (revert)
- `Core/AuraState.lua` — current implementation
