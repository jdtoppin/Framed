# Icon.lua C-Level Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate `IconOnUpdate` from Icon.lua by migrating depletion bar and duration text to C-level WoW APIs, reducing per-frame Lua cost to near zero.

**Architecture:** Replace Lua OnUpdate depletion with `SetTimerDuration` on the StatusBar, replace Lua duration text with Blizzard's cooldown countdown (`SetCooldownFromDurationObject` with `SetDrawSwipe(false)`). A single shared ticker (0.5s) handles color progression and duration threshold via `DurationObject:EvaluateRemainingPercent(curve)`. Aura elements pass `unit` + `auraInstanceID` so Icon can call `C_UnitAuras.GetAuraDuration()`.

**Tech Stack:** WoW 12.0.1+ APIs: `SetTimerDuration`, `SetCooldownFromDurationObject`, `CreateLuaDurationObject`, `C_UnitAuras.GetAuraDuration`, `DurationObject:EvaluateRemainingPercent`, `C_CurveUtil.CreateColorCurve`

**Spec:** `docs/superpowers/specs/2026-04-07-icon-clevel-migration-design.md`

**IMPORTANT:** This migration is strictly for Icon/Icons indicators only. Do NOT touch Bar, BorderIcon, BorderGlow, Overlay, Color, or any other indicator type.

---

### Task 1: Add shared ticker module

A single global ticker frame that all active icons register with for color progression and threshold visibility updates.

**Files:**
- Create: `Elements/Indicators/IconTicker.lua`

- [ ] **Step 1: Create the shared ticker**

Create `Elements/Indicators/IconTicker.lua`:

```lua
local addonName, Framed = ...
local F = Framed

F.Indicators = F.Indicators or {}

-- ============================================================
-- Shared ticker for Icon color progression + threshold visibility
-- One OnUpdate for ALL active icons, throttled to 0.5s
-- ============================================================

local TICKER_INTERVAL = 0.5

local tickerFrame = CreateFrame('Frame')
local activeIcons = {}  -- set: icon = true
local activeCount = 0

tickerFrame:Hide()  -- starts hidden; shown when first icon registers

tickerFrame:SetScript('OnUpdate', function(self, elapsed)
	self._elapsed = (self._elapsed or 0) + elapsed
	if(self._elapsed < TICKER_INTERVAL) then return end
	self._elapsed = 0

	for icon in next, activeIcons do
		-- Color progression
		if(icon._colorCurve and icon._durationObj) then
			local color = icon._durationObj:EvaluateRemainingPercent(icon._colorCurve)
			if(icon._cdText) then
				icon._cdText:SetTextColor(color:GetRGBA())
			end
		end

		-- Threshold visibility
		if(icon._thresholdCurve and icon._durationObj) then
			local vis = icon._durationObj:EvaluateRemainingPercent(icon._thresholdCurve)
			if(icon._cdText) then
				-- Bracket curve returns alpha 1 (show) or 0 (hide)
				local _, _, _, a = vis:GetRGBA()
				if(F.IsValueNonSecret(a)) then
					if(a > 0.5) then
						icon._cdText:Show()
					else
						icon._cdText:Hide()
					end
				end
			end
		end
	end
end)

--- Register an icon for ticker updates.
--- @param icon table The icon object
function F.Indicators.IconTicker_Register(icon)
	if(not activeIcons[icon]) then
		activeIcons[icon] = true
		activeCount = activeCount + 1
		if(activeCount > 0) then
			tickerFrame:Show()
		end
	end
end

--- Unregister an icon from ticker updates.
--- @param icon table The icon object
function F.Indicators.IconTicker_Unregister(icon)
	if(activeIcons[icon]) then
		activeIcons[icon] = nil
		activeCount = activeCount - 1
		if(activeCount <= 0) then
			activeCount = 0
			tickerFrame:Hide()
		end
	end
end
```

- [ ] **Step 2: Add IconTicker.lua to the TOC file**

In `Framed.toc`, add the new file immediately before `Elements/Indicators/Icon.lua`:

```
Elements\Indicators\IconTicker.lua
Elements\Indicators\Icon.lua
```

- [ ] **Step 3: Commit**

```bash
git add Elements/Indicators/IconTicker.lua Framed.toc
git commit -m "Add shared IconTicker module for color/threshold updates"
```

---

### Task 2: Create threshold bracket curves

Build cached bracket curves for each `durationMode` threshold. These are color curves where alpha=1 below threshold, alpha=0 above.

**Files:**
- Create: `Elements/Indicators/IconCurves.lua`

- [ ] **Step 1: Create the curves module**

Create `Elements/Indicators/IconCurves.lua`:

```lua
local addonName, Framed = ...
local F = Framed

F.Indicators = F.Indicators or {}

-- ============================================================
-- Cached bracket curves for duration threshold visibility
-- Each curve maps remaining% → alpha (1 = show, 0 = hide)
-- ============================================================

local cachedThresholdCurves = {}

-- Threshold modes that use percentage-based visibility
local THRESHOLD_PERCENTS = {
	['<75']  = 0.75,
	['<50']  = 0.50,
	['<25']  = 0.25,
}

--- Get or create a bracket curve for the given durationMode.
--- Returns nil for 'Always' or 'Never' (no curve needed).
--- For percentage modes: alpha=1 when remaining% < threshold, alpha=0 when above.
--- For time modes ('<15s', '<5s'): returns nil (not percentage-based, needs special handling).
--- @param mode string
--- @return LuaCurveObjectBase|nil
function F.Indicators.GetThresholdCurve(mode)
	if(mode == 'Always' or mode == 'Never') then return nil end

	if(cachedThresholdCurves[mode]) then
		return cachedThresholdCurves[mode]
	end

	local pct = THRESHOLD_PERCENTS[mode]
	if(not pct) then return nil end  -- time-based modes not supported via curves

	local curve = C_CurveUtil.CreateColorCurve()
	-- Below threshold: visible (alpha = 1)
	-- At 0% remaining (expired): visible
	curve:AddPoint(0, CreateColor(1, 1, 1, 1))
	-- Just below threshold: visible
	curve:AddPoint(pct - 0.001, CreateColor(1, 1, 1, 1))
	-- At threshold: hidden
	curve:AddPoint(pct, CreateColor(1, 1, 1, 0))
	-- Full duration remaining: hidden
	curve:AddPoint(1, CreateColor(1, 1, 1, 0))

	cachedThresholdCurves[mode] = curve
	return curve
end

--- Build a color progression curve from user config colors.
--- @param startColor table {r, g, b} color at full duration (remaining% = 1)
--- @param midColor table {r, g, b} color at half duration (remaining% = 0.5)
--- @param endColor table {r, g, b} color near expiry (remaining% = 0)
--- @return LuaCurveObjectBase
function F.Indicators.CreateDurationColorCurve(startColor, midColor, endColor)
	local curve = C_CurveUtil.CreateColorCurve()
	curve:AddPoint(0, CreateColor(endColor[1], endColor[2], endColor[3]))
	curve:AddPoint(0.5, CreateColor(midColor[1], midColor[2], midColor[3]))
	curve:AddPoint(1, CreateColor(startColor[1], startColor[2], startColor[3]))
	return curve
end
```

- [ ] **Step 2: Add IconCurves.lua to the TOC file**

In `Framed.toc`, add immediately before `IconTicker.lua`:

```
Elements\Indicators\IconCurves.lua
Elements\Indicators\IconTicker.lua
Elements\Indicators\Icon.lua
```

- [ ] **Step 3: Commit**

```bash
git add Elements/Indicators/IconCurves.lua Framed.toc
git commit -m "Add IconCurves module for threshold and color progression curves"
```

---

### Task 3: Rewrite Icon.lua core — remove OnUpdate, add Cooldown + SetTimerDuration

This is the main migration. Replace the OnUpdate handler and related methods with C-level APIs.

**Files:**
- Modify: `Elements/Indicators/Icon.lua`

- [ ] **Step 1: Remove the OnUpdate handler and constants**

Delete lines 12-71 (the `DURATION_UPDATE_INTERVAL` constant and `IconOnUpdate` function). These are:

```lua
-- ============================================================
-- Combined OnUpdate handler for depletion fill + duration text
-- ============================================================

local DURATION_UPDATE_INTERVAL = 0.1

local function IconOnUpdate(frame, elapsed)
	...
end
```

Replace with a comment:

```lua
-- ============================================================
-- Duration/depletion driven by C-level APIs (SetTimerDuration,
-- SetCooldownFromDurationObject). Color progression + threshold
-- handled by shared IconTicker module.
-- ============================================================
```

- [ ] **Step 2: Rewrite SetSpell to accept unit + auraInstanceID and use C-level APIs**

Replace the current `SetSpell` method (lines 79-177) with:

```lua
--- Set the displayed spell/aura data on this icon.
--- @param unit string|nil Unit token (required for C-level duration APIs)
--- @param auraInstanceID number|nil Aura instance ID (required for C-level duration APIs)
--- @param spellID number
--- @param iconTexture number|string Texture ID or path
--- @param duration number Duration in seconds (may be a secret value)
--- @param expirationTime number Expiration GetTime() value (may be a secret value)
--- @param stacks number Stack count
--- @param dispelType string|nil Dispel/debuff type ('Magic', 'Curse', etc.)
function IconMethods:SetSpell(unit, auraInstanceID, spellID, iconTexture, duration, expirationTime, stacks, dispelType)
	-- Texture
	if(self._displayType == C.IconDisplay.COLORED_SQUARE) then
		local colorKey = (dispelType and dispelType ~= '') and dispelType or 'none'
		local color = DEBUFF_TYPE_COLORS[colorKey] or DEBUFF_TYPE_COLORS['none']
		self.texture:SetColorTexture(color[1], color[2], color[3])
	else
		-- SpellIcon (default)
		if(iconTexture) then
			self.texture:SetTexture(iconTexture)
		elseif(spellID) then
			local tex
			if(C_Spell and C_Spell.GetSpellInfo) then
				local info = C_Spell.GetSpellInfo(spellID)
				if(info) then tex = info.iconID end
			elseif(GetSpellInfo) then
				local _, _, ic = GetSpellInfo(spellID)
				tex = ic
			end
			self.texture:SetTexture(tex)
		end
	end

	-- Stacks
	if(self._config.showStacks) then
		self:SetStacks(stacks)
	end

	-- Per-spell color (ColoredSquare mode)
	if(self._displayType == C.IconDisplay.COLORED_SQUARE and self._spellColors) then
		local sc = self._spellColors[spellID]
		if(sc) then
			self.texture:SetColorTexture(sc[1], sc[2], sc[3], 1)
		end
	end

	-- C-level depletion + duration via DurationObject
	local durationObj
	if(unit and auraInstanceID) then
		durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
	end

	if(not durationObj and self._manualDurObj) then
		-- Preview/manual path: use pre-set DurationObject
		durationObj = self._manualDurObj
	end

	self._durationObj = durationObj

	-- Depletion bar (C-level SetTimerDuration)
	if(self._depletionBar) then
		if(durationObj and not durationObj:IsZero()) then
			self._depletionBar:SetMinMaxValues(0, 1)
			self._depletionBar:SetTimerDuration(durationObj, nil, Enum.StatusBarTimerDirection.RemainingTime)
			self._depletionBar:Show()
		else
			self._depletionBar:SetValue(0)
			self._depletionBar:Hide()
		end
	end

	-- Duration text (Blizzard cooldown countdown)
	if(self._cooldown) then
		if(durationObj and not durationObj:IsZero()) then
			self._cooldown:SetCooldownFromDurationObject(durationObj)

			-- Reparent and style Blizzard's countdown text once (lazy init),
			-- then re-anchor after every cooldown set (Blizzard re-centers it).
			local cdText = self._cooldown.GetCountdownFontString and self._cooldown:GetCountdownFontString()
			if(cdText) then
				if(not self._countdownReparented) then
					cdText:SetParent(self._textOverlay or self._frame)
					local df = self._durationFont
					if(df) then
						local fontFace = F.Media.GetActiveFont()
						cdText:SetFont(fontFace, df.size, df.outline)
						if(df.shadow == false) then
							cdText:SetShadowOffset(0, 0)
						else
							cdText:SetShadowOffset(1, -1)
						end
					end
					self._countdownReparented = true
				end
				-- Re-anchor (Blizzard resets to CENTER on each cooldown set)
				cdText:ClearAllPoints()
				local df = self._durationFont
				if(df) then
					cdText:SetPoint(df.anchor or 'BOTTOM', self._frame, df.anchor or 'BOTTOM', df.offsetX or 0, df.offsetY or 0)
				end
				self._cdText = cdText
			end

			-- Register with shared ticker for color/threshold if needed
			if(self._colorCurve or self._thresholdCurve) then
				F.Indicators.IconTicker_Register(self)
			end
		else
			self._cooldown:Clear()
			F.Indicators.IconTicker_Unregister(self)
		end
	end

	-- Glow (auto-start when glowType is configured and not 'None')
	if(self._glowType and self._glowType ~= 'None') then
		self:StartGlow(self._glowColor, self._glowType, self._glowConfig)
	end

	self._frame:Show()
end
```

- [ ] **Step 3: Rewrite SetDepletion for manual/preview use**

Replace the current `SetDepletion` method (lines 198-227) with a method that sets up a manual DurationObject for non-aura contexts (preview):

```lua
--- Set depletion via manual DurationObject (for preview / non-aura contexts).
--- @param duration number Total duration in seconds
--- @param expirationTime number Absolute expiration time from GetTime()
function IconMethods:SetDepletion(duration, expirationTime)
	if(not duration or duration <= 0) then
		self._manualDurObj = nil
		return
	end
	if(not self._manualDurObj) then
		self._manualDurObj = CreateLuaDurationObject()
	end
	local startTime = expirationTime - duration
	self._manualDurObj:SetTimeFromStart(startTime, duration)
end
```

- [ ] **Step 4: Rewrite Clear to use C-level cleanup**

Replace the current `Clear` method (lines 229-248) with:

```lua
--- Clear and hide this icon, stopping all C-level animations.
function IconMethods:Clear()
	self.texture:SetTexture(nil)
	if(self.stacks) then
		self.stacks:SetText('')
		self.stacks:Hide()
	end
	if(self._depletionBar) then
		self._depletionBar:SetValue(0)
		self._depletionBar:Hide()
	end
	if(self._cooldown) then
		self._cooldown:Clear()
	end
	self:StopGlow()
	self._durationObj = nil
	F.Indicators.IconTicker_Unregister(self)
	self._frame:Hide()
end
```

- [ ] **Step 5: Rewrite the Factory to create Cooldown frame instead of duration FontString**

In the Factory function `F.Indicators.Icon.Create` (starts at line 312), make these changes:

**5a.** Remove the `showCooldown` config extraction (line 315). Depletion is always on. Change:

```lua
local showCooldown = config.showCooldown ~= false  -- default true
```

to remove it entirely, and replace all references to `showCooldown` in the factory with `true` (or just remove the conditionals).

**5b.** The depletion bar block (lines 352-408) — remove the `if(showCooldown) then` wrapper. The bar is always created.

**5c.** Replace the duration text block (lines 428-447) with a Cooldown frame:

Replace:
```lua
-- 5. Duration text (configurable anchor, font, outline, shadow)
local durationText
local durationColorCurve
if(showDuration) then
	...
end
```

With:
```lua
-- 5. Cooldown frame for Blizzard countdown text (no swipe)
local cooldown
local durationColorCurve
local thresholdCurve
if(showDuration) then
	cooldown = CreateFrame('Cooldown', nil, frame, 'CooldownFrameTemplate')
	cooldown:SetAllPoints(frame)
	cooldown:SetDrawSwipe(false)
	cooldown:SetDrawEdge(false)
	cooldown:SetDrawBling(false)
	cooldown:SetHideCountdownNumbers(false)
	cooldown:SetFrameLevel((depletionBar and depletionBar:GetFrameLevel() or frame:GetFrameLevel()) + 2)

	-- Color progression curve
	local df = config.durationFont or {}
	if(df.colorProgression) then
		local startColor = df.progressionStart or { 0, 1, 0 }
		local midColor   = df.progressionMid   or { 1, 1, 0 }
		local endColor   = df.progressionEnd    or { 1, 0, 0 }
		durationColorCurve = F.Indicators.CreateDurationColorCurve(startColor, midColor, endColor)
	end

	-- Threshold curve
	thresholdCurve = F.Indicators.GetThresholdCurve(durationMode)
end
```

**5d.** Update the icon object table (lines 449-477). Replace:

```lua
local icon = {
	_frame        = frame,
	_config       = {
		showCooldown = showCooldown,
		showStacks   = showStacks,
	},
	_displayType  = displayType,
	_durationMode    = durationMode,
	_durationColorCurve = durationColorCurve,
	_spellColors     = config.spellColors,
	_totalDuration   = 0,
	_durationActive  = false,
	_durationElapsed = 0,
	_expirationTime  = 0,

	_depletionBar        = depletionBar,
	_depletionDuration   = 0,
	_depletionExpiration = 0,
	_depletionActive     = false,

	_glowType   = config.glowType,
	_glowColor  = config.glowColor,
	_glowConfig = config.glowConfig,

	texture  = texture,
	stacks   = stacksText,
	duration = durationText,
}
```

With:

```lua
local icon = {
	_frame        = frame,
	_config       = {
		showStacks = showStacks,
	},
	_displayType     = displayType,
	_durationMode    = durationMode,
	_durationFont    = config.durationFont,
	_spellColors     = config.spellColors,

	_depletionBar    = depletionBar,
	_cooldown        = cooldown,
	_textOverlay     = textOverlay,
	_colorCurve      = durationColorCurve,
	_thresholdCurve  = thresholdCurve,
	_durationObj     = nil,
	_cdText          = nil,
	_countdownReparented = false,

	_glowType   = config.glowType,
	_glowColor  = config.glowColor,
	_glowConfig = config.glowConfig,

	texture  = texture,
	stacks   = stacksText,
}
```

**5e.** Remove the `frame._iconRef = icon` line (line 485) — no longer needed since there's no OnUpdate referencing back to the icon.

- [ ] **Step 6: Commit**

```bash
git add Elements/Indicators/Icon.lua
git commit -m "Migrate Icon.lua from OnUpdate to C-level SetTimerDuration + cooldown"
```

---

### Task 4: Update Icons.lua to pass unit + auraInstanceID

Icons.lua pools Icon objects and dispatches aura data to them. The `SetIcons` method needs to forward `unit` and `auraInstanceID` from each aura entry.

**Files:**
- Modify: `Elements/Indicators/Icons.lua`

- [ ] **Step 1: Update SetIcons to pass unit + auraInstanceID**

In `Icons.lua`, replace the `SetSpell` call at lines 73-80:

```lua
		icon:SetSpell(
			aura.spellId,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.stacks,
			aura.dispelType
		)
```

With:

```lua
		icon:SetSpell(
			aura.unit,
			aura.auraInstanceID,
			aura.spellId,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.stacks,
			aura.dispelType
		)
```

- [ ] **Step 2: Remove showCooldown from Icons config**

In `Icons.lua` line 187, remove:

```lua
		showCooldown  = config.showCooldown  ~= false,
```

And in the lazy icon creation block (lines 27-41), remove the `showCooldown` key from the config table passed to `F.Indicators.Icon.Create`.

- [ ] **Step 3: Commit**

```bash
git add Elements/Indicators/Icons.lua
git commit -m "Update Icons.lua to pass unit + auraInstanceID to child icons"
```

---

### Task 5: Update Buffs.lua to pass unit + auraInstanceID to Icon/Icons

The Buffs element is the only element that uses Icon/Icons renderers. It already has `unit` and `auraInstanceID` in its aura entries — we just need to update the `SetSpell` call site.

**Files:**
- Modify: `Elements/Auras/Buffs.lua`

- [ ] **Step 1: Update the ICON renderer SetSpell call**

In `Buffs.lua`, find the SetSpell call at lines 214-221:

```lua
			renderer:SetSpell(
				aura.spellId,
				aura.icon,
				aura.duration,
				aura.expirationTime,
				aura.stacks,
				aura.dispelType
			)
```

Replace with:

```lua
			renderer:SetSpell(
				aura.unit,
				aura.auraInstanceID,
				aura.spellId,
				aura.icon,
				aura.duration,
				aura.expirationTime,
				aura.stacks,
				aura.dispelType
			)
```

The ICONS renderer path (line 204 `renderer:SetIcons(list)`) needs no change — the aura entries in `list` already contain `unit` and `auraInstanceID` fields, and Task 4 updated `Icons.lua` to forward them.

- [ ] **Step 2: Commit**

```bash
git add Elements/Auras/Buffs.lua
git commit -m "Pass unit + auraInstanceID to Icon renderers in Buffs element"
```

---

### Task 6: Update AuraDefaults.lua — remove showCooldown

**Files:**
- Modify: `Presets/AuraDefaults.lua`

- [ ] **Step 1: Remove showCooldown from defaultBuffIndicator**

In `Presets/AuraDefaults.lua`, line 40, remove:

```lua
		showCooldown  = true,
```

The depletion bar is now always created. The `showCooldown` key is no longer read by Icon.lua.

- [ ] **Step 2: Commit**

```bash
git add Presets/AuraDefaults.lua
git commit -m "Remove showCooldown default (depletion always on for Icon indicators)"
```

---

### Task 7: Update preview system for C-level APIs

The preview system creates fake icons without real aura data. It needs to use `CreateLuaDurationObject` to drive the depletion bar and cooldown countdown through the same C-level path.

**Files:**
- Modify: `Preview/PreviewIndicators.lua`

- [ ] **Step 1: Update PI.CreateIcon to use C-level depletion and cooldown**

In `Preview/PreviewIndicators.lua`, replace the depletion bar block (lines 115-150):

```lua
	-- Linear depletion bar (if showCooldown)
	if(indConfig and indConfig.showCooldown ~= false) then
		local fillDir = indConfig.fillDirection or 'topToBottom'
		local depBar = CreateFrame('StatusBar', nil, f)
		...
		if(animated) then
			startBarDepletionLoop(depBar)
		else
			depBar:SetValue(1 - FAKE_DEPLETION_PCT)
		end
	end
```

With:

```lua
	-- Depletion bar overlay (C-level SetTimerDuration)
	local fillDir = (indConfig and indConfig.fillDirection) or 'topToBottom'
	local depBar = CreateFrame('StatusBar', nil, f)
	depBar:SetAllPoints(f)
	depBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
	depBar:SetStatusBarColor(0, 0, 0, 0.6)
	depBar:SetMinMaxValues(0, 1)
	if(fillDir == 'leftToRight' or fillDir == 'rightToLeft') then
		depBar:SetOrientation('HORIZONTAL')
		if(fillDir == 'rightToLeft') then depBar:SetReverseFill(true) end
	else
		depBar:SetOrientation('VERTICAL')
		if(fillDir == 'topToBottom') then depBar:SetReverseFill(true) end
	end
	depBar:SetFrameLevel(f:GetFrameLevel() + 1)

	-- Leading edge line
	local edge = depBar:CreateTexture(nil, 'OVERLAY')
	edge:SetColorTexture(1, 1, 1, 0.75)
	if(fillDir == 'topToBottom' or fillDir == 'bottomToTop') then
		edge:SetHeight(0.75)
		edge:SetPoint('TOPLEFT',  depBar:GetStatusBarTexture(), 'BOTTOMLEFT',  0, 0)
		edge:SetPoint('TOPRIGHT', depBar:GetStatusBarTexture(), 'BOTTOMRIGHT', 0, 0)
	else
		edge:SetWidth(0.75)
		edge:SetPoint('TOPLEFT',    depBar:GetStatusBarTexture(), 'TOPRIGHT',    0, 0)
		edge:SetPoint('BOTTOMLEFT', depBar:GetStatusBarTexture(), 'BOTTOMRIGHT', 0, 0)
	end

	if(animated) then
		-- Animated preview: loop with C-level DurationObject
		local function startCLevelDepletionLoop()
			local durObj = CreateLuaDurationObject()
			durObj:SetTimeFromStart(GetTime(), ANIM_CYCLE)
			depBar:SetTimerDuration(durObj, nil, Enum.StatusBarTimerDirection.RemainingTime)
			C_Timer.After(ANIM_CYCLE, function()
				if(depBar:IsShown()) then startCLevelDepletionLoop() end
			end)
		end
		startCLevelDepletionLoop()
	else
		depBar:SetValue(1 - FAKE_DEPLETION_PCT)
	end
```

- [ ] **Step 2: Update the duration text section to use a Cooldown frame**

Replace the duration text block (lines 162-173):

```lua
	-- Duration text
	if(indConfig and indConfig.durationMode and indConfig.durationMode ~= 'Never') then
		local df = indConfig.durationFont or {}
		local durText = f:CreateFontString(nil, 'OVERLAY')
		durText:SetFont(F.Media.GetActiveFont(), df.size or 9, df.outline or 'OUTLINE')
		durText:SetPoint(df.anchor or 'BOTTOM', f, df.anchor or 'BOTTOM', df.offsetX or 0, df.offsetY or 0)
		durText:SetText('18')
		if(df.shadow ~= false) then durText:SetShadowOffset(1, -1) end
		if(df.colorProgression) then
			durText:SetTextColor(0.6, 1.0, 0.0, 1)
		end
	end
```

With:

```lua
	-- Duration countdown (Blizzard cooldown frame, no swipe)
	if(indConfig and indConfig.durationMode and indConfig.durationMode ~= 'Never') then
		local cd = CreateFrame('Cooldown', nil, f, 'CooldownFrameTemplate')
		cd:SetAllPoints(f)
		cd:SetDrawSwipe(false)
		cd:SetDrawEdge(false)
		cd:SetDrawBling(false)
		cd:SetHideCountdownNumbers(false)
		cd:SetFrameLevel(depBar:GetFrameLevel() + 1)

		if(animated) then
			-- Loop the cooldown countdown to match the depletion bar
			local function startCooldownCountdownLoop()
				local durObj = CreateLuaDurationObject()
				durObj:SetTimeFromStart(GetTime(), ANIM_CYCLE)
				cd:SetCooldownFromDurationObject(durObj)
				C_Timer.After(ANIM_CYCLE, function()
					if(cd:IsShown()) then startCooldownCountdownLoop() end
				end)
			end
			startCooldownCountdownLoop()
		else
			-- Static preview: show a cooldown at a fixed point
			local durObj = CreateLuaDurationObject()
			durObj:SetTimeFromStart(GetTime() - (ANIM_CYCLE * FAKE_DEPLETION_PCT), ANIM_CYCLE)
			cd:SetCooldownFromDurationObject(durObj)
		end

		-- Style the countdown font string (lazy, same as live Icon)
		C_Timer.After(0, function()
			local cdText = cd.GetCountdownFontString and cd:GetCountdownFontString()
			if(cdText) then
				local df = indConfig.durationFont or {}
				cdText:SetParent(f)
				cdText:SetFont(F.Media.GetActiveFont(), df.size or 9, df.outline or 'OUTLINE')
				if(df.shadow == false) then
					cdText:SetShadowOffset(0, 0)
				else
					cdText:SetShadowOffset(1, -1)
				end
				cdText:ClearAllPoints()
				cdText:SetPoint(df.anchor or 'BOTTOM', f, df.anchor or 'BOTTOM', df.offsetX or 0, df.offsetY or 0)
			end
		end)
	end
```

- [ ] **Step 3: Remove the old startBarDepletionLoop function if no longer used**

Check if `startBarDepletionLoop` (lines 63-71) is still used by any other preview builder. If it's only used by `PI.CreateIcon`, remove it. If other preview builders (Bar, BorderIcon) also use it, keep it.

Search for `startBarDepletionLoop` references. It is only called within `PI.CreateIcon` (line 146), so delete lines 62-71:

```lua
-- Looping StatusBar depletion: value animates 0 → 1 over ANIM_CYCLE, then restarts
local function startBarDepletionLoop(bar)
	bar:SetValue(0)
	Widgets.StartAnimation(bar, 'deplete', 0, 1, ANIM_CYCLE,
		function(f, v) f:SetValue(v) end,
		function(f)
			if(f:IsShown()) then startBarDepletionLoop(f) end
		end
	)
end
```

- [ ] **Step 4: Commit**

```bash
git add Preview/PreviewIndicators.lua
git commit -m "Update icon preview to use C-level depletion and cooldown countdown"
```

---

### Task 8: Update Settings UI — remove showCooldown references

The Settings builders may reference `showCooldown`. Remove those references since depletion is always on.

**Files:**
- Modify: `Settings/Builders/IndicatorPanels.lua` (if references exist)
- Modify: `Settings/Builders/IndicatorCRUD.lua`

- [ ] **Step 1: Remove showCooldown from IndicatorCRUD.lua**

In `Settings/Builders/IndicatorCRUD.lua`, find the default ICON data block (around lines 193-205) and remove `showCooldown = true`. Do the same for the ICONS data block (around lines 207-217).

- [ ] **Step 2: Check IndicatorPanels.lua for showCooldown references**

Search `IndicatorPanels.lua` for `showCooldown`. If any UI controls reference it (checkbox, etc.), remove them. The depletion bar is always on and needs no toggle.

- [ ] **Step 3: Commit**

```bash
git add Settings/Builders/IndicatorCRUD.lua Settings/Builders/IndicatorPanels.lua
git commit -m "Remove showCooldown from settings UI (depletion always on)"
```

---

### Task 9: Verify TOC load order and test in-game

Ensure all new files load in the correct order and the migration works end-to-end.

**Files:**
- Modify: `Framed.toc` (verify final state)

- [ ] **Step 1: Verify TOC load order**

The final load order for indicator files in `Framed.toc` must be:

```
Elements\Indicators\Shared.lua
Elements\Indicators\IconCurves.lua
Elements\Indicators\IconTicker.lua
Elements\Indicators\Icon.lua
Elements\Indicators\Icons.lua
```

`IconCurves.lua` and `IconTicker.lua` must load before `Icon.lua` since Icon.lua references `F.Indicators.GetThresholdCurve`, `F.Indicators.CreateDurationColorCurve`, `F.Indicators.IconTicker_Register`, and `F.Indicators.IconTicker_Unregister`.

- [ ] **Step 2: Sync to WoW addon folder and /reload test**

Copy the worktree to the WoW addon folder and test:

1. `/reload` — verify no Lua errors on load
2. Open settings → check icon previews render with depletion + countdown
3. Enter combat with buffs active → verify depletion fills and countdown text shows
4. Check that color progression works (if configured)
5. Test threshold modes in combat — this is the combat testing gate for `EvaluateRemainingPercent` with secret DurationObjects

- [ ] **Step 3: If threshold curves fail in combat**

If `EvaluateRemainingPercent` returns secret results that can't be compared in Lua:

1. Remove `IconCurves.lua`'s `GetThresholdCurve` function
2. Remove threshold curve creation from Icon.lua factory
3. Remove threshold check from `IconTicker.lua`
4. Simplify `durationMode` to a boolean enable/disable (show/hide countdown numbers via `SetHideCountdownNumbers`)
5. Update settings UI: replace `durationMode` dropdown with a checkbox

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "Verify TOC load order and finalize Icon C-level migration"
```
