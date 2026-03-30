local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}


function F.AppearanceCards.GlobalFont(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - Widgets.CARD_PADDING * 2, 220)

	local fontDropdown = Widgets.CreateTextureDropdown(inner, widgetW, 'font')
	cardY = B.PlaceWidget(fontDropdown, inner, cardY, B.DROPDOWN_H)

	local savedFont = getConfig('font') or 'Expressway'
	fontDropdown:SetValue(savedFont)

	fontDropdown:SetOnSelect(function(texturePath, name)
		setConfig('font', name)
		fireChange()
	end)

	Widgets.EndCard(card, parent, cardY)
	return card
end
