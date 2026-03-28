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
local placeWidget  = B.PlaceWidget
local placeHeading = B.PlaceHeading

function F.SettingsCards.Name(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local CARD_PADDING = 12
	local widgetW = width - CARD_PADDING * 2

	local showNameCheck = Widgets.CreateCheckButton(inner, 'Show Name', function(checked)
		setConfig('showName', checked)
	end)
	showNameCheck:SetChecked(getConfig('showName') ~= false)
	cardY = placeWidget(showNameCheck, inner, cardY, CHECK_H)

	-- Name color mode switch
	cardY = placeHeading(inner, 'Name Color', 3, cardY)
	local nameColorSwitch = Widgets.CreateSwitch(inner, widgetW, SWITCH_H, {
		{ text = 'Class',  value = 'class' },
		{ text = 'White',  value = 'white' },
		{ text = 'Custom', value = 'custom' },
	})
	nameColorSwitch:SetValue(getConfig('name.colorMode') or 'class')
	cardY = placeWidget(nameColorSwitch, inner, cardY, SWITCH_H)

	-- Y after the color switch -- reflow starts from here
	local nameColorSwitchEndY = cardY

	-- Custom name color picker
	local nameCustomPicker = Widgets.CreateColorPicker(inner, 'Name Color', false,
		nil,
		function(r, g, b) setConfig('name.customColor', { r, g, b }) end)
	local savedNameColor = getConfig('name.customColor') or { 1, 1, 1 }
	nameCustomPicker:SetColor(savedNameColor[1], savedNameColor[2], savedNameColor[3], 1)
	local nameCustomPickerH = 22

	-- Name font size
	local nameFontSize = Widgets.CreateSlider(inner, 'Font Size', widgetW, 6, 24, 1)
	nameFontSize:SetValue(getConfig('name.fontSize') or 0)
	Widgets.SetTooltip(nameFontSize, 'Name Font Size', 'Override the global font size for name text')
	nameFontSize:SetAfterValueChanged(function(value)
		setConfig('name.fontSize', value)
	end)

	-- Name outline
	local nameOutline = Widgets.CreateDropdown(inner, widgetW)
	nameOutline:SetItems({
		{ text = 'None',       value = '' },
		{ text = 'Outline',    value = 'OUTLINE' },
		{ text = 'Monochrome', value = 'MONOCHROME' },
	})
	nameOutline:SetValue(getConfig('name.outline') or '')
	nameOutline:SetOnSelect(function(value)
		setConfig('name.outline', value)
	end)

	-- Name shadow
	local nameShadow = Widgets.CreateCheckButton(inner, 'Text Shadow', function(checked)
		setConfig('name.shadow', checked)
	end)
	nameShadow:SetChecked(getConfig('name.shadow') ~= false)

	-- Reflow name card widgets based on color mode
	local curNameColorMode = getConfig('name.colorMode') or 'class'

	local function reflowNameCard()
		local y = nameColorSwitchEndY

		if(curNameColorMode == 'custom') then
			nameCustomPicker:Show()
			nameCustomPicker:ClearAllPoints()
			Widgets.SetPoint(nameCustomPicker, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - nameCustomPickerH - C.Spacing.normal
		else
			nameCustomPicker:Hide()
		end

		nameFontSize:ClearAllPoints()
		Widgets.SetPoint(nameFontSize, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - SLIDER_H - C.Spacing.normal

		nameOutline:ClearAllPoints()
		Widgets.SetPoint(nameOutline, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - DROPDOWN_H - C.Spacing.normal

		nameShadow:ClearAllPoints()
		Widgets.SetPoint(nameShadow, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - CHECK_H - C.Spacing.normal

		return y
	end

	nameColorSwitch:SetOnSelect(function(value)
		curNameColorMode = value
		setConfig('name.colorMode', value)
		reflowNameCard()
		if(onResize) then onResize() end
	end)

	cardY = reflowNameCard()

	-- Name text position anchor
	cardY = placeHeading(inner, 'Text Position', 3, cardY)
	local nameAnchor = Widgets.CreateAnchorPicker(inner, widgetW)
	local savedNameAnchor = getConfig('name.anchor') or 'CENTER'
	nameAnchor:SetAnchor(savedNameAnchor, 0, 0)
	nameAnchor:SetOnChanged(function(point)
		setConfig('name.anchor', point)
	end)
	nameAnchor._xInput:Hide()
	nameAnchor._yInput:Hide()
	cardY = placeWidget(nameAnchor, inner, cardY, 56)

	-- Name text offsets
	cardY = placeHeading(inner, 'Text Offsets', 3, cardY)
	local nameOffsetX = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	nameOffsetX:SetValue(getConfig('name.anchorX') or 0)
	nameOffsetX:SetAfterValueChanged(function(value)
		setConfig('name.anchorX', value)
	end)
	cardY = placeWidget(nameOffsetX, inner, cardY, SLIDER_H)

	local nameOffsetY = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	nameOffsetY:SetValue(getConfig('name.anchorY') or 0)
	nameOffsetY:SetAfterValueChanged(function(value)
		setConfig('name.anchorY', value)
	end)
	cardY = placeWidget(nameOffsetY, inner, cardY, SLIDER_H)

	Widgets.EndCard(card, parent, cardY)
	card:ClearAllPoints()
	card._startY = 0
	return card
end
