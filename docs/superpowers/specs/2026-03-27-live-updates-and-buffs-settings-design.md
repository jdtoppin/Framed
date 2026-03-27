# Live Config Updates & Buffs Settings Expansion

**Date:** 2026-03-27
**Scope:** Wire all settings to live-update frames without /reload; expand Buffs indicator edit panel with proper per-type settings cards; add shared settings builders; add `/framed reset all` command; fix default positions and enabled states; oUF integration.

---

## Part 0: oUF Integration & Architecture Notes

### Use oUF's Element Lifecycle

For toggling elements on/off at runtime, use oUF's built-in methods — NOT custom show/hide:

```lua
-- Toggle a status icon
frame:DisableElement('GroupRoleIndicator')  -- unregisters events, calls disable()
frame:EnableElement('GroupRoleIndicator')   -- registers events, calls enable()

-- Refresh a single element after config change
element:ForceUpdate()  -- triggers element's Path() chain

-- Refresh all elements (e.g., after resize)
frame:UpdateAllElements('CONFIG_CHANGED')
```

oUF automatically handles event registration/unregistration in Enable/Disable. Our live-update handlers should call these instead of manually showing/hiding widgets.

### When to Use Which oUF Method

| Scenario | Method | Example |
|----------|--------|---------|
| Toggle an element on/off | `EnableElement`/`DisableElement` | Status icons, Castbar, HealthPrediction, Power |
| Refresh one element after config change | `element:ForceUpdate()` | Health color mode changed, text format changed |
| Refresh all elements after structural change | `frame:UpdateAllElements('CONFIG_CHANGED')` | Frame resized (elements may need repositioning) |
| Text show/hide (not a full oUF element) | `:SetShown(value)` | `frame.Name`, `frame.Health.text`, `frame.Power.text` — these are FontStrings, not oUF elements |

**Castbar** is a full oUF element — toggle with `DisableElement('Castbar')`/`EnableElement('Castbar')`, not show/hide on the wrapper frame.

### oUF Provides (use directly)

- Health/Power bar color modes: `health.colorClass`, `health.colorReaction`, `health.colorSmooth`, `health.colorThreat`
- Element Enable/Disable with event management
- `ForceUpdate()` per element, `UpdateAllElements()` per frame
- All standard status indicators (Role, Leader, ReadyCheck, RaidTarget, Combat, Resting, Phase, Resurrect, Summon, RaidRole, PvP)
- HealthPrediction (incoming heals, absorbs)
- Castbar with interrupt indicator

### Framed Builds On Top (custom)

- Text formatting (health %, deficit, etc.) — via PostUpdate callbacks
- Frame sizing/layout — oUF has no layout management
- Aura indicator system (Buffs multi-type renderers, BorderIcon pools)
- Settings integration and CONFIG_CHANGED listeners
- Glow effects (LibCustomGlow wrapper)

### Player-in-Group Separation

The player frame in party/raid headers is **correctly separate** from the standalone player frame:

| Context | unitType | Config Path | Aura Scope |
|---------|----------|-------------|------------|
| Standalone | `'player'` | `presets.X.unitConfigs.player.*` | `presets.X.auras.player.*` |
| In party header | `'party'` | `presets.X.unitConfigs.party.*` | `presets.X.auras.party.*` |
| In raid header | `'raid'` | `presets.X.unitConfigs.raid.*` | `presets.X.auras.raid.*` |

This is intentional — the player in a group uses compact group styling, not full player styling. No fix needed.

**Mechanism:** `Apply()` in StyleBuilder sets `self._framedUnitType = unitType` (line 500) at setup time. Group header child frames get `unitType = 'party'` or `'raid'`, standalone player gets `unitType = 'player'`. `ForEachFrame(unitType, callback)` filters on this property, so party config changes never touch the standalone player frame and vice versa. This property is already set and used by existing listeners — no new code needed.

---

## Part 0.5: Default Positions & Enabled States

### Problem

Current AuraDefaults have overlapping positions (debuffs BOTTOMLEFT + defensives TOPLEFT + buffs TOPLEFT on compact group frames) and missing enabled flags on some elements. A first-time user shouldn't see icons piled on top of each other.

### Design Principles (from Cell/ElvUI reference)

- **Non-overlapping defaults** — each indicator gets its own visual real estate
- **Healer-oriented group defaults** — dispels, raid debuffs, externals enabled; DPS-only indicators disabled
- **Solo frames are feature-rich** — castbar, portrait, full debuff display
- **Group frames are compact** — fewer debuffs, prioritize raid mechanics
- **Disabled by default on group frames**: health text, power text, combat icon, crowd controls, missing buffs, LoC

### Default Positions (Group Frames: party/raid)

Reference: Cell's proven layout adapted for our BorderIcon system.

```
┌──────────────────────────────────┐
│ [Role]  [Leader]     [Raid Icon] │  ← Status icons (top edge)
│  [Defensives←]    [→Externals]   │  ← Left/Right edges, below top
│                                  │
│         [Raid Debuffs]           │  ← CENTER, prominent
│       [Targeted Spells]          │  ← CENTER, high frame level
│         [Dispellable]            │  ← CENTER overlay (gradient)
│                                  │
│ [Debuffs→]        [Dispel icon]  │  ← BOTTOMLEFT / BOTTOMRIGHT
│ [Missing Buffs→ (if enabled)]    │  ← BOTTOMRIGHT, above dispel
└──────────────────────────────────┘
```

| Element | Anchor | Offset | Size | Frame Level | Enabled |
|---------|--------|--------|------|-------------|---------|
| Debuffs | BOTTOMLEFT | 1, 4 | 13 | 5 | Yes |
| Raid Debuffs | CENTER | 0, 3 | 22 | 20 | Yes |
| Externals | RIGHT | 2, 5 | 12 | 10 | Yes |
| Defensives | LEFT | -2, 5 | 12 | 10 | Yes |
| Dispellable | BOTTOMRIGHT | 0, 4 | 12 | 15 | Yes |
| Targeted Spells | CENTER | 0, 6 | 20 | 50 | Yes |
| Missing Buffs | BOTTOMRIGHT | -2, 16 | 12 | 10 | No (disabled) |
| Private Auras | TOP | 0, -3 | 16 | 25 | Yes |
| LoC | CENTER | 0, 0 | 22 | 30 | No (disabled) |
| CC | CENTER | 0, 0 | 22 | 20 | No (disabled) |
| Buffs (My Buffs) | TOPRIGHT | -2, -2 | 14 | 5 | Yes |

### Default Positions (Solo Frames: player/target)

Larger frames, more room. Debuffs below health bar, buffs above.

| Element | Anchor | Offset | Size | Frame Level | Enabled |
|---------|--------|--------|------|-------------|---------|
| Debuffs | BOTTOMLEFT | 2, 2 | 14 | 5 | Yes (6 max) |
| Buffs (My Buffs) | TOPLEFT | 2, -2 | 14 | 5 | Yes |

### Default Positions (Arena Frames)

Enemy unit frames — debuffs and dispellable only, plus CC tracking.

| Element | Anchor | Offset | Size | Frame Level | Enabled |
|---------|--------|--------|------|-------------|---------|
| Debuffs | BOTTOMLEFT | 2, 2 | 14 | 5 | Yes (4 max) |
| Buffs (My Buffs) | TOPLEFT | 2, -2 | 14 | 5 | Yes |
| Dispellable | CENTER | 0, 0 | 14 | 7 | Yes |
| CC | CENTER | 0, 0 | 22 | 20 | No (disabled) |
| LoC | CENTER | 0, 0 | 22 | 30 | No (disabled) |

### Default Positions (Boss Frames)

Boss units — debuffs, raid debuffs, buffs.

| Element | Anchor | Offset | Size | Frame Level | Enabled |
|---------|--------|--------|------|-------------|---------|
| Debuffs | BOTTOMLEFT | 2, 2 | 14 | 5 | Yes (4 max) |
| Buffs (My Buffs) | TOPLEFT | 2, -2 | 14 | 5 | Yes |
| Raid Debuffs | CENTER | 0, 0 | 14 | 6 | Yes |

### World Buff / Raid Buff Filtering on Group Frames

Group frames should not show world buffs (Darkmoon Faire, holiday events), consumable buffs (flasks, food, augment runes), or long-duration raid-wide auras. These clutter compact frames and aren't actionable for healing.

**Config key:** `buffs.hideUnimportantBuffs` (boolean, default `true` for party/raid, `false` for solo/arena/boss)

**Filter logic** in Buffs.lua Update, applied per-aura before indicator matching:

```lua
-- Skip unimportant buffs on group frames when filter is enabled
if(element._hideUnimportantBuffs) then
    local dominated = auraData.duration == 0        -- no duration (permanent zone buffs)
        or auraData.duration > 600                   -- 10+ minute buffs (flasks, food, world buffs)
        or (not auraData.canApplyAura                -- not player-castable
            and not auraData.isBossAura              -- not a boss mechanic
            and auraData.duration > 120)             -- 2+ min non-player auras
    if(dominated) then skip end
end
```

The threshold-based approach catches the vast majority of unimportant buffs without maintaining a spell blacklist. Short-duration player-applied buffs (hots, externals, Power Infusion, etc.) always pass through.

**Intentional trade-off:** Long-duration player-castable buffs like Power Word: Fortitude (60 min) are filtered by the `duration > 600` rule. This is intentional — Fortitude is not actionable for healing decisions. If the group needs rebuffing, the MissingBuffs indicator handles that concern separately. This filter is strictly about keeping group frame buff icons limited to actionable, time-sensitive information.

**Settings toggle:** Add to group frame aura config section (near the top of the Buffs panel for party/raid) as a simple checkbox: "Hide world & consumable buffs". Fires `CONFIG_CHANGED`, Rebuild sets `element._hideUnimportantBuffs` from config.

### Default LoC & CC Configs

Currently `lossOfControl = {}` and `crowdControl = {}` on all frame types. Replace with:

```lua
lossOfControl = {
    enabled    = false,
    iconSize   = 22,
    anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
    frameLevel = 30,
    types      = { 'stun', 'incapacitate', 'disorient', 'fear', 'silence', 'root' },
},
crowdControl = {
    enabled    = false,
    iconSize   = 22,
    anchor     = { 'CENTER', nil, 'CENTER', 0, 0 },
    frameLevel = 20,
    spells     = {}, -- uses DEFAULT_CC_SPELLS from CrowdControl element
},
```

Both disabled by default. When a user enables LoC or CC through settings, the element is set up via `Rebuild()`. The empty `spells = {}` for CC means the element falls back to its built-in `DEFAULT_CC_SPELLS` list (Polymorph, Hex, Freezing Trap, etc.).

### Missing `enabled` Flags

Add explicit `enabled` flags to elements currently missing them in `AuraDefaults.lua`:

- `missingBuffs.enabled = false` (group frames — disabled by default)
- `privateAuras.enabled = true` (group frames)

### Default Enabled States by Frame Type

| Element | Player | Target | Party | Raid | Arena | Boss |
|---------|--------|--------|-------|------|-------|------|
| Buffs | Yes | Yes | Yes | Yes | Yes | Yes |
| Debuffs | Yes | Yes | Yes | Yes (max 1) | Yes (max 4) | Yes (max 4) |
| Raid Debuffs | — | — | Yes | Yes | — | Yes |
| Externals | — | — | Yes | Yes | — | — |
| Defensives | — | — | Yes | Yes | — | — |
| Dispellable | — | — | Yes | Yes | Yes | — |
| Targeted Spells | — | — | Yes | Yes | — | — |
| Missing Buffs | — | — | No | No | — | — |
| Private Auras | — | — | Yes | Yes | — | — |
| LoC | — | — | No | No | No | — |
| CC | — | — | No | No | No | — |

("—" = not applicable / not included in that frame type's aura defaults)

---

## Part 1: Live Config Update System

### Problem

35 frame settings and several aura settings fire `CONFIG_CHANGED` but have no listener — the user changes a slider and nothing happens until `/reload`. Additionally, some aura elements (Buffs, LoC, CC, MissingBuffs, PrivateAuras) have no live-update wiring at all.

### Architecture: StyleBuilder File Split

StyleBuilder.lua is ~1190 lines (over the 500-line guideline). Split into focused files:

| File | Responsibility | ~Lines |
|------|---------------|--------|
| `Units/StyleBuilder.lua` | Core: defaults, unit presets, `GetConfig()`, `GetAuraConfig()`, `Apply()`, shared `ForEachFrame()` helper | ~720 |
| `Units/LiveUpdate/FrameConfig.lua` | Everything under `unitConfigs.*`: dimensions, position, power, castbar, shields/absorbs, status icons, show/hide toggles, text (font/anchor/color/format), health bar colors, gradients, highlights | ~650 |
| `Units/LiveUpdate/AuraConfig.lua` | Everything under `presets.*.auras.*`: all aura elements, debounced Rebuild, enabled toggles | ~350 |

Split is by **config namespace** — one path-match per file. FrameConfig exceeds the 500-line guideline but is justified by cohesion: all `unitConfigs` handlers share the same path pattern and `ForEachFrame` iteration. Splitting further would create 3 files with duplicated matching logic.

**Shared helper** exposed on `F.StyleBuilder`:

```lua
function F.StyleBuilder.ForEachFrame(unitType, callback)
    local oUF = F.oUF
    for _, frame in next, oUF.objects do
        if(frame._framedUnitType == unitType) then
            callback(frame)
        end
    end
end
```

All listener files use this instead of inline iteration. Load order in TOC: StyleBuilder.lua first, then LiveUpdate/* files.

### Combat Queue for Group Layout

Group layout changes (`spacing`, `orientation`, `growthDirection`) use `header:SetAttribute()` which is locked during combat. Implementation:

```lua
-- In FrameConfig.lua
local pendingGroupChanges = {}

local function applyOrQueue(header, attr, value)
    if(InCombatLockdown()) then
        pendingGroupChanges[#pendingGroupChanges + 1] = { header, attr, value }
    else
        header:SetAttribute(attr, value)
    end
end

-- Register once: flush on combat end
F.EventBus:Register('PLAYER_REGEN_ENABLED', function()
    for _, change in next, pendingGroupChanges do
        change[1]:SetAttribute(change[2], change[3])
    end
    wipe(pendingGroupChanges)
end, 'LiveUpdate.CombatQueue')
```

#### Combat Queue UX Feedback

When any group layout change is queued during combat, show a single persistent status line at the **top of the Group Layout section**: "Changes queued — will apply after combat" in `C.Colors.textSecondary`. This covers all queued settings at once — if the user changes spacing, orientation, and growth direction mid-combat, one message communicates all three. Clear the status line when `PLAYER_REGEN_ENABLED` fires and all queued changes are applied. Without this, the user sees no visual change and thinks the setting is broken.

### Frame Settings: New Live-Update Handlers (FrameConfig.lua)

All handlers listen on `CONFIG_CHANGED`, parse `unitConfigs.<unitType>.<key>`, iterate matching frames.

#### Dimensions & Position

| Key | Handler |
|-----|---------|
| `width` | `frame:SetWidth(value)`, resize health/power bars proportionally |
| `height` | `frame:SetHeight(value)`, resize health bar, reposition power bar |
| `position.anchor` | `frame:ClearAllPoints(); frame:SetPoint(...)` — solo frames only |
| `position.x` | Update X offset in SetPoint |
| `position.y` | Update Y offset in SetPoint |

Position changes for group frames (party/raid) use `applyOrQueue()`.

#### Group Layout

| Key | Handler |
|-----|---------|
| `spacing` | `applyOrQueue(header, 'yOffset', -value)` or `xOffset` based on orientation |
| `orientation` | `applyOrQueue(header, 'point', ...)` — rebuild point/xOffset/yOffset attrs |
| `growthDirection` | `applyOrQueue(header, 'point', ...)` — same as orientation |

#### Power Bar & Cast Bar

| Key | Handler |
|-----|---------|
| `showPower` | Show/hide Power element; if hiding, reclaim height for health bar |
| `power.height` | `frame.Power:SetHeight(value)`, adjust health bar height |
| `showCastBar` | Show/hide Castbar element via element Enable/Disable |

#### Shields & Absorbs

| Key | Handler |
|-----|---------|
| `health.healPrediction` | Toggle `frame.HealthPrediction` element Enable/Disable |
| `health.healPredictionColor` | Set color on prediction bar texture |
| `health.damageAbsorb` | Toggle absorb bar visibility |
| `health.damageAbsorbColor` | Set color on absorb bar texture |
| `health.healAbsorb` | Toggle heal absorb bar visibility |
| `health.healAbsorbColor` | Set color on heal absorb texture |
| `health.overAbsorb` | Toggle over-absorb glow visibility |

#### Status Icons (11 toggles + statusText)

Each `statusIcons.<iconName>` toggle calls the corresponding oUF element's Enable or Disable:

```lua
local STATUS_ELEMENT_MAP = {
    role       = 'GroupRoleIndicator',
    leader     = 'LeaderIndicator',
    readyCheck = 'ReadyCheckIndicator',
    raidIcon   = 'RaidTargetIndicator',
    combat     = 'CombatIndicator',
    resting    = 'RestingIndicator',
    phase      = 'PhaseIndicator',
    resurrect  = 'ResurrectIndicator',
    summon     = 'SummonIndicator',
    raidRole   = 'RaidRoleIndicator',
    pvp        = 'PvPIndicator',
}
```

`statusText` toggles the StatusText element show/hide.

#### Show/Hide Toggles

| Key | Handler |
|-----|---------|
| `showName` | `frame.Name:SetShown(value)` |
| `health.showText` | `frame.Health.text:SetShown(value)` |
| `power.showText` | `frame.Power.text:SetShown(value)` |

### Text & Color Settings (also in FrameConfig.lua)

Move existing TextConfig, HealthColorConfig, and HighlightConfig listeners from StyleBuilder.lua into FrameConfig.lua. All parse the same `unitConfigs.<unitType>.<key>` path pattern. Additional text handlers:

| Key | Handler |
|-----|---------|
| `health.textFormat` | Update `frame.Health._textFormat`, call `health:ForceUpdate()` to re-render |
| `health.attachedToName` | If true: anchor health text to `frame.Name:RIGHT`; if false: anchor to own position. Update `frame.Health._attachedToName` flag |
| `health.smooth` | Toggle `frame.Health.smoothing = value` |

Health color and highlight handlers are already complete — just moved into this file.

### Aura Settings: Expanded Handlers (AuraConfig.lua)

Move existing AuraConfig listener from StyleBuilder.lua. Major additions:

#### BorderIcon Pool Recreation (structural keys)

Add `Destroy()` method to BorderIcon:

```lua
function BorderIconMethods:Destroy()
    self._frame:SetScript('OnUpdate', nil)
    self._frame._biRef = nil
    self._frame:Hide()
    self._frame:SetParent(nil)
end
```

Updated `wipePool()` calls `Destroy()` on each entry before `wipe()`. After wipe, `ForceUpdate()` lazily recreates icons with new config values for `showStacks`, `showDuration`, `frameLevel`, fonts.

#### Expanded AURA_ELEMENT_MAP

```lua
local AURA_ELEMENT_MAP = {
    debuffs        = 'FramedDebuffs',
    externals      = 'FramedExternals',
    defensives     = 'FramedDefensives',
    raidDebuffs    = 'FramedRaidDebuffs',
    dispellable    = 'FramedDispellable',
    targetedSpells = 'FramedTargetedSpells',
    buffs          = 'FramedBuffs',
    lossOfControl  = 'FramedLossOfControl',
    crowdControl   = 'FramedCrowdControl',
    missingBuffs   = 'FramedMissingBuffs',
    privateAuras   = 'FramedPrivateAuras',
}
```

#### Debounced Updates

All live-update handlers use `C_Timer`-based debounce to prevent performance issues during slider drags. Two tiers with different intervals:

**Tier 1 — Short debounce for non-structural changes (0.05s):**

Position, size, and color changes are cheap (`SetPoint`, `SetSize`, `SetColor`) but still iterate `ForEachFrame` on every slider tick. A 0.05s debounce coalesces rapid slider ticks into a single update — effectively "apply on next frame after user pauses." Feels instant to the user, avoids hammering every oUF frame per pixel of movement.

```lua
local pendingUpdates = {}  -- [key] = timerHandle

local function debouncedApply(key, applyFn, ...)
    if(pendingUpdates[key]) then
        pendingUpdates[key]:Cancel()
    end
    local args = { ... }
    pendingUpdates[key] = C_Timer.NewTimer(0.05, function()
        pendingUpdates[key] = nil
        applyFn(unpack(args))
    end)
end
```

**Tier 2 — Longer debounce for structural changes (0.15s):**

Structural keys that trigger `Rebuild()` (destroy and recreate renderers) use a longer debounce. Only one `Rebuild()` fires when the user stops dragging.

```lua
local pendingRebuilds = {}  -- [element] = timerHandle

local function debouncedRebuild(element, config)
    if(pendingRebuilds[element]) then
        pendingRebuilds[element]:Cancel()
    end
    pendingRebuilds[element] = C_Timer.NewTimer(0.15, function()
        pendingRebuilds[element] = nil
        element:Rebuild(config)
    end)
end
```

Both tiers use `C_Timer` which is fully compatible with WoW's UI thread and makes no framerate assumptions.

#### Rebuild Pattern for Structural Elements

Elements that create their visual structure at Setup time expose a `Rebuild(config)` method:

| Element | Rebuild behavior |
|---------|-----------------|
| **Buffs** | Destroy old renderers, recreate `_indicators`/`_spellLookup`/`_hasTrackAll` from new config, `ForceUpdate()` |
| **LossOfControl** | Destroy overlay/icon, recreate with new `iconSize`/`point`/`types` config |
| **CrowdControl** | Destroy container/icon, recreate with new `iconSize`/`point`/`spells` config |
| **MissingBuffs** | Destroy slots (BorderIcon + Glow per slot), recreate with new size/anchor/glow config |
| **PrivateAuras** | Unregister old C-level anchor, re-register with new `iconSize`/`anchor` |
| **TargetedSpells** | For `displayMode` change: destroy pool/glow, recreate based on new mode |

The listener detects these elements and calls `element:Rebuild(newConfig)` instead of swapping `_config`.

#### Master Enabled Toggle on All Aura Panels

Every aura settings panel (LoC, CC, MissingBuffs, PrivateAuras, Debuffs, Externals, Defensives, etc.) must have an **enabled toggle** at the top of the panel. This is critical for elements disabled by default (LoC, CC, MissingBuffs) — without it, users have no way to enable them from the UI.

The toggle writes `enabled` to the element's config and fires `CONFIG_CHANGED`. The AuraConfig listener responds by calling `EnableElement`/`DisableElement` on matching frames. Panels that already have an enabled toggle keep it; panels missing one get it added.

#### LoC & CC Wiring

Currently CrowdControl is only set up in Arena.lua with hardcoded config, and LossOfControl is not set up anywhere. Changes:

1. `Apply()` in StyleBuilder calls Setup for LoC/CC on all unit types (reading from `GetAuraConfig(unitType, 'lossOfControl')`) — but only if `config.enabled` is true
2. Settings panels already write preset-scoped config (fixed earlier this session)
3. Listener calls `element:Rebuild(newConfig)` on config change, or `EnableElement`/`DisableElement` for enabled toggle changes

### Settings Panel Refresh on External Config Changes

When the user has a settings panel open and config changes externally (Copy-to, preset switch, spec override activation), the panel's widgets show stale values. The user sees old settings until they navigate away and back.

**Solution:** Panels optionally expose a `Refresh()` callback returned from their `create()` function. The settings framework stores this alongside the panel frame. When `EDITING_PRESET_CHANGED` fires, or after a Copy-to operation completes, the framework calls `Refresh()` on the currently active panel.

```lua
-- In panel create():
local function refresh()
    -- Re-read all config values and update widgets
    sizeSlider:SetValue(get('iconWidth'))
    heightSlider:SetValue(get('iconHeight'))
    -- ... etc
end

return scroll, refresh  -- second return value is the refresh callback
```

The settings framework registers for `EDITING_PRESET_CHANGED` once and calls the active panel's refresh if available. `CopyToDialog` calls the refresh after its confirm action completes. Panels without a `Refresh()` callback (simple static panels) are skipped — they'll rebuild on next navigation.

### Preset Scoping & Per-UnitType Aura Wiring

All new features in this spec must be properly scoped to the preset and unit type system. Nothing should be global or hard-coded — every config read/write goes through the preset-aware resolution chain.

#### Preset Architecture (7 presets)

| Preset | Type | Fallback | Unit Types |
|--------|------|----------|------------|
| Solo | Base | — | player, target |
| Party | Base | — | player (in-group), party |
| Raid | Base | — | player (in-group), raid |
| Arena | Base | — | arena |
| Mythic Raid | Derived | Raid | player (in-group), raid |
| World Raid | Derived | Raid | player (in-group), raid |
| Battleground | Derived | Raid | player (in-group), raid |
| Boss | — | — | boss |

Derived presets (Mythic Raid, World Raid, Battleground) share Raid's data via fallback until the user customizes them. At that point, `PresetManager.MarkCustomized(presetName)` sets the `.customized` flag and the preset gets its own independent copy.

#### Config Path Structure

All aura config lives at:

```
FramedDB.presets[presetName].auras[unitType][auraType]
```

For example: `FramedDB.presets.Party.auras.party.buffs` or `FramedDB.presets.Solo.auras.player.debuffs`.

Unit configs (frame dimensions, power bar, status icons) live at:

```
FramedDB.presets[presetName].unitConfigs[unitType]
```

#### GetAuraConfig Resolution Chain

When `GetAuraConfig(unitType, auraType)` is called, it resolves through:

1. **Active preset** for the current content type → check `presets[name].auras[unitType][auraType]`
2. **Canonical base preset** (for derived presets that aren't customized) → fallback to Raid's data via `Constants.PresetInfo[name].groupKey`
3. **Built-in defaults** from `StyleBuilder.Presets` (Solo/Group/Arena/Boss builders in `AuraDefaults.lua`)
4. **Empty table** as final fallback

This chain is already implemented. New elements (Bars renderer, expanded Color/Overlay/Border/Glow settings, LoC/CC wiring) must NOT bypass it. Specifically:
- `Apply()` must always call `GetAuraConfig(unitType, auraType)` — never read from a hardcoded table
- Settings panels must write to `presets.<presetName>.auras.<unitType>.<auraType>` via `F.Config:Set()`, using `F.Settings.GetEditingPreset()` and `F.Settings.GetEditingUnitType()` to resolve the path

#### Spec Overrides

Per-character spec overrides live in `FramedCharDB.specOverrides[specID][contentType] = presetName`. When a player switches specs, the layout system resolves which preset is active for the current content type. This is transparent to the live-update system — `CONFIG_CHANGED` fires against the active preset, and `ForEachFrame` iterates frames whose `_framedUnitType` matches.

No new code is needed for spec overrides — the existing resolution works. But all new elements must be wired through the same `GetAuraConfig()` path so spec-specific preset selections automatically apply.

#### What This Means for New Features

1. **AuraDefaults.lua** must provide defaults for new config keys in ALL four default builders:
   - `Solo()` — player, target unit types
   - `Group()` — party, raid unit types (used by Party, Raid, and all derived presets)
   - `Arena()` — arena unit type
   - `Boss()` — boss unit type

2. **New aura elements** (Bars renderer, LoC/CC wiring, expanded indicator settings) must have their defaults included in the appropriate builders. If an element doesn't apply to a frame type, don't include it — an absent key returns `nil` from `GetAuraConfig()`, and the element doesn't set up.

3. **Live-update handlers** in `AuraConfig.lua` parse paths like `presets.X.auras.party.buffs.hideUnimportantBuffs`. The `X` is the active preset name. The handler extracts the unit type from the path and calls `ForEachFrame(unitType, callback)` — this automatically scopes updates to only the frames using that unit type under that preset.

4. **Derived preset fallback** is transparent. When a user is editing "Mythic Raid" and it's not yet customized, the settings UI shows Raid's values. When they change a value, `PresetManager.MarkCustomized('Mythic Raid')` fires, the preset gets its own copy, and `CONFIG_CHANGED` fires against the Mythic Raid preset. The live-update handler picks it up normally.

5. **Settings panels** that already use `F.Settings.GetEditingPreset()` and `F.Settings.GetEditingUnitType()` (e.g., CrowdControl.lua) are already correct. New panels and expanded settings must follow the same pattern — no hardcoded preset names or unit types.

---

## Part 2: Shared Settings Builders

### Problem

Font settings (face, size, outline, shadow) appear in 5+ places. Glow settings (type, color, per-type params) appear in 3 places. Position + frame level is on every indicator. Duplicating this UI code is fragile and inconsistent.

### BuildFontCard

```lua
--- Build a font settings card with conditional show/hide.
--- @param parent Frame
--- @param width number
--- @param yOffset number
--- @param label string e.g. 'Duration Font', 'Stack Font'
--- @param configPrefix string e.g. 'durationFont', 'stackFont'
--- @param get function(key) -> value
--- @param set function(key, value)
--- @return number yOffset after card
F.Settings.BuildFontCard(parent, width, yOffset, label, configPrefix, get, set)
```

Contains: Font face dropdown, font size slider (6-24), outline dropdown (None/Outline/Mono), shadow toggle.

Used in: IndicatorCRUD (duration font, stack font per indicator), BorderIconSettings (stack/duration fonts), FrameSettingsBuilder (name/health/power text).

### BuildGlowCard

```lua
--- Build a glow settings card with per-type conditional sliders.
--- @param parent Frame
--- @param width number
--- @param yOffset number
--- @param get function(key) -> value
--- @param set function(key, value)
--- @param opts? { allowNone: boolean } -- if true, dropdown includes 'None'
--- @return number yOffset after card
F.Settings.BuildGlowCard(parent, width, yOffset, get, set, opts)
```

Contains: Glow type dropdown, color picker (hidden if None), per-type sliders with visibility toggling.

Used in: IndicatorCRUD (Icon/Icons glow card, standalone Glow indicator), TargetedSpells panel.

### BuildPositionCard

```lua
--- Build a position & layer card: anchor picker + X/Y sliders + frame level.
--- @param parent Frame
--- @param width number
--- @param yOffset number
--- @param get function(key) -> value
--- @param set function(key, value)
--- @param opts? { hideFrameLevel: boolean, hidePosition: boolean }
--- @return number yOffset after card
F.Settings.BuildPositionCard(parent, width, yOffset, get, set, opts)
```

Contains: AnchorPicker, X offset slider (-50 to 50), Y offset slider (-50 to 50), Frame level slider (1-20).

Options:
- `hideFrameLevel` — hides the frame level slider (for cases where it's not relevant)
- `hidePosition` — hides anchor picker + X/Y sliders, shows only frame level. Used by Border and simple indicator types that are always full-frame but still need layer control.

Frame level is merged into this card since it's always a positioning/layering concern. Reduces card count per indicator type by 1.

Used in: Every indicator type in IndicatorCRUD, aura panels (MissingBuffs, PrivateAuras, Dispels, etc.), Border (with `hidePosition`), simple indicators (with `hidePosition`).

### BuildThresholdColorCard

```lua
--- Build a threshold color card with low-time-% and low-seconds conditional color pickers.
--- @param parent Frame
--- @param width number
--- @param yOffset number
--- @param get function(key) -> value
--- @param set function(key, value)
--- @param opts? { showBorderColor: boolean, showBgColor: boolean }
--- @return number yOffset after card
F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set, opts)
```

Contains: Base color picker, "Low Time" toggle + threshold % slider + color picker (hidden when off), "Low Seconds" toggle + threshold seconds slider + color picker (hidden when off). Optional border color and background color pickers.

Used in: Bar/Bars (with border/bg colors), Color (Rect), Overlay. Replaces the old `BuildSimpleIndicatorCard` — Color and Overlay now have full threshold color support per Cell's UX.

### File Organization

All four shared builders live in a single file: `Settings/Builders/SharedCards.lua`. Each function is ~50-120 lines, totaling ~350 lines — well under the 500-line limit. One file, one import, four exports on `F.Settings`: `BuildFontCard`, `BuildGlowCard`, `BuildPositionCard`, `BuildThresholdColorCard`.

---

## Part 3: Buffs Indicator Settings Expansion

### Approach

The CRUD flow (create → list → edit) stays unchanged. We expand the **edit panel** for each indicator type with proper settings cards. Cards use conditional show/hide — e.g., duration font settings only appear when duration is enabled.

### Create Card Change

Add a **display type selector** that is **conditionally shown when Icon or Icons is selected** as the type:

- Two toggle buttons: **Spell Icons** | **Square Colors**
- Default: Spell Icons
- Hidden when type is Bar, Bars, Border, Color, Overlay, or Glow
- Sets `displayType` in the created indicator config: `'SpellIcon'` or `'ColoredSquare'`

This same toggle also appears at the **top of the Icon/Icons edit panel** so users can switch display type after creation without deleting and recreating the indicator. Changing it triggers a full `Rebuild()` since the renderer visual output changes.

#### Indicator Type Description

Below the type dropdown in the Create card, show a description FontString that updates when the dropdown selection changes. Helps users understand what each type does without trial and error.

| Type | Description |
|------|-------------|
| Icon | Single spell icon or colored square |
| Icons | Row/grid of spell icons or colored squares |
| Bar | Single depleting status bar |
| Bars | Row/grid of depleting status bars |
| Color | Colored rectangle positioned on frame |
| Overlay | Health bar overlay — depleting, static fill, or both |
| Border | Colored border around the frame edge |
| Glow | Glow effect around the frame |

FrameBar is no longer a separate create type — it's now the "FrameBar" mode within Overlay. Existing `FRAME_BAR` indicators in saved variables are handled by the Overlay renderer (which checks `overlayMode`). The `FRAME_BAR` constant is kept for backward compat in the RENDERERS dispatch table, routing to the Overlay renderer with `overlayMode = 'FrameBar'`.

Text uses `C.Colors.textSecondary` and `C.Font.sizeSmall`. Updates instantly on dropdown change — no separate action needed.

### Per-Spell Color (Square Colors Mode)

When indicator `displayType == 'ColoredSquare'`, each row in the spell list gets a color picker swatch next to the existing up/down/delete controls. The spell list widget accepts an `opts.showColorPicker` flag and reads from `spellColors` table. Colors stored in config as:

```lua
spellColors = {
    [spellId] = { r, g, b },
}
```

The Icon/Icons renderer reads `spellColors[spellId]` at Update time and applies it to the colored square background.

### Spell List Order = Priority

For **single-value renderers** (Icon, Bar, Border, Color, Overlay, Glow), when multiple tracked spells are active simultaneously on a unit, the **spell list order determines priority** — the spell at position 1 takes precedence over position 2, and so on. The first matching active aura wins; later matches are ignored.

In `Buffs.lua` Update, when dispatching to a single-value renderer, `break` after the first match in `_spellLookup` iteration order. The spell list widget's up/down reorder buttons directly control priority — this should be communicated to users via tooltip on the reorder buttons: "Higher = higher priority when multiple spells are active."

For **multi-value renderers** (Icons, Bars), all matching active auras display up to `maxDisplayed`. Order in the display follows spell list order for spell-specific matches, then aura iteration order for track-all indicators.

### Icon & Icons Edit Settings

Icon and Icons share **one edit panel**. The only difference: Icons shows an extra Layout card. A single `if(indicatorType == 'Icons')` check controls that card's visibility.

#### Size Card
| Setting | Widget | Config Key |
|---------|--------|------------|
| Width | Slider 8-48 (default 14) | `iconWidth` |
| Height | Slider 8-48 (default 14) | `iconHeight` |

No backward compat needed — alpha only, old `iconSize` keys can be reset.

#### Layout Card (Icons only — hidden for single Icon)
| Setting | Widget | Config Key |
|---------|--------|------------|
| Max Displayed | Slider 1-10 (default 3) | `maxDisplayed` |
| Num Per Line | Slider 0-10 (0=single row) | `numPerLine` |
| Spacing X | Slider 0-20 (default 1) | `spacingX` |
| Spacing Y | Slider 0-20 (default 1) | `spacingY` |
| Orientation | Dropdown: Right/Left/Up/Down | `orientation` |

#### Cooldown & Duration Card
| Setting | Widget | Config Key | Visibility |
|---------|--------|------------|------------|
| Show Cooldown | Toggle | `showCooldown` | Always |
| Show Duration | Dropdown: Never, Always, <75%, <50%, <25%, <15s, <5s | `durationMode` | Always |

Cooldown and duration are both temporal display on the icon — one card instead of two. When `durationMode != 'Never'`, card grows to show font settings via `BuildFontCard()` with prefix `durationFont`.

Duration threshold logic in Buffs.lua Update: compare `(expirationTime - GetTime()) / duration` against percentage thresholds, or `expirationTime - GetTime()` against second thresholds. Only show duration text when condition met.

`durationMode` values: `'Never'`, `'Always'`, `'<75'`, `'<50'`, `'<25'`, `'<15s'`, `'<5s'`

Dropdown labels include the less-than symbol for clarity: "Never", "Always", "<75%", "<50%", "<25%", "<15s", "<5s".

#### Stack Card
| Setting | Widget | Config Key | Visibility |
|---------|--------|------------|------------|
| Show Stacks | Toggle | `showStacks` | Always |

When `showStacks` is enabled, card grows to show font settings via `BuildFontCard()` with prefix `stackFont`.

#### Glow Card

Built via `BuildGlowCard()` with `allowNone = true`. Glow applies to the individual icon frame when active.

#### Position & Layer Card

Built via `BuildPositionCard()`. X/Y offsets are sliders (not edit boxes).

### Bar Edit Settings (Cell: "Bar")

| Setting | Widget | Config Key |
|---------|--------|------------|
| Width | Slider 3-500 (default 50) | `barWidth` |
| Height | Slider 3-500 (default 4) | `barHeight` |
| Orientation | Dropdown: Horizontal/Vertical | `barOrientation` |
| Color | Color picker | `color` |
| Low Time Color | Toggle + threshold % + color picker | `lowTimeColor` |
| Low Seconds Color | Toggle + threshold seconds + color picker | `lowSecsColor` |
| Border Color | Color picker | `borderColor` |
| Background Color | Color picker with alpha | `bgColor` |
| Show Stacks | Toggle | `showStacks` |
| Show Duration | Dropdown (same modes as Icon) | `durationMode` |

When `showStacks` is enabled, show font settings via `BuildFontCard()` with prefix `stackFont`. Same for duration.

Glow via `BuildGlowCard()` with `allowNone = true`. Position & Layer via `BuildPositionCard()`.

### Bars Edit Settings (Cell: "Bars" — NEW)

Bars is to Bar what Icons is to Icon — a multi-bar layout. Bar and Bars share **one edit panel**, with Bars showing an extra Layout card (same pattern as Icon/Icons).

#### Size Card
| Setting | Widget | Config Key |
|---------|--------|------------|
| Width | Slider 3-500 (default 50) | `barWidth` |
| Height | Slider 3-500 (default 4) | `barHeight` |
| Orientation | Dropdown: Horizontal/Vertical | `barOrientation` |

#### Layout Card (Bars only — hidden for single Bar)
| Setting | Widget | Config Key |
|---------|--------|------------|
| Max Displayed | Slider 1-10 (default 3) | `maxDisplayed` |
| Num Per Line | Slider 0-10 (0=single row) | `numPerLine` |
| Spacing X | Slider -1 to 50 (default 1) | `spacingX` |
| Spacing Y | Slider -1 to 50 (default 1) | `spacingY` |
| Layout Direction | Dropdown: Right/Left/Up/Down | `orientation` |

Note: `barOrientation` controls how each individual bar fills (horizontal/vertical), while `orientation` controls how multiple bars are arranged in the grid. These are independent.

#### Color Card
| Setting | Widget | Config Key |
|---------|--------|------------|
| Color | Color picker | `color` |
| Low Time Color | Toggle + threshold % + color picker | `lowTimeColor` |
| Low Seconds Color | Toggle + threshold seconds + color picker | `lowSecsColor` |
| Border Color | Color picker | `borderColor` |
| Background Color | Color picker with alpha | `bgColor` |

#### Stack & Duration Card
Same as Icon — `showStacks` toggle with font, `durationMode` dropdown with font.

Glow via `BuildGlowCard()`. Position & Layer via `BuildPositionCard()`.

#### Bars Renderer (New File)

New file: `Elements/Indicators/Bars.lua`. Mirrors the Icons renderer pattern:
- Creates a pool of Bar sub-frames arranged in a grid
- Each sub-frame is a StatusBar with border, background, optional stack/duration text
- `SetBars(auraList)` — positions and fills bars from aura data
- `Clear()` — hides all bars
- Grid layout uses `numPerLine`, `spacingX`, `spacingY`, `orientation`
- Individual bar fill direction uses `barOrientation`

### Color Edit Settings (Cell: "Rect")

Cell's "Rect" is a positioned, sized colored rectangle — NOT a simple full-frame tint. It has full indicator settings.

| Setting | Widget | Config Key |
|---------|--------|------------|
| Width | Slider 3-500 (default 10) | `rectWidth` |
| Height | Slider 3-500 (default 10) | `rectHeight` |
| Color | Color picker | `color` |
| Low Time Color | Toggle + threshold % + color picker | `lowTimeColor` |
| Low Seconds Color | Toggle + threshold seconds + color picker | `lowSecsColor` |
| Border Color | Color picker | `borderColor` |
| Show Stacks | Toggle | `showStacks` |
| Show Duration | Dropdown (same modes as Icon) | `durationMode` |

When stacks/duration enabled, show font settings via `BuildFontCard()`. Glow via `BuildGlowCard()`. Position & Layer via `BuildPositionCard()`.

### Overlay / FrameBar Edit Settings (Merged Panel)

Overlay (Cell: "Texture") and FrameBar are both health-bar-anchored indicators. They share one edit panel with a **mode dropdown** at the top that controls which settings are visible and how the renderer behaves.

#### Mode Dropdown

| Mode | Behavior | Description |
|------|----------|-------------|
| **Overlay** | Depleting bar that shrinks as aura duration runs out | Cell's "Texture" equivalent — shows remaining duration visually |
| **FrameBar** | Fixed-fill bar that shows while aura is active | Static color overlay, no depletion animation |
| **Both** | Overlay depletion layered on top of FrameBar fill | FrameBar as background tint + Overlay depletion on top for duration feedback |

Config key: `overlayMode` — values `'Overlay'`, `'FrameBar'`, `'Both'` (default `'Overlay'`).

#### Settings (conditional visibility based on mode)

| Setting | Widget | Config Key | Visible When |
|---------|--------|------------|-------------|
| Mode | Dropdown: Overlay / FrameBar / Both | `overlayMode` | Always |
| Color | Color picker with alpha | `color` | Always |
| Low Time Color | Toggle + threshold % + color picker | `lowTimeColor` | Overlay or Both |
| Low Seconds Color | Toggle + threshold seconds + color picker | `lowSecsColor` | Overlay or Both |
| Smooth | Toggle (smooth depletion animation) | `smooth` | Overlay or Both |
| Orientation | Dropdown: Horizontal/Vertical | `barOrientation` | Overlay or Both |

Uses `BuildPositionCard()` with `hidePosition = true` (always anchored to health bar — only frame level relevant).

Changing the mode fires `CONFIG_CHANGED` and triggers a `Rebuild()` since the renderer structure changes (depletion vs static fill). In "Both" mode, the Overlay renderer creates two texture layers — a static fill at the base frame level and a depleting overlay one level above.

**Both mode alpha behavior:** The FrameBar layer uses `color` alpha as-is (the user controls its intensity). The Overlay (depleting) layer always renders at **full opacity (1.0)** regardless of the `color` alpha setting, so the depletion visual is always clearly visible on top of the static fill. This prevents the case where a low-alpha color (e.g., `{1, 0, 0, 0.3}`) produces two barely-visible stacked layers. If the user wants a subtle Overlay, they control that via the FrameBar color alpha alone — the depletion bar stays crisp.

### Border Edit Settings (Cell: "Border")

| Setting | Widget | Config Key |
|---------|--------|------------|
| Thickness | Slider 1-15 (default 2) | `borderThickness` |
| Color | Color picker | `color` |
| Fade Out | Toggle (fade animation when aura expires) | `fadeOut` |

Uses `BuildPositionCard()` with `hidePosition = true` (borders always wrap the frame edge — only frame level is relevant).

### Glow (Standalone) Edit Settings (Cell: "Glow")

| Setting | Widget | Config Key |
|---------|--------|------------|
| Fade Out | Toggle (fade when aura expires) | `fadeOut` |

Glow type/color/params via `BuildGlowCard()` with `allowNone = false`. Uses `BuildPositionCard()` with `hidePosition = true`.

### Cell ↔ Framed Type Mapping

| Cell Type | Framed Type | Key Difference |
|-----------|-------------|----------------|
| Icon | Icon | Identical concept |
| Icons | Icons | Identical concept |
| Bar | Bar | Identical concept |
| Bars | **Bars (NEW)** | Multi-bar grid layout |
| Rect | Color | Cell "Rect" is a positioned rectangle; Framed "Color" currently simpler — expanding to match |
| Overlay/Texture | Overlay (mode: Overlay) | Cell has depletion direction + threshold colors |
| Border | Border | Cell adds fadeOut toggle |
| Glow | Glow | Cell adds fadeOut toggle |
| Color | Overlay (mode: FrameBar) | Cell "Color" is a full-frame tint; Framed merges FrameBar + Overlay into one type with mode selector |
| Text | — | Not in Framed (text-only indicator, no icon/bar) |
| Block/Blocks | — | Not in Framed (colored blocks with duration/stack-based coloring) |

### Renderer Changes Required

| Renderer | Change |
|----------|--------|
| **Icon** | Accept `iconWidth`/`iconHeight`. Accept `durationMode` threshold. Accept `durationFont`/`stackFont` config. Accept `spellColors` for ColoredSquare mode. Accept glow params per-icon on active aura. |
| **Icons** | Same as Icon, plus accept `numPerLine`, `spacingX`, `spacingY`. |
| **Bar** | Accept `barWidth`/`barHeight`/`barOrientation`. Accept threshold color changes (`lowTimeColor`, `lowSecsColor`). Accept `borderColor`/`bgColor`. Accept `showStacks`/`durationMode` with fonts. |
| **Bars (NEW)** | New renderer. Multi-bar grid using Bar sub-frames. Accept all Bar settings plus `maxDisplayed`, `numPerLine`, `spacingX`/`spacingY`, `orientation`. |
| **Color** | Expand from simple tint to positioned rectangle. Accept `rectWidth`/`rectHeight`. Accept threshold colors, stack/duration, glow. |
| **Overlay** | Accept `overlayMode` (Overlay/FrameBar/Both). Accept `barOrientation` for depletion direction. Accept threshold colors (`lowTimeColor`, `lowSecsColor`). Accept `smooth` toggle. In FrameBar mode: static fill, no depletion. In Both mode: two layers. |
| **Border** | Accept `borderThickness`. Accept `color`. Accept `fadeOut` toggle. |
| **Glow** | Accept `fadeOut` toggle. |

### AuraDefaults Expansion

`Presets/AuraDefaults.lua` needs updated defaults for all new config keys so nil reads don't occur:

```lua
-- Icon/Icons defaults
iconWidth     = 14,
iconHeight    = 14,
showCooldown  = true,
showStacks    = true,
durationMode  = 'Never',
durationFont  = { face = nil, size = 10, outline = '', shadow = true },
stackFont     = { face = nil, size = 10, outline = 'OUTLINE', shadow = false },
glowType      = 'None',
glowColor     = { 1, 1, 1, 1 },
glowConfig    = {},
numPerLine    = 0,
spacingX      = 1,
spacingY      = 1,

-- Bar/Bars defaults
barWidth        = 50,
barHeight       = 4,
barOrientation  = 'Horizontal',
color           = { 1, 1, 1, 1 },
lowTimeColor    = { enabled = false, threshold = 25, color = { 1, 0.5, 0, 1 } },
lowSecsColor    = { enabled = false, threshold = 5,  color = { 1, 0, 0, 1 } },
borderColor     = { 0, 0, 0, 1 },
bgColor         = { 0, 0, 0, 0.5 },

-- Color (Rect) defaults
rectWidth       = 10,
rectHeight      = 10,

-- Overlay / FrameBar defaults (merged type)
overlayMode     = 'Overlay',   -- 'Overlay' | 'FrameBar' | 'Both'
smooth          = true,

-- Border defaults
borderThickness = 2,
fadeOut          = false,
```

```lua
-- Buffs element-level defaults (per unit type)
hideUnimportantBuffs = true,  -- party/raid only; false for solo/arena/boss
```

The old `iconSize` key is removed from defaults. Existing saved variables will be wiped via `/framed reset all`.

### Live Update Wiring

All Buffs indicator settings changes fire `CONFIG_CHANGED` with path `presets.<name>.auras.<unitType>.buffs`. The AuraConfig listener calls `element:Rebuild(newConfig)` which:

1. Calls `Destroy()` on each existing renderer
2. Rebuilds `_indicators`, `_spellLookup`, `_hasTrackAll` from fresh config
3. Calls `ForceUpdate()` to re-render with new auras

Rebuild is always a full rebuild since indicator renderers are cheap to create and it ensures consistency.

---

## Part 4: `/framed reset all` Command

### Purpose

Alpha-only escape hatch. Wipes all saved variables and reloads to factory defaults. Critical for development when config schema changes break the addon.

### Slash Command

Add to existing slash command handler in `Init.lua`:

```lua
elseif(cmd == 'reset' and arg1 == 'all') then
    F.Settings.ShowResetDialog()
```

### Dialog Flow

**Single confirmation dialog:**
- Title: "Reset All Settings"
- Body text in **red**: "This will delete ALL Framed settings, presets, and customizations. A backup will be saved — you can restore later with /framed restore."
- Left button: "Yes, Reset Everything" (red tint)
- Right button: "Cancel"

One dialog is sufficient since the backup/restore mechanism provides a safety net. If user clicks "Yes, Reset Everything":

```lua
-- Snapshot current state before wiping
FramedBackupDB = {
    db   = FramedDB and CopyTable(FramedDB) or nil,
    char = FramedCharDB and CopyTable(FramedCharDB) or nil,
    timestamp = time(),
}
FramedDB = nil
FramedCharDB = nil
ReloadUI()
```

### `/framed restore` Command

Restores the backup taken during the last reset. Added to `Init.lua` alongside `reset all`:

```lua
elseif(cmd == 'restore') then
    if(not FramedBackupDB or not FramedBackupDB.db) then
        print('Framed: No backup found. Nothing to restore.')
        return
    end
    local ts = FramedBackupDB.timestamp
    local dateStr = ts and date('%Y-%m-%d %H:%M', ts) or 'unknown date'
    Widgets.ShowConfirmDialog(
        'Restore Settings',
        'Restore settings from backup taken on ' .. dateStr .. '?\nThis will overwrite your current configuration.',
        function()
            FramedDB = CopyTable(FramedBackupDB.db)
            FramedCharDB = FramedBackupDB.char and CopyTable(FramedBackupDB.char) or nil
            ReloadUI()
        end,
        nil
    )
```

The backup persists across reloads since `FramedBackupDB` is a SavedVariable. Only one backup is kept — each reset overwrites the previous backup.

### Implementation

Uses `Widgets.ShowConfirmDialog()` which returns the dialog frame. Custom button labels and red text are applied after the call:

```lua
local function showResetDialog()
    local d = Widgets.ShowConfirmDialog(
        'Reset All Settings',
        'This will delete ALL Framed settings, presets, and customizations.\nA backup will be saved — you can restore later with /framed restore.',
        function()
            FramedBackupDB = {
                db   = FramedDB and CopyTable(FramedDB) or nil,
                char = FramedCharDB and CopyTable(FramedCharDB) or nil,
                timestamp = time(),
            }
            FramedDB = nil
            FramedCharDB = nil
            ReloadUI()
        end,
        nil
    )
    d._message:SetTextColor(1, 0.2, 0.2)
    d._btnYes._label:SetText('Yes, Reset Everything')
    d._btnNo._label:SetText('Cancel')
end
```

### Slash Command Location

The slash command handler is in `Init.lua` (lines 94-164), not `Core/SlashCommands.lua`. Add the `reset all` and `restore` cases there.

---

## Part 5: Implementation Guidelines

### Rendering Verification

Every element and indicator type must render visually on frames — settings and live-update wiring are useless without actual rendering. Implementation must verify the full pipeline: **config → Setup/Apply → event fires → Update runs → visual appears on frame**.

#### Current Rendering State (audited)

All core elements (Health, Power, Name, Castbar, HealthPrediction, all 11 status icons) and all aura elements (Debuffs, RaidDebuffs, Externals, Defensives, Dispellable, TargetedSpells, Buffs, MissingBuffs, PrivateAuras) are rendering end-to-end. All existing indicator renderers (Icon, Icons, Bar, Border, Color, Overlay, Glow, BorderIcon) have working Create/Show/Hide/SetAura methods. FrameBar is merged into Overlay as a mode.

**Not yet rendering**: LoC and CC — elements exist and work standalone but are not called in `Apply()`. Fixed by this spec (Part 1, LoC & CC Wiring).

#### New/Changed Renderers Requiring Rendering Verification

| Renderer | What to Verify |
|----------|---------------|
| **Bars (NEW)** | Multi-bar grid creates StatusBar sub-frames, positions them in grid, fills/depletes correctly, shows stack/duration text |
| **Bar (expanded)** | Threshold color transitions work (low time %, low seconds), border/background colors render, stack/duration text visible |
| **Color (expanded)** | Now a positioned rectangle (not full-frame tint) — verify it creates a sized frame at anchor position, shows threshold colors |
| **Overlay (expanded, merged with FrameBar)** | `overlayMode` Overlay: depletion works for both orientations, smooth animates, threshold colors transition. FrameBar: static fill visible while aura active. Both: two layers render correctly (static underneath, depleting on top) |
| **Border (expanded)** | fadeOut animation plays when aura expires (not just instant hide) |
| **Glow (expanded)** | fadeOut animation plays when aura expires |

#### Health Bar Color Modes

All health color modes are already rendering:
- `colorClass` — oUF colors by class
- `colorReaction` — oUF colors by NPC reaction
- `colorSmooth` — gradient from red→yellow→green based on HP %
- `dark` / custom — flat color via PostUpdate

Frame strata defaults are set by `Widgets.CreateStatusBar()` and `CreateTexture(nil, 'OVERLAY')` throughout. Each aura element's `frameLevel` config is applied at Setup time. The default positions table (Part 0.5) assigns frame levels to prevent z-fighting between overlapping center elements (Raid Debuffs: 20, TargetedSpells: 50, LoC: 30, Dispellable: 15).

### 12.0.1 API Notes

These notes guide implementation decisions — no spec design changes needed, but implementors must be aware:

**`Enum.SecretAspect.CooldownStyle` (NEW):** Cooldown display properties may be protected in some contexts. Icon and BorderIcon cooldown rendering (`SetCooldown`, cooldown swipe) must handle the case where cooldown style is secret. Defensive approach: wrap cooldown style configuration in `F.IsValueNonSecret()` checks. Do NOT break existing BorderIcon behavior — it already works everywhere; this is purely additive protection.

**`UnitCastingInfo` return value 11 `delayTimeMs` (NEW):** oUF's castbar element (`Libs/oUF/elements/castbar.lua:195`) currently destructures 10 return values and does not capture `delayTimeMs`. During implementation, extend our castbar's PostUpdate (or patch the element if needed) to read value 11 and display pushback time. Do not modify oUF's castbar.lua directly — use a PostUpdate hook or override the Path function.

**`DurationObject:GetClockTime` (NEW):** The `DurationObject` API is expanding. Our Bar renderer's `SetTimerDuration` path already uses `CreateLuaDurationObject()` when available. Implementation should check if `GetClockTime` provides a cleaner way to read remaining time for duration text display.

**`FontString:ClearText` (NEW):** Minor convenience — can replace `:SetText('')` calls. Use where appropriate during implementation.

### Existing Elements — Do Not Rewrite

This spec adds settings, live-update wiring, and rendering for elements that **already exist and work**. Implementation must build on top of existing code, not rewrite it. Key elements to preserve:

- **RaidDebuffs** — already uses 12.0.1 C-level `HARMFUL|RAID` server-side filtering and priority. Do not add manual debuff lists or per-boss filtering — the API handles this.
- **Debuffs** — debuff filtering in Midnight is handled server-side via `C_UnitAuras` filter flags. Do not add client-side blacklists.
- **HealthPrediction** — already updated to use `UnitHealPredictionCalculator` (committed previously). Do not duplicate.
- **Range** — oUF's Range element handles OOR alpha fade. Do not duplicate.
- **Aggro/threat highlighting** — oUF provides this via `ThreatIndicator` element. Out of scope for this spec.
- **TargetedSpells, PrivateAuras, Dispellable, CrowdControl, LossOfControl** — all exist as working elements. This spec only adds settings wiring, enabled toggles, and `Rebuild()` methods.

### Krealle's PR 463 Principles (enderneko/Cell#463)

All implementation must follow the coding principles established from Krealle's review feedback on Cell PR 463. These are foundational to Framed's code quality:

1. **No pcall for error suppression** — feature detect (`if C_API then`) before executing dependent logic, never wrap in pcall to catch errors
2. **One shared secret value wrapper** — `F.IsValueNonSecret()` in `Core/SecretValues.lua`, used everywhere. No per-file wrappers, polyfills, or alternative check functions
3. **No aura sanitization** — never replace secret stacks/duration with placeholder strings (`""`). Pass secret values through to C-level APIs that accept them (`SetValue`, `SetVertexColor`, `SetFormattedText`), or degrade gracefully by hiding the display element
4. **Treat potentially-secret auras as always secret** — don't juggle mixed secret/non-secret state. If an aura field *could* be secret, code as if it always is
5. **No `rawequal()`** — plain `==` works. `rawX` methods are for metatables
6. **Prefer focused commits** — good practice for traceability, but not a hard gate during alpha
7. **Review AI output thoroughly** — inconsistencies between files (e.g., bare `issecretvalue()` in one file and `F.IsValueNonSecret()` in another) indicate inadequate review
8. **Respect existing code structure** — build on existing patterns, don't introduce non-generic duplicated workarounds across files

### No Cell References in Code

Cell references in this spec (section headings, mapping table, design notes) are for **design-time context only**. No Lua code, comments, UI labels, config keys, or variable names should reference Cell, ElvUI, or any other addon by name. All naming must be Framed's own terminology.

### No Stubs Policy

Every feature in this spec must be **fully implemented or not started**. No `-- TODO`, `-- Coming Soon`, `-- Placeholder`, or empty function bodies. If a feature hits an unexpected blocker during implementation:

1. **Stop and ask** — do not leave a stub and move on
2. **Investigate the root cause** — is it a missing widget, a Blizzard API limitation, a design gap?
3. **Resolve or redesign** — either fix the blocker or revise the spec to remove/change the feature
4. **Never ship dead code** — no unused config keys, no settings that write to config nothing reads, no UI elements that don't do anything

### Post-Implementation Code Review

After all implementation is complete, run a **superpowers code review** (`code-reviewer` agent) to verify:

- All spec items are fully implemented (no gaps or stubs)
- Every element and indicator type renders visually on frames (config → Setup → event → Update → visual)
- New/expanded renderers (Bars, Bar threshold colors, Color as positioned rect, Overlay modes (Overlay/FrameBar/Both), Border/Glow fadeOut) confirmed working
- Live-update handlers actually work (config change → frame updates without reload)
- Shared builders are used everywhere they should be (no duplicated font/glow/position/threshold-color UI code)
- No orphaned config keys (every key written by settings is read by an element)
- No orphaned elements (every element set up in Apply() has a settings panel)
- Frame levels don't z-fight (center elements layered correctly per Part 0.5 defaults)
- Code style matches CLAUDE.md conventions (tabs, parenthesized conditions, camelCase locals, etc.)
- File sizes stay under ~500 lines
- PR 463 principles enforced: no pcall suppression, single `F.IsValueNonSecret()` wrapper used everywhere, no aura sanitization, no `rawequal()`, potentially-secret auras treated as always secret

---

## Files Changed Summary

### New Files
- `Units/LiveUpdate/FrameConfig.lua` — All `unitConfigs.*` live-update handlers: dimensions, position, power, castbar, shields/absorbs, status icons, show/hide toggles, text, health colors, highlights, combat queue with UX feedback
- `Units/LiveUpdate/AuraConfig.lua` — All `presets.*.auras.*` handlers: aura elements, debounced Rebuild, enabled toggle wiring
- `Settings/Builders/SharedCards.lua` — All shared settings builders (FontCard, GlowCard, PositionCard, ThresholdColorCard)

### Modified Files
- `Units/StyleBuilder.lua` — Remove listener registrations, add `ForEachFrame()` export, add LoC/CC to `Apply()`
- `Elements/Indicators/BorderIcon.lua` — Add `Destroy()` method
- `Elements/Indicators/Icon.lua` — Accept width/height, duration threshold, font config, spell colors, glow
- `Elements/Indicators/Icons.lua` — Same as Icon, plus numPerLine/spacingX/spacingY
- `Elements/Indicators/Bar.lua` — Accept barWidth/barHeight/barOrientation, threshold colors, border/bg colors, stack/duration
- `Elements/Indicators/Bars.lua` — **NEW** multi-bar grid renderer (mirrors Icons pattern for bars)
- `Elements/Indicators/Border.lua` — Accept borderThickness, color, fadeOut
- `Elements/Indicators/Color.lua` — Expand from simple tint to positioned rectangle with size, threshold colors, stack/duration, glow
- `Elements/Indicators/Overlay.lua` — Merge FrameBar into Overlay with `overlayMode` (Overlay/FrameBar/Both), accept barOrientation, threshold colors, smooth toggle
- `Elements/Auras/Buffs.lua` — Add `Rebuild(config)` method, duration threshold filtering, `hideUnimportantBuffs` filter, spell priority (break on first match for single-value renderers), add `BARS` to RENDERERS dispatch table
- `Elements/Auras/MissingBuffs.lua` — Add `Rebuild(config)` method
- `Elements/Auras/TargetedSpells.lua` — Add `Rebuild(config)` method
- `Elements/Status/LossOfControl.lua` — Add `Rebuild(config)` method
- `Elements/Status/CrowdControl.lua` — Add `Rebuild(config)` method
- `Settings/Builders/IndicatorCRUD.lua` — Expand edit panel per-type, use shared builders, add type description in Create card, add Refresh() callback
- `Settings/Builders/BorderIconSettings.lua` — Use shared `BuildFontCard`, `BuildPositionCard`
- `Settings/Panels/TargetedSpells.lua` — Use shared `BuildGlowCard`
- `Settings/Panels/LossOfControl.lua` — Add enabled toggle at top
- `Settings/Panels/CrowdControl.lua` — Add enabled toggle at top
- `Settings/Panels/MissingBuffs.lua` — Add enabled toggle at top
- `Settings/Panels/PrivateAuras.lua` — Add enabled toggle at top
- `Elements/Indicators/Glow.lua` — Accept fadeOut toggle
- `Core/Constants.lua` — Add `IndicatorType.BARS` constant
- `Presets/AuraDefaults.lua` — Add new config key defaults, remove old `iconSize`, add LoC/CC default configs, add missing `enabled` flags, update positions per Part 0.5
- `Init.lua` — Add `reset all` and `restore` subcommands
- `Settings/Framework.lua` — Add `Refresh()` callback support for active panel, register `EDITING_PRESET_CHANGED` listener
- `Framed.toc` — Add LiveUpdate/* files (2 files, not 4), SharedCards.lua, bump version
