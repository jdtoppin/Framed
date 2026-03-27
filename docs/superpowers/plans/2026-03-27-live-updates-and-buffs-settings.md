# Live Config Updates & Buffs Settings Expansion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire all settings to live-update frames without `/reload`, expand Buffs indicator edit panels with proper per-type settings, add shared settings builders, add `/framed reset all` command, and fix default positions.

**Architecture:** StyleBuilder.lua splits into 3 files: core `StyleBuilder.lua` (config resolution + `Apply()`), `LiveUpdate/FrameConfig.lua` (all `unitConfigs.*` handlers), and `LiveUpdate/AuraConfig.lua` (all aura handlers with C_Timer debounce). A new `Settings/Builders/SharedCards.lua` provides reusable font/glow/position/threshold-color cards consumed by IndicatorCRUD and aura panels. Renderers (Bar, Color, Overlay, Border, Glow, Icon/Icons) are expanded in-place. A new Bars renderer mirrors Icons for multi-bar grids. All aura elements gain `Rebuild(config)` methods for structural live-update.

**Tech Stack:** WoW 12.0.1 Lua API, oUF framework (embedded), LibCustomGlow-1.0

**Spec:** `docs/superpowers/specs/2026-03-27-live-updates-and-buffs-settings-design.md`

---

## Phase 1: Foundation

### Task 1: Constants — Add BARS Indicator Type

**Files:**
- Modify: `Core/Constants.lua:134-143`

- [ ] **Step 1: Add BARS to IndicatorType enum**

In `Core/Constants.lua`, add `BARS` after `BAR`:

```lua
Constants.IndicatorType = {
	ICON      = 'Icon',
	ICONS     = 'Icons',
	FRAME_BAR = 'FrameBar',
	BAR       = 'Bar',
	BARS      = 'Bars',
	BORDER    = 'Border',
	COLOR     = 'Color',
	OVERLAY   = 'Overlay',
	GLOW      = 'Glow',
}
```

`FRAME_BAR` is kept for backward compat — the Overlay renderer routes it internally.

- [ ] **Step 2: Commit**

```bash
git add Core/Constants.lua
git commit -m "feat: add BARS indicator type constant"
```

---

### Task 2: AuraDefaults — Expand Defaults, Positions & Enabled Flags

**Files:**
- Modify: `Presets/AuraDefaults.lua`

This task updates all default builders with: new config key defaults (iconWidth/iconHeight, durationMode, threshold colors, etc.), correct positions per spec Part 0.5, explicit `enabled` flags, and proper LoC/CC/MissingBuffs defaults.

- [ ] **Step 1: Update shared font helpers and add new default helpers**

At the top of `AuraDefaults.lua`, after the existing `durationFont()` function (line 23), keep existing helpers unchanged. Update `defaultBuffIndicator()` to use `iconWidth`/`iconHeight` instead of `iconSize`:

```lua
local function defaultBuffIndicator()
	return {
		name         = 'My Buffs',
		type         = 'Icons',
		enabled      = true,
		spells       = {},
		castBy       = 'me',
		iconWidth    = 14,
		iconHeight   = 14,
		maxDisplayed = 3,
		orientation  = 'RIGHT',
		showCooldown  = true,
		showStacks    = true,
		durationMode  = 'Never',
		durationFont  = durationFont(),
		stackFont     = stackFont(),
		glowType      = 'None',
		glowColor     = { 1, 1, 1, 1 },
		glowConfig    = {},
		numPerLine    = 0,
		spacingX      = 1,
		spacingY      = 1,
		anchor       = { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 },
		frameLevel   = 5,
	}
end
```

- [ ] **Step 2: Update `debuffConfig` with new keys**

Replace the `debuffConfig` function:

```lua
local function debuffConfig(iconSize, maxDisplayed)
	return {
		enabled              = true,
		iconSize             = iconSize or 14,
		bigIconSize          = 18,
		maxDisplayed         = maxDisplayed or 6,
		showDuration         = true,
		showAnimation        = true,
		orientation          = 'RIGHT',
		anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
		frameLevel           = 5,
		onlyDispellableByMe  = false,
		stackFont            = stackFont(),
		durationFont         = durationFont(),
	}
end
```

(No changes to debuffConfig itself — it's for the Debuffs element, not Buffs indicators.)

- [ ] **Step 3: Update `Solo()` with LoC/CC defaults and positions**

```lua
function F.AuraDefaults.Solo(debuffSize, debuffMax)
	return {
		buffs = { indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = debuffConfig(debuffSize or 14, debuffMax or 6),
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
			spells     = {},
		},
	}
end
```

- [ ] **Step 4: Update `Minimal()` with same LoC/CC defaults**

```lua
function F.AuraDefaults.Minimal()
	return {
		buffs = { indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = debuffConfig(14, 3),
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
			spells     = {},
		},
	}
end
```

- [ ] **Step 5: Update `Group()` with spec Part 0.5 positions and enabled flags**

Replace the `Group()` function with updated positions, enabled flags, `hideUnimportantBuffs`, and full LoC/CC/MissingBuffs/PrivateAuras configs:

```lua
function F.AuraDefaults.Group(sizes)
	local s = sizes or {}
	local icon     = s.iconSize or 14
	local big      = s.bigIconSize or 18
	local rd       = s.raidDebuffIcon or 22
	local rdBig    = s.raidDebuffBigIcon or big
	local ext      = s.externalsIcon or 12
	local def      = s.defensivesIcon or 12
	local extMax   = s.externalsMax or 2
	local defMax   = s.defensivesMax or 2
	local debMax   = s.debuffMax or 3
	local rdMax    = s.raidDebuffMax or 1
	local tsIcon   = s.targetedSpellsIcon or 20
	local dispIcon = s.dispellableIcon or 12

	return {
		buffs = {
			hideUnimportantBuffs = true,
			indicators = { ['My Buffs'] = defaultBuffIndicator() },
		},
		debuffs = {
			enabled              = true,
			iconSize             = 13,
			bigIconSize          = big,
			maxDisplayed         = debMax,
			showDuration         = true,
			showAnimation        = true,
			orientation          = 'RIGHT',
			anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 1, 4 },
			frameLevel           = 5,
			onlyDispellableByMe  = false,
			stackFont            = stackFont(),
			durationFont         = durationFont(),
		},
		raidDebuffs = {
			enabled        = true,
			iconSize       = rd,
			bigIconSize    = rdBig,
			maxDisplayed   = rdMax,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'CENTER', nil, 'CENTER', 0, 3 },
			frameLevel     = 20,
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		targetedSpells = {
			enabled       = true,
			displayMode   = 'Both',
			iconSize      = tsIcon,
			borderColor   = { 1, 0, 0, 1 },
			maxDisplayed  = 1,
			anchor        = { 'CENTER', nil, 'CENTER', 0, 6 },
			frameLevel    = 50,
			glow          = {
				type      = 'Pixel',
				color     = { 1, 0, 0, 1 },
				lines     = 8,
				frequency = 0.25,
				length    = 4,
				thickness = 2,
			},
		},
		dispellable = {
			enabled              = true,
			onlyDispellableByMe  = false,
			highlightType        = 'gradient_half',
			iconSize             = dispIcon,
			anchor               = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', 0, 4 },
			frameLevel           = 15,
		},
		externals = {
			enabled        = true,
			iconSize       = ext,
			maxDisplayed   = extMax,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'DOWN',
			anchor         = { 'RIGHT', nil, 'RIGHT', 2, 5 },
			frameLevel     = 10,
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		defensives = {
			enabled        = true,
			iconSize       = def,
			maxDisplayed   = defMax,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'DOWN',
			anchor         = { 'LEFT', nil, 'LEFT', -2, 5 },
			frameLevel     = 10,
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
		missingBuffs = {
			enabled       = false,
			iconSize      = s.missingBuffsIcon or 12,
			frameLevel    = 10,
			anchor        = { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 16 },
			growDirection  = 'RIGHT',
			spacing       = 1,
			glowType      = 'Pixel',
			glowColor     = { 1, 0.8, 0, 1 },
		},
		privateAuras = {
			enabled  = true,
			iconSize = s.privateAurasIcon or 16,
			anchor   = { 'TOP', nil, 'TOP', 0, -3 },
			frameLevel = 25,
		},
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
			spells     = {},
		},
	}
end
```

- [ ] **Step 6: Update `Arena()` with spec positions**

```lua
function F.AuraDefaults.Arena()
	return {
		buffs = { indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = {
			enabled              = true,
			iconSize             = 14,
			bigIconSize          = 18,
			maxDisplayed         = 4,
			showDuration         = true,
			showAnimation        = true,
			orientation          = 'RIGHT',
			anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
			frameLevel           = 5,
			onlyDispellableByMe  = false,
			stackFont            = stackFont(),
			durationFont         = durationFont(),
		},
		dispellable = {
			enabled              = true,
			onlyDispellableByMe  = false,
			highlightType        = 'gradient_half',
			iconSize             = 14,
			anchor               = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel           = 7,
		},
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
			spells     = {},
		},
	}
end
```

- [ ] **Step 7: Update `Boss()` with spec positions**

```lua
function F.AuraDefaults.Boss()
	return {
		buffs = { indicators = { ['My Buffs'] = defaultBuffIndicator() } },
		debuffs = debuffConfig(14, 4),
		raidDebuffs = {
			enabled        = true,
			iconSize       = 14,
			bigIconSize    = 18,
			maxDisplayed   = 1,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel     = 6,
			stackFont      = stackFont(),
			durationFont   = durationFont(),
		},
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
			spells     = {},
		},
	}
end
```

- [ ] **Step 8: Sync to WoW folder and verify**

Sync the addon folder to your WoW AddOns directory. `/reload` in-game. Verify no Lua errors. Existing frames should render identically (positions only change for NEW characters without saved variables — existing saved variables override defaults).

- [ ] **Step 9: Commit**

```bash
git add Presets/AuraDefaults.lua
git commit -m "feat: expand AuraDefaults with new config keys, positions, and enabled flags

Updates all default builders (Solo, Group, Arena, Boss) per spec Part 0.5:
- Non-overlapping default positions for group frames
- Explicit enabled flags on LoC, CC, MissingBuffs, PrivateAuras
- hideUnimportantBuffs default for group frames
- New indicator config key defaults (iconWidth/Height, durationMode, etc.)"
```

---

### Task 3: BorderIcon — Add Destroy() Method

**Files:**
- Modify: `Elements/Indicators/BorderIcon.lua`

The Rebuild pattern needs to destroy and recreate BorderIcons. Currently there's no `Destroy()` method.

- [ ] **Step 1: Add Destroy method to BorderIconMethods**

Find the `BorderIconMethods` section (after the existing methods like `Clear`, `Show`, `Hide`). Add:

```lua
--- Tear down the BorderIcon for pool cleanup.
--- Removes OnUpdate, clears back-reference, hides, and orphans the frame.
function BorderIconMethods:Destroy()
	self._frame:SetScript('OnUpdate', nil)
	self._frame._biRef = nil
	self._frame:Hide()
	self._frame:SetParent(nil)
end
```

- [ ] **Step 2: Commit**

```bash
git add Elements/Indicators/BorderIcon.lua
git commit -m "feat: add Destroy() method to BorderIcon for pool cleanup"
```

---

## Phase 2: Renderer Expansion

### Task 4: Bar Renderer — Threshold Colors, Dimensions, Stack/Duration

**Files:**
- Modify: `Elements/Indicators/Bar.lua`

Expand Bar to accept `barWidth`, `barHeight`, `barOrientation`, threshold colors (`lowTimeColor`, `lowSecsColor`), `borderColor`, `bgColor`, `showStacks`, `durationMode` with font config.

- [ ] **Step 1: Expand Create() factory to accept new config keys**

In `Bar.lua`, update the `Create()` function to read new config and create border/background/text elements:

```lua
function F.Indicators.Bar.Create(parent, config)
	config = config or {}
	local color       = config.color or { C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1 }
	local barWidth    = config.barWidth or 50
	local barHeight   = config.barHeight or 4
	local orientation = config.barOrientation or 'Horizontal'
	local borderColor = config.borderColor or { 0, 0, 0, 1 }
	local bgColor     = config.bgColor or { 0, 0, 0, 0.5 }

	-- Container frame
	local frame = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(frame, barWidth, barHeight)
	frame:SetFrameLevel(parent:GetFrameLevel() + 5)
	frame:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.5)
	frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
	frame:Hide()

	-- Status bar
	local statusBar = Widgets.CreateStatusBar(frame, barWidth - 2, barHeight - 2)
	statusBar:SetPoint('CENTER', frame, 'CENTER', 0, 0)
	statusBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)

	if(orientation == 'Vertical') then
		statusBar:SetOrientation('VERTICAL')
	end

	-- Stack text (optional)
	local stackText
	if(config.showStacks ~= false) then
		local sf = config.stackFont or {}
		stackText = Widgets.CreateFontString(frame, sf.size or 10, { 1, 1, 1, 1 })
		stackText:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -1, 1)
		stackText:SetJustifyH('RIGHT')
		stackText:Hide()
	end

	-- Duration text (optional)
	local durationText
	if(config.durationMode and config.durationMode ~= 'Never') then
		local df = config.durationFont or {}
		durationText = Widgets.CreateFontString(frame, df.size or 10, { 1, 1, 1, 1 })
		durationText:SetPoint('LEFT', frame, 'LEFT', 2, 0)
		durationText:SetJustifyH('LEFT')
		durationText:Hide()
	end

	local bar = {
		_frame       = frame,
		_statusBar   = statusBar,
		_stackText   = stackText,
		_durationText = durationText,
		_color       = color,
		_lowTimeColor = config.lowTimeColor,   -- { enabled, threshold, color }
		_lowSecsColor = config.lowSecsColor,   -- { enabled, threshold, color }
		_durationMode = config.durationMode or 'Never',
	}

	for k, v in next, BarMethods do
		bar[k] = v
	end

	frame._barRef = bar
	return bar
end
```

- [ ] **Step 2: Add threshold color logic to SetDuration**

Add a method that checks threshold colors and updates the bar color:

```lua
--- Update bar color based on remaining time thresholds.
--- Called from OnUpdate or SetDuration.
function BarMethods:UpdateThresholdColor(remaining, duration)
	local ltc = self._lowSecsColor
	if(ltc and ltc.enabled and remaining <= ltc.threshold) then
		local c = ltc.color
		self._statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
		return
	end

	local lpc = self._lowTimeColor
	if(lpc and lpc.enabled and duration > 0) then
		local pct = (remaining / duration) * 100
		if(pct <= lpc.threshold) then
			local c = lpc.color
			self._statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
			return
		end
	end

	-- Reset to base color
	local c = self._color
	self._statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
end
```

- [ ] **Step 3: Add SetStacks method**

```lua
function BarMethods:SetStacks(count)
	if(not self._stackText) then return end
	if(count and count > 1) then
		self._stackText:SetText(count)
		self._stackText:Show()
	else
		self._stackText:Hide()
	end
end
```

- [ ] **Step 4: Update the OnUpdate handler to include threshold color checks and duration text**

In the existing OnUpdate handler (module-level function), add threshold color updates and duration text formatting:

```lua
local DURATION_UPDATE_INTERVAL = 0.1

local function onUpdate(self, elapsed)
	local bar = self._barRef
	if(not bar or not bar._expirationTime) then
		self:SetScript('OnUpdate', nil)
		return
	end

	bar._elapsed = (bar._elapsed or 0) + elapsed
	if(bar._elapsed < DURATION_UPDATE_INTERVAL) then return end
	bar._elapsed = 0

	local remaining = bar._expirationTime - GetTime()
	if(remaining <= 0) then
		bar:Clear()
		return
	end

	-- Update threshold colors
	bar:UpdateThresholdColor(remaining, bar._duration or 0)

	-- Update duration text
	if(bar._durationText and bar._durationMode ~= 'Never') then
		local show = bar:ShouldShowDuration(remaining, bar._duration or 0)
		if(show) then
			bar._durationText:SetText(bar:FormatDuration(remaining))
			bar._durationText:Show()
		else
			bar._durationText:Hide()
		end
	end
end
```

- [ ] **Step 5: Add duration threshold check and format helpers**

```lua
--- Check if duration text should be shown based on durationMode.
function BarMethods:ShouldShowDuration(remaining, duration)
	local mode = self._durationMode
	if(mode == 'Always') then return true end
	if(mode == 'Never') then return false end

	if(duration > 0) then
		local pct = (remaining / duration) * 100
		if(mode == '<75' and pct < 75) then return true end
		if(mode == '<50' and pct < 50) then return true end
		if(mode == '<25' and pct < 25) then return true end
	end

	if(mode == '<15s' and remaining < 15) then return true end
	if(mode == '<5s' and remaining < 5) then return true end

	return false
end

--- Format duration as seconds (with tenths below 10s).
function BarMethods:FormatDuration(remaining)
	if(remaining >= 60) then
		return math.floor(remaining / 60) .. 'm'
	elseif(remaining >= 10) then
		return math.floor(remaining) .. ''
	else
		return ('%.1f'):format(remaining)
	end
end
```

- [ ] **Step 6: Update existing SetDuration to store duration for threshold checks**

In the existing `SetDuration` method, add storage of `_duration`:

```lua
function BarMethods:SetDuration(duration, expirationTime)
	self._duration = duration
	self._expirationTime = expirationTime
	self._elapsed = 0
	-- ... existing C-level SetTimerDuration or fallback logic ...
	self._frame:SetScript('OnUpdate', onUpdate)
	self:Show()
end
```

- [ ] **Step 7: Sync and verify in-game**

Sync to WoW. `/reload`. Verify existing Bar indicators still render correctly (no breaking change to existing API — new config keys are optional with defaults).

- [ ] **Step 8: Commit**

```bash
git add Elements/Indicators/Bar.lua
git commit -m "feat: expand Bar renderer with threshold colors, dimensions, border/bg, stack/duration"
```

---

### Task 5: Bars Renderer — New Multi-Bar Grid

**Files:**
- Create: `Elements/Indicators/Bars.lua`

New file mirroring the Icons pattern but for status bars. Creates a pool of Bar sub-frames arranged in a grid.

- [ ] **Step 1: Create Bars.lua**

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Bars = {}

-- ============================================================
-- Bars methods
-- ============================================================

local BarsMethods = {}

--- Set bars from aura data list. Each entry: { spellId, icon, duration, expirationTime, count, color }
--- @param auraList table[]
function BarsMethods:SetBars(auraList)
	local count = math.min(#auraList, self._maxDisplayed)
	local config = self._config

	for i = 1, count do
		local bar = self:_GetBar(i)
		local aura = auraList[i]
		if(aura.duration and aura.duration > 0 and aura.expirationTime) then
			bar:SetDuration(aura.duration, aura.expirationTime)
		else
			bar:SetValue(1, 1)
		end
		if(aura.color) then
			bar:SetColor(aura.color[1], aura.color[2], aura.color[3], aura.color[4] or 1)
		end
		if(aura.count) then
			bar:SetStacks(aura.count)
		end
		bar:Show()
	end

	-- Hide unused bars
	for i = count + 1, #self._pool do
		self._pool[i]:Clear()
	end

	self._activeCount = count
	self:_Layout(count)
	if(count > 0) then self._frame:Show() end
end

--- Hide all bars.
function BarsMethods:Clear()
	for i = 1, #self._pool do
		self._pool[i]:Clear()
	end
	self._activeCount = 0
	self._frame:Hide()
end

function BarsMethods:Show() self._frame:Show() end
function BarsMethods:Hide() self._frame:Hide() end
function BarsMethods:GetFrame() return self._frame end
function BarsMethods:SetPoint(...) self._frame:SetPoint(...) end
function BarsMethods:ClearAllPoints() self._frame:ClearAllPoints() end
function BarsMethods:GetActiveCount() return self._activeCount end

--- Lazily create or return an existing bar in the pool.
function BarsMethods:_GetBar(index)
	if(not self._pool[index]) then
		self._pool[index] = F.Indicators.Bar.Create(self._frame, self._config)
	end
	return self._pool[index]
end

--- Layout bars in a grid.
function BarsMethods:_Layout(count)
	local barW    = self._config.barWidth or 50
	local barH    = self._config.barHeight or 4
	local spX     = self._config.spacingX or 1
	local spY     = self._config.spacingY or 1
	local perLine = self._config.numPerLine or 0
	local orient  = self._config.orientation or 'DOWN'

	if(perLine <= 0) then perLine = count end

	for i = 1, count do
		local bar = self._pool[i]
		local frame = bar:GetFrame()
		frame:ClearAllPoints()

		local idx = i - 1
		local col = idx % perLine
		local row = math.floor(idx / perLine)

		local x, y = 0, 0
		if(orient == 'RIGHT') then
			x = col * (barW + spX)
			y = -(row * (barH + spY))
		elseif(orient == 'LEFT') then
			x = -(col * (barW + spX))
			y = -(row * (barH + spY))
		elseif(orient == 'DOWN') then
			x = row * (barW + spX)
			y = -(col * (barH + spY))
		elseif(orient == 'UP') then
			x = row * (barW + spX)
			y = col * (barH + spY)
		end

		frame:SetPoint('TOPLEFT', self._frame, 'TOPLEFT', x, y)
	end
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a Bars (multi-bar grid) indicator.
--- @param parent Frame
--- @param config table
--- @return table bars
function F.Indicators.Bars.Create(parent, config)
	config = config or {}

	local frame = CreateFrame('Frame', nil, parent)
	frame:SetFrameLevel(parent:GetFrameLevel() + 5)
	frame:Hide()

	local bars = {
		_frame        = frame,
		_pool         = {},
		_config       = config,
		_activeCount  = 0,
		_maxDisplayed = config.maxDisplayed or 3,
	}

	for k, v in next, BarsMethods do
		bars[k] = v
	end

	return bars
end
```

- [ ] **Step 2: Add to TOC after Bar.lua**

In `Framed.toc`, after `Elements/Indicators/Bar.lua`:

```
Elements/Indicators/Bars.lua
```

- [ ] **Step 3: Sync and verify no Lua errors on /reload**

- [ ] **Step 4: Commit**

```bash
git add Elements/Indicators/Bars.lua Framed.toc
git commit -m "feat: add Bars renderer — multi-bar grid indicator"
```

---

### Task 6: Color Renderer — Rework to Positioned Rectangle

**Files:**
- Modify: `Elements/Indicators/Color.lua`

Currently Color is a health bar color override. Rework to a positioned, sized colored rectangle (Cell's "Rect" equivalent) with threshold colors, stack/duration, and glow support.

- [ ] **Step 1: Rewrite Color.lua**

The current file is 75 lines and does health bar color override. Replace entirely with a positioned rectangle renderer:

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Color = {}

-- ============================================================
-- Color (Positioned Rectangle) methods
-- ============================================================

local DURATION_UPDATE_INTERVAL = 0.1

local ColorMethods = {}

function ColorMethods:SetColor(r, g, b, a)
	self._color = { r, g, b, a or 1 }
	self._texture:SetColorTexture(r, g, b, a or 1)
end

function ColorMethods:SetDuration(duration, expirationTime)
	self._duration = duration
	self._expirationTime = expirationTime
	self._elapsed = 0
	self._frame:SetScript('OnUpdate', onColorUpdate)
	self:Show()
end

function ColorMethods:SetValue(current, max)
	self._duration = nil
	self._expirationTime = nil
	self._frame:SetScript('OnUpdate', nil)
	self:Show()
end

function ColorMethods:SetStacks(count)
	if(not self._stackText) then return end
	if(count and count > 1) then
		self._stackText:SetText(count)
		self._stackText:Show()
	else
		self._stackText:Hide()
	end
end

function ColorMethods:Clear()
	self._frame:SetScript('OnUpdate', nil)
	self._duration = nil
	self._expirationTime = nil
	if(self._stackText) then self._stackText:Hide() end
	if(self._durationText) then self._durationText:Hide() end
	self._frame:Hide()
end

function ColorMethods:Show() self._frame:Show() end
function ColorMethods:Hide() self._frame:Hide() end
function ColorMethods:GetFrame() return self._frame end
function ColorMethods:SetPoint(...) self._frame:SetPoint(...) end
function ColorMethods:ClearAllPoints() self._frame:ClearAllPoints() end

function ColorMethods:UpdateThresholdColor(remaining, duration)
	local ltc = self._lowSecsColor
	if(ltc and ltc.enabled and remaining <= ltc.threshold) then
		local c = ltc.color
		self._texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		return
	end
	local lpc = self._lowTimeColor
	if(lpc and lpc.enabled and duration > 0) then
		local pct = (remaining / duration) * 100
		if(pct <= lpc.threshold) then
			local c = lpc.color
			self._texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
			return
		end
	end
	local c = self._color
	self._texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- Module-level OnUpdate
local function onColorUpdate(self, elapsed)
	local rect = self._colorRef
	if(not rect or not rect._expirationTime) then
		self:SetScript('OnUpdate', nil)
		return
	end
	rect._elapsed = (rect._elapsed or 0) + elapsed
	if(rect._elapsed < DURATION_UPDATE_INTERVAL) then return end
	rect._elapsed = 0
	local remaining = rect._expirationTime - GetTime()
	if(remaining <= 0) then
		rect:Clear()
		return
	end
	rect:UpdateThresholdColor(remaining, rect._duration or 0)
end

-- ============================================================
-- Factory
-- ============================================================

function F.Indicators.Color.Create(parent, config)
	config = config or {}
	local color   = config.color or { 1, 1, 1, 1 }
	local rectW   = config.rectWidth or 10
	local rectH   = config.rectHeight or 10
	local borderColor = config.borderColor or { 0, 0, 0, 1 }

	local frame = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(frame, rectW, rectH)
	frame:SetFrameLevel(parent:GetFrameLevel() + 5)
	frame:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	frame:SetBackdropColor(0, 0, 0, 0)
	frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
	frame:Hide()

	local texture = frame:CreateTexture(nil, 'ARTWORK')
	texture:SetPoint('TOPLEFT', frame, 'TOPLEFT', 1, -1)
	texture:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -1, 1)
	texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)

	-- Stack text (optional)
	local stackText
	if(config.showStacks ~= false) then
		local sf = config.stackFont or {}
		stackText = Widgets.CreateFontString(frame, sf.size or 10, { 1, 1, 1, 1 })
		stackText:SetPoint('CENTER', frame, 'CENTER', 0, 0)
		stackText:Hide()
	end

	local rect = {
		_frame        = frame,
		_texture      = texture,
		_stackText    = stackText,
		_color        = color,
		_lowTimeColor = config.lowTimeColor,
		_lowSecsColor = config.lowSecsColor,
		_durationMode = config.durationMode or 'Never',
	}

	for k, v in next, ColorMethods do
		rect[k] = v
	end

	frame._colorRef = rect
	return rect
end
```

- [ ] **Step 2: Sync and verify no Lua errors**

Existing Buffs indicators using Color type will need to be rebuilt via `Rebuild()` (added in Task 10). For now, verify no Lua errors.

- [ ] **Step 3: Commit**

```bash
git add Elements/Indicators/Color.lua
git commit -m "feat: rework Color renderer from health-bar tint to positioned rectangle"
```

---

### Task 7: Overlay Renderer — Merge FrameBar, Add Modes

**Files:**
- Modify: `Elements/Indicators/Overlay.lua`

Rework from full-frame tint to health-bar-anchored indicator with three modes: Overlay (depleting), FrameBar (static fill), Both (two layers). Accept threshold colors and smooth toggle.

- [ ] **Step 1: Rewrite Overlay.lua**

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Overlay = {}

-- ============================================================
-- Overlay methods
-- ============================================================

local DURATION_UPDATE_INTERVAL = 0.1

local OverlayMethods = {}

function OverlayMethods:SetDuration(duration, expirationTime)
	self._duration = duration
	self._expirationTime = expirationTime
	self._elapsed = 0

	local mode = self._overlayMode

	-- FrameBar layer: static fill while aura is active
	if(mode == 'FrameBar' or mode == 'Both') then
		self._fbTexture:SetWidth(self._parent:GetWidth())
		self._fbTexture:Show()
		self._fbFrame:Show()
	end

	-- Overlay layer: depleting bar
	if(mode == 'Overlay' or mode == 'Both') then
		self._olStatusBar:SetMinMaxValues(0, duration)
		self._olStatusBar:SetValue(expirationTime - GetTime())
		self._olFrame:Show()
		self._olFrame:SetScript('OnUpdate', self._onUpdate)
	end

	self:Show()
end

function OverlayMethods:SetValue(current, max)
	-- For auras with no duration — show as static
	self._duration = nil
	self._expirationTime = nil

	local mode = self._overlayMode
	if(mode == 'FrameBar' or mode == 'Both') then
		self._fbTexture:SetWidth(self._parent:GetWidth())
		self._fbTexture:Show()
		self._fbFrame:Show()
	end
	if(mode == 'Overlay' or mode == 'Both') then
		self._olStatusBar:SetMinMaxValues(0, 1)
		self._olStatusBar:SetValue(1)
		self._olFrame:Show()
	end
	self:Show()
end

function OverlayMethods:SetColor(r, g, b, a)
	self._color = { r, g, b, a or 1 }
	if(self._fbTexture) then
		self._fbTexture:SetColorTexture(r, g, b, a or 1)
	end
	-- Overlay layer always full opacity in Both mode
	if(self._overlayMode == 'Both') then
		self._olStatusBar:SetStatusBarColor(r, g, b, 1)
	else
		self._olStatusBar:SetStatusBarColor(r, g, b, a or 1)
	end
end

function OverlayMethods:Clear()
	if(self._olFrame) then
		self._olFrame:SetScript('OnUpdate', nil)
		self._olFrame:Hide()
	end
	if(self._fbFrame) then
		self._fbFrame:Hide()
	end
	self._duration = nil
	self._expirationTime = nil
	self._frame:Hide()
end

function OverlayMethods:Show() self._frame:Show() end
function OverlayMethods:Hide() self._frame:Hide() end
function OverlayMethods:GetFrame() return self._frame end

function OverlayMethods:UpdateThresholdColor(remaining, duration)
	local ltc = self._lowSecsColor
	if(ltc and ltc.enabled and remaining <= ltc.threshold) then
		local c = ltc.color
		if(self._overlayMode == 'Both') then
			self._olStatusBar:SetStatusBarColor(c[1], c[2], c[3], 1)
		else
			self._olStatusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
		end
		return
	end
	local lpc = self._lowTimeColor
	if(lpc and lpc.enabled and duration > 0) then
		local pct = (remaining / duration) * 100
		if(pct <= lpc.threshold) then
			local c = lpc.color
			if(self._overlayMode == 'Both') then
				self._olStatusBar:SetStatusBarColor(c[1], c[2], c[3], 1)
			else
				self._olStatusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
			end
			return
		end
	end
	local c = self._color
	if(self._overlayMode == 'Both') then
		self._olStatusBar:SetStatusBarColor(c[1], c[2], c[3], 1)
	else
		self._olStatusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	end
end

-- ============================================================
-- Factory
-- ============================================================

function F.Indicators.Overlay.Create(parent, config)
	config = config or {}
	local color       = config.color or { 0, 0, 0, 0.6 }
	local mode        = config.overlayMode or 'Overlay'
	local orientation = config.barOrientation or 'Horizontal'
	local smooth      = config.smooth ~= false

	-- Container frame — anchored to parent (health bar)
	local frame = CreateFrame('Frame', nil, parent)
	frame:SetAllPoints(parent)
	frame:SetFrameLevel(parent:GetFrameLevel() + 2)
	frame:Hide()

	-- FrameBar layer (static fill)
	local fbFrame = CreateFrame('Frame', nil, frame)
	fbFrame:SetAllPoints(frame)
	fbFrame:SetFrameLevel(frame:GetFrameLevel())
	fbFrame:Hide()

	local fbTexture = fbFrame:CreateTexture(nil, 'OVERLAY')
	fbTexture:SetPoint('TOPLEFT', fbFrame, 'TOPLEFT', 0, 0)
	fbTexture:SetPoint('BOTTOMLEFT', fbFrame, 'BOTTOMLEFT', 0, 0)
	fbTexture:SetWidth(0.001)
	fbTexture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)

	-- Overlay layer (depleting status bar)
	local olFrame = CreateFrame('Frame', nil, frame)
	olFrame:SetAllPoints(frame)
	olFrame:SetFrameLevel(frame:GetFrameLevel() + 1)
	olFrame:Hide()

	local olBar = Widgets.CreateStatusBar(olFrame, 1, 1)
	olBar:SetAllPoints(olFrame)
	if(mode == 'Both') then
		olBar:SetStatusBarColor(color[1], color[2], color[3], 1)
	else
		olBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
	end
	if(orientation == 'Vertical') then
		olBar:SetOrientation('VERTICAL')
	end

	local overlay = {
		_frame        = frame,
		_parent       = parent,
		_fbFrame      = fbFrame,
		_fbTexture    = fbTexture,
		_olFrame      = olFrame,
		_olStatusBar  = olBar,
		_color        = color,
		_overlayMode  = mode,
		_smooth       = smooth,
		_lowTimeColor = config.lowTimeColor,
		_lowSecsColor = config.lowSecsColor,
	}

	-- OnUpdate for depletion
	local function onOverlayUpdate(self, elapsed)
		if(not overlay._expirationTime) then
			self:SetScript('OnUpdate', nil)
			return
		end
		overlay._elapsed = (overlay._elapsed or 0) + elapsed
		if(overlay._elapsed < DURATION_UPDATE_INTERVAL) then return end
		overlay._elapsed = 0

		local remaining = overlay._expirationTime - GetTime()
		if(remaining <= 0) then
			overlay:Clear()
			return
		end
		overlay._olStatusBar:SetValue(remaining)
		overlay:UpdateThresholdColor(remaining, overlay._duration or 0)
	end
	overlay._onUpdate = onOverlayUpdate

	for k, v in next, OverlayMethods do
		overlay[k] = v
	end

	return overlay
end
```

- [ ] **Step 2: Verify FrameBar.lua backward compat**

The existing `FrameBar.lua` file stays in the codebase (it's still loaded by TOC). The RENDERERS dispatch in Buffs.lua will route `FRAME_BAR` to the Overlay renderer with `overlayMode = 'FrameBar'` (handled in Task 10). For now, both files coexist.

- [ ] **Step 3: Sync and verify no Lua errors**

- [ ] **Step 4: Commit**

```bash
git add Elements/Indicators/Overlay.lua
git commit -m "feat: rework Overlay renderer with Overlay/FrameBar/Both modes"
```

---

### Task 8: Border & Glow Renderer — Thickness, FadeOut

**Files:**
- Modify: `Elements/Indicators/Border.lua`
- Modify: `Elements/Indicators/Glow.lua`

- [ ] **Step 1: Add fadeOut and color config to Border.Create**

In `Border.lua`, update the `Create()` factory to accept `config` parameter:

```lua
function F.Indicators.Border.Create(parent, config)
	config = config or {}
	local thickness = config.borderThickness or 2
	local fadeOut   = config.fadeOut or false

	-- ... existing texture creation code ...

	local border = {
		_parent    = parent,
		_top       = top,
		_bottom    = bottom,
		_left      = left,
		_right     = right,
		_thickness = thickness,
		_fadeOut    = fadeOut,
	}
	-- ... existing method assignment ...
	border:SetThickness(thickness)
	return border
end
```

Update the `Clear()` method to support fadeOut:

```lua
function BorderMethods:Clear()
	if(self._fadeOut) then
		-- Animate fade, then hide
		local alpha = self._top:GetAlpha()
		if(alpha > 0) then
			Widgets.FadeOut(self._top, C.Animation.durationNormal)
			Widgets.FadeOut(self._bottom, C.Animation.durationNormal)
			Widgets.FadeOut(self._left, C.Animation.durationNormal)
			Widgets.FadeOut(self._right, C.Animation.durationNormal, function()
				self._top:Hide()
				self._bottom:Hide()
				self._left:Hide()
				self._right:Hide()
			end)
			return
		end
	end
	self._top:Hide()
	self._bottom:Hide()
	self._left:Hide()
	self._right:Hide()
end
```

- [ ] **Step 2: Add fadeOut to Glow.Create**

In `Glow.lua`, update the `Create()` factory to accept `fadeOut` in config:

```lua
function F.Indicators.Glow.Create(parent, config)
	config = config or {}
	-- ... existing code ...
	local glow = {
		_parent    = parent,
		_glowType  = config.glowType or C.GlowType.PROC,
		_color     = config.color or { C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1 },
		_active    = false,
		_fadeOut    = config.fadeOut or false,
		-- ... existing fields ...
	}
	-- ... existing method assignment ...
	return glow
end
```

Update the `Stop()` method to support fadeOut:

```lua
function GlowMethods:Stop()
	if(not self._active) then return end

	if(self._fadeOut and self._parent) then
		-- For glow, we can't fade LCG effects directly.
		-- Instead, stop immediately — fadeOut is a flag for the aura system
		-- to call Stop() slightly before the aura expires for a visual grace period.
	end

	-- ... existing stop logic (LCG Stop calls) ...
	self._active = false
end
```

- [ ] **Step 3: Sync and verify**

- [ ] **Step 4: Commit**

```bash
git add Elements/Indicators/Border.lua Elements/Indicators/Glow.lua
git commit -m "feat: add fadeOut toggle to Border and Glow renderers, borderThickness config"
```

---

### Task 9: Icon/Icons Renderer — Width/Height, Duration Threshold, Spell Colors

**Files:**
- Modify: `Elements/Indicators/Icon.lua`
- Modify: `Elements/Indicators/Icons.lua`

- [ ] **Step 1: Update Icon.Create to accept iconWidth/iconHeight**

In `Icon.lua`, update the factory to accept separate width/height:

```lua
function F.Indicators.Icon.Create(parent, size, config)
	config = config or {}
	local iconWidth  = config.iconWidth or size or 14
	local iconHeight = config.iconHeight or size or 14
	-- ... replace all uses of 'size' with iconWidth/iconHeight ...
```

Update `SetSize` method:

```lua
function IconMethods:SetSize(w, h)
	Widgets.SetSize(self._frame, w, h or w)
	self.texture:SetAllPoints(self._frame)
end
```

- [ ] **Step 2: Add durationMode threshold logic to Icon**

Add the same `ShouldShowDuration` and `FormatDuration` helpers (shared pattern with Bar):

```lua
--- Check if duration text should display based on durationMode threshold.
function IconMethods:ShouldShowDuration(remaining, duration)
	local mode = self._durationMode
	if(mode == 'Always') then return true end
	if(mode == 'Never' or not mode) then return false end

	if(duration > 0) then
		local pct = (remaining / duration) * 100
		if(mode == '<75' and pct < 75) then return true end
		if(mode == '<50' and pct < 50) then return true end
		if(mode == '<25' and pct < 25) then return true end
	end

	if(mode == '<15s' and remaining < 15) then return true end
	if(mode == '<5s' and remaining < 5) then return true end

	return false
end
```

Update the existing OnUpdate handler to check `durationMode` instead of always showing duration:

```lua
-- In the OnUpdate handler, replace the unconditional duration text update:
if(icon._durationText) then
	local show = icon:ShouldShowDuration(remaining, icon._totalDuration or 0)
	if(show) then
		icon._durationText:SetText(icon:FormatDuration(remaining))
		icon._durationText:Show()
	else
		icon._durationText:Hide()
	end
end
```

Store `_durationMode` and `_totalDuration` in the factory and `SetSpell`:

```lua
-- In Create:
icon._durationMode = config.durationMode or 'Always'

-- In SetSpell:
self._totalDuration = duration
```

- [ ] **Step 3: Add spell colors for ColoredSquare mode**

In `Icon.lua`, update `SetSpell` to check for per-spell color:

```lua
function IconMethods:SetSpell(spellId, iconTexture, duration, expirationTime, stacks, dispelType)
	-- ... existing code ...

	-- Per-spell color (ColoredSquare mode)
	if(self._displayType == C.IconDisplay.COLORED_SQUARE and self._spellColors) then
		local sc = self._spellColors[spellId]
		if(sc) then
			self.texture:SetColorTexture(sc[1], sc[2], sc[3], 1)
		end
	end

	-- ... rest of existing code ...
end
```

Store `_spellColors` from config in the factory:

```lua
-- In Create:
icon._spellColors = config.spellColors  -- may be nil
```

- [ ] **Step 4: Add per-icon glow to Icon**

In `Icon.lua`, add glow methods that delegate to a child Glow renderer:

```lua
function IconMethods:StartGlow(color, glowType, glowConfig)
	if(not self._glow) then
		self._glow = F.Indicators.Glow.Create(self._frame)
	end
	self._glow:Start(color, glowType, glowConfig)
end

function IconMethods:StopGlow()
	if(self._glow) then
		self._glow:Stop()
	end
end
```

- [ ] **Step 5: Update Icons.Create to accept new config keys**

In `Icons.lua`, update the factory to pass through new config:

```lua
function F.Indicators.Icons.Create(parent, config)
	config = config or {}
	-- ... update internal config resolution:
	local iconWidth  = config.iconWidth or config.iconSize or 14
	local iconHeight = config.iconHeight or config.iconSize or 14
	local spX = config.spacingX or config.spacing or 1
	local spY = config.spacingY or config.spacing or 1
	local numPerLine = config.numPerLine or 0
	-- ...
```

When creating child Icons in the pool, pass through the full config:

```lua
-- In _GetIcon or wherever pool icons are lazily created:
local iconConfig = {
	iconWidth    = iconWidth,
	iconHeight   = iconHeight,
	displayType  = config.displayType,
	showCooldown = config.showCooldown,
	showStacks   = config.showStacks,
	durationMode = config.durationMode or 'Always',
	durationFont = config.durationFont,
	stackFont    = config.stackFont,
	spellColors  = config.spellColors,
}
local icon = F.Indicators.Icon.Create(self._frame, nil, iconConfig)
```

Update the grid layout to use `iconWidth`/`iconHeight` for spacing:

```lua
-- In layout calculation, replace iconSize with iconWidth/iconHeight:
local x = col * (iconWidth + spX)
local y = -(row * (iconHeight + spY))
```

- [ ] **Step 6: Sync and verify existing icons render**

- [ ] **Step 7: Commit**

```bash
git add Elements/Indicators/Icon.lua Elements/Indicators/Icons.lua
git commit -m "feat: expand Icon/Icons with width/height, durationMode, spell colors, glow"
```

---

## Phase 3: Element Rebuild Methods

### Task 10: Buffs Element — Rebuild, Filters, Priority, BARS Dispatch

**Files:**
- Modify: `Elements/Auras/Buffs.lua`

- [ ] **Step 1: Add BARS to the RENDERERS dispatch table**

At the top of `Buffs.lua`, find the RENDERERS table (~line 14) and add:

```lua
local RENDERERS = {
	[C.IndicatorType.ICON]      = F.Indicators.Icon,
	[C.IndicatorType.ICONS]     = F.Indicators.Icons,
	[C.IndicatorType.BAR]       = F.Indicators.Bar,
	[C.IndicatorType.BARS]      = F.Indicators.Bars,
	[C.IndicatorType.FRAME_BAR] = F.Indicators.Overlay,  -- backward compat → Overlay with FrameBar mode
	[C.IndicatorType.BORDER]    = F.Indicators.Border,
	[C.IndicatorType.COLOR]     = F.Indicators.Color,
	[C.IndicatorType.OVERLAY]   = F.Indicators.Overlay,
	[C.IndicatorType.GLOW]      = F.Indicators.Glow,
}
```

- [ ] **Step 2: Update createRenderer() for new types and config keys**

In the `createRenderer()` function, update the config passed to each renderer type:

For FRAME_BAR backward compat, route to Overlay with FrameBar mode:

```lua
elseif(indType == C.IndicatorType.FRAME_BAR) then
	renderer = F.Indicators.Overlay.Create(self.Health or self, {
		overlayMode = 'FrameBar',
		color = indConfig.color,
	})
```

For BARS:

```lua
elseif(indType == C.IndicatorType.BARS) then
	renderer = F.Indicators.Bars.Create(self, {
		barWidth       = indConfig.barWidth or 50,
		barHeight      = indConfig.barHeight or 4,
		barOrientation = indConfig.barOrientation or 'Horizontal',
		color          = indConfig.color,
		borderColor    = indConfig.borderColor,
		bgColor        = indConfig.bgColor,
		lowTimeColor   = indConfig.lowTimeColor,
		lowSecsColor   = indConfig.lowSecsColor,
		showStacks     = indConfig.showStacks,
		durationMode   = indConfig.durationMode,
		durationFont   = indConfig.durationFont,
		stackFont      = indConfig.stackFont,
		maxDisplayed   = indConfig.maxDisplayed or 3,
		numPerLine     = indConfig.numPerLine or 0,
		spacingX       = indConfig.spacingX or 1,
		spacingY       = indConfig.spacingY or 1,
		orientation    = indConfig.orientation or 'DOWN',
	})
```

For COLOR (now positioned rectangle):

```lua
elseif(indType == C.IndicatorType.COLOR) then
	renderer = F.Indicators.Color.Create(self, {
		color         = indConfig.color,
		rectWidth     = indConfig.rectWidth or 10,
		rectHeight    = indConfig.rectHeight or 10,
		borderColor   = indConfig.borderColor,
		lowTimeColor  = indConfig.lowTimeColor,
		lowSecsColor  = indConfig.lowSecsColor,
		showStacks    = indConfig.showStacks,
		durationMode  = indConfig.durationMode,
		stackFont     = indConfig.stackFont,
	})
```

For OVERLAY (merged with FrameBar):

```lua
elseif(indType == C.IndicatorType.OVERLAY) then
	renderer = F.Indicators.Overlay.Create(self.Health or self, {
		overlayMode    = indConfig.overlayMode or 'Overlay',
		color          = indConfig.color,
		barOrientation = indConfig.barOrientation or 'Horizontal',
		smooth         = indConfig.smooth,
		lowTimeColor   = indConfig.lowTimeColor,
		lowSecsColor   = indConfig.lowSecsColor,
	})
```

Update ICON/ICONS to pass new config:

```lua
elseif(indType == C.IndicatorType.ICON or indType == C.IndicatorType.ICONS) then
	local iconConfig = {
		iconWidth    = indConfig.iconWidth or indConfig.iconSize or 14,
		iconHeight   = indConfig.iconHeight or indConfig.iconSize or 14,
		displayType  = indConfig.displayType,
		showCooldown = indConfig.showCooldown,
		showStacks   = indConfig.showStacks,
		durationMode = indConfig.durationMode or 'Never',
		durationFont = indConfig.durationFont,
		stackFont    = indConfig.stackFont,
		spellColors  = indConfig.spellColors,
		glowType     = indConfig.glowType,
		glowColor    = indConfig.glowColor,
		glowConfig   = indConfig.glowConfig,
	}
	if(indType == C.IndicatorType.ICONS) then
		iconConfig.maxIcons     = indConfig.maxDisplayed or 4
		iconConfig.numPerLine   = indConfig.numPerLine or 0
		iconConfig.spacingX     = indConfig.spacingX or 1
		iconConfig.spacingY     = indConfig.spacingY or 1
		iconConfig.growDirection = indConfig.orientation or 'RIGHT'
		renderer = F.Indicators.Icons.Create(self, iconConfig)
	else
		renderer = F.Indicators.Icon.Create(self, nil, iconConfig)
	end
```

- [ ] **Step 3: Add hideUnimportantBuffs filter to Update()**

In the Update function, after collecting aura data and before indicator matching, add:

```lua
-- Skip unimportant buffs on group frames when filter is enabled
if(element._hideUnimportantBuffs) then
	local dominated = auraData.duration == 0
		or auraData.duration > 600
		or (not auraData.canApplyAura
			and not auraData.isBossAura
			and auraData.duration > 120)
	if(dominated) then
		-- skip this aura, continue to next
	end
end
```

Set `_hideUnimportantBuffs` during Setup from config:

```lua
-- In Setup, after creating indicators:
element._hideUnimportantBuffs = config.hideUnimportantBuffs or false
```

- [ ] **Step 4: Add spell priority (break on first match) for single-value renderers**

In the Update function, when dispatching to single-value renderers (Icon, Bar, Border, Color, Overlay, Glow), ensure iteration respects spell list order and breaks after first match:

```lua
-- For single-value renderers, the first matching spell in _spellLookup wins.
-- _spellLookup is already ordered by spell list position.
-- When matched[idx] is set, skip further matches for that indicator.
if(matched[idx]) then
	-- Already found a higher-priority match for this single-value renderer
else
	matched[idx] = auraData
end
```

This should already be the behavior if `matched[idx]` is only set once. Verify and enforce.

- [ ] **Step 5: Add Rebuild(config) method**

Add a `Rebuild` method to the element that destroys existing renderers and recreates from fresh config:

```lua
--- Structural rebuild: destroy all renderers and recreate from new config.
--- Called by AuraConfig.lua when indicator structure changes.
local function Rebuild(element, config)
	-- Destroy existing renderers
	if(element._indicators) then
		for _, ind in next, element._indicators do
			if(ind._renderer) then
				ind._renderer:Clear()
				-- Destroy if method exists (Icons pool, BorderIcon pool, etc.)
				if(ind._renderer.Destroy) then
					ind._renderer:Destroy()
				end
			end
		end
	end

	-- Rebuild indicator data structures from new config
	element._indicators = {}
	element._spellLookup = {}
	element._hasTrackAll = {}
	element._hideUnimportantBuffs = config.hideUnimportantBuffs or false

	-- Recreate renderers
	local indicators = config.indicators or {}
	for name, indConfig in next, indicators do
		if(indConfig.enabled ~= false) then
			local renderer = createRenderer(element.__owner, indConfig)
			if(renderer) then
				-- Position renderer
				local anchor = indConfig.anchor
				if(anchor and renderer.ClearAllPoints and renderer.SetPoint) then
					renderer:ClearAllPoints()
					renderer:SetPoint(anchor[1], element.__owner, anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0)
				end
				if(indConfig.frameLevel and renderer.GetFrame) then
					renderer:GetFrame():SetFrameLevel(element.__owner:GetFrameLevel() + (indConfig.frameLevel or 5))
				end

				local idx = #element._indicators + 1
				element._indicators[idx] = {
					_renderer   = renderer,
					_type       = indConfig.type,
					_castBy     = indConfig.castBy or 'anyone',
					_color      = indConfig.color,
					_glowType   = indConfig.glowType,
					_glowConfig = indConfig.glowConfig,
					_name       = name,
				}

				-- Build spell lookup
				local spells = indConfig.spells
				if(spells and #spells > 0) then
					for _, spellId in next, spells do
						if(not element._spellLookup[spellId]) then
							element._spellLookup[spellId] = {}
						end
						element._spellLookup[spellId][#element._spellLookup[spellId] + 1] = idx
					end
				else
					element._hasTrackAll[#element._hasTrackAll + 1] = idx
				end
			end
		end
	end

	-- Force refresh
	element:ForceUpdate()
end
```

Expose it on the element: `element.Rebuild = Rebuild`

- [ ] **Step 6: Sync and verify**

- [ ] **Step 7: Commit**

```bash
git add Elements/Auras/Buffs.lua
git commit -m "feat: add Rebuild(), hideUnimportantBuffs filter, BARS dispatch, spell priority to Buffs"
```

---

### Task 11: Other Element Rebuild Methods

**Files:**
- Modify: `Elements/Status/LossOfControl.lua`
- Modify: `Elements/Status/CrowdControl.lua`
- Modify: `Elements/Auras/MissingBuffs.lua`
- Modify: `Elements/Auras/PrivateAuras.lua`
- Modify: `Elements/Auras/TargetedSpells.lua`

Each element gets a `Rebuild(config)` method that tears down and recreates its visual structure.

- [ ] **Step 1: LossOfControl — Add Rebuild**

In `LossOfControl.lua`, add after the Disable function:

```lua
--- Structural rebuild with new config.
local function Rebuild(element, config)
	-- Stop any active timers
	if(element._stopTimer) then element._stopTimer() end

	-- Hide existing visuals
	if(element._overlay) then element._overlay:Hide() end
	if(element._icon) then element._icon:Hide() end
	if(element._duration) then element._duration:Hide() end

	-- Update config properties
	local iconSize = config.iconSize or 22
	local point    = config.anchor or { 'CENTER', nil, 'CENTER', 0, 0 }
	element._types = config.types or { 'stun', 'incapacitate', 'disorient', 'fear', 'silence', 'root' }

	-- Resize and reposition
	if(element._icon) then
		Widgets.SetSize(element._icon, iconSize, iconSize)
	end
	if(element._frame) then
		element._frame:ClearAllPoints()
		element._frame:SetPoint(point[1], element.__owner, point[3] or point[1], point[4] or 0, point[5] or 0)
	end

	-- Force update to re-evaluate current auras
	element:ForceUpdate()
end
```

Set on the element in Setup: `element.Rebuild = Rebuild`

- [ ] **Step 2: CrowdControl — Add Rebuild**

Same pattern as LossOfControl:

```lua
local function Rebuild(element, config)
	if(element._stopTimer) then element._stopTimer() end
	if(element._icon) then element._icon:Hide() end

	local iconSize = config.iconSize or 24
	local point    = config.anchor or { 'CENTER', nil, 'CENTER', 0, 0 }
	element._spells = config.spells

	if(element._icon) then
		Widgets.SetSize(element._icon, iconSize, iconSize)
	end
	if(element._frame) then
		element._frame:ClearAllPoints()
		element._frame:SetPoint(point[1], element.__owner, point[3] or point[1], point[4] or 0, point[5] or 0)
	end

	element:ForceUpdate()
end
```

- [ ] **Step 3: MissingBuffs — Add Rebuild**

```lua
local function Rebuild(element, config)
	-- Hide and clear all existing slots
	if(element._slots) then
		for _, slot in next, element._slots do
			if(slot.bi) then
				slot.bi:Clear()
				slot.bi:Destroy()
			end
			if(slot.glow) then slot.glow:Stop() end
		end
	end

	-- Recreate with new config
	local iconSize     = config.iconSize or 12
	local growDir      = config.growDirection or 'RIGHT'
	local spacing      = config.spacing or 1
	local glowType     = config.glowType or 'Pixel'
	local glowColor    = config.glowColor or { 1, 0.8, 0, 1 }
	local frameLevel   = config.frameLevel or 5

	-- Rebuild slots for each tracked buff
	element._slots = {}
	for _, spellId in next, BUFF_ORDER do
		local bi = F.Indicators.BorderIcon.Create(element._frame, iconSize, {
			showCooldown = false,
			showStacks   = false,
			showDuration = false,
			frameLevel   = element.__owner:GetFrameLevel() + frameLevel,
		})
		local glow = F.Indicators.Glow.Create(bi:GetFrame(), {
			glowType = glowType,
			color    = glowColor,
		})
		element._slots[spellId] = { bi = bi, glow = glow }
	end

	-- Reposition anchor
	local anchor = config.anchor or { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 2 }
	element._frame:ClearAllPoints()
	element._frame:SetPoint(anchor[1], element.__owner, anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0)

	element:ForceUpdate()
end
```

- [ ] **Step 4: PrivateAuras — Add Rebuild**

```lua
local function Rebuild(element, config)
	-- Remove existing C-level anchor
	if(element._anchorID and PRIVATE_AURAS_SUPPORTED) then
		C_UnitAuras.RemovePrivateAuraAnchor(element._anchorID)
		element._anchorID = nil
	end

	-- Update config
	element._iconSize = config.iconSize or 20

	-- Reposition
	local anchor = config.anchor or { 'TOP', nil, 'TOP', 0, -3 }
	element._frame:ClearAllPoints()
	element._frame:SetPoint(anchor[1], element.__owner, anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0)

	-- Re-register if enabled and visible
	if(element.__owner:IsVisible() and PRIVATE_AURAS_SUPPORTED) then
		element._anchorID = C_UnitAuras.AddPrivateAuraAnchor({
			unitToken = element.__owner.unit,
			auraIndex = 1,
			parent    = element._frame,
			showCountdownFrame  = true,
			showCountdownNumbers = true,
			iconInfo = {
				iconWidth  = element._iconSize,
				iconHeight = element._iconSize,
				iconAnchor = {
					point         = 'CENTER',
					relativeTo    = element._frame,
					relativePoint = 'CENTER',
					offsetX       = 0,
					offsetY       = 0,
				},
			},
		})
	end
end
```

- [ ] **Step 5: TargetedSpells — Add Rebuild**

```lua
local function Rebuild(element, config)
	-- Clear existing pool
	if(element._pool) then
		for _, bi in next, element._pool do
			bi:Clear()
			if(bi.Destroy) then bi:Destroy() end
		end
	end
	if(element._glow) then element._glow:Stop() end

	-- Rebuild with new config
	local displayMode  = config.displayMode or 'Both'
	local iconSize     = config.iconSize or 16
	local maxDisplayed = config.maxDisplayed or 1
	local borderColor  = config.borderColor or { 1, 0, 0, 1 }

	element._displayMode  = displayMode
	element._maxDisplayed = maxDisplayed
	element._borderColor  = borderColor

	-- Recreate pool
	element._pool = {}
	if(displayMode == 'Icons' or displayMode == 'Both') then
		for i = 1, maxDisplayed do
			element._pool[i] = F.Indicators.BorderIcon.Create(element._frame, iconSize, {
				borderColor = borderColor,
			})
		end
	end

	-- Recreate glow
	if(displayMode == 'Border_Glow' or displayMode == 'Both') then
		local glowConfig = config.glow or {}
		element._glow = F.Indicators.Glow.Create(element._glowFrame or element.__owner, {
			glowType = glowConfig.type,
			color    = glowConfig.color,
		})
		element._glowType   = glowConfig.type
		element._glowColor  = glowConfig.color
		element._glowConfig = glowConfig
	end

	-- Reposition
	local anchor = config.anchor or { 'CENTER', nil, 'CENTER', 0, 0 }
	element._frame:ClearAllPoints()
	element._frame:SetPoint(anchor[1], element.__owner, anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0)

	element:ForceUpdate()
end
```

- [ ] **Step 6: Sync and verify**

- [ ] **Step 7: Commit**

```bash
git add Elements/Status/LossOfControl.lua Elements/Status/CrowdControl.lua Elements/Auras/MissingBuffs.lua Elements/Auras/PrivateAuras.lua Elements/Auras/TargetedSpells.lua
git commit -m "feat: add Rebuild(config) methods to LoC, CC, MissingBuffs, PrivateAuras, TargetedSpells"
```

---

## Phase 4: StyleBuilder Split & Live Update

### Task 12: StyleBuilder — Split, ForEachFrame, LoC/CC Wiring

**Files:**
- Modify: `Units/StyleBuilder.lua`

This task extracts `ForEachFrame()` as a shared helper, adds LoC/CC to `Apply()`, and removes the listener registration code that will move to the new LiveUpdate files. The existing listener functions stay temporarily until Tasks 13 and 14 create the new files.

- [ ] **Step 1: Add ForEachFrame helper**

After the `GetAuraConfig` function (~line 486), add:

```lua
--- Iterate all oUF frames matching a unit type.
--- @param unitType string  'player'|'party'|'raid'|'arena'|'boss'
--- @param callback function(frame)
function F.StyleBuilder.ForEachFrame(unitType, callback)
	local oUF = F.oUF
	for _, frame in next, oUF.objects do
		if(frame._framedUnitType == unitType) then
			callback(frame)
		end
	end
end
```

- [ ] **Step 2: Add LoC and CC setup to Apply()**

In `Apply()`, after the existing aura element setup blocks (after Defensives setup, before the pixel updater registration), add:

```lua
-- Loss of Control
local locConfig = F.StyleBuilder.GetAuraConfig(unitType, 'lossOfControl')
if(locConfig and locConfig.enabled) then
	F.Elements.LossOfControl.Setup(self, locConfig)
end

-- Crowd Control
local ccConfig = F.StyleBuilder.GetAuraConfig(unitType, 'crowdControl')
if(ccConfig and ccConfig.enabled) then
	F.Elements.CrowdControl.Setup(self, ccConfig)
end
```

- [ ] **Step 3: Sync and verify**

`/reload` — LoC/CC elements are disabled by default, so no visual change expected. Verify no Lua errors.

- [ ] **Step 4: Commit**

```bash
git add Units/StyleBuilder.lua
git commit -m "feat: add ForEachFrame helper, wire LoC/CC in Apply()"
```

---

### Task 13: FrameConfig.lua — Live Update Handlers for unitConfigs

**Files:**
- Create: `Units/LiveUpdate/FrameConfig.lua`
- Modify: `Framed.toc`

This file handles all `unitConfigs.*` config changes: dimensions, position, power, castbar, shields/absorbs, status icons, show/hide toggles, text, health bar colors, highlights. It also includes the combat queue for group layout changes.

- [ ] **Step 1: Create FrameConfig.lua**

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

-- ============================================================
-- FrameConfig — live-update handlers for unitConfigs.*
-- Listens on CONFIG_CHANGED, parses unitConfigs.<unitType>.<key>,
-- iterates matching frames via F.StyleBuilder.ForEachFrame().
-- ============================================================

local ForEachFrame = F.StyleBuilder.ForEachFrame

-- ============================================================
-- Combat queue for group layout (SetAttribute locked in combat)
-- ============================================================

local pendingGroupChanges = {}
local combatQueueStatus   -- FontString shown on settings panel

local function applyOrQueue(header, attr, value)
	if(InCombatLockdown()) then
		pendingGroupChanges[#pendingGroupChanges + 1] = { header, attr, value }
		-- Show status text if available
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

-- ============================================================
-- Debounce (Tier 1: 0.05s for non-structural changes)
-- ============================================================

local pendingUpdates = {}

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

-- ============================================================
-- Status icon element map
-- ============================================================

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

-- ============================================================
-- Path parser: extract unitType and key from config path
-- Path: unitConfigs.<unitType>.<key>[.<subkey>...]
-- ============================================================

local function parseUnitConfigPath(path)
	local unitType, rest = path:match('^unitConfigs%.([^%.]+)%.(.+)$')
	return unitType, rest
end

-- ============================================================
-- Main CONFIG_CHANGED handler
-- ============================================================

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local unitType, key = parseUnitConfigPath(path)
	if(not unitType) then return end

	-- ── Dimensions ─────────────────────────────────────
	if(key == 'width') then
		local config = F.StyleBuilder.GetConfig(unitType)
		debouncedApply('width.' .. unitType, function()
			ForEachFrame(unitType, function(frame)
				Widgets.SetSize(frame, config.width, nil)
				frame.Health:SetWidth(config.width)
				if(frame.Power and frame.Power:IsShown()) then
					frame.Power:SetWidth(config.width)
				end
			end)
		end)
		return
	end

	if(key == 'height') then
		local config = F.StyleBuilder.GetConfig(unitType)
		debouncedApply('height.' .. unitType, function()
			ForEachFrame(unitType, function(frame)
				Widgets.SetSize(frame, nil, config.height)
			end)
		end)
		return
	end

	-- ── Power bar ──────────────────────────────────────
	if(key == 'showPower') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(config.showPower) then
				frame:EnableElement('Power')
				frame.Power:Show()
			else
				frame:DisableElement('Power')
				frame.Power:Hide()
			end
		end)
		return
	end

	-- ── Cast bar ───────────────────────────────────────
	if(key == 'showCastBar') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(config.showCastBar) then
				frame:EnableElement('Castbar')
			else
				frame:DisableElement('Castbar')
			end
		end)
		return
	end

	-- ── Status icons ───────────────────────────────────
	local iconKey = key:match('^statusIcons%.(.+)$')
	if(iconKey) then
		local elementName = STATUS_ELEMENT_MAP[iconKey]
		if(elementName) then
			local config = F.StyleBuilder.GetConfig(unitType)
			local enabled = config.statusIcons and config.statusIcons[iconKey]
			ForEachFrame(unitType, function(frame)
				if(enabled) then
					frame:EnableElement(elementName)
				else
					frame:DisableElement(elementName)
				end
			end)
		end
		return
	end

	-- ── Show/hide toggles ──────────────────────────────
	if(key == 'showName') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Name) then frame.Name:SetShown(config.showName ~= false) end
		end)
		return
	end

	if(key == 'health.showText') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Health and frame.Health.text) then
				frame.Health.text:SetShown(config.health and config.health.showText)
			end
		end)
		return
	end

	if(key == 'power.showText') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Power and frame.Power.text) then
				frame.Power.text:SetShown(config.power and config.power.showText)
			end
		end)
		return
	end

	-- ── Health prediction (shields/absorbs) ────────────
	if(key:match('^health%.healPrediction')) then
		local config = F.StyleBuilder.GetConfig(unitType)
		local hp = config.health
		ForEachFrame(unitType, function(frame)
			if(hp.healPrediction) then
				frame:EnableElement('HealthPrediction')
			else
				frame:DisableElement('HealthPrediction')
			end
		end)
		return
	end

	-- ── Health text format ─────────────────────────────
	if(key == 'health.textFormat') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Health) then
				frame.Health._textFormat = config.health and config.health.textFormat
				frame.Health:ForceUpdate()
			end
		end)
		return
	end

	-- ── Health smooth ──────────────────────────────────
	if(key == 'health.smooth') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Health) then
				frame.Health.smoothing = config.health and config.health.smooth
			end
		end)
		return
	end

end, 'LiveUpdate.FrameConfig')
```

- [ ] **Step 2: Add to TOC after StyleBuilder.lua**

In `Framed.toc`, after `Units/StyleBuilder.lua`:

```
Units/LiveUpdate/FrameConfig.lua
```

- [ ] **Step 3: Move existing TextConfig, HealthColorConfig, HighlightConfig listeners from StyleBuilder.lua to FrameConfig.lua**

Remove the four EventBus registrations from StyleBuilder.lua (the `StyleBuilder.HighlightConfig`, `StyleBuilder.TextConfig`, `StyleBuilder.HealthColorConfig` listeners). Rewrite them in FrameConfig.lua using the same `ForEachFrame` pattern and `parseUnitConfigPath`. The existing logic is correct — just needs the helper function wrappers.

(The exact code for these is already in StyleBuilder.lua lines 772-1041. Move them into the CONFIG_CHANGED handler in FrameConfig.lua, matching on the appropriate key patterns.)

- [ ] **Step 4: Sync and verify**

- [ ] **Step 5: Commit**

```bash
git add Units/LiveUpdate/FrameConfig.lua Units/StyleBuilder.lua Framed.toc
git commit -m "feat: create FrameConfig.lua with live-update handlers for unitConfigs, combat queue"
```

---

### Task 14: AuraConfig.lua — Live Update Handlers for Auras

**Files:**
- Create: `Units/LiveUpdate/AuraConfig.lua`
- Modify: `Framed.toc`

Handles all `presets.*.auras.*` config changes: enabled toggles, aura element config, debounced Rebuild.

- [ ] **Step 1: Create AuraConfig.lua**

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

-- ============================================================
-- AuraConfig — live-update handlers for presets.*.auras.*
-- ============================================================

local ForEachFrame = F.StyleBuilder.ForEachFrame

-- ============================================================
-- Aura element name map
-- ============================================================

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

-- Elements whose config changes require structural Rebuild
local REBUILD_ELEMENTS = {
	buffs          = true,
	lossOfControl  = true,
	crowdControl   = true,
	missingBuffs   = true,
	privateAuras   = true,
	targetedSpells = true,
}

-- ============================================================
-- Debounce — Tier 2: 0.15s for structural Rebuild
-- ============================================================

local pendingRebuilds = {}

local function debouncedRebuild(element, config)
	local key = tostring(element)
	if(pendingRebuilds[key]) then
		pendingRebuilds[key]:Cancel()
	end
	pendingRebuilds[key] = C_Timer.NewTimer(0.15, function()
		pendingRebuilds[key] = nil
		if(element.Rebuild) then
			element:Rebuild(config)
		end
	end)
end

-- ============================================================
-- Debounce — Tier 1: 0.05s for non-structural changes
-- ============================================================

local pendingUpdates = {}

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

-- ============================================================
-- Path parser: extract unitType and auraType from config path
-- Path: presets.<presetName>.auras.<unitType>.<auraType>[.<key>...]
-- ============================================================

local function parseAuraConfigPath(path)
	local unitType, auraType, rest = path:match('^presets%.[^%.]+%.auras%.([^%.]+)%.([^%.]+)(.*)$')
	if(rest) then rest = rest:match('^%.(.+)$') end  -- strip leading dot
	return unitType, auraType, rest
end

-- ============================================================
-- Main CONFIG_CHANGED handler
-- ============================================================

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local unitType, auraType, subKey = parseAuraConfigPath(path)
	if(not unitType or not auraType) then return end

	local elementName = AURA_ELEMENT_MAP[auraType]
	if(not elementName) then return end

	-- ── Enabled toggle ─────────────────────────────────
	if(subKey == 'enabled') then
		local config = F.StyleBuilder.GetAuraConfig(unitType, auraType)
		ForEachFrame(unitType, function(frame)
			if(config and config.enabled) then
				-- Setup and enable if not already
				if(not frame[elementName]) then
					local setupFn = F.Elements[auraType:sub(1,1):upper() .. auraType:sub(2)]
					if(setupFn and setupFn.Setup) then
						setupFn.Setup(frame, config)
					end
				end
				frame:EnableElement(elementName)
			else
				frame:DisableElement(elementName)
			end
		end)
		return
	end

	-- ── Structural rebuild ─────────────────────────────
	if(REBUILD_ELEMENTS[auraType]) then
		local config = F.StyleBuilder.GetAuraConfig(unitType, auraType)
		ForEachFrame(unitType, function(frame)
			local element = frame[elementName]
			if(element and element.Rebuild) then
				debouncedRebuild(element, config)
			end
		end)
		return
	end

	-- ── Non-structural changes (debuffs, externals, etc.) ──
	-- These elements use BorderIcon pools — config changes like
	-- iconSize, anchor, frameLevel need pool rebuild via ForceUpdate
	local config = F.StyleBuilder.GetAuraConfig(unitType, auraType)
	debouncedApply(auraType .. '.' .. unitType, function()
		ForEachFrame(unitType, function(frame)
			local element = frame[elementName]
			if(element) then
				-- Update cached config properties
				if(config.iconSize) then element._iconSize = config.iconSize end
				if(config.anchor) then
					local a = config.anchor
					element._frame:ClearAllPoints()
					element._frame:SetPoint(a[1], frame, a[3] or a[1], a[4] or 0, a[5] or 0)
				end
				element:ForceUpdate()
			end
		end)
	end)
end, 'LiveUpdate.AuraConfig')
```

- [ ] **Step 2: Move existing AuraConfig listener from StyleBuilder.lua**

Remove the `StyleBuilder.AuraConfig` EventBus registration from StyleBuilder.lua (~lines 1081-1189). The new AuraConfig.lua handles all aura config changes.

- [ ] **Step 3: Add to TOC after FrameConfig.lua**

```
Units/LiveUpdate/AuraConfig.lua
```

- [ ] **Step 4: Sync and verify**

- [ ] **Step 5: Commit**

```bash
git add Units/LiveUpdate/AuraConfig.lua Units/StyleBuilder.lua Framed.toc
git commit -m "feat: create AuraConfig.lua with debounced live-update handlers for all aura elements"
```

---

## Phase 5: Shared Settings Builders

### Task 15: SharedCards — BuildFontCard, BuildGlowCard, BuildPositionCard, BuildThresholdColorCard

**Files:**
- Create: `Settings/Builders/SharedCards.lua`
- Modify: `Framed.toc`

All four shared builders in one file. Each returns yOffset after the card for vertical layout chaining.

- [ ] **Step 1: Create SharedCards.lua**

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

-- ============================================================
-- SharedCards — Reusable settings card builders
-- ============================================================

-- ============================================================
-- BuildFontCard
-- ============================================================

--- Build a font settings card: face dropdown, size slider, outline dropdown, shadow toggle.
--- @param parent Frame
--- @param width number
--- @param yOffset number
--- @param label string  e.g. 'Duration Font'
--- @param configPrefix string  e.g. 'durationFont'
--- @param get function(key) -> value
--- @param set function(key, value)
--- @return number yOffset after card
function F.Settings.BuildFontCard(parent, width, yOffset, label, configPrefix, get, set)
	local cardW = width
	local innerW = cardW - C.Spacing.tight * 2

	local card, cardH = Widgets.CreateCard(parent, cardW)
	card:ClearAllPoints()
	Widgets.SetPoint(card, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local cy = -C.Spacing.tight

	-- Heading
	local heading = Widgets.CreateFontString(card, C.Font.sizeSmall, C.Colors.textActive)
	heading:SetPoint('TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	heading:SetText(label)
	cy = cy - heading:GetStringHeight() - C.Spacing.base

	-- Font size slider
	local sizeSlider = Widgets.CreateSlider(card, innerW, 'Size', 6, 24, 1)
	Widgets.SetPoint(sizeSlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	sizeSlider:SetValue(get(configPrefix .. '.size') or 10)
	sizeSlider:SetOnValueChanged(function(val)
		set(configPrefix .. '.size', val)
	end)
	cy = cy - sizeSlider._explicitHeight - C.Spacing.base

	-- Outline dropdown
	local outlineItems = {
		{ label = 'None',    value = '' },
		{ label = 'Outline', value = 'OUTLINE' },
		{ label = 'Mono',    value = 'MONOCHROME' },
	}
	local outlineDD = Widgets.CreateDropdown(card, innerW, 'Outline', outlineItems)
	Widgets.SetPoint(outlineDD, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	outlineDD:SetSelectedValue(get(configPrefix .. '.outline') or '')
	outlineDD:SetOnValueChanged(function(val)
		set(configPrefix .. '.outline', val)
	end)
	cy = cy - outlineDD._explicitHeight - C.Spacing.base

	-- Shadow toggle
	local shadowSwitch = Widgets.CreateSwitch(card, 'Shadow')
	Widgets.SetPoint(shadowSwitch, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	shadowSwitch:SetChecked(get(configPrefix .. '.shadow') or false)
	shadowSwitch:SetOnValueChanged(function(val)
		set(configPrefix .. '.shadow', val)
	end)
	cy = cy - shadowSwitch._explicitHeight - C.Spacing.tight

	Widgets.SetCardHeight(card, math.abs(cy))
	return yOffset - math.abs(cy) - C.Spacing.normal
end

-- ============================================================
-- BuildGlowCard
-- ============================================================

--- Build a glow settings card: type dropdown, color picker, per-type sliders.
--- @param parent Frame
--- @param width number
--- @param yOffset number
--- @param get function(key) -> value
--- @param set function(key, value)
--- @param opts? { allowNone: boolean }
--- @return number yOffset after card
function F.Settings.BuildGlowCard(parent, width, yOffset, get, set, opts)
	opts = opts or {}
	local cardW = width
	local innerW = cardW - C.Spacing.tight * 2

	local card, cardH = Widgets.CreateCard(parent, cardW)
	card:ClearAllPoints()
	Widgets.SetPoint(card, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local cy = -C.Spacing.tight

	-- Heading
	local heading = Widgets.CreateFontString(card, C.Font.sizeSmall, C.Colors.textActive)
	heading:SetPoint('TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	heading:SetText('Glow')
	cy = cy - heading:GetStringHeight() - C.Spacing.base

	-- Glow type dropdown
	local typeItems = {}
	if(opts.allowNone) then
		typeItems[#typeItems + 1] = { label = 'None', value = 'None' }
	end
	typeItems[#typeItems + 1] = { label = 'Proc',  value = C.GlowType.PROC }
	typeItems[#typeItems + 1] = { label = 'Pixel', value = C.GlowType.PIXEL }
	typeItems[#typeItems + 1] = { label = 'Soft',  value = C.GlowType.SOFT }
	typeItems[#typeItems + 1] = { label = 'Shine', value = C.GlowType.SHINE }

	local typeDD = Widgets.CreateDropdown(card, innerW, 'Glow Type', typeItems)
	Widgets.SetPoint(typeDD, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	typeDD:SetSelectedValue(get('glowType') or (opts.allowNone and 'None' or C.GlowType.PROC))
	typeDD:SetOnValueChanged(function(val)
		set('glowType', val)
		-- Show/hide color picker based on selection
		if(val == 'None') then
			if(colorPicker) then colorPicker:Hide() end
		else
			if(colorPicker) then colorPicker:Show() end
		end
	end)
	cy = cy - typeDD._explicitHeight - C.Spacing.base

	-- Glow color picker
	local glowColor = get('glowColor') or { 1, 1, 1, 1 }
	local colorPicker = Widgets.CreateColorPicker(card, innerW, 'Color', glowColor)
	Widgets.SetPoint(colorPicker, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	colorPicker:SetOnColorChanged(function(r, g, b, a)
		set('glowColor', { r, g, b, a })
	end)
	if(get('glowType') == 'None') then colorPicker:Hide() end
	cy = cy - colorPicker._explicitHeight - C.Spacing.tight

	Widgets.SetCardHeight(card, math.abs(cy))
	return yOffset - math.abs(cy) - C.Spacing.normal
end

-- ============================================================
-- BuildPositionCard
-- ============================================================

--- Build a position & layer card: anchor picker + X/Y sliders + frame level.
--- @param parent Frame
--- @param width number
--- @param yOffset number
--- @param get function(key) -> value
--- @param set function(key, value)
--- @param opts? { hideFrameLevel: boolean, hidePosition: boolean }
--- @return number yOffset after card
function F.Settings.BuildPositionCard(parent, width, yOffset, get, set, opts)
	opts = opts or {}
	local cardW = width
	local innerW = cardW - C.Spacing.tight * 2

	local card, cardH = Widgets.CreateCard(parent, cardW)
	card:ClearAllPoints()
	Widgets.SetPoint(card, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local cy = -C.Spacing.tight

	-- Heading
	local heading = Widgets.CreateFontString(card, C.Font.sizeSmall, C.Colors.textActive)
	heading:SetPoint('TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	heading:SetText('Position & Layer')
	cy = cy - heading:GetStringHeight() - C.Spacing.base

	if(not opts.hidePosition) then
		-- Anchor picker
		if(Widgets.CreateAnchorPicker) then
			local anchor = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
			local picker = Widgets.CreateAnchorPicker(card, innerW)
			Widgets.SetPoint(picker, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
			picker:SetAnchor(anchor)
			picker:SetOnAnchorChanged(function(a)
				set('anchor', a)
			end)
			cy = cy - picker._explicitHeight - C.Spacing.base
		end

		-- X offset slider
		local xSlider = Widgets.CreateSlider(card, innerW, 'X Offset', -50, 50, 1)
		Widgets.SetPoint(xSlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
		local anchor = get('anchor') or {}
		xSlider:SetValue(anchor[4] or 0)
		xSlider:SetOnValueChanged(function(val)
			local a = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
			a[4] = val
			set('anchor', a)
		end)
		cy = cy - xSlider._explicitHeight - C.Spacing.base

		-- Y offset slider
		local ySlider = Widgets.CreateSlider(card, innerW, 'Y Offset', -50, 50, 1)
		Widgets.SetPoint(ySlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
		ySlider:SetValue(anchor[5] or 0)
		ySlider:SetOnValueChanged(function(val)
			local a = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
			a[5] = val
			set('anchor', a)
		end)
		cy = cy - ySlider._explicitHeight - C.Spacing.base
	end

	-- Frame level slider
	if(not opts.hideFrameLevel) then
		local flSlider = Widgets.CreateSlider(card, innerW, 'Frame Level', 1, 50, 1)
		Widgets.SetPoint(flSlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
		flSlider:SetValue(get('frameLevel') or 5)
		flSlider:SetOnValueChanged(function(val)
			set('frameLevel', val)
		end)
		cy = cy - flSlider._explicitHeight - C.Spacing.tight
	end

	Widgets.SetCardHeight(card, math.abs(cy))
	return yOffset - math.abs(cy) - C.Spacing.normal
end

-- ============================================================
-- BuildThresholdColorCard
-- ============================================================

--- Build a threshold color card: base color + low time % + low seconds triggers.
--- @param parent Frame
--- @param width number
--- @param yOffset number
--- @param get function(key) -> value
--- @param set function(key, value)
--- @param opts? { showBorderColor: boolean, showBgColor: boolean }
--- @return number yOffset after card
function F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set, opts)
	opts = opts or {}
	local cardW = width
	local innerW = cardW - C.Spacing.tight * 2

	local card, cardH = Widgets.CreateCard(parent, cardW)
	card:ClearAllPoints()
	Widgets.SetPoint(card, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local cy = -C.Spacing.tight

	-- Heading
	local heading = Widgets.CreateFontString(card, C.Font.sizeSmall, C.Colors.textActive)
	heading:SetPoint('TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	heading:SetText('Colors')
	cy = cy - heading:GetStringHeight() - C.Spacing.base

	-- Base color
	local baseColor = get('color') or { 1, 1, 1, 1 }
	local basePicker = Widgets.CreateColorPicker(card, innerW, 'Color', baseColor)
	Widgets.SetPoint(basePicker, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	basePicker:SetOnColorChanged(function(r, g, b, a)
		set('color', { r, g, b, a })
	end)
	cy = cy - basePicker._explicitHeight - C.Spacing.base

	-- Low Time % toggle + threshold + color
	local ltc = get('lowTimeColor') or { enabled = false, threshold = 25, color = { 1, 0.5, 0, 1 } }
	local ltSwitch = Widgets.CreateSwitch(card, 'Low Time %')
	Widgets.SetPoint(ltSwitch, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	ltSwitch:SetChecked(ltc.enabled)
	cy = cy - ltSwitch._explicitHeight - C.Spacing.base

	local ltSlider = Widgets.CreateSlider(card, innerW, 'Threshold %', 5, 75, 5)
	Widgets.SetPoint(ltSlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	ltSlider:SetValue(ltc.threshold or 25)
	cy = cy - ltSlider._explicitHeight - C.Spacing.base

	local ltColor = Widgets.CreateColorPicker(card, innerW, 'Low Time Color', ltc.color or { 1, 0.5, 0, 1 })
	Widgets.SetPoint(ltColor, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	cy = cy - ltColor._explicitHeight - C.Spacing.base

	-- Wire up low time controls
	local function updateLowTime()
		set('lowTimeColor', {
			enabled   = ltSwitch:IsChecked(),
			threshold = ltSlider:GetValue(),
			color     = { ltColor:GetColor() },
		})
	end
	ltSwitch:SetOnValueChanged(function(val)
		ltSlider:SetShown(val)
		ltColor:SetShown(val)
		updateLowTime()
	end)
	ltSlider:SetOnValueChanged(function() updateLowTime() end)
	ltColor:SetOnColorChanged(function() updateLowTime() end)
	ltSlider:SetShown(ltc.enabled)
	ltColor:SetShown(ltc.enabled)

	-- Low Seconds toggle + threshold + color
	local lsc = get('lowSecsColor') or { enabled = false, threshold = 5, color = { 1, 0, 0, 1 } }
	local lsSwitch = Widgets.CreateSwitch(card, 'Low Seconds')
	Widgets.SetPoint(lsSwitch, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	lsSwitch:SetChecked(lsc.enabled)
	cy = cy - lsSwitch._explicitHeight - C.Spacing.base

	local lsSlider = Widgets.CreateSlider(card, innerW, 'Threshold (sec)', 1, 30, 1)
	Widgets.SetPoint(lsSlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	lsSlider:SetValue(lsc.threshold or 5)
	cy = cy - lsSlider._explicitHeight - C.Spacing.base

	local lsColor = Widgets.CreateColorPicker(card, innerW, 'Low Secs Color', lsc.color or { 1, 0, 0, 1 })
	Widgets.SetPoint(lsColor, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	cy = cy - lsColor._explicitHeight - C.Spacing.base

	local function updateLowSecs()
		set('lowSecsColor', {
			enabled   = lsSwitch:IsChecked(),
			threshold = lsSlider:GetValue(),
			color     = { lsColor:GetColor() },
		})
	end
	lsSwitch:SetOnValueChanged(function(val)
		lsSlider:SetShown(val)
		lsColor:SetShown(val)
		updateLowSecs()
	end)
	lsSlider:SetOnValueChanged(function() updateLowSecs() end)
	lsColor:SetOnColorChanged(function() updateLowSecs() end)
	lsSlider:SetShown(lsc.enabled)
	lsColor:SetShown(lsc.enabled)

	-- Optional border/bg colors
	if(opts.showBorderColor) then
		local bc = get('borderColor') or { 0, 0, 0, 1 }
		local bcPicker = Widgets.CreateColorPicker(card, innerW, 'Border Color', bc)
		Widgets.SetPoint(bcPicker, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
		bcPicker:SetOnColorChanged(function(r, g, b, a)
			set('borderColor', { r, g, b, a })
		end)
		cy = cy - bcPicker._explicitHeight - C.Spacing.base
	end

	if(opts.showBgColor) then
		local bg = get('bgColor') or { 0, 0, 0, 0.5 }
		local bgPicker = Widgets.CreateColorPicker(card, innerW, 'Background Color', bg)
		Widgets.SetPoint(bgPicker, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
		bgPicker:SetOnColorChanged(function(r, g, b, a)
			set('bgColor', { r, g, b, a })
		end)
		cy = cy - bgPicker._explicitHeight - C.Spacing.tight
	end

	Widgets.SetCardHeight(card, math.abs(cy))
	return yOffset - math.abs(cy) - C.Spacing.normal
end
```

- [ ] **Step 2: Add to TOC after IndicatorCRUD.lua**

```
Settings/Builders/SharedCards.lua
```

- [ ] **Step 3: Sync and verify no Lua errors**

- [ ] **Step 4: Commit**

```bash
git add Settings/Builders/SharedCards.lua Framed.toc
git commit -m "feat: add SharedCards builders (Font, Glow, Position, ThresholdColor)"
```

---

## Phase 6: Settings UI Expansion

### Task 16: IndicatorCRUD — Per-Type Edit Panels, Type Description, DisplayType Toggle

**Files:**
- Modify: `Settings/Builders/IndicatorCRUD.lua`

This expands the `buildIndicatorSettings()` function to use SharedCards for each indicator type, adds type description in the Create card, and adds the displayType toggle for Icon/Icons.

- [ ] **Step 1: Add type description to Create card**

In the Create card section (~line 504), after the type dropdown, add a description FontString:

```lua
-- Type description
local TYPE_DESCRIPTIONS = {
	Icon    = 'Single spell icon or colored square',
	Icons   = 'Row/grid of spell icons or colored squares',
	Bar     = 'Single depleting status bar',
	Bars    = 'Row/grid of depleting status bars',
	Color   = 'Colored rectangle positioned on frame',
	Overlay = 'Health bar overlay — depleting, static fill, or both',
	Border  = 'Colored border around the frame edge',
	Glow    = 'Glow effect around the frame',
}

local descFS = Widgets.CreateFontString(card, C.Font.sizeSmall, C.Colors.textSecondary)
descFS:SetPoint('TOPLEFT', typeDropdown, 'BOTTOMLEFT', 0, -C.Spacing.base)
descFS:SetWidth(innerW)
descFS:SetWordWrap(true)
descFS:SetText(TYPE_DESCRIPTIONS[typeDropdown:GetSelectedValue()] or '')

typeDropdown:SetOnValueChanged(function(val)
	descFS:SetText(TYPE_DESCRIPTIONS[val] or '')
	-- ... existing logic ...
end)
```

- [ ] **Step 2: Add displayType toggle for Icon/Icons in Create card**

After the type description, add a conditionally-shown toggle:

```lua
-- Display type toggle (Icon/Icons only)
local displayTypeRow = CreateFrame('Frame', nil, card)
displayTypeRow:SetPoint('TOPLEFT', descFS, 'BOTTOMLEFT', 0, -C.Spacing.base)
Widgets.SetSize(displayTypeRow, innerW, 24)
displayTypeRow:Hide()

local spellIconBtn = Widgets.CreateButton(displayTypeRow, 'Spell Icons', 'accent', innerW / 2 - 2, 24)
spellIconBtn:SetPoint('LEFT', displayTypeRow, 'LEFT', 0, 0)
local squareBtn = Widgets.CreateButton(displayTypeRow, 'Square Colors', 'widget', innerW / 2 - 2, 24)
squareBtn:SetPoint('RIGHT', displayTypeRow, 'RIGHT', 0, 0)

local selectedDisplayType = C.IconDisplay.SPELL_ICON
spellIconBtn:SetOnClick(function()
	selectedDisplayType = C.IconDisplay.SPELL_ICON
	-- visual toggle feedback
end)
squareBtn:SetOnClick(function()
	selectedDisplayType = C.IconDisplay.COLORED_SQUARE
end)

-- Show/hide based on type selection
typeDropdown:SetOnValueChanged(function(val)
	descFS:SetText(TYPE_DESCRIPTIONS[val] or '')
	displayTypeRow:SetShown(val == 'Icon' or val == 'Icons')
end)
```

In the create handler, include `displayType = selectedDisplayType` in the new indicator data when type is Icon/Icons.

- [ ] **Step 3: Expand buildIndicatorSettings with per-type SharedCards**

Replace the type-specific section (~lines 408-463) with full per-type panels:

```lua
local indType = cur.type

-- ── Icon / Icons ───────────────────────────────────
if(indType == 'Icon' or indType == 'Icons') then
	-- Size card
	local sizeCard, sizeH = Widgets.CreateCard(parent, width)
	Widgets.SetPoint(sizeCard, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local scy = -C.Spacing.tight

	local wSlider = Widgets.CreateSlider(sizeCard, width - C.Spacing.tight * 2, 'Width', 8, 48, 1)
	Widgets.SetPoint(wSlider, 'TOPLEFT', sizeCard, 'TOPLEFT', C.Spacing.tight, scy)
	wSlider:SetValue(get('iconWidth') or 14)
	wSlider:SetOnValueChanged(function(v) set('iconWidth', v) end)
	scy = scy - wSlider._explicitHeight - C.Spacing.base

	local hSlider = Widgets.CreateSlider(sizeCard, width - C.Spacing.tight * 2, 'Height', 8, 48, 1)
	Widgets.SetPoint(hSlider, 'TOPLEFT', sizeCard, 'TOPLEFT', C.Spacing.tight, scy)
	hSlider:SetValue(get('iconHeight') or 14)
	hSlider:SetOnValueChanged(function(v) set('iconHeight', v) end)
	scy = scy - hSlider._explicitHeight - C.Spacing.tight

	Widgets.SetCardHeight(sizeCard, math.abs(scy))
	yOffset = yOffset - math.abs(scy) - C.Spacing.normal

	-- Layout card (Icons only)
	if(indType == 'Icons') then
		local layoutCard, lH = Widgets.CreateCard(parent, width)
		Widgets.SetPoint(layoutCard, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		local lcy = -C.Spacing.tight
		local lInner = width - C.Spacing.tight * 2

		local maxSlider = Widgets.CreateSlider(layoutCard, lInner, 'Max Displayed', 1, 10, 1)
		Widgets.SetPoint(maxSlider, 'TOPLEFT', layoutCard, 'TOPLEFT', C.Spacing.tight, lcy)
		maxSlider:SetValue(get('maxDisplayed') or 3)
		maxSlider:SetOnValueChanged(function(v) set('maxDisplayed', v) end)
		lcy = lcy - maxSlider._explicitHeight - C.Spacing.base

		local nplSlider = Widgets.CreateSlider(layoutCard, lInner, 'Num Per Line (0=single row)', 0, 10, 1)
		Widgets.SetPoint(nplSlider, 'TOPLEFT', layoutCard, 'TOPLEFT', C.Spacing.tight, lcy)
		nplSlider:SetValue(get('numPerLine') or 0)
		nplSlider:SetOnValueChanged(function(v) set('numPerLine', v) end)
		lcy = lcy - nplSlider._explicitHeight - C.Spacing.base

		local sxSlider = Widgets.CreateSlider(layoutCard, lInner, 'Spacing X', 0, 20, 1)
		Widgets.SetPoint(sxSlider, 'TOPLEFT', layoutCard, 'TOPLEFT', C.Spacing.tight, lcy)
		sxSlider:SetValue(get('spacingX') or 1)
		sxSlider:SetOnValueChanged(function(v) set('spacingX', v) end)
		lcy = lcy - sxSlider._explicitHeight - C.Spacing.base

		local sySlider = Widgets.CreateSlider(layoutCard, lInner, 'Spacing Y', 0, 20, 1)
		Widgets.SetPoint(sySlider, 'TOPLEFT', layoutCard, 'TOPLEFT', C.Spacing.tight, lcy)
		sySlider:SetValue(get('spacingY') or 1)
		sySlider:SetOnValueChanged(function(v) set('spacingY', v) end)
		lcy = lcy - sySlider._explicitHeight - C.Spacing.base

		local orientItems = {
			{ label = 'Right', value = 'RIGHT' },
			{ label = 'Left',  value = 'LEFT' },
			{ label = 'Up',    value = 'UP' },
			{ label = 'Down',  value = 'DOWN' },
		}
		local orientDD = Widgets.CreateDropdown(layoutCard, lInner, 'Orientation', orientItems)
		Widgets.SetPoint(orientDD, 'TOPLEFT', layoutCard, 'TOPLEFT', C.Spacing.tight, lcy)
		orientDD:SetSelectedValue(get('orientation') or 'RIGHT')
		orientDD:SetOnValueChanged(function(v) set('orientation', v) end)
		lcy = lcy - orientDD._explicitHeight - C.Spacing.tight

		Widgets.SetCardHeight(layoutCard, math.abs(lcy))
		yOffset = yOffset - math.abs(lcy) - C.Spacing.normal
	end

	-- Cooldown & Duration card
	local cdCard, cdH = Widgets.CreateCard(parent, width)
	Widgets.SetPoint(cdCard, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local cdcy = -C.Spacing.tight
	local cdInner = width - C.Spacing.tight * 2

	local cdSwitch = Widgets.CreateSwitch(cdCard, 'Show Cooldown')
	Widgets.SetPoint(cdSwitch, 'TOPLEFT', cdCard, 'TOPLEFT', C.Spacing.tight, cdcy)
	cdSwitch:SetChecked(get('showCooldown') ~= false)
	cdSwitch:SetOnValueChanged(function(v) set('showCooldown', v) end)
	cdcy = cdcy - cdSwitch._explicitHeight - C.Spacing.base

	local durationItems = {
		{ label = 'Never',  value = 'Never' },
		{ label = 'Always', value = 'Always' },
		{ label = '<75%',   value = '<75' },
		{ label = '<50%',   value = '<50' },
		{ label = '<25%',   value = '<25' },
		{ label = '<15s',   value = '<15s' },
		{ label = '<5s',    value = '<5s' },
	}
	local durDD = Widgets.CreateDropdown(cdCard, cdInner, 'Show Duration', durationItems)
	Widgets.SetPoint(durDD, 'TOPLEFT', cdCard, 'TOPLEFT', C.Spacing.tight, cdcy)
	durDD:SetSelectedValue(get('durationMode') or 'Never')
	durDD:SetOnValueChanged(function(v) set('durationMode', v) end)
	cdcy = cdcy - durDD._explicitHeight - C.Spacing.tight

	Widgets.SetCardHeight(cdCard, math.abs(cdcy))
	yOffset = yOffset - math.abs(cdcy) - C.Spacing.normal

	-- Duration font (shown when durationMode != Never)
	if((get('durationMode') or 'Never') ~= 'Never') then
		yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Duration Font', 'durationFont', get, set)
	end

	-- Stack card
	local stSwitch = Widgets.CreateSwitch(parent, 'Show Stacks')
	Widgets.SetPoint(stSwitch, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	stSwitch:SetChecked(get('showStacks') ~= false)
	stSwitch:SetOnValueChanged(function(v) set('showStacks', v) end)
	yOffset = yOffset - stSwitch._explicitHeight - C.Spacing.normal

	if(get('showStacks') ~= false) then
		yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Stack Font', 'stackFont', get, set)
	end

	-- Glow card
	yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = true })

	-- Position & Layer
	yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set)

-- ── Bar / Bars ─────────────────────────────────────
elseif(indType == 'Bar' or indType == 'Bars') then
	-- Size card
	local bCard, bH = Widgets.CreateCard(parent, width)
	Widgets.SetPoint(bCard, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local bcy = -C.Spacing.tight
	local bInner = width - C.Spacing.tight * 2

	local bwSlider = Widgets.CreateSlider(bCard, bInner, 'Width', 3, 500, 1)
	Widgets.SetPoint(bwSlider, 'TOPLEFT', bCard, 'TOPLEFT', C.Spacing.tight, bcy)
	bwSlider:SetValue(get('barWidth') or 50)
	bwSlider:SetOnValueChanged(function(v) set('barWidth', v) end)
	bcy = bcy - bwSlider._explicitHeight - C.Spacing.base

	local bhSlider = Widgets.CreateSlider(bCard, bInner, 'Height', 3, 500, 1)
	Widgets.SetPoint(bhSlider, 'TOPLEFT', bCard, 'TOPLEFT', C.Spacing.tight, bcy)
	bhSlider:SetValue(get('barHeight') or 4)
	bhSlider:SetOnValueChanged(function(v) set('barHeight', v) end)
	bcy = bcy - bhSlider._explicitHeight - C.Spacing.base

	local boItems = {
		{ label = 'Horizontal', value = 'Horizontal' },
		{ label = 'Vertical',   value = 'Vertical' },
	}
	local boDD = Widgets.CreateDropdown(bCard, bInner, 'Bar Orientation', boItems)
	Widgets.SetPoint(boDD, 'TOPLEFT', bCard, 'TOPLEFT', C.Spacing.tight, bcy)
	boDD:SetSelectedValue(get('barOrientation') or 'Horizontal')
	boDD:SetOnValueChanged(function(v) set('barOrientation', v) end)
	bcy = bcy - boDD._explicitHeight - C.Spacing.tight

	Widgets.SetCardHeight(bCard, math.abs(bcy))
	yOffset = yOffset - math.abs(bcy) - C.Spacing.normal

	-- Layout card (Bars only)
	if(indType == 'Bars') then
		local blCard, blH = Widgets.CreateCard(parent, width)
		Widgets.SetPoint(blCard, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		local blcy = -C.Spacing.tight

		local bmSlider = Widgets.CreateSlider(blCard, bInner, 'Max Displayed', 1, 10, 1)
		Widgets.SetPoint(bmSlider, 'TOPLEFT', blCard, 'TOPLEFT', C.Spacing.tight, blcy)
		bmSlider:SetValue(get('maxDisplayed') or 3)
		bmSlider:SetOnValueChanged(function(v) set('maxDisplayed', v) end)
		blcy = blcy - bmSlider._explicitHeight - C.Spacing.base

		local bnSlider = Widgets.CreateSlider(blCard, bInner, 'Num Per Line (0=single row)', 0, 10, 1)
		Widgets.SetPoint(bnSlider, 'TOPLEFT', blCard, 'TOPLEFT', C.Spacing.tight, blcy)
		bnSlider:SetValue(get('numPerLine') or 0)
		bnSlider:SetOnValueChanged(function(v) set('numPerLine', v) end)
		blcy = blcy - bnSlider._explicitHeight - C.Spacing.base

		local bsxSlider = Widgets.CreateSlider(blCard, bInner, 'Spacing X', -1, 50, 1)
		Widgets.SetPoint(bsxSlider, 'TOPLEFT', blCard, 'TOPLEFT', C.Spacing.tight, blcy)
		bsxSlider:SetValue(get('spacingX') or 1)
		bsxSlider:SetOnValueChanged(function(v) set('spacingX', v) end)
		blcy = blcy - bsxSlider._explicitHeight - C.Spacing.base

		local bsySlider = Widgets.CreateSlider(blCard, bInner, 'Spacing Y', -1, 50, 1)
		Widgets.SetPoint(bsySlider, 'TOPLEFT', blCard, 'TOPLEFT', C.Spacing.tight, blcy)
		bsySlider:SetValue(get('spacingY') or 1)
		bsySlider:SetOnValueChanged(function(v) set('spacingY', v) end)
		blcy = blcy - bsySlider._explicitHeight - C.Spacing.base

		local blOrientItems = {
			{ label = 'Right', value = 'RIGHT' },
			{ label = 'Left',  value = 'LEFT' },
			{ label = 'Up',    value = 'UP' },
			{ label = 'Down',  value = 'DOWN' },
		}
		local blOrientDD = Widgets.CreateDropdown(blCard, bInner, 'Layout Direction', blOrientItems)
		Widgets.SetPoint(blOrientDD, 'TOPLEFT', blCard, 'TOPLEFT', C.Spacing.tight, blcy)
		blOrientDD:SetSelectedValue(get('orientation') or 'DOWN')
		blOrientDD:SetOnValueChanged(function(v) set('orientation', v) end)
		blcy = blcy - blOrientDD._explicitHeight - C.Spacing.tight

		Widgets.SetCardHeight(blCard, math.abs(blcy))
		yOffset = yOffset - math.abs(blcy) - C.Spacing.normal
	end

	-- Threshold color card with border/bg
	yOffset = F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set, { showBorderColor = true, showBgColor = true })

	-- Duration dropdown
	local bdItems = {
		{ label = 'Never',  value = 'Never' },
		{ label = 'Always', value = 'Always' },
		{ label = '<75%',   value = '<75' },
		{ label = '<50%',   value = '<50' },
		{ label = '<25%',   value = '<25' },
		{ label = '<15s',   value = '<15s' },
		{ label = '<5s',    value = '<5s' },
	}
	local bdDD = Widgets.CreateDropdown(parent, width, 'Show Duration', bdItems)
	Widgets.SetPoint(bdDD, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	bdDD:SetSelectedValue(get('durationMode') or 'Never')
	bdDD:SetOnValueChanged(function(v) set('durationMode', v) end)
	yOffset = yOffset - bdDD._explicitHeight - C.Spacing.normal

	if((get('durationMode') or 'Never') ~= 'Never') then
		yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Duration Font', 'durationFont', get, set)
	end

	-- Stacks
	local bstSwitch = Widgets.CreateSwitch(parent, 'Show Stacks')
	Widgets.SetPoint(bstSwitch, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	bstSwitch:SetChecked(get('showStacks') ~= false)
	bstSwitch:SetOnValueChanged(function(v) set('showStacks', v) end)
	yOffset = yOffset - bstSwitch._explicitHeight - C.Spacing.normal

	if(get('showStacks') ~= false) then
		yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Stack Font', 'stackFont', get, set)
	end

	-- Glow + Position
	yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = true })
	yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set)

-- ── Color (Rect) ───────────────────────────────────
elseif(indType == 'Color') then
	-- Size card
	local rcCard, rcH = Widgets.CreateCard(parent, width)
	Widgets.SetPoint(rcCard, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local rccy = -C.Spacing.tight
	local rcInner = width - C.Spacing.tight * 2

	local rwSlider = Widgets.CreateSlider(rcCard, rcInner, 'Width', 3, 500, 1)
	Widgets.SetPoint(rwSlider, 'TOPLEFT', rcCard, 'TOPLEFT', C.Spacing.tight, rccy)
	rwSlider:SetValue(get('rectWidth') or 10)
	rwSlider:SetOnValueChanged(function(v) set('rectWidth', v) end)
	rccy = rccy - rwSlider._explicitHeight - C.Spacing.base

	local rhSlider = Widgets.CreateSlider(rcCard, rcInner, 'Height', 3, 500, 1)
	Widgets.SetPoint(rhSlider, 'TOPLEFT', rcCard, 'TOPLEFT', C.Spacing.tight, rccy)
	rhSlider:SetValue(get('rectHeight') or 10)
	rhSlider:SetOnValueChanged(function(v) set('rectHeight', v) end)
	rccy = rccy - rhSlider._explicitHeight - C.Spacing.tight

	Widgets.SetCardHeight(rcCard, math.abs(rccy))
	yOffset = yOffset - math.abs(rccy) - C.Spacing.normal

	-- Threshold colors with border
	yOffset = F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set, { showBorderColor = true })

	-- Stacks + Duration (same pattern as Bar)
	local cstSwitch = Widgets.CreateSwitch(parent, 'Show Stacks')
	Widgets.SetPoint(cstSwitch, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	cstSwitch:SetChecked(get('showStacks') ~= false)
	cstSwitch:SetOnValueChanged(function(v) set('showStacks', v) end)
	yOffset = yOffset - cstSwitch._explicitHeight - C.Spacing.normal

	if(get('showStacks') ~= false) then
		yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Stack Font', 'stackFont', get, set)
	end

	-- Glow + Position
	yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = true })
	yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set)

-- ── Overlay ────────────────────────────────────────
elseif(indType == 'Overlay') then
	-- Mode dropdown
	local omCard, omH = Widgets.CreateCard(parent, width)
	Widgets.SetPoint(omCard, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local omcy = -C.Spacing.tight
	local omInner = width - C.Spacing.tight * 2

	local modeItems = {
		{ label = 'Overlay',  value = 'Overlay' },
		{ label = 'FrameBar', value = 'FrameBar' },
		{ label = 'Both',     value = 'Both' },
	}
	local modeDD = Widgets.CreateDropdown(omCard, omInner, 'Mode', modeItems)
	Widgets.SetPoint(modeDD, 'TOPLEFT', omCard, 'TOPLEFT', C.Spacing.tight, omcy)
	modeDD:SetSelectedValue(get('overlayMode') or 'Overlay')
	modeDD:SetOnValueChanged(function(v) set('overlayMode', v) end)
	omcy = omcy - modeDD._explicitHeight - C.Spacing.base

	-- Color picker (always visible)
	local olColor = get('color') or { 0, 0, 0, 0.6 }
	local olPicker = Widgets.CreateColorPicker(omCard, omInner, 'Color', olColor)
	Widgets.SetPoint(olPicker, 'TOPLEFT', omCard, 'TOPLEFT', C.Spacing.tight, omcy)
	olPicker:SetOnColorChanged(function(r, g, b, a) set('color', { r, g, b, a }) end)
	omcy = omcy - olPicker._explicitHeight - C.Spacing.tight

	Widgets.SetCardHeight(omCard, math.abs(omcy))
	yOffset = yOffset - math.abs(omcy) - C.Spacing.normal

	-- Threshold colors (Overlay or Both only)
	local mode = get('overlayMode') or 'Overlay'
	if(mode == 'Overlay' or mode == 'Both') then
		yOffset = F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set)

		-- Smooth toggle
		local smSwitch = Widgets.CreateSwitch(parent, 'Smooth Animation')
		Widgets.SetPoint(smSwitch, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		smSwitch:SetChecked(get('smooth') ~= false)
		smSwitch:SetOnValueChanged(function(v) set('smooth', v) end)
		yOffset = yOffset - smSwitch._explicitHeight - C.Spacing.normal

		-- Bar orientation
		local olOrientItems = {
			{ label = 'Horizontal', value = 'Horizontal' },
			{ label = 'Vertical',   value = 'Vertical' },
		}
		local olOrientDD = Widgets.CreateDropdown(parent, width, 'Orientation', olOrientItems)
		Widgets.SetPoint(olOrientDD, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		olOrientDD:SetSelectedValue(get('barOrientation') or 'Horizontal')
		olOrientDD:SetOnValueChanged(function(v) set('barOrientation', v) end)
		yOffset = yOffset - olOrientDD._explicitHeight - C.Spacing.normal
	end

	-- Position (frame level only — always anchored to health bar)
	yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set, { hidePosition = true })

-- ── Border ─────────────────────────────────────────
elseif(indType == 'Border') then
	local brCard, brH = Widgets.CreateCard(parent, width)
	Widgets.SetPoint(brCard, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local brcy = -C.Spacing.tight
	local brInner = width - C.Spacing.tight * 2

	-- Thickness slider
	local thSlider = Widgets.CreateSlider(brCard, brInner, 'Thickness', 1, 15, 1)
	Widgets.SetPoint(thSlider, 'TOPLEFT', brCard, 'TOPLEFT', C.Spacing.tight, brcy)
	thSlider:SetValue(get('borderThickness') or 2)
	thSlider:SetOnValueChanged(function(v) set('borderThickness', v) end)
	brcy = brcy - thSlider._explicitHeight - C.Spacing.base

	-- Color picker
	local brColor = get('color') or { 1, 1, 1, 1 }
	local brPicker = Widgets.CreateColorPicker(brCard, brInner, 'Color', brColor)
	Widgets.SetPoint(brPicker, 'TOPLEFT', brCard, 'TOPLEFT', C.Spacing.tight, brcy)
	brPicker:SetOnColorChanged(function(r, g, b, a) set('color', { r, g, b, a }) end)
	brcy = brcy - brPicker._explicitHeight - C.Spacing.base

	-- FadeOut toggle
	local foSwitch = Widgets.CreateSwitch(brCard, 'Fade Out')
	Widgets.SetPoint(foSwitch, 'TOPLEFT', brCard, 'TOPLEFT', C.Spacing.tight, brcy)
	foSwitch:SetChecked(get('fadeOut') or false)
	foSwitch:SetOnValueChanged(function(v) set('fadeOut', v) end)
	brcy = brcy - foSwitch._explicitHeight - C.Spacing.tight

	Widgets.SetCardHeight(brCard, math.abs(brcy))
	yOffset = yOffset - math.abs(brcy) - C.Spacing.normal

	-- Position (frame level only)
	yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set, { hidePosition = true })

-- ── Glow ───────────────────────────────────────────
elseif(indType == 'Glow') then
	-- FadeOut toggle
	local gfoSwitch = Widgets.CreateSwitch(parent, 'Fade Out')
	Widgets.SetPoint(gfoSwitch, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	gfoSwitch:SetChecked(get('fadeOut') or false)
	gfoSwitch:SetOnValueChanged(function(v) set('fadeOut', v) end)
	yOffset = yOffset - gfoSwitch._explicitHeight - C.Spacing.normal

	-- Glow card (None not allowed for standalone glow)
	yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = false })
	-- Position (frame level only)
	yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set, { hidePosition = true })
end
```

- [ ] **Step 4: Sync and verify**

Open settings in-game, navigate to a Buffs panel, click Edit on an indicator. Verify the expanded settings appear correctly for each type.

- [ ] **Step 5: Commit**

```bash
git add Settings/Builders/IndicatorCRUD.lua
git commit -m "feat: expand IndicatorCRUD with per-type edit panels, type description, displayType toggle"
```

---

### Task 16b: Migrate Existing Panels to SharedCards + Per-Spell Color

**Files:**
- Modify: `Settings/Builders/BorderIconSettings.lua`
- Modify: `Settings/Panels/TargetedSpells.lua`
- Modify: `Widgets/SpellList.lua`

Existing panels that duplicate font/glow/position UI should use the new SharedCards. Also add per-spell color picker support to the SpellList widget.

- [ ] **Step 1: Update BorderIconSettings.lua to use SharedCards**

Find the font settings section (stack font, duration font) and replace with calls to `F.Settings.BuildFontCard()`. Find the position section and replace with `F.Settings.BuildPositionCard()`:

```lua
-- Replace inline stack font widgets with:
yOffset = F.Settings.BuildFontCard(content, width, yOffset, 'Stack Font', 'stackFont', get, set)

-- Replace inline duration font widgets with:
yOffset = F.Settings.BuildFontCard(content, width, yOffset, 'Duration Font', 'durationFont', get, set)

-- Replace inline position widgets with:
yOffset = F.Settings.BuildPositionCard(content, width, yOffset, get, set)
```

- [ ] **Step 2: Update TargetedSpells.lua panel to use BuildGlowCard**

Find the glow type/color/params section and replace with:

```lua
yOffset = F.Settings.BuildGlowCard(content, width, yOffset, getGlow, setGlow, { allowNone = false })
```

Where `getGlow` and `setGlow` read/write to the `glow` subtable of the TargetedSpells config.

- [ ] **Step 3: Add per-spell color picker to SpellList widget**

In `Widgets/SpellList.lua`, add support for an `opts.showColorPicker` flag. When true, each spell row gets a color swatch next to the existing up/down/delete controls:

```lua
-- In the row creation function, after existing controls:
if(self._showColorPicker) then
	local spellColors = self._spellColors or {}
	local color = spellColors[spellId] or { 1, 1, 1 }
	local swatch = Widgets.CreateColorPicker(row, 20, nil, color)
	swatch:SetPoint('RIGHT', deleteBtn, 'LEFT', -4, 0)
	swatch:SetOnColorChanged(function(r, g, b)
		if(not self._spellColors) then self._spellColors = {} end
		self._spellColors[spellId] = { r, g, b }
		if(self._onChanged) then self._onChanged(self:GetSpells()) end
	end)
end
```

The IndicatorCRUD edit panel for Icon/Icons sets `showColorPicker = true` and passes `spellColors` when `displayType == 'ColoredSquare'`.

- [ ] **Step 4: Sync and verify**

- [ ] **Step 5: Commit**

```bash
git add Settings/Builders/BorderIconSettings.lua Settings/Panels/TargetedSpells.lua Widgets/SpellList.lua
git commit -m "feat: migrate BorderIconSettings and TargetedSpells to SharedCards, add per-spell color to SpellList"
```

---

### Task 17: Settings Panel Enabled Toggles

**Files:**
- Modify: `Settings/Panels/LossOfControl.lua`
- Modify: `Settings/Panels/CrowdControl.lua`
- Modify: `Settings/Panels/MissingBuffs.lua`
- Modify: `Settings/Panels/PrivateAuras.lua`

Each panel needs an enabled toggle at the top, reading/writing the `enabled` config key.

- [ ] **Step 1: Add enabled toggle to LossOfControl.lua**

After the unit type dropdown row and before the description text, add:

```lua
-- ── Enabled toggle ────────────────────────────────
local function getEnabled()
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	local config = (F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.lossOfControl')) or {}
	return config.enabled or false
end

local function setEnabled(val)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.lossOfControl.enabled', val)
	end
	if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.lossOfControl.enabled')
	end
end

local enableSwitch = Widgets.CreateSwitch(content, 'Enabled')
enableSwitch:ClearAllPoints()
Widgets.SetPoint(enableSwitch, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
enableSwitch:SetChecked(getEnabled())
enableSwitch:SetOnValueChanged(function(val) setEnabled(val) end)
yOffset = yOffset - enableSwitch._explicitHeight - C.Spacing.normal
```

- [ ] **Step 2: Apply same pattern to CrowdControl.lua**

Same structure, reading/writing `crowdControl.enabled`.

- [ ] **Step 3: Apply same pattern to MissingBuffs.lua**

Same structure, reading/writing `missingBuffs.enabled`.

- [ ] **Step 4: Apply same pattern to PrivateAuras.lua**

Same structure, reading/writing `privateAuras.enabled`.

- [ ] **Step 5: Sync and verify**

Open settings → navigate to each panel (LoC, CC, MissingBuffs, PrivateAuras). Verify the enabled toggle appears and toggles the element on/off.

- [ ] **Step 6: Commit**

```bash
git add Settings/Panels/LossOfControl.lua Settings/Panels/CrowdControl.lua Settings/Panels/MissingBuffs.lua Settings/Panels/PrivateAuras.lua
git commit -m "feat: add enabled toggle to LoC, CC, MissingBuffs, PrivateAuras settings panels"
```

---

### Task 18: Panel Refresh Framework

**Files:**
- Modify: `Settings/Framework.lua`

Add support for panels to return a `Refresh()` callback from `create()`. The framework stores it and calls it on `EDITING_PRESET_CHANGED` or after Copy-to.

- [ ] **Step 1: Update SetActivePanel to store Refresh callback**

In `SetActivePanel()` (~line 213), where `info.create(Settings._contentParent)` is called, capture a second return value:

```lua
-- In the panel creation block:
local panelFrame, refreshFn = info.create(Settings._contentParent)
Settings._panelFrames[panelId] = panelFrame
Settings._panelRefresh[panelId] = refreshFn  -- may be nil
```

Initialize `_panelRefresh` at the top of the file:

```lua
Settings._panelRefresh = {}
```

- [ ] **Step 2: Register EDITING_PRESET_CHANGED listener for refresh**

After the existing `EDITING_PRESET_CHANGED` handler, add:

```lua
F.EventBus:Register('EDITING_PRESET_CHANGED', function()
	local activeId = Settings._activePanelId
	if(activeId and Settings._panelRefresh[activeId]) then
		Settings._panelRefresh[activeId]()
	end
end, 'Settings.PanelRefresh')
```

- [ ] **Step 3: Expose RefreshActivePanel for Copy-to**

```lua
function Settings.RefreshActivePanel()
	local activeId = Settings._activePanelId
	if(activeId and Settings._panelRefresh[activeId]) then
		Settings._panelRefresh[activeId]()
	end
end
```

- [ ] **Step 4: Update CopyToDialog to call RefreshActivePanel on complete**

In `Settings/CopyToDialog.lua`, after the confirm callback completes the copy operation, add:

```lua
if(F.Settings.RefreshActivePanel) then
	F.Settings.RefreshActivePanel()
end
```

- [ ] **Step 5: Sync and verify**

- [ ] **Step 6: Commit**

```bash
git add Settings/Framework.lua Settings/CopyToDialog.lua
git commit -m "feat: add panel Refresh() callback support for external config changes"
```

---

## Phase 7: Commands & Wiring

### Task 19: /framed reset all — Single Confirmation Dialog

**Files:**
- Modify: `Init.lua`

The existing `/framed restore` command restores from a per-session backup. This task adds `/framed reset all` with a single confirmation dialog and updates `restore` to work with the reset-specific backup.

- [ ] **Step 1: Add reset all command**

In `Init.lua`, in the slash command handler, before the `elseif(cmd == 'restore')` block, add:

```lua
elseif(cmd == 'reset all' or (cmd == 'reset' and msg:lower():trim():match('^reset%s+all$'))) then
	local d = F.Widgets.ShowConfirmDialog(
		'Reset All Settings',
		'This will delete ALL Framed settings, presets, and customizations.\nA backup will be saved — you can restore later with /framed restore.',
		function()
			FramedBackupDB = {
				db        = FramedDB and CopyTable(FramedDB) or nil,
				char      = FramedCharDB and CopyTable(FramedCharDB) or nil,
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
```

Note: The slash command parser uses `msg:lower():trim()` which gives us the full message. We need to handle "reset all" as a two-word command. Update the parser:

```lua
SlashCmdList['FRAMED'] = function(msg)
	local trimmed = msg:lower():trim()
	local cmd, arg1 = trimmed:match('^(%S+)%s*(.*)$')
	if(not cmd) then cmd = '' end

	if(cmd == 'version' or cmd == 'v') then
		-- ... existing ...
	elseif(cmd == 'reset' and arg1 == 'all') then
		-- reset all logic above
	elseif(cmd == 'restore') then
		-- ... existing restore logic ...
```

- [ ] **Step 2: Update restore command to use timestamped backup**

Replace the existing `restore` block with the spec's version:

```lua
elseif(cmd == 'restore') then
	if(not FramedBackupDB or not FramedBackupDB.db) then
		-- Fall back to legacy backup format
		if(FramedBackupDB and not FramedBackupDB.db) then
			-- Old format: FramedBackupDB is the raw DB copy
			F.Widgets.ShowConfirmDialog('Restore Settings', 'Restore settings from last session backup? This will reload the UI.', function()
				FramedDB = CopyTable(FramedBackupDB)
				ReloadUI()
			end)
		else
			print('|cff00ccff Framed|r No backup found. Nothing to restore.')
		end
		return
	end
	local ts = FramedBackupDB.timestamp
	local dateStr = ts and date('%Y-%m-%d %H:%M', ts) or 'unknown date'
	F.Widgets.ShowConfirmDialog(
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

- [ ] **Step 3: Update help text**

Add to the help output:

```lua
print('  /framed reset all — Reset all settings to defaults (with backup)')
```

- [ ] **Step 4: Sync and verify**

Test `/framed reset all` — should show red confirmation dialog. Test `/framed restore` — should show backup date.

- [ ] **Step 5: Commit**

```bash
git add Init.lua
git commit -m "feat: add /framed reset all with backup + update /framed restore with timestamp"
```

---

### Task 20: TOC — Final Load Order Verification

**Files:**
- Modify: `Framed.toc`

Ensure all new files are in the TOC in the correct load order.

- [ ] **Step 1: Verify and update TOC**

The following files must be in the TOC. Check each exists:

```
# Elements - Indicators (after existing entries)
Elements/Indicators/Bars.lua         # NEW — after Bar.lua

# Units (after StyleBuilder.lua)
Units/LiveUpdate/FrameConfig.lua     # NEW
Units/LiveUpdate/AuraConfig.lua      # NEW

# Settings (after IndicatorCRUD.lua)
Settings/Builders/SharedCards.lua    # NEW
```

- [ ] **Step 2: Bump version**

In the TOC header, bump the patch version:

```
## Version: 0.3.2
```

- [ ] **Step 3: Full sync and /reload test**

Sync entire addon folder. `/reload` in-game. Open settings, navigate through all panels. Check:
- No Lua errors
- Indicators render on frames
- Settings panels load correctly
- Enabled toggles work
- Reset/restore commands work

- [ ] **Step 4: Commit**

```bash
git add Framed.toc
git commit -m "chore: update TOC load order for new files, bump to 0.3.2"
```

---

## Post-Implementation

### Task 21: Code Review

After all tasks are complete, run a **superpowers code review** (`code-reviewer` agent) to verify:

- [ ] All spec items fully implemented (no gaps or stubs)
- [ ] Every element and indicator type renders visually on frames
- [ ] New/expanded renderers confirmed working
- [ ] Live-update handlers work (config change → frame updates without reload)
- [ ] SharedCards used everywhere (no duplicated font/glow/position/threshold-color code)
- [ ] No orphaned config keys or elements
- [ ] Frame levels don't z-fight per Part 0.5
- [ ] Code style matches CLAUDE.md (tabs, parenthesized conditions, camelCase, etc.)
- [ ] File sizes under ~500 lines
- [ ] PR 463 principles enforced (no pcall, single `F.IsValueNonSecret()`, no sanitization, no `rawequal()`)
- [ ] No Cell/ElvUI references in Lua code, comments, or UI labels
