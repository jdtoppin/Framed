# Icon.lua C-Level Migration Design

**Date:** 2026-04-07
**Issue:** #63
**Scope:** Eliminate `IconOnUpdate` from `Elements/Indicators/Icon.lua` by migrating depletion bar animation and duration text to C-level WoW APIs. This migration is strictly for Icon/Icons indicators only. Do not touch Bar, BorderIcon, BorderGlow, Overlay, Color, or any other indicator type.

## Problem

Each Icon indicator runs a per-frame Lua `OnUpdate` handler (`IconOnUpdate`) that:

1. Animates a depletion StatusBar fill via `GetTime()` math + `SetValue()`
2. Formats and updates duration text via `FormatDuration()` + `SetText()` at 0.1s throttle
3. Evaluates a color curve for duration text color progression

In a 20-player raid with ~4 active icons per frame, this creates ~80 individual OnUpdate handlers firing at 60 FPS. Each tick allocates temporary strings (from `FormatDuration`), creating GC pressure and measurable memory growth.

## Solution

Replace both OnUpdate responsibilities with C-level APIs that handle animation/timing internally in compiled C++, eliminating all per-frame Lua cost per icon.

### Depletion Bar: `SetTimerDuration`

The existing depletion StatusBar uses Lua to interpolate `SetValue()` each frame. Replace with:

```lua
local durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
if(durationObj) then
    statusBar:SetTimerDuration(durationObj, nil, Enum.StatusBarTimerDirection.RemainingTime)
end
```

- `SetTimerDuration` drives the StatusBar value over time entirely in C
- Respects the StatusBar's existing `SetOrientation()` and `SetReverseFill()` — vertical depletion works unchanged
- Same pattern already proven in `Bar.lua`
- For preview/non-aura contexts, use `CreateLuaDurationObject()` + `SetTimeFromStart()`

### Duration Text: Blizzard Cooldown Countdown

The existing Lua ticker formats remaining time as text. Replace with a Cooldown frame whose built-in countdown handles text rendering:

```lua
local cooldown = CreateFrame('Cooldown', nil, frame, 'CooldownFrameTemplate')
cooldown:SetDrawSwipe(false)        -- No swipe overlay (depletion bar handles that)
cooldown:SetHideCountdownNumbers(false)
cooldown:SetCooldownFromDurationObject(durationObj)
```

The countdown FontString is reparented and styled with user config, same pattern as `BorderIcon.lua`:

```lua
local cdText = cooldown:GetCountdownFontString()
cdText:SetParent(iconFrame)
cdText:SetFont(fontFace, durationFont.size, durationFont.outline)
cdText:ClearAllPoints()
cdText:SetPoint(durationFont.anchor, iconFrame, durationFont.anchor, durationFont.xOffset, durationFont.yOffset)
```

### Color Progression & Duration Threshold: Shared Ticker

A single shared ticker frame (one for ALL active icons, 0.5s throttle) handles two optional features using `DurationObject:EvaluateRemainingPercent(curve)`:

**Color progression** (green -> yellow -> red):

```lua
local color = durationObj:EvaluateRemainingPercent(colorCurve)
cdText:SetTextColor(color:GetRGBA())
```

The color curve is created once per icon from the user's configured colors.

**Duration threshold visibility** (show below 50%, 25%, etc.):

```lua
local visibility = durationObj:EvaluateRemainingPercent(thresholdCurve)
-- Bracket curve: alpha=1 below threshold, alpha=0 above
```

Bracket curves are created once per threshold mode. The result controls countdown text visibility.

**Combat testing required:** `EvaluateRemainingPercent` with a non-secret curve on a secret DurationObject should return a non-secret result per API docs (`SecretWhenCurveSecret = true`). If this doesn't hold in practice, duration threshold support is removed (no dead code) and replaced with a simple enable/disable toggle.

### Shared Ticker Design

```lua
local activeTicker = CreateFrame('Frame')
local activeIcons = {}  -- set of icons with active color/threshold

activeTicker:SetScript('OnUpdate', function(self, elapsed)
    self._elapsed = (self._elapsed or 0) + elapsed
    if(self._elapsed < 0.5) then return end
    self._elapsed = 0
    for icon in next, activeIcons do
        -- Color progression
        if(icon._colorCurve and icon._durationObj) then
            local color = icon._durationObj:EvaluateRemainingPercent(icon._colorCurve)
            icon._cdText:SetTextColor(color:GetRGBA())
        end
        -- Threshold visibility
        if(icon._thresholdCurve and icon._durationObj) then
            local vis = icon._durationObj:EvaluateRemainingPercent(icon._thresholdCurve)
            -- Apply visibility based on curve result
        end
    end
end)
```

Cost: ~160-320 C function calls every 0.5 seconds for a full raid. No string allocations, no Lua math.

## Display Type Compatibility

Both **Spell Icon** and **Colored Square** display modes share the same underlying depletion StatusBar + Cooldown frame. The Cooldown frame has `SetDrawSwipe(false)` so there's no swipe overlay on either mode — the depletion bar fill is the only timer visual, countdown text is the only text.

No display-type-specific branching needed.

## Aura Element Changes

Aura elements (Buffs, Debuffs, etc.) must pass `unit` and `auraInstanceID` through to Icon so it can call `C_UnitAuras.GetAuraDuration()`. This follows the same pattern BorderIcon.lua already uses.

The Icon `SetSpell` signature gains `unit` and `auraInstanceID` parameters (optional, for backward compatibility with preview code that doesn't have real auras).

## Settings Changes

### Kept as-is
- Duration font: size, outline, shadow, anchor, x/y offset
- Color progression: checkbox + 3 color pickers (full duration, half, near expiry)
- Duration mode dropdown: 'Always', 'Never', '<75%', '<50%', '<25%', '<15s', '<5s'
- Fill direction: topToBottom, bottomToTop, leftToRight, rightToLeft

### Removed
- `showCooldown` config key — depletion is always on (was already always true in practice)

### Notes
- Duration mode may simplify to enable/disable toggle if threshold curves don't survive combat testing
- Color progression settings map to a `C_CurveUtil.CreateColorCurve()` instead of a Lua-evaluated curve

## Config Keys

No new config keys. Existing keys map to the new implementation:

| Key | Current use | New use |
|-----|------------|---------|
| `durationMode` | Lua `ShouldShowDuration()` | Bracket curve threshold |
| `durationFont` | Lua `SetText()` + `SetFont()` | Blizzard countdown FontString styling |
| `durationFont.colorProgression` | Lua curve + `SetTextColor()` per tick | C-level `EvaluateRemainingPercent` + `SetTextColor()` at 0.5s |
| `fillDirection` | StatusBar `SetOrientation`/`SetReverseFill` | Unchanged |
| `displayType` | SPELL_ICON vs COLORED_SQUARE | Unchanged |

## Preview System

Preview icons (PreviewIndicators.lua, PreviewAuras.lua) don't have real aura data, so they use manually created DurationObjects:

```lua
local durationObj = CreateLuaDurationObject()
durationObj:SetTimeFromStart(GetTime(), fakeDuration)
```

This feeds into the same `SetTimerDuration` and `SetCooldownFromDurationObject` paths. Preview animations are live and C-driven, same as real frames.

## What's Removed from Icon.lua

- `IconOnUpdate` function (lines 18-71)
- `DURATION_UPDATE_INTERVAL` constant (line 16)
- `_depletionActive`, `_durationActive`, `_durationElapsed` state fields
- `FormatDuration()` calls
- `ShouldShowDuration()` calls (replaced by curve-based threshold)
- All `SetScript('OnUpdate', ...)` calls in Icon methods
- `SetDepletion()` method body replaced with `SetTimerDuration` call

## What's Added

- Cooldown frame per icon (`SetDrawSwipe(false)`, countdown text only)
- Shared color/threshold ticker frame (one global, 0.5s throttle)
- `activeIcons` registration set for the shared ticker
- Bracket curves per threshold mode (created once, cached)
- DurationObject caching per icon (reused via `:Assign()`, not re-created)
- `unit` and `auraInstanceID` parameters on `SetSpell`

## Wirings

1. **Icon.lua** — core implementation (depletion, duration, ticker registration)
2. **Icons.lua** — pool passes config to child icons, children self-register with shared ticker
3. **Aura elements** (Buffs.lua, Debuffs.lua, Defensives.lua, Externals.lua, etc.) — pass `unit` + `auraInstanceID` through to Icon's `SetSpell`
4. **Settings UI** (IndicatorPanels.lua) — no structural changes
5. **LiveUpdate** (AuraConfig.lua) — config changes trigger structural rebuild as before
6. **Preview** (PreviewIndicators.lua, PreviewAuras.lua) — use `CreateLuaDurationObject` for fake durations
7. **AuraDefaults.lua** — remove `showCooldown` default (always on), keep all other defaults

## Fallback Strategy

No pre-12.0.1 fallback. Per CLAUDE.md: "Never split code into secret/non-secret paths." The C-level APIs (`SetTimerDuration`, `SetCooldownFromDurationObject`, `C_UnitAuras.GetAuraDuration`) are all 12.0.1+ and the addon targets current live only.
