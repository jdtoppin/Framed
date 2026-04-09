# Framed Changelog

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
