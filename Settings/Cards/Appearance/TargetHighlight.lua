local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local SWATCH_H     = 20

function F.AppearanceCards.TargetHighlight(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - Widgets.CARD_PADDING * 2, 220)

	cardY = B.PlaceHeading(inner, 'Color', 4, cardY)

	local thColorPicker = Widgets.CreateColorPicker(inner)
	thColorPicker:SetHasAlpha(true)
	thColorPicker:ClearAllPoints()
	Widgets.SetPoint(thColorPicker, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)

	local savedThColor = getConfig('targetHighlightColor')
	if(savedThColor) then
		thColorPicker:SetColor(savedThColor[1], savedThColor[2], savedThColor[3], savedThColor[4] or 1)
	else
		thColorPicker:SetColor(0.839, 0, 0.075, 1)  -- #d60013
	end

	thColorPicker:SetOnColorChanged(function(r, g, b, a)
		setConfig('targetHighlightColor', { r, g, b, a })
	end)
	cardY = cardY - SWATCH_H - C.Spacing.normal

	local thWidthSlider = Widgets.CreateSlider(inner, 'Border Width', widgetW, 1, 4, 1)
	thWidthSlider:SetValue(getConfig('targetHighlightWidth') or 2)
	thWidthSlider:SetAfterValueChanged(function(value)
		setConfig('targetHighlightWidth', value)
	end)
	cardY = B.PlaceWidget(thWidthSlider, inner, cardY, B.SLIDER_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
