# Sidebar Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the settings sidebar to remove visual clutter (redundant heading + editing label), add collapsible FRAMES/AURAS sections with smooth animation, persist collapsed state, and fix dynamic accent color.

**Architecture:** All changes are in `Settings/Sidebar.lua`. Collapsible sections use `SetClipsChildren(true)` containers with `AnimateHeight` for smooth transitions. Elements anchor to previous container bottoms (anchor chain) so everything moves naturally during animation. Config keys persist collapsed state.

**Tech Stack:** WoW Lua API, oUF patterns, Framed Config/EventBus/Constants

---

## File Structure

- **Modify:** `Settings/Sidebar.lua` (~434 lines → ~550 lines) — All changes described below

No other files are created or modified.

---

### Task 1: Remove Cached Accent Color + Dynamic Accent Fix

Remove the cached `ACCENT_R/G/B` locals and read `C.Colors.accent` at point of use so the sidebar reflects live accent color changes.

**Files:**
- Modify: `Settings/Sidebar.lua:27` (remove cached locals)
- Modify: `Settings/Sidebar.lua:65,108` (read accent dynamically in `setSidebarSelected` and `createNavButton`)

- [ ] **Step 1: Remove cached accent color locals**

In `Settings/Sidebar.lua`, delete line 27:

```lua
-- DELETE this line:
local ACCENT_R,     ACCENT_G,     ACCENT_B     = C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3]
```

- [ ] **Step 2: Update `setSidebarSelected` to read accent dynamically**

Replace the `ACCENT_R, ACCENT_G, ACCENT_B` references in `setSidebarSelected` (around line 65):

```lua
local function setSidebarSelected(btn, selected)
	if(selected) then
		btn._highlight:Show()
		btn._highlight:SetVertexColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
		AnimateWidth(btn._highlight, btn:GetWidth(), C.Animation.durationNormal)
		if(btn._icon) then
			btn._icon:SetVertexColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3])
		end
		if(btn._label) then
			btn._label:SetTextColor(HOVER_R, HOVER_G, HOVER_B)
		end
	else
		AnimateWidth(btn._highlight, 1, C.Animation.durationNormal, function()
			btn._highlight:Hide()
		end)
		if(btn._icon) then
			btn._icon:SetVertexColor(DIM_ICON_R, DIM_ICON_G, DIM_ICON_B)
		end
		if(btn._label) then
			btn._label:SetTextColor(DIM_TEXT_R, DIM_TEXT_G, DIM_TEXT_B)
		end
	end
end
```

- [ ] **Step 3: Update `createNavButton` highlight and hover to use dynamic accent**

In `createNavButton`, replace the two `ACCENT_R, ACCENT_G, ACCENT_B` usages:

Gradient highlight initial color (around line 108):
```lua
	highlight:SetVertexColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
```

OnEnter hover — no change needed here (hover uses `HOVER_R/G/B` white, not accent).

- [ ] **Step 4: Commit**

```bash
git add Settings/Sidebar.lua
git commit -m "refactor(sidebar): read accent color dynamically instead of caching at load time"
```

---

### Task 2: Remove FRAME_PRESETS Section Header

Skip the section header `CreateFontString` when the section ID is `FRAME_PRESETS`. Keep dividers and button.

**Files:**
- Modify: `Settings/Sidebar.lua:349-371` (standard section rendering in `buildSidebarContent`)

- [ ] **Step 1: Add FRAME_PRESETS check to skip header label**

In the standard section rendering block (the `else` branch around line 349), change the header text condition from:

```lua
			if(sectionLabel ~= '') then
```

to:

```lua
			if(sectionLabel ~= '' and sectionId ~= 'FRAME_PRESETS') then
```

This skips the "FRAME PRESETS" header label while keeping dividers and the "Frame Presets" button. The check uses `sectionId` (not the display label) for robustness.

- [ ] **Step 2: Commit**

```bash
git add Settings/Sidebar.lua
git commit -m "fix(sidebar): remove redundant FRAME_PRESETS section header label"
```

---

### Task 3: Remove Editing Label

Remove the `editingLabel` font string from the PRESET_SCOPED section and its update in the EDITING_PRESET_CHANGED listener.

**Files:**
- Modify: `Settings/Sidebar.lua:244,291-298,375-378` (editingLabel creation + event handler)

- [ ] **Step 1: Remove editingLabel declaration**

In `buildSidebarContent`, remove `editingLabel` from the local declaration (line 244). Change:

```lua
	local editingLabel
	local groupFrameBtn
```

to:

```lua
	local groupFrameBtn
```

- [ ] **Step 2: Remove editingLabel creation block**

Delete the "Editing: X Frame Preset" accent label block (lines 291-298):

```lua
			-- DELETE this entire block:
			-- "Editing: X Frame Preset" accent label
			editingLabel = sidebar:CreateFontString(nil, 'OVERLAY')
			editingLabel:SetFont(F.Media.GetActiveFont(), C.Font.sizeSmall, '')
			editingLabel:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
			editingLabel:SetText('Editing: ' .. Settings.GetEditingPreset() .. ' Frame Preset')
			editingLabel:ClearAllPoints()
			editingLabel:SetPoint('TOPLEFT', sidebar, 'TOPLEFT', 12, yOffset)
			yOffset = yOffset - EDITING_LABEL_H
```

Note: The `ACCENT_R/G/B` references here are already gone from Task 1. This block is deleted entirely.

- [ ] **Step 3: Remove editingLabel update from EDITING_PRESET_CHANGED**

In the EDITING_PRESET_CHANGED listener (around line 375), remove the editingLabel update:

```lua
	F.EventBus:Register('EDITING_PRESET_CHANGED', function(presetName)
		if(groupFrameBtn) then
			local groupLabel = getGroupFrameLabel()
			if(groupLabel) then
				groupFrameBtn:Show()
				groupFrameBtn._label:SetText(groupLabel)
			else
				groupFrameBtn:Hide()
			end
		end
	end, 'Sidebar')
```

- [ ] **Step 4: Remove unused EDITING_LABEL_H constant**

Delete line 196:

```lua
-- DELETE:
local EDITING_LABEL_H = 16   -- vertical space consumed by the editing preset label
```

- [ ] **Step 5: Commit**

```bash
git add Settings/Sidebar.lua
git commit -m "fix(sidebar): remove 'Editing: X Frame Preset' label from sidebar"
```

---

### Task 4: Add AnimateHeight Function

Add a new `AnimateHeight` function mirroring the existing `AnimateWidth`, for use by collapsible sections and window resize.

**Files:**
- Modify: `Settings/Sidebar.lua` (add after `AnimateWidth`, around line 53)

- [ ] **Step 1: Add AnimateHeight function**

Insert after the `AnimateWidth` function (after line 53):

```lua
-- ============================================================
-- AnimateHeight
-- OnUpdate-based linear interpolation of a frame's height.
-- ============================================================

local function AnimateHeight(frame, targetHeight, duration, onDone)
	local startHeight = frame:GetHeight()
	if(math.abs(startHeight - targetHeight) < 0.5) then
		frame:SetHeight(targetHeight)
		if(onDone) then onDone() end
		return
	end
	local elapsed = 0
	frame._heightAnimOnDone = onDone
	frame:SetScript('OnUpdate', function(self, dt)
		elapsed = elapsed + dt
		local t = math.min(elapsed / duration, 1)
		local h = startHeight + (targetHeight - startHeight) * t
		self:SetHeight(math.max(h, 0.001))
		if(t >= 1) then
			self:SetScript('OnUpdate', nil)
			self:SetHeight(targetHeight)
			if(self._heightAnimOnDone) then
				self._heightAnimOnDone()
				self._heightAnimOnDone = nil
			end
		end
	end)
end
```

- [ ] **Step 2: Commit**

```bash
git add Settings/Sidebar.lua
git commit -m "feat(sidebar): add AnimateHeight utility for collapsible sections"
```

---

### Task 5: Add recalcContainerHeight Helper

Add a helper that computes the natural height of a container by summing visible children's heights + gaps.

**Files:**
- Modify: `Settings/Sidebar.lua` (add after `AnimateHeight`)

- [ ] **Step 1: Add recalcContainerHeight helper**

Insert after `AnimateHeight`:

```lua
-- ============================================================
-- Container Height Calculator
-- ============================================================

--- Compute the total height for a collapsible section container.
--- Only counts visible (shown) children.
--- @param children table Array of child button frames
--- @return number totalHeight
local function recalcContainerHeight(children)
	local h = 0
	for _, child in next, children do
		if(child:IsShown()) then
			h = h + SIDEBAR_BTN_H + SIDEBAR_BTN_GAP
		end
	end
	return h
end
```

- [ ] **Step 2: Commit**

```bash
git add Settings/Sidebar.lua
git commit -m "feat(sidebar): add recalcContainerHeight helper for collapsible sections"
```

---

### Task 6: Build Collapsible FRAMES and AURAS Sections

This is the core task. Replace the static FRAMES/AURAS `CreateFontString` sub-headings with clickable toggle buttons. Create `SetClipsChildren(true)` containers for each section's child buttons. Wire up the toggle behavior with animation. Use anchor chain so elements below move automatically.

**Files:**
- Modify: `Settings/Sidebar.lua:277-371` (rewrite the entire PRESET_SCOPED rendering block)

- [ ] **Step 1: Rewrite the PRESET_SCOPED section rendering**

Replace the entire `if(isPresetScoped) then` block (lines 277-348 approximately) with the new collapsible section implementation. The code below replaces everything from `if(isPresetScoped) then` up to (but not including) the `else` branch:

```lua
		if(isPresetScoped) then
			local panels = sectionPanels[sectionId]

			-- Split panels into frames vs auras sub-groups
			local framePanels = {}
			local auraPanels = {}
			for _, panel in next, panels do
				if(panel.subSection == 'auras') then
					auraPanels[#auraPanels + 1] = panel
				else
					framePanels[#framePanels + 1] = panel
				end
			end

			-- ── Helper: build one collapsible section ──────────────
			local function buildCollapsibleSection(anchorFrame, anchorPoint, sectionName, sectionPanelList, configKey)
				local isCollapsed = F.Config:Get(configKey) or false

				-- Section header toggle button
				local headerBtn = CreateFrame('Button', nil, sidebar)
				headerBtn:SetHeight(SUBHEADING_H)
				headerBtn:ClearAllPoints()
				headerBtn:SetPoint('TOPLEFT', anchorFrame, anchorPoint, 2, 0)
				headerBtn:SetPoint('TOPRIGHT', sidebar, 'TOPRIGHT', -3, 0)

				-- Arrow indicator
				local arrow = headerBtn:CreateFontString(nil, 'OVERLAY')
				arrow:SetFont(F.Media.GetActiveFont(), C.Font.sizeSmall, '')
				arrow:SetPoint('LEFT', 8, 0)

				-- Section label
				local headerLabel = headerBtn:CreateFontString(nil, 'OVERLAY')
				headerLabel:SetFont(F.Media.GetActiveFont(), C.Font.sizeSmall, '')
				headerLabel:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3])
				headerLabel:SetText(sectionName)
				headerLabel:SetPoint('LEFT', arrow, 'RIGHT', 4, 0)

				-- Child container with clipping
				local container = CreateFrame('Frame', nil, sidebar)
				container:SetClipsChildren(true)
				container:ClearAllPoints()
				container:SetPoint('TOPLEFT', headerBtn, 'BOTTOMLEFT', 0, 0)
				container:SetPoint('TOPRIGHT', headerBtn, 'BOTTOMRIGHT', 0, 0)

				-- Create child nav buttons inside the container
				local children = {}
				local childYOffset = 0
				for _, panel in next, sectionPanelList do
					local btn = createNavButton(container, panel, childYOffset)
					Settings._sidebarButtons[panel.id] = btn
					children[#children + 1] = btn

					-- Group frame button — dynamic label & visibility per preset
					if(panel.id == 'party') then
						groupFrameBtn = btn
						local groupLabel = getGroupFrameLabel()
						if(groupLabel) then
							btn._label:SetText(groupLabel)
							btn:Show()
						else
							btn:Hide()
						end
					end

					childYOffset = childYOffset - SIDEBAR_BTN_H - SIDEBAR_BTN_GAP
				end

				-- Set initial state
				local fullHeight = recalcContainerHeight(children)
				if(isCollapsed) then
					container:SetHeight(0.001)
					arrow:SetText('\226\150\182')  -- ▶
					arrow:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3])
				else
					container:SetHeight(fullHeight)
					arrow:SetText('\226\150\188')  -- ▼
					arrow:SetTextColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3])
				end

				-- Toggle on click
				headerBtn:SetScript('OnClick', function()
					isCollapsed = not isCollapsed
					F.Config:Set(configKey, isCollapsed)

					local targetContainerH = isCollapsed and 0.001 or recalcContainerHeight(children)
					local delta = targetContainerH - container:GetHeight()
					local currentWindowH = Settings._mainFrame:GetHeight()
					local targetWindowH = math.max(WINDOW_MIN_H, math.min(currentWindowH + delta, WINDOW_MAX_H))

					if(isCollapsed) then
						arrow:SetText('\226\150\182')  -- ▶
						arrow:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3])
					else
						arrow:SetText('\226\150\188')  -- ▼
						arrow:SetTextColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3])
					end

					local dur = C.Animation.durationNormal
					AnimateHeight(container, targetContainerH, dur)
					AnimateHeight(Settings._mainFrame, targetWindowH, dur, function()
						if(Settings._contentParent) then
							local contentH = Settings._mainFrame:GetHeight() - HEADER_HEIGHT - SUB_HEADER_H
							Settings._contentParent:SetHeight(contentH)
							Settings._contentParent._explicitHeight = contentH
						end
					end)
				end)

				-- Store references for external recalculation
				container._children = children
				container._isCollapsed = function() return isCollapsed end
				container._recalc = function(animate)
					local newH = recalcContainerHeight(children)
					fullHeight = newH
					if(isCollapsed) then return end
					local oldH = container:GetHeight()
					local delta = newH - oldH
					if(math.abs(delta) < 0.5) then return end
					local currentWindowH = Settings._mainFrame:GetHeight()
					local targetWindowH = math.max(WINDOW_MIN_H, math.min(currentWindowH + delta, WINDOW_MAX_H))
					if(animate) then
						local dur = C.Animation.durationNormal
						AnimateHeight(container, newH, dur)
						AnimateHeight(Settings._mainFrame, targetWindowH, dur, function()
							if(Settings._contentParent) then
								local contentH = Settings._mainFrame:GetHeight() - HEADER_HEIGHT - SUB_HEADER_H
								Settings._contentParent:SetHeight(contentH)
								Settings._contentParent._explicitHeight = contentH
							end
						end)
					else
						container:SetHeight(newH)
						Settings._mainFrame:SetHeight(targetWindowH)
						if(Settings._contentParent) then
							local contentH = targetWindowH - HEADER_HEIGHT - SUB_HEADER_H
							Settings._contentParent:SetHeight(contentH)
							Settings._contentParent._explicitHeight = contentH
						end
					end
				end

				return headerBtn, container
			end

			-- ── Build FRAMES section ────────────────────────────────
			local framesHeader, framesContainer = buildCollapsibleSection(
				sidebar, 'TOPLEFT',
				'FRAMES', framePanels,
				'sidebar.framesCollapsed'
			)
			-- Position the FRAMES header at the current yOffset
			framesHeader:ClearAllPoints()
			framesHeader:SetPoint('TOPLEFT', sidebar, 'TOPLEFT', 2, yOffset)
			framesHeader:SetPoint('TOPRIGHT', sidebar, 'TOPRIGHT', -3, yOffset)

			-- ── Build AURAS section (anchored to FRAMES container bottom) ──
			local aurasHeader, aurasContainer
			if(#auraPanels > 0) then
				aurasHeader, aurasContainer = buildCollapsibleSection(
					framesContainer, 'BOTTOMLEFT',
					'AURAS', auraPanels,
					'sidebar.aurasCollapsed'
				)
			end

			-- Store container references for EDITING_PRESET_CHANGED
			sidebar._framesContainer = framesContainer
			sidebar._aurasContainer = aurasContainer

			-- The BOTTOM divider will anchor to the last container via anchor chain
			sidebar._lastPresetContainer = aurasContainer or framesContainer

			-- Compute yOffset for window sizing from actual container heights
			-- (containers are already sized: 0.001 if collapsed, full if expanded)
			yOffset = yOffset - SUBHEADING_H - framesContainer:GetHeight()
			if(#auraPanels > 0) then
				yOffset = yOffset - SUBHEADING_H - aurasContainer:GetHeight()
			end
```

- [ ] **Step 2: Update BOTTOM section separator to anchor to last container**

In the BOTTOM section rendering, when `isBottomSection` is true and `sidebar._lastPresetContainer` exists, anchor the separator to the container's bottom instead of using the running `yOffset`. Replace the separator creation for the bottom section case:

In the separator block (around line 266), after the separator is created, add an anchor override:

```lua
		if(isBottomSection or yOffset < -8) then
			local sep = sidebar:CreateTexture(nil, 'ARTWORK')
			sep:SetHeight(1)
			sep:SetColorTexture(0.25, 0.25, 0.25, 1)
			sep:ClearAllPoints()
			if(isBottomSection and sidebar._lastPresetContainer) then
				sep:SetPoint('TOPLEFT', sidebar._lastPresetContainer, 'BOTTOMLEFT', 4, -4)
				sep:SetPoint('TOPRIGHT', sidebar._lastPresetContainer, 'BOTTOMRIGHT', -4, -4)
				sidebar._bottomSep = sep
			else
				sep:SetPoint('TOPLEFT',  sidebar, 'TOPLEFT',  6, yOffset - 4)
				sep:SetPoint('TOPRIGHT', sidebar, 'TOPRIGHT', -6, yOffset - 4)
			end
			yOffset = yOffset - 10
		end
```

And for BOTTOM section panel buttons, anchor them relative to the separator instead of using absolute yOffset. Change the BOTTOM section button creation:

```lua
			local panels = sectionPanels[sectionId]
			if(isBottomSection and sidebar._bottomSep) then
				local bottomYOff = -6
				for _, panel in next, panels do
					local btn = createNavButton(sidebar, panel, 0)
					btn:ClearAllPoints()
					btn:SetPoint('TOPLEFT', sidebar._bottomSep, 'BOTTOMLEFT', 0, bottomYOff)
					btn:SetPoint('TOPRIGHT', sidebar._bottomSep, 'BOTTOMRIGHT', 0, bottomYOff)
					Settings._sidebarButtons[panel.id] = btn
					bottomYOff = bottomYOff - SIDEBAR_BTN_H - SIDEBAR_BTN_GAP
				end
			else
				for _, panel in next, panels do
					local btn = createNavButton(sidebar, panel, yOffset)
					Settings._sidebarButtons[panel.id] = btn
					yOffset = yOffset - SIDEBAR_BTN_H - SIDEBAR_BTN_GAP
				end
			end
```

- [ ] **Step 3: Update EDITING_PRESET_CHANGED to recalc FRAMES container**

Replace the EDITING_PRESET_CHANGED listener to also recalculate the FRAMES container when `groupFrameBtn` visibility changes:

```lua
	F.EventBus:Register('EDITING_PRESET_CHANGED', function(presetName)
		if(groupFrameBtn) then
			local groupLabel = getGroupFrameLabel()
			if(groupLabel) then
				groupFrameBtn:Show()
				groupFrameBtn._label:SetText(groupLabel)
			else
				groupFrameBtn:Hide()
			end
			-- Recalc FRAMES container height since groupFrameBtn visibility changed
			if(sidebar._framesContainer and sidebar._framesContainer._recalc) then
				sidebar._framesContainer._recalc(true)
			end
		end
	end, 'Sidebar')
```

- [ ] **Step 4: Remove unused SUBHEADING_H constant rename**

Keep `SUBHEADING_H` — it's still used as the height for the collapsible section header buttons.

- [ ] **Step 5: Commit**

```bash
git add Settings/Sidebar.lua
git commit -m "feat(sidebar): add collapsible FRAMES and AURAS sections with smooth animation"
```

---

### Task 7: Update Window Sizing in BuildSidebar

The `BuildSidebar` function computes the window height from `buildSidebarContent`'s returned yOffset. Since collapsed sections reduce the initial height, this should already work. But verify the window sizing accounts for collapsed sections properly, and that the initial window height respects the same min/max clamping.

**Files:**
- Modify: `Settings/Sidebar.lua` (the `Settings.BuildSidebar` function)

- [ ] **Step 1: Verify BuildSidebar window sizing**

The existing `BuildSidebar` code at the bottom of the file should work as-is because `buildSidebarContent` returns `math.abs(yOffset) + 8` which already accounts for collapsed containers (the yOffset only advances when expanded). No changes needed here unless testing reveals issues.

If the initial window height is wrong when sections start collapsed, ensure the yOffset calculation at the end of the PRESET_SCOPED block correctly uses container heights (which are 1 when collapsed, not the full height).

- [ ] **Step 2: Manual testing verification**

Verify in-game with `/reload`:
1. Both sections expand/collapse on click with smooth animation
2. Window resizes in parallel with container
3. BOTTOM section (Tour, About) moves smoothly when sections toggle
4. Collapsed state persists across `/reload`
5. Changing frame preset updates groupFrameBtn and recalculates container
6. Accent color reads dynamically (change in Appearance, sidebar updates)
7. "Frame Presets" button still shows, but "FRAME PRESETS" header label is gone
8. "Editing: X Frame Preset" label is gone from sidebar

- [ ] **Step 3: Commit any fixes from testing**

```bash
git add Settings/Sidebar.lua
git commit -m "fix(sidebar): adjust window sizing for collapsible sections"
```

---

### Task Summary

| Task | Description | Est. Complexity |
|------|-------------|-----------------|
| 1 | Dynamic accent color | Simple (3 replacements) |
| 2 | Remove FRAME_PRESETS header | Simple (1 condition) |
| 3 | Remove editing label | Simple (delete code) |
| 4 | AnimateHeight function | Simple (mirror AnimateWidth) |
| 5 | recalcContainerHeight helper | Simple (sum visible heights) |
| 6 | Collapsible sections + anchor chain | Complex (core feature) |
| 7 | Window sizing verification + testing | Medium (integration) |
