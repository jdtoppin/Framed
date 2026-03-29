local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local SWATCH_H     = 20

function F.AppearanceCards.MouseoverHighlight(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - Widgets.CARD_PADDING * 2, 220)

	cardY = B.PlaceHeading(inner, 'Color', 4, cardY)

	local moColorPicker = Widgets.CreateColorPicker(inner)
	moColorPicker:SetHasAlpha(true)
	moColorPicker:ClearAllPoints()
	Widgets.SetPoint(moColorPicker, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)

	local savedMoColor = getConfig('mouseoverHighlightColor')
	if(savedMoColor) then
		moColorPicker:SetColor(savedMoColor[1], savedMoColor[2], savedMoColor[3], savedMoColor[4] or 0.6)
	else
		moColorPicker:SetColor(0.969, 0.925, 1, 0.6)  -- #f7ecff @ 60%
	end

	moColorPicker:SetOnColorChanged(function(r, g, b, a)
		setConfig('mouseoverHighlightColor', { r, g, b, a })
	end)
	cardY = cardY - SWATCH_H - C.Spacing.normal

	local moWidthSlider = Widgets.CreateSlider(inner, 'Border Width', widgetW, 1, 4, 1)
	moWidthSlider:SetValue(getConfig('mouseoverHighlightWidth') or 2)
	moWidthSlider:SetAfterValueChanged(function(value)
		setConfig('mouseoverHighlightWidth', value)
	end)
	cardY = B.PlaceWidget(moWidthSlider, inner, cardY, B.SLIDER_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
