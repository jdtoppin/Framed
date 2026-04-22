# A1 — AuraState Classification Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a classification layer to `Core/AuraState.lua` that precomputes per-aura flags (`isExternalDefensive`, `isImportant`, `isPlayerCast`, `isBigDefensive`, plus five structural passthroughs) and exposes them via three instance methods (`GetHelpfulClassified`, `GetHarmfulClassified`, `GetClassifiedByInstanceID`). Ship a `/framed aurastate <unit>` debug slash for live verification. Closes issue #136.

**Architecture:** Lazy-at-read classification keyed by `auraInstanceID`, invalidated from the write path. Classification lives on the existing per-frame AuraState instance (shared idempotently across all aura elements via the `if(not self.FramedAuraState)` guard in each element's Setup). No new event registrations. No changes to existing elements or legacy stores (`_helpfulById`, `_helpfulMatches`). Behavior-neutral for all current elements — they keep using `GetHelpful(filter)` / `GetHarmful(filter)` until the B-series migrates them individually.

**Tech Stack:** Lua 5.1 (WoW 12.0.1), oUF embedded framework (`F.oUF`), `C_UnitAuras` C-level APIs (`IsAuraFilteredOutByInstanceID`), AuraCache generation-based invalidation.

**Reference:** `docs/superpowers/specs/2026-04-21-unit-aura-fanout-rearchitecture-design.md`

**Branch:** `working-testing` (per `project_framed_worktree`). Each task commits to that branch and pushes.

---

## File Structure

| File | Responsibility | Change type |
|------|----------------|-------------|
| `Core/AuraState.lua` | Per-frame aura state with lazy-view pattern; **A1 extends** with classified stores, classify helper, 3 read methods, 4 invalidation methods, 1 debug print function | Modified |
| `Init.lua` | Slash-command dispatcher (lines 284-438) | Modified — one new `elseif` case + one help line |

No new files. All A1 code fits in two existing files.

---

## Task 1: Add per-instance classified state fields

**Files:**
- Modify: `Core/AuraState.lua:312-327` (the `F.AuraState.Create` factory)

Per the spec's "Post-A1 store shape" section, each AuraState instance gets two per-classification dicts + two per-classification views, parallel to the existing `_helpfulById` / `_harmfulById` / views pattern.

- [ ] **Step 1: Read current `F.AuraState.Create`**

Run: look at `Core/AuraState.lua` lines 312-327. Current body:

```lua
function F.AuraState.Create(owner)
	return setmetatable({
		_owner = owner,
		_unit = nil,
		_initialized = false,
		_gen = 0,
		_lastUpdateInfo = nil,
		_lastUpdateUnit = nil,
		_helpfulById = {},
		_helpfulViews = {},
		_helpfulMatches = {},
		_harmfulById = {},
		_harmfulViews = {},
		_harmfulMatches = {},
	}, AuraState)
end
```

- [ ] **Step 2: Add four classified-store fields**

Edit `Core/AuraState.lua` — replace the `F.AuraState.Create` body with:

```lua
function F.AuraState.Create(owner)
	return setmetatable({
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
	}, AuraState)
end
```

- [ ] **Step 3: `/reload` in-game and verify no startup errors**

In WoW: run `/reload`.

Expected: addon loads without Lua errors. The four new fields exist on every AuraState instance but are not yet read or written by anything — no observable change. Run `/framed events` → UNIT_AURA still registered once; no duplicates.

- [ ] **Step 4: Commit and push**

```bash
git add Core/AuraState.lua
git commit -m "$(cat <<'EOF'
feat(aurastate): add classified store fields

Scaffolding for A1 (#136). Adds per-instance `_helpfulClassifiedById`,
`_helpfulClassifiedView`, and harmful twins to F.AuraState.Create. No
reader or writer touches these yet — no observable behavior change.
EOF
)"
git push origin working-testing
```

---

## Task 2: Add module-local `classify()` helper

**Files:**
- Modify: `Core/AuraState.lua` — insert new function above line 14 (the `isCompoundUnit` helper)

Per the spec's "Classification function" section. This is a pure function — no state, no side effects, no allocation outside the returned table. Safe to unit-test by reading the call site only.

- [ ] **Step 1: Verify the `IsAuraFilteredOutByInstanceID` module local exists**

Run: look at `Core/AuraState.lua:9`. Current line:

```lua
local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
```

This is already present. `classify()` will close over it — no re-capture needed.

- [ ] **Step 2: Insert the `classify` helper above `isCompoundUnit`**

Edit `Core/AuraState.lua` — find the block starting at line 11:

```lua
-- Compound unit tokens (e.g. 'party2target', 'playertarget', 'focustarget')
-- are rejected by C_UnitAuras.GetAuraSlots. Pinned target-chain slots can
-- produce these tokens — skip aura queries for them rather than erroring.
local function isCompoundUnit(unit)
```

Replace that block with:

```lua
-- Classify a single aura into a wrapper entry { aura, flags }.
-- Tier 1 flags are structural passthroughs from AuraData (never secret).
-- Tier 2 flags use C_UnitAuras filter probes (secret-safe C API).
local function classify(unit, aura, isHelpful)
	local id = aura.auraInstanceID
	local prefix = isHelpful and 'HELPFUL' or 'HARMFUL'

	local flags = {
		isHelpful         = aura.isHelpful         or false,
		isHarmful         = aura.isHarmful         or false,
		isRaid            = aura.isRaid            or false,
		isBossAura        = aura.isBossAura        or false,
		isFromPlayerOrPet = aura.isFromPlayerOrPlayerPet or false,
	}

	-- Explicit `== false` (not `not ...`). IsAuraFilteredOutByInstanceID returns
	-- nil for invalid state; `not nil == true` would promote every aura.
	flags.isExternalDefensive = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|EXTERNAL_DEFENSIVE') == false
	flags.isImportant         = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|IMPORTANT')          == false
	flags.isPlayerCast        = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|PLAYER')             == false
	flags.isBigDefensive      = isHelpful
	                            and IsAuraFilteredOutByInstanceID(unit, id, 'HELPFUL|BIG_DEFENSIVE') == false
	                            or false

	return { aura = aura, flags = flags }
end

-- Compound unit tokens (e.g. 'party2target', 'playertarget', 'focustarget')
-- are rejected by C_UnitAuras.GetAuraSlots. Pinned target-chain slots can
-- produce these tokens — skip aura queries for them rather than erroring.
local function isCompoundUnit(unit)
```

- [ ] **Step 3: `/reload` and verify no parse errors**

Run: `/reload` in-game. Expected: addon loads without errors. `classify()` is defined but not called — no observable change.

- [ ] **Step 4: Commit and push**

```bash
git add Core/AuraState.lua
git commit -m "$(cat <<'EOF'
feat(aurastate): add classify() helper

Module-local pure function for A1 (#136). Builds a { aura, flags }
wrapper entry — five structural passthroughs plus four C-probe flags
(EXTERNAL_DEFENSIVE, IMPORTANT, PLAYER, BIG_DEFENSIVE). Uses explicit
`== false` normalization to handle nil returns safely. Not yet wired
to any caller.
EOF
)"
git push origin working-testing
```

---

## Task 3: Add `GetHelpfulClassified` and `GetHarmfulClassified` read methods

**Files:**
- Modify: `Core/AuraState.lua` — append new methods after `GetHarmful` (ends around line 310), before `F.AuraState.Create`

Per the spec's "Components and APIs" section. These mirror the existing `GetHelpful` / `GetHarmful` view-rebuild pattern (AuraState.lua:248-310): check `view.dirty`, rebuild if needed, cache entries in `_helpfulClassifiedById` for reuse across rebuilds.

- [ ] **Step 1: Locate the insertion point**

Run: look at `Core/AuraState.lua` — find the end of `function AuraState:GetHarmful(filter)` (ends with `end` around line 310), and the start of `function F.AuraState.Create(owner)` (around line 312). The two new methods go between them.

- [ ] **Step 2: Insert both read methods**

Edit `Core/AuraState.lua` — find this transition:

```lua
	return view.list
end

function F.AuraState.Create(owner)
```

Replace with:

```lua
	return view.list
end

--- Array of wrapper entries for all helpful auras on the instance's unit.
--- @return table   -- array of { aura = AuraData, flags = { isHelpful, ... } }
function AuraState:GetHelpfulClassified()
	local view = self._helpfulClassifiedView
	if(not view.dirty) then
		return view.list
	end

	view.dirty = false
	wipe(view.list)

	if(not self._unit) then
		return view.list
	end

	for id, aura in next, self._helpfulById do
		local entry = self._helpfulClassifiedById[id]
		if(not entry) then
			entry = classify(self._unit, aura, true)
			self._helpfulClassifiedById[id] = entry
		end
		view.list[#view.list + 1] = entry
	end

	return view.list
end

--- Array of wrapper entries for all harmful auras on the instance's unit.
--- @return table   -- array of { aura = AuraData, flags = { isHelpful, ... } }
function AuraState:GetHarmfulClassified()
	local view = self._harmfulClassifiedView
	if(not view.dirty) then
		return view.list
	end

	view.dirty = false
	wipe(view.list)

	if(not self._unit) then
		return view.list
	end

	for id, aura in next, self._harmfulById do
		local entry = self._harmfulClassifiedById[id]
		if(not entry) then
			entry = classify(self._unit, aura, false)
			self._harmfulClassifiedById[id] = entry
		end
		view.list[#view.list + 1] = entry
	end

	return view.list
end

function F.AuraState.Create(owner)
```

- [ ] **Step 3: `/reload` and verify no errors**

Run: `/reload`. Expected: no errors. Methods are defined but no caller exists yet.

- [ ] **Step 4: Smoke-test via scratch print (optional sanity check)**

In WoW chat, run:

```
/run local s = FramedAddon.AuraState.Create('test'); s:FullRefresh('player'); local list = s:GetHelpfulClassified(); print('helpful count:', #list); for _, e in next, list do print(e.aura.auraInstanceID, e.flags.isHelpful, e.flags.isRaid) end
```

Expected: prints your current helpful auras on `player`, with `isHelpful=true` for each. Caveat: without invalidation wiring (Tasks 5-6), this only works on a fresh throwaway state — don't reuse the scratch `s` across aura changes.

- [ ] **Step 5: Commit and push**

```bash
git add Core/AuraState.lua
git commit -m "$(cat <<'EOF'
feat(aurastate): add GetHelpfulClassified / GetHarmfulClassified

A1 (#136) read methods. Mirrors the existing GetHelpful / GetHarmful
view-rebuild pattern — check view.dirty, rebuild from _helpfulById
with classify() on cache miss, reuse entries across generations when
not invalidated. No element consumes these yet.
EOF
)"
git push origin working-testing
```

---

## Task 4: Add `GetClassifiedByInstanceID`

**Files:**
- Modify: `Core/AuraState.lua` — append after `GetHarmfulClassified`

Per the spec's "Components and APIs" section. Single-entry accessor for the planned B3 Buffs per-indicator resolution path. Falls through helpful → harmful stores; lazy-classifies on cache miss.

- [ ] **Step 1: Insert `GetClassifiedByInstanceID` method**

Edit `Core/AuraState.lua` — find the end of `GetHarmfulClassified` (just added in Task 3) followed by `function F.AuraState.Create(owner)`. Insert between them:

```lua
	return view.list
end

--- Wrapper entry for a single aura instance ID, or nil.
--- Planned primary consumer: B3 Buffs (#139) per-indicator spellID resolution.
--- @param instanceID number
--- @return table|nil   -- { aura, flags } or nil if not tracked on this unit
function AuraState:GetClassifiedByInstanceID(instanceID)
	if(not instanceID or not self._unit) then
		return nil
	end

	local entry = self._helpfulClassifiedById[instanceID]
	if(entry) then
		return entry
	end
	entry = self._harmfulClassifiedById[instanceID]
	if(entry) then
		return entry
	end

	-- Cache miss — look up in the raw stores and classify lazily.
	local aura = self._helpfulById[instanceID]
	if(aura) then
		entry = classify(self._unit, aura, true)
		self._helpfulClassifiedById[instanceID] = entry
		return entry
	end
	aura = self._harmfulById[instanceID]
	if(aura) then
		entry = classify(self._unit, aura, false)
		self._harmfulClassifiedById[instanceID] = entry
		return entry
	end

	return nil
end

function F.AuraState.Create(owner)
```

- [ ] **Step 2: `/reload` and verify no errors**

Run: `/reload`. Expected: no errors. Method defined, no caller.

- [ ] **Step 3: Commit and push**

```bash
git add Core/AuraState.lua
git commit -m "$(cat <<'EOF'
feat(aurastate): add GetClassifiedByInstanceID

A1 (#136) single-entry accessor. Falls through helpful → harmful
classified stores; lazy-classifies on cache miss. Shipped for B3 Buffs
(#139) per-indicator resolution and possible B6 StatusText (#142)
delta-payload processing; no caller in A1 itself.
EOF
)"
git push origin working-testing
```

---

## Task 5: Add classified-store invalidation methods

**Files:**
- Modify: `Core/AuraState.lua` — insert after existing `MarkHarmfulDirty` (ends at line 76)

Per the spec's "UNIT_AURA write path" section. Four methods parallel to `InvalidateHelpfulMatch` / `MarkHelpfulDirty` / `InvalidateHarmfulMatch` / `MarkHarmfulDirty`.

- [ ] **Step 1: Locate insertion point**

Run: look at `Core/AuraState.lua` — find the end of `function AuraState:MarkHarmfulDirty()` block (ends around line 76), followed by `function AuraState:EnsureHelpfulView(filter)`.

- [ ] **Step 2: Insert four invalidation methods**

Edit `Core/AuraState.lua` — find:

```lua
function AuraState:MarkHarmfulDirty()
	for _, view in next, self._harmfulViews do
		view.dirty = true
	end
end

function AuraState:EnsureHelpfulView(filter)
```

Replace with:

```lua
function AuraState:MarkHarmfulDirty()
	for _, view in next, self._harmfulViews do
		view.dirty = true
	end
end

function AuraState:InvalidateHelpfulClassified(auraInstanceID)
	self._helpfulClassifiedById[auraInstanceID] = nil
end

function AuraState:InvalidateHarmfulClassified(auraInstanceID)
	self._harmfulClassifiedById[auraInstanceID] = nil
end

function AuraState:MarkHelpfulClassifiedDirty()
	self._helpfulClassifiedView.dirty = true
end

function AuraState:MarkHarmfulClassifiedDirty()
	self._harmfulClassifiedView.dirty = true
end

function AuraState:EnsureHelpfulView(filter)
```

- [ ] **Step 3: `/reload` and verify no errors**

Run: `/reload`. Expected: no errors. Methods defined, write path still uses only legacy invalidation.

- [ ] **Step 4: Commit and push**

```bash
git add Core/AuraState.lua
git commit -m "$(cat <<'EOF'
feat(aurastate): add classified invalidation methods

A1 (#136) invalidation API. Four methods mirror the existing
Invalidate*Match / Mark*Dirty pair — separate per-ID invalidation
from view-dirty marking so ApplyUpdateInfo can batch dirty-marks.
Not yet called from the write path.
EOF
)"
git push origin working-testing
```

---

## Task 6: Wire invalidation into `FullRefresh` and `ApplyUpdateInfo`

**Files:**
- Modify: `Core/AuraState.lua` — `FullRefresh` (lines 120-130) and `ApplyUpdateInfo` (lines 185-246)

This is the task that makes the classified stores actually correct under aura mutations. Ten insertion points total.

- [ ] **Step 1: Update `FullRefresh` to wipe classified stores and mark views dirty**

Edit `Core/AuraState.lua` — find the header of `FullRefresh`:

```lua
function AuraState:FullRefresh(unit)
	self._unit = unit
	self._initialized = true
	self._gen = F.AuraCache.GetGeneration(unit)
	wipe(self._helpfulById)
	wipe(self._harmfulById)
	self:ResetHelpfulMatches()
	self:ResetHarmfulMatches()
	self:MarkHelpfulDirty()
	self:MarkHarmfulDirty()
```

Replace with:

```lua
function AuraState:FullRefresh(unit)
	self._unit = unit
	self._initialized = true
	self._gen = F.AuraCache.GetGeneration(unit)
	wipe(self._helpfulById)
	wipe(self._harmfulById)
	wipe(self._helpfulClassifiedById)
	wipe(self._harmfulClassifiedById)
	self:ResetHelpfulMatches()
	self:ResetHarmfulMatches()
	self:MarkHelpfulDirty()
	self:MarkHarmfulDirty()
	self:MarkHelpfulClassifiedDirty()
	self:MarkHarmfulClassifiedDirty()
```

- [ ] **Step 2: Add classified-invalidate calls to the `addedAuras` loop**

Find in `ApplyUpdateInfo`:

```lua
	if(updateInfo.addedAuras) then
		for _, aura in next, updateInfo.addedAuras do
			if(aura and aura.auraInstanceID and isHelpfulAura(unit, aura)) then
				self._helpfulById[aura.auraInstanceID] = aura
				self:InvalidateHelpfulMatch(aura.auraInstanceID)
				helpfulChanged = true
			end
			if(aura and aura.auraInstanceID and isHarmfulAura(unit, aura)) then
				self._harmfulById[aura.auraInstanceID] = aura
				self:InvalidateHarmfulMatch(aura.auraInstanceID)
				harmfulChanged = true
			end
		end
	end
```

Replace with:

```lua
	if(updateInfo.addedAuras) then
		for _, aura in next, updateInfo.addedAuras do
			if(aura and aura.auraInstanceID and isHelpfulAura(unit, aura)) then
				self._helpfulById[aura.auraInstanceID] = aura
				self:InvalidateHelpfulMatch(aura.auraInstanceID)
				self:InvalidateHelpfulClassified(aura.auraInstanceID)
				helpfulChanged = true
			end
			if(aura and aura.auraInstanceID and isHarmfulAura(unit, aura)) then
				self._harmfulById[aura.auraInstanceID] = aura
				self:InvalidateHarmfulMatch(aura.auraInstanceID)
				self:InvalidateHarmfulClassified(aura.auraInstanceID)
				harmfulChanged = true
			end
		end
	end
```

- [ ] **Step 3: Add classified-invalidate calls to the `updatedAuraInstanceIDs` loop**

Find:

```lua
	if(updateInfo.updatedAuraInstanceIDs and GetAuraDataByAuraInstanceID) then
		for _, auraInstanceID in next, updateInfo.updatedAuraInstanceIDs do
			local aura = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
			if(aura and aura.auraInstanceID and isHelpfulAura(unit, aura)) then
				self._helpfulById[auraInstanceID] = aura
				self:InvalidateHelpfulMatch(auraInstanceID)
				helpfulChanged = true
			elseif(self._helpfulById[auraInstanceID]) then
				self._helpfulById[auraInstanceID] = nil
				self:InvalidateHelpfulMatch(auraInstanceID)
				helpfulChanged = true
			end

			if(aura and aura.auraInstanceID and isHarmfulAura(unit, aura)) then
				self._harmfulById[auraInstanceID] = aura
				self:InvalidateHarmfulMatch(auraInstanceID)
				harmfulChanged = true
			elseif(self._harmfulById[auraInstanceID]) then
				self._harmfulById[auraInstanceID] = nil
				self:InvalidateHarmfulMatch(auraInstanceID)
				harmfulChanged = true
			end
		end
	end
```

Replace with:

```lua
	if(updateInfo.updatedAuraInstanceIDs and GetAuraDataByAuraInstanceID) then
		for _, auraInstanceID in next, updateInfo.updatedAuraInstanceIDs do
			local aura = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
			if(aura and aura.auraInstanceID and isHelpfulAura(unit, aura)) then
				self._helpfulById[auraInstanceID] = aura
				self:InvalidateHelpfulMatch(auraInstanceID)
				self:InvalidateHelpfulClassified(auraInstanceID)
				helpfulChanged = true
			elseif(self._helpfulById[auraInstanceID]) then
				self._helpfulById[auraInstanceID] = nil
				self:InvalidateHelpfulMatch(auraInstanceID)
				self:InvalidateHelpfulClassified(auraInstanceID)
				helpfulChanged = true
			end

			if(aura and aura.auraInstanceID and isHarmfulAura(unit, aura)) then
				self._harmfulById[auraInstanceID] = aura
				self:InvalidateHarmfulMatch(auraInstanceID)
				self:InvalidateHarmfulClassified(auraInstanceID)
				harmfulChanged = true
			elseif(self._harmfulById[auraInstanceID]) then
				self._harmfulById[auraInstanceID] = nil
				self:InvalidateHarmfulMatch(auraInstanceID)
				self:InvalidateHarmfulClassified(auraInstanceID)
				harmfulChanged = true
			end
		end
	end
```

- [ ] **Step 4: Add classified-invalidate calls to the `removedAuraInstanceIDs` loop**

Find:

```lua
	if(updateInfo.removedAuraInstanceIDs) then
		for _, auraInstanceID in next, updateInfo.removedAuraInstanceIDs do
			if(self._helpfulById[auraInstanceID]) then
				self._helpfulById[auraInstanceID] = nil
				self:InvalidateHelpfulMatch(auraInstanceID)
				helpfulChanged = true
			end
			if(self._harmfulById[auraInstanceID]) then
				self._harmfulById[auraInstanceID] = nil
				self:InvalidateHarmfulMatch(auraInstanceID)
				harmfulChanged = true
			end
		end
	end
```

Replace with:

```lua
	if(updateInfo.removedAuraInstanceIDs) then
		for _, auraInstanceID in next, updateInfo.removedAuraInstanceIDs do
			if(self._helpfulById[auraInstanceID]) then
				self._helpfulById[auraInstanceID] = nil
				self:InvalidateHelpfulMatch(auraInstanceID)
				self:InvalidateHelpfulClassified(auraInstanceID)
				helpfulChanged = true
			end
			if(self._harmfulById[auraInstanceID]) then
				self._harmfulById[auraInstanceID] = nil
				self:InvalidateHarmfulMatch(auraInstanceID)
				self:InvalidateHarmfulClassified(auraInstanceID)
				harmfulChanged = true
			end
		end
	end
```

- [ ] **Step 5: Add classified dirty-mark at the end of `ApplyUpdateInfo`**

Find the tail of `ApplyUpdateInfo`:

```lua
	if(helpfulChanged) then
		self:MarkHelpfulDirty()
	end
	if(harmfulChanged) then
		self:MarkHarmfulDirty()
	end
end
```

Replace with:

```lua
	if(helpfulChanged) then
		self:MarkHelpfulDirty()
		self:MarkHelpfulClassifiedDirty()
	end
	if(harmfulChanged) then
		self:MarkHarmfulDirty()
		self:MarkHarmfulClassifiedDirty()
	end
end
```

- [ ] **Step 6: `/reload` and verify classified stores stay correct under aura mutations**

Run: `/reload`. Expected: no errors. Cast a self-buff (e.g., as Paladin, Blessing of the Seasons; as any class, eat/drink to trigger Food). In the chat, run:

```
/run local pf = FramedAddon.Units.Player.frame; local s = pf and pf.FramedAuraState; if s then print('helpful count:', #s:GetHelpfulClassified()) else print('no aurastate') end
```

Expected: prints the number of helpful auras on player; count updates correctly as you add/remove buffs (re-run the command after each mutation). No errors, no stale counts.

- [ ] **Step 7: Commit and push**

```bash
git add Core/AuraState.lua
git commit -m "$(cat <<'EOF'
feat(aurastate): wire classified invalidation into write path

A1 (#136) core wiring. FullRefresh wipes classified stores and marks
both views dirty. ApplyUpdateInfo invalidates per-ID classified
entries in addedAuras/updatedAuraInstanceIDs/removedAuraInstanceIDs
branches and marks views dirty when helpfulChanged/harmfulChanged.
Classified reads now return fresh data on every UNIT_AURA mutation.
EOF
)"
git push origin working-testing
```

---

## Task 7: Add `/framed aurastate <unit>` debug slash

**Files:**
- Modify: `Core/AuraState.lua` — append `F.AuraState.PrintDebug` at bottom of file
- Modify: `Init.lua:421` — new `elseif(cmd == 'aurastate')` case before help block
- Modify: `Init.lua:422-431` — add help line in the `help` case

Per the spec's "Debug slash: `/framed aurastate <unit>`" section.

- [ ] **Step 1: Append `PrintDebug` function to `Core/AuraState.lua`**

Edit `Core/AuraState.lua` — the file currently ends at line 327 with `end` closing `F.AuraState.Create`. Append below that:

```lua

-- =================================================================
-- Debug: /framed aurastate <unit>
-- =================================================================

local function classifyFlagsString(flags)
	local parts = {}
	if(flags.isPlayerCast)        then parts[#parts + 1] = 'player-cast'        end
	if(flags.isExternalDefensive) then parts[#parts + 1] = 'external-defensive' end
	if(flags.isBigDefensive)      then parts[#parts + 1] = 'big-defensive'      end
	if(flags.isImportant)         then parts[#parts + 1] = 'important'          end
	if(flags.isRaid)              then parts[#parts + 1] = 'raid'               end
	if(flags.isBossAura)          then parts[#parts + 1] = 'boss'               end
	if(flags.isFromPlayerOrPet)   then parts[#parts + 1] = 'from-player'        end
	return table.concat(parts, ', ')
end

local function printEntry(entry)
	local aura = entry.aura
	local name = (F.IsValueNonSecret and F.IsValueNonSecret(aura.name)) and aura.name or '(secret)'
	local flags = classifyFlagsString(entry.flags)
	local dispel = aura.dispelName and ('  [dispel: ' .. aura.dispelName .. ']') or ''
	print(('    [%d]  %-22s [%s]%s'):format(aura.auraInstanceID, name, flags, dispel))
end

function F.AuraState.PrintDebug(unit)
	unit = (unit and unit ~= '') and unit or 'target'
	if(not UnitExists(unit)) then
		print('|cff00ccff[Framed/aurastate]|r unit "' .. unit .. '" does not exist')
		return
	end

	local state = F.AuraState.Create('slash')
	state:FullRefresh(unit)

	local gen = F.AuraCache.GetGeneration(unit)
	print(('|cff00ccff[Framed/aurastate]|r %s  (gen %d)'):format(unit, gen))

	local helpful = state:GetHelpfulClassified()
	print(('  HELPFUL (%d):'):format(#helpful))
	for _, entry in next, helpful do
		printEntry(entry)
	end

	local harmful = state:GetHarmfulClassified()
	print(('  HARMFUL (%d):'):format(#harmful))
	for _, entry in next, harmful do
		printEntry(entry)
	end
end
```

- [ ] **Step 2: Add `aurastate` case to the `/framed` dispatcher**

Edit `Init.lua` — find around line 414-421:

```lua
	elseif(cmd == 'testimport') then
		local encoded, err = generateSyntheticImportString()
		if(not encoded) then
			print('|cff00ccff Framed|r testimport failed: ' .. (err or 'unknown error'))
			return
		end
		showTestImportPopup(encoded)
	elseif(cmd == 'help') then
```

Replace with:

```lua
	elseif(cmd == 'testimport') then
		local encoded, err = generateSyntheticImportString()
		if(not encoded) then
			print('|cff00ccff Framed|r testimport failed: ' .. (err or 'unknown error'))
			return
		end
		showTestImportPopup(encoded)
	elseif(cmd == 'aurastate') then
		F.AuraState.PrintDebug(arg1)
	elseif(cmd == 'help') then
```

- [ ] **Step 3: Add help line to the `help` block**

Edit `Init.lua` — find the tail of the help block around lines 430-431:

```lua
		print('  /framed debugicons — Debug indicator element state')
		print('  /framed testimport — Generate a synthetic-diff import string for testing backfill')
	else
```

Replace with:

```lua
		print('  /framed debugicons — Debug indicator element state')
		print('  /framed testimport — Generate a synthetic-diff import string for testing backfill')
		print('  /framed aurastate [unit] — Print classified aura state for unit (default: target)')
	else
```

- [ ] **Step 4: `/reload` and verify slash works**

Run: `/reload`. Then:

1. `/framed help` → expected: lists the new `aurastate` line.
2. `/framed aurastate` (no args) → expected: prints `[Framed/aurastate] target  (gen N)` followed by HELPFUL and HARMFUL sections for your current target (or an "does not exist" message if no target).
3. `/framed aurastate player` → expected: prints player's own auras, HELPFUL includes any active buffs (Food, Drinking, self-buffs).
4. `/framed aurastate bogusunit` → expected: `unit "bogusunit" does not exist` message, no errors.
5. `/framed aurastate party2target` → expected: runs cleanly; HELPFUL/HARMFUL counts likely 0 because `isCompoundUnit` short-circuits `FullRefresh`.

- [ ] **Step 5: Commit and push**

```bash
git add Core/AuraState.lua Init.lua
git commit -m "$(cat <<'EOF'
feat(aurastate): add /framed aurastate <unit> debug slash

A1 (#136) observable surface. Prints classified helpful + harmful
entries with active flag slugs and dispel type. Uses
F.IsValueNonSecret for aura names — secret names print as "(secret)".
Throwaway AuraState instance per call; no shared state with frame
AuraStates.
EOF
)"
git push origin working-testing
```

---

## Task 8: Live smoke test + PR

**Files:** none. This task is manual verification against the spec's A1 acceptance checklist, followed by opening the PR.

No code changes in this task. If any verification fails, the failing piece becomes a bugfix commit before PR.

- [ ] **Step 1: Run the correctness checklist per spec section "A1 acceptance"**

For each scenario below, run `/framed aurastate <unit>` and confirm the flags match. Cross-check visually with the relevant element (Externals/Defensives) to confirm classification matches what elements expect:

| Scenario | Expected flags on the aura entry |
|----------|----------------------------------|
| Empty target | Empty HELPFUL and HARMFUL lists, `gen ≥ 1` |
| Power Word: Shield on you (any source) | `isExternalDefensive`, `isImportant` |
| Power Word: Shield cast by you on yourself | Above + `isPlayerCast` |
| Ironbark on you | `isExternalDefensive`, `isBigDefensive`, `isFromPlayerOrPet` (if druid is in party) |
| Blessing of Protection on you by another paladin | `isExternalDefensive`, `isImportant`, `isPlayerCast=false` |
| Self Devotion Aura | `isHelpful`, `isRaid`, `isPlayerCast` |
| Boss DoT on you | `isHarmful`, `isBossAura` |
| Dispellable magic debuff from arena opponent | `isHarmful`, `isImportant`, `[dispel: Magic]` appended |
| `/reload` during combat | Same classifications pre vs. post-reload; gen counter restarts but first read classifies correctly |

- [ ] **Step 2: Run the non-regression checklist**

- Every existing element (Externals, Defensives, Buffs, Debuffs, MissingBuffs, StatusText) renders identically to pre-A1 — no visual changes.
- `/framed events` shows UNIT_AURA registered once, no duplicates.
- No Lua errors in a 10-minute session including: target dummy rotation + 5-man heroic dungeon. Watch the BugSack / default error frame carefully.

- [ ] **Step 3: Verify encounter-boundary behavior (if available during session)**

If a raid boss encounter is accessible during the test window:

1. Engage the boss (triggers `ENCOUNTER_START` at `Core/AuraCache.lua:73-79`).
2. Run `/framed aurastate player`.
3. Confirm: the aura instance IDs are fresh (not stale from pre-pull), flags match expected.
4. On `ENCOUNTER_END` (boss kill or wipe), run again — still correct.

If no raid access this session, note it as "encounter-boundary verification deferred to next raid night" in the PR description. `Core/AuraCache.lua:73-79` already handles the bump per `project memory`; the risk is just live confirmation.

- [ ] **Step 4: Profiler snapshot — A1 overhead check**

In game:

```
/console scriptProfile 1
/reload
```

Run around normally for ~60 seconds in a target-dummy or low-churn scenario, then:

```
/dump GetAddOnCPUUsage('Framed')
```

Compare against the baseline of `~0.448ms` from `project_framed` memory. Expected: within ~5% of baseline. Higher is acceptable for A1 (classify runs on first-reader-per-generation for each aura, but no element reads the classified API yet — overhead should be near zero). If significantly higher, investigate classify hotspots but not a hard block for PR.

- [ ] **Step 5: Open PR from `working-testing` to `main`**

```bash
gh pr create --base main --head working-testing --title "feat(aurastate): classification layer (A1 / #136)" --body "$(cat <<'EOF'
## Summary

Foundation for the UNIT_AURA fan-out rearchitecture (parent #115).

- New per-instance classified stores on `AuraState` (`_helpfulClassifiedById`, `_harmfulClassifiedById`, plus views)
- Module-local `classify(unit, aura, isHelpful)` helper — 5 structural passthroughs + 4 C-probe flags
- Three read methods: `GetHelpfulClassified`, `GetHarmfulClassified`, `GetClassifiedByInstanceID`
- Four invalidation methods wired into `FullRefresh` + `ApplyUpdateInfo`
- New `/framed aurastate <unit>` debug slash for live verification

Behavior-neutral for all current elements — they keep consuming `GetHelpful(filter)` / `GetHarmful(filter)`. The B-series (#137-#142) migrates individual elements to read flags directly.

Spec: `docs/superpowers/specs/2026-04-21-unit-aura-fanout-rearchitecture-design.md`

## Test plan

- [x] `/framed aurastate target` — correctness checklist (9 scenarios)
- [x] Non-regression: every existing aura element renders identically
- [x] No Lua errors in 10-minute combat session (dummy + 5-man)
- [ ] Encounter-boundary verification (raid boss ENCOUNTER_START / ENCOUNTER_END) — [deferred to next raid night if not tested this session]
- [x] Profiler: A1 overhead within 5% of 0.448ms baseline

Closes #136.
EOF
)"
```

- [ ] **Step 6: Link issue + close**

After PR merges to main and the 24-48h live-use window passes without reports, close issue #136 with a comment citing the PR. A1 is live; next up is B6 (#142 StatusText).

---

## Self-Review

Ran after drafting the plan.

**Spec coverage** — each spec requirement mapped:

- "Module-local `classify(unit, aura, isHelpful)`" → Task 2 ✓
- "Per-instance state additions in `F.AuraState.Create`" → Task 1 ✓
- "New instance methods: `GetHelpfulClassified`, `GetHarmfulClassified`, `GetClassifiedByInstanceID`" → Tasks 3, 4 ✓
- "New invalidation methods (4)" → Task 5 ✓
- "Write-path additions in `FullRefresh`, `ApplyUpdateInfo`" → Task 6 ✓
- "New `/framed aurastate` case in slash dispatcher" → Task 7 ✓
- "Debug slash output format" → Task 7 ✓
- A1 acceptance checklist (9 scenarios) → Task 8 Step 1 ✓
- Non-regression checklist → Task 8 Step 2 ✓
- Encounter boundary verification → Task 8 Step 3 ✓
- Rollback safety (A1 alone is rollback-safe) → Implicit via per-task commits ✓

**Placeholder scan** — no "TBD", "TODO", "similar to Task N" shortcuts. Every code block is copy-pasteable.

**Type consistency** — `classify()` returns `{ aura, flags }` with 9 flag keys (5 Tier 1 + 4 Tier 2). `GetHelpfulClassified` / `GetHarmfulClassified` / `GetClassifiedByInstanceID` all return this shape (or nil for the ID accessor's miss case). `isFromPlayerOrPlayerPet` on `AuraData` maps to `isFromPlayerOrPet` on `flags` (deliberate rename — shorter, matches common WoW addon convention). `flags.isBigDefensive` is always `false` for harmful entries (spec invariant). Signatures in Tasks 3-7 match Task 2's definition.

---

## B-series and C1 plans

**Not included in this plan.** Each B-issue (B1 through B6) and C1 will get its own plan, written when the issue is picked up. This matches the spec's per-element gate model — the plan for B1 Externals depends on observations from A1's live behavior (actual classify() cost, whether flag-table churn is visible on profile, whether the spec's expected flag combinations match what `IsAuraFilteredOutByInstanceID` actually returns in edge cases). Locking in B-plans before A1 ships would risk re-writing them all after A1 lands.

Next plan to write (after A1 merges): `2026-04-21-b6-statustext-migration.md` — the smallest B-issue, used as smoke test for the classified-flag read pattern.
