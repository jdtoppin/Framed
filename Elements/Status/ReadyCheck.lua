local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.ReadyCheck = {}

-- ============================================================
-- ReadyCheck Element Setup
-- ============================================================

--- Configure oUF's built-in ReadyCheckIndicator element on a unit frame.
--- oUF handles the ready/not-ready/waiting textures and auto-fade after
--- the check completes.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.ReadyCheck.Setup(self, config)

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
	-- Assign to oUF — activates the ReadyCheckIndicator element
	-- --------------------------------------------------------

	self.ReadyCheckIndicator = icon
end
