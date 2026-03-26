# Sidebar Rework

## Overview

Rework the settings sidebar to reduce visual clutter: remove the redundant "Frame Presets" section header, remove the "Editing: X Frame Preset" label, and convert the static FRAMES and AURAS sub-headings into collapsible toggle buttons with smooth animation. Also fix the accent color to be read dynamically instead of cached at load time.

**Minimum scope:** Only `Settings/Sidebar.lua` changes (plus two config keys for persisted collapse state). No changes to Framework.lua, MainFrame.lua, or any panel files.

## Goals

- Remove redundant "Frame Presets" section header (keep button + dividers)
- Remove "Editing: X Frame Preset" accent label from sidebar
- Make FRAMES and AURAS sub-headings clickable toggle buttons that collapse/expand their child panels
- Smooth height animation on collapse/expand
- Persist collapsed state across sessions via config
- Fix accent color to be dynamic (read at time of use, not cached at load)

## Non-Goals

- No changes to panel registration or the `RegisterPanel` API
- No changes to Framework.lua section definitions
- No changes to MainFrame.lua or the title header
- No changes to any panel files
- No "Editing: X" label in the header bar (deferred to presets work)

---

## Section 1: Removals

### FRAME_PRESETS Section Header

The `FRAME_PRESETS` section currently renders a section header label ("FRAME PRESETS") followed by a single button also labeled "Frame Presets". Remove the header label rendering for this section. Keep the button and the dividers on both sides.

In the standard section rendering path (`buildSidebarContent`), when the section ID is `'FRAME_PRESETS'` (`sectionId == 'FRAME_PRESETS'`), skip the header `CreateFontString`. Use the section ID, not the label string, for this check — the label is `'FRAME PRESETS'` (with a space) which is fragile. The dividers before and after the section remain.

### "Editing: X Frame Preset" Label

Remove the `editingLabel` font string creation (currently in the `PRESET_SCOPED` section rendering). Remove the portion of the `EDITING_PRESET_CHANGED` listener that updates `editingLabel`. Keep the portion that updates `groupFrameBtn` label and visibility.

---

## Section 2: Collapsible Section Headers

### Button Replacement

Replace the static FRAMES and AURAS `CreateFontString` sub-headings with `Button` frames. Each button contains:

- **Arrow indicator** — a `FontString` showing ▶ (collapsed) or ▼ (expanded), positioned at the left edge
- **Section label** — uppercase text ("FRAMES" / "AURAS"), positioned after the arrow

The arrow uses the accent color when expanded and secondary text color when collapsed. The label always uses secondary text color.

### Child Container

Each section's child panel buttons are parented to a container `Frame` with `SetClipsChildren(true)`. The container is anchored to the section header button's bottom edge.

- **Expanded:** container height = sum of visible child button heights + gaps (via `recalcContainerHeight`)
- **Collapsed:** container height = 0 (children clipped)

Child buttons are created inside their container with fixed yOffsets relative to the container top (not the sidebar). Their positions don't change — only the container height changes.

### Anchor Chain

Elements below a collapsible container (the AURAS section header, BOTTOM divider, etc.) must anchor to the **bottom edge** of the previous container rather than using absolute yOffsets from the sidebar top. This way, when a container's height animates, everything below it moves automatically without manual repositioning.

Specifically: the AURAS section header anchors to the bottom of the FRAMES container. The BOTTOM divider anchors to the bottom of the AURAS container. This chain ensures smooth movement during animation.

### Toggle Behavior

Clicking the section header button:

1. Flips the collapsed state
2. Updates the arrow indicator (▶ ↔ ▼) and arrow color
3. Animates the container height from current → target, and the window height in parallel (see Section 3)
4. Persists the new state to config

### Active Panel in Collapsed Section

Collapsing a section is purely visual — the active panel remains selected even though its sidebar button is hidden. The right-hand content stays stable. There is no auto-selection of a different panel when a section is collapsed.

### Dynamic Group Frame Button

The `groupFrameBtn` (party/raid) is dynamically shown/hidden by `EDITING_PRESET_CHANGED`. When it is hidden or shown, the FRAMES container's natural height changes. The `EDITING_PRESET_CHANGED` listener must recalculate the FRAMES container height (skipping hidden children) and update the container + window height accordingly (animated if the section is expanded, instant if collapsed).

A `recalcContainerHeight(container, children)` helper computes the sum of heights + gaps for visible (`:IsShown()`) children only. This helper is used by both the toggle animation and the preset-changed listener.

### Default State

Both sections start **expanded** (collapsed = false). The persisted config overrides this on subsequent opens.

---

## Section 3: Animation

### Height Animation

A new `AnimateHeight` function (mirroring the existing `AnimateWidth`):

```lua
local function AnimateHeight(frame, targetHeight, duration, onDone)
```

Uses the same OnUpdate linear interpolation pattern as `AnimateWidth`. Interpolates from current height to target height over `duration` seconds. Calls `onDone` when complete.

Duration: use `C.Animation.durationNormal` for the collapse/expand transition.

### Parallel Window Resize

The window height animates **in parallel** with the container height — not after. This prevents a visual jump where the container shrinks smoothly but the window snaps at the end (or vice versa).

On toggle, fire two `AnimateHeight` calls with the same duration:
1. Container: current height → target height (0 or full)
2. Window: current height → new height (computed from the delta)

Both interpolate together, so the sidebar content and window edge move in sync. After both complete, update `Settings._contentParent` dimensions.

Apply the same min/max clamping (`WINDOW_MIN_H` / `WINDOW_MAX_H`) as `BuildSidebar` currently does.

---

## Section 4: Persisted State

Two config keys:

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `sidebar.framesCollapsed` | boolean | `false` | FRAMES section collapsed |
| `sidebar.aurasCollapsed` | boolean | `false` | AURAS section collapsed |

Read during `buildSidebarContent` to set initial container heights (0 if collapsed, full if expanded). Write on each toggle via `F.Config:Set()`.

`F.Config:Get()` returns `nil` for unset keys. The code treats `nil` as `false` (expanded), so no default registration or migration is needed.

---

## Section 5: Dynamic Accent Color

### Problem

The current sidebar caches accent color at file load time:

```lua
local ACCENT_R, ACCENT_G, ACCENT_B = C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3]
```

If the user changes their accent color in Appearance settings, the sidebar gradient, hover highlight, and selection highlight continue using the old color.

### Fix

Remove the cached `ACCENT_R/G/B` locals. Instead, read `C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3]` at the point of use:

- `setSidebarSelected` — gradient highlight `SetVertexColor`
- `createNavButton` — gradient highlight initial color, hover `OnEnter` icon color
- Section header arrow color when expanded

This ensures the sidebar always reflects the current accent color. The dim/hover colors (`DIM_ICON_*`, `DIM_TEXT_*`, `HOVER_*`) are neutral grays and whites — they stay cached.

---

## Section 6: File Changes

- **Modified:** `Settings/Sidebar.lua` — all changes described above
- **No other files modified**
