# Edit Mode Rewrite Design Spec

## Overview

Rewrite Framed's edit mode from a simple drag-handle system into a full inline editing experience with live preview, inline settings panels, grid/alignment system, and confirmation dialogs. The edit mode becomes the primary way users configure frame positions and settings visually.

## Goals

- Replace the current handle-based drag system with a rich overlay that shows all preset frames
- Provide inline settings editing identical to sidebar panels, with live preview
- Add position/anchor controls (X/Y, anchor picker, pixel nudge) to both edit mode and sidebar
- Add text anchor pickers for name, health, and power text positioning
- Implement grid snap with visible grid (lines or dots) and Blizzard-style alignment guides
- Provide clear Save/Cancel/Preset-swap workflows with confirmation dialogs
- Keep memory usage constant regardless of how many frames are edited (panel recycling)

## Architecture: Overlay Approach

A single full-screen overlay frame (`FULLSCREEN_DIALOG` strata) owns everything: border, dimming, grid, alignment guides, click catchers, and the recycled settings panel. This gives clean lifecycle management — show/hide one parent controls the entire edit mode.

### Why Overlay (not Decorated Frames)

- Single parent = clean lifecycle. Hide overlay = full cleanup, no stale textures or leaked handlers.
- Natural z-ordering — overlay above game world, settings panel above overlay, dialogs above all.
- Simple memory management — one overlay + one settings panel + lightweight click catchers.
- `FULLSCREEN_DIALOG` strata ensures all other UI (including other addons) renders behind.

---

## Section 1: Edit Mode Entry & Overlay

### Activation

- `/framed edit` or settings button (same triggers as current)
- Sidebar closes, overlay fades in
- Defaults to whichever preset is currently selected in sidebar settings

### Session Preset Auto-Detection

- On first addon load, auto-detect current content mode (solo, party, raid, etc.) and select that preset
- Once the user manually switches presets in sidebar, that choice persists for the session (`sessionPresetOverride`)
- `sessionPresetOverride` is nil on load (auto-detect), set on manual switch, never persisted to saved config
- Relog resets to auto-detect

### Overlay Composition (single parent frame)

- **Strata:** `FULLSCREEN_DIALOG` — above all other addon frames and Blizzard UI
- **Red border:** 1px red border around all screen edges, fades in on entry
- **Dark fill:** 85% opacity dark overlay covering the entire screen
- **Grid:** Rendered on overlay behind frames (see Section 3)
- **Preset frames:** All unit frames for the current preset rendered above the overlay, dimmed to dark accent color with "Click to edit" text centered on each

### Top Bar

Centered at top of screen with horizontal padding (not full-width), matching existing edit mode bar style.

Contents (left to right):
1. **Preset dropdown** — selects which preset to edit
2. **"Editing: [Preset Name]"** — green accent text showing current preset
3. **Grid Snap toggle** — enables/disables snap behavior
4. **Grid Style selector** (Lines / Dots) — only relevant when snap enabled, defaults to Lines
5. **Save button**
6. **Cancel button**

### Exit Transitions

- **Save:** Border flashes green, then overlay fades out
- **Discard:** Overlay fades out directly (no green flash)

### Combat Protection

On `PLAYER_REGEN_DISABLED` (entering combat):
1. If a frame drag is in progress, stop it immediately and snapshot the current position to edit cache
2. Hide the overlay (edit cache and all state preserved in memory)
3. Protected frames cannot be moved via `SetPoint` during combat lockdown

On `PLAYER_REGEN_ENABLED` (leaving combat):
1. Re-show overlay with full state restored
2. Edit cache intact, resume editing where you left off

---

## Section 2: Frame Selection & Settings Panel

### Clicking a Frame

1. "Click to edit" text disappears on the selected frame
2. Frame animates from dimmed to full live preview (smooth opacity transition)
3. All enabled elements render on the selected frame — status icons, name text, health text, power text, aura icons, etc.
4. Other frames stay dimmed with "Click to edit"
5. Settings panel slides in from the smart side (default right of frame, flips left/up/down at screen edges)

### Live Preview Behavior

- All toggle changes take immediate visual effect on the frame
- Disable health text = it vanishes instantly; enable debuffs = they appear
- Same for status icons, power bar, any element or aura group
- All changes go to the edit cache, not saved config — committed only on Save exit

### Settings Panel (Single Recycled Instance)

Only one settings panel exists in memory at any time. Rebuilt from config + edit cache on each frame switch.

**Tab layout at top of panel:**

**Tab 1: [Frame Name]** (e.g., "Player")
- Full frame settings, built via `F.FrameSettingsBuilder.Create(parent, unitType)` where `unitType` is derived from the selected frame's `FRAME_KEYS` entry (e.g., `'player'`, `'target'`, `'party'`)
- Plus a new **Position & Layout** card containing:
  - **Growth Direction** selector (existing)
  - **Frame Anchor Point** picker (3x3 grid, using existing `Widgets.CreateAnchorPicker`) — placed next to Growth Direction to show their relationship
  - **Position X / Y** input fields
  - **Pixel nudge arrows** (up/down/left/right buttons for 1px adjustments)
  - `(i)` info icon on card header with hover callout explaining what anchor point + growth direction do together

**Tab 2: Auras** (dropdown)
- Dropdown to select aura group: Buffs, Debuffs, Externals, Raid Debuffs, Defensives, Targeted Spells, Dispels, Missing Buffs, Private Auras, Loss of Control, Crowd Control
- Selecting a group **dims other aura groups** on the frame (frame itself stays fully live)
- Shows that aura group's full settings panel
- Same recycling pattern — only one aura group's settings built at a time

### Text Anchor Pickers

Name, health, and power text each get an anchor picker (3x3 grid) in their respective settings cards, controlling where the text is positioned relative to the frame (TOPLEFT, CENTER, BOTTOMRIGHT, etc.). Shown in both edit mode panel and sidebar settings.

### Frame-to-Frame Switching

1. Panel animates out from current frame
2. Dirty values flushed to edit cache, panel widgets released
3. Panel rebuilds for new frame from config + cached edits
4. Panel animates in on the new frame
5. No save prompt — changes are cached, not committed

### Group Frame Behavior

Group frame types (party, raid, arena, boss) share a single config scope. Clicking any child frame of a group header opens the shared group settings panel (e.g., clicking any party member opens "Party Frames" settings). Click catchers cover each visible child frame individually, but all route to the same group-level panel and config key.

### Resize Handles

- Visible on selected frame edges and corners for single-unit frames only
- Group frame headers (party, raid) are repositioned via drag but not directly resizable — their size is controlled by per-unit dimensions in the settings panel
- Tooltip on hover: "Drag to resize"
- Width/height fields in settings panel update live during drag
- Respects grid snap when enabled
- All changes go to edit cache

---

## Section 3: Grid, Snapping & Alignment

### Grid System

- Grid rendered on the overlay behind frames
- **Grid Snap toggle** in top bar enables/disables snap behavior
- **Grid Style selector** (Lines / Dots) — defaults to Lines for performance
- Grid only visible when snap is enabled
- Grid spacing is `C.Spacing.base` (4px)

### Grid Rendering

- **Lines mode** (default): Tiling line textures across the overlay — cheap to render, clear visual reference
- **Dots mode**: Small dot textures at grid intersections — heavier, optional alternative

### Alignment Guides

Consistent with Blizzard's edit mode behavior:

- **Red animated lines** that appear **only while dragging** a frame
- **Center alignment:** Horizontal and vertical center lines when frame center approaches screen center
- **Edge alignment:** Lines when a dragged frame's edge aligns with another frame's edge
- **Fade in** on proximity, **fade out** when dragging further away or on release
- All guides (center + edge) use the same red animated style

### Snap Behavior

- When snap enabled, frames land on grid increments on drag release
- **Pixel nudge arrows ignore snap** — always move by exact pixels for fine-tuning
- Resize via drag handles also respects snap when enabled

---

## Section 4: Confirmation Dialogs & Exit

### Dialog Widget Extension

The existing `Widgets.Dialog` supports 2-button (Yes/No) and 1-button (OK) layouts. This design requires a new **3-button layout** mode. Add a `ShowThreeButtonDialog(title, message, btn1Label, btn2Label, btn3Label, onBtn1, onBtn2, onBtn3)` API or extend the existing pattern. Three buttons at `BUTTON_WIDTH = 90` with `BUTTON_GAP = 8` total 286px — increase `DIALOG_WIDTH` from 350 to ~420 to accommodate comfortably. Horizontal layout, same centering pattern as existing 2-button mode.

**Escape key behavior:** When a dialog is visible, it captures Escape exclusively — the dialog dismisses but Escape does not propagate to the overlay's Cancel handler underneath. The existing Dialog.lua already operates at `FULLSCREEN_DIALOG` strata which should naturally consume Escape first, but this must be verified during implementation.

### Save Dialog (3 buttons)

Triggered when user clicks Save in top bar.

| Button | Action |
|--------|--------|
| **Save Changes and Exit** | Commit edit cache to saved config, green border flash, close edit mode + settings entirely |
| **Save Changes + Return to Menu** | Commit edit cache, green border flash, transition back to sidebar settings |
| **Continue Editing** | Dismiss dialog, stay in edit mode |

### Cancel Dialog (3 buttons)

Triggered when user clicks Cancel in top bar or presses Escape.

| Button | Action |
|--------|--------|
| **Discard and Exit** | Clear edit cache, revert frames to pre-edit positions, close edit mode + settings |
| **Discard + Return to Menu** | Clear edit cache, revert frames, transition back to sidebar |
| **Continue Editing** | Dismiss dialog, stay in edit mode |

### Preset Swap Dialog (3 buttons)

Triggered when user changes the preset dropdown while having unsaved edits.

| Button | Action |
|--------|--------|
| **Save Changes and Switch** | Commit current preset's edit cache, switch to new preset, load fresh |
| **Discard and Switch** | Clear current preset's edit cache (no save), switch to new preset fresh |
| **Continue Editing** | Dismiss dialog, stay on current preset (dropdown reverts) |

### Border Transitions

- **Entry:** Red 1px border fades in
- **Save exit:** Border transitions from red to green flash, then fades out
- **Discard exit:** Red border fades out directly

### Combat Interruption

- Combat starts → overlay auto-hides, state preserved
- Combat ends → overlay re-shows, edit cache intact, resume editing

---

## Section 5: Memory & Performance

### Single Panel Recycling

- Only **one settings panel instance** exists at any time
- On frame switch: flush dirty values (unsaved field changes) to edit cache, release/recycle panel widgets, rebuild for new frame
- Same pattern for aura sub-panels — only the active aura group's settings are built
- This keeps UI memory O(1) regardless of how many frames are clicked through

### Edit Cache

- Lightweight flat table per touched frame: `{ ["health.height"] = 32, ["position.x"] = 120 }`
- O(1) for UI memory (one panel), O(n) only for small key/value diffs per touched frame
- **On Save:** Walk cache, commit all entries to real config (`F.Config:Set`), clear cache
- **On Discard:** Clear cache, revert frame positions to pre-edit-mode snapshot
- **On Preset Swap:** Auto-save (commit + clear) before loading new preset — never hold edits for multiple presets

### Edit Cache Read Strategy

When rebuilding the settings panel for a frame, the panel needs to read values that may have been edited but not yet saved. The approach:

- **Shadow config wrapper:** `EditCache.Get(configKey)` checks the edit cache first; if the key exists, return the cached value. Otherwise, fall back to `F.Config:Get(configKey)`.
- **Panel widget `onChange` handlers** write to the edit cache via `EditCache.Set(configKey, value)` instead of `F.Config:Set()`.
- `FrameSettingsBuilder` widgets are wired to use the shadow accessor during edit mode. When edit mode is inactive, they use `F.Config` directly as normal.
- This avoids polluting the real config with uncommitted values and keeps the boundary clean.

### Overlay Lifecycle

- Single parent frame at `FULLSCREEN_DIALOG` strata
- All children (border, dim fill, grid, click catchers, settings panel, resize handles) parented to overlay
- Show overlay = everything appears; hide overlay = full cleanup
- No stale textures or leaked event handlers possible

### Grid Rendering Performance

- Lines mode: Tiling line textures (fewer draw calls, default choice)
- Dots mode: Repeated small textures (heavier, user opt-in)
- Grid only rendered when snap is enabled — no cost when off

### Session Preset Flag

- `sessionPresetOverride` — nil on addon load (auto-detect content mode), set on manual switch
- Never persisted to saved config — resets each session

---

## Existing Code Reuse

### Keep / Evolve

| Component | Current Location | Reuse Strategy |
|-----------|-----------------|----------------|
| `FRAME_KEYS` definitions | `EditMode/EditMode.lua:37-47` | Keep as canonical frame registry, extend with unit element visibility |
| `SnapToGrid()` | `EditMode/EditMode.lua:53-57` | Keep, parameterize grid size |
| `SaveCurrentPositions()` / `RestorePositions()` | `EditMode/EditMode.lua:63-87` | Keep for pre-edit snapshot and discard restore |
| `PersistPositions()` | `EditMode/EditMode.lua:89-103` | Evolve to flush from edit cache instead of reading live frame positions |
| `Widgets.CreateAnchorPicker()` | `Widgets/AnchorPicker.lua` | Reuse directly for frame anchor and text anchor pickers |
| `Widgets.ShowConfirmDialog()` | `Widgets/Dialog.lua` | Extend with 3-button layout for Save/Cancel dialogs |
| `Widgets.MakeDraggable()` | `Widgets/Base.lua` | Keep for frame dragging; extend with `onMove` callback (called on each `OnUpdate` during drag) for alignment guide updates — current API only has `onDragStart`/`onDragStop` |
| `Widgets.FadeIn/FadeOut` | `Widgets/Base.lua` | Keep for all transitions |
| `AnimateHeight` | `Settings/Sidebar.lua:59-82` | Extract from `local` function to `Widgets.AnimateHeight` for reuse in panel slide animations |
| Frame settings builders | `Settings/Panels/*.lua` | Reuse `create()` functions directly for inline panel content |

### Replace

| Component | Reason |
|-----------|--------|
| Handle system (`CreateHandleForFrame`, `CreateHandles`, `DestroyHandles`) | Replaced by click catchers + inline settings |
| Simple overlay (invisible, keyboard-only) | Replaced by visible overlay with border, dim, grid |
| Top bar (title + 3 buttons) | Replaced by extended top bar with preset dropdown, grid controls |

---

## Info Icon Widget

A small `(i)` icon added to settings card headers that shows a tooltip/callout on hover. Explains what the card's group of settings does. Used on cards like "Position & Layout" to explain anchor point + growth direction relationship.

- Icon: Small circle with "i", using `C.Colors.textSecondary`
- Hover: Shows `GameTooltip` or custom callout with explanation text
- Positioned at the right edge of the card header
- Used across both edit mode inline panel and sidebar settings panels

---

## File Structure (Estimated)

```
EditMode/
  EditMode.lua         -- Rewrite: overlay, entry/exit, state management, combat protection
  EditCache.lua        -- New: edit cache (dirty tracking, flush, commit, discard)
  Grid.lua             -- New: grid rendering (lines/dots), snap logic
  AlignmentGuides.lua  -- New: proximity-based red alignment lines
  ClickCatchers.lua    -- New: transparent frames over unit frames for click detection
  SettingsPanel.lua    -- New: recycled inline settings panel, tab system, smart positioning
  ResizeHandles.lua    -- New: edge/corner drag handles with tooltip
  Dialogs.lua          -- New: edit mode specific dialog flows (save/cancel/swap)
  TopBar.lua           -- New: preset dropdown, editing label, grid controls, save/cancel

Widgets/
  Dialog.lua           -- Extend: add 3-button layout support
  AnchorPicker.lua     -- Existing: reuse as-is
  InfoIcon.lua         -- New: (i) hover tooltip widget for settings cards

Settings/
  FrameSettingsBuilder.lua  -- Modify: add Position & Layout card with anchor picker + nudge arrows
  Sidebar.lua               -- No changes (edit mode is separate from sidebar)
```

---

## Open Questions (Resolved)

All design questions were resolved during brainstorming:

1. **Panel positioning** → Smart side: default right, flip at screen edges
2. **Frame switching** → Animate out/in, no save prompt (cached)
3. **Grid visibility** → Visible when snap enabled, lines by default
4. **Alignment guides** → Blizzard-style, only while dragging, fade in/out on proximity
5. **Preset swap** → 3-button confirmation dialog (Save and Switch / Discard and Switch / Continue Editing)
6. **Memory management** → Single recycled panel, lightweight edit cache per frame
7. **Resize** → Drag handles on edges/corners with live-updating width/height fields
8. **Text positioning** → Anchor picker (3x3) for name/health/power text in both views
