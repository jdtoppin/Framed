local addonName, Framed = ...
local oUF = Framed.oUF
local C = Framed.Constants
local Widgets = Framed.Widgets

Framed.Elements = Framed.Elements or {}
Framed.Elements.LeaderIcon = {}

-- ============================================================
-- LeaderIcon Element Setup
-- ============================================================

--- Configure oUF's built-in LeaderIndicator and AssistantIndicator elements.
--- oUF shows the leader (crown) or assistant (star) icon — never both at once.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function Framed.Elements.LeaderIcon.Setup(self, config)

    -- --------------------------------------------------------
    -- Config defaults
    -- --------------------------------------------------------

    config = config or {}
    config.size  = config.size  or 12
    config.point = config.point or { "TOPLEFT", self, "TOPLEFT", 2, -2 }

    -- --------------------------------------------------------
    -- Leader icon texture (crown)
    -- --------------------------------------------------------

    local leaderIcon = self:CreateTexture(nil, "OVERLAY")
    Widgets.SetSize(leaderIcon, config.size, config.size)

    local p = config.point
    Widgets.SetPoint(leaderIcon, p[1], p[2], p[3], p[4], p[5])

    -- --------------------------------------------------------
    -- Assistant icon texture (star)
    -- Same position — oUF ensures only one is shown at a time.
    -- --------------------------------------------------------

    local assistIcon = self:CreateTexture(nil, "OVERLAY")
    Widgets.SetSize(assistIcon, config.size, config.size)
    Widgets.SetPoint(assistIcon, p[1], p[2], p[3], p[4], p[5])

    -- --------------------------------------------------------
    -- Assign to oUF — activates both indicator elements
    -- --------------------------------------------------------

    self.LeaderIndicator    = leaderIcon
    self.AssistantIndicator = assistIcon
end
