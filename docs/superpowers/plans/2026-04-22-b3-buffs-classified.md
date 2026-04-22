# B3 — Buffs Classified Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `Elements/Auras/Buffs.lua` from `auraState:GetHelpful(filterString)` to `auraState:GetHelpfulClassified()`, preserving the #113 secret-sourceUnit castBy fix exactly, without any semantic change to `passesCastByFilter`.

**Architecture:** Two-path iteration (classified / raw fallback) mirroring B1/B2/B4. When the effective server filter would be `HELPFUL|RAID_IN_COMBAT` (no indicator has a spell list), the classified loop gates entries on `flags.isRaidInCombat` so track-all indicators don't suddenly see cosmetic/consumable/world buffs. `passesCastByFilter` is unchanged — it reads `entry.aura.sourceUnit` the same way it used to read `auraData.sourceUnit`. A1 extension: `isRaidInCombat` becomes `prefix`-based (both helpful and harmful) instead of harmful-only; `RAID_IN_COMBAT` is a symmetric Blizzard modifier, so widening the gate costs one extra probe per helpful classify and unlocks the Buffs narrow-filter path.

**Tech Stack:** Lua 5.1, oUF, `F.AuraState.GetHelpfulClassified`, `F.IsValueNonSecret`, existing `passesCastByFilter` helper.

---

## Context

### Current aura-fetch shape (pre-B3)

```lua
local filter = element._buffFilter  -- 'HELPFUL' or 'HELPFUL|RAID_IN_COMBAT'
local auras = auraState and auraState:GetHelpful(filter) or F.AuraCache.GetUnitAuras(unit, filter)
for _, auraData in next, auras do
    local spellId = auraData.spellId
    if(F.IsValueNonSecret(spellId)) then
        local sourceUnit = auraData.sourceUnit
        -- check spellLookup[spellId] + hasTrackAll
        -- passesCastByFilter(sourceUnit, ind._castBy)
        -- annotate + push to pool / first-match
    end
end
```

### `computeBuffFilter` semantics (preserved)

```lua
local function computeBuffFilter(indicatorConfigs)
    for _, ind in next, indicatorConfigs do
        if(ind.enabled ~= false and ind.spells and #ind.spells > 0) then
            return 'HELPFUL'
        end
    end
    return 'HELPFUL|RAID_IN_COMBAT'
end
```

**Key property:** if *any* enabled indicator has a spell list, the filter widens to `HELPFUL` **globally** — which means track-all indicators in mixed configs also see cosmetic/world/consumable buffs (the existing trade-off for making tracked spells visible). B3 must preserve this exact behavior.

### Narrow-filter gating in classified path

Pre-B3, `GetHelpful('HELPFUL|RAID_IN_COMBAT')` returned only server-filtered auras. Post-B3, `GetHelpfulClassified()` returns **all** helpful auras on the unit. To preserve narrow-mode semantics without a regression:

```lua
local narrowFilter = element._buffFilter == 'HELPFUL|RAID_IN_COMBAT'
for _, entry in next, classified do
    local flags = entry.flags
    if(not narrowFilter or flags.isRaidInCombat) then
        local auraData = entry.aura
        -- ...existing spell-match + castBy logic, unchanged
    end
end
```

This keeps flasks / food / racial / cosmetic buffs out of track-all indicators when no spell list is configured — matching Blizzard's server-side behavior.

### Why `isRaidInCombat` must be relaxed to both sides

B4 introduced `isRaidInCombat` as a harmful-only probe (`not isHelpful and ... or false`). `RAID_IN_COMBAT` is a symmetric Blizzard filter modifier — `HELPFUL|RAID_IN_COMBAT` is a real, queryable filter (Buffs already uses it as the narrow default). So B3's Task 1 relaxes the gate to match `isExternalDefensive` / `isImportant` / `isPlayerCast`:

```lua
flags.isRaidInCombat = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|RAID_IN_COMBAT') == false
```

Cost: one extra probe per helpful classify. B4 Debuffs' use (`flags.isRaidInCombat` for the `raidCombat` filter mode) is unaffected — harmful auras still get `HARMFUL|RAID_IN_COMBAT` probed and the result is unchanged. `isRaidDispellable` stays harmful-only (`RAID_PLAYER_DISPELLABLE` is semantically harmful-only — dispelling applies to debuffs).

### castBy semantics — pure migration, no refinement

Issue #139 calls out that `isFromPlayerOrPet` is available as a first-class flag and could inform the secret-sourceUnit fallback, but **also explicitly warns against using it as a direct `castBy='me'` proxy** (it's "any player or pet on your side", including every raid member's pets). The safer B3 scope is:

- **In B3:** keep `passesCastByFilter` byte-identical. Read `sourceUnit` from `entry.aura.sourceUnit` (same location as pre-B3's `auraData.sourceUnit`). The #113 fix survives unchanged because the function body doesn't change.
- **Defer** any refinement that tightens the secret-source fallback using `isFromPlayerOrPet`. That's a behavior change, not a migration — belongs in a follow-up issue so it can be evaluated on its own merits.

PR body should flag this as follow-up.

### Annotation pattern (unchanged, called out for safety)

The current code mutates `auraData` in place with `auraData.unit`, `auraData.stacks`, `auraData.dispelType` to satisfy renderer expectations. In the classified path, `entry.aura` **is** the same `auraData` reference as before (AuraState's classified store wraps the same AuraCache-owned auraData). Annotations still stick to the shared reference. This is a pre-existing hazard (not introduced by B3) — flag but don't fix in this PR.

### Fallback path (no AuraState)

Vestigial but preserved, matching B1/B2/B4. When `self.FramedAuraState` is nil, the element falls through to `F.AuraCache.GetUnitAuras(unit, element._buffFilter)` with the original server filter string. All downstream logic — spell-lookup, castBy, annotation, dispatch — stays verbatim in the fallback branch.

---

## File Structure

- **Modify:** `Core/AuraState.lua` — relax `isRaidInCombat` gate from `not isHelpful` to `prefix`-based.
- **Modify:** `Elements/Auras/Buffs.lua` — replace the aura-fetch + inner loop with two-path (classified / fallback). `passesCastByFilter`, `computeBuffFilter`, renderer dispatch, annotation, spell-priority sort all unchanged.

No new files. No changes to renderers, `Rebuild`, `Setup`, or any of the renderer-creation helpers.

---

## Task 1: Relax `isRaidInCombat` gate to both helpful and harmful

**Files:**
- Modify: `Core/AuraState.lua` — the `flags.isRaidInCombat` line (currently lines 39-41)

- [ ] **Step 1: Read the current classify() to confirm line positions**

Read `Core/AuraState.lua:30-42`. Confirm the existing block still has `isRaidInCombat` as the last flag, gated with `not isHelpful and ... or false`. If the file drifted, re-read before editing.

- [ ] **Step 2: Replace the harmful-only gate with prefix-based probe**

Replace:

```lua
	flags.isRaidInCombat      = not isHelpful
	                            and IsAuraFilteredOutByInstanceID(unit, id, 'HARMFUL|RAID_IN_COMBAT') == false
	                            or false
```

With:

```lua
	flags.isRaidInCombat      = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|RAID_IN_COMBAT') == false
```

Leave `isRaidDispellable` alone — `RAID_PLAYER_DISPELLABLE` is harmful-only semantically.

- [ ] **Step 3: Verify the edit landed correctly**

Run: `Grep -n "isRaidInCombat\|isRaidDispellable" Core/AuraState.lua`
Expected:
```
36:	flags.isRaidDispellable   = not isHelpful
37:	                            and IsAuraFilteredOutByInstanceID(unit, id, 'HARMFUL|RAID_PLAYER_DISPELLABLE') == false
38:	                            or false
39:	flags.isRaidInCombat      = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|RAID_IN_COMBAT') == false
```

`isRaidDispellable` stays harmful-gated. `isRaidInCombat` becomes a single-line prefix-based probe.

- [ ] **Step 4: Confirm Debuffs' `raidCombat` filter is unaffected**

Run: `Grep -n "isRaidInCombat" Elements/Auras/Debuffs.lua`
Expected: one match at the `flagKey = 'isRaidInCombat'` dispatch line inside `updateIndicator`. Harmful auras still get `HARMFUL|RAID_IN_COMBAT` probed; the flag result is identical to pre-Task-1.

- [ ] **Step 5: Commit**

```bash
git add Core/AuraState.lua
git commit -m "$(cat <<'EOF'
refactor(aurastate): widen isRaidInCombat to both helpful and harmful

RAID_IN_COMBAT is a symmetric Blizzard filter modifier — both
HELPFUL|RAID_IN_COMBAT and HARMFUL|RAID_IN_COMBAT are real filters.
Prior harmful-only gate was B4-scoped; widening unlocks B3 Buffs,
which uses HELPFUL|RAID_IN_COMBAT as its narrow default filter.

isRaidDispellable stays harmful-only — RAID_PLAYER_DISPELLABLE is
semantically harmful-only (dispelling applies to debuffs).

Debuffs' raidCombat filter mode is unaffected — harmful auras still
probe HARMFUL|RAID_IN_COMBAT and return identical results.

Cost: one additional filter probe per helpful classify. Amortized
across all helpful-side consumers (first one being B3 Buffs).

Part of #115 UNIT_AURA fan-out rearchitecture (#139 prep).
EOF
)"
```

---

## Task 2: Migrate `Elements/Auras/Buffs.lua` Update loop to classified path

**Files:**
- Modify: `Elements/Auras/Buffs.lua:128-211` (the aura-fetch + per-aura inner loop)

- [ ] **Step 1: Read the current Update to confirm line ranges**

Read `Elements/Auras/Buffs.lua:128-211`. Confirm:
- `auraState` setup at lines 152-159 (UNIT_AURA / fullrefresh branch)
- Filter + fetch at lines 160-161
- Per-aura loop at lines 162-211 with spell-specific then track-all indicator matching

If any ranges drifted, re-read before editing.

- [ ] **Step 2: Replace the fetch + loop block with two-path classified / fallback**

The existing block (lines 152-211):

```lua
	local auraState = self.FramedAuraState
	if(auraState) then
		if(event == 'UNIT_AURA') then
			auraState:ApplyUpdateInfo(unit, updateInfo)
		else
			auraState:EnsureInitialized(unit)
		end
	end
	local filter = element._buffFilter
	local auras = auraState and auraState:GetHelpful(filter) or F.AuraCache.GetUnitAuras(unit, filter)
	for _, auraData in next, auras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local sourceUnit = auraData.sourceUnit
			local annotated = false

			-- Check spell-specific indicators
			local indicatorIndices = spellLookup[spellId]
			if(indicatorIndices) then
				for _, idx in next, indicatorIndices do
					local ind = indicators[idx]
					if(passesCastByFilter(sourceUnit, ind._castBy)) then
						-- Annotate auraData with renderer-expected field names
						-- (non-conflicting keys: auraData has no .stacks/.dispelType/.unit)
						if(not annotated) then
							auraData.unit      = unit
							auraData.stacks    = auraData.applications
							auraData.dispelType = auraData.dispelName
							annotated = true
						end
						if(ind._type == C.IndicatorType.ICONS or ind._type == C.IndicatorType.BARS) then
							local list = iconsAurasPool[idx]
							list[#list + 1] = auraData
						elseif(not matchedPool[idx]) then
							matchedPool[idx] = auraData
						end
					end
				end
			end

			-- Check track-all indicators (empty spells list)
			for _, idx in next, hasTrackAll do
				local ind = indicators[idx]
				if(passesCastByFilter(sourceUnit, ind._castBy)) then
					if(not annotated) then
						auraData.unit      = unit
						auraData.stacks    = auraData.applications
						auraData.dispelType = auraData.dispelName
						annotated = true
					end
					if(ind._type == C.IndicatorType.ICONS or ind._type == C.IndicatorType.BARS) then
						local list = iconsAurasPool[idx]
						list[#list + 1] = auraData
					elseif(not matchedPool[idx]) then
						matchedPool[idx] = auraData
					end
				end
			end
		end
	end
```

Replace with:

```lua
	local auraState = self.FramedAuraState
	if(auraState) then
		if(event == 'UNIT_AURA') then
			auraState:ApplyUpdateInfo(unit, updateInfo)
		else
			auraState:EnsureInitialized(unit)
		end
	end

	local classified   = auraState and auraState:GetHelpfulClassified()
	local buffFilter   = element._buffFilter
	local narrowFilter = buffFilter == 'HELPFUL|RAID_IN_COMBAT'

	-- Inner loop helper: match one auraData against all indicators and
	-- push into the appropriate pool. Factored out so classified and
	-- fallback paths share the same matching logic byte-for-byte.
	local function matchAura(auraData)
		local spellId = auraData.spellId
		if(not F.IsValueNonSecret(spellId)) then return end

		local sourceUnit = auraData.sourceUnit
		local annotated = false

		-- Check spell-specific indicators
		local indicatorIndices = spellLookup[spellId]
		if(indicatorIndices) then
			for _, idx in next, indicatorIndices do
				local ind = indicators[idx]
				if(passesCastByFilter(sourceUnit, ind._castBy)) then
					if(not annotated) then
						auraData.unit      = unit
						auraData.stacks    = auraData.applications
						auraData.dispelType = auraData.dispelName
						annotated = true
					end
					if(ind._type == C.IndicatorType.ICONS or ind._type == C.IndicatorType.BARS) then
						local list = iconsAurasPool[idx]
						list[#list + 1] = auraData
					elseif(not matchedPool[idx]) then
						matchedPool[idx] = auraData
					end
				end
			end
		end

		-- Check track-all indicators (empty spells list)
		for _, idx in next, hasTrackAll do
			local ind = indicators[idx]
			if(passesCastByFilter(sourceUnit, ind._castBy)) then
				if(not annotated) then
					auraData.unit      = unit
					auraData.stacks    = auraData.applications
					auraData.dispelType = auraData.dispelName
					annotated = true
				end
				if(ind._type == C.IndicatorType.ICONS or ind._type == C.IndicatorType.BARS) then
					local list = iconsAurasPool[idx]
					list[#list + 1] = auraData
				elseif(not matchedPool[idx]) then
					matchedPool[idx] = auraData
				end
			end
		end
	end

	if(classified) then
		for _, entry in next, classified do
			local flags = entry.flags
			if(not narrowFilter or flags.isRaidInCombat) then
				matchAura(entry.aura)
			end
		end
	else
		-- Vestigial no-AuraState fallback. Every aura-tracking frame creates
		-- AuraState via the idempotent Setup guard — preserved to match the
		-- element-level pattern used across Auras/.
		local auras = F.AuraCache.GetUnitAuras(unit, buffFilter)
		for _, auraData in next, auras do
			matchAura(auraData)
		end
	end
```

**Note on `matchAura` closure cost:** one closure allocation per Update per frame. This is fine at runtime — the alternative (inlining both paths) would duplicate ~40 lines of matching logic and be a maintenance hazard. If profiling later shows the closure as a hotspot, hoist it to a module-local function that takes the captured state as explicit parameters (`matchAura(auraData, unit, indicators, spellLookup, hasTrackAll, iconsAurasPool, matchedPool)`). Not worth doing preemptively.

- [ ] **Step 3: Syntax check**

Run: `luac -p Elements/Auras/Buffs.lua` if available. Otherwise visually scan the edited region:
- `local function matchAura(auraData)` opens; closes before the `if(classified)` block
- `if(classified) then ... else ... end` balanced
- `narrowFilter` local declared once near the top
- No stray duplicate `local auras = ...` outside the fallback branch

- [ ] **Step 4: Grep for stale `GetHelpful(` calls**

Run: `Grep -n "GetHelpful(" Elements/Auras/Buffs.lua`
Expected: zero matches. The classified path uses `GetHelpfulClassified()`; fallback uses `F.AuraCache.GetUnitAuras`.

Run: `Grep -n "computeBuffFilter\|_buffFilter" Elements/Auras/Buffs.lua`
Expected: `computeBuffFilter` definition + two call sites (Rebuild + Setup); `_buffFilter` stored on the element in Rebuild + Setup + read in Update's `buffFilter` local. Unchanged count relative to pre-B3.

- [ ] **Step 5: Confirm `passesCastByFilter` was not touched**

Run: `Grep -n "function passesCastByFilter" Elements/Auras/Buffs.lua`
Expected: exactly one match — the existing definition. Body bytes identical to pre-B3. This is the #113 fix; must not regress.

Run: `Grep -n "passesCastByFilter(" Elements/Auras/Buffs.lua`
Expected: two call sites (spell-specific + track-all), both inside `matchAura`.

- [ ] **Step 6: Commit**

```bash
git add Elements/Auras/Buffs.lua
git commit -m "$(cat <<'EOF'
feat(buffs): migrate to AuraState classified API (B3 #139)

Replace auraState:GetHelpful(filterString) fetch with
GetHelpfulClassified() + narrow-filter gating on flags.isRaidInCombat
when the effective filter would be HELPFUL|RAID_IN_COMBAT.

Preserves:
  - passesCastByFilter byte-identical (the #113 secret-sourceUnit fix)
  - computeBuffFilter global widening semantics (any spell-list
    indicator widens the whole element to HELPFUL)
  - Annotation pattern (auraData.unit / .stacks / .dispelType)
  - Per-indicator spell priority sort, renderer dispatch (7 types),
    spell-lookup + track-all matching
  - Vestigial no-AuraState fallback

Matching logic factored into a local matchAura helper so classified
and fallback paths share it. No behavior change relative to pre-B3
for any castBy / filter / indicator combination.

Follow-up (not in this PR): evaluate refining the secret-sourceUnit
fallback with flags.isFromPlayerOrPet for castBy='me'. Deferred
because it's a behavior change, not a migration.

Part of #115 UNIT_AURA fan-out rearchitecture.
EOF
)"
```

- [ ] **Step 7: Push to working-testing**

```bash
git push origin working-testing
```

---

## Task 3: Live smoke test — castBy matrix in LFR

Buffs is the riskiest B-migration per #139. Test matrix must cover `castBy` × indicator-config × combat-state, with explicit attention to the #113 secret-sourceUnit regression mode.

**Files:** None.

- [ ] **Step 1: /reload in WoW**

The addon folder is a symlink — edits to `Core/AuraState.lua` and `Elements/Auras/Buffs.lua` are already live. `/reload` to pick them up.

- [ ] **Step 2: Sanity-check classified output**

Run `/framed aurastate player` out of combat. Confirm helpful auras print `isRaidInCombat` in the flag list where appropriate (e.g., in-combat raid buffs should show it; flasks/racials should not). The flag is now present on helpful entries — earlier B4 builds only had it on harmful.

- [ ] **Step 3: `castBy = 'me'` without spell list, in combat**

Configure a Buffs indicator: `castBy = 'me'`, no `spells` list (track-all). Pull a mob and confirm your self-cast HoTs / shields / class buffs appear on your own frame during combat. The #113 regression would manifest as NOTHING showing up (secret sourceUnit → all auras silently filtered).

**If nothing shows up:** `passesCastByFilter`'s secret-source over-match broke. Revert immediately and file a regression issue.

- [ ] **Step 4: `castBy = 'me'` with spell list, in combat**

Configure an indicator with specific tracked self-cast spells (e.g., your own HoT spellIDs). In combat, confirm tracked spells render. Because the filter widens to `HELPFUL` when any spell list is present, this indicator reaches the classified loop with `narrowFilter = false` — every helpful aura is considered, then spell-list matching narrows.

- [ ] **Step 5: `castBy = 'me'` with spell list, out of combat**

Cast a tracked spell on yourself out of combat. Confirm it renders. (This is the baseline sanity — sourceUnit is non-secret out of combat, so the fast path works.)

- [ ] **Step 6: `castBy = 'others'` with spell list**

Configure an indicator tracking a specific follower/party HoT (e.g., a druid's Rejuvenation spellID). Have a party member cast it on you out of combat — confirm it renders. Then pull, and confirm it continues to render in combat even when sourceUnit may be secret (the over-match in `passesCastByFilter` should still match 'others').

- [ ] **Step 7: `castBy = 'others'` without spell list**

Configure a track-all indicator with `castBy = 'others'`. Out of combat in a group, confirm party-applied buffs render (e.g., Fortitude, Arcane Intellect, follower HoTs). In combat — same set should render (with over-match on secret sources).

- [ ] **Step 8: `castBy = 'anyone'` / `'all'`**

Configure a track-all indicator with `castBy = 'anyone'` (or the legacy `'all'`). Confirm every raid-in-combat buff shows up when the indicator is the only one in the config (`narrowFilter = true`, flag-gated), and confirm cosmetic/flask buffs **don't** appear out of combat.

Then add a second indicator with a spell list (e.g., your class's tracked spell). Reload. Now `narrowFilter = false` — confirm track-all indicator starts showing cosmetic/flask buffs (this is the documented widening trade-off). If it doesn't, the filter-widening semantics regressed.

- [ ] **Step 9: Narrow-filter correctness — flasks / food / racials**

With a track-all indicator and NO spell-list indicator in the config, out of combat: confirm flasks / food buffs / racial buffs do NOT render. This exercises `narrowFilter = true` + `flags.isRaidInCombat = false`.

If flasks appear here: the narrow-filter gate is misbehaving. Debug via `/framed aurastate player` — confirm the flask aura's `isRaidInCombat` flag is false.

- [ ] **Step 10: Renderer dispatch — one of each type**

Configure indicators with different renderer types and confirm each renders:
- `ICON` — a single tracked spell
- `ICONS` — a track-all list with multiple auras sorted by priority
- `BAR` — a duration-driven bar for a tracked spell
- `BARS` — multi-bar list
- `BORDER` — a border-glow indicator tied to a spell
- `RECTANGLE` — a color block
- `OVERLAY` — a health overlay

Verify glows/colors/stacks/durations all look correct. No renderer-dispatch code changed in B3, but this confirms no downstream integration got disturbed by the loop rewrite.

- [ ] **Step 11: Combat churn — full LFR pull**

Run a full LFR pull. Watch BugSack / `/etrace` for Lua errors. Confirm:
- Icons / bars appear and disappear cleanly as auras cycle
- No flicker during UNIT_AURA bursts
- Priority sort holds (spell-list indicators stay in configured order)
- No orphaned renderers after buff drop-offs

- [ ] **Step 12: Report findings**

Post a brief summary covering each matrix cell (`me` / `others` / `anyone` × with/without spells × in/out of combat), narrow-filter correctness, and renderer types verified. Specifically call out: did the #113 secret-sourceUnit scenario still work (self-cast visibility in combat)?

If ANY cell regresses, STOP and consult before Task 4. Per `feedback_aura_indicators_fragile` — don't paper over regressions.

---

## Task 4: Create PR (working-testing → working)

Same pattern as B1 (#150), B2 (#147), B4 (#151).

**Files:** None.

- [ ] **Step 1: Confirm branch state**

```bash
git status
```
Expected: `On branch working-testing`, clean tree, up-to-date with origin.

- [ ] **Step 2: Create the PR**

```bash
gh pr create --base working --head working-testing \
  --title "B3 — migrate Buffs to AuraState classified API (#139)" \
  --body "$(cat <<'EOF'
## Summary
- **B3 Buffs migrated to classified API** (#115, #139) — `Update` now iterates `auraState:GetHelpfulClassified()` with narrow-filter gating on `flags.isRaidInCombat` when the effective filter would be `HELPFUL|RAID_IN_COMBAT`. Per-aura spell-match + castBy logic factored into a local `matchAura` helper shared by classified and fallback paths.
- **AuraState extension** — `isRaidInCombat` relaxed from harmful-only to both-sides (prefix-based probe), matching `isExternalDefensive` / `isImportant` / `isPlayerCast`. `RAID_IN_COMBAT` is a symmetric Blizzard filter modifier. `isRaidDispellable` stays harmful-only (dispelling is semantically harmful-only). B4 Debuffs' `raidCombat` mode is unaffected.
- **#113 fix preserved exactly** — `passesCastByFilter` body is byte-identical; the secret-sourceUnit over-match still protects self-cast visibility in combat.

## Preserved behavior
- `computeBuffFilter` global widening (any spell-list indicator widens element-wide to `HELPFUL`)
- Annotation pattern (`auraData.unit` / `.stacks` / `.dispelType`) — existing shared-reference hazard, not introduced by B3
- Per-indicator spell priority sort
- All 7 renderer types (`ICON` / `ICONS` / `BAR` / `BARS` / `BORDER` / `RECTANGLE` / `OVERLAY`)
- Vestigial no-AuraState fallback

## Test plan
- [x] `castBy='me'` no spell list, in combat — self-casts visible (#113 scenario)
- [x] `castBy='me'` with spell list, in+out of combat
- [x] `castBy='others'` with spell list, in+out of combat
- [x] `castBy='others'` no spell list, in group
- [x] `castBy='anyone'` narrow filter, no cosmetic leak
- [x] `castBy='anyone'` wide filter (mixed config), documented cosmetic-leak trade-off intact
- [x] Flasks / food / racials hidden under narrow filter
- [x] One of each renderer type renders correctly
- [x] LFR pull — no Lua errors, no flicker

## Follow-ups (not in this PR)
- Evaluate refining the secret-sourceUnit fallback in `passesCastByFilter` using `flags.isFromPlayerOrPet` for `castBy='me'` (can reject sources that are definitively NOT a player/pet). Deferred because it's a behavior change, not a migration.
- B5 MissingBuffs (#141) — final B-series element. Inverse filter, trickier shape.
- Release cut bundling B1+B2+B4+B3 (and possibly B5) into the next alpha.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Report PR URL to user**

Hand back for review + merge.

---

## Rollback strategy

If B3 regresses:

1. `git revert` Task 2's commit — Buffs reverts to the probe/filter-string path; #113 fix still in place (untouched).
2. Optionally `git revert` Task 1's commit — the widened `isRaidInCombat` flag is inert if no consumer reads it (B4 Debuffs' usage is harmful-side only; relaxing to both sides doesn't change harmful-side results). Safe to leave in place.
3. Other B-series migrations are unaffected.

AuraState API surface stays append-only. No saved-variable migration required.

---

## Self-review

- **Spec coverage:** #139 covers migrating Buffs.lua + preserving #113. Task 1 extends A1 for the narrow filter, Task 2 does the migration with `passesCastByFilter` untouched, Task 3 exercises the castBy matrix including the #113 regression mode, Task 4 opens the PR. ✓
- **Placeholder scan:** No TBD / TODO / vague steps. Every step has code or concrete commands. ✓
- **Type consistency:** `isRaidInCombat` spelled identically in AuraState Task 1, Buffs narrow-filter check (Task 2), and Debuffs' existing `raidCombat` dispatch. `narrowFilter` local used once per Update. `matchAura` closure captures match the variables used by its body. ✓
- **Risk handling:** The riskiest parts (castBy semantics, narrow-filter widening) are flagged as "preserved exactly" with byte-identical code paths and explicit test cells that would catch regressions. Secret-source refinement is deferred, not silently included. ✓
