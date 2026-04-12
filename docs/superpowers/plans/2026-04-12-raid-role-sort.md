# Raid & Party Role-Based Sorting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `sortMode` (`group`/`role` for raid, `index`/`role` for party) and `roleOrder` config keys to raid and party frames, with a new Sorting settings card, combat-safe LiveUpdate path, `PLAYER_ROLES_ASSIGNED` re-sort, and sort-aware edit-mode previews.

**Architecture:** A new `F.LiveUpdate.FrameConfigLayout.GroupAttrs(config, unitType)` helper produces the correct `SecureGroupHeader` attribute set from config. Both `Units/Raid.lua` and `Units/Party.lua` call it at spawn time; a new `ApplySortConfig` LiveUpdate handler calls it at runtime and writes attributes via the existing `Shared.applyOrQueue` combat queue. A `PLAYER_ROLES_ASSIGNED` listener forces a re-sort when `sortMode == 'role'`. A new `Settings/Cards/Sorting.lua` card surfaces the controls via Framed's existing dropdown widget, extended with a new `CreateIconRowDropdown` factory that renders role icons per row. `PreviewManager`'s edit-mode group layout gets a role-aware branch and shares its bounds math with `ClickCatchers`.

**Tech Stack:** Lua 5.1 (WoW addon dialect), oUF (embedded), `SecureGroupHeaderTemplate` attributes, luacheck, manual in-game `/reload` verification.

**Spec:** `docs/superpowers/specs/2026-04-12-raid-role-sort-design.md`

---

## Verification Model

Framed has **no unit-test framework.** Verification for each task uses:

1. **`luacheck`** — static analysis (from repo root: `luacheck .`). Must report zero new warnings.
2. **Sync to WoW addon folder** — the user's manual sync workflow (rsync/cp the addon into `Interface/AddOns/Framed`).
3. **`/reload`** in-game — confirm no Lua errors in the chat frame or error popup.
4. **Manual check** — each task below specifies an explicit in-game test that maps to one or more spec acceptance criteria (`AC-N`).

"Failing test first" is substituted with "confirm the current behavior, then add the change, then confirm the new behavior." This keeps the discipline of verifying before and after without a test harness that doesn't exist.

Commit after each task per the repo convention (see memory: `feedback_commit_after_task.md`). Use the feature branch `working-testing`.

---

## File Structure

**New files**
- `Settings/Cards/Sorting.lua` — new settings card for sort mode + role order dropdowns

**Modified files**
- `Presets/Defaults.lua` — `raidConfig()` and `partyConfig()` add `sortMode`/`roleOrder`
- `Units/LiveUpdate/FrameConfigLayout.lua` — new `Layout` namespace with `GroupAttrs`, `ApplySortConfig`; new `CONFIG_CHANGED` branches; new `PLAYER_ROLES_ASSIGNED` handler
- `Units/LiveUpdate/FrameConfigShared.lua` — expose `combatQueueStatus` setter so the Sorting card can register a status line
- `Units/Raid.lua` — spawn consumes `Layout.GroupAttrs` instead of inline attributes
- `Units/Party.lua` — spawn consumes `Layout.GroupAttrs` instead of inline attributes
- `Widgets/Dropdown.lua` — new `Widgets.CreateIconRowDropdown(parent, width, iconsPerRow)` factory
- `Settings/FrameSettingsBuilder.lua` — register the Sorting card for raid and party panels
- `Framed.toc` — add `Settings/Cards/Sorting.lua` to the load list
- `Preview/PreviewManager.lua` — sort-aware layout branch + `bucketByRole` helper + shared bounds helper
- `EditMode/ClickCatchers.lua` — `getGroupBounds` delegates to the shared `PreviewManager` helper

---

## Task 1: Add `sortMode` / `roleOrder` Defaults

**Files:**
- Modify: `Presets/Defaults.lua` (`raidConfig()` ~line 296, `partyConfig()` ~line 278)

- [ ] **Step 1: Read the current `raidConfig()` and `partyConfig()` blocks**

Open `Presets/Defaults.lua` and confirm `raidConfig()` currently ends with:

```lua
local function raidConfig()
    local c = baseUnitConfig()
    c.width       = 72
    c.height      = 36
    c.spacing     = 2
    c.orientation = 'vertical'
    c.anchorPoint = 'TOPLEFT'
    c.position    = { x = 40, y = -48, anchor = 'TOPLEFT' }
    c.health.showText   = true
    c.health.textFormat = 'percent'
    c.name.fontSize = C.Font.sizeSmall
    c.statusIcons.combat  = false
    c.statusIcons.resting = false
    c.statusIcons.raidRole = false
    return c
end
```

And `partyConfig()`:

```lua
local function partyConfig()
    local c = baseUnitConfig()
    c.width       = 120
    c.height      = 36
    c.spacing     = 2
    c.orientation = 'vertical'
    c.anchorPoint = 'TOPLEFT'
    c.position    = { x = 40, y = -48, anchor = 'TOPLEFT' }
    c.health.showText   = true
    c.health.textFormat = 'percent'
    c.name.fontSize = C.Font.sizeSmall
    c.threat = defaultThreat()
    c.statusIcons.combat  = false
    c.statusIcons.resting = false
    -- ... more lines down to `return c`
```

- [ ] **Step 2: Add the two keys to `raidConfig()`**

Add after the `c.position = ...` line and before `c.health.showText = true`:

```lua
    c.sortMode  = 'group'
    c.roleOrder = 'TANK,HEALER,DAMAGER'
```

Final block:

```lua
local function raidConfig()
    local c = baseUnitConfig()
    c.width       = 72
    c.height      = 36
    c.spacing     = 2
    c.orientation = 'vertical'
    c.anchorPoint = 'TOPLEFT'
    c.position    = { x = 40, y = -48, anchor = 'TOPLEFT' }
    c.sortMode    = 'group'
    c.roleOrder   = 'TANK,HEALER,DAMAGER'
    c.health.showText   = true
    c.health.textFormat = 'percent'
    c.name.fontSize = C.Font.sizeSmall
    c.statusIcons.combat  = false
    c.statusIcons.resting = false
    c.statusIcons.raidRole = false
    return c
end
```

- [ ] **Step 3: Add the two keys to `partyConfig()`**

Add the same pair after the `c.position = ...` line:

```lua
    c.sortMode  = 'index'
    c.roleOrder = 'HEALER,TANK,DAMAGER'
```

- [ ] **Step 4: Run luacheck**

```bash
luacheck Presets/Defaults.lua
```

Expected: no new warnings. (Existing warnings in the file, if any, are unchanged.)

- [ ] **Step 5: Manual verification** *(AC-1, AC-2)*

Sync to WoW addon folder, `/reload`, then in the chat frame:

```
/run print('raid sortMode:', F.StyleBuilder.GetConfig('raid').sortMode)
/run print('raid roleOrder:', F.StyleBuilder.GetConfig('raid').roleOrder)
/run print('party sortMode:', F.StyleBuilder.GetConfig('party').sortMode)
/run print('party roleOrder:', F.StyleBuilder.GetConfig('party').roleOrder)
```

Expected output:
```
raid sortMode: group
raid roleOrder: TANK,HEALER,DAMAGER
party sortMode: index
party roleOrder: HEALER,TANK,DAMAGER
```

Visual: raid and party frames look identical to before (no spawn-path changes yet).

- [ ] **Step 6: Commit and push**

```bash
git add Presets/Defaults.lua
git commit -m "$(cat <<'EOF'
Add sortMode/roleOrder defaults for raid and party

Raid defaults to sortMode='group' preserving today's behavior.
Party defaults to sortMode='index' (its current no-groupBy state).
Role order defaults: raid T/H/D, party H/T/D (dungeon-friendly).

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 2: Add `Layout.GroupAttrs` Helper (Pure)

**Files:**
- Modify: `Units/LiveUpdate/FrameConfigLayout.lua` (add new namespace + helper at top)

- [ ] **Step 1: Read the current file structure**

`FrameConfigLayout.lua` currently has no exported namespace — it only registers one `CONFIG_CHANGED` handler. The first 14 lines are imports. We are going to add a `Layout` table above the handler, export it at the bottom, and use it from the handler in later tasks.

- [ ] **Step 2: Add `Layout` table and `GroupAttrs` helper**

Insert after line 14 (after the imports block), before the `suppressPositionUpdate` line:

```lua
-- ============================================================
-- Layout namespace — exposed as F.LiveUpdate.FrameConfigLayout
-- ============================================================

local Layout = {}

--- Produce the SecureGroupHeader attribute set for a given group
--- unit type and its config. Consumed by Units/Raid.lua and
--- Units/Party.lua spawn paths, and by Layout.ApplySortConfig at
--- runtime.
--- @param config table  Unit config from F.StyleBuilder.GetConfig
--- @param unitType string  'raid' or 'party'
--- @return table  Map of SecureGroupHeader attribute → value
function Layout.GroupAttrs(config, unitType)
    if(unitType == 'raid' and config.sortMode == 'role') then
        return {
            sortMethod     = 'INDEX',
            groupBy        = 'ASSIGNEDROLE',
            groupingOrder  = config.roleOrder .. ',NONE',
            maxColumns     = 10,
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
            maxColumns     = 4,
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

- [ ] **Step 3: Export the `Layout` table at the bottom of the file**

Add at the very end of `FrameConfigLayout.lua`, after the existing `end, 'LiveUpdate.FrameConfigLayout')` line:

```lua

-- ============================================================
-- Export
-- ============================================================

F.LiveUpdate.FrameConfigLayout = Layout
```

- [ ] **Step 4: Run luacheck**

```bash
luacheck Units/LiveUpdate/FrameConfigLayout.lua
```

Expected: no new warnings. (`Layout` is used only by the export line for now; that's fine — it's not unused because it's assigned to a table field.)

- [ ] **Step 5: Manual verification**

Sync + `/reload`. Test:

```
/run print(type(F.LiveUpdate.FrameConfigLayout.GroupAttrs))
```

Expected: `function`

```
/run local a = F.LiveUpdate.FrameConfigLayout.GroupAttrs({ sortMode = 'group' }, 'raid') print(a.groupBy, a.groupingOrder)
```

Expected: `GROUP    1,2,3,4,5,6,7,8`

```
/run local a = F.LiveUpdate.FrameConfigLayout.GroupAttrs({ sortMode = 'role', roleOrder = 'TANK,HEALER,DAMAGER' }, 'raid') print(a.groupBy, a.groupingOrder)
```

Expected: `ASSIGNEDROLE    TANK,HEALER,DAMAGER,NONE`

```
/run local a = F.LiveUpdate.FrameConfigLayout.GroupAttrs({ sortMode = 'index' }, 'party') print(a.sortMethod, a.maxColumns)
```

Expected: `INDEX    1`

```
/run local a = F.LiveUpdate.FrameConfigLayout.GroupAttrs({ sortMode = 'role', roleOrder = 'HEALER,TANK,DAMAGER' }, 'party') print(a.groupBy, a.groupingOrder, a.maxColumns)
```

Expected: `ASSIGNEDROLE    HEALER,TANK,DAMAGER,NONE    4`

Visual: frames look identical — helper is pure, no consumers yet.

- [ ] **Step 6: Commit and push**

```bash
git add Units/LiveUpdate/FrameConfigLayout.lua
git commit -m "$(cat <<'EOF'
Add Layout.GroupAttrs helper for group-header attribute shape

Pure function: maps (config, unitType) to the SecureGroupHeader
attribute set. Both spawn paths and the future LiveUpdate handler
will consume it. NONE is appended to roleOrder at apply time so
unassigned-role units always render.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 3: Wire Raid & Party Spawn to `GroupAttrs`

**Files:**
- Modify: `Units/Raid.lua` (SpawnHeader call at lines 47-65)
- Modify: `Units/Party.lua` (SpawnHeader call at lines 196-211)

- [ ] **Step 1: Read the current `Units/Raid.lua` `Spawn()` function**

Confirm lines 22-75 match the existing structure: orientation/anchor-driven `point`, `xOff`, `yOff`, `colAnchor` computation, then a `SpawnHeader` call with inline attributes.

- [ ] **Step 2: Replace Raid.lua's inline sort attributes with `GroupAttrs`**

In `Units/Raid.lua`, replace the existing `SpawnHeader` call (lines 47-65) with:

```lua
    local attrs = F.LiveUpdate.FrameConfigLayout.GroupAttrs(config, 'raid')

    local header = oUF:SpawnHeader(
        'FramedRaidHeader',
        nil,
        'showRaid', true,
        'showParty', false,
        'showSolo', false,
        'point', point,
        'xOffset', xOff,
        'yOffset', yOff,
        'columnSpacing', spacing,
        'columnAnchorPoint', colAnchor,
        'maxColumns', attrs.maxColumns,
        'unitsPerColumn', attrs.unitsPerColumn,
        'sortMethod', attrs.sortMethod,
        'groupBy', attrs.groupBy,
        'groupingOrder', attrs.groupingOrder,
        'initial-width', config.width,
        'initial-height', config.height
    )
```

The five attributes that came from `attrs` are exactly what was hardcoded before in group mode (`INDEX`, `GROUP`, `1,2,3,4,5,6,7,8`, `8`, `5`). Default raid config has `sortMode='group'`, so `GroupAttrs` returns those same values and behavior is byte-identical.

- [ ] **Step 3: Replace Party.lua's inline sort attributes with `GroupAttrs`**

In `Units/Party.lua`, replace the existing `SpawnHeader` call (lines 196-211) with:

```lua
    local attrs = F.LiveUpdate.FrameConfigLayout.GroupAttrs(config, 'party')

    local header = oUF:SpawnHeader(
        'FramedPartyHeader',
        nil,
        'showParty', true,
        'showPlayer', true,
        'showSolo', false,
        'point', point,
        'xOffset', xOff,
        'yOffset', yOff,
        'columnSpacing', spacing,
        'columnAnchorPoint', colAnchor,
        'maxColumns', attrs.maxColumns,
        'unitsPerColumn', attrs.unitsPerColumn,
        'sortMethod', attrs.sortMethod,
        'groupBy', attrs.groupBy,
        'groupingOrder', attrs.groupingOrder,
        'initial-width', config.width,
        'initial-height', config.height
    )
```

Note: Party now passes `columnSpacing` (previously absent) so role mode's sub-columns have spacing between them. In index mode (`maxColumns=1`) the attribute is harmless — no wrapping ever happens.

Note: Party now passes `groupBy` and `groupingOrder`. In index mode, `GroupAttrs` returns these as `nil`, and `SpawnHeader` ignores nil attribute values (it only sets the keys it receives non-nil for). This behavior is standard oUF and works with default config unchanged.

**Important:** Before saving, verify that `oUF:SpawnHeader` tolerates `nil` attribute values. Check by searching the oUF source:

```bash
grep -n "SpawnHeader" Libs/oUF/elements/header.lua 2>/dev/null || grep -n "SpawnHeader" Libs/oUF/headers.lua 2>/dev/null
```

If `SpawnHeader` does NOT tolerate nil values (e.g., it passes them straight to `SetAttribute`), then the party index-mode branch of `GroupAttrs` must return an empty-string or safe default for `groupBy`/`groupingOrder`, or the party spawn path needs to conditionally include these attributes. The current spec assumes nil is tolerated — if it isn't, adjust the Party.lua spawn to wrap the call in a helper that omits nil pairs.

- [ ] **Step 4: Run luacheck**

```bash
luacheck Units/Raid.lua Units/Party.lua
```

Expected: no new warnings.

- [ ] **Step 5: Manual verification — raid unchanged** *(AC-1)*

Sync + `/reload` while solo (no party/raid). In a party or raid, confirm:

1. Raid frames spawn and render exactly as before — 8 group columns, 5 per column.
2. Party frames spawn and render exactly as before — single column of up to 5.
3. No Lua errors in chat or error popup.

Use:
```
/run print(F.Units.Raid.header:GetAttribute('groupBy'))
/run print(F.Units.Raid.header:GetAttribute('groupingOrder'))
/run print(F.Units.Party.header:GetAttribute('sortMethod'))
/run print(F.Units.Party.header:GetAttribute('maxColumns'))
```

Expected:
- `GROUP`
- `1,2,3,4,5,6,7,8`
- `INDEX`
- `1`

- [ ] **Step 6: Commit and push**

```bash
git add Units/Raid.lua Units/Party.lua
git commit -m "$(cat <<'EOF'
Spawn raid and party headers via Layout.GroupAttrs

Both spawn paths now consume the shared attribute helper instead of
hardcoding sortMethod/groupBy/groupingOrder/maxColumns. Default
config yields byte-identical SecureGroupHeader attributes, so this
is a refactor with no behavior change.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 4: Add `ApplySortConfig` LiveUpdate Handler

**Files:**
- Modify: `Units/LiveUpdate/FrameConfigLayout.lua` (add `Layout.ApplySortConfig` + `CONFIG_CHANGED` branch)

This task produces the first end-to-end working slice: `sortMode` / `roleOrder` can be flipped via `F.Config:Set(...)` and the header reflows live. No UI yet — that comes in Task 7.

- [ ] **Step 1: Add `Layout.ApplySortConfig` below `Layout.GroupAttrs`**

In `Units/LiveUpdate/FrameConfigLayout.lua`, add immediately after the `Layout.GroupAttrs` function (before the `suppressPositionUpdate` local):

```lua
--- Push the current sort config to a spawned group header.
--- Re-applies every attribute that GroupAttrs controls, so that
--- switching sortMode from 'group' to 'role' or back produces the
--- correct layout. All writes go through Shared.applyOrQueue to
--- respect combat lockdown.
---
--- Party pets are separate oUF spawns anchored to party header
--- children by unit attribute (see Units/Party.lua AnchorPetFrames).
--- When the secure header re-sorts, its children have their `unit`
--- attribute reassigned, so any pet frame SetPoint'd to a specific
--- child will now visually sit next to the WRONG party member.
--- We re-run AnchorPetFrames on the next frame (C_Timer.After(0))
--- so the secure template has time to finish its attribute-driven
--- re-layout before we re-resolve owners. AnchorPetFrames only
--- calls ClearAllPoints/SetPoint, which are not combat-protected
--- on insecure frames, so this is safe during the combat-queued
--- replay as well — by the time applyOrQueue drains, we're already
--- out of combat.
--- @param unitType string  'raid' or 'party'
function Layout.ApplySortConfig(unitType)
    local header = getGroupHeader(unitType)
    if(not header) then return end

    local config = F.StyleBuilder.GetConfig(unitType)
    local attrs  = Layout.GroupAttrs(config, unitType)

    applyOrQueue(header, 'sortMethod',     attrs.sortMethod)
    applyOrQueue(header, 'groupBy',        attrs.groupBy or '')
    applyOrQueue(header, 'groupingOrder',  attrs.groupingOrder or '')
    applyOrQueue(header, 'maxColumns',     attrs.maxColumns)
    applyOrQueue(header, 'unitsPerColumn', attrs.unitsPerColumn)

    -- Re-anchor party pets after the secure header resettles.
    -- C_Timer.After(0, ...) defers one frame so SecureGroupHeader_Update
    -- has finished reassigning unit attributes to its children.
    if(unitType == 'party' and F.Units.Party and F.Units.Party.AnchorPetFrames) then
        C_Timer.After(0, F.Units.Party.AnchorPetFrames)
    end
end
```

**Why `or ''` on `groupBy` / `groupingOrder`:** in index mode `GroupAttrs` returns these as nil; `SetAttribute` with an empty string clears the attribute, which is what we want (no grouping).

**Why the deferred pet re-anchor:** `SecureGroupHeaderTemplate` re-sorts by reassigning the `unit` attribute on its existing child buttons (not by moving which physical frame holds which unit). Party pet frames are `SetPoint`'d to whichever party header child currently holds `unit='partyN'` (`Units/Party.lua:283-305`), so after a sort change, pet1 is still parented to the child that used to be party1 — which now displays a different party member. `AnchorPetFrames` re-runs `findOwnerFrame(header, 'partyN')` and repoints; deferring one frame via `C_Timer.After(0, ...)` ensures the secure template has finished its attribute pass before we re-resolve owners.

- [ ] **Step 2: Add a new branch in the `CONFIG_CHANGED` handler**

Still in `FrameConfigLayout.lua`, inside the existing `F.EventBus:Register('CONFIG_CHANGED', ...)` handler, add a new `if` branch just before the existing `-- Group layout: spacing, orientation, anchorPoint` branch (currently around line 177):

```lua
    -- Sort config: sortMode, roleOrder
    if(key == 'sortMode' or key == 'roleOrder') then
        if(not GROUP_TYPES[unitType]) then return end
        Layout.ApplySortConfig(unitType)
        return
    end
```

- [ ] **Step 3: Run luacheck**

```bash
luacheck Units/LiveUpdate/FrameConfigLayout.lua
```

Expected: no new warnings.

- [ ] **Step 4: Manual verification — flip raid to role mode live** *(AC-3)*

Sync + `/reload` inside a raid group of at least 5 people (a pug, a guild run, or the Training Dummies in Stormwind work — but the `/reload` test requires a real group to see reflow). If you can't get into a real group, Acceptance Criterion 3 is a hard pass/fail during playtesting and can be deferred to the final sweep.

Run:
```
/run F.Config:Set('presets.' .. F.AutoSwitch.GetCurrentPreset() .. '.unitConfigs.raid.sortMode', 'role')
```

Expected: raid frames immediately reflow into three role columns (Tank, Healer, DPS, in that order per the default `roleOrder`). No `/reload` needed.

Switch back:
```
/run F.Config:Set('presets.' .. F.AutoSwitch.GetCurrentPreset() .. '.unitConfigs.raid.sortMode', 'group')
```

Expected: raid frames reflow back to 8 group columns.

Switch role order:
```
/run F.Config:Set('presets.' .. F.AutoSwitch.GetCurrentPreset() .. '.unitConfigs.raid.sortMode', 'role')
/run F.Config:Set('presets.' .. F.AutoSwitch.GetCurrentPreset() .. '.unitConfigs.raid.roleOrder', 'HEALER,TANK,DAMAGER')
```

Expected: columns swap so healers come first.

- [ ] **Step 5: Manual verification — party pets follow their owners across a sort change** *(AC-3)*

Get into a party with at least one hunter/warlock/DK/mage (anyone with a persistent pet). With `partyPets.enabled = true` (the default), flip party to role mode:

```
/run F.Config:Set('presets.' .. F.AutoSwitch.GetCurrentPreset() .. '.unitConfigs.party.sortMode', 'role')
```

Expected: each pet frame visually sits next to its owner's party frame in the new role-sorted layout. No pet frames stranded next to the wrong character. If you see a pet next to the wrong owner, `C_Timer.After(0, AnchorPetFrames)` didn't fire late enough — bump to `C_Timer.After(0.05, ...)` and retest.

Switch back:
```
/run F.Config:Set('presets.' .. F.AutoSwitch.GetCurrentPreset() .. '.unitConfigs.party.sortMode', 'index')
```

Expected: pets follow their owners back to the index layout.

- [ ] **Step 6: Commit and push**

```bash
git add Units/LiveUpdate/FrameConfigLayout.lua
git commit -m "$(cat <<'EOF'
Add Layout.ApplySortConfig LiveUpdate handler

Routes sortMode/roleOrder CONFIG_CHANGED events through
Shared.applyOrQueue so combat lockdown is respected. Writes five
SecureGroupHeader attributes in one batch; empty strings clear
groupBy/groupingOrder for party index mode. For party, defers
AnchorPetFrames by one frame so pets follow their owners after
the secure header finishes reassigning unit attributes.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 5: Add `PLAYER_ROLES_ASSIGNED` Handler

**Files:**
- Modify: `Units/LiveUpdate/FrameConfigLayout.lua` (add new EventBus registration)

- [ ] **Step 1: Add the handler at the bottom of `FrameConfigLayout.lua`**

Insert after the existing `F.EventBus:Register('CONFIG_CHANGED', ..., 'LiveUpdate.FrameConfigLayout')` call and before the `F.LiveUpdate.FrameConfigLayout = Layout` export:

```lua
-- ============================================================
-- PLAYER_ROLES_ASSIGNED: force a re-sort when sortMode == 'role'
-- ============================================================
--
-- SecureGroupHeaderTemplate watches GROUP_ROSTER_UPDATE but not
-- PLAYER_ROLES_ASSIGNED, so a spec/role swap that doesn't change
-- roster membership leaves the header with stale role assignments.
-- Re-running ApplySortConfig re-writes groupingOrder which forces
-- the secure template to re-evaluate its sort pass.
--
-- Spec/role changes are out-of-combat only in retail WoW, so this
-- always takes the immediate-apply branch of applyOrQueue.

F.EventBus:Register('PLAYER_ROLES_ASSIGNED', function()
    for _, unitType in next, { 'raid', 'party' } do
        local config = F.StyleBuilder.GetConfig(unitType)
        if(config.sortMode == 'role') then
            Layout.ApplySortConfig(unitType)
        end
    end
end, 'LiveUpdate.RoleResort')
```

- [ ] **Step 2: Run luacheck**

```bash
luacheck Units/LiveUpdate/FrameConfigLayout.lua
```

Expected: no new warnings.

- [ ] **Step 3: Manual verification — mid-session role swap** *(AC-6)*

This check requires at least one other player. Get into a party with a friend who can dual-spec or swap talents. Put raid in role mode:

```
/run F.Config:Set('presets.' .. F.AutoSwitch.GetCurrentPreset() .. '.unitConfigs.raid.sortMode', 'role')
```

Have the other player:
1. Confirm current role via `/run print(UnitGroupRolesAssigned('player'))`
2. Swap talents or explicitly set role (right-click portrait → Set Role → other role)

Watch their frame in your raid. Expected: their frame **moves to the new role column immediately**, no `/reload`.

Fallback verification if no human available: set your own sortMode and force a role change via the talent UI, observe your own player frame in the raid column.

**Party pet verification:** repeat the same test in party with a pet-class friend, with party in role mode. When they swap specs, expected: their frame moves to the new role column AND their pet (if they still have one) reappears next to their new position. Pet re-anchoring flows through `ApplySortConfig` — no additional wiring needed in this handler.

- [ ] **Step 4: Commit and push**

```bash
git add Units/LiveUpdate/FrameConfigLayout.lua
git commit -m "$(cat <<'EOF'
Re-sort group headers on PLAYER_ROLES_ASSIGNED

SecureGroupHeaderTemplate does not watch role changes, so a spec
swap mid-session leaves the header with stale role assignments.
This handler re-runs ApplySortConfig for any group in role mode,
forcing an immediate reflow out of combat. No /reload required.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 6: Add `Widgets.CreateIconRowDropdown` Factory

**Files:**
- Modify: `Widgets/Dropdown.lua` (add new factory function at the end of the file)

- [ ] **Step 1: Read the existing row-decorator support**

`Widgets/Dropdown.lua:464` already supports `item._decorateRow(row, item)` as a per-item callback during `OpenDropdownList`. The existing `row._swatch` texture (line 323) is a single 20×12 texture at `LEFT +4,0`. For three-icon role previews, we need a new factory that creates additional textures on demand via the `_decorateRow` hook and stores them on `row._customDecorations` (already referenced at lines 418-422 as the reset list).

- [ ] **Step 2: Add a helper to find/create custom decoration textures on a row**

Add near the top of `Dropdown.lua`, after the existing forward declarations (around line 36):

```lua
-- ── Icon-row decoration helpers ─────────────────────────────

--- Lazily create `count` icon textures on `row`, cached in
--- row._customDecorations. Returns the array of textures.
--- @param row Frame
--- @param count number
--- @param iconSize number
--- @return table  Array of count textures, all shown
local function ensureCustomDecorations(row, count, iconSize)
    row._customDecorations = row._customDecorations or {}
    local decorations = row._customDecorations
    for i = 1, count do
        local tex = decorations[i]
        if(not tex) then
            tex = row:CreateTexture(nil, 'OVERLAY')
            decorations[i] = tex
        end
        tex:SetSize(iconSize, iconSize)
        tex:Show()
    end
    return decorations
end
```

- [ ] **Step 3: Add the `CreateIconRowDropdown` factory**

Append at the very end of `Widgets/Dropdown.lua`:

```lua
-- ============================================================
-- CreateIconRowDropdown — dropdown with N inline icons per row
-- ============================================================
--
-- Items supply `icons` as an array of { texture, texCoord, label }
-- tuples where `texture` is a path string, `texCoord` is
-- { left, right, top, bottom }, and `label` is the text that goes
-- after the icons (optional; if the item also has `text`, that is
-- used as the primary label instead).
--
-- Layout per row: icon1, icon2, ... iconN, text
-- Icon size matches label font size (16px default).

local ICON_ROW_SIZE    = 16
local ICON_ROW_PADDING = 4
local ICON_ROW_GAP     = 2

--- Factory for a dropdown button whose list rows render a fixed
--- number of inline icons (with tex coords) followed by the label.
--- Shares the singleton dropdown list with Widgets.CreateDropdown.
--- @param parent Frame
--- @param width number
--- @param iconsPerRow number
--- @return Frame dropdown
function Widgets.CreateIconRowDropdown(parent, width, iconsPerRow)
    local dropdown = Widgets.CreateDropdown(parent, width)

    -- Replace the default SetItems with a version that attaches a
    -- per-item _decorateRow callback before delegating.
    local originalSetItems = dropdown.SetItems
    dropdown.SetItems = function(self, items)
        for _, item in next, items do
            item._decorateRow = function(row, itm)
                local decorations = ensureCustomDecorations(row, iconsPerRow, ICON_ROW_SIZE)
                local x = ICON_ROW_PADDING
                for i = 1, iconsPerRow do
                    local iconSpec = itm.icons and itm.icons[i]
                    local tex = decorations[i]
                    if(iconSpec and iconSpec.texture) then
                        tex:SetTexture(iconSpec.texture)
                        local tc = iconSpec.texCoord
                        if(tc) then
                            tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
                        else
                            tex:SetTexCoord(0, 1, 0, 1)
                        end
                        tex:ClearAllPoints()
                        tex:SetPoint('LEFT', row, 'LEFT', x, 0)
                        tex:Show()
                        x = x + ICON_ROW_SIZE + ICON_ROW_GAP
                    else
                        tex:Hide()
                    end
                end
                -- Shift label to start after the icons
                row._label:ClearAllPoints()
                row._label:SetPoint('LEFT',  row, 'LEFT', x, 0)
                row._label:SetPoint('RIGHT', row, 'RIGHT', -4, 0)
                -- Hide the default swatch since this widget uses custom textures
                row._swatch:Hide()
            end
        end
        originalSetItems(self, items)
    end

    return dropdown
end
```

- [ ] **Step 4: Run luacheck**

```bash
luacheck Widgets/Dropdown.lua
```

Expected: no new warnings.

- [ ] **Step 5: Manual verification — smoke test the factory**

Sync + `/reload`. In chat:

```
/run local d = F.Widgets.CreateIconRowDropdown(UIParent, 200, 3) d:SetPoint('CENTER') d:SetItems({ { text = 'Test', value = 't', icons = { { texture = 'Interface\\Icons\\Spell_Holy_AuraOfLight', texCoord = {0,1,0,1} }, { texture = 'Interface\\Icons\\Spell_Holy_DivineIllumination', texCoord = {0,1,0,1} }, { texture = 'Interface\\Icons\\Spell_Holy_FlashHeal', texCoord = {0,1,0,1} } } } }) d:SetValue('t')
```

Expected: a dropdown button appears at screen center. Clicking it shows a list with one row that has three small icons followed by the text "Test."

Clean up: `/run for _, f in next, { UIParent:GetChildren() } do if(f.__isDropdown) then f:Hide() end end` — or just `/reload`.

- [ ] **Step 6: Commit and push**

```bash
git add Widgets/Dropdown.lua
git commit -m "$(cat <<'EOF'
Add Widgets.CreateIconRowDropdown factory

Extends the existing Dropdown widget with a per-row decorator
that renders N inline icon textures (each with its own tex coords)
followed by the label. Shares the singleton list infrastructure
with CreateDropdown/CreateTextureDropdown. Consumers pass
items = { { text, value, icons = { { texture, texCoord }, ... } } }.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 7: Create `Settings/Cards/Sorting.lua` + Registration

**Files:**
- Create: `Settings/Cards/Sorting.lua`
- Modify: `Framed.toc` (add the new card file to the load list)
- Modify: `Settings/FrameSettingsBuilder.lua` (register the Sorting card for raid/party)
- Modify: `Units/LiveUpdate/FrameConfigShared.lua` (expose `combatQueueStatus` setter)

This is the largest task in the plan. It produces the end-user UI.

- [ ] **Step 1: Expose a `combatQueueStatus` setter on Shared**

`FrameConfigShared.lua:20` currently has:

```lua
local combatQueueStatus -- luacheck: ignore 221 (set by future settings UI)
```

We need a way for the Sorting card to register its status text. Replace lines 18-42 (the `pendingGroupChanges` + `combatQueueStatus` + `applyOrQueue` + `PLAYER_REGEN_ENABLED` block) with:

```lua
-- ============================================================
-- Combat queue for group layout (SetAttribute locked in combat)
-- ============================================================

local pendingGroupChanges = {}
local combatQueueStatus

function Shared.SetCombatQueueStatus(frame)
    combatQueueStatus = frame
    if(frame) then
        frame:Hide()
    end
end

function Shared.applyOrQueue(header, attr, value)
    if(InCombatLockdown()) then
        pendingGroupChanges[#pendingGroupChanges + 1] = { header, attr, value }
        if(combatQueueStatus) then
            combatQueueStatus:SetText('Changes queued — will apply after combat')
            combatQueueStatus:Show()
        end
    else
        header:SetAttribute(attr, value)
    end
end

F.EventBus:Register('PLAYER_REGEN_ENABLED', function()
    for _, change in next, pendingGroupChanges do
        change[1]:SetAttribute(change[2], change[3])
    end
    wipe(pendingGroupChanges)
    if(combatQueueStatus) then
        combatQueueStatus:Hide()
    end
end, 'LiveUpdate.CombatQueue')
```

The only substantive change: `Shared.SetCombatQueueStatus(frame)` replaces the old "set by future settings UI" placeholder comment, and the `local combatQueueStatus` no longer needs the `luacheck: ignore 221` annotation (it is now read via the setter).

- [ ] **Step 2: Run luacheck on FrameConfigShared.lua**

```bash
luacheck Units/LiveUpdate/FrameConfigShared.lua
```

Expected: no new warnings. (If luacheck complains about the removed `ignore` comment, that's fine — the comment was a hint to an older luacheck rule, not a real issue.)

- [ ] **Step 3: Create `Settings/Cards/Sorting.lua`**

Create the file with:

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}

-- ============================================================
-- Sort mode dropdown labels per unit type
-- ============================================================

local MODE_ITEMS = {
    raid = {
        { text = 'By raid group',  value = 'group' },
        { text = 'By role',        value = 'role' },
    },
    party = {
        { text = 'By join order',  value = 'index' },
        { text = 'By role',        value = 'role' },
    },
}

-- ============================================================
-- Role-order presets — text label + ordered role tokens
-- ============================================================

local ROLE_ORDER_PRESETS = {
    { text = 'Tank, Healer, DPS',   value = 'TANK,HEALER,DAMAGER',   roles = { 'TANK',    'HEALER',  'DAMAGER' } },
    { text = 'Tank, DPS, Healer',   value = 'TANK,DAMAGER,HEALER',   roles = { 'TANK',    'DAMAGER', 'HEALER'  } },
    { text = 'Healer, Tank, DPS',   value = 'HEALER,TANK,DAMAGER',   roles = { 'HEALER',  'TANK',    'DAMAGER' } },
    { text = 'Healer, DPS, Tank',   value = 'HEALER,DAMAGER,TANK',   roles = { 'HEALER',  'DAMAGER', 'TANK'    } },
    { text = 'DPS, Tank, Healer',   value = 'DAMAGER,TANK,HEALER',   roles = { 'DAMAGER', 'TANK',    'HEALER'  } },
    { text = 'DPS, Healer, Tank',   value = 'DAMAGER,HEALER,TANK',   roles = { 'DAMAGER', 'HEALER',  'TANK'    } },
}

-- ============================================================
-- Build dropdown items with inline role-icon previews
-- ============================================================

local function buildRoleOrderItems()
    local style = F.Config:Get('general.roleIconStyle') or 2
    local texturePath = F.Elements.RoleIcon.GetTexturePath(style)
    local texCoords   = F.Elements.RoleIcon.TEXCOORDS

    local items = {}
    for i, preset in next, ROLE_ORDER_PRESETS do
        local icons = {}
        for j, role in next, preset.roles do
            icons[j] = {
                texture  = texturePath,
                texCoord = texCoords[role],
            }
        end
        items[i] = {
            text  = preset.text,
            value = preset.value,
            icons = icons,
        }
    end
    return items
end

-- ============================================================
-- Card builder
-- ============================================================

function F.SettingsCards.Sorting(parent, width, unitType, getConfig, setConfig)
    local card, inner, cardY = Widgets.StartCard(parent, width, 0)
    local widgetW = width - Widgets.CARD_PADDING * 2

    -- ── Sort mode dropdown ──────────────────────────────────
    cardY = B.PlaceHeading(inner, 'Sort Mode', 4, cardY)

    local modeDropdown = Widgets.CreateDropdown(inner, widgetW)
    modeDropdown:SetItems(MODE_ITEMS[unitType] or MODE_ITEMS.raid)
    modeDropdown:SetValue(getConfig('sortMode'))
    cardY = B.PlaceWidget(modeDropdown, inner, cardY, B.DROPDOWN_H)

    -- ── Role order dropdown (icon row variant) ──────────────
    cardY = B.PlaceHeading(inner, 'Role Order', 4, cardY)

    local orderDropdown = Widgets.CreateIconRowDropdown(inner, widgetW, 3)
    orderDropdown:SetItems(buildRoleOrderItems())
    orderDropdown:SetValue(getConfig('roleOrder'))
    cardY = B.PlaceWidget(orderDropdown, inner, cardY, B.DROPDOWN_H)

    -- Greying: disable role-order dropdown when mode isn't 'role'
    local function refreshOrderEnabled()
        local isRole = (getConfig('sortMode') == 'role')
        if(orderDropdown.SetEnabled) then
            orderDropdown:SetEnabled(isRole)
        elseif(isRole) then
            orderDropdown:SetAlpha(1.0)
        else
            orderDropdown:SetAlpha(0.4)
        end
    end
    refreshOrderEnabled()

    modeDropdown:SetOnSelect(function(value)
        setConfig('sortMode', value)
        refreshOrderEnabled()
    end)
    orderDropdown:SetOnSelect(function(value)
        setConfig('roleOrder', value)
    end)

    -- ── Combat queue status line ────────────────────────────
    local statusText = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
    statusText:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cardY)
    statusText:SetJustifyH('LEFT')
    statusText:SetText('')
    statusText:Hide()
    F.LiveUpdate.FrameConfigShared.SetCombatQueueStatus(statusText)
    cardY = cardY - B.CHECK_H - C.Spacing.normal

    Widgets.EndCard(card, inner, cardY)
    return card
end
```

**Note on `SetEnabled`:** if `Widgets.CreateDropdown` does not expose `SetEnabled`, the alpha fallback is the visible-but-unclickable state. The plan executor should confirm during Step 4 below which the existing widget supports. If neither works, a third fallback is to hide the dropdown entirely and only show it when mode is 'role' — acceptable UX either way.

- [ ] **Step 4: Add the card to `Framed.toc`**

In `Framed.toc`, find the block where `Settings/Cards/*.lua` files are listed (search for `Settings/Cards/PositionAndLayout.lua`) and add after it:

```
Settings/Cards/Sorting.lua
```

- [ ] **Step 5: Register the Sorting card in `FrameSettingsBuilder.lua`**

In `Settings/FrameSettingsBuilder.lua`, find the block of `grid:AddCard(...)` calls (around line 165). After the `position` card registration (line 165), add:

```lua
    if(unitType == 'party' or unitType == 'raid') then
        grid:AddCard('sorting', 'Sorting', F.SettingsCards.Sorting, { unitType, getConfig, setConfig })
    end
```

This places the Sorting card right after Position & Layout, keeping related layout/grouping controls together.

- [ ] **Step 6: Run luacheck**

```bash
luacheck Settings/Cards/Sorting.lua Settings/FrameSettingsBuilder.lua Units/LiveUpdate/FrameConfigShared.lua
```

Expected: no new warnings.

- [ ] **Step 7: Manual verification — card renders and works** *(AC-3, AC-5, AC-8)*

Sync + `/reload`. Open Framed settings (`/framed` or the minimap icon), navigate to the raid settings panel. Expected:

1. A "Sorting" card appears directly below "Position & Layout".
2. The card shows two dropdowns: "Sort Mode" (with "By raid group" / "By role") and "Role Order" (with 6 options, each showing three role icons).
3. "Role Order" is greyed / alpha-dimmed while mode is "By raid group".
4. Selecting "By role" in mode → "Role Order" becomes interactive → dropdown opens and shows six rows with inline role icons.
5. Selecting a role order → raid frames (if in a raid) immediately reflow; the stored value is persisted.
6. Navigate to the party settings panel (via preset sidebar or re-open settings in a party preset). Expected: the same Sorting card with "By join order" / "By role" mode options.
7. Confirm raid and party settings are independent: set raid to `Tank, Healer, DPS` in role mode, party to `Healer, Tank, DPS` in role mode → both frames render independently with their own orders.

If `SetEnabled` doesn't exist on the dropdown, observe whether the alpha fallback produces an acceptable "disabled" look. If not, iterate on the greying approach in-place and include the fix in the same commit.

- [ ] **Step 8: Manual verification — combat queue status line** *(AC-4)*

Pull something and enter combat. Open settings (settings panels work in combat since they're not secure). Change raid `sortMode` from "By raid group" to "By role". Expected:

1. The "Changes queued — will apply after combat" text appears below the dropdowns.
2. Raid frames do NOT reflow yet.
3. Leave combat. The status text disappears. Raid frames reflow.

- [ ] **Step 9: Commit and push**

```bash
git add Settings/Cards/Sorting.lua Framed.toc Settings/FrameSettingsBuilder.lua Units/LiveUpdate/FrameConfigShared.lua
git commit -m "$(cat <<'EOF'
Add Sorting settings card for raid and party frames

Two dropdowns: sort mode (group/role for raid, index/role for
party) and a 6-preset role-order dropdown that renders inline
role icons via the new CreateIconRowDropdown widget. A combat
queue status line wires Shared.SetCombatQueueStatus so queued
attribute writes get a visible "will apply after combat" hint.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 8: Sort-Aware Preview Layout

**Files:**
- Modify: `Preview/PreviewManager.lua` (`showGroupPreview` around lines 165-274)

- [ ] **Step 1: Add `bucketByRole` helper**

In `Preview/PreviewManager.lua`, add this local function near the top of the file (after the `GROUP_FAKES` declaration around line 43, before the `getUnitConfig` function):

```lua
-- ============================================================
-- Role bucketing for sort-aware preview layout
-- ============================================================

--- Partition a list of fake unit records into role buckets, then
--- emit them in the order specified by `roleOrder` (a comma-
--- separated string of role tokens). Units with roles not in the
--- order are appended at the end, preserving original index order
--- within each bucket.
--- @param units table  Array of records with a `role` field
--- @param roleOrder string  e.g. 'TANK,HEALER,DAMAGER'
--- @return table  Re-ordered array, same length as input
local function bucketByRole(units, roleOrder)
    local buckets = {}
    local order = {}
    for token in roleOrder:gmatch('[^,]+') do
        buckets[token] = {}
        order[#order + 1] = token
    end
    local leftovers = {}

    for _, unit in next, units do
        local role = unit.role
        if(role and buckets[role]) then
            local b = buckets[role]
            b[#b + 1] = unit
        else
            leftovers[#leftovers + 1] = unit
        end
    end

    local result = {}
    for _, token in next, order do
        for _, unit in next, buckets[token] do
            result[#result + 1] = unit
        end
    end
    for _, unit in next, leftovers do
        result[#result + 1] = unit
    end
    return result
end
```

- [ ] **Step 2: Modify `showGroupPreview` to build a role-aware ordered list**

Replace lines 219-244 (the `for i = 1, count do ... end` block) with:

```lua
    -- Build full unit list first (so we can bucket by role if needed)
    local units = {}
    for i = 1, count do
        local fakeUnit = GROUP_FAKES[((i - 1) % #GROUP_FAKES) + 1]
        units[i] = {
            name = fakeUnit.name .. (i > #GROUP_FAKES and (' ' .. i) or ''),
            class = fakeUnit.class,
            role = fakeUnit.role,  -- NEW: preserve for bucketing
            healthPct = math.max(0.1, (fakeUnit.healthPct or 0.8) - (i * 0.03)),
            powerPct = fakeUnit.powerPct or 0.5,
        }
    end

    -- Role-aware ordering
    if(config.sortMode == 'role' and config.roleOrder) then
        units = bucketByRole(units, config.roleOrder)
    end

    for i = 1, count do
        local varied = units[i]

        -- Column-based layout: 5 units per column, then wrap to next column
        local idx = i - 1
        local col = math.floor(idx / UNITS_PER_COLUMN)
        local row = idx % UNITS_PER_COLUMN
        local offX = row * primaryX + col * colX
        local offY = row * primaryY + col * colY

        local pf = F.PreviewFrame.Create(container, config, varied, realFrame, auraConfig)
        -- Anchor to real frame so previews follow during drag
        if(realFrame) then
            pf:SetPoint(anchorPoint, realFrame, anchorPoint, offX, offY)
        else
            pf:SetPoint(anchorPoint, UIParent, posAnchor, baseX + offX, baseY + offY)
        end
        previewFrames[i] = pf
        pf:Show()
    end
```

**Note:** The existing layout uses flat column-flow (5 per column, wrap to next column). In role mode, `bucketByRole` puts all tanks first, then all healers, then all dps — so tanks fill column 1 (up to 5), healers start wherever tanks leave off. This is not *exactly* how `SecureGroupHeader` with `groupBy='ASSIGNEDROLE'` lays out (which starts each role at a new column boundary), so there is a minor visual discrepancy: the preview may pack tanks and healers in the same column when there are fewer than 5 of each.

For parity with the real header, replace the column math with "each role is its own column group":

```lua
    -- Role-aware ordering (each role = its own column group)
    local layoutMode = (config.sortMode == 'role' and config.roleOrder) and 'role' or 'flat'
    local orderedList
    local roleBreaks  -- indices at which a new column MUST start
    if(layoutMode == 'role') then
        orderedList, roleBreaks = {}, { [1] = true }
        local tokens = {}
        for token in config.roleOrder:gmatch('[^,]+') do tokens[#tokens + 1] = token end
        local buckets = {}
        for _, token in next, tokens do buckets[token] = {} end
        local leftovers = {}
        for _, unit in next, units do
            if(unit.role and buckets[unit.role]) then
                local b = buckets[unit.role]
                b[#b + 1] = unit
            else
                leftovers[#leftovers + 1] = unit
            end
        end
        for _, token in next, tokens do
            if(#buckets[token] > 0) then
                roleBreaks[#orderedList + 1] = true
                for _, u in next, buckets[token] do
                    orderedList[#orderedList + 1] = u
                end
            end
        end
        if(#leftovers > 0) then
            roleBreaks[#orderedList + 1] = true
            for _, u in next, leftovers do
                orderedList[#orderedList + 1] = u
            end
        end
    else
        orderedList = units
    end

    -- Walk the ordered list, breaking to a new column either at
    -- unitsPerColumn or at a role break.
    local col, row = 0, 0
    for i = 1, #orderedList do
        if(i > 1 and (roleBreaks and roleBreaks[i] or row == UNITS_PER_COLUMN)) then
            col = col + 1
            row = 0
        end
        local varied = orderedList[i]
        local offX = row * primaryX + col * colX
        local offY = row * primaryY + col * colY

        local pf = F.PreviewFrame.Create(container, config, varied, realFrame, auraConfig)
        if(realFrame) then
            pf:SetPoint(anchorPoint, realFrame, anchorPoint, offX, offY)
        else
            pf:SetPoint(anchorPoint, UIParent, posAnchor, baseX + offX, baseY + offY)
        end
        previewFrames[i] = pf
        pf:Show()

        row = row + 1
    end
```

**Remove the standalone `bucketByRole` function added in Step 1** — it is superseded by the inline role-bucket logic in the layout loop, which needs `roleBreaks` metadata the flat bucket helper doesn't produce.

(Keeping one implementation, inline with the layout pass, avoids the drift between "order of units" and "column break positions" that would arise if the helper and the consumer lived in different files.)

- [ ] **Step 3: Run luacheck**

```bash
luacheck Preview/PreviewManager.lua
```

Expected: no new warnings. The `bucketByRole` helper added in Step 1 has been removed in Step 2, so it should not produce an "unused function" warning.

- [ ] **Step 4: Manual verification — edit-mode preview reflows** *(AC-9)*

Sync + `/reload`. Solo, open Framed settings → raid panel. Click the edit mode button (or `/framed editmode` — confirm the exact command in-game).

1. With `sortMode='group'`, preview shows 20 fake raid frames in 4 columns of 5.
2. Switch Sorting card to "By role" with "Tank, Healer, DPS". Preview reflows: 4-unit tank column, 4-unit healer column, 12 DPS in 3 columns (5/5/2 or similar depending on overflow behavior).
3. Switch role order to "Healer, Tank, DPS". Healers and tanks swap positions; DPS stays at the end.
4. Exit edit mode. Real raid frames (in an actual raid) still behave per Task 4 — the preview change is independent of the real header.

- [ ] **Step 5: Commit and push**

```bash
git add Preview/PreviewManager.lua
git commit -m "$(cat <<'EOF'
Make edit-mode preview layout sort-aware

Preview frames now bucket by role when config.sortMode == 'role',
matching SecureGroupHeader's groupBy='ASSIGNEDROLE' column breaks.
Fake unit pool already had role fields from Preview.lua — the
layout pass just consumes them now.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 9: Shared Bounds Helper for ClickCatchers

**Files:**
- Modify: `Preview/PreviewManager.lua` (extract + export a bounds helper)
- Modify: `EditMode/ClickCatchers.lua` (delegate `getGroupBounds` to the shared helper)

- [ ] **Step 1: Add `PM.GetGroupBounds` to `PreviewManager.lua`**

Add this public function in `Preview/PreviewManager.lua`, after the `PM.GetGroupPreviewCount` / `SetGroupPreviewCount` block (around line 56):

```lua
--- Compute the outer-bounding rectangle (w, h) that a group
--- preview will occupy given its config. Returns nil if config
--- is missing required fields. Sort-aware: role mode respects
--- role buckets as column breaks, so the bounds match what
--- showGroupPreview actually lays out.
--- @param config table
--- @param frameKey string  'party' | 'raid' | etc.
--- @return number? width
--- @return number? height
function PM.GetGroupBounds(config, frameKey)
    local count = GROUP_FRAME_COUNTS[frameKey]
    if(not count) then return nil end

    local w = config.width
    local h = config.height
    local spacing = config.spacing
    local isVertical = (config.orientation == 'vertical')

    -- Determine column breakpoints (same logic as showGroupPreview)
    local columns = {}  -- columns[i] = count of rows in column i
    if(config.sortMode == 'role' and config.roleOrder) then
        if(not GROUP_FAKES) then
            GROUP_FAKES = F.Preview.GetFakeUnits(5)
        end
        local tokens = {}
        for token in config.roleOrder:gmatch('[^,]+') do tokens[#tokens + 1] = token end
        local buckets = {}
        for _, token in next, tokens do buckets[token] = 0 end
        local leftovers = 0
        for i = 1, count do
            local fakeUnit = GROUP_FAKES[((i - 1) % #GROUP_FAKES) + 1]
            if(fakeUnit.role and buckets[fakeUnit.role] ~= nil) then
                buckets[fakeUnit.role] = buckets[fakeUnit.role] + 1
            else
                leftovers = leftovers + 1
            end
        end
        local function pushBucket(n)
            while n > 0 do
                local take = math.min(n, UNITS_PER_COLUMN)
                columns[#columns + 1] = take
                n = n - take
            end
        end
        for _, token in next, tokens do
            if(buckets[token] > 0) then pushBucket(buckets[token]) end
        end
        if(leftovers > 0) then pushBucket(leftovers) end
    else
        -- Flat column flow
        local remaining = count
        while remaining > 0 do
            local take = math.min(remaining, UNITS_PER_COLUMN)
            columns[#columns + 1] = take
            remaining = remaining - take
        end
    end

    local numCols = #columns
    local tallest = 0
    for _, colCount in next, columns do
        if(colCount > tallest) then tallest = colCount end
    end

    if(isVertical) then
        local totalW = numCols * w + math.max(0, numCols - 1) * spacing
        local totalH = tallest * h + math.max(0, tallest - 1) * spacing
        return totalW, totalH
    else
        local totalW = tallest * w + math.max(0, tallest - 1) * spacing
        local totalH = numCols * h + math.max(0, numCols - 1) * spacing
        return totalW, totalH
    end
end
```

- [ ] **Step 2: Update `ClickCatchers.lua` to delegate**

In `EditMode/ClickCatchers.lua`, replace the `getGroupBounds` local function (lines 91-105) with a thin delegation:

```lua
local function getGroupBounds(config, frameKey)
    return F.PreviewManager.GetGroupBounds(config, frameKey)
end
```

Keep the `UNITS_PER_COLUMN` constant if it's used elsewhere in the file; otherwise it can be removed. (Check with `grep` in the file before deleting.)

- [ ] **Step 3: Run luacheck**

```bash
luacheck Preview/PreviewManager.lua EditMode/ClickCatchers.lua
```

Expected: no new warnings. If `UNITS_PER_COLUMN` is flagged as unused in `ClickCatchers.lua`, remove it.

- [ ] **Step 4: Manual verification — catcher tracks preview in role mode** *(AC-10)*

Sync + `/reload`. Solo, enter edit mode on raid. With `sortMode='role'`, select "By role" + "Tank, Healer, DPS". Expected:

1. The click catcher (transparent rectangle with the accent border) exactly wraps the 4/4/12 preview layout — not the old 5-per-column bounds.
2. Click anywhere inside the visible preview frames → catcher responds to the click (the selection highlights, drag works).
3. Switch role order to "DPS, Healer, Tank". The catcher resizes to match the new layout.
4. Switch mode back to "By raid group". Catcher resizes back to the flat column-flow bounds.

- [ ] **Step 5: Commit and push**

```bash
git add Preview/PreviewManager.lua EditMode/ClickCatchers.lua
git commit -m "$(cat <<'EOF'
Share sort-aware bounds math between preview and edit mode catcher

PreviewManager.GetGroupBounds is now the single source of truth for
"how big is a group preview?" — role mode and flat mode both go
through the same column-breakpoint computation. ClickCatchers
delegates to it so the catcher outline stays pixel-aligned with
the preview frames regardless of sort mode.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 10: Final Acceptance Sweep

**Files:** none (verification only — any fixes go in a follow-up commit)

- [ ] **Step 1: Re-run luacheck on the whole repo**

```bash
luacheck .
```

Expected: no new warnings attributable to this feature.

- [ ] **Step 2: Run every acceptance criterion in order**

Sync + `/reload` before each criterion if state needs resetting.

- [ ] **AC-1: Default behavior unchanged** — Fresh SavedVariables (delete `WTF/Account/<account>/SavedVariables/Framed.lua` or use a test character). `/reload`. Raid in an actual raid renders as 8 group columns. Party renders as single index-sorted column.

- [ ] **AC-2: Upgraders unchanged** — Restore pre-upgrade SavedVariables (or manually edit to omit `sortMode`/`roleOrder`). `/reload`. Confirm `EnsureDefaults` backfilled the keys: `/run print(F.StyleBuilder.GetConfig('raid').sortMode)` → `group`. Visual behavior identical to AC-1.

- [ ] **AC-3: Raid role sort, out of combat** — Settings → raid → Sorting → "By role" + "Tank, Healer, DPS". In an actual raid: frames reflow to three role columns. No `/reload`.

- [ ] **AC-3b: Party pets track sort changes** — In a party with a pet-class player, flip party between index and role mode. Pet frames stay visually next to their owners across both transitions. No pets stranded next to the wrong character.

- [ ] **AC-4: Raid role sort, in combat** — Pull a mob. Settings → change role order. "Changes queued — will apply after combat" appears. Leave combat. Layout updates, message disappears.

- [ ] **AC-5: Role order change** — In role mode, switch from "Tank, Healer, DPS" to "Healer, Tank, DPS". Columns swap positions. No `/reload`.

- [ ] **AC-6: Mid-session spec swap** — Raid in role mode. A party member changes spec out of combat. Their frame moves to the new role column immediately. No `/reload`.

- [ ] **AC-7: NONE-role unit visibility** — Open-world raid group with an un-assigned-role member. In role mode, confirm they render (in a NONE column after the three role columns), not hidden.

- [ ] **AC-8: Party independent from raid** — Party set to "By role" / "Healer, Tank, DPS". Raid set to "By role" / "Tank, Healer, DPS". In a group that's both (unusual but possible via preset swap), confirm each layout renders with its own order.

- [ ] **AC-9: Edit-mode preview parity** — Solo, edit mode on raid in role mode. Preview frames group fake units into role columns. Switching role orders updates the preview.

- [ ] **AC-10: ClickCatcher tracks preview** — In the same edit-mode state, confirm the catcher outline exactly wraps the preview frames in role mode. Clicks land inside.

- [ ] **Step 3: Fix any failures inline**

Any failing AC gets a focused fix commit. Re-run the affected AC only; do not re-run the whole sweep unless the fix is systemic.

- [ ] **Step 4: Close out**

If all ACs pass and the working-testing branch is clean, hand back to the user for merge-to-working decision (per `feedback_git_workflow.md`: worktree → working → main, never direct to main). The `superpowers:finishing-a-development-branch` skill is the appropriate next step.

---

## Risks and Mitigations

1. **`oUF:SpawnHeader` nil attribute tolerance** (Task 3) — if nil `groupBy`/`groupingOrder` causes a Lua error during party spawn in index mode, the mitigation is to wrap the `SpawnHeader` call in a helper that filters nil pairs, or to have `GroupAttrs` return empty strings instead of nils for party/index mode. Check during Task 3, Step 3.

2. **`Widgets.CreateDropdown.SetEnabled` existence** (Task 7) — the card greys the Role Order dropdown when mode isn't 'role'. If `SetEnabled` is not on the dropdown widget, the plan falls back to alpha dimming, then to hiding. All three are acceptable UX.

3. **Preview layout discrepancy with real header** (Task 8) — the preview's column-break logic is an approximation of `SecureGroupHeader`'s. If playtesting shows a noticeable mismatch (e.g., real header breaks at different column boundaries), the fix is to adjust the preview's `roleBreaks` logic to match the observed real-header behavior. Spec AC-9 explicitly states the preview is an approximation, not a pixel-perfect mirror.

4. **`PLAYER_ROLES_ASSIGNED` firing during combat** (Task 5) — the plan assumes this is out-of-combat only. In practice, some edge cases (e.g., LFG role assignment) can fire the event outside the player's control. The call still routes through `applyOrQueue`, which handles in-combat queuing, so the worst case is a one-frame delay until combat ends. Not a bug.

5. **Party pet re-anchor timing** (Task 4) — `C_Timer.After(0, AnchorPetFrames)` defers one frame so `SecureGroupHeader_Update` has finished reassigning `unit` attributes to its children before `findOwnerFrame` resolves owners. If playtesting shows pets briefly flashing to the wrong owner or not following at all, bump the delay to `0.05` seconds. The underlying assumption — that the secure header resettles within a frame of `SetAttribute` calls landing — holds for the out-of-combat path. For the combat-queued path, the attribute writes drain in `PLAYER_REGEN_ENABLED`, still out of combat, so the deferred re-anchor is safe.

## Memory References

- `feedback_commit_after_task.md` — commit + push after every task (followed throughout)
- `feedback_git_workflow.md` — worktree → working → main (this plan runs in `.worktrees/working-testing`)
- `feedback_wow_sync.md` — sync to WoW addon folder for `/reload` testing (every manual verification step)
- `feedback_no_stubs.md` — no TODO/Coming Soon placeholders (every task produces a complete, verifiable slice)
- `feedback_aura_indicators_fragile.md` — does NOT apply; this plan doesn't touch aura indicator rendering
- `feedback_table_pooling.md` — does NOT apply; this plan creates no new pooled tables
