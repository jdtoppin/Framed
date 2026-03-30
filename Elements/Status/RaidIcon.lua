local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.RaidIcon = {}

-- ============================================================
-- RaidIcon Element Setup
-- ============================================================

--- Configure oUF's built-in RaidTargetIndicator element on a unit frame.
--- oUF automatically shows the appropriate raid marker (skull, X, star, etc.).
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.RaidIcon.Setup(self, config)

	-- --------------------------------------------------------
	-- Icon texture
	-- --------------------------------------------------------

	local icon = (self._iconOverlay or self):CreateTexture(nil, 'OVERLAY')
	Widgets.SetSize(icon, config.size, config.size)
	icon:Hide()

	local p = config.point
	Widgets.SetPoint(icon, p[1], p[2], p[3], p[4], p[5])

	-- --------------------------------------------------------
	-- Assign to oUF — activates the RaidTargetIndicator element
	-- --------------------------------------------------------

	self.RaidTargetIndicator = icon
end
