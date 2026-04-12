# Framed Changelog

## v0.8.5-alpha

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
