local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Color = {}

-- ============================================================
-- Color methods
-- ============================================================

local ColorMethods = {}

--- Override the health bar color, saving the original first.
--- Subsequent calls while already overridden update the override color
--- without re-saving the already-modified color as 'original'.
--- @param r number
--- @param g number
--- @param b number
--- @param a? number
function ColorMethods:Override(r, g, b, a)
	a = a or 1

	if(not self._overridden) then
		-- Capture the current color before we change it
		local cr, cg, cb, ca = self._healthBar:GetStatusBarColor()
		self._originalColor = { cr, cg, cb, ca or 1 }
	end

	self._healthBar:SetStatusBarColor(r, g, b, a)
	self._overridden = true
end

--- Restore the original health bar color captured before the last Override.
--- If the health element has a ForceUpdate method the caller should trigger
--- that separately so oUF recalculates the color from current HP values.
function ColorMethods:Clear()
	if(not self._overridden) then return end

	if(self._originalColor) then
		self._healthBar:SetStatusBarColor(unpack(self._originalColor))
	end

	self._originalColor = nil
	self._overridden    = false
end

--- Return whether a color override is currently active.
--- @return boolean
function ColorMethods:IsOverridden()
	return self._overridden
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a Color indicator that manages health bar color overrides.
--- @param healthBar Frame An oUF Health StatusBar (or equivalent)
--- @return table color
function F.Indicators.Color.Create(healthBar)
	local color = {
		_healthBar     = healthBar,
		_overridden    = false,
		_originalColor = nil,
	}

	for k, v in next, ColorMethods do
		color[k] = v
	end

	return color
end
