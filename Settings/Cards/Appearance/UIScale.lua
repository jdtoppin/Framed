local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local SLIDER_H     = 26
local CARD_PADDING = 12
local placeWidget  = B.PlaceWidget

function F.AppearanceCards.UIScale(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - CARD_PADDING * 2, 220)

	local scaleSlider = Widgets.CreateSlider(inner, 'Scale', widgetW, 0.2, 1.5, 0.01)
	cardY = placeWidget(scaleSlider, inner, cardY, SLIDER_H)
	scaleSlider:SetFormat('%.2f')

	local savedScale = getConfig('uiScale')
	if(savedScale) then
		scaleSlider:SetValue(savedScale)
	else
		scaleSlider:SetValue(1.0)
	end

	scaleSlider:SetAfterValueChanged(function(value)
		setConfig('uiScale', value)
		fireChange()
	end)

	Widgets.EndCard(card, parent, cardY)
	card:ClearAllPoints()
	card._startY = 0
	return card
end
