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

function F.SettingsCards.HealthColor(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local CARD_PADDING = 12  -- must match Widgets.Frame CARD_PADDING

	-- Health color mode switch
	cardY = placeHeading(inner, 'Color Mode', 3, cardY)
	local healthColorSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
		{ text = 'Class',    value = 'class' },
		{ text = 'Dark',     value = 'dark' },
		{ text = 'Gradient', value = 'gradient' },
		{ text = 'Custom',   value = 'custom' },
	})
	healthColorSwitch:SetValue(getConfig('health.colorMode') or 'class')
	cardY = placeWidget(healthColorSwitch, inner, cardY, SWITCH_H)

	-- Y after the mode switch -- reflow starts from here
	local colorSwitchEndY = cardY

	-- ── Helper: build a gradient section (3 color pickers + threshold sliders) ──
	local function buildGradientSection(gradParent, prefix, defaults)
		local section = CreateFrame('Frame', nil, gradParent)
		section:SetWidth(WIDGET_W)

		local sY = 0

		for _, row in next, defaults do
			local colorKey = prefix .. row.colorKey
			local thresholdKey = prefix .. row.thresholdKey
			local picker = Widgets.CreateColorPicker(section, row.label, false,
				nil,
				function(r, g, b) setConfig(colorKey, { r, g, b }) end)
			picker:SetPoint('TOPLEFT', section, 'TOPLEFT', 0, sY)
			local saved = getConfig(colorKey) or row.color
			picker:SetColor(saved[1], saved[2], saved[3], 1)

			local pctSlider = Widgets.CreateSlider(section, '% Threshold', WIDGET_W - 30, 0, 100, 5)
			pctSlider:SetValue(getConfig(thresholdKey) or row.pct)
			pctSlider:SetAfterValueChanged(function(value)
				setConfig(thresholdKey, value)
			end)
			pctSlider:SetPoint('TOPLEFT', section, 'TOPLEFT', 0, sY - 22)
			sY = sY - 22 - SLIDER_H - C.Spacing.normal
		end

		local h = math.abs(sY)
		section:SetHeight(h)
		return section, h
	end

	local GRADIENT_ROWS = {
		{ label = 'Healthy',  colorKey = 'gradientColor1', thresholdKey = 'gradientThreshold1', color = { 0.2, 0.8, 0.2 }, pct = 95 },
		{ label = 'Warning',  colorKey = 'gradientColor2', thresholdKey = 'gradientThreshold2', color = { 0.9, 0.6, 0.1 }, pct = 50 },
		{ label = 'Critical', colorKey = 'gradientColor3', thresholdKey = 'gradientThreshold3', color = { 0.8, 0.1, 0.1 }, pct = 5 },
	}

	local LOSS_GRADIENT_ROWS = {
		{ label = 'Healthy',  colorKey = 'lossGradientColor1', thresholdKey = 'lossGradientThreshold1', color = { 0.1, 0.4, 0.1 }, pct = 95 },
		{ label = 'Warning',  colorKey = 'lossGradientColor2', thresholdKey = 'lossGradientThreshold2', color = { 0.4, 0.25, 0.05 }, pct = 50 },
		{ label = 'Critical', colorKey = 'lossGradientColor3', thresholdKey = 'lossGradientThreshold3', color = { 0.4, 0.05, 0.05 }, pct = 5 },
	}

	-- ── Health gradient section ──
	local gradientSection, gradientSectionH = buildGradientSection(inner, 'health.', GRADIENT_ROWS)

	-- ── Health custom picker ──
	local customPicker = Widgets.CreateColorPicker(inner, 'Health Bar Color', false,
		nil,
		function(r, g, b) setConfig('health.customColor', { r, g, b }) end)
	local savedCustom = getConfig('health.customColor') or { 0.2, 0.8, 0.2 }
	customPicker:SetColor(savedCustom[1], savedCustom[2], savedCustom[3], 1)
	local customPickerH = 22

	-- ── Smooth bars checkbox ──
	local smoothCheck = Widgets.CreateCheckButton(inner, 'Smooth Bars', function(checked)
		setConfig('health.smooth', checked)
	end)
	smoothCheck:SetChecked(getConfig('health.smooth') ~= false)

	-- ── Health Loss Color heading ──
	local lossHeading, lossHeadingH = Widgets.CreateHeading(inner, 'Health Loss Color', 3)

	-- ── Loss color mode switch ──
	local lossColorSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
		{ text = 'Class',    value = 'class' },
		{ text = 'Dark',     value = 'dark' },
		{ text = 'Gradient', value = 'gradient' },
		{ text = 'Custom',   value = 'custom' },
	})
	lossColorSwitch:SetValue(getConfig('health.lossColorMode') or 'dark')

	-- ── Loss gradient section ──
	local lossGradientSection, lossGradientSectionH = buildGradientSection(inner, 'health.', LOSS_GRADIENT_ROWS)

	-- ── Loss custom picker ──
	local lossPicker = Widgets.CreateColorPicker(inner, 'Loss Color', false,
		nil,
		function(r, g, b) setConfig('health.lossCustomColor', { r, g, b }) end)
	local savedLoss = getConfig('health.lossCustomColor') or { 0.15, 0.15, 0.15 }
	lossPicker:SetColor(savedLoss[1], savedLoss[2], savedLoss[3], 1)
	local lossPickerH = 22

	-- ── Reflow: position all widgets inside the card based on current modes ──
	local curHealthMode = getConfig('health.colorMode') or 'class'
	local curLossMode = getConfig('health.lossColorMode') or 'dark'

	local function reflowColorCard()
		local y = colorSwitchEndY

		-- Health gradient section
		if(curHealthMode == 'gradient') then
			gradientSection:Show()
			gradientSection:ClearAllPoints()
			Widgets.SetPoint(gradientSection, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - gradientSectionH
		else
			gradientSection:Hide()
		end

		-- Health custom picker
		if(curHealthMode == 'custom') then
			customPicker:Show()
			customPicker:ClearAllPoints()
			Widgets.SetPoint(customPicker, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - customPickerH - C.Spacing.normal
		else
			customPicker:Hide()
		end

		-- Smooth bars
		smoothCheck:ClearAllPoints()
		Widgets.SetPoint(smoothCheck, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - CHECK_H - C.Spacing.normal

		-- Loss heading
		lossHeading:ClearAllPoints()
		Widgets.SetPoint(lossHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - lossHeadingH

		-- Loss switch
		lossColorSwitch:ClearAllPoints()
		Widgets.SetPoint(lossColorSwitch, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - SWITCH_H - C.Spacing.normal

		-- Loss gradient section
		if(curLossMode == 'gradient') then
			lossGradientSection:Show()
			lossGradientSection:ClearAllPoints()
			Widgets.SetPoint(lossGradientSection, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - lossGradientSectionH
		else
			lossGradientSection:Hide()
		end

		-- Loss custom picker
		if(curLossMode == 'custom') then
			lossPicker:Show()
			lossPicker:ClearAllPoints()
			Widgets.SetPoint(lossPicker, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - lossPickerH - C.Spacing.normal
		else
			lossPicker:Hide()
		end

		-- Update card height
		local innerH = math.abs(y)
		inner:SetHeight(innerH)
		card:SetHeight(innerH + CARD_PADDING * 2)

		Widgets.EndCard(card, parent, y)
		card:ClearAllPoints()
		card._startY = 0
		if(onResize) then onResize() end
	end

	healthColorSwitch:SetOnSelect(function(value)
		curHealthMode = value
		setConfig('health.colorMode', value)
		reflowColorCard()
	end)

	lossColorSwitch:SetOnSelect(function(value)
		curLossMode = value
		setConfig('health.lossColorMode', value)
		reflowColorCard()
	end)

	-- Initial reflow
	reflowColorCard()

	return card
end
