# UNIT_AURA Fan-Out Rearchitecture Design Spec

**Date:** 2026-04-21
**Issue:** #115 (parent); #136 (A1), #137-#142 (B1-B6), #143 (C1)
**Status:** Approved

## Summary

Move per-aura classification work (external-defensive, important, player-cast, big-defensive) out of individual aura elements and into a shared AuraState classification layer. Each element migrates from making its own `C_UnitAuras.IsAuraFilteredOutByInstanceID` probes to reading pre-computed boolean flags off a wrapper entry. Shares the cost of classification across every consumer of the same `(unit, aura)` pair.

Today's aura elements fall into two classes:

- **Classification-heavy** (Externals, Defensives) — call `IsAuraFilteredOutByInstanceID` directly in their Update paths, up to 5 probes per aura per UNIT_AURA in Externals.
- **Spell-set-driven** (Buffs, Debuffs, MissingBuffs) — don't do classification themselves, but would benefit from pre-computed flags to simplify `castBy='me'` decisions and dispel-color handling.
- **Text/status** (StatusText) — registers its own UNIT_AURA handler for Drinking/Food detection; consolidation reduces total UNIT_AURA fan-out count.

After this rearchitecture: four probes per aura per classification write, shared across all elements on the same frame (via the existing per-frame `self.FramedAuraState` instance). Target: ≈50% reduction from baseline.

## Motivation

Framed's baseline profile (from combat telemetry in the `project_framed` memory):

- Framed: **0.448ms avg** per frame
- Cell: 0.231ms
- Dander: 0.075ms

The dominant cost in Framed is `IsAuraFilteredOutByInstanceID` chains in Externals (up to 5 probes per aura per UNIT_AURA) and Defensives, plus parallel work across elements on the same frame reading different filters of the same aura set. Existing caching addresses adjacent layers but not classification:

- `AuraCache` dedupes raw `GetUnitAuras` calls across elements (per-(unit, filter) generation-gated).
- `AuraState._helpfulMatches[filter][auraInstanceID]` memoizes filter-probe results per instance, per filter — but each filter is a separate cache, and the memoization is cleared on every aura change.

Neither layer materializes classification flags for the element to read cheaply. Elements still chain multiple probes per aura.

The fix: classify once on the shared per-frame AuraState, expose flags, let elements read them directly.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Classification timing | Write-path invalidate, read-path materialize (lazy) | First reader per generation pays classify cost; subsequent readers hit the cached wrapper; hidden frames / disabled elements pay zero |
| Ship scope (A1) | Helpful + harmful together | Catches cross-element collisions up front; avoids two migrations |
| Wrapper shape | `{ aura, flags }` per entry | `aura` stays a live ref; `flags` is a stable-shape boolean table |
| Tier structure | 2 tiers (passthrough + C probe) | Originally 3 tiers; revised to drop `AuraIsBigDefensive` in favor of probe |
| Update-path behavior | Always re-classify | Correctness > microperf at UNIT_AURA rate |
| B-series pacing | Per-element gate | Each element migrates independently; smoke test + merge between |
| B-series order | B6 → B1 → B2 → B4 → B5 → B3 | Simplest first (smoke); Buffs last (size + #113 retirement) |
| Buffs castBy model | `flags.isPlayerCast` exclusively | Retires #113 over-match workaround silently |
| Debug surface | `/framed aurastate <unit>` slash | Permanent shipping feature; matches `/framed events` / `/framed config` pattern |
| Flag-table pooling | Deferred (unpooled in A1) | Prior attempt caused cross-addon taint; conservative retry is a separate issue |
| Spec structure | Single comprehensive spec | A1 + B1-B6 + C1 share enough design surface to document once |

## Prior Work and Dependencies

### #123 (aura instance ID re-randomization) is stale

Parent issue #115 is tagged as blocked by #123 ("verify 12.0.5 aura instance ID re-randomization handling"). Investigation during brainstorming confirmed #123's code-side fix is already implemented: `Core/AuraCache.lua:73-79` bumps the generation counter for every tracked unit on `ENCOUNTER_START` and `ENCOUNTER_END`. The comment at that site explicitly documents the 12.0.5 re-randomization behavior.

What remains for #123 is live verification on a real boss encounter, not code work. Since A1 shares the same invalidation surface (generation bump → classified store invalidation), A1 will inherently exercise the ENCOUNTER_START path during A1's own smoke-testing phase.

**Action before A1 starts:** downgrade #123's "blocker" tag. Either close with comment "code-side implemented at AuraCache.lua:73-79; live verification will happen during A1 smoke-testing", or keep open but remove the `blocks #136` relationship.

### Dander Frames inspiration (no code copied)

Dander's low CPU footprint (0.075ms) is observed to come from classification sharing. The architectural pattern is public behavior visible via profiler + code reading; no code is copied. Dander is ARR-licensed and off-limits for direct reference per `feedback_licensing_references`. This spec independently derives the classification layer from Framed's existing AuraCache + AuraState infrastructure.

## Architecture

### The structural shift

AuraState is a per-frame class (`Core/AuraState.lua`), created idempotently by the first element on each frame to run Setup:

```lua
if(not self.FramedAuraState and F.AuraState) then
    self.FramedAuraState = F.AuraState.Create(self)
end
```

All elements on the same frame share that one instance. A1 extends this shared instance with a classification layer.

**Before:**

```
UNIT_AURA -> Externals.Update
            -> for each helpful aura:
                 probe EXTERNAL_DEFENSIVE, IMPORTANT, BIG_DEFENSIVE, RAID, PLAYER (up to 5 probes)
          -> Defensives.Update
            -> for each helpful aura:
                 probe BIG_DEFENSIVE, PLAYER (2 probes)
          -> Debuffs.Update, MissingBuffs.Update, ...
            -> spellID-based work
```

**After:**

```
UNIT_AURA -> shared AuraState classifies each aura once
              probe EXTERNAL_DEFENSIVE, IMPORTANT, PLAYER, BIG_DEFENSIVE (4 probes)
          -> Externals.Update
            -> for each classified entry: read entry.flags.*  (free lookups)
          -> Defensives.Update
            -> for each classified entry: read entry.flags.*  (free lookups)
          -> Debuffs, MissingBuffs, ... -> read flags where useful
```

### Post-A1 store shape

Two new per-instance dictionaries on `AuraState`, parallel to the existing `self._helpfulById` / `self._harmfulById`:

```lua
self._helpfulClassifiedById[instanceID] = {
    aura  = <AuraData ref>,   -- never copied, never mutated
    flags = {                 -- always all 9 keys, always boolean
        isHelpful           = bool,
        isHarmful           = bool,
        isRaid              = bool,
        isBossAura          = bool,
        isFromPlayerOrPet   = bool,
        isExternalDefensive = bool,
        isImportant         = bool,
        isPlayerCast        = bool,
        isBigDefensive      = bool,
    },
}
```

`isBigDefensive` is always `false` for harmful auras (the `HELPFUL|BIG_DEFENSIVE` filter has no harmful analog). The flag is present on every wrapper for shape stability.

Existing `self._helpfulById` / `self._harmfulById` stores stay untouched during the migration. Each B-issue migrates one element's read path; writes to both stores happen in parallel. After B6 ships, a follow-up collapses the two stores.

### Flag lifecycle tiers

| Tier | Flags | Source | Secret-safe |
|------|-------|--------|-------------|
| 1 (passthrough) | `isHelpful`, `isHarmful`, `isRaid`, `isBossAura`, `isFromPlayerOrPet` | `AuraData` structural booleans | Always |
| 2 (C probe) | `isExternalDefensive`, `isImportant`, `isPlayerCast`, `isBigDefensive` | `C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, id, filter)` | Always (C-level API) |

**Originally proposed a third tier** (spellID-keyed cache for `isBigDefensive` via `C_UnitAuras.AuraIsBigDefensive`). Dropped because (a) `spellId` is typically secret in combat, and `AuraIsBigDefensive` is not documented to accept secret scalars; (b) the probe alternative is already proven by current Externals.lua. Two tiers keeps single-path and avoids feature-detection branching.

### Filter strings used

All four are present in `/tmp/wow-ui-source/Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua:158-174` and used by Framed today:

- `HELPFUL|EXTERNAL_DEFENSIVE` → `flags.isExternalDefensive`
- `HELPFUL|IMPORTANT` / `HARMFUL|IMPORTANT` → `flags.isImportant`
- `HELPFUL|PLAYER` / `HARMFUL|PLAYER` → `flags.isPlayerCast`
- `HELPFUL|BIG_DEFENSIVE` → `flags.isBigDefensive` (helpful only — no harmful variant applies)

### Integration with existing invalidation

AuraCache's generation counter is the single invalidation signal. A1 introduces zero new event registrations. Every invalidation path that works today for `GetHelpful` / `GetHarmful` works identically for the classified APIs:

- UNIT_AURA: generation bumps on affected unit.
- Unit token reassignment (PLAYER_TARGET_CHANGED, PLAYER_FOCUS_CHANGED, UNIT_TARGET, GROUP_ROSTER_UPDATE, ARENA_OPPONENT_UPDATE, INSTANCE_ENCOUNTER_ENGAGE_UNIT, NAME_PLATE_UNIT_ADDED/REMOVED): generation bumps on the token.
- ENCOUNTER_START / ENCOUNTER_END (12.0.5 ID re-randomization): generation bumps on every tracked unit.

AuraState's existing `ensureFresh(unit)` gate catches all three categories.

### Non-goals for A1

- No pooling of `flags` tables. (Deferred issue.)
- No collapse of `_helpfulById` + `_helpfulClassifiedById`. (Follow-up after B6.)
- No removal of `_helpfulMatches` filter memoization — some filters (e.g., `RAID_IN_COMBAT`) stay in use via `GetHelpful(filter)` post-B6.
- No changes to existing `GetHelpful(filter)` / `GetHarmful(filter)` shape or behavior.
- No mutation of `AuraData` references.
- No new event registrations.

## Components and APIs

### Public API additions — AuraState instance methods

Match the existing `GetHelpful(filter)` / `GetHarmful(filter)` method shape (colon-call, no unit parameter — unit is stored on the instance):

```lua
--- Array of wrapper entries for all helpful auras on the instance's unit.
--- @return table   -- array of { aura, flags }
function AuraState:GetHelpfulClassified() end

--- Array of wrapper entries for all harmful auras on the instance's unit.
--- @return table   -- array of { aura, flags }
function AuraState:GetHarmfulClassified() end

--- Wrapper entry for a single aura instance ID, or nil.
--- Useful for elements handling UNIT_AURA delta payloads directly.
--- @param instanceID number
--- @return table|nil   -- { aura, flags } or nil
function AuraState:GetClassifiedByInstanceID(instanceID) end
```

All three run through the existing `EnsureInitialized(self._unit)` generation gate — same semantics as `GetHelpful` / `GetHarmful`.

`GetClassifiedByInstanceID` is the single-entry accessor for elements that hold a spellID-to-instanceID map or process `updateInfo.updatedAuraInstanceIDs` payloads directly. **Primary planned consumer: B3 Buffs (#139)** per-indicator resolution path — the migrated Buffs element resolves indicator-tracked spells to their current wrapper entry in O(1) rather than scanning the full classified array. **B6 StatusText (#142)** is a secondary candidate if its migrated Drinking/Food detection switches from array-scan to delta-payload processing. The API ships in A1 so B-series wiring exists when those migrations land; final call sites are fixed at B-series issue refinement.

Unlike `GetHelpful(filter)` which takes a filter string, the classified APIs return all helpful/harmful auras with flags populated. Filter-like narrowing is done by the caller via flag reads: `if(entry.flags.isExternalDefensive)`.

### Internal state

Added to the `AuraState` instance table in `F.AuraState.Create`:

```lua
self._helpfulClassifiedById = {}    -- [instanceID] = entry
self._harmfulClassifiedById = {}    -- [instanceID] = entry
self._helpfulClassifiedView = { dirty = true, list = {} }
self._harmfulClassifiedView = { dirty = true, list = {} }
```

The `{ dirty, list }` view shape mirrors the existing `_helpfulViews[filter]` / `_harmfulViews[filter]` pattern in AuraState.lua:78-109 — rebuild-on-read with a dirty flag toggled on write. Classified has no filter dimension, so it's a single view instead of a per-filter table.

### Classification function

Module-local helper in `Core/AuraState.lua`, called from the instance's `GetHelpfulClassified` / `GetHarmfulClassified` view-rebuild path:

```lua
local function classify(unit, aura, isHelpful)
    local id = aura.auraInstanceID
    local prefix = isHelpful and 'HELPFUL' or 'HARMFUL'

    -- Tier 1: structural passthrough (always safe, never secret)
    local flags = {
        isHelpful         = aura.isHelpful or false,
        isHarmful         = aura.isHarmful or false,
        isRaid            = aura.isRaid or false,
        isBossAura        = aura.isBossAura or false,
        isFromPlayerOrPet = aura.isFromPlayerOrPlayerPet or false,
    }

    -- Tier 2: instance-ID filter probes.
    -- NOTE: explicit `== false` (not `not ...`). IsAuraFilteredOutByInstanceID
    -- returns nil for invalid state; `not nil == true` would promote every aura.
    flags.isExternalDefensive = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|EXTERNAL_DEFENSIVE') == false
    flags.isImportant         = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|IMPORTANT')          == false
    flags.isPlayerCast        = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|PLAYER')             == false
    flags.isBigDefensive      = isHelpful
                                and IsAuraFilteredOutByInstanceID(unit, id, 'HELPFUL|BIG_DEFENSIVE') == false
                                or false

    return { aura = aura, flags = flags }
end
```

The existing `IsAuraFilteredOutByInstanceID` local at AuraState.lua:9 is reused — no re-capture.

`classify()` is called exclusively from the view-rebuild path (`GetHelpfulClassified` / `GetHarmfulClassified`). It is never invoked from `FullRefresh` or `ApplyUpdateInfo` — those only nil invalidated entries and mark views dirty. This keeps the write path cheap and defers classify cost to first-reader-per-generation.

### Element consumption pattern (post-migration)

```lua
-- Before (today, Externals.lua:42):
local rawAuras = auraState and auraState:GetHelpful('HELPFUL')
    or F.AuraCache.GetUnitAuras(unit, 'HELPFUL')
for _, aura in next, rawAuras do
    local isExt = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
        unit, aura.auraInstanceID, 'HELPFUL|EXTERNAL_DEFENSIVE')
    if(isExt) then
        ...
    end
end

-- After (B1 migration):
local classified = auraState and auraState:GetHelpfulClassified() or nil
if(classified) then
    for _, entry in next, classified do
        if(entry.flags.isExternalDefensive) then
            local aura = entry.aura
            ...
        end
    end
end
```

Per-aura C API probe count for Externals: **up to 5 → 0**. All five filter probes (EXTERNAL_DEFENSIVE, IMPORTANT, BIG_DEFENSIVE, RAID, PLAYER) at Externals.lua:51/59/62/76/79/97 become flag reads; the cost moves into the shared `classify()` step, which runs once per aura per generation on the per-frame AuraState instance.

Elements without a shared AuraState (e.g., a theoretical frame with zero aura elements) would fall back to `F.AuraCache.GetUnitAuras` exactly like today. Since every aura-tracking frame has at least one element that creates AuraState via the idempotent Setup guard, the `classified = nil` branch is vestigial — preserved only to match the existing element-level `auraState and ... or fallback` pattern.

### Debug slash: `/framed aurastate <unit>`

New case in the existing `/framed` dispatcher in `Init.lua`. Unit defaults to `target` if omitted.

Output format:

```
AuraState: target  (gen 47)
  HELPFUL (3):
    [4521]  Rallying Cry          [player-cast, raid]
    [4877]  Pain Suppression      [external-defensive, important]
    [4921]  Ironbark              [external-defensive, big-defensive]
  HARMFUL (2):
    [5102]  Fel Flame             [boss, important]
    [5144]  (secret)              [dispel: magic]
```

- Columns: `[instanceID]  <name or "(secret)">  [comma-separated active flags]`
- Flag names use kebab-case slugs matching the camelCase key (`isExternalDefensive` → `external-defensive`).
- Appends `[dispel: <name>]` when `entry.aura.dispelName` is non-nil.
- Permanent shipping feature. Low enough cost to run in live combat.

### Wrapper entry invariants

- `entry.aura` is always a non-nil `AuraData` reference.
- `entry.flags` is always a non-nil table with **all 9 flag keys present and boolean**.
- Consumers may rely on `if(entry.flags.isX) then` without defensive nil-checks.
- Array order from `GetHelpfulClassified` / `GetHarmfulClassified` is **undefined** — underlying store is a hash keyed by `auraInstanceID`, iterated with `next`. Matches existing `GetHelpful` / `GetHarmful` semantics. Callers that need stable render order must sort after fetch.

If classification produces a wrapper entry violating these invariants, that's an AuraState bug — not something elements paper over.

## Data Flow and Lifecycle

### UNIT_AURA write path

Every aura mutation event flows through `AuraState:FullRefresh(unit)` or `AuraState:ApplyUpdateInfo(unit, updateInfo)`. A1 adds classified-store invalidation alongside the existing filter-match invalidation:

| Trigger | Existing behavior | New classified store behavior |
|---------|-------------------|-------------------------------|
| `FullRefresh` | Wipes `self._helpfulById` + repopulates; `ResetHelpfulMatches` | Wipes `self._helpfulClassifiedById`; marks `_helpfulClassifiedView` dirty |
| Added aura | Inserts into `self._helpfulById[id]`; `InvalidateHelpfulMatch(id)` | `self._helpfulClassifiedById[id] = nil` (force re-classify on next read); marks view dirty |
| Updated aura | Replaces entry in `self._helpfulById[id]`; `InvalidateHelpfulMatch(id)` | `self._helpfulClassifiedById[id] = nil`; marks view dirty |
| Removed aura | `nil`s entry in `self._helpfulById[id]`; `InvalidateHelpfulMatch(id)` | `nil`s entry in `self._helpfulClassifiedById[id]`; marks view dirty |

Classification is populated lazily on first `GetHelpfulClassified()` read per generation. The view-rebuild walks `self._helpfulById`, reuses any still-valid entries in `self._helpfulClassifiedById`, and calls `classify()` for entries that are missing or invalidated.

**Helpful and harmful are symmetric.** Everything above applies identically to the harmful side via `_harmfulById` / `_harmfulClassifiedById` / `_harmfulClassifiedView`.

New instance methods for consistency with the existing invalidation methods:

- `AuraState:InvalidateHelpfulClassified(auraInstanceID)` — removes ID from `_helpfulClassifiedById`, marks classified view dirty.
- `AuraState:InvalidateHarmfulClassified(auraInstanceID)` — parallel for harmful.
- `AuraState:MarkHelpfulClassifiedDirty()` / `AuraState:MarkHarmfulClassifiedDirty()` — mirror the existing `MarkHelpfulDirty` / `MarkHarmfulDirty` pattern.

Called from the same points as `InvalidateHelpfulMatch` / `InvalidateHarmfulMatch` (AuraState.lua:189, 205, 209, 215, 219, 229, 234).

### Update-path re-classification rationale

Update events (`updateInfo.updatedAuraInstanceIDs`) invalidate the classified entry for each affected ID and let the next read re-classify. No in-place delta-check on which flag might have flipped. Three reasons:

1. An aura can change category mid-life as the game propagates classifications asynchronously.
2. UNIT_AURA fires at human-reaction frequency, not render frequency. Four C probes per updated aura is cheap.
3. Invalidation is a single code path symmetric with the existing `InvalidateHelpfulMatch` pattern. Delta-checking introduces branches that would need testing in edge cases.

Cold start and re-classification pay for a full aura only on first read of that generation. If no element calls `GetHelpfulClassified()` in a given generation (e.g., frame hidden, all aura elements disabled), classify runs zero times for that generation — lazy materialization is a net win over eager write-path population.

### Encounter boundaries

`ENCOUNTER_START` / `ENCOUNTER_END` bump every tracked unit's generation via the existing AuraCache handler. The next read of any classified API sees generation mismatch → `FullRefresh` → fresh scan with post-randomization instanceIDs → new `classify` calls → correct flags.

### Cold start

First-ever `GetHelpfulClassified()` call on a fresh AuraState instance:

1. `AuraCache.GetGeneration(self._unit)` → 0 (never bumped for this unit).
2. `EnsureInitialized(self._unit)` at AuraState.lua:151 sees `self._initialized == false` → runs `FullRefresh`.
3. `FullRefresh` populates `self._helpfulById` and marks classified view dirty (new behavior).
4. View-rebuild walks `self._helpfulById`, calls `classify()` for each aura, populates `self._helpfulClassifiedById` + `_helpfulClassifiedView.list`.
5. Returns populated list.

No cold-start branch leaks to callers.

### Lifecycle diagram

```
   UNIT_AURA event
        |
        v
   AuraCache.bump(unit)                           <-- existing
        |  generation[unit]++
        v
   oUF dispatches to elements' Update
        |
        v
   AuraState:ApplyUpdateInfo(unit, updateInfo)    <-- existing + new branches
     -> update self._helpfulById / _harmfulById   <-- existing
     -> nil classified entries for changed IDs    <-- new
     -> mark classified views dirty               <-- new
        |
        v
   [element calls auraState:GetHelpfulClassified()]
        |
        v
   view.dirty?
       |          \
       no          yes
       |            \
       v             v
   return list   walk self._helpfulById:
                   for each aura:
                     cached = self._helpfulClassifiedById[id]
                     if not cached: classify()       <-- 4x probes, cache result
                     append to view.list
                   view.dirty = false
                   return view.list
```

## Error Handling and Secret-Value Interactions

### Secret-value invariants

A1 is single-path. The same `classify()` runs for every aura regardless of which fields are secret. No `F.IsValueNonSecret()` branches anywhere in the classification layer.

Why this works cleanly:

- **Tier 1 passthrough:** structural booleans on `AuraData` (`isHelpful`, `isHarmful`, `isRaid`, `isBossAura`, `isFromPlayerOrPlayerPet`) are never secret, regardless of whether other fields on the same AuraData are secret.
- **Tier 2 probes:** `IsAuraFilteredOutByInstanceID` is explicitly secret-safe per the CLAUDE.md "Secret Values" section.
- **`entry.aura`** is a live ref — it carries whatever secret-ness the aura has. Downstream consumers handle via existing `F.IsValueNonSecret()` + secret-safe C-level rendering, exactly as they do today against raw `GetHelpful` results.

The classification layer sits strictly upstream of any secret-value read. The "never split secret/non-secret paths" CLAUDE.md rule is upheld.

### C API return normalization

`IsAuraFilteredOutByInstanceID(unit, id, filter)` returns:

- `true` → aura does NOT match the filter.
- `false` → aura matches the filter.
- `nil` → invalid unit, unknown instanceID, or unrecognized filter.

Every Tier 2 flag uses `filtered == false` normalization:

```lua
flags.isExternalDefensive = C_UnitAuras.IsAuraFilteredOutByInstanceID(...) == false
```

**Not `not filtered`.** Since `not nil == true`, the naive form would silently promote every aura to match every filter. This is the single most important implementation detail in A1. An inline comment at the probe call site calls out this distinction.

### Stale-ID degradation

If an element retains an `entry` across a generation bump (shouldn't happen — contract is "re-fetch every frame"):

- `entry.aura` is still a live table; fields still read cleanly.
- `entry.flags` still holds booleans — stale but doesn't throw.
- Likely the aura has been removed; `entry.aura.expirationTime` reads as past → element's existing expiration handling hides it.

A1 does not add new defensive code for this. The contract matches existing `GetHelpful`: call fresh every UNIT_AURA.

### Invalid or compound unit tokens

For an AuraState instance on a frame whose unit is `raid50` in a 5-man, or a compound token like `party2target` (rejected by `C_UnitAuras.GetAuraSlots`):

- `isCompoundUnit(unit)` guard at AuraState.lua:14 short-circuits `FullRefresh` for compound tokens — empty stores returned.
- For invalid-but-simple tokens like `raid50`, `GetAuraSlots` returns empty results — empty stores.
- Either way, `GetHelpfulClassified()` returns an empty list. No error, no warning.

Identical to existing `GetHelpful('HELPFUL')` behavior for the same tokens.

### No pcall

Per CLAUDE.md "No pcall" rule, zero pcall in the classification layer. If a C API call throws, that's a Blizzard bug worth surfacing. No feature-detection guards for the four filter strings in scope — all four are present on live.

### Flag-table GC pressure

Unpooled in A1. Churn is ~2-4 KB/sec during active combat (~120 tables/min at steady state). Tolerable; visible on profile graphs but not catastrophic. Pooling deferred as a follow-up issue — prior attempt caused cross-addon taint (`feedback_table_pooling` memory), so a conservative retry design is out of scope here.

## Testing Strategy

### Philosophy

Framed has no automated test harness; verification is live in-game. This matches all comparable WoW addons and is the standard per `feedback_coding_standards`. The per-element gate from the B-series is the test harness — each migration isolates its own regression surface.

### A1 (#136) acceptance

A1 does not change element behavior. Verification is correctness of classification + absence of regression in existing elements.

**Correctness checklist (via `/framed aurastate <unit>`):**

Each scenario below must also cross-check against the current element behavior — e.g., an aura marked `isExternalDefensive=true` by the new classifier must also be shown by the pre-A1 `Externals` element when that aura is on-screen. This cross-check is what confirms the classification matches what elements expect.

| Scenario | Expected flags |
|----------|----------------|
| Empty unit | Empty lists, gen ≥ 1 |
| Power Word: Shield cast on you (any source) | `isExternalDefensive=true`, `isImportant=true` |
| Power Word: Shield cast by you on yourself | Above + `isPlayerCast=true` |
| Ironbark cast on you | `isExternalDefensive=true`, `isBigDefensive=true`, `isFromPlayerOrPet=true` (if druid is in party) |
| Blessing of Protection cast on you by another paladin | `isExternalDefensive=true`, `isImportant=true`, `isPlayerCast=false` |
| Self-cast Devotion Aura | `isHelpful=true`, `isRaid=true`, `isPlayerCast=true` |
| Boss DoT on you | `isHarmful=true`, `isBossAura=true` |
| Dispellable magic debuff (from arena opponent) | `isHarmful=true`, `isImportant=true`, `entry.aura.dispelName == 'Magic'` |
| `/reload` during combat | Same classifications as pre-reload; gen restarts at 0 for the instance, first read classifies fresh |

**Non-regression checklist:**

- Every existing element renders identically (Externals, Defensives, Buffs, Debuffs, MissingBuffs, StatusText).
- `/framed events` shows UNIT_AURA registered, no duplicates.
- No Lua errors during a 10-minute target-dummy + 5-man heroic session.
- Profiler: `F.AuraState` per-frame cost delta < 5% over baseline. If higher, investigate `classify()` hot spots but not a hard block (B-series gains dwarf A1 overhead).

**Encounter boundary verification:**

Enter a raid boss encounter mid-auras. On `ENCOUNTER_START`, generation bumps (existing behavior at AuraCache.lua:73-79). Next `/framed aurastate <unit>` call shows re-classified state with fresh instanceIDs and no stale flags.

### B-series acceptance (generic template)

Each of #137-#142 follows:

1. **Pre-migration snapshot.** Screenshot the element in 3-4 representative scenarios.
2. **Migrate** to read `entry.flags.*` or the classified slice instead of element-side probes / separate `GetHelpful(filter)` calls.
3. **Post-migration smoke.** Same scenarios, same screenshots. Diff visually.
4. **Error capture.** No new Lua errors in 10-minute combat session.
5. **Profiler snapshot.** Element's per-frame cost drops (big drop for #137/B1 and #138/B2; incidental-to-zero for others).
6. **Commit + push to `working-testing`.** Merge to main after 24-48h live use without reports.

**Per-element scope summary (from each issue body):**

| Issue | Element | Migration focus | Must-test scenarios |
|-------|---------|-----------------|---------------------|
| #142 B6 (first) | `Elements/Status/StatusText.lua` | Event-handler consolidation: consume classified helpful slice for Drinking/Food detection | Drinking food buff appears with correct text/color/timer; no regression in summon-pending, disconnect, AFK, dead, ghost states |
| #137 B1 | `Elements/Auras/Externals.lua` | Replace 5-probe classification chain with flag reads | Self PWS; external Ironbark; external BoP; IMPORTANT-only non-defensive helpful (still appears); RAID fallback for secret-spellID auras in combat (still hides Rejuvenation out of combat) |
| #138 B2 | `Elements/Auras/Defensives.lua` | Single BIG_DEFENSIVE probe becomes `flags.isBigDefensive` read | Self Divine Shield; Ice Block; Cooldown Aggressive; player-cast border color distinction preserved |
| #140 B4 | `Elements/Auras/Debuffs.lua` | Consume classified harmful slice (A1 already includes harmful per Q1) | Dispel-type colorization; boss/role debuff priority; `castBy` filter for harmful |
| #141 B5 | `Elements/Auras/MissingBuffs.lua` | Consistency migration (spellID-driven, no classification needed) | Missing raid buff surfaces; cast it + confirm it clears |
| #139 B3 (last) | `Elements/Auras/Buffs.lua` | `castBy='me'` uses `flags.isPlayerCast` (retires #113 over-match fallback); preserve `computeBuffFilter` and per-indicator spellID lookups | `castBy='me'` / `'others'` / `'all'` in combat + out of combat, with indicators with/without spell lists; no regression on border colors, stacks, ordering |

### B3 Buffs: #113 retirement

Brainstorming decision: B3 uses `flags.isPlayerCast` (populated by the `HELPFUL|PLAYER` probe — per AuraUtil.lua:158-174, "combine with Player & Helpful to return self-cast HoTs") for `castBy` discrimination. This is a definitive C-API answer and simpler than the #139 issue description's two-branch (`sourceUnit` non-secret → use `sourceUnit`; secret → fall back to `isFromPlayerOrPet`) approach.

- **Today (with #113):** if `sourceUnit` is secret, the fallback treats the aura as cast-by-self when user configured `castBy='me'`. World buffs like Rallying Cry occasionally show in the wrong slot during combat.
- **After B3:** `isPlayerCast` is a definitive answer regardless of sourceUnit secrecy. Rallying Cry you didn't cast classifies as `isPlayerCast=false`. `castBy='me'` shows only genuinely player-cast auras.

**Action when B3 is planned:** update issue #139's "Preserve exactly" list to reflect `isPlayerCast` as the castBy mechanism; the two-branch fallback is superseded by this spec.

Preserved from the original #139 scope (unchanged):

- `computeBuffFilter` at Buffs.lua:71 — widens to `HELPFUL` when any indicator has a spell list, else `HELPFUL|RAID_IN_COMBAT`. This is an orthogonal filter for input scoping, not a castBy decision.
- Per-indicator spell list matching — spellID-driven, independent of classification.

No CHANGELOG call-out for the behavior change. Single-user audience, no migration friction.

### C1 (#143) benchmark + visual regression

C1 is the closing verification pass. Deliverable: a documented report (no code changes).

**Protocol:**

1. **Three profiler snapshots under identical conditions:**
   - S0: pre-A1 baseline (from memory: 0.448ms avg).
   - S1: post-A1, pre-B-series (classification writing, no element reading flags yet).
   - S2: post-B6 (all elements migrated).
2. **Three scenarios, 60 seconds each:**
   - Target dummy solo (minimal churn).
   - 5-man M+ dungeon (moderate churn).
   - Raid boss encounter (peak churn).
   - **Reproducibility:** specific dungeon/boss/affix combos are named in the C1 GitHub issue body at execution time and reused verbatim across S0/S1/S2. Comparing 0.448ms on one boss to 0.22ms on a different boss is noise, not signal.
3. **Metrics per snapshot per scenario:**
   - `GetAddOnCPUUsage('Framed')` delta over window.
   - UNIT_AURA handler cost per event (profiler or `debugprofilestop`).
   - GC pressure (`collectgarbage('count')` delta over window).
4. **Visual regression set:** screenshots of 8-12 representative element states, pre-A1 vs post-B6. Archived in the C1 GitHub issue as attachments.

**Success bar:**

- **S2 ≤ 0.22ms (≈50% reduction from S0 0.448ms baseline)** on the raid scenario.
- Measurable improvement on M+ scenario.
- Target dummy may be flat — classification has fixed overhead, low-churn case is the weakest for a sharing optimization.
- No visual regression in any screenshot pair.

Cell (0.231ms) and Dander (0.075ms) are context only, not gates. Closing the gap toward Dander is aspirational future work.

### Rollback strategy

Each B-issue is its own commit behind main, enabling single-commit revert without touching siblings:

1. `git revert` the B-issue's commit.
2. A1 + other B-issues stay in place; reverted element falls back to its pre-migration path against the legacy `_helpfulById` / `_harmfulById` stores.
3. Patch-level version bump per `feedback_release_workflow`.

A1 itself is rollback-safe: new APIs + debug slash only. Reverting A1 is a non-event unless a B-issue already consumes it, which the per-element gate should prevent.

**Mid-migration stability invariant.** Migrated and unmigrated elements coexist on the same AuraState instance without interference. Legacy stores (`_helpfulById`, `_harmfulById`, `_helpfulMatches`, `_harmfulMatches`) remain populated throughout and after the B-series. Unmigrated elements continue reading via `GetHelpful(filter)` / `GetHarmful(filter)`; migrated elements read via classified APIs. Both paths see identical underlying `AuraData` references and the same UNIT_AURA invalidations via the generation-bump mechanism. The B-series can pause at any element boundary without destabilizing the addon.

### Explicitly deferred

- Automated Lua unit tests (no harness exists today).
- CI integration (`auto-tag.yml` + `release.yml` unchanged).
- Visual regression automation (screenshot diffing is research scope).
- Cross-locale testing (only English verified; other locales use same code path).

## Dependencies and Sequencing

### Issue graph

```
[#123 stale --> close]

A1 (#136 AuraState classify)
  |
  v
B6 (#142 StatusText) [smoke-test migration]
  |
  v
B1 (#137 Externals)
  |
  v
B2 (#138 Defensives)
  |
  v
B4 (#140 Debuffs)
  |
  v
B5 (#141 MissingBuffs)
  |
  v
B3 (#139 Buffs) [#113 retirement]
  |
  v
C1 (#143 Benchmark + VR)
```

### Locked execution order

1. **Pre-work:** Close #123 as already-implemented.
2. **A1 #136** — AuraState classification + debug slash.
3. **B6 #142** — StatusText (smallest element; validates `entry.flags.*` pattern).
4. **B1 #137** — Externals (highest C-API savings).
5. **B2 #138** — Defensives (shares logic with Externals).
6. **B4 #140** — Debuffs (independent of healing-oriented elements).
7. **B5 #141** — MissingBuffs (complements Buffs, lighter).
8. **B3 #139** — Buffs (largest; widest user-visible surface; #113 retirement).
9. **C1 #143** — Benchmark + visual regression.

### Branch and release discipline

- All work on `working-testing` per `project_framed_worktree`.
- Each issue = one PR from `working-testing` → `main`.
- Commit + push after every task per `feedback_commit_after_task`.
- Patch-level bump (0.x.Y) per `feedback_versioning`.
- Version bump commit touches only TOC + CHANGELOG + About card per `feedback_release_workflow`.
- Display name "Moodibs" per `feedback_author_name`.

### Post-C1 follow-ups (out of scope)

File as new GitHub issues when A1 ships:

- **Flag-table pooling revisit** — conservative retry with bool-typed, wipe-on-release, internal-only pool.
- **Store consolidation** — collapse `_helpfulById` + `_helpfulClassifiedById` into single classified store. Requires verifying no remaining caller needs raw AuraData without the flag wrapper.
- **Partial `_helpfulMatches` cleanup** — the four filters that move to flags (`EXTERNAL_DEFENSIVE`, `IMPORTANT`, `PLAYER`, `BIG_DEFENSIVE`) can be stripped from the per-filter memoization path. Filters that stay in use post-B6 (e.g., `RAID_IN_COMBAT` for Buffs' `computeBuffFilter`, `RAID` for Debuffs' raid-filtered path) keep their memoization.
- **Cache coverage gap analysis** — document structural reasons Framed can't easily match Dander's 0.075ms.

## Files Touched

### A1 (#136)

- `Core/AuraState.lua`:
  - Module-local `classify(unit, aura, isHelpful)` helper.
  - Per-instance state additions in `F.AuraState.Create` (`_helpfulClassifiedById`, `_harmfulClassifiedById`, `_helpfulClassifiedView`, `_harmfulClassifiedView`).
  - New instance methods: `GetHelpfulClassified`, `GetHarmfulClassified`, `GetClassifiedByInstanceID`.
  - New invalidation methods: `InvalidateHelpfulClassified`, `InvalidateHarmfulClassified`, `MarkHelpfulClassifiedDirty`, `MarkHarmfulClassifiedDirty`.
  - Write-path additions in `FullRefresh`, `ApplyUpdateInfo` (wipe classified store / invalidate per-ID entries alongside existing filter-match invalidation).
- `Init.lua` — new `/framed aurastate` case in slash dispatcher.

### B-series (#137 - #142)

Each migrates one element's read path:

- `Elements/Status/StatusText.lua` (B6 #142) — event-handler consolidation
- `Elements/Auras/Externals.lua` (B1 #137) — probe chain → flag reads
- `Elements/Auras/Defensives.lua` (B2 #138) — single-probe → flag read
- `Elements/Auras/Debuffs.lua` (B4 #140) — consume classified harmful slice
- `Elements/Auras/MissingBuffs.lua` (B5 #141) — consistency migration
- `Elements/Auras/Buffs.lua` (B3 #139) — castBy via `isPlayerCast`

### C1 (#143)

No code changes. Report attached to the GitHub issue.

## References

- Parent issue: #115
- Sub-issues: #136, #137, #138, #139, #140, #141, #142, #143
- Stale dependency to close: #123
- Prior art in-repo: `Core/AuraCache.lua` (Aura Cache Design spec, 2026-04-10), `Core/AuraState.lua`
- Source of truth for filter strings: `/tmp/wow-ui-source/Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua:158-174`
- Source of truth for AuraData fields: `/tmp/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua`
