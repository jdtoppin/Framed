local addonName, Framed = ...
local oUF = Framed.oUF
local C = Framed.Constants
local Widgets = Framed.Widgets

Framed.Elements = Framed.Elements or {}
Framed.Elements.MouseoverHighlight = {}

-- ============================================================
-- Update
-- UPDATE_MOUSEOVER_UNIT is a fallback safety check.
-- OnEnter / OnLeave (hooked in Enable) are the authoritative
-- show/hide triggers for immediate response.
-- ============================================================

local function Update(self, event, unit)
    local element = self.FramedMouseoverHighlight
    if not element then return end

    -- Only called by UPDATE_MOUSEOVER_UNIT (unitless). Re-verify that
    -- the cursor is still over this frame's unit.
    local frameUnit = self.unit
    if not frameUnit then return end

    if UnitIsUnit(frameUnit, "mouseover") then
        element:Show()
    else
        element:Hide()
    end
end

-- ============================================================
-- ForceUpdate
-- ============================================================

local function ForceUpdate(element)
    return Update(element.__owner, "ForceUpdate", element.__owner.unit)
end

-- ============================================================
-- Enable / Disable
-- ============================================================

local function Enable(self, unit)
    local element = self.FramedMouseoverHighlight
    if not element then return end

    element.__owner   = self
    element.ForceUpdate = ForceUpdate

    -- UPDATE_MOUSEOVER_UNIT is unitless (true) — used as a safety check
    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", Update, true)

    -- OnEnter / OnLeave hooks provide immediate response
    self:HookScript("OnEnter", function(frame)
        local el = frame.FramedMouseoverHighlight
        if el then el:Show() end
    end)

    self:HookScript("OnLeave", function(frame)
        local el = frame.FramedMouseoverHighlight
        if el then el:Hide() end
    end)

    return true
end

local function Disable(self)
    local element = self.FramedMouseoverHighlight
    if not element then return end

    element:Hide()
    self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT", Update)
    -- HookScript hooks cannot be cleanly removed, but Hide() is a no-op
    -- when the element is already hidden so this is safe.
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement("FramedMouseoverHighlight", Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create the mouseover highlight overlay texture on a unit frame.
--- The overlay is a very subtle white texture at 8% opacity.
--- Assigns result to self.FramedMouseoverHighlight, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: color
function Framed.Elements.MouseoverHighlight.Setup(self, config)
    config = config or {}
    local color = config.color or { 1, 1, 1, 0.08 }

    local overlay = self:CreateTexture(nil, "HIGHLIGHT")
    overlay:SetAllPoints(self)
    overlay:SetTexture("Interface\\BUTTONS\\WHITE8x8")
    overlay:SetVertexColor(color[1], color[2], color[3], color[4] or 0.08)
    overlay:Hide()

    self.FramedMouseoverHighlight = overlay
end
