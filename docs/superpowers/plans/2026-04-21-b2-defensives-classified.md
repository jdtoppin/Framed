# B2 Defensives Classified-API Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `Elements/Auras/Defensives.lua` from inline `IsAuraFilteredOutByInstanceID` probes to flag reads on AuraState's classified store. Smoke-test migration for the B-series.

**Architecture:** Replace three C-API probes per aura (BIG_DEFENSIVE, EXTERNAL_DEFENSIVE, PLAYER) with field reads on `entry.flags.*` from `auraState:GetHelpfulClassified()`. Preserve the no-AuraState fallback path for frames that don't create one (vestigial, matches existing element-level convention).

**Tech Stack:** Lua 5.1, oUF, Framed's `F.AuraState` classified API (shipped in A1 / v0.8.14-alpha).

---

## Context and References

- **Spec:** `docs/superpowers/specs/2026-04-21-unit-aura-fanout-rearchitecture-design.md`
- **A1 implementation:** `Core/AuraState.lua` — `classify()` at line 14, `GetHelpfulClassified()` at line 375
- **Current Defensives probes:** `Elements/Auras/Defensives.lua:52-56` (BIG_DEFENSIVE + EXTERNAL_DEFENSIVE), line 71 (PLAYER)
- **Issue:** #138 (B2 Defensives)
- **Parent:** #115 (UNIT_AURA fan-out rearchitecture)

## Scope note — three probes, not one

The spec's per-element table says "Single BIG_DEFENSIVE probe becomes `flags.isBigDefensive` read + `flags.isPlayerCast` for border-color distinction." The actual code has three probes: BIG_DEFENSIVE (line 52), EXTERNAL_DEFENSIVE exclusion (line 55), and PLAYER (line 71). All three map to existing flags in A1's `classify()`. The migration covers all three.

## Fallback path

When `self.FramedAuraState` is nil (no aura element on the frame has created one), the existing fallback at line 42 uses `F.AuraCache.GetUnitAuras` and raw AuraData. Keep that path using the original probe logic — the spec at line 272 calls this branch "vestigial but preserved to match the existing element-level `auraState and ... or fallback` pattern." Do not touch it.

---

## File Structure

- **Modify:** `Elements/Auras/Defensives.lua` — replace the inner loop of `Update` with a two-path pattern: classified iteration when AuraState exists, raw-AuraData iteration (current code) when it doesn't.

No new files. No changes to `Core/AuraState.lua`.

---

## Task 1: Migrate Defensives.lua Update to classified API

**Files:**
- Modify: `Elements/Auras/Defensives.lua:44-123` (the main `for _, auraData in next, rawAuras do` loop)

- [ ] **Step 1: Verify current probe positions with Grep**

Run: `Grep -n "IsAuraFilteredOutByInstanceID" Elements/Auras/Defensives.lua`
Expected output:
```
52:		local show = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
55:			local isExtDef = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
71:			local isPlayerCast = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
```

If positions differ, re-read the file before editing.

- [ ] **Step 2: Restructure the fetch + iterate block**

Replace lines 34-42 and the `for _, auraData in next, rawAuras do` loop (line 45) through `end` of that loop (line 123) with two-path iteration. Concretely:

Replace this block (lines 31-45):
```lua
	-- BIG_DEFENSIVE is a classification filter, not a query filter —
	-- GetUnitAuras does not support it. Fetch all helpful auras, then
	-- classify each one via IsAuraFilteredOutByInstanceID.
	local auraState = self.FramedAuraState
	if(auraState) then
		if(event == 'UNIT_AURA') then
			auraState:ApplyUpdateInfo(unit, updateInfo)
		else
			auraState:EnsureInitialized(unit)
		end
	end
	local rawAuras = auraState and auraState:GetHelpful('HELPFUL') or F.AuraCache.GetUnitAuras(unit, 'HELPFUL')

	local displayed = 0
	for _, auraData in next, rawAuras do
```

With:
```lua
	local auraState = self.FramedAuraState
	if(auraState) then
		if(event == 'UNIT_AURA') then
			auraState:ApplyUpdateInfo(unit, updateInfo)
		else
			auraState:EnsureInitialized(unit)
		end
	end

	local classified = auraState and auraState:GetHelpfulClassified()
	local rawAuras   = (not classified) and F.AuraCache.GetUnitAuras(unit, 'HELPFUL') or nil

	local displayed = 0

	if(classified) then
		for _, entry in next, classified do
			if(displayed >= maxDisplayed) then break end

			local auraData = entry.aura
			local flags    = entry.flags
			local id       = auraData.auraInstanceID

			-- Primary classification: BIG_DEFENSIVE, excluding EXTERNAL_DEFENSIVE
			-- (those belong in the Externals element).
			local show = flags.isBigDefensive and not flags.isExternalDefensive

			-- Skip long-duration buffs (flasks, food, racials) that aren't real
			-- defensives. duration == 0 means permanent.
			if(show) then
				local dur = auraData.duration
				if(F.IsValueNonSecret(dur) and (dur == 0 or dur >= 600)) then
					show = false
				end
			end

			if(show) then
				local isPlayerCast = flags.isPlayerCast

				if(not ((visibilityMode == 'player' and not isPlayerCast)
					or (visibilityMode == 'others' and isPlayerCast))) then
					displayed = displayed + 1
					renderEntry(self, element, pool, displayed, iconSize, cfg, orientation,
						anchorPoint, anchorX, anchorY, playerColor, otherColor,
						unit, id, auraData, isPlayerCast)
				end
			end
		end
	else
		for _, auraData in next, rawAuras do
			if(displayed >= maxDisplayed) then break end

			local id = auraData.auraInstanceID

			local show = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
				unit, id, 'HELPFUL|BIG_DEFENSIVE')
			if(show) then
				local isExtDef = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
					unit, id, 'HELPFUL|EXTERNAL_DEFENSIVE')
				if(isExtDef) then show = false end
			end

			if(show) then
				local dur = auraData.duration
				if(F.IsValueNonSecret(dur) and (dur == 0 or dur >= 600)) then
					show = false
				end
			end

			if(show) then
				local isPlayerCast = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
					unit, id, 'HELPFUL|PLAYER')

				if(not ((visibilityMode == 'player' and not isPlayerCast)
					or (visibilityMode == 'others' and isPlayerCast))) then
					displayed = displayed + 1
					renderEntry(self, element, pool, displayed, iconSize, cfg, orientation,
						anchorPoint, anchorX, anchorY, playerColor, otherColor,
						unit, id, auraData, isPlayerCast)
				end
			end
		end
	end

	for idx = displayed + 1, #pool do
		pool[idx]:Clear()
	end
end
```

And delete the original monolithic loop body (the big `if(show) then ... bi:Show()` render block that was lines 77-121 in the original) — moved into `renderEntry` below.

- [ ] **Step 3: Extract the BorderIcon render into a local `renderEntry` helper**

Add this module-local function between the `local oUF = F.oUF` block and the `Update` function (so before line 12):

```lua
-- ============================================================
-- renderEntry — acquire / position / paint a single BorderIcon slot
-- ============================================================

local function renderEntry(self, element, pool, displayed, iconSize, cfg, orientation,
	anchorPoint, anchorX, anchorY, playerColor, otherColor,
	unit, id, auraData, isPlayerCast)

	if(not pool[displayed]) then
		pool[displayed] = F.Indicators.BorderIcon.Create(self, iconSize, {
			showCooldown = true,
			showStacks   = cfg.showStacks ~= false,
			showDuration = cfg.showDuration ~= false,
			frameLevel   = cfg.frameLevel,
			stackFont    = cfg.stackFont,
			durationFont = cfg.durationFont,
		})
	end

	local bi = pool[displayed]
	bi:ClearAllPoints()
	bi:SetSize(iconSize)

	local offset = (displayed - 1) * (iconSize + 2)
	if(orientation == 'RIGHT') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX + offset, anchorY)
	elseif(orientation == 'LEFT') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX - offset, anchorY)
	elseif(orientation == 'DOWN') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY - offset)
	elseif(orientation == 'UP') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY + offset)
	end

	local borderColor = isPlayerCast and playerColor or otherColor
	if(bi.SetBorderColor) then
		bi:SetBorderColor(borderColor[1], borderColor[2], borderColor[3])
	end

	bi:SetAura(
		unit, id,
		auraData.spellId,
		auraData.icon,
		auraData.duration,
		auraData.expirationTime,
		auraData.applications,
		nil
	)
	bi:Show()
end
```

- [ ] **Step 4: Verify the file is syntactically valid**

Run: `Bash luac -p Elements/Auras/Defensives.lua` (if luac is installed locally) OR visually scan the file structure: every `function … end`, every `if … then … end`, every `for … do … end` pair closes cleanly.

If local `luac` not available, check by `Read`-ing the final file and visually verify indentation and structure.

- [ ] **Step 5: Grep for any orphaned probe calls**

Run: `Grep -n "IsAuraFilteredOutByInstanceID" Elements/Auras/Defensives.lua`
Expected: only the three probes inside the `else` (no-AuraState fallback) block — roughly 3 matches. If zero, the fallback got inadvertently removed; revisit. If >3, the happy path still has probes; revisit.

- [ ] **Step 6: Commit**

```bash
git add Elements/Auras/Defensives.lua
git commit -m "$(cat <<'EOF'
feat(defensives): migrate to AuraState classified API (B2 #138)

Replace 3 IsAuraFilteredOutByInstanceID probes per aura
(BIG_DEFENSIVE, EXTERNAL_DEFENSIVE, PLAYER) with flag reads on
entry.flags.* from auraState:GetHelpfulClassified().

The no-AuraState fallback path keeps its original probe logic —
per spec, this branch is vestigial but preserved for consistency
with the element-level pattern used across Auras/.

Render slot acquisition/positioning/painting factored into a
local renderEntry helper so both paths share it without copy-paste.

Part of #115 UNIT_AURA fan-out rearchitecture.
EOF
)"
```

---

## Task 2: Live smoke test

Framed has no automated test harness; verification is in-game per `feedback_coding_standards` and the spec's "Testing Strategy" section.

**Files:** None.

- [ ] **Step 1: /reload in WoW**

The addon folder is a symlink (per `feedback_wow_sync`), so the edited Defensives.lua is already live. `/reload` to pick it up.

- [ ] **Step 2: Verify with `/framed aurastate player`**

Cast Power Word: Shield on yourself (or similar self-buff), then run `/framed aurastate player`. Confirm the printed flags include `external-defensive` and `important` for PWS. This confirms the classified API is populated before Defensives reads it.

- [ ] **Step 3: Self-defensive test — Divine Shield / Ice Block / Cloak / Shield Wall**

Cast a personal defensive (class-appropriate):
- Paladin: Divine Shield
- Mage: Ice Block
- Rogue: Cloak of Shadows
- Warrior: Shield Wall

**Expected:** Defensive BorderIcon appears on your player frame with green (player-cast) border color. Position matches the configured anchor. Duration text displays. Icon clears when the aura expires.

**If regression:** revert Task 1's commit, re-examine the flag mapping.

- [ ] **Step 4: External-defensive exclusion**

Have a healer cast Power Word: Shield on you (or use a target dummy + offer PWS yourself). **Expected:** PWS does NOT appear in Defensives — it's classified as `isExternalDefensive` and excluded. It should appear in Externals instead.

If PWS appears in Defensives: the `not flags.isExternalDefensive` exclusion didn't fire. Check Step 2's `/framed aurastate player` output to confirm `external-defensive` is in the flag list.

- [ ] **Step 5: Visibility mode test**

Open Framed Settings → Defensives panel. Toggle `visibilityMode` through `all` / `player` / `others` and confirm:
- `all`: all BIG_DEFENSIVE auras render
- `player`: only player-cast renders (green border)
- `others`: only other-cast renders (yellow border)

- [ ] **Step 6: Border color distinction**

If you have a target dummy setup, stand a second character near your main's view. Have it apply a big defensive to you (if any class can externally apply something that's classified as BIG_DEFENSIVE and NOT EXTERNAL_DEFENSIVE — rare, but test whatever applies). Otherwise confirm via the self-cast path that the green (player) border shows correctly.

- [ ] **Step 7: Long-duration skip**

Confirm flasks / food buffs / racial buffs (all duration 0 or >= 600s) do NOT appear. This exercises the `dur == 0 or dur >= 600` filter after the flag check.

- [ ] **Step 8: Combat churn — 5-man or target dummy burst**

Run a dungeon pull or a 60s target-dummy rotation with all personal cooldowns active. Watch for:
- No Lua errors in `/etrace` or BugSack
- Icons appear/disappear cleanly with cooldown usage
- No visual flicker or orphaned icons after auras drop

- [ ] **Step 9: Report findings**

Post a brief summary back to the user confirming:
- Which personal defensives were tested
- Border color distinction worked
- External-defensive exclusion worked
- No regressions observed in a combat session

If any step reveals a regression, STOP, do not proceed to Task 3, and consult the user.

---

## Task 3: Release cut

**Files:**
- Modify: `CHANGELOG.md` (new v0.8.15-alpha block)
- Modify: `Framed.toc:5` (version bump)
- Modify: `Settings/Cards/About.lua` (regenerated by sync-changelog.lua)

Per `feedback_release_workflow`: fix commit first (Task 1), bump commit second (this task) touches only CHANGELOG / TOC / About.

- [ ] **Step 1: Add v0.8.15-alpha block to CHANGELOG.md**

Open `CHANGELOG.md` and insert between `[Unreleased]` and `v0.8.14-alpha`:

```markdown
## v0.8.15-alpha

- **B2 Defensives migrated to classified API** (#115, #138) — `Elements/Auras/Defensives.lua` now reads `entry.flags.*` from `auraState:GetHelpfulClassified()` instead of issuing 3 `IsAuraFilteredOutByInstanceID` probes per aura per UNIT_AURA. First consumer of A1's classification infrastructure. Behavior unchanged — same defensives render, same player/other border distinction, same long-duration skip.
```

- [ ] **Step 2: Run sync-changelog.lua**

```bash
./tools/sync-changelog.lua
```

This regenerates the `-- BEGIN/END GENERATED CHANGELOG` block in `Settings/Cards/About.lua` with the new entries (most-recent-2 kept).

- [ ] **Step 3: Bump Framed.toc version**

Edit `Framed.toc` line 5:
```
## Version: 0.8.14-alpha
```
to:
```
## Version: 0.8.15-alpha
```

- [ ] **Step 4: Verify the bump commit's diff is scoped correctly**

Run: `Bash git status && git diff --stat`
Expected three files changed: `CHANGELOG.md`, `Framed.toc`, `Settings/Cards/About.lua`. Nothing else.

If other files appear, stash them before committing the bump — the release-workflow memory requires the bump commit to be narrow.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md Framed.toc Settings/Cards/About.lua
git commit -m "Bump to v0.8.15-alpha"
```

- [ ] **Step 6: Push**

```bash
git push origin working-testing
```

---

## Task 4: Create PRs (working-testing → working, then working → main)

Follows the same two-stage promotion pattern used for v0.8.14-alpha (PRs #145 + #146). Per `project_framed_worktree`: working-testing → working for dev promotion; working → main triggers release automation.

**Files:** None.

- [ ] **Step 1: Create working-testing → working PR**

```bash
gh pr create --base working --head working-testing \
  --title "v0.8.15-alpha — B2 Defensives classified-API migration" \
  --body "$(cat <<'EOF'
## Summary
- **B2 Defensives migrated to classified API** (#115, #138) — first element consumer of A1's classification layer. Replaces 3 `IsAuraFilteredOutByInstanceID` probes per aura (BIG_DEFENSIVE, EXTERNAL_DEFENSIVE, PLAYER) with flag reads.
- Behavior unchanged; smoke-test migration validates the `entry.flags.*` pattern for the rest of the B-series.
- Version bump 0.8.14-alpha → 0.8.15-alpha.

## Test plan
- [x] Self-cast personal defensive (Divine Shield / Ice Block / etc.) renders with green border
- [x] PWS (external-defensive) does NOT appear in Defensives (appears in Externals)
- [x] Visibility mode all / player / others each filter correctly
- [x] Long-duration skip (flasks / food / racials) preserved
- [x] Combat session with cooldowns — no Lua errors, no orphaned icons

## Follow-ups
- B1 Externals (#137) next in the series

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 2: Wait for working-testing → working PR to be reviewed and merged**

STOP here. Hand back to the user for merge. Once merged, continue to Step 3.

- [ ] **Step 3: Create working → main promotion PR**

Run after the working-testing PR is merged:

```bash
gh pr create --base main --head working \
  --title "Promote v0.8.15-alpha to main" \
  --body "$(cat <<'EOF'
## Summary
- **B2 Defensives migrated to classified API** (#115, #138) — first element consumer of A1's classification layer; 3 probes per aura replaced with flag reads. Behavior unchanged.
- Version bump 0.8.14-alpha → 0.8.15-alpha.

## Test plan
QA completed on the `working-testing` → `working` leg (previous PR). Promotion only.

## Post-merge
- [ ] Confirm `auto-tag.yml` creates `v0.8.15-alpha` tag
- [ ] Confirm `release.yml` publishes to CurseForge and posts to Discord

## Follow-ups
- B1 Externals (#137) next in the series
- #118 gen-check defect — remains blocked until all B-series elements ship

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Hand back to user**

Report both PR URLs. The user owns the merge; auto-tag + release automation fire on the main merge.

---

## Rollback strategy

Per the spec's "Rollback strategy" section (line 556):
1. `git revert` the Task 1 commit (and the bump in Task 3 if already landed).
2. AuraState's classification layer stays in place; Defensives reverts to its pre-B2 probe path against `_helpfulById`.
3. Other B-issues (none shipped yet) unaffected.

A1's API surface is append-only — reverting B2 does not require touching `Core/AuraState.lua`.
