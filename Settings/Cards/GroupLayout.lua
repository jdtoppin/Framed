local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}

local SLIDER_H     = B.SLIDER_H
local SWITCH_H     = B.SWITCH_H
local DROPDOWN_H   = B.DROPDOWN_H
local CHECK_H      = B.CHECK_H
local WIDGET_W     = B.WIDGET_W
local placeWidget  = B.PlaceWidget
local placeHeading = B.PlaceHeading

function F.SettingsCards.GroupLayout(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	-- Spacing slider
	local spacingSlider = Widgets.CreateSlider(inner, 'Spacing', WIDGET_W, 0, 20, 1)
	spacingSlider:SetValue(getConfig('spacing') or 2)
	spacingSlider:SetAfterValueChanged(function(value)
		setConfig('spacing', value)
	end)
	cardY = placeWidget(spacingSlider, inner, cardY, SLIDER_H)

	-- Orientation switch
	cardY = placeHeading(inner, 'Orientation', 3, cardY)
	local orientSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
		{ text = 'Vertical',   value = 'vertical' },
		{ text = 'Horizontal', value = 'horizontal' },
	})
	orientSwitch:SetValue(getConfig('orientation') or 'vertical')
	orientSwitch:SetOnSelect(function(value)
		setConfig('orientation', value)
	end)
	cardY = placeWidget(orientSwitch, inner, cardY, SWITCH_H)

	-- Growth direction dropdown
	cardY = placeHeading(inner, 'Growth Direction', 3, cardY)
	local growthDropdown = Widgets.CreateDropdown(inner, WIDGET_W)
	growthDropdown:SetItems({
		{ text = 'Top to Bottom',  value = 'topToBottom' },
		{ text = 'Bottom to Top',  value = 'bottomToTop' },
		{ text = 'Left to Right',  value = 'leftToRight' },
		{ text = 'Right to Left',  value = 'rightToLeft' },
	})
	growthDropdown:SetValue(getConfig('growthDirection') or 'topToBottom')
	growthDropdown:SetOnSelect(function(value)
		setConfig('growthDirection', value)
	end)
	cardY = placeWidget(growthDropdown, inner, cardY, DROPDOWN_H)

	Widgets.EndCard(card, parent, cardY)
	card:ClearAllPoints()
	card._startY = 0
	return card
end
