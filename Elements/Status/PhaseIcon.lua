local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.PhaseIcon = {}

-- ============================================================
-- PhaseIcon Element Setup
-- ============================================================

--- Configure oUF's built-in PhaseIndicator element on a unit frame.
--- oUF shows the icon when the unit is in a different phase from the player.
--- Includes tooltip support for the phase reason.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.PhaseIcon.Setup(self, config)

	-- --------------------------------------------------------
	-- Config defaults
	-- --------------------------------------------------------

	config = config or {}
	config.size  = config.size  or 16
	config.point = config.point or { 'CENTER', self, 'CENTER', 0, 0 }

	-- --------------------------------------------------------
	-- Container frame (required for tooltip support)
	-- --------------------------------------------------------

	local frame = CreateFrame('Frame', nil, self)
	Widgets.SetSize(frame, config.size, config.size)
	frame:EnableMouse(true)

	local p = config.point
	Widgets.SetPoint(frame, p[1], p[2], p[3], p[4], p[5])
	frame:SetFrameLevel(self:GetFrameLevel() + 6)

	-- --------------------------------------------------------
	-- Icon texture inside the container
	-- --------------------------------------------------------

	local icon = frame:CreateTexture(nil, 'OVERLAY')
	icon:SetAllPoints()
	frame.Icon = icon

	-- --------------------------------------------------------
	-- Assign to oUF — activates the PhaseIndicator element
	-- --------------------------------------------------------

	self.PhaseIndicator = frame
end
