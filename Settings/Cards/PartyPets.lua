local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}

-- ============================================================
-- Party Pets card — show/hide toggle + health text options
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
	spacingSlider:SetValue(getPetConfig('spacing') or 2)
	spacingSlider:SetAfterValueChanged(function(value)
		setPetConfig('spacing', value)
	end)
	cardY = B.PlaceWidget(spacingSlider, inner, cardY, B.SLIDER_H)

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
	formatDropdown:SetValue(getPetConfig('healthTextFormat') or 'percent')
	formatDropdown:SetOnSelect(function(value)
		setPetConfig('healthTextFormat', value)
	end)
	cardY = B.PlaceWidget(formatDropdown, inner, cardY, B.DROPDOWN_H)

	-- Font size slider
	local fontSizeSlider = Widgets.CreateSlider(inner, 'Font Size', widgetW, 6, 24, 1)
	fontSizeSlider:SetValue(getPetConfig('healthTextFontSize') or C.Font.sizeSmall)
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
	colorDropdown:SetValue(getPetConfig('healthTextColor') or 'white')
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
	outlineDropdown:SetValue(getPetConfig('healthTextOutline') or '')
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

	-- X offset slider
	local xOffSlider = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	xOffSlider:SetValue(getPetConfig('healthTextOffsetX') or 0)
	xOffSlider:SetAfterValueChanged(function(value)
		setPetConfig('healthTextOffsetX', value)
	end)
	cardY = B.PlaceWidget(xOffSlider, inner, cardY, B.SLIDER_H)

	-- Y offset slider
	local yOffSlider = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	yOffSlider:SetValue(getPetConfig('healthTextOffsetY') or 2)
	yOffSlider:SetAfterValueChanged(function(value)
		setPetConfig('healthTextOffsetY', value)
	end)
	cardY = B.PlaceWidget(yOffSlider, inner, cardY, B.SLIDER_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
