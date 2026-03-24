local addonName, Framed = ...
local oUF = Framed.oUF
local C = Framed.Constants
local Widgets = Framed.Widgets

Framed.Elements = Framed.Elements or {}
Framed.Elements.StatusText = {}

-- ============================================================
-- Status color constants
-- ============================================================

local COLOR_DEAD     = { 0.8, 0.1, 0.1 }
local COLOR_GHOST    = { 0.6, 0.6, 0.6 }
local COLOR_OFFLINE  = { 0.5, 0.5, 0.5 }
local COLOR_AFK      = { 1,   0.8, 0   }
local COLOR_ACCEPTED = { 0.2, 0.8, 0.2 }
local COLOR_DECLINED = { 0.8, 0.1, 0.1 }

-- Summon status enum values
local SUMMON_NONE     = 0
local SUMMON_PENDING  = 1
local SUMMON_ACCEPTED = 2
local SUMMON_DECLINED = 3

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
    local element = self.FramedStatusText
    if not element then return end

    if unit ~= self.unit then return end

    local text, color

    if UnitIsDeadOrGhost(unit) then
        if UnitIsGhost(unit) then
            text  = "GHOST"
            color = COLOR_GHOST
        else
            text  = "DEAD"
            color = COLOR_DEAD
        end
    elseif not UnitIsConnected(unit) then
        text  = "OFFLINE"
        color = COLOR_OFFLINE
    elseif UnitIsAFK(unit) then
        text  = "AFK"
        color = COLOR_AFK
    elseif C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
        local status = C_IncomingSummon.IncomingSummonStatus(unit)
        if status == SUMMON_PENDING then
            text  = "SUMMON"
            color = C.Colors.accent
        elseif status == SUMMON_ACCEPTED then
            text  = "ACCEPTED"
            color = COLOR_ACCEPTED
        elseif status == SUMMON_DECLINED then
            text  = "DECLINED"
            color = COLOR_DECLINED
        end
    end

    if text then
        element:SetText(text)
        element:SetTextColor(color[1], color[2], color[3], 1)
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
    local element = self.FramedStatusText
    if not element then return end

    element.__owner   = self
    element.ForceUpdate = ForceUpdate

    self:RegisterEvent("UNIT_HEALTH",            Update)
    self:RegisterEvent("UNIT_CONNECTION",         Update)
    self:RegisterEvent("PLAYER_FLAGS_CHANGED",    Update)
    self:RegisterEvent("INCOMING_SUMMON_CHANGED", Update, true)

    return true
end

local function Disable(self)
    local element = self.FramedStatusText
    if not element then return end

    element:Hide()

    self:UnregisterEvent("UNIT_HEALTH",            Update)
    self:UnregisterEvent("UNIT_CONNECTION",         Update)
    self:UnregisterEvent("PLAYER_FLAGS_CHANGED",    Update)
    self:UnregisterEvent("INCOMING_SUMMON_CHANGED", Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement("FramedStatusText", Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create the status text overlay FontString on a unit frame.
--- Assigns result to self.FramedStatusText, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: size, point
function Framed.Elements.StatusText.Setup(self, config)
    config = config or {}
    config.size  = config.size  or C.Font.sizeSmall
    config.point = config.point or { "CENTER", self, "CENTER", 0, 0 }

    -- FontString sits in the OVERLAY layer so it renders above bars/textures
    local fs = Widgets.CreateFontString(self, config.size, C.Colors.textActive)
    fs:SetFont(STANDARD_TEXT_FONT, config.size, "OUTLINE")

    local p = config.point
    fs:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0)
    fs:SetJustifyH("CENTER")
    fs:Hide()

    self.FramedStatusText = fs
end
