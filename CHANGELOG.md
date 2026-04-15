# Framed Changelog

## v0.8.9-alpha

- Fix party/raid role sorting being silently ignored — the header was writing a nameList but kept `sortMethod='INDEX'`, which falls through Blizzard's sort branches and leaves frames in default order; now uses `sortMethod='NAMELIST'` so role order actually takes effect
- Fix `attempt to compare a secret number value` error from the cast tracker's recheck-skip optimization — the spellId comparison now guards against secret values returned by `UnitCastingInfo`/`UnitChannelInfo` in combat
- Fix `ADDON_ACTION_BLOCKED` on `FramedPartyPet1:ClearAllPoints()` when party composition changed mid-combat — pet re-anchor is now deferred until `PLAYER_REGEN_ENABLED` when the secure frames are locked down
- Internal cleanup: drop hardcoded fallback values in the Dispellable element that duplicated canonical defaults from `Presets/Defaults.lua`

## v0.8.8-alpha

- The new **Backups** system is now feature-complete — save, rename, load, and delete named snapshots, with inline export/import, version and size metadata, stale-version warnings, last-loaded tracking, and roundtrip verification that reports exactly which keys differ from your current config
- Fix Backups snapshot rows overflowing at narrow widths — titles now wrap above the buttons, the metadata line (version · date · layouts · size) wraps below the version when it's too long, and the row grows to fit; very narrow widths stack the buttons under the text
- Fix buttons disappearing from a Backups row when its Export area was opened — buttons are now pinned to the top of the row and the export area expands downward from the row's current height
- Fix auto-backup rows having an empty slot where Rename would be — Export now sits directly next to Delete
- Fix Rename edit box not dismissing when clicking the Rename button again or clicking outside the field; pressing Escape or Enter also closes it cleanly
- Style the version and author name in the About card with the accent color
- Polish inline dropdowns (underline, chevron, accent default) and cascade EditBox width through anchors so nested inputs size correctly
- Fix a race in the Toast dismiss animation that could leave a stale frame visible when a new toast slid in on top of it
- Show the active preset name in accent color in the Settings header

## v0.8.6-alpha

- Fix import/export failing with "Invalid payload structure" on every valid import — a double-pcall was silently dropping the deserialized payload; also rewrite the error messages in plain language
- Add tooltips on the Import mode switch explaining what Replace and Merge actually do
- Fix **Missing Buffs** indicator running even when disabled in settings
- Fix party/raid role sorting occasionally snapping frames to the wrong position on first group spawn — roster events are now bridged through EventBus and the nameList is rebuilt once group membership is fully populated
- Backfill aura sub-table defaults into existing saved presets — Arena/Boss/Solo/Minimal frames no longer end up missing dispellable, defensive, external, and missing-buff configuration after upgrading
- Guard **Private Auras** and **Targeted Spells** against partial config tables so missing optional sub-tables no longer error during Setup
- Reduce cast-tracker broadcast chatter by skipping redundant updates
- Polish **Framed Overview** illustrations and dim the background while the Overview is open
- Retarget the Setup Wizard card's Tour button to the new Overview (old `Onboarding/Tour.lua` removed in v0.8.5-alpha)
- Internal cleanup: drop unused imports, rename shadowing locals, fix luacheck warnings across Elements, Settings, Widgets, and builders

## v0.8.5-alpha

- Add **Framed Overview** — a 6-page illustrated walkthrough covering layouts, edit mode, settings cards, aura indicators, and defensives/externals; auto-shows on first login after the setup wizard and can be relaunched from Appearance → Setup Wizard → Take Overview
- Escape collapses the Overview to a top-right pip instead of leaking to the game menu; click the pip to resume
- Replace the unreachable guided tour with the new Overview (old `Onboarding/Tour.lua` removed)
- Promote `SetupAccentHover` to the shared Widgets library so other panels can reuse the accent fade
- Export `F.Preview.ApplyUnitToFrame` so the Overview welcome page can render a live 3-member party sample
- Add role sorting for raid and party frames (Tank/Healer/DPS ordering via SecureGroupHeader nameList)
- Raid role mode: flat sort across groups, follows orientation and anchor point
- Party role mode: single sorted column
- Add Sorting settings card with role order presets
- Add icon-row dropdown widget showing inline role icon previews
- Edit mode preview and click catcher now reflect sort mode layout
- Fix edit mode preset switch snapping frames to top-left when target preset had no config for that frame
- Post release notes to Discord from the release workflow

## v0.8.4-alpha

- Fix stale target/focus frame auras after retarget — aura cache now invalidates on token reassignment events (PLAYER_TARGET_CHANGED, PLAYER_FOCUS_CHANGED, UNIT_TARGET, group/arena/boss/nameplate updates) instead of only UNIT_AURA
