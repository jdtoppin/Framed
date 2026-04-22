# Classified Entry Pool Implementation Plan (#144)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate per-update allocation of classified `{ aura, flags }` wrappers in `Core/AuraState.lua` via a taint-safe, per-instance paired free list.

**Architecture:** Single shared paired pool per `AuraState` instance. Dedicated `acquireClassified` / `releaseClassified` helpers are the only acquire/release paths. Flags table identity stays attached to its wrapper; wipe happens at acquire (lazy). Helpful and harmful entries share one pool. Weak-keyed `F.AuraState._instances` registry enables aggregate observability.

**Tech Stack:** WoW 12.0.x Lua, embedded oUF, Framed AuraState.

**Spec:** `docs/superpowers/specs/2026-04-22-classified-entry-pool-design.md`

**Divergence from spec:** Spec proposed extending `/framed aurastate [unit]` with a pool-size line. That command creates a fresh AuraState (Init.lua:428), so its freelist is always 0 — the extension would be meaningless. Plan uses `/framed memusage` (aggregate) + new `/framed pools` (per-instance breakdown) instead, satisfying the spec's observability intent against real frames.

**Related:** #144 (scope), #155 (measurements), #159 (MemDiag tooling for A/B).

---

## Task 1: Audit classified consumers for stashed references

**Goal:** Pool merge is gated on this passing. Any caller that stashes `entry` or `entry.flags` across a UNIT_AURA must be fixed before the pool lands.

**Files:**
- Read-only: any file calling `GetHelpfulClassified`, `GetHarmfulClassified`, or `GetClassifiedByInstanceID`

- [ ] **Step 1: Enumerate consumers**

Run:
```
grep -rn "GetHelpfulClassified\|GetHarmfulClassified\|GetClassifiedByInstanceID" Elements/ Units/ Widgets/ Preview/
```

Expected call sites (from prior review — verify none are missing):
- `Elements/Auras/Buffs.lua`
- `Elements/Auras/Debuffs.lua`
- `Elements/Auras/Externals.lua`
- `Elements/Auras/Defensives.lua`
- `Elements/Auras/Dispellable.lua`
- `Elements/Auras/PrivateAuras.lua`
- `Elements/Auras/MissingBuffs.lua` (accepts either shape via `item.aura or item`)

- [ ] **Step 2: Check each consumer for stashing**

For each file, look for:
- Assignment of an entry to `self.*` or any non-local state: `self.X = entry`, `self.X[k] = entry`, `frame.Y = entry.flags`
- Assignment of an entry to a module-level table
- Any lifetime longer than the immediate iteration loop

The pattern that's safe:
```lua
for _, entry in next, auraState:GetHelpfulClassified() do
    if(entry.flags.isBigDefensive) then
        -- use entry.aura.*, entry.flags.* inline; never save
    end
end
```

The pattern that's unsafe (hypothetical):
```lua
for _, entry in next, auraState:GetHelpfulClassified() do
    self.currentEntry = entry  -- BAD: stashes ref past iteration
end
```

- [ ] **Step 3: Record findings and fix violators**

If any violator exists: fix it *in the same task* by extracting the needed fields inline before the stash, or by storing the `auraInstanceID` + re-resolving via `GetClassifiedByInstanceID` each time. Do not leave violators for a later task — the pool must land on a clean base.

If no violators: write a single-line comment at the top of `Core/AuraState.lua` documenting the audit:

```lua
-- Classified entries are pooled per-instance. Consumers must not stash
-- entry or entry.flags across UNIT_AURA — pool reuse silently refills
-- the wrapper. Audit completed 2026-04-22; all Elements/Auras/* iterate
-- inline without stashing.
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs(AuraState): note classified-entry stash invariant for pool (#144)"
git push origin working-testing
```

---

## Task 2: Add instance registry and pool field

**Files:**
- Modify: `Core/AuraState.lua` (near line 4 and around line 456)

- [ ] **Step 1: Add weak-keyed instance registry**

Near the top of `Core/AuraState.lua`, right after `F.AuraState = {}`:

```lua
local _, Framed = ...
local F = Framed

F.AuraState = {}

-- Weak-keyed registry so diagnostics can walk live instances without
-- preventing GC of frames whose AuraState becomes unreferenced.
F.AuraState._instances = setmetatable({}, { __mode = 'k' })
```

- [ ] **Step 2: Initialize pool field and register instance in Create**

Modify `F.AuraState.Create` (currently at line 456):

```lua
function F.AuraState.Create(owner)
    local inst = setmetatable({
        _owner = owner,
        _unit = nil,
        _initialized = false,
        _gen = 0,
        _lastUpdateInfo = nil,
        _lastUpdateUnit = nil,
        _helpfulById = {},
        _helpfulViews = {},
        _helpfulMatches = {},
        _helpfulClassifiedById = {},
        _helpfulClassifiedView = { dirty = true, list = {} },
        _harmfulById = {},
        _harmfulViews = {},
        _harmfulMatches = {},
        _harmfulClassifiedById = {},
        _harmfulClassifiedView = { dirty = true, list = {} },
        _classifiedFreeList = {},
    }, AuraState)
    F.AuraState._instances[inst] = true
    return inst
end
```

- [ ] **Step 3: Reload and verify no errors**

In WoW: `/reload`. Confirm no Lua errors at login. Run `/framed aurastate target` and confirm dumps still work.

- [ ] **Step 4: Commit**

```bash
git add Core/AuraState.lua
git commit -m "refactor(AuraState): add instance registry and freelist field (#144)"
git push origin working-testing
```

---

## Task 3: Replace classify() with acquireClassified() and wire call sites

**Files:**
- Modify: `Core/AuraState.lua:18-42` (classify function)
- Modify: `Core/AuraState.lua:395` (GetHelpfulClassified call site)
- Modify: `Core/AuraState.lua:416` (GetHarmfulClassified call site)
- Modify: `Core/AuraState.lua:433` and `445` (GetClassifiedByInstanceID call sites)

- [ ] **Step 1: Replace the module-local `classify` function with `acquireClassified`**

Replace lines 18-42:

```lua
-- Acquire a classified entry from the per-instance pool (or allocate
-- fresh if the pool is empty) and fill its flag fields for `aura`.
--
-- Tier 1 flags are structural AuraData booleans. Per Blizzard's 12.0.x
-- changes, isHelpful / isHarmful / isRaid / isNameplateOnly /
-- isFromPlayerOrPlayerPet are non-secret. isBossAura remains secret on
-- encounter auras and must be guarded with F.IsValueNonSecret to avoid
-- tainted boolean tests.
-- Tier 2 flags use C_UnitAuras filter probes (secret-safe C API).
local function acquireClassified(pool, unit, aura, isHelpful)
    local id = aura.auraInstanceID
    local prefix = isHelpful and 'HELPFUL' or 'HARMFUL'

    local entry = pool[#pool]
    if(entry) then
        pool[#pool] = nil
        wipe(entry.flags)
    else
        entry = { flags = {} }
    end

    entry.aura = aura

    local flags = entry.flags
    flags.isHelpful         = aura.isHelpful         or false
    flags.isHarmful         = aura.isHarmful         or false
    flags.isRaid            = aura.isRaid            or false
    flags.isBossAura        = F.IsValueNonSecret(aura.isBossAura) and aura.isBossAura or false
    flags.isFromPlayerOrPet = aura.isFromPlayerOrPlayerPet or false

    flags.isExternalDefensive = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|EXTERNAL_DEFENSIVE') == false
    flags.isImportant         = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|IMPORTANT')          == false
    flags.isPlayerCast        = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|PLAYER')             == false
    flags.isBigDefensive      = isHelpful
                                and IsAuraFilteredOutByInstanceID(unit, id, 'HELPFUL|BIG_DEFENSIVE') == false
                                or false
    flags.isRaidDispellable   = not isHelpful
                                and IsAuraFilteredOutByInstanceID(unit, id, 'HARMFUL|RAID_PLAYER_DISPELLABLE') == false
                                or false
    flags.isRaidInCombat      = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|RAID_IN_COMBAT') == false

    return entry
end
```

- [ ] **Step 2: Wire `GetHelpfulClassified` to use the pool**

Modify line 395 area:

Current:
```lua
for id, aura in next, self._helpfulById do
    local entry = self._helpfulClassifiedById[id]
    if(not entry) then
        entry = classify(self._unit, aura, true)
        self._helpfulClassifiedById[id] = entry
    end
    view.list[#view.list + 1] = entry
end
```

Replace with:
```lua
for id, aura in next, self._helpfulById do
    local entry = self._helpfulClassifiedById[id]
    if(not entry) then
        entry = acquireClassified(self._classifiedFreeList, self._unit, aura, true)
        self._helpfulClassifiedById[id] = entry
    end
    view.list[#view.list + 1] = entry
end
```

- [ ] **Step 3: Wire `GetHarmfulClassified` to use the pool**

Modify line 416 area — symmetric:
```lua
for id, aura in next, self._harmfulById do
    local entry = self._harmfulClassifiedById[id]
    if(not entry) then
        entry = acquireClassified(self._classifiedFreeList, self._unit, aura, false)
        self._harmfulClassifiedById[id] = entry
    end
    view.list[#view.list + 1] = entry
end
```

- [ ] **Step 4: Wire both `GetClassifiedByInstanceID` call sites**

Current lines 433 and 445:
```lua
entry = classify(self._unit, aura, true)
```
```lua
entry = classify(self._unit, aura, false)
```

Replace with:
```lua
entry = acquireClassified(self._classifiedFreeList, self._unit, aura, true)
```
```lua
entry = acquireClassified(self._classifiedFreeList, self._unit, aura, false)
```

- [ ] **Step 5: Reload and smoke test**

In WoW:
- `/reload`
- `/framed aurastate target` on a unit with live auras — classifications should match pre-change behavior
- Cast a buff on yourself, observe it appears in Buffs element correctly
- Take damage from a debuff, observe it appears in Debuffs element correctly
- Target-swap a few times — no aura flicker or misclassification

At this point the pool is being *acquired from* but never *released to* (Task 4), so `_classifiedFreeList` stays empty in practice. That's intentional — the acquire path is testable in isolation before wiring release.

- [ ] **Step 6: Commit**

```bash
git add Core/AuraState.lua
git commit -m "refactor(AuraState): route classify() through per-instance pool (#144)"
git push origin working-testing
```

---

## Task 4: Wire releaseClassified into Invalidate and Reset paths

**Files:**
- Modify: `Core/AuraState.lua` (add `releaseClassified` helper)
- Modify: `Core/AuraState.lua:111-117` (Reset*Classified methods)
- Modify: `Core/AuraState.lua:119-125` (Invalidate*Classified methods)

- [ ] **Step 1: Add `releaseClassified` local helper**

Add right after the `acquireClassified` function (near line 60 in the new layout):

```lua
-- Return a classified entry to the pool. Nils the aura reference so
-- the underlying AuraData can be GC'd even while the wrapper sits in
-- the free list; flags contents are left stale until the next acquire
-- wipes them (lazy — avoids paying wipe cost on entries that never
-- get reused before session end).
local function releaseClassified(pool, entry)
    entry.aura = nil
    pool[#pool + 1] = entry
end
```

- [ ] **Step 2: Update `InvalidateHelpfulClassified` to release**

Current (line 119-121):
```lua
function AuraState:InvalidateHelpfulClassified(auraInstanceID)
    self._helpfulClassifiedById[auraInstanceID] = nil
end
```

Replace with:
```lua
function AuraState:InvalidateHelpfulClassified(auraInstanceID)
    local entry = self._helpfulClassifiedById[auraInstanceID]
    if(entry) then
        releaseClassified(self._classifiedFreeList, entry)
        self._helpfulClassifiedById[auraInstanceID] = nil
    end
end
```

- [ ] **Step 3: Update `InvalidateHarmfulClassified` to release**

Symmetric:
```lua
function AuraState:InvalidateHarmfulClassified(auraInstanceID)
    local entry = self._harmfulClassifiedById[auraInstanceID]
    if(entry) then
        releaseClassified(self._classifiedFreeList, entry)
        self._harmfulClassifiedById[auraInstanceID] = nil
    end
end
```

- [ ] **Step 4: Update `ResetHelpfulClassified` to release each entry**

Current (line 111-113):
```lua
function AuraState:ResetHelpfulClassified()
    wipe(self._helpfulClassifiedById)
end
```

Replace with:
```lua
function AuraState:ResetHelpfulClassified()
    for id, entry in next, self._helpfulClassifiedById do
        releaseClassified(self._classifiedFreeList, entry)
    end
    wipe(self._helpfulClassifiedById)
end
```

- [ ] **Step 5: Update `ResetHarmfulClassified` to release each entry**

Symmetric:
```lua
function AuraState:ResetHarmfulClassified()
    for id, entry in next, self._harmfulClassifiedById do
        releaseClassified(self._classifiedFreeList, entry)
    end
    wipe(self._harmfulClassifiedById)
end
```

- [ ] **Step 6: Reload and test the full round-trip**

In WoW:
- `/reload`
- Target a unit, observe auras
- Apply new auras, let some expire, re-target — classified view should update without visual glitches
- Enter/leave combat several times (fires FullRefresh → Reset*Classified paths)
- Open `/framed aurastate target`, confirm classifications still accurate

At this point the pool is actually working: acquires pull from the free list when available, releases push entries back on invalidation and reset.

- [ ] **Step 7: Commit**

```bash
git add Core/AuraState.lua
git commit -m "refactor(AuraState): release classified entries to pool on invalidate/reset (#144)"
git push origin working-testing
```

---

## Task 5: Add aggregate pool line to /framed memusage

**Files:**
- Modify: `Init.lua` (extend `/framed memusage` output near line 481)

- [ ] **Step 1: Add aggregate computation and print**

In `Init.lua`, locate the `memusage` command block (around line 456). After the existing "top 10 addons" loop (around line 501), just before the `elseif(cmd == 'casttracker')` branch, insert:

```lua
-- Classified entry pool aggregate across all live AuraState instances.
local totalPooled = 0
local instanceCount = 0
for instance in next, F.AuraState._instances do
    instanceCount = instanceCount + 1
    totalPooled = totalPooled + #instance._classifiedFreeList
end
print(('|cff00ccff[Framed/mem]|r aurastate pool: %d entries across %d instances'):format(
    totalPooled, instanceCount))
```

- [ ] **Step 2: Reload and verify**

In WoW:
- `/reload`
- `/framed memusage` — should print the new line
- Before combat: expect low numbers (frame init may have released very little)
- After combat: expect higher numbers as aura churn pushes entries through the pool

- [ ] **Step 3: Commit**

```bash
git add Init.lua
git commit -m "feat(debug): show classified pool aggregate in /framed memusage (#144)"
git push origin working-testing
```

---

## Task 6: Add /framed pools command for per-instance breakdown

**Files:**
- Modify: `Init.lua` (new command branch + help text)

- [ ] **Step 1: Add `pools` command branch**

In `Init.lua`, insert a new branch after `casttracker` (roughly after line 511), before the `help` branch:

```lua
elseif(cmd == 'pools') then
    local rows = {}
    for instance in next, F.AuraState._instances do
        local owner = instance._owner
        local ownerName = owner and owner.GetName and owner:GetName() or '<anon>'
        local row = {
            name = ownerName,
            unit = instance._unit or '?',
            pooled = #instance._classifiedFreeList,
            helpful = 0,
            harmful = 0,
        }
        for _ in next, instance._helpfulClassifiedById do
            row.helpful = row.helpful + 1
        end
        for _ in next, instance._harmfulClassifiedById do
            row.harmful = row.harmful + 1
        end
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b) return a.pooled > b.pooled end)
    print('|cff00ccff Framed|r classified pool per instance:')
    print(('  %-32s %-12s %6s %6s %6s'):format('frame', 'unit', 'pooled', 'live+', 'live-'))
    for _, r in next, rows do
        print(('  %-32s %-12s %6d %6d %6d'):format(r.name, r.unit, r.pooled, r.helpful, r.harmful))
    end
```

- [ ] **Step 2: Add help text entry**

In the `cmd == 'help'` branch (around line 523), add:

```lua
print('  /framed pools — Dump per-instance classified pool sizes (for #144 diagnostics)')
```

- [ ] **Step 3: Reload and verify**

In WoW:
- `/reload`
- `/framed pools` — should print a table with one row per real frame
- Numbers should be sensible: live+ and live- bounded by auras on that unit, pooled grows with churn

- [ ] **Step 4: Commit**

```bash
git add Init.lua
git commit -m "feat(debug): add /framed pools for per-instance classified pool inspection (#144)"
git push origin working-testing
```

---

## Task 7: Acceptance gate — MemDiag A/B and test matrix

**Goal:** Validate that the pool actually reduces allocation without regressing correctness or introducing growth pathology.

**No code changes.** If any check fails, root-cause and add a follow-up task before declaring the PR ready.

- [ ] **Step 1: Pre-change MemDiag baseline**

Checkout the parent of the first pool commit (Task 2's commit on `working-testing`):

```bash
git log --oneline -n 10  # find commit hash BEFORE Task 2's commit
git checkout <parent-hash>
```

In WoW:
- `/reload`
- Enter LFR, wait for a pull to start (≥15 players visible in raid frames)
- `/framed memdiag 30`
- Save the bucket totals + top rows

Return to tip:
```bash
git checkout working-testing
```

- [ ] **Step 2: Post-change MemDiag comparison**

In WoW on comparable LFR content:
- `/reload`
- `/framed memdiag 30`
- Compare to Step 1 numbers

Expected:
- `AuraState:*` rows (`ApplyUpdateInfo`, `GetHelpfulClassified`, `GetHarmfulClassified`, `GetClassifiedByInstanceID`) drop materially in per-call KB
- `event:UNIT_AURA` bucket (nests AuraState) drops by comparable amount
- Total 30 s allocation delta drops toward baseline (Framed share of yoyo shrinks)

If allocation *doesn't* drop: the pool isn't being exercised. Check `/framed pools` — if pooled counts stay at 0, release path is not wired.

- [ ] **Step 3: 0.7.20 regression replay**

Load addons: MPlusQOL, AbilityTimeline, WeakAuras. Enter a 10+ player raid pull.

Check after pull:
- No `attempt to compare number with nil` errors in BugSack
- No nil text errors from AceEvent dispatch
- No missing / stale / ghost aura icons on any unit frame

If any surface: the aliasing audit (Task 1) missed a consumer or an external addon is holding references we didn't expect. Root-cause before proceeding.

- [ ] **Step 4: Growth-bound check**

Run several LFR pulls back-to-back. After each, run `/framed memusage` and note the `aurastate pool` total. Expected: total stabilizes at working-set peak and does not climb monotonically across pulls.

If it climbs without bound across 3+ pulls: freelist is retaining entries beyond reuse — investigate whether Reset paths are missing release, then add a hard cap follow-up if warranted.

- [ ] **Step 5: Verify no ghost auras via audit replay**

One explicit stress case: `/target <friendly>`, apply a buff (e.g., trinket proc), `/cleartarget`, wait 10s for the buff to expire off them, re-target. The formerly-pooled entry for that buff's ID will have been recycled by now — confirm no ghost aura appears on the fresh target.

- [ ] **Step 6: Record findings in the PR body**

When opening the PR for this branch, include in the body:
- Pre/post MemDiag bucket totals for AuraState:* rows
- Pool growth observation across multiple pulls
- Explicit statement that 0.7.20 regression tests passed

No commit for this task.

---

## Checklist self-review

- Task 1 addresses the aliasing audit gate from the spec.
- Tasks 2–4 implement the pool strictly to spec: per-instance, paired, wipe at acquire, release routed through dedicated helpers.
- Tasks 5–6 implement the observability surfaces (diverging from spec's `/framed aurastate` note — documented above).
- Task 7 is the test gate from the spec, operationalized.
- Every code task ends with a commit + push (user's `feedback_commit_after_task` convention).
- Every step references exact file paths and shows complete code.
- No TODOs, no "fill in details", no placeholders.
