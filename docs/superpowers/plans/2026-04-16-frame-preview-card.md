# Frame Preview Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a live preview card to every Frame settings page that renders the frame with all configured elements at real pixel size, with live CONFIG_CHANGED updates, group layout support, raid stepper, party pet toggle, and focus mode.

**Architecture:** Thin Settings wrapper (`Settings/Builders/FramePreview.lua`) reuses `Preview/PreviewFrame.lua` element builders. Frame pages migrate off CardGrid to a wrapper-grid pinned-row layout (`Preview | PositionAndLayout`). Performance handled via frame pooling and targeted cosmetic updates.

**Tech Stack:** WoW Lua, oUF framework (embedded as `F.oUF`), Framed widget library (`F.Widgets`), EventBus for CONFIG_CHANGED

**Spec:** `docs/superpowers/specs/2026-04-16-frame-preview-card-design.md`

**Scope boundaries:** This is strictly a UI/UX project. Do NOT modify: Config API, EventBus, preset system, live frame rendering (`Units/`, `Elements/`, `StyleBuilder.lua`), LiveUpdate handlers, Edit Mode, or any settings card wiring except `PositionAndLayout.lua`. If a task requires changing any of these, stop and re-evaluate.

**Canonical defaults:** Every config key the preview reads MUST have a default in `Presets/Defaults.lua`. No hardcoded `or` fallbacks in new code (`FramePreview.lua`, new builders). The one exception is `config.elementStrata or {}` guards in `PreviewFrame.lua` — that file is shared with Edit Mode and the `or {}` handles migration of configs created before elementStrata was added. Existing fallbacks in existing code that serve a documented purpose should be left alone.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Settings/Builders/FramePreview.lua` | **Create** | Main orchestrator: preview card, solo/group rendering, CONFIG_CHANGED listener, focus mode, raid stepper, pet toggle, frame pooling |
| `Preview/PreviewFrame.lua` | **Modify** | Add `if(auraConfig)` nil guard; wire `elementStrata` into existing builders; add `BuildPortrait`, `BuildStatusText`, `BuildShieldsAndAbsorbs` |
| `Settings/FrameSettingsBuilder.lua` | **Modify** | Migrate off CardGrid to wrapper-grid pinned row; inject preview card; extract PositionAndLayout to pinned row |
| `Settings/Cards/PositionAndLayout.lua` | **Modify** | Split active/greyed controls; add Edit Mode link |
| `Presets/Defaults.lua` | **Modify** | Add `elementStrata` default table; add `unitsPerColumn`/`maxColumns` to group configs; add `raidPreviewCount` to charDefaults |
| `Framed.toc` | **Modify** | Add `Settings/Builders/FramePreview.lua` load line |

---

## Task 1: Add defaults and TOC entry

**Files:**
- Modify: `Presets/Defaults.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Add `elementStrata` to `baseUnitConfig()` in `Presets/Defaults.lua`**

Find the `baseUnitConfig()` function (around line 10). Add `elementStrata` after the existing config keys (before the `return` or end of the table):

```lua
elementStrata = {
	healthBar      = 0,
	healPrediction = 1,
	damageAbsorb   = 2,
	healAbsorb     = 3,
	overAbsorb     = 4,
	nameText       = 5,
	statusIcons    = 6,
	statusText     = 7,
	castBar        = 8,
	portrait       = 9,
},
```

- [ ] **Step 2: Add `unitsPerColumn` and `maxColumns` to group unit configs**

These keys are read by CalculateGroupLayout but don't exist in defaults yet. Add them to each group config function:

In `partyConfig()` (around line 280), after `c.anchorPoint`:
```lua
c.unitsPerColumn = 5
c.maxColumns     = 1
```

In `raidConfig()` (around line 300), after `c.anchorPoint`:
```lua
c.unitsPerColumn = 5
c.maxColumns     = 8
```

In `bossConfig()` (around line 251), after `c.anchorPoint`:
```lua
c.unitsPerColumn = 4
c.maxColumns     = 1
```

In `arenaConfig()` (around line 319), after `c.anchorPoint`:
```lua
c.unitsPerColumn = 3
c.maxColumns     = 1
```

- [ ] **Step 3: Add `raidPreviewCount` to `charDefaults` in `Presets/Defaults.lua`**

Find `charDefaults` (or the character-level defaults table). Add:

```lua
settings = {
	raidPreviewCount = 8,
},
```

If `settings` already exists as a sub-table, merge into it rather than overwriting.

- [ ] **Step 4: Add `FramePreview.lua` to `Framed.toc`**

Find the Settings/Builders section (around line 195, near `AuraPreview.lua`). Add immediately after:

```
Settings\Builders\FramePreview.lua
```

- [ ] **Step 5: Verify in-game**

`/reload` — confirm no errors. Run `/framed config` to verify `elementStrata` appears in preset config output.

- [ ] **Step 6: Commit**

```bash
git add Presets/Defaults.lua Framed.toc
git commit -m "feat: add elementStrata, unitsPerColumn/maxColumns defaults, raidPreviewCount charDefault"
```

---

## Task 2: PreviewFrame.lua — nil guard and elementStrata wiring

**Files:**
- Modify: `Preview/PreviewFrame.lua`

- [ ] **Step 1: Add auraConfig nil guard in `BuildAllElements`**

Find `BuildAllElements` (line 432). At line 448-450, the call to `F.PreviewAuras.BuildAll` is unconditional. Wrap it:

```lua
-- Before (line 448-450):
local animated = F.PreviewManager.IsAnimationEnabled()
F.PreviewAuras.BuildAll(frame, auraConfig, animated)

-- After:
local animated = F.PreviewManager.IsAnimationEnabled()
if(auraConfig) then
	F.PreviewAuras.BuildAll(frame, auraConfig, animated)
end
```

- [ ] **Step 2: Wire elementStrata into `BuildHealthBar`**

Find `BuildHealthBar` (line 128). Where it sets frame levels on `textOverlay` (line 156), replace the hardcoded offset:

```lua
-- Before:
textOverlay:SetFrameLevel(bar:GetFrameLevel() + 2)

-- After:
local strata = config.elementStrata or {}
textOverlay:SetFrameLevel(bar:GetFrameLevel() + (strata.healthBar or 0) + 2)
```

- [ ] **Step 3: Wire elementStrata into `BuildPowerBar`**

Find `BuildPowerBar` (line 182). Replace the hardcoded text overlay frame level:

```lua
-- Before:
textOverlay:SetFrameLevel(bar:GetFrameLevel() + 2)

-- After:
local strata = config.elementStrata or {}
textOverlay:SetFrameLevel(bar:GetFrameLevel() + (strata.healthBar or 0) + 2)
```

Wait — power text should use its own strata key. But the spec's `elementStrata` table doesn't have a `powerBar` or `powerText` key. The strata values control the base frame level of each element group relative to the frame root. The text overlay within each element is always `+2` above its own bar. So the wiring should be at the element's wrapper level, not the text level.

Correct approach — wire strata at the wrapper frame level for each element. Find where each element's wrapper is created and set its frame level:

In `BuildHealthBar`, after the wrapper is created (around line 130-135):

```lua
local strata = config.elementStrata or {}
wrapper:SetFrameLevel(frame:GetFrameLevel() + (strata.healthBar or 0))
```

In `BuildPowerBar`, after the wrapper is created (around line 184-188):

```lua
-- Power bar doesn't have its own strata key; it's always below health
-- Leave as-is for now; strata wiring is for elements that overlap
```

- [ ] **Step 4: Wire elementStrata into `BuildNameText`**

Find `BuildNameText` (line 250). Replace the hardcoded frame level on `nameOverlay`:

```lua
-- Before:
nameOverlay:SetFrameLevel(frame._healthBar:GetFrameLevel() + 3)

-- After:
local strata = config.elementStrata or {}
nameOverlay:SetFrameLevel(frame:GetFrameLevel() + (strata.nameText or 5))
```

- [ ] **Step 5: Wire elementStrata into `BuildStatusIcons`**

Find `BuildStatusIcons` (line 324). Replace the hardcoded frame level on `iconOverlay`:

```lua
-- Before:
iconOverlay:SetFrameLevel(frame._healthBar:GetFrameLevel() + 5)

-- After:
local strata = config.elementStrata or {}
iconOverlay:SetFrameLevel(frame:GetFrameLevel() + (strata.statusIcons or 6))
```

- [ ] **Step 6: Wire elementStrata into `BuildCastbar`**

Find `BuildCastbar` (line 375). Set the castbar wrapper's frame level:

```lua
local strata = config.elementStrata or {}
wrapper:SetFrameLevel(frame:GetFrameLevel() + (strata.castBar or 8))
```

- [ ] **Step 7: Verify in-game**

`/reload` — open Edit Mode, confirm preview frames still render correctly with the strata changes. The default values match the old hardcoded values so no visual change expected.

- [ ] **Step 8: Commit**

```bash
git add Preview/PreviewFrame.lua
git commit -m "feat: add auraConfig nil guard and wire elementStrata into preview builders"
```

---

## Task 3: New element builders in PreviewFrame.lua

**Files:**
- Modify: `Preview/PreviewFrame.lua`

- [ ] **Step 1: Add `BuildPortrait`**

Add this function before `BuildAllElements` (before line 430):

```lua
local function BuildPortrait(frame, config, fakeUnit)
	if(not config.portrait) then return end
	local strata = config.elementStrata or {}

	local portraitType = config.portrait.type
	local size = math.min(config.height, config.width) * 0.8

	local wrapper = CreateFrame('Frame', nil, frame)
	wrapper:SetSize(size, size)
	wrapper:SetPoint('LEFT', frame, 'LEFT', 4, 0)
	wrapper:SetFrameLevel(frame:GetFrameLevel() + (strata.portrait or 9))

	local tex = wrapper:CreateTexture(nil, 'ARTWORK')
	tex:SetAllPoints(wrapper)

	-- Use class icon as portrait stand-in (real portraits need a unit token)
	if(fakeUnit and fakeUnit.class) then
		local coords = CLASS_ICON_TCOORDS[fakeUnit.class]
		tex:SetTexture([[Interface\GLUES\CHARACTERCREATE\UI-CHARACTERCREATE-CLASSES]])
		if(coords) then
			tex:SetTexCoord(unpack(coords))
		end
	end

	frame._portrait = wrapper
	frame._portraitTex = tex
end
```

Note: `CLASS_ICON_TCOORDS` is a Blizzard global. If it's not available, add a local lookup table at the top of the file matching `Elements/Core/Portrait.lua`'s approach. Check the codebase first before adding a duplicate.

- [ ] **Step 2: Add `BuildStatusText`**

Add after `BuildPortrait`:

```lua
local function BuildStatusText(frame, config, fakeUnit)
	local stConfig = config.statusText
	if(not stConfig or stConfig.enabled == false) then return end
	local strata = config.elementStrata or {}

	local overlay = CreateFrame('Frame', nil, frame)
	overlay:SetAllPoints(frame)
	overlay:SetFrameLevel(frame:GetFrameLevel() + (strata.statusText or 7))

	local text = Widgets.CreateFontString(overlay, stConfig.fontSize, C.Colors.textActive)
	text:SetPoint(stConfig.anchor, overlay, stConfig.anchor,
		stConfig.anchorX, stConfig.anchorY)

	-- Show a fake status for dead units
	if(fakeUnit and fakeUnit.isDead) then
		text:SetText('DEAD')
		text:SetTextColor(0.8, 0.2, 0.2, 1)
	else
		text:SetText('')
	end

	frame._statusText = text
	frame._statusTextOverlay = overlay
end
```

- [ ] **Step 3: Add `BuildShieldsAndAbsorbs`**

Add after `BuildStatusText`:

```lua
local function BuildShieldsAndAbsorbs(frame, config, fakeUnit)
	if(not frame._healthBar) then return end
	local hc = config.health
	local strata = config.elementStrata or {}
	local healthBar = frame._healthBar
	local barWidth = config.width
	local healthPct = fakeUnit and fakeUnit.healthPct or 0.85

	-- Heal prediction
	if(hc.healPrediction ~= false and fakeUnit and fakeUnit.incomingHeal) then
		local healBar = CreateFrame('StatusBar', nil, healthBar)
		healBar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
		healBar:SetFrameLevel(healthBar:GetFrameLevel() + (strata.healPrediction or 1))
		healBar:SetMinMaxValues(0, 1)
		healBar:SetValue(fakeUnit.incomingHeal)

		local healColor = hc.healPredictionColor
		healBar:SetStatusBarColor(healColor[1], healColor[2], healColor[3], healColor[4])

		-- Position after the health fill
		local fillWidth = barWidth * healthPct
		healBar:SetPoint('LEFT', healthBar, 'LEFT', fillWidth, 0)
		healBar:SetSize(barWidth * fakeUnit.incomingHeal, healthBar:GetHeight())

		frame._healPredBar = healBar
	end

	-- Damage absorb (shields)
	if(hc.damageAbsorb ~= false and fakeUnit and fakeUnit.damageAbsorb) then
		local absorbBar = CreateFrame('StatusBar', nil, healthBar)
		absorbBar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
		absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + (strata.damageAbsorb or 2))
		absorbBar:SetMinMaxValues(0, 1)
		absorbBar:SetValue(1)

		local absorbColor = hc.damageAbsorbColor
		absorbBar:SetStatusBarColor(absorbColor[1], absorbColor[2], absorbColor[3], absorbColor[4])

		local fillWidth = barWidth * healthPct
		absorbBar:SetPoint('LEFT', healthBar, 'LEFT', fillWidth, 0)
		absorbBar:SetSize(barWidth * fakeUnit.damageAbsorb, healthBar:GetHeight())

		frame._damageAbsorbBar = absorbBar
	end

	-- Heal absorb
	if(hc.healAbsorb ~= false and fakeUnit and fakeUnit.healAbsorb) then
		local healAbsorbBar = CreateFrame('StatusBar', nil, healthBar)
		healAbsorbBar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
		healAbsorbBar:SetFrameLevel(healthBar:GetFrameLevel() + (strata.healAbsorb or 3))
		healAbsorbBar:SetMinMaxValues(0, 1)
		healAbsorbBar:SetValue(1)

		local haColor = hc.healAbsorbColor
		healAbsorbBar:SetStatusBarColor(haColor[1], haColor[2], haColor[3], haColor[4])

		-- Heal absorbs eat into the health bar from the right
		local absorbWidth = barWidth * fakeUnit.healAbsorb
		healAbsorbBar:SetPoint('RIGHT', healthBar, 'LEFT', barWidth * healthPct, 0)
		healAbsorbBar:SetSize(absorbWidth, healthBar:GetHeight())

		frame._healAbsorbBar = healAbsorbBar
	end

	-- Overshield (texture on an OVERLAY-level wrapper frame for strata control)
	if(hc.overAbsorb ~= false and fakeUnit and fakeUnit.overAbsorb) then
		local overWrapper = CreateFrame('Frame', nil, healthBar)
		overWrapper:SetFrameLevel(healthBar:GetFrameLevel() + (strata.overAbsorb or 4))
		overWrapper:SetPoint('TOPRIGHT', healthBar, 'TOPRIGHT', 4, 2)
		overWrapper:SetPoint('BOTTOMRIGHT', healthBar, 'BOTTOMRIGHT', 4, -2)
		overWrapper:SetWidth(12)

		local overGlow = overWrapper:CreateTexture(nil, 'OVERLAY')
		overGlow:SetAllPoints(overWrapper)
		overGlow:SetTexture([[Interface\RaidFrame\Shield-Overshield]])
		overGlow:SetBlendMode('ADD')
		overGlow:SetAlpha(0.8)

		frame._overAbsorbGlow = overWrapper
	end
end
```

- [ ] **Step 4: Wire new builders into `BuildAllElements`**

In `BuildAllElements` (line 432), add calls to the new builders after the existing ones (after `BuildHighlights`, before the aura block):

```lua
BuildHealthBar(frame, config)
BuildPowerBar(frame, config)
BuildNameText(frame, config, fakeUnit)
BuildStatusIcons(frame, config)
BuildCastbar(frame, config)
BuildHighlights(frame, config)
BuildPortrait(frame, config, fakeUnit)        -- NEW
BuildStatusText(frame, config, fakeUnit)       -- NEW
BuildShieldsAndAbsorbs(frame, config, fakeUnit) -- NEW

if(auraConfig) then
	-- ...existing aura code...
end
```

- [ ] **Step 5: Update `DestroyChildren` key list**

In `DestroyChildren` (line 510), add the new reference keys to the cleanup list:

```lua
local keys = {
	'_bg', '_healthWrapper', '_healthBar', '_healthText', '_healthTextClassColor',
	'_powerWrapper', '_powerBar', '_powerText', '_powerTextClassColor',
	'_nameText', '_castbar', '_targetHighlight', '_iconOverlay', '_auraGroups',
	'_portrait', '_portraitTex', '_statusText', '_statusTextOverlay',  -- NEW
	'_healPredBar', '_damageAbsorbBar', '_healAbsorbBar', '_overAbsorbGlow', -- NEW
}
```

- [ ] **Step 6: Verify in-game**

`/reload` — open Edit Mode, confirm existing preview frames still render. The new builders only fire for configs that have portrait/statusText/shields data, so no visual change expected until FramePreview.lua provides fake data.

- [ ] **Step 7: Commit**

```bash
git add Preview/PreviewFrame.lua
git commit -m "feat: add Portrait, StatusText, ShieldsAndAbsorbs preview builders"
```

---

## Task 4: Create FramePreview.lua — solo frame rendering

**Files:**
- Create: `Settings/Builders/FramePreview.lua`

- [ ] **Step 1: Create the file with module setup and solo fake data**

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings = F.Settings or {}
F.Settings.FramePreview = {}
local FP = F.Settings.FramePreview

-- ============================================================
-- Solo fake unit data (mirrors PreviewManager.SOLO_FAKES with
-- health at 0.85 so loss color is passively visible)
-- ============================================================

local function getPlayerClass()
	local _, class = UnitClass('player')
	return class or 'PALADIN'
end

local SOLO_FAKES = {
	player       = function() return {
		name = UnitName('player') or 'You', class = getPlayerClass(),
		healthPct = 0.85, powerPct = 0.7,
		incomingHeal = 0.15, damageAbsorb = 0.10, healAbsorb = 0.05,
	} end,
	target       = function() return {
		name = 'Target Dummy', class = 'WARRIOR',
		healthPct = 0.85, powerPct = 0.7,
		incomingHeal = 0.10, damageAbsorb = 0.12,
	} end,
	targettarget = function() return {
		name = 'Healbot', class = 'PRIEST',
		healthPct = 0.85, powerPct = 0.95,
		incomingHeal = 0.08, overAbsorb = true,
	} end,
	focus        = function() return {
		name = 'Focus Target', class = 'MAGE',
		healthPct = 0.85, powerPct = 0.9,
		damageAbsorb = 0.15,
	} end,
	pet          = function() return {
		name = 'Pet', class = 'HUNTER',
		healthPct = 0.85, powerPct = 0.6,
	} end,
}

-- ============================================================
-- State
-- ============================================================

local activePreview = nil    -- current preview card frame
local activeUnitType = nil   -- 'player', 'target', 'party', etc.
local previewFrames = {}     -- array of child preview frames
local framePool = {}         -- recycled preview frames

-- ============================================================
-- Frame pool
-- ============================================================

local function AcquireFrame(parent)
	local frame = tremove(framePool)
	if(frame) then
		frame:SetParent(parent)
		frame:Show()
		return frame
	end
	return nil
end

local function ReleaseFrame(frame)
	frame:Hide()
	frame:SetParent(nil)
	tinsert(framePool, frame)
end

local function DrainPool()
	for _, frame in next, framePool do
		frame:Hide()
		frame:SetParent(nil)
	end
	wipe(framePool)
end

-- ============================================================
-- Config helpers
-- ============================================================

local function getUnitConfig(unitType)
	local presetName = F.Settings.GetEditingPreset()
	return F.Config:Get('presets.' .. presetName .. '.unitConfigs.' .. unitType)
end

-- ============================================================
-- Solo preview rendering
-- ============================================================

local function RenderSoloPreview(viewport, unitType)
	local config = getUnitConfig(unitType)
	if(not config) then return end

	local fakeFn = SOLO_FAKES[unitType]
	local fakeUnit = fakeFn and fakeFn() or { name = 'Unit', class = 'WARRIOR', healthPct = 0.85, powerPct = 0.7 }

	local frame = AcquireFrame(viewport) or F.PreviewFrame.Create(viewport, config, fakeUnit, nil, nil)
	if(frame._config) then
		F.PreviewFrame.UpdateFromConfig(frame, config, nil)
	end

	frame._fakeUnit = fakeUnit
	frame:ClearAllPoints()
	frame:SetPoint('TOPLEFT', viewport, 'TOPLEFT', 0, 0)

	previewFrames[1] = frame
end

-- ============================================================
-- Public: Build the preview card
-- ============================================================

function FP.BuildPreviewCard(parent, width, unitType)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)
	Widgets.CreateAccentBar(card, 'top')

	-- Header row
	local title = Widgets.CreateFontString(inner, C.Font.sizeMedium, C.Colors.textActive)
	title:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cy)
	title:SetText('Preview — ' .. (unitType:sub(1, 1):upper() .. unitType:sub(2)))
	cy = cy - C.Font.sizeMedium - 8

	-- Preview viewport (horizontal scroll for overflow)
	local viewport = CreateFrame('ScrollFrame', nil, inner)
	local viewContent = CreateFrame('Frame', nil, viewport)
	viewport:SetScrollChild(viewContent)
	viewport:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cy)
	viewport:SetPoint('RIGHT', inner, 'RIGHT', 0, 0)

	-- Horizontal mouse wheel scrolling for wide group layouts
	viewport:EnableMouseWheel(true)
	viewport:SetScript('OnMouseWheel', function(self, delta)
		local maxScroll = math.max(0, viewContent:GetWidth() - self:GetWidth())
		local current = self:GetHorizontalScroll()
		self:SetHorizontalScroll(math.max(0, math.min(maxScroll, current - delta * 30)))
	end)

	local config = getUnitConfig(unitType)
	local viewH = config and (config.height + 20) or 60
	viewport:SetHeight(viewH)
	-- Width derived from parent after layout; content sizes to fit frames
	viewContent:SetHeight(viewH)
	cy = cy - viewH - 8

	-- Render the preview
	activeUnitType = unitType
	RenderSoloPreview(viewContent, unitType)

	Widgets.EndCard(card, parent, cy)

	activePreview = card
	card._viewport = viewport
	card._viewContent = viewContent
	card._unitType = unitType

	return card
end

-- ============================================================
-- Public: Destroy preview
-- ============================================================

function FP.Destroy()
	for _, frame in next, previewFrames do
		ReleaseFrame(frame)
	end
	wipe(previewFrames)
	DrainPool()

	if(activePreview) then
		activePreview:Hide()
		activePreview:SetParent(nil)
		activePreview = nil
	end
	activeUnitType = nil
end
```

- [ ] **Step 2: Verify in-game**

`/reload` — no errors expected (file loads but nothing calls `BuildPreviewCard` yet).

- [ ] **Step 3: Commit**

```bash
git add Settings/Builders/FramePreview.lua
git commit -m "feat: create FramePreview.lua with solo preview rendering and frame pool"
```

---

## Task 5: Wire preview into FrameSettingsBuilder (initial integration)

**Files:**
- Modify: `Settings/FrameSettingsBuilder.lua`

- [ ] **Step 1: Add preview card injection before CardGrid**

Find `FrameSettingsBuilder.Create` (line 99). After the scroll content frame is created but before `Widgets.CreateCardGrid` (line 133), add:

```lua
-- Frame preview card (pinned above the card grid for now; migrated to wrapper grid in Task 11)
local previewCard = F.Settings.FramePreview.BuildPreviewCard(content, width, unitType)
if(previewCard) then
	previewCard:SetPoint('TOPLEFT', content, 'TOPLEFT', 0, 0)
end
```

Adjust the CardGrid's anchor to sit below the preview card instead of at the top of `content`. Find where the grid is positioned and update:

```lua
-- Before:
local grid = Widgets.CreateCardGrid(content, width)

-- After:
local grid = Widgets.CreateCardGrid(content, width)
if(previewCard) then
	-- Offset grid below preview card
	grid:SetPoint('TOPLEFT', previewCard, 'BOTTOMLEFT', 0, -8)
end
```

Note: The exact anchoring depends on how `CreateCardGrid` positions itself. Read the existing anchor code at line 133-135 before modifying. The goal is: preview card at top, card grid below it.

- [ ] **Step 2: Add teardown on panel hide**

Find the panel's `OnHide` or destroy path. Add:

```lua
F.Settings.FramePreview.Destroy()
```

If there's no explicit `OnHide`, add one to the scroll frame or content frame:

```lua
content:SetScript('OnHide', function()
	F.Settings.FramePreview.Destroy()
end)
```

- [ ] **Step 3: Verify in-game**

`/reload` — open Settings, navigate to Player page. The preview card should appear at the top showing a single player frame with health/power/name/status icons. Navigate away and back — preview should teardown and rebuild.

- [ ] **Step 4: Commit**

```bash
git add Settings/FrameSettingsBuilder.lua
git commit -m "feat: wire FramePreview into FrameSettingsBuilder with teardown"
```

---

## Task 6: CONFIG_CHANGED live updates with targeted dispatch

**Files:**
- Modify: `Settings/Builders/FramePreview.lua`

- [ ] **Step 1: Add targeted update functions**

Add after the config helpers section in `FramePreview.lua`:

```lua
-- ============================================================
-- Targeted cosmetic updaters (no DestroyChildren, no rebuild)
-- ============================================================

local function updateHealthColor(frame, config)
	if(not frame._healthBar) then return end
	local fakeUnit = frame._fakeUnit
	applyHealthColor(frame._healthBar, config, fakeUnit)
	applyHealthLossColor(frame._healthBar._bg, config, fakeUnit)
end

local function updateHealthText(frame, config)
	if(not frame._healthText) then return end
	local hFmt = (config.health and config.health.textFormat) or 'percent'
	local fakeUnit = frame._fakeUnit
	frame._healthText:SetText(formatHealthText(fakeUnit.healthPct or 0.85, hFmt))
end

local function updatePowerText(frame, config)
	if(not frame._powerText) then return end
	local pFmt = (config.power and config.power.textFormat) or 'percent'
	local fakeUnit = frame._fakeUnit
	frame._powerText:SetText(formatPowerText(fakeUnit.powerPct or 0.7, pFmt))
end
```

Note: `applyHealthColor`, `applyHealthLossColor`, `formatHealthText`, and `formatPowerText` are local functions in `PreviewFrame.lua` and NOT accessible from `FramePreview.lua`. For cosmetic updates that need these functions, fall back to a full rebuild via `PreviewFrame.UpdateFromConfig`. The targeted update optimization applies to cases where we can directly call `SetFont`, `SetTextColor`, `SetStatusBarColor`, etc. without needing PreviewFrame internals.

Revised approach — the dispatch table maps config keys to either `:direct` (call a method on the frame) or `:rebuild` (call `PreviewFrame.UpdateFromConfig`):

```lua
-- ============================================================
-- CONFIG_CHANGED dispatch
-- ============================================================

local STRUCTURAL_KEYS = {
	width = true, height = true, showPower = true,
	orientation = true, unitsPerColumn = true, maxColumns = true, spacing = true,
}

local rebuildPending = false

local function debouncedRebuild()
	if(rebuildPending) then return end
	rebuildPending = true
	C_Timer.After(0.05, function()
		rebuildPending = false
		FP.RebuildPreview()
	end)
end

local function onConfigChanged(path)
	if(not activePreview or not activeUnitType) then return end

	-- Parse path: presets.<preset>.unitConfigs.<unitType>.<key>
	local preset, unit, key = path:match('presets%.([^%.]+)%.unitConfigs%.([^%.]+)%.(.+)')
	if(not preset) then
		-- Check partyPets path: presets.<preset>.partyPets.<key>
		local petPreset, petKey = path:match('presets%.([^%.]+)%.partyPets%.(.+)')
		if(petPreset and activeUnitType == 'party') then
			if(petPreset ~= F.Settings.GetEditingPreset()) then return end
			if(showPets) then
				local config = getUnitConfig(activeUnitType)
				if(config) then
					RenderPetFrames(activePreview._viewContent, config)
				end
			end
			return
		end
		return
	end

	-- Preset guard
	if(preset ~= F.Settings.GetEditingPreset()) then return end
	-- Unit type guard
	if(unit ~= activeUnitType) then return end

	local config = getUnitConfig(activeUnitType)
	if(not config) then return end

	if(STRUCTURAL_KEYS[key:match('^[^%.]+')]) then
		-- Structural: debounced full rebuild
		debouncedRebuild()
	else
		-- Cosmetic: update in place, no debounce (cheap per-tick)
		for _, frame in next, previewFrames do
			F.PreviewFrame.UpdateFromConfig(frame, config, nil)
		end
	end
end

local configListenerHandle = nil

local function RegisterConfigListener()
	configListenerHandle = F.EventBus:Register('CONFIG_CHANGED', onConfigChanged, 'FramePreview.ConfigListener')
end

local function UnregisterConfigListener()
	if(configListenerHandle) then
		F.EventBus:Unregister('CONFIG_CHANGED', 'FramePreview.ConfigListener')
		configListenerHandle = nil
	end
end
```

- [ ] **Step 2: Add `RebuildPreview` function**

```lua
function FP.RebuildPreview()
	if(not activePreview or not activeUnitType) then return end

	-- Release existing frames to pool
	for _, frame in next, previewFrames do
		ReleaseFrame(frame)
	end
	wipe(previewFrames)

	local viewport = activePreview._viewContent
	local config = getUnitConfig(activeUnitType)
	if(not viewport or not config) then return end

	-- Update viewport height
	local viewH = config.height + 20
	activePreview._viewport:SetHeight(viewH)
	viewport:SetHeight(viewH)

	-- Re-render based on unit type
	if(SOLO_FAKES[activeUnitType]) then
		RenderSoloPreview(viewport, activeUnitType)
	-- Group rendering added in Task 7
	end

	-- Re-apply focus mode if active (rebuild creates fresh frames)
	if(focusModeEnabled and focusedCardId) then
		ApplyFocusMode(focusedCardId)
	end
end
```

- [ ] **Step 3: Wire listener registration into BuildPreviewCard and Destroy**

In `BuildPreviewCard`, after rendering the preview, add:

```lua
RegisterConfigListener()
```

In `Destroy`, before clearing `activePreview`, add:

```lua
UnregisterConfigListener()
```

- [ ] **Step 4: Add EDITING_PRESET_CHANGED listener**

In `BuildPreviewCard`, also register for preset changes:

```lua
F.EventBus:Register('EDITING_PRESET_CHANGED', function()
	FP.RebuildPreview()
end, 'FramePreview.PresetListener')
```

In `Destroy`, unregister it:

```lua
F.EventBus:Unregister('EDITING_PRESET_CHANGED', 'FramePreview.PresetListener')
```

- [ ] **Step 5: Verify in-game**

`/reload` — open Settings → Player page. Change health text format dropdown — the preview should update immediately. Change width/height slider — preview should rebuild. Switch preset dropdown — preview should rebuild with new preset's config.

- [ ] **Step 6: Commit**

```bash
git add Settings/Builders/FramePreview.lua
git commit -m "feat: add CONFIG_CHANGED listener with structural/cosmetic dispatch"
```

---

## Task 7: Group frame rendering (party, arena, boss)

**Files:**
- Modify: `Settings/Builders/FramePreview.lua`

- [ ] **Step 1: Add group fake unit data and layout math**

Add after `SOLO_FAKES`:

```lua
-- ============================================================
-- Group fake unit data
-- ============================================================

local GROUP_FAKES = {
	{ name = 'Tankadin',   class = 'PALADIN', role = 'TANK',    healthPct = 0.85, powerPct = 0.7,  incomingHeal = 0.10, damageAbsorb = 0.08 },
	{ name = 'Healbot',    class = 'PRIEST',  role = 'HEALER',  healthPct = 0.92, powerPct = 0.95, overAbsorb = true },
	{ name = 'Stabsworth', class = 'ROGUE',   role = 'DAMAGER', healthPct = 0.65, powerPct = 0.4,  healAbsorb = 0.05 },
	{ name = 'Frostbolt',  class = 'MAGE',    role = 'DAMAGER', healthPct = 0.78, powerPct = 0.9,  damageAbsorb = 0.12 },
	{ name = 'Deadshot',   class = 'HUNTER',  role = 'DAMAGER', healthPct = 0,    powerPct = 0,    isDead = true },
}

local BOSS_FAKES = {
	{ name = 'Boss 1', class = 'WARRIOR', healthPct = 0.95, powerPct = 1.0 },
	{ name = 'Boss 2', class = 'WARRIOR', healthPct = 0.72, powerPct = 0.8 },
	{ name = 'Boss 3', class = 'WARRIOR', healthPct = 0.50, powerPct = 0.6 },
	{ name = 'Boss 4', class = 'WARRIOR', healthPct = 0.30, powerPct = 0.4 },
}

local GROUP_COUNTS = {
	party = 5,
	arena = 3,
	boss  = 4,
}

local function getFakeUnit(index)
	local base = GROUP_FAKES[((index - 1) % #GROUP_FAKES) + 1]
	if(index > #GROUP_FAKES) then
		local copy = {}
		for k, v in next, base do copy[k] = v end
		copy.name = base.name .. ' ' .. math.ceil(index / #GROUP_FAKES)
		return copy
	end
	return base
end

-- ============================================================
-- Group layout math (flat column flow)
-- ============================================================

local function CalculateGroupLayout(config, count)
	local w = config.width
	local h = config.height
	local spacing = config.spacing
	local upc = config.unitsPerColumn
	local isVertical = config.orientation == 'vertical'

	local positions = {}
	for i = 0, count - 1 do
		local col = math.floor(i / upc)
		local row = i % upc
		local x, y
		if(isVertical) then
			x = col * (w + spacing)
			y = -(row * (h + spacing))
		else
			x = row * (w + spacing)
			y = -(col * (h + spacing))
		end
		positions[i + 1] = { x = x, y = y }
	end
	return positions
end
```

- [ ] **Step 2: Add `RenderGroupPreview` function**

```lua
local function RenderGroupPreview(viewport, unitType, count)
	local config = getUnitConfig(unitType)
	if(not config) then return end

	local fakes
	if(unitType == 'boss') then
		fakes = BOSS_FAKES
	end

	local positions = CalculateGroupLayout(config, count)

	for i = 1, count do
		local fakeUnit = fakes and fakes[i] or getFakeUnit(i)
		local frame = AcquireFrame(viewport) or F.PreviewFrame.Create(viewport, config, fakeUnit, nil, nil)
		if(frame._config) then
			frame._fakeUnit = fakeUnit
			F.PreviewFrame.UpdateFromConfig(frame, config, nil)
		end

		frame:ClearAllPoints()
		frame:SetPoint('TOPLEFT', viewport, 'TOPLEFT', positions[i].x, positions[i].y)

		previewFrames[i] = frame
	end

	-- Size the viewport to fit all frames
	local config_w = config.width
	local config_h = config.height
	local spacing = config.spacing
	local upc = config.unitsPerColumn
	local isVertical = config.orientation == 'vertical'

	local cols = math.ceil(count / upc)
	local rows = math.min(count, upc)

	local totalW, totalH
	if(isVertical) then
		totalW = cols * config_w + (cols - 1) * spacing
		totalH = rows * config_h + (rows - 1) * spacing
	else
		totalW = rows * config_w + (rows - 1) * spacing
		totalH = cols * config_h + (cols - 1) * spacing
	end

	viewport:SetSize(math.max(totalW, 1), math.max(totalH, 1))
end
```

- [ ] **Step 3: Add sort function for fake units**

Add after `CalculateGroupLayout`:

```lua
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

local function SortFakeUnits(units, config)
	local sortMode = config.sortMode
	if(not sortMode or sortMode == 'index') then return units end

	local sorted = {}
	for i, u in next, units do sorted[i] = u end

	if(sortMode == 'role') then
		table.sort(sorted, function(a, b)
			return (ROLE_ORDER[a.role] or 99) < (ROLE_ORDER[b.role] or 99)
		end)
	elseif(sortMode == 'class') then
		table.sort(sorted, function(a, b)
			return (a.class or '') < (b.class or '')
		end)
	elseif(sortMode == 'name') then
		table.sort(sorted, function(a, b)
			return (a.name or '') < (b.name or '')
		end)
	end
	return sorted
end
```

In `RenderGroupPreview`, apply sorting before positioning:

```lua
-- After building the fakes list but before positioning
local sortedFakes = {}
for i = 1, count do
	sortedFakes[i] = fakes and fakes[i] or getFakeUnit(i)
end
sortedFakes = SortFakeUnits(sortedFakes, config)
```

Then use `sortedFakes[i]` instead of the inline `fakes and fakes[i] or getFakeUnit(i)` in the render loop.

- [ ] **Step 4: Update `BuildPreviewCard` to handle group types**

In `BuildPreviewCard`, after the viewport setup, replace the solo render call with branching logic:

```lua
if(SOLO_FAKES[unitType]) then
	RenderSoloPreview(viewContent, unitType)
elseif(GROUP_COUNTS[unitType]) then
	local count = GROUP_COUNTS[unitType]
	RenderGroupPreview(viewContent, unitType, count)
end
```

Also update the viewport height calculation to handle group frames:

```lua
local config = getUnitConfig(unitType)
local viewH
if(not config) then
	viewH = 60
elseif(SOLO_FAKES[unitType]) then
	viewH = config.height + 20
elseif(GROUP_COUNTS[unitType]) then
	local count = GROUP_COUNTS[unitType]
	local rows = math.min(count, config.unitsPerColumn)
	viewH = rows * config.height + (rows - 1) * config.spacing + 20
else
	viewH = config.height + 20
end
```

- [ ] **Step 5: Update `RebuildPreview` to handle group types**

In `RebuildPreview`, add the group rendering branch:

```lua
if(SOLO_FAKES[activeUnitType]) then
	RenderSoloPreview(viewport, activeUnitType)
elseif(activeUnitType == 'raid') then
	local count = F.Config:Get('settings.raidPreviewCount')
	RenderGroupPreview(viewport, activeUnitType, count)
elseif(GROUP_COUNTS[activeUnitType]) then
	local count = GROUP_COUNTS[activeUnitType]
	RenderGroupPreview(viewport, activeUnitType, count)
end
```

- [ ] **Step 6: Verify in-game**

`/reload` — open Settings → Party page. Should see 5 party frames with varied health/class colors. Open Boss page — should see 4 boss frames in a vertical stack. Change width/spacing sliders — layout should update. Change sorting dropdown — units should reorder.

- [ ] **Step 7: Commit**

```bash
git add Settings/Builders/FramePreview.lua
git commit -m "feat: add group frame rendering for party, arena, boss with layout math"
```

---

## Task 8: Raid stepper

**Files:**
- Modify: `Settings/Builders/FramePreview.lua`

- [ ] **Step 1: Add stepper widget to preview card header**

In `BuildPreviewCard`, after the title FontString, add raid stepper conditionally:

```lua
if(unitType == 'raid') then
	local count = F.Config:Get('settings.raidPreviewCount')

	local countText = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSubtle)
	countText:SetPoint('RIGHT', inner, 'RIGHT', 0, cy + C.Font.sizeMedium / 2)
	countText:SetText('units: ' .. count)

	local decBtn = CreateFrame('Button', nil, inner)
	decBtn:SetSize(16, 16)
	decBtn:SetPoint('RIGHT', countText, 'LEFT', -4, 0)
	decBtn:SetNormalFontObject(GameFontNormalSmall)
	decBtn:SetText('▼')
	decBtn:SetScript('OnClick', function()
		local cur = F.Config:Get('settings.raidPreviewCount')
		if(cur > 1) then
			F.Config:Set('settings.raidPreviewCount', cur - 1)
			countText:SetText('units: ' .. (cur - 1))
			FP.RebuildPreview()
		end
	end)

	local incBtn = CreateFrame('Button', nil, inner)
	incBtn:SetSize(16, 16)
	incBtn:SetPoint('LEFT', countText, 'RIGHT', 4, 0)
	incBtn:SetNormalFontObject(GameFontNormalSmall)
	incBtn:SetText('▲')
	incBtn:SetScript('OnClick', function()
		local cur = F.Config:Get('settings.raidPreviewCount')
		if(cur < 40) then
			F.Config:Set('settings.raidPreviewCount', cur + 1)
			countText:SetText('units: ' .. (cur + 1))
			FP.RebuildPreview()
		end
	end)

	card._countText = countText
end
```

- [ ] **Step 2: Update `BuildPreviewCard` to use raid count**

In the viewport height calculation, add the raid case:

```lua
elseif(unitType == 'raid') then
	local count = F.Config:Get('settings.raidPreviewCount')
	local rows = math.min(count, config.unitsPerColumn)
	viewH = rows * config.height + (rows - 1) * config.spacing + 20
```

And in the render call:

```lua
elseif(unitType == 'raid') then
	local count = F.Config:Get('settings.raidPreviewCount')
	RenderGroupPreview(viewContent, unitType, count)
```

- [ ] **Step 3: Verify in-game**

`/reload` — open Settings → Raid page. Should see 8 raid frames by default. Click ▲/▼ buttons — frame count should change and layout should reflow. Count should persist across Settings reopen.

- [ ] **Step 4: Commit**

```bash
git add Settings/Builders/FramePreview.lua
git commit -m "feat: add raid stepper with persistent count"
```

---

## Task 9: Party pet toggle

**Files:**
- Modify: `Settings/Builders/FramePreview.lua`

- [ ] **Step 1: Add pet fake data and rendering**

Add after `BOSS_FAKES`:

```lua
local PET_FAKES = {
	{ name = 'Cat',              class = 'HUNTER', healthPct = 0.90, powerPct = 0.8 },
	{ name = 'Wolf',             class = 'HUNTER', healthPct = 0.75, powerPct = 0.6 },
	{ name = 'Imp',              class = 'WARLOCK', healthPct = 0.85, powerPct = 0.9 },
	{ name = 'Water Elemental',  class = 'MAGE',   healthPct = 0.80, powerPct = 0.7 },
	{ name = 'Treant',           class = 'DRUID',  healthPct = 0.95, powerPct = 1.0 },
}

local showPets = false  -- session-only toggle state
local petFrames = {}
```

- [ ] **Step 2: Add pet rendering function**

```lua
local function RenderPetFrames(viewport, config)
	-- Clear existing pet frames
	for _, frame in next, petFrames do
		ReleaseFrame(frame)
	end
	wipe(petFrames)

	if(not showPets) then return end

	local presetName = F.Settings.GetEditingPreset()
	local petConfig = F.Config:Get('presets.' .. presetName .. '.partyPets')
	if(not petConfig or petConfig.enabled == false) then return end

	local petSpacing = petConfig.spacing
	local petH = math.floor(config.height * 0.4)
	local petW = config.width

	for i, ownerFrame in next, previewFrames do
		local petFake = PET_FAKES[((i - 1) % #PET_FAKES) + 1]
		local petFrame = AcquireFrame(viewport) or CreateFrame('Frame', nil, viewport)

		petFrame:SetSize(petW, petH)
		petFrame:ClearAllPoints()
		petFrame:SetPoint('TOPLEFT', ownerFrame, 'BOTTOMLEFT', 0, -petSpacing)

		-- Simple pet rendering: background + name + health bar
		local bg = petFrame:CreateTexture(nil, 'BACKGROUND')
		bg:SetAllPoints(petFrame)
		bg:SetColorTexture(0.1, 0.12, 0.15, 0.8)

		if(petConfig.showName) then
			local nameText = Widgets.CreateFontString(petFrame, petConfig.nameFontSize, C.Colors.textActive)
			nameText:SetPoint(petConfig.nameAnchor, petFrame, petConfig.nameAnchor,
				petConfig.nameOffsetX, petConfig.nameOffsetY)
			nameText:SetText(petFake.name)
		end

		if(petConfig.showHealthText) then
			local healthText = Widgets.CreateFontString(petFrame, petConfig.healthTextFontSize, C.Colors.textActive)
			healthText:SetPoint(petConfig.healthTextAnchor, petFrame, petConfig.healthTextAnchor,
				petConfig.healthTextOffsetX, petConfig.healthTextOffsetY)
			healthText:SetText(math.floor(petFake.healthPct * 100) .. '%')
		end

		petFrame:Show()
		petFrames[i] = petFrame
	end
end
```

- [ ] **Step 3: Add pet toggle to party preview header**

In `BuildPreviewCard`, add a toggle when `unitType == 'party'`:

```lua
if(unitType == 'party') then
	local petToggle = Widgets.CreateCheckButton(inner, 'Show Pets', function(checked)
		showPets = checked
		local config = getUnitConfig(unitType)
		if(config) then
			RenderPetFrames(card._viewContent, config)
		end
	end)
	petToggle:SetChecked(false)
	petToggle:SetPoint('RIGHT', inner, 'RIGHT', 0, cy + C.Font.sizeMedium / 2)
end
```

- [ ] **Step 4: Wire pet rebuild into group preview**

In `RenderGroupPreview`, after positioning all frames, add:

```lua
if(unitType == 'party') then
	RenderPetFrames(viewport, config)
end
```

- [ ] **Step 5: Clean up pet frames in Destroy**

In `FP.Destroy()`, add before `DrainPool()`:

```lua
for _, frame in next, petFrames do
	ReleaseFrame(frame)
end
wipe(petFrames)
showPets = false
```

- [ ] **Step 6: Verify in-game**

`/reload` — open Settings → Party page. Pet toggle should be in the preview header. Toggle ON — small pet frames should appear below each party member. Toggle OFF — pet frames should disappear. Change PartyPets settings (spacing, font size) — pet frames should update.

- [ ] **Step 7: Commit**

```bash
git add Settings/Builders/FramePreview.lua
git commit -m "feat: add party pet toggle with per-member pet frames"
```

---

## Task 10: PositionAndLayout card split

**Files:**
- Modify: `Settings/Cards/PositionAndLayout.lua`

- [ ] **Step 1: Read the existing PositionAndLayout card**

Read `Settings/Cards/PositionAndLayout.lua` fully. Identify:
- Where x/y offset sliders are created
- Where anchor picker is created
- Where width/height sliders are created
- Where group-only controls (orientation, spacing, unitsPerColumn, maxColumns) are created

- [ ] **Step 2: Add a `pinnedMode` parameter**

Modify the function signature to accept an optional `pinnedMode` parameter:

```lua
function F.SettingsCards.PositionAndLayout(parent, width, unitType, getConfig, setConfig, onResize, pinnedMode)
```

When `pinnedMode` is true:
- Width/height sliders render normally (active)
- Group layout controls (orientation, spacing, unitsPerColumn, maxColumns) render normally (active)
- X/Y/anchor controls render at reduced opacity with non-interactive state

- [ ] **Step 3: Grey out position controls when `pinnedMode` is true**

After creating the x offset slider, y offset slider, and anchor picker, wrap them in a grey-out block:

```lua
if(pinnedMode) then
	-- Grey out position controls
	local greyGroup = { xOffSlider, yOffSlider, anchorPicker }
	for _, widget in next, greyGroup do
		widget:SetAlpha(0.35)
		widget:EnableMouse(false)
	end
end
```

Note: the exact variable names for the x/y/anchor widgets depend on what the existing code calls them. Read the file first and use the actual variable names.

- [ ] **Step 4: Add Edit Mode link when `pinnedMode` is true**

After the greyed-out controls, add:

```lua
if(pinnedMode) then
	local editModeLink = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSubtle)
	editModeLink:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cy)
	editModeLink:SetText('Edit Mode →')
	cy = cy - C.Font.sizeSmall - 4

	local clickFrame = CreateFrame('Button', nil, inner)
	clickFrame:SetAllPoints(editModeLink)
	clickFrame:SetScript('OnClick', function()
		if(F.EditMode and F.EditMode.Toggle) then
			F.EditMode.Toggle()
		end
	end)
	clickFrame:SetScript('OnEnter', function(self)
		editModeLink:SetTextColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
	end)
	clickFrame:SetScript('OnLeave', function(self)
		editModeLink:SetTextColor(C.Colors.textSubtle[1], C.Colors.textSubtle[2], C.Colors.textSubtle[3], 1)
	end)
end
```

Note: Check `C.Colors` for the actual accent color field name. Use `C.Colors.textActive` if `accent` doesn't exist.

- [ ] **Step 5: Verify in-game**

`/reload` — for now the card still renders in the CardGrid (not pinned yet). Verify it renders correctly with `pinnedMode = nil` (default, non-pinned behavior). The wrapper grid migration in Task 11 will pass `pinnedMode = true`.

- [ ] **Step 6: Commit**

```bash
git add Settings/Cards/PositionAndLayout.lua
git commit -m "feat: add pinnedMode to PositionAndLayout with greyed-out position controls"
```

---

## Task 11: Wrapper-grid migration

**Files:**
- Modify: `Settings/FrameSettingsBuilder.lua`

This is the largest single task. It replaces the CardGrid-first layout with a wrapper-grid pinned row (Preview | PositionAndLayout) and a scroll region below for the remaining cards.

- [ ] **Step 1: Read `Settings/FrameSettingsBuilder.lua` fully**

Understand the current flow:
- Scroll frame creation
- Content frame setup
- CardGrid creation and card registration
- How cards are added and laid out
- Panel return value

Also read how the aura panel layout refactor implemented the wrapper-grid pattern. Check `Settings/Panels/Buffs.lua` for the Phase 3/4 pattern if it's been implemented.

- [ ] **Step 2: Replace CardGrid with wrapper-grid structure**

The new structure inside `FrameSettingsBuilder.Create`:

```
scroll frame
  └── content frame
       ├── pinnedRow (Frame)
       │    ├── previewCard (left, natural width)
       │    └── positionCard (right, fills remaining width)
       └── scrollCards (Frame, below pinnedRow)
            └── CardGrid (all remaining cards)
```

Create the pinned row container:

```lua
local pinnedRow = CreateFrame('Frame', nil, content)
pinnedRow:SetPoint('TOPLEFT', content, 'TOPLEFT', 0, 0)
pinnedRow:SetPoint('RIGHT', content, 'RIGHT', 0, 0)
```

Build the preview card into the left side:

```lua
local previewCard = F.Settings.FramePreview.BuildPreviewCard(pinnedRow, nil, unitType)
previewCard:SetPoint('TOPLEFT', pinnedRow, 'TOPLEFT', 0, 0)
```

Build the PositionAndLayout card into the right side with `pinnedMode = true`:

```lua
local posCard = F.SettingsCards.PositionAndLayout(pinnedRow, nil, unitType, getConfig, setConfig, relayout, true)
posCard:SetPoint('TOPLEFT', previewCard, 'TOPRIGHT', 8, 0)
posCard:SetPoint('RIGHT', pinnedRow, 'RIGHT', 0, 0)
```

Stretch both cards to match the taller one:

```lua
pinnedRow:SetScript('OnSizeChanged', function(self)
	local previewH = previewCard:GetHeight()
	local posH = posCard:GetHeight()
	local maxH = math.max(previewH, posH)
	self:SetHeight(maxH)
	previewCard:SetHeight(maxH)
	posCard:SetHeight(maxH)
end)
```

Place the CardGrid below the pinned row:

```lua
local grid = Widgets.CreateCardGrid(content, width)
grid:SetPoint('TOPLEFT', pinnedRow, 'BOTTOMLEFT', 0, -8)
```

- [ ] **Step 3: Remove PositionAndLayout from the CardGrid**

Find the `grid:AddCard('position', ...)` call and remove it — PositionAndLayout is now in the pinned row, not the grid.

- [ ] **Step 4: Wire teardown**

Ensure `OnHide` calls both `F.Settings.FramePreview.Destroy()` and cleans up the position card.

- [ ] **Step 5: Verify in-game**

`/reload` — open Settings → Player page. Preview should be pinned top-left, PositionAndLayout pinned top-right with greyed-out x/y/anchor. Settings cards should scroll below. Click "Edit Mode →" link — should toggle Edit Mode. Test on Party, Raid, Boss, Target pages.

- [ ] **Step 6: Commit**

```bash
git add Settings/FrameSettingsBuilder.lua
git commit -m "feat: migrate Frame pages to wrapper-grid pinned row layout"
```

---

## Task 12: Reflow animations

**Files:**
- Modify: `Settings/Builders/FramePreview.lua`

- [ ] **Step 1: Animate preview card resize on structural changes**

In `RebuildPreview`, instead of directly setting viewport size, animate the transition:

```lua
local function AnimateViewportResize(viewport, card, targetW, targetH)
	local currentW = viewport:GetWidth()
	local currentH = viewport:GetHeight()

	if(math.abs(currentW - targetW) < 1 and math.abs(currentH - targetH) < 1) then
		viewport:SetSize(targetW, targetH)
		return
	end

	Widgets.StartAnimation(viewport, 'previewResize', 0, 1, 0.3,
		function(f, t)
			local w = currentW + (targetW - currentW) * t
			local h = currentH + (targetH - currentH) * t
			f:SetSize(w, h)
		end,
		function(f)
			f:SetSize(targetW, targetH)
		end
	)
end
```

- [ ] **Step 2: Animate group frame repositioning on layout changes**

In `RenderGroupPreview`, when frames already exist at old positions, animate to new positions:

```lua
for i = 1, count do
	-- ...existing frame setup...

	local pos = positions[i]
	if(frame._lastX and frame._lastY) then
		-- Animate from old position to new
		local fromX, fromY = frame._lastX, frame._lastY
		Widgets.StartAnimation(frame, 'reposition', 0, 1, 0.3,
			function(f, t)
				f:ClearAllPoints()
				f:SetPoint('TOPLEFT', viewport, 'TOPLEFT',
					fromX + (pos.x - fromX) * t,
					fromY + (pos.y - fromY) * t)
			end,
			function(f)
				f:ClearAllPoints()
				f:SetPoint('TOPLEFT', viewport, 'TOPLEFT', pos.x, pos.y)
			end
		)
	else
		frame:ClearAllPoints()
		frame:SetPoint('TOPLEFT', viewport, 'TOPLEFT', pos.x, pos.y)
	end

	frame._lastX = pos.x
	frame._lastY = pos.y
end
```

- [ ] **Step 3: Verify in-game**

`/reload` — open Settings → Raid page. Change orientation dropdown — frames should animate to new positions smoothly. Change units-per-column — reflow should animate. Change stepper count — new frames should appear smoothly.

- [ ] **Step 4: Commit**

```bash
git add Settings/Builders/FramePreview.lua
git commit -m "feat: add animated reflow for preview resize and group repositioning"
```

---

## Task 13: Focus mode toggle

**Files:**
- Modify: `Settings/Builders/FramePreview.lua`
- Modify: `Settings/FrameSettingsBuilder.lua`

- [ ] **Step 1: Add focus mode state and element-to-card mapping**

In `FramePreview.lua`, add after the state variables:

```lua
local focusModeEnabled = false
local focusedCardId = nil

local CARD_ELEMENT_MAP = {
	healthColor      = { '_healthBar', '_healthBar._bg', '_portrait', '_portraitTex' },
	healthText       = { '_healthText' },
	powerBar         = { '_powerBar', '_powerWrapper' },
	powerText        = { '_powerText' },
	name             = { '_nameText' },
	castBar          = { '_castbar' },
	statusIcons      = { '_iconOverlay' },
	statusText       = { '_statusText', '_statusTextOverlay' },
	shieldsAbsorbs   = { '_healPredBar', '_damageAbsorbBar', '_healAbsorbBar', '_overAbsorbGlow' },
	partyPets        = {},  -- handled separately via petFrames
}
```

- [ ] **Step 2: Add dimming/spotlight functions**

```lua
local function SetElementAlpha(frame, keys, alpha)
	for _, key in next, keys do
		-- Handle nested keys like '_healthBar._bg'
		local obj = frame
		for part in key:gmatch('[^%.]+') do
			obj = obj and obj[part]
		end
		if(obj and obj.SetAlpha) then
			obj:SetAlpha(alpha)
		end
	end
end

local function ApplyFocusMode(cardId)
	focusedCardId = cardId

	for _, frame in next, previewFrames do
		-- Dim all elements
		for _, keys in next, CARD_ELEMENT_MAP do
			SetElementAlpha(frame, keys, 0.2)
		end

		-- Spotlight the focused card's elements
		if(cardId and CARD_ELEMENT_MAP[cardId]) then
			SetElementAlpha(frame, CARD_ELEMENT_MAP[cardId], 1.0)
		end
	end

	-- Handle pet frames
	local petAlpha = (cardId == 'partyPets') and 1.0 or 0.2
	for _, petFrame in next, petFrames do
		petFrame:SetAlpha(petAlpha)
	end
end

local function ClearFocusMode()
	focusedCardId = nil
	for _, frame in next, previewFrames do
		for _, keys in next, CARD_ELEMENT_MAP do
			SetElementAlpha(frame, keys, 1.0)
		end
	end
	for _, petFrame in next, petFrames do
		petFrame:SetAlpha(1.0)
	end
end

function FP.OnCardFocused(cardId)
	if(not focusModeEnabled) then return end
	ApplyFocusMode(cardId)
end
```

- [ ] **Step 3: Add focus mode toggle to preview header**

In `BuildPreviewCard`, add the toggle after the title:

```lua
local focusToggle = Widgets.CreateCheckButton(inner, 'Focus Mode', function(checked)
	focusModeEnabled = checked
	if(checked) then
		-- Auto-select first card
		ApplyFocusMode('healthColor')
		-- Notify FrameSettingsBuilder to highlight the first card
		if(card._onFocusChanged) then
			card._onFocusChanged('healthColor')
		end
	else
		ClearFocusMode()
		if(card._onFocusChanged) then
			card._onFocusChanged(nil)
		end
	end
end)
focusToggle:SetChecked(false)
```

- [ ] **Step 4: Wire card click handlers in FrameSettingsBuilder**

In `Settings/FrameSettingsBuilder.lua`, after adding cards to the grid, wire click handlers on each card's header area. For each card registered via `grid:AddCard(id, title, builder, params)`, add a click handler:

```lua
-- After grid setup, iterate registered cards and add click-to-focus
local cardIds = { 'healthColor', 'healthText', 'powerBar', 'powerText', 'name', 'castBar', 'statusIcons', 'statusText', 'shieldsAbsorbs', 'sorting', 'partyPets' }

for _, cardId in next, cardIds do
	local cardFrame = grid:GetCard(cardId)
	if(cardFrame) then
		local clickOverlay = CreateFrame('Button', nil, cardFrame)
		clickOverlay:SetPoint('TOPLEFT', cardFrame, 'TOPLEFT', 0, 0)
		clickOverlay:SetPoint('TOPRIGHT', cardFrame, 'TOPRIGHT', 0, 0)
		clickOverlay:SetHeight(24) -- header area only
		clickOverlay:SetScript('OnClick', function()
			F.Settings.FramePreview.OnCardFocused(cardId)
		end)
	end
end
```

Note: Check if `grid:GetCard(id)` exists. If not, the card references need to be stored during `AddCard` and accessed via a different pattern. Read the CardGrid implementation first.

- [ ] **Step 5: Add selected card visual (left accent bar)**

In `OnCardFocused`, add/move an accent bar on the focused card:

```lua
-- Store a reusable accent indicator
local focusAccent = nil

local function ShowFocusAccent(cardFrame)
	if(not focusAccent) then
		focusAccent = CreateFrame('Frame', nil, UIParent)
		focusAccent:SetWidth(3)
		local tex = focusAccent:CreateTexture(nil, 'OVERLAY')
		tex:SetAllPoints(focusAccent)
		tex:SetColorTexture(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
	end
	focusAccent:SetParent(cardFrame)
	focusAccent:ClearAllPoints()
	focusAccent:SetPoint('TOPLEFT', cardFrame, 'TOPLEFT', 0, 0)
	focusAccent:SetPoint('BOTTOMLEFT', cardFrame, 'BOTTOMLEFT', 0, 0)
	focusAccent:Show()
end
```

- [ ] **Step 6: Clean up focus state in Destroy**

In `FP.Destroy()`, add:

```lua
focusModeEnabled = false
focusedCardId = nil
if(focusAccent) then
	focusAccent:Hide()
	focusAccent:SetParent(nil)
end
```

- [ ] **Step 7: Verify in-game**

`/reload` — open Settings → Player page. Toggle Focus Mode ON — HealthColor card should auto-select, preview should dim everything except health bar + portrait. Click different card headers — spotlight should shift. Toggle OFF — all elements full opacity.

- [ ] **Step 8: Commit**

```bash
git add Settings/Builders/FramePreview.lua Settings/FrameSettingsBuilder.lua
git commit -m "feat: add Focus Mode toggle with click-to-focus card spotlighting"
```

---

## Task 14: Final integration and polish

**Files:**
- All modified files

- [ ] **Step 1: Verify all frame types**

`/reload` — systematically test each Settings page:
- Player: solo preview, all elements visible, Focus Mode works
- Target: solo preview
- Target of Target: solo preview
- Focus: solo preview
- Pet: solo preview
- Boss: 4 frames in vertical stack
- Party: 5 frames, pet toggle, Focus Mode
- Raid: 8 frames default, stepper works 1–40, layout reflows

- [ ] **Step 2: Verify live updates across all pages**

On each page, change:
- Health text format → preview updates
- Width slider → preview resizes
- Health color → preview recolors
- Power bar enable/disable → preview rebuilds
- Preset switch → full rebuild

- [ ] **Step 3: Verify animations**

- Orientation change → frames animate to new positions
- Width/height slider drag → smooth per-tick resize
- Raid stepper → frames fade in/out, viewport animates
- Preview card → resizes smoothly

- [ ] **Step 4: Verify teardown and memory**

- Navigate away from frame page → no errors
- Navigate back → preview rebuilds cleanly
- Rapid page switching → no frame leaks
- Close Settings → full cleanup

- [ ] **Step 5: Commit final state**

```bash
git add -A
git commit -m "feat: Frame Preview Card — complete implementation with all frame types"
```

- [ ] **Step 6: Push**

```bash
git push origin working-testing
```
