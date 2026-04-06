local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================
local SLIDER_H   = 26
local DROPDOWN_H = 22
local CHECK_H    = 22
local WIDGET_W   = 220

-- ============================================================
-- Config helpers
-- ============================================================

local function makeHelpers(unitType)
	local function get(key)
		local presetName = F.Settings.GetEditingPreset()
		return F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.privateAuras.' .. key)
	end

	local function set(key, value)
		local presetName = F.Settings.GetEditingPreset()
		if(F.Config) then
			F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.privateAuras.' .. key, value)
		end
		if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
		if(F.EventBus) then
			F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.privateAuras')
		end
	end

	return get, set
end

-- ============================================================
-- Card builders
-- ============================================================

local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

local function buildOverviewCard(parent, width, get, set)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	-- Enabled toggle
	local enableCB = Widgets.CreateCheckButton(inner, 'Enabled', function(checked)
		set('enabled', checked)
	end)
	enableCB:SetChecked(get('enabled') or false)
	cy = placeWidget(enableCB, inner, cy, CHECK_H)

	-- Description
	local descFS = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textSecondary)
	descFS:SetWidth(width - Widgets.CARD_PADDING * 2)
	descFS:SetWordWrap(true)
	descFS:SetText('Private auras are Blizzard-controlled aura anchors. Their spells are defined by the game, but you can configure their size and position on unit frames.')
	cy = placeWidget(descFS, inner, cy, descFS:GetStringHeight() + C.Spacing.tight)

	-- Reload notice
	local reloadInfo = Widgets.CreateInfoIcon(inner,
		'Requires /reload',
		'Private Auras are registered at the C-level API. Changes to icon size and anchor require a /reload to take effect.')
	cy = placeWidget(reloadInfo, inner, cy, reloadInfo:GetHeight())

	return Widgets.EndCard(card, parent, cy)
end

local function buildDisplayCard(parent, width, get, set)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	-- Icon Size
	local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', WIDGET_W, 8, 48, 1)
	sizeSlider:SetValue(get('iconSize') or 20)
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	cy = placeWidget(sizeSlider, inner, cy, SLIDER_H)

	-- Max Displayed
	local maxSlider = Widgets.CreateSlider(inner, 'Max Displayed', WIDGET_W, 1, 5, 1)
	maxSlider:SetValue(get('maxDisplayed') or 3)
	maxSlider:SetAfterValueChanged(function(v) set('maxDisplayed', v) end)
	cy = placeWidget(maxSlider, inner, cy, SLIDER_H)

	-- Orientation
	local oriDD = Widgets.CreateDropdown(inner, WIDGET_W)
	oriDD:SetItems({
		{ text = 'Right',             value = 'RIGHT' },
		{ text = 'Left',              value = 'LEFT' },
		{ text = 'Up',                value = 'UP' },
		{ text = 'Down',              value = 'DOWN' },
		{ text = 'Center Horizontal', value = 'CENTER_HORIZONTAL' },
		{ text = 'Center Vertical',   value = 'CENTER_VERTICAL' },
	})
	oriDD:SetValue(get('orientation') or 'RIGHT')
	oriDD:SetOnSelect(function(v) set('orientation', v) end)
	cy = placeWidget(oriDD, inner, cy, DROPDOWN_H)

	return Widgets.EndCard(card, parent, cy)
end

local function buildPositionCard(parent, width, get, set)
	local wrapper = CreateFrame('Frame', nil, parent)
	wrapper:SetWidth(width)
	local yOff = F.Settings.BuildPositionCard(wrapper, width, 0, get, set, {
		hideFrameLevel = true,
	})
	wrapper:SetHeight(math.abs(yOff))
	return wrapper
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id         = 'privateauras',
	label      = 'Private Auras',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 18,
	create     = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll  = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		local unitType = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
		local get, set = makeHelpers(unitType)

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'privateauras', 'privateAuras')

		-- CardGrid
		local grid = Widgets.CreateCardGrid(content, width)
		grid:SetTopOffset(math.abs(yOffset))

		grid:AddCard('overview', 'Overview',         buildOverviewCard, { get, set })
		grid:AddCard('display',  'Display Settings', buildDisplayCard,  { get, set })
		grid:AddCard('position', nil,                buildPositionCard, { get, set })

		grid:Layout(0, parentH)
		content:SetHeight(grid:GetTotalHeight())
		scroll:UpdateScrollRange()

		-- Scroll integration
		local function onScroll()
			local offset = scroll._scrollFrame:GetVerticalScroll()
			local viewH  = scroll._scrollFrame:GetHeight()
			grid:Layout(offset, viewH)
			content:SetHeight(grid:GetTotalHeight())
		end

		scroll._scrollFrame:HookScript('OnMouseWheel', function()
			C_Timer.After(0, onScroll)
		end)

		-- Resize handling
		local resizeKey = 'PrivateAuras.resize.' .. unitType
		local function onResize(newW)
			local newWidth = newW - C.Spacing.normal * 2
			grid:SetWidth(newWidth)
			content:SetWidth(newW)
			content:SetHeight(grid:GetTotalHeight())
		end

		F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)

		scroll:HookScript('OnHide', function()
			grid:CancelAnimations()
			F.EventBus:Unregister('SETTINGS_RESIZED', resizeKey)
		end)

		scroll:HookScript('OnShow', function()
			F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)
			grid:Layout(0, parentH, false)
			content:SetHeight(grid:GetTotalHeight())
		end)

		return scroll
	end,
})
