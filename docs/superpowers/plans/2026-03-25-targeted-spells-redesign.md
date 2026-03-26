# Targeted Spells Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the non-functional CLEU-based TargetedSpells element with a `UNIT_SPELLCAST_*` + nameplate cast tracker, supporting Midnight secret values.

**Architecture:** A centralized `Core/CastTracker.lua` singleton listens for spellcast events on nameplates/target/focus, resolves cast targets via `UnitIsUnit`, and fires ForceUpdate on registered oUF frames. The existing `Elements/Auras/TargetedSpells.lua` becomes a thin display layer consuming the tracker. Two display paths: non-secret (resolved target units) and secret (`SetAlphaFromBoolean`).

**Tech Stack:** WoW Lua API (12.0.1), oUF element system, `C_Spell.IsSpellImportant`, `SetAlphaFromBoolean`

---

### Task 1: Add CastTracker.lua to TOC

**Files:**
- Modify: `Framed.toc:30` (after `Core/Config.lua`)

- [ ] **Step 1: Add TOC entry**

In `Framed.toc`, after line 30 (`Core/Config.lua`), add:

```
Core/CastTracker.lua
```

The `# Core` section should now read:

```
# Core
Init.lua
Core/Constants.lua
Media/Media.lua
Core/SecretValues.lua
Core/DispelCapability.lua
Core/Utilities.lua
Core/EventBus.lua
Core/Config.lua
Core/CastTracker.lua
```

- [ ] **Step 2: Create empty CastTracker.lua**

Create `Core/CastTracker.lua` with the namespace boilerplate only:

```lua
local addonName, Framed = ...
local F = Framed

F.CastTracker = {}
```

- [ ] **Step 3: Commit**

```bash
git add Framed.toc Core/CastTracker.lua
git commit -m "chore: add CastTracker.lua to TOC and create skeleton"
```

---

### Task 2: CastTracker — Event Registration and State Management

**Files:**
- Modify: `Core/CastTracker.lua`

**Context:** This task builds the event frame, Enable/Disable, Register/Unregister, and state reset. No cast logic yet — just the infrastructure. The tracker uses a hidden frame for events and an OnUpdate frame for rechecks. `F.CastTracker` is a table (not a metatable class) with method-style functions.

**Reference:** Cell's `Indicators/TargetedSpells.lua` lines 1-30 (local state), lines 370-420 (`I.EnableTargetedSpells`), lines 280-350 (event handler structure). Fetch via: `gh api repos/jdtoppin/Cell/contents/Indicators/TargetedSpells.lua --jq '.download_url' | xargs curl -s`

- [ ] **Step 1: Implement event infrastructure**

Replace the contents of `Core/CastTracker.lua` with:

```lua
local addonName, Framed = ...
local F = Framed

F.CastTracker = {}

-- ============================================================
-- Local state
-- ============================================================

local UnitIsUnit = UnitIsUnit
local UnitExists = UnitExists
local UnitIsEnemy = UnitIsEnemy
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local C_Spell = C_Spell
local strfind = string.find
local wipe = wipe
local GetTime = GetTime

local casts = {}
local registeredFrames = {}
local useSecretPath = false

local eventFrame = CreateFrame('Frame')
eventFrame:Hide()

local recheckFrame = CreateFrame('Frame')
recheckFrame:Hide()

local recheck = {}

-- ============================================================
-- Forward declarations
-- ============================================================

local CheckUnitCast
local Reset
local BroadcastUpdate

-- ============================================================
-- Secret-safe UnitIsUnit
-- ============================================================

local function SafeUnitIsUnit(a, b)
	local result = UnitIsUnit(a, b)
	if(not F.IsValueNonSecret(result)) then return false end
	return result
end

-- ============================================================
-- Group iteration helper
-- ============================================================

local function GetTargetUnitID_Safe(targetToken)
	if(SafeUnitIsUnit(targetToken, 'player')) then return 'player', false end
	if(UnitExists('pet') and SafeUnitIsUnit(targetToken, 'pet')) then return 'pet', false end

	if(IsInRaid()) then
		for i = 1, GetNumGroupMembers() do
			local unit = 'raid' .. i
			if(SafeUnitIsUnit(targetToken, unit)) then return unit, false end
			local petUnit = 'raidpet' .. i
			if(UnitExists(petUnit) and SafeUnitIsUnit(targetToken, petUnit)) then return petUnit, false end
		end
	else
		for i = 1, 4 do
			local unit = 'party' .. i
			if(UnitExists(unit) and SafeUnitIsUnit(targetToken, unit)) then return unit, false end
			local petUnit = 'partypet' .. i
			if(UnitExists(petUnit) and SafeUnitIsUnit(targetToken, petUnit)) then return petUnit, false end
		end
	end

	-- Check if UnitIsUnit is returning secrets (not just nil/no target)
	if(UnitExists(targetToken)) then
		local result = UnitIsUnit(targetToken, 'player')
		if(not F.IsValueNonSecret(result)) then
			return nil, true -- target exists but results are secret
		end
	end

	return nil, false
end

-- ============================================================
-- Broadcast ForceUpdate to all registered frames
-- ============================================================

BroadcastUpdate = function()
	for _, frame in next, registeredFrames do
		local element = frame.FramedTargetedSpells
		if(element and element.ForceUpdate) then
			element.ForceUpdate(element)
		end
	end
end

-- ============================================================
-- State reset
-- ============================================================

Reset = function()
	wipe(casts)
	wipe(recheck)
	useSecretPath = false
	recheckFrame:Hide()
	BroadcastUpdate()
end

-- ============================================================
-- Register / Unregister frames
-- ============================================================

function F.CastTracker:Register(frame)
	for _, f in next, registeredFrames do
		if(f == frame) then return end
	end
	registeredFrames[#registeredFrames + 1] = frame
end

function F.CastTracker:Unregister(frame)
	for i, f in next, registeredFrames do
		if(f == frame) then
			table.remove(registeredFrames, i)
			return
		end
	end
end

-- ============================================================
-- Query API
-- ============================================================

function F.CastTracker:IsSecretPath()
	return useSecretPath
end

function F.CastTracker:GetAllActiveCasts()
	local result = {}
	local now = GetTime()
	for sourceKey, castInfo in next, casts do
		if(castInfo.endTime > now) then
			result[#result + 1] = castInfo
		else
			casts[sourceKey] = nil
		end
	end
	table.sort(result, function(a, b)
		if(a.isImportant ~= b.isImportant) then
			return a.isImportant
		end
		return a.startTime < b.startTime
	end)
	return result
end

function F.CastTracker:GetCastsOnUnit(unit)
	local result = {}
	local now = GetTime()
	for sourceKey, castInfo in next, casts do
		if(castInfo.endTime > now) then
			if(castInfo.targetUnit == unit) then
				result[#result + 1] = castInfo
			end
		else
			casts[sourceKey] = nil
		end
	end
	table.sort(result, function(a, b)
		if(a.isImportant ~= b.isImportant) then
			return a.isImportant
		end
		return a.startTime < b.startTime
	end)
	return result
end

-- ============================================================
-- Enable / Disable the tracker globally
-- ============================================================

function F.CastTracker:Enable()
	eventFrame:RegisterEvent('UNIT_SPELLCAST_START')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_STOP')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_DELAYED')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_FAILED')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_INTERRUPTED')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_CHANNEL_START')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_CHANNEL_STOP')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_CHANNEL_UPDATE')
	eventFrame:RegisterEvent('PLAYER_TARGET_CHANGED')
	eventFrame:RegisterEvent('NAME_PLATE_UNIT_ADDED')
	eventFrame:RegisterEvent('NAME_PLATE_UNIT_REMOVED')
	eventFrame:RegisterEvent('ENCOUNTER_END')
	eventFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
	eventFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
end

function F.CastTracker:Disable()
	Reset()
	eventFrame:UnregisterAllEvents()
end
```

- [ ] **Step 2: Commit**

```bash
git add Core/CastTracker.lua
git commit -m "feat(cast-tracker): add event registration, state management, and query API"
```

---

### Task 3: CastTracker — Cast Detection and Target Resolution

**Files:**
- Modify: `Core/CastTracker.lua` (add `CheckUnitCast`, event handler, recheck OnUpdate)

**Context:** This is the core logic. `CheckUnitCast` queries `UnitCastingInfo` / `UnitChannelInfo` on a source unit, resolves the target, stores the cast, and broadcasts. The event handler dispatches to `CheckUnitCast` or removes casts. The recheck OnUpdate re-polls every 0.1s.

**Reference:** Cell's `CheckUnitCast` function (lines 170-270), event handler (lines 280-330), recheck OnUpdate (lines 250-280).

- [ ] **Step 1: Add CheckUnitCast between the forward declarations and BroadcastUpdate**

Insert after the `-- Forward declarations` section and before `-- Broadcast ForceUpdate`, replacing the forward declaration comment block:

```lua
-- ============================================================
-- Check if a source unit is casting at a group member
-- ============================================================

CheckUnitCast = function(sourceUnit, isRecheck)
	if(not UnitIsEnemy('player', sourceUnit)) then return end

	local sourceKey = sourceUnit
	local previousTarget

	if(casts[sourceKey]) then
		previousTarget = casts[sourceKey].targetUnit
		if(casts[sourceKey].endTime <= GetTime()) then
			casts[sourceKey] = nil
			BroadcastUpdate()
			previousTarget = nil
		end
	end

	-- Query cast info: UnitCastingInfo or UnitChannelInfo
	local name, _, texture, startTimeMS, endTimeMS, _, _, _, spellId = UnitCastingInfo(sourceUnit)
	local isChanneling = false
	if(not name) then
		name, _, texture, startTimeMS, endTimeMS, _, _, spellId = UnitChannelInfo(sourceUnit)
		isChanneling = true
	end

	if(not name) then return end

	-- Get icon: C_Spell.GetSpellTexture is C-level and accepts secret spellId
	if(C_Spell and C_Spell.GetSpellTexture and spellId) then
		local tex = C_Spell.GetSpellTexture(spellId)
		if(tex) then texture = tex end
	end

	-- Determine importance (priority signal, not hard filter)
	local isImportant = false
	if(C_Spell and C_Spell.IsSpellImportant and spellId) then
		local result = C_Spell.IsSpellImportant(spellId)
		if(not F.IsValueNonSecret(result)) then
			-- Secret boolean — treat as important
			isImportant = true
		elseif(result) then
			isImportant = true
		end
	end

	-- Time values may be secret
	local startTime, endTime
	if(F.IsValueNonSecret(startTimeMS) and F.IsValueNonSecret(endTimeMS)) then
		startTime = startTimeMS / 1000
		endTime = endTimeMS / 1000
	else
		startTime = GetTime()
		endTime = GetTime() + 3
	end

	-- Update or create cast entry
	if(casts[sourceKey]) then
		casts[sourceKey].startTime = startTime
		casts[sourceKey].endTime = endTime
		casts[sourceKey].icon = texture
		casts[sourceKey].spellId = spellId
		casts[sourceKey].isImportant = isImportant
		casts[sourceKey].isChanneling = isChanneling
	else
		casts[sourceKey] = {
			startTime    = startTime,
			endTime      = endTime,
			icon         = texture,
			isChanneling = isChanneling,
			sourceUnit   = sourceUnit,
			spellId      = spellId,
			isImportant  = isImportant,
			targetUnit   = nil,
			recheck      = 0,
		}
	end

	-- Resolve target
	local targetUnit, isSecret = GetTargetUnitID_Safe(sourceUnit .. 'target')

	if(isSecret) then
		useSecretPath = true
		casts[sourceKey].targetUnit = nil
		BroadcastUpdate()
	else
		casts[sourceKey].targetUnit = targetUnit
		BroadcastUpdate()
	end

	-- Schedule recheck (target can change mid-cast)
	if(not isRecheck) then
		if(not recheck[sourceKey]) then
			recheck[sourceKey] = sourceUnit
		end
		recheckFrame:Show()
	end

	if(not useSecretPath and previousTarget and previousTarget ~= targetUnit) then
		BroadcastUpdate()
	end
end
```

- [ ] **Step 2: Add the event handler at the bottom of the file (before Enable/Disable)**

Insert before the `-- Enable / Disable` section:

```lua
-- ============================================================
-- Event handler
-- ============================================================

eventFrame:SetScript('OnEvent', function(_, event, sourceUnit)
	if(event == 'ENCOUNTER_END' or event == 'PLAYER_REGEN_ENABLED' or event == 'PLAYER_ENTERING_WORLD') then
		Reset()
		return
	end

	-- Filter soft-target units
	if(sourceUnit and strfind(sourceUnit, '^soft')) then return end

	if(event == 'PLAYER_TARGET_CHANGED') then
		CheckUnitCast('target')

	elseif(event == 'UNIT_SPELLCAST_START'
		or event == 'UNIT_SPELLCAST_CHANNEL_START'
		or event == 'UNIT_SPELLCAST_DELAYED'
		or event == 'UNIT_SPELLCAST_CHANNEL_UPDATE'
		or event == 'NAME_PLATE_UNIT_ADDED') then
		CheckUnitCast(sourceUnit)

	elseif(event == 'UNIT_SPELLCAST_STOP'
		or event == 'UNIT_SPELLCAST_INTERRUPTED'
		or event == 'UNIT_SPELLCAST_FAILED'
		or event == 'UNIT_SPELLCAST_CHANNEL_STOP') then
		local sourceKey = sourceUnit
		if(casts[sourceKey]) then
			casts[sourceKey] = nil
			BroadcastUpdate()
		end

	elseif(event == 'NAME_PLATE_UNIT_REMOVED') then
		local sourceKey = sourceUnit
		if(casts[sourceKey]) then
			casts[sourceKey] = nil
			BroadcastUpdate()
		end
	end
end)

-- ============================================================
-- Recheck OnUpdate (0.1s interval, up to 6 rechecks)
-- ============================================================

recheckFrame:SetScript('OnUpdate', function(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if(self.elapsed < 0.1) then return end
	self.elapsed = 0

	local empty = true

	for sourceKey, unit in next, recheck do
		if(casts[sourceKey]) then
			casts[sourceKey].recheck = casts[sourceKey].recheck + 1
			if(casts[sourceKey].recheck >= 6) then
				recheck[sourceKey] = nil
			else
				empty = false
				if(useSecretPath) then
					CheckUnitCast(unit, true)
				else
					local recheckRequired
					if(not casts[sourceKey].targetUnit) then
						recheckRequired = UnitExists(unit .. 'target')
					else
						recheckRequired = not SafeUnitIsUnit(unit .. 'target', casts[sourceKey].targetUnit)
					end
					if(recheckRequired) then
						CheckUnitCast(unit, true)
					end
				end
			end
		else
			recheck[sourceKey] = nil
		end
	end

	if(empty) then
		self:Hide()
	end
end)
```

- [ ] **Step 3: Commit**

```bash
git add Core/CastTracker.lua
git commit -m "feat(cast-tracker): add CheckUnitCast, event handler, and recheck timer"
```

---

### Task 4: Rewrite TargetedSpells Element — Update Function

**Files:**
- Modify: `Elements/Auras/TargetedSpells.lua`

**Context:** Replace the entire Update function body and delete all CLEU-related code (`makeCLEUHandler`, CLEU comments). The Update function now reads from `F.CastTracker` and has two display paths (non-secret and secret). The existing `showSpell`/`hideSpell` helpers are replaced with new `showCasts`/`hideAll`/`showCastsSecret` functions that handle multi-icon display and the secret path.

**Reference:** Cell's `ShowCasts` (non-secret, lines 75-95), `ShowCastsSecret` (secret, lines 115-150), `HideCasts` (lines 70-80). Adapt for Framed's BorderIcon/Glow API.

- [ ] **Step 1: Replace helpers and Update function**

Replace everything from `-- Helpers` through the end of `ForceUpdate` (lines 30-95) with:

```lua
local UnitIsUnit = UnitIsUnit

-- ============================================================
-- Helpers
-- ============================================================

--- Hide all indicators on the element — pool entries + glow.
--- @param element table
local function hideAll(element)
	local pool = element._pool
	if(pool) then
		for _, bi in next, pool do
			bi:Clear()
			bi:SetAlpha(1)
		end
	end
	if(element._glow) then
		element._glow:Stop()
	end
	-- Reset glow frame alpha in case SetAlphaFromBoolean was used
	if(element._glowFrame) then
		element._glowFrame:SetAlpha(1)
		element._glowFrame:Show()
	end
end

--- Display casts on this element (non-secret path).
--- @param element table
--- @param castList table  Sorted casts from CastTracker
local function showCasts(element, castList)
	local displayMode = element._displayMode
	local maxDisplayed = element._maxDisplayed or 1
	local count = math.min(#castList, maxDisplayed)
	local pool = element._pool

	-- Icons display
	if(displayMode == DisplayMode.ICONS or displayMode == DisplayMode.BOTH) then
		for i = 1, count do
			local cast = castList[i]
			local bi = pool[i]
			if(bi) then
				local duration = cast.endTime - cast.startTime
				bi.cooldown:SetReverse(not cast.isChanneling)
				bi:SetAura(cast.spellId, cast.icon, duration, cast.endTime, 0, nil)
				local bc = element._borderColor
				if(bc) then
					bi:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
				end
				bi:Show()
			end
		end
		-- Hide unused pool entries
		for i = count + 1, #pool do
			pool[i]:Clear()
		end
	end

	-- Glow display
	if(count > 0 and (displayMode == DisplayMode.BORDER_GLOW or displayMode == DisplayMode.BOTH)) then
		if(element._glow) then
			element._glow:Start(element._glowColor, element._glowType, element._glowConfig)
		end
	elseif(element._glow) then
		element._glow:Stop()
	end
end

--- Display casts on this element (secret path — uses SetAlphaFromBoolean).
--- @param element table
--- @param castList table  All active casts from CastTracker
--- @param unit string  This frame's unit token
local function showCastsSecret(element, castList, unit)
	local displayMode = element._displayMode
	local maxDisplayed = element._maxDisplayed or 1
	local count = math.min(#castList, maxDisplayed)
	local pool = element._pool

	-- Icons display
	if(displayMode == DisplayMode.ICONS or displayMode == DisplayMode.BOTH) then
		for i = 1, count do
			local cast = castList[i]
			local bi = pool[i]
			if(bi) then
				local duration = cast.endTime - cast.startTime
				bi.cooldown:SetReverse(not cast.isChanneling)
				bi:SetAura(cast.spellId, cast.icon, duration, cast.endTime, 0, nil)
				local bc = element._borderColor
				if(bc) then
					bi:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
				end
				bi:Show()
				-- C-level: set alpha 1 if targeting this unit, 0 otherwise
				bi:SetAlphaFromBoolean(UnitIsUnit(cast.sourceUnit .. 'target', unit), 1, 0)
			end
		end
		-- Hide unused pool entries
		for i = count + 1, #pool do
			pool[i]:Clear()
			pool[i]:SetAlpha(1)
		end
	end

	-- Glow display
	if(count > 0 and (displayMode == DisplayMode.BORDER_GLOW or displayMode == DisplayMode.BOTH)) then
		if(element._glow) then
			element._glow:Start(element._glowColor, element._glowType, element._glowConfig)
		end
		-- Use SetAlphaFromBoolean on the glow frame
		if(element._glowFrame) then
			element._glowFrame:Show()
			element._glowFrame:SetAlphaFromBoolean(UnitIsUnit(castList[1].sourceUnit .. 'target', unit), 1, 0)
		end
	elseif(element._glow) then
		element._glow:Stop()
		if(element._glowFrame) then
			element._glowFrame:SetAlpha(1)
		end
	end
end

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedTargetedSpells
	if(not element) then return end

	if(not unit) then unit = self.unit end
	if(not unit) then return end

	if(F.CastTracker:IsSecretPath()) then
		local allCasts = F.CastTracker:GetAllActiveCasts()
		if(#allCasts == 0) then
			hideAll(element)
		else
			showCastsSecret(element, allCasts, unit)
		end
	else
		local unitCasts = F.CastTracker:GetCastsOnUnit(unit)
		if(#unitCasts == 0) then
			hideAll(element)
		else
			showCasts(element, unitCasts)
		end
	end
end

-- ============================================================
-- ForceUpdate
-- ============================================================

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end
```

- [ ] **Step 2: Delete CLEU handler**

Delete the entire `-- CLEU listener builder` section (the `makeCLEUHandler` function). It should be lines ~97-145 in the current file — everything from `-- ============================================================` / `-- CLEU listener builder` through the closing `end` of the returned function.

- [ ] **Step 3: Commit**

```bash
git add Elements/Auras/TargetedSpells.lua
git commit -m "feat(targeted-spells): rewrite Update with CastTracker display paths, delete CLEU handler"
```

---

### Task 5: Rewrite TargetedSpells Element — Enable/Disable and Setup

**Files:**
- Modify: `Elements/Auras/TargetedSpells.lua`

**Context:** Replace Enable to register with CastTracker instead of creating a CLEU frame. Replace Disable to unregister and hide. Update Setup to create a pool of BorderIcons (for multi-icon display) and store `_maxDisplayed` and `_glowFrame`. Remove `_cleuFrame`, `_activeSourceGUID`, `_activeSpellId` from the container.

- [ ] **Step 1: Replace Enable and Disable**

Replace the `-- Enable / Disable` section with:

```lua
-- ============================================================
-- Enable / Disable
-- ============================================================

local function Enable(self, unit)
	local element = self.FramedTargetedSpells
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	F.CastTracker:Register(self)

	return true
end

local function Disable(self)
	local element = self.FramedTargetedSpells
	if(not element) then return end

	F.CastTracker:Unregister(self)
	hideAll(element)
end
```

- [ ] **Step 2: Replace Setup to create a pool and store glowFrame**

Replace the `-- Setup` section. The key changes are:
- Create a `_pool` array of BorderIcons (up to `maxDisplayed`) instead of a single `_borderIcon`
- Store `_maxDisplayed` on the container
- Store `_glowFrame` (the glow indicator's parent frame) for secret path `SetAlphaFromBoolean`
- Remove `_activeSourceGUID`, `_activeSpellId`, `_cleuFrame`

```lua
-- ============================================================
-- Setup
-- ============================================================

--- Create a TargetedSpells element on a unit frame.
--- Shows BorderIcons and/or Glow when enemies are casting at this unit.
--- Uses F.CastTracker for cast detection (not CLEU).
--- Assigns result to self.FramedTargetedSpells, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: displayMode, iconSize, borderColor, anchor,
---                       frameLevel, maxDisplayed, glow = { type, color, lines, frequency, length, thickness }
function F.Elements.TargetedSpells.Setup(self, config)
	config = config or {}

	-- Backward compat: map old lowercase display mode strings to new PascalCase values
	local rawMode = config.displayMode or DisplayMode.BOTH
	local displayMode = legacyDisplayModeMap[rawMode] or rawMode

	local iconSize     = config.iconSize     or 16
	local maxDisplayed = config.maxDisplayed  or 1
	local anchor       = config.anchor       or { 'CENTER', self, 'CENTER', 0, 0 }
	local frameLevel   = config.frameLevel   or nil

	-- Border color for the BorderIcon border
	local borderColor = config.borderColor

	-- Glow subtable
	local glowCfg   = config.glow or {}
	local glowType  = glowCfg.type  or C.GlowType.PROC
	local glowColor = glowCfg.color or C.Colors.accent
	local glowConfig = nil
	if(glowCfg.lines or glowCfg.frequency or glowCfg.length or glowCfg.thickness) then
		glowConfig = {
			lines     = glowCfg.lines,
			frequency = glowCfg.frequency,
			length    = glowCfg.length,
			thickness = glowCfg.thickness,
		}
	end

	-- Create BorderIcon pool
	local pool = {}
	if(displayMode == DisplayMode.ICONS or displayMode == DisplayMode.BOTH) then
		for i = 1, maxDisplayed do
			local biConfig = {
				showCooldown = true,
				showStacks   = false,
				showDuration = false,
				borderColor  = borderColor,
			}
			if(frameLevel) then
				biConfig.frameLevel = frameLevel
			end
			local bi = F.Indicators.BorderIcon.Create(self, iconSize, biConfig)
			local a = anchor
			local offset = (i - 1) * (iconSize + 2)
			bi:SetPoint(a[1], a[2], a[3], (a[4] or 0) + offset, a[5] or 0)
			pool[i] = bi
		end
	end

	-- Create glow
	local glow, glowFrame
	if(displayMode == DisplayMode.BORDER_GLOW or displayMode == DisplayMode.BOTH) then
		-- Glow needs a dedicated wrapper frame for SetAlphaFromBoolean on secret path.
		-- Glow.Create applies glow effects to the parent frame directly (_parent),
		-- so we create a wrapper frame that the glow attaches to, and we control
		-- that wrapper's alpha via SetAlphaFromBoolean.
		glowFrame = CreateFrame('Frame', nil, self)
		glowFrame:SetAllPoints(self)
		glowFrame:SetFrameLevel(self:GetFrameLevel() + (frameLevel or 10))
		local glowCreateConfig = {
			glowType = glowType,
			color    = glowColor,
		}
		glow = F.Indicators.Glow.Create(glowFrame, glowCreateConfig)
	end

	local container = {
		_pool          = pool,
		_glow          = glow,
		_glowFrame     = glowFrame,
		_displayMode   = displayMode,
		_maxDisplayed  = maxDisplayed,
		_borderColor   = borderColor,
		_glowColor     = glowColor,
		_glowType      = glowType,
		_glowConfig    = glowConfig,
	}

	self.FramedTargetedSpells = container
end
```

- [ ] **Step 3: Verify the file no longer references CLEU, CombatLogGetCurrentEventInfo, or _activeSourceGUID**

Search the file for any remaining CLEU references. There should be none.

- [ ] **Step 4: Commit**

```bash
git add Elements/Auras/TargetedSpells.lua
git commit -m "feat(targeted-spells): replace Enable/Disable/Setup with CastTracker integration"
```

---

### Task 6: Wire Up CastTracker Initialization

**Files:**
- Modify: `Init.lua:39` (in the `PLAYER_LOGIN` handler, after `F.AutoSwitch.Check()`)

**Context:** The CastTracker needs to be enabled once globally when the addon initializes. Other systems are initialized in the `PLAYER_LOGIN` handler in `Init.lua` (e.g., `F.ClickCasting.RefreshAll()` at line 33, `F.AutoSwitch.Check()` at line 39). Add `F.CastTracker:Enable()` after `F.AutoSwitch.Check()` and before `F.EventBus:Fire('PLAYER_LOGIN')`.

**Important:** Do NOT modify the `oUF:AddElement` registration — it must remain at the bottom of `Elements/Auras/TargetedSpells.lua`.

- [ ] **Step 1: Add CastTracker:Enable() to Init.lua**

In `Init.lua`, after line 39 (`F.AutoSwitch.Check()`) and before line 41 (`F.EventBus:Fire('PLAYER_LOGIN')`), add:

```lua
		-- Enable cast tracker for targeted spells
		if(F.CastTracker) then
			F.CastTracker:Enable()
		end
```

- [ ] **Step 2: Commit**

```bash
git add Init.lua
git commit -m "feat: enable CastTracker on addon initialization"
```

---

### Task 7: Sync and Verify

**Files:**
- No code changes

- [ ] **Step 1: Sync to WoW addon folder**

```bash
rsync -av --delete --exclude='.git' --exclude='.DS_Store' --exclude='.superpowers' --exclude='docs/' /Users/josiahtoppin/Documents/Projects/Framed/ "/Applications/World of Warcraft/_retail_/Interface/AddOns/Framed/"
```

- [ ] **Step 2: Verify in-game**

`/reload` — verify:
1. No Lua errors on login
2. Target an enemy mob — if it casts at you or party members, targeted spell icons/glow should appear on the appropriate unit frame
3. Check both Icons mode and BorderGlow mode in settings
4. Verify indicators clear when casts end or on encounter reset
