# Frame Preview Card — Design Spec

**Date:** 2026-04-16
**Scope:** Add a live preview card to every Frame settings page (Player, Target, ToT, Focus, Pet, Boss, Party, Raid) that renders the frame with all its configured elements at real pixel size. Includes migrating Frame pages off CardGrid to the Phase 4 wrapper-grid pinned-row layout established in the aura panel layout refactor.

---

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Placement | Frame pages only (Option A) | Aura Preview stays untouched on aura pages. Two independent previews, zero overlap. |
| Group roster count | Full for party/arena/boss; user-controlled stepper for raid | Party (5), arena (3), boss (4) are small enough to always show full. Raid (1–40) needs flexibility. |
| Scaling | Real pixels 1:1, scroll on overflow | Honest representation. Raid stepper lets users avoid overflow by reducing count. |
| Layout | `Preview (natural width) \| PositionAndLayout (1fr)` pinned row | PositionAndLayout has the tightest feedback loop — width/height/orientation/spacing sliders directly drive preview changes. Position controls (x/y/anchor) greyed out with subtle Edit Mode link. |
| Reflow | Both cards animate smoothly on orientation/size changes | No snap-in. `Widgets.StartAnimation` for all discrete layout changes. Continuous slider drags update per-tick. |
| Architecture | Approach A — thin Settings wrapper, reuse `PreviewFrame.Create` | Maximum reuse, minimum blast radius. Edit Mode untouched. |
| Preset | Reads editing preset, not active preset | Mirrors AuraPreview. Auto-switch-on-context-entry means editing preset almost always matches intent. |
| Aura rendering | Excluded | Frame chrome only. Auras are covered by Aura Preview on separate pages. |
| Solo fake health | ~0.85 | Health loss color passively visible without special animation. |
| Focus mode toggle | Click-to-focus with first-card auto-select on OFF | Parallels aura "Show All Enabled Auras" toggle, adapted for frame card structure. |

---

## Architecture

### File structure

**New file:** `Settings/Builders/FramePreview.lua` (~250–300 lines)

**Reused as-is:**
- `Preview/PreviewFrame.lua` — `PreviewFrame.Create()`, `PreviewFrame.UpdateFromConfig()`, all element builders
- `Preview/Preview.lua` — `FAKE_UNITS` table for group-slot names/classes

**One non-breaking tweak to `Preview/PreviewFrame.lua`:**
1. Wrap `F.PreviewAuras.BuildAll(...)` in `if(auraConfig) then ... end` (line 450) so Settings can pass `nil` without triggering aura rendering. Edit Mode always passes a real `auraConfig` — behavior unchanged.

**Solo fake data** lives directly in `FramePreview.lua` (~10 lines) rather than importing from `PreviewManager.SOLO_FAKES` (which is a local, not exported). Small duplication but avoids reaching into Edit Mode internals.

**Zero changes to:** `Preview/PreviewAuras.lua`, `Preview/PreviewIndicators.lua`, `Preview/PreviewManager.lua`, `Preview/Preview.lua`, any `Units/` code, any `Elements/` code, `StyleBuilder.lua`, `Settings/Builders/AuraPreview.lua`.

### Dependency direction

```
Settings/Builders/FrameSettingsBuilder.lua
          │
          ▼
Settings/Builders/FramePreview.lua   (new — orchestrator for Settings card)
          │
          ▼  (read-only calls, no mutation)
Preview/PreviewFrame.lua             (element builders — shared layer)
          │
          ▼
Preview/Preview.lua                  (fake unit data)
```

Edit Mode's path into `PreviewFrame.lua` (via `PreviewManager`) is untouched. Both Settings and Edit Mode are peer consumers of the shared element layer.

---

## Settings card integration

### Entry point

`FrameSettingsBuilder.Create(parent, unitType)` calls `F.Settings.FramePreview.BuildPreviewCard(content, createCardW, unitType)` once, before inserting the first settings card. One call site — no changes to individual page files (`Player.lua`, `Target.lua`, etc.).

### Page layout — wrapper-grid migration

Frame pages migrate off `CardGrid` to the Phase 4 wrapper-grid pattern from the aura panel layout refactor (`2026-04-15-aura-panel-layout-design.md`).

**Pinned row:** `Preview (natural width, animated) | PositionAndLayout (1fr)`, both stretched to match the taller card. The existing `PositionAndLayout` card is extracted from the CardGrid and placed directly in the pinned row — it is not duplicated or rebuilt, just re-parented.

**PositionAndLayout card split:**
- **Active controls (above divider):** width, height. For group frames: orientation, spacing, units-per-column, max-columns. All drive live preview changes.
- **Greyed-out controls (below divider, ~35% opacity):** x offset, y offset, anchor. Read-only display of current values.
- **Edit Mode link:** subtle text link (`Edit Mode →`) below the greyed-out section. Launches in-world positioning.

**Scroll region below:** all remaining per-frame settings cards (HealthColor, HealthText, PowerBar, PowerText, Name, CastBar, StatusIcons, StatusText, ShieldsAndAbsorbs, Sorting, PartyPets).

### Reflow on layout changes

When the preview content changes size (orientation switch, width/height slider, stepper count change):
- The preview card animates to its new dimensions via `Widgets.StartAnimation`
- The wrapper grid smoothly adjusts both cards' positions and sizes in lockstep
- The PositionAndLayout card fills remaining horizontal space

Continuous slider drags (width/height) update the preview per-tick without animation for responsiveness. Discrete changes (orientation, stepper, unitsPerColumn) use animated transitions.

### Teardown

Panel `OnHide` and `EDITING_PRESET_CHANGED` trigger full teardown: unregister `CONFIG_CHANGED` listener, hide/destroy child frames, nil references. Rebuild from scratch on next show.

---

## Solo vs group rendering

### Solo frames (Player, Target, ToT, Focus, Pet)

One call to `PreviewFrame.Create(parent, config, fakeUnit)` with the unit's config and its solo fake entry. The preview card's inner viewport centers the single frame.

**Solo fakes** (defined directly in `FramePreview.lua`):

| Unit type | Name | Class | Health % |
|---|---|---|---|
| player | UnitName('player') | Player's class | 0.85 |
| target | Target Dummy | WARRIOR | 0.85 |
| targettarget | Healbot | PRIEST | 0.85 |
| focus | Focus Target | MAGE | 0.85 |
| pet | Pet | HUNTER | 0.85 |

All at ~0.85 health so loss color is passively visible.

### Boss frames (multi-unit solo)

Boss frames are a special case — boss1–boss4 are individual unit tokens, not managed by a SecureGroupHeader. They're NPC frames, not true group frames. The preview renders 4 independent boss frames in a fixed vertical stack (no orientation/spacing/sort controls, no stepper). Each uses the same boss unit config with varied fake data (different health percentages).

**Note:** Boss frame preset visibility is a known issue — see GitHub #82. Currently boss frames show regardless of content type; they should respect content-based presets.

### Group frames (Party, Arena, Raid)

The preview spawns N child frames (one per fake unit) and positions them according to the editing preset's layout config.

**Layout math** (flat column flow, ~15 lines in `FramePreview.lua`):

```
For each unit i (0-indexed):
  col = floor(i / unitsPerColumn)
  row = i % unitsPerColumn

  If orientation == VERTICAL:
    x = col * (frameWidth + spacing)
    y = row * (frameHeight + spacing)
  If orientation == HORIZONTAL:
    x = row * (frameWidth + spacing)
    y = col * (frameHeight + spacing)
```

**Fake unit data:** Group previews pull from `Preview.GetFakeUnits()` — the existing FAKE_UNITS table (Tankadin, Healbot, Stabsworth, Frostbolt, Deadshot). For counts beyond 5, the list cycles with a numeric suffix ("Tankadin 2"). Mixed classes and health percentages give visual variety.

### Party pet toggle

On the Party page only, the preview card header includes a small toggle (checkbox or icon button) for showing/hiding pet sub-frames in the preview.

- **Default:** OFF (pets hidden). Pet frames clutter the party preview unless the user is actively configuring PartyPets settings.
- **When ON:** A smaller pet frame renders anchored below each party member frame, respecting `partyPets.spacing`. Pet frames show name + health text per `partyPets` config.
- **Persistence:** Session-only (resets on panel rebuild). Not saved to config — it's a preview display toggle, not a setting.
- **Fake pet data:** Simple entries — "Cat", "Wolf", "Imp", "Water Elemental", "Treant" — with varied health percentages.

### Raid stepper

- **Location:** Preview card header row, right-aligned: `Preview — Raid  [units: 8 ▲▼]`
- **Control:** Increment/decrement buttons (▲▼), not a slider
- **Range:** 1–40, default 8 (shows one column wrap with unitsPerColumn=5)
- **Persistence:** Character SavedVariable under `charDefaults.settings.raidPreviewCount`
- **Animation:** Changing count triggers animated reflow — frames fade in/out at edges while the grid smoothly resizes

### Roster counts

| Frame type | Count | Stepper |
|---|---|---|
| Party | 5 (always full) | No |
| Arena | 3 (always full) | No |
| Boss | 4 (fixed vertical stack) | No |
| Raid | 1–40, default 8 | Yes |

---

## Live updates via CONFIG_CHANGED

### Event filter

`FramePreview.lua` registers one `EventBus` listener for `CONFIG_CHANGED`. The handler inspects the config path against two patterns:

```
Primary:    presets.<presetName>.unitConfigs.<unitType>.<key>
Party pets: presets.<presetName>.partyPets.<key>
```

The `partyPets` config lives at preset level (NOT inside `unitConfigs`), so the Party page preview must watch both path patterns. The party pets path only triggers updates when the current page is Party and the pet toggle is ON.

### Guards

1. **Preset guard:** `if presetName ~= F.Settings.GetEditingPreset() then return end`
2. **Unit type guard:** `if unitType ~= currentUnitType then return end`

### Rebuild vs targeted update

| Change type | Examples | Action |
|---|---|---|
| **Structural** | `width`, `height`, `showPower`, `orientation`, `unitsPerColumn`, `maxColumns`, `spacing` | Full rebuild: `PreviewFrame.UpdateFromConfig()` on each child (using frame pool), recalculate group positions, animate card resize. Debounced at ~0.05s. |
| **Cosmetic** | `health.lossColor`, `health.textFormat`, `name.fontSize`, `power.textFormat`, `statusIcons.*` | Targeted update: modify the specific property on existing frames/textures/fontstrings directly (e.g., `applyHealthColor()`, `SetFont()`, `SetText()`). NO `DestroyChildren` / `BuildAllElements`. No debounce — cheap enough to fire per-tick on slider drags. |

A mapping from config key → update function is maintained in `FramePreview.lua` so the `CONFIG_CHANGED` handler can dispatch to the correct targeted updater without a full rebuild. Unknown keys fall back to a full rebuild as a safety net.

### Preset switch

`EDITING_PRESET_CHANGED` triggers full teardown + rebuild from scratch with the new preset's config. No incremental update.

---

## Element coverage

### Existing builders (in `Preview/PreviewFrame.lua`)

| Element | Builder | Settings card |
|---|---|---|
| Health bar (fill + loss) | `BuildHealthBar` + `applyHealthColor` + `applyHealthLossColor` | HealthColor |
| Health text | (inside `BuildHealthBar`) | HealthText |
| Power bar | `BuildPowerBar` | PowerBar |
| Power text | (inside `BuildPowerBar`) | PowerText |
| Name text | `BuildNameText` | Name |
| Status icons (combat, role, leader, raidIcon, readyCheck, phase, resurrect, summon, pvp, resting, raidRole) | `BuildStatusIcons` | StatusIcons |
| Cast bar | `BuildCastbar` | CastBar |
| Highlights (target, mouseover) | `BuildHighlights` | — |

### New builders needed

| Element | Builder | Settings card | Complexity |
|---|---|---|---|
| Portrait | `BuildPortrait` | HealthColor (portrait section) | Medium — 2D/3D class portrait texture, respects enable toggle + style switch |
| Shields & Absorbs | `BuildShieldsAndAbsorbs` | ShieldsAndAbsorbs | High — 4 independent overlay layers on health bar: heal prediction, shields (damage absorbs), heal absorbs, overshield. Each with enable toggle + color. Fake data needed for all 4. |
| Status text | `BuildStatusText` | StatusText | Low — FontString overlay showing fake status string. Config drives font size, format, position. |
| Sorting | (reorder fake unit array) | Sorting | Low — logic only, reorder array by role/class/name before positioning. No new visual element. |
| Party Pets | `BuildPartyPet` | PartyPets | Medium — smaller sub-frame anchored below each party member. Renders pet name + health text with font/anchor/outline config. No explicit width/height in config — size derived from party frame or fixed. Only on Party page. |

### Out of scope

| Element | Reason |
|---|---|
| Threat border | No settings card exists yet. Future work. |
| Range alpha | Not meaningful in a static preview. |
| Auras / Indicators | Covered by Aura Preview on separate pages. |

### Fake data for shields & absorbs

To make all 4 overlay layers visible on the preview, fake units need additional fields:

- `incomingHeal`: ~15% of max health (visible heal prediction bar)
- `damageAbsorb`: ~10% of max health (shield overlay)
- `healAbsorb`: ~5% of max health (heal absorb overlay)
- `overAbsorb`: true on one fake unit (overshield glow)

---

## Show All Enabled / Focus Mode toggle

### Behavior

A toggle in the Preview card header, mirroring the aura preview's "Show all enabled auras" toggle but adapted for frame settings.

**Toggle ON — "Show All Enabled" (default):** Every enabled element renders at full opacity. The complete frame is visible.

**Toggle OFF — "Focus Mode":** All elements dim to ~20% opacity. Clicking a settings card header in the scroll region spotlights its corresponding element(s) on the preview — full opacity, everything else stays dimmed. The selected card gets a left accent bar (same visual language as the selected indicator row in aura panels).

### Element-to-card mapping

| Settings card | Spotlighted elements |
|---|---|
| HealthColor | Health bar (fill + loss) + Portrait |
| HealthText | Health text overlay |
| PowerBar | Power bar |
| PowerText | Power text overlay |
| Name | Name text |
| CastBar | Castbar |
| StatusIcons | Status icon row |
| StatusText | Status text overlay |
| ShieldsAndAbsorbs | All 4 absorb overlay layers |
| PartyPets | Pet sub-frames (Party page only) |
| Sorting | N/A (reorders units, no visual element to spotlight) |
| PositionAndLayout | N/A (pinned, not in scroll region) |

### Default state

When toggle is OFF, the **first card** in the scroll region (HealthColor) is auto-selected. This ensures the user immediately sees the dimming/focus behavior and understands the mode without needing to click first.

### Deselection

Clicking the preview card itself or toggling back to ON deselects and restores all elements to full opacity.

---

## Element strata / z-ordering

Frame elements currently use hardcoded relative frame levels (e.g., absorb bar at `health + 2`, heal prediction at `health + 3`, name text at `health + 5`). This causes z-ordering conflicts (e.g., buffs rendering below heal absorbs) with no user recourse. A configurable strata system is tracked in GitHub #83.

### Preview support (wired in now)

The preview reads an `elementStrata` config map when building elements — applying each element's frame level offset from the map rather than using hardcoded values. This future-proofs the preview so that when strata settings are added (#83), the preview automatically reflects them.

**Default `elementStrata` in `Presets/Defaults.lua`:**

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
}
```

Values are relative frame level offsets from the base frame. The default order matches the current hardcoded behavior so existing users see no change. When a future settings card (drag-to-reorder or up/down buttons) lets users reorder elements, the preview will render them at the new levels automatically.

### Implementation in PreviewFrame.lua

Each `Build*` function reads its element's offset from `config.elementStrata` (falling back to the default if absent) and calls `SetFrameLevel(baseLevel + offset)` instead of using hardcoded `+ N` values. This is a small refactor to each existing builder — replacing `bar:GetFrameLevel() + 2` with `bar:GetFrameLevel() + (config.elementStrata.damageAbsorb or 2)`.

---

## Scope boundaries

**This is strictly a UI/UX project.** The following systems are NOT modified and must NOT be touched:

- **Config API** (`Core/Config.lua`) — no changes to how config is read, written, or structured (except adding `elementStrata` defaults)
- **EventBus** (`Core/EventBus.lua`) — no new events, no changes to event dispatch. The preview is a consumer of existing `CONFIG_CHANGED` and `EDITING_PRESET_CHANGED` events only.
- **Preset system** (`Presets/`, `Layouts/`) — no changes to how presets are stored, switched, auto-detected, or applied. The preview reads the editing preset; it does not modify it.
- **Live frame rendering** (`Units/`, `Elements/`, `StyleBuilder.lua`) — no changes to how real in-game frames are built, updated, or styled. The preview is a parallel mock, not a modification of the live rendering pipeline.
- **LiveUpdate handlers** (`Units/LiveUpdate/`) — no changes. These handle runtime config application to real frames. The preview has its own CONFIG_CHANGED listener that is completely independent.
- **Settings wiring** (`Settings/Cards/*.lua` except `PositionAndLayout.lua`) — settings cards continue to call `setConfig()` exactly as they do today. The preview reacts to the resulting `CONFIG_CHANGED` events. No card is modified to "know about" the preview (except `PositionAndLayout.lua` which gets the greyed-out split + Edit Mode link).
- **Edit Mode** (`EditMode/`, `Preview/PreviewManager.lua`) — no changes. Edit Mode keeps its own preview pipeline. This project adds a peer consumer of `PreviewFrame.lua`, not a modification of Edit Mode.

If an implementation task requires changing any of the above systems, **stop and re-evaluate** — it likely means scope creep or a wrong approach.

---

## Assumptions

1. **Sticky-top:** Structurally pinned via wrapper grid (Phase 4 pattern), not the old sticky-scroll hack.
2. **Live update:** Every slider, toggle, and color picker re-renders the preview via `CONFIG_CHANGED`. No apply button.
3. **Editing preset:** Preview reads from `F.Settings.GetEditingPreset()`, not the active runtime preset. Auto-switch-on-context-entry means the editing preset almost always matches intent.
4. **Teardown on panel hide:** Preview destroyed and rebuilt fresh on re-entry. No persistent global preview.
5. **Combat-safe:** Non-secure `CreateFrame('Frame')` — builds/updates freely during combat.
6. **No aura rendering:** Settings passes `auraConfig=nil` to `PreviewFrame.Create`. The `if(auraConfig)` guard in `BuildAllElements` skips aura rendering.

---

## Risks and open questions

### Sequencing dependency on aura panel layout refactor

This spec references Phase 4's wrapper-grid pattern from the aura panel layout refactor (`2026-04-15-aura-panel-layout-design.md`). The aura refactor is in progress and expected to be complete before this project starts. If it isn't, the wrapper-grid pattern is simple enough (a container frame with two children and `SetPoint`-based layout) to build here as the first consumer.

### Horizontal scroll (scroll-inside-scroll)

The settings panel already scrolls vertically. If a raid preview at high stepper count is wider than the preview card, the preview needs its own internal horizontal `ScrollFrame`. This creates scroll-inside-scroll. The preview viewport must be implemented as a `ScrollFrame` with horizontal overflow enabled and vertical overflow disabled (the preview card grows vertically; the outer panel handles vertical scroll).

### Performance at high stepper counts

Raid at 40 units = 40 × `PreviewFrame.Create` calls, each building 10+ sub-elements (~400+ frames/textures/fontstrings). The current `UpdateFromConfig` approach (`DestroyChildren` + `BuildAllElements` on every change) will not scale — slider drags at 40 units will stutter even with debounce. This is not a "might happen" risk; it's a certainty that must be engineered around.

**Required approach — frame pooling + targeted updates:**

1. **Frame pooling for group previews.** When the stepper count decreases or a full rebuild triggers, child frames are hidden and returned to a pool (`FramePreview._framePool`) — NOT destroyed. When the count increases or a rebuild triggers, frames are pulled from the pool before creating new ones. This eliminates `CreateFrame` / garbage collection churn on every config change.

2. **Targeted element updates for cosmetic changes.** Cosmetic changes (color, text format, font size, text anchor, etc.) must NOT trigger `DestroyChildren` + `BuildAllElements`. Instead, update the specific property on the existing frame/texture/fontstring directly — e.g., `frame._healthText:SetFont(...)` for a font size change, `applyHealthColor(frame._healthBar, config, fakeUnit)` for a color change. Only structural changes (width, height, showPower, orientation) trigger a full rebuild.

3. **Debounce on full rebuilds only.** Targeted cosmetic updates are cheap enough to fire per-tick on slider drags. Full structural rebuilds get the ~0.05s debounce.

4. **Pool cleanup on teardown.** When the panel hides, the pool is drained — all pooled frames are destroyed. The pool lives only for the lifetime of the panel session, not globally.

### PositionAndLayout card modifications

The existing `Settings/Cards/PositionAndLayout.lua` needs actual code changes to support the split active/greyed state:
- Width/height controls remain active
- Group layout controls (orientation, spacing, etc.) remain active
- X/Y/anchor controls render at 35% opacity, non-interactive
- A subtle Edit Mode link is added below the greyed-out section
- The card must work correctly both in its new pinned position AND if re-parented back to a CardGrid in the future

---

## Out of scope (future work)

- Threat border settings card + preview renderer
- Element strata settings card (drag-to-reorder UI) — GitHub #83
- Boss frame preset visibility — GitHub #82
- Per-frame Appearance overrides (global theme settings promoted to per-frame)
- Aura/indicator rendering on the Frame Preview (would merge Frame + Aura previews)
- Edit Mode simplification (strip down to wireframe/positional outlines)
- Onboarding tour explaining Focus Mode toggle

---

## References

- Aura panel layout refactor: `docs/superpowers/specs/2026-04-15-aura-panel-layout-design.md` (Phase 4 pattern)
- Preview infrastructure: `Preview/PreviewFrame.lua`, `Preview/Preview.lua`, `Preview/PreviewManager.lua`
- Aura preview builder: `Settings/Builders/AuraPreview.lua`
- Frame settings builder: `Settings/FrameSettingsBuilder.lua`
- Shields & Absorbs card: `Settings/Cards/ShieldsAndAbsorbs.lua`
- Status Icons card: `Settings/Cards/StatusIcons.lua`
- Defaults: `Presets/Defaults.lua`
