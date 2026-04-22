# B5 — MissingBuffs Classified Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch `Elements/Auras/MissingBuffs.lua` from `AuraState:GetHelpful('HELPFUL')` to `AuraState:GetHelpfulClassified()` so every helpful-side B-series element consumes the same slice.

**Architecture:** MissingBuffs is spellID set-membership, not classification filtering — it reads `auraData.spellId` and `auraData.name`, never any flag. The migration peels the `aura` field out of each classified entry inside `auraListHasBuff`. No flag use, no behavior change.

**Tech Stack:** WoW 12.0.x Lua, embedded oUF, Framed AuraState.

**Part of:** #115 UNIT_AURA fan-out rearchitecture, closes #141.

---

## Task 1: Migrate MissingBuffs.lua to classified path

**Files:**
- Modify: `Elements/Auras/MissingBuffs.lua:111-122` (auraListHasBuff helper)
- Modify: `Elements/Auras/MissingBuffs.lua:195` (auraState read)

- [ ] **Step 1: Rewrite `auraListHasBuff` to accept classified entries**

The helper currently iterates auraData objects directly. Switch the loop to read `entry.aura`. Keep the name-fallback logic for secret-spellId cases.

Current (lines 111-122):

```lua
local function auraListHasBuff(rawAuras, targetSpellId)
	local targetName = ensureCached(targetSpellId)
	for _, auraData in next, rawAuras do
		local sid = auraData.spellId
		if(F.IsValueNonSecret(sid) and sid == targetSpellId) then return true end
		if(targetName) then
			local n = auraData.name
			if(F.IsValueNonSecret(n) and n == targetName) then return true end
		end
	end
	return false
end
```

Replace with:

```lua
-- Scan classified entries for a matching buff. Accepts either
-- classified entries ({ aura, flags }) or raw aura objects — the
-- fallback path still feeds raw auras when AuraState is unavailable.
local function auraListHasBuff(auras, targetSpellId)
	local targetName = ensureCached(targetSpellId)
	for _, item in next, auras do
		local auraData = item.aura or item
		local sid = auraData.spellId
		if(F.IsValueNonSecret(sid) and sid == targetSpellId) then return true end
		if(targetName) then
			local n = auraData.name
			if(F.IsValueNonSecret(n) and n == targetName) then return true end
		end
	end
	return false
end
```

The `item.aura or item` form keeps the fallback path (which passes raw auras from `C_UnitAuras.GetUnitAuras`) working without branching at the call site.

- [ ] **Step 2: Swap the auraState read**

Current (line 195):

```lua
local rawAuras = auraState and auraState:GetHelpful('HELPFUL') or C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')
```

Replace with:

```lua
local auras = auraState and auraState:GetHelpfulClassified()
	or C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')
```

Rename `rawAuras` → `auras` at the call site on line 206:

```lua
elseif(providingClass and groupClasses[providingClass] and not auraListHasBuff(auras, spellId)) then
```

- [ ] **Step 3: Verify no other consumers of `rawAuras`**

Run: `grep -n rawAuras Elements/Auras/MissingBuffs.lua`

Expected: no matches (the only reference outside the Update function was in the `auraListHasBuff` signature, which we already updated).

- [ ] **Step 4: Commit**

```bash
git add Elements/Auras/MissingBuffs.lua
git commit -m "refactor(MissingBuffs): migrate to classified aura path (#141)"
git push
```

---

## Task 2: LFR smoke test

- [ ] **Step 1: `/reload` in-game**

Verify no errors on load.

- [ ] **Step 2: Verify missing-buff detection**

In a group (party or LFR) where multiple buff-providing classes are present:
- Missing icons for classes present in group should glow/appear.
- Apply the buff (e.g. Arcane Intellect) → icon should disappear next UNIT_AURA.
- Remove the buff → icon should reappear.

- [ ] **Step 3: Verify hidden-state cases**

- Dead/ghost unit → all slots hidden.
- Pet unit → all slots hidden.
- NPC follower unit (delve): only own-class buff icon should be visible; other classes hidden (pre-existing NPC-secret-aura behavior).

- [ ] **Step 4: Report back**

User confirms smoke passes before opening PR.

---

## Task 3: Open PR

- [ ] **Step 1: Open working-testing → working PR**

```bash
gh pr create --base working --head working-testing \
  --title "B5 — migrate MissingBuffs to AuraState classified API (#141)" \
  --body "..."
```

PR body should cover:
- One-line migration (swap `GetHelpful('HELPFUL')` → `GetHelpfulClassified()`, peel `entry.aura` in helper).
- No behavior change. Fallback path unchanged.
- Closes #141.
- Test plan reflects Task 2 steps.

---

## Self-review checklist

- [x] Every spec step has actual code, not placeholder text.
- [x] `item.aura or item` form preserves the fallback path (C_UnitAuras raw auras) without call-site branching.
- [x] No flag reads (MissingBuffs never consumed classification flags — the classified view is used purely for slice consistency).
- [x] No other call sites reference `rawAuras` or the old helper signature.
- [x] Task ordering: migration → user-run smoke → PR, matching B1/B2/B3/B4 pattern.
