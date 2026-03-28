local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local DROPDOWN_H   = 22
local CARD_PADDING = 12
local placeWidget  = B.PlaceWidget

function F.AppearanceCards.GlobalFont(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - CARD_PADDING * 2, 220)

	local fontDropdown = Widgets.CreateTextureDropdown(inner, widgetW, 'font')
	cardY = placeWidget(fontDropdown, inner, cardY, DROPDOWN_H)

	local savedFont = getConfig('font')
	if(savedFont) then
		fontDropdown:SetValue(savedFont)
	end

	fontDropdown:SetOnSelect(function(texturePath, name)
		setConfig('font', name)
		fireChange()
	end)

	Widgets.EndCard(card, parent, cardY)
	card:ClearAllPoints()
	card._startY = 0
	return card
end
