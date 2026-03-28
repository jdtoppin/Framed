local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}


function F.SettingsCards.Name(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - Widgets.CARD_PADDING * 2, B.WIDGET_W)

	local showNameCheck = Widgets.CreateCheckButton(inner, 'Show Name', function(checked)
		setConfig('showName', checked)
	end)
	showNameCheck:SetChecked(getConfig('showName') ~= false)
	cardY = B.PlaceWidget(showNameCheck, inner, cardY, B.CHECK_H)

	-- Name color mode switch
	cardY = B.PlaceHeading(inner, 'Name Color', 3, cardY)
	local nameColorSwitch = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
		{ text = 'Class',  value = 'class' },
		{ text = 'Dark',   value = 'dark' },
		{ text = 'White',  value = 'white' },
		{ text = 'Custom', value = 'custom' },
	})
	nameColorSwitch:SetValue(getConfig('name.colorMode') or 'class')
	cardY = B.PlaceWidget(nameColorSwitch, inner, cardY, B.SWITCH_H)

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
	nameFontSize:SetValue(getConfig('name.fontSize') or C.Font.sizeNormal)
	Widgets.SetTooltip(nameFontSize, 'Name Font Size', 'Override the global font size for name text')
	nameFontSize:SetAfterValueChanged(function(value)
		setConfig('name.fontSize', value)
	end)

	-- Name outline
	local outlineHeading, outlineHeadingH = Widgets.CreateHeading(inner, 'Outline', 3)
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

	-- Name text position anchor (created here, positioned by reflow)
	local posHeading, posHeadingH = Widgets.CreateHeading(inner, 'Text Position', 3)
	local nameAnchor = Widgets.CreateAnchorPicker(inner, widgetW)
	local savedNameAnchor = getConfig('name.anchor') or 'CENTER'
	nameAnchor:SetAnchor(savedNameAnchor, 0, 0)
	nameAnchor:SetOnChanged(function(point)
		setConfig('name.anchor', point)
	end)
	nameAnchor._xInput:Hide()
	nameAnchor._yInput:Hide()

	-- Name text offsets (created here, positioned by reflow)
	local offsetsHeading, offsetsHeadingH = Widgets.CreateHeading(inner, 'Text Offsets', 3)
	local nameOffsetX = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	nameOffsetX:SetValue(getConfig('name.anchorX') or 0)
	nameOffsetX:SetAfterValueChanged(function(value)
		setConfig('name.anchorX', value)
	end)

	local nameOffsetY = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	nameOffsetY:SetValue(getConfig('name.anchorY') or 0)
	nameOffsetY:SetAfterValueChanged(function(value)
		setConfig('name.anchorY', value)
	end)

	-- Reflow ALL widgets based on color mode
	local curNameColorMode = getConfig('name.colorMode') or 'class'
	local initialized = false

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
		y = y - B.SLIDER_H - C.Spacing.normal

		outlineHeading:ClearAllPoints()
		Widgets.SetPoint(outlineHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - outlineHeadingH

		nameOutline:ClearAllPoints()
		Widgets.SetPoint(nameOutline, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.DROPDOWN_H - C.Spacing.normal

		nameShadow:ClearAllPoints()
		Widgets.SetPoint(nameShadow, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.CHECK_H - C.Spacing.normal

		-- Text Position
		posHeading:ClearAllPoints()
		Widgets.SetPoint(posHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - posHeadingH

		nameAnchor:ClearAllPoints()
		Widgets.SetPoint(nameAnchor, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - 56 - C.Spacing.normal

		-- Text Offsets
		offsetsHeading:ClearAllPoints()
		Widgets.SetPoint(offsetsHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - offsetsHeadingH

		nameOffsetX:ClearAllPoints()
		Widgets.SetPoint(nameOffsetX, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.SLIDER_H - C.Spacing.normal

		nameOffsetY:ClearAllPoints()
		Widgets.SetPoint(nameOffsetY, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.SLIDER_H - C.Spacing.normal

		Widgets.EndCard(card, parent, y)
		if(initialized and onResize) then onResize() end
	end

	nameColorSwitch:SetOnSelect(function(value)
		curNameColorMode = value
		setConfig('name.colorMode', value)
		reflowNameCard()
	end)

	reflowNameCard()
	initialized = true

	return card
end
