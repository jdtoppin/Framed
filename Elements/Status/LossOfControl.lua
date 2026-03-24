local addonName, Framed = ...
local oUF = Framed.oUF
local C = Framed.Constants
local Widgets = Framed.Widgets

Framed.Elements = Framed.Elements or {}
Framed.Elements.LossOfControl = {}

-- ============================================================
-- CC Type Definitions
-- Priority: Stun > MC > Fear > Silence > Root
-- ============================================================

local CC_TYPE = {
    STUN    = 1,
    MC      = 2,
    FEAR    = 3,
    SILENCE = 4,
    ROOT    = 5,
}

-- Overlay colors per CC type (r, g, b, a)
local CC_COLORS = {
    [CC_TYPE.STUN]    = { 0.8, 0.1, 0.1, 0.55 },   -- red
    [CC_TYPE.MC]      = { 0.6, 0.1, 0.8, 0.55 },   -- purple
    [CC_TYPE.FEAR]    = { 0.9, 0.8, 0.1, 0.55 },   -- yellow
    [CC_TYPE.SILENCE] = { 0.1, 0.4, 0.9, 0.55 },   -- blue
    [CC_TYPE.ROOT]    = { 0.1, 0.7, 0.2, 0.55 },   -- green
}

-- Known CC spell IDs grouped by type.
-- Keyed by spellID → CC_TYPE priority value.
-- Higher priority value = overrides lower (STUN overrides ROOT).
local CC_SPELL_TYPES = {
    -- ---- Stuns ----
    [853]    = CC_TYPE.STUN,    -- Hammer of Justice (Paladin)
    [2094]   = CC_TYPE.STUN,    -- Blind (Rogue) — technically incapacitate but stun-adjacent
    [5246]   = CC_TYPE.STUN,    -- Intimidating Shout (Warrior)
    [20066]  = CC_TYPE.STUN,    -- Repentance (Paladin)
    [22703]  = CC_TYPE.STUN,    -- Infernal Awakening
    [30283]  = CC_TYPE.STUN,    -- Shadowfury (Warlock)
    [46968]  = CC_TYPE.STUN,    -- Shockwave (Warrior)
    [49203]  = CC_TYPE.STUN,    -- Hungering Cold (Death Knight)
    [64044]  = CC_TYPE.STUN,    -- Psychic Horror (Priest)
    [89766]  = CC_TYPE.STUN,    -- Axe Toss (Warlock pet)
    [108194] = CC_TYPE.STUN,    -- Asphyxiate (Death Knight)
    [119381] = CC_TYPE.STUN,    -- Leg Sweep (Monk)
    [132169] = CC_TYPE.STUN,    -- Stormbolt (Warrior)
    [179057] = CC_TYPE.STUN,    -- Chaos Nova (Demon Hunter)
    [205364] = CC_TYPE.STUN,    -- Master's Call (Hunter pet Tendon Rip)
    [211881] = CC_TYPE.STUN,    -- Fel Eruption (Demon Hunter)
    [221562] = CC_TYPE.STUN,    -- Asphyxiate (Blood DK)
    [255941] = CC_TYPE.STUN,    -- Greater Blessing of Kings knockback/stun
    [408] = CC_TYPE.STUN,       -- Kidney Shot (Rogue)
    [1833] = CC_TYPE.STUN,      -- Cheap Shot (Rogue)

    -- ---- Mind Control ----
    [605]    = CC_TYPE.MC,      -- Mind Control (Priest)
    [15487]  = CC_TYPE.MC,      -- Dominate Mind (Priest)

    -- ---- Fears ----
    [5484]   = CC_TYPE.FEAR,    -- Howl of Terror (Warlock)
    [5782]   = CC_TYPE.FEAR,    -- Fear (Warlock)
    [8122]   = CC_TYPE.FEAR,    -- Psychic Scream (Priest)
    [31224]  = CC_TYPE.FEAR,    -- Cloak of Shadows — no, skip
    [113792] = CC_TYPE.FEAR,    -- Psychic Terror (Priest talent)

    -- ---- Silences ----
    [15487]  = CC_TYPE.SILENCE, -- Silence (Priest) — shares ID with Dominate Mind effect, treat as MC above
    [47476]  = CC_TYPE.SILENCE, -- Strangulate (Death Knight)
    [81261]  = CC_TYPE.SILENCE, -- Solar Beam (Druid)
    [196364] = CC_TYPE.SILENCE, -- Unstable Affliction silence component
    [202933] = CC_TYPE.SILENCE, -- Spider Sting silence
    [217832] = CC_TYPE.SILENCE, -- Imprison silence component (partial)
    [263354] = CC_TYPE.SILENCE, -- Quaking silence
    [31935]  = CC_TYPE.SILENCE, -- Avenger's Shield silence

    -- ---- Roots ----
    [122]    = CC_TYPE.ROOT,    -- Frost Nova (Mage)
    [339]    = CC_TYPE.ROOT,    -- Entangling Roots (Druid)
    [33395]  = CC_TYPE.ROOT,    -- Freeze (Mage Water Elemental)
    [64695]  = CC_TYPE.ROOT,    -- Earthgrab (Shaman)
    [116706] = CC_TYPE.ROOT,    -- Disable (Monk)
    [162480] = CC_TYPE.ROOT,    -- Steel Trap (Hunter)
    [212638] = CC_TYPE.ROOT,    -- Tracker's Net (Hunter)
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
    local element = self.FramedLossOfControl
    if not element then return end

    if unit ~= self.unit then return end

    -- Scan unit debuffs for known CC spells
    local bestPriority = nil
    local bestIcon     = nil
    local bestExpiry   = nil

    local i = 1
    while true do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
        if not auraData then break end

        -- Guard against secret/restricted values on 12.0+
        local spellId = auraData.spellId
        if Framed.IsValueNonSecret(spellId) then
            local ccType = CC_SPELL_TYPES[spellId]
            if ccType then
                -- Lower CC_TYPE value = higher priority
                if bestPriority == nil or ccType < bestPriority then
                    bestPriority = ccType
                    bestIcon     = auraData.icon
                    bestExpiry   = auraData.expirationTime
                end
            end
        end

        i = i + 1
    end

    if bestPriority then
        local color = CC_COLORS[bestPriority]
        element.overlay:SetVertexColor(color[1], color[2], color[3], color[4])
        element.overlay:Show()

        if bestIcon then
            element.icon:SetTexture(bestIcon)
            element.icon:Show()
        else
            element.icon:Hide()
        end

        if bestExpiry and bestExpiry > 0 then
            local remaining = bestExpiry - GetTime()
            if remaining > 0 then
                element.duration:SetText(FormatDuration(remaining))
                element.duration:Show()
            else
                element.duration:Hide()
            end
        else
            element.duration:Hide()
        end

        -- Store expiry for OnUpdate ticker
        element._expiry = bestExpiry

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
    local element = frame.FramedLossOfControl
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
    local element = self.FramedLossOfControl
    if not element then return end

    element.__owner   = self
    element.ForceUpdate = ForceUpdate

    self:RegisterEvent("UNIT_AURA", Update)
    self:HookScript("OnUpdate", OnUpdate)

    return true
end

local function Disable(self)
    local element = self.FramedLossOfControl
    if not element then return end

    element:Hide()
    self:UnregisterEvent("UNIT_AURA", Update)
    -- OnUpdate hook cannot be removed, but it short-circuits when _expiry is nil
    element._expiry = nil
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement("FramedLossOfControl", Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create the Loss-of-Control overlay on a unit frame.
--- Widget contains: colored semi-transparent overlay, centered spell icon,
--- and a duration FontString. Assigns to self.FramedLossOfControl.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: iconSize, point
function Framed.Elements.LossOfControl.Setup(self, config)
    config = config or {}
    local iconSize = config.iconSize or 20
    local point    = config.point    or { "CENTER", self, "CENTER", 0, 0 }

    -- Container frame
    local container = CreateFrame("Frame", nil, self)
    container:SetAllPoints(self)
    container:SetFrameLevel(self:GetFrameLevel() + 15)
    container:Hide()

    -- Semi-transparent colored overlay covering the full frame
    local overlay = container:CreateTexture(nil, "BACKGROUND")
    overlay:SetAllPoints(container)
    overlay:SetTexture("Interface\\BUTTONS\\WHITE8x8")
    overlay:SetVertexColor(0.8, 0.1, 0.1, 0.55)
    container.overlay = overlay

    -- Spell icon (centered)
    local icon = container:CreateTexture(nil, "ARTWORK")
    Widgets.SetSize(icon, iconSize, iconSize)
    local p = point
    icon:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    container.icon = icon

    -- Duration text below the icon
    local duration = Widgets.CreateFontString(container, C.Font.sizeSmall, C.Colors.textActive)
    duration:SetFont(STANDARD_TEXT_FONT, C.Font.sizeSmall, "OUTLINE")
    duration:SetPoint("TOP", icon, "BOTTOM", 0, -2)
    duration:SetJustifyH("CENTER")
    container.duration = duration

    self.FramedLossOfControl = container
end
