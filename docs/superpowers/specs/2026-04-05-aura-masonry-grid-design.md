# Aura Settings Masonry Grid — Design Spec

**Date:** 2026-04-05
**Goal:** Replace the vertical scroll-based aura settings panels with a responsive masonry card grid layout, matching the UX established by the unit frame settings pages. Add a mini live preview to the sub-header for visual feedback while editing.

---

## Architecture

Four components with clear boundaries:

### 1. Pinned Row (Buffs/Debuffs only)

A flex container sitting **above** the CardGrid, not part of the masonry. Holds two cards in a 1/3 + 2/3 ratio:

- **Create Card** (flex:1) — Type dropdown, type description, display type toggle (Icon/Icons only), name input, create button
- **Indicator List Card** (flex:2) — All indicators as rows with enable/disable checkbox, name, type label, edit button, delete button. No internal scroll — the list is always fully visible.

The pinned row is always side by side. The minimum window width (700px) guarantees at least 2 columns of content area (518px), so the flex layout never needs to stack.

Simpler aura pages (Dispellable, Externals, etc.) skip the pinned row entirely.

### 2. Settings CardGrid

Standard `CardGrid` widget below the pinned row (or directly below the sub-header for simpler pages). Inherits all existing CardGrid behavior:

- `CARD_MIN_W = 240`, `CARD_GAP = 12`, `CARD_V_GAP = 12`
- `calcColumnLayout()` responsive column calculation
- Lazy loading with `LAZY_BUFFER = 400px`
- Staggered entrance animation on first load
- `AnimatedReflow` when card content changes height (e.g., selecting a dropdown reveals additional options)
- Card titles via `addCardTitle()`

### 3. Sub-header Preview

A mini inline preview frame (~140px wide) in the existing title card, right-aligned next to "Editing: Preset".

- Built using `PreviewIndicators` renderers
- Shows health bar, power bar, name text, and all enabled aura indicators from the current unit type's config
- Includes animation loops (depletion bars, cooldown swipes, alpha fades) matching edit mode preview behavior
- Eye icon toggle: switches between indicator-level dimming and show-all mode
- Respects filtering config (castBy, hideUnimportantBuffs, onlyDispellableByMe, visibilityMode) via appropriate fake data selection

**New file:** `Settings/Builders/AuraPreview.lua`

### 4. Card Builders

Extracted from `IndicatorCRUD.lua` and `IndicatorPanels.lua`. Each existing settings group becomes a standalone builder function compatible with `CardGrid:AddCard(id, title, builder)`.

Card builders receive `get(key)` and `set(key, value)` closures as parameters — they never import Config directly or construct their own config paths. This preserves preset + unit type scoping.

---

## Panel Layouts

### Buffs/Debuffs Pages

Top to bottom:
1. **Sub-header** — "Buffs" label left, "Editing: Preset" + mini preview right. Breadcrumb updates to "Buffs › Indicator Name" when editing.
2. **Unit type dropdown row** — existing `BuildAuraUnitTypeRow()`, unchanged
3. **Pinned row** — Create card (flex:1) + Indicator List card (flex:2)
4. **CardGrid** — settings cards appear when an indicator is selected for editing

### Simpler Aura Pages

(Dispellable, Externals, Defensives, Raid Debuffs, Missing Buffs, Private Auras, Targeted Spells, Loss of Control, Crowd Control)

Top to bottom:
1. **Sub-header** — page label + mini preview
2. **Unit type dropdown row**
3. **CardGrid** — Overview card (enable/disable toggle + description) as the first card, followed by settings cards

---

## Card Builder Library

Card builders map directly to the existing groupings in `IndicatorPanels.lua`. No restructuring — same content, same groupings, different container.

### Shared card builders (already exist as reusable functions)

- **Layout/Position** — anchor picker, frame level, X/Y offsets. For multi-types (Icons, Bars): grow direction, max displayed, num per line, spacing X/Y.
- **Threshold Colors** — base color + low time threshold + low seconds threshold + optional border/background colors. Uses `BuildThresholdColorCard()`.
- **Font** — size, outline, shadow. Uses `BuildFontCard()`. Reused for both duration and stack font.
- **Glow** — type, color, frequency. Uses `BuildGlowCard()`.

### Type-specific card builders (extracted from BuildIndicatorSettings)

- **Cast By** — dropdown (me/others/anyone). Used by: Icon, Icons, Bar, Bars.
- **Tracked Spells** — spell list (all entries visible, card grows), add input, import button, delete all button. Optional per-spell color pickers for colored square / bar types. Used by: Icon, Icons, Bar, Bars.
- **Appearance** — display type switch (spell icons / color squares) + width/height sliders. Used by: Icon, Icons.
- **Cooldown & Duration** — cooldown toggle, duration mode dropdown, duration font settings (anchor, size, outline, shadow, color progression). Used by: Icon, Icons.
- **Stacks** — show toggle + stack font settings (anchor, size, outline, shadow). Used by: Icon, Icons, Bar, Bars, Rectangle.
- **Size** — width/height sliders + bar orientation dropdown. Used by: Bar, Bars, Rectangle.
- **Mode** — overlay mode dropdown + color picker + animation settings (smooth toggle, bar orientation). Used by: Overlay.
- **Border** — thickness, color mode, source colors. Used by: Border.

---

## Card Lifecycle & Dynamic Spawning

### Editing an indicator

1. User clicks Edit on an indicator in the List card
2. List card highlights the row, swaps Edit → Close
3. Panel determines which card builders apply for this indicator type
4. Each card builder is added to the CardGrid via `AddCard(id, title, builder)`
5. CardGrid lazy-builds and animates them in (staggered entrance)
6. Sub-header breadcrumb updates to "Buffs › Indicator Name"
7. Preview dims non-active aura groups, highlights the active indicator

### Switching to a different indicator

1. All current settings cards are removed from the CardGrid
2. New cards for the selected indicator are added
3. Grid animates the transition
4. Breadcrumb and preview update

### Closing

1. User clicks Close on the active indicator
2. All settings cards removed from CardGrid
3. Breadcrumb reverts to page name only
4. Preview returns to page-level dimming (or show-all if eye toggle is on)

### Creating a new indicator

1. User fills in Create card, clicks Create
2. `setIndicator(name, newConfig)` fires `CONFIG_CHANGED`
3. Indicator List card rebuilds to show the new entry
4. Auto-open the new indicator for editing (spawn its settings cards immediately)

### Deleting an indicator

1. If deleted indicator was being edited, destroy its settings cards first
2. Remove from config via `setIndicator(name, nil)`
3. List card rebuilds
4. Preview re-renders without the deleted indicator

### Enabling/disabling an indicator

1. Checkbox calls `setIndicator(name, data)` with updated `enabled` flag
2. `CONFIG_CHANGED` fires — live frames update immediately
3. List card updates row visual (enabled = full brightness, disabled = dimmed)
4. Preview re-renders — disabled indicators disappear completely (mirrors live frame behavior)
5. If the toggled indicator is currently being edited, its settings cards stay open

### Unit type change

1. Destroy everything — pinned row content, all grid cards, preview
2. Rebuild from scratch with new unit type's config
3. Same as today's full panel rebuild via `SetActivePanel()`

### Preset change

1. `EDITING_PRESET_CHANGED` fires
2. Panel frame is nilled in `_panelFrames` (existing behavior)
3. Next `SetActivePanel()` rebuilds everything fresh

---

## Preview Behavior

### Dimming

- **Page-level:** On Buffs page, all non-buff aura groups dimmed to 0.2 alpha. On Debuffs page, all non-debuff groups dimmed. Etc.
- **Indicator-level:** When editing "My Buffs", only that indicator's icons are at full brightness. Other buff indicators and all other aura groups are dimmed.
- **Show-all mode:** Eye toggle sets all groups to 1.0 alpha.
- **Disabled indicators:** Not rendered on the preview at all (matches live frame behavior).

### Filtering

Preview respects the same filtering the live frames use:
- `castBy` filter — fake data reflects player/others/anyone filtering
- `hideUnimportantBuffs` — reduces visible buff count on party/raid
- `onlyDispellableByMe` — only shows your class's dispellable types
- `visibilityMode` on Externals/Defensives — respects all/player/others

### Data source

Settings preview reads from `Config.Get()` (live SavedVariables), NOT `EditCache`. The edit mode preview and settings preview are completely independent — settings preview shows live state, edit mode preview shows staged state. They never cross-read.

### Performance lifecycle

- **Created** when an aura panel is opened (in `SetActivePanel()`, checking `info.subSection == 'auras'`)
- **Animation loops start** on creation (depletion bars, cooldown swipes — same as edit mode)
- **Re-renders** on `CONFIG_CHANGED` (destroy old frames/loops, create new ones)
- **Destroyed** when navigating away from aura panels or closing settings
- **Zero footprint** when settings are closed — no lingering frames, textures, or OnUpdate callbacks

---

## New Config Key

### `dispellable.highlightAlpha`

- **Default:** `0.8` in `Presets/Defaults.lua`
- **Purpose:** Configurable alpha for the dispellable highlight gradient overlay (currently hardcoded as `OVERLAY_ALPHA = 0.8` in `Elements/Auras/Dispellable.lua`)
- **UI:** Alpha slider (0–100%) on the Dispellable settings page highlight card
- **Element change:** `Dispellable.lua` reads from config instead of the constant
- **Backfill:** `EnsureDefaults()` via `DeepMerge` handles existing profiles — no migration needed

---

## Hard Constraints

### Do not touch

- `Config.lua`, `EditCache.lua` — config read/write layer
- `EventBus` event contracts — `CONFIG_CHANGED`, `EDIT_CACHE_VALUE_CHANGED`, `EDITING_PRESET_CHANGED`
- `setIndicator()` / `getIndicator()` closures — capture preset + unit type in scope
- All Element files (`Elements/Auras/*`, `Elements/Indicators/*`, `Elements/Status/*`) — except `Dispellable.lua` for the alpha config
- All Preview files (`Preview/*`) — edit mode preview is independent
- `StyleBuilder.lua`, `LiveUpdate.lua` — config → frame visual pipeline
- Sidebar navigation and panel registration system

### Callback identity rule

Card builders receive `get(key)` and `set(key, value)` closures as parameters. They never import Config directly or construct their own config paths. This preserves preset + unit type scoping.

### Event listener cleanup

Every `CONFIG_CHANGED` listener registered by a panel or the preview must be unregistered when the panel is destroyed (page switch, unit type change, settings close). Follow the same cleanup pattern the current panels use.

### Import popup

Stays as a singleton modal overlay. Triggered from within the Tracked Spells card builder, calls back through `setIndicator()` unchanged.

### SavedVariables integrity

The only new config key is `dispellable.highlightAlpha`. No existing keys are renamed, restructured, or removed. `EnsureDefaults()` via `DeepMerge` backfills to existing profiles.

### TOC file

`Settings/Builders/AuraPreview.lua` is the only new file. Added to `Framed.toc` after `Settings/Builders/SharedCards.lua`, before panel files. No other TOC changes.

### Widget API surface

Card builders use only existing widget constructors (`CreateDropdown`, `CreateSlider`, `CreateCheckButton`, `CreateSpellList`, `CreateSpellInput`, `CreateAnchorPicker`, `CreateColorPicker`, `CreateButton`, `CreateSwitch`, `CreateFontString`). The preview widget uses existing `PreviewIndicators` builders. No new widget types. No new dependencies.

### Edit mode interaction

If the user opens settings while in edit mode, the settings preview reads from `Config.Get()` (live SavedVariables), not `EditCache`. The two preview systems are completely independent.

---

## Files Modified

| File | Change |
|------|--------|
| `Settings/Panels/Buffs.lua` | Rewrite layout: pinned row + CardGrid |
| `Settings/Panels/Debuffs.lua` | Same as Buffs |
| `Settings/Panels/Dispellable.lua` | Swap to CardGrid, add highlightAlpha slider |
| `Settings/Panels/Externals.lua` | Swap to CardGrid |
| `Settings/Panels/Defensives.lua` | Swap to CardGrid |
| `Settings/Panels/RaidDebuffs.lua` | Swap to CardGrid |
| `Settings/Panels/MissingBuffs.lua` | Swap to CardGrid |
| `Settings/Panels/PrivateAuras.lua` | Swap to CardGrid |
| `Settings/Panels/TargetedSpells.lua` | Swap to CardGrid |
| `Settings/Panels/LossOfControl.lua` | Swap to CardGrid |
| `Settings/Panels/CrowdControl.lua` | Swap to CardGrid |
| `Settings/Builders/IndicatorCRUD.lua` | Extract Create and List into card builders |
| `Settings/Builders/IndicatorPanels.lua` | Extract per-type settings into card builders |
| `Settings/Framework.lua` | Add preview show/hide logic in `SetActivePanel()` |
| `Settings/MainFrame.lua` | Add preview anchor point in title card |
| `Presets/Defaults.lua` | Add `dispellable.highlightAlpha` default (0.8) |
| `Elements/Auras/Dispellable.lua` | Read `highlightAlpha` from config instead of constant |

## New Files

| File | Purpose |
|------|---------|
| `Settings/Builders/AuraPreview.lua` | Mini preview widget builder for sub-header |

## Files NOT Modified

| File | Reason |
|------|--------|
| `Widgets/CardGrid.lua` | No changes needed — no column span, no new features |
| `Core/*` | No changes to config, events, constants, or secret values |
| `Elements/*` (except Dispellable) | Live frame elements untouched |
| `Preview/*` | Edit mode preview is independent |
| `StyleBuilder.lua`, `LiveUpdate.lua` | Config → frame pipeline untouched |
