local addonName, Framed = ...
local oUF = Framed.oUF
local C = Framed.Constants
local Widgets = Framed.Widgets

Framed.Elements = Framed.Elements or {}
Framed.Elements.Health = {}

-- ============================================================
-- Number Abbreviation Helper
-- ============================================================

--- Abbreviate a number: >= 1M → "1.2M", >= 1K → "145K", else raw.
--- @param value number
--- @return string
local function AbbreviateNumber(value)
    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%dK", math.floor(value / 1000 + 0.5))
    else
        return tostring(math.floor(value + 0.5))
    end
end

-- ============================================================
-- Health Element Setup
-- ============================================================

--- Configure oUF's built-in Health element on a unit frame.
--- @param self Frame  The oUF unit frame
--- @param width number  Bar width in UI units
--- @param height number  Bar height in UI units
--- @param config? table  Optional config table; defaults applied if nil
function Framed.Elements.Health.Setup(self, width, height, config)

    -- --------------------------------------------------------
    -- Config defaults
    -- --------------------------------------------------------

    config = config or {}
    config.colorMode      = config.colorMode or "class"         -- "class", "gradient", "custom"
    config.smooth         = config.smooth ~= false               -- default true
    config.customColor    = config.customColor or {0.2, 0.8, 0.2}
    config.threshold      = config.threshold or nil              -- e.g., 0.35 for 35%
    config.thresholdColor = config.thresholdColor or {0.8, 0.1, 0.1}
    config.showText       = config.showText or false
    config.textFormat     = config.textFormat or "percent"       -- "percent", "current", "deficit", "current-max", "none"
    config.healPrediction = config.healPrediction ~= false       -- default true

    -- --------------------------------------------------------
    -- Health bar (via Widgets.CreateStatusBar)
    -- StatusBar._wrapper is the backdrop frame; oUF needs the bar itself.
    -- --------------------------------------------------------

    local health = Widgets.CreateStatusBar(self, width, height)

    -- Position the wrapper (backdrop frame) on the unit frame
    health._wrapper:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)

    -- --------------------------------------------------------
    -- Background texture behind the health bar fill
    -- Sits inside the wrapper, below the bar texture
    -- --------------------------------------------------------

    local bg = health:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(health)
    bg:SetTexture("Interface\\BUTTONS\\WHITE8x8")
    local bgC = C.Colors.background
    bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

    -- --------------------------------------------------------
    -- Color mode
    -- --------------------------------------------------------

    if config.colorMode == "class" then
        health.colorClass    = true
        health.colorReaction = true
    elseif config.colorMode == "gradient" then
        health.colorSmooth = true
    end
    -- "custom" is handled entirely in PostUpdate

    -- --------------------------------------------------------
    -- Smooth interpolation
    -- --------------------------------------------------------

    health:SetSmooth(config.smooth)

    -- --------------------------------------------------------
    -- Health text (optional)
    -- --------------------------------------------------------

    if config.showText then
        local text = Widgets.CreateFontString(health, C.Font.sizeSmall, C.Colors.textActive)
        text:SetPoint("CENTER", health, "CENTER", 0, 0)
        health.text = text
    end

    -- --------------------------------------------------------
    -- PostUpdate: custom color, threshold override, text formatting
    -- --------------------------------------------------------

    health.PostUpdate = function(h, unit, cur, max)
        -- Custom color mode
        if config.colorMode == "custom" then
            h:SetStatusBarColor(unpack(config.customColor))
        end

        -- Threshold color override (always applied on top of any color mode)
        if config.threshold then
            local pct = (max > 0) and (cur / max) or 1
            if pct < config.threshold then
                h:SetStatusBarColor(unpack(config.thresholdColor))
            end
        end

        -- Health text formatting
        if config.showText and h.text then
            local fmt = config.textFormat
            if fmt == "none" or max <= 0 then
                h.text:SetText("")
            elseif fmt == "percent" then
                local pct = math.floor(cur / max * 100 + 0.5)
                h.text:SetText(pct .. "%")
            elseif fmt == "current" then
                h.text:SetText(AbbreviateNumber(cur))
            elseif fmt == "deficit" then
                local deficit = max - cur
                if deficit <= 0 then
                    h.text:SetText("")
                else
                    h.text:SetText("-" .. AbbreviateNumber(deficit))
                end
            elseif fmt == "current-max" then
                h.text:SetText(AbbreviateNumber(cur) .. "/" .. AbbreviateNumber(max))
            else
                h.text:SetText("")
            end
        end
    end

    -- --------------------------------------------------------
    -- Heal prediction bars (oUF HealthPrediction element)
    -- --------------------------------------------------------

    if config.healPrediction then
        local myBar = self:CreateTexture(nil, "OVERLAY")
        myBar:SetTexture("Interface\\BUTTONS\\WHITE8x8")
        myBar:SetVertexColor(0, 0.8, 0.2, 0.4)     -- own heals: green, semi-transparent

        local otherBar = self:CreateTexture(nil, "OVERLAY")
        otherBar:SetTexture("Interface\\BUTTONS\\WHITE8x8")
        otherBar:SetVertexColor(0, 0.6, 0.2, 0.3)  -- other heals: darker green

        local absorbBar = self:CreateTexture(nil, "OVERLAY")
        absorbBar:SetTexture("Interface\\BUTTONS\\WHITE8x8")
        absorbBar:SetVertexColor(1, 0.8, 0, 0.4)   -- absorbs: gold

        self.HealthPrediction = {
            myBar      = myBar,
            otherBar   = otherBar,
            absorbBar  = absorbBar,
            maxOverflow = 1.05,
        }
    end

    -- --------------------------------------------------------
    -- Assign to oUF — activates the Health element
    -- --------------------------------------------------------

    self.Health = health
end
