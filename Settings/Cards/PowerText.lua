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

	-- Power text format dropdown
	cardY = B.PlaceHeading(inner, 'Power Text Format', 3, cardY)
	local powerFormatDropdown = Widgets.CreateDropdown(inner, widgetW)
	powerFormatDropdown:SetItems({
		{ text = 'Percentage', value = 'percent' },
		{ text = 'Current',    value = 'current' },
	})
	powerFormatDropdown:SetValue(getConfig('power.textFormat') or 'current')
	powerFormatDropdown:SetOnSelect(function(value)
		setConfig('power.textFormat', value)
	end)
	cardY = B.PlaceWidget(powerFormatDropdown, inner, cardY, B.DROPDOWN_H)

	-- Power text font size
	local powerFontSize = Widgets.CreateSlider(inner, 'Font Size', widgetW, 6, 24, 1)
	powerFontSize:SetValue(getConfig('power.fontSize') or C.Font.sizeSmall)
	Widgets.SetTooltip(powerFontSize, 'Power Text Font Size', 'Override the global font size for power text')
	powerFontSize:SetAfterValueChanged(function(value)
		setConfig('power.fontSize', value)
	end)
	cardY = B.PlaceWidget(powerFontSize, inner, cardY, B.SLIDER_H)

	-- Power text color mode
	cardY = B.PlaceHeading(inner, 'Text Color', 3, cardY)
	local powerColorSwitch = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
		{ text = 'Class',  value = 'class' },
		{ text = 'Dark',   value = 'dark' },
		{ text = 'White',  value = 'white' },
		{ text = 'Custom', value = 'custom' },
	})
	powerColorSwitch:SetValue(getConfig('power.textColorMode') or 'white')
	cardY = B.PlaceWidget(powerColorSwitch, inner, cardY, B.SWITCH_H)

	local colorSwitchEndY = cardY

	-- Custom color picker (shown only in custom mode)
	local powerCustomPicker = Widgets.CreateColorPicker(inner, 'Text Color', false,
		nil,
		function(r, g, b) setConfig('power.textCustomColor', { r, g, b }) end)
	local savedTextColor = getConfig('power.textCustomColor') or { 1, 1, 1 }
	powerCustomPicker:SetColor(savedTextColor[1], savedTextColor[2], savedTextColor[3], 1)
	local colorPickerH = 22

	-- Power text outline
	local outlineHeading, outlineHeadingH = Widgets.CreateHeading(inner, 'Outline', 3)
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

	-- Power text shadow
	local powerShadow = Widgets.CreateCheckButton(inner, 'Text Shadow', function(checked)
		setConfig('power.shadow', checked)
	end)
	powerShadow:SetChecked(getConfig('power.shadow') ~= false)

	-- Power text position anchor
	local posHeading, posHeadingH = Widgets.CreateHeading(inner, 'Text Position', 3)
	local powerTextAnchor = Widgets.CreateAnchorPicker(inner, widgetW)
	local savedPowerAnchor = getConfig('power.textAnchor') or 'CENTER'
	powerTextAnchor:SetAnchor(savedPowerAnchor, 0, 0)
	powerTextAnchor:SetOnChanged(function(point)
		setConfig('power.textAnchor', point)
	end)
	powerTextAnchor._xInput:Hide()
	powerTextAnchor._yInput:Hide()

	-- Power text offsets
	local offsetsHeading, offsetsHeadingH = Widgets.CreateHeading(inner, 'Text Offsets', 3)
	local powerOffsetX = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	powerOffsetX:SetValue(getConfig('power.textAnchorX') or 0)
	powerOffsetX:SetAfterValueChanged(function(value)
		setConfig('power.textAnchorX', value)
	end)

	local powerOffsetY = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	powerOffsetY:SetValue(getConfig('power.textAnchorY') or 0)
	powerOffsetY:SetAfterValueChanged(function(value)
		setConfig('power.textAnchorY', value)
	end)

	-- Reflow from color switch onward
	local curColorMode = getConfig('power.textColorMode') or 'white'
	local initialized = false

	local function reflowCard()
		local y = colorSwitchEndY

		if(curColorMode == 'custom') then
			powerCustomPicker:Show()
			powerCustomPicker:ClearAllPoints()
			Widgets.SetPoint(powerCustomPicker, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - colorPickerH - C.Spacing.normal
		else
			powerCustomPicker:Hide()
		end

		outlineHeading:ClearAllPoints()
		Widgets.SetPoint(outlineHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - outlineHeadingH

		powerOutline:ClearAllPoints()
		Widgets.SetPoint(powerOutline, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.DROPDOWN_H - C.Spacing.normal

		powerShadow:ClearAllPoints()
		Widgets.SetPoint(powerShadow, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.CHECK_H - C.Spacing.normal

		posHeading:ClearAllPoints()
		Widgets.SetPoint(posHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - posHeadingH

		powerTextAnchor:ClearAllPoints()
		Widgets.SetPoint(powerTextAnchor, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - 56 - C.Spacing.normal

		offsetsHeading:ClearAllPoints()
		Widgets.SetPoint(offsetsHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - offsetsHeadingH

		powerOffsetX:ClearAllPoints()
		Widgets.SetPoint(powerOffsetX, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.SLIDER_H - C.Spacing.normal

		powerOffsetY:ClearAllPoints()
		Widgets.SetPoint(powerOffsetY, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.SLIDER_H - C.Spacing.normal

		Widgets.EndCard(card, parent, y)
		if(initialized and onResize) then onResize() end
	end

	powerColorSwitch:SetOnSelect(function(value)
		curColorMode = value
		setConfig('power.textColorMode', value)
		reflowCard()
	end)

	reflowCard()
	initialized = true

	return card
end
