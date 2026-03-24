local addonName, Framed = ...
local oUF = Framed.oUF
local C = Framed.Constants
local Widgets = Framed.Widgets

Framed.Elements = Framed.Elements or {}
Framed.Elements.RoleIcon = {}

-- ============================================================
-- RoleIcon Element Setup
-- ============================================================

--- Configure oUF's built-in GroupRoleIndicator element on a unit frame.
--- oUF automatically shows the appropriate tank/healer/DPS icon.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function Framed.Elements.RoleIcon.Setup(self, config)

    -- --------------------------------------------------------
    -- Config defaults
    -- --------------------------------------------------------

    config = config or {}
    config.size  = config.size  or 12
    config.point = config.point or { "TOPLEFT", self, "TOPLEFT", 2, -2 }

    -- --------------------------------------------------------
    -- Icon texture
    -- --------------------------------------------------------

    local icon = self:CreateTexture(nil, "OVERLAY")
    Widgets.SetSize(icon, config.size, config.size)

    local p = config.point
    Widgets.SetPoint(icon, p[1], p[2], p[3], p[4], p[5])

    -- --------------------------------------------------------
    -- Assign to oUF — activates the GroupRoleIndicator element
    -- --------------------------------------------------------

    self.GroupRoleIndicator = icon
end
