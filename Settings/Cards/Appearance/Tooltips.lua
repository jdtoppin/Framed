local _, Framed = ...
local F = Framed
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local FRAME_ANCHORS = {
	{ text = 'Right',  value = 'RIGHT' },
	{ text = 'Left',   value = 'LEFT' },
	{ text = 'Top',    value = 'TOP' },
	{ text = 'Bottom', value = 'BOTTOM' },
}

local SCREEN_ANCHORS = {
	{ text = 'Bottom Right', value = 'BOTTOMRIGHT' },
	{ text = 'Bottom Left',  value = 'BOTTOMLEFT' },
	{ text = 'Top Right',    value = 'TOPRIGHT' },
	{ text = 'Top Left',     value = 'TOPLEFT' },
}


function F.AppearanceCards.Tooltips(parent, width, getConfig, setConfig, fireChange, onResize)
	local card, inner = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- Show Tooltips
	local ttEnabled = Widgets.CreateCheckButton(inner, 'Show Tooltips', function(checked)
		setConfig('tooltipEnabled', checked)
		fireChange()
	end)
	ttEnabled:SetChecked(getConfig('tooltipEnabled') ~= false)

	-- Hide in Combat
	local ttCombat = Widgets.CreateCheckButton(inner, 'Hide in Combat', function(checked)
		setConfig('tooltipHideInCombat', checked)
		fireChange()
	end)
	ttCombat:SetChecked(getConfig('tooltipHideInCombat') == true)

	-- Handle legacy ANCHOR_* values from old config
	local currentMode = getConfig('tooltipMode')
	if(not currentMode) then
		local anchor = getConfig('tooltipAnchor') or ''
		if(anchor == 'ANCHOR_CURSOR') then
			currentMode = 'cursor'
			setConfig('tooltipMode', 'cursor')
			setConfig('tooltipAnchor', 'RIGHT')
		else
			currentMode = 'frame'
			setConfig('tooltipMode', 'frame')
			if(anchor:sub(1, 7) == 'ANCHOR_') then
				setConfig('tooltipAnchor', anchor:sub(8))
			end
		end
	end

	-- Mode dropdown (default / frame / screen / cursor)
	local ttMode = Widgets.CreateDropdown(inner, widgetW)
	ttMode:SetItems({
		{ text = 'Default',          value = 'default' },
		{ text = 'Anchor to Frame',  value = 'frame' },
		{ text = 'Anchor to Screen', value = 'screen' },
		{ text = 'Follow Cursor',    value = 'cursor' },
	})
	ttMode:SetValue(currentMode)

	-- Anchor dropdown (shown for frame and screen modes)
	local ttAnchor = Widgets.CreateDropdown(inner, widgetW)

	-- Offset sliders (shown with ttAnchor)
	local ttOffX = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	ttOffX:SetValue(getConfig('tooltipOffsetX'))
	ttOffX:SetAfterValueChanged(function(value)
		setConfig('tooltipOffsetX', value)
		fireChange()
	end)

	local ttOffY = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	ttOffY:SetValue(getConfig('tooltipOffsetY'))
	ttOffY:SetAfterValueChanged(function(value)
		setConfig('tooltipOffsetY', value)
		fireChange()
	end)

	local initialized = false

	local function reflow()
		local y = 0
		y = B.PlaceWidget(ttEnabled, inner, y, B.CHECK_H)
		y = B.PlaceWidget(ttCombat,  inner, y, B.CHECK_H)
		y = B.PlaceWidget(ttMode,    inner, y, B.DROPDOWN_H)

		local showAnchor = currentMode == 'frame' or currentMode == 'screen'
		if(showAnchor) then
			if(currentMode == 'screen') then
				ttAnchor:SetItems(SCREEN_ANCHORS)
				local anchor = getConfig('tooltipAnchor')
				if(anchor ~= 'BOTTOMRIGHT' and anchor ~= 'BOTTOMLEFT' and anchor ~= 'TOPRIGHT' and anchor ~= 'TOPLEFT') then
					anchor = 'BOTTOMRIGHT'
					setConfig('tooltipAnchor', anchor)
				end
				ttAnchor:SetValue(anchor)
			else
				ttAnchor:SetItems(FRAME_ANCHORS)
				local anchor = getConfig('tooltipAnchor')
				if(anchor ~= 'RIGHT' and anchor ~= 'LEFT' and anchor ~= 'TOP' and anchor ~= 'BOTTOM') then
					anchor = 'RIGHT'
					setConfig('tooltipAnchor', anchor)
				end
				ttAnchor:SetValue(anchor)
			end
			ttAnchor:Show()
			ttOffX:Show()
			ttOffY:Show()
			y = B.PlaceWidget(ttAnchor, inner, y, B.DROPDOWN_H)
			y = B.PlaceWidget(ttOffX,   inner, y, B.SLIDER_H)
			y = B.PlaceWidget(ttOffY,   inner, y, B.SLIDER_H)
		else
			ttAnchor:Hide()
			ttOffX:Hide()
			ttOffY:Hide()
		end

		Widgets.EndCard(card, parent, y)
		if(initialized and onResize) then onResize() end
	end

	ttAnchor:SetOnSelect(function(value)
		setConfig('tooltipAnchor', value)
		fireChange()
	end)

	ttMode:SetOnSelect(function(value)
		currentMode = value
		setConfig('tooltipMode', value)
		reflow()
		fireChange()
	end)

	reflow()
	initialized = true

	return card
end
