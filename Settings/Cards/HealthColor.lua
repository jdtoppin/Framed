local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}


function F.SettingsCards.HealthColor(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- ── Portrait toggle ─────────────────────────────────────
	cardY = B.PlaceHeading(inner, 'Portrait', 3, cardY)

	local portraitStyle = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
		{ text = '2D', value = '2D' },
		{ text = '3D', value = '3D' },
	})

	local savedPortrait = getConfig('portrait')
	local portraitEnabled = savedPortrait and true or false
	local portraitType = (type(savedPortrait) == 'table' and savedPortrait.type) or '2D'

	local reflowRef = {}
	local portraitCheck = Widgets.CreateCheckButton(inner, 'Show Portrait', function(checked)
		if(checked) then
			setConfig('portrait', { type = portraitStyle:GetValue() or '2D' })
		else
			setConfig('portrait', nil)
		end
		if(reflowRef[1]) then reflowRef[1]() end
	end)
	portraitCheck:SetChecked(portraitEnabled)
	cardY = B.PlaceWidget(portraitCheck, inner, cardY, B.CHECK_H)

	portraitStyle:SetValue(portraitType)
	if(not portraitEnabled) then portraitStyle:Hide() end

	-- Y after portrait checkbox — reflow starts here
	local portraitCheckEndY = cardY

	-- Health color mode heading + switch (created here, positioned by reflow)
	local colorModeHeading, colorModeHeadingH = Widgets.CreateHeading(inner, 'Color Mode', 4)
	local healthColorSwitch = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
		{ text = 'Class',    value = 'class' },
		{ text = 'Dark',     value = 'dark' },
		{ text = 'Gradient', value = 'gradient' },
		{ text = 'Custom',   value = 'custom' },
	})
	healthColorSwitch:SetValue(getConfig('health.colorMode'))

	-- ── Helper: build a gradient section (3 color pickers + threshold sliders) ──
	local function buildGradientSection(gradParent, prefix, defaults)
		local section = CreateFrame('Frame', nil, gradParent)
		section:SetWidth(widgetW)

		local sY = 0

		for _, row in next, defaults do
			local colorKey = prefix .. row.colorKey
			local thresholdKey = prefix .. row.thresholdKey
			local picker = Widgets.CreateColorPicker(section, row.label, false,
				nil,
				function(r, g, b) setConfig(colorKey, { r, g, b }) end)
			picker:SetPoint('TOPLEFT', section, 'TOPLEFT', 0, sY)
			local saved = getConfig(colorKey)
			picker:SetColor(saved[1], saved[2], saved[3], 1)

			local pctSlider = Widgets.CreateSlider(section, '% Threshold', widgetW - 30, 0, 100, 5)
			pctSlider:SetValue(getConfig(thresholdKey))
			pctSlider:SetAfterValueChanged(function(value)
				setConfig(thresholdKey, value)
			end)
			pctSlider:SetPoint('TOPLEFT', section, 'TOPLEFT', 0, sY - 22)
			sY = sY - 22 - B.SLIDER_H - C.Spacing.normal
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
	local savedCustom = getConfig('health.customColor')
	customPicker:SetColor(savedCustom[1], savedCustom[2], savedCustom[3], 1)
	local customPickerH = 22

	-- ── Smooth bars checkbox ──
	local smoothCheck = Widgets.CreateCheckButton(inner, 'Smooth Bars', function(checked)
		setConfig('health.smooth', checked)
	end)
	smoothCheck:SetChecked(getConfig('health.smooth') ~= false)

	-- ── Health Loss Color heading ──
	local lossHeading, lossHeadingH = Widgets.CreateHeading(inner, 'Health Loss Color', 4)

	-- ── Loss color mode switch ──
	local lossColorSwitch = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
		{ text = 'Class',    value = 'class' },
		{ text = 'Dark',     value = 'dark' },
		{ text = 'Gradient', value = 'gradient' },
		{ text = 'Custom',   value = 'custom' },
	})
	lossColorSwitch:SetValue(getConfig('health.lossColorMode'))

	-- ── Loss gradient section ──
	local lossGradientSection, lossGradientSectionH = buildGradientSection(inner, 'health.', LOSS_GRADIENT_ROWS)

	-- ── Loss custom picker ──
	local lossPicker = Widgets.CreateColorPicker(inner, 'Loss Color', false,
		nil,
		function(r, g, b) setConfig('health.lossCustomColor', { r, g, b }) end)
	local savedLoss = getConfig('health.lossCustomColor')
	lossPicker:SetColor(savedLoss[1], savedLoss[2], savedLoss[3], 1)
	local lossPickerH = 22

	-- ── Reflow: position all widgets inside the card based on current modes ──
	local curHealthMode = getConfig('health.colorMode')
	local curLossMode = getConfig('health.lossColorMode')
	local initialized = false

	local function reflowColorCard()
		local y = portraitCheckEndY

		-- Portrait style switch
		if(portraitCheck:GetChecked()) then
			portraitStyle:Show()
			portraitStyle:ClearAllPoints()
			Widgets.SetPoint(portraitStyle, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - B.SWITCH_H - C.Spacing.normal
		else
			portraitStyle:Hide()
		end

		-- Color mode heading + switch
		colorModeHeading:ClearAllPoints()
		Widgets.SetPoint(colorModeHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - colorModeHeadingH

		healthColorSwitch:ClearAllPoints()
		Widgets.SetPoint(healthColorSwitch, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.SWITCH_H - C.Spacing.normal

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
		y = y - B.CHECK_H - C.Spacing.normal

		-- Loss heading
		lossHeading:ClearAllPoints()
		Widgets.SetPoint(lossHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - lossHeadingH

		-- Loss switch
		lossColorSwitch:ClearAllPoints()
		Widgets.SetPoint(lossColorSwitch, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.SWITCH_H - C.Spacing.normal

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

		Widgets.EndCard(card, parent, y)
		if(initialized and onResize) then onResize() end
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

	-- Wire up portrait style select
	portraitStyle:SetOnSelect(function(value)
		setConfig('portrait', { type = value })
	end)

	-- Set reflow reference for portrait checkbox
	reflowRef[1] = reflowColorCard

	-- Initial reflow (without triggering grid re-layout)
	reflowColorCard()
	initialized = true

	return card
end
