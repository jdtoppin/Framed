local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.PvPIcon = {}

-- ============================================================
-- PvPIcon Element Setup
-- ============================================================

--- Configure oUF's built-in PvPIndicator element on a unit frame.
--- oUF shows faction/FFA icons when the unit is PvP flagged.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.PvPIcon.Setup(self, config)

	-- --------------------------------------------------------
	-- Config defaults
	-- --------------------------------------------------------

	config = config or {}
	config.size  = config.size  or 16
	config.point = config.point or { 'BOTTOMLEFT', self, 'BOTTOMLEFT', 2, 2 }

	-- --------------------------------------------------------
	-- Icon texture
	-- --------------------------------------------------------

	local icon = (self._iconOverlay or self):CreateTexture(nil, 'OVERLAY')
	Widgets.SetSize(icon, config.size, config.size)

	local p = config.point
	Widgets.SetPoint(icon, p[1], p[2], p[3], p[4], p[5])

	-- --------------------------------------------------------
	-- Assign to oUF — activates the PvPIndicator element
	-- --------------------------------------------------------

	self.PvPIndicator = icon
end
