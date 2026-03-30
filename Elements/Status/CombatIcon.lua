local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.CombatIcon = {}

-- ============================================================
-- CombatIcon Element Setup
-- ============================================================

--- Configure oUF's built-in CombatIndicator element on a unit frame.
--- oUF shows/hides the icon automatically based on unit combat state.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.CombatIcon.Setup(self, config)

	-- --------------------------------------------------------
	-- Icon texture
	-- --------------------------------------------------------

	local icon = (self._iconOverlay or self):CreateTexture(nil, 'OVERLAY')
	Widgets.SetSize(icon, config.size, config.size)

	local p = config.point
	Widgets.SetPoint(icon, p[1], p[2], p[3], p[4], p[5])

	-- --------------------------------------------------------
	-- Assign to oUF — activates the CombatIndicator element
	-- --------------------------------------------------------

	self.CombatIndicator = icon
end
