# B4 — Debuffs Classified Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `Elements/Auras/Debuffs.lua` to consume `auraState:GetHarmfulClassified()` via per-indicator flag dispatch, eliminating one server-filter fetch (plus a second for the dispellable double-pass) per indicator per UNIT_AURA.

**Architecture:** Extend `Core/AuraState.lua` classify() with two harmful-only flags (`isRaidDispellable`, `isRaidInCombat`). Replace `updateIndicator`'s `auraState:GetHarmful(filterString)` call with a single `GetHarmfulClassified()` iteration dispatched via a pre-loop `flagKey` lookup. Preserve: the `encounter`-mode `IsEncounterInProgress` gate, the long-duration skip, the dispellable Physical/bleed double-pass, boss `bigIconSize`, and the `dispelName` coloring passed to `BorderIcon:SetAura`. Vestigial no-AuraState fallback keeps the current server-filter path.

**Tech Stack:** Lua 5.1, oUF, `F.AuraState.GetHarmfulClassified`, `F.IsValueNonSecret`, `F.Indicators.BorderIcon`.

---

## Context

### Current filter map (pre-B4)

```lua
local FILTER_MAP = {
    all          = 'HARMFUL',
    raid         = 'HARMFUL|RAID',
    important    = 'HARMFUL|IMPORTANT',
    dispellable  = 'HARMFUL|RAID_PLAYER_DISPELLABLE',
    raidCombat   = 'HARMFUL|RAID_IN_COMBAT',
    encounter    = 'HARMFUL|RAID',
}
```

### Classified flag mapping

| filterMode | Classified flag | New? |
|------------|-----------------|------|
| `all` | (no flag — all entries pass) | — |
| `raid` | `flags.isRaid` | existing Tier 1 |
| `important` | `flags.isImportant` | existing Tier 2 |
| `dispellable` | `flags.isRaidDispellable` | **NEW** |
| `raidCombat` | `flags.isRaidInCombat` | **NEW** |
| `encounter` | `flags.isRaid` (gated on `IsEncounterInProgress`) | existing Tier 1 |

Only two new flags. `raid` and `encounter` both read `flags.isRaid` — the encounter-mode difference is the `IsEncounterInProgress()` short-circuit already at the top of `updateIndicator`, which stays.

### Preserved behavior (must not drift)

1. **Boss bigIconSize** — `F.IsValueNonSecret(auraData.isBossAura) and auraData.isBossAura` inside `displayAura`. Boss auras render at `cfg.bigIconSize`; others at `cfg.iconSize`. Size affects running pixel offset.
2. **Long-duration skip** — `dur == 0 or dur >= 600` guarded by `F.IsValueNonSecret`, filters flasks / permanent debuffs / racials from rendering in the primary pass.
3. **Dispel-type coloring** — `auraData.dispelName` is passed as the 7th arg to `BorderIcon:SetAura`. `BorderIcon` uses this to drive the colored overlay (the fix that landed earlier for the dispel-type bug relies on it being passed here).
4. **Red border** — `bi:SetBorderColor(1, 0, 0, 1)` inside `displayAura`; all debuffs use this color regardless of dispel type.
5. **Dispellable + Physical/bleed double-pass** — `RAID_PLAYER_DISPELLABLE` excludes Physical/bleed debuffs from the server-side result. After the primary dispellable pass, a supplementary `HARMFUL|RAID`-equivalent iteration picks up auras whose `dispelName` is nil/empty/`'Physical'`. The supplementary pass passes `nil` for the dispelType (not `auraData.dispelName`) so the BorderIcon doesn't draw a dispel-color overlay for non-dispellable debuffs.
6. **Per-indicator architecture** — one `FramedDebuffs` element has N named indicators, each with its own `_config` / `_pool` / `_container`. `Update` loops all indicators and calls `updateIndicator(self, unit, ind)` per indicator. That shape is unchanged.

### Why only one fetch per indicator (not per filter)

Before B4: each indicator calls `GetHarmful(filterString)`, which populates a view keyed by filter string. The helpful classified view is a single list — one populate, read from by any number of callers. After B4, `GetHarmfulClassified()` is fetched **once per indicator** (still technically re-populated per indicator on first access, but the classification cache is shared — only the view's list rebuild repeats if dirty). Further, since classification is cached per auraInstanceID, the second indicator's iteration on the same unit reuses the cached `entry` wrappers.

Net: N indicators × M auras drops from `N × M × (1 probe chain resolving one filter string)` to `M probes once` (all classified-cached) + `N × M flag reads`. Flag reads are field lookups on a Lua table — ~free.

### Fallback path (no AuraState)

Vestigial but preserved, matching B1/B2. When `self.FramedAuraState` is nil, the element falls through to `F.AuraCache.GetUnitAuras(unit, filterString)` with the original server filter. All downstream logic (long-duration skip, dispellable double-pass, boss sizing) stays verbatim in the fallback branch.

### New flag definitions (Task 1)

Mirrors A1's `isBigDefensive` pattern — a harmful-only probe wrapped with `not isHelpful and ... or false`:

```lua
flags.isRaidDispellable = not isHelpful
                          and IsAuraFilteredOutByInstanceID(unit, id, 'HARMFUL|RAID_PLAYER_DISPELLABLE') == false
                          or false
flags.isRaidInCombat    = not isHelpful
                          and IsAuraFilteredOutByInstanceID(unit, id, 'HARMFUL|RAID_IN_COMBAT') == false
                          or false
```

Harmful classify() goes from 3 probes (isExternalDefensive, isImportant, isPlayerCast) to 5. Helpful classify() unchanged.

---

## File Structure

- **Modify:** `Core/AuraState.lua` — add two flags to `classify()` (lines 22-35 area).
- **Modify:** `Elements/Auras/Debuffs.lua` — replace `updateIndicator` body with classified-path + vestigial fallback.

No new files. No changes to `Core/AuraCache.lua`, `F.AuraState.GetHarmful*`, or `BorderIcon`.

---

## Task 1: Add `isRaidDispellable` and `isRaidInCombat` flags to AuraState.classify()

**Files:**
- Modify: `Core/AuraState.lua:18-38` (the `classify` function)

- [ ] **Step 1: Read the current classify() to confirm no drift**

Read `Core/AuraState.lua` lines 18-38 to confirm the probe block still starts at line 30 with `flags.isExternalDefensive`. If the file has drifted, re-read before editing.

- [ ] **Step 2: Add the two new flags after `isBigDefensive`**

Edit `Core/AuraState.lua`. The existing block (lines 30-35):

```lua
	flags.isExternalDefensive = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|EXTERNAL_DEFENSIVE') == false
	flags.isImportant         = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|IMPORTANT')          == false
	flags.isPlayerCast        = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|PLAYER')             == false
	flags.isBigDefensive      = isHelpful
	                            and IsAuraFilteredOutByInstanceID(unit, id, 'HELPFUL|BIG_DEFENSIVE') == false
	                            or false
```

Becomes:

```lua
	flags.isExternalDefensive = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|EXTERNAL_DEFENSIVE') == false
	flags.isImportant         = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|IMPORTANT')          == false
	flags.isPlayerCast        = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|PLAYER')             == false
	flags.isBigDefensive      = isHelpful
	                            and IsAuraFilteredOutByInstanceID(unit, id, 'HELPFUL|BIG_DEFENSIVE') == false
	                            or false
	flags.isRaidDispellable   = not isHelpful
	                            and IsAuraFilteredOutByInstanceID(unit, id, 'HARMFUL|RAID_PLAYER_DISPELLABLE') == false
	                            or false
	flags.isRaidInCombat      = not isHelpful
	                            and IsAuraFilteredOutByInstanceID(unit, id, 'HARMFUL|RAID_IN_COMBAT') == false
	                            or false
```

- [ ] **Step 3: Verify the probes only fire for harmful auras**

Grep the section to confirm:

Run: `Grep -n "isRaidDispellable\|isRaidInCombat" Core/AuraState.lua`
Expected: two matches, each under `not isHelpful and ... or false`.

No changes needed to the `/framed aurastate` slash handler — `Init.lua:431-439`'s `formatFlags` enumerates `flags` dynamically (`for k, v in next, flags do`), so new flag keys appear automatically. Slash-output flag names will be the camelCase Lua keys (`isRaidDispellable`, `isRaidInCombat`), matching the existing `isExternalDefensive` / `isImportant` / etc. style.

- [ ] **Step 4: Syntax check**

Run: `luac -p Core/AuraState.lua` if luac is available locally. If not, visually scan the edited region and confirm:
- Each `flags.X = ...` statement ends on its own line
- `and` / `or` precedence matches the existing `isBigDefensive` pattern
- No stray trailing commas (these are assignments, not a table literal)

- [ ] **Step 5: Commit**

```bash
git add Core/AuraState.lua
git commit -m "$(cat <<'EOF'
feat(aurastate): add isRaidDispellable + isRaidInCombat flags

Mirrors the isBigDefensive helpful-only pattern on the harmful side —
probes HARMFUL|RAID_PLAYER_DISPELLABLE and HARMFUL|RAID_IN_COMBAT once
per aura per generation, cached on the classified entry.

Consumed by B4 Debuffs (#140) to dispatch filter modes via flag reads
instead of re-fetching per-filter server-side aura slices.

Helpful classify() unchanged — both flags short-circuit to false when
isHelpful is true.

Part of #115 UNIT_AURA fan-out rearchitecture.
EOF
)"
```

---

## Task 2: Migrate `Elements/Auras/Debuffs.lua` updateIndicator to classified path

**Files:**
- Modify: `Elements/Auras/Debuffs.lua` — `updateIndicator` function (lines 82-146)

- [ ] **Step 1: Read the current file to confirm line ranges**

Read `Elements/Auras/Debuffs.lua` lines 82-146. Confirm `updateIndicator` still has the FILTER_MAP lookup at line 103, the `GetHarmful(filter)` call at line 105, the primary loop at lines 113-123, and the dispellable double-pass at lines 128-140. If any of these ranges drifted, re-read the file before editing.

- [ ] **Step 2: Replace `updateIndicator` body with two-path classified / fallback structure**

Open `Elements/Auras/Debuffs.lua`. The current `updateIndicator` body (lines 82-146):

```lua
local function updateIndicator(self, unit, ind)
	local cfg = ind._config
	local maxDisplayed = cfg.maxDisplayed

	-- Backward compat: map old boolean to new filterMode
	local filterMode = cfg.filterMode
	if(not filterMode and cfg.onlyDispellableByMe) then
		filterMode = 'dispellable'
	end

	-- Encounter mode: only show during active boss encounters
	if(filterMode == 'encounter') then
		if(not C_InstanceEncounter or not C_InstanceEncounter.IsEncounterInProgress
			or not C_InstanceEncounter.IsEncounterInProgress()) then
			for idx = 1, #ind._pool do
				ind._pool[idx]:Clear()
			end
			return
		end
	end

	local filter = FILTER_MAP[filterMode] or 'HARMFUL'
	local auraState = self.FramedAuraState
	local rawAuras = auraState and auraState:GetHarmful(filter) or F.AuraCache.GetUnitAuras(unit, filter)
	local pool = ind._pool

	-- Single-pass: filter and display directly from auraData.
	-- auraInstanceID is NeverSecret; BorderIcon.SetAura uses C-level APIs
	-- for secret fields (icon, duration, etc.).
	local displayed = 0
	local runOffset = 0
	for _, auraData in next, rawAuras do
		if(displayed >= maxDisplayed) then break end

		local dur = auraData.duration
		local skip = F.IsValueNonSecret(dur) and (dur == 0 or dur >= 600)

		if(not skip) then
			displayed = displayed + 1
			runOffset = displayAura(self, unit, pool, displayed, runOffset, cfg, auraData, auraData.dispelName)
		end
	end

	-- When filterMode is 'dispellable', also include Physical/bleed debuffs
	-- from a broader HARMFUL|RAID query (RAID_PLAYER_DISPELLABLE excludes them).
	-- Supplementary results appear after the server-sorted dispellable set.
	if(filterMode == 'dispellable' and displayed < maxDisplayed) then
		local raidAuras = auraState and auraState:GetHarmful('HARMFUL|RAID') or F.AuraCache.GetUnitAuras(unit, 'HARMFUL|RAID')
		for _, auraData in next, raidAuras do
			if(displayed >= maxDisplayed) then break end

			local dn = auraData.dispelName
			local isPhysical = F.IsValueNonSecret(dn) and (not dn or dn == '' or dn == 'Physical')
			if(isPhysical) then
				displayed = displayed + 1
				runOffset = displayAura(self, unit, pool, displayed, runOffset, cfg, auraData, nil)
			end
		end
	end

	-- Hide pool entries beyond active count
	for idx = displayed + 1, #pool do
		pool[idx]:Clear()
	end
end
```

Replace with:

```lua
local function updateIndicator(self, unit, ind)
	local cfg = ind._config
	local maxDisplayed = cfg.maxDisplayed
	local pool = ind._pool

	-- Backward compat: map old boolean to new filterMode
	local filterMode = cfg.filterMode
	if(not filterMode and cfg.onlyDispellableByMe) then
		filterMode = 'dispellable'
	end

	-- Encounter mode: only show during active boss encounters
	if(filterMode == 'encounter') then
		if(not C_InstanceEncounter or not C_InstanceEncounter.IsEncounterInProgress
			or not C_InstanceEncounter.IsEncounterInProgress()) then
			for idx = 1, #pool do
				pool[idx]:Clear()
			end
			return
		end
	end

	local auraState  = self.FramedAuraState
	local classified = auraState and auraState:GetHarmfulClassified()

	local displayed = 0
	local runOffset = 0

	if(classified) then
		-- Dispatch filter mode to a single flag key (nil = match all).
		-- encounter mode uses the same flag as raid — the IsEncounterInProgress
		-- gate above already short-circuits the no-encounter case.
		local flagKey
		if(filterMode == 'raid' or filterMode == 'encounter') then flagKey = 'isRaid'
		elseif(filterMode == 'important')   then flagKey = 'isImportant'
		elseif(filterMode == 'dispellable') then flagKey = 'isRaidDispellable'
		elseif(filterMode == 'raidCombat')  then flagKey = 'isRaidInCombat'
		end

		for _, entry in next, classified do
			if(displayed >= maxDisplayed) then break end

			local flags = entry.flags
			if(not flagKey or flags[flagKey]) then
				local auraData = entry.aura
				local dur = auraData.duration
				local skip = F.IsValueNonSecret(dur) and (dur == 0 or dur >= 600)
				if(not skip) then
					displayed = displayed + 1
					runOffset = displayAura(self, unit, pool, displayed, runOffset, cfg, auraData, auraData.dispelName)
				end
			end
		end

		-- Dispellable supplementary pass: RAID_PLAYER_DISPELLABLE excludes
		-- Physical/bleeds, so iterate raid-flagged entries and include any
		-- whose dispelName is nil/empty/Physical. Pass nil dispelType — these
		-- aren't dispellable, no overlay color.
		if(filterMode == 'dispellable' and displayed < maxDisplayed) then
			for _, entry in next, classified do
				if(displayed >= maxDisplayed) then break end

				local flags = entry.flags
				if(flags.isRaid) then
					local auraData = entry.aura
					local dn = auraData.dispelName
					local isPhysical = F.IsValueNonSecret(dn) and (not dn or dn == '' or dn == 'Physical')
					if(isPhysical) then
						displayed = displayed + 1
						runOffset = displayAura(self, unit, pool, displayed, runOffset, cfg, auraData, nil)
					end
				end
			end
		end
	else
		-- Vestigial no-AuraState fallback. Every aura-tracking frame creates
		-- AuraState via the idempotent Setup guard — preserved to match the
		-- element-level pattern used across Auras/.
		local filter = FILTER_MAP[filterMode] or 'HARMFUL'
		local rawAuras = F.AuraCache.GetUnitAuras(unit, filter)

		for _, auraData in next, rawAuras do
			if(displayed >= maxDisplayed) then break end

			local dur = auraData.duration
			local skip = F.IsValueNonSecret(dur) and (dur == 0 or dur >= 600)

			if(not skip) then
				displayed = displayed + 1
				runOffset = displayAura(self, unit, pool, displayed, runOffset, cfg, auraData, auraData.dispelName)
			end
		end

		if(filterMode == 'dispellable' and displayed < maxDisplayed) then
			local raidAuras = F.AuraCache.GetUnitAuras(unit, 'HARMFUL|RAID')
			for _, auraData in next, raidAuras do
				if(displayed >= maxDisplayed) then break end

				local dn = auraData.dispelName
				local isPhysical = F.IsValueNonSecret(dn) and (not dn or dn == '' or dn == 'Physical')
				if(isPhysical) then
					displayed = displayed + 1
					runOffset = displayAura(self, unit, pool, displayed, runOffset, cfg, auraData, nil)
				end
			end
		end
	end

	-- Hide pool entries beyond active count
	for idx = displayed + 1, #pool do
		pool[idx]:Clear()
	end
end
```

- [ ] **Step 3: Syntax check**

Run: `luac -p Elements/Auras/Debuffs.lua` if luac is available. Otherwise visually confirm:
- `if(classified) then ... else ... end` block is balanced
- Both branches close with `end` before the `-- Hide pool entries` trailing loop
- No duplicate `local pool = ind._pool` (moved to the top)
- `flagKey` lookup uses `elseif` chain (not `elif` or `else if`)

- [ ] **Step 4: Grep for orphaned GetHarmful(filter) calls**

Run: `Grep -n "GetHarmful(" Elements/Auras/Debuffs.lua`
Expected: zero matches (all replaced with classified path or removed; the fallback uses `F.AuraCache.GetUnitAuras`).

Run: `Grep -n "FILTER_MAP" Elements/Auras/Debuffs.lua`
Expected: two matches — the table definition at line 13 and the fallback lookup inside the `else` branch. If >2, there's a stale classified-path reference; revisit.

- [ ] **Step 5: Confirm preserved invariants via grep**

Run: `Grep -n "bigIconSize\|isBossAura" Elements/Auras/Debuffs.lua`
Expected: the existing `displayAura` references (lines ~29, ~51) — unchanged.

Run: `Grep -n "dispelName" Elements/Auras/Debuffs.lua`
Expected: three matches — primary render pass, double-pass Physical check, and `displayAura`'s `dispelType` parameter pass-through to `BorderIcon:SetAura`.

- [ ] **Step 6: Commit**

```bash
git add Elements/Auras/Debuffs.lua
git commit -m "$(cat <<'EOF'
feat(debuffs): migrate to AuraState classified API (B4 #140)

Replace per-indicator GetHarmful(filterString) + server-filter fetch
with a single GetHarmfulClassified() iteration dispatched via a
flagKey lookup. Filter modes map:

  all          → no flag predicate
  raid         → flags.isRaid
  important    → flags.isImportant
  dispellable  → flags.isRaidDispellable
  raidCombat   → flags.isRaidInCombat
  encounter    → flags.isRaid (gated on IsEncounterInProgress)

Dispellable + Physical/bleed double-pass becomes a second loop over
the same classified list, filtering on flags.isRaid + isPhysical
dispelName check — same behavior, no extra fetch.

Boss bigIconSize, long-duration skip, dispel-type coloring, red
border, per-indicator architecture all preserved.

Vestigial no-AuraState fallback keeps the original server-filter
path for consistency with B1/B2.

Part of #115 UNIT_AURA fan-out rearchitecture.
EOF
)"
```

- [ ] **Step 7: Push to working-testing**

```bash
git push origin working-testing
```

Per `feedback_commit_after_task`: push after each task to prevent crash data loss.

---

## Task 3: Live smoke test in LFR

Framed has no automated test harness; verification is in-game per `feedback_coding_standards` and the spec's "Testing Strategy" section.

**Files:** None.

- [ ] **Step 1: /reload in WoW**

The addon folder is a symlink (per `feedback_wow_sync`), so edits to `Core/AuraState.lua` and `Elements/Auras/Debuffs.lua` are already live. `/reload` to pick them up.

- [ ] **Step 2: Verify new flags via `/framed aurastate target`**

Target a raid member with a harmful debuff (any dungeon trash target works). Run `/framed aurastate target`. Confirm the HARMFUL section's printed flags for each aura include the new entries (`isRaidDispellable`, `isRaidInCombat`) when applicable. Flag names appear as the raw camelCase Lua keys per the handler's dynamic `formatFlags` loop.

If neither appears in the output and you know the target has a dispellable debuff, the Task 1 flag addition didn't land — revisit.

- [ ] **Step 3: `all` filter mode**

Configure one Debuffs indicator with `filterMode = 'all'` (this is the default). Target a dummy with several debuffs applied. **Expected:** every debuff renders, respecting `maxDisplayed`, sorted by Blizzard's default harmful order. Long-duration debuffs (if any) are skipped.

- [ ] **Step 4: `raid` filter mode**

Configure an indicator with `filterMode = 'raid'`. In LFR during a pull, confirm only raid-flagged debuffs render (boss mechanics, DoTs cast by bosses on raid members). Trivial self-inflicted debuffs (e.g. hunger, class-internal markers) should NOT appear.

- [ ] **Step 5: `important` filter mode**

Configure an indicator with `filterMode = 'important'`. During an encounter, confirm only debuffs Blizzard flags IMPORTANT render — typically stuns, silences, and mechanics that require reaction.

- [ ] **Step 6: `dispellable` filter mode + Physical/bleed double-pass**

Configure an indicator with `filterMode = 'dispellable'`. As a healer or dispel-capable class in LFR, confirm:
- Magic / Curse / Poison / Disease debuffs render (if dispellable by your class/spec)
- Physical/bleed debuffs also render after the dispellable set (no dispel-color overlay — `dispelType` is nil for these)
- Red border on all debuffs regardless of dispel type

If only dispellable debuffs render and no physical/bleeds: the double-pass didn't fire. Check Step 2's `/framed aurastate` output to confirm `raid` flag appears on Physical debuffs.

- [ ] **Step 7: `raidCombat` filter mode**

Configure an indicator with `filterMode = 'raidCombat'`. Enter combat and confirm raid-important-in-combat debuffs render. Out of combat, the indicator should empty out.

- [ ] **Step 8: `encounter` filter mode**

Configure an indicator with `filterMode = 'encounter'`. Before a boss pull, confirm the indicator is empty. Start the encounter — raid-flagged debuffs render. Encounter ends — indicator clears. This exercises both the `IsEncounterInProgress` gate and the `flags.isRaid` match.

- [ ] **Step 9: Boss bigIconSize**

During an encounter where a boss aura is applied (any LFR boss with a boss-flagged mechanic), confirm that boss auras render at `cfg.bigIconSize` (visually larger than other icons). The running pixel offset advances by the bigger size for that slot; subsequent icons don't overlap.

- [ ] **Step 10: Dispel-type coloring**

Confirm that Magic debuffs show the magic-colored overlay, Curses the curse-colored overlay, etc. This verifies `auraData.dispelName` is still passed to `BorderIcon:SetAura` (and the color curve infrastructure we use for dispel coloring still runs).

If all debuffs appear without a dispel-color overlay: the `displayAura` call is passing `nil` where it should pass `auraData.dispelName`. Revisit Task 2's primary render pass.

- [ ] **Step 11: Combat churn — 5-man or raid pull**

Run a full LFR pull with multiple debuffs cycling. Watch for:
- No Lua errors in `/etrace` or BugSack
- Icons appear/disappear cleanly as debuffs come and go
- No orphaned icons after debuffs expire
- No flicker during UNIT_AURA bursts

- [ ] **Step 12: Report findings to user**

Post a brief summary confirming each filter mode renders correctly, boss sizing works, dispel-type coloring is preserved, and no regressions observed in a combat session.

If any step reveals a regression, STOP, do not proceed to Task 4, and consult the user. Per `feedback_aura_indicators_fragile`: indicator rendering is fragile and easy to break; any visual regression must be investigated, not papered over.

---

## Task 4: Create PR (working-testing → working)

Follows the same pattern used for B1 (PR #150) and B2 (PR #147). Per `project_framed_worktree`: working-testing → working for dev promotion; the release cut (TOC bump + CHANGELOG entry + working → main) comes later when multiple B-migrations batch into a single version.

**Files:** None.

- [ ] **Step 1: Confirm branch is pushed and clean**

```bash
git status
```
Expected: `On branch working-testing`, `nothing to commit, working tree clean`, `Your branch is up to date with 'origin/working-testing'`.

If not up to date, push before creating the PR.

- [ ] **Step 2: Create the PR**

```bash
gh pr create --base working --head working-testing \
  --title "B4 — migrate Debuffs to AuraState classified API (#140)" \
  --body "$(cat <<'EOF'
## Summary
- **B4 Debuffs migrated to classified API** (#115, #140) — `updateIndicator` now iterates `auraState:GetHarmfulClassified()` once per indicator and dispatches filter modes via a single `flagKey` lookup. Eliminates the per-indicator `GetHarmful(filterString)` fetch + the dispellable double-pass's separate `HARMFUL|RAID` fetch.
- **AuraState extension** — `classify()` gains two harmful-only flags: `isRaidDispellable` (HARMFUL|RAID_PLAYER_DISPELLABLE) and `isRaidInCombat` (HARMFUL|RAID_IN_COMBAT). Mirrors the helpful-side `isBigDefensive` short-circuit pattern; helpful classify() unchanged.
- Behavior preserved: boss bigIconSize, long-duration skip, dispel-type coloring, red border, dispellable + Physical/bleed double-pass, per-indicator architecture.

## Test plan
- [x] `/framed aurastate target` prints `isRaidDispellable` / `isRaidInCombat` flags for harmful auras
- [x] `all` mode — all debuffs render, long-duration skip preserved
- [x] `raid` mode — raid-flagged debuffs only
- [x] `important` mode — IMPORTANT-flagged debuffs only
- [x] `dispellable` mode — dispellable debuffs plus Physical/bleed double-pass
- [x] `raidCombat` mode — raid-in-combat debuffs only
- [x] `encounter` mode — `IsEncounterInProgress` gate works, raid-flagged debuffs render during encounter
- [x] Boss bigIconSize renders during encounter boss auras
- [x] Dispel-type color overlay preserved (magic / curse / poison / disease / bleed)
- [x] No Lua errors during LFR combat churn

## Follow-ups
- B3 Buffs (#139) — castBy flag still needs design (harmful + helpful `isFromPlayerOrPet` may not be a 1:1 substitute)
- B5 MissingBuffs (#141) — trickier because it's an inverse filter
- Release cut bundling B1+B2+B4 (and possibly B3/B5) into the next alpha version

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Report PR URL to user**

Hand back to the user for review + merge. Do not attempt to merge yourself.

---

## Rollback strategy

If B4 introduces a regression that needs urgent revert:

1. `git revert` the Task 2 commit (Debuffs migration) — removes the classified-path consumer.
2. Optionally `git revert` the Task 1 commit (AuraState flags) — the new flags are inert if no consumer reads them, so leaving them in place is safe and they'll be reused by future work.
3. Other B-series elements (B1 Externals, B2 Defensives) are unaffected — they read different helpful-side flags.

AuraState's API surface remains append-only after rollback. No cache or saved-variable migration required.

---

## Self-review (completed before plan ships)

- **Spec coverage:** #140 covers migrating Debuffs.lua + harmful-side classification extension. Task 1 adds the flags; Task 2 migrates the element; Task 3 smoke-tests all 6 filter modes + the preserved behaviors called out in the issue. ✓
- **Placeholder scan:** No TBD / TODO / vague "handle edge cases" — every step has concrete code or concrete commands. ✓
- **Type consistency:** Flag names match across Task 1 definition (`isRaidDispellable` / `isRaidInCombat`) and Task 2 dispatch (`flags.isRaidDispellable` / `flags.isRaidInCombat`). `flagKey` values are string literals matching the flag names. `FILTER_MAP` keys match `filterMode` check branches. ✓
- **Fallback parity:** No-AuraState branch uses `F.AuraCache.GetUnitAuras(unit, filter)` with the original `FILTER_MAP` string — same as pre-B4 behavior. ✓
