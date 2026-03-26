# Copy-To Dialog Design Spec

## Overview

Replace the "coming soon" stub on the aura panel "Copy to..." button with a working dialog that copies the current aura panel's config from one unit type to one or more target unit types within the same preset.

## Goal

Let users quickly replicate aura settings (buffs, debuffs, externals, etc.) across unit types without manually reconfiguring each one.

## Scope

- Single aura panel scope — copies only the active panel's config (e.g., Buffs), not all aura configs
- Overwrite semantics — target config is replaced entirely, no merge
- Same-preset only — copies within the current editing preset
- **Excluded panels:** CrowdControl and LossOfControl store config globally (not per-preset/per-unit), so Copy-To does not apply. The "Copy to..." button should be hidden or disabled for these panels.

## Config Key Mapping

Panel IDs don't always match config keys. `BuildAuraUnitTypeRow` must accept an explicit `configKey` parameter to pass through to the dialog:

| Panel ID | Config Key |
|----------|-----------|
| `buffs` | `buffs` |
| `debuffs` | `debuffs` |
| `raiddebuffs` | `raidDebuffs` |
| `externals` | `externals` |
| `defensives` | `defensives` |
| `targetedspells` | `targetedSpells` |
| `dispels` | `dispellable` |
| `missingbuffs` | `missingBuffs` |
| `privateauras` | `privateAuras` |
| `crowdcontrol` | *(excluded — global config)* |
| `lossofcontrol` | *(excluded — global config)* |

The full config path for a copyable panel is: `presets.<preset>.auras.<unitType>.<configKey>`

## Dialog UX

**Trigger:** Click "Copy to..." button on any supported aura settings panel.

**Dialog layout:**
- **Title:** "Copy [Panel Label] Settings" — panel label looked up from `Settings._panels[panelId].label`
- **Subtitle:** "From: [Source Unit Type Label]"
- **Target selection:** `CreateMultiSelectButtonGroup` toggle buttons for each available unit type, excluding the current source. Buttons wrap horizontally.
- **Confirm button** — disabled until at least one target is selected
- **Cancel button** — dismisses the dialog

## Behavior

**On Confirm:**
1. Deep-clone the source config at `presets.<preset>.auras.<sourceUnit>.<configKey>`
2. For each selected target, write the clone via `F.Config:Set('presets.<preset>.auras.<targetUnit>.<configKey>', clonedTable)` — this fires `CONFIG_CHANGED` automatically
3. Call `F.PresetManager.MarkCustomized(presetName)`
4. Invalidate cached panel frames for affected targets (`Settings._panelFrames[panelId] = nil`)
5. Close dialog
6. Print confirmation: `"Framed: Copied [panel] settings from [source] to [target1], [target2], ..."`

**On Cancel:** Dismiss dialog, no changes.

## Deep Clone

A simple recursive table copy. Config values are plain Lua tables (numbers, strings, booleans, nested tables). No metatables, frames, or userdata to worry about.

## File Structure

| File | Action |
|------|--------|
| `Settings/CopyToDialog.lua` | **Create** — dialog frame, toggle buttons, confirm/cancel logic, deep clone, config write |
| `Settings/Framework.lua` | **Modify** — add `configKey` parameter to `BuildAuraUnitTypeRow`, expose `getUnitTypeItems` as `Settings._getUnitTypeItems()`, replace `print('coming soon')` with call to show dialog, hide button for excluded panels |
| `Framed.toc` | **Modify** — add `Settings/CopyToDialog.lua` |

## Unit Type List

Expose `getUnitTypeItems()` as `Settings._getUnitTypeItems()` (underscore-prefixed private convention). The dialog calls this and excludes the source unit type from the toggle button list.

## Existing Code Reuse

| Component | Location | Usage |
|-----------|----------|-------|
| `Widgets.CreateMultiSelectButtonGroup` | `Widgets/Button.lua:505` | Target unit type toggle buttons |
| `Widgets.CreateButton` | `Widgets/Button.lua` | Confirm/Cancel buttons |
| `Widgets.FadeIn/FadeOut` | `Widgets/Base.lua` | Dialog show/hide transitions |
| `Settings._getUnitTypeItems()` | `Settings/Framework.lua` | Unit type list |
| `Settings._panels[panelId].label` | `Settings/Framework.lua` | Panel display name |
| `Settings.GetEditingUnitType()` | `Settings/Framework.lua` | Source unit type |
| `Settings.GetEditingPreset()` | `Settings/Framework.lua` | Current preset name |

## Edge Cases

- **Only one unit type available:** If the preset only has one unit type (unlikely but possible), the button should be disabled or the dialog should show a message.
- **Source unit type has empty/default config:** Copy proceeds normally — the empty config overwrites the target, effectively resetting it.
- **Excluded panels (CrowdControl, LossOfControl):** Button hidden — these use global config paths, not per-unit-type.
