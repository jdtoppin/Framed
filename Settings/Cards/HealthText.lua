local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}


function F.SettingsCards.HealthText(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- Attach to Name toggle
	local healthPositionWidgets = {}
	local function updateHealthPositionDimming(attached)
		local alpha = attached and 0.35 or 1
		for _, w in next, healthPositionWidgets do
			w:SetAlpha(alpha)
			if(attached) then
				w:EnableMouse(false)
			else
				w:EnableMouse(true)
			end
		end
	end

	local isAttached = getConfig('health.attachedToName') or false
	local attachToNameCheck = Widgets.CreateCheckButton(inner, 'Attach to Name', function(checked)
		setConfig('health.attachedToName', checked)
		updateHealthPositionDimming(checked)
	end)
	attachToNameCheck:SetChecked(isAttached)
	cardY = B.PlaceWidget(attachToNameCheck, inner, cardY, B.CHECK_H)

	local showHealthTextCheck = Widgets.CreateCheckButton(inner, 'Show Health Text', function(checked)
		setConfig('health.showText', checked)
	end)
	showHealthTextCheck:SetChecked(getConfig('health.showText') or false)
	cardY = B.PlaceWidget(showHealthTextCheck, inner, cardY, B.CHECK_H)

	-- Health text format dropdown
	cardY = B.PlaceHeading(inner, 'Health Text Format', 3, cardY)
	local healthFormatDropdown = Widgets.CreateDropdown(inner, widgetW)
	healthFormatDropdown:SetItems({
		{ text = 'Percentage',   value = 'percent' },
		{ text = 'Current',      value = 'current' },
		{ text = 'Deficit',      value = 'deficit' },
		{ text = 'Current-Max',  value = 'currentMax' },
	})
	healthFormatDropdown:SetValue(getConfig('health.textFormat') or 'percent')
	healthFormatDropdown:SetOnSelect(function(value)
		setConfig('health.textFormat', value)
	end)
	cardY = B.PlaceWidget(healthFormatDropdown, inner, cardY, B.DROPDOWN_H)

	-- Health text font size
	local healthFontSize = Widgets.CreateSlider(inner, 'Font Size', widgetW, 6, 24, 1)
	healthFontSize:SetValue(getConfig('health.fontSize') or C.Font.sizeSmall)
	Widgets.SetTooltip(healthFontSize, 'Health Text Font Size', 'Override the global font size for health text')
	healthFontSize:SetAfterValueChanged(function(value)
		setConfig('health.fontSize', value)
	end)
	cardY = B.PlaceWidget(healthFontSize, inner, cardY, B.SLIDER_H)

	-- Health text color mode
	cardY = B.PlaceHeading(inner, 'Text Color', 3, cardY)
	local healthColorSwitch = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
		{ text = 'Class',  value = 'class' },
		{ text = 'Dark',   value = 'dark' },
		{ text = 'White',  value = 'white' },
		{ text = 'Custom', value = 'custom' },
	})
	healthColorSwitch:SetValue(getConfig('health.textColorMode') or 'white')
	cardY = B.PlaceWidget(healthColorSwitch, inner, cardY, B.SWITCH_H)

	local colorSwitchEndY = cardY

	-- Custom color picker (shown only in custom mode)
	local healthCustomPicker = Widgets.CreateColorPicker(inner, 'Text Color', false,
		nil,
		function(r, g, b) setConfig('health.textCustomColor', { r, g, b }) end)
	local savedTextColor = getConfig('health.textCustomColor') or { 1, 1, 1 }
	healthCustomPicker:SetColor(savedTextColor[1], savedTextColor[2], savedTextColor[3], 1)
	local colorPickerH = 22

	-- Health text outline
	local outlineHeading, outlineHeadingH = Widgets.CreateHeading(inner, 'Outline', 3)
	local healthOutline = Widgets.CreateDropdown(inner, widgetW)
	healthOutline:SetItems({
		{ text = 'None',       value = '' },
		{ text = 'Outline',    value = 'OUTLINE' },
		{ text = 'Monochrome', value = 'MONOCHROME' },
	})
	healthOutline:SetValue(getConfig('health.outline') or '')
	healthOutline:SetOnSelect(function(value)
		setConfig('health.outline', value)
	end)

	-- Health text shadow
	local healthShadow = Widgets.CreateCheckButton(inner, 'Text Shadow', function(checked)
		setConfig('health.shadow', checked)
	end)
	healthShadow:SetChecked(getConfig('health.shadow') ~= false)

	-- Health text position anchor
	local posHeading, posHeadingH = Widgets.CreateHeading(inner, 'Text Position', 3)
	local healthTextAnchor = Widgets.CreateAnchorPicker(inner, widgetW)
	local savedHealthAnchor = getConfig('health.textAnchor') or 'CENTER'
	healthTextAnchor:SetAnchor(savedHealthAnchor, 0, 0)
	healthTextAnchor:SetOnChanged(function(point)
		setConfig('health.textAnchor', point)
	end)
	healthTextAnchor._xSlider:Hide()
	healthTextAnchor._ySlider:Hide()

	-- Health text offsets
	local offsetsHeading, offsetsHeadingH = Widgets.CreateHeading(inner, 'Text Offsets', 3)
	local healthOffsetX = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	healthOffsetX:SetValue(getConfig('health.textAnchorX') or 0)
	healthOffsetX:SetAfterValueChanged(function(value)
		setConfig('health.textAnchorX', value)
	end)

	local healthOffsetY = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	healthOffsetY:SetValue(getConfig('health.textAnchorY') or 0)
	healthOffsetY:SetAfterValueChanged(function(value)
		setConfig('health.textAnchorY', value)
	end)

	-- Populate health position widgets for dimming control
	healthPositionWidgets[1] = healthTextAnchor
	healthPositionWidgets[2] = healthOffsetX
	healthPositionWidgets[3] = healthOffsetY

	-- Reflow from color switch onward
	local curColorMode = getConfig('health.textColorMode') or 'white'
	local initialized = false

	local function reflowCard()
		local y = colorSwitchEndY

		if(curColorMode == 'custom') then
			healthCustomPicker:Show()
			healthCustomPicker:ClearAllPoints()
			Widgets.SetPoint(healthCustomPicker, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - colorPickerH - C.Spacing.normal
		else
			healthCustomPicker:Hide()
		end

		outlineHeading:ClearAllPoints()
		Widgets.SetPoint(outlineHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - outlineHeadingH

		healthOutline:ClearAllPoints()
		Widgets.SetPoint(healthOutline, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.DROPDOWN_H - C.Spacing.normal

		healthShadow:ClearAllPoints()
		Widgets.SetPoint(healthShadow, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.CHECK_H - C.Spacing.normal

		posHeading:ClearAllPoints()
		Widgets.SetPoint(posHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - posHeadingH

		healthTextAnchor:ClearAllPoints()
		Widgets.SetPoint(healthTextAnchor, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - 56 - C.Spacing.normal

		offsetsHeading:ClearAllPoints()
		Widgets.SetPoint(offsetsHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - offsetsHeadingH

		healthOffsetX:ClearAllPoints()
		Widgets.SetPoint(healthOffsetX, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.SLIDER_H - C.Spacing.normal

		healthOffsetY:ClearAllPoints()
		Widgets.SetPoint(healthOffsetY, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.SLIDER_H - C.Spacing.normal

		Widgets.EndCard(card, parent, y)
		if(initialized and onResize) then onResize() end
	end

	healthColorSwitch:SetOnSelect(function(value)
		curColorMode = value
		setConfig('health.textColorMode', value)
		reflowCard()
	end)

	updateHealthPositionDimming(isAttached)
	reflowCard()
	initialized = true

	return card
end
