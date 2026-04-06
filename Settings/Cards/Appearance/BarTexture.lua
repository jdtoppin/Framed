local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}


function F.AppearanceCards.BarTexture(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local barDropdown = Widgets.CreateTextureDropdown(inner, widgetW, 'statusbar')
	cardY = B.PlaceWidget(barDropdown, inner, cardY, B.DROPDOWN_H)

	local savedBar = getConfig('barTexture') or 'Framed Plain'
	barDropdown:SetValue(savedBar)

	barDropdown:SetOnSelect(function(texturePath, name)
		setConfig('barTexture', name)
		fireChange()
	end)

	Widgets.EndCard(card, parent, cardY)
	return card
end
