# Copy-To Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the "Copy to..." button on aura settings panels so users can copy aura config from one unit type to one or more others within the same preset.

**Architecture:** A new `Settings/CopyToDialog.lua` creates a dialog with multi-select toggle buttons for target unit types. On confirm, it deep-clones the source config and writes it to each target via `Config:Set`. `Framework.lua` is updated to expose helpers, accept a `configKey` parameter, and wire the button.

**Tech Stack:** WoW Lua, Framed widget library (`Widgets.CreateButton`, `Widgets.CreateMultiSelectButtonGroup`, `Widgets.FadeIn/FadeOut`)

**Spec:** `docs/superpowers/specs/2026-03-26-copy-to-dialog-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Settings/CopyToDialog.lua` | Create | Dialog frame, toggle buttons, deep clone, config write, confirm/cancel |
| `Settings/Framework.lua` | Modify | Expose `_getUnitTypeItems`, add `configKey` param to `BuildAuraUnitTypeRow`, wire button |
| `Settings/Panels/*.lua` | Modify | Pass `configKey` arg to `BuildAuraUnitTypeRow` (11 files) |
| `Framed.toc` | Modify | Add `Settings/CopyToDialog.lua` |

---

## Task Summary

| Task | Description | Files |
|------|-------------|-------|
| 0 | Framework.lua changes | `Settings/Framework.lua` |
| 1 | CopyToDialog.lua | `Settings/CopyToDialog.lua` |
| 2 | Wire panels + TOC | `Settings/Panels/*.lua`, `Framed.toc` |

---

### Task 0: Update Framework.lua

**Files:**
- Modify: `Settings/Framework.lua:93-170`

**Context:** `BuildAuraUnitTypeRow(content, width, yOffset, panelId)` currently takes `panelId` as its 4th argument. We need to add a 5th `configKey` argument so the copy-to button knows the correct config path. When `configKey` is `nil` (for excluded panels like CrowdControl and LossOfControl), the copy-to button is hidden.

Also expose `getUnitTypeItems()` as `Settings._getUnitTypeItems()` so `CopyToDialog.lua` can call it.

- [ ] **Step 1: Expose getUnitTypeItems**

In `Settings/Framework.lua`, change line 101 from:

```lua
local function getUnitTypeItems()
```

to:

```lua
function Settings._getUnitTypeItems()
```

Then update the one call site on line 141 from `getUnitTypeItems()` to `Settings._getUnitTypeItems()`.

- [ ] **Step 2: Add configKey parameter and wire the copy-to button**

Update the `BuildAuraUnitTypeRow` signature and body. The new signature is:

```lua
--- @param content Frame   The scroll content frame
--- @param width   number  Available content width
--- @param yOffset number  Current vertical cursor
--- @param panelId string  Panel id used for rebuild on change
--- @param configKey? string  Aura config key (e.g., 'buffs', 'raidDebuffs'). nil = hide copy button.
--- @return number yOffset Updated vertical cursor
function Settings.BuildAuraUnitTypeRow(content, width, yOffset, panelId, configKey)
```

Replace the copy-to button block (lines 152-158) with:

```lua
	-- ── "Copy to..." button ──────────────────────────────────
	if(configKey) then
		local copyBtn = Widgets.CreateButton(content, 'Copy to...', 'widget', 90, DROPDOWN_H)
		copyBtn:ClearAllPoints()
		Widgets.SetPoint(copyBtn, 'TOPLEFT', content, 'TOPLEFT', 280, yOffset)

		-- Disable when only one unit type exists (no targets to copy to)
		local unitItems = Settings._getUnitTypeItems()
		if(#unitItems <= 1) then
			copyBtn:Disable()
		end

		copyBtn:SetScript('OnClick', function()
			local panelLabel
			for _, p in next, Settings._panels do
				if(p.id == panelId) then
					panelLabel = p.label
					break
				end
			end
			Settings.ShowCopyToDialog(configKey, panelLabel or panelId, panelId)
		end)
	end
```

- [ ] **Step 3: Commit**

```bash
git add Settings/Framework.lua
git commit -m "feat: expose _getUnitTypeItems and add configKey to BuildAuraUnitTypeRow"
```

---

### Task 1: Create CopyToDialog.lua

**Files:**
- Create: `Settings/CopyToDialog.lua`

**Context:** This file creates a dialog frame that lets the user select one or more target unit types and copies the aura config from the current source unit type to each target. The dialog is shown by calling `Settings.ShowCopyToDialog(configKey, panelLabel, panelId)`.

**Dependencies:**
- `Settings._getUnitTypeItems()` — returns `{ { text, value }, ... }` for all unit types in the current preset
- `Settings.GetEditingUnitType()` — source unit type string
- `Settings.GetEditingPreset()` — current preset name
- `Widgets.CreateButton` — for toggle buttons and confirm/cancel
- `Widgets.CreateMultiSelectButtonGroup` — wires toggle behavior
- `Widgets.FadeIn / Widgets.FadeOut` — show/hide transitions
- `F.Config:Set(path, value)` — writes config (auto-fires `CONFIG_CHANGED`)
- `F.PresetManager.MarkCustomized(presetName)` — marks preset as user-modified
- `Settings._panelFrames[panelId]` — cached panel frames to invalidate

**Code style reminders (from CLAUDE.md):**
- `local addonName, Framed = ...` / `local F = Framed` at top
- Tabs for indentation
- Parenthesized conditions: `if(not x) then`
- `for _, v in next, tbl do` (never `pairs`/`ipairs`)
- Single quotes for strings

- [ ] **Step 1: Create the file**

Create `Settings/CopyToDialog.lua` with the following implementation:

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants
local Settings = F.Settings

-- ============================================================
-- CopyToDialog — Copy aura config from one unit type to others
-- ============================================================

local DIALOG_WIDTH  = 360
local DIALOG_HEIGHT = 200
local BTN_W         = 90
local BTN_H         = 22
local BTN_GAP       = 6

local dialog     -- the dialog frame (created once, reused)
local toggleBtns = {}
local multiGroup

-- ── Deep clone ──────────────────────────────────────────────

local function deepClone(src)
	if(type(src) ~= 'table') then return src end
	local copy = {}
	for k, v in next, src do
		copy[k] = deepClone(v)
	end
	return copy
end

-- ── Build / rebuild dialog contents ─────────────────────────

local function buildDialog(configKey, panelLabel, panelId)
	if(not dialog) then
		dialog = CreateFrame('Frame', nil, UIParent, 'BackdropTemplate')
		dialog:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
		dialog:SetPoint('CENTER')
		dialog:SetFrameStrata('FULLSCREEN_DIALOG')
		dialog:SetBackdrop({
			bgFile   = [[Interface\Buttons\WHITE8x8]],
			edgeFile = [[Interface\Buttons\WHITE8x8]],
			edgeSize = 1,
		})
		dialog:SetBackdropColor(C.Colors.frameBg[1], C.Colors.frameBg[2], C.Colors.frameBg[3], 0.95)
		dialog:SetBackdropBorderColor(C.Colors.border[1], C.Colors.border[2], C.Colors.border[3], 1)
		dialog:EnableMouse(true)
		dialog:EnableKeyboard(true)
		dialog:SetScript('OnKeyDown', function(self, key)
			if(key == 'ESCAPE') then
				self:SetPropagateKeyboardInput(false)
				Widgets.FadeOut(self, 0.15, function() self:Hide() end)
			else
				self:SetPropagateKeyboardInput(true)
			end
		end)

		-- Title
		dialog._title = Widgets.CreateFontString(dialog, C.Font.sizeLarge, C.Colors.textNormal)
		dialog._title:SetPoint('TOP', dialog, 'TOP', 0, -C.Spacing.normal)

		-- Subtitle
		dialog._subtitle = Widgets.CreateFontString(dialog, C.Font.sizeSmall, C.Colors.textSecondary)
		dialog._subtitle:SetPoint('TOP', dialog._title, 'BOTTOM', 0, -4)

		-- Cancel button
		dialog._cancelBtn = Widgets.CreateButton(dialog, 'Cancel', 'widget', BTN_W, BTN_H)
		dialog._cancelBtn:SetPoint('BOTTOMRIGHT', dialog, 'BOTTOMRIGHT', -C.Spacing.normal, C.Spacing.normal)
		dialog._cancelBtn:SetScript('OnClick', function()
			Widgets.FadeOut(dialog, 0.15, function() dialog:Hide() end)
		end)

		-- Confirm button
		dialog._confirmBtn = Widgets.CreateButton(dialog, 'Confirm', 'accent', BTN_W, BTN_H)
		dialog._confirmBtn:SetPoint('RIGHT', dialog._cancelBtn, 'LEFT', -BTN_GAP, 0)
	end

	-- Update text
	dialog._title:SetText('Copy ' .. panelLabel .. ' Settings')

	local sourceUnit = Settings.GetEditingUnitType()
	local sourceLabel = sourceUnit
	local items = Settings._getUnitTypeItems()
	for _, item in next, items do
		if(item.value == sourceUnit) then
			sourceLabel = item.text
			break
		end
	end
	dialog._subtitle:SetText('From: ' .. sourceLabel)

	-- Clear old toggle buttons
	for _, btn in next, toggleBtns do
		btn:Hide()
		btn:SetParent(nil)
	end
	toggleBtns = {}

	-- Create toggle buttons for each target unit type (excluding source)
	local targets = {}
	for _, item in next, items do
		if(item.value ~= sourceUnit) then
			targets[#targets + 1] = item
		end
	end

	local btnsPerRow = math.floor((DIALOG_WIDTH - C.Spacing.normal * 2 + BTN_GAP) / (BTN_W + BTN_GAP))
	local startX = C.Spacing.normal
	local startY = -60

	for i, item in next, targets do
		local btn = Widgets.CreateButton(dialog, item.text, 'widget', BTN_W, BTN_H)
		btn.value = item.value
		local row = math.floor((i - 1) / btnsPerRow)
		local col = (i - 1) % btnsPerRow
		btn:ClearAllPoints()
		Widgets.SetPoint(btn, 'TOPLEFT', dialog, 'TOPLEFT',
			startX + col * (BTN_W + BTN_GAP),
			startY - row * (BTN_H + BTN_GAP))
		toggleBtns[#toggleBtns + 1] = btn
	end

	-- Wire multi-select group
	multiGroup = Widgets.CreateMultiSelectButtonGroup(toggleBtns, function(selected)
		-- Enable confirm only when at least one target is selected
		local hasSelection = false
		for _ in next, selected do
			hasSelection = true
			break
		end
		if(hasSelection) then
			dialog._confirmBtn:Enable()
		else
			dialog._confirmBtn:Disable()
		end
	end)

	-- Disable confirm initially
	dialog._confirmBtn:Disable()

	-- Build a value→label lookup for friendly print output
	local labelLookup = {}
	for _, item in next, items do
		labelLookup[item.value] = item.text
	end

	-- Wire confirm action
	dialog._confirmBtn:SetScript('OnClick', function()
		local presetName = Settings.GetEditingPreset()
		local sourcePath = 'presets.' .. presetName .. '.auras.' .. sourceUnit .. '.' .. configKey
		local sourceData = F.Config:Get(sourcePath)

		local copiedTo = {}
		for targetUnit in next, multiGroup._selected do
			local targetPath = 'presets.' .. presetName .. '.auras.' .. targetUnit .. '.' .. configKey
			F.Config:Set(targetPath, deepClone(sourceData))
			copiedTo[#copiedTo + 1] = labelLookup[targetUnit] or targetUnit
		end

		if(F.PresetManager) then
			F.PresetManager.MarkCustomized(presetName)
		end

		-- Invalidate cached panel so it rebuilds with new config
		Settings._panelFrames[panelId] = nil

		Widgets.FadeOut(dialog, 0.15, function() dialog:Hide() end)

		if(#copiedTo > 0) then
			print('Framed: Copied ' .. panelLabel .. ' settings from ' .. sourceLabel .. ' to ' .. table.concat(copiedTo, ', '))
		end
	end)

	-- Adjust dialog height based on number of rows
	local numRows = math.ceil(#targets / btnsPerRow)
	local neededH = 60 + numRows * (BTN_H + BTN_GAP) + BTN_H + C.Spacing.normal * 2 + 10
	dialog:SetHeight(math.max(DIALOG_HEIGHT, neededH))
end

-- ── Public API ──────────────────────────────────────────────

function Settings.ShowCopyToDialog(configKey, panelLabel, panelId)
	buildDialog(configKey, panelLabel, panelId)
	dialog:Show()
	Widgets.FadeIn(dialog, 0.15)
end
```

- [ ] **Step 2: Commit**

```bash
git add Settings/CopyToDialog.lua
git commit -m "feat: add CopyToDialog for copying aura config between unit types"
```

---

### Task 2: Wire Aura Panels and TOC

**Files:**
- Modify: `Settings/Panels/Buffs.lua:24`
- Modify: `Settings/Panels/Debuffs.lua:24`
- Modify: `Settings/Panels/RaidDebuffs.lua:24`
- Modify: `Settings/Panels/Externals.lua:24`
- Modify: `Settings/Panels/Defensives.lua:24`
- Modify: `Settings/Panels/MissingBuffs.lua:59`
- Modify: `Settings/Panels/PrivateAuras.lua:57`
- Modify: `Settings/Panels/TargetedSpells.lua:58`
- Modify: `Settings/Panels/Dispels.lua:59`
- Modify: `Settings/Panels/CrowdControl.lua:67`
- Modify: `Settings/Panels/LossOfControl.lua:85`
- Modify: `Framed.toc`

**Context:** Each aura panel calls `BuildAuraUnitTypeRow(content, width, yOffset, panelId)`. Add the 5th `configKey` argument. For CrowdControl and LossOfControl, pass `nil` to hide the copy button.

- [ ] **Step 1: Update each panel's BuildAuraUnitTypeRow call**

For each panel, find the `BuildAuraUnitTypeRow` call and add the configKey:

| File | Current call | New call |
|------|-------------|----------|
| `Buffs.lua:24` | `..., 'buffs')` | `..., 'buffs', 'buffs')` |
| `Debuffs.lua:24` | `..., 'debuffs')` | `..., 'debuffs', 'debuffs')` |
| `RaidDebuffs.lua:24` | `..., 'raiddebuffs')` | `..., 'raiddebuffs', 'raidDebuffs')` |
| `Externals.lua:24` | `..., 'externals')` | `..., 'externals', 'externals')` |
| `Defensives.lua:24` | `..., 'defensives')` | `..., 'defensives', 'defensives')` |
| `MissingBuffs.lua:59` | `..., 'missingbuffs')` | `..., 'missingbuffs', 'missingBuffs')` |
| `PrivateAuras.lua:57` | `..., 'privateauras')` | `..., 'privateauras', 'privateAuras')` |
| `TargetedSpells.lua:58` | `..., 'targetedspells')` | `..., 'targetedspells', 'targetedSpells')` |
| `Dispels.lua:59` | `..., 'dispels')` | `..., 'dispels', 'dispellable')` |
| `CrowdControl.lua:67` | `..., 'crowdcontrol')` | `..., 'crowdcontrol')` *(no change — nil hides button)* |
| `LossOfControl.lua:85` | `..., 'lossofcontrol')` | `..., 'lossofcontrol')` *(no change — nil hides button)* |

- [ ] **Step 2: Add CopyToDialog.lua to Framed.toc**

Add `Settings/CopyToDialog.lua` after `Settings/Framework.lua` (line 139) so it loads before the panels that use it:

```
Settings/Framework.lua
Settings/CopyToDialog.lua
Settings/MainFrame.lua
```

- [ ] **Step 3: Commit**

```bash
git add Settings/Panels/Buffs.lua Settings/Panels/Debuffs.lua Settings/Panels/RaidDebuffs.lua \
       Settings/Panels/Externals.lua Settings/Panels/Defensives.lua Settings/Panels/MissingBuffs.lua \
       Settings/Panels/PrivateAuras.lua Settings/Panels/TargetedSpells.lua Settings/Panels/Dispels.lua \
       Framed.toc
git commit -m "feat: wire copy-to configKey to all aura panels and add CopyToDialog to TOC"
```
