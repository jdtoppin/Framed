local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}


function F.SettingsCards.CastBar(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local showCastCheck = Widgets.CreateCheckButton(inner, 'Show Cast Bar', function(checked)
		setConfig('showCastBar', checked)
	end)
	showCastCheck:SetChecked(getConfig('showCastBar') ~= false)
	cardY = B.PlaceWidget(showCastCheck, inner, cardY, B.CHECK_H)

	-- Size mode: attached (syncs width with parent frame) or detached (own dimensions)
	cardY = B.PlaceHeading(inner, 'Size', 4, cardY)
	local castSizeSwitch = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
		{ text = 'Attached', value = 'attached' },
		{ text = 'Detached', value = 'detached' },
	})
	castSizeSwitch:SetValue(getConfig('castbar.sizeMode') or 'attached')
	cardY = B.PlaceWidget(castSizeSwitch, inner, cardY, B.SWITCH_H)

	local castSizeSwitchEndY = cardY

	-- Detached width slider
	local castWidthSlider = Widgets.CreateSlider(inner, 'Width', widgetW, 50, 400, 1)
	castWidthSlider:SetValue(getConfig('castbar.width') or getConfig('width') or 192)
	castWidthSlider:SetAfterValueChanged(function(value)
		setConfig('castbar.width', value)
	end)

	-- Height slider (shown in both modes)
	local castHeightSlider = Widgets.CreateSlider(inner, 'Height', widgetW, 4, 40, 1)
	castHeightSlider:SetValue(getConfig('castbar.height') or 16)
	castHeightSlider:SetAfterValueChanged(function(value)
		setConfig('castbar.height', value)
	end)

	-- Background heading + switch (created here, positioned by reflow)
	local castBgHeading, castBgHeadingH = Widgets.CreateHeading(inner, 'Background', 4)
	local castBgSwitch = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
		{ text = 'Always',  value = 'always' },
		{ text = 'On Cast', value = 'oncast' },
	})
	castBgSwitch:SetValue(getConfig('castbar.backgroundMode') or 'always')
	castBgSwitch:SetOnSelect(function(value)
		setConfig('castbar.backgroundMode', value)
	end)

	-- Reflow based on size mode
	local curCastSizeMode = getConfig('castbar.sizeMode') or 'attached'
	local initialized = false

	local function reflowCastSize()
		local y = castSizeSwitchEndY
		if(curCastSizeMode == 'detached') then
			castWidthSlider:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, y)
			castWidthSlider:Show()
			y = y - B.SLIDER_H - C.Spacing.normal
		else
			castWidthSlider:Hide()
		end
		castHeightSlider:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, y)
		castHeightSlider:Show()
		y = y - B.SLIDER_H - C.Spacing.normal
		-- Background heading
		castBgHeading:ClearAllPoints()
		Widgets.SetPoint(castBgHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - castBgHeadingH
		-- Background switch
		castBgSwitch:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.SWITCH_H - C.Spacing.normal
		cardY = y

		Widgets.EndCard(card, parent, cardY)
		if(initialized and onResize) then onResize() end
	end

	reflowCastSize()
	initialized = true

	castSizeSwitch:SetOnSelect(function(value)
		curCastSizeMode = value
		setConfig('castbar.sizeMode', value)
		reflowCastSize()
	end)

	return card
end
