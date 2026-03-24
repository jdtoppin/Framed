local addonName, Framed = ...
local oUF = Framed.oUF
local C = Framed.Constants
local Widgets = Framed.Widgets

Framed.Elements = Framed.Elements or {}
Framed.Elements.Range = {}

-- ============================================================
-- Range Element Setup
-- ============================================================
-- Uses oUF's built-in Range element. oUF handles OnUpdate polling
-- and applies insideAlpha / outsideAlpha automatically based on
-- whether the unit is within range.

--- Configure oUF's Range element on a unit frame.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config; defaults applied if nil
function Framed.Elements.Range.Setup(self, config)

    -- --------------------------------------------------------
    -- Config defaults
    -- --------------------------------------------------------

    config = config or {}
    config.outsideAlpha = config.outsideAlpha or 0.4

    -- --------------------------------------------------------
    -- Assign to oUF — activates the Range element
    -- oUF polls range and sets frame alpha accordingly.
    -- --------------------------------------------------------

    self.Range = {
        insideAlpha  = 1,
        outsideAlpha = config.outsideAlpha,
    }
end
