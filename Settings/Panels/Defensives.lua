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

-- ============================================================
-- Config helpers (assigned per-panel in create; card builders close over these)
-- ============================================================

local get, set

-- ============================================================
-- Card builders — function(parent, width) → card frame
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
	local descFS = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textActive)
	descFS:SetWidth(width - Widgets.CARD_PADDING * 2)
	descFS:SetJustifyH('LEFT')
	descFS:SetWordWrap(true)
	descFS:SetText('Major personal defensive cooldowns. Supports visibility modes: show all, player-cast only, or other-cast only. Border color differentiates source.')
	cy = placeWidget(descFS, inner, cy, descFS:GetStringHeight())

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildDisplayCard(parent, width)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- Visibility mode
	local visDD = Widgets.CreateDropdown(inner, widgetW)
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

	-- Icon Size
	local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', widgetW, 8, 48, 1)
	sizeSlider:SetValue(get('iconSize') or 16)
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	cy = placeWidget(sizeSlider, inner, cy, SLIDER_H)

	-- Max Displayed
	local maxSlider = Widgets.CreateSlider(inner, 'Max Displayed', widgetW, 1, 20, 1)
	maxSlider:SetValue(get('maxDisplayed') or 3)
	maxSlider:SetAfterValueChanged(function(v) set('maxDisplayed', v) end)
	cy = placeWidget(maxSlider, inner, cy, SLIDER_H)

	-- Orientation
	local oriDD = Widgets.CreateDropdown(inner, widgetW)
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

local function buildLayoutCard(parent, width)
	local _, card = F.Settings.BuildPositionCard(parent, width, 0, get, set, { noHeading = true })
	return card
end

local function buildDurationFontCard(parent, width)
	local _, card = F.Settings.BuildFontCard(parent, width, 0, 'Duration', 'durationFont', get, set, {
		noHeading = true,
		showAnchor = true,
		showToggle = {
			label = 'Show Duration',
			get = function() return get('showDuration') ~= false end,
			set = function(checked) set('showDuration', checked) end,
		},
	})
	return card
end

local function buildStackFontCard(parent, width)
	local _, card = F.Settings.BuildFontCard(parent, width, 0, 'Stacks', 'stackFont', get, set, { noHeading = true, showAnchor = true })
	return card
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
			if(key ~= 'enabled' and F.EventBus) then
				F.EventBus:Fire('CONFIG_CHANGED', basePath)
			end
			F.Settings.UpdateAuraPreviewDimming('defensives', nil)
		end

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'defensives', 'defensives')

		-- ── Pinned row: Preview | Overview ───────────────────────
		local CARD_GAP      = C.Spacing.normal
		local pinnedRowY    = yOffset
		local previewCardW  = math.floor((width - CARD_GAP) * 0.40)
		local overviewCardW = width - previewCardW - CARD_GAP

		local previewCard = F.Settings.AuraPreview.BuildPreviewCard(content, previewCardW)
		previewCard:ClearAllPoints()
		Widgets.SetPoint(previewCard, 'TOPLEFT', content, 'TOPLEFT', 0, pinnedRowY)
		local previewCardH     = previewCard:GetHeight()
		local previewOrigLevel = previewCard:GetFrameLevel()

		local overviewCard = buildOverviewCard(content, overviewCardW)
		overviewCard:ClearAllPoints()
		Widgets.SetPoint(overviewCard, 'TOPLEFT', content, 'TOPLEFT', previewCardW + CARD_GAP, pinnedRowY)

		local pinnedRowH = math.max(previewCardH, overviewCard:GetHeight())
		previewCard:SetHeight(pinnedRowH)
		overviewCard:SetHeight(pinnedRowH)
		yOffset = pinnedRowY - pinnedRowH - C.Spacing.normal

		-- ── CardGrid for settings cards ──────────────────────────
		local grid = Widgets.CreateCardGrid(content, width)
		grid:SetTopOffset(math.abs(yOffset))

		grid:AddCard('display',      'Display',  buildDisplayCard,      {})
		grid:AddCard('layout',       'Layout',   buildLayoutCard,       {})
		grid:AddCard('durationFont', 'Duration', buildDurationFontCard, {})
		grid:AddCard('stackFont',    'Stacks',   buildStackFontCard,    {})

		grid:Layout(0, parentH)
		content:SetHeight(grid:GetTotalHeight())
		scroll:UpdateScrollRange()

		-- ── Pin preview + overview above scroll ──────────────────
		local scrim = CreateFrame('Frame', nil, scroll)
		scrim:SetFrameLevel(previewOrigLevel + 49)
		scrim:SetPoint('TOPLEFT', scroll, 'TOPLEFT', 0, 0)
		scrim:SetPoint('TOPRIGHT', scroll, 'TOPRIGHT', 0, 0)
		scrim:SetHeight(math.abs(pinnedRowY) + pinnedRowH + C.Spacing.normal)
		local scrimBg = scrim:CreateTexture(nil, 'BACKGROUND')
		scrimBg:SetAllPoints(scrim)
		local bg = C.Colors.background
		scrimBg:SetColorTexture(bg[1], bg[2], bg[3], 0.85)

		previewCard:SetParent(scroll)
		previewCard:SetFrameLevel(previewOrigLevel + 50)
		previewCard:ClearAllPoints()
		Widgets.SetPoint(previewCard, 'TOPLEFT', scroll, 'TOPLEFT', 0, pinnedRowY)

		overviewCard:SetParent(scroll)
		overviewCard:SetFrameLevel(previewOrigLevel + 50)
		overviewCard:ClearAllPoints()
		Widgets.SetPoint(overviewCard, 'TOPLEFT', scroll, 'TOPLEFT', previewCardW + CARD_GAP, pinnedRowY)

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
		local resizeKey        = 'Defensives.resize'
		local currentPreviewW  = previewCardW
		local currentOverviewW = overviewCardW

		local function onResize(newW)
			local newWidth      = newW - C.Spacing.normal * 2
			currentPreviewW     = math.floor((newWidth - CARD_GAP) * 0.40)
			currentOverviewW    = newWidth - currentPreviewW - CARD_GAP

			previewCard:SetWidth(currentPreviewW)
			overviewCard:SetWidth(currentOverviewW)
			overviewCard:ClearAllPoints()
			Widgets.SetPoint(overviewCard, 'TOPLEFT', scroll, 'TOPLEFT', currentPreviewW + CARD_GAP, pinnedRowY)

			local preview = F.Settings._auraPreview
			if(preview) then
				preview._maxWidth = currentPreviewW - Widgets.CARD_PADDING * 2
			end

			grid:SetWidth(newWidth)
			content:SetHeight(grid:GetTotalHeight())
		end

		local function rebuildPinnedRow()
			local oldOverview = overviewCard
			overviewCard = buildOverviewCard(scroll, currentOverviewW)
			overviewCard:SetFrameLevel(previewOrigLevel + 50)
			overviewCard:ClearAllPoints()
			Widgets.SetPoint(overviewCard, 'TOPLEFT', scroll, 'TOPLEFT', currentPreviewW + CARD_GAP, pinnedRowY)

			pinnedRowH = math.max(previewCard:GetHeight(), overviewCard:GetHeight())
			previewCard:SetHeight(pinnedRowH)
			overviewCard:SetHeight(pinnedRowH)
			scrim:SetHeight(math.abs(pinnedRowY) + pinnedRowH + C.Spacing.normal)
			grid:SetTopOffset(math.abs(pinnedRowY) + pinnedRowH + C.Spacing.normal)

			oldOverview:Hide()
			oldOverview:SetParent(nil)
		end

		local function fullRebuild()
			if(F.Settings._auraPreview) then
				F.Settings.AuraPreview.Rebuild()
			end
			rebuildPinnedRow()
			grid:RebuildCards()
			content:SetHeight(grid:GetTotalHeight())
			scroll:UpdateScrollRange()
		end

		F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)
		F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', fullRebuild, resizeKey .. '.complete')

		-- ── Cleanup on hide, re-register on show ─────────────────
		scroll:HookScript('OnHide', function()
			grid:CancelAnimations()
			F.EventBus:Unregister('SETTINGS_RESIZED', resizeKey)
			F.EventBus:Unregister('SETTINGS_RESIZE_COMPLETE', resizeKey .. '.complete')
		end)

		scroll:HookScript('OnShow', function()
			F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)
			F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', fullRebuild, resizeKey .. '.complete')
			local curW = parent._explicitWidth  or parent:GetWidth()  or parentW
			onResize(curW)
			fullRebuild()
		end)

		scroll._ownedPreview = F.Settings._auraPreview
		return scroll
	end,
})
