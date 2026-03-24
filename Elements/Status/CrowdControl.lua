local addonName, Framed = ...
local oUF = Framed.oUF
local C = Framed.Constants
local Widgets = Framed.Widgets

Framed.Elements = Framed.Elements or {}
Framed.Elements.CrowdControl = {}

-- ============================================================
-- Known player-cast CC spell IDs
-- ============================================================

local CC_SPELLS = {
    [118]    = true,    -- Polymorph (Mage)
    [28271]  = true,    -- Polymorph: Turtle (Mage)
    [28272]  = true,    -- Polymorph: Pig (Mage)
    [61305]  = true,    -- Polymorph: Black Cat (Mage)
    [61721]  = true,    -- Polymorph: Rabbit (Mage)
    [61780]  = true,    -- Polymorph: Turkey (Mage)
    [51514]  = true,    -- Hex (Shaman)
    [211015] = true,    -- Hex: Cockroach (Shaman)
    [211010] = true,    -- Hex: Snake (Shaman)
    [269352] = true,    -- Hex: Skeletal Hatchling (Shaman)
    [277778] = true,    -- Hex: Zandalari Tendonripper (Shaman)
    [309328] = true,    -- Hex: Living Honey (Shaman)
    [6770]   = true,    -- Sap (Rogue)
    [217832] = true,    -- Imprison (Demon Hunter)
    [710]    = true,    -- Banish (Warlock)
    [33786]  = true,    -- Cyclone (Druid)
    [20066]  = true,    -- Repentance (Paladin)
    [9484]   = true,    -- Shackle Undead (Priest)
    [2637]   = true,    -- Hibernate (Druid)
    [3355]   = true,    -- Freezing Trap (Hunter)
    [19386]  = true,    -- Wyvern Sting (Hunter)
    [187650] = true,    -- Freezing Trap (Hunter — BfA+ ID)
}

-- ============================================================
-- Duration Formatting
-- ============================================================

local function FormatDuration(seconds)
    if seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    elseif seconds >= 1 then
        return string.format("%d", math.ceil(seconds))
    else
        return string.format("%.1f", seconds)
    end
end

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
    local element = self.FramedCrowdControl
    if not element then return end

    if unit ~= self.unit then return end

    -- Scan unit's debuffs for player-applied CC
    local foundIcon   = nil
    local foundExpiry = nil
    local foundCount  = 0

    local i = 1
    while true do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
        if not auraData then break end

        local spellId = auraData.spellId
        if spellId and not issecretvalue(spellId) and CC_SPELLS[spellId] then
            -- Check that this debuff was applied by the player
            local sourceUnit = auraData.sourceUnit
            if sourceUnit and not issecretvalue(sourceUnit) and UnitIsUnit(sourceUnit, "player") then
                -- Take the first matching CC (or highest-expiry one)
                if foundIcon == nil then
                    foundIcon   = auraData.icon
                    foundExpiry = auraData.expirationTime
                    foundCount  = auraData.applications or 1
                end
            end
        end

        i = i + 1
    end

    if foundIcon then
        element.icon:SetTexture(foundIcon)
        element.icon:Show()

        if foundExpiry and foundExpiry > 0 then
            local remaining = foundExpiry - GetTime()
            if remaining > 0 then
                element.duration:SetText(FormatDuration(remaining))
                element.duration:Show()
            else
                element.duration:Hide()
            end
        else
            element.duration:Hide()
        end

        element._expiry = foundExpiry
        element:Show()
    else
        element._expiry = nil
        element:Hide()
    end
end

-- ============================================================
-- OnUpdate ticker for duration countdown
-- ============================================================

local function OnUpdate(frame, elapsed)
    local element = frame.FramedCrowdControl
    if not element or not element._expiry then return end

    local remaining = element._expiry - GetTime()
    if remaining > 0 then
        element.duration:SetText(FormatDuration(remaining))
    else
        element.duration:Hide()
        element._expiry = nil
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
    local element = self.FramedCrowdControl
    if not element then return end

    element.__owner   = self
    element.ForceUpdate = ForceUpdate

    self:RegisterEvent("UNIT_AURA", Update)
    self:HookScript("OnUpdate", OnUpdate)

    return true
end

local function Disable(self)
    local element = self.FramedCrowdControl
    if not element then return end

    element:Hide()
    self:UnregisterEvent("UNIT_AURA", Update)
    element._expiry = nil
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement("FramedCrowdControl", Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create the player-applied CC tracker widget on a unit frame.
--- Shows a spell icon and live countdown timer for Polymorph, Hex,
--- Sap, Cyclone, Banish, Imprison, and other player-cast CC spells.
--- Assigns result to self.FramedCrowdControl, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: iconSize, point
function Framed.Elements.CrowdControl.Setup(self, config)
    config = config or {}
    local iconSize = config.iconSize or 24
    local point    = config.point    or { "CENTER", self, "CENTER", 0, 0 }

    -- Container frame
    local container = CreateFrame("Frame", nil, self)
    container:SetFrameLevel(self:GetFrameLevel() + 15)
    Widgets.SetSize(container, iconSize, iconSize + 14)
    container:Hide()

    -- Position the container
    local p = point
    container:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0)

    -- Spell icon
    local icon = container:CreateTexture(nil, "ARTWORK")
    Widgets.SetSize(icon, iconSize, iconSize)
    icon:SetPoint("TOP", container, "TOP", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    container.icon = icon

    -- Thin black border around icon
    local border = CreateFrame("Frame", nil, container, "BackdropTemplate")
    border:SetAllPoints(icon)
    border:SetFrameLevel(container:GetFrameLevel() + 1)
    border:SetBackdrop({
        bgFile   = nil,
        edgeFile = "Interface\\BUTTONS\\WHITE8x8",
        edgeSize = 1,
    })
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(0, 0, 0, 1)

    -- Duration text below the icon
    local duration = Widgets.CreateFontString(container, C.Font.sizeSmall, C.Colors.textActive)
    duration:SetFont(STANDARD_TEXT_FONT, C.Font.sizeSmall, "OUTLINE")
    duration:SetPoint("TOP", icon, "BOTTOM", 0, -1)
    duration:SetJustifyH("CENTER")
    container.duration = duration

    self.FramedCrowdControl = container
end
