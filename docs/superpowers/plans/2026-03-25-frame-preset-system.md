# Frame Preset System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "layout" concept with Frame Presets — complete configuration bundles scoped to content types, with auras moved to a dedicated per-preset per-unit-type subtree, a restructured settings sidebar, and a new preset management panel.

**Architecture:** Seven default presets (4 base + 3 derived with fallback). Data lives in `FramedDB.presets` with `unitConfigs`, `auras`, and `positions` per preset. Settings UI restructures into GLOBAL / FRAME_PRESETS / PRESET_SCOPED / BOTTOM sections. All scoped panels read/write through `F.Settings.GetEditingPreset()`. Auto-switch resolves preset at runtime via content detection + spec overrides + derived fallback chain.

**Tech Stack:** Lua (WoW API), oUF framework

**Spec:** `docs/superpowers/specs/2026-03-25-frame-preset-system-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Presets/Defaults.lua` | Default preset data for all 7 presets (replaces `Layouts/Defaults.lua`) |
| `Presets/Manager.lua` | Preset CRUD: copy settings, reset derived presets (replaces `Layouts/Manager.lua`) |
| `Presets/AutoSwitch.lua` | Content-type → preset resolution with spec overrides + derived fallback (replaces `Layouts/AutoSwitch.lua`) |
| `Presets/ContentDetection.lua` | Content type detection with camelCase keys (replaces `Layouts/ContentDetection.lua`) |
| `Settings/Panels/FramePresets.lua` | New preset management panel (list, copy, reset, auto-switch, spec overrides) |

### Removed Files
| File | Reason |
|------|--------|
| `Layouts/Defaults.lua` | Replaced by `Presets/Defaults.lua` |
| `Layouts/Manager.lua` | Replaced by `Presets/Manager.lua` |
| `Layouts/AutoSwitch.lua` | Replaced by `Presets/AutoSwitch.lua` |
| `Layouts/ContentDetection.lua` | Replaced by `Presets/ContentDetection.lua` |
| `Settings/Panels/Layouts.lua` | Replaced by `Settings/Panels/FramePresets.lua` |
| `Settings/Panels/Battlegrounds.lua` | Folded into single group frame item per preset |
| `Settings/Panels/WorldRaids.lua` | Folded into single group frame item per preset |

### Modified Files
| File | Changes |
|------|---------|
| `Core/Constants.lua` | Content type keys to camelCase, add preset metadata constants |
| `Core/Config.lua` | `accountDefaults.layouts` → `accountDefaults.presets`, `charDefaults` updated (remove `editModePositions`, update `autoSwitch` keys, restructure `specOverrides`) |
| `Units/StyleBuilder.lua` | `GetConfig()` resolves through active preset with derived fallback; aura config reads from `preset.auras` |
| `Settings/Framework.lua` | New sections (GLOBAL, FRAME_PRESETS, PRESET_SCOPED, BOTTOM), `GetEditingPreset()`/`SetEditingPreset()`, `EDITING_PRESET_CHANGED` event |
| `Settings/Sidebar.lua` | Sub-headings (FRAMES, AURAS), dynamic "Editing: X" label, dynamic group frame label, preset change listener |
| `Settings/MainFrame.lua` | Remove preview toggle if needed; adapt header for preset context |
| `Settings/FrameSettingsBuilder.lua` | Config accessors read from `presets.X.unitConfigs.Y` via editing preset; add scoped banner |
| `Settings/Builders/IndicatorCRUD.lua` | Config path reads from `presets.X.auras.Y.buffs` via editing preset + unit type |
| `Settings/Panels/Appearance.lua` | Move to GLOBAL section |
| `Settings/Panels/ClickCasting.lua` | Move to GLOBAL section |
| `Settings/Panels/Profiles.lua` | Move to GLOBAL section |
| `Settings/Panels/Player.lua` | Move to PRESET_SCOPED section, add scoped banner |
| `Settings/Panels/Target.lua` | Move to PRESET_SCOPED section, add scoped banner |
| `Settings/Panels/TargetOfTarget.lua` | Move to PRESET_SCOPED section, add scoped banner |
| `Settings/Panels/Focus.lua` | Move to PRESET_SCOPED section, add scoped banner |
| `Settings/Panels/Pet.lua` | Move to PRESET_SCOPED section, add scoped banner |
| `Settings/Panels/Boss.lua` | Move to PRESET_SCOPED section, add scoped banner |
| `Settings/Panels/PartyFrames.lua` | Dynamic label per preset, PRESET_SCOPED section, hidden for Solo |
| `Settings/Panels/RaidFrames.lua` | Remove — group frame is now a single dynamic item in PartyFrames.lua |
| `Settings/Panels/ArenaFrames.lua` | Remove — group frame is now a single dynamic item |
| `Settings/Panels/Buffs.lua` | PRESET_SCOPED section, add unit type dropdown, scoped banner, copy-to button |
| `Settings/Panels/Debuffs.lua` | Same as Buffs |
| `Settings/Panels/RaidDebuffs.lua` | Same as Buffs |
| `Settings/Panels/Externals.lua` | Same as Buffs |
| `Settings/Panels/Defensives.lua` | Same as Buffs |
| `Settings/Panels/MissingBuffs.lua` | Same as Buffs |
| `Settings/Panels/PrivateAuras.lua` | Same as Buffs |
| `Settings/Panels/TargetedSpells.lua` | Same as Buffs |
| `Settings/Panels/Dispels.lua` | Same as Buffs |
| `Settings/Panels/LossOfControl.lua` | Same as Buffs |
| `Settings/Panels/CrowdControl.lua` | Same as Buffs |
| `Settings/Panels/About.lua` | Move to BOTTOM section |
| `EditMode/EditMode.lua` | Positions save to `FramedDB.presets[editingPreset].positions`, label shows "Edit Mode: X Frame Preset" |
| `Init.lua` | `LayoutDefaults` → `PresetDefaults`, `LAYOUT_CHANGED` references updated |
| `Framed.toc` | Replace Layouts/ section with Presets/, remove deleted panels, add new panels |

---

## Phase 1: Data Foundation

### Task 1: Update Constants — Content Type Keys to camelCase

**Files:**
- Modify: `Core/Constants.lua:71-90`

Update `ContentType` enum values from UPPER_CASE to camelCase strings, and add preset metadata.

- [ ] **Step 1: Update ContentType enum values**

```lua
Constants.ContentType = {
	SOLO         = 'solo',
	PARTY        = 'party',
	RAID         = 'raid',
	MYTHIC_RAID  = 'mythicRaid',
	WORLD_RAID   = 'worldRaid',
	BATTLEGROUND = 'battleground',
	ARENA        = 'arena',
}

-- Priority order for content detection (most specific first)
Constants.ContentTypePriority = {
	Constants.ContentType.ARENA,
	Constants.ContentType.BATTLEGROUND,
	Constants.ContentType.MYTHIC_RAID,
	Constants.ContentType.RAID,
	Constants.ContentType.WORLD_RAID,
	Constants.ContentType.PARTY,
	Constants.ContentType.SOLO,
}
```

- [ ] **Step 2: Add preset metadata constants**

```lua
-- Preset definitions: name → { isBase, fallback, groupKey, groupLabel }
-- groupKey is the unitConfigs/auras key for group frames
-- groupLabel is the sidebar display name
Constants.PresetInfo = {
	['Solo']          = { isBase = true,  fallback = nil,    groupKey = nil,     groupLabel = nil },
	['Party']         = { isBase = true,  fallback = nil,    groupKey = 'party', groupLabel = 'Party Frames' },
	['Raid']          = { isBase = true,  fallback = nil,    groupKey = 'raid',  groupLabel = 'Raid Frames' },
	['Arena']         = { isBase = true,  fallback = nil,    groupKey = 'arena', groupLabel = 'Arena Frames' },
	['Mythic Raid']   = { isBase = false, fallback = 'Raid', groupKey = 'raid',  groupLabel = 'Raid Frames' },
	['World Raid']    = { isBase = false, fallback = 'Raid', groupKey = 'raid',  groupLabel = 'Raid Frames' },
	['Battleground']  = { isBase = false, fallback = 'Raid', groupKey = 'raid',  groupLabel = 'Raid Frames' },
}

-- Ordered list of preset names for UI display
Constants.PresetOrder = {
	'Solo', 'Party', 'Raid', 'Arena',
	'Mythic Raid', 'World Raid', 'Battleground',
}
```

- [ ] **Step 3: Commit**

```bash
git add Core/Constants.lua
git commit -m "feat: update ContentType to camelCase, add PresetInfo metadata"
```

---

### Task 2: Create PresetDefaults — Full Default Preset Data

**Files:**
- Create: `Presets/Defaults.lua`
- Reference: `Layouts/Defaults.lua` (for existing unit config structure)

Build the complete default preset structure with `unitConfigs`, `auras`, and `positions` for all 7 presets. Auras are extracted from the old unitConfig fields into the new `preset.auras[unitType][auraType]` subtree.

- [ ] **Step 1: Create Presets/Defaults.lua with helper functions**

Start with the shared helper that builds a default unit config (extracted from current `Layouts/Defaults.lua` patterns). Add a helper that builds default aura config for a unit type.

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.PresetDefaults = {}

-- ============================================================
-- Shared unit config template (no aura fields — those live in preset.auras)
-- ============================================================
local function baseUnitConfig(overrides)
	local cfg = {
		width = 200, height = 36,
		healthColorMode = 'Class', smoothHealth = true,
		showHealthText = true, healthTextFormat = 'Percentage',
		showPower = true, powerHeight = 4,
		showName = true, nameColorMode = 'Class', nameTruncation = 10,
		showCastBar = false, showAbsorbBar = true,
		showRoleIcon = false, showLeaderIcon = false,
		showReadyCheck = false, showRaidIcon = true, showCombatIcon = false,
		showPortrait = false,
		statusText = true, targetHighlight = true, mouseoverHighlight = true,
		rangeAlpha = 0.4,
	}
	if(overrides) then
		for k, v in next, overrides do cfg[k] = v end
	end
	return cfg
end

-- Group frame config adds spacing/orientation/growth
local function baseGroupConfig(overrides)
	local cfg = baseUnitConfig({
		width = 72, height = 36,
		showRoleIcon = true, showLeaderIcon = true, showReadyCheck = true,
		spacing = 2, orientation = 'Vertical', growthDirection = 'TOP_TO_BOTTOM',
	})
	if(overrides) then
		for k, v in next, overrides do cfg[k] = v end
	end
	return cfg
end
```

- [ ] **Step 2: Add default aura config builder**

```lua
-- ============================================================
-- Default aura configs per unit type
-- ============================================================

-- Default buff indicator (shipped on every unit type)
local function defaultBuffIndicator()
	return {
		name = 'My Buffs',
		type = 'Icons',
		enabled = true,
		spells = {},
		castBy = 'me',
		iconSize = 14,
		maxDisplayed = 3,
		orientation = 'RIGHT',
		anchor = { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 },
	}
end

-- Build full aura config for a unit type
local function defaultAuras()
	return {
		buffs = {
			indicators = {
				['My Buffs'] = defaultBuffIndicator(),
			},
		},
		debuffs = {
			enabled = true, iconSize = 18, maxDisplayed = 3,
			showDuration = true, showAnimation = true,
			orientation = 'RIGHT',
			anchor = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
			frameLevel = 50,
		},
		raidDebuffs = {
			enabled = true, iconSize = 22,
			filterMode = 'ENCOUNTER_ONLY', minPriority = 3,
			showDuration = true, showStacks = true,
			anchor = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel = 60,
		},
		externals = {
			enabled = true, iconSize = 14, maxDisplayed = 2,
			showDuration = true, showStacks = false,
			orientation = 'RIGHT',
			anchor = { 'TOPRIGHT', nil, 'TOPRIGHT', -2, -2 },
		},
		defensives = {
			enabled = true, iconSize = 14, maxDisplayed = 2,
			showDuration = true, showStacks = false,
			orientation = 'LEFT',
			anchor = { 'TOPLEFT', nil, 'TOPLEFT', 2, -18 },
		},
		missingBuffs = {
			enabled = true, iconSize = 14,
			trackedBuffs = {},
			dimAlpha = 0.4, growDirection = 'RIGHT',
			anchor = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 2 },
		},
		targetedSpells = {
			enabled = true, displayMode = 'BorderGlow',
			iconSize = 22, borderColor = { 1, 0, 0, 1 },
			anchor = { 'CENTER', nil, 'CENTER', 0, 0 },
			glow = { type = 'PROC', color = { 1, 0, 0, 1 } },
		},
		dispellable = {
			enabled = true, iconSize = 14,
			highlightType = 'GRADIENT_HALF',
			anchor = { 'TOPLEFT', nil, 'TOPLEFT', 0, 0 },
			frameLevel = 55,
		},
		privateAuras = {
			enabled = true, iconSize = 18,
			anchor = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 18 },
		},
		lossOfControl = {},
		crowdControl = {},
	}
end
```

- [ ] **Step 3: Build all 7 preset defaults**

```lua
-- ============================================================
-- Unit types present in each preset category
-- ============================================================
local SOLO_UNITS   = { 'player', 'target', 'targettarget', 'focus', 'pet', 'boss' }
local PARTY_UNITS  = { 'player', 'target', 'targettarget', 'focus', 'pet', 'boss', 'party' }
local RAID_UNITS   = { 'player', 'target', 'targettarget', 'focus', 'pet', 'boss', 'raid' }
local ARENA_UNITS  = { 'player', 'target', 'targettarget', 'focus', 'pet', 'boss', 'arena' }

local function buildUnitConfigs(unitList, overridesPerUnit)
	local configs = {}
	for _, unitType in next, unitList do
		local overrides = overridesPerUnit and overridesPerUnit[unitType]
		if(unitType == 'party' or unitType == 'raid' or unitType == 'arena') then
			configs[unitType] = baseGroupConfig(overrides)
		else
			configs[unitType] = baseUnitConfig(overrides)
		end
	end
	return configs
end

local function buildAuras(unitList)
	local auras = {}
	for _, unitType in next, unitList do
		auras[unitType] = defaultAuras()
	end
	return auras
end

local function buildPreset(unitList, unitOverrides)
	return {
		positions = {},
		unitConfigs = buildUnitConfigs(unitList, unitOverrides),
		auras = buildAuras(unitList),
	}
end

-- ============================================================
-- GetAll — returns complete default preset table
-- ============================================================
function F.PresetDefaults.GetAll()
	local presets = {}

	-- Base presets
	presets['Solo'] = buildPreset(SOLO_UNITS, {
		player = { width = 200, height = 40, showCastBar = true, showPortrait = true, showCombatIcon = true },
		target = { width = 200, height = 40, showCastBar = true, showPortrait = true },
		targettarget = { width = 120, height = 28 },
		focus = { width = 150, height = 32, showCastBar = true },
		pet = { width = 120, height = 28 },
		boss = { width = 150, height = 36 },
	})
	presets['Solo'].isBase = true

	presets['Party'] = buildPreset(PARTY_UNITS, {
		player = { width = 200, height = 40, showCastBar = true, showPortrait = true },
		target = { width = 200, height = 40, showCastBar = true, showPortrait = true },
		targettarget = { width = 120, height = 28 },
		focus = { width = 150, height = 32, showCastBar = true },
		pet = { width = 120, height = 28 },
		boss = { width = 150, height = 36 },
		party = {},  -- inherits from baseGroupConfig which already has role/leader/readyCheck
	})
	presets['Party'].isBase = true

	presets['Raid'] = buildPreset(RAID_UNITS, {
		player = { width = 180, height = 36, showCastBar = true },
		target = { width = 180, height = 36, showCastBar = true },
		targettarget = { width = 100, height = 24 },
		focus = { width = 130, height = 28 },
		pet = { width = 100, height = 24 },
		boss = { width = 150, height = 36 },
		raid = { width = 72, height = 36, showRoleIcon = true, showReadyCheck = true },
	})
	presets['Raid'].isBase = true

	presets['Arena'] = buildPreset(ARENA_UNITS, {
		player = { width = 200, height = 40, showCastBar = true },
		target = { width = 200, height = 40, showCastBar = true },
		targettarget = { width = 120, height = 28 },
		focus = { width = 150, height = 32, showCastBar = true },
		pet = { width = 100, height = 24 },
		boss = { width = 150, height = 36 },
		arena = { width = 150, height = 36, showCastBar = true },
	})
	presets['Arena'].isBase = true

	-- Derived presets (copy from their fallback)
	for _, name in next, { 'Mythic Raid', 'World Raid', 'Battleground' } do
		local info = C.PresetInfo[name]
		presets[name] = F.DeepCopy(presets[info.fallback])
		presets[name].isBase = nil
		presets[name].customized = false
		presets[name].fallback = info.fallback
	end

	return presets
end

-- ============================================================
-- EnsureDefaults — populate FramedDB.presets on first run
-- ============================================================
function F.PresetDefaults.EnsureDefaults()
	if(not FramedDB) then FramedDB = {} end
	if(not FramedDB.presets) then
		FramedDB.presets = F.PresetDefaults.GetAll()
		return
	end

	-- Ensure each preset exists (don't overwrite user data)
	local defaults = F.PresetDefaults.GetAll()
	for name, preset in next, defaults do
		if(not FramedDB.presets[name]) then
			FramedDB.presets[name] = preset
		end
	end
end
```

- [ ] **Step 4: Commit**

```bash
git add Presets/Defaults.lua
git commit -m "feat: add PresetDefaults with full 7-preset default data"
```

---

### Task 3: Update Config.lua — accountDefaults and charDefaults

**Files:**
- Modify: `Core/Config.lua:13-48`

- [ ] **Step 1: Replace layouts with presets in accountDefaults**

Change `layouts = {}` to `presets = {}` in `accountDefaults`.

```lua
local accountDefaults = {
	general = {
		accentColor = { 0, 0.8, 1 },
		uiScale = 1.0,
		wizardCompleted = false,
		tooltipEnabled = true,
		tooltipHideInCombat = false,
		tooltipAnchor = 'ANCHOR_RIGHT',
		tooltipOffsetX = 0,
		tooltipOffsetY = 0,
	},
	presets = {},  -- Populated by Presets/Defaults.lua
	raidDebuffs = {
		overrides = {},
		custom = {},
	},
	profiles = {},
}
```

- [ ] **Step 2: Update charDefaults — camelCase keys, remove editModePositions**

```lua
local charDefaults = {
	autoSwitch = {
		['solo']         = 'Solo',
		['party']        = 'Party',
		['raid']         = 'Raid',
		['mythicRaid']   = 'Mythic Raid',
		['worldRaid']    = 'World Raid',
		['battleground'] = 'Battleground',
		['arena']        = 'Arena',
	},
	specOverrides = {},
	-- editModePositions removed — positions now live in each preset
	tourState = {
		completed = false,
		lastStep = 0,
	},
}
```

- [ ] **Step 3: Commit**

```bash
git add Core/Config.lua
git commit -m "feat: update Config defaults for preset system (layouts→presets, camelCase keys)"
```

---

## Phase 2: Core Modules

### Task 4: Create Presets/ContentDetection.lua

**Files:**
- Create: `Presets/ContentDetection.lua`
- Reference: `Layouts/ContentDetection.lua`

Port content detection to use camelCase content type keys.

- [ ] **Step 1: Create ContentDetection with camelCase returns**

Same detection logic as `Layouts/ContentDetection.lua`, but `Detect()` returns camelCase strings (`'solo'`, `'party'`, `'raid'`, `'mythicRaid'`, `'worldRaid'`, `'battleground'`, `'arena'`).

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.ContentDetection = {}

function F.ContentDetection.Detect()
	if(IsActiveBattlefieldArena and IsActiveBattlefieldArena()) then
		return C.ContentType.ARENA
	end

	local _, instanceType = IsInInstance()

	if(instanceType == 'arena') then
		return C.ContentType.ARENA
	end

	if(C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground()) then
		return C.ContentType.BATTLEGROUND
	end
	if(instanceType == 'pvp') then
		return C.ContentType.BATTLEGROUND
	end

	if(IsInRaid()) then
		if(instanceType == 'raid') then
			local difficultyID = GetRaidDifficultyID and GetRaidDifficultyID() or 0
			if(difficultyID == 16) then
				return C.ContentType.MYTHIC_RAID
			end
			return C.ContentType.RAID
		end
		-- Outdoor raid (world boss, etc.)
		return C.ContentType.WORLD_RAID
	end

	if(IsInGroup()) then
		return C.ContentType.PARTY
	end

	return C.ContentType.SOLO
end
```

- [ ] **Step 2: Commit**

```bash
git add Presets/ContentDetection.lua
git commit -m "feat: add ContentDetection with camelCase content type keys"
```

---

### Task 5: Create Presets/AutoSwitch.lua

**Files:**
- Create: `Presets/AutoSwitch.lua`
- Reference: `Layouts/AutoSwitch.lua`

Port auto-switch to use presets with derived fallback resolution.

- [ ] **Step 1: Create AutoSwitch with preset resolution and derived fallback**

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.AutoSwitch = {}

local currentPreset
local currentContentType
local pendingPreset

-- ============================================================
-- Resolution chain
-- ============================================================

--- Resolve which preset name to use for a content type.
--- Checks spec overrides first, then autoSwitch mapping.
local function ResolvePresetName(contentType)
	-- 1. Spec override (GetSpecializationInfo returns actual specID like 105, not index 1-4)
	local specIndex = GetSpecialization and GetSpecialization()
	local specID = specIndex and GetSpecializationInfo and select(1, GetSpecializationInfo(specIndex)) or nil
	local specOverrides = F.Config:GetChar('specOverrides')
	if(specOverrides and specOverrides[specID]) then
		local override = specOverrides[specID][contentType]
		if(override) then return override end
	end

	-- 2. Auto-switch mapping
	local autoSwitch = F.Config:GetChar('autoSwitch')
	if(autoSwitch and autoSwitch[contentType]) then
		return autoSwitch[contentType]
	end

	-- 3. Fallback
	return 'Solo'
end

--- Resolve the effective preset data, following derived fallback if needed.
--- Returns presetName (the resolved name) and presetData (the table to use).
function F.AutoSwitch.ResolvePreset(presetName)
	local presets = F.Config:Get('presets')
	if(not presets) then return presetName, nil end

	local preset = presets[presetName]
	if(not preset) then return presetName, nil end

	-- Derived preset: use fallback if not customized
	if(preset.fallback and preset.customized == false) then
		local fallbackData = presets[preset.fallback]
		if(fallbackData) then
			return presetName, fallbackData
		end
	end

	return presetName, preset
end

-- ============================================================
-- Activation
-- ============================================================

local function ActivatePreset(presetName)
	if(presetName == currentPreset) then return end
	currentPreset = presetName
	F.EventBus:Fire('PRESET_CHANGED', presetName)
end

function F.AutoSwitch.Check()
	local contentType = F.ContentDetection.Detect()
	currentContentType = contentType

	local presetName = ResolvePresetName(contentType)

	if(InCombatLockdown and InCombatLockdown()) then
		pendingPreset = presetName
		return
	end

	ActivatePreset(presetName)
end

local function ProcessPending()
	if(pendingPreset) then
		ActivatePreset(pendingPreset)
		pendingPreset = nil
	end
end

-- ============================================================
-- Getters
-- ============================================================

function F.AutoSwitch.GetCurrentPreset()
	return currentPreset or 'Solo'
end

function F.AutoSwitch.GetCurrentContentType()
	return currentContentType or C.ContentType.SOLO
end

-- ============================================================
-- Event handling
-- ============================================================

local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('GROUP_ROSTER_UPDATE')
eventFrame:RegisterEvent('ZONE_CHANGED_NEW_AREA')
eventFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
eventFrame:RegisterEvent('ACTIVE_TALENT_GROUP_CHANGED')
eventFrame:RegisterEvent('PLAYER_REGEN_ENABLED')

eventFrame:SetScript('OnEvent', function(self, event)
	if(event == 'PLAYER_REGEN_ENABLED') then
		ProcessPending()
	else
		F.AutoSwitch.Check()
	end
end)

-- Listen for preset data changes (copy/reset) and re-fire PRESET_CHANGED
-- so runtime frames refresh their config
F.EventBus:On('PRESET_DATA_CHANGED', function(presetName)
	if(presetName == currentPreset) then
		F.EventBus:Fire('PRESET_CHANGED', presetName)
	end
end)
```

- [ ] **Step 2: Commit**

```bash
git add Presets/AutoSwitch.lua
git commit -m "feat: add AutoSwitch with preset resolution and derived fallback"
```

---

### Task 6: Create Presets/Manager.lua

**Files:**
- Create: `Presets/Manager.lua`

Preset management: copy settings between presets, reset derived presets, query helpers.

- [ ] **Step 1: Create Manager with copy and reset operations**

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.PresetManager = {}

--- Get all preset names in display order.
function F.PresetManager.GetNames()
	return C.PresetOrder
end

--- Get preset info from Constants.
function F.PresetManager.GetInfo(name)
	return C.PresetInfo[name]
end

--- Check if a preset is a base preset.
function F.PresetManager.IsBase(name)
	local info = C.PresetInfo[name]
	return info and info.isBase or false
end

--- Check if a derived preset has been customized.
function F.PresetManager.IsCustomized(name)
	local preset = F.Config:Get('presets.' .. name)
	if(not preset) then return false end
	return preset.customized == true
end

--- Copy all settings from one preset to another.
--- Copies unitConfigs, auras, and positions. Flips customized=true on derived targets.
function F.PresetManager.CopySettings(sourceName, targetName)
	local presets = F.Config:Get('presets')
	if(not presets or not presets[sourceName] or not presets[targetName]) then return false end

	local source = presets[sourceName]
	-- If source is uncustomized derived, copy from its fallback
	local sourceData = source
	if(source.fallback and source.customized == false) then
		sourceData = presets[source.fallback] or source
	end

	local target = presets[targetName]
	target.unitConfigs = F.DeepCopy(sourceData.unitConfigs)
	target.auras = F.DeepCopy(sourceData.auras)
	target.positions = F.DeepCopy(sourceData.positions)

	-- Mark derived preset as customized
	if(target.fallback) then
		target.customized = true
	end

	F.EventBus:Fire('PRESET_DATA_CHANGED', targetName)
	return true
end

--- Reset a derived preset to its fallback defaults.
function F.PresetManager.ResetToDefault(name)
	local presets = F.Config:Get('presets')
	if(not presets or not presets[name]) then return false end

	local preset = presets[name]
	if(not preset.fallback) then return false end  -- can't reset base presets

	-- Copy fresh defaults from fallback
	local defaults = F.PresetDefaults.GetAll()
	local defaultPreset = defaults[name]
	if(not defaultPreset) then return false end

	preset.unitConfigs = F.DeepCopy(defaultPreset.unitConfigs)
	preset.auras = F.DeepCopy(defaultPreset.auras)
	preset.positions = F.DeepCopy(defaultPreset.positions)
	preset.customized = false

	F.EventBus:Fire('PRESET_DATA_CHANGED', name)
	return true
end

--- Mark a derived preset as customized (called on first settings write).
function F.PresetManager.MarkCustomized(presetName)
	local preset = F.Config:Get('presets.' .. presetName)
	if(not preset or not preset.fallback) then return end
	if(preset.customized) then return end
	preset.customized = true
end

-- No rename/delete for the 7 fixed presets. If custom presets are added later,
-- UpdateAutoSwitchReferences would be needed here.
```

- [ ] **Step 2: Commit**

```bash
git add Presets/Manager.lua
git commit -m "feat: add PresetManager with copy settings and reset operations"
```

---

## Phase 3: Config Resolution

### Task 7: Rewrite StyleBuilder.GetConfig for Presets

**Files:**
- Modify: `Units/StyleBuilder.lua`

Update `GetConfig()` to resolve unit configs through the active preset with derived fallback.

- [ ] **Step 1: Read current StyleBuilder.lua to understand full structure**

Read the file, identify the `GetConfig` function and the `Presets` table.

- [ ] **Step 2: Rewrite GetConfig to use preset resolution**

Replace the current `GetConfig` that reads from `F.Config:Get('layouts')` with preset-aware resolution:

```lua
--- Get the effective unit config for a unit type.
--- Uses the runtime active preset (from AutoSwitch), with derived fallback.
function F.StyleBuilder.GetConfig(unitType)
	local presetName = F.AutoSwitch.GetCurrentPreset()
	local _, presetData = F.AutoSwitch.ResolvePreset(presetName)

	if(presetData and presetData.unitConfigs and presetData.unitConfigs[unitType]) then
		return presetData.unitConfigs[unitType]
	end

	-- Fall back to built-in preset
	if(F.StyleBuilder.Presets[unitType]) then
		return F.StyleBuilder.Presets[unitType]
	end

	return DEFAULT_CONFIG
end
```

- [ ] **Step 3: Add GetAuraConfig helper**

```lua
--- Get the effective aura config for a unit type and aura type.
--- @param unitType  string  e.g. 'player', 'party', 'raid'
--- @param auraType  string  e.g. 'buffs', 'debuffs', 'raidDebuffs'
function F.StyleBuilder.GetAuraConfig(unitType, auraType)
	local presetName = F.AutoSwitch.GetCurrentPreset()
	local _, presetData = F.AutoSwitch.ResolvePreset(presetName)

	if(presetData and presetData.auras and presetData.auras[unitType]) then
		return presetData.auras[unitType][auraType] or {}
	end

	return {}
end
```

- [ ] **Step 4: Commit**

```bash
git add Units/StyleBuilder.lua
git commit -m "feat: rewrite StyleBuilder.GetConfig for preset resolution with fallback"
```

---

### Task 8: Update Unit Spawn Files to Pass Aura Configs from Preset

**Files:**
- Modify: All unit files in `Units/` that call aura element Setup functions

The aura element Setup functions already accept a `config` parameter. The change is in *what config gets passed*. Currently the config comes from `unitConfigs[unitType].buffs` etc. Now it must come from `preset.auras[unitType].buffs`.

- [ ] **Step 1: Identify where aura configs are passed to Setup**

Read each unit file's style function to find where aura element configs are sourced. The style function calls `F.StyleBuilder.GetConfig(unitType)` and passes sub-fields to element Setup. These need to pass `F.StyleBuilder.GetAuraConfig(unitType, 'buffs')` instead.

- [ ] **Step 2: Update aura config sourcing in the shared style application**

In the style function (likely in StyleBuilder or in each unit file), change aura config reads:

```lua
-- OLD: config.buffs, config.debuffs, etc. (from unitConfigs)
-- NEW: separate aura config lookup
local auraConfig = F.StyleBuilder.GetAuraConfig(unitType, 'buffs')
```

Update each aura element setup call to use the new path.

- [ ] **Step 3: Commit**

```bash
git add Units/
git commit -m "feat: wire aura element configs from preset.auras instead of unitConfigs"
```

---

## Phase 4: Settings Framework

### Task 9: Restructure Settings Framework Sections

**Files:**
- Modify: `Settings/Framework.lua`

Replace old sections with new ones and add editing preset state.

- [ ] **Step 1: Replace section definitions**

```lua
local SECTIONS = {
	{ id = 'GLOBAL',         label = 'GLOBAL',        order = 1 },
	{ id = 'FRAME_PRESETS',  label = 'FRAME PRESETS',  order = 2 },
	{ id = 'PRESET_SCOPED',  label = '',               order = 3 },  -- uses "Editing: X" instead
	{ id = 'BOTTOM',         label = '',               order = 99 },
}
```

- [ ] **Step 2: Add editing preset state**

```lua
local editingPreset = nil

function Settings.GetEditingPreset()
	return editingPreset or F.AutoSwitch.GetCurrentPreset() or 'Solo'
end

function Settings.SetEditingPreset(presetName)
	if(editingPreset == presetName) then return end
	editingPreset = presetName
	F.EventBus:Fire('EDITING_PRESET_CHANGED', presetName)
end
```

- [ ] **Step 3: Commit**

```bash
git add Settings/Framework.lua
git commit -m "feat: restructure Settings sections, add editing preset state"
```

---

### Task 10: Restructure Sidebar

**Files:**
- Modify: `Settings/Sidebar.lua`

Add "Editing: X Frame Preset" accent label, FRAMES/AURAS sub-headings, dynamic group frame label, and `EDITING_PRESET_CHANGED` listener.

- [ ] **Step 1: Add "Editing: X" label in PRESET_SCOPED section**

Before the first nav button in the PRESET_SCOPED section, create a non-interactive accent-colored label:

```lua
-- Create accent label: "Editing: Solo Frame Preset"
local editingLabel = sidebar:CreateFontString(nil, 'OVERLAY')
editingLabel:SetFont(C.Font.file, C.Font.sizeSmall, '')
editingLabel:SetTextColor(unpack(C.Colors.accent))
editingLabel:SetText('Editing: ' .. F.Settings.GetEditingPreset() .. ' Frame Preset')
```

- [ ] **Step 2: Add FRAMES and AURAS sub-headings**

Within the PRESET_SCOPED section, insert visual sub-heading labels (not clickable):

```lua
-- Sub-heading factory
local function createSubHeading(parent, text, yOffset)
	local label = parent:CreateFontString(nil, 'OVERLAY')
	label:SetFont(C.Font.file, C.Font.sizeSmall, '')
	label:SetTextColor(unpack(C.Colors.textSecondary))
	label:SetText(text)
	Widgets.SetPoint(label, 'TOPLEFT', parent, 'TOPLEFT', 12, yOffset)
	return label, yOffset - 16
end
```

Insert `createSubHeading(sidebar, 'FRAMES', yOffset)` before the Player nav button and `createSubHeading(sidebar, 'AURAS', yOffset)` before the Buffs nav button.

- [ ] **Step 3: Make group frame label dynamic**

The group frame nav button's label changes based on the editing preset:
- Solo → hidden
- Party → "Party Frames"
- Raid/Mythic Raid/World Raid/Battleground → "Raid Frames"
- Arena → "Arena Frames"

```lua
local function getGroupFrameLabel()
	local info = C.PresetInfo[F.Settings.GetEditingPreset()]
	return info and info.groupLabel or nil
end
```

Hide the button entirely when `getGroupFrameLabel()` returns nil. Note: the Boss nav button is **always visible** regardless of preset (boss encounters exist across all content types).

- [ ] **Step 4: Listen for EDITING_PRESET_CHANGED**

```lua
F.EventBus:On('EDITING_PRESET_CHANGED', function(presetName)
	-- Update "Editing: X" label
	editingLabel:SetText('Editing: ' .. presetName .. ' Frame Preset')

	-- Update group frame button visibility/label
	local groupLabel = getGroupFrameLabel()
	if(groupLabel) then
		groupFrameBtn:Show()
		groupFrameBtn._labelText:SetText(groupLabel)
	else
		groupFrameBtn:Hide()
	end

	-- Rebuild sidebar height if needed
end)
```

- [ ] **Step 5: Commit**

```bash
git add Settings/Sidebar.lua
git commit -m "feat: restructure sidebar with sub-headings, dynamic preset label, group frame label"
```

---

### Task 11: Update All Panel Registrations — Section Moves

**Files:**
- Modify: All `Settings/Panels/*.lua` files

Move panels to their new sections. This is a mechanical change to the `section` field in each `RegisterPanel` call.

- [ ] **Step 1: Move global panels to GLOBAL section**

In `Appearance.lua`, `ClickCasting.lua`, `Profiles.lua`: change `section = 'GENERAL'` to `section = 'GLOBAL'`.

- [ ] **Step 2: Move frame panels to PRESET_SCOPED section**

In `Player.lua`, `Target.lua`, `TargetOfTarget.lua`, `Focus.lua`, `Pet.lua`, `Boss.lua`, `PartyFrames.lua`: change `section = 'UNIT_FRAMES'` or `section = 'GROUP_FRAMES'` to `section = 'PRESET_SCOPED'`. Skip `RaidFrames.lua`, `ArenaFrames.lua`, `Battlegrounds.lua`, `WorldRaids.lua` — these are deleted in Task 16.

- [ ] **Step 3: Move aura panels to PRESET_SCOPED section**

In `Buffs.lua`, `Debuffs.lua`, `RaidDebuffs.lua`, `Externals.lua`, `Defensives.lua`, `MissingBuffs.lua`, `PrivateAuras.lua`, `TargetedSpells.lua`, `Dispels.lua`, `LossOfControl.lua`, `CrowdControl.lua`: change `section = 'AURAS'` to `section = 'PRESET_SCOPED'`.

- [ ] **Step 4: Move About and Tour to BOTTOM section**

In `About.lua` and `Tour.lua`: change section to `'BOTTOM'`.

- [ ] **Step 5: Commit**

```bash
git add Settings/Panels/
git commit -m "feat: move all panels to new section IDs (GLOBAL, PRESET_SCOPED, BOTTOM)"
```

---

## Phase 5: Settings Config Paths

### Task 12: Update FrameSettingsBuilder Config Paths

**Files:**
- Modify: `Settings/FrameSettingsBuilder.lua`

Change config accessors to read/write through the editing preset.

- [ ] **Step 1: Update config accessor helpers**

Replace the layout-based config path with preset-based:

```lua
-- OLD:
local layoutName = F.AutoSwitch and F.AutoSwitch.GetCurrentLayout() or 'Default Solo'
local function getConfig(key)
	return F.Config:Get('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. key)
end
local function setConfig(key, value)
	F.Config:Set('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. key, value)
end

-- NEW:
local function getPresetName()
	return F.Settings.GetEditingPreset()
end
local function getConfig(key)
	return F.Config:Get('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key)
end
local function setConfig(key, value)
	F.Config:Set('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key, value)
	F.PresetManager.MarkCustomized(getPresetName())
end
```

- [ ] **Step 2: Add scoped page banner**

At the top of the panel content, add a subtle banner:

```lua
-- Scoped page banner
local banner = content:CreateFontString(nil, 'OVERLAY')
banner:SetFont(C.Font.file, C.Font.sizeSmall, '')
banner:SetTextColor(unpack(C.Colors.accent))
banner:SetText('These settings apply to: ' .. getPresetName() .. ' Frame Preset')
Widgets.SetPoint(banner, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
yOffset = yOffset - 16 - C.Spacing.tight
```

- [ ] **Step 3: Listen for EDITING_PRESET_CHANGED to refresh**

The panel needs to rebuild when the preset changes. Since panels are built lazily and cached, the simplest approach is to track the preset name at build time and rebuild if it changes:

```lua
-- Store reference for refresh
scroll._builtForPreset = getPresetName()

F.EventBus:On('EDITING_PRESET_CHANGED', function(presetName)
	if(scroll._builtForPreset and scroll._builtForPreset ~= presetName) then
		-- Mark panel as needing rebuild on next show
		Settings._panelFrames[panelId] = nil
	end
end)
```

- [ ] **Step 4: Commit**

```bash
git add Settings/FrameSettingsBuilder.lua
git commit -m "feat: update FrameSettingsBuilder to read/write through editing preset"
```

---

### Task 13: Update IndicatorCRUD Config Paths

**Files:**
- Modify: `Settings/Builders/IndicatorCRUD.lua`

Change config reads/writes from `layouts.X.unitConfigs.Y.buffs` to `presets.X.auras.Y.buffs`.

- [ ] **Step 1: Update config path in IndicatorCRUD**

Find the config path construction and update it. The current path is likely:
```lua
'layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.buffs.indicators'
```

Change to:
```lua
'presets.' .. presetName .. '.auras.' .. unitType .. '.buffs.indicators'
```

Where `presetName` comes from `F.Settings.GetEditingPreset()`.

- [ ] **Step 2: Mark preset as customized on writes**

After any config write in the CRUD operations (create, update, delete indicator), call:
```lua
F.PresetManager.MarkCustomized(presetName)
```

- [ ] **Step 3: Commit**

```bash
git add Settings/Builders/IndicatorCRUD.lua
git commit -m "feat: update IndicatorCRUD config paths to preset.auras"
```

---

### Task 14: Update Aura Panel Registration with Unit Type Dropdown

**Files:**
- Modify: `Settings/Panels/Buffs.lua` (reference implementation)
- Then apply pattern to all other aura panels

Each aura panel needs a unit type dropdown at the top to select which unit type's aura config to edit.

- [ ] **Step 1: Add unit type dropdown to Buffs panel**

```lua
-- Unit type dropdown at top of panel
local function getUnitTypeItems()
	local presetName = F.Settings.GetEditingPreset()
	local info = C.PresetInfo[presetName]
	local items = {
		{ text = 'Player',           value = 'player' },
		{ text = 'Target',           value = 'target' },
		{ text = 'Target of Target', value = 'targettarget' },
		{ text = 'Focus',            value = 'focus' },
		{ text = 'Pet',              value = 'pet' },
		{ text = 'Boss',             value = 'boss' },
	}
	-- Add group frame type if applicable
	if(info and info.groupKey) then
		table.insert(items, { text = info.groupLabel, value = info.groupKey })
	end
	return items
end

-- Default unit type: group frames for Party/Raid/Arena, Player for Solo
local function getDefaultUnitType()
	local info = C.PresetInfo[F.Settings.GetEditingPreset()]
	return (info and info.groupKey) or 'player'
end
```

- [ ] **Step 2: Wire dropdown to IndicatorCRUD's unitType parameter**

When the dropdown selection changes, call `F.Settings.SetEditingUnitType(value)` (reuses the existing function in `Settings/Framework.lua`), then invalidate and rebuild the panel. The IndicatorCRUD builder already reads from `F.Settings.GetEditingUnitType()` to construct its config path — so changing the editing unit type and rebuilding the panel is sufficient to show the correct data.

```lua
local unitTypeDD = Widgets.CreateDropdown(content, 200)
unitTypeDD:SetLabel('Configure for:')
unitTypeDD:SetItems(getUnitTypeItems())
unitTypeDD:SetValue(getDefaultUnitType())
unitTypeDD:SetOnSelect(function(value)
	F.Settings.SetEditingUnitType(value)
	-- Trigger panel rebuild
	Settings._panelFrames['buffs'] = nil
	Settings.SetActivePanel('buffs')
end)
```

- [ ] **Step 3: Add "Copy to..." button**

```lua
local copyBtn = Widgets.CreateButton(content, 'Copy to...', 'default', 100, 24)
copyBtn:SetOnClick(function()
	ShowCopyToDialog(F.Settings.GetEditingUnitType(), 'buffs')
end)
```

The `ShowCopyToDialog` shows checkboxes (using `Widgets.CreateCheckButton`) for each unit type and copies the current unit type's aura config to selected targets. The copy overwrites the target's config entirely for that aura type (no merge). The dialog uses a similar pattern to `Widgets.ShowConfirmDialog` but with checkbox content.

- [ ] **Step 4: Apply same pattern to all other aura panels**

Debuffs, RaidDebuffs, Externals, Defensives, MissingBuffs, TargetedSpells, Dispels, PrivateAuras, LossOfControl, CrowdControl all need the same unit type dropdown and copy-to button. The `configKey` parameter changes per panel (e.g., `'debuffs'`, `'raidDebuffs'`).

- [ ] **Step 5: Commit**

```bash
git add Settings/Panels/
git commit -m "feat: add unit type dropdown and copy-to to all aura panels"
```

---

## Phase 6: Frame Presets Panel

### Task 15: Create Frame Presets Panel

**Files:**
- Create: `Settings/Panels/FramePresets.lua`

The main preset management panel with preset list, actions, auto-switch, and spec overrides.

- [ ] **Step 1: Register panel and create scroll frame**

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings.RegisterPanel({
	id = 'framePresets',
	label = 'Frame Presets',
	section = 'FRAME_PRESETS',
	order = 10,
	create = function(parent)
		-- Build panel
	end,
})
```

- [ ] **Step 2: Build preset list with rows**

For each of the 7 presets, create a row showing:
- Preset name
- Status tag ("base" or "uses: Raid" / "customized")
- [Select] button that calls `F.Settings.SetEditingPreset(presetName)`
- Accent highlight on the currently editing preset row
- Row hover highlight with child button propagation (same pattern as indicator list)

```lua
local function buildPresetRow(parent, presetName, width, yOffset)
	local ROW_H = 28
	local info = C.PresetInfo[presetName]

	local row = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	row:SetSize(width, ROW_H)
	Widgets.SetPoint(row, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	Widgets.ApplyBackdrop(row, C.Colors.card)

	-- Name label
	local nameLabel = row:CreateFontString(nil, 'OVERLAY')
	nameLabel:SetFont(C.Font.file, C.Font.sizeNormal, '')
	nameLabel:SetTextColor(unpack(C.Colors.textActive))
	nameLabel:SetText(presetName)
	Widgets.SetPoint(nameLabel, 'LEFT', row, 'LEFT', 8, 0)

	-- Status tag
	local tag = row:CreateFontString(nil, 'OVERLAY')
	tag:SetFont(C.Font.file, C.Font.sizeSmall, '')
	if(info.isBase) then
		tag:SetText('base')
		tag:SetTextColor(unpack(C.Colors.textSecondary))
	else
		local preset = F.Config:Get('presets.' .. presetName)
		if(preset and preset.customized) then
			tag:SetText('customized')
			tag:SetTextColor(unpack(C.Colors.accent))
		else
			tag:SetText('uses: ' .. (info.fallback or ''))
			tag:SetTextColor(unpack(C.Colors.textSecondary))
		end
	end
	Widgets.SetPoint(tag, 'LEFT', nameLabel, 'RIGHT', 8, 0)

	-- Select button
	local selectBtn = Widgets.CreateButton(row, 'Select', 'default', 60, 22)
	Widgets.SetPoint(selectBtn, 'RIGHT', row, 'RIGHT', -4, 0)
	selectBtn:SetOnClick(function()
		F.Settings.SetEditingPreset(presetName)
	end)

	-- Highlight + hover propagation
	row:SetScript('OnEnter', function(self)
		Widgets.SetBackdropHighlight(self, true)
	end)
	row:SetScript('OnLeave', function(self)
		if(self:IsMouseOver()) then return end
		Widgets.SetBackdropHighlight(self, false)
	end)
	selectBtn:HookScript('OnEnter', function() Widgets.SetBackdropHighlight(row, true) end)
	selectBtn:HookScript('OnLeave', function()
		if(row:IsMouseOver()) then return end
		Widgets.SetBackdropHighlight(row, false)
	end)

	return row, yOffset - ROW_H - C.Spacing.tight
end
```

- [ ] **Step 3: Add Copy Settings From... action**

Below the preset list, add a dropdown to pick a source preset and a Copy button:

```lua
-- Copy Settings From...
local copyDropdown = Widgets.CreateDropdown(content, 200)
copyDropdown:SetLabel('Copy Settings From...')
local copyItems = {}
for _, name in next, C.PresetOrder do
	table.insert(copyItems, { text = name, value = name })
end
copyDropdown:SetItems(copyItems)

local copyBtn = Widgets.CreateButton(content, 'Copy', 'default', 80, 24)
copyBtn:SetOnClick(function()
	local source = copyDropdown:GetValue()
	local target = F.Settings.GetEditingPreset()
	if(not source or source == target) then return end
	Widgets.ShowConfirmDialog(
		'Copy Settings',
		'Copy all settings from ' .. source .. ' to ' .. target .. '? This will overwrite current settings.',
		function()
			F.PresetManager.CopySettings(source, target)
		end
	)
end)
```

- [ ] **Step 4: Add Reset to Default action (derived presets only)**

```lua
local resetBtn = Widgets.CreateButton(content, 'Reset to Default', 'red', 140, 24)
resetBtn:SetOnClick(function()
	local presetName = F.Settings.GetEditingPreset()
	Widgets.ShowConfirmDialog(
		'Reset to Default',
		'Reset ' .. presetName .. ' to its default settings?',
		function()
			F.PresetManager.ResetToDefault(presetName)
		end
	)
end)
-- Only show for derived presets
local function updateResetVisibility()
	local info = C.PresetInfo[F.Settings.GetEditingPreset()]
	if(info and not info.isBase) then
		resetBtn:Show()
	else
		resetBtn:Hide()
	end
end
```

- [ ] **Step 5: Add Auto-Switch section**

```lua
-- Auto-Switch: content type → preset dropdown
local contentTypes = {
	{ key = 'solo',         label = 'Solo Content' },
	{ key = 'party',        label = 'Party Content' },
	{ key = 'raid',         label = 'Raid Content' },
	{ key = 'mythicRaid',   label = 'Mythic Raid Content' },
	{ key = 'worldRaid',    label = 'World Raid Content' },
	{ key = 'battleground', label = 'Battleground Content' },
	{ key = 'arena',        label = 'Arena Content' },
}

for _, ct in next, contentTypes do
	local dd = Widgets.CreateDropdown(content, 200)
	dd:SetLabel(ct.label)
	dd:SetItems(copyItems)  -- reuse preset name items
	dd:SetValue(F.Config:GetChar('autoSwitch.' .. ct.key) or ct.key)
	dd:SetOnSelect(function(value)
		F.Config:SetChar('autoSwitch.' .. ct.key, value)
	end)
end
```

- [ ] **Step 6: Add Spec Overrides section**

Collapsible per-spec sections. Each spec expands to show content type → preset dropdown with "Use default" option.

```lua
-- Get specs for current class
local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
for i = 1, numSpecs do
	local specID, specName = GetSpecializationInfo and GetSpecializationInfo(i)
	if(specID and specName) then
		-- Create collapsible section header for this spec
		-- Inside: content type dropdowns with "Use default" as first option
		-- "Use default" = nil (remove key from specOverrides)
		-- Store: FramedCharDB.specOverrides[specID][contentType] = presetName
		-- Use specID (e.g. 105 for Resto Druid), NOT spec index (1-4)
	end
end
```

- [ ] **Step 7: Commit**

```bash
git add Settings/Panels/FramePresets.lua
git commit -m "feat: add Frame Presets management panel with list, copy, auto-switch, spec overrides"
```

---

## Phase 7: Group Frame Consolidation

### Task 16: Consolidate Group Frame Panels into Single Dynamic Panel

**Files:**
- Modify: `Settings/Panels/PartyFrames.lua` → becomes the single group frame panel
- Remove: `Settings/Panels/RaidFrames.lua`, `Settings/Panels/ArenaFrames.lua`, `Settings/Panels/Battlegrounds.lua`, `Settings/Panels/WorldRaids.lua`

- [ ] **Step 1: Rewrite PartyFrames.lua as dynamic group frame panel**

The panel ID becomes `'groupFrames'`. Its label is determined dynamically from the editing preset's `groupLabel`. The `unitType` passed to `FrameSettingsBuilder.Create` comes from the preset's `groupKey`.

```lua
F.Settings.RegisterPanel({
	id = 'groupFrames',
	label = 'Party Frames',  -- default, updated dynamically
	section = 'PRESET_SCOPED',
	order = 70,  -- after Boss
	groupPreview = true,
	create = function(parent)
		local info = C.PresetInfo[F.Settings.GetEditingPreset()]
		local unitType = info and info.groupKey or 'party'
		F.Settings.SetEditingUnitType(unitType)
		return F.FrameSettingsBuilder.Create(parent, unitType)
	end,
})
```

- [ ] **Step 2: Update sidebar to use dynamic label**

The sidebar button for `'groupFrames'` reads its label from `getGroupFrameLabel()` (implemented in Task 10). It hides when the editing preset is Solo.

- [ ] **Step 3: Remove old group frame panel files**

Delete `RaidFrames.lua`, `ArenaFrames.lua`, `Battlegrounds.lua`, `WorldRaids.lua`.

- [ ] **Step 4: Commit**

```bash
git add Settings/Panels/PartyFrames.lua
git rm Settings/Panels/RaidFrames.lua Settings/Panels/ArenaFrames.lua Settings/Panels/Battlegrounds.lua Settings/Panels/WorldRaids.lua
git commit -m "feat: consolidate group frame panels into single dynamic panel"
```

---

## Phase 8: Edit Mode

### Task 17: Update Edit Mode for Preset Positions

**Files:**
- Modify: `EditMode/EditMode.lua`

Positions save to `FramedDB.presets[editingPreset].positions` instead of `FramedCharDB.editModePositions`.

- [ ] **Step 1: Update PersistPositions to save to preset**

```lua
-- OLD:
local layoutName = F.AutoSwitch.GetCurrentLayout() or 'Default'
F.Config:SetChar('editModePositions.' .. layoutName .. '.' .. def.key, posData)

-- NEW:
local presetName = F.Settings.GetEditingPreset()
F.Config:Set('presets.' .. presetName .. '.positions.' .. def.key, posData)
```

- [ ] **Step 2: Update RestorePositions to read from preset**

```lua
-- Read from editing preset's positions
local presetName = F.Settings.GetEditingPreset()
local positions = F.Config:Get('presets.' .. presetName .. '.positions') or {}
```

- [ ] **Step 3: Update Edit Mode label**

When entering edit mode, show "Edit Mode: X Frame Preset":

```lua
-- In the edit mode top bar label:
local presetName = F.Settings.GetEditingPreset()
label:SetText('Edit Mode: ' .. presetName .. ' Frame Preset')
```

- [ ] **Step 4: Commit**

```bash
git add EditMode/EditMode.lua
git commit -m "feat: update Edit Mode to save/load positions from editing preset"
```

---

## Phase 9: Wiring & Cleanup

### Task 18: Update Init.lua References

**Files:**
- Modify: `Init.lua`

- [ ] **Step 1: Update PLAYER_LOGIN handler**

```lua
-- OLD:
F.LayoutDefaults.EnsureDefaults()
-- NEW:
F.PresetDefaults.EnsureDefaults()
```

- [ ] **Step 2: Commit**

```bash
git add Init.lua
git commit -m "feat: update Init.lua to use PresetDefaults"
```

---

### Task 19: Update Framed.toc — File References

**Files:**
- Modify: `Framed.toc`

- [ ] **Step 1: Replace Layouts section with Presets section**

```toc
# Presets
Presets/Defaults.lua
Presets/ContentDetection.lua
Presets/AutoSwitch.lua
Presets/Manager.lua
```

- [ ] **Step 2: Update Settings/Panels section**

Remove deleted panel files (Layouts.lua, RaidFrames.lua, ArenaFrames.lua, Battlegrounds.lua, WorldRaids.lua). Add FramePresets.lua.

```toc
Settings/Panels/FramePresets.lua
```

- [ ] **Step 3: Commit**

```bash
git add Framed.toc
git commit -m "feat: update TOC for preset system file structure"
```

---

### Task 20: Delete Old Layout Files

**Files:**
- Remove: `Layouts/Defaults.lua`, `Layouts/ContentDetection.lua`, `Layouts/AutoSwitch.lua`, `Layouts/Manager.lua`
- Remove: `Settings/Panels/Layouts.lua`

- [ ] **Step 1: Remove old files**

```bash
git rm Layouts/Defaults.lua Layouts/ContentDetection.lua Layouts/AutoSwitch.lua Layouts/Manager.lua
git rm Settings/Panels/Layouts.lua
```

- [ ] **Step 2: Commit**

```bash
git commit -m "chore: remove old Layouts/ files and Layouts panel, replaced by Presets/"
```

---

### Task 21: Sync to WoW Addon Folder and Verify

**Files:**
- No code changes — runtime verification

- [ ] **Step 1: Sync addon to WoW folder**

Copy the updated addon to `/Applications/World of Warcraft/_retail_/Interface/AddOns/Framed/`.

- [ ] **Step 2: /reload in-game and verify**

Test checklist:
1. Addon loads without errors
2. `/framed` opens settings with new sidebar structure
3. GLOBAL section shows Appearance, Click Casting, Profiles
4. FRAME PRESETS section shows Frame Presets panel
5. Frame Presets panel lists all 7 presets with correct tags
6. Selecting a preset updates "Editing: X Frame Preset" label
7. PRESET_SCOPED section shows FRAMES and AURAS sub-headings
8. Group frame label changes per preset (hidden for Solo)
9. Frame settings panels read/write to correct preset
10. Aura panels show unit type dropdown
11. Auto-switch correctly detects content and activates preset
12. Edit Mode shows "Edit Mode: X Frame Preset" and saves positions to preset
13. Derived presets fall back to Raid when not customized
14. Copy Settings and Reset to Default work correctly

- [ ] **Step 3: Fix any issues found during verification**

- [ ] **Step 4: Final commit with any fixes**

```bash
git add -A
git commit -m "fix: address issues found during in-game preset system verification"
```
