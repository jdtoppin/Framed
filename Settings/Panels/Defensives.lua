local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Widget constants
-- ============================================================

local SLIDER_H   = 26
local CHECK_H    = 22
local DROPDOWN_H = 22
local WIDGET_W   = 220

-- ============================================================
-- Config helpers (assigned per-panel in create; card builders close over these)
-- ============================================================

local get, set

-- ============================================================
-- Card builders
-- Each follows CardGrid builder signature:
--   function(parent, width, data, update, get, set, rebuildPanel)
-- ============================================================

local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

local function buildOverviewCard(parent, width)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	-- Enabled toggle
	local enableCB = Widgets.CreateCheckButton(inner, 'Enabled', function(checked)
		set('enabled', checked)
	end)
	enableCB:SetChecked(get('enabled'))
	cy = placeWidget(enableCB, inner, cy, CHECK_H)

	-- Description
	local descFS = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textSecondary)
	descFS:SetWidth(width - Widgets.CARD_PADDING * 2)
	descFS:SetWordWrap(true)
	descFS:SetJustifyH('LEFT')
	descFS:SetText('Major personal defensive cooldowns. Supports visibility modes: show all, player-cast only, or other-cast only. Border color differentiates source.')
	cy = placeWidget(descFS, inner, cy, descFS:GetStringHeight())

	-- Visibility mode
	local visDD = Widgets.CreateDropdown(inner, WIDGET_W)
	visDD:SetItems({
		{ text = 'All',         value = 'all' },
		{ text = 'Player Only', value = 'player' },
		{ text = 'Others Only', value = 'others' },
	})
	visDD:SetValue(get('visibilityMode') or 'all')
	visDD:SetOnSelect(function(v) set('visibilityMode', v) end)
	cy = placeWidget(visDD, inner, cy, DROPDOWN_H)

	-- Source colors
	if(Widgets.CreateColorPicker) then
		local savedPlayerColor = get('playerColor')
		local playerCP = Widgets.CreateColorPicker(inner, 'Player Cast')
		if(savedPlayerColor) then
			playerCP:SetColor(savedPlayerColor[1], savedPlayerColor[2], savedPlayerColor[3])
		else
			playerCP:SetColor(0, 0.8, 0)
		end
		playerCP:SetOnColorChanged(function(r, g, b)
			set('playerColor', { r, g, b })
		end)
		cy = placeWidget(playerCP, inner, cy, playerCP:GetHeight())

		local savedOtherColor = get('otherColor')
		local otherCP = Widgets.CreateColorPicker(inner, 'Other Cast')
		if(savedOtherColor) then
			otherCP:SetColor(savedOtherColor[1], savedOtherColor[2], savedOtherColor[3])
		else
			otherCP:SetColor(1, 0.85, 0)
		end
		otherCP:SetOnColorChanged(function(r, g, b)
			set('otherColor', { r, g, b })
		end)
		cy = placeWidget(otherCP, inner, cy, otherCP:GetHeight())
	end

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildDisplayCard(parent, width)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	-- Icon Size
	local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', WIDGET_W, 8, 48, 1)
	sizeSlider:SetValue(get('iconSize') or 16)
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	cy = placeWidget(sizeSlider, inner, cy, SLIDER_H)

	-- Max Displayed
	local maxSlider = Widgets.CreateSlider(inner, 'Max Displayed', WIDGET_W, 1, 20, 1)
	maxSlider:SetValue(get('maxDisplayed') or 3)
	maxSlider:SetAfterValueChanged(function(v) set('maxDisplayed', v) end)
	cy = placeWidget(maxSlider, inner, cy, SLIDER_H)

	-- Show Duration
	local durCheck = Widgets.CreateCheckButton(inner, 'Show Duration', function(checked)
		set('showDuration', checked)
	end)
	durCheck:SetChecked(get('showDuration') ~= false)
	cy = placeWidget(durCheck, inner, cy, CHECK_H)

	-- Show Animation
	local animCheck = Widgets.CreateCheckButton(inner, 'Show Animation', function(checked)
		set('showAnimation', checked)
	end)
	animCheck:SetChecked(get('showAnimation') ~= false)
	cy = placeWidget(animCheck, inner, cy, CHECK_H)

	-- Orientation
	local oriDD = Widgets.CreateDropdown(inner, WIDGET_W)
	oriDD:SetItems({
		{ text = 'Right', value = 'RIGHT' },
		{ text = 'Left',  value = 'LEFT' },
		{ text = 'Up',    value = 'UP' },
		{ text = 'Down',  value = 'DOWN' },
	})
	oriDD:SetValue(get('orientation') or 'RIGHT')
	oriDD:SetOnSelect(function(v) set('orientation', v) end)
	cy = placeWidget(oriDD, inner, cy, DROPDOWN_H)

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildPositionCard(parent, width)
	local wrapper = CreateFrame('Frame', nil, parent)
	wrapper:SetWidth(width)
	local yOff = F.Settings.BuildPositionCard(wrapper, width, 0, get, set)
	wrapper:SetHeight(math.abs(yOff))
	return wrapper
end

local function buildDurationFontCard(parent, width)
	local wrapper = CreateFrame('Frame', nil, parent)
	wrapper:SetWidth(width)
	local yOff = F.Settings.BuildFontCard(wrapper, width, 0, 'Duration Text Font', 'durationFont', get, set, { showAnchor = true })
	wrapper:SetHeight(math.abs(yOff))
	return wrapper
end

local function buildStackFontCard(parent, width)
	local wrapper = CreateFrame('Frame', nil, parent)
	wrapper:SetWidth(width)
	local yOff = F.Settings.BuildFontCard(wrapper, width, 0, 'Stack Count Font', 'stackFont', get, set, { showAnchor = true })
	wrapper:SetHeight(math.abs(yOff))
	return wrapper
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id         = 'defensives',
	label      = 'Defensives',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 14,
	create     = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll  = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ── Capture preset + unitType once for this panel instance ────
		local presetName = F.Settings.GetEditingPreset()
		local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
		local basePath   = 'presets.' .. presetName .. '.auras.' .. unitType .. '.defensives'

		get = function(key) return F.Config and F.Config:Get(basePath .. '.' .. key) end
		set = function(key, value)
			if(F.Config) then F.Config:Set(basePath .. '.' .. key, value) end
			if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
			if(key == 'enabled') then
				F.Settings.UpdateAuraPreviewDimming('defensives', nil)
			elseif(F.EventBus) then
				F.EventBus:Fire('CONFIG_CHANGED', basePath)
			end
		end

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'defensives', 'defensives')

		-- ── CardGrid ─────────────────────────────────────────────
		local grid = Widgets.CreateCardGrid(content, width)
		grid:SetTopOffset(math.abs(yOffset))

		grid:AddCard('overview',     'Overview',         buildOverviewCard,     {})
		grid:AddCard('display',      'Display',          buildDisplayCard,      {})
		grid:AddCard('position',     'Position',         buildPositionCard,     {})
		grid:AddCard('durationFont', nil,                buildDurationFontCard, {})
		grid:AddCard('stackFont',    nil,                buildStackFontCard,    {})

		grid:Layout(0, parentH)
		content:SetHeight(grid:GetTotalHeight())
		scroll:UpdateScrollRange()

		-- ── Scroll integration ───────────────────────────────────
		local function onScroll()
			local offset = scroll._scrollFrame:GetVerticalScroll()
			local viewH  = scroll._scrollFrame:GetHeight()
			grid:Layout(offset, viewH)
			content:SetHeight(grid:GetTotalHeight())
		end

		scroll._scrollFrame:HookScript('OnMouseWheel', function()
			C_Timer.After(0, onScroll)
		end)

		-- ── Resize handling ──────────────────────────────────────
		local resizeKey = 'Defensives.resize'
		local function onResize(newW)
			local newWidth = newW - C.Spacing.normal * 2
			grid:SetWidth(newWidth)
			content:SetWidth(newW)
			content:SetHeight(grid:GetTotalHeight())
		end

		F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)

		-- ── Cleanup on hide, re-register on show ─────────────────
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
