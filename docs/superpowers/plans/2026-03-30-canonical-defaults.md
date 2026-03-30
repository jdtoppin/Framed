# Canonical Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all scattered `or` fallback defaults with a single canonical defaults table in `Presets/Defaults.lua`, ensuring every config key has an explicit value in SavedVariables at first load.

**Architecture:** Expand `Presets/Defaults.lua` config functions from ~15 keys to ~80 keys each using a shared `baseUnitConfig()` helper. Delete redundant `StyleBuilder.DEFAULT_CONFIG` and fold `ICON_DEFAULTS` into preset defaults. Strip all `or fallback` patterns from consumer files (~150 instances across ~30 files). Update `EnsureDefaults()` to backfill new keys for existing users.

**Tech Stack:** WoW Lua (no test framework — all testing is manual in-game via `/framed reset all` + `/reload`)

**Spec:** `docs/superpowers/specs/2026-03-30-canonical-defaults-design.md`

---

## Decision Framework: Which `or` Patterns to Strip

Before stripping, classify each `or` pattern:

| Category | Action | Example |
|----------|--------|---------|
| **Config fallback** | **STRIP** | `config.health.colorMode or 'class'` → `config.health.colorMode` |
| **Settings card fallback** | **STRIP** | `getConfig('width') or 200` → `getConfig('width')` |
| **Nil-guard for guaranteed sub-table** | **STRIP guard + fallback** | `config.power and config.power.height or 0` → `config.power.height` |
| **Nil-guard for optional sub-table** | **KEEP guard, STRIP value fallback** | `config.castbar or {}` → wrap in `if(config.castbar) then` |
| **Conditional logic** | **KEEP** | `(sizeMode == 'detached' and cbCfg.width) or config.width` |
| **Runtime API fallback** | **KEEP** | `frame.unit or frame:GetAttribute('unit')` |
| **Color alpha channel** | **STRIP** (ensure 4-element colors in defaults) | `color[4] or 1` → `color[4]` |
| **UI layout fallback** | **KEEP** | `parent._explicitWidth or parent:GetWidth() or 530` |
| **Function existence check** | **KEEP** | `F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'` |
| **Error/input fallback** | **KEEP** | `err or 'unknown error'`, `btnVal or 'LeftButton'` |

**Guaranteed sub-tables** (always exist in defaults): `health`, `power`, `name`, `range`, `statusIcons`, `statusText`, `position`

**Optional sub-tables** (nil means feature disabled): `castbar`, `portrait`, `threat`

---

## File Structure

| File | Change |
|------|--------|
| `Presets/Defaults.lua` | Add `baseUnitConfig()` helper, expand all 9 config functions to ~80 keys, update `EnsureDefaults()` |
| `Core/Config.lua` | Expand `accountDefaults.general`, add `charDefaults` keys |
| `Units/StyleBuilder.lua` | Delete `DEFAULT_CONFIG`, delete `ICON_DEFAULTS`, update `GetConfig()` fallback chain |
| `Units/LiveUpdate/FrameConfig.lua` | Strip ~100 config `or` fallbacks |
| `Settings/Cards/*.lua` (11 files) | Strip ~70 config `or` fallbacks |
| `Settings/Panels/*.lua` (3 files) | Strip ~10 aura config `or` fallbacks |
| `Elements/Status/*.lua` (12 files) | Strip ~40 config `or` fallbacks |
| `Units/*.lua` (9 spawn files) | Strip ~25 config `or` fallbacks |

---

### Task 1: Expand Presets/Defaults.lua with Complete Unit Configs

**Files:**
- Modify: `Presets/Defaults.lua`

This is the foundation. Every subsequent task depends on these defaults being complete.

- [ ] **Step 1: Add `baseUnitConfig()` helper function**

Insert after the `local C = F.Constants` line and before `local function playerConfig()`. This returns the complete set of keys shared across all unit types. Values are sourced from `StyleBuilder.DEFAULT_CONFIG` (the current authoritative defaults).

```lua
--- Base config shared by all unit types. Each unit config function calls this
--- and overrides unit-specific values. Every key that any consumer reads must
--- exist here or in the unit-specific override.
local function baseUnitConfig()
	return {
		width  = 200,
		height = 40,
		position = { x = 0, y = 0, anchor = 'CENTER' },
		health = {
			colorMode          = 'class',
			colorThreat        = false,
			smooth             = true,
			customColor        = { 0.2, 0.8, 0.2, 1 },
			gradientColor1     = { 0.2, 0.8, 0.2, 1 },
			gradientThreshold1 = 95,
			gradientColor2     = { 0.9, 0.6, 0.1, 1 },
			gradientThreshold2 = 50,
			gradientColor3     = { 0.8, 0.1, 0.1, 1 },
			gradientThreshold3 = 5,
			lossColorMode      = 'dark',
			lossCustomColor    = { 0.15, 0.15, 0.15, 1 },
			lossGradientColor1     = { 0.1, 0.4, 0.1, 1 },
			lossGradientThreshold1 = 95,
			lossGradientColor2     = { 0.4, 0.25, 0.05, 1 },
			lossGradientThreshold2 = 50,
			lossGradientColor3     = { 0.4, 0.05, 0.05, 1 },
			lossGradientThreshold3 = 5,
			showText           = false,
			textFormat         = 'percent',
			textColorMode      = 'white',
			textCustomColor    = { 1, 1, 1, 1 },
			fontSize           = C.Font.sizeSmall,
			textAnchor         = 'CENTER',
			textAnchorX        = 0,
			textAnchorY        = 0,
			outline            = '',
			shadow             = true,
			attachedToName     = false,
			healPrediction     = true,
			healPredictionMode = 'all',
			healPredictionColor = { 0.6, 0.6, 0.6, 0.4 },
			damageAbsorb       = true,
			damageAbsorbColor  = { 1, 1, 1, 0.6 },
			healAbsorb         = true,
			healAbsorbColor    = { 0.7, 0.1, 0.1, 0.5 },
			overAbsorb         = true,
		},
		power = {
			height        = 2,
			position      = 'bottom',
			showText      = false,
			textFormat    = 'current',
			textColorMode = 'white',
			textCustomColor = { 1, 1, 1, 1 },
			fontSize      = C.Font.sizeSmall,
			textAnchor    = 'CENTER',
			textAnchorX   = 0,
			textAnchorY   = 0,
			outline       = '',
			shadow        = true,
		},
		name = {
			colorMode   = 'class',
			customColor = { 1, 1, 1, 1 },
			fontSize    = C.Font.sizeNormal,
			anchor      = 'CENTER',
			anchorX     = 0,
			anchorY     = 0,
			outline     = '',
			shadow      = true,
		},
		range = { outsideAlpha = 0.4 },
		statusIcons = {
			role       = true,
			rolePoint  = 'TOPLEFT',  roleX  = 2,   roleY  = -2, roleSize  = 12,
			leader     = true,
			leaderPoint = 'TOPLEFT', leaderX = 16,  leaderY = -2, leaderSize = 12,
			readyCheck = true,
			readyCheckPoint = 'CENTER', readyCheckX = 0, readyCheckY = 0, readyCheckSize = 16,
			raidIcon   = true,
			raidIconPoint = 'TOP',   raidIconX = 0,  raidIconY = -2, raidIconSize = 16,
			combat     = false,
			combatPoint = 'TOPRIGHT', combatX = -2,  combatY = -2, combatSize = 12,
			resting    = false,
			restingPoint = 'BOTTOMLEFT', restingX = 2, restingY = 2, restingSize = 12,
			phase      = true,
			phasePoint = 'CENTER',   phaseX = 0,    phaseY = 0,  phaseSize = 16,
			resurrect  = true,
			resurrectPoint = 'CENTER', resurrectX = 0, resurrectY = 0, resurrectSize = 16,
			summon     = true,
			summonPoint = 'CENTER',  summonX = 0,   summonY = 0, summonSize = 16,
			raidRole   = true,
			raidRolePoint = 'BOTTOMRIGHT', raidRoleX = -2, raidRoleY = 2, raidRoleSize = 12,
			pvp        = false,
			pvpPoint   = 'BOTTOMLEFT', pvpX = 2,    pvpY = 2,   pvpSize = 16,
		},
		statusText = {
			enabled  = true,
			fontSize = C.Font.sizeSmall,
			outline  = 'OUTLINE',
			shadow   = false,
			anchor   = 'CENTER',
			anchorX  = 0,
			anchorY  = 0,
		},
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end
```

- [ ] **Step 2: Add castbar/portrait/threat helper builders**

These are optional sub-tables — not every unit has them. Add right after `baseUnitConfig()`:

```lua
--- Default castbar config. Only added to units that show a cast bar.
local function defaultCastbar(frameWidth)
	return {
		height         = 16,
		sizeMode       = 'attached',
		width          = frameWidth,
		backgroundMode = 'always',
		showIcon       = true,
		showText       = true,
		showTime       = true,
	}
end

--- Default portrait config.
local function defaultPortrait()
	return { type = '2D' }
end

--- Default threat config.
local function defaultThreat()
	return { aggroBlink = false }
end
```

- [ ] **Step 3: Rewrite `playerConfig()` using base helper**

Replace the existing `playerConfig()` function entirely:

```lua
local function playerConfig()
	local c = baseUnitConfig()
	c.width  = 200
	c.height = 40
	c.position = { x = -200, y = -200, anchor = 'CENTER' }
	c.castbar  = defaultCastbar(200)
	c.portrait = defaultPortrait()
	c.threat   = defaultThreat()
	return c
end
```

- [ ] **Step 4: Rewrite `targetConfig()` using base helper**

```lua
local function targetConfig()
	local c = baseUnitConfig()
	c.width  = 200
	c.height = 40
	c.position = { x = 200, y = -200, anchor = 'CENTER' }
	c.castbar  = defaultCastbar(200)
	c.portrait = defaultPortrait()
	c.threat   = defaultThreat()
	return c
end
```

- [ ] **Step 5: Rewrite `targettargetConfig()` using base helper**

```lua
local function targettargetConfig()
	local c = baseUnitConfig()
	c.width  = 120
	c.height = 24
	c.position = { x = 200, y = -260, anchor = 'CENTER' }
	c.name.fontSize = C.Font.sizeSmall
	return c
end
```

Note: No castbar, portrait, or threat for targettarget. Health absorb fields remain at base defaults (enabled).

- [ ] **Step 6: Rewrite `focusConfig()` using base helper**

```lua
local function focusConfig()
	local c = baseUnitConfig()
	c.width  = 160
	c.height = 30
	c.position = { x = -300, y = -100, anchor = 'CENTER' }
	c.castbar = defaultCastbar(160)
	return c
end
```

- [ ] **Step 7: Rewrite `petConfig()` using base helper**

```lua
local function petConfig()
	local c = baseUnitConfig()
	c.width  = 120
	c.height = 20
	c.position = { x = -200, y = -260, anchor = 'CENTER' }
	c.name.fontSize = C.Font.sizeSmall
	return c
end
```

- [ ] **Step 8: Rewrite `bossConfig()` using base helper**

```lua
local function bossConfig()
	local c = baseUnitConfig()
	c.width  = 160
	c.height = 30
	c.position = { x = 300, y = 100, anchor = 'CENTER' }
	c.health.showText   = true
	c.health.textFormat = 'current'
	c.health.damageAbsorb = false
	c.health.healAbsorb   = false
	c.health.overAbsorb   = false
	c.castbar = defaultCastbar(160)
	c.spacing = 4
	return c
end
```

- [ ] **Step 9: Rewrite `partyConfig()` using base helper**

```lua
local function partyConfig()
	local c = baseUnitConfig()
	c.width  = 120
	c.height = 36
	c.position = { x = 40, y = -48, anchor = 'TOPLEFT' }
	c.health.showText   = true
	c.health.textFormat = 'percent'
	c.name.fontSize     = C.Font.sizeSmall
	c.threat   = defaultThreat()
	c.spacing     = 2
	c.orientation = 'vertical'
	c.anchorPoint = 'TOPLEFT'
	return c
end
```

- [ ] **Step 10: Rewrite `raidConfig()` using base helper**

```lua
local function raidConfig()
	local c = baseUnitConfig()
	c.width  = 72
	c.height = 36
	c.position = { x = 40, y = -48, anchor = 'TOPLEFT' }
	c.health.showText   = true
	c.health.textFormat = 'percent'
	c.name.fontSize     = C.Font.sizeSmall
	c.spacing     = 2
	c.orientation = 'vertical'
	c.anchorPoint = 'TOPLEFT'
	return c
end
```

- [ ] **Step 11: Rewrite `arenaConfig()` using base helper**

```lua
local function arenaConfig()
	local c = baseUnitConfig()
	c.width  = 160
	c.height = 30
	c.position = { x = 300, y = 100, anchor = 'CENTER' }
	c.health.showText   = true
	c.health.textFormat = 'current'
	c.health.damageAbsorb = false
	c.health.healAbsorb   = false
	c.health.overAbsorb   = false
	c.castbar     = defaultCastbar(160)
	c.spacing     = 4
	c.orientation = 'vertical'
	c.anchorPoint = 'TOPLEFT'
	return c
end
```

- [ ] **Step 12: Update Arena preset IIFE overrides**

In `GetAll()`, the Arena preset uses IIFEs to modify player/target configs (removing portrait). These need updating to work with the new structure:

```lua
-- Arena preset player config (no portrait in arena)
player = (function()
	local p = playerConfig()
	p.portrait = nil
	return p
end)(),
-- Arena preset target config (no portrait in arena)
target = (function()
	local t = targetConfig()
	t.portrait = nil
	return t
end)(),
```

- [ ] **Step 13: Update Party preset pet IIFE override**

```lua
pet = (function()
	local p = petConfig()
	p.width  = 72
	p.height = 18
	return p
end)(),
```

- [ ] **Step 14: Commit**

```bash
git add Presets/Defaults.lua
git commit -m "feat: expand preset defaults to ~80 keys per unit config

Add baseUnitConfig() helper with complete health, power, name,
statusIcons (with position/size flat keys), statusText, and range
defaults. Rewrite all 9 unit config functions to use the base helper
with unit-specific overrides. Every config key that any consumer reads
now has an explicit default value.

Closes part of #34"
```

---

### Task 2: Expand Account Defaults and Character Defaults

**Files:**
- Modify: `Core/Config.lua`

- [ ] **Step 1: Expand `accountDefaults.general`**

Add missing appearance keys. Find the `accountDefaults` table and expand `general`:

```lua
general = {
	accentColor = { 0, 0.8, 1, 1 },
	uiScale = 1.0,
	barTexture = nil,
	font = nil,
	roleIconStyle = 2,
	wizardCompleted = false,
	tooltipEnabled = true,
	tooltipHideInCombat = false,
	tooltipAnchor = 'ANCHOR_RIGHT',
	tooltipOffsetX = 0,
	tooltipOffsetY = 0,
	targetHighlightColor = { 0.839, 0, 0.075, 1 },
	targetHighlightWidth = 2,
	mouseoverHighlightColor = { 0.969, 0.925, 1, 0.6 },
	mouseoverHighlightWidth = 2,
	pinnedCards = {},
	pinnedAppearanceCards = {},
},
```

New keys vs current: `barTexture`, `font`, `roleIconStyle`, `pinnedCards`, `pinnedAppearanceCards`. Ensure `accentColor` has 4 elements (add alpha `1`).

- [ ] **Step 2: Expand `charDefaults`**

Add last-visited state keys:

```lua
local charDefaults = {
	autoSwitch = {
		['solo']         = 'Solo',
		['party']        = 'Party',
		['raid']         = 'Raid',
		['mythicRaid']   = 'Mythic Raid',
		['worldRaid']    = 'World Raid',
		['battleground'] = 'Battleground',
		['arena']        = 'Arena',
	},
	specOverrides = {},
	tourState = {
		completed = false,
		lastStep = 0,
	},
	lastPanel = nil,
	lastEditingPreset = nil,
	lastEditingUnitType = nil,
}
```

New keys: `lastPanel`, `lastEditingPreset`, `lastEditingUnitType`.

**Note:** The spec mentions `Settings/Framework.lua` should read these charDefaults on settings open and restore last-visited state. That is a consumer-side feature change — implement it as a follow-up after the defaults infrastructure is complete, not as part of this refactor.

- [ ] **Step 3: Commit**

```bash
git add Core/Config.lua
git commit -m "feat: expand account and character defaults with missing keys

Add barTexture, font, roleIconStyle, pinnedCards, pinnedAppearanceCards
to accountDefaults.general. Add lastPanel, lastEditingPreset,
lastEditingUnitType to charDefaults for settings state restoration.

Part of #34"
```

---

### Task 3: Delete StyleBuilder.DEFAULT_CONFIG and ICON_DEFAULTS

**Files:**
- Modify: `Units/StyleBuilder.lua`

- [ ] **Step 1: Delete the `DEFAULT_CONFIG` table**

Remove the entire `local DEFAULT_CONFIG = { ... }` block (approximately lines 7-97 in StyleBuilder.lua). This is now redundant — all values live in `Presets/Defaults.lua`.

- [ ] **Step 2: Delete the `ICON_DEFAULTS` table**

Remove the entire `local ICON_DEFAULTS = { ... }` block (approximately lines 99-111). Icon position/size values are now flat keys in `statusIcons` within each preset default.

- [ ] **Step 3: Update `GetConfig()` to remove DEFAULT_CONFIG fallback tier**

Current `GetConfig()` has a 4-tier fallback ending with `return DEFAULT_CONFIG`. Remove the final fallback:

Before:
```lua
-- 4. Built-in fallback
return DEFAULT_CONFIG
```

After: Remove this line entirely. If `GetConfig()` can't find a config for a unit type, it should return `nil` (which is a bug — every unit type must have preset defaults).

Alternatively, if you want a safety net during development, add an assertion:
```lua
error('GetConfig: no config found for unitType=' .. tostring(unitType))
```

- [ ] **Step 4: Update `iconCfg()` helper in `Apply()`**

The `iconCfg()` helper currently reads from `ICON_DEFAULTS`. Change it to read from the config's statusIcons flat keys directly:

Before (around line 667):
```lua
local function iconCfg(key)
	local d = ICON_DEFAULTS[key]
	local pt = icons[key .. 'Point'] or d.point
	local x  = icons[key .. 'X']     or d.x
	local y  = icons[key .. 'Y']     or d.y
	local sz = icons[key .. 'Size']  or d.size
	return { size = sz, point = { pt, self, pt, x, y } }
end
```

After:
```lua
local function iconCfg(key)
	local pt = icons[key .. 'Point']
	local x  = icons[key .. 'X']
	local y  = icons[key .. 'Y']
	local sz = icons[key .. 'Size']
	return { size = sz, point = { pt, self, pt, x, y } }
end
```

- [ ] **Step 5: Update icon setup in the initial setup function**

Find the icon setup section in the initial element creation (around line 1666). Same pattern — strip ICON_DEFAULTS references:

Before:
```lua
local icons = config.statusIcons or {}
...
local pt = icons[iconKey .. 'Point'] or defaults.point
local x  = icons[iconKey .. 'X']     or defaults.x
local y  = icons[iconKey .. 'Y']     or defaults.y
local sz = icons[iconKey .. 'Size']  or defaults.size
```

After:
```lua
local icons = config.statusIcons
...
local pt = icons[iconKey .. 'Point']
local x  = icons[iconKey .. 'X']
local y  = icons[iconKey .. 'Y']
local sz = icons[iconKey .. 'Size']
```

- [ ] **Step 6: Update icon handling in CONFIG_CHANGED handler**

Find the statusIcons CONFIG_CHANGED section (around line 744). Strip `ICON_DEFAULTS` references:

Before:
```lua
local pt = icons[baseKey .. 'Point'] or defaults.point
local x  = icons[baseKey .. 'X']     or defaults.x
local y  = icons[baseKey .. 'Y']     or defaults.y
local sz = icons[baseKey .. 'Size']  or defaults.size
```

After:
```lua
local pt = icons[baseKey .. 'Point']
local x  = icons[baseKey .. 'X']
local y  = icons[baseKey .. 'Y']
local sz = icons[baseKey .. 'Size']
```

Also remove the `local defaults = ICON_DEFAULTS[baseKey]` line and the `if(not defaults) then return end` guard — the values are guaranteed to exist in config.

- [ ] **Step 7: Commit**

```bash
git add Units/StyleBuilder.lua
git commit -m "refactor: delete DEFAULT_CONFIG and ICON_DEFAULTS from StyleBuilder

These tables are now redundant — all values live in Presets/Defaults.lua.
GetConfig() no longer falls back to DEFAULT_CONFIG. Icon position/size
values are read directly from config.statusIcons flat keys.

Part of #34"
```

---

### Task 4: Strip `or` Fallbacks from FrameConfig.lua

**Files:**
- Modify: `Units/LiveUpdate/FrameConfig.lua`

This is the largest consumer file (~143 `or` patterns). Apply the decision framework from the top of this plan.

- [ ] **Step 1: Strip layout/positioning fallbacks**

**Lines ~134-136** (`applyGroupLayoutToHeader`):
```lua
-- Before:
local orient  = config.orientation or 'vertical'
local anchor  = config.anchorPoint or 'TOPLEFT'
local spacing = config.spacing or 2

-- After:
local orient  = config.orientation
local anchor  = config.anchorPoint
local spacing = config.spacing
```

**Lines ~182-183** (`repositionFrame`):
```lua
-- Before:
local x = (pos and pos.x) or 0
local y = (pos and pos.y) or 0

-- After:
local x = pos.x
local y = pos.y
```

Note: `pos` is `config.position` which is now guaranteed to exist.

**Lines ~268-270** (CONFIG_CHANGED position handler):
```lua
-- Before:
local pos = config.position or {}
local x = pos.x or 0
local y = pos.y or 0

-- After:
local x = config.position.x
local y = config.position.y
```

- [ ] **Step 2: Strip power bar fallbacks**

Throughout the file, replace all instances of this pattern:

```lua
-- Before:
local powerHeight = config.power and config.power.height or 0
local pos = config.power and config.power.position or 'bottom'

-- After:
local powerHeight = config.power.height
local pos = config.power.position
```

This pattern appears at lines ~286, ~311, ~393, ~452-453, ~581, ~583, ~1311, ~1321.

- [ ] **Step 3: Strip castbar fallbacks (keep nil-guard)**

Castbar is an optional sub-table. Keep the nil-guard but strip value fallbacks within:

```lua
-- Before:
local cbCfg = config.castbar or {}
local cbWidth = (cbCfg.sizeMode == 'detached' and cbCfg.width) or config.width
local cbHeight = cbCfg.height or 16

-- After:
if(config.castbar) then
	local cbCfg = config.castbar
	local cbWidth = (cbCfg.sizeMode == 'detached' and cbCfg.width) or config.width
	local cbHeight = cbCfg.height
	-- ... rest of castbar logic
end
```

Note: The `(sizeMode == 'detached' and width) or config.width` pattern is **conditional logic** (not a fallback) — keep it.

This pattern appears at lines ~326-328, ~408-410, ~529-531, ~1621-1623.

For `backgroundMode`:
```lua
-- Before:
local mode = config.castbar and config.castbar.backgroundMode or 'always'

-- After (inside castbar guard):
local mode = config.castbar.backgroundMode
```

- [ ] **Step 4: Strip health color fallbacks**

```lua
-- Before:
local mode = config.health and config.health.colorMode or 'class'
h._customColor = config.health and config.health.customColor or { 0.2, 0.8, 0.2 }

-- After:
local mode = config.health.colorMode
h._customColor = config.health.customColor
```

For gradient thresholds/colors (lines ~591-593, ~641-646, ~698-703):
```lua
-- Before:
[(hc.gradientThreshold3 or 5) / 100]  = CreateColor(unpack(hc.gradientColor3 or { 0.8, 0.1, 0.1 })),

-- After:
[hc.gradientThreshold3 / 100] = CreateColor(unpack(hc.gradientColor3)),
```

For `hc = config.health or {}` patterns — strip the `or {}`:
```lua
-- Before:
local hc = config.health or {}

-- After:
local hc = config.health
```

- [ ] **Step 5: Strip health/power/name text fallbacks**

All text setup sections follow the same pattern. For health text (lines ~815-825, ~839-860):
```lua
-- Before:
local text = Widgets.CreateFontString(textOverlay, hc.fontSize or C.Font.sizeSmall, C.Colors.textActive, hc.outline or '', hc.shadow ~= false)
local ap = hc.textAnchor or 'CENTER'
text:SetPoint(ap, anchor, ap, (hc.textAnchorX or 0) + 1, hc.textAnchorY or 0)
text._anchorX = hc.textAnchorX or 0
text._anchorY = hc.textAnchorY or 0
frame.Health._textFormat = hc.textFormat or 'percent'
frame.Health._textColorMode = hc.textColorMode or 'white'

-- After:
local text = Widgets.CreateFontString(textOverlay, hc.fontSize, C.Colors.textActive, hc.outline, hc.shadow ~= false)
local ap = hc.textAnchor
text:SetPoint(ap, anchor, ap, hc.textAnchorX + 1, hc.textAnchorY)
text._anchorX = hc.textAnchorX
text._anchorY = hc.textAnchorY
frame.Health._textFormat = hc.textFormat
frame.Health._textColorMode = hc.textColorMode
```

Apply the same pattern to power text (lines ~918-928, ~1495-1524) and name text (lines ~1537-1588).

For name text, be careful with cascading fallbacks:
```lua
-- Before:
local fontSize = nc.fontSize or ec.fontSize or C.Font.sizeNormal
local outline = nc.outline or ec.outline or ''
local ap = nc.anchor or ecPt or curPt or 'CENTER'
local x = nc.anchorX or ec.anchorX or frame.Name._anchorX or 0

-- After:
local fontSize = nc.fontSize
local outline = nc.outline
local ap = nc.anchor
local x = nc.anchorX
```

The `ec` (existing config) and `frame.Name._anchorX` fallbacks were defensive — no longer needed when config is complete.

- [ ] **Step 6: Strip heal prediction and absorb color fallbacks**

```lua
-- Before:
local mode = config.health and config.health.healPredictionMode or 'all'
local color = config.health and config.health.healPredictionColor or { 0.6, 0.6, 0.6, 0.4 }
frame.Health._healPredBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 0.4)

-- After:
local mode = config.health.healPredictionMode
local color = config.health.healPredictionColor
frame.Health._healPredBar:SetStatusBarColor(color[1], color[2], color[3], color[4])
```

Same for damage absorb color (lines ~1059-1062) and heal absorb color (lines ~1071-1074). The alpha `or 0.4`/`or 0.6`/`or 0.5` patterns are stripped because all colors now have 4 elements in defaults.

- [ ] **Step 7: Strip font/outline fallbacks in CONFIG_CHANGED handlers**

Health font handler (lines ~1105-1112):
```lua
-- Before:
local size = hc.fontSize or C.Font.sizeSmall
local flags = hc.outline or ''

-- After:
local size = hc.fontSize
local flags = hc.outline
```

Same pattern for power font (lines ~1157-1164), name font (lines ~1208-1214).

Health text anchor handler (lines ~1124-1135):
```lua
-- Before:
local ap = hc.textAnchor or 'CENTER'
local x = hc.textAnchorX or 0
local y = hc.textAnchorY or 0

-- After:
local ap = hc.textAnchor
local x = hc.textAnchorX
local y = hc.textAnchorY
```

Same for power text anchor (lines ~1176-1186), name anchor (lines ~1226-1234).

- [ ] **Step 8: Strip dimension fallbacks in CONFIG_CHANGED handler**

Lines ~298-299:
```lua
-- Before:
oldW = frame:GetWidth() or config.width
oldH = frame:GetHeight() or config.height

-- After:
oldW = frame:GetWidth()
oldH = frame:GetHeight()
```

Note: `frame:GetWidth()` always returns a number for visible frames. The `or config.width` was overly defensive.

Lines ~370-371:
```lua
-- Before:
local oldW = frame._width or frame:GetWidth() or config.width
local oldH = frame._height or frame:GetHeight() or config.height

-- After:
local oldW = frame._width or frame:GetWidth()
local oldH = frame._height or frame:GetHeight()
```

Keep `frame._width or frame:GetWidth()` — these are runtime state fallbacks, not config.

Lines ~377-378:
```lua
-- Before:
local curX = (pos and pos.x) or 0
local curY = (pos and pos.y) or 0

-- After:
local curX = config.position.x
local curY = config.position.y
```

- [ ] **Step 9: Strip pet text fallbacks**

Lines ~1829-1835:
```lua
-- Before:
local format   = petCfg.healthTextFormat or 'percent'
local fontSize = petCfg.healthTextFontSize or C.Font.sizeSmall
local outline  = petCfg.healthTextOutline or ''
local colorMode = petCfg.healthTextColor or 'white'
local offX     = petCfg.healthTextOffsetX or 0
local offY     = petCfg.healthTextOffsetY or 2

-- After:
local format   = petCfg.healthTextFormat
local fontSize = petCfg.healthTextFontSize
local outline  = petCfg.healthTextOutline
local colorMode = petCfg.healthTextColor
local offX     = petCfg.healthTextOffsetX
local offY     = petCfg.healthTextOffsetY
```

- [ ] **Step 10: Strip party/raid width/height fallbacks**

Lines ~1788-1789:
```lua
-- Before:
local w = partyConfig.width or 120
local h = partyConfig.height or 36

-- After:
local w = partyConfig.width
local h = partyConfig.height
```

- [ ] **Step 11: Commit**

```bash
git add Units/LiveUpdate/FrameConfig.lua
git commit -m "refactor: strip ~100 or-fallbacks from FrameConfig.lua

All config values are now guaranteed to exist in SavedVariables via
Presets/Defaults.lua. Nil-guards kept for optional sub-tables (castbar).
Runtime fallbacks (frame:GetWidth()) kept where appropriate.

Part of #34"
```

---

### Task 5: Strip `or` Fallbacks from StyleBuilder.lua

**Files:**
- Modify: `Units/StyleBuilder.lua`

After Task 3 deleted DEFAULT_CONFIG and ICON_DEFAULTS, remaining `or` patterns in StyleBuilder need stripping.

- [ ] **Step 1: Strip name anchor fallbacks in Apply()**

Lines ~606-608:
```lua
-- Before:
local nameAnchorPt = nameCfg.anchor or 'CENTER'
local nameAnchorX  = nameCfg.anchorX or 0
local nameAnchorY  = nameCfg.anchorY or 0

-- After:
local nameAnchorPt = nameCfg.anchor
local nameAnchorX  = nameCfg.anchorX
local nameAnchorY  = nameCfg.anchorY
```

- [ ] **Step 2: Strip power bar fallbacks in Apply()**

Lines ~581-583:
```lua
-- Before:
local powerHeight  = config.power and config.power.height or 0
local powerPosition = config.power and config.power.position or 'bottom'

-- After:
local powerHeight  = config.power.height
local powerPosition = config.power.position
```

- [ ] **Step 3: Strip castbar fallbacks in Apply() (keep nil-guard)**

Lines ~629-630:
```lua
-- Before:
local cbWidth  = (cbCfg.sizeMode == 'detached' and cbCfg.width) or config.width
local cbHeight = cbCfg.height or 16

-- After:
local cbWidth  = (cbCfg.sizeMode == 'detached' and cbCfg.width) or config.width
local cbHeight = cbCfg.height
```

Keep the `(detached and width) or config.width` conditional logic.

- [ ] **Step 4: Strip gradient fallbacks in Apply()**

Lines ~1111-1113:
```lua
-- Before:
[(cfg.gradientThreshold3 or 5)  / 100] = CreateColor(unpack(cfg.gradientColor3 or { 0.8, 0.1, 0.1 })),
[(cfg.gradientThreshold2 or 50) / 100] = CreateColor(unpack(cfg.gradientColor2 or { 0.9, 0.6, 0.1 })),
[(cfg.gradientThreshold1 or 95) / 100] = CreateColor(unpack(cfg.gradientColor1 or { 0.2, 0.8, 0.2 })),

-- After:
[cfg.gradientThreshold3 / 100] = CreateColor(unpack(cfg.gradientColor3)),
[cfg.gradientThreshold2 / 100] = CreateColor(unpack(cfg.gradientColor2)),
[cfg.gradientThreshold1 / 100] = CreateColor(unpack(cfg.gradientColor1)),
```

- [ ] **Step 5: Strip name/health/power live-update handler fallbacks**

These are the `_anchorX or 0`, `_anchorPoint or 'CENTER'`, `_fontFlags or ''`, `_customColor or { ... }`, `_textCustomColor or { ... }` patterns in the CONFIG_CHANGED handler chain (lines ~877-1065).

Each follows the same rule: stored state on frames (`frame.Name._anchorX`) is set during initial setup from config values. Since config values are now guaranteed, the stored state is guaranteed too. Strip the `or` fallbacks.

Representative example:
```lua
-- Before:
local x = frame.Name._anchorX or 0
local y = frame.Name._anchorY or 0

-- After:
local x = frame.Name._anchorX
local y = frame.Name._anchorY
```

Apply to all similar patterns for Name, Health.text, and Power.text anchor/font references.

- [ ] **Step 6: Strip color alpha fallbacks**

Throughout the file, patterns like `color[4] or 1` and `tc[4] or 1`:
```lua
-- Before:
frame.Name:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)

-- After:
frame.Name:SetTextColor(tc[1], tc[2], tc[3], tc[4])
```

This is safe because all color defaults now have 4 elements.

**Keep** `bgC[4] or 1` patterns where `bgC` comes from `C.Colors` constants (not config) — verify those constants also have 4 elements, or leave as-is.

- [ ] **Step 7: Keep aura config `or` patterns (out of scope)**

Lines ~1220, ~1273-1301: These are aura config fallbacks (`newConfig.onlyDispellableByMe or false`, `newConfig.highlightType or C.HighlightType.GRADIENT_FULL`, etc.). Aura defaults are managed by `AuraDefaults.lua` and are out of scope for this refactor. **Leave these `or` patterns in place.**

Also keep `presetData.auras[unitType][auraType] or {}` (line ~504) — aura config structure is separate.

- [ ] **Step 8: Keep `Health._wrapper or Health` patterns**

Patterns like `frame.Health._wrapper or frame.Health` (lines ~880, ~892, ~899, ~948, ~955, ~962, ~1014, ~1021, ~1028) are runtime state checks — the wrapper may or may not exist depending on whether the power bar is embedded. **Keep all of these.**

- [ ] **Step 9: Commit**

```bash
git add Units/StyleBuilder.lua
git commit -m "refactor: strip remaining or-fallbacks from StyleBuilder.lua

Config values and frame stored state are now guaranteed by canonical
defaults. Aura config fallbacks and runtime state checks (wrapper)
left unchanged as they are out of scope.

Part of #34"
```

---

### Task 6: Strip `or` Fallbacks from Settings/Cards/*.lua

**Files:**
- Modify: `Settings/Cards/PositionAndLayout.lua`
- Modify: `Settings/Cards/HealthColor.lua`
- Modify: `Settings/Cards/HealthText.lua`
- Modify: `Settings/Cards/PowerBar.lua`
- Modify: `Settings/Cards/PowerText.lua`
- Modify: `Settings/Cards/Name.lua`
- Modify: `Settings/Cards/CastBar.lua`
- Modify: `Settings/Cards/StatusIcons.lua`
- Modify: `Settings/Cards/StatusText.lua`
- Modify: `Settings/Cards/ShieldsAndAbsorbs.lua`
- Modify: `Settings/Cards/PartyPets.lua`
- Modify: `Settings/Cards/Appearance/Tooltips.lua`
- Modify: `Settings/Cards/Appearance/TargetHighlight.lua`
- Modify: `Settings/Cards/Appearance/MouseoverHighlight.lua`

All Settings/Cards follow the same pattern: `getConfig('key') or defaultValue`. Strip every `or defaultValue` where the key now has a canonical default.

- [ ] **Step 1: Strip PositionAndLayout.lua fallbacks**

```lua
-- Before:
widthSlider:SetValue(getConfig('width') or 200)
heightSlider:SetValue(getConfig('height') or 36)
local savedAnchor = getConfig('position.anchor') or 'CENTER'
spacingSlider:SetValue(getConfig('spacing') or 2)
orientSwitch:SetValue(getConfig('orientation') or 'vertical')
apDropdown:SetValue(getConfig('anchorPoint') or 'TOPLEFT')
local actualX = getConfig('position.x') or 0
local actualY = getConfig('position.y') or 0

-- After:
widthSlider:SetValue(getConfig('width'))
heightSlider:SetValue(getConfig('height'))
local savedAnchor = getConfig('position.anchor')
spacingSlider:SetValue(getConfig('spacing'))
orientSwitch:SetValue(getConfig('orientation'))
apDropdown:SetValue(getConfig('anchorPoint'))
local actualX = getConfig('position.x')
local actualY = getConfig('position.y')
```

Also strip the EditCache fallbacks in drag sync (lines 157-158):
```lua
-- Before:
local x = F.EditCache.Get(unitType, 'position.x') or 0
local y = F.EditCache.Get(unitType, 'position.y') or 0

-- After:
local x = F.EditCache.Get(unitType, 'position.x')
local y = F.EditCache.Get(unitType, 'position.y')
```

- [ ] **Step 2: Strip HealthColor.lua fallbacks**

```lua
-- Before:
getConfig('health.colorMode') or 'class'
getConfig(colorKey) or row.color
getConfig(thresholdKey) or row.pct
getConfig('health.customColor') or { 0.2, 0.8, 0.2 }
getConfig('health.lossColorMode') or 'dark'
getConfig('health.lossCustomColor') or { 0.15, 0.15, 0.15 }

-- After: strip all or-suffixes
getConfig('health.colorMode')
getConfig(colorKey)
getConfig(thresholdKey)
getConfig('health.customColor')
getConfig('health.lossColorMode')
getConfig('health.lossCustomColor')
```

Keep the portrait type logic: `(type(savedPortrait) == 'table' and savedPortrait.type) or '2D'` — this handles the case where portrait config might be `true` (legacy) vs table.

- [ ] **Step 3: Strip HealthText.lua fallbacks**

Strip all `or` from: `attachedToName`, `showText`, `textFormat`, `fontSize`, `textColorMode`, `textCustomColor`, `outline`, `textAnchor`, `textAnchorX`, `textAnchorY`.

- [ ] **Step 4: Strip PowerBar.lua fallbacks**

```lua
-- Before:
getConfig('power.position') or 'bottom'
getConfig('power.height') or 2
getConfig(configKey) or pt.default

-- After:
getConfig('power.position')
getConfig('power.height')
getConfig(configKey)
```

Note: The `pt.default` fallback for custom power colors may need special handling — these are per-power-type colors that might not be in saved config yet. **Keep this `or pt.default` if custom power colors are not in the defaults table.** If they need to be added to defaults, that should be a separate step.

- [ ] **Step 5: Strip PowerText.lua fallbacks**

Strip all `or` from: `showText`, `textFormat`, `fontSize`, `textColorMode`, `textCustomColor`, `outline`, `textAnchor`, `textAnchorX`, `textAnchorY`.

- [ ] **Step 6: Strip Name.lua fallbacks**

Strip all `or` from: `colorMode`, `customColor`, `fontSize`, `outline`, `anchor`, `anchorX`, `anchorY`.

- [ ] **Step 7: Strip CastBar.lua fallbacks**

```lua
-- Before:
getConfig('castbar.sizeMode') or 'attached'
getConfig('castbar.width') or getConfig('width') or 192
getConfig('castbar.height') or 16
getConfig('castbar.backgroundMode') or 'always'

-- After:
getConfig('castbar.sizeMode')
getConfig('castbar.width') or getConfig('width')
getConfig('castbar.height')
getConfig('castbar.backgroundMode')
```

Keep `getConfig('castbar.width') or getConfig('width')` — this is conditional logic (detached width falls back to frame width when not explicitly set). Actually, since `castbar.width` is now always set in defaults, this can be simplified to just `getConfig('castbar.width')`.

- [ ] **Step 8: Strip StatusIcons.lua fallbacks**

```lua
-- Before:
getConfig('statusIcons.' .. iconKey .. 'Point') or defaults.point
getConfig('statusIcons.' .. iconKey .. 'X') or defaults.x
getConfig('statusIcons.' .. iconKey .. 'Y') or defaults.y
getConfig('statusIcons.' .. iconKey .. 'Size') or defaults.size

-- After:
getConfig('statusIcons.' .. iconKey .. 'Point')
getConfig('statusIcons.' .. iconKey .. 'X')
getConfig('statusIcons.' .. iconKey .. 'Y')
getConfig('statusIcons.' .. iconKey .. 'Size')
```

Remove the `ICON_DEFAULTS` import and any local reference to `StyleBuilder.ICON_DEFAULTS` if present.

Also strip `(F.Config and F.Config:Get('general.roleIconStyle')) or 2` → `F.Config:Get('general.roleIconStyle')`.

- [ ] **Step 9: Strip StatusText.lua fallbacks**

```lua
-- Before:
getConfig('statusText.fontSize') or C.Font.sizeSmall
getConfig('statusText.outline') or 'OUTLINE'
getConfig('statusText.shadow') or false
getConfig('statusText.anchor') or 'CENTER'
getConfig('statusText.anchorX') or 0
getConfig('statusText.anchorY') or 0

-- After (strip all or-suffixes):
getConfig('statusText.fontSize')
getConfig('statusText.outline')
getConfig('statusText.shadow')
getConfig('statusText.anchor')
getConfig('statusText.anchorX')
getConfig('statusText.anchorY')
```

- [ ] **Step 10: Strip ShieldsAndAbsorbs.lua fallbacks**

```lua
-- Before:
getConfig('health.healPredictionMode') or 'all'
getConfig('health.healPredictionColor') or { 0.6, 0.6, 0.6, 0.4 }
getConfig('health.damageAbsorbColor') or { 1, 1, 1, 0.6 }
getConfig('health.healAbsorbColor') or { 0.7, 0.1, 0.1, 0.5 }

-- After (strip all or-suffixes):
getConfig('health.healPredictionMode')
getConfig('health.healPredictionColor')
getConfig('health.damageAbsorbColor')
getConfig('health.healAbsorbColor')
```

- [ ] **Step 11: Strip PartyPets.lua fallbacks**

```lua
-- Before:
getPetConfig('spacing') or 2
getPetConfig('healthTextFormat') or 'percent'
getPetConfig('healthTextFontSize') or C.Font.sizeSmall
getPetConfig('healthTextColor') or 'white'
getPetConfig('healthTextOutline') or ''
getPetConfig('healthTextOffsetX') or 0
getPetConfig('healthTextOffsetY') or 2

-- After (strip all or-suffixes):
getPetConfig('spacing')
getPetConfig('healthTextFormat')
getPetConfig('healthTextFontSize')
getPetConfig('healthTextColor')
getPetConfig('healthTextOutline')
getPetConfig('healthTextOffsetX')
getPetConfig('healthTextOffsetY')
```

- [ ] **Step 12: Strip Appearance card fallbacks**

**Tooltips.lua:**
```lua
-- Before:
getConfig('tooltipAnchor') or 'ANCHOR_RIGHT'
getConfig('tooltipOffsetX') or 0
getConfig('tooltipOffsetY') or 0

-- After:
getConfig('tooltipAnchor')
getConfig('tooltipOffsetX')
getConfig('tooltipOffsetY')
```

**TargetHighlight.lua:**
```lua
-- Before:
getConfig('targetHighlightWidth') or 2

-- After:
getConfig('targetHighlightWidth')
```

Keep `savedThColor[4] or 1` — this is a color alpha guard for existing saved data that might be 3-element. Once defaults guarantee 4-element colors, this is safe to strip too.

**MouseoverHighlight.lua:** Same pattern as TargetHighlight.

- [ ] **Step 13: Commit**

```bash
git add Settings/Cards/
git commit -m "refactor: strip ~70 or-fallbacks from Settings/Cards

All getConfig() calls now return guaranteed values from SavedVariables.
Conditional logic and runtime fallbacks left in place.

Part of #34"
```

---

### Task 7: Strip `or` Fallbacks from Elements/Status/*.lua

**Files:**
- Modify: All 12 icon/element files in `Elements/Status/`

Every Status element Setup() function follows the same pattern:
```lua
config = config or {}
config.size  = config.size  or 12
config.point = config.point or { 'TOPLEFT', self, 'TOPLEFT', 2, -2 }
```

Since StyleBuilder always passes complete config (from preset defaults via `iconCfg()`), these fallbacks are unnecessary.

- [ ] **Step 1: Strip icon Setup() fallbacks**

For each of these files, remove the `config = config or {}` line and strip `or` from size/point:

**RoleIcon.lua** (lines 78-80):
```lua
-- Before:
config = config or {}
config.size  = config.size  or 12
config.point = config.point or { 'TOPLEFT', self, 'TOPLEFT', 2, -2 }

-- After: (remove all three lines, use config directly)
```

Apply the same to: `LeaderIcon.lua`, `ReadyCheck.lua`, `RaidIcon.lua`, `CombatIcon.lua`, `RestingIcon.lua`, `PhaseIcon.lua`, `ResurrectIcon.lua`, `SummonIcon.lua`, `RaidRoleIcon.lua`, `PvPIcon.lua`.

- [ ] **Step 2: Strip StatusText.lua Setup() fallbacks**

```lua
-- Before:
config = config or {}
local size    = config.fontSize or C.Font.sizeSmall
local outline = config.outline or 'OUTLINE'
local anchor  = config.anchor or 'CENTER'
local ax      = config.anchorX or 0
local ay      = config.anchorY or 0

-- After:
local size    = config.fontSize
local outline = config.outline
local anchor  = config.anchor
local ax      = config.anchorX
local ay      = config.anchorY
```

- [ ] **Step 3: Strip TargetHighlight.lua and MouseoverHighlight.lua fallbacks**

**TargetHighlight.lua** Setup() (lines 85-87):
```lua
-- Before:
config = config or {}
local color     = config.color     or DEFAULT_COLOR
local thickness = config.thickness or 2

-- After:
local color     = config.color
local thickness = config.thickness
```

Also strip the global config read fallbacks (lines ~119-120):
```lua
-- Before:
color = F.Config:Get('general.targetHighlightColor') or DEFAULT_COLOR
thickness = F.Config:Get('general.targetHighlightWidth') or 2

-- After:
color = F.Config:Get('general.targetHighlightColor')
thickness = F.Config:Get('general.targetHighlightWidth')
```

Same pattern for MouseoverHighlight.lua.

Keep the `color[4] or 1` / `color[4] or 0.6` patterns in SetBackdropBorderColor calls only if you are not confident all saved colors have 4 elements. Otherwise strip.

- [ ] **Step 4: Strip CrowdControl.lua and LossOfControl.lua fallbacks**

These elements receive config from aura setup, not from icon defaults. Their `or` patterns for `iconSize`, `anchor`, and `point` are aura config fallbacks.

**Decision:** These are aura-related and may be covered by AuraDefaults.lua. Check if the aura config always provides these values. If yes, strip. If no (because aura defaults are out of scope), keep them.

For now, **keep** the aura element config fallbacks — they're part of the aura system which has its own defaults management.

- [ ] **Step 5: Strip RoleIcon.lua config read**

Line 37:
```lua
-- Before:
return F.Config:Get('general.roleIconStyle') or 2

-- After:
return F.Config:Get('general.roleIconStyle')
```

- [ ] **Step 6: Commit**

```bash
git add Elements/Status/
git commit -m "refactor: strip or-fallbacks from Elements/Status icon setup

Icon config is always complete when passed from StyleBuilder. Aura
element fallbacks (CrowdControl, LossOfControl) left in place as
they belong to the aura defaults system.

Part of #34"
```

---

### Task 8: Strip `or` Fallbacks from Units/*.lua Spawn Files

**Files:**
- Modify: `Units/Player.lua`, `Units/Target.lua`, `Units/TargetTarget.lua`, `Units/Focus.lua`, `Units/Pet.lua`, `Units/Boss.lua`, `Units/Arena.lua`, `Units/Party.lua`, `Units/Raid.lua`

- [ ] **Step 1: Strip solo unit position fallbacks**

For Player.lua, Target.lua, Focus.lua (same pattern):
```lua
-- Before:
local x = (pos and pos.x) or 0
local y = (pos and pos.y) or 0

-- After:
local x = config.position.x
local y = config.position.y
```

For TargetTarget.lua, Pet.lua:
```lua
-- Before:
local pos = config.position or {}
local x = (pos and pos.x) or 0
local y = (pos and pos.y) or 0

-- After:
local x = config.position.x
local y = config.position.y
```

- [ ] **Step 2: Strip Boss.lua and Arena.lua fallbacks**

```lua
-- Before:
local pos = config.position or {}
local baseX = (pos and pos.x) or 0
local baseY = (pos and pos.y) or 0
local spacing = config.spacing or 4

-- After:
local baseX = config.position.x
local baseY = config.position.y
local spacing = config.spacing
```

- [ ] **Step 3: Strip Party.lua fallbacks**

```lua
-- Before:
local w = config.width or 120
local h = config.height or 36
local orient  = config.orientation or 'vertical'
local anchor  = config.anchorPoint or 'TOPLEFT'
local spacing = config.spacing or 2
'initial-width', config.width or 120
'initial-height', config.height or 36
local pos = config.position or {}
local posX = pos.x or 0
local posY = pos.y or 0

-- After:
local w = config.width
local h = config.height
local orient  = config.orientation
local anchor  = config.anchorPoint
local spacing = config.spacing
'initial-width', config.width
'initial-height', config.height
local posX = config.position.x
local posY = config.position.y
```

Also strip pet text fallbacks in Party.lua:
```lua
-- Before:
textFormat    = petCfg.healthTextFormat or 'percent'
fontSize      = petCfg.healthTextFontSize or C.Font.sizeSmall
textColorMode = petCfg.healthTextColor or 'white'
textAnchorX   = petCfg.healthTextOffsetX or 0
textAnchorY   = petCfg.healthTextOffsetY or 0
outline       = petCfg.healthTextOutline or ''

-- After:
textFormat    = petCfg.healthTextFormat
fontSize      = petCfg.healthTextFontSize
textColorMode = petCfg.healthTextColor
textAnchorX   = petCfg.healthTextOffsetX
textAnchorY   = petCfg.healthTextOffsetY
outline       = petCfg.healthTextOutline
```

Keep `cfg or { enabled = true, spacing = 2 }` for `getPartyPetsConfig` if the partyPets config might not exist for non-Party presets. Actually, partyPets is only in the Party preset defaults, so this guard is still needed for other presets that might call this code. **Keep this one.**

- [ ] **Step 4: Strip Raid.lua fallbacks**

```lua
-- Before:
local orient  = config.orientation or 'vertical'
local anchor  = config.anchorPoint or 'TOPLEFT'
local spacing = config.spacing or 2
'initial-width', config.width or 72
'initial-height', config.height or 36
local pos = config.position or {}
local posX = pos.x or 0
local posY = pos.y or 0

-- After:
local orient  = config.orientation
local anchor  = config.anchorPoint
local spacing = config.spacing
'initial-width', config.width
'initial-height', config.height
local posX = config.position.x
local posY = config.position.y
```

- [ ] **Step 5: Strip color alpha fallback in Party.lua**

```lua
-- Before:
bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

-- After:
bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4])
```

Only if `bgC` comes from config with 4-element colors. If `bgC` comes from `C.Colors`, check that constant has 4 elements.

- [ ] **Step 6: Commit**

```bash
git add Units/Player.lua Units/Target.lua Units/TargetTarget.lua Units/Focus.lua Units/Pet.lua Units/Boss.lua Units/Arena.lua Units/Party.lua Units/Raid.lua
git commit -m "refactor: strip or-fallbacks from unit spawn files

Position, dimension, spacing, orientation, and pet text values are now
guaranteed by canonical defaults.

Part of #34"
```

---

### Task 9: Strip `or` Fallbacks from Settings/Panels/*.lua

**Files:**
- Modify: `Settings/Panels/TargetedSpells.lua`
- Modify: `Settings/Panels/Dispels.lua`
- Modify: `Settings/Panels/MissingBuffs.lua`
- Modify: `Settings/Panels/PrivateAuras.lua`
- Modify: `Settings/Panels/LossOfControl.lua`
- Modify: `Settings/Panels/Appearance.lua`

**Scope note:** Only strip config-value fallbacks. Keep UI layout fallbacks (`parent._explicitWidth or ...`), function existence checks (`F.Settings.GetEditingUnitType and ...`), and error handling.

- [ ] **Step 1: Strip Appearance.lua pinnedCards fallback**

```lua
-- Before:
F.Config and F.Config:Get('general.pinnedAppearanceCards') or {}

-- After:
F.Config:Get('general.pinnedAppearanceCards')
```

- [ ] **Step 2: Assess aura panel fallbacks**

The aura panels (TargetedSpells, Dispels, MissingBuffs, PrivateAuras, LossOfControl) read aura config with fallbacks like `get('iconSize') or 20`, `get('anchor') or { ... }`.

**Decision:** Aura defaults are managed by `Presets/AuraDefaults.lua` which is out of scope. Check whether the aura config keys read by these panels exist in AuraDefaults. If they do, strip. If not, keep.

Review the aura defaults to determine which keys are covered. For any keys NOT in AuraDefaults, either:
1. Add them to AuraDefaults (small scope expansion), or
2. Keep the `or` fallback (acceptable since aura system is separate)

For this plan, **keep aura panel `or` fallbacks** unless the implementer verifies the keys exist in AuraDefaults during implementation.

- [ ] **Step 3: Commit (if any changes made)**

```bash
git add Settings/Panels/Appearance.lua
git commit -m "refactor: strip pinnedCards or-fallback from Appearance panel

Part of #34"
```

---

### Task 10: Update EnsureDefaults() Backfill Logic

**Files:**
- Modify: `Presets/Defaults.lua` (the `EnsureDefaults()` function)

For existing users who already have SavedVariables, `EnsureDefaults()` must backfill all the new keys without overwriting existing user values.

- [ ] **Step 1: Add generic deep-merge backfill to EnsureDefaults()**

The current `EnsureDefaults()` has specific migration logic for statusIcons, statusText, and growthDirection. Add a generic deep-merge that handles ALL new keys:

After the existing migration code, add a general backfill loop:

```lua
-- General backfill: deep-merge any missing keys from defaults
-- into existing unit configs. This handles all new keys added
-- by the canonical defaults expansion.
for unitType, defaultUC in next, defaults[presetName].unitConfigs do
	if(savedUC[unitType]) then
		F.DeepMerge(savedUC[unitType], defaultUC)
	else
		savedUC[unitType] = F.DeepCopy(defaultUC)
	end
end
```

This requires a `DeepMerge` utility that only writes missing keys (similar to `mergeDefaults` in Config.lua but for nested tables).

- [ ] **Step 2: Add `F.DeepMerge` utility if not already present**

Check if `F.DeepMerge` already exists. If not, add to `Core/Config.lua` (near `mergeDefaults`):

```lua
--- Deep-merge defaults into target, only filling missing keys.
--- Existing values (including explicit false) are never overwritten.
function F.DeepMerge(target, defaults)
	for k, v in next, defaults do
		if(target[k] == nil) then
			target[k] = F.DeepCopy(v)
		elseif(type(v) == 'table' and type(target[k]) == 'table') then
			F.DeepMerge(target[k], v)
		end
	end
end
```

- [ ] **Step 3: Verify `F.DeepCopy` exists**

`EnsureDefaults()` already uses `F.DeepCopy`. Verify it exists and handles nested tables correctly. It should be in `Core/Config.lua` or a utility file.

- [ ] **Step 4: Update statusIcons backfill for flat keys**

The current statusIcons backfill only handles boolean enabled/disabled flags. Update it to also backfill the new flat position/size keys:

```lua
-- Backfill statusIcons (booleans AND position/size flat keys)
if(savedUC[unitType].statusIcons) then
	local defaultIcons = defaultUC.statusIcons
	for key, val in next, defaultIcons do
		if(savedUC[unitType].statusIcons[key] == nil) then
			savedUC[unitType].statusIcons[key] = F.DeepCopy(val)
		end
	end
end
```

This replaces the existing per-boolean-key loop with a generic one that covers all statusIcons keys.

- [ ] **Step 5: Update statusText backfill for new detail keys**

The current statusText migration handles boolean → table upgrade. After that, backfill new detail keys:

```lua
-- Backfill statusText detail keys
if(type(savedUC[unitType].statusText) == 'table') then
	local defaultST = defaultUC.statusText
	for key, val in next, defaultST do
		if(savedUC[unitType].statusText[key] == nil) then
			savedUC[unitType].statusText[key] = val
		end
	end
end
```

- [ ] **Step 6: Commit**

```bash
git add Presets/Defaults.lua Core/Config.lua
git commit -m "feat: update EnsureDefaults with generic deep-merge backfill

Existing users get all new canonical default keys backfilled without
losing their customizations. Adds F.DeepMerge utility for non-destructive
nested table merging.

Part of #34"
```

---

### Task 11: Final Validation and Cleanup

**Files:**
- All modified files

- [ ] **Step 1: Search for remaining config `or` fallbacks**

Run a grep to find any remaining `or` patterns that should have been stripped:

```bash
cd /path/to/Framed
grep -rn "getConfig\(.*\) or " Settings/Cards/ Settings/Panels/
grep -rn "config\.\w\+ or " Units/LiveUpdate/FrameConfig.lua Units/StyleBuilder.lua
grep -rn "\.x) or 0" Units/
grep -rn "or C\.Font\." Units/ Settings/
```

Any matches should be reviewed against the decision framework and either stripped or explicitly documented as intentional.

- [ ] **Step 2: Verify DEFAULT_CONFIG and ICON_DEFAULTS are deleted**

```bash
grep -rn "DEFAULT_CONFIG" Units/StyleBuilder.lua
grep -rn "ICON_DEFAULTS" Units/StyleBuilder.lua Settings/Cards/StatusIcons.lua
```

Both should return zero results.

- [ ] **Step 3: In-game testing**

1. `/framed reset all` + `/reload` — triggers clean first-load path
2. Verify all frames render at correct positions with correct sizes
3. Open Settings → every slider, dropdown, and color picker should show real values (not 0 or nil)
4. Change several settings (width, health color mode, name font size) → verify they persist across `/reload`
5. Enter Edit Mode → drag frames → save → verify positions match in Settings
6. Switch presets in sidebar → verify all values update correctly per preset
7. Check party frames: spacing, orientation, anchor point, pet health text all render correctly
8. Check boss/arena frames: position, spacing, castbar all render correctly

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: final cleanup for canonical defaults refactor

Verified all or-fallbacks stripped, defaults complete, EnsureDefaults
backfills correctly.

Closes #34"
```

---

## Testing Checklist (Run After Each Task)

Since this is a WoW addon with no automated test framework, testing is manual:

1. **After Task 1 (expanded defaults):** `/framed reset all` + `/reload`. Frames should render identically to before. Open Settings — values should now show real defaults instead of 0/nil.

2. **After Task 2 (Config.lua):** `/framed reset all` + `/reload`. Check Appearance tab — all cards should show correct values.

3. **After Task 3 (delete StyleBuilder tables):** `/reload`. Frames should render identically. If any Lua errors about nil indexing, a default is missing.

4. **After Tasks 4-9 (strip or-patterns):** Each batch should be followed by `/reload` and visual inspection. **Any nil-index Lua error means a default is missing** — add it to `Presets/Defaults.lua` before continuing.

5. **After Task 10 (EnsureDefaults):** Test with EXISTING SavedVariables (don't reset). New keys should appear in Settings without losing existing customizations.

6. **After Task 11 (final):** Full test pass with fresh install AND existing data.
