local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}


function F.SettingsCards.PowerText(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - Widgets.CARD_PADDING * 2, B.WIDGET_W)

	local showPowerTextCheck = Widgets.CreateCheckButton(inner, 'Show Power Text', function(checked)
		setConfig('power.showText', checked)
	end)
	showPowerTextCheck:SetChecked(getConfig('power.showText') or false)
	cardY = B.PlaceWidget(showPowerTextCheck, inner, cardY, B.CHECK_H)

	-- Power text font size
	local powerFontSize = Widgets.CreateSlider(inner, 'Font Size', widgetW, 6, 24, 1)
	powerFontSize:SetValue(getConfig('power.fontSize') or 0)
	Widgets.SetTooltip(powerFontSize, 'Power Text Font Size', 'Override the global font size for power text')
	powerFontSize:SetAfterValueChanged(function(value)
		setConfig('power.fontSize', value)
	end)
	cardY = B.PlaceWidget(powerFontSize, inner, cardY, B.SLIDER_H)

	-- Power text outline
	cardY = B.PlaceHeading(inner, 'Outline', 3, cardY)
	local powerOutline = Widgets.CreateDropdown(inner, widgetW)
	powerOutline:SetItems({
		{ text = 'None',       value = '' },
		{ text = 'Outline',    value = 'OUTLINE' },
		{ text = 'Monochrome', value = 'MONOCHROME' },
	})
	powerOutline:SetValue(getConfig('power.outline') or '')
	powerOutline:SetOnSelect(function(value)
		setConfig('power.outline', value)
	end)
	cardY = B.PlaceWidget(powerOutline, inner, cardY, B.DROPDOWN_H)

	-- Power text shadow
	local powerShadow = Widgets.CreateCheckButton(inner, 'Text Shadow', function(checked)
		setConfig('power.shadow', checked)
	end)
	powerShadow:SetChecked(getConfig('power.shadow') ~= false)
	cardY = B.PlaceWidget(powerShadow, inner, cardY, B.CHECK_H)

	-- Power text position anchor
	cardY = B.PlaceHeading(inner, 'Text Position', 3, cardY)
	local powerTextAnchor = Widgets.CreateAnchorPicker(inner, widgetW)
	local savedPowerAnchor = getConfig('power.textAnchor') or 'CENTER'
	powerTextAnchor:SetAnchor(savedPowerAnchor, 0, 0)
	powerTextAnchor:SetOnChanged(function(point)
		setConfig('power.textAnchor', point)
	end)
	powerTextAnchor._xInput:Hide()
	powerTextAnchor._yInput:Hide()
	cardY = B.PlaceWidget(powerTextAnchor, inner, cardY, 56)

	-- Power text offsets
	cardY = B.PlaceHeading(inner, 'Text Offsets', 3, cardY)
	local powerOffsetX = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	powerOffsetX:SetValue(getConfig('power.textAnchorX') or 0)
	powerOffsetX:SetAfterValueChanged(function(value)
		setConfig('power.textAnchorX', value)
	end)
	cardY = B.PlaceWidget(powerOffsetX, inner, cardY, B.SLIDER_H)

	local powerOffsetY = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	powerOffsetY:SetValue(getConfig('power.textAnchorY') or 0)
	powerOffsetY:SetAfterValueChanged(function(value)
		setConfig('power.textAnchorY', value)
	end)
	cardY = B.PlaceWidget(powerOffsetY, inner, cardY, B.SLIDER_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
