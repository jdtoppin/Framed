# Aura Panel Layout Refactor

**Date:** 2026-04-15
**Scope:** Restructure the aura panel layout (Buffs, Debuffs, Dispels, Defensives, Externals, etc.) to pin Preview and Indicators list side-by-side, move indicator creation inline into the Indicators card title row, convert the sub-header Copy To button into a `Copy to [target] [Copy]` dropdown, and replace the separate Create Indicator card. Scroll content below the pinned row hosts the settings cards for the selected indicator.

---

## Problem

Today the Buffs panel (and its siblings) uses three top cards that all scroll together:

1. **Preview** (left, ~40% width)
2. **Create Indicator** (stacked under Preview, ~40% width)
3. **Indicators list** (right, ~60% width, full-height of the 40/60 row)

Below that row, the selected indicator's settings cards (Appearance, Position, Filters…) are rendered inline in the same scroll region. Problems:

- **Create card is permanently visible** even though users only need it briefly. It eats vertical space the rest of the time.
- **Indicators list scrolls with the page**, so when users scroll down to edit Position/Filters they lose quick-access to switching indicators.
- **Copy To lives in the sub-header** as a button that opens a modal dialog (`Settings/CopyToDialog.lua`). The dialog is a multi-select checkbox UI for picking targets — heavyweight for a single-target push.
- **No visual distinction for the selected indicator row** beyond a full-border highlight, which competes with the card border.

## Goals

1. Keep Preview pinned to the top-left so the user always sees their frame.
2. Keep Indicators pinned next to Preview so switching between indicators is one click regardless of how far they've scrolled.
3. Make indicator creation inline — hidden until invoked, no dedicated card.
4. Replace the Copy To modal with a `Copy to [dropdown] [Copy]` control inline in the sub-header. Same backend wiring, single-target UX.
5. Give the selected indicator row a lightweight visual marker (left-edge accent + tinted gradient) matching the sidebar's active-item pattern.
6. Add micro-copy under the Preview's `Show all enabled auras` toggle explaining what it does.

## Non-Goals

- No changes to how aura configs are stored or read — this is a Settings UI refactor only.
- No sub-header changes beyond the Copy To control.
- No changes to how the selected indicator's settings cards are built — only their placement changes.
- **Short CardGrid panels** (Dispels, MissingBuffs, TargetedSpells, PrivateAuras, CrowdControl, LossOfControl) keep their existing CardGrid layout. They already fit in the viewport without scrolling past the Preview, so migrating them off CardGrid wouldn't earn enough to justify the churn. They still get Phase 2's sub-header Copy To dropdown (where applicable) and Phase 3's shared Preview helper blurb for free.
- **CrowdControl and LossOfControl** additionally do not get the sub-header Copy To control — they store global config, so there are no unit-type destinations to copy between. Same behavior as today.

---

## Layout

### Sub-header (unchanged shape, new Copy To control)

```
┌─ Sub-header ────────────────────────────────────────────────────────────┐
│ Buffs / PLAYER FRAME ▾           Copy to [Target ▾] [Copy]  Editing: … │
└─────────────────────────────────────────────────────────────────────────┘
```

- `Copy to` label + dropdown + button replace the existing `_headerCopyToBtn` button in `Settings/MainFrame.lua:254-257`.
- Dropdown targets are the valid copy destinations (same set the dialog exposes today): Target, Target of Target, Focus, Pet, Boss, Party, Raid, Mythic Raid, etc. — whatever `F.Settings.CopyTo` / `CopyToDialog.lua` currently computes as valid targets for the active panel's config key.
- Clicking `Copy` copies the current aura panel's config from the active unit type to the selected target. No dialog.
- The control is still per-panel chrome — it hides/shows based on whether the active panel supports Copy To (same logic as today; CrowdControl and LossOfControl stay excluded).
- `Editing: <preset>` stays pinned on the far right, unchanged.

### Pinned row: Preview + Indicators

```
┌─ Preview (natural width ~260px) ──┐ ┌─ Indicators (fills rest) ──────────────┐
│ [top accent bar]                  │ │ INDICATORS                 + click to  │
│                                   │ │                            add new...  │
│   [mock unit frame]               │ │ ───────────────────────────────────────│
│                                   │ │ Name              Type                 │
│ ─────────────────────────────     │ │ ┌─ scroll region (fills card) ──────┐  │
│ [x] Show all enabled auras        │ │ │▌ Renew        Icon    [•] del edit│  │
│ Renders every enabled indicator   │ │ │  PW: Shield   Bar     [•] del edit│  │
│ simultaneously so you can see how │ │ │  Prayer…      Overlay [•] del edit│  │
│ they stack on this unit frame.    │ │ │  Atonement    Border  [ ] del edit│  │
│ Turn off to preview only the      │ │ │  …                                │  │
│ selected indicator.               │ │ └────────────────────────────────────┘  │
└───────────────────────────────────┘ └─────────────────────────────────────────┘
```

**Preview card:**

- Natural width matches today (driven by the mock unit frame size, which varies per panel).
- `Widgets.CreateAccentBar(previewCard, 'top')` — unchanged.
- Below the unit frame, a separator line then the existing `Show all enabled auras` checkbox.
- **New:** a helper blurb under the checkbox (small, `text-dim`):

    > Renders every enabled indicator simultaneously so you can see how they stack on this unit frame. Turn off to preview only the selected indicator.

- The preview card stretches vertically to match the Indicators card height. The blurb fills any leftover vertical space so the card doesn't look sparse when stretched.

**Indicators card:**

- Fills the remaining row width (same sizing as today — a wrapper-context grid, not `CardGrid`).
- Fixed `max-height` matching the tallest the pinned row should ever get. Long indicator lists scroll **inside** the card, not by scrolling the whole panel.
- Title row:
    - `INDICATORS` card title on the left
    - spacer
    - `+` icon button + `click to add new...` hint on the right
- Clicking `+` expands an inline create form (see below). The `+` becomes `×` while expanded.
- Below the title row: column header row (`Name | Type | …`) — unchanged from today.
- Below the header row: scroll region containing indicator rows.
- Selected row treatment:
    - `border-left: 2px solid accent`
    - `background: linear-gradient(90deg, accent-dim, transparent)`
    - Matches the sidebar's active item pattern in `Settings/MainFrame.lua` for consistency.
    - No full-border highlight — the left accent + gradient is the only marker.

### Inline Create Form (expanded state)

Clicking the `+` icon expands an inline form inside the Indicators card, between the title row and the list header:

```
┌─ Indicators ───────────────────────────────────────┐
│ INDICATORS                              × cancel   │
│ ──────────────────────────────────────────────────│
│ ┌─ dashed accent border, panel-colored inset ──┐  │
│ │ Name ▾           Type ▾          Display ▾   │  │
│ │                                               │  │
│ │ Single spell icon or colored square,  [Create]│  │
│ │ positioned on the frame.                      │  │
│ └───────────────────────────────────────────────┘  │
│ ──────────────────────────────────────────────────│
│ Name              Type                             │
│ [list rows…]                                       │
└────────────────────────────────────────────────────┘
```

- Form is a single inset block with a dashed accent border (visually distinct from the regular cards).
- Three fields across: Name, Type, Display — exactly the fields the current Create Indicator card exposes. Validation rules unchanged.
- Type description line (text-dim, left-aligned) + `Create` button on the right.
- `Create` commits the new indicator, collapses the form, and selects the new row.
- `×` in the title row (which replaces `+` while expanded) cancels and collapses without committing.
- Collapsing restores the `+ click to add new...` state.

### Scroll region (below pinned row)

Below the pinned row, the scroll region hosts the settings cards for the **selected** indicator (unchanged content):

```
Editing: Renew (icon, top-left)

┌─ Appearance ─┐  ┌─ Position ─┐  ┌─ Filters ─┐
│ …            │  │ …          │  │ …          │
```

- A small `Editing: <name> (<type>, <anchor>)` label sits above the first settings card (text-dim, small caps). This replaces the current lack of a "what are you editing" cue when scrolled.
- The cards themselves (Appearance, Position, Filters, …) are unchanged. Only their container placement shifts.

---

## Affected Panels

All "per-unit-type aura panel" files in `Settings/Panels/`:

| Panel | Current layout | Phase 2 (Copy To) | Phase 3/4 (layout) | Notes |
|-------|---------------|-------------------|---------------------|-------|
| `Buffs.lua` | Wrapper grid (not CardGrid) | ✓ | **Phase 3** | Reference implementation — land alongside Debuffs. |
| `Debuffs.lua` | Wrapper grid | ✓ | **Phase 3** | Same shape as Buffs; preserve the `Filter mode` dropdown in the inline create form. |
| `Defensives.lua` | `CardGrid` | ✓ | **Phase 4** | Enough content to justify pinned Preview + Overview; migrate off CardGrid. |
| `Externals.lua` | `CardGrid` | ✓ | **Phase 4** | Enough content to justify pinned Preview + Overview; migrate off CardGrid. |
| `Dispels.lua` | `CardGrid` | ✓ | — | Short panel (4 cards); keeps CardGrid layout. Gets sub-header Copy To + Preview blurb for free. |
| `MissingBuffs.lua` | `CardGrid` | ✓ | — | Short panel; keeps CardGrid layout. |
| `TargetedSpells.lua` | `CardGrid` | ✓ | — | Short panel; keeps CardGrid layout. |
| `PrivateAuras.lua` | `CardGrid` | ✓ | — | Short panel; keeps CardGrid layout. |
| `CrowdControl.lua` | `CardGrid` | — (global config) | — | 5 cards but all fit; keeps CardGrid layout. Sub-header Copy To stays hidden. |
| `LossOfControl.lua` | `CardGrid` | — (global config) | — | Short panel; keeps CardGrid layout. Sub-header Copy To stays hidden. |

All six aura panels with per-unit config get the Phase 2 sub-header Copy To dropdown regardless of whether they migrate layouts. The Phase 3 Preview helper blurb lives in the shared `Settings/Builders/AuraPreview.lua` and reaches every panel via `F.Settings.AuraPreview.BuildPreviewCard`, so short CardGrid panels get it for free without any per-panel edits.

**Not affected:**

- Non-aura panels (General, Layouts, etc.).

## Backend Changes

### Copy To wiring

- `Settings/CopyToDialog.lua` currently exposes `Settings.ShowCopyToDialog(configKey, panelLabel, panelId)` which builds a modal with checkboxes. The new sub-header control bypasses the modal entirely.
- Extract a direct-write helper:

    ```lua
    --- Copy aura config from the current editing unit type to a single target unit type
    --- within the same preset. Overwrite semantics (same as the dialog today).
    --- @param configKey string    e.g. 'buffs', 'debuffs', 'externals'
    --- @param targetUnitType string  e.g. 'target', 'focus', 'party', 'raid'
    --- @return boolean success
    function F.Settings.CopyTo(configKey, targetUnitType)
    ```

- The helper contains the existing deep-clone + `Config:Set` operations from `CopyToDialog.lua`'s OK handler.
- The sub-header `Copy` button calls `F.Settings.CopyTo(configKey, dropdown:GetValue())`.
- `Settings.ShowCopyToDialog` can either (a) stay as a thin wrapper that collects selections and calls the helper per target — keeps the old API alive for any other caller — or (b) be deleted if nothing else references it. Grep before deciding.

### No config schema changes

- Copy To still operates on `presets.<preset>.auras.<unitType>.<configKey>`.
- No new defaults required.

### Widget additions

- `Widgets/` may need a small helper for "dashed-accent inset panel" if one doesn't exist already. Check before adding.
- The `Show all enabled auras` helper blurb is just a `Widgets.CreateFontString` call in `Settings/Builders/AuraPreview.lua` — no new widget needed.
- The inline create form can reuse existing field builders; the only new container is the dashed-border wrapper.

---

## Implementation Plan

### Phase 1 — Extract Copy To helper

1. Read `Settings/CopyToDialog.lua` end-to-end.
2. Extract the deep-clone + write logic into `F.Settings.CopyTo(configKey, targetUnitType)`.
3. Update `CopyToDialog.lua`'s OK handler to call the helper in a loop (one per selected target).
4. Verify the dialog still works — no UX change at this step.

### Phase 2 — Sub-header Copy To dropdown

1. Replace the `_headerCopyToBtn` creation in `Settings/MainFrame.lua:254-257` with a three-part control: label + dropdown + Copy button.
2. Wire the dropdown to the valid-target list for the current panel's config key.
3. Wire the Copy button to `F.Settings.CopyTo(configKey, dropdown:GetValue())`.
4. Show/hide logic stays the same (hidden for CrowdControl / LossOfControl).
5. Verify all aura panels can copy to all valid targets.

### Phase 3 — Buffs + Debuffs reference layout

Buffs and Debuffs share the same wrapper-grid + Create Indicator + Indicators list shape today, so they land together to avoid a half-migrated state where one panel is reference and the other still has a Create card.

1. Remove the Create Indicator card entirely from both panels.
2. Change the pinned row to `Preview (natural width) | Indicators (1fr)` using the existing wrapper-grid pattern (not CardGrid).
3. Give the Indicators card a fixed max-height and internal scroll region, stretched to match the Preview card's height.
4. Add the inline `+ click to add new...` control in the Indicators card title row.
5. Build the inline create form (hidden by default, expanded on `+` click). Debuffs has an extra `Filter mode` dropdown (`all`/`harmful`/…) — that needs to be preserved in the inline form, likely as a fourth field in the top row or a pre-row above Name/Type/Display.
6. Add the `Show all enabled auras` helper blurb in `Settings/Builders/AuraPreview.lua` (shared builder — one change covers both panels).
7. Update the selected-row visual to left-accent + gradient only (drop the full border).
8. Add the `Editing: <name>` label above the settings cards in the scroll region.
9. Test live on both panels: reload, edit indicators, create new, switch between them, scroll the settings cards. Verify Copy To still works from both.

### Phase 4 — Migrate Defensives + Externals off CardGrid

Only **Defensives** and **Externals** migrate in this phase. They have enough parameter cards that scrolling past the Preview becomes a real cost, so the pinned Preview + Overview row pays for itself. The other CardGrid panels (Dispels, MissingBuffs, TargetedSpells, PrivateAuras, CrowdControl, LossOfControl) are short enough to fit in the viewport and stay on CardGrid — they already get Phase 2's sub-header Copy To dropdown and Phase 3's shared Preview helper blurb, which is the full benefit they'd see from a layout migration anyway.

Mental model for the migrated panels: pinned row = "what you're editing + top-level context", scroll region = "the details". Buffs/Debuffs's "context" is the indicator list; Defensives/Externals's "context" is the Overview card (panel-level enable + description + panel-wide toggles). Parameter cards below the pinned row.

For Defensives and Externals only:

1. Migrate off `CardGrid` to the wrapper-grid pattern that Phase 3 established.
2. **Pinned row:** `Preview (natural width) | Overview (1fr)`, both stretched to match the taller of the two.
    - Preview keeps its top accent bar and the new `Show all enabled auras` blurb (already added in Phase 3 via the shared `Settings/Builders/AuraPreview.lua` builder).
    - Overview card stretches vertically to match Preview; its existing description FontString fills the extra space naturally. If any panel's Overview is too short for that to work, pad with a helper blurb.
    - Drop the old `grid:SetSticky('preview')` call — the wrapper grid pins Preview structurally.
3. **Scroll region below the pinned row:** the panel's parameter cards (Highlight, Icon, and any others) in the same order they appear today.
4. **No `Editing: <name>` label** — CardGrid panels don't have a selected-item concept, so that label from Phase 3 doesn't apply.
5. **No inline create form** — CardGrid panels don't have indicators to create.
6. **Per-panel Overview shape varies** — Dispels has `enabled + description + onlyDispellableByMe`; Defensives/Externals/etc. may differ. Migrate panel-by-panel; read each Overview builder before reshaping.
7. Verify Copy To still works for that panel (drives from the sub-header, which is already migrated in Phase 2).
8. Verify live-update (CONFIG_CHANGED) still reaches the right cards — especially `UpdateAuraPreviewDimming` and any per-panel preview updaters like `UpdateDispelAlpha`.

### Phase 5 — Cleanup

1. Delete `CopyToDialog.lua` if nothing else references it after Phase 2.
2. Remove any dead defaults, widgets, or builders that only existed for the old Create Indicator card.
3. Update `CHANGELOG.md` with the layout refactor under the next version bump.

## Risk / Open Questions

- **Max-height of the Indicators card:** needs to match the Preview's stretched height exactly. Likely driven by the Preview's natural content height (unit frame + toggle + blurb). If the Preview is taller on some panels (bigger mock frames), the Indicators card should stretch with it — use CSS-equivalent `align-items: stretch` in the frame grid.
- **`CardGrid` vs wrapper grid:** migrating panels off CardGrid is a bigger edit than reshaping Buffs. Worth confirming the wrapper-grid pattern scales before committing to migrating all of them. Buffs first, then re-evaluate.
- **`Settings.ShowCopyToDialog` callers:** grep the codebase before deleting. If anything outside the aura panels uses it (slash commands, keybinds, etc.), keep the wrapper.
- **Inline create form width:** on narrow windows the three-column form may wrap awkwardly. Confirm behavior at min window width (2-col card grid threshold from `project_responsive_cards`).

## Out of Scope (future work)

- Per-indicator drag-to-reorder in the Indicators list.
- Bulk enable/disable in the Indicators list.
- Search/filter the indicator list by name.
- A Copy From feature (pulling another unit type's config into the current one) — this was explored during design and rejected; Copy To already covers the use case inversely.
- **Appearance and Frame pages** are known future candidates for the pinned Preview + Overview pattern established in Phase 4, but they need non-aura preview content that doesn't exist yet (Appearance: live unit frame reflecting font/texture/border/color-mode toggles; Frame: sizing and element-anchor visualization). The layout migration for those pages should happen in the same spec as the preview design so the container and content are decided together — migrating them here would either require placeholder previews (stubs) or leave a single Overview card pinned alone, which is indistinguishable from their current CardGrid layout. A follow-up spec should reference Phase 4 of this document for the layout pattern.

---

## References

- Mockup: `/tmp/framed-preview-mockups.html` (Variant A)
- Existing Copy To: `Settings/CopyToDialog.lua`, `docs/superpowers/specs/2026-03-26-copy-to-dialog-design.md`
- Sub-header source: `Settings/MainFrame.lua:210-274`
- Reference layout: `Settings/Panels/Buffs.lua:216-350`
- Preview builder: `Settings/Builders/AuraPreview.lua`
- Accent bar helper: `Widgets/Base.lua:375-389`
