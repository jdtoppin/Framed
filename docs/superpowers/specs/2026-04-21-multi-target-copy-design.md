# Multi-Target Copy Design Spec

**Date:** 2026-04-21
**Status:** Draft — awaiting user review

## Summary

Extend Framed's settings copy operations from single-target to multi-target at two scopes — aura panel and frame — while leaving the existing preset-level copy (`Copy Settings From`) untouched. Both scopes share one reusable checklist picker and one shared fan-out write helper. This reduces the multi-hour setup cost of tuning `(preset × frame × aura-panel)` combinations by letting users propagate a tuned source to N peers in one action.

## Motivation

Settings in Framed form a three-level tree: **Preset → Frame → Aura panel**. Every leaf is a unique `(preset, frame, configKey)` tuple. Users report the combinatorics cause "hundreds of hours" of setup when building out multiple presets (Raid, M+, Arena, Solo, Party) each with 6–9 frames each with ~10 aura panels.

Today's copy surface is uneven:

- **Aura panel:** `Copy To` header button with a **single-target** dropdown, same-preset only. See `Settings/Framework.lua:206` and `Settings/MainFrame.lua:272`.
- **Frame:** no copy mechanism.
- **Preset:** `Copy Settings From` dropdown in `Settings/Panels/FramePresets.lua:134` calling `F.PresetManager.CopySettings(source, target)`. One source → active preset.

The missing pieces, in order of pain:

1. **Multi-target fan-out at the aura panel level.** Single-target means users click Copy To N times to propagate one aura filter across frames or presets.
2. **No frame-scope copy at all.** Users cannot say "make my Focus frame look like my Target frame" without touching every settings card individually.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Direction | Push (`Copy To…`) | Matches existing aura-panel pattern; research (Figma Publish, Premiere Paste Attributes) confirms push + checklist is the dominant multi-target pattern |
| Picker shape | Flat grouped checklist, not tree | Matches Framed's shallow config depth; tree would be overkill at this scale |
| Destructive-overwrite UX | Single modal with count — "Overwrite N targets?" — only when ≥1 target differs from source | Diff preview is high-cost and rarely pays off below Figma scale; preset revert already exists as undo |
| Button naming | `Copy To…` (with ellipsis) | Standard "opens a picker" affordance |
| Placement | Panel header button only (no right-click menu in v1) | Header-button wins on discoverability; WeakAuras' sub-tab burial is a known anti-pattern |
| Scope of v1 | Aura-panel + frame only; preset untouched | Preset-level copy already exists; no need to re-invent |
| Sub-toggles | One: `Include aura panels` at frame scope | Premiere-style orthogonal sub-toggle; one is enough to avoid silent incoherence from hidden dependencies |
| Inheritance / linked configs | Not in v1 | Industry precedent (WeakAuras added inheritance years after copy) shows copy is a legitimate end state; layering inheritance later does not require removing copy |
| Multi-select edit mode | Not in v1 | See Future Considerations — significant write-path rework and indeterminate-state UX; 80% of value is captured by multi-target copy |
| Excluded panels | CrowdControl and LossOfControl | These store config globally, not per-preset/per-frame (matches prior `2026-03-26-copy-to-dialog-design.md` exclusion) |

## Scope

### (A) Aura panel: upgrade existing `Copy To…`

**Source:** the current aura panel on the current frame in the active preset — e.g., `Raid.Defensives` in preset "Raid".

**Target set — grouped checklist:**

- *Other frames in this preset* — all frames that exist in the active preset except the source frame; checkbox per frame.
- *Same frame in other presets* — for each other preset, one entry if that preset contains a frame with the same key as the source; labeled `<frameName> (<presetName>)`.

Users may check any combination across both groups. A "Select all in group" link-button per group is permitted.

**Write:** for each checked target, overwrite `presets.<targetPreset>.auras.<targetFrame>.<configKey>` with the source payload.

**Fires:** `CONFIG_CHANGED` per target, respecting the active-preset guard documented in `project_live_update_presets` (targets that are not in the active preset must not trigger live frame rebuilds).

### (B) Frame: new `Copy Frame To…`

**Source:** all settings for the current frame — every settings card's configKey plus every aura panel's configKey under that frame — in the active preset.

**Trigger:** new header button in the frame's settings area (same visual slot convention as the aura-panel Copy To).

**Target set — grouped checklist** (same shape as A, but targets are `(preset, frame)` pairs):

- *Other frames in this preset* — frame keys in the active preset excluding the source.
- *Same frame in other presets* — the source frame key as it exists in each other preset.

**Sub-toggle:** `☑ Include aura panels` (default on). When off, the copy payload excludes all aura-panel configKeys under the frame; only frame-level appearance/layout/bar/text/highlight configs are propagated.

**Write:** for each checked target, overwrite the frame's config subtree (respecting the sub-toggle). Aura panels within the frame are written individually so that per-panel `CONFIG_CHANGED` semantics match the single-panel case.

### Shared infrastructure

- **Reusable picker widget** — new `Widgets.CreateCopyToPicker(source, scope)`-style helper (exact API TBD by implementation plan). Takes a source descriptor and a scope (`'auraPanel'` or `'frame'`), resolves target groups, renders the grouped checklist, and returns the user's selection.
- **Shared overwrite-confirm helper** — given source payload and selected targets, returns true/false based on whether any target already differs; if so, shows the "Overwrite N targets?" modal.
- **Shared fan-out write helper** — given source tree + list of target coordinates + scope, writes each target atomically and fires the correct `CONFIG_CHANGED` events, with active-preset guards intact.

All three are built once and consumed by both (A) and (B). Future scopes (e.g., multi-target preset copy, if ever added) can reuse them.

## Out of Scope

- **Preset-level multi-target copy.** `Copy Settings From` covers the seeding case; multi-target preset overwrite is rare and not prioritized.
- **Inheritance / linked configs.** Whether to make auras inherit from `AuraDefaults`, or make frames inherit layout from a parent frame, is a separate design.
- **Multi-select preset edit mode.** See Future Considerations.
- **Diff preview inside the picker.** Overwrite-confirm shows a count only.
- **Right-click / context menu placement.** Header button only in v1.
- **CrowdControl and LossOfControl aura panels.** These store global config and have no per-frame payload; the `Copy To…` button stays hidden on those panels, matching the existing behavior documented in `2026-03-26-copy-to-dialog-design.md`.

## Future Considerations

### Inheritance / linked configs
Long-game direction observed across Figma (variables/components), JetBrains (scheme inheritance), CSS cascade, and WeakAuras (group inheritance). Inheritance removes drift but introduces override-rule UX and "where did this value come from?" debugging. Framed's shallow tree and imperative user mental model make copy a legitimate end state; inheritance can be layered on later without replacing copy. `Presets/AuraDefaults.lua` is the likely starting point.

### Multi-select preset edit mode
Natural extension: select multiple presets at the top level and have every settings edit propagate to all selected presets simultaneously. This is a *continuous* fan-out rather than an *imperative* one, and the UX cost is substantial:

- Every settings control (checkbox, slider, dropdown, color picker) needs **indeterminate-state rendering** for the case where selected presets disagree on a value.
- The write pipeline and `CONFIG_CHANGED` handlers currently assume a single active preset (see `project_live_update_presets`). Multi-target writes require rework of the active-preset model.
- Live preview / auto-switch semantics become ambiguous.

Deferred until users have lived with multi-target copy for some time; the remaining pain after copy may be small enough that a lighter design (e.g., per-preset "Mirror to preset X" toggle) covers it.

## Open Questions

None blocking. Implementation plan should decide:

- Exact widget API for the shared picker.
- Whether `Select all in group` link-buttons are included in v1 or deferred.
- Exact `CONFIG_CHANGED` fan-out shape for the frame-scope case (single `FRAME_COPIED` event vs. one event per written configKey). Leaning toward the latter so existing per-panel live-update handlers require no changes.

## References

- Existing single-target aura Copy To: `Settings/Framework.lua:206-267`, `Settings/MainFrame.lua:272-280`
- Existing preset Copy Settings From: `Settings/Panels/FramePresets.lua:134-161`, `Presets/Manager.lua` (`CopySettings`)
- Prior aura-panel copy spec: `docs/superpowers/specs/2026-03-26-copy-to-dialog-design.md`
- Excluded-panel rationale: same prior spec, "Config Key Mapping" section
- Active-preset guard for live updates: `project_live_update_presets` memory
