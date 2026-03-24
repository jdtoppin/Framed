local addonName, Framed = ...
local C = Framed.Constants
local Widgets = Framed.Widgets

Framed.Indicators = Framed.Indicators or {}
Framed.Indicators.Border = {}

-- ============================================================
-- Border methods
-- ============================================================
-- Uses four individual edge textures at OVERLAY layer so this
-- border is independent of any backdrop the parent may have.

local BorderMethods = {}

--- Set border color on all four edges and show them.
--- @param r number
--- @param g number
--- @param b number
--- @param a? number
function BorderMethods:SetColor(r, g, b, a)
    a = a or 1
    self._top:SetColorTexture(r, g, b, a)
    self._bottom:SetColorTexture(r, g, b, a)
    self._left:SetColorTexture(r, g, b, a)
    self._right:SetColorTexture(r, g, b, a)
    self._top:Show()
    self._bottom:Show()
    self._left:Show()
    self._right:Show()
end

--- Set border thickness in pixels and re-anchor edges.
--- @param px number Thickness (default 2)
function BorderMethods:SetThickness(px)
    px = px or 2
    self._thickness = px

    local top    = self._top
    local bottom = self._bottom
    local left   = self._left
    local right  = self._right
    local parent = self._parent

    -- Top edge: full width, `px` pixels tall, anchored to top
    top:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0,   0)
    top:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  0,   0)
    top:SetHeight(px)

    -- Bottom edge: full width, `px` pixels tall, anchored to bottom
    bottom:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, 0)
    bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(px)

    -- Left edge: inset between top/bottom edges, `px` pixels wide
    left:SetPoint("TOPLEFT",    parent, "TOPLEFT",    0, -px)
    left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0,  px)
    left:SetWidth(px)

    -- Right edge: inset between top/bottom edges, `px` pixels wide
    right:SetPoint("TOPRIGHT",    parent, "TOPRIGHT",    0, -px)
    right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0,  px)
    right:SetWidth(px)
end

--- Hide all edges and reset color state.
function BorderMethods:Clear()
    self._top:Hide()
    self._bottom:Hide()
    self._left:Hide()
    self._right:Hide()
end

--- Show all edges (restores visibility without changing color).
function BorderMethods:Show()
    self._top:Show()
    self._bottom:Show()
    self._left:Show()
    self._right:Show()
end

--- Hide all edges (alias for Clear without the reset semantics).
function BorderMethods:Hide()
    self:Clear()
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a Border indicator: four OVERLAY edge textures on `parent`.
--- All edges are hidden by default; call SetColor to show them.
--- @param parent Frame The frame to border
--- @return table border
function Framed.Indicators.Border.Create(parent)
    local level = parent:GetFrameLevel() + 3

    local function MakeEdge()
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)  -- default white; overridden by SetColor
        t:Hide()
        return t
    end

    local top    = MakeEdge()
    local bottom = MakeEdge()
    local left   = MakeEdge()
    local right  = MakeEdge()

    local border = {
        _parent    = parent,
        _top       = top,
        _bottom    = bottom,
        _left      = left,
        _right     = right,
        _thickness = 2,
    }

    for k, v in pairs(BorderMethods) do
        border[k] = v
    end

    -- Apply default 2px thickness anchoring
    border:SetThickness(2)

    return border
end
