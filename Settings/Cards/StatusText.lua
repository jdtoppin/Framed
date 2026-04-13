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

	-- Text position anchor
	cardY = B.PlaceHeading(inner, 'Text Position', 4, cardY)
	local anchorPicker = Widgets.CreateAnchorPicker(inner, widgetW)
	anchorPicker:SetAnchor(getConfig('statusText.anchor'), 0, 0)
	anchorPicker._xSlider:Hide()
	anchorPicker._ySlider:Hide()
	anchorPicker:SetOnChanged(function(point)
		setConfig('statusText.anchor', point)
	end)
	cardY = B.PlaceWidget(anchorPicker, inner, cardY, 56)

	-- X / Y offsets
	cardY = B.PlaceHeading(inner, 'Text Offsets', 4, cardY)
	local offsetX = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	offsetX:SetValue(getConfig('statusText.anchorX'))
	offsetX:SetAfterValueChanged(function(value)
		setConfig('statusText.anchorX', value)
	end)
	cardY = B.PlaceWidget(offsetX, inner, cardY, B.SLIDER_H)

	local offsetY = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	offsetY:SetValue(getConfig('statusText.anchorY'))
	offsetY:SetAfterValueChanged(function(value)
		setConfig('statusText.anchorY', value)
	end)
	cardY = B.PlaceWidget(offsetY, inner, cardY, B.SLIDER_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
