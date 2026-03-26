# Edit Mode Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite Framed's edit mode from a simple drag-handle system into a full inline editing experience with live preview, recycled settings panels, grid/alignment, and confirmation dialogs.

**Architecture:** Single full-screen overlay at `FULLSCREEN_DIALOG` strata owns everything (border, dim, grid, click catchers, inline settings panel). Edit cache provides shadow config so changes preview live but only commit on Save. One settings panel instance recycled across frame selections.

**Tech Stack:** WoW Lua (TOC 120001), oUF (embedded), Framed widget library, Framed Config/EventBus

**Spec:** `docs/superpowers/specs/2026-03-26-edit-mode-rewrite-design.md`

---

## File Structure

```
EditMode/
  EditMode.lua              -- REWRITE: overlay lifecycle, entry/exit, combat protection, state machine
  EditCache.lua             -- NEW: shadow config wrapper, dirty tracking, commit/discard
  Grid.lua                  -- NEW: grid rendering (lines/dots), snap logic
  AlignmentGuides.lua       -- NEW: proximity-based red alignment guide lines
  ClickCatchers.lua         -- NEW: transparent click-catcher frames over unit frames
  InlinePanel.lua           -- NEW: recycled inline settings panel, tab system, smart positioning
  ResizeHandles.lua         -- NEW: edge/corner drag handles with tooltip
  Dialogs.lua               -- NEW: 3-button dialog flows (save/cancel/preset-swap)
  TopBar.lua                -- NEW: preset dropdown, editing label, grid controls, save/cancel

Widgets/
  Base.lua                  -- MODIFY: add onMove callback to MakeDraggable
  Dialog.lua                -- MODIFY: add 3-button layout support
  InfoIcon.lua              -- NEW: (i) hover tooltip widget for settings card headers
  Frame.lua                 -- MODIFY: extract AnimateHeight from Sidebar.lua to here

Settings/
  FrameSettingsBuilder.lua  -- MODIFY: add Position & Layout card, text anchor pickers
  Sidebar.lua               -- MODIFY: remove local AnimateHeight (use Widgets.AnimateHeight)

Framed.toc                  -- MODIFY: add new EditMode/*.lua files
```

---

## Prerequisites

Before starting, ensure the working directory is clean and synced:
```bash
# Sync project to WoW addon folder for /reload testing
cp -R /Users/josiahtoppin/Documents/Projects/Framed/* "/Applications/World of Warcraft/_retail_/Interface/AddOns/Framed/"
```

All testing is done via `/reload` in WoW. There is no automated test framework.

---

## Task 0: Base Frame Element Audit

**Purpose:** Ensure all frame elements (health, power, name, status icons, auras) are rendering and updating correctly on live frames before building edit mode live preview on top of them.

**Files:**
- Read: `Units/StyleBuilder.lua`, `Units/Player.lua`, `Units/Target.lua`, `Units/Party.lua`
- Read: `Elements/Core/*.lua`, `Elements/Status/*.lua`
- Potentially modify: any element or unit file with registration/update bugs

- [ ] **Step 1: Enter WoW and visually audit each frame type**

Check each unit frame (player, target, target of target, focus, pet, party, boss) with no settings menu open. For each frame, verify:
- Health bar shows and updates on damage/healing
- Power bar shows (if enabled) and updates on resource changes
- Name text shows with correct color mode
- Status icons show (role, leader, ready check, raid icon, combat)
- Cast bar shows on cast
- Aura icons show (buffs, debuffs) when present
- Absorb bar overlay shows with absorb shields

Document any elements that are missing, stale, or not updating.

- [ ] **Step 2: Fix any identified rendering bugs**

For each broken element:
1. Check that the element is registered in `Units/StyleBuilder.lua` for that unit type
2. Check that the element's `Enable()` function is called and the required events are registered
3. Check that the element's `Update()` path runs on the correct events
4. Fix and verify with `/reload`

- [ ] **Step 3: Commit fixes**

```bash
git add Units/ Elements/ && git commit -m "fix: audit and fix base frame element rendering"
```

---

## Task 1: Extract AnimateHeight to Widgets

**Purpose:** `AnimateHeight` is currently a local function in `Settings/Sidebar.lua`. The edit mode needs it for panel slide animations. Extract it to `Widgets` namespace.

**Files:**
- Modify: `Widgets/Frame.lua` (add `Widgets.AnimateHeight`)
- Modify: `Settings/Sidebar.lua` (replace local function with `Widgets.AnimateHeight` call)

- [ ] **Step 1: Add `Widgets.AnimateHeight` to `Widgets/Frame.lua`**

Add at the end of the file, before the final return/end:

```lua
-- ============================================================
-- AnimateHeight
-- OnUpdate-based linear interpolation of a frame's height.
-- ============================================================

--- Animate a frame's height from current to target over duration.
--- @param frame Frame     The frame to animate
--- @param targetHeight number  Target height
--- @param duration number     Duration in seconds
--- @param onDone? function    Called when animation completes
function Widgets.AnimateHeight(frame, targetHeight, duration, onDone)
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

- [ ] **Step 2: Update `Settings/Sidebar.lua` to use `Widgets.AnimateHeight`**

Remove the local `AnimateHeight` function (lines 59-82). Replace all calls to `AnimateHeight(` with `Widgets.AnimateHeight(` throughout the file. There are 4 call sites:
- Line ~412 (toggle click handler, container)
- Line ~413 (toggle click handler, main frame)
- Line ~436 (recalc, container)
- Line ~437 (recalc, main frame)

- [ ] **Step 3: Verify in-game**

```
/reload
```
Open Framed settings. Click FRAMES/AURAS collapse toggles. Verify smooth animation still works identically.

- [ ] **Step 4: Commit**

```bash
git add Widgets/Frame.lua Settings/Sidebar.lua
git commit -m "refactor: extract AnimateHeight to Widgets namespace"
```

---

## Task 2: Extend MakeDraggable with onMove Callback

**Purpose:** Alignment guides need per-frame position updates during drag. The current `MakeDraggable` only has `onDragStart` and `onDragStop` — no continuous update hook.

**Files:**
- Modify: `Widgets/Base.lua:413-434`

- [ ] **Step 1: Add `onMove` parameter to `MakeDraggable`**

Replace the current `MakeDraggable` function at `Widgets/Base.lua:407-434`:

```lua
--- Make a frame draggable within its parent bounds.
--- Handles RegisterForDrag, clamp-to-parent, and callbacks.
--- @param frame Frame The frame to make draggable
--- @param onDragStart? function Called when drag begins (frame)
--- @param onDragStop? function Called when drag ends (frame, x, y)
--- @param clampToParent? boolean Clamp within parent bounds (default true)
--- @param onMove? function Called each frame during drag (frame, x, y)
function Widgets.MakeDraggable(frame, onDragStart, onDragStop, clampToParent, onMove)
	if(clampToParent == nil) then clampToParent = true end

	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag('LeftButton')

	if(clampToParent) then
		frame:SetClampedToScreen(true)
	end

	frame:SetScript('OnDragStart', function(self)
		self:StartMoving()
		if(onDragStart) then onDragStart(self) end
		if(onMove) then
			self._dragOnMove = onMove
			self:SetScript('OnUpdate', function(s)
				local point, _, relPoint, x, y = s:GetPoint()
				if(s._dragOnMove) then s._dragOnMove(s, x, y) end
			end)
		end
	end)

	frame:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		if(self._dragOnMove) then
			self:SetScript('OnUpdate', nil)
			self._dragOnMove = nil
		end
		local point, _, relPoint, x, y = self:GetPoint()
		if(onDragStop) then onDragStop(self, x, y) end
	end)
end
```

- [ ] **Step 2: Verify existing MakeDraggable callers still work**

The only current caller is `EditMode/EditMode.lua:156` which passes `(frame, nil, onDragStop, true)`. The new `onMove` parameter is the 5th arg, so the existing 4th arg `true` (clampToParent) is unaffected. Verify in-game that current edit mode drag still works:

```
/framed edit
```
Drag a frame. Verify snap works. Save.

- [ ] **Step 3: Commit**

```bash
git add Widgets/Base.lua
git commit -m "feat: add onMove callback to MakeDraggable for continuous drag updates"
```

---

## Task 3: Extend Dialog Widget with 3-Button Layout

**Purpose:** Edit mode needs 3-button confirmation dialogs for Save, Cancel, and Preset Swap flows.

**Files:**
- Modify: `Widgets/Dialog.lua`

- [ ] **Step 1: Add third button to `BuildDialog()`**

In `Widgets/Dialog.lua`, inside the `BuildDialog()` function (after the `btnNo` creation around line 84), add:

```lua
	-- Third button (3-button dialogs)
	local btnThird = Widgets.CreateButton(frame, '', 'widget', BUTTON_WIDTH, BUTTON_HEIGHT)
	frame._btnThird = btnThird
```

- [ ] **Step 2: Update `DIALOG_WIDTH` for 3-button layout**

Change the constant at line 13:

```lua
local DIALOG_WIDTH_2  = 350    -- 2-button dialogs
local DIALOG_WIDTH_3  = 420    -- 3-button dialogs
```

Update `BuildDialog()` to use `DIALOG_WIDTH_2` as default. Track active width on the frame:

```lua
	frame._activeWidth = DIALOG_WIDTH_2
```

Update `_UpdateHeight` to use `self._activeWidth` instead of the hardcoded constant:

```lua
	function frame:_UpdateHeight()
		local msgHeight = self._message:GetStringHeight()
		local total = PAD
					+ self._title:GetStringHeight()
					+ TITLE_MSG_GAP
					+ msgHeight
					+ MSG_BTN_GAP
					+ BUTTON_HEIGHT
					+ PAD
		Widgets.SetSize(self, self._activeWidth, math.max(total, 100))
	end
```

- [ ] **Step 3: Add 3-button layout mode to `_LayoutButtons`**

Extend the `_LayoutButtons` method to handle a `'three'` mode:

```lua
	function frame:_LayoutButtons(mode)
		self._btnYes:Hide()
		self._btnNo:Hide()
		self._btnOK:Hide()
		self._btnThird:Hide()

		if(mode == 'confirm') then
			local totalW = BUTTON_WIDTH * 2 + BUTTON_GAP
			local leftX  = -(totalW / 2)
			self._btnYes:ClearAllPoints()
			self._btnYes:SetPoint('BOTTOM', self, 'BOTTOM', leftX + BUTTON_WIDTH / 2, PAD)
			self._btnNo:ClearAllPoints()
			self._btnNo:SetPoint('BOTTOM', self, 'BOTTOM', leftX + BUTTON_WIDTH + BUTTON_GAP + BUTTON_WIDTH / 2, PAD)
			self._btnYes:Show()
			self._btnNo:Show()
		elseif(mode == 'three') then
			local totalW = BUTTON_WIDTH * 3 + BUTTON_GAP * 2
			local leftX  = -(totalW / 2)
			self._btnYes:ClearAllPoints()
			self._btnYes:SetPoint('BOTTOM', self, 'BOTTOM', leftX + BUTTON_WIDTH / 2, PAD)
			self._btnNo:ClearAllPoints()
			self._btnNo:SetPoint('BOTTOM', self, 'BOTTOM', leftX + BUTTON_WIDTH + BUTTON_GAP + BUTTON_WIDTH / 2, PAD)
			self._btnThird:ClearAllPoints()
			self._btnThird:SetPoint('BOTTOM', self, 'BOTTOM', leftX + (BUTTON_WIDTH + BUTTON_GAP) * 2 + BUTTON_WIDTH / 2, PAD)
			self._btnYes:Show()
			self._btnNo:Show()
			self._btnThird:Show()
		else
			self._btnOK:ClearAllPoints()
			self._btnOK:SetPoint('BOTTOM', self, 'BOTTOM', 0, PAD)
			self._btnOK:Show()
		end
	end
```

- [ ] **Step 4: Wire third button dismiss**

After the existing button click wiring (line ~179):

```lua
	btnThird:SetOnClick(function() frame:_Dismiss('third') end)
```

Update `_Dismiss` to handle `'third'`:

```lua
	function frame:_Dismiss(reason)
		local cb
		if(reason == 'confirm') then
			cb = self._onConfirm
		elseif(reason == 'cancel') then
			cb = self._onCancel
		elseif(reason == 'third') then
			cb = self._onThird
		else
			cb = self._onDismiss
		end
		Widgets.FadeOut(dimmer, C.Animation.durationNormal)
		Widgets.FadeOut(self, C.Animation.durationNormal, function()
			if(cb) then cb() end
		end)
	end
```

- [ ] **Step 5: Add `ShowThreeButtonDialog` public API**

```lua
--- Show a modal dialog with three buttons.
--- @param title      string
--- @param message    string
--- @param btn1Label  string   Left button label (accent style)
--- @param btn2Label  string   Middle button label (widget style)
--- @param btn3Label  string   Right button label (widget style)
--- @param onBtn1     function Called when left button clicked
--- @param onBtn2?    function Called when middle button clicked
--- @param onBtn3?    function Called when right button clicked (or Escape)
--- @return Frame dialog
function Widgets.ShowThreeButtonDialog(title, message, btn1Label, btn2Label, btn3Label, onBtn1, onBtn2, onBtn3)
	local d = GetDialog()

	if(d._anim) then d._anim['fade'] = nil end

	d._title:SetText(title or '')
	d._message:SetText(message or '')

	d._btnYes._label:SetText(btn1Label)
	d._btnNo._label:SetText(btn2Label)
	d._btnThird._label:SetText(btn3Label)

	d._activeWidth = DIALOG_WIDTH_3
	d:_UpdateHeight()
	d:_LayoutButtons('three')

	d._onConfirm = onBtn1
	d._onCancel  = onBtn2
	d._onThird   = onBtn3
	d._onDismiss = nil

	Widgets.FadeIn(d._dimmer, C.Animation.durationNormal)
	Widgets.FadeIn(d, C.Animation.durationNormal)

	return d
end
```

- [ ] **Step 6: Clean up `OnHide` to clear `_onThird`**

Update the `OnHide` hook (around line 106):

```lua
	frame:HookScript('OnHide', function(self)
		self._onConfirm = nil
		self._onCancel  = nil
		self._onThird   = nil
		self._onDismiss = nil
		if(dimmer:IsShown() and dimmer:GetAlpha() <= 0.01) then
			dimmer:Hide()
		end
	end)
```

- [ ] **Step 7: Test in-game**

Test by temporarily calling `Widgets.ShowThreeButtonDialog(...)` from a slash command or the settings. Verify:
- 3 buttons display horizontally centered
- Each button fires its callback
- Escape dismisses (fires third/cancel callback)
- Dialog fades in/out correctly

- [ ] **Step 8: Commit**

```bash
git add Widgets/Dialog.lua
git commit -m "feat: add 3-button dialog layout to Widget.Dialog"
```

---

## Task 4: Create InfoIcon Widget

**Purpose:** `(i)` icon for settings card headers that shows a tooltip on hover.

**Files:**
- Create: `Widgets/InfoIcon.lua`
- Modify: `Framed.toc` (add after `Widgets/AnchorPicker.lua`)

- [ ] **Step 1: Create `Widgets/InfoIcon.lua`**

```lua
local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- InfoIcon — Small (i) button with hover tooltip
-- ============================================================

local ICON_SIZE = 14

--- Create an info icon that shows a tooltip on hover.
--- @param parent Frame   Parent frame
--- @param tooltipTitle string  Tooltip title text
--- @param tooltipBody  string  Tooltip body text
--- @return Button icon
function Widgets.CreateInfoIcon(parent, tooltipTitle, tooltipBody)
	local btn = CreateFrame('Button', nil, parent)
	btn:SetSize(ICON_SIZE, ICON_SIZE)

	-- Circle background
	local bg = btn:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(btn)
	bg:SetColorTexture(C.Colors.widget[1], C.Colors.widget[2], C.Colors.widget[3], 0.8)

	-- "i" label
	local label = Widgets.CreateFontString(btn, 10, C.Colors.textSecondary)
	label:SetPoint('CENTER', btn, 'CENTER', 0, 0)
	label:SetText('i')
	btn._label = label

	-- Hover: show tooltip
	btn:SetScript('OnEnter', function(self)
		label:SetTextColor(1, 1, 1, 1)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:AddLine(tooltipTitle, 1, 1, 1)
		if(tooltipBody and tooltipBody ~= '') then
			GameTooltip:AddLine(tooltipBody, C.Colors.textNormal[1], C.Colors.textNormal[2], C.Colors.textNormal[3], true)
		end
		GameTooltip:Show()
	end)

	btn:SetScript('OnLeave', function()
		label:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3], 1)
		GameTooltip:Hide()
	end)

	return btn
end
```

- [ ] **Step 2: Add to `Framed.toc`**

Add after the `Widgets/AnchorPicker.lua` line:

```
Widgets/InfoIcon.lua
```

- [ ] **Step 3: Test in-game**

After `/reload`, temporarily create an InfoIcon in a settings panel to verify the tooltip shows on hover and hides on leave.

- [ ] **Step 4: Commit**

```bash
git add Widgets/InfoIcon.lua Framed.toc
git commit -m "feat: add InfoIcon widget for settings card tooltips"
```

---

## Task 5: Create Edit Cache

**Purpose:** Shadow config layer that intercepts reads/writes during edit mode so changes preview live but don't commit to real config until Save.

**Files:**
- Create: `EditMode/EditCache.lua`
- Modify: `Framed.toc` (add before `EditMode/EditMode.lua`)

- [ ] **Step 1: Create `EditMode/EditCache.lua`**

```lua
local addonName, Framed = ...
local F = Framed

-- ============================================================
-- EditCache — Shadow config for edit mode
-- Stores pending changes per frame key. Reads check cache first,
-- falls back to F.Config. Writes go to cache only.
-- Commit flushes to real config. Discard clears everything.
-- ============================================================

local EditCache = {}
F.EditCache = EditCache

-- cache[frameKey][configPath] = value
local cache = {}
local active = false
local preEditPositions = {}

--- Activate the edit cache (called on edit mode entry).
function EditCache.Activate()
	active = true
	cache = {}
	preEditPositions = {}
end

--- Deactivate the edit cache (called on edit mode exit).
function EditCache.Deactivate()
	active = false
	cache = {}
	preEditPositions = {}
end

--- Check if the edit cache is active.
--- @return boolean
function EditCache.IsActive()
	return active
end

--- Store a value in the edit cache for a specific frame key.
--- @param frameKey string  Frame identifier (e.g., 'player', 'target', 'party')
--- @param configPath string  Config key relative to the preset (e.g., 'health.height')
--- @param value any  The new value
function EditCache.Set(frameKey, configPath, value)
	if(not cache[frameKey]) then
		cache[frameKey] = {}
	end
	cache[frameKey][configPath] = value
end

--- Read a value, checking the edit cache first, then falling back to real config.
--- @param frameKey string  Frame identifier
--- @param configPath string  Config key relative to the preset
--- @return any value
function EditCache.Get(frameKey, configPath)
	if(active and cache[frameKey] and cache[frameKey][configPath] ~= nil) then
		return cache[frameKey][configPath]
	end
	-- Fall back to real config
	local presetName = F.Settings.GetEditingPreset()
	return F.Config:Get('presets.' .. presetName .. '.unitConfigs.' .. frameKey .. '.' .. configPath)
end

--- Check if a specific frame has any cached edits.
--- @param frameKey string
--- @return boolean
function EditCache.HasEdits(frameKey)
	return cache[frameKey] ~= nil and next(cache[frameKey]) ~= nil
end

--- Check if any frame has cached edits.
--- @return boolean
function EditCache.HasAnyEdits()
	for _, edits in next, cache do
		if(next(edits)) then return true end
	end
	return false
end

--- Get all cached edits for a specific frame.
--- @param frameKey string
--- @return table|nil  Flat table of { [configPath] = value } or nil
function EditCache.GetEditsForFrame(frameKey)
	return cache[frameKey]
end

--- Flush (remove) cached edits for a specific frame key.
--- @param frameKey string
function EditCache.FlushFrame(frameKey)
	cache[frameKey] = nil
end

--- Commit all cached edits to real config.
function EditCache.Commit()
	local presetName = F.Settings.GetEditingPreset()
	for frameKey, edits in next, cache do
		for configPath, value in next, edits do
			F.Config:Set('presets.' .. presetName .. '.unitConfigs.' .. frameKey .. '.' .. configPath, value)
		end
	end
	F.PresetManager.MarkCustomized(presetName)
	cache = {}
end

--- Discard all cached edits (clear without committing).
function EditCache.Discard()
	cache = {}
end

--- Save a snapshot of frame positions before edit mode starts.
--- @param positions table  { [frameKey] = { point, relativeTo, relPoint, x, y } }
function EditCache.SavePreEditPositions(positions)
	preEditPositions = positions
end

--- Get the pre-edit position snapshot for restoring on discard.
--- @return table
function EditCache.GetPreEditPositions()
	return preEditPositions
end
```

- [ ] **Step 2: Add to `Framed.toc`**

Add before the `EditMode/EditMode.lua` line:

```
EditMode/EditCache.lua
```

- [ ] **Step 3: Commit**

```bash
git add EditMode/EditCache.lua Framed.toc
git commit -m "feat: add EditCache shadow config for edit mode"
```

---

## Task 6: Create Edit Mode Overlay & Entry/Exit

**Purpose:** Build the core overlay frame with red border, dark fill, combat protection, and entry/exit lifecycle. This replaces the current `EditMode.lua`.

**Files:**
- Rewrite: `EditMode/EditMode.lua`

- [ ] **Step 1: Rewrite `EditMode/EditMode.lua`**

```lua
local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditCache = F.EditCache

F.EditMode = {}
local EditMode = F.EditMode

-- ============================================================
-- Constants
-- ============================================================

local BORDER_SIZE     = 1
local DIM_ALPHA       = 0.85
local BORDER_RED      = { 0.8, 0.1, 0.1, 1 }
local BORDER_GREEN    = { 0.1, 0.8, 0.2, 1 }

-- ============================================================
-- State
-- ============================================================

local isActive         = false
local selectedFrameKey = nil
local overlay          = nil
local sessionPresetOverride = nil   -- nil = auto-detect, string = manual choice

-- ============================================================
-- Frame Key Definitions
-- ============================================================

local FRAME_KEYS = {
	{ key = 'player',       label = 'Player',           isGroup = false, getter = function() return F.Units.Player and F.Units.Player.frame end },
	{ key = 'target',       label = 'Target',           isGroup = false, getter = function() return F.Units.Target and F.Units.Target.frame end },
	{ key = 'targettarget', label = 'Target of Target', isGroup = false, getter = function() return F.Units.TargetTarget and F.Units.TargetTarget.frame end },
	{ key = 'focus',        label = 'Focus',            isGroup = false, getter = function() return F.Units.Focus and F.Units.Focus.frame end },
	{ key = 'pet',          label = 'Pet',              isGroup = false, getter = function() return F.Units.Pet and F.Units.Pet.frame end },
	{ key = 'party',        label = 'Party Frames',     isGroup = true,  getter = function() return F.Units.Party and F.Units.Party.header end },
	{ key = 'raid',         label = 'Raid Frames',      isGroup = true,  getter = function() return F.Units.Raid and F.Units.Raid.header end },
	{ key = 'boss',         label = 'Boss Frames',      isGroup = true,  getter = function() return F.Units.Boss and F.Units.Boss.frames and F.Units.Boss.frames[1] end },
	{ key = 'arena',        label = 'Arena Frames',     isGroup = true,  getter = function() return F.Units.Arena and F.Units.Arena.frames and F.Units.Arena.frames[1] end },
}

EditMode.FRAME_KEYS = FRAME_KEYS

-- ============================================================
-- Position Snapshot (for discard/restore)
-- ============================================================

local function SaveCurrentPositions()
	local positions = {}
	for _, def in next, FRAME_KEYS do
		local frame = def.getter()
		if(frame) then
			local point, relativeTo, relPoint, x, y = frame:GetPoint()
			if(point) then
				local relName = relativeTo and relativeTo:GetName() or 'UIParent'
				positions[def.key] = { point, relName, relPoint, x, y }
			end
		end
	end
	EditCache.SavePreEditPositions(positions)
end

local function RestorePositions()
	local positions = EditCache.GetPreEditPositions()
	for _, def in next, FRAME_KEYS do
		local saved = positions[def.key]
		if(saved) then
			local frame = def.getter()
			if(frame) then
				frame:ClearAllPoints()
				local relFrame = (saved[2] == 'UIParent') and UIParent or _G[saved[2]]
				frame:SetPoint(saved[1], relFrame, saved[3], saved[4], saved[5])
			end
		end
	end
end

-- ============================================================
-- Overlay Construction (lazy)
-- ============================================================

local function BuildOverlay()
	overlay = CreateFrame('Frame', 'FramedEditModeOverlay', UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata('FULLSCREEN_DIALOG')
	overlay:SetFrameLevel(1)
	overlay:EnableMouse(false)
	overlay:Hide()

	-- Dark fill
	local dimTex = overlay:CreateTexture(nil, 'BACKGROUND')
	dimTex:SetAllPoints(overlay)
	dimTex:SetColorTexture(0, 0, 0, DIM_ALPHA)
	overlay._dimTex = dimTex

	-- Red border (4 edge textures)
	local borders = {}
	local edges = {
		{ 'TOPLEFT', 'TOPRIGHT', 'TOPLEFT', 'TOPRIGHT', nil, BORDER_SIZE },       -- top
		{ 'BOTTOMLEFT', 'BOTTOMRIGHT', 'BOTTOMLEFT', 'BOTTOMRIGHT', nil, BORDER_SIZE }, -- bottom
		{ 'TOPLEFT', 'BOTTOMLEFT', 'TOPLEFT', 'BOTTOMLEFT', BORDER_SIZE, nil },   -- left
		{ 'TOPRIGHT', 'BOTTOMRIGHT', 'TOPRIGHT', 'BOTTOMRIGHT', BORDER_SIZE, nil }, -- right
	}
	for _, e in next, edges do
		local tex = overlay:CreateTexture(nil, 'OVERLAY')
		tex:SetPoint(e[1], overlay, e[3], 0, 0)
		tex:SetPoint(e[2], overlay, e[4], 0, 0)
		if(e[5]) then tex:SetWidth(e[5]) end
		if(e[6]) then tex:SetHeight(e[6]) end
		tex:SetColorTexture(BORDER_RED[1], BORDER_RED[2], BORDER_RED[3], BORDER_RED[4])
		borders[#borders + 1] = tex
	end
	overlay._borders = borders

	-- Keyboard: Escape triggers cancel
	overlay:SetPropagateKeyboardInput(false)
	overlay:EnableKeyboard(true)
	overlay:SetScript('OnKeyDown', function(self, key)
		if(key == 'ESCAPE') then
			EditMode.RequestCancel()
		end
	end)
end

--- Flash the border to a color then fade out.
local function FlashBorder(color, callback)
	if(not overlay or not overlay._borders) then
		if(callback) then callback() end
		return
	end
	for _, tex in next, overlay._borders do
		tex:SetColorTexture(color[1], color[2], color[3], color[4])
	end
	-- Brief hold then fade
	C_Timer.After(0.3, function()
		if(callback) then callback() end
	end)
end

--- Reset border to red.
local function ResetBorderColor()
	if(not overlay or not overlay._borders) then return end
	for _, tex in next, overlay._borders do
		tex:SetColorTexture(BORDER_RED[1], BORDER_RED[2], BORDER_RED[3], BORDER_RED[4])
	end
end

-- ============================================================
-- Session Preset Management
-- ============================================================

--- Get the preset to use. Returns manual override if set, else auto-detect.
--- @return string presetName
function EditMode.GetSessionPreset()
	return sessionPresetOverride or F.Settings.GetEditingPreset()
end

--- Set a manual preset override for the session.
--- @param presetName string
function EditMode.SetSessionPreset(presetName)
	sessionPresetOverride = presetName
end

-- ============================================================
-- Public API
-- ============================================================

--- Enter edit mode.
function EditMode.Enter()
	if(InCombatLockdown()) then
		if(DEFAULT_CHAT_FRAME) then
			DEFAULT_CHAT_FRAME:AddMessage('|cff00ccffFramed|r: Cannot enter Edit Mode during combat.')
		end
		return
	end

	if(isActive) then return end
	isActive = true

	-- Close sidebar if open
	F.Settings.Hide()

	SaveCurrentPositions()
	EditCache.Activate()

	if(not overlay) then
		BuildOverlay()
	end

	ResetBorderColor()

	-- Build sub-components (TopBar, ClickCatchers, Grid will hook in here)
	F.EventBus:Fire('EDIT_MODE_ENTERED')

	Widgets.FadeIn(overlay)
	overlay:EnableKeyboard(true)
end

--- Perform save: commit cache, flash green, exit.
--- @param returnToMenu boolean  If true, reopen sidebar after exit
function EditMode.Save(returnToMenu)
	if(not isActive) then return end

	EditCache.Commit()

	FlashBorder(BORDER_GREEN, function()
		EditMode.Exit(returnToMenu)
	end)
end

--- Perform discard: clear cache, restore positions, exit.
--- @param returnToMenu boolean  If true, reopen sidebar after exit
function EditMode.Discard(returnToMenu)
	if(not isActive) then return end

	EditCache.Discard()
	RestorePositions()
	EditMode.Exit(returnToMenu)
end

--- Exit edit mode (internal, called after save or discard).
--- @param returnToMenu boolean
function EditMode.Exit(returnToMenu)
	isActive = false
	selectedFrameKey = nil

	EditCache.Deactivate()

	F.EventBus:Fire('EDIT_MODE_EXITED')

	Widgets.FadeOut(overlay, nil, function()
		overlay:EnableKeyboard(false)
	end)

	if(returnToMenu) then
		F.Settings.Show()
	end
end

--- Request cancel (called by Escape or Cancel button).
--- Shows the cancel confirmation dialog if there are unsaved edits.
function EditMode.RequestCancel()
	if(not isActive) then return end
	if(EditCache.HasAnyEdits()) then
		F.EventBus:Fire('EDIT_MODE_SHOW_CANCEL_DIALOG')
	else
		EditMode.Discard(false)
	end
end

--- Request save (called by Save button).
--- Shows the save confirmation dialog.
function EditMode.RequestSave()
	if(not isActive) then return end
	F.EventBus:Fire('EDIT_MODE_SHOW_SAVE_DIALOG')
end

--- Get the currently selected frame key.
--- @return string|nil
function EditMode.GetSelectedFrameKey()
	return selectedFrameKey
end

--- Set the selected frame key.
--- @param key string|nil
function EditMode.SetSelectedFrameKey(key)
	selectedFrameKey = key
	F.EventBus:Fire('EDIT_MODE_FRAME_SELECTED', key)
end

--- Query whether edit mode is active.
--- @return boolean
function EditMode.IsActive()
	return isActive
end

--- Get the overlay frame.
--- @return Frame|nil
function EditMode.GetOverlay()
	return overlay
end

-- ============================================================
-- Combat Protection
-- ============================================================

local combatFrame = CreateFrame('Frame')
combatFrame:RegisterEvent('PLAYER_REGEN_DISABLED')
combatFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
combatFrame:SetScript('OnEvent', function(self, event)
	if(not isActive) then return end

	if(event == 'PLAYER_REGEN_DISABLED') then
		-- Stop any active drag, hide overlay
		if(overlay and overlay:IsShown()) then
			overlay:Hide()
		end
	elseif(event == 'PLAYER_REGEN_ENABLED') then
		-- Re-show overlay
		if(isActive and overlay) then
			overlay:Show()
		end
	end
end)
```

- [ ] **Step 2: Test in-game**

```
/reload
/framed edit
```
Verify:
- Overlay appears with red border and dark dimming
- Escape closes edit mode
- `/framed edit` while in combat shows the combat message
- Overlay appears/disappears correctly

- [ ] **Step 3: Commit**

```bash
git add EditMode/EditMode.lua
git commit -m "feat: rewrite EditMode overlay with border, dim, combat protection"
```

---

## Task 7: Create Click Catchers

**Purpose:** Transparent frames placed over each unit frame that handle click-to-select in edit mode. Show "Click to edit" text and dim state.

**Files:**
- Create: `EditMode/ClickCatchers.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Create `EditMode/ClickCatchers.lua`**

```lua
local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode

-- ============================================================
-- ClickCatchers — transparent frames over unit frames for
-- click-to-select in edit mode.
-- ============================================================

local catchers = {}
local DIM_OVERLAY_ALPHA = 0.7

local function DestroyCatchers()
	for _, catcher in next, catchers do
		catcher:Hide()
		catcher:SetParent(nil)
	end
	catchers = {}
end

local function CreateCatcher(def, overlay)
	local frame = def.getter()
	if(not frame) then return end

	local catcher = CreateFrame('Button', nil, overlay)
	catcher:SetFrameLevel(overlay:GetFrameLevel() + 10)
	catcher:SetAllPoints(frame)

	-- Dark accent overlay
	local dimTex = catcher:CreateTexture(nil, 'ARTWORK')
	dimTex:SetAllPoints(catcher)
	local accent = C.Colors.accent
	dimTex:SetColorTexture(accent[1] * 0.15, accent[2] * 0.15, accent[3] * 0.15, DIM_OVERLAY_ALPHA)
	catcher._dimTex = dimTex

	-- "Click to edit" label
	local label = Widgets.CreateFontString(catcher, C.Font.sizeSmall, C.Colors.textNormal)
	label:SetPoint('CENTER', catcher, 'CENTER', 0, 0)
	label:SetText('Click to edit')
	catcher._label = label

	-- Hover highlight
	catcher:SetScript('OnEnter', function(self)
		self._dimTex:SetAlpha(DIM_OVERLAY_ALPHA * 0.5)
		self._label:SetTextColor(1, 1, 1, 1)
	end)
	catcher:SetScript('OnLeave', function(self)
		self._dimTex:SetAlpha(DIM_OVERLAY_ALPHA)
		local tn = C.Colors.textNormal
		self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)
	end)

	-- Click → select this frame
	catcher._frameKey = def.key
	catcher._isGroup = def.isGroup
	catcher:SetScript('OnClick', function(self)
		EditMode.SetSelectedFrameKey(self._frameKey)
	end)

	catchers[def.key] = catcher
	return catcher
end

local function CreateAllCatchers()
	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	DestroyCatchers()
	for _, def in next, EditMode.FRAME_KEYS do
		CreateCatcher(def, overlay)
	end
end

--- Hide a specific catcher (when its frame is selected for editing).
local function HideCatcher(frameKey)
	if(catchers[frameKey]) then
		catchers[frameKey]:Hide()
	end
end

--- Show all catchers (deselect state).
local function ShowAllCatchers()
	for _, catcher in next, catchers do
		catcher:Show()
	end
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_ENTERED', function()
	CreateAllCatchers()
end, 'ClickCatchers')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyCatchers()
end, 'ClickCatchers')

F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
	-- Show all catchers first, then hide the selected one
	ShowAllCatchers()
	if(frameKey) then
		HideCatcher(frameKey)
	end
end, 'ClickCatchers')
```

- [ ] **Step 2: Add to `Framed.toc`**

Add after `EditMode/EditCache.lua`:

```
EditMode/ClickCatchers.lua
```

- [ ] **Step 3: Test in-game**

```
/reload
/framed edit
```
Verify:
- All visible unit frames have a dimmed "Click to edit" overlay
- Hovering brightens the catcher
- Clicking a catcher prints/fires the frame selection event
- The clicked frame's catcher disappears

- [ ] **Step 4: Commit**

```bash
git add EditMode/ClickCatchers.lua Framed.toc
git commit -m "feat: add click catcher overlays for edit mode frame selection"
```

---

## Task 8: Create Top Bar

**Purpose:** Centered top bar with preset dropdown, "Editing: X" label, grid controls, Save, and Cancel buttons.

**Files:**
- Create: `EditMode/TopBar.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Create `EditMode/TopBar.lua`**

```lua
local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode

-- ============================================================
-- TopBar — preset dropdown, editing label, grid controls,
-- save/cancel buttons. Centered at top of screen.
-- ============================================================

local TOP_BAR_WIDTH   = 580
local TOP_BAR_HEIGHT  = 40
local BUTTON_WIDTH    = 90
local BUTTON_HEIGHT   = 22
local DROPDOWN_W      = 140

local topBar = nil

local function BuildTopBar()
	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	topBar = Widgets.CreateBorderedFrame(overlay, TOP_BAR_WIDTH, TOP_BAR_HEIGHT, C.Colors.panel, C.Colors.border)
	topBar:SetFrameLevel(overlay:GetFrameLevel() + 50)
	topBar:SetPoint('TOP', UIParent, 'TOP', 0, -C.Spacing.tight)

	-- ── Preset dropdown (left) ──────────────────────────────
	local presetDD = Widgets.CreateDropdown(topBar, DROPDOWN_W)
	local items = {}
	for _, name in next, C.PresetOrder do
		items[#items + 1] = { text = name, value = name }
	end
	presetDD:SetItems(items)
	presetDD:SetValue(EditMode.GetSessionPreset())
	presetDD:ClearAllPoints()
	presetDD:SetPoint('LEFT', topBar, 'LEFT', C.Spacing.normal, 0)
	presetDD:SetOnSelect(function(value)
		F.EventBus:Fire('EDIT_MODE_PRESET_SWAP_REQUESTED', value)
	end)
	topBar._presetDD = presetDD

	-- ── "Editing: X" label ──────────────────────────────────
	local editLabel = Widgets.CreateFontString(topBar, C.Font.sizeNormal, C.Colors.accent)
	editLabel:SetPoint('LEFT', presetDD, 'RIGHT', C.Spacing.normal, 0)
	editLabel:SetText('Editing: ' .. EditMode.GetSessionPreset())
	topBar._editLabel = editLabel

	-- ── Cancel button (rightmost) ───────────────────────────
	local cancelBtn = Widgets.CreateButton(topBar, 'Cancel', 'widget', BUTTON_WIDTH, BUTTON_HEIGHT)
	cancelBtn:SetPoint('RIGHT', topBar, 'RIGHT', -C.Spacing.normal, 0)
	cancelBtn:SetOnClick(function()
		EditMode.RequestCancel()
	end)

	-- ── Save button ─────────────────────────────────────────
	local saveBtn = Widgets.CreateButton(topBar, 'Save', 'accent', BUTTON_WIDTH, BUTTON_HEIGHT)
	saveBtn:SetPoint('RIGHT', cancelBtn, 'LEFT', -C.Spacing.base, 0)
	saveBtn:SetOnClick(function()
		EditMode.RequestSave()
	end)

	-- ── Grid Style selector ─────────────────────────────────
	local gridStyleSwitch = Widgets.CreateSwitch(topBar, 100, BUTTON_HEIGHT, {
		{ text = 'Lines', value = 'lines' },
		{ text = 'Dots',  value = 'dots' },
	})
	gridStyleSwitch:SetValue('lines')
	gridStyleSwitch:SetPoint('RIGHT', saveBtn, 'LEFT', -C.Spacing.normal, 0)
	gridStyleSwitch:SetOnSelect(function(value)
		F.EventBus:Fire('EDIT_MODE_GRID_STYLE_CHANGED', value)
	end)
	topBar._gridStyleSwitch = gridStyleSwitch

	-- ── Grid Snap toggle ────────────────────────────────────
	local snapBtn = Widgets.CreateButton(topBar, 'Grid Snap', 'widget', BUTTON_WIDTH, BUTTON_HEIGHT)
	snapBtn:SetPoint('RIGHT', gridStyleSwitch, 'LEFT', -C.Spacing.base, 0)
	topBar._snapBtn = snapBtn
	topBar._gridSnap = true

	local function UpdateSnapButton()
		if(topBar._gridSnap) then
			local accent = C.Colors.accent
			snapBtn:SetBackdropColor(C.Colors.accentDim[1], C.Colors.accentDim[2], C.Colors.accentDim[3], C.Colors.accentDim[4] or 1)
			snapBtn:SetBackdropBorderColor(accent[1], accent[2], accent[3], accent[4] or 1)
			snapBtn._label:SetTextColor(1, 1, 1, 1)
		else
			local s = snapBtn._scheme
			snapBtn:SetBackdropColor(s.bg[1], s.bg[2], s.bg[3], s.bg[4] or 1)
			local bc = s.border
			snapBtn:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
			local tc = s.textColor
			snapBtn._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
	end

	snapBtn:SetOnClick(function()
		topBar._gridSnap = not topBar._gridSnap
		UpdateSnapButton()
		F.EventBus:Fire('EDIT_MODE_GRID_SNAP_CHANGED', topBar._gridSnap)
	end)
	UpdateSnapButton()
end

local function DestroyTopBar()
	if(topBar) then
		topBar:Hide()
		topBar:SetParent(nil)
		topBar = nil
	end
end

--- Update the "Editing: X" label text.
local function UpdateEditingLabel(presetName)
	if(topBar and topBar._editLabel) then
		topBar._editLabel:SetText('Editing: ' .. presetName)
	end
end

--- Get current grid snap state.
function EditMode.IsGridSnapEnabled()
	return topBar and topBar._gridSnap or false
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_ENTERED', function()
	BuildTopBar()
end, 'TopBar')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyTopBar()
end, 'TopBar')

F.EventBus:Register('EDITING_PRESET_CHANGED', function(presetName)
	UpdateEditingLabel(presetName)
end, 'TopBar.EditingLabel')

F.EventBus:Register('EDIT_MODE_PRESET_SWAP_CANCELLED', function()
	-- Revert dropdown to the current preset when user cancels a swap
	if(topBar and topBar._presetDD) then
		topBar._presetDD:SetValue(EditMode.GetSessionPreset())
	end
end, 'TopBar.PresetSwapCancel')
```

- [ ] **Step 2: Add to `Framed.toc`**

Add after `EditMode/ClickCatchers.lua`:

```
EditMode/TopBar.lua
```

- [ ] **Step 3: Test in-game**

```
/reload
/framed edit
```
Verify:
- Top bar appears centered at top, not full width
- Preset dropdown shows all presets
- "Editing: X" text in green accent
- Grid Snap toggle changes visual state
- Save and Cancel buttons are clickable

- [ ] **Step 4: Commit**

```bash
git add EditMode/TopBar.lua Framed.toc
git commit -m "feat: add edit mode top bar with preset dropdown and grid controls"
```

---

## Task 9: Create Edit Mode Dialogs

**Purpose:** Wire up the 3-button Save, Cancel, and Preset Swap confirmation dialogs.

**Files:**
- Create: `EditMode/Dialogs.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Create `EditMode/Dialogs.lua`**

```lua
local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local EditMode = F.EditMode
local EditCache = F.EditCache

-- ============================================================
-- Edit Mode Dialogs
-- ============================================================

-- ── Keyboard conflict prevention ────────────────────────────
-- When a dialog is open, disable the overlay's Escape handler
-- so the dialog consumes Escape exclusively.
local function SuppressOverlayKeyboard()
	local overlay = EditMode.GetOverlay()
	if(overlay) then overlay:EnableKeyboard(false) end
end

local function RestoreOverlayKeyboard()
	local overlay = EditMode.GetOverlay()
	if(overlay and EditMode.IsActive()) then overlay:EnableKeyboard(true) end
end

-- ── Save Dialog ─────────────────────────────────────────────
F.EventBus:Register('EDIT_MODE_SHOW_SAVE_DIALOG', function()
	SuppressOverlayKeyboard()
	Widgets.ShowThreeButtonDialog(
		'Save Changes',
		'How would you like to save your edit mode changes?',
		'Save + Exit',
		'Save + Menu',
		'Continue Editing',
		function() EditMode.Save(false) end,   -- Save and Exit
		function() EditMode.Save(true) end,    -- Save and Return to Menu
		function() RestoreOverlayKeyboard() end  -- Continue Editing (restore keyboard)
	)
end, 'EditMode.Dialogs')

-- ── Cancel Dialog ───────────────────────────────────────────
F.EventBus:Register('EDIT_MODE_SHOW_CANCEL_DIALOG', function()
	SuppressOverlayKeyboard()
	Widgets.ShowThreeButtonDialog(
		'Discard Changes?',
		'You have unsaved changes. What would you like to do?',
		'Discard + Exit',
		'Discard + Menu',
		'Continue Editing',
		function() EditMode.Discard(false) end,  -- Discard and Exit
		function() EditMode.Discard(true) end,   -- Discard and Return to Menu
		function() RestoreOverlayKeyboard() end  -- Continue Editing (restore keyboard)
	)
end, 'EditMode.Dialogs')

-- ── Preset Swap Dialog ──────────────────────────────────────
F.EventBus:Register('EDIT_MODE_PRESET_SWAP_REQUESTED', function(newPreset)
	if(not EditCache.HasAnyEdits()) then
		-- No edits, just switch
		EditMode.SetSessionPreset(newPreset)
		F.Settings.SetEditingPreset(newPreset)
		F.EventBus:Fire('EDIT_MODE_PRESET_SWITCHED', newPreset)
		return
	end

	SuppressOverlayKeyboard()
	Widgets.ShowThreeButtonDialog(
		'Switch Preset',
		'You have unsaved changes to the current preset. What would you like to do?',
		'Save + Switch',
		'Discard + Switch',
		'Continue Editing',
		function()
			-- Save current, then switch
			RestoreOverlayKeyboard()
			EditCache.Commit()
			EditCache.Activate()
			EditMode.SetSessionPreset(newPreset)
			F.Settings.SetEditingPreset(newPreset)
			F.EventBus:Fire('EDIT_MODE_PRESET_SWITCHED', newPreset)
		end,
		function()
			-- Discard current, then switch
			RestoreOverlayKeyboard()
			EditCache.Discard()
			EditCache.Activate()
			EditMode.SetSessionPreset(newPreset)
			F.Settings.SetEditingPreset(newPreset)
			F.EventBus:Fire('EDIT_MODE_PRESET_SWITCHED', newPreset)
		end,
		function()
			-- Continue Editing — revert dropdown to current preset
			RestoreOverlayKeyboard()
			F.EventBus:Fire('EDIT_MODE_PRESET_SWAP_CANCELLED')
		end
	)
end, 'EditMode.Dialogs')
```

- [ ] **Step 2: Add to `Framed.toc`**

Add after `EditMode/TopBar.lua`:

```
EditMode/Dialogs.lua
```

- [ ] **Step 3: Test in-game**

```
/reload
/framed edit
```
- Click Save → verify 3-button dialog appears with correct labels
- Click Cancel → verify 3-button dialog appears
- If no edits, Cancel should exit immediately (no dialog)
- Switch preset dropdown → dialog should appear if edits exist

- [ ] **Step 4: Commit**

```bash
git add EditMode/Dialogs.lua Framed.toc
git commit -m "feat: add edit mode confirmation dialogs (save/cancel/preset swap)"
```

---

## Task 10: Create Grid Rendering

**Purpose:** Render a visual grid (lines or dots) on the overlay when grid snap is enabled.

**Files:**
- Create: `EditMode/Grid.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Create `EditMode/Grid.lua`**

```lua
local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode

-- ============================================================
-- Grid — Visual grid rendering for edit mode
-- ============================================================

local GRID_SPACING = C.Spacing.base  -- 4px
local GRID_COLOR   = { 1, 1, 1, 0.06 }
local DOT_SIZE     = 1

local gridFrame = nil
local gridStyle = 'lines'   -- 'lines' or 'dots'
local activeTextures = {}   -- currently visible textures
local texturePool = {}      -- recycled hidden textures

--- Get a texture from the pool or create a new one.
local function AcquireTexture()
	local tex = table.remove(texturePool)
	if(not tex) then
		tex = gridFrame:CreateTexture(nil, 'ARTWORK')
	end
	tex:Show()
	return tex
end

--- Return all active textures to the pool.
local function ClearGrid()
	for _, tex in next, activeTextures do
		tex:Hide()
		tex:ClearAllPoints()
		texturePool[#texturePool + 1] = tex
	end
	activeTextures = {}
end

local function RenderLines()
	ClearGrid()
	if(not gridFrame) then return end

	local w = GetScreenWidth()
	local h = GetScreenHeight()
	local idx = 0

	-- Vertical lines
	for x = GRID_SPACING, w, GRID_SPACING do
		idx = idx + 1
		local tex = AcquireTexture()
		tex:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
		tex:SetWidth(1)
		tex:SetPoint('TOP', gridFrame, 'TOPLEFT', x, 0)
		tex:SetPoint('BOTTOM', gridFrame, 'BOTTOMLEFT', x, 0)
		activeTextures[idx] = tex
	end

	-- Horizontal lines
	for y = GRID_SPACING, h, GRID_SPACING do
		idx = idx + 1
		local tex = AcquireTexture()
		tex:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
		tex:SetHeight(1)
		tex:SetPoint('LEFT', gridFrame, 'TOPLEFT', 0, -y)
		tex:SetPoint('RIGHT', gridFrame, 'TOPRIGHT', 0, -y)
		activeTextures[idx] = tex
	end
end

local function RenderDots()
	ClearGrid()
	if(not gridFrame) then return end

	local w = GetScreenWidth()
	local h = GetScreenHeight()
	local idx = 0
	-- Larger spacing for dots to reduce texture count
	local spacing = GRID_SPACING * 4

	for x = spacing, w, spacing do
		for y = spacing, h, spacing do
			idx = idx + 1
			local tex = AcquireTexture()
			tex:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4] * 2)
			tex:SetSize(DOT_SIZE, DOT_SIZE)
			tex:SetPoint('CENTER', gridFrame, 'TOPLEFT', x, -y)
			activeTextures[idx] = tex
		end
	end
end

local function RenderGrid()
	if(gridStyle == 'dots') then
		RenderDots()
	else
		RenderLines()
	end
end

local function BuildGridFrame()
	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	gridFrame = CreateFrame('Frame', nil, overlay)
	gridFrame:SetAllPoints(overlay)
	gridFrame:SetFrameLevel(overlay:GetFrameLevel() + 2)

	-- Only show grid if snap is enabled
	if(EditMode.IsGridSnapEnabled()) then
		RenderGrid()
		gridFrame:Show()
	else
		gridFrame:Hide()
	end
end

local function DestroyGridFrame()
	ClearGrid()
	if(gridFrame) then
		gridFrame:Hide()
		gridFrame:SetParent(nil)
		gridFrame = nil
	end
end

-- ============================================================
-- Snap Logic
-- ============================================================

--- Snap coordinates to the grid.
--- @param x number
--- @param y number
--- @return number, number
function EditMode.SnapToGrid(x, y)
	if(not EditMode.IsGridSnapEnabled()) then return x, y end
	return Widgets.Round(x / GRID_SPACING) * GRID_SPACING,
	       Widgets.Round(y / GRID_SPACING) * GRID_SPACING
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_ENTERED', function()
	BuildGridFrame()
end, 'Grid')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyGridFrame()
end, 'Grid')

F.EventBus:Register('EDIT_MODE_GRID_SNAP_CHANGED', function(enabled)
	if(not gridFrame) then return end
	if(enabled) then
		RenderGrid()
		gridFrame:Show()
	else
		ClearGrid()
		gridFrame:Hide()
	end
end, 'Grid')

F.EventBus:Register('EDIT_MODE_GRID_STYLE_CHANGED', function(style)
	gridStyle = style
	if(gridFrame and gridFrame:IsShown()) then
		RenderGrid()
	end
end, 'Grid')
```

- [ ] **Step 2: Add to `Framed.toc`**

Add after `EditMode/Dialogs.lua`:

```
EditMode/Grid.lua
```

- [ ] **Step 3: Test in-game**

```
/reload
/framed edit
```
- Verify grid lines appear behind frames
- Toggle Grid Snap off → grid disappears
- Switch to Dots style → dots appear
- Toggle snap off and back on → grid re-renders

- [ ] **Step 4: Commit**

```bash
git add EditMode/Grid.lua Framed.toc
git commit -m "feat: add grid rendering (lines/dots) for edit mode"
```

---

## Task 11: Create Alignment Guides

**Purpose:** Red alignment guide lines that fade in/out during frame dragging when approaching center or edge alignment with other frames.

**Files:**
- Create: `EditMode/AlignmentGuides.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Create `EditMode/AlignmentGuides.lua`**

```lua
local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode

-- ============================================================
-- AlignmentGuides — Red lines during drag for center/edge snap
-- ============================================================

local GUIDE_COLOR     = { 0.8, 0.1, 0.1, 0.8 }
local GUIDE_THICKNESS = 1
local SNAP_THRESHOLD  = 8   -- pixels proximity to show guide
local FADE_SPEED      = 0.15

local guideFrame = nil
local guides = {
	centerH = nil,  -- horizontal center line
	centerV = nil,  -- vertical center line
}
local edgeGuides = {}  -- dynamic edge alignment lines

local function CreateGuide(parent, isHorizontal)
	local tex = parent:CreateTexture(nil, 'OVERLAY')
	tex:SetColorTexture(GUIDE_COLOR[1], GUIDE_COLOR[2], GUIDE_COLOR[3], 0)
	if(isHorizontal) then
		tex:SetHeight(GUIDE_THICKNESS)
		tex:SetPoint('LEFT', parent, 'LEFT', 0, 0)
		tex:SetPoint('RIGHT', parent, 'RIGHT', 0, 0)
	else
		tex:SetWidth(GUIDE_THICKNESS)
		tex:SetPoint('TOP', parent, 'TOP', 0, 0)
		tex:SetPoint('BOTTOM', parent, 'BOTTOM', 0, 0)
	end
	tex._targetAlpha = 0
	tex._isHorizontal = isHorizontal
	return tex
end

local function SetGuidePosition(guide, offset)
	guide:ClearAllPoints()
	if(guide._isHorizontal) then
		guide:SetHeight(GUIDE_THICKNESS)
		guide:SetPoint('LEFT', guideFrame, 'LEFT', 0, 0)
		guide:SetPoint('RIGHT', guideFrame, 'RIGHT', 0, 0)
		guide:SetPoint('TOP', guideFrame, 'CENTER', 0, offset)
	else
		guide:SetWidth(GUIDE_THICKNESS)
		guide:SetPoint('TOP', guideFrame, 'TOP', 0, 0)
		guide:SetPoint('BOTTOM', guideFrame, 'BOTTOM', 0, 0)
		guide:SetPoint('LEFT', guideFrame, 'CENTER', offset, 0)
	end
end

local function FadeGuide(guide, targetAlpha, dt)
	local current = guide:GetAlpha()
	if(math.abs(current - targetAlpha) < 0.01) then
		guide:SetAlpha(targetAlpha)
		return
	end
	local step = dt / FADE_SPEED
	if(targetAlpha > current) then
		guide:SetAlpha(math.min(current + step, targetAlpha))
	else
		guide:SetAlpha(math.max(current - step, targetAlpha))
	end
end

local function BuildGuideFrame()
	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	guideFrame = CreateFrame('Frame', nil, overlay)
	guideFrame:SetAllPoints(overlay)
	guideFrame:SetFrameLevel(overlay:GetFrameLevel() + 40)
	guideFrame:Hide()

	guides.centerH = CreateGuide(guideFrame, true)
	guides.centerV = CreateGuide(guideFrame, false)

	-- OnUpdate for smooth fade
	guideFrame:SetScript('OnUpdate', function(self, dt)
		for _, guide in next, guides do
			FadeGuide(guide, guide._targetAlpha, dt)
		end
		for _, guide in next, edgeGuides do
			FadeGuide(guide, guide._targetAlpha, dt)
		end
	end)
end

local function DestroyGuideFrame()
	if(guideFrame) then
		guideFrame:Hide()
		guideFrame:SetParent(nil)
		guideFrame = nil
	end
	guides = { centerH = nil, centerV = nil }
	edgeGuides = {}
end

-- ============================================================
-- Public API (called by drag handlers)
-- ============================================================

--- Update alignment guides based on the dragging frame's position.
--- Call this from the onMove callback during a frame drag.
--- @param dragFrame Frame  The frame being dragged
function EditMode.UpdateAlignmentGuides(dragFrame)
	if(not guideFrame) then return end
	guideFrame:Show()

	local screenW = GetScreenWidth()
	local screenH = GetScreenHeight()
	local screenCX = screenW / 2
	local screenCY = screenH / 2

	-- Dragging frame bounds
	local left = dragFrame:GetLeft() or 0
	local right = dragFrame:GetRight() or 0
	local top = dragFrame:GetTop() or 0
	local bottom = dragFrame:GetBottom() or 0
	local cx = (left + right) / 2
	local cy = (top + bottom) / 2

	-- Center vertical guide (frame center X near screen center X)
	if(math.abs(cx - screenCX) < SNAP_THRESHOLD) then
		guides.centerV._targetAlpha = GUIDE_COLOR[4]
		SetGuidePosition(guides.centerV, 0)
	else
		guides.centerV._targetAlpha = 0
	end

	-- Center horizontal guide (frame center Y near screen center Y)
	if(math.abs(cy - screenCY) < SNAP_THRESHOLD) then
		guides.centerH._targetAlpha = GUIDE_COLOR[4]
		SetGuidePosition(guides.centerH, 0)
	else
		guides.centerH._targetAlpha = 0
	end

	-- Edge alignment with other frames (future: iterate other frame positions)
	-- For now, center guides only. Edge guides will be added when more frames are
	-- integrated into the drag system.
end

--- Hide all alignment guides (called on drag stop).
function EditMode.HideAlignmentGuides()
	if(not guideFrame) then return end
	for _, guide in next, guides do
		guide._targetAlpha = 0
	end
	for _, guide in next, edgeGuides do
		guide._targetAlpha = 0
	end
	-- Hide the frame after fade completes
	C_Timer.After(FADE_SPEED + 0.05, function()
		if(guideFrame) then guideFrame:Hide() end
	end)
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_ENTERED', function()
	BuildGuideFrame()
end, 'AlignmentGuides')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyGuideFrame()
end, 'AlignmentGuides')
```

- [ ] **Step 2: Add to `Framed.toc`**

Add after `EditMode/Grid.lua`:

```
EditMode/AlignmentGuides.lua
```

- [ ] **Step 3: Commit**

```bash
git add EditMode/AlignmentGuides.lua Framed.toc
git commit -m "feat: add alignment guide lines for edit mode dragging"
```

---

## Task 12: Create Resize Handles

**Purpose:** Drag handles on edges/corners of selected single-unit frames for resizing with live width/height updates.

**Files:**
- Create: `EditMode/ResizeHandles.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Create `EditMode/ResizeHandles.lua`**

```lua
local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode
local EditCache = F.EditCache

-- ============================================================
-- ResizeHandles — Edge/corner drag handles for frame resizing
-- ============================================================

local HANDLE_SIZE    = 8
local HANDLE_COLOR   = { C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 0.6 }
local HANDLE_HOVER   = { 1, 1, 1, 0.8 }

local handles = {}

local HANDLE_POINTS = {
	'TOPLEFT', 'TOP', 'TOPRIGHT',
	'LEFT', 'RIGHT',
	'BOTTOMLEFT', 'BOTTOM', 'BOTTOMRIGHT',
}

local CURSORS = {
	TOPLEFT     = 'UI_RESIZE_TOPLEFT',
	TOP         = 'UI_RESIZE_TOP',
	TOPRIGHT    = 'UI_RESIZE_TOPRIGHT',
	LEFT        = 'UI_RESIZE_LEFT',
	RIGHT       = 'UI_RESIZE_RIGHT',
	BOTTOMLEFT  = 'UI_RESIZE_BOTTOMLEFT',
	BOTTOM      = 'UI_RESIZE_BOTTOM',
	BOTTOMRIGHT = 'UI_RESIZE_BOTTOMRIGHT',
}

local function DestroyHandles()
	for _, handle in next, handles do
		handle:Hide()
		handle:SetParent(nil)
	end
	handles = {}
end

local function CreateHandle(parent, point, targetFrame, frameKey)
	local handle = CreateFrame('Button', nil, parent)
	handle:SetSize(HANDLE_SIZE, HANDLE_SIZE)
	handle:SetPoint('CENTER', targetFrame, point, 0, 0)
	handle:SetFrameLevel(parent:GetFrameLevel() + 60)

	local tex = handle:CreateTexture(nil, 'OVERLAY')
	tex:SetAllPoints(handle)
	tex:SetColorTexture(HANDLE_COLOR[1], HANDLE_COLOR[2], HANDLE_COLOR[3], HANDLE_COLOR[4])
	handle._tex = tex

	-- Tooltip
	handle:SetScript('OnEnter', function(self)
		self._tex:SetColorTexture(HANDLE_HOVER[1], HANDLE_HOVER[2], HANDLE_HOVER[3], HANDLE_HOVER[4])
		GameTooltip:SetOwner(self, 'ANCHOR_CURSOR')
		GameTooltip:AddLine('Drag to resize', 1, 1, 1)
		GameTooltip:Show()
	end)

	handle:SetScript('OnLeave', function(self)
		self._tex:SetColorTexture(HANDLE_COLOR[1], HANDLE_COLOR[2], HANDLE_COLOR[3], HANDLE_COLOR[4])
		GameTooltip:Hide()
	end)

	-- Resize dragging
	handle:EnableMouse(true)
	handle:RegisterForDrag('LeftButton')

	handle:SetScript('OnDragStart', function(self)
		local scale = targetFrame:GetEffectiveScale()
		local sx, sy = GetCursorPosition()
		local startW = targetFrame:GetWidth()
		local startH = targetFrame:GetHeight()
		local startX = sx / scale
		local startY = sy / scale

		-- Only run OnUpdate during active drag
		self:SetScript('OnUpdate', function(s)
			local cx, cy = GetCursorPosition()
			cx = cx / scale
			cy = cy / scale

			local dx = cx - startX
			local dy = cy - startY
			local newW = startW
			local newH = startH

			-- Determine resize direction based on handle point
			if(point == 'RIGHT' or point == 'TOPRIGHT' or point == 'BOTTOMRIGHT') then
				newW = math.max(20, startW + dx)
			elseif(point == 'LEFT' or point == 'TOPLEFT' or point == 'BOTTOMLEFT') then
				newW = math.max(20, startW - dx)
			end
			if(point == 'TOP' or point == 'TOPLEFT' or point == 'TOPRIGHT') then
				newH = math.max(16, startH + dy)
			elseif(point == 'BOTTOM' or point == 'BOTTOMLEFT' or point == 'BOTTOMRIGHT') then
				newH = math.max(16, startH - dy)
			end

			-- Snap to grid if enabled
			if(EditMode.IsGridSnapEnabled()) then
				newW = Widgets.Round(newW / C.Spacing.base) * C.Spacing.base
				newH = Widgets.Round(newH / C.Spacing.base) * C.Spacing.base
			end

			targetFrame:SetSize(newW, newH)

			-- Update edit cache
			EditCache.Set(frameKey, 'width', Widgets.Round(newW))
			EditCache.Set(frameKey, 'height', Widgets.Round(newH))

			-- Fire event for live settings panel update
			F.EventBus:Fire('EDIT_MODE_FRAME_RESIZED', frameKey, newW, newH)
		end)
	end)

	handle:SetScript('OnDragStop', function(self)
		self:SetScript('OnUpdate', nil)
	end)

	return handle
end

local function CreateHandlesForFrame(overlay, targetFrame, frameKey)
	DestroyHandles()
	for _, point in next, HANDLE_POINTS do
		handles[#handles + 1] = CreateHandle(overlay, point, targetFrame, frameKey)
	end
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
	DestroyHandles()
	if(not frameKey) then return end

	-- Only show resize handles for non-group frames
	for _, def in next, EditMode.FRAME_KEYS do
		if(def.key == frameKey and not def.isGroup) then
			local frame = def.getter()
			local overlay = EditMode.GetOverlay()
			if(frame and overlay) then
				CreateHandlesForFrame(overlay, frame, frameKey)
			end
			break
		end
	end
end, 'ResizeHandles')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyHandles()
end, 'ResizeHandles')
```

- [ ] **Step 2: Add to `Framed.toc`**

Add after `EditMode/AlignmentGuides.lua`:

```
EditMode/ResizeHandles.lua
```

- [ ] **Step 3: Commit**

```bash
git add EditMode/ResizeHandles.lua Framed.toc
git commit -m "feat: add resize handles for edit mode frame resizing"
```

---

## Task 13: Add Position & Layout Card to FrameSettingsBuilder

**Purpose:** Add anchor picker, X/Y position fields, and pixel nudge arrows to frame settings. These appear in both the sidebar and edit mode inline panel. Also make the builder edit-cache-aware so inline panel changes go through the shadow config.

**Files:**
- Modify: `Settings/FrameSettingsBuilder.lua`

- [ ] **Step 1: Make getConfig/setConfig edit-cache-aware**

In `Settings/FrameSettingsBuilder.lua`, update the `getConfig` and `setConfig` local functions (around lines 98-104) to route through EditCache when active:

```lua
	local function getConfig(key)
		if(F.EditCache and F.EditCache.IsActive()) then
			return F.EditCache.Get(unitType, key)
		end
		return F.Config:Get('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key)
	end
	local function setConfig(key, value)
		if(F.EditCache and F.EditCache.IsActive()) then
			F.EditCache.Set(unitType, key, value)
			return
		end
		F.Config:Set('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key, value)
		F.PresetManager.MarkCustomized(getPresetName())
	end
```

This ensures that when the inline panel is built during edit mode, all widget reads come from the cache overlay and all writes go to the cache — not directly to saved config.

- [ ] **Step 2: Add Position & Layout card after the Frame Size section**

In `Settings/FrameSettingsBuilder.lua`, after the Frame Size card's `Widgets.EndCard(sizeCard, content, cardY)` (around line 139), add:

```lua
	-- ============================================================
	-- Position & Layout
	-- ============================================================

	yOffset = placeHeading(content, 'Position & Layout', 2, yOffset)

	local posCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	-- Info icon for this card
	local posInfo = Widgets.CreateInfoIcon(inner,
		'Position & Layout',
		'Anchor point determines which corner of the frame is pinned to its position. '
		.. 'Growth direction controls which way group frames expand. '
		.. 'These two settings work together to control frame placement.')
	posInfo:SetPoint('TOPRIGHT', inner, 'TOPRIGHT', -4, -4)

	-- Frame Anchor Point picker
	cardY = placeHeading(inner, 'Frame Anchor', 3, cardY)
	local anchorPicker = Widgets.CreateAnchorPicker(inner, WIDGET_W)
	local savedAnchor = getConfig('position.anchor') or 'CENTER'
	local savedPosX = getConfig('position.x') or 0
	local savedPosY = getConfig('position.y') or 0
	anchorPicker:SetAnchor(savedAnchor, savedPosX, savedPosY)
	anchorPicker:SetOnChanged(function(point, x, y)
		setConfig('position.anchor', point)
		setConfig('position.x', x)
		setConfig('position.y', y)
	end)
	cardY = placeWidget(anchorPicker, inner, cardY, 80)

	-- Pixel nudge arrows
	cardY = placeHeading(inner, 'Pixel Nudge', 3, cardY)

	local nudgeFrame = CreateFrame('Frame', nil, inner)
	nudgeFrame:SetSize(100, 50)

	local nudgeUp = Widgets.CreateButton(nudgeFrame, '^', 'widget', 24, 20)
	nudgeUp:SetPoint('TOP', nudgeFrame, 'TOP', 0, 0)
	local nudgeDown = Widgets.CreateButton(nudgeFrame, 'v', 'widget', 24, 20)
	nudgeDown:SetPoint('BOTTOM', nudgeFrame, 'BOTTOM', 0, 0)
	local nudgeLeft = Widgets.CreateButton(nudgeFrame, '<', 'widget', 24, 20)
	nudgeLeft:SetPoint('LEFT', nudgeFrame, 'LEFT', 0, 0)
	local nudgeRight = Widgets.CreateButton(nudgeFrame, '>', 'widget', 24, 20)
	nudgeRight:SetPoint('RIGHT', nudgeFrame, 'RIGHT', 0, 0)

	local function nudge(dx, dy)
		local point, curX, curY = anchorPicker:GetAnchor()
		anchorPicker:SetAnchor(point, curX + dx, curY + dy)
		setConfig('position.x', curX + dx)
		setConfig('position.y', curY + dy)
	end

	nudgeUp:SetOnClick(function() nudge(0, 1) end)
	nudgeDown:SetOnClick(function() nudge(0, -1) end)
	nudgeLeft:SetOnClick(function() nudge(-1, 0) end)
	nudgeRight:SetOnClick(function() nudge(1, 0) end)

	cardY = placeWidget(nudgeFrame, inner, cardY, 50)

	yOffset = Widgets.EndCard(posCard, content, cardY)
```

- [ ] **Step 2: Add text anchor pickers to the Name and Health Text sections**

In the Name card (around line 260-293), after the name truncation slider, add:

```lua
	-- Name text position anchor
	cardY = placeHeading(inner, 'Text Position', 3, cardY)
	local nameAnchor = Widgets.CreateAnchorPicker(inner, WIDGET_W)
	local savedNameAnchor = getConfig('name.anchor') or 'LEFT'
	nameAnchor:SetAnchor(savedNameAnchor, 0, 0)
	nameAnchor:SetOnChanged(function(point)
		setConfig('name.anchor', point)
	end)
	-- Hide X/Y inputs — only the 3x3 grid matters for text positioning
	nameAnchor._xInput:Hide()
	nameAnchor._yInput:Hide()
	cardY = placeWidget(nameAnchor, inner, cardY, 56)
```

Similarly, in the Health Text card (around line 295-331), after the health format dropdown, add:

```lua
	-- Health text position anchor
	cardY = placeHeading(inner, 'Text Position', 3, cardY)
	local healthTextAnchor = Widgets.CreateAnchorPicker(inner, WIDGET_W)
	local savedHealthAnchor = getConfig('health.textAnchor') or 'CENTER'
	healthTextAnchor:SetAnchor(savedHealthAnchor, 0, 0)
	healthTextAnchor:SetOnChanged(function(point)
		setConfig('health.textAnchor', point)
	end)
	healthTextAnchor._xInput:Hide()
	healthTextAnchor._yInput:Hide()
	cardY = placeWidget(healthTextAnchor, inner, cardY, 56)
```

And after the power text checkbox:

```lua
	-- Power text position anchor
	cardY = placeHeading(inner, 'Power Text Position', 3, cardY)
	local powerTextAnchor = Widgets.CreateAnchorPicker(inner, WIDGET_W)
	local savedPowerAnchor = getConfig('power.textAnchor') or 'CENTER'
	powerTextAnchor:SetAnchor(savedPowerAnchor, 0, 0)
	powerTextAnchor:SetOnChanged(function(point)
		setConfig('power.textAnchor', point)
	end)
	powerTextAnchor._xInput:Hide()
	powerTextAnchor._yInput:Hide()
	cardY = placeWidget(powerTextAnchor, inner, cardY, 56)
```

- [ ] **Step 3: Test in-game**

```
/reload
/framed config
```
Open any frame settings panel (Player, Target, etc.). Verify:
- Position & Layout card appears with (i) icon, anchor picker, X/Y fields, nudge arrows
- Name card has text position anchor picker
- Health Text card has text position and power text position anchor pickers
- Changes are saved to config

- [ ] **Step 4: Commit**

```bash
git add Settings/FrameSettingsBuilder.lua
git commit -m "feat: add Position & Layout card and text anchor pickers to frame settings"
```

---

## Task 14: Create Inline Settings Panel (InlinePanel)

**Purpose:** The recycled settings panel that appears next to a selected frame in edit mode. Uses `FrameSettingsBuilder.Create()` for frame settings tab and aura panel builders for the Auras tab.

**Files:**
- Create: `EditMode/InlinePanel.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Create `EditMode/InlinePanel.lua`**

This is the most complex component. It handles:
- Smart positioning (default right, flip at edges)
- Tab system (Frame name tab + Auras tab)
- Panel recycling (destroy and rebuild on frame switch)
- Slide in/out animation
- Aura group dimming on the live frame

```lua
local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode
local EditCache = F.EditCache

-- ============================================================
-- InlinePanel — Recycled settings panel attached to selected frame
-- ============================================================

local PANEL_WIDTH    = 380
local PANEL_MIN_H    = 300
local PANEL_MAX_H    = 600
local TAB_HEIGHT     = 28
local TAB_GAP        = 2
local EDGE_MARGIN    = 16

local panel       = nil
local activeTab   = nil   -- 'frame' or 'auras'
local currentKey  = nil
local contentFrame = nil

local function DestroyPanel()
	if(panel) then
		panel:Hide()
		panel:SetParent(nil)
		panel = nil
		contentFrame = nil
		activeTab = nil
		currentKey = nil
	end
end

--- Determine the best side to show the panel relative to the frame.
--- @param targetFrame Frame
--- @return string anchorSide  'RIGHT' or 'LEFT'
local function GetSmartSide(targetFrame)
	local screenW = GetScreenWidth()
	local frameRight = targetFrame:GetRight() or 0
	local frameLeft = targetFrame:GetLeft() or 0

	-- Space available on each side
	local spaceRight = screenW - frameRight
	local spaceLeft = frameLeft

	if(spaceRight >= PANEL_WIDTH + EDGE_MARGIN) then
		return 'RIGHT'
	elseif(spaceLeft >= PANEL_WIDTH + EDGE_MARGIN) then
		return 'LEFT'
	else
		-- Default to right, panel will overlap
		return 'RIGHT'
	end
end

local function BuildPanel(frameKey, targetFrame)
	DestroyPanel()

	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	currentKey = frameKey

	-- Create panel frame
	panel = Widgets.CreateBorderedFrame(overlay, PANEL_WIDTH, PANEL_MIN_H, C.Colors.panel, C.Colors.border)
	panel:SetFrameLevel(overlay:GetFrameLevel() + 30)

	-- Position relative to target frame
	local side = GetSmartSide(targetFrame)
	panel:ClearAllPoints()
	if(side == 'RIGHT') then
		panel:SetPoint('TOPLEFT', targetFrame, 'TOPRIGHT', EDGE_MARGIN, 0)
	else
		panel:SetPoint('TOPRIGHT', targetFrame, 'TOPLEFT', -EDGE_MARGIN, 0)
	end

	-- ── Tab buttons ─────────────────────────────────────────
	local frameDef = nil
	for _, def in next, EditMode.FRAME_KEYS do
		if(def.key == frameKey) then
			frameDef = def
			break
		end
	end

	local frameTabBtn = Widgets.CreateButton(panel, frameDef and frameDef.label or frameKey, 'accent', PANEL_WIDTH / 2 - TAB_GAP, TAB_HEIGHT)
	frameTabBtn:SetPoint('TOPLEFT', panel, 'TOPLEFT', 0, 0)

	local aurasTabBtn = Widgets.CreateButton(panel, 'Auras', 'widget', PANEL_WIDTH / 2 - TAB_GAP, TAB_HEIGHT)
	aurasTabBtn:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', 0, 0)

	-- ── Content area ────────────────────────────────────────
	contentFrame = CreateFrame('Frame', nil, panel)
	contentFrame:SetPoint('TOPLEFT', panel, 'TOPLEFT', 0, -TAB_HEIGHT - 2)
	contentFrame:SetPoint('BOTTOMRIGHT', panel, 'BOTTOMRIGHT', 0, 0)
	contentFrame._explicitWidth = PANEL_WIDTH
	contentFrame._explicitHeight = PANEL_MIN_H - TAB_HEIGHT - 2

	-- ── Build frame settings tab content ────────────────────
	local function ShowFrameTab()
		activeTab = 'frame'
		-- Clear content
		for _, child in next, { contentFrame:GetChildren() } do
			child:Hide()
			child:SetParent(nil)
		end

		-- Use FrameSettingsBuilder to create the same content as sidebar
		local unitType = frameKey
		-- Group frames use their config key
		if(frameDef and frameDef.isGroup) then
			local info = C.PresetInfo[F.Settings.GetEditingPreset()]
			unitType = (info and info.groupKey) or frameKey
		end

		local scrollPanel = F.FrameSettingsBuilder.Create(contentFrame, unitType)
		scrollPanel:SetAllPoints(contentFrame)
		scrollPanel:Show()

		-- Update tab visual
		frameTabBtn._label:SetTextColor(1, 1, 1, 1)
		aurasTabBtn._label:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3], 1)
	end

	local function ShowAurasTab()
		activeTab = 'auras'
		-- Clear content
		for _, child in next, { contentFrame:GetChildren() } do
			child:Hide()
			child:SetParent(nil)
		end

		-- TODO: Build auras dropdown + aura settings panel
		-- For now, show placeholder
		local placeholder = Widgets.CreateFontString(contentFrame, C.Font.sizeNormal, C.Colors.textSecondary)
		placeholder:SetPoint('CENTER', contentFrame, 'CENTER', 0, 0)
		placeholder:SetText('Auras tab - coming soon')

		-- Update tab visual
		aurasTabBtn._label:SetTextColor(1, 1, 1, 1)
		frameTabBtn._label:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3], 1)
	end

	frameTabBtn:SetOnClick(function() ShowFrameTab() end)
	aurasTabBtn:SetOnClick(function() ShowAurasTab() end)

	-- Default to frame tab
	ShowFrameTab()

	-- Slide in animation
	Widgets.FadeIn(panel)
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
	if(not frameKey) then
		DestroyPanel()
		return
	end

	-- Find the target frame
	local targetFrame = nil
	for _, def in next, EditMode.FRAME_KEYS do
		if(def.key == frameKey) then
			targetFrame = def.getter()
			break
		end
	end

	if(not targetFrame) then
		DestroyPanel()
		return
	end

	-- If switching frames, animate out then build new
	if(panel and currentKey ~= frameKey) then
		Widgets.FadeOut(panel, C.Animation.durationFast, function()
			BuildPanel(frameKey, targetFrame)
		end)
	else
		BuildPanel(frameKey, targetFrame)
	end
end, 'InlinePanel')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyPanel()
end, 'InlinePanel')
```

- [ ] **Step 2: Add to `Framed.toc`**

Add after `EditMode/ResizeHandles.lua`:

```
EditMode/InlinePanel.lua
```

- [ ] **Step 3: Test in-game**

```
/reload
/framed edit
```
- Click a frame → settings panel slides in on the right
- Click a different frame → panel animates out then in on new frame
- Frame tab shows the same settings as sidebar
- Panel positions correctly even for frames near screen edges

- [ ] **Step 4: Commit**

```bash
git add EditMode/InlinePanel.lua Framed.toc
git commit -m "feat: add inline settings panel for edit mode with smart positioning"
```

---

## Task 15: Wire Frame Dragging in Edit Mode

**Purpose:** Connect frame dragging with grid snap and alignment guides in the new edit mode.

**Files:**
- Modify: `EditMode/ClickCatchers.lua` (add drag wiring when frame is selected)
- Modify: `EditMode/EditMode.lua` (add drag setup on frame selection)

- [ ] **Step 1: Add drag wiring to frame selection**

In `EditMode/EditMode.lua`, update the `EDIT_MODE_FRAME_SELECTED` handling. After `SetSelectedFrameKey`, wire up dragging on the actual unit frame:

Add a new event listener at the bottom of `EditMode/EditMode.lua`:

```lua
-- ============================================================
-- Frame Drag Wiring
-- ============================================================

local currentDragFrame = nil

F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
	-- Remove drag from previous
	if(currentDragFrame) then
		currentDragFrame:SetMovable(false)
		currentDragFrame:EnableMouse(false)
		currentDragFrame:SetScript('OnDragStart', nil)
		currentDragFrame:SetScript('OnDragStop', nil)
		currentDragFrame:SetScript('OnUpdate', nil)
		currentDragFrame = nil
	end

	if(not frameKey) then return end

	-- Find the frame
	local targetFrame = nil
	for _, def in next, FRAME_KEYS do
		if(def.key == frameKey) then
			targetFrame = def.getter()
			break
		end
	end

	if(not targetFrame) then return end
	currentDragFrame = targetFrame

	Widgets.MakeDraggable(targetFrame,
		function(frame)  -- onDragStart
			-- nothing extra needed
		end,
		function(frame, x, y)  -- onDragStop
			local sx, sy = EditMode.SnapToGrid(x, y)
			if(sx ~= x or sy ~= y) then
				local point, relativeTo, relPoint = frame:GetPoint()
				frame:ClearAllPoints()
				frame:SetPoint(point, relativeTo, relPoint, sx, sy)
			end
			EditCache.Set(frameKey, 'position.x', sx)
			EditCache.Set(frameKey, 'position.y', sy)
			EditMode.HideAlignmentGuides()
		end,
		true,  -- clampToParent
		function(frame, x, y)  -- onMove
			EditMode.UpdateAlignmentGuides(frame)
		end
	)
end, 'EditMode.DragWiring')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	if(currentDragFrame) then
		currentDragFrame:SetMovable(false)
		currentDragFrame:EnableMouse(false)
		currentDragFrame:SetScript('OnDragStart', nil)
		currentDragFrame:SetScript('OnDragStop', nil)
		currentDragFrame:SetScript('OnUpdate', nil)
		currentDragFrame = nil
	end
end, 'EditMode.DragWiring')
```

- [ ] **Step 2: Test in-game**

```
/reload
/framed edit
```
- Click a frame to select it
- Drag the selected frame — it should move
- With Grid Snap on, frame snaps to grid on release
- Red alignment guides appear when near screen center

- [ ] **Step 3: Commit**

```bash
git add EditMode/EditMode.lua
git commit -m "feat: wire frame dragging with grid snap and alignment guides"
```

---

## Task 16: Update TOC and Final Integration

**Purpose:** Ensure all new files are in the TOC in correct load order, version bump, and full integration test.

**Files:**
- Modify: `Framed.toc`
- Modify: `Init.lua` (version bump)

- [ ] **Step 1: Verify TOC load order**

The `# Edit Mode` section in `Framed.toc` should be:

```
# Edit Mode
EditMode/EditCache.lua
EditMode/EditMode.lua
EditMode/ClickCatchers.lua
EditMode/TopBar.lua
EditMode/Dialogs.lua
EditMode/Grid.lua
EditMode/AlignmentGuides.lua
EditMode/ResizeHandles.lua
EditMode/InlinePanel.lua
```

Order matters: `EditCache` before `EditMode` (dependency), `EditMode` before everything else (provides `F.EditMode` namespace and `FRAME_KEYS`).

- [ ] **Step 2: Bump version**

In `Framed.toc`:
```
## Version: 0.2.1-alpha
```

In `Init.lua`:
```lua
F.version = '0.2.1-alpha'
```

- [ ] **Step 3: Sync to WoW folder and full integration test**

```bash
cp -R /Users/josiahtoppin/Documents/Projects/Framed/* "/Applications/World of Warcraft/_retail_/Interface/AddOns/Framed/"
```

In-game, test the full flow:
1. `/framed edit` — overlay appears with red border, dark dim, grid
2. All preset frames visible with "Click to edit" overlay
3. Click Player frame — catcher disappears, settings panel slides in, resize handles appear
4. Drag Player frame — alignment guides show near center, snap on release
5. Resize via corner handles — width/height update
6. Click Target frame — panel animates out/in, switches to Target settings
7. Click Save → 3-button dialog → "Save + Exit" → green border flash, exit
8. `/framed edit` again → make changes → Cancel → 3-button dialog → Discard
9. Switch preset dropdown with edits → swap dialog appears
10. Enter combat during edit mode → overlay hides → leave combat → overlay re-shows
11. Drag Player frame near Target frame's edge → red edge alignment guide appears
12. Click a frame → Auras tab → dropdown with 11 groups → select Debuffs → settings load, other auras dim

- [ ] **Step 4: Commit**

```bash
git add Framed.toc Init.lua
git commit -m "chore: bump version to 0.2.1-alpha, finalize edit mode TOC order"
```

---

## Task 17: Edge Alignment Guides

**Purpose:** Extend `AlignmentGuides.lua` (Task 11) to detect and show red alignment lines when a dragged frame's edges align with other visible frames' edges, not just screen center.

**Files:**
- Modify: `EditMode/AlignmentGuides.lua`

- [ ] **Step 1: Add edge guide pool and helper to collect visible frame bounds**

Add after the `edgeGuides = {}` declaration and before `CreateGuide`:

```lua
local EDGE_GUIDE_POOL_SIZE = 8  -- max simultaneous edge guides (4 edges x 2 axes)

--- Collect screen bounds for all visible frames except the one being dragged.
--- @param excludeFrame Frame
--- @return table[] Array of { left, right, top, bottom }
local function GetOtherFrameBounds(excludeFrame)
	local bounds = {}
	for _, def in next, EditMode.FRAME_KEYS do
		local frame = def.getter()
		if(frame and frame ~= excludeFrame and frame:IsVisible()) then
			local left = frame:GetLeft()
			local right = frame:GetRight()
			local top = frame:GetTop()
			local bottom = frame:GetBottom()
			if(left and right and top and bottom) then
				bounds[#bounds + 1] = {
					left   = left,
					right  = right,
					top    = top,
					bottom = bottom,
				}
			end
		end
	end
	return bounds
end
```

- [ ] **Step 2: Add edge alignment detection to `UpdateAlignmentGuides`**

Replace the comment block at the end of `UpdateAlignmentGuides`:

```lua
	-- Edge alignment with other frames (future: iterate other frame positions)
	-- For now, center guides only. Edge guides will be added when more frames are
	-- integrated into the drag system.
```

With:

```lua
	-- ── Edge alignment with other visible frames ────────────
	local otherBounds = GetOtherFrameBounds(dragFrame)
	local edgeIdx = 0

	-- Edges to check: left, right of dragged frame against left, right of others (vertical guides)
	-- And: top, bottom of dragged frame against top, bottom of others (horizontal guides)
	local dragEdges = {
		{ val = left,   isH = false },  -- drag left edge
		{ val = right,  isH = false },  -- drag right edge
		{ val = top,    isH = true  },  -- drag top edge
		{ val = bottom, isH = true  },  -- drag bottom edge
	}

	for _, de in next, dragEdges do
		for _, ob in next, otherBounds do
			local otherEdges
			if(de.isH) then
				otherEdges = { ob.top, ob.bottom }
			else
				otherEdges = { ob.left, ob.right }
			end

			for _, oe in next, otherEdges do
				if(math.abs(de.val - oe) < SNAP_THRESHOLD) then
					edgeIdx = edgeIdx + 1
					if(edgeIdx > EDGE_GUIDE_POOL_SIZE) then break end

					-- Acquire or create edge guide
					if(not edgeGuides[edgeIdx]) then
						edgeGuides[edgeIdx] = CreateGuide(guideFrame, de.isH)
					end

					local guide = edgeGuides[edgeIdx]
					guide._isHorizontal = de.isH
					guide._targetAlpha = GUIDE_COLOR[4]

					-- Position the guide at the aligned edge
					guide:ClearAllPoints()
					if(de.isH) then
						guide:SetHeight(GUIDE_THICKNESS)
						guide:SetPoint('LEFT', guideFrame, 'LEFT', 0, 0)
						guide:SetPoint('RIGHT', guideFrame, 'RIGHT', 0, 0)
						-- Offset from center: oe is screen Y, center is screenH/2
						local yOff = oe - screenH / 2
						guide:SetPoint('TOP', guideFrame, 'CENTER', 0, yOff)
					else
						guide:SetWidth(GUIDE_THICKNESS)
						guide:SetPoint('TOP', guideFrame, 'TOP', 0, 0)
						guide:SetPoint('BOTTOM', guideFrame, 'BOTTOM', 0, 0)
						-- Offset from center: oe is screen X, center is screenW/2
						local xOff = oe - screenW / 2
						guide:SetPoint('LEFT', guideFrame, 'CENTER', xOff, 0)
					end
				end
			end
			if(edgeIdx > EDGE_GUIDE_POOL_SIZE) then break end
		end
		if(edgeIdx > EDGE_GUIDE_POOL_SIZE) then break end
	end

	-- Fade out unused edge guides
	for i = edgeIdx + 1, #edgeGuides do
		edgeGuides[i]._targetAlpha = 0
	end
```

- [ ] **Step 3: Test in-game**

```
/reload
/framed edit
```
- Drag Player frame near Target frame's left edge → red vertical line appears
- Drag a frame so its top aligns with another frame's bottom → red horizontal line appears
- Move away → guides fade out
- Center guides still work as before

- [ ] **Step 4: Commit**

```bash
git add EditMode/AlignmentGuides.lua
git commit -m "feat: add edge-to-edge alignment guides between frames during drag"
```

---

## Task 18: Auras Tab Implementation

**Purpose:** Replace the "coming soon" placeholder in `InlinePanel.lua`'s Auras tab with a full implementation: aura group dropdown, per-group settings panel loading via the registered panel `create()` functions, and dimming of non-selected aura groups on the live frame.

**Files:**
- Modify: `EditMode/InlinePanel.lua`

- [ ] **Step 1: Add aura group definitions and active group state**

Add after the `local contentFrame = nil` declaration:

```lua
local activeAuraGroup = nil  -- current aura group panel id

--- All aura group panels in display order.
--- These match the panel ids registered in Settings/Panels/*.lua with subSection = 'auras'.
local AURA_GROUPS = {
	{ id = 'buffs',          label = 'Buffs' },
	{ id = 'debuffs',        label = 'Debuffs' },
	{ id = 'externals',      label = 'Externals' },
	{ id = 'raiddebuffs',    label = 'Raid Debuffs' },
	{ id = 'defensives',     label = 'Defensives' },
	{ id = 'targetedspells', label = 'Targeted Spells' },
	{ id = 'dispels',        label = 'Dispels' },
	{ id = 'missingbuffs',   label = 'Missing Buffs' },
	{ id = 'privateauras',   label = 'Private Auras' },
	{ id = 'lossofcontrol',  label = 'Loss of Control' },
	{ id = 'crowdcontrol',   label = 'Crowd Control' },
}

--- Find a registered panel's create function by its id.
--- @param panelId string
--- @return function|nil create
local function GetPanelCreate(panelId)
	for _, p in next, F.Settings._panels do
		if(p.id == panelId) then
			return p.create
		end
	end
	return nil
end
```

- [ ] **Step 2: Add aura dimming helpers**

Add after the aura group definitions:

```lua
--- Dim all aura elements on a frame except the active group.
--- @param frameKey string  The selected frame key
--- @param activeGroup string|nil  The active aura group id, or nil to restore all
local function DimNonActiveAuras(frameKey, activeGroup)
	-- Fire event so aura elements can respond
	F.EventBus:Fire('EDIT_MODE_AURA_DIM', frameKey, activeGroup)
end
```

- [ ] **Step 3: Replace the `ShowAurasTab` placeholder**

Replace the entire `ShowAurasTab` function:

```lua
	local function ShowAurasTab()
		activeTab = 'auras'
		-- Clear content
		for _, child in next, { contentFrame:GetChildren() } do
			child:Hide()
			child:SetParent(nil)
		end

		-- ── Aura group dropdown ─────────────────────────────
		local dropdownItems = {}
		for _, group in next, AURA_GROUPS do
			dropdownItems[#dropdownItems + 1] = { text = group.label, value = group.id }
		end

		local ddLabel = Widgets.CreateFontString(contentFrame, C.Font.sizeSmall, C.Colors.textSecondary)
		ddLabel:SetText('Aura Group:')
		ddLabel:ClearAllPoints()
		Widgets.SetPoint(ddLabel, 'TOPLEFT', contentFrame, 'TOPLEFT', C.Spacing.normal, -C.Spacing.normal)

		local auraDropdown = Widgets.CreateDropdown(contentFrame, PANEL_WIDTH - C.Spacing.normal * 2)
		auraDropdown:SetItems(dropdownItems)
		auraDropdown:ClearAllPoints()
		Widgets.SetPoint(auraDropdown, 'TOPLEFT', ddLabel, 'BOTTOMLEFT', 0, -C.Spacing.small)

		-- ── Aura settings content area ──────────────────────
		local auraContent = CreateFrame('Frame', nil, contentFrame)
		auraContent:ClearAllPoints()
		Widgets.SetPoint(auraContent, 'TOPLEFT', auraDropdown, 'BOTTOMLEFT', 0, -C.Spacing.normal)
		auraContent:SetPoint('BOTTOMRIGHT', contentFrame, 'BOTTOMRIGHT', 0, 0)
		auraContent._explicitWidth = PANEL_WIDTH - C.Spacing.normal * 2
		auraContent._explicitHeight = PANEL_MIN_H - TAB_HEIGHT - 60

		local function LoadAuraGroup(groupId)
			-- Clear previous aura panel
			for _, child in next, { auraContent:GetChildren() } do
				child:Hide()
				child:SetParent(nil)
			end

			activeAuraGroup = groupId

			-- Find the registered panel's create function
			local createFn = GetPanelCreate(groupId)
			if(not createFn) then
				local noPanel = Widgets.CreateFontString(auraContent, C.Font.sizeNormal, C.Colors.textSecondary)
				noPanel:SetPoint('CENTER', auraContent, 'CENTER', 0, 0)
				noPanel:SetText('Panel not available')
				return
			end

			-- Build the aura settings panel inside our content area
			local auraPanel = createFn(auraContent)
			if(auraPanel) then
				auraPanel:ClearAllPoints()
				auraPanel:SetAllPoints(auraContent)
				auraPanel._width = nil
				auraPanel._height = nil
				auraPanel:Show()
			end

			-- Dim non-active aura groups on the live frame
			DimNonActiveAuras(currentKey, groupId)
		end

		auraDropdown:SetOnSelect(function(value)
			LoadAuraGroup(value)
		end)

		-- Default to first group or restore previous selection
		local defaultGroup = activeAuraGroup or AURA_GROUPS[1].id
		auraDropdown:SetValue(defaultGroup)
		LoadAuraGroup(defaultGroup)

		-- Update tab visual
		aurasTabBtn._label:SetTextColor(1, 1, 1, 1)
		frameTabBtn._label:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3], 1)
	end
```

- [ ] **Step 4: Reset aura dimming on tab switch and exit**

In `ShowFrameTab`, add at the top after `activeTab = 'frame'`:

```lua
		-- Restore all aura visibility when switching to frame tab
		DimNonActiveAuras(currentKey, nil)
		activeAuraGroup = nil
```

In the `EDIT_MODE_EXITED` handler, add before `DestroyPanel()`:

```lua
	-- Restore aura visibility
	if(currentKey) then
		DimNonActiveAuras(currentKey, nil)
	end
	activeAuraGroup = nil
```

- [ ] **Step 5: Test in-game**

```
/reload
/framed edit
```
- Click a frame → click Auras tab → dropdown appears with all 11 aura groups
- Select "Debuffs" → debuff settings panel loads, other aura groups dim on the frame
- Switch to "Buffs" → panel rebuilds with buff settings, dimming updates
- Switch back to Frame tab → all aura groups restore to normal visibility
- Exit edit mode → aura visibility restored

- [ ] **Step 6: Commit**

```bash
git add EditMode/InlinePanel.lua
git commit -m "feat: implement auras tab with group dropdown and aura dimming"
```

---

## Summary

| Task | Component | Files | Depends On |
|------|-----------|-------|------------|
| 0 | Base frame audit | Elements/*, Units/* | — |
| 1 | Extract AnimateHeight | Widgets/Frame.lua, Settings/Sidebar.lua | — |
| 2 | MakeDraggable onMove | Widgets/Base.lua | — |
| 3 | 3-button Dialog | Widgets/Dialog.lua | — |
| 4 | InfoIcon widget | Widgets/InfoIcon.lua | — |
| 5 | EditCache | EditMode/EditCache.lua | — |
| 6 | Overlay & Entry/Exit | EditMode/EditMode.lua | 5 |
| 7 | Click Catchers | EditMode/ClickCatchers.lua | 6 |
| 8 | Top Bar | EditMode/TopBar.lua | 6 |
| 9 | Dialogs | EditMode/Dialogs.lua | 3, 5, 6 |
| 10 | Grid | EditMode/Grid.lua | 6 |
| 11 | Alignment Guides (center) | EditMode/AlignmentGuides.lua | 2, 6 |
| 12 | Resize Handles | EditMode/ResizeHandles.lua | 5, 6 |
| 13 | Position & Layout card | Settings/FrameSettingsBuilder.lua | 4 |
| 14 | Inline Panel | EditMode/InlinePanel.lua | 6, 7, 13 |
| 15 | Frame Drag Wiring | EditMode/EditMode.lua | 2, 10, 11 |
| 16 | TOC & Integration | Framed.toc, Init.lua | All except 17, 18 |
| 17 | Edge Alignment Guides | EditMode/AlignmentGuides.lua | 11 |
| 18 | Auras Tab | EditMode/InlinePanel.lua | 14 |

Tasks 0-5 can run in parallel (no dependencies). Tasks 6-12 depend on 5/6. Tasks 13-16 integrate the core. Tasks 17-18 extend completed components.

---

## Implementation Notes

### Frame Cleanup Pattern

Throughout the plan, sub-components (TopBar, ClickCatchers, InlinePanel, etc.) are destroyed and recreated on each edit mode session. The `SetParent(nil)` pattern does not actually destroy frames in WoW — it orphans them. For the initial implementation, this is acceptable since edit mode sessions are infrequent. **If memory profiling shows growth**, refactor to a show/hide pattern where sub-components are created once and reused across sessions.

### ClickCatcher Positioning

ClickCatchers use `SetAllPoints(unitFrame)` but are parented to the overlay at a different strata. If position tracking is unreliable due to different parent hierarchies, switch to an `OnUpdate` script that syncs catcher position to the unit frame's screen coordinates each frame.

### Keyboard Input Propagation

The overlay swallows all keyboard input while active, matching Blizzard's edit mode behavior. If chat typing is needed during edit mode, add selective key propagation later.
