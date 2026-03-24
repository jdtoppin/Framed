local addonName, Framed = ...

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- ColorPicker — 20x20 swatch button that opens WoW's color
-- picker frame. Supports optional alpha channel.
-- ============================================================

local SWATCH_SIZE = 20

-- Dark fallback shown behind semi-transparent swatches
local DARK_BG = { 0.08, 0.08, 0.08, 1 }

-- ============================================================
-- Internal helpers
-- ============================================================

--- Update the swatch texture to reflect the stored color.
--- @param picker Frame
local function UpdateSwatchVisual(picker)
    local r, g, b, a = picker._r, picker._g, picker._b, picker._a
    picker._swatch:SetColorTexture(r, g, b, a)
    -- Drive the backdrop bg to match (border stays black)
    picker:SetBackdropColor(r, g, b, a)
end

--- Build the ColorPickerFrame info table and show the picker.
--- @param picker Frame
local function OpenColorPicker(picker)
    local r, g, b, a = picker._r, picker._g, picker._b, picker._a

    -- Cache colors before the dialog opens so we can restore on cancel
    picker._prevR, picker._prevG, picker._prevB, picker._prevA = r, g, b, a

    local function ApplyColor(restore)
        local nr, ng, nb
        local na = picker._a
        if restore then
            nr, ng, nb, na =
                picker._prevR, picker._prevG, picker._prevB, picker._prevA
        elseif ColorPickerFrame.GetColorRGB then
            -- 10.2.5+ API
            nr, ng, nb = ColorPickerFrame:GetColorRGB()
            if picker._hasAlpha then
                na = 1 - ColorPickerFrame:GetColorAlpha()
            end
        else
            nr, ng, nb = ColorPickerFrame:GetColorRGB()
            if picker._hasAlpha and OpacitySliderFrame then
                na = 1 - OpacitySliderFrame:GetValue()
            end
        end
        picker._r, picker._g, picker._b, picker._a = nr, ng, nb, na
        UpdateSwatchVisual(picker)
        if picker._onColorChanged then
            picker._onColorChanged(nr, ng, nb, na)
        end
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        -- 10.2.5+ unified API
        local info = {
            swatchFunc  = ApplyColor,
            hasOpacity  = picker._hasAlpha,
            opacityFunc = ApplyColor,
            cancelFunc  = function() ApplyColor(true) end,
            r = r, g = g, b = b,
            opacity = 1 - a,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        -- Legacy API (pre-10.2.5)
        ColorPickerFrame.func        = ApplyColor
        ColorPickerFrame.hasOpacity  = picker._hasAlpha
        ColorPickerFrame.opacityFunc = ApplyColor
        ColorPickerFrame.cancelFunc  = function() ApplyColor(true) end
        ColorPickerFrame:SetColorRGB(r, g, b)
        if picker._hasAlpha and OpacitySliderFrame then
            OpacitySliderFrame:SetValue(1 - a)
        end
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

-- ============================================================
-- Widgets.CreateColorPicker
-- ============================================================

--- Create a 20x20 color swatch button.
--- @param parent Frame Parent frame
--- @return Frame picker
function Widgets.CreateColorPicker(parent)
    local picker = CreateFrame("Button", nil, parent, "BackdropTemplate")

    -- Default color: opaque white
    picker._r, picker._g, picker._b, picker._a = 1, 1, 1, 1
    picker._hasAlpha        = false
    picker._onColorChanged  = nil

    -- Backdrop: 1px black border, bg driven by swatch color
    picker._bgColor     = { 1, 1, 1, 1 }
    picker._borderColor = C.Colors.border
    Widgets.ApplyBackdrop(picker, picker._bgColor, picker._borderColor)
    Widgets.SetSize(picker, SWATCH_SIZE, SWATCH_SIZE)
    picker:EnableMouse(true)

    -- Dark background layer (visible through semi-transparent swatches)
    local darkBg = picker:CreateTexture(nil, "BACKGROUND")
    darkBg:SetAllPoints(picker)
    darkBg:SetColorTexture(DARK_BG[1], DARK_BG[2], DARK_BG[3], DARK_BG[4])

    -- Color swatch texture (sits above dark bg, below border)
    local swatch = picker:CreateTexture(nil, "ARTWORK")
    swatch:SetAllPoints(picker)
    swatch:SetColorTexture(1, 1, 1, 1)
    picker._swatch = swatch

    -- --------------------------------------------------------
    -- Scripts
    -- --------------------------------------------------------

    picker:SetScript("OnClick", function(self)
        if not self:IsEnabled() then return end
        OpenColorPicker(self)
    end)

    picker:SetScript("OnEnter", function(self)
        local a = C.Colors.accent
        self:SetBackdropBorderColor(a[1], a[2], a[3], a[4] or 1)
        if Widgets.ShowTooltip and self._tooltipTitle then
            Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
        end
    end)

    picker:SetScript("OnLeave", function(self)
        local b = self._borderColor or C.Colors.border
        self:SetBackdropBorderColor(b[1], b[2], b[3], b[4] or 1)
        if Widgets.HideTooltip then
            Widgets.HideTooltip()
        end
    end)

    -- --------------------------------------------------------
    -- Public API
    -- --------------------------------------------------------

    --- Set swatch color and update the visual.
    --- @param r number
    --- @param g number
    --- @param b number
    --- @param a? number Defaults to 1
    function picker:SetColor(r, g, b, a)
        self._r, self._g, self._b, self._a = r, g, b, (a or 1)
        UpdateSwatchVisual(self)
    end

    --- Get the current color.
    --- @return number r, number g, number b, number a
    function picker:GetColor()
        return self._r, self._g, self._b, self._a
    end

    --- Set callback invoked with (r, g, b, a) when the user picks a color.
    --- @param func function
    function picker:SetOnColorChanged(func)
        self._onColorChanged = func
    end

    --- Toggle alpha slider in the color picker dialog.
    --- @param enabled boolean
    function picker:SetHasAlpha(enabled)
        self._hasAlpha = enabled
    end

    -- --------------------------------------------------------
    -- Mixins
    -- --------------------------------------------------------

    Widgets.ApplyBaseMixin(picker)
    Widgets.AttachTooltipScripts(picker)

    return picker
end
