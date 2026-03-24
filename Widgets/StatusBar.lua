local addonName, Framed = ...

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- Feature Detection
-- WoW 12.0.1 introduced SetInterpolateToTargetValue on StatusBarMixin.
-- Check at load time; no pcall.
-- ============================================================

local hasNativeInterpolation = StatusBarMixin and StatusBarMixin.SetInterpolateToTargetValue ~= nil

-- ============================================================
-- Smooth Interpolation Config
-- ============================================================

local LERP_SPEED = 5.0   -- units per second multiplier for OnUpdate fallback

-- ============================================================
-- StatusBar Widget
-- ============================================================

--- Create a styled status bar with smooth interpolation support.
--- @param parent Frame
--- @param width number
--- @param height number
--- @return Frame bar The status bar widget
function Widgets.CreateStatusBar(parent, width, height)

    -- Wrapper frame: provides backdrop (background + 1px border)
    -- StatusBar does not inherit BackdropTemplate, so we wrap it.
    local wrapper = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Widgets.SetSize(wrapper, width, height)
    Widgets.ApplyBackdrop(wrapper, C.Colors.panel, C.Colors.border)

    -- Inner status bar: inset 1px on all sides to sit inside the border
    local bar = CreateFrame("StatusBar", nil, wrapper)
    bar:SetPoint("TOPLEFT",     wrapper, "TOPLEFT",      1, -1)
    bar:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", -1,  1)

    -- Solid-color bar texture
    bar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8x8")
    bar:GetStatusBarTexture():SetHorizTile(false)
    bar:GetStatusBarTexture():SetVertTile(false)

    -- Default fill color: accent
    local accent = C.Colors.accent
    bar:SetStatusBarColor(accent[1], accent[2], accent[3], accent[4] or 1)

    -- Default range
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)

    -- --------------------------------------------------------
    -- Smooth Interpolation State
    -- --------------------------------------------------------

    bar._smoothEnabled = true
    bar._currentValue  = 0
    bar._targetValue   = 0

    -- --------------------------------------------------------
    -- Native interpolation (WoW 12.0.1+)
    -- --------------------------------------------------------

    if hasNativeInterpolation then
        bar:SetInterpolateToTargetValue(true)
    end

    -- --------------------------------------------------------
    -- API: SetSmooth
    -- --------------------------------------------------------

    --- Enable or disable smooth interpolation.
    --- @param enabled boolean
    function bar:SetSmooth(enabled)
        self._smoothEnabled = enabled
        if hasNativeInterpolation then
            self:SetInterpolateToTargetValue(enabled)
        end
        -- If disabling, snap to target immediately
        if not enabled then
            self._currentValue = self._targetValue
            self:SetValue_Raw(self._targetValue)
        end
    end

    -- --------------------------------------------------------
    -- API: SetValue / GetValue
    -- --------------------------------------------------------

    -- Keep a reference to the underlying StatusBar SetValue
    local rawSetValue = bar.SetValue

    --- Raw set, bypassing interpolation. Used internally.
    function bar:SetValue_Raw(val)
        rawSetValue(self, val)
    end

    --- Set bar value. Animates smoothly if smooth is enabled.
    --- @param val number
    function bar:SetValue(val)
        local min, max = self:GetMinMaxValues()
        val = math.max(min, math.min(max, val))
        self._targetValue = val

        if not self._smoothEnabled then
            self._currentValue = val
            self:SetValue_Raw(val)
            return
        end

        if hasNativeInterpolation then
            -- Native API: pass value; the engine handles animation
            self:SetValue_Raw(val)
        else
            -- OnUpdate-based fallback: _currentValue approaches _targetValue
            -- The OnUpdate script is registered once below
        end
    end

    --- Get the current logical target value (not the animated display value).
    --- @return number
    function bar:GetValue()
        return self._targetValue
    end

    -- --------------------------------------------------------
    -- API: SetBarColor
    -- --------------------------------------------------------

    --- Set the bar fill color.
    --- @param r number
    --- @param g number
    --- @param b number
    --- @param a? number
    function bar:SetBarColor(r, g, b, a)
        self:SetStatusBarColor(r, g, b, a or 1)
    end

    -- --------------------------------------------------------
    -- API: SetMinMaxValues (wrapped to clamp stored target)
    -- --------------------------------------------------------

    local rawSetMinMax = bar.SetMinMaxValues

    function bar:SetMinMaxValues(min, max)
        rawSetMinMax(self, min, max)
        -- Clamp stored values to new range
        self._targetValue  = math.max(min, math.min(max, self._targetValue  or min))
        self._currentValue = math.max(min, math.min(max, self._currentValue or min))
    end

    -- --------------------------------------------------------
    -- OnUpdate fallback interpolation
    -- Only active when native interpolation is unavailable
    -- --------------------------------------------------------

    if not hasNativeInterpolation then
        bar:HookScript("OnUpdate", function(self, elapsed)
            if not self._smoothEnabled then return end
            if self._currentValue == self._targetValue then return end

            local delta = self._targetValue - self._currentValue
            local step  = delta * math.min(elapsed * LERP_SPEED, 1)

            -- Snap when close enough to avoid endless micro-lerp
            if math.abs(delta) < 0.01 then
                self._currentValue = self._targetValue
            else
                self._currentValue = self._currentValue + step
            end

            rawSetValue(self, self._currentValue)
        end)
    end

    -- --------------------------------------------------------
    -- Expose wrapper so callers can position the outer frame
    -- --------------------------------------------------------

    bar._wrapper = wrapper

    -- Apply base mixin (enabled state, tooltip support)
    Widgets.ApplyBaseMixin(bar)

    return bar
end
