local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local SLIDER_H     = 26
local CHECK_H      = 22
local DROPDOWN_H   = 22
local CARD_PADDING = 12
local placeWidget  = B.PlaceWidget

function F.AppearanceCards.Tooltips(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - CARD_PADDING * 2, 220)

	local ttEnabled = Widgets.CreateCheckButton(inner, 'Show Tooltips', function(checked)
		setConfig('tooltipEnabled', checked)
		fireChange()
	end)
	ttEnabled:SetChecked(getConfig('tooltipEnabled') ~= false)
	cardY = placeWidget(ttEnabled, inner, cardY, CHECK_H)

	local ttCombat = Widgets.CreateCheckButton(inner, 'Hide in Combat', function(checked)
		setConfig('tooltipHideInCombat', checked)
		fireChange()
	end)
	ttCombat:SetChecked(getConfig('tooltipHideInCombat') == true)
	cardY = placeWidget(ttCombat, inner, cardY, CHECK_H)

	local ttAnchor = Widgets.CreateDropdown(inner, widgetW)
	ttAnchor:SetItems({
		{ text = 'Right',  value = 'ANCHOR_RIGHT' },
		{ text = 'Left',   value = 'ANCHOR_LEFT' },
		{ text = 'Top',    value = 'ANCHOR_TOP' },
		{ text = 'Bottom', value = 'ANCHOR_BOTTOM' },
		{ text = 'Cursor', value = 'ANCHOR_CURSOR' },
	})
	ttAnchor:SetValue(getConfig('tooltipAnchor') or 'ANCHOR_RIGHT')
	ttAnchor:SetOnSelect(function(value)
		setConfig('tooltipAnchor', value)
		fireChange()
	end)
	cardY = placeWidget(ttAnchor, inner, cardY, DROPDOWN_H)

	local ttOffX = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	ttOffX:SetValue(getConfig('tooltipOffsetX') or 0)
	ttOffX:SetAfterValueChanged(function(value)
		setConfig('tooltipOffsetX', value)
		fireChange()
	end)
	cardY = placeWidget(ttOffX, inner, cardY, SLIDER_H)

	local ttOffY = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	ttOffY:SetValue(getConfig('tooltipOffsetY') or 0)
	ttOffY:SetAfterValueChanged(function(value)
		setConfig('tooltipOffsetY', value)
		fireChange()
	end)
	cardY = placeWidget(ttOffY, inner, cardY, SLIDER_H)

	Widgets.EndCard(card, parent, cardY)
	card:ClearAllPoints()
	card._startY = 0
	return card
end
