local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local DROPDOWN_H   = 22
local CARD_PADDING = 12
local placeWidget  = B.PlaceWidget

function F.AppearanceCards.BarTexture(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - CARD_PADDING * 2, 220)

	local barDropdown = Widgets.CreateTextureDropdown(inner, widgetW, 'statusbar')
	cardY = placeWidget(barDropdown, inner, cardY, DROPDOWN_H)

	local savedBar = getConfig('barTexture')
	if(savedBar) then
		barDropdown:SetValue(savedBar)
	end

	barDropdown:SetOnSelect(function(texturePath, name)
		setConfig('barTexture', name)
		fireChange()
	end)

	Widgets.EndCard(card, parent, cardY)
	card:ClearAllPoints()
	card._startY = 0
	return card
end
