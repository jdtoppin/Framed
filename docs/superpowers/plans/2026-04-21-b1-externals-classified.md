# B1 — Externals Classified Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `Elements/Auras/Externals.lua` to consume `auraState:GetHelpfulClassified()` via `entry.flags.*` reads, eliminating 5 `IsAuraFilteredOutByInstanceID` probes per aura per UNIT_AURA.

**Architecture:** Two-path iteration (classified / raw fallback) mirroring B2 Defensives. Extract inline render block into a module-local `renderEntry` helper. Flag reads: `isExternalDefensive` (primary), `isImportant` + `!isBigDefensive` (IMPORTANT fallback), `isRaid` + secret-spellId + `!isBigDefensive` (RAID fallback), `isPlayerCast` (border color). `renderEntry` signature matches B2's exactly — same helper shape across aura elements.

**Tech Stack:** Lua 5.1, oUF, `F.AuraState.GetHelpfulClassified`, `F.IsValueNonSecret`, `F.Indicators.BorderIcon`.

---

## Context

### Current probes (pre-B1)

```
Step 1 (primary):       HELPFUL|EXTERNAL_DEFENSIVE       → isExternalDefensive
Step 2 (IMPORTANT):     HELPFUL|IMPORTANT                → isImportant
                        HELPFUL|BIG_DEFENSIVE            → isBigDefensive (exclusion)
Step 3 (RAID fallback): F.IsValueNonSecret(spellId)      → (not a probe)
                        HELPFUL|RAID                     → isRaid
                        HELPFUL|BIG_DEFENSIVE            → isBigDefensive (duplicate of step 2, same flag)
Border color:           HELPFUL|PLAYER                   → isPlayerCast
```

Five unique classification probes become five flag reads. The duplicate `BIG_DEFENSIVE` probe (step 2 vs step 3) collapses to a single flag read.

### Why Externals is a bigger win than Defensives

Defensives eliminated 3 probes per aura. Externals eliminates 5. With A1's classify() doing 4 probes per aura once and caching, the per-UNIT_AURA cost drops from `N_aura × 5` to `4` (amortized; cached across all consumers).

### Cross-element invariant preserved

`not flags.isBigDefensive` gates the IMPORTANT and RAID fallback branches. This keeps spells classified as `BIG_DEFENSIVE` in the Defensives element and off the Externals element (no double-display). B2 Defensives uses the complementary check: `flags.isBigDefensive and not flags.isExternalDefensive` — the two elements partition the HELPFUL space cleanly.

### RAID fallback rationale (preserved verbatim)

In combat, Power Infusion and similar raid-important buffs may have a secret `spellId`. Spell-level classification is unavailable in that window, so the element falls back to the `HELPFUL|RAID` filter to catch them. Out of combat, `spellId` is non-secret — the RAID filter would be too broad (would catch every Rejuvenation), so the fallback is gated by `not F.IsValueNonSecret(auraData.spellId)`. Post-migration logic is identical; only the probe is replaced with a flag read.

### Migration shape (reference — B2's pattern)

```lua
local classified = auraState and auraState:GetHelpfulClassified()
local rawAuras   = (not classified) and F.AuraCache.GetUnitAuras(unit, 'HELPFUL') or nil

if(classified) then
    for _, entry in next, classified do
        local auraData = entry.aura
        local flags    = entry.flags
        local id       = auraData.auraInstanceID
        -- flag-based classification chain
    end
else
    -- vestigial raw-probe fallback preserved
end
```

---

## Task 1: Migrate `Elements/Auras/Externals.lua`

**Files:**
- Modify: `Elements/Auras/Externals.lua` (~245 lines, full Update() rewrite + renderEntry helper)

- [ ] **Step 1: Read the current file and the B2 reference**

Read the current file to confirm no drift since spec was written:
```
Read: Elements/Auras/Externals.lua
```

Read B2's final form as the template for `renderEntry` shape and two-path structure:
```
Read: Elements/Auras/Defensives.lua
```

- [ ] **Step 2: Extract `renderEntry` helper above `Update`**

Insert before the existing `Update` function. Signature and body match B2's exactly — this keeps the two element files structurally parallel.

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

- [ ] **Step 3: Replace the body of `Update` with the two-path iteration**

Keep the preamble unchanged (config unpacking, unit guard). Replace the aura loop (lines ~42–149 in the current file) with:

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

			-- Step 1: EXTERNAL_DEFENSIVE (primary)
			local show = flags.isExternalDefensive

			-- Step 2: IMPORTANT fallback — exclude BIG_DEFENSIVE to avoid
			-- duplicating spells that already appear in the Defensives element.
			-- NOTE: IMPORTANT may be removed in 12.0.5 per Blizzard feedback.
			if(not show and flags.isImportant and not flags.isBigDefensive) then
				show = true
			end

			-- Step 3: RAID fallback — only for secret auras (combat) where
			-- spell-level classification isn't available. Catches Power Infusion
			-- and similar raid-important buffs. Too broad out of combat (catches
			-- basic HoTs like Rejuvenation). Exclude BIG_DEFENSIVE.
			if(not show) then
				local isSecret = not F.IsValueNonSecret(auraData.spellId)
				if(isSecret and flags.isRaid and not flags.isBigDefensive) then
					show = true
				end
			end

			-- Skip long-duration buffs (flasks, food, racials) that slip through
			-- classification filters. duration == 0 means permanent.
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
		-- Fallback: no AuraState on this frame. Vestigial in practice — every
		-- aura-tracking frame creates AuraState via the idempotent Setup guard —
		-- preserved to match the element-level pattern used across Auras/.
		for _, auraData in next, rawAuras do
			if(displayed >= maxDisplayed) then break end

			local id = auraData.auraInstanceID

			-- Step 1: EXTERNAL_DEFENSIVE (primary classification)
			local show = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
				unit, id, 'HELPFUL|EXTERNAL_DEFENSIVE')

			-- Step 2: IMPORTANT fallback — exclude BIG_DEFENSIVE.
			if(not show) then
				local isImportant = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
					unit, id, 'HELPFUL|IMPORTANT')
				if(isImportant) then
					local isBigDef = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
						unit, id, 'HELPFUL|BIG_DEFENSIVE')
					show = not isBigDef
				end
			end

			-- Step 3: RAID fallback for secret auras — exclude BIG_DEFENSIVE.
			if(not show) then
				local isSecret = not F.IsValueNonSecret(auraData.spellId)
				if(isSecret) then
					local isRaid = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
						unit, id, 'HELPFUL|RAID')
					if(isRaid) then
						local isBigDef = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
							unit, id, 'HELPFUL|BIG_DEFENSIVE')
						show = not isBigDef
					end
				end
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
```

- [ ] **Step 4: Verify syntax**

Run:
```
luajit -e "assert(loadfile('Elements/Auras/Externals.lua')); print('SYNTAX OK')"
```
Expected: `SYNTAX OK`

- [ ] **Step 5: Commit**

```
git add Elements/Auras/Externals.lua
git commit -m "feat(externals): migrate to AuraState classified API (B1 #137)

Replace 5 IsAuraFilteredOutByInstanceID probes per aura per UNIT_AURA
with entry.flags.* reads from auraState:GetHelpfulClassified():
- isExternalDefensive (primary)
- isImportant + !isBigDefensive (IMPORTANT fallback)
- isRaid + secret-spellId + !isBigDefensive (RAID fallback)
- isPlayerCast (border color)

Two-path iteration (classified / raw fallback) mirrors B2 Defensives.
Extract inline render block into a renderEntry helper matching B2's
signature. Behavior unchanged — same externals render, same RAID
fallback gating, same BIG_DEFENSIVE cross-element exclusion."
```

---

## Task 2: Live smoke test in LFR

**Files:** none (live addon test)

- [ ] **Step 1: Push commit**

```
git push origin working-testing
```

- [ ] **Step 2: Ask user to /reload in LFR**

User runs `/reload` in raid finder and verifies:

1. **External defensives render** — healer-cast Power Word: Shield / Ironbark / Blessing of Protection on player frame show up in the Externals element with the "other" border color.
2. **Self-cast PWS** (discipline priest only) — if player casts PWS on self, it shows with the "player" border color.
3. **Secret-spellID combat buffs** — Power Infusion (or similar) applied by a raid member during combat renders via the RAID fallback.
4. **BIG_DEFENSIVE cross-element exclusion** — player casts Ice Block / Divine Shield / Shield Wall: it renders in **Defensives**, not Externals. No double-display.
5. **Out-of-combat RAID gating** — healer casts Rejuvenation on player outside combat: should NOT appear in Externals (gated by secret-spellID check; spellId is non-secret out of combat).
6. **End-of-duration** — no flash, no render anomalies (same regression check as B2).
7. **No Lua errors** — no `AuraState.lua:22` taint, no `Externals.lua` errors.

- [ ] **Step 3: If any regression, stop and diagnose**

If a defensive doesn't render, flash returns, or Lua errors appear: capture the error text, re-read current file state, diagnose. Revert only if the fix is unclear.

---

## Task 3: Create PR

**Files:** none (GitHub PR via gh)

- [ ] **Step 1: Confirm commits on working-testing**

```
git log --oneline origin/working..HEAD
```
Expected: shows the B1 migration commit and plan-doc commit.

- [ ] **Step 2: Open PR**

```
gh pr create --base working --head working-testing \
  --title "B1 — migrate Externals to AuraState classified API (#137)" \
  --body "<body below>"
```

PR body:

```markdown
## Summary

- **B1: Externals migrated to AuraState classified API** (#115, #137) — `Elements/Auras/Externals.lua` now reads `entry.flags.*` from `auraState:GetHelpfulClassified()` instead of issuing 5 `IsAuraFilteredOutByInstanceID` probes per aura per UNIT_AURA. Second consumer of A1's classification infrastructure (after B2 Defensives).
- **Migration detail** — 5 flag reads replace 5 C-API probes: `isExternalDefensive` (primary), `isImportant` + `!isBigDefensive` (IMPORTANT fallback), `isRaid` + secret-spellId + `!isBigDefensive` (RAID fallback), `isPlayerCast` (border color). Duplicate `BIG_DEFENSIVE` probe across fallbacks collapses to a single flag read.
- **Structure** — two-path iteration (classified / raw fallback) mirrors B2 Defensives; extract inline render block into a `renderEntry` helper matching B2's signature.
- **Behavior unchanged** — same externals render, same RAID fallback gating, same BIG_DEFENSIVE cross-element exclusion.
- **No version bump** — remaining B-series (B4 Dispellable, B5 Buffs/Debuffs, B3 castBy) will ship in a bundled release once they land.

Plan: `docs/superpowers/plans/2026-04-21-b1-externals-classified.md`

## Test plan

- [x] LFR — external defensives render with other-color border
- [x] LFR — secret-spellID combat buffs (Power Infusion) render via RAID fallback
- [x] LFR — BIG_DEFENSIVE cross-element exclusion holds (Ice Block stays in Defensives)
- [x] Out-of-combat — Rejuvenation does NOT appear in Externals (RAID fallback gated by secret-spellID)
- [x] No Lua errors, no end-of-duration flash

## Follow-ups

- B4 #140 (Dispellable) — separate plan + PR
- B5 #141 (Buffs/Debuffs) — separate plan + PR
- B3 #139 (castBy flag-based) — separate plan + PR
- Bundled release after B-series completes
```

- [ ] **Step 3: Report PR URL to user**

---

## Self-review

**1. Spec coverage:** B1 maps to spec line 502 ("#137 B1 — `Elements/Auras/Externals.lua` — Replace 5-probe classification chain with flag reads"). All four call-outs covered: self PWS (`isPlayerCast` border), external Ironbark (`isExternalDefensive`), IMPORTANT-only non-defensive helpful (`isImportant` + `!isBigDefensive`), RAID fallback for secret-spellID (`isRaid` + secret + `!isBigDefensive`).

**2. Placeholder scan:** No "TBD", no "similar to B2" — renderEntry body repeated in full. Commit message concrete. PR body concrete. No dangling "fill in details".

**3. Type consistency:** `entry.aura` / `entry.flags` shape matches A1's `classify()` output. Flag names (`isExternalDefensive`, `isImportant`, `isBigDefensive`, `isRaid`, `isPlayerCast`) match `Core/AuraState.lua:18-35` exactly. `renderEntry` signature matches B2's exactly.

**4. Cross-element invariant:** `!flags.isBigDefensive` gate preserved on both IMPORTANT and RAID fallback branches. Defensives uses `flags.isBigDefensive and not flags.isExternalDefensive`. The two elements partition the HELPFUL classification space cleanly — no overlap, no gap.
