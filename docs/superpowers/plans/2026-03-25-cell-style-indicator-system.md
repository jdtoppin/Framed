# Cell-Style Indicator System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign Framed's aura indicator pages with Cell-style BorderIcon rendering, full CRUD for buffs, shared settings builders, and highlight overlays for dispels.

**Architecture:** New `BorderIcon` indicator renderer composes existing primitives (BackdropTemplate + Icon + CooldownFrame). Shared `BorderIconSettings` builder DRYs up the 4 identical settings panels. `IndicatorCRUD` builder handles buff indicator create/edit/delete UI + healer spell import popup. All aura elements rewritten to use new config schema while maintaining backward compatibility with old format.

**Tech Stack:** Lua (WoW API), oUF framework, LibCustomGlow-1.0, BackdropTemplate

**Spec:** `docs/superpowers/specs/2026-03-25-cell-style-indicator-system-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Elements/Indicators/BorderIcon.lua` | BorderIcon renderer: BackdropTemplate frame + inner icon + cooldown + colored border + stack/duration text |
| `Elements/Auras/Externals.lua` | oUF element: displays external defensive cooldowns on unit frames using BorderIcon pool |
| `Elements/Auras/Defensives.lua` | oUF element: displays personal defensive cooldowns using BorderIcon pool |
| `Data/DefensiveSpells.lua` | Curated spell ID lookup tables for externals and defensives (Blizzard has no "is defensive" API) |
| `Core/DispelCapability.lua` | `F.CanPlayerDispel(dispelType)` helper mapping class/spec to dispellable types |
| `Settings/Builders/BorderIconSettings.lua` | Shared settings UI factory for debuffs/raidDebuffs/externals/defensives panels |
| `Settings/Builders/IndicatorCRUD.lua` | CRUD UI factory for Buffs panel + healer spell import popup |

### Modified Files
| File | Changes |
|------|---------|
| `Core/Constants.lua` | Add `GlowType.SHINE`, `HighlightType` enum, `Colors.dispel` table |
| `Elements/Indicators/Icon.lua` | Add vertical depletion StatusBar mode for ColoredSquare |
| `Elements/Indicators/Icons.lua` | Add grid layout: `numPerLine`, `spacingX`, `spacingY` |
| `Elements/Indicators/Glow.lua` | Add Shine glow type dispatch |
| `Elements/Auras/Buffs.lua` | Rewrite: multi-indicator dispatch from `indicators[]` array |
| `Elements/Auras/Debuffs.lua` | Rewrite: BorderIcon pool with dispel-type coloring |
| `Elements/Auras/RaidDebuffs.lua` | Rewrite: BorderIcon pool |
| `Elements/Auras/TargetedSpells.lua` | Update: BorderIcon + BorderGlow modes, rename displayMode values |
| `Elements/Auras/Dispellable.lua` | Rewrite: always-on BorderIcon + 4 highlight overlay types + Physical/bleed |
| `Settings/Panels/Buffs.lua` | Rewrite: full CRUD via IndicatorCRUD builder |
| `Settings/Panels/Debuffs.lua` | Rewrite: BorderIconSettings builder + onlyDispellableByMe |
| `Settings/Panels/RaidDebuffs.lua` | Rewrite: BorderIconSettings builder |
| `Settings/Panels/TargetedSpells.lua` | Rewrite: Icons/BorderGlow/Both + glow settings |
| `Settings/Panels/Dispels.lua` | Rewrite: highlight type dropdown + icon settings + onlyDispellableByMe |
| `Settings/Panels/Externals.lua` | Rewrite: BorderIconSettings builder, remove spell list |
| `Settings/Panels/Defensives.lua` | Rewrite: BorderIconSettings builder, remove spell list |
| `Layouts/Defaults.lua` | Update base functions with new aura config schema |
| `Units/StyleBuilder.lua` | Wire up new Externals/Defensives elements in Apply() |
| `Settings/Framework.lua` | Add `Settings.GetEditingUnitType()` and `Settings.SetEditingUnitType()` for aura panels |
| `Framed.toc` | Add new files to load order |

---

## Task 1: Constants & Dispel Colors

**Files:**
- Modify: `Core/Constants.lua:118-130`

This task adds the new constants referenced by all subsequent tasks.

- [ ] **Step 1: Add GlowType.SHINE**

In `Core/Constants.lua`, add `SHINE` to the `GlowType` table (after line 121):

```lua
Constants.GlowType = {
	PROC  = 'Proc',
	PIXEL = 'Pixel',
	SOFT  = 'Soft',
	SHINE = 'Shine',
}
```

- [ ] **Step 2: Add HighlightType enum**

After the `GlowType` block, add a new section:

```lua
-- ============================================================
-- Dispel Highlight Types
-- ============================================================
Constants.HighlightType = {
	GRADIENT_FULL  = 'gradient_full',
	GRADIENT_HALF  = 'gradient_half',
	SOLID_CURRENT  = 'solid_current',
	SOLID_ENTIRE   = 'solid_entire',
}
```

- [ ] **Step 3: Add centralized dispel colors**

After the existing `Colors` table (after line 28), add:

```lua
-- Dispel type colors (3-value RGB — alpha applied at call site)
-- Physical/bleed included for healer awareness
Constants.Colors.dispel = {
	Magic    = { 0.2, 0.6, 1   },
	Curse    = { 0.6, 0,   1   },
	Disease  = { 0.6, 0.4, 0   },
	Poison   = { 0,   0.6, 0.1 },
	Physical = { 0.8, 0,   0   },
}
```

- [ ] **Step 4: Verify and commit**

Run: `/reload` in-game — addon should load without errors.

```bash
git add Core/Constants.lua
git commit -m "feat: add GlowType.SHINE, HighlightType enum, and centralized dispel colors"
```

---

## Task 1B: CanPlayerDispel Helper & Settings.GetEditingUnitType

**Files:**
- Create: `Core/DispelCapability.lua`
- Modify: `Settings/Framework.lua`
- Modify: `Framed.toc` (add `Core/DispelCapability.lua` after `Core/SecretValues.lua`)

Two utility functions referenced by later tasks that must exist first.

- [ ] **Step 1: Create CanPlayerDispel helper**

Create `Core/DispelCapability.lua`. Maps WoW class names to dispel types they can remove. Updated at `PLAYER_LOGIN` and `ACTIVE_TALENT_GROUP_CHANGED` by scanning known dispel spell IDs.

```lua
local addonName, Framed = ...
local F = Framed

-- Mapping of dispel spellIDs to what types they remove.
-- Source: Warcraft Wiki dispel mechanics.
local DISPEL_SPELLS = {
	-- Priest
	[527]    = { Magic = true, Disease = true },  -- Purify
	[528]    = { Disease = true },                 -- Cure Disease (Shadow)
	[32375]  = { Magic = true },                   -- Mass Dispel
	-- Paladin
	[4987]   = { Magic = true, Poison = true, Disease = true }, -- Cleanse
	-- Druid
	[2782]   = { Curse = true, Poison = true },    -- Remove Corruption
	[88423]  = { Magic = true, Curse = true, Poison = true },  -- Nature's Cure (Resto)
	-- Shaman
	[51886]  = { Curse = true },                   -- Cleanse Spirit
	[77130]  = { Magic = true, Curse = true },     -- Purify Spirit (Resto)
	-- Monk
	[115450] = { Magic = true, Poison = true, Disease = true }, -- Detox (MW)
	[218164] = { Poison = true, Disease = true },  -- Detox (BM/WW)
	-- Mage
	[475]    = { Curse = true },                   -- Remove Curse
	-- Evoker
	[365585] = { Magic = true, Poison = true },    -- Expunge (Pres)
	[374251] = { Poison = true },                  -- Cauterizing Flame
}

local canDispel = {}

local function RefreshDispelCapability()
	wipe(canDispel)
	for spellId, types in next, DISPEL_SPELLS do
		if(IsSpellKnown(spellId)) then
			for dispelType in next, types do
				canDispel[dispelType] = true
			end
		end
	end
end

--- Check if the player's current class/spec can dispel a given type.
--- @param dispelType string  'Magic', 'Curse', 'Disease', 'Poison', 'Physical'
--- @return boolean
function F.CanPlayerDispel(dispelType)
	if(not dispelType or dispelType == '' or dispelType == 'Physical') then
		return false  -- Physical/bleeds cannot be dispelled
	end
	return canDispel[dispelType] or false
end

-- Refresh on login and talent changes
local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('ACTIVE_TALENT_GROUP_CHANGED')
frame:SetScript('OnEvent', RefreshDispelCapability)
```

- [ ] **Step 2: Add GetEditingUnitType to Settings Framework**

In `Settings/Framework.lua`, after the `GetEditingLayout` function (around line 44), add:

```lua
--- Get the unit type whose aura panels are currently being configured.
--- Set by FrameSettingsBuilder or unit frame panel navigation.
--- Falls back to 'party' if nothing is explicitly selected.
--- @return string
function Settings.GetEditingUnitType()
	return Settings._editingUnitType or 'party'
end

--- Set the unit type being edited. Called when switching between
--- unit frame types (e.g., Player → Party → Raid in the sidebar).
--- @param unitType string
function Settings.SetEditingUnitType(unitType)
	Settings._editingUnitType = unitType
end
```

Then in each unit frame panel registration (e.g., `Panels/Player.lua`, `Panels/PartyFrames.lua`), the `create` function should call `F.Settings.SetEditingUnitType(unitType)` before returning. This ensures aura sub-panels know which unit type is active.

- [ ] **Step 3: Add to TOC and commit**

In `Framed.toc`, after `Core/SecretValues.lua`, add:

```
Core/DispelCapability.lua
```

```bash
git add Core/DispelCapability.lua Settings/Framework.lua Framed.toc
git commit -m "feat: add F.CanPlayerDispel helper and Settings.GetEditingUnitType"
```

---

## Task 2: BorderIcon Indicator Renderer

**Files:**
- Create: `Elements/Indicators/BorderIcon.lua`
- Modify: `Framed.toc:78` (insert after `Glow.lua`)

The BorderIcon is the core visual primitive for debuffs, raid debuffs, targeted spells, externals, defensives, and dispels. It must exist before any aura element can use it.

- [ ] **Step 1: Create BorderIcon.lua**

Create `Elements/Indicators/BorderIcon.lua`. Follow the same method-table pattern as `Icon.lua` and `Glow.lua`.

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.BorderIcon = {}

-- ============================================================
-- Duration OnUpdate handler
-- ============================================================

local DURATION_UPDATE_INTERVAL = 0.1

local function DurationOnUpdate(frame, elapsed)
	local bi = frame._biRef
	if(not bi) then return end

	bi._durationElapsed = (bi._durationElapsed or 0) + elapsed
	if(bi._durationElapsed < DURATION_UPDATE_INTERVAL) then return end
	bi._durationElapsed = 0

	local remaining = bi._expirationTime - GetTime()
	if(remaining <= 0) then
		bi.duration:SetText('')
		bi._durationActive = false
		frame:SetScript('OnUpdate', nil)
		return
	end

	bi.duration:SetText(F.FormatDuration(remaining))
end

-- ============================================================
-- BorderIcon methods
-- ============================================================

local BorderIconMethods = {}

--- Set the displayed aura data on this border icon.
--- @param spellId number
--- @param iconTexture number|string|nil Texture ID or path
--- @param duration number
--- @param expirationTime number
--- @param count number Stack count
--- @param dispelType string|nil Dispel/debuff type
function BorderIconMethods:SetAura(spellId, iconTexture, duration, expirationTime, count, dispelType)
	-- Icon texture
	if(iconTexture) then
		self.icon:SetTexture(iconTexture)
	elseif(spellId and F.IsValueNonSecret(spellId)) then
		local tex
		if(C_Spell and C_Spell.GetSpellInfo) then
			local info = C_Spell.GetSpellInfo(spellId)
			if(info) then tex = info.iconID end
		elseif(GetSpellInfo) then
			local _, _, ic = GetSpellInfo(spellId)
			tex = ic
		end
		self.icon:SetTexture(tex)
	end

	-- Border color from dispel type
	if(dispelType and F.IsValueNonSecret(dispelType)) then
		local color = C.Colors.dispel[dispelType]
		if(color) then
			self:SetBorderColor(color[1], color[2], color[3], 1)
		end
	end

	-- Cooldown swipe
	if(self.cooldown) then
		local durationSafe = F.IsValueNonSecret(duration)
		local expirationSafe = F.IsValueNonSecret(expirationTime)
		if(durationSafe and expirationSafe and duration and duration > 0 and expirationTime and expirationTime > 0) then
			local startTime = expirationTime - duration
			self.cooldown:SetCooldown(startTime, duration)
		else
			self.cooldown:Clear()
		end
	end

	-- Stacks
	if(self.stacks) then
		if(count and count > 1) then
			self.stacks:SetText(count)
			self.stacks:Show()
		else
			self.stacks:SetText('')
			self.stacks:Hide()
		end
	end

	-- Duration text
	if(self.duration) then
		local durationSafe = F.IsValueNonSecret(duration)
		local expirationSafe = F.IsValueNonSecret(expirationTime)
		if(not durationSafe or not expirationSafe or duration == 0) then
			self.duration:SetText('')
			self._durationActive = false
			self._frame:SetScript('OnUpdate', nil)
		else
			self._expirationTime = expirationTime
			self._durationActive = true
			self._durationElapsed = 0
			local remaining = expirationTime - GetTime()
			if(remaining > 0) then
				self.duration:SetText(F.FormatDuration(remaining))
				self._frame:SetScript('OnUpdate', DurationOnUpdate)
			else
				self.duration:SetText('')
				self._durationActive = false
				self._frame:SetScript('OnUpdate', nil)
			end
		end
	end

	self._frame:Show()
end

--- Set the border color manually (overrides dispel-type auto-color).
--- @param r number
--- @param g number
--- @param b number
--- @param a? number
function BorderIconMethods:SetBorderColor(r, g, b, a)
	a = a or 1
	self._frame:SetBackdropBorderColor(r, g, b, a)
end

--- Clear and hide this border icon.
function BorderIconMethods:Clear()
	self.icon:SetTexture(nil)
	if(self.cooldown) then
		self.cooldown:Clear()
	end
	if(self.stacks) then
		self.stacks:SetText('')
		self.stacks:Hide()
	end
	if(self.duration) then
		self.duration:SetText('')
	end
	self._durationActive = false
	self._frame:SetScript('OnUpdate', nil)
	self._frame:Hide()
end

function BorderIconMethods:Show()
	self._frame:Show()
end

function BorderIconMethods:Hide()
	self._frame:Hide()
end

function BorderIconMethods:SetPoint(...)
	self._frame:SetPoint(...)
end

function BorderIconMethods:ClearAllPoints()
	self._frame:ClearAllPoints()
end

function BorderIconMethods:GetFrame()
	return self._frame
end

function BorderIconMethods:SetFrameLevel(level)
	self._frame:SetFrameLevel(level)
end

function BorderIconMethods:SetSize(size)
	local borderThickness = self._borderThickness
	Widgets.SetSize(self._frame, size, size)
	self.icon:SetPoint('TOPLEFT', self._frame, 'TOPLEFT', borderThickness, -borderThickness)
	self.icon:SetPoint('BOTTOMRIGHT', self._frame, 'BOTTOMRIGHT', -borderThickness, borderThickness)
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a BorderIcon indicator: BackdropTemplate frame with colored border,
--- inner icon texture, cooldown swipe, and stack/duration text overlays.
--- @param parent Frame
--- @param size number Pixel size (width = height)
--- @param config? table { borderThickness, showCooldown, showStacks, showDuration, borderColor, frameLevel, stackFont, durationFont }
--- @return table borderIcon
function F.Indicators.BorderIcon.Create(parent, size, config)
	config = config or {}
	local borderThickness = config.borderThickness or 2
	local showCooldown    = config.showCooldown ~= false
	local showStacks      = config.showStacks   ~= false
	local showDuration    = config.showDuration  ~= false
	local frameLevel      = config.frameLevel    or (parent:GetFrameLevel() + 5)

	-- 1. Outer frame with backdrop border
	local frame = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(frame, size, size)
	frame:SetFrameLevel(frameLevel)
	frame:SetBackdrop({
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = borderThickness,
	})
	-- Default border: dark/black
	frame:SetBackdropBorderColor(0, 0, 0, 1)
	frame:Hide()

	-- 2. Inner icon texture (inset by border thickness)
	local icon = frame:CreateTexture(nil, 'ARTWORK')
	icon:SetPoint('TOPLEFT', frame, 'TOPLEFT', borderThickness, -borderThickness)
	icon:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -borderThickness, borderThickness)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- 3. Cooldown frame (covers the icon area)
	local cooldown
	if(showCooldown) then
		cooldown = CreateFrame('Cooldown', nil, frame, 'CooldownFrameTemplate')
		cooldown:SetPoint('TOPLEFT', icon, 'TOPLEFT', 0, 0)
		cooldown:SetPoint('BOTTOMRIGHT', icon, 'BOTTOMRIGHT', 0, 0)
		cooldown:SetDrawBling(false)
		cooldown:SetDrawEdge(false)
		cooldown:SetHideCountdownNumbers(true)
	end

	-- 4. Stack count text (bottom-right, on top of cooldown)
	local stacksText
	if(showStacks) then
		local stackFontSize = (config.stackFont and config.stackFont.size) or C.Font.sizeSmall
		local stackFontColor = (config.stackFont and config.stackFont.color) or C.Colors.textActive
		stacksText = Widgets.CreateFontString(frame, stackFontSize, stackFontColor)
		stacksText:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -1, 1)
		stacksText:Hide()
	end

	-- 5. Duration text (bottom center)
	local durationText
	if(showDuration) then
		local durFontSize = (config.durationFont and config.durationFont.size) or C.Font.sizeSmall
		durationText = Widgets.CreateFontString(frame, durFontSize, C.Colors.textActive)
		durationText:SetPoint('BOTTOM', frame, 'BOTTOM', 0, 1)
	end

	-- Build object
	local bi = {
		_frame           = frame,
		_borderThickness = borderThickness,
		_durationActive  = false,
		_durationElapsed = 0,
		_expirationTime  = 0,

		icon     = icon,
		cooldown = cooldown,
		stacks   = stacksText,
		duration = durationText,
	}

	-- Apply methods
	for k, v in next, BorderIconMethods do
		bi[k] = v
	end

	-- Back-reference for OnUpdate
	frame._biRef = bi

	-- Apply initial border color if provided
	if(config.borderColor) then
		local bc = config.borderColor
		bi:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
	end

	return bi
end
```

- [ ] **Step 2: Add to TOC**

In `Framed.toc`, add after `Elements/Indicators/Glow.lua` (line 78):

```
Elements/Indicators/BorderIcon.lua
```

- [ ] **Step 3: Verify and commit**

Run: `/reload` in-game — addon loads without errors.

```bash
git add Elements/Indicators/BorderIcon.lua Framed.toc
git commit -m "feat: add BorderIcon indicator renderer"
```

---

## Task 3: Vertical Depletion for ColoredSquare in Icon.lua

**Files:**
- Modify: `Elements/Indicators/Icon.lua`

When `displayType == ColoredSquare`, replace the CooldownFrame swipe with a vertical StatusBar that depletes downward over the aura duration.

- [ ] **Step 1: Add vertical depletion StatusBar**

In `Icon.lua`, modify the factory function `F.Indicators.Icon.Create` (around line 224). After the cooldown frame creation block (lines 246-253), add a vertical StatusBar as an alternative:

```lua
	-- 2a. Vertical depletion bar (for ColoredSquare mode)
	local depletionBar
	if(displayType == C.IconDisplay.COLORED_SQUARE) then
		depletionBar = CreateFrame('StatusBar', nil, frame)
		depletionBar:SetAllPoints(frame)
		depletionBar:SetOrientation('VERTICAL')
		depletionBar:SetFillStyle('REVERSE')  -- depletes from top
		depletionBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
		depletionBar:SetMinMaxValues(0, 1)
		depletionBar:SetValue(1)
		depletionBar:Hide()
		-- Don't create the CooldownFrame when in ColoredSquare mode
		cooldown = nil
	end
```

- [ ] **Step 2: Add depletion OnUpdate logic**

Add a new OnUpdate function before `DurationOnUpdate` or modify `IconMethods:SetCooldown` to handle the depletion bar:

```lua
--- Start the vertical depletion animation.
--- @param duration number
--- @param expirationTime number
function IconMethods:SetDepletion(duration, expirationTime)
	if(not self._depletionBar) then return end
	local durationSafe = F.IsValueNonSecret(duration)
	local expirationSafe = F.IsValueNonSecret(expirationTime)

	if(not durationSafe or not expirationSafe or duration == 0) then
		self._depletionBar:SetValue(1)
		self._depletionBar:Hide()
		return
	end

	self._depletionBar:Show()
	self._depletionDuration = duration
	self._depletionExpiration = expirationTime
	self._frame:SetScript('OnUpdate', function(f, elapsed)
		local icon = f._iconRef
		if(not icon or not icon._depletionBar) then return end
		local remaining = icon._depletionExpiration - GetTime()
		if(remaining <= 0) then
			icon._depletionBar:SetValue(0)
			f:SetScript('OnUpdate', nil)
			return
		end
		icon._depletionBar:SetValue(remaining / icon._depletionDuration)
	end)
end
```

- [ ] **Step 3: Update SetSpell to route ColoredSquare through depletion**

In `IconMethods:SetSpell` (line 61), modify the cooldown section:

```lua
	-- Cooldown swipe OR vertical depletion
	if(self._displayType == C.IconDisplay.COLORED_SQUARE and self._depletionBar) then
		self:SetDepletion(duration, expirationTime)
	elseif(self._config.showCooldown and self.cooldown) then
		self:SetCooldown(duration, expirationTime)
	end
```

- [ ] **Step 4: Wire depletionBar into the icon object**

In the factory's icon object table (around line 271), add:

```lua
		_depletionBar       = depletionBar,
		_depletionDuration  = 0,
		_depletionExpiration = 0,
```

- [ ] **Step 5: Update Clear() to reset depletion**

In `IconMethods:Clear()` (line 171), add:

```lua
	if(self._depletionBar) then
		self._depletionBar:SetValue(1)
		self._depletionBar:Hide()
	end
```

- [ ] **Step 6: Verify and commit**

Test: Create a buff indicator with ColoredSquare display type. Cast a spell with a duration on yourself. The colored square should deplete vertically rather than showing a cooldown swipe.

```bash
git add Elements/Indicators/Icon.lua
git commit -m "feat: add vertical depletion animation for ColoredSquare display type"
```

---

## Task 4: Grid Layout for Icons.lua

**Files:**
- Modify: `Elements/Indicators/Icons.lua`

Add `numPerLine`, `spacingX`, `spacingY` support for multi-row icon grids.

- [ ] **Step 1: Update the config parsing in the factory**

In `F.Indicators.Icons.Create` (line 143), extend the `cfg` table:

```lua
	local cfg = {
		maxIcons      = config.maxIcons      or 4,
		iconSize      = config.iconSize      or 14,
		spacing       = config.spacing       or 1,
		spacingX      = config.spacingX      or config.spacing or 1,
		spacingY      = config.spacingY      or config.spacing or 1,
		numPerLine    = config.numPerLine    or 0,  -- 0 = single row/column (no wrapping)
		growDirection = config.growDirection or 'RIGHT',
		displayType   = config.displayType   or C.IconDisplay.SPELL_ICON,
		showCooldown  = config.showCooldown  ~= false,
		showStacks    = config.showStacks    ~= false,
		showDuration  = config.showDuration  ~= false,
	}
```

- [ ] **Step 2: Update container sizing**

Replace the container sizing logic (lines 158-166) to account for grid layout:

```lua
	local totalWidth, totalHeight
	local growDirection = cfg.growDirection
	local numPerLine = cfg.numPerLine
	local maxIcons = cfg.maxIcons

	if(numPerLine > 0 and maxIcons > numPerLine) then
		local numLines = math.ceil(maxIcons / numPerLine)
		if(growDirection == 'RIGHT' or growDirection == 'LEFT') then
			totalWidth  = numPerLine * cfg.iconSize + math.max(0, numPerLine - 1) * cfg.spacingX
			totalHeight = numLines * cfg.iconSize + math.max(0, numLines - 1) * cfg.spacingY
		else -- UP / DOWN
			totalWidth  = numLines * cfg.iconSize + math.max(0, numLines - 1) * cfg.spacingX
			totalHeight = numPerLine * cfg.iconSize + math.max(0, numPerLine - 1) * cfg.spacingY
		end
	else
		if(growDirection == 'RIGHT' or growDirection == 'LEFT') then
			totalWidth  = maxIcons * cfg.iconSize + math.max(0, maxIcons - 1) * cfg.spacingX
			totalHeight = cfg.iconSize
		else
			totalWidth  = cfg.iconSize
			totalHeight = maxIcons * cfg.iconSize + math.max(0, maxIcons - 1) * cfg.spacingY
		end
	end
```

- [ ] **Step 3: Update positioning in SetIcons**

Replace the positioning block in `IconsMethods:SetIcons` (lines 38-50) with grid-aware positioning:

```lua
		-- Position based on grow direction + grid
		local numPerLine = cfg.numPerLine
		local row, col

		if(numPerLine > 0) then
			col = (i - 1) % numPerLine
			row = math.floor((i - 1) / numPerLine)
		else
			col = i - 1
			row = 0
		end

		local offsetX = col * (cfg.iconSize + cfg.spacingX)
		local offsetY = row * (cfg.iconSize + cfg.spacingY)
		local growDirection = cfg.growDirection or 'RIGHT'

		if(growDirection == 'RIGHT') then
			icon:SetPoint('TOPLEFT', container, 'TOPLEFT', offsetX, -offsetY)
		elseif(growDirection == 'LEFT') then
			icon:SetPoint('TOPRIGHT', container, 'TOPRIGHT', -offsetX, -offsetY)
		elseif(growDirection == 'DOWN') then
			icon:SetPoint('TOPLEFT', container, 'TOPLEFT', offsetY, -offsetX)
		elseif(growDirection == 'UP') then
			icon:SetPoint('BOTTOMLEFT', container, 'BOTTOMLEFT', offsetY, offsetX)
		end
```

- [ ] **Step 4: Verify and commit**

Test: Existing Icons grids (buffs/debuffs on player/target frames) still work with default single-row layout.

```bash
git add Elements/Indicators/Icons.lua
git commit -m "feat: add grid layout support to Icons indicator (numPerLine, spacingX, spacingY)"
```

---

## Task 5: Shine Glow Type

**Files:**
- Modify: `Elements/Indicators/Glow.lua`

- [ ] **Step 1: Add Shine to glow dispatch**

In `Glow.lua`, update `LCG_Start` (line 24) and `LCG_Stop` (line 38):

```lua
local function LCG_Start(parent, glowType, color, glowConfig)
	if(glowType == C.GlowType.PIXEL) then
		local cfg = glowConfig or {}
		LCG.PixelGlow_Start(parent, color, cfg.lines, cfg.frequency, cfg.length, cfg.thickness, nil, nil)
	elseif(glowType == C.GlowType.SOFT) then
		LCG.AutoCastGlow_Start(parent, color)
	elseif(glowType == C.GlowType.SHINE) then
		-- Shine uses ButtonGlow with higher frequency for a pulsing "shine" effect
		LCG.ButtonGlow_Start(parent, color, 0.25, 0.12)
	else
		-- Default: Proc / ButtonGlow
		LCG.ButtonGlow_Start(parent, color)
	end
end

local function LCG_Stop(parent, glowType)
	if(glowType == C.GlowType.PIXEL) then
		LCG.PixelGlow_Stop(parent)
	elseif(glowType == C.GlowType.SOFT) then
		LCG.AutoCastGlow_Stop(parent)
	elseif(glowType == C.GlowType.SHINE) then
		LCG.ButtonGlow_Stop(parent)
	else
		LCG.ButtonGlow_Stop(parent)
	end
end
```

- [ ] **Step 2: Update Start method to pass glowConfig**

In `GlowMethods:Start` (line 57), accept and pass through `glowConfig`:

```lua
function GlowMethods:Start(color, glowType, glowConfig)
	color    = color    or self._color
	glowType = glowType or self._glowType

	if(self._active) then
		self:_StopCurrent()
	end

	self._color      = color
	self._glowType   = glowType
	self._glowConfig = glowConfig

	if(LCG) then
		LCG_Start(self._parent, glowType, color, glowConfig)
	else
		if(self._fallbackBorder) then
			self._fallbackBorder:SetColor(
				color[1] or 0,
				color[2] or 0.8,
				color[3] or 1,
				color[4] or 1)
		end
	end

	self._active = true
end
```

- [ ] **Step 3: Verify and commit**

```bash
git add Elements/Indicators/Glow.lua
git commit -m "feat: add Shine glow type and glowConfig pass-through for Pixel parameters"
```

---

## Task 6: Update Layout Defaults

**Files:**
- Modify: `Layouts/Defaults.lua`

Update the unit config base functions (`partyBase()`, `raidBase()`, `arenaEnemyBase()`, etc.) to use the new aura config schema. **Migration note:** Old saved variables store aura config at `layouts.<name>.auras.<category>`. The new schema stores at `layouts.<name>.unitConfigs.<unitType>.<category>`. The `GetConfig` merge in `StyleBuilder` already falls back to preset defaults for missing keys, so existing users get clean defaults. If a migration from old paths is needed later, it can be added to `LayoutDefaults.EnsureDefaults()` — but for now, fresh defaults are sufficient since this is an alpha addon.

- [ ] **Step 1: Update partyBase()**

In `Layouts/Defaults.lua`, replace the existing aura-related keys in `partyBase()` (lines 129-134):

```lua
		-- Replace old flat keys:
		--   raidDebuffs  = { iconSize = 18, ... }
		--   dispellable  = { glowType = ... }
		--   buffs        = { maxIcons = 4, ... }
		--   debuffs      = { maxIcons = 3, ... }
		--   missingBuffs = { iconSize = 12 }
		--   privateAuras = { iconSize = 16 }
		-- With new schema:
		buffs = {
			enabled    = true,
			indicators = {},
		},
		debuffs = {
			enabled              = true,
			iconSize             = 16,
			bigIconSize          = 22,
			maxDisplayed         = 3,
			showDuration         = true,
			showAnimation        = true,
			orientation          = 'RIGHT',
			anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
			frameLevel           = 5,
			onlyDispellableByMe  = false,
			stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
			                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                         color = { 1, 1, 1, 1 } },
			durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		raidDebuffs = {
			enabled        = true,
			iconSize       = 16,
			bigIconSize    = 20,
			maxDisplayed   = 1,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel     = 6,
			stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
			                   anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                   color = { 1, 1, 1, 1 } },
			durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		targetedSpells = {
			enabled       = true,
			displayMode   = 'Both',
			iconSize      = 16,
			borderColor   = { 1, 0, 0, 1 },
			maxDisplayed  = 1,
			anchor        = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel    = 8,
			glow          = {
				type      = 'Pixel',
				color     = { 1, 0, 0, 1 },
				lines     = 8,
				frequency = 0.25,
				length    = 4,
				thickness = 2,
			},
		},
		dispellable = {
			enabled              = true,
			onlyDispellableByMe  = false,
			highlightType        = 'gradient_half',
			iconSize             = 16,
			anchor               = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel           = 7,
		},
		externals = {
			enabled        = true,
			iconSize       = 16,
			maxDisplayed   = 2,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'TOPRIGHT', nil, 'TOPRIGHT', -2, -2 },
			frameLevel     = 5,
			stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
			                   anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                   color = { 1, 1, 1, 1 } },
			durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		defensives = {
			enabled        = true,
			iconSize       = 16,
			maxDisplayed   = 2,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 },
			frameLevel     = 5,
			stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
			                   anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                   color = { 1, 1, 1, 1 } },
			durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		missingBuffs = { iconSize = 12 },
		privateAuras = { iconSize = 16 },
```

- [ ] **Step 2: Apply same pattern to raidBase()**

Update `raidBase()` similarly — replace the old `raidDebuffs` and `dispellable` keys and add the new aura config keys. Raid gets smaller icons and fewer max displayed.

- [ ] **Step 3: Apply to arenaEnemyBase()**

Update `arenaEnemyBase()` — replace old `debuffs` and `dispellable` keys.

- [ ] **Step 4: Update playerBase() and targetBase()**

These have simpler aura configs (just `buffs` and `debuffs`). Replace with the new schema format. Player/target don't need raidDebuffs, dispellable, externals, or defensives.

- [ ] **Step 5: Update layout-specific overrides**

Go through each layout's inline overrides (e.g., `mythicRaid`'s raid table, `battleground`'s raid table, `arena`'s party table) and update any references to old aura keys.

- [ ] **Step 6: Update StyleBuilder.Apply() and Presets**

In `Units/StyleBuilder.lua`, update the `Apply()` function and `Presets` to reference the new config structure. The aura element Setup calls need to pass the correct config shape. Also wire up `Externals` and `Defensives` elements:

```lua
	-- Externals (optional)
	if(config.externals and F.Elements.Externals) then
		F.Elements.Externals.Setup(self, config.externals)
	end

	-- Defensives (optional)
	if(config.defensives and F.Elements.Defensives) then
		F.Elements.Defensives.Setup(self, config.defensives)
	end
```

- [ ] **Step 7: Verify and commit**

Delete `FramedDB` saved variables to get fresh defaults. `/reload` — verify all unit frames spawn correctly.

```bash
git add Layouts/Defaults.lua Units/StyleBuilder.lua
git commit -m "feat: update layout defaults and StyleBuilder with new aura config schema"
```

---

## Task 7: Rewrite Debuffs Element

**Files:**
- Modify: `Elements/Auras/Debuffs.lua`

Rewrite to use BorderIcon pool instead of Icons grid. Colors borders by dispel type.

- [ ] **Step 1: Rewrite Debuffs.lua**

Replace the entire contents of `Elements/Auras/Debuffs.lua`:

```lua
local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Debuffs = {}

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedDebuffs
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local cfg = element._config
	local maxDisplayed = cfg.maxDisplayed or 3
	local onlyDispellableByMe = cfg.onlyDispellableByMe

	-- Collect auras
	local auraList = {}
	local i = 1
	while(true) do
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if(not auraData) then break end

		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local dispelName = auraData.dispelName
			local dispelSafe = (not dispelName) or F.IsValueNonSecret(dispelName)

			-- Apply dispellable-by-me filter if enabled
			local passFilter = true
			if(onlyDispellableByMe and dispelSafe) then
				-- Only show auras the player can dispel (or non-dispellable ones like bleeds)
				if(dispelName and dispelName ~= '') then
					-- Check if player's class/spec can dispel this type
					-- Uses a helper that maps class dispel spells to dispel types:
					-- e.g., Priest: Magic+Disease, Paladin: Magic+Poison+Disease, etc.
					passFilter = F.CanPlayerDispel(dispelName)
				end
				-- Physical/bleeds (no dispelName) always pass
			end

			if(passFilter) then
				auraList[#auraList + 1] = {
					spellId        = spellId,
					icon           = auraData.icon,
					duration       = auraData.duration,
					expirationTime = auraData.expirationTime,
					stacks         = auraData.applications or 0,
					dispelType     = dispelSafe and dispelName or nil,
					isBossAura     = auraData.isBossAura,
				}
			end
		end
		i = i + 1
	end

	-- Sort by priority: boss auras first, then by duration
	table.sort(auraList, function(a, b)
		if(a.isBossAura ~= b.isBossAura) then
			return a.isBossAura and true or false
		end
		return (a.duration or 0) > (b.duration or 0)
	end)

	-- Display up to maxDisplayed using BorderIcon pool
	local count = math.min(#auraList, maxDisplayed)
	local pool = element._pool
	local iconSize = cfg.iconSize or 16
	local bigIconSize = cfg.bigIconSize or iconSize
	local orientation = cfg.orientation or 'RIGHT'

	for idx = 1, count do
		local aura = auraList[idx]

		-- Lazily create pool entries
		if(not pool[idx]) then
			pool[idx] = F.Indicators.BorderIcon.Create(self, iconSize, {
				showCooldown = true,
				showStacks   = cfg.showStacks ~= false,
				showDuration = cfg.showDuration ~= false,
				frameLevel   = cfg.frameLevel or 5,
				stackFont    = cfg.stackFont,
				durationFont = cfg.durationFont,
			})
		end

		local bi = pool[idx]

		-- Size: big for boss auras
		local size = aura.isBossAura and bigIconSize or iconSize

		bi:ClearAllPoints()
		bi:SetSize(size)

		-- Position
		local offset = 0
		for j = 1, idx - 1 do
			local prevSize = (auraList[j].isBossAura and bigIconSize or iconSize)
			offset = offset + prevSize + 2
		end

		if(orientation == 'RIGHT') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', offset, 0)
		elseif(orientation == 'LEFT') then
			bi:SetPoint('TOPRIGHT', element._container, 'TOPRIGHT', -offset, 0)
		elseif(orientation == 'DOWN') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', 0, -offset)
		elseif(orientation == 'UP') then
			bi:SetPoint('BOTTOMLEFT', element._container, 'BOTTOMLEFT', 0, offset)
		end

		bi:SetAura(
			aura.spellId,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.stacks,
			aura.dispelType
		)
		bi:Show()
	end

	-- Hide pool entries beyond active count
	for idx = count + 1, #pool do
		pool[idx]:Clear()
	end
end

-- ============================================================
-- ForceUpdate
-- ============================================================

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

-- ============================================================
-- Enable / Disable
-- ============================================================

local function Enable(self, unit)
	local element = self.FramedDebuffs
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedDebuffs
	if(not element) then return end

	for _, bi in next, element._pool do
		bi:Clear()
	end

	self:UnregisterEvent('UNIT_AURA', Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedDebuffs', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

function F.Elements.Debuffs.Setup(self, config)
	config = config or {}

	-- Backward compatibility: old format had maxIcons/iconSize/growDirection
	-- New format has maxDisplayed/iconSize/orientation/anchor/etc.
	if(config.maxIcons and not config.maxDisplayed) then
		config.maxDisplayed = config.maxIcons
		config.orientation  = config.growDirection or 'RIGHT'
	end

	local container = CreateFrame('Frame', nil, self)
	container:SetAllPoints(self)

	local element = {
		_container = container,
		_config    = config,
		_pool      = {},
	}

	local a = config.anchor
	if(a) then
		container:ClearAllPoints()
		Widgets.SetPoint(container, a[1], a[2] or self, a[3], a[4] or 0, a[5] or 0)
	end

	self.FramedDebuffs = element
end
```

- [ ] **Step 2: Verify and commit**

Test: Target a mob, see debuffs with colored borders matching dispel type. `/reload` — no errors.

```bash
git add Elements/Auras/Debuffs.lua
git commit -m "feat: rewrite Debuffs element with BorderIcon pool and dispel-type coloring"
```

---

## Task 8: Rewrite RaidDebuffs Element

**Files:**
- Modify: `Elements/Auras/RaidDebuffs.lua`

Same pattern as Debuffs but with priority filtering via `F.RaidDebuffRegistry`. Uses `bigIconSize` for high-priority debuffs.

- [ ] **Step 1: Rewrite RaidDebuffs.lua**

Follow the same structure as the Debuffs rewrite in Task 7, but:
- Keep the existing priority filtering via `F.RaidDebuffRegistry:GetEffectivePriority(spellId)` and `F.RaidDebuffRegistry:ShouldShow(auraData, filterMode)`
- Use BorderIcon pool instead of single Icon
- Apply `bigIconSize` for debuffs with priority >= `C.DebuffPriority.IMPORTANT`
- Backward compatibility: detect old config format (`{ iconSize = 18, filterMode = ..., minPriority = ... }`) and map to new schema

- [ ] **Step 2: Verify and commit**

Test: In a dungeon/raid, see raid debuffs with BorderIcon rendering and correct priority filtering.

```bash
git add Elements/Auras/RaidDebuffs.lua
git commit -m "feat: rewrite RaidDebuffs element with BorderIcon pool"
```

---

## Task 9: Rewrite Dispellable Element

**Files:**
- Modify: `Elements/Auras/Dispellable.lua`

Major rewrite: always-on BorderIcon + 4 highlight overlay types + Physical/bleed support.

- [ ] **Step 1: Rewrite Dispellable.lua**

Key changes from existing implementation:
- Replace `F.Indicators.Glow` with `F.Indicators.BorderIcon` (always-on icon)
- Add Physical debuff type to priority table: `Physical = 5`
- Add 4 highlight overlay textures (gradient_full, gradient_half, solid_current, solid_entire)
- `onlyDispellableByMe` filter — but Physical/bleeds always pass
- Create overlay textures during Setup, show/hide/color during Update

Structure:
```lua
-- Priority: Magic(1) > Curse(2) > Disease(3) > Poison(4) > Physical(5)
local DISPEL_PRIORITY = {
	Magic    = 1,
	Curse    = 2,
	Disease  = 3,
	Poison   = 4,
	Physical = 5,
}

-- In Update: find highest-priority debuff (dispellable or bleed)
-- Always show BorderIcon with the debuff's spell icon
-- Apply highlight overlay based on config.highlightType
-- Color both by dispel type (from C.Colors.dispel)
```

Highlight overlay implementation:
- Create a texture at Setup time for each mode
- `gradient_full`: Full-height gradient, alpha blend with `SetGradient('VERTICAL', ...)`
- `gradient_half`: Same but only covers top half of health bar
- `solid_current`: Solid texture that follows health bar fill width
- `solid_entire`: Solid texture covering entire unit frame
- Only one is visible at a time based on `config.highlightType`

- [ ] **Step 2: Verify and commit**

Test: Have a party member with a dispellable debuff. Verify: BorderIcon shows with correct spell icon and colored border; highlight overlay matches the configured type.

```bash
git add Elements/Auras/Dispellable.lua
git commit -m "feat: rewrite Dispellable with BorderIcon + highlight overlays + Physical/bleed"
```

---

## Task 10: Update TargetedSpells Element

**Files:**
- Modify: `Elements/Auras/TargetedSpells.lua`

Update display modes, switch icon to BorderIcon, add BorderGlow with Shine support.

- [ ] **Step 1: Update DisplayMode values**

```lua
local DisplayMode = {
	BOTH       = 'Both',
	ICONS      = 'Icons',
	BORDER_GLOW = 'BorderGlow',
}
```

- [ ] **Step 2: Replace Icon with BorderIcon in showSpell**

When `displayMode == 'Icons'` or `'Both'`, use `BorderIcon` instead of `Icon`:
```lua
if(displayMode == DisplayMode.ICONS or displayMode == DisplayMode.BOTH) then
	if(element._borderIcon) then
		element._borderIcon:SetAura(spellId, iconTexture, 0, 0, 0, nil)
		-- Apply configured border color
		local bc = element._borderColor
		if(bc) then
			element._borderIcon:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
		end
		element._borderIcon:Show()
	end
end
```

- [ ] **Step 3: Replace Border with Glow for BorderGlow mode**

When `displayMode == 'BorderGlow'` or `'Both'`, use `Glow` indicator with the configured glow settings:
```lua
if(displayMode == DisplayMode.BORDER_GLOW or displayMode == DisplayMode.BOTH) then
	if(element._glow) then
		element._glow:Start(element._glowColor, element._glowType, element._glowConfig)
	end
end
```

- [ ] **Step 4: Update Setup to create BorderIcon + Glow**

Replace the Setup function to create `BorderIcon` and `Glow` based on config, reading from the new schema (displayMode, iconSize, borderColor, glow settings, frameLevel, anchor).

- [ ] **Step 5: Backward compatibility**

Detect old config format (lowercase `'icon'`/`'border'`/`'both'`) and map to new values.

- [ ] **Step 6: Verify and commit**

Test: Have an enemy cast at you in a dungeon. Verify BorderIcon + glow display.

```bash
git add Elements/Auras/TargetedSpells.lua
git commit -m "feat: update TargetedSpells with BorderIcon + BorderGlow modes"
```

---

## Task 11: Create Externals & Defensives Elements

**Files:**
- Create: `Elements/Auras/Externals.lua`
- Create: `Elements/Auras/Defensives.lua`
- Modify: `Framed.toc` (add after `TargetedSpells.lua`)

These are new oUF elements that display BorderIcon pools for external/personal defensive cooldowns using curated spell ID lookup tables. **Note:** `Data/` is a new directory and `F.Data` is a new namespace — this task creates both.

- [ ] **Step 1: Create a shared curated spell data file**

Since Blizzard does not expose a reliable "is defensive cooldown" classification at the API level, Externals and Defensives use curated spell ID lookup tables (moved from the old settings panels into data). Create a `Data/DefensiveSpells.lua` file with two tables:

```lua
F.Data = F.Data or {}
F.Data.ExternalSpellIDs = {
	[33206]  = true,  -- Pain Suppression
	[47788]  = true,  -- Guardian Spirit
	[102342] = true,  -- Ironbark
	[97462]  = true,  -- Rallying Cry
	[196718] = true,  -- Darkness
	[6940]   = true,  -- Blessing of Sacrifice
	[31821]  = true,  -- Aura Mastery
	[62618]  = true,  -- Power Word: Barrier
}
F.Data.DefensiveSpellIDs = {
	[45438]  = true,  -- Ice Block
	[642]    = true,  -- Divine Shield
	[31224]  = true,  -- Cloak of Shadows
	[48792]  = true,  -- Icebound Fortitude
	[47585]  = true,  -- Dispersion
	[61336]  = true,  -- Survival Instincts
	[871]    = true,  -- Shield Wall
	[12975]  = true,  -- Last Stand
}
```

Add `Data/DefensiveSpells.lua` to `Framed.toc` after the existing Data section.

- [ ] **Step 2: Create Externals.lua**

Follow the same oUF element pattern as Debuffs (Task 7) but:
- Filter: `'HELPFUL'` auras where `F.Data.ExternalSpellIDs[spellId]` is true
- Additionally check `auraData.sourceUnit ~= 'player'` to exclude self-cast versions
- BorderIcon pool with configurable size, max, duration, orientation, anchor, frameLevel
- Register as `oUF:AddElement('FramedExternals', Update, Enable, Disable)`
- Setup assigns to `self.FramedExternals`

- [ ] **Step 3: Create Defensives.lua**

Same pattern but:
- Filter: `'HELPFUL'` auras where `F.Data.DefensiveSpellIDs[spellId]` is true
- Check `auraData.sourceUnit == 'player'` (self-cast only)
- Register as `oUF:AddElement('FramedDefensives', ...)`
- Setup assigns to `self.FramedDefensives`

- [ ] **Step 4: Add to TOC**

In `Framed.toc`, add `Data/DefensiveSpells.lua` after the existing Data section (before Elements). Then after `Elements/Auras/TargetedSpells.lua`, add:

```
Data/DefensiveSpells.lua

Elements/Auras/Externals.lua
Elements/Auras/Defensives.lua
```

- [ ] **Step 5: Verify and commit**

Test: Cast a defensive cooldown on yourself. Verify BorderIcon appears on the frame.

```bash
git add Data/DefensiveSpells.lua Elements/Auras/Externals.lua Elements/Auras/Defensives.lua Framed.toc
git commit -m "feat: add Externals and Defensives oUF elements with BorderIcon pools"
```

---

## Task 12: Rewrite Buffs Element (Multi-Indicator Dispatch)

**Files:**
- Modify: `Elements/Auras/Buffs.lua`

The most complex element rewrite — reads from `indicators[]` array and dispatches to the correct renderer per indicator type.

- [ ] **Step 1: Rewrite Buffs.lua**

Key changes:
- Read `config.indicators[]` array (new format) or fall back to old format
- For each enabled indicator, create the appropriate renderer via dispatch table:

```lua
local RENDERERS = {
	[C.IndicatorType.ICON]      = F.Indicators.Icon,
	[C.IndicatorType.ICONS]     = F.Indicators.Icons,
	[C.IndicatorType.BAR]       = F.Indicators.Bar,
	[C.IndicatorType.FRAME_BAR] = F.Indicators.FrameBar,
	[C.IndicatorType.BORDER]    = F.Indicators.Border,
	[C.IndicatorType.COLOR]     = F.Indicators.Color,
	[C.IndicatorType.OVERLAY]   = F.Indicators.Overlay,
	[C.IndicatorType.GLOW]      = F.Indicators.Glow,
}
```

- Build a spell-to-indicator lookup table for fast matching during Update
- In Update: iterate helpful auras, match against lookup, dispatch to renderer
- Apply `castBy` filter (me/others/anyone) with secret-value safety
- Backward compatibility: if config has `maxIcons` but no `indicators`, create a single Icons renderer matching old behavior

- [ ] **Step 2: Verify and commit**

Test: Without any custom indicators (empty array), buffs should not show. Create an indicator via the settings panel (Task 15) and verify it works.

```bash
git add Elements/Auras/Buffs.lua
git commit -m "feat: rewrite Buffs element with multi-indicator dispatch"
```

---

## Task 13: BorderIcon Settings Builder

**Files:**
- Create: `Settings/Builders/BorderIconSettings.lua`
- Modify: `Framed.toc` (add before settings panels)

Shared UI factory used by Debuffs, Raid Debuffs, Externals, Defensives panels.

- [ ] **Step 1: Create the Builders directory and file**

Create `Settings/Builders/BorderIconSettings.lua`:

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings = F.Settings or {}
F.Settings.Builders = F.Settings.Builders or {}

-- Layout constants
local PANE_TITLE_H = 20
local SLIDER_H     = 26
local CHECK_H      = 22
local DROPDOWN_H   = 22
local LABEL_H      = 16
local WIDGET_W     = 220

-- Helper: get/set config values scoped to the editing layout + unit type + config key
local function makeConfigHelpers(unitType, configKey)
	local function get(key)
		local layoutName = F.Settings.GetEditingLayout()
		return F.Config and F.Config:Get('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. configKey .. '.' .. key)
	end
	local function set(key, value)
		local layoutName = F.Settings.GetEditingLayout()
		if(F.Config) then
			F.Config:Set('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. configKey .. '.' .. key, value)
		end
		if(F.EventBus) then
			F.EventBus:Fire('CONFIG_CHANGED', 'layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. configKey)
		end
	end
	return get, set
end

--- Create the shared BorderIcon settings UI.
--- @param parent Frame  The content frame to build into
--- @param width number  Available width
--- @param opts table  { unitType, configKey, showDispellableByMe?, showBigIconSize? }
--- @return number yOffset  The final yOffset after all widgets
function F.Settings.Builders.BorderIconSettings(parent, width, yOffset, opts)
	local get, set = makeConfigHelpers(opts.unitType, opts.configKey)

	-- ── Only show dispellable by me ─────────────────────────
	if(opts.showDispellableByMe) then
		local dispCheck = Widgets.CreateCheckButton(parent, 'Only show dispellable by me', function(checked)
			set('onlyDispellableByMe', checked)
		end)
		dispCheck:SetChecked(get('onlyDispellableByMe') == true)
		dispCheck:ClearAllPoints()
		Widgets.SetPoint(dispCheck, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - CHECK_H - C.Spacing.normal
	end

	-- ── Display section ─────────────────────────────────────
	local displayPane = Widgets.CreateTitledPane(parent, 'Display', width)
	displayPane:ClearAllPoints()
	Widgets.SetPoint(displayPane, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

	-- Icon Size
	local sizeSlider = Widgets.CreateSlider(parent, 'Icon Size', WIDGET_W, 8, 48, 1)
	sizeSlider:SetValue(get('iconSize') or 16)
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	sizeSlider:ClearAllPoints()
	Widgets.SetPoint(sizeSlider, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - SLIDER_H - C.Spacing.normal

	-- Big Icon Size (debuffs/raidDebuffs only)
	if(opts.showBigIconSize) then
		local bigSlider = Widgets.CreateSlider(parent, 'Big Icon Size', WIDGET_W, 8, 64, 1)
		bigSlider:SetValue(get('bigIconSize') or 22)
		bigSlider:SetAfterValueChanged(function(v) set('bigIconSize', v) end)
		bigSlider:ClearAllPoints()
		Widgets.SetPoint(bigSlider, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - SLIDER_H - C.Spacing.normal
	end

	-- Max Displayed
	local maxSlider = Widgets.CreateSlider(parent, 'Max Displayed', WIDGET_W, 1, 20, 1)
	maxSlider:SetValue(get('maxDisplayed') or 3)
	maxSlider:SetAfterValueChanged(function(v) set('maxDisplayed', v) end)
	maxSlider:ClearAllPoints()
	Widgets.SetPoint(maxSlider, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - SLIDER_H - C.Spacing.normal

	-- Show Duration
	local durCheck = Widgets.CreateCheckButton(parent, 'Show Duration', function(checked) set('showDuration', checked) end)
	durCheck:SetChecked(get('showDuration') ~= false)
	durCheck:ClearAllPoints()
	Widgets.SetPoint(durCheck, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - CHECK_H - C.Spacing.normal

	-- Show Animation (fade out)
	local animCheck = Widgets.CreateCheckButton(parent, 'Show Animation', function(checked) set('showAnimation', checked) end)
	animCheck:SetChecked(get('showAnimation') ~= false)
	animCheck:ClearAllPoints()
	Widgets.SetPoint(animCheck, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - CHECK_H - C.Spacing.normal

	-- Orientation
	local oriDD = Widgets.CreateDropdown(parent, WIDGET_W)
	oriDD:SetItems({
		{ text = 'Right', value = 'RIGHT' },
		{ text = 'Left',  value = 'LEFT' },
		{ text = 'Up',    value = 'UP' },
		{ text = 'Down',  value = 'DOWN' },
	})
	oriDD:SetValue(get('orientation') or 'RIGHT')
	oriDD:SetOnSelect(function(v) set('orientation', v) end)
	oriDD:ClearAllPoints()
	Widgets.SetPoint(oriDD, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - DROPDOWN_H - C.Spacing.normal

	-- Frame Level
	local lvlSlider = Widgets.CreateSlider(parent, 'Frame Level', WIDGET_W, 1, 20, 1)
	lvlSlider:SetValue(get('frameLevel') or 5)
	lvlSlider:SetAfterValueChanged(function(v) set('frameLevel', v) end)
	lvlSlider:ClearAllPoints()
	Widgets.SetPoint(lvlSlider, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - SLIDER_H - C.Spacing.normal

	-- ── Position section ────────────────────────────────────
	local posPane = Widgets.CreateTitledPane(parent, 'Position', width)
	posPane:ClearAllPoints()
	Widgets.SetPoint(posPane, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

	-- Anchor picker (if available)
	if(Widgets.CreateAnchorPicker) then
		local anchor = get('anchor') or { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 }
		local picker = Widgets.CreateAnchorPicker(parent, width)
		picker:SetAnchor(anchor[1], anchor[4] or 0, anchor[5] or 0)
		picker:ClearAllPoints()
		Widgets.SetPoint(picker, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		picker:SetOnChanged(function(point, x, y)
			set('anchor', { point, nil, point, x, y })
		end)
		yOffset = yOffset - picker:GetHeight() - C.Spacing.normal
	end

	-- ── Stack Font section ──────────────────────────────────
	local stackPane = Widgets.CreateTitledPane(parent, 'Stack Font', width)
	stackPane:ClearAllPoints()
	Widgets.SetPoint(stackPane, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

	local stackSize = Widgets.CreateSlider(parent, 'Size', WIDGET_W, 6, 24, 1)
	stackSize:SetValue(get('stackFont.size') or 10)
	stackSize:SetAfterValueChanged(function(v) set('stackFont.size', v) end)
	stackSize:ClearAllPoints()
	Widgets.SetPoint(stackSize, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - SLIDER_H - C.Spacing.normal

	-- ── Duration Font section ───────────────────────────────
	local durPane = Widgets.CreateTitledPane(parent, 'Duration Font', width)
	durPane:ClearAllPoints()
	Widgets.SetPoint(durPane, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

	local durSize = Widgets.CreateSlider(parent, 'Size', WIDGET_W, 6, 24, 1)
	durSize:SetValue(get('durationFont.size') or 10)
	durSize:SetAfterValueChanged(function(v) set('durationFont.size', v) end)
	durSize:ClearAllPoints()
	Widgets.SetPoint(durSize, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - SLIDER_H - C.Spacing.normal

	return yOffset
end
```

- [ ] **Step 2: Add to TOC**

In `Framed.toc`, add before `Settings/Panels/Appearance.lua`:

```
Settings/Builders/BorderIconSettings.lua
```

- [ ] **Step 3: Verify and commit**

```bash
git add Settings/Builders/BorderIconSettings.lua Framed.toc
git commit -m "feat: add shared BorderIconSettings builder for aura panels"
```

---

## Task 14: Rewrite Debuffs/RaidDebuffs/Externals/Defensives Settings Panels

**Files:**
- Modify: `Settings/Panels/Debuffs.lua`
- Modify: `Settings/Panels/RaidDebuffs.lua`
- Modify: `Settings/Panels/Externals.lua`
- Modify: `Settings/Panels/Defensives.lua`

All four panels now use the shared `BorderIconSettings` builder.

- [ ] **Step 1: Rewrite Debuffs.lua panel**

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings.RegisterPanel({
	id      = 'debuffs',
	label   = 'Debuffs',
	section = 'AURAS',
	order   = 12,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- Description
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('Debuffs displayed on unit frames using border icons colored by dispel type.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- Shared BorderIcon settings
		yOffset = F.Settings.Builders.BorderIconSettings(content, width, yOffset, {
			unitType            = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party',
			configKey           = 'debuffs',
			showDispellableByMe = true,
			showBigIconSize     = true,
		})

		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
```

- [ ] **Step 2: Rewrite RaidDebuffs.lua panel**

Same pattern with `configKey = 'raidDebuffs'`, `showBigIconSize = true`, `showDispellableByMe = false`.

- [ ] **Step 3: Rewrite Externals.lua panel**

Same pattern with `configKey = 'externals'`, no dispellable-by-me, no big icon size. Remove all spell list code.

- [ ] **Step 4: Rewrite Defensives.lua panel**

Same pattern with `configKey = 'defensives'`. Remove all spell list code.

- [ ] **Step 5: Verify and commit**

Test: Open settings, navigate to each panel. Sliders and checkboxes should reflect default values. Changes should persist after `/reload`.

```bash
git add Settings/Panels/Debuffs.lua Settings/Panels/RaidDebuffs.lua Settings/Panels/Externals.lua Settings/Panels/Defensives.lua
git commit -m "feat: rewrite Debuffs/RaidDebuffs/Externals/Defensives panels with shared builder"
```

---

## Task 15: Indicator CRUD Builder + Import Popup

**Files:**
- Create: `Settings/Builders/IndicatorCRUD.lua`
- Modify: `Framed.toc` (add after `BorderIconSettings.lua`)

This is the most complex settings UI — the full CRUD for buff indicators.

- [ ] **Step 1: Create IndicatorCRUD.lua**

This file provides `F.Settings.Builders.IndicatorCRUD(parent, width, yOffset, opts)`.

Key components:
1. **Import Healer Spells button** — opens the popup
2. **Create Indicator section** — type dropdown + name editbox + create button
3. **Indicator list** — scrollable list showing name, type, enabled checkbox, edit/delete buttons
4. **Settings section** — dynamically adapts to selected indicator's type
5. **Import popup** — dialog frame with class-grouped spell checkboxes + select all/deselect all + custom add

The healer spell list (constant table):
```lua
local HEALER_SPELLS = {
	DRUID   = { 774, 155777, 8936, 48438, 33763, 102342, 203651 },
	PALADIN = { 53563, 156910, 200025, 223306, 287280, 6940, 1022 },
	PRIEST  = { 139, 17, 41635, 194384, 33206, 47788, 21562 },
	SHAMAN  = { 61295, 73920, 77472, 974, 198838 },
	MONK    = { 119611, 116849, 124682, 116841, 191840 },
	EVOKER  = { 355941, 376788, 364343, 373861, 360823 },
}
```

Due to the complexity of this file (~400-500 lines), the implementer should:
- Follow the existing panel patterns in `Settings/Panels/Buffs.lua` for widget creation
- Build the import popup as a custom frame: `CreateFrame('Frame', nil, UIParent, 'BackdropTemplate')` with a dimmer overlay, scroll frame for the spell list, and buttons. Do NOT use `Widgets.ShowConfirmDialog` — that is a simple confirm/message singleton, not suitable for complex content. The popup pattern should match how `Widgets/Dialog.lua` builds its singleton but with custom content.
- Use `Widgets.CreateScrollFrame` for the indicator list
- Store/read indicators at `layouts.<name>.unitConfigs.<unitType>.buffs.indicators`

- [ ] **Step 2: Add to TOC**

After `Settings/Builders/BorderIconSettings.lua`:

```
Settings/Builders/IndicatorCRUD.lua
```

- [ ] **Step 3: Verify and commit**

```bash
git add Settings/Builders/IndicatorCRUD.lua Framed.toc
git commit -m "feat: add IndicatorCRUD builder with import popup for buff indicators"
```

---

## Task 16: Rewrite Buffs Settings Panel

**Files:**
- Modify: `Settings/Panels/Buffs.lua`

Replace the current placeholder panel with the full CRUD via `IndicatorCRUD` builder.

- [ ] **Step 1: Rewrite Buffs.lua panel**

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings.RegisterPanel({
	id      = 'buffs',
	label   = 'Buffs',
	section = 'AURAS',
	order   = 11,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- Description
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('Create and configure buff indicators. Each indicator tracks specific spells and renders them using the chosen display type.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- CRUD builder
		yOffset = F.Settings.Builders.IndicatorCRUD(content, width, yOffset, {
			unitType  = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party',
			configKey = 'buffs',
		})

		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
```

- [ ] **Step 2: Verify and commit**

Test: Open Buffs panel, create an indicator, import healer spells, edit settings, delete indicator. Verify persistence across `/reload`.

```bash
git add Settings/Panels/Buffs.lua
git commit -m "feat: rewrite Buffs settings panel with full CRUD and import popup"
```

---

## Task 17: Rewrite TargetedSpells & Dispels Settings Panels

**Files:**
- Modify: `Settings/Panels/TargetedSpells.lua`
- Modify: `Settings/Panels/Dispels.lua`

These panels have unique layouts that don't use the shared builder.

- [ ] **Step 1: Rewrite TargetedSpells.lua panel**

Key UI elements:
- Display Mode dropdown: Icons / Border Glow / Both
- Icon Settings section (shown when Icons or Both): icon size, border color, max displayed, anchor, frame level
- Border Glow Settings section (shown when BorderGlow or Both): glow type (Pixel/Proc/Soft/Shine), color, lines, frequency, length, thickness
- Config path: `layouts.<name>.unitConfigs.<unitType>.targetedSpells.<key>`

Use `Widgets.CreateColorPicker` for border color and glow color.

- [ ] **Step 2: Rewrite Dispels.lua panel**

Key UI elements:
- "Only show dispellable by me" checkbox (at top)
- Highlight Type dropdown: Gradient - Health Bar (Full), Gradient - Health Bar (Half), Solid - Health Bar (Current), Solid - Entire Frame
- Icon section: size slider, anchor picker, frame level slider
- Config path: `layouts.<name>.unitConfigs.<unitType>.dispellable.<key>`

- [ ] **Step 3: Verify and commit**

Test: Open each panel, change settings, `/reload`, verify persistence.

```bash
git add Settings/Panels/TargetedSpells.lua Settings/Panels/Dispels.lua
git commit -m "feat: rewrite TargetedSpells and Dispels settings panels"
```

---

## Task 18: Final Integration & Cleanup

**Files:**
- Modify: `Framed.toc` (verify final load order)
- Modify: `Elements/Indicators/Icon.lua` (replace local DEBUFF_TYPE_COLORS with C.Colors.dispel)
- Modify: `Elements/Auras/Dispellable.lua` (replace local DISPEL_COLORS with C.Colors.dispel)

- [ ] **Step 1: Replace local dispel color tables with centralized constants**

In `Icon.lua` (lines 13-20), replace `DEBUFF_TYPE_COLORS` references with `C.Colors.dispel`. Keep the `Physical` and `none` fallbacks:

```lua
-- Wrap C.Colors.dispel with a 'none' fallback without mutating the shared constant table
local DEBUFF_TYPE_COLORS = setmetatable({ none = C.Colors.dispel.Physical }, { __index = C.Colors.dispel })
```

In `Dispellable.lua`, the local `DISPEL_COLORS` table is no longer needed since the rewrite (Task 9) uses `C.Colors.dispel` directly.

- [ ] **Step 2: Verify final TOC load order**

Ensure `Framed.toc` has this order for the new/modified sections:

```
# Elements - Indicators
Elements/Indicators/Icon.lua
Elements/Indicators/Icons.lua
Elements/Indicators/FrameBar.lua
Elements/Indicators/Bar.lua
Elements/Indicators/Border.lua
Elements/Indicators/Color.lua
Elements/Indicators/Overlay.lua
Elements/Indicators/Glow.lua
Elements/Indicators/BorderIcon.lua

# Elements - Auras
Elements/Auras/Buffs.lua
Elements/Auras/Debuffs.lua
Elements/Auras/RaidDebuffs.lua
Elements/Auras/PrivateAuras.lua
Elements/Auras/Dispellable.lua
Elements/Auras/MissingBuffs.lua
Elements/Auras/TargetedSpells.lua
Elements/Auras/Externals.lua
Elements/Auras/Defensives.lua

# Settings (builders before panels)
Settings/Builders/BorderIconSettings.lua
Settings/Builders/IndicatorCRUD.lua
Settings/Panels/...
```

- [ ] **Step 3: Delete FramedDB and full test**

Delete saved variables to get fresh defaults. Test all unit frame types:
- Player/Target: buffs/debuffs display
- Party: full indicator suite (buffs, debuffs, raid debuffs, dispels, externals, defensives)
- Raid: compact indicators
- Boss/Arena: debuffs, targeted spells
- Settings: all aura panels functional

- [ ] **Step 4: Commit**

```bash
git add Elements/Indicators/Icon.lua Elements/Auras/Dispellable.lua Framed.toc
git commit -m "feat: final integration and cleanup for Cell-style indicator system"
```
