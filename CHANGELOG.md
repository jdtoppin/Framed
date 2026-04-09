# Framed Changelog

## v0.7.25-alpha

- Eliminate auraEntry table allocations in Buffs: annotate auraData in-place instead of copying

## v0.7.24-alpha

- Fix MissingBuffs: zero-table inline scan instead of building intermediate sets

## v0.7.23-alpha

- Replace per-spell aura queries in MissingBuffs with single GetUnitAuras lookup

## v0.7.22-alpha

- Zero-allocation single-pass filter+display for Externals, Defensives, and Debuffs aura elements

## v0.7.21-alpha

- Reduce memory churn: reuse outer container tables in aura Update handlers
- Fix health.lossCustomColor nil error when opening settings on older profiles
- Hide missing buff icons on dead/ghost units

## v0.7.20-alpha

- Revert table pooling (investigating interaction with other addons)
- Hide missing buff icons on dead/ghost units

## v0.7.19-alpha

- Fix memory leak: reuse table pools in aura Update handlers instead of creating throwaway tables per UNIT_AURA event

## v0.7.18-alpha

- Fix duplicate auras showing in both Defensives and Externals (IMPORTANT fallback overlap)
- Filter Sated/Exhaustion and other long-duration debuffs (>=10 min) from debuff indicators
- Gate Externals RAID fallback to secret auras only (combat only)
- Migrate saved profiles to disable main tank/assist icons on party/raid frames

## v0.7.17-alpha

- Gate Externals RAID fallback to secret auras only (fixes basic HoTs showing)
- Filter long-duration (>=10 min) and permanent debuffs from debuff indicators (Sated, Exhaustion)
- Add showName to canonical defaults, remove fallback patterns
- Disable main tank/assist indicator for party and raid frames

## v0.7.16-alpha

- Filter out long-duration (>10 min) and permanent buffs from Defensives and Externals

## v0.7.15-alpha

- Add live frame position preview while dragging position sliders
- Slider widget uses relative cursor tracking for smoother drag behavior
- Inline panel stays fixed during slider drag, snaps back on release
- Position slider range scales to screen resolution and UI scale
- Add screen-edge clamping during frame drag and slider positioning
- Add visual highlight on edit mode resize handles during drag
- Scale settings window max size proportionally to screen resolution
- Fix settings window resize grabber dead zone past max bounds
- Fix preview rebuild flicker during position/size slider changes
- Fix lazy load breaking after settings window resize
- Fix delete button clipping on spell list card
- Fix colored squares not saving/loading per-spell colors
- Add HELPFUL|RAID fallback to Externals for Power Infusion and similar buffs

## v0.7.13-alpha

- Fix automated release pipeline
- Add manual changelog for cleaner release notes

## v0.7.6-alpha

- Fix group frames jumping off-screen after edit mode drag
- Fix preset list rows reverting to old background color on preset switch
- Fix health bar stuck at 0 after resurrection in combat
- Fix StatusText errors from secret boolean values in combat
- Fix Health UpdateColor errors from secret value comparisons in combat

## v0.7.5-alpha

- Add unit tooltips on hover for all frames
- Wire party pet name text for live update
- Add name text settings (anchor, offsets, font) to party pets
- Add health text anchor picker to party pets
- Fix icon duration/stack text x/y offsets not applying

## v0.7.1-alpha

- Subset all fonts to reduce addon size (13.3MB → 2.6MB)

## v0.7.0-alpha

- Initial alpha release
