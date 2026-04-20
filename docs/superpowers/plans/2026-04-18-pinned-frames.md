# Pinned Frames Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement name-tracking "pinned" unit frames — up to 9 standalone frames that watch specific group members by name, following players across roster reshuffles, with role-grouped class-colored assignment UI in both the Settings card and on the live frames, full aura configuration as a first-class unit type, and EditMode integration.

**Architecture:** Nine frames pre-spawned via `oUF:Spawn('player', 'FramedPinnedN')` once at addon load (placeholder unit replaced via `SetAttribute('unit', ...)` immediately after resolution). A resolver scans the roster on `GROUP_ROSTER_UPDATE`, matches stored names to current unit tokens, and mirrors both the secure attribute and `frame.unit`. Static tokens (`focus`, `focustarget`) and derived tokens (`nametarget`) are supported. A throttled `OnUpdate` (0.2s, GUID-diff) handles `focustarget`/`nametarget`. Layout is a grid anchored off `F.Units.Pinned.anchor`. All assignment changes during combat are queued and flushed on `PLAYER_REGEN_ENABLED`. Frames are tagged with `_framedUnitType = 'pinned'` so the generic `FrameConfigPreset` handler picks them up on preset activation. Aura config lives at `presets.<name>.auras.pinned` and appears in the Auras panel's unit-type dropdown via `Settings._getUnitTypeItems()`.

**Tech Stack:** Lua 5.1, WoW Interface 12.0.0/12.0.1, embedded oUF (`F.oUF`), Framed conventions (tabs, `if(cond) then`, single quotes, `for _, v in next, tbl do`), Framed Config API + EventBus + StyleBuilder + FrameSettingsBuilder + Widgets (`CreateDropdown`, `StartCard`/`EndCard`, `CreateCardGrid`).

**Reference files in this codebase:**
- `Units/Boss.lua` — simplest multi-frame pattern
- `Units/Party.lua` — combat-deferred layout
- `Units/LiveUpdate/FrameConfigLayout.lua` — CONFIG_CHANGED blueprint
- `Units/LiveUpdate/FrameConfigPreset.lua:460` — PRESET_CHANGED generic handler (already iterates `_framedUnitType`-tagged frames)
- `Units/LiveUpdate/FrameConfigShared.lua` — `guardConfigChanged`, `debouncedApply`, `applyOrQueue`
- `Settings/Panels/Boss.lua` — thin panel wrapper template
- `Settings/Panels/Buffs.lua` — aura panel structure (reference for what the 10 aura panels share)
- `Settings/Framework.lua:104` — `Settings._getUnitTypeItems()` (where pinned must appear)
- `Settings/FrameSettingsBuilder.lua` — shared preview/summary/card layout
- `Widgets/Dropdown.lua:492` — `_decorateRow` hook for custom row rendering
- `Presets/Defaults.lua:408` — `F.PresetDefaults.GetAll()` preset factory
- `Presets/AuraDefaults.lua:299` — `F.AuraDefaults.Group(sizes)`
- `EditMode/EditMode.lua:37-47` — `FRAME_KEYS` registry
- `Core/Constants.lua:96` — `PresetInfo`

---

## File Structure

**New files:**
- `Units/Pinned.lua` (~500 lines) — Style, Spawn, resolver, combat deferral, grid layout, refreshOnUpdate, slot identity label, placeholder overlays, reassign hover gear, EditMode click hook
- `Units/LiveUpdate/FrameConfigPinned.lua` (~90 lines) — CONFIG_CHANGED + PRESET_CHANGED handlers
- `Settings/Panels/Pinned.lua` (~15 lines) — sidebar registration
- `Settings/Cards/Pinned.lua` (~220 lines) — per-slot assignment list with role-grouped dropdown

**Modified files:**
- `Presets/Defaults.lua` — add `pinnedConfig()`, register in Party/Raid/Arena + derived; add `auras.pinned` to each
- `Presets/AuraDefaults.lua` — no structural change (pinned reuses `F.AuraDefaults.Group`)
- `Settings/Framework.lua` — extend `Settings._getUnitTypeItems()` to include `pinned` when active preset has `auras.pinned`
- `Settings/FrameSettingsBuilder.lua` — register `pinned` in `GROUP_TYPES`/`GROUP_COUNTS`, per-unit-type branches
- `EditMode/EditMode.lua` — add entry to `FRAME_KEYS`; ensure inline settings panel opens on click
- `Framed.toc` — register new files in load order
- `Init.lua` — `F.Units.Pinned.Spawn()` call in `oUF:Factory`

---

## Design Decisions Made During Planning

**These are deviations or clarifications from the spec that the engineer should know about:**

1. **Right-click reassignment → gear-icon-on-hover instead.** The spec says "Right-click assigned pin: opens dropdown to reassign/unassign." But Framed frames already bind `*type2` via click-casting (`ClickCasting/ClickCasting.lua:34,255`) for `togglemenu` by default, user-rebindable. Adding a plain right-click reassign handler would collide with the user's click-cast bindings and with Blizzard's unit context menu. **Resolution:** Show a small gear icon in the top-right corner of each assigned pin when hovered AND out of combat. Left-click the gear → dropdown opens. The underlying frame's right-click remains fully available for click-casting.

2. **Empty-slot placeholders stay non-secure.** Placeholders for unassigned slots are non-secure frames (dashed border + "+ Click to assign" hint). Left-click opens the dropdown. Since they're non-secure, they work in combat too — but assignment itself is combat-deferred via `pendingResolve`.

3. **EditMode click-to-configure.** The spec says "Clicking a pinned frame in edit mode opens the standard inline settings panel." This is the first time pinned needs this, so Task 11 adds the EditMode click hook. Verify whether Framed's EditMode already supports click-to-configure for other unit types — if so, pinned piggybacks on that path.

4. **Aura config path is `presets.<name>.auras.pinned`** — confirmed by reading `Presets/Defaults.lua:427,471,490,498` (auras live at the top-level `auras.<unitType>` table, NOT inside `unitConfigs`).

5. **Pinned appears in the aura unit-type dropdown via `Settings._getUnitTypeItems()`**, not by registering 10 new aura panels. The existing 10 aura panels (`Buffs`, `Debuffs`, `Defensives`, `Dispels`, etc.) already dispatch on `Settings.GetEditingUnitType()` — extending the unit-type list is the single point of change.

---

## Testing Approach

**No unit test harness for WoW addon behavior.** Verification is:

1. **Lua syntax check** — `luac -p <file>` (parses without executing)
2. **`/reload` in WoW** — addon loads without errors
3. **Manual scenario verification** — specific in-game interaction steps

Each task lists verification commands. Run them in the order given; if any fail, stop and fix before proceeding.

**Standing setup:** Sync `/Users/josiahtoppin/Documents/Projects/Framed/` into the WoW `Interface/AddOns/Framed/` folder before each `/reload`. Per user's `feedback_wow_sync.md` memory.

---

## Task 1: Add `pinnedConfig()` defaults and `auras.pinned` in group presets

**Why first:** Every downstream task reads these paths via `F.Config:Get`. `EnsureDefaults`/`DeepMerge` must backfill to existing SavedVariables before any code runs.

**Files:**
- Modify: `Presets/Defaults.lua`

- [ ] **Step 1: Add `pinnedConfig()` helper**

Open `Presets/Defaults.lua`. Immediately below the `baseUnitConfig()` closing `end`, add:

```lua
-- Pinned frames: shared style across up to 9 slots, per-slot name-tracking.
-- Opt-in by default (enabled = false). Solo preset omits this block entirely.
local function pinnedConfig()
	local cfg = baseUnitConfig()
	cfg.enabled  = false
	cfg.count    = 3
	cfg.columns  = 3
	cfg.width    = 160
	cfg.height   = 40
	cfg.spacing  = 2
	cfg.slots    = {}  -- keys 1..9; nil = unassigned
	cfg.position = { x = 0, y = 0, anchor = 'CENTER' }
	return cfg
end
```

- [ ] **Step 2: Register `pinned` in Party preset's `unitConfigs`**

Find the Party preset block (around line 430). Inside `unitConfigs = { ... }`, add:

```lua
pinned = pinnedConfig(),
```

- [ ] **Step 3: Register `pinned` in Party preset's `auras`**

The Party preset builds `partyAuras` before the block. Locate the `partyAuras.party = A.Group(PARTY_AURA_SIZES)` line (around line 428). Add below it:

```lua
partyAuras.pinned = A.Group(PARTY_AURA_SIZES)
```

- [ ] **Step 4: Register `pinned` in Raid preset**

Same as Steps 2-3 for the Raid preset block (around line 474). Add `pinned = pinnedConfig()` inside `unitConfigs`, and after `raidAuras.raid = A.Group(RAID_AURA_SIZES)`:

```lua
raidAuras.pinned = A.Group(RAID_AURA_SIZES)
```

- [ ] **Step 5: Register `pinned` in Arena preset**

Same pattern (block around line 500). Add `pinned = pinnedConfig()` inside `unitConfigs`, and after `arenaAuras.arena = A.Arena()`:

```lua
arenaAuras.pinned = A.Group(PARTY_AURA_SIZES)
```

- [ ] **Step 6: Verify derived presets inherit via DeepCopy**

Read `F.PresetDefaults.GetAll` lines 524-531 — derived presets copy from Raid via `F.DeepCopy`. Since Raid now has `pinned` in both `unitConfigs` and `auras`, derived presets inherit automatically. No code change required.

- [ ] **Step 7: Verify Solo preset has NO pinned block**

Lines 411-424: confirm Solo's `unitConfigs` contains no `pinned` key and `auras = soloUnitAuras()` has no `pinned` sub-table (because `soloUnitAuras()` returns the base aura set without group extensions).

- [ ] **Step 8: Syntax check**

```bash
luac -p /Users/josiahtoppin/Documents/Projects/Framed/Presets/Defaults.lua
```

Expected: no output.

- [ ] **Step 9: `/reload` test**

Sync + `/reload`. No errors. Run `/framed config` — presets list should show Party/Raid/Arena.

- [ ] **Step 10: Verify SavedVariables backfill**

```
/dump FramedDB.presets.Party.unitConfigs.pinned
/dump FramedDB.presets.Party.auras.pinned
```

Both should print populated tables (pinned.enabled = false, auras.pinned = the Group aura set).

- [ ] **Step 11: Commit**

```bash
cd /Users/josiahtoppin/Documents/Projects/Framed
git add Presets/Defaults.lua
git commit -m "feat(pinned): add pinnedConfig and auras.pinned defaults"
git push
```

---

## Task 2: Minimal `Units/Pinned.lua` — Style, Spawn, grid layout (placeholder unit)

**Why next:** Simplest testable checkpoint — frames on screen with a known placeholder unit. Proves TOC wiring, oUF integration, anchor setup, and layout math before resolver complexity.

**Files:**
- Create: `Units/Pinned.lua`
- Modify: `Framed.toc`
- Modify: `Init.lua`

- [ ] **Step 1: Create `Units/Pinned.lua` skeleton**

```lua
local _, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units        = F.Units        or {}
F.Units.Pinned = F.Units.Pinned or {}

local MAX_SLOTS = 9

-- ============================================================
-- Config accessor
-- ============================================================
function F.Units.Pinned.GetConfig()
	local presetName = F.PresetManager and F.PresetManager.GetActive()
	if(not presetName) then return nil end
	return F.Config:Get('presets.' .. presetName .. '.unitConfigs.pinned')
end

-- ============================================================
-- Style
-- ============================================================
local function Style(self, unit)
	self:SetFrameStrata('LOW')
	self:RegisterForClicks('AnyUp')
	self._framedUnitType = 'pinned'

	local config = F.Units.Pinned.GetConfig()
	if(config) then
		F.Widgets.SetSize(self, config.width or 160, config.height or 40)
		F.StyleBuilder.Apply(self, config, 'pinned')
	else
		F.Widgets.SetSize(self, 160, 40)
	end

	F.Widgets.RegisterForUIScale(self)
end

-- ============================================================
-- Position
-- ============================================================
function F.Units.Pinned.ApplyPosition()
	local anchor = F.Units.Pinned.anchor
	if(not anchor) then return end
	local config = F.Units.Pinned.GetConfig()
	local pos = (config and config.position) or { x = 0, y = 0, anchor = 'CENTER' }
	anchor:ClearAllPoints()
	anchor:SetPoint(pos.anchor or 'CENTER', UIParent, pos.anchor or 'CENTER', pos.x or 0, pos.y or 0)
end

-- ============================================================
-- Layout (grid)
-- ============================================================
function F.Units.Pinned.Layout()
	local anchor = F.Units.Pinned.anchor
	local frames = F.Units.Pinned.frames
	if(not anchor or not frames) then return end

	local config = F.Units.Pinned.GetConfig()
	if(not config or not config.enabled) then
		anchor:Hide()
		return
	end
	anchor:Show()

	local count   = math.max(1, math.min(config.count   or 3, MAX_SLOTS))
	local columns = math.max(1, math.min(config.columns or 3, count))
	local width   = config.width   or 160
	local height  = config.height  or 40
	local spacing = config.spacing or 2

	for i = 1, MAX_SLOTS do
		local f = frames[i]
		if(f) then
			if(i <= count) then
				local row = math.ceil(i / columns) - 1
				local col = ((i - 1) % columns)
				f:ClearAllPoints()
				f:SetPoint('TOPLEFT', anchor, 'TOPLEFT',
					col * (width + spacing),
					-(row * (height + spacing)))
				F.Widgets.SetSize(f, width, height)
				f:Show()
			else
				f:Hide()
			end
		end
	end

	local rows = math.ceil(count / columns)
	F.Widgets.SetSize(anchor,
		columns * width + (columns - 1) * spacing,
		rows    * height + (rows    - 1) * spacing)
end

-- ============================================================
-- Spawn
-- ============================================================
function F.Units.Pinned.Spawn()
	oUF:RegisterStyle('FramedPinned', Style)
	oUF:SetActiveStyle('FramedPinned')

	local anchor = CreateFrame('Frame', 'FramedPinnedAnchor', UIParent)
	F.Widgets.SetSize(anchor, 1, 1)
	F.Units.Pinned.anchor = anchor
	F.Units.Pinned.ApplyPosition()

	local frames = {}
	for i = 1, MAX_SLOTS do
		local frame = oUF:Spawn('player', 'FramedPinnedFrame' .. i)
		frame:SetParent(anchor)
		frames[i] = frame
	end
	F.Units.Pinned.frames = frames

	F.Units.Pinned.Layout()
end
```

- [ ] **Step 2: Register in `Framed.toc`**

After `Units/Arena.lua`, add:

```
Units/Pinned.lua
```

- [ ] **Step 3: Register spawn call in `Init.lua`**

In the `oUF:Factory(function(self) ... end)` block (around line 120), add after `F.Units.Arena.Spawn()`:

```lua
F.Units.Pinned.Spawn()
```

- [ ] **Step 4: Syntax check**

```bash
luac -p /Users/josiahtoppin/Documents/Projects/Framed/Units/Pinned.lua
luac -p /Users/josiahtoppin/Documents/Projects/Framed/Init.lua
```

Expected: no output.

- [ ] **Step 5: `/reload` + smoke test**

`/reload`. No errors. Frames hidden (enabled = false).

```
/run F.Config:Set('presets.Party.unitConfigs.pinned.enabled', true); F.Units.Pinned.Layout()
```

Expected: 3 frames in a 3x3 shape at screen center, each showing `'player'`.

- [ ] **Step 6: Disable and commit**

```
/run F.Config:Set('presets.Party.unitConfigs.pinned.enabled', false); F.Units.Pinned.Layout()
```

```bash
git add Units/Pinned.lua Framed.toc Init.lua
git commit -m "feat(pinned): spawn 9 frames with grid layout (placeholder unit)"
git push
```

---

## Task 3: Name-based unit resolver + combat deferral

**Why now:** Core feature — replace the placeholder `'player'` unit with real name-tracking.

**Files:**
- Modify: `Units/Pinned.lua`

- [ ] **Step 1: Add resolver helpers near the top of `Units/Pinned.lua` (after `MAX_SLOTS`)**

```lua
-- ============================================================
-- Roster / unit resolution
-- ============================================================

--- Convert UnitName(token) into storage format ('Name' or 'Name-Realm').
local function fullUnitName(token)
	if(not UnitExists(token)) then return nil end
	local name, realm = UnitName(token)
	if(not name) then return nil end
	if(realm and realm ~= '') then
		return name .. '-' .. realm
	end
	return name
end
F.Units.Pinned.FullUnitName = fullUnitName

--- Scan the current group for a player matching storedName.
local function findUnitForName(storedName)
	if(not storedName) then return nil end
	if(IsInRaid()) then
		for i = 1, GetNumGroupMembers() do
			if(fullUnitName('raid' .. i) == storedName) then
				return 'raid' .. i
			end
		end
	elseif(IsInGroup()) then
		for i = 1, GetNumGroupMembers() - 1 do
			if(fullUnitName('party' .. i) == storedName) then
				return 'party' .. i
			end
		end
		if(fullUnitName('player') == storedName) then
			return 'player'
		end
	else
		if(fullUnitName('player') == storedName) then
			return 'player'
		end
	end
	return nil
end
F.Units.Pinned.FindUnitForName = findUnitForName
```

- [ ] **Step 2: Add `setFrameUnit` helper**

```lua
--- Swap a frame's unit. Updates secure attribute + frame.unit mirror.
--- Combat-safe: returns false if InCombatLockdown prevents SetAttribute.
local function setFrameUnit(frame, token)
	if(InCombatLockdown()) then return false end
	if(token) then
		frame:SetAttribute('unit', token)
		frame.unit = token
	else
		frame:SetAttribute('unit', nil)
		frame.unit = nil
	end
	if(frame.UpdateAllElements) then
		frame:UpdateAllElements('RefreshUnit')
	end
	return true
end
```

- [ ] **Step 3: Add `Resolve` function**

```lua
local pendingResolve = false

function F.Units.Pinned.Resolve()
	if(InCombatLockdown()) then
		pendingResolve = true
		return
	end
	pendingResolve = false

	local config = F.Units.Pinned.GetConfig()
	local frames = F.Units.Pinned.frames
	if(not config or not frames) then return end

	local slots = config.slots or {}
	for i = 1, MAX_SLOTS do
		local frame = frames[i]
		if(frame) then
			local slot  = slots[i]
			local token = nil
			if(slot) then
				if(slot.type == 'unit') then
					token = slot.value
				elseif(slot.type == 'name') then
					token = findUnitForName(slot.value)
				elseif(slot.type == 'nametarget') then
					local base = findUnitForName(slot.value)
					token = base and (base .. 'target') or nil
				end
			end
			setFrameUnit(frame, token)
		end
	end
end
```

- [ ] **Step 4: Register events at the bottom of the file**

```lua
-- ============================================================
-- Event registration
-- ============================================================
F.EventBus:Register('GROUP_ROSTER_UPDATE', function()
	F.Units.Pinned.Resolve()
end, 'Pinned.Resolve')

F.EventBus:Register('PLAYER_REGEN_ENABLED', function()
	if(pendingResolve) then
		F.Units.Pinned.Resolve()
	end
end, 'Pinned.CombatFlush')
```

- [ ] **Step 5: Call `Resolve` at the end of `Spawn`**

After `F.Units.Pinned.Layout()` in `Spawn`, add:

```lua
F.Units.Pinned.Resolve()
```

- [ ] **Step 6: Syntax check + `/reload`**

```bash
luac -p /Users/josiahtoppin/Documents/Projects/Framed/Units/Pinned.lua
```

`/reload` — no errors.

- [ ] **Step 7: Manual resolver test**

Join a party with a friend. Run:

```
/run F.Config:Set('presets.Party.unitConfigs.pinned.enabled', true)
/run F.Config:Set('presets.Party.unitConfigs.pinned.slots', { [1] = { type = 'name', value = F.Units.Pinned.FullUnitName('player') }, [2] = { type = 'unit', value = 'focus' } })
/run F.Units.Pinned.Layout(); F.Units.Pinned.Resolve()
```

Expected: slot 1 shows you; slot 2 shows focus if set (otherwise hidden).

- [ ] **Step 8: Commit**

```bash
git add Units/Pinned.lua
git commit -m "feat(pinned): name-based unit resolver + combat deferral"
git push
```

---

## Task 4: `refreshOnUpdate` polling for `focustarget` and `nametarget`

**Why now:** Without this, `focustarget` and `nametarget` slots show stale units — WoW fires no event when a unit's target changes.

**Files:**
- Modify: `Units/Pinned.lua`

- [ ] **Step 1: Add polling infrastructure below the resolver helpers**

```lua
-- ============================================================
-- Derived-unit polling
-- WoW fires no event when a unit's target changes. Polls GUID of each
-- polling slot at 0.2s intervals; fires RefreshUnit on change.
-- ============================================================
local POLL_INTERVAL = 0.2
local pollFrame     = CreateFrame('Frame')
local pollElapsed   = 0
local lastGUIDs     = {}

local function slotNeedsPolling(slot)
	if(not slot) then return false end
	if(slot.type == 'nametarget') then return true end
	if(slot.type == 'unit' and slot.value == 'focustarget') then return true end
	return false
end

local function onPollUpdate(_, elapsed)
	pollElapsed = pollElapsed + elapsed
	if(pollElapsed < POLL_INTERVAL) then return end
	pollElapsed = 0

	local config = F.Units.Pinned.GetConfig()
	local frames = F.Units.Pinned.frames
	if(not config or not frames) then return end
	local slots = config.slots or {}

	for i = 1, MAX_SLOTS do
		local slot  = slots[i]
		local frame = frames[i]
		if(slotNeedsPolling(slot) and frame and frame.unit) then
			local newGUID = UnitGUID(frame.unit)
			if(newGUID ~= lastGUIDs[i]) then
				lastGUIDs[i] = newGUID
				if(frame.UpdateAllElements) then
					frame:UpdateAllElements('RefreshUnit')
				end
			end
		else
			lastGUIDs[i] = nil
		end
	end
end

local function updatePolling()
	local config = F.Units.Pinned.GetConfig()
	if(not config or not config.enabled) then
		pollFrame:SetScript('OnUpdate', nil)
		return
	end

	local slots = config.slots or {}
	for i = 1, MAX_SLOTS do
		if(slotNeedsPolling(slots[i])) then
			pollFrame:SetScript('OnUpdate', onPollUpdate)
			return
		end
	end
	pollFrame:SetScript('OnUpdate', nil)
end
F.Units.Pinned.UpdatePolling = updatePolling
```

- [ ] **Step 2: Call `updatePolling` at the end of `Resolve` and `Layout`**

In `Resolve` — add after the slot loop:

```lua
	updatePolling()
end
```

In `Layout` — add before the trailing `end`:

```lua
	updatePolling()
end
```

- [ ] **Step 3: Syntax check + `/reload`**

```bash
luac -p /Users/josiahtoppin/Documents/Projects/Framed/Units/Pinned.lua
```

- [ ] **Step 4: Manual polling test**

In a group:

```
/run F.Config:Set('presets.Party.unitConfigs.pinned.slots', { [1] = { type = 'nametarget', value = F.Units.Pinned.FullUnitName('player') } })
/run F.Units.Pinned.Resolve()
```

Target various NPCs. Slot 1 should update within ~0.2s each time your target changes.

- [ ] **Step 5: Commit**

```bash
git add Units/Pinned.lua
git commit -m "feat(pinned): throttled OnUpdate for derived unit slots"
git push
```

---

## Task 5: Slot identity label

**Why now:** Per spec, `nametarget` and `unit`-type slots need a dimmed label distinguishing them from direct name pins.

**Files:**
- Modify: `Units/Pinned.lua`

- [ ] **Step 1: Add label creation in `Style`**

Inside the `Style(self, unit)` function, after `F.StyleBuilder.Apply(...)`:

```lua
	if(not self.SlotIdentity) then
		local fs = F.Widgets.CreateFontString(self, F.Constants.Font.sizeSmall, F.Constants.Colors.textSecondary)
		fs:SetPoint('BOTTOM', self, 'TOP', 0, 2)
		fs:SetAlpha(0.7)
		self.SlotIdentity = fs
	end
```

- [ ] **Step 2: Add `slotIdentityText` helper near the other helpers**

```lua
local function slotIdentityText(slot)
	if(not slot) then return nil end
	if(slot.type == 'nametarget') then
		return (slot.value or '?') .. "'s Target"
	elseif(slot.type == 'unit') then
		if(slot.value == 'focus')       then return 'Focus'        end
		if(slot.value == 'focustarget') then return 'Focus Target' end
		return slot.value
	end
	return nil
end
```

- [ ] **Step 3: Update label in `Resolve`**

Inside the per-slot loop in `Resolve`, after `setFrameUnit(frame, token)`:

```lua
			if(frame.SlotIdentity) then
				local labelText = slotIdentityText(slot)
				if(labelText) then
					frame.SlotIdentity:SetText(labelText)
					frame.SlotIdentity:Show()
				else
					frame.SlotIdentity:Hide()
				end
			end
```

- [ ] **Step 4: Syntax check + `/reload` + manual test**

Set slots [1] = name, [2] = nametarget, [3] = unit focus. Verify slot 1 has no label, slot 2 shows "Name's Target", slot 3 shows "Focus".

- [ ] **Step 5: Commit**

```bash
git add Units/Pinned.lua
git commit -m "feat(pinned): dimmed slot identity label"
git push
```

---

## Task 6: Empty-slot placeholders (non-secure overlays)

**Why now:** Per spec, empty slots show a dashed-border "+ Click to assign" placeholder on hover. Plus: slot count N but only some assigned → users need to see where the inactive slots are so they can assign them without opening Settings.

**Files:**
- Modify: `Units/Pinned.lua`

- [ ] **Step 1: Add placeholder creation**

Below the `Layout` function in `Units/Pinned.lua`:

```lua
-- ============================================================
-- Empty-slot placeholders
-- Non-secure overlay frames shown when a slot is unassigned.
-- Safe in combat (non-secure, no SetAttribute).
-- ============================================================

local function createPlaceholder(parent, slotIndex)
	local ph = CreateFrame('Button', nil, parent, 'BackdropTemplate')
	ph:SetFrameStrata('MEDIUM')
	ph:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	ph:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
	ph:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)

	local plus = F.Widgets.CreateFontString(ph, F.Constants.Font.sizeLarge, F.Constants.Colors.textSecondary)
	plus:SetPoint('CENTER', ph, 'CENTER', 0, 4)
	plus:SetText('+')

	local hint = F.Widgets.CreateFontString(ph, F.Constants.Font.sizeSmall, F.Constants.Colors.textSecondary)
	hint:SetPoint('BOTTOM', ph, 'BOTTOM', 0, 4)
	hint:SetAlpha(0.7)
	hint:SetText('Click to assign')

	ph._slotIndex = slotIndex
	ph:SetAlpha(0)  -- hidden until hover
	ph:RegisterForClicks('LeftButtonUp')

	ph:SetScript('OnEnter', function(self) self:SetAlpha(1) end)
	ph:SetScript('OnLeave', function(self) self:SetAlpha(0) end)

	ph:SetScript('OnClick', function(self)
		if(F.Units.Pinned.OpenAssignmentMenu) then
			F.Units.Pinned.OpenAssignmentMenu(self._slotIndex, self)
		end
	end)

	return ph
end
```

- [ ] **Step 2: Extend `Layout` to manage placeholders**

Modify `F.Units.Pinned.Layout` — before the trailing `updatePolling()`:

```lua
	-- Manage placeholders for active but unassigned slots
	F.Units.Pinned.placeholders = F.Units.Pinned.placeholders or {}
	local phs = F.Units.Pinned.placeholders
	local slots = config.slots or {}

	for i = 1, MAX_SLOTS do
		if(i <= count and not slots[i]) then
			phs[i] = phs[i] or createPlaceholder(anchor, i)
			local f = frames[i]
			phs[i]:ClearAllPoints()
			phs[i]:SetAllPoints(f)
			F.Widgets.SetSize(phs[i], width, height)
			phs[i]:Show()
		elseif(phs[i]) then
			phs[i]:Hide()
		end
	end
```

- [ ] **Step 3: Add a stub `OpenAssignmentMenu` that Task 8 will replace**

At the bottom of the file (before event registration):

```lua
--- Placeholder: real implementation lives in Settings/Cards/Pinned.lua
--- and attaches via F.Units.Pinned.OpenAssignmentMenu = ... on card load.
--- When invoked before the card is loaded, print a hint.
function F.Units.Pinned.OpenAssignmentMenu(slotIndex, anchorFrame)
	print('|cff00ccffFramed|r Pinned: open /framed → Pinned to assign slot ' .. slotIndex)
end
```

- [ ] **Step 4: Syntax check + `/reload`**

Enable pinned on Party. Expected: 3 empty placeholders appear with dashed borders; hovering them fades them to full opacity; clicking prints the hint message.

- [ ] **Step 5: Commit**

```bash
git add Units/Pinned.lua
git commit -m "feat(pinned): empty-slot placeholder overlays with click-to-assign"
git push
```

---

## Task 7: Hover gear icon on assigned pins (out-of-combat reassign affordance)

**Why now:** Spec calls for right-click reassignment. See *Design Decisions Made During Planning #1* — we use a hover-activated gear icon to avoid colliding with click-casting `*type2` bindings.

**Files:**
- Modify: `Units/Pinned.lua`

- [ ] **Step 1: Add gear-icon creation in `Style`**

Inside `Style`, after the SlotIdentity block:

```lua
	if(not self.ReassignGear) then
		local gear = CreateFrame('Button', nil, self)
		gear:SetSize(14, 14)
		gear:SetPoint('TOPRIGHT', self, 'TOPRIGHT', -2, -2)
		gear:SetFrameLevel(self:GetFrameLevel() + 5)

		local icon = gear:CreateTexture(nil, 'OVERLAY')
		icon:SetAllPoints(gear)
		icon:SetTexture(F.Media.GetIcon('Gear') or [[Interface\GossipFrame\BinderGossipIcon]])
		gear._icon = icon

		gear:SetAlpha(0)
		gear:RegisterForClicks('LeftButtonUp')

		-- Hide gear during combat
		self:HookScript('OnEnter', function(frame)
			if(InCombatLockdown()) then return end
			if(frame._pinnedSlotIndex) then
				gear:SetAlpha(0.8)
			end
		end)
		self:HookScript('OnLeave', function()
			gear:SetAlpha(0)
		end)
		gear:SetScript('OnEnter', function(self) self:SetAlpha(1) end)
		gear:SetScript('OnLeave', function(self)
			if(self:GetParent():IsMouseOver()) then self:SetAlpha(0.8) else self:SetAlpha(0) end
		end)

		gear:SetScript('OnClick', function(g)
			local parent = g:GetParent()
			if(parent._pinnedSlotIndex and F.Units.Pinned.OpenAssignmentMenu) then
				F.Units.Pinned.OpenAssignmentMenu(parent._pinnedSlotIndex, parent)
			end
		end)

		self.ReassignGear = gear
	end
```

- [ ] **Step 2: Tag each frame with its slot index in `Spawn`**

Inside the frame creation loop in `Spawn`:

```lua
		frame._pinnedSlotIndex = i
```

Place this line immediately after `frames[i] = frame`.

- [ ] **Step 3: Hide gear when slot is unassigned (via `Resolve`)**

Inside the per-slot loop in `Resolve`, after the SlotIdentity update:

```lua
			if(frame.ReassignGear) then
				if(slot) then
					-- Gear visible-on-hover; don't force show here
				else
					frame.ReassignGear:SetAlpha(0)
				end
			end
```

- [ ] **Step 4: Syntax check + `/reload` + manual test**

With pinned enabled and slot 1 assigned: hover the frame → small gear appears top-right. Click gear → assignment menu opens (stub message for now; real menu arrives in Task 8). In combat: hover should NOT reveal gear.

- [ ] **Step 5: Commit**

```bash
git add Units/Pinned.lua
git commit -m "feat(pinned): hover gear icon for reassignment (out of combat)"
git push
```

---

## Task 8: `Settings/Cards/Pinned.lua` — role-grouped dropdown + `OpenAssignmentMenu`

**Why now:** Single file that implements BOTH the Settings-card per-slot list AND the `OpenAssignmentMenu` entry point used by Task 6 placeholders + Task 7 gear icons. DRY — one dropdown factory, two call sites.

**Files:**
- Create: `Settings/Cards/Pinned.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Create `Settings/Cards/Pinned.lua`**

```lua
local _, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings       = F.Settings       or {}
F.Settings.Cards = F.Settings.Cards or {}

local MAX_SLOTS   = 9
local ROLES       = { 'TANK', 'HEALER', 'DAMAGER' }
local ROLE_LABELS = { TANK = 'Tanks', HEALER = 'Healers', DAMAGER = 'DPS' }

-- ============================================================
-- Helpers
-- ============================================================

local function classHex(classToken)
	local c = classToken and RAID_CLASS_COLORS[classToken]
	if(not c) then return 'ffffff' end
	return ('%02x%02x%02x'):format(
		math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end

local function fullUnitName(token)
	if(F.Units.Pinned and F.Units.Pinned.FullUnitName) then
		return F.Units.Pinned.FullUnitName(token)
	end
	if(not UnitExists(token)) then return nil end
	local name, realm = UnitName(token)
	if(not name) then return nil end
	if(realm and realm ~= '') then return name .. '-' .. realm end
	return name
end

local function scanRoster()
	local roster = {}
	local function add(token)
		if(not UnitExists(token)) then return end
		roster[#roster + 1] = {
			name  = fullUnitName(token),
			token = token,
			class = select(2, UnitClass(token)),
			role  = UnitGroupRolesAssigned(token) or 'DAMAGER',
		}
	end
	if(IsInRaid()) then
		for i = 1, GetNumGroupMembers() do add('raid' .. i) end
	elseif(IsInGroup()) then
		for i = 1, GetNumGroupMembers() - 1 do add('party' .. i) end
		add('player')
	else
		add('player')
	end
	return roster
end

local function assignedNames(slots, excludeIndex)
	local set = {}
	for i = 1, MAX_SLOTS do
		if(i ~= excludeIndex) then
			local s = slots[i]
			if(s and (s.type == 'name' or s.type == 'nametarget') and s.value) then
				set[s.value] = true
			end
		end
	end
	return set
end

-- ============================================================
-- Dropdown decorators for headers (non-selectable rows)
-- ============================================================

local function headerDecorator(row, item)
	row._label:SetTextColor(0.6, 0.6, 0.6, 1)
	row:SetScript('OnEnter', function() end)
	row:SetScript('OnLeave', function() end)
	row:SetScript('OnMouseDown', function() end)  -- swallow clicks
end

local function classColorDecorator(classToken, indent)
	local hex = classHex(classToken)
	return function(row, item)
		row._label:SetText(((indent and '    ') or '') .. item.text)
		local r = tonumber(hex:sub(1, 2), 16) / 255
		local g = tonumber(hex:sub(3, 4), 16) / 255
		local b = tonumber(hex:sub(5, 6), 16) / 255
		row._label:SetTextColor(r, g, b, 1)
	end
end

-- ============================================================
-- Build dropdown items
-- ============================================================

--- @param slotIndex number
--- @return table items suitable for dropdown:SetItems
local function buildItems(slotIndex)
	local config = F.Units.Pinned.GetConfig() or {}
	local slots  = config.slots or {}
	local blocked = assignedNames(slots, slotIndex)

	local items = {}

	-- Unit References
	items[#items + 1] = { text = '— Unit References —', value = '__hdr_unit', _decorateRow = headerDecorator }
	items[#items + 1] = { text = 'Focus',        value = 'FOCUS' }
	items[#items + 1] = { text = 'Focus Target', value = 'FOCUSTARGET' }

	-- Role groups
	local roster = scanRoster()
	local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }
	for _, p in next, roster do
		local bucket = byRole[p.role] or byRole.DAMAGER
		bucket[#bucket + 1] = p
	end

	for _, roleToken in next, ROLES do
		local bucket = byRole[roleToken]
		if(bucket and #bucket > 0) then
			items[#items + 1] = {
				text  = '— ' .. ROLE_LABELS[roleToken] .. ' —',
				value = '__hdr_' .. roleToken,
				_decorateRow = headerDecorator,
			}
			for _, p in next, bucket do
				if(p.name and not blocked[p.name]) then
					items[#items + 1] = {
						text  = p.name,
						value = 'NAME:' .. p.name,
						_decorateRow = classColorDecorator(p.class, false),
					}
					items[#items + 1] = {
						text  = p.name .. "'s Target",
						value = 'TARGET:' .. p.name,
						_decorateRow = classColorDecorator(p.class, true),
					}
				end
			end
		end
	end

	-- None
	items[#items + 1] = { text = '— None —',  value = '__hdr_none', _decorateRow = headerDecorator }
	items[#items + 1] = { text = '(Unassign)', value = 'UNASSIGN' }

	return items
end

--- Convert stored slot config into a dropdown value string for SetValue.
local function slotToValue(slot)
	if(not slot) then return 'UNASSIGN' end
	if(slot.type == 'unit' and slot.value == 'focus')       then return 'FOCUS' end
	if(slot.type == 'unit' and slot.value == 'focustarget') then return 'FOCUSTARGET' end
	if(slot.type == 'name')                                  then return 'NAME:' .. slot.value end
	if(slot.type == 'nametarget')                            then return 'TARGET:' .. slot.value end
	return 'UNASSIGN'
end

--- Convert dropdown value back to a stored slot config.
local function valueToSlot(value)
	if(value == 'UNASSIGN') then return nil end
	if(value == 'FOCUS')       then return { type = 'unit', value = 'focus' } end
	if(value == 'FOCUSTARGET') then return { type = 'unit', value = 'focustarget' } end
	local name = value:match('^NAME:(.+)$')
	if(name) then return { type = 'name', value = name } end
	local tgtName = value:match('^TARGET:(.+)$')
	if(tgtName) then return { type = 'nametarget', value = tgtName } end
	return nil
end

--- Persist a slot selection.
local function persistSlot(slotIndex, value)
	local presetName = F.PresetManager.GetActive()
	if(not presetName) then return end
	local path = 'presets.' .. presetName .. '.unitConfigs.pinned.slots.' .. slotIndex
	F.Config:Set(path, valueToSlot(value))
	F.PresetManager.MarkCustomized(presetName)
end

-- ============================================================
-- Open assignment menu (detached dropdown anchored to a frame)
-- Used by Task 6 placeholders and Task 7 gear icons.
-- ============================================================

local detachedDropdown

function F.Units.Pinned.OpenAssignmentMenu(slotIndex, anchorFrame)
	if(InCombatLockdown()) then
		print('|cff00ccffFramed|r Pinned: cannot reassign during combat')
		return
	end

	if(not detachedDropdown) then
		detachedDropdown = Widgets.CreateDropdown(UIParent, 200)
		detachedDropdown:SetFrameStrata('DIALOG')
	end

	detachedDropdown:ClearAllPoints()
	detachedDropdown:SetPoint('TOP', anchorFrame, 'BOTTOM', 0, -2)
	detachedDropdown:SetItems(buildItems(slotIndex))

	local config = F.Units.Pinned.GetConfig() or {}
	local slots  = config.slots or {}
	detachedDropdown:SetValue(slotToValue(slots[slotIndex]))

	detachedDropdown:SetOnSelect(function(value)
		if(type(value) == 'string' and value:sub(1, 5) == '__hdr') then return end
		persistSlot(slotIndex, value)
	end)

	detachedDropdown:Show()
	if(detachedDropdown.Open) then detachedDropdown:Open() end
end

-- ============================================================
-- Settings card (per-slot list)
-- ============================================================

local function renderSlotRow(parent, slotIndex, yOffset)
	local row = CreateFrame('Frame', nil, parent)
	row:SetSize(500, 28)
	row:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, yOffset)

	local label = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textPrimary)
	label:SetPoint('LEFT', row, 'LEFT', 0, 0)
	label:SetText('Slot ' .. slotIndex)
	label:SetWidth(60)

	local dd = Widgets.CreateDropdown(row, 320)
	dd:ClearAllPoints()
	dd:SetPoint('LEFT', label, 'RIGHT', 12, 0)

	local function refresh()
		dd:SetItems(buildItems(slotIndex))
		local config = F.Units.Pinned.GetConfig() or {}
		local slots  = config.slots or {}
		dd:SetValue(slotToValue(slots[slotIndex]))
	end

	dd:SetOnSelect(function(value)
		if(type(value) == 'string' and value:sub(1, 5) == '__hdr') then
			refresh()
			return
		end
		persistSlot(slotIndex, value)
		refresh()
	end)

	refresh()
	row._refresh = refresh
	return row
end

function F.Settings.Cards.Pinned(parent, width)
	local card, inner = Widgets.StartCard(parent, width, 0)

	local title = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textActive)
	title:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, -4)
	title:SetText('Slot Assignments')

	local rows = {}
	local function rebuild()
		for _, r in next, rows do r:Hide(); r:SetParent(nil) end
		rows = {}
		local config = F.Units.Pinned.GetConfig()
		if(not config) then return end
		local count = math.max(1, math.min(config.count or 3, MAX_SLOTS))

		local y = -28
		for i = 1, count do
			rows[i] = renderSlotRow(inner, i, y)
			y = y - 32
		end

		Widgets.EndCard(card, parent, y)
	end

	rebuild()

	F.EventBus:Register('CONFIG_CHANGED', function(path)
		if(not path) then return end
		if(path:match('unitConfigs%.pinned%.count$') or path:match('unitConfigs%.pinned%.slots')) then
			rebuild()
		end
	end, 'PinnedCard.' .. tostring(card) .. '.CC')

	F.EventBus:Register('GROUP_ROSTER_UPDATE', rebuild, 'PinnedCard.' .. tostring(card) .. '.Roster')

	return card
end
```

- [ ] **Step 2: Register in `Framed.toc`**

After `Settings/Cards/` entries (or wherever unit-type cards live — match the load-after-Units pattern), add:

```
Settings/Cards/Pinned.lua
```

- [ ] **Step 3: Syntax check**

```bash
luac -p /Users/josiahtoppin/Documents/Projects/Framed/Settings/Cards/Pinned.lua
```

Expected: no output.

- [ ] **Step 4: `/reload` + test the detached assignment menu**

Enable pinned on Party preset. Click an empty-slot placeholder → dropdown appears below the placeholder with role groups. Select a teammate → frame populates. Hover an assigned pin → gear appears. Click gear → dropdown reopens with current selection highlighted.

- [ ] **Step 5: Commit**

```bash
git add Settings/Cards/Pinned.lua Framed.toc
git commit -m "feat(pinned): role-grouped assignment dropdown for card + in-world"
git push
```

---

## Task 9: Extend `FrameSettingsBuilder` for `pinned`; register Pinned panel

**Why now:** The Settings sidebar needs a "Pinned" entry under Frames that renders the shared style cards + the slot assignment card.

**Files:**
- Modify: `Settings/FrameSettingsBuilder.lua`
- Create: `Settings/Panels/Pinned.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Audit `FrameSettingsBuilder.lua` for unit-type tables and branches**

Open `Settings/FrameSettingsBuilder.lua`. Search for string equality against unit-type literals (`'party'`, `'raid'`, `'arena'`, `'boss'`). For each, decide whether pinned behaves identically. In general pinned behaves as a group type.

Specifically, look for:
- A `GROUP_TYPES` table — add `pinned = true`
- A `GROUP_COUNTS` table — add `pinned = 9`
- Preview-frame spawning logic that switches on unit type — add a `pinned` branch (use multi-frame preview like party/raid)
- Per-card inclusion gates (e.g., "include spacing card only for groups") — verify pinned is in the inclusion set

- [ ] **Step 2: Append slot assignment card into the pinned panel's CardGrid**

Find the function that adds cards to the grid for a given unit type (likely a `for ... addCard ...` loop or a `CARDS_FOR_UNIT_TYPE` table). Add pinned's slot assignment card either by:

**(a)** Extending a `CARDS_FOR_UNIT_TYPE` table:

```lua
CARDS_FOR_UNIT_TYPE = {
	...,
	pinned = { 'slot-assignments', 'Slot Assignments', F.Settings.Cards.Pinned },
}
```

**(b)** Or by adding a branch after the standard cards are added:

```lua
if(unitType == 'pinned' and F.Settings.Cards.Pinned) then
	grid:AddCard('slot-assignments', 'Slot Assignments', F.Settings.Cards.Pinned, {})
end
```

Use whichever pattern matches the existing file's style.

- [ ] **Step 3: Create `Settings/Panels/Pinned.lua`**

```lua
local _, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id       = 'pinned',
	label    = 'Pinned',
	section  = 'PRESET_SCOPED',
	unitType = 'pinned',
	order    = 65,
	create   = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'pinned')
	end,
})
```

- [ ] **Step 4: Register in `Framed.toc`**

After `Settings/Panels/Boss.lua`:

```
Settings/Panels/Pinned.lua
```

- [ ] **Step 5: Syntax check**

```bash
luac -p /Users/josiahtoppin/Documents/Projects/Framed/Settings/Panels/Pinned.lua
luac -p /Users/josiahtoppin/Documents/Projects/Framed/Settings/FrameSettingsBuilder.lua
```

Expected: no output.

- [ ] **Step 6: Scenario tests**

- Solo preset active → `/framed` → sidebar has no "Pinned" entry.
- Party preset active → `/framed` → sidebar shows "Pinned". Open it → preview, summary, sliders for count/columns/spacing, standard style cards, and the slot assignment card.
- Change count slider 3 → 9 → slot assignment card rebuilds to show 9 rows. Frames in-world reflow to a 3x3 (columns default 3).
- Assign slot 1 → in-world frame shows teammate.

- [ ] **Step 7: Commit**

```bash
git add Settings/FrameSettingsBuilder.lua Settings/Panels/Pinned.lua Framed.toc
git commit -m "feat(pinned): register Pinned settings panel with slot assignment card"
git push
```

---

## Task 10: `FrameConfigPinned.lua` — LiveUpdate + PRESET_CHANGED handler

**Why now:** Without this, settings-panel changes require `/reload`, and preset switching doesn't re-layout pinned frames.

**Files:**
- Create: `Units/LiveUpdate/FrameConfigPinned.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Create `Units/LiveUpdate/FrameConfigPinned.lua`**

```lua
local _, Framed = ...
local F = Framed

local Shared = F.LiveUpdate and F.LiveUpdate.FrameConfigShared
if(not Shared) then return end

local guardConfigChanged = Shared.guardConfigChanged
local debouncedApply     = Shared.debouncedApply

-- ============================================================
-- CONFIG_CHANGED: per-key routing
-- ============================================================

local function onConfigChanged(path)
	local unitType, key = guardConfigChanged(path)
	if(unitType ~= 'pinned') then return end

	if(key == 'position.x' or key == 'position.y' or key == 'position.anchor') then
		F.Units.Pinned.ApplyPosition()
	elseif(key == 'enabled' or key == 'count' or key == 'columns'
	    or key == 'width' or key == 'height' or key == 'spacing') then
		debouncedApply('pinned.layout', function()
			F.Units.Pinned.Layout()
			F.Units.Pinned.Resolve()
		end)
	elseif(key and key:match('^slots')) then
		F.Units.Pinned.Resolve()
		F.Units.Pinned.Layout()  -- placeholders toggle
	else
		-- Shared style change: re-apply StyleBuilder to live frames
		debouncedApply('pinned.style', function()
			local config = F.Units.Pinned.GetConfig()
			local frames = F.Units.Pinned.frames
			if(not config or not frames) then return end
			for i = 1, 9 do
				local f = frames[i]
				if(f) then
					F.StyleBuilder.Apply(f, config, 'pinned')
					if(f.UpdateAllElements) then f:UpdateAllElements('RefreshStyle') end
				end
			end
		end)
	end
end
F.EventBus:Register('CONFIG_CHANGED', onConfigChanged, 'FrameConfigPinned.CC')

-- ============================================================
-- PRESET_CHANGED: full re-apply
-- ============================================================

F.EventBus:Register('PRESET_CHANGED', function()
	F.Units.Pinned.ApplyPosition()
	F.Units.Pinned.Layout()
	F.Units.Pinned.Resolve()
end, 'FrameConfigPinned.PresetChanged')
```

- [ ] **Step 2: Register in `Framed.toc`**

After `Units/LiveUpdate/FrameConfigLayout.lua`:

```
Units/LiveUpdate/FrameConfigPinned.lua
```

- [ ] **Step 3: Syntax check + `/reload`**

```bash
luac -p /Users/josiahtoppin/Documents/Projects/Framed/Units/LiveUpdate/FrameConfigPinned.lua
```

- [ ] **Step 4: LiveUpdate tests**

- Change columns slider → frames reflow within ~50ms.
- Change `enabled` toggle → frames appear/disappear live.
- Assign slot in Settings card → frame populates without `/reload`.

- [ ] **Step 5: Preset switch test**

With pinned enabled on Party (3 frames assigned), switch to Raid preset (`/framed` → preset dropdown). Raid's pinned defaults to disabled → frames hide. Switch back to Party → frames reappear with Party's assignments.

- [ ] **Step 6: Commit**

```bash
git add Units/LiveUpdate/FrameConfigPinned.lua Framed.toc
git commit -m "feat(pinned): LiveUpdate + PRESET_CHANGED handler"
git push
```

---

## Task 11: EditMode integration — `FRAME_KEYS` entry + click-to-configure

**Why now:** Users need drag-to-position and click-in-edit-mode-to-open-settings, matching other Framed unit types.

**Files:**
- Modify: `EditMode/EditMode.lua`

- [ ] **Step 1: Add `FRAME_KEYS` entry**

Open `EditMode/EditMode.lua`. Locate `FRAME_KEYS` (lines 37-47). Add after the `arena` entry:

```lua
{ key = 'pinned', label = 'Pinned Frames', isGroup = true,
  getter = function() return F.Units.Pinned and F.Units.Pinned.anchor end },
```

- [ ] **Step 2: Audit the inline-settings click hook**

Search `EditMode/EditMode.lua` for where clicking a frame in edit mode opens the inline settings panel. This may be:
- A generic `OnClick` hook applied to every registered frame via `FRAME_KEYS`
- A per-unit-type hook registered elsewhere

If it's generic (uses the `FRAME_KEYS` getter), pinned works automatically once Step 1 lands. If it's per-unit-type, add a branch for pinned that opens `/framed` → Pinned panel (`F.Settings.Toggle` + `F.Settings.SetActivePanel('pinned')`).

- [ ] **Step 3: Verify drag persistence writes to `unitConfigs.pinned.position.x/y`**

Trace the EditMode drag handler's config-write path. Confirm it writes to `presets.<active>.unitConfigs.<key>.position.*` where `<key>` comes from the `FRAME_KEYS` entry. If so, pinned inherits persistence automatically.

- [ ] **Step 4: Syntax check + `/reload`**

```bash
luac -p /Users/josiahtoppin/Documents/Projects/Framed/EditMode/EditMode.lua
```

- [ ] **Step 5: EditMode tests**

- `/framed edit` → "Pinned Frames" drag handle appears over the pinned grid.
- Drag the handle → grid moves. Exit edit mode → `/reload` → position persists.
- Click a pinned frame in edit mode → inline settings panel opens showing the Pinned panel's shared style cards + the slot assignment card (if Step 2 is generic) OR the Pinned settings tab (if Step 2 requires per-unit-type wiring).

- [ ] **Step 6: Commit**

```bash
git add EditMode/EditMode.lua
git commit -m "feat(pinned): EditMode integration + click-to-configure"
git push
```

---

## Task 12: Auras panel — register `pinned` in `Settings._getUnitTypeItems()`

**Why now:** This is the single change that makes pinned appear as a selectable unit type across ALL 10 aura sub-panels (Buffs, Debuffs, Defensives, Dispels, Externals, MissingBuffs, PrivateAuras, TargetedSpells, LossOfControl, CrowdControl). Each aura panel already dispatches on `Settings.GetEditingUnitType()` — they need no per-panel modification.

**Files:**
- Modify: `Settings/Framework.lua`

- [ ] **Step 1: Extend `Settings._getUnitTypeItems` to append pinned when available**

Open `Settings/Framework.lua`. Find `Settings._getUnitTypeItems` (line 104). Currently:

```lua
function Settings._getUnitTypeItems()
	local presetName = Settings.GetEditingPreset()
	local info = C.PresetInfo[presetName]
	local items = {
		{ text = 'Player',           value = 'player' },
		...
	}
	if(info and info.groupKey) then
		items[#items + 1] = { text = info.groupLabel, value = info.groupKey }
	end
	return items
end
```

After the existing `groupKey` append, add:

```lua
	-- Pinned appears as an additional group-tier unit type whenever the
	-- active preset has an auras.pinned block (which Solo lacks).
	if(presetName and F.Config and F.Config:Get('presets.' .. presetName .. '.auras.pinned')) then
		items[#items + 1] = { text = 'Pinned Frames', value = 'pinned' }
	end
	return items
end
```

- [ ] **Step 2: Verify aura panels route through this function**

Open `Settings/Panels/Buffs.lua:210` — `local unitType = F.Settings.GetEditingUnitType()` — and `makeConfigHelpers(unitType)` builds the path `presets.<preset>.auras.<unitType>.buffs.indicators`. So when `unitType = 'pinned'`, the path becomes `presets.Party.auras.pinned.buffs.indicators`, which matches the defaults registered in Task 1. **No per-panel modification required.**

Sanity-check one other panel (e.g., `Settings/Panels/Defensives.lua`) — confirm the same pattern.

- [ ] **Step 3: Syntax check + `/reload`**

```bash
luac -p /Users/josiahtoppin/Documents/Projects/Framed/Settings/Framework.lua
```

- [ ] **Step 4: Scenario test**

- Party preset active → `/framed` → Auras → Buffs → unit-type dropdown shows: Player, Target, Target of Target, Focus, Pet, Boss, **Party Frames**, **Pinned Frames**.
- Select Pinned Frames → buffs indicators for pinned render and dispatch correctly.
- Assign a pin, apply a buff to that player → buff shows on the pinned frame.
- Switch to Solo preset → Auras → Buffs → "Pinned Frames" is absent (no `auras.pinned` in Solo).

- [ ] **Step 5: Aura live-update test**

With a pin assigned, in the Auras → Debuffs panel for Pinned Frames, enable a new indicator. Verify it appears on the pinned frame without `/reload`.

- [ ] **Step 6: Commit**

```bash
git add Settings/Framework.lua
git commit -m "feat(pinned): register pinned as aura unit type in all aura panels"
git push
```

---

## Task 13: StyleBuilder verification + frame tagging audit

**Why now:** Pinned frames are tagged `_framedUnitType = 'pinned'` (Task 2 Step 1). The generic `FrameConfigPreset` handler at `Units/LiveUpdate/FrameConfigPreset.lua:460` iterates `oUF.objects` by `_framedUnitType` and calls `F.StyleBuilder.GetConfig(unitType)`. If StyleBuilder doesn't know `pinned`, this path silently no-ops.

**Files:**
- Audit: `Units/StyleBuilder.lua`
- Audit: `Units/LiveUpdate/FrameConfigPreset.lua`

- [ ] **Step 1: Verify `F.StyleBuilder.GetConfig('pinned')` returns the pinned config**

Open `Units/StyleBuilder.lua`. Search for `GetConfig`. Confirm it reads `F.Config:Get('presets.' .. active .. '.unitConfigs.' .. unitType)` — i.e., unit-type-agnostic. If so, pinned works automatically.

If `GetConfig` has a unit-type switch/whitelist, add `pinned`.

- [ ] **Step 2: Verify `F.StyleBuilder.GetAuraConfig('pinned', key)` works**

Search for `GetAuraConfig`. Confirm it reads `presets.<active>.auras.<unitType>.<key>`. Because Task 1 added `auras.pinned`, this should work without modification.

- [ ] **Step 3: Verify `F.StyleBuilder.Apply(frame, config, 'pinned')` from Task 2 Style function works**

Search for `StyleBuilder.Apply`. Confirm the third arg (unit type) doesn't gate element setup by a whitelist. If it does, add `pinned` to the whitelist.

- [ ] **Step 4: Verify `FrameConfigPreset.lua` aura loop handles `pinned`**

Read `Units/LiveUpdate/FrameConfigPreset.lua:473-492`. The loop uses `auraUnitType = unitType` for non-partypet frames, then reads `F.StyleBuilder.GetAuraConfig(auraUnitType, aura.key)`. Since pinned has `auras.pinned` in the preset and `_framedUnitType = 'pinned'` on the frame, this loop handles pinned without modification.

- [ ] **Step 5: If any Step 1-3 audit found gaps, commit the fix**

If no gaps found: no commit. If gaps: one focused commit per gap.

---

## Task 14: Edge case verification sweep

**Why now:** Walk through every edge case in the spec and confirm behavior before declaring feature-complete.

**Files:**
- None (audit only; any fixes get their own focused commits)

- [ ] **Step 1: Player leaves group**

In a party with slot 1 pinned to a teammate, have them leave. Expected: `GROUP_ROSTER_UPDATE` → `Resolve` → `findUnitForName` returns nil → frame hides via `RegisterUnitWatch`. Rejoining restores the pin.

- [ ] **Step 2: Preset switch with combat lockdown**

Enter combat. In combat, trigger a preset switch (via AutoSwitch or manual). Expected: `PRESET_CHANGED` handler fires, `Resolve` hits `InCombatLockdown` → queues `pendingResolve = true`. On `PLAYER_REGEN_ENABLED`, resolve runs with the new preset's assignments.

- [ ] **Step 3: Empty group**

Solo with Party preset active, pinned enabled, slot 1 = name, slot 2 = focus. Expected: slot 1 hides, slot 2 still works if focus exists.

- [ ] **Step 4: Slot count reduced**

count = 9 → 3. Slots 4-9 hide. Raising back → they restore.

- [ ] **Step 5: Role change**

In party, teammate changes spec/role. Open a dropdown → they appear under the new role group on next open (roster is rescanned on every open).

- [ ] **Step 6: Feature disabled**

Toggle `enabled = false`. All frames and placeholders hide. Polling stops.

- [ ] **Step 7: Cross-realm**

In a cross-realm group, confirm `fullUnitName` returns `'Name-Realm'` format, dropdown displays that format, and stored slot value matches scanner output.

- [ ] **Step 8: Connected-realm**

Connected-realm teammates return `realm = nil` from `UnitName`. Storage format is short name. Scanner matches short name. No change needed.

- [ ] **Step 9: Duplicate prevention**

Assign slot 1 = Bob (name). Open slot 2 dropdown → Bob's name is absent from the role list. Unassign slot 1 → open slot 2 → Bob reappears.

- [ ] **Step 10: Taint check**

With pinned enabled and assigned, enter combat (training dummy). Verify no Lua errors, no taint warnings in chat. Keep BugSack or equivalent open for visibility.

- [ ] **Step 11: If any check fails**

Commit a focused fix per failure, e.g., `fix(pinned): duplicate filter missed cross-realm suffix`. Do not bundle multiple fixes.

---

## Task 15: CHANGELOG + final integration pass

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Golden path manual test**

1. Fresh WoW session, `/reload`
2. `/framed` → Settings → Party preset → Pinned panel → enable toggle on
3. Assign slot 1 = self, slot 2 = self's target, slot 3 = Focus
4. Verify 3 frames visible and tracking
5. Columns slider 3 → 1 → 3, live reflow
6. `/framed edit` → drag grid → exit → `/reload` → position persists
7. Auras → Buffs → Pinned Frames → add an indicator, verify it renders
8. Enter combat briefly, verify no taint
9. Switch to Raid preset, verify separate config
10. Switch to Solo, verify Pinned panel and aura entry both absent
11. Hover an empty slot → placeholder fades in, click → dropdown opens
12. Hover an assigned pin → gear icon appears, click → dropdown opens
13. Unassign via dropdown → slot returns to placeholder state

- [ ] **Step 2: Update `CHANGELOG.md`**

Add at the top of `CHANGELOG.md` (per `feedback_release_changelog.md`: update CHANGELOG before any TOC bump):

```markdown
## [Unreleased]

### Added
- **Pinned Frames** — up to 9 standalone frames that track specific group members by name. Follows players across roster reshuffles. Supports Focus / Focus Target / name-target slots. Role-grouped class-colored assignment dropdown (Settings card, in-world placeholder click, and hover-gear icon). Full aura configuration as a first-class unit type. Per-preset; absent in Solo.
```

- [ ] **Step 3: Final commit**

```bash
git add CHANGELOG.md
git commit -m "docs(pinned): changelog entry"
git push
```

- [ ] **Step 4: Open PR from `working-testing` to `main`**

Per `feedback_git_workflow.md`: worktree → working → main via GitHub PR. No TOC bump or tag — that's the user's release workflow.

---

## Self-Review

**Spec coverage:**

| Spec Section | Task(s) |
|---|---|
| Data model | 1 |
| Frame spawning | 2 |
| Name-based resolution | 3 |
| Name-target resolution | 3, 4 |
| Static token resolution | 3 |
| Combat deferral | 3, 14 |
| Grid layout | 2 |
| EditMode integration (FRAME_KEYS + inline settings) | 11 |
| LiveUpdate | 10 |
| Role-grouped dropdown with class colors, duplicate filter | 8 |
| Frame interaction (empty placeholders + assigned gear) | 6, 7 |
| Aura configuration (first-class unit type) | 1, 12 |
| Slot identity label | 5 |
| Cross-realm handling | 3, 14 |
| OnUpdate throttle | 4 |
| Settings card | 8, 9 |
| Edge cases (all 6) | 14 |
| File surface (all 9 files) | All |

**Type consistency:**
- Slot shape: `{ type = 'name'|'nametarget'|'unit', value = <string> }` everywhere.
- Dropdown value encoding: `'UNASSIGN' | 'FOCUS' | 'FOCUSTARGET' | 'NAME:<name>' | 'TARGET:<name>' | '__hdr_*'`. `valueToSlot`/`slotToValue` are the only converters.
- Function names stable: `F.Units.Pinned.{GetConfig, Layout, Resolve, ApplyPosition, UpdatePolling, OpenAssignmentMenu, FullUnitName, FindUnitForName}`.
- `MAX_SLOTS = 9` is duplicated in `Units/Pinned.lua` and `Settings/Cards/Pinned.lua` (intentional — avoids load-order dependency).
- Frame tag: `_framedUnitType = 'pinned'` set in `Style`, consumed by `FrameConfigPreset.lua:462` generic handler.

**Known audit-required points (flagged in tasks, not failures):**
- Task 9 Step 1: `FrameSettingsBuilder` unit-type branches — exact table names vary, engineer matches real code.
- Task 11 Step 2: EditMode click-to-configure — may already be generic (via `FRAME_KEYS.getter`) or may need per-unit-type wiring.
- Task 13: StyleBuilder could be unit-type-agnostic (no change) or have a whitelist (add `pinned`).

**Design decision deviations** (documented in "Design Decisions Made During Planning"):
1. Right-click reassign → hover gear icon (avoids click-cast conflict).
2. Empty-slot placeholders are non-secure (combat-safe).
3. EditMode click-to-configure delegates to the `FRAME_KEYS`/inline-settings generic path if it exists.

**No placeholders, TBDs, or "implement later"**. Every code step shows the code. Where audit is required, the task says so explicitly.
