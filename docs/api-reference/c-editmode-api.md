# C_EditMode API Reference

Source: `Blizzard_APIDocumentationGenerated/EditModeManagerDocumentation.lua`

## Functions

### C_EditMode.ConvertLayoutInfoToString(layoutInfo) → layoutInfoAsString
Convert layout info struct to a shareable string.

### C_EditMode.ConvertStringToLayoutInfo(layoutInfoAsString) → layoutInfo
Parse a layout string back to a struct. May return nothing.

### C_EditMode.GetAccountSettings() → accountSettings
Returns `table<EditModeSettingInfo>`.

### C_EditMode.GetLayouts() → layoutInfo
Returns `EditModeLayouts` (all layouts + activeLayout index).

### C_EditMode.IsValidLayoutName(name) → isApproved
Check if a layout name is valid.

### C_EditMode.OnEditModeExit()
Signal that edit mode has been exited.

### C_EditMode.OnLayoutAdded(addedLayoutIndex, activateNewLayout, isLayoutImported)
Signal a new layout was added.

### C_EditMode.OnLayoutDeleted(deletedLayoutIndex)
Signal a layout was deleted.

### C_EditMode.SaveLayouts(saveInfo)
Save all layouts. `saveInfo` is `EditModeLayouts`.

### C_EditMode.SetAccountSetting(setting, value)
Set an account-wide edit mode setting.

### C_EditMode.SetActiveLayout(activeLayout)
Set the active layout by index.

## Events

### EDIT_MODE_LAYOUTS_UPDATED (layoutInfo, reconcileLayouts)
Fires when layouts are updated. `layoutInfo` is `EditModeLayouts`, `reconcileLayouts` is bool.

## Structures

### EditModeAnchorInfo
```
point: FramePoint
relativeTo: string
relativePoint: FramePoint
offsetX: number
offsetY: number
```

### EditModeLayoutInfo
```
layoutName: string
layoutType: EditModeLayoutType
systems: table<EditModeSystemInfo>
```

### EditModeLayouts
```
layouts: table<EditModeLayoutInfo>
activeLayout: luaIndex
```

### EditModeSettingInfo
```
setting: number
value: number
```

### EditModeSystemInfo
```
system: EditModeSystem
systemIndex: luaIndex (nilable)
anchorInfo: EditModeAnchorInfo
anchorInfo2: EditModeAnchorInfo (nilable)
settings: table<EditModeSettingInfo>
isInDefaultPosition: bool
```

## Key Enums

### EditModeSystem (24 systems)
| Value | Name |
|-------|------|
| 0 | ActionBar |
| 1 | CastBar |
| 2 | Minimap |
| 3 | UnitFrame |
| 4 | EncounterBar |
| 5 | ExtraAbilities |
| 6 | AuraFrame |
| 7 | TalkingHeadFrame |
| 8 | ChatFrame |
| 9 | VehicleLeaveButton |
| 10 | LootFrame |
| 11 | HudTooltip |
| 12 | ObjectiveTracker |
| 13 | MicroMenu |
| 14 | Bags |
| 15 | StatusTrackingBar |
| 16 | DurabilityFrame |
| 17 | TimerBars |
| 18 | VehicleSeatIndicator |
| 19 | ArchaeologyBar |
| 20 | CooldownViewer |
| 21 | PersonalResourceDisplay |
| 22 | EncounterEvents |
| 23 | DamageMeter |

### EditModeUnitFrameSystemIndices
| Value | Name |
|-------|------|
| 1 | Player |
| 2 | Target |
| 3 | Focus |
| 4 | Party |
| 5 | Raid |
| 6 | Boss |
| 7 | Arena |
| 8 | Pet |

### EditModeUnitFrameSetting (21 settings)
| Value | Name |
|-------|------|
| 0 | HidePortrait |
| 1 | CastBarUnderneath |
| 2 | BuffsOnTop |
| 3 | UseLargerFrame |
| 4 | UseRaidStylePartyFrames |
| 5 | ShowPartyFrameBackground |
| 6 | UseHorizontalGroups |
| 7 | CastBarOnSide |
| 8 | ShowCastTime |
| 9 | ViewRaidSize |
| 10 | FrameWidth |
| 11 | FrameHeight |
| 12 | DisplayBorder |
| 13 | RaidGroupDisplayType |
| 14 | SortPlayersBy |
| 15 | RowSize |
| 16 | FrameSize |
| 17 | ViewArenaSize |
| 18 | AuraOrganizationType |
| 19 | IconSize |
| 20 | Opacity |

### EditModeLayoutType
| Value | Name |
|-------|------|
| 0 | Preset |
| 1 | Account |
| 2 | Character |

### EditModeAccountSetting
| Value | Name |
|-------|------|
| 0 | ShowGrid |
| 1 | GridSpacing |
| 2 | EnableSnap |
| 3 | EnableAdvancedOptions |
| 4 | SnapRange |

## Notes for Framed

- Blizzard's Edit Mode uses `EditModeSystem.UnitFrame` (3) with `systemIndex` matching `EditModeUnitFrameSystemIndices` for Player/Target/Focus/Party/Raid/Boss/Arena/Pet
- The `EditModeAnchorInfo` struct mirrors WoW's standard SetPoint 5-tuple (point, relativeTo, relativePoint, offsetX, offsetY)
- `C_EditMode.GetLayouts()` can be used to detect if the user is in Blizzard's edit mode
- The `EDIT_MODE_LAYOUTS_UPDATED` event fires when Blizzard's layouts change
- Account settings include grid snap and snap range — could coordinate with Framed's own grid snap
