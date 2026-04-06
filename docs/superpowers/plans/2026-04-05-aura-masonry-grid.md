# Aura Settings Masonry Grid — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the vertical scroll-based aura settings panels with responsive masonry card grids, add a mini live preview to the sub-header, and extract indicator settings into reusable card builders.

**Architecture:** A pinned flex row (Create + List) sits above a CardGrid for Buffs/Debuffs pages. Clicking Edit spawns per-indicator settings cards into the grid. Simpler aura pages get their own CardGrid with settings cards. A mini preview in the sub-header uses PreviewIndicators renderers with dimming and animation. All config wiring is unchanged — card builders receive `get`/`set` closures.

**Tech Stack:** WoW Frame API, Widgets.CardGrid, Widgets.StartCard/EndCard, PreviewIndicators renderers, EventBus.

**Design Spec:** `docs/superpowers/specs/2026-04-05-aura-masonry-grid-design.md`

---

## Hard Constraints

Read these before every task:

1. **Do NOT modify** `Config.lua`, `EditCache.lua`, `EventBus` event contracts, `StyleBuilder.lua`, `LiveUpdate.lua`, or any Element file except `Dispellable.lua` (for highlightAlpha).
2. **Do NOT modify** any file in `Preview/` — the edit mode preview is independent.
3. **Card builders receive `get`/`set` closures** — never import Config directly or construct config paths.
4. **Event listeners must be cleaned up** when panels are destroyed (page switch, unit type change, settings close).
5. **`setIndicator()`/`getIndicator()` closures** capture preset + unit type in their scope — pass them through unchanged.
6. **Import popup** stays as a singleton modal — triggered from Tracked Spells card, calls `setIndicator()` unchanged.
7. **SavedVariables** — only new key is `dispellable.highlightAlpha`. No existing keys renamed or removed.
8. **Follow existing code style** — tabs, parenthesized conditions, single quotes, `for _, v in next, tbl do`, camelCase locals, PascalCase element functions.

---

## Phased Approach

| Phase | Description | Depends On | Checkpoint |
|-------|------------|------------|------------|
| **1** | Add RemoveCard to CardGrid | Nothing | Cards can be dynamically added/removed |
| **2** | Extract indicator card builders | Nothing | Builders exist as standalone functions |
| **3** | AuraPreview widget | Nothing | Preview renders in isolation |
| **4** | Framework changes | Phase 3 | Preview shows/hides on panel switch |
| **5** | Buffs panel (template) | Phase 1, 2, 4 | Buffs page fully working with grid |
| **6** | Debuffs panel | Phase 5 | Debuffs page working |
| **7** | Simpler aura panels | Phase 1, 4 | All 9 simpler pages working |
| **8** | highlightAlpha config | Nothing | Dispellable reads from config |
| **9** | Sync + test pass | All phases | Full in-game verification |

---

## Phase 1: Add RemoveCard to CardGrid

### Task 1: Add RemoveCard and RemoveAllCards methods

**Files:**
- Modify: `Widgets/CardGrid.lua:292-306` (after AddCard)

CardGrid currently has no way to remove cards. The indicator editing flow needs to spawn settings cards on Edit and destroy them on Close/Switch. Add two methods.

- [ ] **Step 1: Add RemoveCard method**

Add after the `AddCard` function (after line 306 in `Widgets/CardGrid.lua`):

```lua
local function RemoveCard(grid, id)
	local entry = grid._cardIndex[id]
	if(not entry) then return end

	-- Destroy the built frame
	if(entry.card) then
		entry.card:Hide()
		entry.card:SetParent(nil)
	end

	-- Remove from ordered array
	for i = #grid._cards, 1, -1 do
		if(grid._cards[i].id == id) then
			table.remove(grid._cards, i)
			break
		end
	end

	grid._cardIndex[id] = nil
end
```

- [ ] **Step 2: Add RemoveAllCards method**

Add immediately after RemoveCard:

```lua
local function RemoveAllCards(grid)
	for i = #grid._cards, 1, -1 do
		local entry = grid._cards[i]
		if(entry.card) then
			entry.card:Hide()
			entry.card:SetParent(nil)
		end
		grid._cardIndex[entry.id] = nil
		grid._cards[i] = nil
	end
end
```

- [ ] **Step 3: Expose on the grid object**

Find the grid method assignment block (around lines 437-446) and add:

```lua
grid.RemoveCard     = RemoveCard
grid.RemoveAllCards = RemoveAllCards
```

- [ ] **Step 4: Commit**

```bash
git add Widgets/CardGrid.lua
git commit -m "feat: add RemoveCard and RemoveAllCards to CardGrid widget"
```

---

## Phase 2: Extract Indicator Card Builders

### Task 2A: Create IndicatorCardBuilders.lua with Cast By and Tracked Spells

**Files:**
- Create: `Settings/Builders/IndicatorCardBuilders.lua`
- Reference: `Settings/Builders/IndicatorPanels.lua:246-314` (Cast By + Tracked Spells)
- Reference: `Settings/Builders/IndicatorCRUD.lua:56-72` (setIndicator wiring)

Extract the Cast By card and Tracked Spells card from `BuildIndicatorSettings()` into standalone card builder functions compatible with `CardGrid:AddCard()`.

Card builders must follow the pattern used by unit frame cards (see `Settings/Cards/PositionAndLayout.lua`): receive `(parent, width, ...args)`, return the card frame from `Widgets.EndCard()`.

- [ ] **Step 1: Create file with Cast By card builder**

Create `Settings/Builders/IndicatorCardBuilders.lua`:

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local Settings = F.Settings

-- Shared layout constants (match IndicatorPanels.lua)
local WIDGET_W    = 200
local DROPDOWN_H  = 30
local SLIDER_H    = 36
local CHECK_H     = 22
local BUTTON_H    = 28

local function placeWidget(widget, parent, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.tight
end

local function placeHeading(parent, text, level, yOffset)
	local fs = Widgets.CreateFontString(parent, level == 2 and C.Font.sizeSmall or C.Font.sizeNormal, C.Colors.textSecondary)
	fs:SetText(text)
	fs:ClearAllPoints()
	Widgets.SetPoint(fs, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	return yOffset - (level == 2 and C.Font.sizeSmall or C.Font.sizeNormal) - C.Spacing.tight
end

-- ============================================================
-- Card Builders
-- Each follows the CardGrid builder signature:
--   function(parent, width, data, update, get, set, rebuildPanel)
-- Returns: card frame (from EndCard)
-- ============================================================

local Builders = {}
F.Settings.IndicatorCardBuilders = Builders

-- ── Cast By ─────────────────────────────────────────────────
function Builders.CastBy(parent, width, data, update)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local castByDD = Widgets.CreateDropdown(inner, WIDGET_W)
	castByDD:SetItems({
		{ text = 'Me',      value = C.CastFilter.ME },
		{ text = 'Others',  value = C.CastFilter.OTHERS },
		{ text = 'Anyone',  value = C.CastFilter.ANYONE },
	})
	castByDD:SetValue(data.castBy or C.CastFilter.ME)
	castByDD:SetOnSelect(function(value) update('castBy', value) end)
	cardY = placeWidget(castByDD, inner, cardY, DROPDOWN_H)

	return Widgets.EndCard(card, parent, cardY)
end
```

- [ ] **Step 2: Add Tracked Spells card builder**

Append to `IndicatorCardBuilders.lua`. This includes the spell list, spell input, import button, delete all button, and optional per-spell color pickers. Reference `IndicatorPanels.lua:263-314`.

```lua
-- ── Tracked Spells ──────────────────────────────────────────
function Builders.TrackedSpells(parent, width, data, update, rebuildPanel)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local spList = Widgets.CreateSpellList(inner, width - 24, nil)
	spList:SetSpells(data.spells or {})
	spList:SetOnChanged(function(spells)
		update('spells', spells)
		if(spList._showColorPicker) then
			update('spellColors', spList:GetSpellColors())
		end
	end)

	-- Show per-spell color pickers for colored square and bar types
	if(data.displayType == C.IconDisplay.COLORED_SQUARE
		or data.type == C.IndicatorType.BAR
		or data.type == C.IndicatorType.BARS) then
		spList:SetSpellColors(data.spellColors or {})
		spList:SetShowColorPicker(true)
	end

	-- Calculate spell list height based on spell count
	local spellCount = data.spells and #data.spells or 0
	local spListH = math.max(60, spellCount * 24 + 8)
	cardY = placeWidget(spList, inner, cardY, spListH)

	local spInput = Widgets.CreateSpellInput(inner, width - 24)
	cardY = placeWidget(spInput, inner, cardY, 50)
	spInput:SetSpellList(spList)
	spInput:SetOnAdd(function() update('spells', spList:GetSpells()) end)

	local btnRow = CreateFrame('Frame', nil, inner)
	btnRow:SetHeight(24)
	Widgets.SetPoint(btnRow, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
	btnRow:SetWidth(width - 24)

	local importBtn = Widgets.CreateButton(btnRow, 'Import Healer Spells', 'widget', 160, 24)
	Widgets.SetPoint(importBtn, 'TOPLEFT', btnRow, 'TOPLEFT', 0, 0)
	importBtn:SetOnClick(function()
		F.Settings.Builders.ShowImportPopup(function(selectedSpells)
			if(not selectedSpells or #selectedSpells == 0) then return end
			local existing = spList:GetSpells()
			for _, spellID in next, selectedSpells do
				existing[#existing + 1] = spellID
			end
			spList:SetSpells(existing)
			update('spells', existing)
		end)
	end)

	local deleteAllBtn = Widgets.CreateButton(btnRow, 'Delete All Spells', 'red', 140, 24)
	deleteAllBtn:SetPoint('LEFT', importBtn, 'RIGHT', C.Spacing.tight, 0)
	deleteAllBtn:SetOnClick(function()
		Widgets.ShowConfirmDialog('Delete All Spells', 'Remove all tracked spells from this indicator?', function()
			spList:SetSpells({})
			update('spells', {})
		end)
	end)

	cardY = cardY - 24 - C.Spacing.tight

	return Widgets.EndCard(card, parent, cardY)
end
```

- [ ] **Step 3: Commit**

```bash
git add Settings/Builders/IndicatorCardBuilders.lua
git commit -m "feat: extract Cast By and Tracked Spells indicator card builders"
```

### Task 2B: Add Appearance, Cooldown & Duration, and Stacks card builders

**Files:**
- Modify: `Settings/Builders/IndicatorCardBuilders.lua`
- Reference: `Settings/Builders/IndicatorPanels.lua:320-576` (Appearance, Cooldown & Duration, Stacks)

- [ ] **Step 1: Add Appearance card builder (Icon/Icons only)**

Reference `IndicatorPanels.lua:320-355`. Append to `IndicatorCardBuilders.lua`:

```lua
-- ── Appearance (Icon/Icons) ─────────────────────────────────
function Builders.Appearance(parent, width, data, update, rebuildPanel)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local dtLabel = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	dtLabel:SetText('Display Type')
	cardY = placeWidget(dtLabel, inner, cardY, C.Font.sizeSmall)

	local dtSwitch = Widgets.CreateSwitch(inner, WIDGET_W, BUTTON_H, {
		{ text = 'Spell Icons',    value = C.IconDisplay.SPELL_ICON },
		{ text = 'Color Squares',  value = C.IconDisplay.COLORED_SQUARE },
	})
	dtSwitch:SetValue(data.displayType or C.IconDisplay.SPELL_ICON)
	dtSwitch:SetOnSelect(function(v)
		update('displayType', v)
		-- Rebuild panel to update spell list color pickers
		if(rebuildPanel) then rebuildPanel() end
	end)
	cardY = placeWidget(dtSwitch, inner, cardY, BUTTON_H)

	local wSlider = Widgets.CreateSlider(inner, 'Width', WIDGET_W, 3, 48, 1)
	wSlider:SetValue(data.iconWidth or 16)
	wSlider:SetAfterValueChanged(function(v) update('iconWidth', v) end)
	cardY = placeWidget(wSlider, inner, cardY, SLIDER_H)

	local hSlider = Widgets.CreateSlider(inner, 'Height', WIDGET_W, 3, 48, 1)
	hSlider:SetValue(data.iconHeight or 16)
	hSlider:SetAfterValueChanged(function(v) update('iconHeight', v) end)
	cardY = placeWidget(hSlider, inner, cardY, SLIDER_H)

	return Widgets.EndCard(card, parent, cardY)
end
```

- [ ] **Step 2: Add Layout card builder (Icons/Bars multi-type)**

Reference `IndicatorPanels.lua:357-422` (Icons) and `609-665` (Bars). This card covers anchor, frame level, grow direction, max displayed, num per line, spacing — shared across Icons and Bars types with conditional fields.

```lua
-- ── Layout (Icons, Bars — multi-element types) ──────────────
-- Also used as Position for single-element types (Icon, Bar, Rectangle)
function Builders.Layout(parent, width, data, update, get, set)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local iType = data.type

	-- Anchor picker
	if(Widgets.CreateAnchorPicker) then
		local anchor = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
		local picker = Widgets.CreateAnchorPicker(inner, WIDGET_W, 50)
		picker:SetAnchor(anchor[1] or 'CENTER', anchor[4] or 0, anchor[5] or 0)
		picker:SetOnChanged(function(point, x, y)
			local a = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
			a[1] = point
			a[3] = point
			a[4] = x
			a[5] = y
			set('anchor', a)
		end)
		cardY = placeWidget(picker, inner, cardY, picker._height or 91)
	end

	-- Frame level
	local flSlider = Widgets.CreateSlider(inner, 'Frame Level', WIDGET_W, 1, 50, 1)
	flSlider:SetValue(get('frameLevel') or 5)
	flSlider:SetAfterValueChanged(function(val) set('frameLevel', val) end)
	cardY = placeWidget(flSlider, inner, cardY, SLIDER_H)

	-- Multi-element fields (Icons, Bars)
	if(iType == C.IndicatorType.ICONS or iType == C.IndicatorType.BARS) then
		-- Grow direction
		local anchorData = data.anchor or { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 }
		local anchorH = anchorData[3] or 'TOPLEFT'
		local defaultGrow = (anchorH == 'TOPRIGHT' or anchorH == 'RIGHT' or anchorH == 'BOTTOMRIGHT') and 'LEFT' or 'RIGHT'
		local effectiveGrow = data.orientation or defaultGrow

		local growLabel = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
		growLabel:SetText('Grow Direction')
		cardY = placeWidget(growLabel, inner, cardY, C.Font.sizeSmall)

		local ORIENTATION_ITEMS = {
			{ text = 'Right', value = 'RIGHT' },
			{ text = 'Left',  value = 'LEFT' },
			{ text = 'Up',    value = 'UP' },
			{ text = 'Down',  value = 'DOWN' },
		}

		local oriDD = Widgets.CreateDropdown(inner, WIDGET_W)
		oriDD:SetItems(ORIENTATION_ITEMS)
		oriDD:SetValue(effectiveGrow)
		oriDD:SetOnSelect(function(v) update('orientation', v) end)
		cardY = placeWidget(oriDD, inner, cardY, DROPDOWN_H)

		local mxSlider = Widgets.CreateSlider(inner, 'Max Displayed', WIDGET_W, 1, 10, 1)
		mxSlider:SetValue(data.maxDisplayed or 3)
		mxSlider:SetAfterValueChanged(function(v) update('maxDisplayed', v) end)
		cardY = placeWidget(mxSlider, inner, cardY, SLIDER_H)

		local nplSlider = Widgets.CreateSlider(inner, 'Num Per Line', WIDGET_W, 0, 10, 1)
		nplSlider:SetValue(data.numPerLine or 0)
		nplSlider:SetAfterValueChanged(function(v) update('numPerLine', v) end)
		cardY = placeWidget(nplSlider, inner, cardY, SLIDER_H)

		local spxSlider = Widgets.CreateSlider(inner, 'Spacing X', WIDGET_W, -20, 20, 1)
		spxSlider:SetValue(data.spacingX or 2)
		spxSlider:SetAfterValueChanged(function(v) update('spacingX', v) end)
		cardY = placeWidget(spxSlider, inner, cardY, SLIDER_H)

		local spySlider = Widgets.CreateSlider(inner, 'Spacing Y', WIDGET_W, -20, 20, 1)
		spySlider:SetValue(data.spacingY or 2)
		spySlider:SetAfterValueChanged(function(v) update('spacingY', v) end)
		cardY = placeWidget(spySlider, inner, cardY, SLIDER_H)
	end

	return Widgets.EndCard(card, parent, cardY)
end
```

- [ ] **Step 3: Add Cooldown & Duration card builder**

Reference `IndicatorPanels.lua:425-520`. Includes cooldown toggle, duration mode, duration font settings with anchor/size/outline/shadow, color progression.

```lua
-- ── Cooldown & Duration (Icon/Icons) ────────────────────────
function Builders.CooldownDuration(parent, width, data, update, get, set)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local cdSwitch = Widgets.CreateCheckButton(inner, 'Show Cooldown', function(checked)
		update('showCooldown', checked)
	end)
	cdSwitch:SetChecked(data.showCooldown ~= false)
	cardY = placeWidget(cdSwitch, inner, cardY, CHECK_H)

	local durModeLabel = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	durModeLabel:SetText('Duration Text')
	cardY = placeWidget(durModeLabel, inner, cardY, C.Font.sizeSmall)

	local DURATION_MODE_ITEMS = {
		{ text = 'Never',   value = 'Never' },
		{ text = 'Always',  value = 'Always' },
		{ text = '< 75%',   value = '<75%' },
		{ text = '< 50%',   value = '<50%' },
		{ text = '< 25%',   value = '<25%' },
		{ text = '< 15s',   value = '<15s' },
		{ text = '< 5s',    value = '<5s' },
	}

	local durDD = Widgets.CreateDropdown(inner, WIDGET_W)
	durDD:SetItems(DURATION_MODE_ITEMS)
	durDD:SetValue(data.durationMode or 'Never')
	durDD:SetOnSelect(function(v) update('durationMode', v) end)
	cardY = placeWidget(durDD, inner, cardY, DROPDOWN_H)

	-- Duration font settings
	local fontCfg = get('durationFont') or {}

	if(Widgets.CreateAnchorPicker) then
		local dfAnchor = fontCfg.anchor or 'BOTTOM'
		local dfPicker = Widgets.CreateAnchorPicker(inner, WIDGET_W, 15)
		dfPicker:SetAnchor(dfAnchor, fontCfg.xOffset or 0, fontCfg.yOffset or 0)
		dfPicker:SetOnChanged(function(point, x, y)
			fontCfg.anchor = point
			fontCfg.xOffset = x
			fontCfg.yOffset = y
			set('durationFont', fontCfg)
		end)
		cardY = placeWidget(dfPicker, inner, cardY, dfPicker._height or 91)
	end

	local dfSizeSlider = Widgets.CreateSlider(inner, 'Font Size', WIDGET_W, 6, 24, 1)
	dfSizeSlider:SetValue(fontCfg.size or C.Font.sizeSmall)
	dfSizeSlider:SetAfterValueChanged(function(val)
		fontCfg.size = val
		set('durationFont', fontCfg)
	end)
	cardY = placeWidget(dfSizeSlider, inner, cardY, SLIDER_H)

	local dfOutlineDD = Widgets.CreateDropdown(inner, WIDGET_W)
	dfOutlineDD:SetItems({
		{ text = 'None',    value = '' },
		{ text = 'Outline', value = 'OUTLINE' },
		{ text = 'Mono',    value = 'MONOCHROME' },
	})
	dfOutlineDD:SetValue(fontCfg.outline or '')
	dfOutlineDD:SetOnSelect(function(value)
		fontCfg.outline = value
		set('durationFont', fontCfg)
	end)
	cardY = placeWidget(dfOutlineDD, inner, cardY, DROPDOWN_H)

	local dfShadowCB = Widgets.CreateCheckButton(inner, 'Shadow', function(checked)
		fontCfg.shadow = checked
		set('durationFont', fontCfg)
	end)
	dfShadowCB:SetChecked(fontCfg.shadow or false)
	cardY = placeWidget(dfShadowCB, inner, cardY, CHECK_H)

	local cpCB = Widgets.CreateCheckButton(inner, 'Color Progression', function(checked)
		fontCfg.colorProgression = checked
		set('durationFont', fontCfg)
	end)
	cpCB:SetChecked(fontCfg.colorProgression or false)
	cardY = placeWidget(cpCB, inner, cardY, CHECK_H)

	local startC = fontCfg.progressionStart or { 0, 1, 0 }
	local startPicker = Widgets.CreateColorPicker(inner, 'Full Duration', false, function(r, g, b)
		fontCfg.progressionStart = { r, g, b }
		set('durationFont', fontCfg)
	end)
	startPicker:SetColor(startC[1], startC[2], startC[3], 1)
	cardY = placeWidget(startPicker, inner, cardY, DROPDOWN_H)

	local midC = fontCfg.progressionMid or { 1, 1, 0 }
	local midPicker = Widgets.CreateColorPicker(inner, 'Half Duration', false, function(r, g, b)
		fontCfg.progressionMid = { r, g, b }
		set('durationFont', fontCfg)
	end)
	midPicker:SetColor(midC[1], midC[2], midC[3], 1)
	cardY = placeWidget(midPicker, inner, cardY, DROPDOWN_H)

	local endC = fontCfg.progressionEnd or { 1, 0, 0 }
	local endPicker = Widgets.CreateColorPicker(inner, 'Near Expiry', false, function(r, g, b)
		fontCfg.progressionEnd = { r, g, b }
		set('durationFont', fontCfg)
	end)
	endPicker:SetColor(endC[1], endC[2], endC[3], 1)
	cardY = placeWidget(endPicker, inner, cardY, DROPDOWN_H)

	return Widgets.EndCard(card, parent, cardY)
end
```

- [ ] **Step 4: Add Stacks card builder**

Reference `IndicatorPanels.lua:522-576`.

```lua
-- ── Stacks ──────────────────────────────────────────────────
function Builders.Stacks(parent, width, data, update, get, set)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local stSwitch = Widgets.CreateCheckButton(inner, 'Show Stacks', function(checked)
		update('showStacks', checked)
	end)
	stSwitch:SetChecked(data.showStacks == true)
	cardY = placeWidget(stSwitch, inner, cardY, CHECK_H)

	-- Stack font settings
	local sfCfg = get('stackFont') or {}

	if(Widgets.CreateAnchorPicker) then
		local sfAnchor = sfCfg.anchor or 'BOTTOMRIGHT'
		local sfPicker = Widgets.CreateAnchorPicker(inner, WIDGET_W, 15)
		sfPicker:SetAnchor(sfAnchor, sfCfg.offsetX or 0, sfCfg.offsetY or 0)
		sfPicker:SetOnChanged(function(point, x, y)
			sfCfg.anchor = point
			sfCfg.offsetX = x
			sfCfg.offsetY = y
			set('stackFont', sfCfg)
		end)
		cardY = placeWidget(sfPicker, inner, cardY, sfPicker._height or 91)
	end

	local sfSizeSlider = Widgets.CreateSlider(inner, 'Font Size', WIDGET_W, 6, 24, 1)
	sfSizeSlider:SetValue(sfCfg.size or C.Font.sizeSmall)
	sfSizeSlider:SetAfterValueChanged(function(val)
		sfCfg.size = val
		set('stackFont', sfCfg)
	end)
	cardY = placeWidget(sfSizeSlider, inner, cardY, SLIDER_H)

	local sfOutlineDD = Widgets.CreateDropdown(inner, WIDGET_W)
	sfOutlineDD:SetItems({
		{ text = 'None',    value = '' },
		{ text = 'Outline', value = 'OUTLINE' },
		{ text = 'Mono',    value = 'MONOCHROME' },
	})
	sfOutlineDD:SetValue(sfCfg.outline or '')
	sfOutlineDD:SetOnSelect(function(value)
		sfCfg.outline = value
		set('stackFont', sfCfg)
	end)
	cardY = placeWidget(sfOutlineDD, inner, cardY, DROPDOWN_H)

	local sfShadowCB = Widgets.CreateCheckButton(inner, 'Shadow', function(checked)
		sfCfg.shadow = checked
		set('stackFont', sfCfg)
	end)
	sfShadowCB:SetChecked(sfCfg.shadow or false)
	cardY = placeWidget(sfShadowCB, inner, cardY, CHECK_H)

	return Widgets.EndCard(card, parent, cardY)
end
```

- [ ] **Step 5: Commit**

```bash
git add Settings/Builders/IndicatorCardBuilders.lua
git commit -m "feat: add Appearance, Layout, CooldownDuration, and Stacks card builders"
```

### Task 2C: Add Size, Mode, and Border card builders

**Files:**
- Modify: `Settings/Builders/IndicatorCardBuilders.lua`
- Reference: `Settings/Builders/IndicatorPanels.lua:586-607` (Size), `745-800` (Mode), and Border type handling

- [ ] **Step 1: Add Size card builder (Bar/Bars/Rectangle)**

Reference `IndicatorPanels.lua:586-607`.

```lua
-- ── Size (Bar/Bars/Rectangle) ───────────────────────────────
function Builders.Size(parent, width, data, update)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local iType = data.type

	local BAR_ORIENTATION_ITEMS = {
		{ text = 'Horizontal', value = 'Horizontal' },
		{ text = 'Vertical',   value = 'Vertical' },
	}

	if(iType == C.IndicatorType.BAR or iType == C.IndicatorType.BARS) then
		local bwSlider = Widgets.CreateSlider(inner, 'Width', WIDGET_W, 3, 100, 1)
		bwSlider:SetValue(data.barWidth or 100)
		bwSlider:SetAfterValueChanged(function(v) update('barWidth', v) end)
		cardY = placeWidget(bwSlider, inner, cardY, SLIDER_H)

		local bhSlider = Widgets.CreateSlider(inner, 'Height', WIDGET_W, 3, 100, 1)
		bhSlider:SetValue(data.barHeight or 4)
		bhSlider:SetAfterValueChanged(function(v) update('barHeight', v) end)
		cardY = placeWidget(bhSlider, inner, cardY, SLIDER_H)

		local barOriDD = Widgets.CreateDropdown(inner, WIDGET_W)
		barOriDD:SetItems(BAR_ORIENTATION_ITEMS)
		barOriDD:SetValue(data.barOrientation or 'Horizontal')
		barOriDD:SetOnSelect(function(v) update('barOrientation', v) end)
		cardY = placeWidget(barOriDD, inner, cardY, DROPDOWN_H)

	elseif(iType == C.IndicatorType.RECTANGLE) then
		local rwSlider = Widgets.CreateSlider(inner, 'Width', WIDGET_W, 3, 500, 1)
		rwSlider:SetValue(data.rectWidth or 10)
		rwSlider:SetAfterValueChanged(function(v) update('rectWidth', v) end)
		cardY = placeWidget(rwSlider, inner, cardY, SLIDER_H)

		local rhSlider = Widgets.CreateSlider(inner, 'Height', WIDGET_W, 3, 500, 1)
		rhSlider:SetValue(data.rectHeight or 10)
		rhSlider:SetAfterValueChanged(function(v) update('rectHeight', v) end)
		cardY = placeWidget(rhSlider, inner, cardY, SLIDER_H)
	end

	return Widgets.EndCard(card, parent, cardY)
end
```

- [ ] **Step 2: Add Mode card builder (Overlay)**

Reference `IndicatorPanels.lua:745-800`.

```lua
-- ── Mode (Overlay) ──────────────────────────────────────────
function Builders.Mode(parent, width, data, update, get, set, rebuildPanel)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local modeDD = Widgets.CreateDropdown(inner, WIDGET_W)
	modeDD:SetItems({
		{ text = 'Duration Overlay', value = 'DurationOverlay' },
		{ text = 'Color',            value = 'Color' },
		{ text = 'Both',             value = 'Both' },
	})
	modeDD:SetValue(data.overlayMode or 'DurationOverlay')
	modeDD:SetOnSelect(function(v)
		update('overlayMode', v)
		if(rebuildPanel) then rebuildPanel() end
	end)
	cardY = placeWidget(modeDD, inner, cardY, DROPDOWN_H)

	local ovColor = data.color or { 0, 0, 0, 0.6 }
	local colorPicker = Widgets.CreateColorPicker(inner, 'Color', true, function(r, g, b, a)
		update('color', { r, g, b, a })
	end)
	colorPicker:SetColor(ovColor[1], ovColor[2], ovColor[3], ovColor[4] or 1)
	cardY = placeWidget(colorPicker, inner, cardY, DROPDOWN_H)

	-- Conditional: DurationOverlay or Both — smooth animation + bar orientation
	local ovMode = data.overlayMode or 'DurationOverlay'
	if(ovMode == 'DurationOverlay' or ovMode == 'Both') then
		local smoothSwitch = Widgets.CreateCheckButton(inner, 'Smooth Animation', function(checked)
			update('smooth', checked)
		end)
		smoothSwitch:SetChecked(data.smooth ~= false)
		cardY = placeWidget(smoothSwitch, inner, cardY, CHECK_H)

		local BAR_ORIENTATION_ITEMS = {
			{ text = 'Horizontal', value = 'Horizontal' },
			{ text = 'Vertical',   value = 'Vertical' },
		}
		local barOriDD = Widgets.CreateDropdown(inner, WIDGET_W)
		barOriDD:SetItems(BAR_ORIENTATION_ITEMS)
		barOriDD:SetValue(data.barOrientation or 'Horizontal')
		barOriDD:SetOnSelect(function(v) update('barOrientation', v) end)
		cardY = placeWidget(barOriDD, inner, cardY, DROPDOWN_H)
	end

	return Widgets.EndCard(card, parent, cardY)
end
```

- [ ] **Step 3: Add Duration card builder (Bar/Bars — separate from CooldownDuration)**

Reference `IndicatorPanels.lua:670-700`. Bars have a simpler duration card (just the mode dropdown + conditional font card).

```lua
-- ── Duration (Bar/Bars) ─────────────────────────────────────
function Builders.Duration(parent, width, data, update, get, set)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local DURATION_MODE_ITEMS = {
		{ text = 'Never',   value = 'Never' },
		{ text = 'Always',  value = 'Always' },
		{ text = '< 75%',   value = '<75%' },
		{ text = '< 50%',   value = '<50%' },
		{ text = '< 25%',   value = '<25%' },
		{ text = '< 15s',   value = '<15s' },
		{ text = '< 5s',    value = '<5s' },
	}

	local durDD = Widgets.CreateDropdown(inner, WIDGET_W)
	durDD:SetItems(DURATION_MODE_ITEMS)
	durDD:SetValue(data.durationMode or 'Never')
	durDD:SetOnSelect(function(v) update('durationMode', v) end)
	cardY = placeWidget(durDD, inner, cardY, DROPDOWN_H)

	return Widgets.EndCard(card, parent, cardY)
end
```

- [ ] **Step 4: Add type-to-cards mapping table**

This table declares which card builders apply to each indicator type. The Buffs/Debuffs panel will read this to spawn the right cards.

```lua
-- ============================================================
-- Type → Card mapping
-- Each entry: { cardId, cardTitle, builderFn }
-- The panel iterates this to spawn cards for the active indicator.
-- ============================================================

Builders.CARDS_FOR_TYPE = {
	[C.IndicatorType.ICONS] = {
		{ 'castBy',           'Cast By',             Builders.CastBy },
		{ 'trackedSpells',    'Tracked Spells',      Builders.TrackedSpells },
		{ 'appearance',       'Appearance',          Builders.Appearance },
		{ 'layout',           'Layout',              Builders.Layout },
		{ 'cooldownDuration', 'Cooldown & Duration', Builders.CooldownDuration },
		{ 'stacks',           'Stacks',              Builders.Stacks },
		{ 'glow',             nil,                   'SharedGlow' },
	},
	[C.IndicatorType.ICON] = {
		{ 'castBy',           'Cast By',             Builders.CastBy },
		{ 'trackedSpells',    'Tracked Spells',      Builders.TrackedSpells },
		{ 'appearance',       'Appearance',          Builders.Appearance },
		{ 'position',         'Position',            'SharedPosition' },
		{ 'cooldownDuration', 'Cooldown & Duration', Builders.CooldownDuration },
		{ 'stacks',           'Stacks',              Builders.Stacks },
		{ 'glow',             nil,                   'SharedGlow' },
	},
	[C.IndicatorType.BARS] = {
		{ 'castBy',           'Cast By',       Builders.CastBy },
		{ 'trackedSpells',    'Tracked Spells', Builders.TrackedSpells },
		{ 'size',             'Size',           Builders.Size },
		{ 'layout',           'Layout',         Builders.Layout },
		{ 'thresholdColors',  nil,              'SharedThresholdColors' },
		{ 'duration',         'Duration',       Builders.Duration },
		{ 'stacks',           'Stacks',         Builders.Stacks },
		{ 'glow',             nil,              'SharedGlow' },
	},
	[C.IndicatorType.BAR] = {
		{ 'castBy',           'Cast By',       Builders.CastBy },
		{ 'trackedSpells',    'Tracked Spells', Builders.TrackedSpells },
		{ 'size',             'Size',           Builders.Size },
		{ 'layout',           'Layout',         Builders.Layout },
		{ 'thresholdColors',  nil,              'SharedThresholdColors' },
		{ 'duration',         'Duration',       Builders.Duration },
		{ 'stacks',           'Stacks',         Builders.Stacks },
		{ 'glow',             nil,              'SharedGlow' },
	},
	[C.IndicatorType.RECTANGLE] = {
		{ 'size',             'Size',      Builders.Size },
		{ 'thresholdColors',  nil,         'SharedThresholdColors' },
		{ 'stacks',           'Stacks',    Builders.Stacks },
		{ 'glow',             nil,         'SharedGlow' },
		{ 'position',         'Position',  'SharedPosition' },
	},
	[C.IndicatorType.OVERLAY] = {
		{ 'mode',             'Mode',      Builders.Mode },
		{ 'thresholdColors',  nil,         'SharedThresholdColors' },
	},
	[C.IndicatorType.BORDER] = {
		-- Border uses BorderIconSettings-style settings
		-- Handled separately in panel code
	},
}

-- Helper: string markers like 'SharedGlow' are resolved at spawn time
-- to call F.Settings.BuildGlowCard, BuildPositionCard, BuildThresholdColorCard
-- wrapped in a CardGrid-compatible builder.
```

- [ ] **Step 5: Add shared card wrapper helpers**

The shared card builders (`BuildGlowCard`, `BuildPositionCard`, `BuildThresholdColorCard`) use `(parent, width, yOffset, get, set, opts)` signatures which return `yOffset`. Wrap them for CardGrid compatibility:

```lua
-- ============================================================
-- Shared card wrappers for CardGrid
-- These adapt the yOffset-based SharedCards builders to return
-- a card frame like CardGrid expects.
-- ============================================================

function Builders.SharedGlow(parent, width, data, update, get, set)
	local wrapper = CreateFrame('Frame', nil, parent)
	wrapper:SetWidth(width)
	local yOff = F.Settings.BuildGlowCard(wrapper, width, 0, get, set, { allowNone = true })
	wrapper:SetHeight(math.abs(yOff))
	return wrapper
end

function Builders.SharedPosition(parent, width, data, update, get, set)
	local wrapper = CreateFrame('Frame', nil, parent)
	wrapper:SetWidth(width)
	local yOff = F.Settings.BuildPositionCard(wrapper, width, 0, get, set)
	wrapper:SetHeight(math.abs(yOff))
	return wrapper
end

function Builders.SharedThresholdColors(parent, width, data, update, get, set, opts)
	local wrapper = CreateFrame('Frame', nil, parent)
	wrapper:SetWidth(width)
	local tcOpts = {}
	if(data.type == C.IndicatorType.BAR or data.type == C.IndicatorType.BARS) then
		tcOpts.showBorderColor = true
		tcOpts.showBgColor = true
		tcOpts.hideBaseColor = true
	elseif(data.type == C.IndicatorType.RECTANGLE) then
		tcOpts.showBorderColor = true
	end
	local yOff = F.Settings.BuildThresholdColorCard(wrapper, width, 0, get, set, tcOpts)
	wrapper:SetHeight(math.abs(yOff))
	return wrapper
end
```

- [ ] **Step 6: Commit**

```bash
git add Settings/Builders/IndicatorCardBuilders.lua
git commit -m "feat: add Size, Mode, Duration builders and type-to-cards mapping"
```

### Task 2D: Add to TOC file

**Files:**
- Modify: `Framed.toc`

- [ ] **Step 1: Add IndicatorCardBuilders.lua to TOC**

Find the Settings/Builders section in `Framed.toc` and add after `SharedCards.lua`:

```
Settings\Builders\IndicatorCardBuilders.lua
```

- [ ] **Step 2: Commit**

```bash
git add Framed.toc
git commit -m "chore: add IndicatorCardBuilders to TOC"
```

---

## Phase 3: AuraPreview Widget

### Task 3A: Create AuraPreview.lua

**Files:**
- Create: `Settings/Builders/AuraPreview.lua`
- Reference: `Preview/PreviewFrame.lua` (health bar, power bar, name text builders)
- Reference: `Preview/PreviewAuras.lua` (aura group rendering, dimming)
- Reference: `Preview/PreviewIndicators.lua` (icon, bar, border icon builders)

This creates a self-contained mini preview widget (~140px) that renders a fake unit frame with aura indicators. It reads live config via `Config.Get()` and uses `PreviewIndicators` renderers for visual consistency with the edit mode preview.

- [ ] **Step 1: Create the file with core preview builder**

Create `Settings/Builders/AuraPreview.lua`:

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local PI = F.PreviewIndicators

local PREVIEW_W = 140
local PREVIEW_H = 36
local HEALTH_H  = 18
local POWER_H   = 4
local NAME_SIZE  = 9
local AURA_ICON_SIZE = 10

local AuraPreview = {}
F.Settings.AuraPreview = AuraPreview

-- ── Fake unit data for preview ──────────────────────────────
local FAKE_NAMES = { 'Healbot', 'Tankbro', 'Dpsguy', 'Rangedps', 'Offtank' }
local FAKE_CLASS_COLORS = {
	{ 0.96, 0.55, 0.73 }, -- Paladin pink
	{ 1.00, 0.49, 0.04 }, -- Warrior orange
	{ 0.00, 0.44, 0.87 }, -- Shaman blue
	{ 0.64, 0.19, 0.79 }, -- Warlock purple
	{ 0.00, 0.98, 0.61 }, -- Monk green
}

-- ── Build the preview frame ─────────────────────────────────
function AuraPreview.Create(parent)
	local frame = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	frame:SetSize(PREVIEW_W, PREVIEW_H)
	frame:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	frame:SetBackdropColor(0.1, 0.1, 0.18, 1)
	frame:SetBackdropBorderColor(0.23, 0.23, 0.35, 1)

	-- Health bar
	local health = CreateFrame('StatusBar', nil, frame)
	health:SetPoint('TOPLEFT', frame, 'TOPLEFT', 2, -2)
	health:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -2, -2)
	health:SetHeight(HEALTH_H)
	health:SetStatusBarTexture(F.Media and F.Media.GetActiveBarTexture and F.Media.GetActiveBarTexture() or [[Interface\BUTTONS\WHITE8x8]])
	health:SetMinMaxValues(0, 1)
	health:SetValue(1)
	local classColor = FAKE_CLASS_COLORS[1]
	health:SetStatusBarColor(classColor[1], classColor[2], classColor[3], 1)
	frame._health = health

	-- Name text
	local name = health:CreateFontString(nil, 'OVERLAY')
	name:SetFont(STANDARD_TEXT_FONT, NAME_SIZE, 'OUTLINE')
	name:SetPoint('LEFT', health, 'LEFT', 4, 0)
	name:SetText(FAKE_NAMES[1])
	frame._name = name

	-- Power bar
	local power = CreateFrame('StatusBar', nil, frame)
	power:SetPoint('TOPLEFT', health, 'BOTTOMLEFT', 0, -1)
	power:SetPoint('TOPRIGHT', health, 'BOTTOMRIGHT', 0, -1)
	power:SetHeight(POWER_H)
	power:SetStatusBarTexture(F.Media and F.Media.GetActiveBarTexture and F.Media.GetActiveBarTexture() or [[Interface\BUTTONS\WHITE8x8]])
	power:SetMinMaxValues(0, 1)
	power:SetValue(1)
	power:SetStatusBarColor(0.16, 0.16, 0.5, 1)
	frame._power = power

	-- Aura groups container
	frame._auraGroups = {}

	-- Eye toggle button
	local eye = CreateFrame('Button', nil, frame)
	eye:SetSize(12, 12)
	eye:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -3, -3)
	eye:SetNormalFontObject(GameFontNormalSmall)

	local eyeTex = eye:CreateTexture(nil, 'ARTWORK')
	eyeTex:SetAllPoints()
	eyeTex:SetTexture([[Interface\MINIMAP\Tracking\None]])
	eyeTex:SetVertexColor(0.6, 0.8, 0.6, 0.8)
	frame._eyeIcon = eyeTex

	frame._showAll = false
	eye:SetScript('OnClick', function()
		frame._showAll = not frame._showAll
		if(frame._showAll) then
			eyeTex:SetVertexColor(0.2, 1.0, 0.2, 1)
		else
			eyeTex:SetVertexColor(0.6, 0.8, 0.6, 0.8)
		end
		if(frame.UpdateDimming) then
			frame:UpdateDimming()
		end
	end)
	frame._eyeBtn = eye

	return frame
end

-- ── Render aura indicators from config ──────────────────────
function AuraPreview.Render(frame, unitType, activeGroupKey, activeIndicatorName)
	-- Clear existing aura groups
	for _, group in next, frame._auraGroups do
		group:Hide()
		group:SetParent(nil)
	end
	wipe(frame._auraGroups)

	-- Read live config
	local config = F.Config and F.Config:GetUnitConfig and F.Config:GetUnitConfig(unitType)
	if(not config) then return end

	-- Build aura indicators using PreviewAuras if available
	if(F.PreviewAuras and F.PreviewAuras.BuildForSettingsPreview) then
		F.PreviewAuras.BuildForSettingsPreview(frame, config, unitType)
	end

	-- Apply dimming
	frame.UpdateDimming = function(self)
		local f = self or frame
		if(f._showAll) then
			for _, group in next, f._auraGroups do
				group:SetAlpha(1.0)
			end
		else
			for groupKey, group in next, f._auraGroups do
				if(activeGroupKey and groupKey ~= activeGroupKey) then
					group:SetAlpha(0.2)
				else
					group:SetAlpha(1.0)
				end
			end
		end
	end

	frame:UpdateDimming()
end

-- ── Destroy ─────────────────────────────────────────────────
function AuraPreview.Destroy(frame)
	if(not frame) then return end
	for _, group in next, frame._auraGroups do
		group:Hide()
		group:SetParent(nil)
	end
	wipe(frame._auraGroups)
	frame:Hide()
	frame:SetParent(nil)
end
```

**Note:** The `BuildForSettingsPreview` function on `PreviewAuras` does not exist yet. This is a hook point — Phase 3 Task 3B will wire the actual rendering. For now the preview frame structure and dimming logic are in place.

- [ ] **Step 2: Add to TOC after SharedCards.lua**

Add to `Framed.toc` in the Settings/Builders section:

```
Settings\Builders\AuraPreview.lua
```

- [ ] **Step 3: Commit**

```bash
git add Settings/Builders/AuraPreview.lua Framed.toc
git commit -m "feat: create AuraPreview widget with frame structure and dimming"
```

### Task 3B: Wire preview rendering with PreviewIndicators

**Files:**
- Modify: `Settings/Builders/AuraPreview.lua`

The preview needs to render actual aura indicators using the same `PreviewIndicators` builders that the edit mode uses. Since we cannot modify `Preview/` files, the `AuraPreview.Render` function will call `PreviewIndicators` directly to create icons/bars at the appropriate positions on the mini frame.

- [ ] **Step 1: Implement aura group rendering in AuraPreview.Render**

Replace the placeholder `BuildForSettingsPreview` call with direct rendering logic. This reads the config for each aura group (buffs, debuffs, dispellable, externals, defensives) and creates miniature indicators using `PreviewIndicators.CreateIcon` and `PreviewIndicators.CreateBorderIcon`.

The implementation should:
- Read `config.buffs.indicators` and render enabled indicators at their configured anchors
- Read `config.debuffs` and render border icons
- Read `config.dispellable`, `config.externals`, `config.defensives` for their respective groups
- Scale all icon sizes down proportionally for the mini preview (~60% of configured size)
- Start animation loops for visual feedback
- Store each group in `frame._auraGroups[groupKey]` for dimming

This is complex rendering code — the implementer should reference `Preview/PreviewAuras.lua:BuildBuffIndicators` (lines 31-108) and `BuildBorderIconGroup` (lines 155-175) as the source of truth for how to render each group. Adapt those patterns to work at mini scale within `AuraPreview.Render`.

- [ ] **Step 2: Commit**

```bash
git add Settings/Builders/AuraPreview.lua
git commit -m "feat: wire AuraPreview rendering with PreviewIndicators"
```

---

## Phase 4: Framework Changes

### Task 4: Add preview show/hide to SetActivePanel

**Files:**
- Modify: `Settings/Framework.lua:310-325` (header update section of SetActivePanel)
- Modify: `Settings/MainFrame.lua:264-277` (title card area)

- [ ] **Step 1: Add preview anchor in MainFrame.lua title card**

In `Settings/MainFrame.lua`, after the `_headerPresetText` creation (around line 277), add a placeholder anchor for the preview:

```lua
-- Preview anchor (populated by AuraPreview when an aura panel is active)
Settings._headerPreviewAnchor = titleCard
```

- [ ] **Step 2: Add preview lifecycle to SetActivePanel in Framework.lua**

In `Settings/Framework.lua`, in the `SetActivePanel` function, after the header text update block (around line 323), add preview management:

```lua
-- ── Aura preview lifecycle ──────────────────────────────
if(Settings._auraPreview) then
	F.Settings.AuraPreview.Destroy(Settings._auraPreview)
	Settings._auraPreview = nil
end

if(info.subSection == 'auras' and Settings._headerPreviewAnchor) then
	local preview = F.Settings.AuraPreview.Create(Settings._headerPreviewAnchor)
	preview:SetPoint('RIGHT', Settings._headerPresetText or Settings._headerPreviewAnchor, 'RIGHT', -C.Spacing.normal, 0)
	-- Position to the right of preset text, or right side of title card
	if(Settings._headerPresetText and Settings._headerPresetText:IsShown()) then
		preview:ClearAllPoints()
		preview:SetPoint('RIGHT', Settings._headerPreviewAnchor, 'RIGHT', -C.Spacing.normal, 0)
	end
	Settings._auraPreview = preview

	-- Initial render with page-level dimming
	local auraGroupKey = info.id  -- 'buffs', 'debuffs', 'dispels', etc.
	local unitType = Settings.GetEditingUnitType() or 'player'
	F.Settings.AuraPreview.Render(preview, unitType, auraGroupKey, nil)
end
```

- [ ] **Step 3: Add breadcrumb update helper**

Add a helper function in `Framework.lua` that the Buffs/Debuffs panels will call when editing an indicator:

```lua
function Settings.UpdateAuraBreadcrumb(pageLabel, indicatorName)
	if(not Settings._headerPanelText) then return end
	if(indicatorName) then
		Settings._headerPanelText:SetText(pageLabel .. '  |cff6688cc>|r  ' .. indicatorName)
	else
		Settings._headerPanelText:SetText(pageLabel)
	end
end

function Settings.UpdateAuraPreviewDimming(activeGroupKey, activeIndicatorName)
	if(not Settings._auraPreview) then return end
	local unitType = Settings.GetEditingUnitType() or 'player'
	F.Settings.AuraPreview.Render(Settings._auraPreview, unitType, activeGroupKey, activeIndicatorName)
end
```

- [ ] **Step 4: Clean up preview on settings close**

In `MainFrame.lua`, find where the settings frame is hidden (OnHide or close button handler) and add:

```lua
if(Settings._auraPreview) then
	F.Settings.AuraPreview.Destroy(Settings._auraPreview)
	Settings._auraPreview = nil
end
```

- [ ] **Step 5: Commit**

```bash
git add Settings/Framework.lua Settings/MainFrame.lua
git commit -m "feat: add aura preview lifecycle to SetActivePanel and title card"
```

---

## Phase 5: Buffs Panel (Template)

### Task 5A: Rewrite Buffs.lua with pinned row + CardGrid

**Files:**
- Modify: `Settings/Panels/Buffs.lua` (full rewrite)
- Reference: `Settings/FrameSettingsBuilder.lua:102-237` (CardGrid usage pattern)
- Reference: `Settings/Builders/IndicatorCRUD.lua:193-588` (current implementation)

This is the most complex panel. It serves as the template for the Debuffs panel.

- [ ] **Step 1: Rewrite Buffs.lua**

Replace the contents of `Settings/Panels/Buffs.lua` with the new grid-based layout. The structure:

1. ScrollFrame wrapping everything (same as FrameSettingsBuilder)
2. Unit type dropdown row via `BuildAuraUnitTypeRow()`
3. Pinned flex row with Create card (flex:1) and Indicator List card (flex:2)
4. CardGrid below the pinned row for settings cards
5. Scroll integration (lazy loading on mouse wheel)
6. Resize handling via `SETTINGS_RESIZED` event

The key behaviors:
- Create card: type dropdown, display type toggle (Icon/Icons only), name input, create button
- List card: rows with enable/disable, name, type, edit/close, delete
- Edit click: reads `CARDS_FOR_TYPE[indicatorType]` from `IndicatorCardBuilders`, spawns each as a grid card
- Close click: calls `grid:RemoveAllCards()` then `grid:Layout()`
- Unit type change: full rebuild via `SetActivePanel()`

The Create and List cards are built using `Widgets.StartCard`/`EndCard` inside plain frames positioned in the flex row. The flex row is a Frame with two children anchored side by side.

**Important wiring details from IndicatorCRUD.lua:**
- `getIndicators()` reads from `F.Config:Get(basePath .. '.indicators')`
- `setIndicator(name, data)` calls `F.Config:Set(basePath .. '.' .. name, data)` which fires `CONFIG_CHANGED`
- `basePath` is constructed from preset + unitType + configKey (e.g., `'presets.mythicDungeon.party.buffs'`)
- These closures are created in the panel's `create` function and capture the current scope

The implementer should read `IndicatorCRUD.lua` lines 48-72 for the exact config path construction, and lines 112-178 for the row rendering pattern. Port these directly — same logic, new container.

For each settings card spawned via `grid:AddCard()`, the builder args should include `(data, update, get, set, rebuildPanel)` where:
- `data` is the indicator's config table
- `update(key, value)` sets `data[key] = value` then calls `setIndicator(name, data)`
- `get(key)` returns `data[key]`
- `set(key, value)` calls `update(key, value)`
- `rebuildPanel` destroys and re-spawns all settings cards (for when a dropdown changes which cards are shown)

The string markers in `CARDS_FOR_TYPE` (`'SharedGlow'`, `'SharedPosition'`, `'SharedThresholdColors'`) should be resolved to the wrapper functions: `Builders.SharedGlow`, `Builders.SharedPosition`, `Builders.SharedThresholdColors`.

- [ ] **Step 2: Test in-game**

Sync to WoW addon folder. Open Framed settings → Buffs page:
- Verify pinned row shows Create + Indicator List side by side
- Click Edit on an indicator → settings cards appear in grid
- Change a setting → live frames update
- Click Close → settings cards disappear
- Create a new indicator → list updates, auto-opens for editing
- Delete an indicator → list updates, cards removed if was editing
- Toggle enable/disable → live frames update, preview updates
- Switch unit type → full rebuild
- Resize settings window → grid reflows

- [ ] **Step 3: Commit**

```bash
git add Settings/Panels/Buffs.lua
git commit -m "feat: rewrite Buffs panel with pinned row and masonry CardGrid"
```

---

## Phase 6: Debuffs Panel

### Task 6: Rewrite Debuffs.lua

**Files:**
- Modify: `Settings/Panels/Debuffs.lua` (full rewrite)
- Reference: `Settings/Builders/DebuffIndicatorCRUD.lua:144-327` (current implementation)
- Reference: newly written `Settings/Panels/Buffs.lua` (template)

Debuffs follows the same pattern as Buffs but uses `DebuffIndicatorCRUD` which differs:
- Filter mode dropdown instead of indicator type (All, Raid, Important, Dispellable, etc.)
- Uses `BorderIconSettings` for per-indicator settings instead of the card builders
- No display type toggle
- Simpler create data structure

- [ ] **Step 1: Rewrite Debuffs.lua following Buffs pattern**

Same structure: ScrollFrame → unit type row → pinned flex row (Create + List) → CardGrid.

The Create card has a filter mode dropdown instead of type dropdown. The List card follows the same pattern. Settings cards use `BorderIconSettings`-style builders extracted into CardGrid-compatible cards.

The implementer should read `DebuffIndicatorCRUD.lua` lines 144-327 for the exact differences from IndicatorCRUD, and `BorderIconSettings.lua` lines 40-228 for the settings that need to be split into cards.

The debuff indicator settings cards should be:
- **Filter Mode** card (from `BorderIconSettings.lua:43-69`)
- **Visibility** card (enabled + visibility mode dropdown, from lines 71-103)
- **Source Colors** card (player/other color pickers, from lines 105-146)
- **Display Settings** card (icon size, big icon size, max displayed, show duration, show animation, orientation, from lines 148-216)
- **Position** card (shared `BuildPositionCard`, from line 219)
- **Duration Font** card (shared `BuildFontCard`, from line 222)
- **Stack Font** card (shared `BuildFontCard`, from line 225)

- [ ] **Step 2: Test in-game**

Same test matrix as Buffs but verify filter mode dropdown works correctly and BorderIconSettings-style cards render properly.

- [ ] **Step 3: Commit**

```bash
git add Settings/Panels/Debuffs.lua
git commit -m "feat: rewrite Debuffs panel with pinned row and masonry CardGrid"
```

---

## Phase 7: Simpler Aura Panels

### Task 7A: Rewrite Dispels.lua

**Files:**
- Modify: `Settings/Panels/Dispels.lua` (full rewrite)
- Reference: current `Dispels.lua` lines 43-160

Structure: ScrollFrame → unit type row → CardGrid with Overview + settings cards.

Cards:
- **Overview** — enabled toggle, "only dispellable by me" toggle, description
- **Highlight** — highlight type dropdown, highlight alpha slider (new — reads `dispellable.highlightAlpha`)
- **Icon** — icon size slider, frame level slider, anchor picker

- [ ] **Step 1: Rewrite Dispels.lua with CardGrid**

Follow the FrameSettingsBuilder pattern: ScrollFrame → content → CardGrid. Add cards using `grid:AddCard()`. Wire `get`/`set` closures the same way the current panel does (reading from the dispellable config path).

Add the highlight alpha slider to the Highlight card:

```lua
local alphaSlider = Widgets.CreateSlider(inner, 'Highlight Alpha', WIDGET_W, 0, 100, 1)
alphaSlider:SetValue((get('highlightAlpha') or 0.8) * 100)
alphaSlider:SetAfterValueChanged(function(v) set('highlightAlpha', v / 100) end)
```

- [ ] **Step 2: Commit**

```bash
git add Settings/Panels/Dispels.lua
git commit -m "feat: rewrite Dispels panel with masonry CardGrid"
```

### Task 7B: Rewrite Externals.lua and Defensives.lua

**Files:**
- Modify: `Settings/Panels/Externals.lua`
- Modify: `Settings/Panels/Defensives.lua`
- Reference: `Settings/Builders/BorderIconSettings.lua:40-228`

These two panels are nearly identical — both use `BorderIconSettings` with `showVisibilityMode = true`, `showSourceColors = true`.

Cards for each:
- **Overview** — enabled toggle, description
- **Visibility** — visibility mode dropdown (all/player/others)
- **Source Colors** — player color picker, other color picker
- **Display** — icon size, max displayed, show duration, show animation, orientation
- **Position** — shared `BuildPositionCard`
- **Font** — shared `BuildFontCard` for duration + stacks

- [ ] **Step 1: Rewrite Externals.lua with CardGrid**

- [ ] **Step 2: Rewrite Defensives.lua with CardGrid**

Nearly identical to Externals — copy and adjust panel ID, label, order, configKey.

- [ ] **Step 3: Commit**

```bash
git add Settings/Panels/Externals.lua Settings/Panels/Defensives.lua
git commit -m "feat: rewrite Externals and Defensives panels with masonry CardGrid"
```

### Task 7C: Rewrite RaidDebuffs.lua (if exists as separate panel)

**Files:**
- Check if `Settings/Panels/RaidDebuffs.lua` exists as a separate panel or is handled within Debuffs

If it exists as a separate panel, rewrite with CardGrid following the same pattern as the other simpler panels. If it's part of the Debuffs indicator system, it was already handled in Phase 6.

- [ ] **Step 1: Check and rewrite if needed**

- [ ] **Step 2: Commit if changes made**

### Task 7D: Rewrite MissingBuffs.lua

**Files:**
- Modify: `Settings/Panels/MissingBuffs.lua`
- Reference: current lines 41-142

Cards:
- **Overview** — enabled toggle, description, reload info
- **Display** — icon size slider, growth direction dropdown
- **Position** — shared `BuildPositionCard`
- **Glow** — shared `BuildGlowCard` with `allowNone = false`

- [ ] **Step 1: Rewrite MissingBuffs.lua with CardGrid**

- [ ] **Step 2: Commit**

```bash
git add Settings/Panels/MissingBuffs.lua
git commit -m "feat: rewrite MissingBuffs panel with masonry CardGrid"
```

### Task 7E: Rewrite PrivateAuras.lua

**Files:**
- Modify: `Settings/Panels/PrivateAuras.lua`
- Reference: current lines 40-136

Cards:
- **Overview** — enabled toggle, description
- **Display** — icon size, max icons, orientation sliders
- **Position** — shared `BuildPositionCard` with `hideFrameLevel = true`

- [ ] **Step 1: Rewrite PrivateAuras.lua with CardGrid**

- [ ] **Step 2: Commit**

```bash
git add Settings/Panels/PrivateAuras.lua
git commit -m "feat: rewrite PrivateAuras panel with masonry CardGrid"
```

### Task 7F: Rewrite TargetedSpells.lua

**Files:**
- Modify: `Settings/Panels/TargetedSpells.lua`
- Reference: current lines 41-217

This panel has conditional card visibility based on display mode (Icons/BorderGlow/Both). Cards:
- **Overview** — enabled toggle, description
- **Display Mode** — dropdown (Icons/BorderGlow/Both)
- **Icon Settings** — icon size, max displayed (visible when mode is Icons or Both)
- **Position** — shared `BuildPositionCard` (visible when mode is Icons or Both)
- **Duration Font** — shared `BuildFontCard` (visible when mode is Icons or Both)
- **Border Glow** — shared `BuildGlowCard` (visible when mode is BorderGlow or Both)

Use `grid:RemoveCard()` and `grid:AddCard()` to dynamically show/hide cards when the display mode changes, followed by `grid:Layout()` to reflow.

- [ ] **Step 1: Rewrite TargetedSpells.lua with CardGrid and conditional cards**

- [ ] **Step 2: Commit**

```bash
git add Settings/Panels/TargetedSpells.lua
git commit -m "feat: rewrite TargetedSpells panel with masonry CardGrid"
```

### Task 7G: Rewrite LossOfControl.lua

**Files:**
- Modify: `Settings/Panels/LossOfControl.lua`
- Reference: current lines 69-155

Cards:
- **Overview** — enabled toggle, description
- **CC Types** — checkboxes for each CC type (stun, fear, root, silence, etc.)
- **Visual Settings** — overlay alpha slider, icon size slider

- [ ] **Step 1: Rewrite LossOfControl.lua with CardGrid**

- [ ] **Step 2: Commit**

```bash
git add Settings/Panels/LossOfControl.lua
git commit -m "feat: rewrite LossOfControl panel with masonry CardGrid"
```

### Task 7H: Rewrite CrowdControl.lua

**Files:**
- Modify: `Settings/Panels/CrowdControl.lua`
- Reference: current lines 67-139

Cards:
- **Overview** — enabled toggle, description
- **Tracked Spells** — SpellList + SpellInput widgets (same as current)
- **Display** — icon size, duration settings
- **Position** — shared `BuildPositionCard`

- [ ] **Step 1: Rewrite CrowdControl.lua with CardGrid**

- [ ] **Step 2: Commit**

```bash
git add Settings/Panels/CrowdControl.lua
git commit -m "feat: rewrite CrowdControl panel with masonry CardGrid"
```

---

## Phase 8: highlightAlpha Config Key

### Task 8: Add highlightAlpha to defaults and Dispellable element

**Files:**
- Modify: `Presets/AuraDefaults.lua:228-235` (dispellable defaults)
- Modify: `Elements/Auras/Dispellable.lua:102` (OVERLAY_ALPHA constant)

- [ ] **Step 1: Add highlightAlpha to defaults**

In `Presets/AuraDefaults.lua`, find the `dispellable` table (around line 228) and add:

```lua
dispellable = {
    enabled              = true,
    onlyDispellableByMe  = false,
    highlightType        = 'gradient_half',
    highlightAlpha       = 0.8,  -- NEW: configurable overlay alpha
    iconSize             = dispIcon,
    anchor               = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', 0, 4 },
    frameLevel           = 15,
}
```

- [ ] **Step 2: Update Dispellable.lua to read from config**

In `Elements/Auras/Dispellable.lua`, find `local OVERLAY_ALPHA = 0.8` (line 102). Replace the constant usage with config reads:

```lua
-- Replace: local OVERLAY_ALPHA = 0.8
-- The alpha is now read from config in the Update function.
```

In the `Update` function, where `OVERLAY_ALPHA` is referenced (around lines 162-174), read from config instead:

```lua
local overlayAlpha = element.__config and element.__config.highlightAlpha or 0.8
```

Then replace all `OVERLAY_ALPHA` references in that function with `overlayAlpha`.

Also update line 246 where `OVERLAY_ALPHA` is referenced in the curve-based rendering.

- [ ] **Step 3: Commit**

```bash
git add Presets/AuraDefaults.lua Elements/Auras/Dispellable.lua
git commit -m "feat: make dispellable highlight alpha configurable via settings"
```

---

## Phase 9: Sync & Full Test Pass

### Task 9: Full in-game verification

**Files:** None (testing only)

- [ ] **Step 1: Sync to WoW addon folder**

```bash
# Copy the worktree to the WoW addon folder
cp -r /path/to/worktree/Framed/* /path/to/wow/Interface/AddOns/Framed/
```

- [ ] **Step 2: Test Buffs page**
- Open Framed settings → Buffs
- Verify pinned row: Create card (1/3) + Indicator List (2/3)
- Create a new indicator → appears in list, auto-opens settings cards
- Edit each indicator type (Icons, Icon, Bar, Bars, Rectangle, Overlay, Border)
- Change settings → live frames update immediately
- Enable/disable → live frames update, preview updates
- Switch unit type → full rebuild with correct config
- Resize window → grid reflows, pinned row adjusts
- Verify preview shows correct auras with dimming
- Toggle eye icon → show-all mode works

- [ ] **Step 3: Test Debuffs page**
- Same matrix as Buffs
- Verify filter mode dropdown works
- Verify BorderIconSettings-style cards render

- [ ] **Step 4: Test each simpler aura page**
- Dispels: highlight type + new alpha slider
- Externals: visibility mode, source colors
- Defensives: same as Externals
- Missing Buffs: glow settings
- Private Auras: icon size, orientation
- Targeted Spells: conditional cards on display mode change
- Loss of Control: CC type toggles
- Crowd Control: spell list

- [ ] **Step 5: Test preset switching**
- Switch preset (e.g., Solo → Mythic+ Dungeon)
- Verify all aura pages rebuild with correct preset data
- Verify no stale config references

- [ ] **Step 6: Test edit mode interaction**
- Enter edit mode while settings are open
- Verify settings preview reads live config, not EditCache
- Verify edit mode preview is unaffected

- [ ] **Step 7: Fix any issues found**

- [ ] **Step 8: Final commit**

```bash
git add -A
git commit -m "fix: address issues found during aura masonry grid testing"
```

- [ ] **Step 9: Push to remote**

```bash
git push
```
