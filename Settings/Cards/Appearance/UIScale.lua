local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}


function F.AppearanceCards.UIScale(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - Widgets.CARD_PADDING * 2, 220)

	local scaleSlider = Widgets.CreateSlider(inner, 'Scale', widgetW, 0.2, 1.5, 0.01)
	cardY = B.PlaceWidget(scaleSlider, inner, cardY, B.SLIDER_H)
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
	return card
end
