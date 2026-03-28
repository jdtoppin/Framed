local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}


function F.SettingsCards.HealthText(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = math.min(width - Widgets.CARD_PADDING * 2, B.WIDGET_W)

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
		{ text = 'None',         value = 'none' },
	})
	healthFormatDropdown:SetValue(getConfig('health.textFormat') or 'none')
	healthFormatDropdown:SetOnSelect(function(value)
		setConfig('health.textFormat', value)
	end)
	cardY = B.PlaceWidget(healthFormatDropdown, inner, cardY, B.DROPDOWN_H)

	-- Health text font size
	local healthFontSize = Widgets.CreateSlider(inner, 'Font Size', widgetW, 6, 24, 1)
	healthFontSize:SetValue(getConfig('health.fontSize') or 0)
	Widgets.SetTooltip(healthFontSize, 'Health Text Font Size', 'Override the global font size for health text')
	healthFontSize:SetAfterValueChanged(function(value)
		setConfig('health.fontSize', value)
	end)
	cardY = B.PlaceWidget(healthFontSize, inner, cardY, B.SLIDER_H)

	-- Health text outline
	cardY = B.PlaceHeading(inner, 'Outline', 3, cardY)
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
	cardY = B.PlaceWidget(healthOutline, inner, cardY, B.DROPDOWN_H)

	-- Health text shadow
	local healthShadow = Widgets.CreateCheckButton(inner, 'Text Shadow', function(checked)
		setConfig('health.shadow', checked)
	end)
	healthShadow:SetChecked(getConfig('health.shadow') ~= false)
	cardY = B.PlaceWidget(healthShadow, inner, cardY, B.CHECK_H)

	-- Health text position anchor
	cardY = B.PlaceHeading(inner, 'Text Position', 3, cardY)
	local healthTextAnchor = Widgets.CreateAnchorPicker(inner, widgetW)
	local savedHealthAnchor = getConfig('health.textAnchor') or 'CENTER'
	healthTextAnchor:SetAnchor(savedHealthAnchor, 0, 0)
	healthTextAnchor:SetOnChanged(function(point)
		setConfig('health.textAnchor', point)
	end)
	healthTextAnchor._xInput:Hide()
	healthTextAnchor._yInput:Hide()
	cardY = B.PlaceWidget(healthTextAnchor, inner, cardY, 56)

	-- Health text offsets
	cardY = B.PlaceHeading(inner, 'Text Offsets', 3, cardY)
	local healthOffsetX = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	healthOffsetX:SetValue(getConfig('health.textAnchorX') or 0)
	healthOffsetX:SetAfterValueChanged(function(value)
		setConfig('health.textAnchorX', value)
	end)
	cardY = B.PlaceWidget(healthOffsetX, inner, cardY, B.SLIDER_H)

	local healthOffsetY = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	healthOffsetY:SetValue(getConfig('health.textAnchorY') or 0)
	healthOffsetY:SetAfterValueChanged(function(value)
		setConfig('health.textAnchorY', value)
	end)
	cardY = B.PlaceWidget(healthOffsetY, inner, cardY, B.SLIDER_H)

	-- Populate health position widgets for dimming control
	healthPositionWidgets[1] = healthTextAnchor
	healthPositionWidgets[2] = healthOffsetX
	healthPositionWidgets[3] = healthOffsetY
	updateHealthPositionDimming(isAttached)

	Widgets.EndCard(card, parent, cardY)
	return card
end
