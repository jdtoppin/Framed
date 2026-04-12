# Raid & Party Role-Based Sorting Design

**Goal:** Let users sort raid and party frames by role (Tank / Healer / DPS) in any of six orderings, in addition to today's raid-group / index sorting. Settings are live-updatable without `/reload`, respect combat lockdown, and reflect mid-session spec swaps immediately.

**Problem:** Framed hardcodes raid to `groupBy='GROUP'` + `sortMethod='INDEX'` (`Units/Raid.lua:60-62`) and party to `sortMethod='INDEX'` with no grouping (`Units/Party.lua:208`). There is no configuration surface for sorting; healers who want tanks at the top, or a party healer-first layout, currently can't get one from Framed. oUF's embedded source has no group-sort abstraction — the only `sort`-related code in `Libs/oUF/` is for runes and auras — so the feature lives at the `SecureGroupHeader` attribute layer that Framed already uses.

**Approach:** Two new config keys per group unit type (`sortMode`, `roleOrder`). A small helper picks the right `SecureGroupHeader` attribute set at spawn time and at live-update time. All attribute writes go through the existing `Shared.applyOrQueue` combat queue in `Units/LiveUpdate/FrameConfigShared.lua`. A `PLAYER_ROLES_ASSIGNED` listener forces a re-sort when spec/role changes out of combat. A new `Settings/Cards/Sorting.lua` card surfaces both controls via a mode dropdown and a six-preset role-order dropdown that renders inline role icons using Framed's existing `F.Elements.RoleIcon` exports. `PreviewManager`'s edit-mode layout becomes sort-aware so users can see the effect of their choices while positioning frames.

## Out of Scope

The broader **frame preview system** (a new preview card on unit-frame settings panels showing name/health/power text with real colors and sizing, plus group previews for party/raid, plus the sticky sub-header rework) is deliberately split into a follow-on spec (**Spec B**). Spec B will reuse the sort-aware `PreviewManager` work from this spec but is a distinct effort with its own UX questions. This spec ships role sorting end-to-end without waiting on Spec B.

## Config Shape

Two new keys per group unit config, added to `Presets/Defaults.lua`:

### Raid — `raidConfig()` (~line 296)

```lua
c.sortMode  = 'group'               -- 'group' | 'role'
c.roleOrder = 'TANK,HEALER,DAMAGER' -- consulted only when sortMode == 'role'
```

### Party — `partyConfig()`

```lua
c.sortMode  = 'index'               -- 'index' | 'role'
c.roleOrder = 'HEALER,TANK,DAMAGER' -- dungeon-friendly default
```

### Notes on the shape

- **Party's mode enum is `'index'|'role'`, not `'group'|'role'`.** Party has never used `groupBy='GROUP'`; "index" is the honest name for its current behavior.
- **`roleOrder` stores the raw `SecureGroupHeader` attribute string**, not a Lua token array. The six dropdown presets map 1:1 to six string constants. Zero translation at the apply site.
- **`NONE` is never stored.** It is appended at apply time so that units with unassigned roles (open-world warmup, LFR queue, pugs before roles are picked) still render instead of being filtered out by `SecureGroupHeader`.
- **Independent party/raid config.** Healer-first party + tank-first raid works naturally.
- **`EnsureDefaults()` backfills** via the standard `F.DeepMerge` path. Upgraders get `sortMode='group'` / `'index'` matching today's behavior with no migration logic.
- **No hardcoded fallbacks elsewhere** — per the `Canonical Defaults` rule in `CLAUDE.md`, these keys live in `Presets/Defaults.lua` only.

## Spawn Path

A shared helper produces the `SecureGroupHeader` attribute set from a config. It lives in `Units/LiveUpdate/FrameConfigLayout.lua` (the module that already owns header-layout mutations) and is consumed by both the spawn path and the LiveUpdate handler.

```lua
-- Pseudocode — final names TBD during implementation
function Layout.GroupAttrs(config, unitType)
    if(unitType == 'raid' and config.sortMode == 'role') then
        return {
            sortMethod     = 'INDEX',
            groupBy        = 'ASSIGNEDROLE',
            groupingOrder  = config.roleOrder .. ',NONE',
            maxColumns     = 10,  -- headroom for 40-man role splits
            unitsPerColumn = 5,
        }
    elseif(unitType == 'raid') then
        return {
            sortMethod     = 'INDEX',
            groupBy        = 'GROUP',
            groupingOrder  = '1,2,3,4,5,6,7,8',
            maxColumns     = 8,
            unitsPerColumn = 5,
        }
    elseif(unitType == 'party' and config.sortMode == 'role') then
        return {
            sortMethod     = 'INDEX',
            groupBy        = 'ASSIGNEDROLE',
            groupingOrder  = config.roleOrder .. ',NONE',
            maxColumns     = 4,  -- Tank/Healer/DPS + NONE
            unitsPerColumn = 5,
        }
    else -- party / index
        return {
            sortMethod     = 'INDEX',
            maxColumns     = 1,
            unitsPerColumn = 5,
        }
    end
end
```

`Units/Raid.lua` and `Units/Party.lua` call `Layout.GroupAttrs` before `oUF:SpawnHeader`, unpack the returned table into the attribute-pair args, and otherwise keep their current spawn logic untouched.

### Why `maxColumns=10` for raid role mode

Worst-case 40-person comp with role-based grouping needs up to 9 columns (e.g., 3 tanks → 1 col, 8 healers → 2 cols, 29 dps → 6 cols = 9). `maxColumns=10` provides safe headroom. Group mode stays at `8` because 8 raid groups × 5 units is exactly 40.

### Why `maxColumns=4` for party role mode

`SecureGroupHeaderTemplate` with `groupBy='ASSIGNEDROLE'` creates one sub-column per unique role value among the members, in `groupingOrder` order. A 5-person party may have up to 4 role buckets present (Tank + Healer + DPS + NONE), so `maxColumns=4` is the minimum that guarantees all members render. Party's current (index mode) setup hardcodes `maxColumns=1` because there's a single column of up to 5 frames; that value must be restored when `sortMode='index'` and bumped to `4` when `sortMode='role'`. Party role mode also needs a `columnSpacing` attribute (currently absent from `Units/Party.lua`); the implementation will add `columnSpacing = config.spacing` alongside the other role-mode attributes so sub-columns are spaced correctly.

## LiveUpdate Handler

New handler in `Units/LiveUpdate/FrameConfigLayout.lua`:

```lua
function Layout.ApplySortConfig(unitType)
    local header = (unitType == 'raid') and F.Units.Raid.header or F.Units.Party.header
    if(not header) then return end

    local config = F.StyleBuilder.GetConfig(unitType)
    local attrs  = Layout.GroupAttrs(config, unitType)

    Shared.applyOrQueue(header, 'sortMethod',     attrs.sortMethod)
    Shared.applyOrQueue(header, 'groupBy',        attrs.groupBy)
    Shared.applyOrQueue(header, 'groupingOrder',  attrs.groupingOrder)
    if(attrs.maxColumns) then
        Shared.applyOrQueue(header, 'maxColumns',     attrs.maxColumns)
        Shared.applyOrQueue(header, 'unitsPerColumn', attrs.unitsPerColumn)
    end
end
```

Registered against `CONFIG_CHANGED` events for `raid.sortMode`, `raid.roleOrder`, `party.sortMode`, `party.roleOrder` via Framed's existing EventBus pattern, matching how the other `Layout.*` handlers in this file are wired.

### Combat handling — free

`Shared.applyOrQueue` (`Units/LiveUpdate/FrameConfigShared.lua:22-32`) already handles `InCombatLockdown()` by queueing attribute changes and draining them on `PLAYER_REGEN_ENABLED`. The existing `combatQueueStatus` label hook (`FrameConfigShared.lua:25-28`) is nearly-dead code today; the new Sorting card will wire a status line to it so the "Changes queued — will apply after combat" message finally has a visible home.

## Mid-Session Role Changes

**Requirement: when a raid or party member changes their role out of combat, their frame must move to the new role column immediately, without `/reload`.**

`SecureGroupHeaderTemplate` watches `GROUP_ROSTER_UPDATE` but not `PLAYER_ROLES_ASSIGNED`, so a spec swap that doesn't change roster membership will not trigger an automatic re-sort. Framed therefore listens explicitly:

```lua
-- FrameConfigLayout.lua — wired next to ApplySortConfig
F.EventBus:Register('PLAYER_ROLES_ASSIGNED', function()
    for _, unitType in next, { 'raid', 'party' } do
        local config = F.StyleBuilder.GetConfig(unitType)
        if(config.sortMode == 'role') then
            Layout.ApplySortConfig(unitType)
        end
    end
end, 'LiveUpdate.RoleResort')
```

- **Re-uses `ApplySortConfig`** rather than a dedicated "nudge" function. Re-writing `groupingOrder` (among others) to its current value is the idiom that forces `SecureGroupHeaderTemplate` to re-run its sort pass. One code path, one thing to test.
- **Combat-safety is not a concern**: spec/role changes are out-of-combat only in retail WoW, so `applyOrQueue`'s `InCombatLockdown()` check always takes the immediate-apply branch here. The call still routes through `applyOrQueue` as cheap insurance.
- **Guarded by `sortMode == 'role'`** — role changes don't affect layout in group/index mode, so the common path skips the re-apply entirely.

## Settings UI

### New card: `Settings/Cards/Sorting.lua`

A single card used by both the raid and party settings pages, registered via the existing shared-card pattern (same way `PositionAndLayout.lua` is reused across unit types). Styling follows `PositionAndLayout.lua` as the template — same card frame, label/dropdown spacing, heading conventions.

**Contents** — two controls plus one status line:

1. **Sort mode dropdown**
   - Raid: `By raid group` *(default)* / `By role`
   - Party: `By join order` *(default)* / `By role`
2. **Role order dropdown** — greyed out when mode isn't `By role`. Six items, each rendered as textual label plus three inline role icons:
   - `Tank → Healer → DPS`   (`TANK,HEALER,DAMAGER`)
   - `Tank → DPS → Healer`   (`TANK,DAMAGER,HEALER`)
   - `Healer → Tank → DPS`   (`HEALER,TANK,DAMAGER`)
   - `Healer → DPS → Tank`   (`HEALER,DAMAGER,TANK`)
   - `DPS → Tank → Healer`   (`DAMAGER,TANK,HEALER`)
   - `DPS → Healer → Tank`   (`DAMAGER,HEALER,TANK`)
3. **Combat queue status line** — hidden by default, wired to `FrameConfigShared.combatQueueStatus`. Shows "Changes queued — will apply after combat" while a queue has pending writes.

### Icon-row dropdown widget extension

`Widgets/Dropdown.lua` already supports per-row texture decoration via `_swatch` (`line 323`) and a row-decorator hook (`line 464` — "Custom row decorator (e.g. for icon previews)"). For this card the per-row machinery is extended to support a small array of decorator textures rather than a single `_swatch`: each row builds three textures left-to-right and each item supplies three `{texture, texCoord}` tuples.

**Implementation strategy:** a new factory `Widgets.CreateIconRowDropdown(parent, width, iconsPerRow)` alongside the existing `CreateTextureDropdown`, sharing the same singleton list frame and scroll infrastructure. Non-invasive to existing dropdowns.

**Icon content per row** is sourced from the existing `F.Elements.RoleIcon` public surface (`Elements/Status/RoleIcon.lua:101-111`):

- Texture: `F.Elements.RoleIcon.GetTexturePath(F.Config:Get('general.roleIconStyle'))`
- TexCoords: `F.Elements.RoleIcon.TEXCOORDS[role]` for each of the three roles

**Bonus:** if the user later changes their role-icon style in the general settings, the sort dropdown's preview icons update automatically the next time the dropdown is opened — no cache invalidation needed.

### Live updates

Selecting a mode or order writes through the Config API (`F.Config:Set('raid.sortMode', ...)` etc). The existing `CONFIG_CHANGED` event fires, `ApplySortConfig('raid')` runs, and the real raid header reflows (or queues the change in combat). No reload, no re-spawn of frames.

## Edit Mode Preview

Framed already has a robust edit-mode preview system in `Preview/PreviewManager.lua` that spawns fake unit frames in the configured layout. Two modifications make it sort-aware:

### 1. `PreviewManager` layout pass

The existing group-preview layout code (around `PreviewManager.lua:172-242`) currently iterates fake units in index order. It grows a branch:

```lua
local orderedUnits
if(config.sortMode == 'role') then
    orderedUnits = bucketByRole(fakeUnits, config.roleOrder)
else
    orderedUnits = fakeUnits
end
-- existing column-flow code now iterates orderedUnits instead of fakeUnits
```

`bucketByRole` is a local helper (~15 lines) that groups fake units by their existing `role` field in the order specified by `config.roleOrder`. For role mode, each role acts as a "column group" matching how `SecureGroupHeader` handles real frames.

### 2. Fake unit pool reuses what exists

`Preview/Preview.lua:16-20` already defines fake units **with `role` fields** — `Tankadin` (TANK), `Healbot` (HEALER), `Stabsworth`/`Frostbolt`/`Deadshot` (DAMAGER). The 5-unit pool repeats 4× to fill raid count=20, giving **4 tanks / 4 healers / 12 dps** — a believable composition that clearly demonstrates role-sort effects.

### 3. `ClickCatchers.getGroupBounds` becomes sort-aware

`EditMode/ClickCatchers.lua:89-105` currently computes catcher bounds assuming the existing column-flow math. For role mode it needs to compute bounds based on the tallest role column and the total column count (e.g., 4/4/12 comp → 1+1+2 = 4 columns × 5 rows tall). The bounds math is factored into a helper shared between `PreviewManager` and `ClickCatchers` so the catcher (click target) and the preview frames (visual) are always pixel-identical and can't drift.

### Live-update wiring — free

`PreviewManager.lua:342-347` already reacts to EditCache changes by calling `PM.ShowPreview(activeFrameKey)`. Selecting a sort mode or order writes through EditCache → existing listener fires → preview re-renders with new layout. No new event plumbing.

## Files Touched

**New files**
- `Settings/Cards/Sorting.lua`
- (potentially) role-icon helper inside `Widgets/Dropdown.lua` or a sibling file

**Modified files**
- `Presets/Defaults.lua` — new keys in `raidConfig()` and `partyConfig()`
- `Units/Raid.lua` — spawn reads `Layout.GroupAttrs`
- `Units/Party.lua` — spawn reads `Layout.GroupAttrs`
- `Units/LiveUpdate/FrameConfigLayout.lua` — `GroupAttrs`, `ApplySortConfig`, `PLAYER_ROLES_ASSIGNED` handler
- `Widgets/Dropdown.lua` — new `CreateIconRowDropdown` factory (or sibling file)
- `Settings/FrameSettingsBuilder.lua` — register the Sorting card for raid and party panels
- `Preview/PreviewManager.lua` — sort-aware layout branch, `bucketByRole` helper
- `EditMode/ClickCatchers.lua` — bounds math shared with `PreviewManager`

## Acceptance Criteria

Binary pass/fail checks the implementation plan must verify:

1. **Default behavior unchanged.** Fresh install, no SavedVariables: raid renders as 8 group columns exactly like today. Party renders as index-sorted single column exactly like today.
2. **Upgraders unchanged.** Existing SavedVariables get `sortMode='group'` / `'index'` backfilled via `EnsureDefaults`; visible behavior is identical to pre-upgrade.
3. **Raid role sort, out-of-combat.** Select `By role` + `Tank → Healer → DPS` in settings → raid header reflows to three role columns (plus overflow columns for DPS in large raids) with no `/reload`.
4. **Raid role sort, in combat.** Same change while in combat → "Changes queued — will apply after combat" status appears → leaving combat drains the queue → layout updates.
5. **Role order change.** In `By role` mode, switch order from `Tank → Healer → DPS` to `Healer → Tank → DPS` → tanks and healers swap column positions with no `/reload`.
6. **Mid-session spec swap.** Raid in `By role` mode, a member changes spec out of combat → their frame moves to the new role column immediately without `/reload`.
7. **NONE-role unit visibility.** Open-world raid group with an unassigned member in `By role` mode → the unassigned member renders (in a NONE column appended after the chosen order), not hidden.
8. **Party independent from raid.** Party set to `By role` + `Healer → Tank → DPS`, raid set to `By role` + `Tank → Healer → DPS` → both layouts render independently with their own orders.
9. **Edit-mode preview parity.** Solo, entering edit mode on raid in `By role` mode → preview frames group fake units into role columns in the selected order. The preview is a visual approximation of what the real header would produce, not a pixel-perfect mirror of `SecureGroupHeader`'s internal math (preview frames are plain frames, not secure template children).
10. **ClickCatcher tracks preview.** The edit-mode click catcher's outline exactly wraps the preview frames in role mode — no visual drift, clicks land inside the outline everywhere.

## Non-Goals

- **Role-within-group sorting** (keeping `groupBy='GROUP'` but sub-sorting each column by role). Requires a custom `sortMethod='NAMELIST'` with a manually-maintained name list rebuilt on roster changes. Meaningfully more code, fiddly. Not shipping.
- **User-configurable `NONE` position.** NONE is appended automatically and not exposed in the UI. It is a transient state, not a user-facing concept.
- **Arena, boss, worldraid sorting.** These unit types use different headers and have different constraints. Out of scope for this spec.
- **Frame preview card on unit-frame settings panels / sticky-header rework.** Deferred to Spec B as noted in "Out of Scope" above.
