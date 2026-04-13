local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}

-- ============================================================
-- Party Pets card — show/hide toggle + name/health text options
-- Only shown in the Party Frames settings panel.
-- Config lives at presets.<name>.partyPets (not inside unitConfigs).
-- ============================================================

function F.SettingsCards.PartyPets(parent, width)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- Config accessors (partyPets is at preset level, not unitConfigs)
	local function getPresetName()
		return F.Settings.GetEditingPreset()
	end

	local function getPetConfig(key)
		local path = 'presets.' .. getPresetName() .. '.partyPets'
		if(key) then path = path .. '.' .. key end
		return F.Config:Get(path)
	end

	local function setPetConfig(key, value)
		local path = 'presets.' .. getPresetName() .. '.partyPets.' .. key
		F.Config:Set(path, value)
		F.PresetManager.MarkCustomized(getPresetName())
	end

	-- Show Party Pets toggle
	local showCheck = Widgets.CreateCheckButton(inner, 'Show Party Pets', function(checked)
		setPetConfig('enabled', checked)
	end)
	showCheck:SetChecked(getPetConfig('enabled') ~= false)
	cardY = B.PlaceWidget(showCheck, inner, cardY, B.CHECK_H)

	-- Spacing slider (gap between pet frame and owner frame)
	local spacingSlider = Widgets.CreateSlider(inner, 'Gap from Owner', widgetW, 0, 20, 1)
	spacingSlider:SetValue(getPetConfig('spacing'))
	spacingSlider:SetAfterValueChanged(function(value)
		setPetConfig('spacing', value)
	end)
	cardY = B.PlaceWidget(spacingSlider, inner, cardY, B.SLIDER_H)

	-- ── Name Text ────────────────────────────────────────────
	cardY = B.PlaceHeading(inner, 'Name Text', 4, cardY)

	-- Show Name toggle
	local showName = Widgets.CreateCheckButton(inner, 'Show Name', function(checked)
		setPetConfig('showName', checked)
	end)
	showName:SetChecked(getPetConfig('showName') ~= false)
	cardY = B.PlaceWidget(showName, inner, cardY, B.CHECK_H)

	-- Name font size slider
	local nameFontSize = Widgets.CreateSlider(inner, 'Font Size', widgetW, 6, 24, 1)
	nameFontSize:SetValue(getPetConfig('nameFontSize'))
	nameFontSize:SetAfterValueChanged(function(value)
		setPetConfig('nameFontSize', value)
	end)
	cardY = B.PlaceWidget(nameFontSize, inner, cardY, B.SLIDER_H)

	-- Name outline dropdown
	local nameOutline = Widgets.CreateDropdown(inner, widgetW)
	nameOutline:SetItems({
		{ text = 'None',       value = '' },
		{ text = 'Outline',    value = 'OUTLINE' },
		{ text = 'Monochrome', value = 'MONOCHROME' },
	})
	nameOutline:SetValue(getPetConfig('nameOutline'))
	nameOutline:SetOnSelect(function(value)
		setPetConfig('nameOutline', value)
	end)
	cardY = B.PlaceWidget(nameOutline, inner, cardY, B.DROPDOWN_H)

	-- Name shadow toggle
	local nameShadow = Widgets.CreateCheckButton(inner, 'Text Shadow', function(checked)
		setPetConfig('nameShadow', checked)
	end)
	nameShadow:SetChecked(getPetConfig('nameShadow') ~= false)
	cardY = B.PlaceWidget(nameShadow, inner, cardY, B.CHECK_H)

	-- Name anchor picker
	local nameAnchor = Widgets.CreateAnchorPicker(inner, widgetW)
	nameAnchor:SetAnchor(getPetConfig('nameAnchor') or 'TOP', 0, 0)
	nameAnchor:SetOnChanged(function(point)
		setPetConfig('nameAnchor', point)
	end)
	nameAnchor._xSlider:Hide()
	nameAnchor._ySlider:Hide()
	cardY = B.PlaceWidget(nameAnchor, inner, cardY, 56)

	-- Name X offset slider
	local nameXOff = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	nameXOff:SetValue(getPetConfig('nameOffsetX'))
	nameXOff:SetAfterValueChanged(function(value)
		setPetConfig('nameOffsetX', value)
	end)
	cardY = B.PlaceWidget(nameXOff, inner, cardY, B.SLIDER_H)

	-- Name Y offset slider
	local nameYOff = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	nameYOff:SetValue(getPetConfig('nameOffsetY'))
	nameYOff:SetAfterValueChanged(function(value)
		setPetConfig('nameOffsetY', value)
	end)
	cardY = B.PlaceWidget(nameYOff, inner, cardY, B.SLIDER_H)

	-- ── Health Text ──────────────────────────────────────────
	cardY = B.PlaceHeading(inner, 'Health Text', 4, cardY)

	-- Show Health Text toggle
	local showHealthText = Widgets.CreateCheckButton(inner, 'Show Health Text', function(checked)
		setPetConfig('showHealthText', checked)
	end)
	showHealthText:SetChecked(getPetConfig('showHealthText') ~= false)
	cardY = B.PlaceWidget(showHealthText, inner, cardY, B.CHECK_H)

	-- Health text format dropdown
	local formatDropdown = Widgets.CreateDropdown(inner, widgetW)
	formatDropdown:SetItems({
		{ text = 'Percent',       value = 'percent' },
		{ text = 'Current',       value = 'current' },
		{ text = 'Current / Max', value = 'currentMax' },
		{ text = 'Deficit',       value = 'deficit' },
	})
	formatDropdown:SetValue(getPetConfig('healthTextFormat'))
	formatDropdown:SetOnSelect(function(value)
		setPetConfig('healthTextFormat', value)
	end)
	cardY = B.PlaceWidget(formatDropdown, inner, cardY, B.DROPDOWN_H)

	-- Font size slider
	local fontSizeSlider = Widgets.CreateSlider(inner, 'Font Size', widgetW, 6, 24, 1)
	fontSizeSlider:SetValue(getPetConfig('healthTextFontSize'))
	fontSizeSlider:SetAfterValueChanged(function(value)
		setPetConfig('healthTextFontSize', value)
	end)
	cardY = B.PlaceWidget(fontSizeSlider, inner, cardY, B.SLIDER_H)

	-- Text color dropdown
	local colorDropdown = Widgets.CreateDropdown(inner, widgetW)
	colorDropdown:SetItems({
		{ text = 'White', value = 'white' },
		{ text = 'Class', value = 'class' },
	})
	colorDropdown:SetValue(getPetConfig('healthTextColor'))
	colorDropdown:SetOnSelect(function(value)
		setPetConfig('healthTextColor', value)
	end)
	cardY = B.PlaceWidget(colorDropdown, inner, cardY, B.DROPDOWN_H)

	-- Outline dropdown
	local outlineDropdown = Widgets.CreateDropdown(inner, widgetW)
	outlineDropdown:SetItems({
		{ text = 'None',       value = '' },
		{ text = 'Outline',    value = 'OUTLINE' },
		{ text = 'Monochrome', value = 'MONOCHROME' },
	})
	outlineDropdown:SetValue(getPetConfig('healthTextOutline'))
	outlineDropdown:SetOnSelect(function(value)
		setPetConfig('healthTextOutline', value)
	end)
	cardY = B.PlaceWidget(outlineDropdown, inner, cardY, B.DROPDOWN_H)

	-- Text shadow toggle
	local shadowCheck = Widgets.CreateCheckButton(inner, 'Text Shadow', function(checked)
		setPetConfig('healthTextShadow', checked)
	end)
	shadowCheck:SetChecked(getPetConfig('healthTextShadow') ~= false)
	cardY = B.PlaceWidget(shadowCheck, inner, cardY, B.CHECK_H)

	-- Health text anchor picker
	local healthAnchor = Widgets.CreateAnchorPicker(inner, widgetW)
	healthAnchor:SetAnchor(getPetConfig('healthTextAnchor') or 'CENTER', 0, 0)
	healthAnchor:SetOnChanged(function(point)
		setPetConfig('healthTextAnchor', point)
	end)
	healthAnchor._xSlider:Hide()
	healthAnchor._ySlider:Hide()
	cardY = B.PlaceWidget(healthAnchor, inner, cardY, 56)

	-- X offset slider
	local xOffSlider = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	xOffSlider:SetValue(getPetConfig('healthTextOffsetX'))
	xOffSlider:SetAfterValueChanged(function(value)
		setPetConfig('healthTextOffsetX', value)
	end)
	cardY = B.PlaceWidget(xOffSlider, inner, cardY, B.SLIDER_H)

	-- Y offset slider
	local yOffSlider = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	yOffSlider:SetValue(getPetConfig('healthTextOffsetY'))
	yOffSlider:SetAfterValueChanged(function(value)
		setPetConfig('healthTextOffsetY', value)
	end)
	cardY = B.PlaceWidget(yOffSlider, inner, cardY, B.SLIDER_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
