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
	-- Config defaults
	-- --------------------------------------------------------

	config = config or {}
	config.size    = config.size    or 12
	config.point   = config.point   or { 'CENTER', self, 'CENTER', 0, 0 }
	config.texture = config.texture or nil   -- nil = use atlas default

	-- --------------------------------------------------------
	-- Icon texture
	-- --------------------------------------------------------

	local icon = self:CreateTexture(nil, 'OVERLAY')
	Widgets.SetSize(icon, config.size, config.size)

	local p = config.point
	Widgets.SetPoint(icon, p[1], p[2], p[3], p[4], p[5])

	-- Apply texture: caller-supplied path takes priority; fall back to atlas.
	if(config.texture) then
		icon:SetTexture(config.texture)
	else
		icon:SetAtlas('UI-HUD-UnitFrame-Player-CombatIcon')
	end

	-- --------------------------------------------------------
	-- Assign to oUF — activates the CombatIndicator element
	-- --------------------------------------------------------

	self.CombatIndicator = icon
end
