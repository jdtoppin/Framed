local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}


function F.SettingsCards.StatusText(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- Show / hide toggle
	local showCheck = Widgets.CreateCheckButton(inner, 'Show Status Text', function(checked)
		setConfig('statusText.enabled', checked)
	end)
	showCheck:SetChecked(getConfig('statusText.enabled') ~= false)
	cardY = B.PlaceWidget(showCheck, inner, cardY, B.CHECK_H)

	-- Font size slider
	local fontSizeSlider = Widgets.CreateSlider(inner, 'Font Size', widgetW, 6, 24, 1)
	fontSizeSlider:SetValue(getConfig('statusText.fontSize'))
	fontSizeSlider:SetAfterValueChanged(function(value)
		setConfig('statusText.fontSize', value)
	end)
	cardY = B.PlaceWidget(fontSizeSlider, inner, cardY, B.SLIDER_H)

	-- Outline dropdown
	cardY = B.PlaceHeading(inner, 'Outline', 4, cardY)
	local outlineDropdown = Widgets.CreateDropdown(inner, widgetW)
	outlineDropdown:SetItems({
		{ text = 'None',       value = '' },
		{ text = 'Outline',    value = 'OUTLINE' },
		{ text = 'Monochrome', value = 'MONOCHROME' },
	})
	outlineDropdown:SetValue(getConfig('statusText.outline'))
	outlineDropdown:SetOnSelect(function(value)
		setConfig('statusText.outline', value)
	end)
	cardY = B.PlaceWidget(outlineDropdown, inner, cardY, B.DROPDOWN_H)

	-- Text shadow toggle
	local shadowCheck = Widgets.CreateCheckButton(inner, 'Text Shadow', function(checked)
		setConfig('statusText.shadow', checked)
	end)
	shadowCheck:SetChecked(getConfig('statusText.shadow'))
	cardY = B.PlaceWidget(shadowCheck, inner, cardY, B.CHECK_H)

	-- Vertical position on the health bar
	cardY = B.PlaceHeading(inner, 'Position', 4, cardY)
	local positionSwitch = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
		{ text = 'Top',    value = 'top'    },
		{ text = 'Center', value = 'center' },
		{ text = 'Bottom', value = 'bottom' },
	})
	positionSwitch:SetValue(getConfig('statusText.position'))
	positionSwitch:SetOnSelect(function(value)
		setConfig('statusText.position', value)
	end)
	cardY = B.PlaceWidget(positionSwitch, inner, cardY, B.SWITCH_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
