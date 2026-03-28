local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.ResurrectIcon = {}

-- ============================================================
-- ResurrectIcon Element Setup
-- ============================================================

--- Configure oUF's built-in ResurrectIndicator element on a unit frame.
--- oUF shows the icon when the unit has an incoming resurrect.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.ResurrectIcon.Setup(self, config)

	-- --------------------------------------------------------
	-- Config defaults
	-- --------------------------------------------------------

	config = config or {}
	config.size  = config.size  or 16
	config.point = config.point or { 'CENTER', self, 'CENTER', 0, 0 }

	-- --------------------------------------------------------
	-- Icon texture
	-- --------------------------------------------------------

	local icon = (self._iconOverlay or self):CreateTexture(nil, 'OVERLAY')
	Widgets.SetSize(icon, config.size, config.size)

	local p = config.point
	Widgets.SetPoint(icon, p[1], p[2], p[3], p[4], p[5])

	-- --------------------------------------------------------
	-- Assign to oUF — activates the ResurrectIndicator element
	-- --------------------------------------------------------

	self.ResurrectIndicator = icon
end
