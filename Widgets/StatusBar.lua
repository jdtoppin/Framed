local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Feature Detection
-- WoW 12.0.1 introduced Enum.StatusBarInterpolation for smooth bar animation.
-- Check at load time; no pcall.
-- ============================================================

local hasNativeInterpolation = Enum and Enum.StatusBarInterpolation ~= nil

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
	local wrapper = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(wrapper, width, height)
	Widgets.ApplyBackdrop(wrapper, C.Colors.panel, C.Colors.border)

	-- Inner status bar: inset 1px on all sides to sit inside the border
	local bar = CreateFrame('StatusBar', nil, wrapper)
	bar:SetPoint('TOPLEFT',     wrapper, 'TOPLEFT',      1, -1)
	bar:SetPoint('BOTTOMRIGHT', wrapper, 'BOTTOMRIGHT', -1,  1)

	-- Bar texture (uses user-configured texture or plain white)
	bar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
	bar:GetStatusBarTexture():SetHorizTile(false)
	bar:GetStatusBarTexture():SetVertTile(false)
	Widgets.TrackStatusBar(bar)

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

	-- Native interpolation is used by passing the enum as the second
	-- argument to SetValue() — there is no separate setup method.

	-- --------------------------------------------------------
	-- API: SetSmooth
	-- --------------------------------------------------------

	--- Enable or disable smooth interpolation.
	--- @param enabled boolean
	function bar:SetSmooth(enabled)
		self._smoothEnabled = enabled
	end

	-- --------------------------------------------------------
	-- API: SetValue / GetValue
	-- --------------------------------------------------------

	-- Keep a reference to the underlying StatusBar SetValue
	local rawSetValue = bar.SetValue

	--- Raw set, bypassing interpolation. Used internally.
	function bar:SetValue_Raw(val, interpolation)
		rawSetValue(self, val, interpolation)
	end

	--- Set bar value. Forwards the interpolation argument to the native SetValue.
	--- @param val number
	--- @param interpolation? number  Enum.StatusBarInterpolation value (passed by oUF)
	function bar:SetValue(val, interpolation)
		-- Always pass interpolation to C-level API, even for secret values.
		-- The native StatusBar:SetValue accepts secret values natively.
		if(not F.IsValueNonSecret(val)) then
			self:SetValue_Raw(val, interpolation)
			return
		end

		local min, max = self:GetMinMaxValues()
		if(F.IsValueNonSecret(min) and F.IsValueNonSecret(max)) then
			val = math.max(min, math.min(max, val))
		end
		self._targetValue  = val
		self._currentValue = val

		self:SetValue_Raw(val, interpolation)
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
		-- Clamp stored values to new range (only if values are non-secret)
		if(F.IsValueNonSecret(min) and F.IsValueNonSecret(max)) then
			self._targetValue  = math.max(min, math.min(max, self._targetValue  or min))
			self._currentValue = math.max(min, math.min(max, self._currentValue or min))
		end
	end

	-- --------------------------------------------------------
	-- Expose wrapper so callers can position the outer frame
	-- --------------------------------------------------------

	bar._wrapper = wrapper

	-- Apply base mixin (enabled state, tooltip support)
	Widgets.ApplyBaseMixin(bar)

	return bar
end
