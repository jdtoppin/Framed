local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local Settings = F.Settings

-- Shared layout constants (match FrameSettingsBuilder.lua)
local DROPDOWN_H  = 22
local SLIDER_H    = 26
local CHECK_H     = 14
local BUTTON_H    = 24

local function placeWidget(widget, parent, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

local function placeHeading(parent, text, level, yOffset)
	local fs = Widgets.CreateFontString(parent, level == 2 and C.Font.sizeSmall or C.Font.sizeNormal, C.Colors.textSecondary)
	fs:SetText(text)
	fs:ClearAllPoints()
	Widgets.SetPoint(fs, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	return yOffset - (level == 2 and C.Font.sizeSmall or C.Font.sizeNormal) - C.Spacing.tight
end

-- ============================================================
-- Card Builders
-- Each follows the CardGrid builder signature:
--   function(parent, width, data, update, get, set, rebuildPanel)
-- Returns: card frame (from EndCard)
-- ============================================================

local Builders = {}
F.Settings.IndicatorCardBuilders = Builders

-- ── Cast By ─────────────────────────────────────────────────
function Builders.CastBy(parent, width, data, update)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local castByDD = Widgets.CreateDropdown(inner, widgetW)
	castByDD:SetItems({
		{ text = 'Me',      value = C.CastFilter.ME },
		{ text = 'Others',  value = C.CastFilter.OTHERS },
		{ text = 'Anyone',  value = C.CastFilter.ANYONE },
	})
	castByDD:SetValue(data.castBy)
	castByDD:SetOnSelect(function(value) update('castBy', value) end)
	cardY = placeWidget(castByDD, inner, cardY, DROPDOWN_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end

-- ── Tracked Spells ──────────────────────────────────────────
function Builders.TrackedSpells(parent, width, data, update, get, set, rebuildPanel)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	-- Calculate spell list height based on spell count (28px per row matches SpellList ROW_HEIGHT)
	local spellCount = data.spells and #data.spells or 0
	local spListH = math.max(60, spellCount * 28)

	local spList = Widgets.CreateSpellList(inner, width - 24, spListH, true)
	spList:SetSpells(data.spells or {})
	spList:SetOnChanged(function(spells)
		update('spells', spells)
		update('spellColors', spList:GetSpellColors())
		if(rebuildPanel) then rebuildPanel() end
	end)

	-- Show per-spell color pickers for colored square and bar types
	if(data.displayType == C.IconDisplay.COLORED_SQUARE
		or data.type == C.IndicatorType.BAR
		or data.type == C.IndicatorType.BARS) then
		spList:SetSpellColors(data.spellColors or {})
		spList:SetShowColorPicker(true)
	end
	spList:ClearAllPoints()
	Widgets.SetPoint(spList, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)

	local spInput = Widgets.CreateSpellInput(inner, width - 24)
	spInput:ClearAllPoints()
	Widgets.SetPoint(spInput, 'TOPLEFT', spList, 'BOTTOMLEFT', 0, -C.Spacing.normal)
	spInput:SetFrameLevel(spList:GetFrameLevel() + 10)
	spInput:SetSpellList(spList)
	spInput:SetOnAdd(function()
		update('spells', spList:GetSpells())
		if(rebuildPanel) then rebuildPanel() end
	end)

	local btnRow = CreateFrame('Frame', nil, inner)
	btnRow:SetHeight(24)
	Widgets.SetPoint(btnRow, 'TOPLEFT', spInput, 'BOTTOMLEFT', 0, -C.Spacing.normal)
	btnRow:SetWidth(width - 24)
	btnRow:SetFrameLevel(spInput:GetFrameLevel() + 2)

	local importBtn = Widgets.CreateButton(btnRow, 'Import Healer Spells', 'widget', 160, 24)
	Widgets.SetPoint(importBtn, 'TOPLEFT', btnRow, 'TOPLEFT', 0, 0)
	importBtn:SetOnClick(function()
		F.Settings.Builders.ShowImportPopup(function(selectedSpells)
			if(not selectedSpells or #selectedSpells == 0) then return end
			for _, spellID in next, selectedSpells do
				spList:AddSpell(spellID)
			end
		end)
	end)

	local deleteAllBtn = Widgets.CreateButton(btnRow, 'Delete All Spells', 'red', 140, 24)
	deleteAllBtn:SetPoint('LEFT', importBtn, 'RIGHT', C.Spacing.tight, 0)
	deleteAllBtn:SetOnClick(function()
		Widgets.ShowConfirmDialog('Delete All Spells', 'Remove all tracked spells from this indicator?', function()
			update('spells', {})
			spList:SetSpells({})
		end)
	end)

	-- Compute total card height: spellList + spacing + spInput(50) + spacing + btnRow(24)
	cardY = cardY - spListH - C.Spacing.normal - 50 - C.Spacing.normal - 24

	Widgets.EndCard(card, parent, cardY)
	return card
end

-- ── Appearance (Icon/Icons) ──────────────────────────────────
function Builders.Appearance(parent, width, data, update, get, set, rebuildPanel)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local dtLabel = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	dtLabel:SetText('Display Type')
	cardY = placeWidget(dtLabel, inner, cardY, C.Font.sizeSmall)

	local dtSwitch = Widgets.CreateSwitch(inner, widgetW, BUTTON_H, {
		{ text = 'Spell Icons',   value = C.IconDisplay.SPELL_ICON },
		{ text = 'Color Squares', value = C.IconDisplay.COLORED_SQUARE },
	})
	dtSwitch:SetValue(data.displayType)
	dtSwitch:SetOnSelect(function(v)
		update('displayType', v)
		-- Rebuild panel to update spell list color pickers
		if(rebuildPanel) then rebuildPanel() end
	end)
	cardY = placeWidget(dtSwitch, inner, cardY, BUTTON_H)

	local wSlider = Widgets.CreateSlider(inner, 'Width', widgetW, 3, 48, 1)
	wSlider:SetValue(data.iconWidth)
	wSlider:SetAfterValueChanged(function(v) update('iconWidth', v) end)
	cardY = placeWidget(wSlider, inner, cardY, SLIDER_H)

	local hSlider = Widgets.CreateSlider(inner, 'Height', widgetW, 3, 48, 1)
	hSlider:SetValue(data.iconHeight)
	hSlider:SetAfterValueChanged(function(v) update('iconHeight', v) end)
	cardY = placeWidget(hSlider, inner, cardY, SLIDER_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end

-- ── Layout (Icons, Bars — multi-element types) ───────────────
-- Also used as Position for single-element types (Icon, Bar, Rectangle)
function Builders.Layout(parent, width, data, update, get, set)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2
	local iType = data.type

	-- Anchor picker
	if(Widgets.CreateAnchorPicker) then
		local anchor = get('anchor')
		local picker = Widgets.CreateAnchorPicker(inner, widgetW, 50)
		picker:SetAnchor(anchor[1] or 'CENTER', anchor[4] or 0, anchor[5] or 0)
		picker:SetOnChanged(function(point, x, y)
			local a = get('anchor')
			a[1] = point
			a[3] = point
			a[4] = x
			a[5] = y
			set('anchor', a)
		end)
		cardY = placeWidget(picker, inner, cardY, picker._height or 91)
	end

	-- Frame level
	local flSlider = Widgets.CreateSlider(inner, 'Frame Level', widgetW, 1, 50, 1)
	flSlider:SetValue(get('frameLevel'))
	flSlider:SetAfterValueChanged(function(val) set('frameLevel', val) end)
	cardY = placeWidget(flSlider, inner, cardY, SLIDER_H)

	-- Multi-element fields (Icons, Bars)
	if(iType == C.IndicatorType.ICONS or iType == C.IndicatorType.BARS) then
		-- Grow direction
		local anchorData = data.anchor
		local anchorH = anchorData[3] or 'TOPLEFT'
		local defaultGrow = (anchorH == 'TOPRIGHT' or anchorH == 'RIGHT' or anchorH == 'BOTTOMRIGHT') and 'LEFT' or 'RIGHT'
		local effectiveGrow = data.orientation or defaultGrow

		local growLabel = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
		growLabel:SetText('Grow Direction')
		cardY = placeWidget(growLabel, inner, cardY, C.Font.sizeSmall)

		local ORIENTATION_ITEMS = {
			{ text = 'Right', value = 'RIGHT' },
			{ text = 'Left',  value = 'LEFT' },
			{ text = 'Up',    value = 'UP' },
			{ text = 'Down',  value = 'DOWN' },
		}

		local oriDD = Widgets.CreateDropdown(inner, widgetW)
		oriDD:SetItems(ORIENTATION_ITEMS)
		oriDD:SetValue(effectiveGrow)
		oriDD:SetOnSelect(function(v) update('orientation', v) end)
		cardY = placeWidget(oriDD, inner, cardY, DROPDOWN_H)

		local mxSlider = Widgets.CreateSlider(inner, 'Max Displayed', widgetW, 1, 10, 1)
		mxSlider:SetValue(data.maxDisplayed)
		mxSlider:SetAfterValueChanged(function(v) update('maxDisplayed', v) end)
		cardY = placeWidget(mxSlider, inner, cardY, SLIDER_H)

		local nplSlider = Widgets.CreateSlider(inner, 'Num Per Line', widgetW, 0, 10, 1)
		nplSlider:SetValue(data.numPerLine)
		nplSlider:SetAfterValueChanged(function(v) update('numPerLine', v) end)
		cardY = placeWidget(nplSlider, inner, cardY, SLIDER_H)

		local spxSlider = Widgets.CreateSlider(inner, 'Spacing X', widgetW, -20, 20, 1)
		spxSlider:SetValue(data.spacingX)
		spxSlider:SetAfterValueChanged(function(v) update('spacingX', v) end)
		cardY = placeWidget(spxSlider, inner, cardY, SLIDER_H)

		local spySlider = Widgets.CreateSlider(inner, 'Spacing Y', widgetW, -20, 20, 1)
		spySlider:SetValue(data.spacingY)
		spySlider:SetAfterValueChanged(function(v) update('spacingY', v) end)
		cardY = placeWidget(spySlider, inner, cardY, SLIDER_H)
	end

	Widgets.EndCard(card, parent, cardY)
	return card
end

-- ── Cooldown & Duration (Icon/Icons) ────────────────────────
function Builders.CooldownDuration(parent, width, data, update, get, set)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local cdSwitch = Widgets.CreateCheckButton(inner, 'Show Cooldown', function(checked)
		update('showCooldown', checked)
	end)
	cdSwitch:SetChecked(data.showCooldown ~= false)
	cardY = placeWidget(cdSwitch, inner, cardY, CHECK_H)

	local durModeLabel = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	durModeLabel:SetText('Duration Text')
	cardY = placeWidget(durModeLabel, inner, cardY, C.Font.sizeSmall)

	local DURATION_MODE_ITEMS = {
		{ text = 'Never',  value = 'Never' },
		{ text = 'Always', value = 'Always' },
		{ text = '< 75%',  value = '<75%' },
		{ text = '< 50%',  value = '<50%' },
		{ text = '< 25%',  value = '<25%' },
		{ text = '< 15s',  value = '<15s' },
		{ text = '< 5s',   value = '<5s' },
	}

	local durDD = Widgets.CreateDropdown(inner, widgetW)
	durDD:SetItems(DURATION_MODE_ITEMS)
	durDD:SetValue(data.durationMode)
	durDD:SetOnSelect(function(v) update('durationMode', v) end)
	cardY = placeWidget(durDD, inner, cardY, DROPDOWN_H)

	-- Duration font settings
	local fontCfg = get('durationFont') or {}

	if(Widgets.CreateAnchorPicker) then
		local dfAnchor = fontCfg.anchor or 'BOTTOM'
		local dfPicker = Widgets.CreateAnchorPicker(inner, widgetW, 15)
		dfPicker:SetAnchor(dfAnchor, fontCfg.xOffset or 0, fontCfg.yOffset or 0)
		dfPicker:SetOnChanged(function(point, x, y)
			fontCfg.anchor = point
			fontCfg.xOffset = x
			fontCfg.yOffset = y
			set('durationFont', fontCfg)
		end)
		cardY = placeWidget(dfPicker, inner, cardY, dfPicker._height or 91)
	end

	local dfSizeSlider = Widgets.CreateSlider(inner, 'Font Size', widgetW, 6, 24, 1)
	dfSizeSlider:SetValue(fontCfg.size or C.Font.sizeSmall)
	dfSizeSlider:SetAfterValueChanged(function(val)
		fontCfg.size = val
		set('durationFont', fontCfg)
	end)
	cardY = placeWidget(dfSizeSlider, inner, cardY, SLIDER_H)

	local dfOutlineDD = Widgets.CreateDropdown(inner, widgetW)
	dfOutlineDD:SetItems({
		{ text = 'None',    value = '' },
		{ text = 'Outline', value = 'OUTLINE' },
		{ text = 'Mono',    value = 'MONOCHROME' },
	})
	dfOutlineDD:SetValue(fontCfg.outline or '')
	dfOutlineDD:SetOnSelect(function(value)
		fontCfg.outline = value
		set('durationFont', fontCfg)
	end)
	cardY = placeWidget(dfOutlineDD, inner, cardY, DROPDOWN_H)

	local dfShadowCB = Widgets.CreateCheckButton(inner, 'Shadow', function(checked)
		fontCfg.shadow = checked
		set('durationFont', fontCfg)
	end)
	dfShadowCB:SetChecked(fontCfg.shadow or false)
	cardY = placeWidget(dfShadowCB, inner, cardY, CHECK_H)

	local cpCB = Widgets.CreateCheckButton(inner, 'Color Progression', function(checked)
		fontCfg.colorProgression = checked
		set('durationFont', fontCfg)
	end)
	cpCB:SetChecked(fontCfg.colorProgression or false)
	cardY = placeWidget(cpCB, inner, cardY, CHECK_H)

	local startC = fontCfg.progressionStart or { 0, 1, 0 }
	local startPicker = Widgets.CreateColorPicker(inner, 'Full Duration', false, function(r, g, b)
		fontCfg.progressionStart = { r, g, b }
		set('durationFont', fontCfg)
	end)
	startPicker:SetColor(startC[1], startC[2], startC[3], 1)
	cardY = placeWidget(startPicker, inner, cardY, DROPDOWN_H)

	local midC = fontCfg.progressionMid or { 1, 1, 0 }
	local midPicker = Widgets.CreateColorPicker(inner, 'Half Duration', false, function(r, g, b)
		fontCfg.progressionMid = { r, g, b }
		set('durationFont', fontCfg)
	end)
	midPicker:SetColor(midC[1], midC[2], midC[3], 1)
	cardY = placeWidget(midPicker, inner, cardY, DROPDOWN_H)

	local endC = fontCfg.progressionEnd or { 1, 0, 0 }
	local endPicker = Widgets.CreateColorPicker(inner, 'Near Expiry', false, function(r, g, b)
		fontCfg.progressionEnd = { r, g, b }
		set('durationFont', fontCfg)
	end)
	endPicker:SetColor(endC[1], endC[2], endC[3], 1)
	cardY = placeWidget(endPicker, inner, cardY, DROPDOWN_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end

-- ── Stacks ───────────────────────────────────────────────────
function Builders.Stacks(parent, width, data, update, get, set)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local stSwitch = Widgets.CreateCheckButton(inner, 'Show Stacks', function(checked)
		update('showStacks', checked)
	end)
	stSwitch:SetChecked(data.showStacks == true)
	cardY = placeWidget(stSwitch, inner, cardY, CHECK_H)

	-- Stack font settings
	local sfCfg = get('stackFont') or {}

	if(Widgets.CreateAnchorPicker) then
		local sfAnchor = sfCfg.anchor or 'BOTTOMRIGHT'
		local sfPicker = Widgets.CreateAnchorPicker(inner, widgetW, 15)
		sfPicker:SetAnchor(sfAnchor, sfCfg.offsetX or 0, sfCfg.offsetY or 0)
		sfPicker:SetOnChanged(function(point, x, y)
			sfCfg.anchor = point
			sfCfg.offsetX = x
			sfCfg.offsetY = y
			set('stackFont', sfCfg)
		end)
		cardY = placeWidget(sfPicker, inner, cardY, sfPicker._height or 91)
	end

	local sfSizeSlider = Widgets.CreateSlider(inner, 'Font Size', widgetW, 6, 24, 1)
	sfSizeSlider:SetValue(sfCfg.size or C.Font.sizeSmall)
	sfSizeSlider:SetAfterValueChanged(function(val)
		sfCfg.size = val
		set('stackFont', sfCfg)
	end)
	cardY = placeWidget(sfSizeSlider, inner, cardY, SLIDER_H)

	local sfOutlineDD = Widgets.CreateDropdown(inner, widgetW)
	sfOutlineDD:SetItems({
		{ text = 'None',    value = '' },
		{ text = 'Outline', value = 'OUTLINE' },
		{ text = 'Mono',    value = 'MONOCHROME' },
	})
	sfOutlineDD:SetValue(sfCfg.outline or '')
	sfOutlineDD:SetOnSelect(function(value)
		sfCfg.outline = value
		set('stackFont', sfCfg)
	end)
	cardY = placeWidget(sfOutlineDD, inner, cardY, DROPDOWN_H)

	local sfShadowCB = Widgets.CreateCheckButton(inner, 'Shadow', function(checked)
		sfCfg.shadow = checked
		set('stackFont', sfCfg)
	end)
	sfShadowCB:SetChecked(sfCfg.shadow or false)
	cardY = placeWidget(sfShadowCB, inner, cardY, CHECK_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end

-- ── Size (Bar/Bars/Rectangle) ───────────────────────────────
function Builders.Size(parent, width, data, update)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2
	local iType = data.type

	local BAR_ORIENTATION_ITEMS = {
		{ text = 'Horizontal', value = 'Horizontal' },
		{ text = 'Vertical',   value = 'Vertical' },
	}

	if(iType == C.IndicatorType.BAR or iType == C.IndicatorType.BARS) then
		local bwSlider = Widgets.CreateSlider(inner, 'Width', widgetW, 3, 100, 1)
		bwSlider:SetValue(data.barWidth)
		bwSlider:SetAfterValueChanged(function(v) update('barWidth', v) end)
		cardY = placeWidget(bwSlider, inner, cardY, SLIDER_H)

		local bhSlider = Widgets.CreateSlider(inner, 'Height', widgetW, 3, 100, 1)
		bhSlider:SetValue(data.barHeight)
		bhSlider:SetAfterValueChanged(function(v) update('barHeight', v) end)
		cardY = placeWidget(bhSlider, inner, cardY, SLIDER_H)

		local barOriDD = Widgets.CreateDropdown(inner, widgetW)
		barOriDD:SetItems(BAR_ORIENTATION_ITEMS)
		barOriDD:SetValue(data.barOrientation)
		barOriDD:SetOnSelect(function(v) update('barOrientation', v) end)
		cardY = placeWidget(barOriDD, inner, cardY, DROPDOWN_H)

	elseif(iType == C.IndicatorType.RECTANGLE) then
		local rwSlider = Widgets.CreateSlider(inner, 'Width', widgetW, 3, 500, 1)
		rwSlider:SetValue(data.rectWidth)
		rwSlider:SetAfterValueChanged(function(v) update('rectWidth', v) end)
		cardY = placeWidget(rwSlider, inner, cardY, SLIDER_H)

		local rhSlider = Widgets.CreateSlider(inner, 'Height', widgetW, 3, 500, 1)
		rhSlider:SetValue(data.rectHeight)
		rhSlider:SetAfterValueChanged(function(v) update('rectHeight', v) end)
		cardY = placeWidget(rhSlider, inner, cardY, SLIDER_H)
	end

	Widgets.EndCard(card, parent, cardY)
	return card
end

-- ── Mode (Overlay) ──────────────────────────────────────────
function Builders.Mode(parent, width, data, update, get, set, rebuildPanel)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local modeDD = Widgets.CreateDropdown(inner, widgetW)
	modeDD:SetItems({
		{ text = 'Duration Overlay', value = 'DurationOverlay' },
		{ text = 'Color',            value = 'Color' },
		{ text = 'Both',             value = 'Both' },
	})
	modeDD:SetValue(data.overlayMode)
	modeDD:SetOnSelect(function(v)
		update('overlayMode', v)
		if(rebuildPanel) then rebuildPanel() end
	end)
	cardY = placeWidget(modeDD, inner, cardY, DROPDOWN_H)

	local ovColor = data.color
	local colorPicker = Widgets.CreateColorPicker(inner, 'Color', true, function(r, g, b, a)
		update('color', { r, g, b, a })
	end)
	colorPicker:SetColor(ovColor[1], ovColor[2], ovColor[3], ovColor[4] or 1)
	cardY = placeWidget(colorPicker, inner, cardY, DROPDOWN_H)

	-- Conditional: DurationOverlay or Both — smooth animation + bar orientation
	local ovMode = data.overlayMode
	if(ovMode == 'DurationOverlay' or ovMode == 'Both') then
		local smoothSwitch = Widgets.CreateCheckButton(inner, 'Smooth Animation', function(checked)
			update('smooth', checked)
		end)
		smoothSwitch:SetChecked(data.smooth ~= false)
		cardY = placeWidget(smoothSwitch, inner, cardY, CHECK_H)

		local BAR_ORIENTATION_ITEMS = {
			{ text = 'Horizontal', value = 'Horizontal' },
			{ text = 'Vertical',   value = 'Vertical' },
		}
		local barOriDD = Widgets.CreateDropdown(inner, widgetW)
		barOriDD:SetItems(BAR_ORIENTATION_ITEMS)
		barOriDD:SetValue(data.barOrientation)
		barOriDD:SetOnSelect(function(v) update('barOrientation', v) end)
		cardY = placeWidget(barOriDD, inner, cardY, DROPDOWN_H)
	end

	Widgets.EndCard(card, parent, cardY)
	return card
end

-- ── Duration (Bar/Bars) ─────────────────────────────────────
function Builders.Duration(parent, width, data, update, get, set)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local DURATION_MODE_ITEMS = {
		{ text = 'Never',   value = 'Never' },
		{ text = 'Always',  value = 'Always' },
		{ text = '< 75%',   value = '<75%' },
		{ text = '< 50%',   value = '<50%' },
		{ text = '< 25%',   value = '<25%' },
		{ text = '< 15s',   value = '<15s' },
		{ text = '< 5s',    value = '<5s' },
	}

	local durDD = Widgets.CreateDropdown(inner, widgetW)
	durDD:SetItems(DURATION_MODE_ITEMS)
	durDD:SetValue(data.durationMode)
	durDD:SetOnSelect(function(v) update('durationMode', v) end)
	cardY = placeWidget(durDD, inner, cardY, DROPDOWN_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end

-- ── Border Mode (Border/Glow switch) ──────────────────────────
function Builders.BorderMode(parent, width, data, update, get, set, rebuildPanel)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local modeSwitch = Widgets.CreateSwitch(inner, widgetW, BUTTON_H, {
		{ text = 'Border', value = 'Border' },
		{ text = 'Glow',   value = 'Glow' },
	})
	modeSwitch:SetValue(data.borderGlowMode or 'Border')
	modeSwitch:SetOnSelect(function(v)
		update('borderGlowMode', v)
		if(rebuildPanel) then rebuildPanel() end
	end)
	cardY = placeWidget(modeSwitch, inner, cardY, BUTTON_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end

-- ── Border Appearance (mode-dependent settings) ───────────────
function Builders.BorderAppearance(parent, width, data, update, get, set)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2
	local bgMode = data.borderGlowMode or 'Border'

	-- Fade Out (shared, always first)
	local fadeCheck = Widgets.CreateCheckButton(inner, 'Fade Out', function(checked)
		update('fadeOut', checked)
	end)
	fadeCheck:SetChecked(data.fadeOut == true)
	cardY = placeWidget(fadeCheck, inner, cardY, CHECK_H)

	if(bgMode == 'Border') then
		-- Color
		local borColor = data.color or { 1, 1, 1, 1 }
		local borColorPicker = Widgets.CreateColorPicker(inner, 'Color', true, function(r, g, b, a)
			update('color', { r, g, b, a })
		end)
		borColorPicker:SetColor(borColor[1], borColor[2], borColor[3], borColor[4] or 1)
		cardY = placeWidget(borColorPicker, inner, cardY, DROPDOWN_H)

		-- Thickness
		local thkSlider = Widgets.CreateSlider(inner, 'Thickness', widgetW, 1, 15, 1)
		thkSlider:SetValue(data.borderThickness or 2)
		thkSlider:SetAfterValueChanged(function(v) update('borderThickness', v) end)
		cardY = placeWidget(thkSlider, inner, cardY, SLIDER_H)
	else
		-- Glow color
		local glowColor = get('glowColor') or { 1, 1, 1, 1 }
		local colorPicker = Widgets.CreateColorPicker(inner, 'Color', true, function(r, g, b, a)
			set('glowColor', { r, g, b, a })
		end)
		colorPicker:SetColor(glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 1)
		cardY = placeWidget(colorPicker, inner, cardY, DROPDOWN_H)

		-- Glow type dropdown (frame-level glows only: Pixel and Shine)
		local typeDD = Widgets.CreateDropdown(inner, widgetW)
		typeDD:SetItems({
			{ text = 'Pixel', value = C.GlowType.PIXEL },
			{ text = 'Shine', value = C.GlowType.SHINE },
		})
		typeDD:SetValue(get('glowType') or C.GlowType.PIXEL)
		typeDD:SetOnSelect(function(value) set('glowType', value) end)
		cardY = placeWidget(typeDD, inner, cardY, DROPDOWN_H)
	end

	Widgets.EndCard(card, parent, cardY)
	return card
end

-- ── Border Position (frame level only, no anchor picker) ──────
function Builders.BorderPosition(parent, width, data, update, get, set)
	local _, card = F.Settings.BuildPositionCard(parent, width, 0, get, set, { noHeading = true, hidePosition = true })
	return card
end

-- ============================================================
-- Type → Card mapping
-- Each entry: { cardId, cardTitle, builderFn }
-- The panel iterates this to spawn cards for the active indicator.
-- ============================================================

Builders.CARDS_FOR_TYPE = {
	[C.IndicatorType.ICONS] = {
		{ 'castBy',           'Cast By',             Builders.CastBy },
		{ 'trackedSpells',    'Tracked Spells',      Builders.TrackedSpells },
		{ 'appearance',       'Appearance',          Builders.Appearance },
		{ 'layout',           'Layout',              Builders.Layout },
		{ 'cooldownDuration', 'Cooldown & Duration', Builders.CooldownDuration },
		{ 'stacks',           'Stacks',              Builders.Stacks },
		{ 'glow',             'Border Glow',         'SharedGlow' },
	},
	[C.IndicatorType.ICON] = {
		{ 'castBy',           'Cast By',             Builders.CastBy },
		{ 'trackedSpells',    'Tracked Spells',      Builders.TrackedSpells },
		{ 'appearance',       'Appearance',          Builders.Appearance },
		{ 'position',         'Position',            'SharedPosition' },
		{ 'cooldownDuration', 'Cooldown & Duration', Builders.CooldownDuration },
		{ 'stacks',           'Stacks',              Builders.Stacks },
		{ 'glow',             'Border Glow',         'SharedGlow' },
	},
	[C.IndicatorType.BARS] = {
		{ 'castBy',           'Cast By',        Builders.CastBy },
		{ 'trackedSpells',    'Tracked Spells',  Builders.TrackedSpells },
		{ 'size',             'Size',            Builders.Size },
		{ 'layout',           'Layout',          Builders.Layout },
		{ 'thresholdColors',  'Colors',          'SharedThresholdColors' },
		{ 'duration',         'Duration',        Builders.Duration },
		{ 'stacks',           'Stacks',          Builders.Stacks },
		{ 'glow',             'Border Glow',     'SharedGlow' },
	},
	[C.IndicatorType.BAR] = {
		{ 'castBy',           'Cast By',        Builders.CastBy },
		{ 'trackedSpells',    'Tracked Spells',  Builders.TrackedSpells },
		{ 'size',             'Size',            Builders.Size },
		{ 'layout',           'Layout',          Builders.Layout },
		{ 'thresholdColors',  'Colors',          'SharedThresholdColors' },
		{ 'duration',         'Duration',        Builders.Duration },
		{ 'stacks',           'Stacks',          Builders.Stacks },
		{ 'glow',             'Border Glow',     'SharedGlow' },
	},
	[C.IndicatorType.RECTANGLE] = {
		{ 'size',             'Size',       Builders.Size },
		{ 'thresholdColors',  nil,          'SharedThresholdColors' },
		{ 'stacks',           'Stacks',     Builders.Stacks },
		{ 'glow',             'Border Glow', 'SharedGlow' },
		{ 'position',         'Position',   'SharedPosition' },
	},
	[C.IndicatorType.OVERLAY] = {
		{ 'castBy',           'Cast By',    Builders.CastBy },
		{ 'trackedSpells',    'Tracked Spells', Builders.TrackedSpells },
		{ 'mode',             'Mode',       Builders.Mode },
		{ 'thresholdColors',  'Colors',     'SharedThresholdColors' },
	},
	[C.IndicatorType.BORDER] = {
		{ 'castBy',             'Cast By',              Builders.CastBy },
		{ 'trackedSpells',      'Tracked Spells',       Builders.TrackedSpells },
		{ 'borderMode',         'Mode',                 Builders.BorderMode },
		{ 'borderAppearance',   'Settings',             Builders.BorderAppearance },
		{ 'position',           'Position',             Builders.BorderPosition },
	},
}

-- Helper: string markers like 'SharedGlow' are resolved at spawn time
-- to call F.Settings.BuildGlowCard, BuildPositionCard, BuildThresholdColorCard
-- wrapped in a CardGrid-compatible builder.

-- ============================================================
-- Shared card wrappers for CardGrid
-- These adapt the yOffset-based SharedCards builders to return
-- a card frame like CardGrid expects.
-- ============================================================

function Builders.SharedGlow(parent, width, data, update, get, set)
	local _, card = F.Settings.BuildGlowCard(parent, width, 0, get, set, { allowNone = true, noHeading = true })
	return card
end

function Builders.SharedPosition(parent, width, data, update, get, set)
	local _, card = F.Settings.BuildPositionCard(parent, width, 0, get, set, { noHeading = true })
	return card
end

function Builders.SharedThresholdColors(parent, width, data, update, get, set, opts)
	local tcOpts = { noHeading = true }
	if(data.type == C.IndicatorType.BAR or data.type == C.IndicatorType.BARS) then
		tcOpts.showBorderColor = true
		tcOpts.showBgColor = true
		tcOpts.hideBaseColor = true
	elseif(data.type == C.IndicatorType.RECTANGLE) then
		tcOpts.showBorderColor = true
	end
	local _, card = F.Settings.BuildThresholdColorCard(parent, width, 0, get, set, tcOpts)
	return card
end
