local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}


function F.SettingsCards.GroupLayout(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - Widgets.CARD_PADDING * 2, B.WIDGET_W)

	-- Spacing slider
	local spacingSlider = Widgets.CreateSlider(inner, 'Spacing', widgetW, 0, 20, 1)
	spacingSlider:SetValue(getConfig('spacing') or 2)
	spacingSlider:SetAfterValueChanged(function(value)
		setConfig('spacing', value)
	end)
	cardY = B.PlaceWidget(spacingSlider, inner, cardY, B.SLIDER_H)

	-- Orientation switch
	cardY = B.PlaceHeading(inner, 'Orientation', 3, cardY)
	local orientSwitch = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
		{ text = 'Vertical',   value = 'vertical' },
		{ text = 'Horizontal', value = 'horizontal' },
	})
	orientSwitch:SetValue(getConfig('orientation') or 'vertical')
	orientSwitch:SetOnSelect(function(value)
		setConfig('orientation', value)
	end)
	cardY = B.PlaceWidget(orientSwitch, inner, cardY, B.SWITCH_H)

	-- Growth direction dropdown
	cardY = B.PlaceHeading(inner, 'Growth Direction', 3, cardY)
	local growthDropdown = Widgets.CreateDropdown(inner, widgetW)
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
	cardY = B.PlaceWidget(growthDropdown, inner, cardY, B.DROPDOWN_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
