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


function F.AppearanceCards.Tooltips(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- Show Tooltips
	local ttEnabled = Widgets.CreateCheckButton(inner, 'Show Tooltips', function(checked)
		setConfig('tooltipEnabled', checked)
		fireChange()
	end)
	ttEnabled:SetChecked(getConfig('tooltipEnabled') ~= false)
	cardY = B.PlaceWidget(ttEnabled, inner, cardY, B.CHECK_H)

	-- Hide in Combat
	local ttCombat = Widgets.CreateCheckButton(inner, 'Hide in Combat', function(checked)
		setConfig('tooltipHideInCombat', checked)
		fireChange()
	end)
	ttCombat:SetChecked(getConfig('tooltipHideInCombat') == true)
	cardY = B.PlaceWidget(ttCombat, inner, cardY, B.CHECK_H)

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

	-- Mode dropdown (frame / screen / cursor)
	local ttMode = Widgets.CreateDropdown(inner, widgetW)
	ttMode:SetItems({
		{ text = 'Default',          value = 'default' },
		{ text = 'Anchor to Frame',  value = 'frame' },
		{ text = 'Anchor to Screen', value = 'screen' },
		{ text = 'Follow Cursor',    value = 'cursor' },
	})
	ttMode:SetValue(currentMode)
	cardY = B.PlaceWidget(ttMode, inner, cardY, B.DROPDOWN_H)

	-- Anchor dropdown (shown for frame and screen modes)
	local ttAnchor = Widgets.CreateDropdown(inner, widgetW)
	cardY = B.PlaceWidget(ttAnchor, inner, cardY, B.DROPDOWN_H)

	-- Offset sliders
	local ttOffX = Widgets.CreateSlider(inner, 'X Offset', widgetW, -50, 50, 1)
	ttOffX:SetValue(getConfig('tooltipOffsetX'))
	ttOffX:SetAfterValueChanged(function(value)
		setConfig('tooltipOffsetX', value)
		fireChange()
	end)
	cardY = B.PlaceWidget(ttOffX, inner, cardY, B.SLIDER_H)

	local ttOffY = Widgets.CreateSlider(inner, 'Y Offset', widgetW, -50, 50, 1)
	ttOffY:SetValue(getConfig('tooltipOffsetY'))
	ttOffY:SetAfterValueChanged(function(value)
		setConfig('tooltipOffsetY', value)
		fireChange()
	end)
	cardY = B.PlaceWidget(ttOffY, inner, cardY, B.SLIDER_H)

	-- Update visibility and items based on mode
	local function updateForMode(mode)
		if(mode == 'default' or mode == 'cursor') then
			ttAnchor:Hide()
			ttOffX:Hide()
			ttOffY:Hide()
		elseif(mode == 'screen') then
			ttAnchor:SetItems(SCREEN_ANCHORS)
			local anchor = getConfig('tooltipAnchor')
			if(anchor ~= 'BOTTOMRIGHT' and anchor ~= 'BOTTOMLEFT' and anchor ~= 'TOPRIGHT' and anchor ~= 'TOPLEFT') then
				anchor = 'BOTTOMRIGHT'
				setConfig('tooltipAnchor', anchor)
			end
			ttAnchor:SetValue(anchor)
			ttAnchor:Show()
			ttOffX:Show()
			ttOffY:Show()
		else
			ttAnchor:SetItems(FRAME_ANCHORS)
			local anchor = getConfig('tooltipAnchor')
			if(anchor ~= 'RIGHT' and anchor ~= 'LEFT' and anchor ~= 'TOP' and anchor ~= 'BOTTOM') then
				anchor = 'RIGHT'
				setConfig('tooltipAnchor', anchor)
			end
			ttAnchor:SetValue(anchor)
			ttAnchor:Show()
			ttOffX:Show()
			ttOffY:Show()
		end
	end

	ttAnchor:SetOnSelect(function(value)
		setConfig('tooltipAnchor', value)
		fireChange()
	end)

	ttMode:SetOnSelect(function(value)
		setConfig('tooltipMode', value)
		updateForMode(value)
		fireChange()
	end)

	updateForMode(currentMode)

	Widgets.EndCard(card, parent, cardY)
	return card
end
