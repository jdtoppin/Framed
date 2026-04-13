local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.RaidRoleIcon = {}

-- ============================================================
-- RaidRoleIcon Element Setup
-- ============================================================

--- Configure oUF's built-in RaidRoleIndicator element on a unit frame.
--- oUF shows main tank or main assist icons for raid-assigned units.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.RaidRoleIcon.Setup(self, config)

	-- --------------------------------------------------------
	-- Icon texture
	-- --------------------------------------------------------

	local icon = (self._iconOverlay or self):CreateTexture(nil, 'OVERLAY')
	Widgets.SetSize(icon, config.size, config.size)

	local p = config.point
	Widgets.SetPoint(icon, p[1], p[2], p[3], p[4], p[5])

	-- --------------------------------------------------------
	-- Assign to oUF — activates the RaidRoleIndicator element
	-- --------------------------------------------------------

	self.RaidRoleIndicator = icon
end
