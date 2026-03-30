local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}


function F.AppearanceCards.Tooltips(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - Widgets.CARD_PADDING * 2, 220)

	local ttEnabled = Widgets.CreateCheckButton(inner, 'Show Tooltips', function(checked)
		setConfig('tooltipEnabled', checked)
		fireChange()
	end)
	ttEnabled:SetChecked(getConfig('tooltipEnabled') ~= false)
	cardY = B.PlaceWidget(ttEnabled, inner, cardY, B.CHECK_H)

	local ttCombat = Widgets.CreateCheckButton(inner, 'Hide in Combat', function(checked)
		setConfig('tooltipHideInCombat', checked)
		fireChange()
	end)
	ttCombat:SetChecked(getConfig('tooltipHideInCombat') == true)
	cardY = B.PlaceWidget(ttCombat, inner, cardY, B.CHECK_H)

	local ttAnchor = Widgets.CreateDropdown(inner, widgetW)
	ttAnchor:SetItems({
		{ text = 'Right',  value = 'ANCHOR_RIGHT' },
		{ text = 'Left',   value = 'ANCHOR_LEFT' },
		{ text = 'Top',    value = 'ANCHOR_TOP' },
		{ text = 'Bottom', value = 'ANCHOR_BOTTOM' },
		{ text = 'Cursor', value = 'ANCHOR_CURSOR' },
	})
	ttAnchor:SetValue(getConfig('tooltipAnchor'))
	ttAnchor:SetOnSelect(function(value)
		setConfig('tooltipAnchor', value)
		fireChange()
	end)
	cardY = B.PlaceWidget(ttAnchor, inner, cardY, B.DROPDOWN_H)

	local ttOffX = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	ttOffX:SetValue(getConfig('tooltipOffsetX'))
	ttOffX:SetAfterValueChanged(function(value)
		setConfig('tooltipOffsetX', value)
		fireChange()
	end)
	cardY = B.PlaceWidget(ttOffX, inner, cardY, B.SLIDER_H)

	local ttOffY = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	ttOffY:SetValue(getConfig('tooltipOffsetY'))
	ttOffY:SetAfterValueChanged(function(value)
		setConfig('tooltipOffsetY', value)
		fireChange()
	end)
	cardY = B.PlaceWidget(ttOffY, inner, cardY, B.SLIDER_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
