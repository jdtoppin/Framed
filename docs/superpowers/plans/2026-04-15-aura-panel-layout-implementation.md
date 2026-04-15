# Aura Panel Layout Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [`docs/superpowers/specs/2026-04-15-aura-panel-layout-design.md`](../specs/2026-04-15-aura-panel-layout-design.md)

**Goal:** Restructure the per-unit aura panels (Buffs, Debuffs, Defensives, Externals) so the Preview and Indicators/Overview cards pin side-by-side at the top while the selected indicator's settings scroll below. Replace the dedicated Create Indicator card with an inline form inside the Indicators card. Replace the sub-header Copy To modal with a `Copy to [target ▾] [Copy]` inline control that writes directly. Add a helper blurb under the shared Preview's `Show all enabled auras` toggle. Short CardGrid panels (Dispels, MissingBuffs, TargetedSpells, PrivateAuras, CrowdControl, LossOfControl) keep their CardGrid layout but inherit the sub-header and Preview changes for free.

**Architecture:** Extract a direct-write `F.Settings.CopyTo(configKey, targetUnitType)` helper from `Settings/CopyToDialog.lua` so both the old dialog and the new sub-header control share one code path. Replace the sub-header `_headerCopyToBtn` (single "Copy to..." button) with a three-widget control (label FontString + inline dropdown + Copy button) and rewire `activateAuraHeaderControls` in `Settings/Framework.lua` to populate the dropdown's target list and bind the Copy button to the helper. Add the `Show all enabled auras` helper blurb in the shared `Settings/Builders/AuraPreview.lua` so every panel that calls `BuildPreviewCard` inherits it. Reshape Buffs + Debuffs to drop the Create Indicator card, add an inline create form inside the Indicators card, give the Indicators card a fixed internal scroll region stretched to the Preview's height, and switch the selected-row highlight to a left-accent + gradient. Migrate Defensives + Externals off `CardGrid` to the same wrapper-grid pattern with `Preview | Overview` pinned on top and the remaining parameter cards scrolling below.

**Tech Stack:** Lua 5.1 (WoW runtime), oUF (embedded), Framed's in-house Widgets/Core/EventBus modules. No new external libraries.

## Scope guardrails — DO NOT TOUCH

This refactor is **visual reorganization only**. The only new functionality is the sub-header Copy To dropdown replacing the modal (Phase 2); everything else in Phases 3–4 is moving existing widgets into different parent frames or different anchor positions, using the same functions that already exist.

**Agents implementing this plan must not:**

- **Touch `Settings/Builders/AuraPreview.lua` beyond the Task 4 blurb insertion.** Do not modify `Render`, `BuildPreviewCard`'s preview frame construction, `Rebuild`, `UpdateDimming`, `UpdateDispelAlpha`, or the `CONFIG_CHANGED` auto-rebuild listener. The only edit to this file in the entire plan is adding the `Widgets.CreateFontString` blurb under the `Show all enabled auras` checkbox in Task 4.
- **Touch `PreviewAuras.BuildAll`, `SetAuraGroupAlpha`, or any `Elements/Auras/` code.** The preview renders itself; we just move the card it lives in.
- **Touch aura indicator rendering code** (see `feedback_aura_indicators_fragile` — prior agents have repeatedly broken this).
- **Touch the settings cards themselves** in any panel. `buildOverviewCard`, `buildDisplayCard`, `buildLayoutCard`, `buildDurationFontCard`, `buildStackFontCard`, `buildFilterModeCard`, `buildDisplaySettingsCard`, `buildPositionCard`, etc. — all stay byte-for-byte identical. Only the container they're parented into changes.
- **Touch `F.Settings.BuildPositionCard`, `F.Settings.BuildFontCard`, or any shared card builders** in `Settings/Cards/`.
- **Touch `CardGrid` itself.** Defensives/Externals migrate *off* CardGrid, but CardGrid stays in place for the short panels (Dispels, MissingBuffs, TargetedSpells, PrivateAuras, CrowdControl, LossOfControl).
- **Touch config paths, defaults, or schema.** No new keys in `Presets/Defaults.lua` or `Core/Config.lua`. `presets.<preset>.auras.<unitType>.<configKey>` stays exactly as-is.
- **Touch validation rules for creating indicators.** The inline create form in Phase 3 reuses the exact same `createBtn:SetOnClick` wiring from today's Create card — same name validation, same type/display semantics, same commit path. The only change is which parent frame the Name/Type/Display widgets are anchored into.
- **Touch live-update wiring.** `F.EventBus` events (`CONFIG_CHANGED`, `SETTINGS_RESIZED`, `SETTINGS_RESIZE_COMPLETE`), `UpdateAuraPreviewDimming`, `MarkCustomized`, and the `_panelFrames[panelId] = nil` + `RefreshActivePanel` invalidation pattern all stay functionally identical. Phase 4 task notes mention rebuild-on-resize because the grid helper goes away, but the *events* and *event handlers' bodies* are unchanged — just their call sites.
- **Touch the "Configure for" unit-type dropdown** (`Settings._headerUnitTypeDD`) or any of its wiring. The dropdown items, label prefix, `SetEditingUnitType` callback, and per-panel population in `activateAuraHeaderControls` (`Framework.lua:214-229`) all stay exactly as-is. The Phase 2 Copy To control anchors to the *right* of this dropdown but does not modify it. Do not touch `buildHeaderUnitTypeItems`, `frameUnitLabel`, `unitTypeLabel`, `_getUnitTypeItems`, `GetEditingUnitType`, or `SetEditingUnitType`.
- **Touch the preset system.** `F.PresetManager`, `GetEditingPreset`, `SetEditingPreset`, `MarkCustomized`, `_headerPresetText`, preset switching, preset creation/duplication/deletion, the `Editing: Default` indicator on the far right of the sub-header — none of this changes. Copy To still calls `MarkCustomized(presetName)` the same way it does today; the helper extracted in Task 1 preserves that call.
- **Touch sidebar, panel registration, or panel routing.** `Settings.RegisterPanel`, `SetActivePanel`, `_activePanelId`, sidebar sections/subsections, the `subSection = 'auras'` grouping, panel order, and all navigation wiring stay as-is. Phase 3 and 4 edit the *bodies* of specific panels' `create` functions, not how those panels register or get routed to.
- **Add new Widgets.** Exception: Phase 3 Task 5 Step 5 may need a dashed-border inset helper in `Widgets/Base.lua` if one doesn't already exist. Check first — do not add one speculatively.
- **Refactor adjacent code "while you're there."** If a card's builder has weird patterns, leave them alone. This is a layout refactor, not a cleanup pass.
- **Leave stubs or TODO placeholders.** Each task lands its full feature or doesn't land at all. In Phase 3 particularly, do not ship a half-built inline create form with a "TODO: wire Create button" comment — either the form commits real indicators or the task isn't done. Same for the selected-row highlight, the `Editing:` label, and every Phase 4 card migration. (See `feedback_no_stubs` memory — prior agents have shipped "Coming Soon" placeholders and it's a hard rule not to.)

**What agents *may* touch (exhaustive list):**

- `Settings/CopyToDialog.lua` — extract helper (Task 1), possibly delete (Task 9).
- `Settings/MainFrame.lua` — replace the 4-line button creation with 3 widget creations (Task 2).
- `Settings/Framework.lua` — rewrite the Copy To show/hide/wiring blocks in `activateAuraHeaderControls` (Task 3).
- `Settings/Builders/AuraPreview.lua` — add the blurb FontString only (Task 4). Nothing else in this file.
- `Settings/Panels/Buffs.lua` — drop Create card, add inline create form, reshape Indicators card, update row highlight, add Editing label (Task 5).
- `Settings/Panels/Debuffs.lua` — same as Buffs plus preserve Filter mode dropdown (Task 6).
- `Settings/Panels/Defensives.lua` — migrate off CardGrid to wrapper grid (Task 7).
- `Settings/Panels/Externals.lua` — same migration as Defensives (Task 8).
- `Framed.toc` — remove `CopyToDialog.lua` line if deleted (Task 9).
- `CHANGELOG.md` and the sync-changelog output in `Settings/Cards/About.lua` — document the refactor (Task 9).

If a task seems to require touching a file not on this list, **stop and ask** — it means either this plan missed something or the implementation is drifting out of scope.

## Testing approach

Framed has no unit test framework — Lua code runs inside the WoW client. Each task has an explicit `/reload` verification section listing what to click, what to observe, and what the expected behavior is. Static checks run via `luacheck . --config .luacheckrc` locally and in CI. The existing GitHub Actions workflow lints every push.

**Sync for testing:** After editing files, sync to your WoW AddOns folder so `/reload` picks up changes. The user has a local sync script; confirm with them if the path isn't obvious.

## File structure

**New files:** none.

**Files modified (Phase 1–2):**

- `Settings/CopyToDialog.lua` — Extract the deep-clone + `Config:Set` block from the OK handler into a new `F.Settings.CopyTo(configKey, targetUnitType)` module-level function. Rewrite the OK handler to loop over `multiGroup._selected` calling `F.Settings.CopyTo` per target. No UX change.
- `Settings/MainFrame.lua` — Replace the `_headerCopyToBtn` button (lines 254–257) with three widgets anchored in the same spot: a "Copy to" FontString label, `Settings._headerCopyToDD` (inline dropdown), and `Settings._headerCopyToBtn` (now a small accent button). All three hide together when the active panel has no `configKey`.
- `Settings/Framework.lua` — Update `activateAuraHeaderControls` (lines 199–260) to populate the new dropdown with the panel's valid copy-to targets (current unit type excluded), wire the Copy button to `F.Settings.CopyTo(configKey, dropdown:GetValue())`, and show/hide the new label+dropdown alongside the button. Remove the `ShowCopyToDialog`-driven `SetOnClick` at line 234.

**Files modified (Phase 3):**

- `Settings/Builders/AuraPreview.lua` — In `BuildPreviewCard` (line 136), add a `Widgets.CreateFontString` helper blurb directly below the `Show all enabled auras` checkbox with the spec-mandated copy. Returns a taller card; panels that anchor off `previewCard:GetHeight()` pick up the new height automatically.
- `Settings/Panels/Buffs.lua` — Remove the Create Indicator card. Keep the Preview + Indicators pinned row but drop the left column's `createCard` anchoring. Give the Indicators card a fixed internal scroll region matching the Preview's stretched height. Add an inline `+ click to add new...` title-row control and an expandable inline create form (Name / Type / Display fields + Create button) that lives between the title row and the list header. Switch the selected row visual to `border-left + linear-gradient` (drop the full-border highlight). Add a small `Editing: <name> (<type>, <anchor>)` label above the settings cards in the scroll region.
- `Settings/Panels/Debuffs.lua` — Same changes as Buffs, plus preserve the `Filter mode` dropdown in the inline create form (pre-row above Name/Type/Display, since it's the narrowest semantic match for the existing placement).

**Files modified (Phase 4):**

- `Settings/Panels/Defensives.lua` — Migrate off `CardGrid`. Build a wrapper-grid pinned row with `Preview (natural width) | Overview (1fr)`, both stretched to match the taller of the two. Below the pinned row: `Display`, `Layout`, `Duration`, `Stacks` parameter cards in the same order they appear today, rendered into an internal scroll region. Drop `grid:SetSticky('preview')`.
- `Settings/Panels/Externals.lua` — Same migration as Defensives. Card shape is identical (same `buildOverviewCard` / `buildDisplayCard` / `buildLayoutCard` / `buildDurationFontCard` / `buildStackFontCard` builders), so the migration is a near-mechanical copy.

**Files modified (Phase 5 — cleanup):**

- `Settings/CopyToDialog.lua` — Delete entirely if nothing else references `Settings.ShowCopyToDialog` after Phase 2. Grep first.
- `Framed.toc` — Remove `Settings/CopyToDialog.lua` from the load order if deleted above.
- `CHANGELOG.md` — Add an entry under the next version block describing the layout refactor.

## Task dependency graph

```
Phase 1: Task 1 (extract CopyTo helper)
           │
           ▼
Phase 2: Task 2 (sub-header control widgets)
           │
           ▼
         Task 3 (Framework wiring)
           │
           ▼
Phase 3: Task 4 (shared Preview blurb)
           │
           ├──▶ Task 5 (Buffs layout)
           │
           └──▶ Task 6 (Debuffs layout)
                   │
                   ▼
Phase 4: Task 7 (Defensives migration)
           │
           ▼
         Task 8 (Externals migration)
           │
           ▼
Phase 5: Task 9 (dialog cleanup + changelog)
```

Phases 1–2 are pure plumbing with no visual change to the non-sub-header UI. Phase 3 (Tasks 4–6) lands the visible Buffs/Debuffs reshape. Phase 4 (Tasks 7–8) migrates Defensives + Externals. Phase 5 (Task 9) cleans up and documents.

## Per-phase shippability

**Every phase leaves `working-testing` in a shippable state.** The implementer may pause at the end of any phase — commit, push, open a PR, ship an alpha build — without leaving the addon half-broken. Concretely:

- **After Phase 1:** pure refactor. The dialog's OK handler now routes through `F.Settings.CopyTo` but observable behavior is unchanged. Ship anytime.
- **After Phase 2:** the new sub-header Copy To control is live on all applicable aura panels and the old dialog path is dormant but still present. Ship anytime.
- **After Phase 3:** Buffs and Debuffs use the new pinned-row layout with the inline create form; all other aura panels keep their current CardGrid layout (unchanged visually except for the Task 4 Preview blurb and the Task 3 sub-header Copy To). Ship anytime — Buffs/Debuffs look new, everything else looks old-but-working.
- **After Phase 4:** Defensives and Externals join Buffs/Debuffs on the wrapper-grid pattern; Dispels/MissingBuffs/TargetedSpells/PrivateAuras/CrowdControl/LossOfControl still use CardGrid. Ship anytime.
- **After Phase 5:** `CopyToDialog.lua` is gone (if dead) and the CHANGELOG documents the refactor.

If a phase stalls mid-way (e.g. Phase 3 Task 5 reveals a blocker during Buffs reshape), roll the branch back to the last completed task's commit — everything before that point is green and shippable. **Do not mix phases within a single commit**; the per-task commits in each phase are the rollback points.

---

## Phase 1 — Extract Copy To helper

### Task 1: Extract `F.Settings.CopyTo` from the dialog's OK handler

**Why:** The new sub-header control needs to copy to a single target without opening a modal, but the existing deep-clone + `Config:Set` + `MarkCustomized` + panel-cache-invalidate + `RefreshActivePanel` sequence lives inside the dialog's OK handler at `CopyToDialog.lua:153-181`. Extracting it into a module-level helper gives both the old dialog (which still exists until Phase 5) and the new sub-header control one shared implementation, so there's no risk of the two paths diverging.

**Files:**

- Modify: `Settings/CopyToDialog.lua`

- [ ] **Step 1: Read the full current file**

Run: Read `Settings/CopyToDialog.lua`

Expected: 196 lines. The critical section is lines 153–181 (the `_confirmBtn:SetScript('OnClick', ...)` handler) and the module-local `deepClone` helper at lines 23–30.

- [ ] **Step 2: Add `F.Settings.CopyTo` near the top of the file**

Add a new module-level function just below the `deepClone` local (after line 30, before `buildDialog`). This function is the extracted core of the OK handler's per-target block:

```lua
-- ── Public helper: copy aura config to a single target ──────
-- Overwrite semantics (same as the dialog's OK handler).
--   configKey       e.g. 'buffs', 'debuffs', 'externals'
--   targetUnitType  e.g. 'target', 'focus', 'party', 'raid'
-- Returns true on success, false if nothing was copied.
function Settings.CopyTo(configKey, targetUnitType)
	if(not configKey or not targetUnitType) then return false end
	if(not F.Config) then return false end

	local sourceUnit = Settings.GetEditingUnitType()
	if(not sourceUnit or sourceUnit == targetUnitType) then return false end

	local presetName = Settings.GetEditingPreset()
	if(not presetName) then return false end

	local sourcePath = 'presets.' .. presetName .. '.auras.' .. sourceUnit .. '.' .. configKey
	local targetPath = 'presets.' .. presetName .. '.auras.' .. targetUnitType .. '.' .. configKey

	local sourceData = F.Config:Get(sourcePath)
	F.Config:Set(targetPath, deepClone(sourceData))

	if(F.PresetManager) then
		F.PresetManager.MarkCustomized(presetName)
	end

	return true
end
```

Notes for implementers:
- The `no-op if source == target` guard is new relative to the dialog path, because the dialog excludes the source from its target list in the UI. The sub-header dropdown will too, but the helper should still be safe against direct callers.
- The helper does **not** invalidate `Settings._panelFrames[panelId]` or call `RefreshActivePanel` — those are UI responsibilities belonging to the caller that knows which panel is active. Dialog callers do it in a loop prologue/epilogue (see Step 3); sub-header callers do it in Task 3.

- [ ] **Step 3: Rewrite the OK handler to use the helper**

Replace lines 153–181 with a loop that calls `Settings.CopyTo` per selected target, then performs the panel-invalidate + refresh + print side effects once after the loop. The new handler body:

```lua
-- Wire confirm action
dialog._confirmBtn:SetScript('OnClick', function()
	local sourceLabel -- recomputed for the print output
	local items = Settings._getUnitTypeItems()
	local sourceUnit = Settings.GetEditingUnitType()
	for _, item in next, items do
		if(item.value == sourceUnit) then
			sourceLabel = item.text
			break
		end
	end

	-- Build a value→label lookup for friendly print output
	local labelLookup = {}
	for _, item in next, items do
		labelLookup[item.value] = item.text
	end

	local copiedTo = {}
	for targetUnit in next, multiGroup._selected do
		if(Settings.CopyTo(configKey, targetUnit)) then
			copiedTo[#copiedTo + 1] = labelLookup[targetUnit] or targetUnit
		end
	end

	-- Invalidate cached panel so it rebuilds with new config
	Settings._panelFrames[panelId] = nil

	Widgets.FadeOut(dialog, 0.15, function() dialog:Hide() end)

	if(F.Settings.RefreshActivePanel) then
		F.Settings.RefreshActivePanel()
	end

	if(#copiedTo > 0) then
		print('Framed: Copied ' .. panelLabel .. ' settings from ' .. (sourceLabel or sourceUnit) .. ' to ' .. table.concat(copiedTo, ', '))
	end
end)
```

This is a pure refactor — the dialog's observable behavior is unchanged. The `sourceLabel` lookup that used to happen inside `buildDialog` for the subtitle still happens there; we recompute it inside the handler here only because the handler needs it for the print line.

- [ ] **Step 4: Lint**

Run: `luacheck Settings/CopyToDialog.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 5: Reload in WoW and verify**

Run in-game:
1. `/reload`
2. Open Settings → Buffs, click `Copy to...` in the sub-header.
3. In the modal, check two target unit types (e.g. Target and Focus) and click Confirm.
4. Expected: chat prints `Framed: Copied Buffs settings from <source> to <Target>, <Focus>`. Both targets' Buffs config now mirrors the source.
5. Verify the active panel re-rendered (scroll region rebuilds without a flicker artifact).

- [ ] **Step 6: Commit**

```bash
git add Settings/CopyToDialog.lua
git commit -m "Extract F.Settings.CopyTo helper from dialog OK handler"
git push origin working-testing
```

---

## Phase 2 — Sub-header Copy To dropdown

### Task 2: Replace `_headerCopyToBtn` with label + dropdown + button

**Why:** The current sub-header has a single `Copy to...` button that opens the modal. The spec calls for an inline `Copy to [Target ▾] [Copy]` control so the user can push the active panel's config to a specific target without leaving the settings window. This task creates the three new widgets at the same anchor the old button used, leaving them hidden until Task 3 wires them up.

**Files:**

- Modify: `Settings/MainFrame.lua`

- [ ] **Step 1: Read the sub-header construction region**

Run: Read `Settings/MainFrame.lua` lines 219–275

Expected: `titleCard` frame, `_headerPanelText`, `_headerUnitTypeDD`, `_headerCopyToBtn` (lines 254–257), `_headerIndicatorText`, `_headerPresetText`. The Copy To button is anchored `LEFT` of its previous sibling `_headerUnitTypeDD` via `Widgets.SetPoint(Settings._headerCopyToBtn, 'LEFT', Settings._headerUnitTypeDD, 'RIGHT', 8, 0)`.

- [ ] **Step 2: Replace the single-button creation with three widgets**

In `Settings/MainFrame.lua`, replace the block at lines 251–257 (the `-- ── Copy-to button next to the inline dropdown ──` comment through `Settings._headerCopyToBtn:Hide()`) with:

```lua
-- ── Copy-to control (label + dropdown + Copy button) ───────
-- Visible only on aura panels that registered a configKey.
-- Framework.activateAuraHeaderControls populates the dropdown and
-- wires the button per panel.
Settings._headerCopyToLabel = Widgets.CreateFontString(titleCard, C.Font.sizeNormal, C.Colors.textNormal)
Settings._headerCopyToLabel:ClearAllPoints()
Widgets.SetPoint(Settings._headerCopyToLabel, 'LEFT', Settings._headerUnitTypeDD, 'RIGHT', 12, 0)
Settings._headerCopyToLabel:SetText('Copy to')
Settings._headerCopyToLabel:Hide()

Settings._headerCopyToDD = Widgets.CreateInlineDropdown(titleCard)
Settings._headerCopyToDD:ClearAllPoints()
Widgets.SetPoint(Settings._headerCopyToDD, 'LEFT', Settings._headerCopyToLabel, 'RIGHT', 4, 0)
Settings._headerCopyToDD:Hide()

Settings._headerCopyToBtn = Widgets.CreateButton(titleCard, 'Copy', 'accent', 52, 20)
Settings._headerCopyToBtn:ClearAllPoints()
Widgets.SetPoint(Settings._headerCopyToBtn, 'LEFT', Settings._headerCopyToDD, 'RIGHT', 6, 0)
Settings._headerCopyToBtn:Hide()
```

Implementation notes:
- `Widgets.CreateInlineDropdown` already exists (used for `_headerUnitTypeDD` at line 246) and renders a compact "▾" dropdown — the right primitive for inline chrome.
- The `accent` style button is intentional — it's the commit action for the control and should read as primary. If the style looks wrong during visual review, fall back to `'widget'` like the old button.
- All three widgets stay at the `LEFT`-of-previous chain rooted at `_headerUnitTypeDD`, so when `_headerIndicatorText` is shown (drill-in breadcrumb), the whole copy-to control is pushed to the right along with it automatically.

**Important:** `_headerIndicatorText` is anchored `LEFT → _headerUnitTypeDD:RIGHT + 8` at line 263. After this change, it still anchors off `_headerUnitTypeDD`, so when drilled into an indicator the copy-to widgets and the breadcrumb text will overlap. Solution: Task 3 hides the copy-to control whenever the drill-in breadcrumb is visible (it already does this implicitly — drilled-in panels aren't the "base aura page" where Copy To belongs). Leave the anchor as-is.

- [ ] **Step 3: Lint**

Run: `luacheck Settings/MainFrame.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 4: Reload and verify the new widgets render**

At this point the widgets exist but are never shown (Task 3 wires that up). Sanity check:
1. `/reload`
2. Open Settings → Buffs.
3. Expected: the sub-header looks **identical to before Task 1** — no Copy To button visible, because we haven't shown the new widgets yet. This confirms we didn't break the `Hide()` path.
4. Run `/run print(Framed.Settings._headerCopyToLabel ~= nil, Framed.Settings._headerCopyToDD ~= nil, Framed.Settings._headerCopyToBtn ~= nil)` and expect `true, true, true`.

- [ ] **Step 5: Commit**

```bash
git add Settings/MainFrame.lua
git commit -m "Replace sub-header Copy To button with label+dropdown+button control"
git push origin working-testing
```

### Task 3: Wire the sub-header control in `Framework.lua`

**Why:** `activateAuraHeaderControls` (`Settings/Framework.lua:199-260`) is the single point where sub-header state is set per panel. Today it shows/hides the old `copy` button and wires its `SetOnClick` to `ShowCopyToDialog`. After this task it will also populate `_headerCopyToDD` with the valid-target list, bind the Copy button to `F.Settings.CopyTo`, and show/hide the new `_headerCopyToLabel` + `_headerCopyToDD` alongside the button.

**Files:**

- Modify: `Settings/Framework.lua`

- [ ] **Step 1: Read `activateAuraHeaderControls` end-to-end and verify the InlineDropdown API**

Run: Read `Settings/Framework.lua` lines 195–275 (the whole function).

Expected: The function hides all header controls for non-aura panels at lines 205–212, populates `_headerUnitTypeDD` for aura panels at lines 214–229, then handles the copy-to button at lines 231–244. The breadcrumb / drill-in text handling follows after.

Also grep `Widgets/` for the `InlineDropdown` definition and confirm it exposes `:SetItems`, `:SetValue`, `:SetOnSelect`, and `:GetValue`. The first three are confirmed in use at `Framework.lua:217-228` (via `_headerUnitTypeDD`). `:GetValue` is used in the handler below — if it doesn't exist, track the selected value in a closure via `SetOnSelect` instead, and read that closure variable inside the Copy button's click handler.

- [ ] **Step 2: Rewrite the Copy To block**

Replace lines 231–244 (the `-- Copy-to: visible only when ...` block, ending with `copy:Show()` / `else ... copy:Hide()`) with logic that populates the dropdown and wires the button:

```lua
-- Copy-to: visible only when the panel registered a configKey.
local configKey = Settings._auraConfigKeys[info.id]
local copyLabel = Settings._headerCopyToLabel
local copyDD    = Settings._headerCopyToDD
if(configKey) then
	-- Build target list = all unit types EXCEPT the current source.
	local sourceUnit = Settings.GetEditingUnitType()
	local targets = {}
	for _, item in next, Settings._getUnitTypeItems() do
		if(item.value ~= sourceUnit) then
			targets[#targets + 1] = { text = item.text, value = item.value }
		end
	end

	if(#targets == 0) then
		-- Only one unit type exists — nothing to copy to.
		if(copyLabel) then copyLabel:Hide() end
		if(copyDD) then copyDD:Hide() end
		copy:Hide()
	else
		if(copyDD) then
			copyDD:SetItems(targets)
			copyDD:SetValue(targets[1].value)
			copyDD:Show()
		end
		if(copyLabel) then copyLabel:Show() end

		copy:SetOnClick(function()
			local target = copyDD and copyDD:GetValue() or nil
			if(not target) then return end
			if(Settings.CopyTo(configKey, target)) then
				-- Invalidate + refresh so the active panel rebuilds
				-- against the new config.
				Settings._panelFrames[info.id] = nil
				if(Settings.RefreshActivePanel) then
					Settings.RefreshActivePanel()
				end
				-- Friendly chat confirmation (mirrors dialog output).
				local targetLabel = target
				for _, item in next, Settings._getUnitTypeItems() do
					if(item.value == target) then targetLabel = item.text; break end
				end
				print('Framed: Copied ' .. (info.label or info.id) .. ' settings to ' .. targetLabel)
			end
		end)
		copy:Enable()
		copy:Show()
	end
else
	if(copyLabel) then copyLabel:Hide() end
	if(copyDD) then
		if(copyDD.Close) then copyDD:Close() end
		copyDD:Hide()
	end
	copy:Hide()
end
```

Notes:
- The label + dropdown Hide path is added to both the non-aura early-return at line 205 (update that block too — see Step 3) and the `configKey == nil` branch above.
- The "only one unit type" path now hides the entire control instead of disabling the button, because an empty dropdown would look broken.
- The `GetValue`-returns-nil defense guards against race conditions where the dropdown was Hide()'d mid-click; cheap to include.
- `info.label` is the panel's registered label (e.g. `'Buffs'`), which reads more naturally than the raw id.

- [ ] **Step 3: Update the non-aura early return to hide the new widgets**

In the same function, at lines 205–212, the non-aura branch currently calls `copy:Hide()`. Update it to also hide the label and dropdown:

```lua
if(not info or info.subSection ~= 'auras') then
	if(dd.Close) then dd:Close() end
	dd:Hide()
	if(Settings._headerCopyToLabel) then Settings._headerCopyToLabel:Hide() end
	if(Settings._headerCopyToDD) then
		if(Settings._headerCopyToDD.Close) then Settings._headerCopyToDD:Close() end
		Settings._headerCopyToDD:Hide()
	end
	copy:Hide()
	indic:Hide()
	indic:SetText('')
	return
end
```

- [ ] **Step 4: Verify indicator drill-in still hides Copy To**

Grep for `_headerCopyToBtn` in `Framework.lua` to find any other places (around line 470 per earlier grep) that hide/show the button. Each of those sites needs the same label+dropdown treatment. Specifically:

Run: Grep `_headerCopyToBtn` in `Settings/Framework.lua`

Expected: at least two hits — the Copy-to block above (just rewritten) and another near line 470. Update the second site to also hide/show `Settings._headerCopyToLabel` and `Settings._headerCopyToDD` in parallel with the button.

- [ ] **Step 5: Lint**

Run: `luacheck Settings/Framework.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 6: Reload and test every aura panel**

Run in-game, for each of `Buffs`, `Debuffs`, `Defensives`, `Externals`, `Dispels`, `MissingBuffs`, `TargetedSpells`, `PrivateAuras`:

1. Open Settings → <panel>.
2. Expected: sub-header shows `Configure for: Player Frame ▾ / Copy to [Target Frame ▾] [Copy]  Editing: Default` (with the exact text varying per panel/unit).
3. Select a target from the dropdown.
4. Click Copy.
5. Expected: chat prints the "Copied ... settings to ..." line. Switch the unit-type dropdown to the target you just copied to and verify the destination config matches the source.

Then for `CrowdControl` and `LossOfControl`:
1. Open the panel.
2. Expected: sub-header shows only `Configure for: ...` (no Copy To label, dropdown, or button) — these panels store global config and have no valid copy destinations.

Then drill into a specific indicator on Buffs (click an indicator row):
1. Expected: breadcrumb text appears (`Buffs / Player Frame ▾  >  <indicator name>`), Copy To control is hidden (this is the existing drill-in hide path, which still works because we share the same `copy:Hide()` call site).

- [ ] **Step 7: Commit**

```bash
git add Settings/Framework.lua
git commit -m "Wire sub-header Copy To control: dropdown + direct-write button"
git push origin working-testing
```

---

## Preview reparenting contract (read before Phase 3 and Phase 4)

The shared `AuraPreview` frame is a **per-panel singleton** whose lifecycle is juggled across panel switches via three pieces of state. Every panel reshape in Phases 3–4 must preserve this contract or panel-switching will break (preview disappears, fails to re-render, or gets orphaned as a visible frame with no parent).

**The three state slots:**

1. `Settings._auraPreview` — global pointer to the *currently active* preview frame. Set by `F.Settings.AuraPreview.BuildPreviewCard` at `Settings/Builders/AuraPreview.lua:153` during panel build. Read by `UpdateAuraPreviewDimming`, `Rebuild`, `UpdateDispelAlpha`, and the `CONFIG_CHANGED` auto-rebuild listener.
2. `scroll._ownedPreview` — per-panel stash. Every aura panel's `create()` function ends with `scroll._ownedPreview = F.Settings._auraPreview` (see `Settings/Panels/Buffs.lua:680`, `Defensives.lua:242`, etc.). This is how each panel remembers which preview frame belongs to it.
3. `Settings._activePanelFrame._ownedPreview` — the restore source. On panel switch, `SetActivePanel` at `Settings/Framework.lua:398-409` checks the incoming panel's `_ownedPreview` field; if present, it reassigns `Settings._auraPreview` to that frame and calls `AuraPreview.Render` to refresh it against current config. This is how returning to a previously-built panel recovers its preview instead of creating a new one.

**Invariants each Phase 3/4 reshape must preserve:**

- **The preview frame must be (transitively) parented to the panel's top-level `scroll` return value**, so it naturally hides when the panel hides and shows when the panel shows. In Phase 3, the preview's new parent will be whatever frame holds the pinned row — that frame must itself be a descendant of `scroll:GetContentFrame()`. In Phase 4, same requirement: the new wrapper-grid pinned-row container must live inside `scroll:GetContentFrame()`, not float free.
- **`scroll._ownedPreview = F.Settings._auraPreview` must remain the last line of `create()`** (or at minimum, must run *after* `BuildPreviewCard` has set `Settings._auraPreview`). Phases 3 and 4 must preserve this assignment verbatim. Do not rename the field; `SetActivePanel` reads it by that exact name.
- **Never destroy the preview frame on panel hide.** `MainFrame.lua:333-338` explicitly clears the global pointer (`Settings._auraPreview = nil`) *without* destroying the frame — and the inline comment there warns that destruction orphans the frame while `_ownedPreview` still references it, breaking the restore path. If any Phase 3/4 cleanup hook is added (e.g. `scroll:HookScript('OnHide', ...)`), it must not call `AuraPreview.Destroy` or `:SetParent(nil)` on the preview.
- **`Framework.lua:423-425` clears `_auraPreview` when switching away from non-aura panels.** This is existing behavior; don't touch it.
- **`BuildPreviewCard` assigns `Settings._auraPreview = preview` internally** — callers must not re-assign it. Phase 4's migration replaces `grid:AddCard('preview', ..., F.Settings.AuraPreview.BuildPreviewCard, {})` with a direct `F.Settings.AuraPreview.BuildPreviewCard(pinnedLeftFrame, previewWidth)` call; `Settings._auraPreview` gets set correctly by that call without any further bookkeeping.

**Concrete contract for Phase 4's Defensives/Externals migration:**

Replace this current shape (`Settings/Panels/Defensives.lua:186-195`):

```lua
local grid = Widgets.CreateCardGrid(content, width)
grid:SetTopOffset(math.abs(yOffset))

grid:AddCard('preview',      'Preview',          F.Settings.AuraPreview.BuildPreviewCard, {})
grid:SetSticky('preview')
grid:AddCard('overview',     'Overview',         buildOverviewCard,     {})
-- … other cards …
```

With something like this (shape only — fill in wrapper + inner scroll frames per Phase 4 Task 7):

```lua
-- Pinned row: Preview (left) + Overview (right), both parented to `content`
local pinnedRow = CreateFrame('Frame', nil, content)
-- … anchor pinnedRow to content ...

local previewCard = F.Settings.AuraPreview.BuildPreviewCard(pinnedRow, previewWidth)
-- BuildPreviewCard has now set Settings._auraPreview internally.

local overviewCard = buildOverviewCard(pinnedRow, overviewWidth)
-- … anchor both cards, stretch to match heights ...

-- Scroll region below pinned row, also parented through `content`
-- hosts Display / Layout / Duration / Stacks cards.
-- … build inner scroll region, add cards ...

-- Preserve the reparenting contract:
scroll._ownedPreview = F.Settings._auraPreview
```

The last line is what makes panel-switching work. Verify by: open Defensives, switch to Externals, switch back to Defensives — the preview should render without flicker and without creating a duplicate frame. If switching away and back leaves a blank Preview card, the contract was broken somewhere above.

---

## Phase 3 — Buffs + Debuffs reference layout

### Task 4: Add `Show all enabled auras` helper blurb in shared builder

**Why:** The spec's Preview card gets a small helper blurb under the `Show all enabled auras` checkbox explaining what the toggle does. Since `Settings/Builders/AuraPreview.lua` is the shared builder every aura panel calls into, one edit here covers Buffs, Debuffs, Defensives, Externals, and all the short CardGrid panels simultaneously.

**Files:**

- Modify: `Settings/Builders/AuraPreview.lua`

- [ ] **Step 1: Read the `BuildPreviewCard` function**

Run: Read `Settings/Builders/AuraPreview.lua` lines 136–176.

Expected: The function creates the preview frame, adds a `Show All Enabled Auras` checkbox at line 159, then calls `Widgets.EndCard`. The blurb needs to land between the checkbox and `EndCard`, advancing the `cy` cursor.

- [ ] **Step 2: Insert the blurb after the checkbox placement**

After the `cy = cy - CHECK_H` line (line 167), add:

```lua
-- Helper blurb explaining the toggle
local blurb = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
blurb:SetWidth(width - Widgets.CARD_PADDING * 2)
blurb:SetJustifyH('LEFT')
blurb:SetWordWrap(true)
blurb:SetText('Renders every enabled indicator simultaneously so you can see how they stack on this unit frame. Turn off to preview only the selected indicator.')
blurb:ClearAllPoints()
Widgets.SetPoint(blurb, 'TOPLEFT', inner, 'TOPLEFT', 0, cy - 2)
cy = cy - blurb:GetStringHeight() - C.Spacing.tight
```

The `-2` y-offset tucks the blurb right under the checkbox label without adding a full `Spacing.normal` gap, matching the spec mock.

- [ ] **Step 3: Lint and reload**

Run: `luacheck Settings/Builders/AuraPreview.lua --config .luacheckrc` — expect clean.

Run: `/reload`, open every aura panel in turn, and verify the Preview card now shows the blurb text directly beneath the checkbox. The card grows by ~2 lines of text height. Other cards that anchor off `previewCard:GetHeight()` (Buffs/Debuffs create card + list card) will shift — confirm Buffs and Debuffs still render (they'll look slightly off until Task 5/6 reshape them, but the blurb shouldn't cause a runtime error).

- [ ] **Step 4: Commit**

```bash
git add Settings/Builders/AuraPreview.lua
git commit -m "Add helper blurb under Show all enabled auras toggle"
git push origin working-testing
```

### Task 5: Reshape Buffs — drop Create card, inline create form, internal scroll

**Why:** The Create Indicator card is permanently visible but users only need it briefly, so it wastes vertical space. Moving creation inline into the Indicators card title row hides the creation UI unless the user clicks `+`, and giving the Indicators card a fixed internal scroll region means users never lose access to the indicator list when they scroll down to edit Position/Filters on the selected indicator.

**Files:**

- Modify: `Settings/Panels/Buffs.lua`

**Scroll anatomy — read this before starting:**

The reshaped panel has **two separate scroll regions**, not one. Do not conflate them.

1. **Outer panel scroll** (existing, unchanged): the `Widgets.CreateScrollFrame` at the top of the `create` function that wraps the entire panel body. This scroll region already exists today and continues to host the pinned row's anchor + the settings cards below it. When the user scrolls the panel, this is what scrolls. The pinned row pins *within* this scroll's content frame — not above it — so "pinned" here means "at the top of the scrollable content," which matches how Buffs/Debuffs already work today. Do not remove or replace this scroll frame.
2. **Indicators-list inner scroll** (new): a second `Widgets.CreateScrollFrame` *inside* the Indicators card's inner content area, holding only the indicator rows. Its height is fixed to match `previewCard:GetHeight()` so the card doesn't stretch arbitrarily. When the user has 40 indicators, this inner scroll lets them browse without pushing the settings cards down the page.

The outer scroll already works today; the inner scroll is the new piece. The outer scroll's content height continues to be driven by `grid:GetTotalHeight()` for the settings CardGrid below the pinned row.

**Structural outline (expand during implementation):**

- [ ] **Step 1:** Read the current layout in `Settings/Panels/Buffs.lua` (roughly lines 180–360) to locate the Preview/Create/List anchoring and the `spawnSettingsCards` / list-row rendering code. The current shape matches Debuffs: `Preview` + `Create` stacked in a ~40% left column with a `List` card in the ~60% right column, their heights linked via `leftColumnH = previewCardH + CARD_GAP + createCard:GetHeight()`.
- [ ] **Step 2:** Delete the Create card block. Change the pinned row layout to `Preview (natural width) | Indicators (1fr)` — Preview keeps its top accent bar and width, Indicators fills the rest of the row.
- [ ] **Step 3:** Give the Indicators card a fixed internal scroll region whose height = `previewCard:GetHeight()` (so the card stretches to the Preview's new blurb-inclusive height).
- [ ] **Step 4:** Add the inline `+ click to add new...` control in the Indicators card title row. `+` is an icon button; when clicked it toggles the expanded-create form state and swaps to an `×` cancel glyph.
- [ ] **Step 5:** Build the expandable inline create form between the title row and the list column header. Fields (horizontally): Name editbox, Type dropdown, Display dropdown. Row below the fields: type description FontString (left) + `Create` accent button (right). Form is hidden by default and has a dashed-accent inset border (check `Widgets/Base.lua` for an existing dashed-border helper; add one if missing).
- [ ] **Step 6:** Rewire the existing `createBtn:SetOnClick` wiring from the old Create card onto the new inline form's Create button. Existing validation rules (non-empty name, unique name, etc.) port over unchanged.
- [ ] **Step 7:** Update the selected-row visual. Replace the full-border highlight (look for `SetBackdropBorderColor` on the row frame) with:
    - A 2-pixel accent-colored left bar (`Widgets.CreateAccentBar(row, 'left')` if the helper supports `'left'`; otherwise construct a small `Texture` manually).
    - A 90°-horizontal `accent-dim → transparent` background gradient on the row. Use `Widgets.SetGradient` or the raw `Texture:SetGradient` path — check existing gradient usage in `Widgets/` first.
- [ ] **Step 8:** Add a small `Editing: <name> (<type>, <anchor>)` label above the first settings card in the scroll region (the `spawnSettingsCards` call site). Use `C.Font.sizeSmall` + `C.Colors.textSecondary`. Update the label whenever the selected indicator changes.
- [ ] **Step 9:** Lint + reload + visual verification: create, rename, delete, edit indicators; scroll the settings cards and confirm the Indicators list stays pinned; verify Copy To still works from the sub-header.
- [ ] **Step 10:** Commit.

**Tricky bits to watch for:**
- The existing list card's `listScrollH = leftColumnH - Widgets.CARD_PADDING * 2` calculation must be replaced with `listScrollH = previewCardH - Widgets.CARD_PADDING * 2` (or similar), since there's no more create card to add to the left column height.
- `content:SetHeight(grid:GetTotalHeight())` at the end of `spawnSettingsCards` still drives the outer scroll region height — the settings-card CardGrid still scrolls. Only the list card scrolls internally.
- The inline create form's `×` collapse state must reset all form fields so the next `+` opens a blank form.

### Task 6: Reshape Debuffs — same as Buffs plus preserve Filter mode dropdown

**Why:** Debuffs shares Buffs' layout shape today (same Preview + Create + List row), so landing it in the same phase avoids a half-migrated state. The only structural difference is the `Filter mode` dropdown (`all`/`harmful`/`helpful`/…) that Debuffs exposes in its current Create card.

**Files:**

- Modify: `Settings/Panels/Debuffs.lua`

**Structural outline (expand during implementation):**

- [ ] **Step 1:** Apply the same structural changes as Task 5 Steps 2–8 to `Debuffs.lua`. The code is near-identical — most edits can be copied across.
- [ ] **Step 2:** Preserve the `Filter mode` dropdown. Place it as a pre-row above the Name/Type/Display row in the inline create form (so the form reads `Filter mode ▾ / Name / Type ▾ / Display ▾ / [desc] [Create]`). The existing `FILTER_MODE_ITEMS` constant and `selectedFilter` closure stay as-is; just rewire their UI host frame from the old create card to the new inline form.
- [ ] **Step 3:** Lint + reload + same verification plan as Task 5.
- [ ] **Step 4:** Commit both Buffs and Debuffs together if Task 5 hasn't landed yet, or as a separate commit chained onto Task 5.

---

## Phase 4 — Migrate Defensives + Externals off CardGrid

### Task 7: Migrate Defensives to wrapper-grid `Preview | Overview` layout

**Why:** Defensives has six parameter cards (Preview, Overview, Display, Layout, Duration, Stacks). With `CardGrid`'s current column count and the new blurb-enlarged Preview, users scroll past the Preview almost immediately when editing Display or Layout sliders. The spec's pinned `Preview | Overview` row keeps the mock frame visible while the user tweaks the other parameter cards in the scroll region below.

**Files:**

- Modify: `Settings/Panels/Defensives.lua`

**Structural outline (expand during implementation):**

- [ ] **Step 1:** Read the current registration (`Settings/Panels/Defensives.lua:151-245`). Confirm the six cards and the `grid:SetSticky('preview')` call at line 190.
- [ ] **Step 2:** Replace the `CreateCardGrid` block with a wrapper-grid layout modeled on the new Buffs Phase 3 structure:
    - Pinned row: `Preview` (natural width, via `F.Settings.AuraPreview.BuildPreviewCard`) on the left, `Overview` card (`buildOverviewCard`) filling the remaining row width.
    - Both cards stretched vertically to match the taller of the two. `previewCard:GetHeight()` drives after Task 4's blurb addition.
    - No `SetSticky` — pinning is structural, not scroll-driven.
- [ ] **Step 3:** Below the pinned row, build an internal scroll region containing the remaining cards (`Display`, `Layout`, `Duration`, `Stacks`) in the same order. These cards already use standard `StartCard`/`EndCard` patterns so they drop straight into a vertical anchor chain.
- [ ] **Step 4:** Rewire `F.EventBus:Register('SETTINGS_RESIZED', ...)` to call `card:SetWidth(newWidth)` on each pinned and scroll card instead of `grid:SetWidth`. The existing `grid:RebuildCards` call becomes a manual per-card rebuild — if each card builder is idempotent (most are), just re-invoke them against the new width.
- [ ] **Step 5:** Preserve the `scroll._ownedPreview = F.Settings._auraPreview` assignment at the end of `create()`. **Do not remove or rename this field.** See the "Preview reparenting contract" section above Phase 3 for why.
- [ ] **Step 6:** Lint + reload. Verify: Preview pins, Overview fits next to it, other cards scroll below, Copy To still works, `UpdateAuraPreviewDimming('defensives', nil)` still updates the preview's group alpha on config change.
- [ ] **Step 7:** Commit.

**Tricky bits to watch for:**
- The existing Overview card's `descFS:SetText('Major personal defensive cooldowns. …')` is short. If the Overview card ends up visibly shorter than the Preview (Preview = mock frame + toggle + blurb ≈ 120–140px; Overview = enable checkbox + two-line description ≈ 60–80px), add a second `Widgets.CreateFontString` helper blurb under the description to pad. If both sit naturally — skip the padding.
- `F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', function() grid:RebuildCards() end, ...)` at line 222 becomes a manual rebuild loop over the pinned + scroll cards. The `resizeKey .. '.complete'` unregister in `OnHide` still fires the same key, just points at a different callback body.

### Task 8: Migrate Externals — same shape as Defensives

**Why:** Externals uses an identical card set and structure to Defensives (same `buildOverviewCard`/`buildDisplayCard`/etc. shape, different Overview description text). The migration is a near-mechanical copy of Task 7.

**Files:**

- Modify: `Settings/Panels/Externals.lua`

**Structural outline:**

- [ ] **Step 1:** Apply the same migration as Task 7 to `Externals.lua`. Diff the file against `Defensives.lua` after the migration — the two should be near-identical (differences: panel id, config key, Overview description text, description-pad heuristics).
- [ ] **Step 2:** Lint + reload + verification (same steps as Task 7, but for the `externals` panel and `'externals'` config key).
- [ ] **Step 3:** Commit.

---

## Phase 5 — Cleanup

### Task 9: Delete CopyToDialog (if dead), document in CHANGELOG

**Why:** Once Phase 2 lands, the dialog-based Copy To path is no longer reachable from the sub-header. If nothing else in the codebase calls `Settings.ShowCopyToDialog`, the entire `Settings/CopyToDialog.lua` module is dead code and should be removed. The layout refactor itself also deserves a CHANGELOG entry.

**Versioning note:** This refactor rides whatever version is already on `working-testing` — **do not bump `Framed.toc`** as part of this task. The CHANGELOG entry gets added under the existing in-progress version block (if one exists) or staged for the next bump. Task 9 only touches `CHANGELOG.md` and the `sync-changelog.lua` output in `Settings/Cards/About.lua`, not `Framed.toc`. A separate, unrelated commit will bump the TOC when the next release ships.

**Files:**

- Possibly delete: `Settings/CopyToDialog.lua`
- Possibly modify: `Framed.toc`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Grep for any remaining `ShowCopyToDialog` callers**

Run: Grep `ShowCopyToDialog` (code only — exclude docs/plans).

Expected: zero hits in `.lua` files (Phase 2's Task 3 replaced the only call site). If any remain, route them through `F.Settings.CopyTo` directly and keep the dialog file alive as a wrapper — otherwise proceed to Step 2.

- [ ] **Step 2: If dialog is dead, delete the file and TOC entry**

```bash
rm Settings/CopyToDialog.lua
```

Edit `Framed.toc` and remove the `Settings\CopyToDialog.lua` line.

- [ ] **Step 3: Update CHANGELOG.md**

Per `CLAUDE.md` release workflow, add an entry to `CHANGELOG.md` under the next version block describing the layout refactor. One-liner format:

```
- Redesigned aura panels: Preview + Indicators/Overview pin side-by-side, inline create form replaces the Create card, and Copy To moves into the sub-header as an inline dropdown.
```

Then run `./tools/sync-changelog.lua` per the release workflow to regenerate the About panel's Changelog card.

- [ ] **Step 4: Lint and reload**

Run: `luacheck . --config .luacheckrc`

Expected: clean. Then `/reload` and smoke-test all aura panels one more time (Copy To from sub-header, create/delete indicators on Buffs + Debuffs, scroll parameter cards on Defensives + Externals).

- [ ] **Step 5: Commit**

```bash
git add Settings/CopyToDialog.lua Framed.toc CHANGELOG.md Settings/Cards/About.lua
git commit -m "Remove CopyToDialog, document layout refactor in changelog"
git push origin working-testing
```

(If `CopyToDialog.lua` wasn't deleted, adjust the `git add` list accordingly.)

---

## Risk / Open questions

- **Dashed-accent inset widget:** Phase 3 Task 5 calls for a dashed-border inset panel for the inline create form. `Widgets/Base.lua` may or may not have a dashed-border helper already. If not, add one as a small addition to `Widgets/Base.lua` (not a new file) rather than inlining the dashed texture per-panel.
- **Selected-row gradient primitive:** the 90° `accent-dim → transparent` gradient in Phase 3 Task 5 Step 7 needs a gradient-capable widget. Check how the sidebar active-item gradient is done in `Settings/MainFrame.lua` or `Settings/Sidebar.lua` first and reuse that pattern rather than inventing a new one.
- **Pinned-card resize rebuild in Phase 4:** the `SETTINGS_RESIZE_COMPLETE` flow currently calls `grid:RebuildCards()`, which knows how to rebuild every card the grid owns. After migration, resize rebuilds must manually iterate the pinned + scroll cards. Consider wrapping the migrated layout in a small helper struct (`{pinnedLeft, pinnedRight, scrollCards}`) so the rebuild loop is one function, not three per-panel copies.
- **`info.label` in Copy To chat print:** if panels ever get renamed in their registration table, the chat output will change silently. Not a blocker — just noted.
- **Min-window width for inline create form:** on the 2-col card grid threshold (`project_responsive_cards`), the Name/Type/Display row may wrap. Verify visually on Phase 3 Task 5 Step 9; if it wraps, stack the fields vertically at narrow widths via a breakpoint check.

---

## References

- Spec: [`docs/superpowers/specs/2026-04-15-aura-panel-layout-design.md`](../specs/2026-04-15-aura-panel-layout-design.md)
- Current Copy To: `Settings/CopyToDialog.lua`, `Settings/Framework.lua:199-275`
- Sub-header construction: `Settings/MainFrame.lua:219-275`
- Shared Preview builder: `Settings/Builders/AuraPreview.lua`
- Reference layout (Buffs, pre-refactor): `Settings/Panels/Buffs.lua:200-380`
- Reference layout (Debuffs, pre-refactor): `Settings/Panels/Debuffs.lua:258-400`
- Defensives / Externals current shape: `Settings/Panels/Defensives.lua`, `Settings/Panels/Externals.lua`
- Mockup: `/tmp/framed-preview-mockups.html` (Variant A)
