# Buffs AuraData Annotation Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Per user preference (`feedback_inline_execution`), Framed plans execute inline rather than subagent-driven.

**Goal:** Stop mutating Blizzard's `AuraData` tables inside `Elements/Auras/Buffs.lua`'s `matchAura` closure. Update every downstream reader (5 sites across 3 files) to source the same values from native Blizzard fields (`aura.applications`) and from the existing `unit` closure local. Drop the unused `dispelType` plumbing from the Buffs rendering path entirely.

**Architecture:** `matchAura` currently writes three Framed-owned keys onto every matched `AuraData` (`.unit`, `.stacks`, `.dispelType`). With cf7fabb's widened filter, that mutation now runs on every helpful aura every `UNIT_AURA` tick — including cosmetic/consumable/world buffs Blizzard previously stripped server-side — suspected as the retention mechanism behind the idle party/raid memory regression. The fix routes renderers to read `aura.applications` directly (the Blizzard-native name for the same integer), passes `unit` via parameter where needed, and deletes the two annotation blocks once every reader has been migrated.

**Tech Stack:** Lua (WoW 12.0.x client API), `C_UnitAuras` AuraData struct (`.applications`, `.dispelName`, `.auraInstanceID`).

**Spec:** `docs/superpowers/specs/2026-04-22-buffs-annotation-cleanup-design.md`

**Branch:** `working-testing` (Framed's single-workspace convention — PRs merge `working-testing` → `working`). Lands as a separate PR after the FullRefresh varargs PR (#155 item 3) merges, to keep MemDiag A/B attribution between the two allocation sources separable.

---

## File Structure

**Modify:** `Elements/Indicators/Icons.lua`
- Add `unit` as first parameter to `IconsMethods:SetIcons`.
- Update the `icon:SetSpell` call inside the loop to read the `unit` param (not `aura.unit`), read `aura.applications` (not `aura.stacks`), and drop the `aura.dispelType` argument.
- Drop the `dispelType` entry from the LuaDoc `@param auraList` comment.

**Modify:** `Elements/Indicators/Icon.lua`
- Drop the `dispelType` parameter from `IconMethods:SetSpell`'s signature.
- Drop the `--- @param dispelType` LuaDoc line.

**Modify:** `Elements/Indicators/Bars.lua`
- Swap `aura.stacks` → `aura.applications` inside the `BarsMethods:SetBars` loop (lines 39–40).

**Modify:** `Elements/Auras/Buffs.lua`
- ICONS dispatch: pass `unit` to `renderer:SetIcons` (new first arg).
- ICON dispatch: pass `unit` (not `aura.unit`), `aura.applications` (not `aura.stacks`), drop `aura.dispelType` arg.
- BAR dispatch (line 295): swap `aura.stacks` → `aura.applications`.
- RECTANGLE dispatch (line 358): swap `aura.stacks` → `aura.applications`.
- Delete both annotation blocks inside `matchAura` (lines 180–185 and 200–205). Drop the `annotated` local (line 170).

No new files. No other files touched. No changes to `Elements/Auras/Debuffs.lua`, `Externals.lua`, `Defensives.lua`, `Dispellable.lua`, `PrivateAuras.lua`, or `MissingBuffs.lua` — they don't use the annotation pattern.

---

## Verification Model

Matches the FullRefresh varargs plan's model. This is a WoW addon with no test harness. Verification after each task is:

1. **Reload:** User runs `/reload` in-game. No Lua errors in `BugSack`.
2. **Targeted behavior check:** User confirms the relevant renderer type still works (buffs render after the matching dispatch is updated).
3. **Final validation** (Task 6): Ghost-aura stress, zero-aura unit, full regression replay, memory A/B.

Each production-code task commits + pushes per `feedback_commit_after_task` (crash protection between reloads).

---

## Task 1: Capture pre-change idle memory baseline

**Why first:** The cf7fabb regression was bisected in an **idle party with Fort+Int active**, not in LFR. The measurement needs to match the regression scenario, not the varargs PR's LFR methodology. This captures the per-second GC growth rate that Option C is expected to collapse.

**Files:** None modified. Data capture only.

- [ ] **Step 1: Confirm branch state**

Run: `git status && git log --oneline -3`
Expected: clean tree (unless the varargs PR branch is still open with uncommitted validation results — in which case, finish that first). HEAD should be at or past `df00aa8 Correct Buffs annotation spec`.

- [ ] **Step 2: Ask user to run idle baseline**

User instructions (deliver to user):
```
Before making changes, I need a fresh idle-party memory baseline that
matches the cf7fabb regression scenario (not LFR).

1. Log in on a character in a party of 5 (any spec, any class).
2. Confirm Fortitude and Intellect buffs are active on you. Nothing
   else — no consumables, no world buffs, no combat buffs.
3. /reload to get a clean Lua heap.
4. Stand idle (no combat, no movement) for 5 seconds to let things settle.
5. Run these two commands back-to-back:
   /run print(string.format('%.1f KB', collectgarbage('count')))
   /framed memdiag 30
6. While the 30-second memdiag runs, also paste a second collectgarbage
   reading at the end:
   /run print(string.format('%.1f KB', collectgarbage('count')))

Paste everything here: the two collectgarbage readings plus the full
memdiag output.

We're looking for:
- Per-second delta between the two collectgarbage readings
  (idle growth rate)
- event:UNIT_AURA bucket total
- Any Buffs.lua rows in the memdiag output
```

- [ ] **Step 3: Record baseline values**

When user pastes output, record four values for the Task 7 comparison:
- `collectgarbage('count')` at T=0 (KB)
- `collectgarbage('count')` at T=30s (KB)
- Per-second idle growth rate: `(T30 - T0) / 30` KB/s
- `event:UNIT_AURA` total from memdiag (KB over 30s)
- Any `Buffs.lua` / `matchAura` rows in the per-function breakdown (if surfaced)

Save as a conversation note (no file edit). These feed the PR body in Task 8.

- [ ] **Step 4: No commit**

Data capture — nothing to commit.

---

## Task 2: Update ICONS path (Icons.lua signature + Buffs.lua caller)

**Why this order:** The ICONS path involves a signature change (`SetIcons(auraList)` → `SetIcons(unit, auraList)`), which is the highest-risk edit in this plan. Doing it first catches any breakage before other changes can mask it. All intermediate states are safe — `matchAura` is still annotating, and after this task, Icons.lua reads from the new `unit` param (same value as the annotated `aura.unit`, just sourced differently). No behavioral change.

**Files:**
- Modify: `Elements/Indicators/Icons.lua`
- Modify: `Elements/Auras/Buffs.lua` (ICONS dispatch only)

- [ ] **Step 1: Update `Icons.lua` LuaDoc and signature**

Locate the existing LuaDoc + signature at lines 15–17 of `Elements/Indicators/Icons.lua`:

```lua
--- Fill icons from the pool with aura data and lay them out.
--- @param auraList table Array of { spellID, icon, duration, expirationTime, stacks, dispelType }
function IconsMethods:SetIcons(auraList)
```

Replace with:

```lua
--- Fill icons from the pool with aura data and lay them out.
--- @param unit string Unit token passed through to Icon:SetSpell for GetAuraDuration lookup
--- @param auraList table Array of { auraInstanceID, spellId, icon, duration, expirationTime, applications }
function IconsMethods:SetIcons(unit, auraList)
```

The `@param auraList` field list is rewritten to reflect what's actually read inside the loop post-change: `auraInstanceID`, `spellId`, `icon`, `duration`, `expirationTime`, `applications`. Drops `stacks` (renamed to its Blizzard-native name) and `dispelType` (dead per Task 3).

- [ ] **Step 2: Update `Icons.lua` body — the `icon:SetSpell` call**

Locate the existing `icon:SetSpell` call inside the loop (around lines 73–82):

```lua
		icon:SetSpell(
			aura.unit,
			aura.auraInstanceID,
			aura.spellId,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.stacks,
			aura.dispelType
		)
```

Replace with:

```lua
		icon:SetSpell(
			unit,
			aura.auraInstanceID,
			aura.spellId,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.applications
		)
```

Three edits in this block: `aura.unit` → `unit` (the new param), `aura.stacks` → `aura.applications`, and the `aura.dispelType` line removed entirely (along with the preceding comma on `aura.stacks`).

- [ ] **Step 3: Update the only caller in `Elements/Auras/Buffs.lua`**

Locate the ICONS dispatch at Buffs.lua:253:

```lua
				renderer:SetIcons(list)
```

Replace with:

```lua
				renderer:SetIcons(unit, list)
```

The `unit` local is already captured in the outer closure (`function element:Update(event, unit, updateInfo)` — verify by reading a few lines up). No new local needed.

- [ ] **Step 4: Request user reload + ICONS render check**

User instructions:
```
Icons.lua now takes unit as its first parameter and reads aura.applications
instead of aura.stacks. The dispelType argument is gone.

Please:

1. /reload
2. Target yourself and confirm buffs rendered by ICONS-type indicators
   display correctly:
   - Icons appear in the right spots
   - Stack counts show on stackable buffs (e.g., a trinket proc)
   - Duration rings / cooldown sweeps animate
3. Check BugSack for any Lua errors.

If you don't know which of your indicators is ICONS-type: look at any
"My Buffs" row or default buff indicator — most buff indicators default
to ICONS. If in doubt, /framed config and check the type field.
```

Expected: ICONS indicators render identically. No errors. At this point `matchAura` is still annotating — so `aura.unit`, `aura.stacks`, `aura.dispelType` still exist on the data; we just stopped reading two of them in this path.

- [ ] **Step 5: Commit + push**

```bash
git add Elements/Indicators/Icons.lua Elements/Auras/Buffs.lua
git commit -m "$(cat <<'EOF'
refactor(indicators): route Icons through unit param + applications

Changes Icons:SetIcons signature to accept unit as the first parameter,
reads aura.applications in place of aura.stacks, and drops the
aura.dispelType argument (dead in Icon:SetSpell body). Buffs.lua's
ICONS dispatch updated to pass unit; no other callers exist.

Intermediate step toward dropping Buffs.lua matchAura's AuraData
mutation. Readers migrate renderer-by-renderer before the mutation
itself is deleted.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push origin working-testing
```

---

## Task 3: Update ICON path (Icon.lua drops dispelType + Buffs.lua ICON dispatch)

**Files:**
- Modify: `Elements/Indicators/Icon.lua` (signature + LuaDoc)
- Modify: `Elements/Auras/Buffs.lua` (ICON dispatch block)

Both callers of `Icon:SetSpell` (`Icons.lua:73` was already updated in Task 2 to pass 7 args; `Buffs.lua:263` is updated below) land in this task so the signature change and its callers stay atomic.

- [ ] **Step 1: Update `Icon.lua` LuaDoc and signature**

Locate the LuaDoc + signature at lines 21–30 of `Elements/Indicators/Icon.lua`:

```lua
--- Set the displayed spell/aura data on this icon.
--- @param unit string|nil Unit token
--- @param auraInstanceID number|nil Aura instance ID
--- @param spellID number
--- @param iconTexture number|string Texture ID or path
--- @param duration number Duration in seconds (may be a secret value)
--- @param expirationTime number Expiration GetTime() value (may be a secret value)
--- @param stacks number Stack count
--- @param dispelType string|nil Dispel/debuff type ('Magic', 'Curse', etc.)
function IconMethods:SetSpell(unit, auraInstanceID, spellID, iconTexture, duration, expirationTime, stacks, dispelType)
```

Replace with:

```lua
--- Set the displayed spell/aura data on this icon.
--- @param unit string|nil Unit token
--- @param auraInstanceID number|nil Aura instance ID
--- @param spellID number
--- @param iconTexture number|string Texture ID or path
--- @param duration number Duration in seconds (may be a secret value)
--- @param expirationTime number Expiration GetTime() value (may be a secret value)
--- @param stacks number Stack count
function IconMethods:SetSpell(unit, auraInstanceID, spellID, iconTexture, duration, expirationTime, stacks)
```

Drops the `--- @param dispelType` LuaDoc line and the `, dispelType` parameter. The body (408 lines below) never reads `dispelType` — verified dead.

**Note on the `stacks` parameter name:** Icon.lua's `SetSpell` still takes a parameter called `stacks` (not `applications`) because the parameter is a local name inside Icon.lua — its caller reads `aura.applications` and passes it in, and the Icon internals continue to call it `stacks`. Renaming the parameter is a separate cosmetic concern, out of scope here.

- [ ] **Step 2: Update ICON dispatch in `Buffs.lua`**

Locate the ICON dispatch at Buffs.lua:260–275:

```lua
		elseif(rendererType == C.IndicatorType.ICON) then
			local aura = matchedPool[idx]
			if(aura) then
				renderer:SetSpell(
					aura.unit,
					aura.auraInstanceID,
					aura.spellId,
					aura.icon,
					aura.duration,
					aura.expirationTime,
					aura.stacks,
					aura.dispelType
				)
			else
				renderer:Clear()
			end
```

Replace the `renderer:SetSpell(...)` call with:

```lua
				renderer:SetSpell(
					unit,
					aura.auraInstanceID,
					aura.spellId,
					aura.icon,
					aura.duration,
					aura.expirationTime,
					aura.applications
				)
```

Three edits: `aura.unit` → `unit` (closure local), `aura.stacks` → `aura.applications`, `aura.dispelType` argument removed (along with the trailing comma on the `aura.stacks` line).

- [ ] **Step 3: Request user reload + ICON render check**

User instructions:
```
Icon.lua's SetSpell signature now drops the unused dispelType parameter.
Buffs.lua's ICON dispatch passes unit + applications, no dispelType.

Please:

1. /reload
2. Find or create an ICON-type buff indicator — typically a
   "single icon" display for a specific spell (not ICONS, not BAR).
   If you're unsure: /framed config and look for indicators with
   type = "Icon" (singular).
3. Confirm the icon renders, shows stack count if the tracked buff
   stacks, and the cooldown ring animates.
4. Check BugSack.

If you don't have an ICON-type buff indicator configured, skip the
render check — the signature change is validated by Task 2's ICONS
render (Icons.lua:73 now calls SetSpell with the new 7-arg form).
```

Expected: no errors. ICON indicators (if any are configured) render correctly. The dispelType removal has no visible effect because Icon.lua never read it.

- [ ] **Step 4: Commit + push**

```bash
git add Elements/Indicators/Icon.lua Elements/Auras/Buffs.lua
git commit -m "$(cat <<'EOF'
refactor(indicators): drop dead dispelType param from Icon:SetSpell

Icon:SetSpell declared dispelType in its signature but never read the
value in its 408-line body. Both callers (Icons.lua inside SetIcons,
Buffs.lua ICON dispatch) updated to match the new 7-arg arity; the
Buffs.lua ICON dispatch also switches to unit closure local and
aura.applications in the same commit.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push origin working-testing
```

---

## Task 4: Swap remaining `aura.stacks` readers (BAR / RECTANGLE / BARS-via-Bars.lua)

**Files:**
- Modify: `Elements/Indicators/Bars.lua` (BARS internal read, inside `Bars:SetBars` loop)
- Modify: `Elements/Auras/Buffs.lua` (BAR dispatch + RECTANGLE dispatch)

Three tiny 1-line substitutions, all semantically identical (`aura.stacks` → `aura.applications`). Combined in one task because the risk is minimal and the validator (reload + render check) applies to all three uniformly.

- [ ] **Step 1: `Bars.lua` — BARS internal read**

Locate lines 39–41 of `Elements/Indicators/Bars.lua` (inside the `for i = 1, count do` loop in `BarsMethods:SetBars`):

```lua
		if(aura.stacks) then
			bar:SetStacks(aura.stacks)
		end
```

Replace with:

```lua
		if(aura.applications) then
			bar:SetStacks(aura.applications)
		end
```

- [ ] **Step 2: `Buffs.lua` — BAR dispatch (line 295)**

Locate the BAR dispatch at Buffs.lua:295:

```lua
				if(aura.stacks) then renderer:SetStacks(aura.stacks) end
```

Replace with:

```lua
				if(aura.applications) then renderer:SetStacks(aura.applications) end
```

- [ ] **Step 3: `Buffs.lua` — RECTANGLE dispatch (line 358)**

Locate the RECTANGLE dispatch at Buffs.lua:358:

```lua
				if(aura.stacks) then renderer:SetStacks(aura.stacks) end
```

Replace with:

```lua
				if(aura.applications) then renderer:SetStacks(aura.applications) end
```

**Important:** Buffs.lua has TWO lines that look identical — one at :295 (BAR) and one at :358 (RECTANGLE). Both need replacing. Use an `Edit` tool call with `replace_all: true` on `if(aura.stacks) then renderer:SetStacks(aura.stacks) end`, OR make two separate edits with context lines to disambiguate. Verify afterward with `rg 'aura\.stacks' Elements/Auras/Buffs.lua` — should return zero hits.

- [ ] **Step 4: Request user reload + BAR / RECTANGLE / BARS render check**

User instructions:
```
All remaining aura.stacks readers now use aura.applications. Three
changes, three renderer types covered: BAR (single-bar), BARS (multi-
bar grid), RECTANGLE.

Please:

1. /reload
2. Confirm each renderer type you have configured still displays stack
   counts correctly. A quick way to trigger a stackable buff: eat food
   (stacks to 10), or use a stackable trinket.
3. If you have a BARS (multi-bar) configuration, confirm stack text
   shows on individual bars in that grid.
4. If you have a RECTANGLE indicator (less common), confirm its
   stack count displays.
5. Check BugSack.

If any of these indicator types aren't configured on your setup, skip
them — the substitution is trivially correct (aura.applications is
Blizzard's native name for the same integer value that annotation
was copying into aura.stacks).
```

Expected: stack counts render identically. No errors. `matchAura` is still annotating at this point — `aura.stacks` still exists on the data, we just stopped reading it anywhere.

- [ ] **Step 5: Commit + push**

```bash
git add Elements/Indicators/Bars.lua Elements/Auras/Buffs.lua
git commit -m "$(cat <<'EOF'
refactor(indicators): read aura.applications for stack counts

Swaps the three remaining aura.stacks reader sites to aura.applications:
Bars.lua:39 (BARS internal loop), Buffs.lua:295 (BAR dispatch), and
Buffs.lua:358 (RECTANGLE dispatch). applications is the Blizzard-native
name for the same integer; stacks was a Framed-owned annotation that
this PR is removing. The annotation itself stays in place for one more
commit to keep this change trivially verifiable.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push origin working-testing
```

---

## Task 5: Delete the annotation blocks in `matchAura`

**Files:**
- Modify: `Elements/Auras/Buffs.lua` (two annotation blocks in `matchAura` + one unused local)

This is the payoff task — the mutation itself is eliminated. After Tasks 2, 3, 4 migrated every reader to sourcing data from Blizzard-native fields / closure params, the annotations are dead writes.

- [ ] **Step 1: Delete the `annotated` local**

Locate the `annotated = false` initialization inside `matchAura` (around line 170 of `Elements/Auras/Buffs.lua`):

```lua
		local function matchAura(auraData)
			local spellId = auraData.spellId
			if(not F.IsValueNonSecret(spellId)) then return end

			local sourceUnit = auraData.sourceUnit
			local annotated = false
```

Remove the `local annotated = false` line. Final form:

```lua
		local function matchAura(auraData)
			local spellId = auraData.spellId
			if(not F.IsValueNonSecret(spellId)) then return end

			local sourceUnit = auraData.sourceUnit
```

- [ ] **Step 2: Delete the first annotation block (spell-lookup branch, lines 178–185)**

Locate the block inside the spell-lookup branch of `matchAura`:

```lua
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
```

Delete the annotation block (the `-- Annotate auraData...` comment plus the `if(not annotated) ... end` block — 8 lines total), leaving:

```lua
				if(passesCastByFilter(sourceUnit, ind._castBy)) then
					if(ind._type == C.IndicatorType.ICONS or ind._type == C.IndicatorType.BARS) then
```

- [ ] **Step 3: Delete the second annotation block (trackAll branch, lines 200–205)**

Locate the block inside the trackAll loop:

```lua
			if(passesCastByFilter(sourceUnit, ind._castBy)) then
				if(not annotated) then
					auraData.unit      = unit
					auraData.stacks    = auraData.applications
					auraData.dispelType = auraData.dispelName
					annotated = true
				end
				if(ind._type == C.IndicatorType.ICONS or ind._type == C.IndicatorType.BARS) then
```

Delete the `if(not annotated) ... end` block (6 lines), leaving:

```lua
			if(passesCastByFilter(sourceUnit, ind._castBy)) then
				if(ind._type == C.IndicatorType.ICONS or ind._type == C.IndicatorType.BARS) then
```

- [ ] **Step 4: Verify no stale readers remain**

Run: `rg 'aura(Data)?\.(unit|stacks|dispelType)' Elements/Auras/Buffs.lua Elements/Indicators/`

Expected output: zero hits in any of these files. If anything matches, a reader was missed — stop and investigate before reloading. (The spec's `docs/superpowers/specs/` match should still appear in unrelated grep runs — fine, docs only.)

- [ ] **Step 5: Request user reload + full-config render check**

User instructions:
```
Mutation is gone. matchAura now leaves every AuraData table untouched
(no more .unit, .stacks, .dispelType writes). This is the commit the
memory regression fix hinges on.

Please:

1. /reload
2. Walk through each renderer type you have configured and confirm it
   still renders correctly:
   - ICONS  (most buff indicators default here)
   - ICON   (single-icon, less common)
   - BAR    (single bar)
   - BARS   (multi-bar grid)
   - RECTANGLE (rare)
3. Target yourself, a party/raid member, and at least one friendly
   unit with a diverse set of buffs.
4. Confirm stack counts show where expected.
5. Confirm cooldown animations work.
6. Check BugSack.

If anything renders wrong: the previous tasks missed a reader. Stop
and report — I'll find it before any other changes.
```

Expected: all buff rendering unchanged. No errors. This is the behavioral parity check that says "we successfully removed the mutation without removing any information consumers needed."

- [ ] **Step 6: Commit + push**

```bash
git add Elements/Auras/Buffs.lua
git commit -m "$(cat <<'EOF'
refactor(buffs): stop mutating AuraData tables in matchAura

Deletes both annotation blocks inside matchAura (plus the unused
'annotated' local). Framed no longer writes .unit, .stacks, or
.dispelType onto Blizzard's AuraData tables. Every downstream reader
was migrated in prior commits to source these values from
aura.applications (native) and the unit closure local.

Fixes the suspected retention mechanism behind the cf7fabb idle
party/raid memory regression: with the widened HELPFUL filter, every
Fort/Int/cosmetic/consumable buff previously flowed through matchAura
every UNIT_AURA tick and got three new keys written. Removing the
mutation eliminates that allocation pattern and the cross-consumer
aliasing hazard on the shared entry.aura reference in the classified
path.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push origin working-testing
```

---

## Task 6: In-game validation pass

**Files:** None modified. Behavioral validation, matching the spec's Test Gate.

- [ ] **Step 1: Ghost-aura stress**

User instructions:
```
Ghost-aura stress test (verifies the mutation removal didn't break
cross-unit state):

1. Target yourself — note the buffs showing.
2. /tar party1 (or any party/raid member with different buffs).
3. Switch back to /tar player.
4. Repeat target-swap several times while buffs are refreshing.
5. Watch for: buffs from another unit bleeding onto yours, missing
   buffs that should be there, duplicated buffs, or stack count
   corruption.

Expected: every target swap shows the correct unit's buffs with no
bleed, no ghosting, and correct stack counts. Mutation removal can't
introduce ghost-aura bugs (the mutation was never the mechanism
preventing them), but this is the standard validator for any AuraState
or Buffs change and inherits from the #144 audit gate.
```

- [ ] **Step 2: Mixed-renderer party/raid test**

User instructions:
```
Render correctness across indicator types:

1. Confirm your party has a mix of buffs: Fort, Int, at least one
   stackable proc buff (e.g., a trinket), and a Rejuvenation-style
   HoT if a druid is around. If you have a custom indicator tracking
   spell 774 (Rejuv) per your SavedVariables, confirm it displays.
2. For each party member, verify all configured indicators render.
3. If you can swap to Arena or Boss preset mid-session, do so and
   confirm those layouts render correctly.

Expected: every renderer type displays every tracked buff correctly,
including stack counts on stackable buffs. No errors.
```

- [ ] **Step 3: Regression replay with other addons**

User instructions:
```
Full regression replay (0.7.20 pool revert signature check):

1. /reload with MPlusQOL / AbilityTimeline / WeakAuras loaded.
2. Enter combat (any target, any fight — dummy works).
3. Let buffs apply, stack, refresh, expire.
4. Exit combat.
5. Target chains: /tar, /tar target, /tar targettarget.
6. Check BugSack for any errors — especially `attempt to compare
   number with nil` or nil-text errors from other addons (those were
   the 0.7.20 shared-state bleed signature).

Expected: zero BugSack errors across the full sequence. Removing a
mutation cannot introduce cross-addon taint — but verifying it's the
merge gate.
```

- [ ] **Step 4: No commit**

Validation task. If any regression surfaces, file a fix task and re-validate before moving to Task 7.

---

## Task 7: Capture post-change idle measurement + compute A/B delta

**Files:** None modified. Data capture + analysis.

- [ ] **Step 1: Request post-change idle measurement**

User instructions:
```
Final measurement — post-change idle memory in the same scenario as
Task 1's baseline.

Same setup:
1. Same character, same party of 5 (or at least same party composition
   as close as possible — if the specific party members have rotated,
   that's fine, just note it).
2. Fortitude + Intellect active. Nothing else.
3. /reload.
4. Stand idle for 5 seconds.
5. Run the same commands:
   /run print(string.format('%.1f KB', collectgarbage('count')))
   /framed memdiag 30
   (wait 30s)
   /run print(string.format('%.1f KB', collectgarbage('count')))

Paste everything here.
```

- [ ] **Step 2: Compute A/B delta**

Compare post-change output to Task 1 baseline. Record:

| Metric | Pre | Post | Delta |
|---|---|---|---|
| `collectgarbage('count')` at T=0 | | | — |
| `collectgarbage('count')` at T=30s | | | — |
| Idle growth rate (KB/s) | | | |
| `event:UNIT_AURA` total (30s) | | | |
| `Buffs.lua` / `matchAura` rows (if surfaced) | | | |

**Merge criterion per the spec:** direction, not magnitude. The idle growth rate should collapse toward 0.8.12's baseline. If growth is substantially lower (or flat), Option C landed the fix. If growth persists at similar magnitude, the retention mechanism is elsewhere — next step is Option A (restore `buffFilterMode` as explicit config), filed as a follow-up issue. Either way, this PR still ships because the mutation removal is also the fix for the pre-existing aliasing hazard documented in `docs/superpowers/plans/2026-04-22-b3-buffs-classified.md:84`.

If party composition drifted between Task 1 and this measurement, note it in the PR body. The idle-growth metric is relatively composition-insensitive as long as the active buff set is the same (Fort + Int), but large group-size differences can matter.

- [ ] **Step 3: No commit**

Analysis task. Findings flow into the PR body in Task 8.

---

## Task 8: Push branch + create PR

**Files:** None modified locally.

- [ ] **Step 1: Confirm the varargs PR has landed first**

Per the branch strategy chosen in brainstorming (Option A — land varargs first, then Option C as follow-up for clean A/B attribution), the varargs PR should be merged to `working` before this PR opens. Check:

```bash
gh pr list --state merged --search "varargs FullRefresh" --limit 5
```

If the varargs PR is NOT yet merged: wait. Don't open this PR until varargs lands, or the MemDiag A/B for this change mixes two allocation sources.

If the varargs PR is merged:

```bash
git fetch origin
git log --oneline origin/working..working-testing
```

Expected: shows the four commits from Tasks 2, 3, 4, 5 (ICONS, ICON, BAR/RECTANGLE/BARS substitutions, mutation delete). Plus the two spec commits (`1f48247`, `df00aa8`) if those haven't already been swept up by the varargs PR's merge into `working`.

- [ ] **Step 2: Create PR**

```bash
gh pr create --base working --head working-testing --title "refactor(buffs): stop mutating AuraData tables in matchAura" --body "$(cat <<'EOF'
## Summary

Eliminates the three Framed-owned annotations written onto Blizzard's `AuraData` tables inside `Buffs.lua`'s `matchAura` (`.unit`, `.stacks`, `.dispelType`). Every downstream reader now sources these values from their native Blizzard fields (`aura.applications`) or from the existing `unit` closure local. The dead `dispelType` parameter is removed from `Icon:SetSpell` entirely.

Option C from the cf7fabb regression triage. Separate PR from the varargs work (#155 item 3) to keep MemDiag A/B attribution clean between the two allocation sources.

## Motivation

**Memory regression (primary).** `cf7fabb` widened the helpful-aura query from `HELPFUL|RAID_IN_COMBAT` to plain `HELPFUL` whenever any enabled buff indicator has a non-empty `spells` list. With the wider filter, Fort / Int / cosmetic / consumable buffs that Blizzard previously stripped server-side now flow through `matchAura` every `UNIT_AURA` tick — and every one gets three new keys written onto it. The user's SavedVariables had custom indicators tracking Rejuvenation (`spells = { 774 }`) on party frames, triggering the widened filter. Bisect (cf7fabb vs its parent on the same idle-party scenario) pinned the regression here.

**Aliasing hazard (pre-existing).** In the classified path, `entry.aura` is the same `AuraData` reference shared across consumers — Framed's in-place mutation leaked Framed-owned keys onto a shared object. Removing the mutation removes the aliasing risk, independent of whether it also fully collapses the regression.

## Design

Spec: `docs/superpowers/specs/2026-04-22-buffs-annotation-cleanup-design.md`

Scope (5 reader sites across 3 files):
- `Icons.lua` — `SetIcons` gains `unit` parameter, reads `aura.applications`, drops `dispelType` arg
- `Icon.lua` — `SetSpell` signature drops dead `dispelType` parameter
- `Bars.lua` — internal `BARS` loop reads `aura.applications`
- `Buffs.lua` — ICON / BAR / RECTANGLE dispatches read `unit` + `aura.applications`; mutation deleted

## Idle memory A/B (party of 5, Fort + Int, 30 s idle)

<!-- Fill in from Task 1 + Task 7 -->

| Metric | Pre | Post | Delta |
|---|---|---|---|
| `collectgarbage('count')` at T=0 | | | |
| `collectgarbage('count')` at T=30s | | | |
| Idle growth rate (KB/s) | | | |
| `event:UNIT_AURA` total | | | |

**Merge criterion:** direction, not magnitude. Idle growth should collapse toward 0.8.12 baseline. If it doesn't, the retention mechanism is elsewhere and Option A (restore `buffFilterMode` as explicit config) is the follow-up — tracked separately. This PR ships regardless because the mutation removal is also the pre-existing aliasing-hazard fix.

## Test plan

- [x] ICONS render correct with new `unit` parameter (Task 2)
- [x] ICON render correct with dropped `dispelType` param (Task 3)
- [x] BAR / BARS / RECTANGLE stack counts render via `aura.applications` (Task 4)
- [x] All five renderer types render correctly after mutation deleted (Task 5)
- [x] Ghost-aura stress — no cross-unit bleed on target swaps (Task 6)
- [x] Mixed-renderer party/raid render correctness (Task 6)
- [x] Regression replay with MPlusQOL / AbilityTimeline / WeakAuras — zero BugSack errors (Task 6)
- [x] Idle-party A/B captured (Task 7)

## Out of scope

- **Option A (restore `buffFilterMode` as explicit config).** Separate future PR if Option C alone doesn't collapse the regression. Tracked per the spec's References section.
- **Debuffs / Externals / Defensives / Dispellable / PrivateAuras / MissingBuffs.** They don't use the annotation pattern.
- **BorderIcon widget.** It legitimately reads `dispelType` and is used by other elements; this PR doesn't touch it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Backfill A/B table from Task 7 findings**

Edit the PR after creation to fill the placeholder table:

```bash
gh pr edit <pr-number> --body "$(cat <<'EOF'
... (paste full body with A/B table filled in from Task 7) ...
EOF
)"
```

Or via `gh pr view <number> --web`.

- [ ] **Step 4: Report PR URL to user**

Share the PR URL. User reviews → merges `working-testing` → `working` → promotes to `main` on release cadence.

- [ ] **Step 5: File the cf7fabb GitHub issue (if not already filed)**

The spec's `**Issue:** TBD` front-matter entry should now point at a real issue. Create one if none exists:

```bash
gh issue create --title "Memory regression in idle party/raid introduced by cf7fabb" --body "$(cat <<'EOF'
## Summary

cf7fabb (`refactor(buffs): derive aura filter from indicator set, drop buffFilterMode`) introduced a measurable idle memory growth rate in party/raid when any buff indicator has a non-empty `spells` list.

## Mechanism

`computeBuffFilter` widens the helpful-aura query from `HELPFUL|RAID_IN_COMBAT` to plain `HELPFUL` whenever any enabled indicator tracks specific spells. With the wider filter, Blizzard's server-side stripping of Fort / Int / cosmetic / consumable / world buffs no longer applies, and those auras flow through Framed's `matchAura` every `UNIT_AURA` tick. Inside `matchAura`, each matched aura was mutated with three Framed-owned keys — suspected retention mechanism.

## Fix

PR #<this-pr>: stop mutating AuraData tables in `matchAura`. Readers migrated to `aura.applications` and the existing `unit` closure local. If idle growth persists after this lands, the follow-up is to restore `buffFilterMode` as explicit user config (Option A).

## Bisect

- Regression first reproduces on cf7fabb (HEAD-solo vs cf7fabb-solo measured identical, so the widened filter is the sole differential).
- User's SavedVariables had 5 custom indicators with `spells = { 774 }` (Rejuvenation) triggering the widened filter on party frames.
EOF
)"
```

Then edit the spec's header to replace `**Issue:** TBD` with the real issue number, and commit that in a small follow-up:

```bash
git add docs/superpowers/specs/2026-04-22-buffs-annotation-cleanup-design.md
git commit -m "Link cf7fabb regression issue in Buffs annotation cleanup spec"
git push origin working-testing
```

---

## Notes for the executor

- **Code style:** Tabs for indentation, single quotes for strings, parenthesized conditions (`if(x) then`), `for _, v in next, tbl do` (never `pairs`/`ipairs`). See `CLAUDE.md`.
- **Symlink:** Framed's addon folder is a symlink to this repo. Edits are live — user just `/reload`s. See `feedback_wow_sync`.
- **Per-task commits:** Commit + push after every production-code task (2, 3, 4, 5). Crash protection between reloads. See `feedback_commit_after_task`.
- **No pcall:** No new feature detection introduced here. Don't add `pcall`.
- **No comments added:** The annotation blocks being deleted include a comment (`-- Annotate auraData with renderer-expected field names...`) — that comment goes away with the blocks. No new comments replace it; the code without mutation is self-explanatory.
- **Fragile aura indicators:** Per `feedback_aura_indicators_fragile`, never touch indicator rendering without explicit instruction. This plan IS that explicit instruction; executing the tasks as written is authorized. If validation (Task 5 Step 5 or Task 6) surfaces a render break, STOP and report — don't try to patch around it.
- **Author name:** Commit Co-Authored-By uses `Claude Opus 4.7`. The git user (`jdtoppin` per gitconfig) shows up as Moodibs in published commits per `feedback_author_name`.
