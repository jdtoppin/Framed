# FullRefresh Varargs-Pack Elimination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Per user preference (`feedback_inline_execution`), Framed plans execute inline rather than subagent-driven.

**Goal:** Eliminate per-`FullRefresh` varargs-pack allocation in `AuraState` by routing HELPFUL and HARMFUL slot lookups through a single reusable per-instance scratch table, reducing the dominant allocation source in Framed's LFR memory yoyo.

**Architecture:** Add a module-local `fillSlots(tbl, ...)` helper that packs vararg returns into a caller-provided table and returns the count. Add a `_slotsScratch = {}` field to each `AuraState` instance. Rewrite the two `{ GetAuraSlots(...) }` call sites in `AuraState:FullRefresh` to use the shared scratch via the helper. The HELPFUL and HARMFUL passes are sequential, so one scratch serves both safely.

**Tech Stack:** Lua (WoW 12.0.x client API), `C_UnitAuras.GetAuraSlots`, `C_UnitAuras.GetAuraDataBySlot`.

**Spec:** `docs/superpowers/specs/2026-04-22-fullrefresh-varargs-design.md`

**Branch:** `working-testing` (Framed's single-workspace convention — no worktree split; PRs merge `working-testing` → `working`).

---

## File Structure

**Modify:** `Core/AuraState.lua`
- Insert module-local `fillSlots` helper near existing allocation-avoidance helpers (after `releaseClassified`, before `isCompoundUnit`).
- Add `_slotsScratch = {}` field to the `F.AuraState.Create` instance table (next to `_classifiedFreeList = {}`).
- Replace HELPFUL varargs-pack + loop inside `AuraState:FullRefresh`.
- Replace HARMFUL varargs-pack + loop inside `AuraState:FullRefresh`.

No other files touched. No new files created.

---

## Verification Model

This is a WoW addon with no test harness. Verification after each task is:
1. **Reload:** User runs `/reload` in-game. No Lua errors in `BugSack`.
2. **Targeted behavior check:** User confirms the affected feature still works (buffs render after HELPFUL rewrite, debuffs render after HARMFUL rewrite, etc.).
3. **Final validation** (Task 6): Ghost-aura stress, zero-aura unit, regression replay, MemDiag A/B.

Each task commits + pushes per `feedback_commit_after_task` (crash protection between reloads).

---

## Task 1: Capture pre-change MemDiag baseline

**Why first:** The existing baseline from #155 was pre-#160. #160 reduced `Get*Classified` allocation but left `FullRefresh`'s varargs packs untouched. We need a fresh baseline on the current `working-testing` HEAD so the post-change A/B is apples-to-apples.

**Files:** None modified. Data capture only.

- [ ] **Step 1: Confirm branch is clean at current HEAD**

Run: `git status && git log --oneline -1`
Expected: clean tree, HEAD at `6dea4e1 Revise FullRefresh varargs spec per review feedback` (or later if spec has been amended).

- [ ] **Step 2: Ask user to run baseline MemDiag in LFR**

User instructions (deliver to user):
```
Before we make any code changes, I need a fresh baseline MemDiag reading.

1. Queue LFR (any wing — pick whichever pops quickest).
2. Once you're in and the first pull starts, run: /framed memdiag 30
3. Wait 30 seconds, then paste the full output here.

We're looking for the AuraState:FullRefresh row's bytes-per-call and total,
plus the event:UNIT_AURA bucket total. That's what Task 6 will compare against.
```

- [ ] **Step 3: Record baseline values**

When user pastes output, record three values for the plan's post-change comparison:
- `AuraState:FullRefresh` — bytes per call, total bytes, call count
- `event:UNIT_AURA` — total bytes
- Total `collectgarbage('count')` delta across the 30 s window

Save as a comment on this task in the conversation (no file edit needed).

- [ ] **Step 4: No commit**

Data capture task — nothing to commit.

---

## Task 2: Add `fillSlots` helper and `_slotsScratch` field

**Files:**
- Modify: `Core/AuraState.lua` (two insertion points)

Both additions are dead code on their own (nothing calls the helper; nothing reads the field). Combining them into one commit avoids having two no-op commits in history while keeping Task 2 small enough to verify with a single reload.

- [ ] **Step 1: Insert `fillSlots` helper after `releaseClassified`**

Locate the existing anchor in `Core/AuraState.lua`:
```lua
local function releaseClassified(pool, entry)
	entry.aura = nil
	pool[#pool + 1] = entry
end

-- Compound unit tokens (e.g. 'party2target', 'playertarget', 'focustarget')
```

Insert the new helper between `end` and the `-- Compound unit tokens` comment, like so:

```lua
local function releaseClassified(pool, entry)
	entry.aura = nil
	pool[#pool + 1] = entry
end

-- Pack GetAuraSlots varargs into `tbl` without allocating a fresh pack table.
-- Returns the count, which callers MUST use as the iteration bound (not #tbl).
-- Position 1 holds the continuation token; real slot IDs start at index 2.
-- The tail loop nils any residual entries from a prior call where the aura
-- count was higher, keeping `tbl` a proper sequence across reuses.
local function fillSlots(tbl, ...)
	local n = select('#', ...)
	for i = 1, n do
		tbl[i] = select(i, ...)
	end
	for i = n + 1, #tbl do
		tbl[i] = nil
	end
	return n
end

-- Compound unit tokens (e.g. 'party2target', 'playertarget', 'focustarget')
```

Use tabs for indentation (per `CLAUDE.md` code style — aligns with oUF).

- [ ] **Step 2: Add `_slotsScratch` field to `F.AuraState.Create`**

Locate the existing `Create` instance-table literal in `Core/AuraState.lua`:

```lua
function F.AuraState.Create(owner)
	local inst = setmetatable({
		_owner = owner,
		...
		_classifiedFreeList = {},
	}, AuraState)
```

Add `_slotsScratch = {},` immediately after `_classifiedFreeList = {},`:

```lua
		_classifiedFreeList = {},
		_slotsScratch = {},
	}, AuraState)
```

- [ ] **Step 3: Request user reload**

User instructions:
```
I've added the fillSlots helper and _slotsScratch field. Both are
dead code for now (no call sites yet), so this reload just confirms
the file parses cleanly.

Please /reload and let me know if BugSack shows any Lua errors.
```

Expected: no errors. The helper is defined but never called; the field is set but never read.

- [ ] **Step 4: Commit + push**

```bash
git add Core/AuraState.lua
git commit -m "refactor(AuraState): add fillSlots helper and _slotsScratch field (#155)

Module-local fillSlots packs GetAuraSlots varargs into a caller-provided
table without allocating a fresh pack per call. _slotsScratch is a
per-instance reusable scratch table. Both unused until FullRefresh
call sites are rewritten in the next commits.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git push origin working-testing
```

---

## Task 3: Rewrite HELPFUL call site in `FullRefresh`

**Files:**
- Modify: `Core/AuraState.lua` (HELPFUL block inside `AuraState:FullRefresh`)

- [ ] **Step 1: Locate the HELPFUL block**

Search for the exact anchor in `Core/AuraState.lua`:
```lua
	local helpfulResults = { GetAuraSlots(unit, 'HELPFUL') }
	for i = 2, #helpfulResults do
		local aura = GetAuraDataBySlot(unit, helpfulResults[i])
		if(aura and aura.auraInstanceID) then
			self._helpfulById[aura.auraInstanceID] = aura
		end
	end
```

This block lives inside `AuraState:FullRefresh`. (Line number was 244 pre-Task-2; adding the helper shifts it by ~15 lines — use the code anchor, not the line number.)

- [ ] **Step 2: Replace with scratch + helper call**

Replace the entire HELPFUL block (exact 7 lines shown above) with:

```lua
	local nHelpful = fillSlots(self._slotsScratch, GetAuraSlots(unit, 'HELPFUL'))
	for i = 2, nHelpful do
		local aura = GetAuraDataBySlot(unit, self._slotsScratch[i])
		if(aura and aura.auraInstanceID) then
			self._helpfulById[aura.auraInstanceID] = aura
		end
	end
```

Changes: `{ GetAuraSlots(...) }` → `fillSlots(self._slotsScratch, GetAuraSlots(...))`; loop bound `#helpfulResults` → `nHelpful`; index source `helpfulResults[i]` → `self._slotsScratch[i]`. Everything else is identical.

- [ ] **Step 3: Request user reload + buff render check**

User instructions:
```
HELPFUL (buffs) path now routes through _slotsScratch via fillSlots.
Please:

1. /reload
2. Target yourself (/tar player) or any friendly unit with visible buffs.
3. Confirm buffs render correctly on the target frame.
4. Check BugSack for any Lua errors.

If buffs render and no errors: we're good. Report back either way.
```

Expected: buffs render identically to before; no Lua errors. Behavior is unchanged — same iteration bounds, same data flow, just the scratch substitution.

- [ ] **Step 4: Commit + push**

```bash
git add Core/AuraState.lua
git commit -m "refactor(AuraState): route FullRefresh HELPFUL through _slotsScratch (#155)

Eliminates one of two { GetAuraSlots(...) } varargs packs per FullRefresh
call. HARMFUL follows in the next commit.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git push origin working-testing
```

---

## Task 4: Rewrite HARMFUL call site in `FullRefresh`

**Files:**
- Modify: `Core/AuraState.lua` (HARMFUL block inside `AuraState:FullRefresh`, immediately after the now-rewritten HELPFUL block)

- [ ] **Step 1: Locate the HARMFUL block**

Search for the exact anchor:
```lua
	local harmfulResults = { GetAuraSlots(unit, 'HARMFUL') }
	for i = 2, #harmfulResults do
		local aura = GetAuraDataBySlot(unit, harmfulResults[i])
		if(aura and aura.auraInstanceID) then
			self._harmfulById[aura.auraInstanceID] = aura
		end
	end
```

- [ ] **Step 2: Replace with scratch + helper call**

Replace the entire HARMFUL block (exact 7 lines shown above) with:

```lua
	local nHarmful = fillSlots(self._slotsScratch, GetAuraSlots(unit, 'HARMFUL'))
	for i = 2, nHarmful do
		local aura = GetAuraDataBySlot(unit, self._slotsScratch[i])
		if(aura and aura.auraInstanceID) then
			self._harmfulById[aura.auraInstanceID] = aura
		end
	end
```

The HELPFUL loop above has already finished reading `_slotsScratch` by the time this call executes, so reusing the same scratch is safe (sequential access, no concurrency, no re-entry — `GetAuraSlots` and `GetAuraDataBySlot` are pure C getters with no Lua callbacks).

- [ ] **Step 3: Request user reload + debuff render check**

User instructions:
```
HARMFUL (debuffs) path now also routes through _slotsScratch. Both
FullRefresh varargs packs are eliminated.

Please:

1. /reload
2. Engage a target dummy or easy mob, apply some debuffs (any DoT, or
   let the mob swing on you).
3. Confirm debuffs render correctly on your target frame.
4. Confirm buffs still render (Task 3 didn't regress).
5. Check BugSack.

If both buff and debuff display works and no errors: green light.
```

Expected: both buffs and debuffs render identically to pre-change; no Lua errors.

- [ ] **Step 4: Commit + push**

```bash
git add Core/AuraState.lua
git commit -m "refactor(AuraState): route FullRefresh HARMFUL through _slotsScratch (#155)

Second and final { GetAuraSlots(...) } varargs pack eliminated. Both
HELPFUL and HARMFUL passes now share the per-instance _slotsScratch
table, accessed sequentially within FullRefresh.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git push origin working-testing
```

---

## Task 5: In-game validation pass

**Files:** None modified. Behavioral validation only, matching the test gate in the spec.

- [ ] **Step 1: Ghost-aura stress**

User instructions:
```
Ghost-aura stress test (verifies the scratch is properly reset between units):

1. Target yourself — note the buffs showing.
2. /tar party1 (or any party/raid member with different buffs).
3. Switch back to /tar player.
4. Repeat target-swap several times, ideally while buffs are expiring
   and being refreshed.
5. Watch for: buffs from another unit bleeding onto yours, missing
   buffs that should be there, duplicated buffs, or any visual
   inconsistency.

Expected: buff display matches current unit exactly at every swap.
Report what you see.
```

- [ ] **Step 2: Zero-aura unit**

User instructions:
```
Zero-aura test (verifies fillSlots handles the no-aura return shape):

1. Find any unit with no active buffs/debuffs — a training dummy that's
   currently not being hit, or a mob just before engaging.
2. /tar that unit.
3. Confirm no Lua errors in BugSack.
4. If you can find a unit that cleanly shows zero auras: confirm an
   empty buff/debuff row (or nothing at all) renders without error.

Expected: no errors regardless of what GetAuraSlots returns for the
no-aura case. The iteration `for i = 2, n` is a no-op for any n ≤ 1.
```

- [ ] **Step 3: Regression replay**

User instructions:
```
Full regression replay:

1. /reload fresh.
2. Enter combat (any target, any fight).
3. Exit combat.
4. Target chains: /tar target, /tar targettarget (compound units —
   AuraState skips these via isCompoundUnit, but we verify no error).
5. If you have MPlusQOL / AbilityTimeline / WeakAuras loaded, verify
   none of them throw `attempt to compare number with nil` or nil-text
   errors (the 0.7.20 pool regression signature).

Expected: zero BugSack errors across the full sequence.
```

- [ ] **Step 4: No commit**

Validation task — nothing to commit unless a regression is found. If a regression surfaces, create a new task to fix and re-validate before proceeding.

---

## Task 6: Capture post-change MemDiag and compute A/B delta

**Files:** None modified. Data capture + analysis.

- [ ] **Step 1: Request post-change MemDiag in comparable LFR**

User instructions:
```
Final measurement — post-change MemDiag in LFR.

1. Queue LFR again (same wing as Task 1 if possible, to minimize pull-
   intensity drift).
2. Once in and the first pull starts, run: /framed memdiag 30
3. Wait 30 seconds, paste the full output.

If same-wing isn't possible, any comparable 20-man raid environment is
fine — we'll note the difference when interpreting.
```

- [ ] **Step 2: Compute the A/B delta**

Compare post-change output to the Task 1 baseline. Record:

| Metric | Pre | Post | Delta |
|---|---|---|---|
| `AuraState:FullRefresh` bytes/call | | | |
| `AuraState:FullRefresh` total | | | |
| `event:UNIT_AURA` total | | | |
| Total GC delta (30 s) | | | |

Important caveat per the spec: MemDiag attribution is per-Lua-function, not per-expression. `AuraState:FullRefresh` bytes-per-call covers *everything* in that function including the AuraData tables returned by `GetAuraDataBySlot` (Blizzard-owned, one per slot, out of scope for this PR). The expected delta is the share that belongs to the two eliminated varargs packs — magnitude is informational, direction is the criterion.

If call counts differ significantly (as happened in #160's A/B where post-change had 1.7× more UNIT_AURA events), normalize bytes-per-call and flag non-comparability in the PR body.

- [ ] **Step 3: No commit**

Analysis task — no file changes. Findings flow into the PR body in Task 7.

---

## Task 7: Push branch + create PR

**Files:** None modified locally. Branch push + GitHub PR.

- [ ] **Step 1: Confirm branch is up to date**

Run:
```bash
git status
git log --oneline origin/working-testing..working-testing
```

Expected: clean tree. Second command shows the three commits from Tasks 2, 3, 4 (helper+field, HELPFUL rewrite, HARMFUL rewrite), already pushed via per-task `git push` calls.

If second command shows commits NOT yet pushed, push them:
```bash
git push origin working-testing
```

- [ ] **Step 2: Verify base branch for PR**

Confirm `working` is the correct PR target (per `project_framed_worktree`: feature PRs go `working-testing` → `working`, then `working` promotes to `main` at release).

Run:
```bash
git fetch origin
git log --oneline origin/working..origin/working-testing
```

Expected: shows the three commits from this branch that `working` doesn't have yet. If there are unrelated commits mixed in, flag before proceeding.

- [ ] **Step 3: Create PR**

```bash
gh pr create --base working --head working-testing --title "refactor(AuraState): eliminate FullRefresh varargs-pack allocation (#155 item 3)" --body "$(cat <<'EOF'
## Summary

Eliminates the two `{ GetAuraSlots(unit, 'HELPFUL') }` / `{ GetAuraSlots(unit, 'HARMFUL') }` varargs packs per `AuraState:FullRefresh` call by routing slot lookups through a single per-instance `_slotsScratch` table via a new `fillSlots(tbl, ...)` module-local helper.

Item 3 from #155's ranked fix list, deferred from #144 to keep that PR's MemDiag attribution clean.

## Design

Spec: `docs/superpowers/specs/2026-04-22-fullrefresh-varargs-design.md`

Key decisions:
- **One scratch per instance** (not one per direction) — HELPFUL and HARMFUL passes are strictly sequential within `FullRefresh`, so a single shared scratch is safe and simpler.
- **Tail-clear on reuse** (not full `wipe`) — table is bounded and `n` is already known; walking the whole table every call is wasted work.
- **Per-instance** (not module-shared) — matches #144's approach; avoids the 0.7.20 revert's shared-state failure mode.

## MemDiag A/B (30 s LFR window)

<!-- Fill in from Task 1 + Task 6 output -->

| Metric | Pre | Post | Delta |
|---|---|---|---|
| `AuraState:FullRefresh` bytes/call | | | |
| `AuraState:FullRefresh` total | | | |
| `event:UNIT_AURA` total | | | |
| Total GC delta | | | |

**Caveat:** MemDiag attribution is per-Lua-function, not per-expression. `FullRefresh`'s total covers the AuraData tables returned by `GetAuraDataBySlot` (Blizzard-owned, out of scope) as well as the eliminated varargs packs. Magnitude is informational; direction is the criterion.

## Test plan

- [x] `fillSlots` helper + `_slotsScratch` field added (Task 2 reload clean)
- [x] HELPFUL call site rewritten, buffs render (Task 3)
- [x] HARMFUL call site rewritten, debuffs render (Task 4)
- [x] Ghost-aura stress — no cross-unit bleed on target swaps (Task 5)
- [x] Zero-aura unit — no errors regardless of `GetAuraSlots` no-aura return shape (Task 5)
- [x] Regression replay with MPlusQOL / AbilityTimeline / WeakAuras — zero BugSack errors (Task 5)
- [x] MemDiag A/B captured (Task 6)

## Out of scope (deferred)

- `Elements/Status/StatusText.lua:80` drink-scan varargs pack — cold path, OOC-only (separate issue).
- `Libs/oUF/elements/auras.lua` call sites — embedded oUF off-limits.
- Item 2 from #155 — reducing `FullRefresh` call frequency — separate future PR to keep A/B clean.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Backfill MemDiag A/B table from Task 6 findings**

The PR body template has a placeholder `<!-- Fill in from Task 1 + Task 6 output -->` with an empty table. Edit the PR after creation:

```bash
gh pr edit <pr-number> --body "$(cat <<'EOF'
... (paste the full body with A/B table filled in from Task 6 Step 2) ...
EOF
)"
```

Or manually via `gh pr view <number> --web` and edit in the browser.

- [ ] **Step 5: Report PR URL to user**

Share the PR URL. The user reviews → merges `working-testing` → `working` → eventually promotes `working` → `main` on release cadence.

---

## Notes for the executor

- **Code style:** Tabs for indentation, single quotes for strings, parenthesized conditions (`if(x) then`), `for _, v in next, tbl do` (never `pairs`/`ipairs`). See `CLAUDE.md`.
- **Symlink:** Framed's addon folder is a symlink to this repo. Edits are live — user just `/reload`s to pick up changes (no rsync). See `feedback_wow_sync`.
- **Per-task commits:** Commit + push after every task. Crash protection between reloads. See `feedback_commit_after_task`.
- **No pcall:** Feature detection via `if C_UnitAuras.GetAuraSlots then`, never `pcall`. This plan doesn't add any new feature detection, but don't introduce `pcall` in the helper.
- **Comments:** Default to no comments. The one comment in `fillSlots` (Task 2 Step 1) documents the non-obvious contract (callers MUST use returned `n`, not `#tbl`) — that's a WHY, not a WHAT, so it stays.
