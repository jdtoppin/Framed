local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}


local GROUP_TYPES = { party = true, raid = true, arena = true }

function F.SettingsCards.PositionAndLayout(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2
	local isGroup = GROUP_TYPES[unitType] or false

	-- Width slider
	local widthSlider = Widgets.CreateSlider(inner, 'Width', widgetW, 20, 300, 1)
	widthSlider:SetValue(getConfig('width'))
	widthSlider:SetAfterValueChanged(function(value)
		setConfig('width', value)
	end)
	cardY = B.PlaceWidget(widthSlider, inner, cardY, B.SLIDER_H)

	-- Height slider
	local heightSlider = Widgets.CreateSlider(inner, 'Height', widgetW, 16, 100, 1)
	heightSlider:SetValue(getConfig('height'))
	heightSlider:SetAfterValueChanged(function(value)
		setConfig('height', value)
	end)
	cardY = B.PlaceWidget(heightSlider, inner, cardY, B.SLIDER_H)

	-- Resize Anchor picker — right after width/height since it's tied to those
	local raHeading, raHeadingH = Widgets.CreateHeading(inner, 'Resize Anchor', 4)
	raHeading:ClearAllPoints()
	Widgets.SetPoint(raHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
	cardY = cardY - raHeadingH

	local anchorInfo = Widgets.CreateInfoIcon(inner,
		'Resize Anchor',
		'Controls which corner or edge of the frame stays fixed when you change '
		.. 'the width or height. For example, TOPLEFT means the top-left corner '
		.. 'stays pinned and the frame grows right and downward.')
	anchorInfo:SetPoint('LEFT', raHeading, 'RIGHT', 4, 0)

	local anchorPicker = Widgets.CreateAnchorPicker(inner, widgetW)
	local savedAnchor = getConfig('position.anchor')
	anchorPicker._xSlider:Hide()
	anchorPicker._ySlider:Hide()
	anchorPicker:SetAnchor(savedAnchor, 0, 0)
	anchorPicker:SetOnChanged(function(point)
		setConfig('position.anchor', point)
	end)
	cardY = B.PlaceWidget(anchorPicker, inner, cardY, 56)

	-- ── Group layout (group frames only) ─────────────────────
	if(isGroup) then
		-- Spacing slider
		local spacingSlider = Widgets.CreateSlider(inner, 'Spacing', widgetW, 0, 20, 1)
		spacingSlider:SetValue(getConfig('spacing'))
		spacingSlider:SetAfterValueChanged(function(value)
			setConfig('spacing', value)
		end)
		cardY = B.PlaceWidget(spacingSlider, inner, cardY, B.SLIDER_H)

		-- Orientation switch
		cardY = B.PlaceHeading(inner, 'Orientation', 4, cardY)
		local orientSwitch = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
			{ text = 'Vertical',   value = 'vertical' },
			{ text = 'Horizontal', value = 'horizontal' },
		})
		orientSwitch:SetValue(getConfig('orientation'))
		orientSwitch:SetOnSelect(function(value)
			setConfig('orientation', value)
		end)
		cardY = B.PlaceWidget(orientSwitch, inner, cardY, B.SWITCH_H)

		-- Raid preview count slider (edit mode only)
		if(unitType == 'raid' and F.EditCache and F.EditCache.IsActive()) then
			local countSlider = Widgets.CreateSlider(inner, 'Preview Count', widgetW, 10, 40, 5)
			countSlider:SetValue(F.PreviewManager.GetGroupPreviewCount('raid') or 20)
			countSlider:SetAfterValueChanged(function(value)
				F.PreviewManager.SetGroupPreviewCount('raid', value)
			end)
			cardY = B.PlaceWidget(countSlider, inner, cardY, B.SLIDER_H)
		end

		-- Anchor Point dropdown — corner the group grows from
		cardY = B.PlaceHeading(inner, 'Anchor Point', 4, cardY)
		local apDropdown = Widgets.CreateDropdown(inner, widgetW)
		apDropdown:SetItems({
			{ text = 'Top Left',     value = 'TOPLEFT' },
			{ text = 'Top Right',    value = 'TOPRIGHT' },
			{ text = 'Bottom Left',  value = 'BOTTOMLEFT' },
			{ text = 'Bottom Right', value = 'BOTTOMRIGHT' },
		})
		apDropdown:SetValue(getConfig('anchorPoint'))
		apDropdown:SetOnSelect(function(value)
			setConfig('anchorPoint', value)
		end)
		cardY = B.PlaceWidget(apDropdown, inner, cardY, B.DROPDOWN_H)
	end

	-- Read the actual frame position from config
	local actualX = getConfig('position.x')
	local actualY = getConfig('position.y')

	-- Frame Position sliders (X / Y)
	cardY = B.PlaceHeading(inner, 'Frame Position', 4, cardY)

	local posXSlider = Widgets.CreateSlider(inner, 'X', widgetW, -1000, 1000, 1)
	posXSlider:SetValue(actualX)
	posXSlider:SetAfterValueChanged(function(value)
		setConfig('position.x', value)
	end)
	cardY = B.PlaceWidget(posXSlider, inner, cardY, B.SLIDER_H)

	local posYSlider = Widgets.CreateSlider(inner, 'Y', widgetW, -1000, 1000, 1)
	posYSlider:SetValue(actualY)
	posYSlider:SetAfterValueChanged(function(value)
		setConfig('position.y', value)
	end)
	cardY = B.PlaceWidget(posYSlider, inner, cardY, B.SLIDER_H)

	-- Pixel nudge arrows
	cardY = B.PlaceHeading(inner, 'Pixel Nudge', 4, cardY)

	local nudgeFrame = CreateFrame('Frame', nil, inner)
	nudgeFrame:SetSize(100, 50)

	local nudgeUp = Widgets.CreateButton(nudgeFrame, '^', 'widget', 24, 20)
	nudgeUp:SetPoint('TOP', nudgeFrame, 'TOP', 0, 0)
	local nudgeDown = Widgets.CreateButton(nudgeFrame, 'v', 'widget', 24, 20)
	nudgeDown:SetPoint('BOTTOM', nudgeFrame, 'BOTTOM', 0, 0)
	local nudgeLeft = Widgets.CreateButton(nudgeFrame, '<', 'widget', 24, 20)
	nudgeLeft:SetPoint('LEFT', nudgeFrame, 'LEFT', 0, 0)
	local nudgeRight = Widgets.CreateButton(nudgeFrame, '>', 'widget', 24, 20)
	nudgeRight:SetPoint('RIGHT', nudgeFrame, 'RIGHT', 0, 0)

	local function nudge(dx, dy)
		local curX = posXSlider:GetValue()
		local curY = posYSlider:GetValue()
		posXSlider:SetValue(curX + dx)
		posYSlider:SetValue(curY + dy)
		setConfig('position.x', curX + dx)
		setConfig('position.y', curY + dy)
	end

	nudgeUp:SetOnClick(function() nudge(0, 1) end)
	nudgeDown:SetOnClick(function() nudge(0, -1) end)
	nudgeLeft:SetOnClick(function() nudge(-1, 0) end)
	nudgeRight:SetOnClick(function() nudge(1, 0) end)

	cardY = B.PlaceWidget(nudgeFrame, inner, cardY, 50)

	-- ── Live sync from resize handles ────────────────────────
	local evtTag = 'PositionAndLayout.' .. unitType
	F.EventBus:Register('EDIT_MODE_FRAME_RESIZED', function(frameKey, newW, newH)
		if(frameKey ~= unitType) then return end
		widthSlider:SetValue(Widgets.Round(newW))
		heightSlider:SetValue(Widgets.Round(newH))
	end, evtTag .. '.resize')

	-- ── Live sync from drag stop ─────────────────────────────
	F.EventBus:Register('EDIT_MODE_DRAG_STOPPED', function(frameKey)
		if(frameKey ~= unitType) then return end
		local x = F.EditCache.Get(unitType, 'position.x')
		local y = F.EditCache.Get(unitType, 'position.y')
		posXSlider:SetValue(Widgets.Round(x))
		posYSlider:SetValue(Widgets.Round(y))
	end, evtTag .. '.drag')

	-- ── Live sync during drag ────────────────────────────────
	F.EventBus:Register('EDIT_MODE_DRAGGING', function(frameKey, x, y)
		if(frameKey ~= unitType) then return end
		posXSlider:SetValue(x)
		posYSlider:SetValue(y)
	end, evtTag .. '.dragging')

	-- Unregister when card is destroyed
	card:HookScript('OnHide', function()
		F.EventBus:Unregister('EDIT_MODE_FRAME_RESIZED', evtTag .. '.resize')
		F.EventBus:Unregister('EDIT_MODE_DRAG_STOPPED', evtTag .. '.drag')
		F.EventBus:Unregister('EDIT_MODE_DRAGGING', evtTag .. '.dragging')
	end)

	Widgets.EndCard(card, parent, cardY)
	return card
end
