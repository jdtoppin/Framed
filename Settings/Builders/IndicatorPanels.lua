local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings = F.Settings or {}
F.Settings.Builders = F.Settings.Builders or {}

-- ============================================================
-- Layout constants (shared with IndicatorCRUD)
-- ============================================================
local SLIDER_H     = 26
local CHECK_H      = 22
local DROPDOWN_H   = 22
local WIDGET_W     = 220

-- ============================================================
-- Layout helpers
-- ============================================================
local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

local function placeHeading(content, text, level, yOffset)
	local heading, height = Widgets.CreateHeading(content, text, level)
	heading:ClearAllPoints()
	Widgets.SetPoint(heading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height
end

-- ============================================================
-- Shared dropdown item tables
-- ============================================================
local DURATION_MODE_ITEMS = {
	{ text = 'Never',  value = 'Never' },
	{ text = 'Always', value = 'Always' },
	{ text = '< 75%',  value = '<75' },
	{ text = '< 50%',  value = '<50' },
	{ text = '< 25%',  value = '<25' },
	{ text = '< 15s',  value = '<15s' },
	{ text = '< 5s',   value = '<5s' },
}

local ORIENTATION_ITEMS = {
	{ text = 'Right', value = 'RIGHT' },
	{ text = 'Left',  value = 'LEFT' },
	{ text = 'Up',    value = 'UP' },
	{ text = 'Down',  value = 'DOWN' },
}

local BAR_ORIENTATION_ITEMS = {
	{ text = 'Horizontal', value = 'Horizontal' },
	{ text = 'Vertical',   value = 'Vertical' },
}

-- ============================================================
-- Build type-specific indicator settings
-- ============================================================
function F.Settings.Builders.BuildIndicatorSettings(parent, width, yOffset, name, data, setIndicator)
	local function update(key, value)
		data[key] = value
		setIndicator(name, data)
	end

	-- get/set wrappers for SharedCards
	local function get(key) return data[key] end
	local function set(key, value) update(key, value) end

	-- ── Cast By card ─────────────────────────────────────
	yOffset = placeHeading(parent, 'Cast By', 2, yOffset)

	local cbCard, cbInner, cbY = Widgets.StartCard(parent, width, yOffset)

	local castByDD = Widgets.CreateDropdown(cbInner, WIDGET_W)
	castByDD:SetItems({
		{ text = 'Me',      value = C.CastFilter.ME },
		{ text = 'Others',  value = C.CastFilter.OTHERS },
		{ text = 'Anyone',  value = C.CastFilter.ANYONE },
	})
	castByDD:SetValue(data.castBy or C.CastFilter.ME)
	castByDD:SetOnSelect(function(value) update('castBy', value) end)
	cbY = placeWidget(castByDD, cbInner, cbY, DROPDOWN_H)

	yOffset = Widgets.EndCard(cbCard, parent, cbY)

	-- ── Tracked Spells card ───────────────────────────────
	yOffset = placeHeading(parent, 'Tracked Spells', 2, yOffset)

	local spCard, spInner, spY = Widgets.StartCard(parent, width, yOffset)

	local spList = Widgets.CreateSpellList(spInner, width - 24, 120)
	spY = placeWidget(spList, spInner, spY, 120)
	spList:SetSpells(data.spells or {})
	spList:SetOnChanged(function(spells) update('spells', spells) end)

	local spInput = Widgets.CreateSpellInput(spInner, width - 24)
	spY = placeWidget(spInput, spInner, spY, 50)
	spInput:SetSpellList(spList)
	spInput:SetOnAdd(function() update('spells', spList:GetSpells()) end)

	local importBtn = Widgets.CreateButton(spInner, 'Import Healer Spells', 'widget', 160, 24)
	spY = placeWidget(importBtn, spInner, spY, 24)
	importBtn:SetOnClick(function()
		F.Settings.Builders.ShowImportPopup(function(selectedSpells)
			if(not selectedSpells or #selectedSpells == 0) then return end
			local existing = spList:GetSpells()
			for _, spellID in next, selectedSpells do
				existing[#existing + 1] = spellID
			end
			spList:SetSpells(existing)
			update('spells', existing)
		end)
	end)

	local deleteAllBtn = Widgets.CreateButton(spInner, 'Delete All Spells', 'red', 140, 24)
	deleteAllBtn:SetPoint('LEFT', importBtn, 'RIGHT', C.Spacing.tight, 0)
	deleteAllBtn:SetOnClick(function()
		Widgets.ShowConfirmDialog('Delete All Spells', 'Remove all tracked spells from this indicator?', function()
			spList:SetSpells({})
			update('spells', {})
		end)
	end)

	yOffset = Widgets.EndCard(spCard, parent, spY)

	-- ── Type-specific settings ────────────────────────────
	local iType = data.type

	if(iType == C.IndicatorType.ICON or iType == C.IndicatorType.ICONS) then
		-- Size card
		yOffset = placeHeading(parent, 'Size', 2, yOffset)
		local szCard, szInner, szY = Widgets.StartCard(parent, width, yOffset)

		local wSlider = Widgets.CreateSlider(szInner, 'Width', WIDGET_W, 8, 48, 1)
		wSlider:SetValue(data.iconWidth or 16)
		wSlider:SetAfterValueChanged(function(v) update('iconWidth', v) end)
		szY = placeWidget(wSlider, szInner, szY, SLIDER_H)

		local hSlider = Widgets.CreateSlider(szInner, 'Height', WIDGET_W, 8, 48, 1)
		hSlider:SetValue(data.iconHeight or 16)
		hSlider:SetAfterValueChanged(function(v) update('iconHeight', v) end)
		szY = placeWidget(hSlider, szInner, szY, SLIDER_H)

		yOffset = Widgets.EndCard(szCard, parent, szY)

		-- Layout card (Icons only)
		if(iType == C.IndicatorType.ICONS) then
			yOffset = placeHeading(parent, 'Layout', 2, yOffset)
			local layCard, layInner, layY = Widgets.StartCard(parent, width, yOffset)

			local mxSlider = Widgets.CreateSlider(layInner, 'Max Displayed', WIDGET_W, 1, 10, 1)
			mxSlider:SetValue(data.maxDisplayed or 3)
			mxSlider:SetAfterValueChanged(function(v) update('maxDisplayed', v) end)
			layY = placeWidget(mxSlider, layInner, layY, SLIDER_H)

			local nplSlider = Widgets.CreateSlider(layInner, 'Num Per Line', WIDGET_W, 0, 10, 1)
			nplSlider:SetValue(data.numPerLine or 0)
			nplSlider:SetAfterValueChanged(function(v) update('numPerLine', v) end)
			layY = placeWidget(nplSlider, layInner, layY, SLIDER_H)

			local spxSlider = Widgets.CreateSlider(layInner, 'Spacing X', WIDGET_W, 0, 20, 1)
			spxSlider:SetValue(data.spacingX or 2)
			spxSlider:SetAfterValueChanged(function(v) update('spacingX', v) end)
			layY = placeWidget(spxSlider, layInner, layY, SLIDER_H)

			local spySlider = Widgets.CreateSlider(layInner, 'Spacing Y', WIDGET_W, 0, 20, 1)
			spySlider:SetValue(data.spacingY or 2)
			spySlider:SetAfterValueChanged(function(v) update('spacingY', v) end)
			layY = placeWidget(spySlider, layInner, layY, SLIDER_H)

			local oriDD = Widgets.CreateDropdown(layInner, WIDGET_W)
			oriDD:SetItems(ORIENTATION_ITEMS)
			oriDD:SetValue(data.orientation or 'RIGHT')
			oriDD:SetOnSelect(function(v) update('orientation', v) end)
			layY = placeWidget(oriDD, layInner, layY, DROPDOWN_H)

			yOffset = Widgets.EndCard(layCard, parent, layY)
		end

		-- Cooldown & Duration card
		yOffset = placeHeading(parent, 'Cooldown & Duration', 2, yOffset)
		local cdCard, cdInner, cdY = Widgets.StartCard(parent, width, yOffset)

		local cdSwitch = Widgets.CreateCheckButton(cdInner, 'Show Cooldown', function(checked)
			update('showCooldown', checked)
		end)
		cdSwitch:SetChecked(data.showCooldown ~= false)
		cdY = placeWidget(cdSwitch, cdInner, cdY, CHECK_H)

		local durDD = Widgets.CreateDropdown(cdInner, WIDGET_W)
		durDD:SetItems(DURATION_MODE_ITEMS)
		durDD:SetValue(data.durationMode or 'Never')
		durDD:SetOnSelect(function(v) update('durationMode', v) end)
		cdY = placeWidget(durDD, cdInner, cdY, DROPDOWN_H)

		yOffset = Widgets.EndCard(cdCard, parent, cdY)

		-- Duration font (shown when durationMode != Never)
		if(data.durationMode and data.durationMode ~= 'Never') then
			yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Duration Font', 'durationFont', get, set)
		end

		-- Stack card
		yOffset = placeHeading(parent, 'Stacks', 2, yOffset)
		local stCard, stInner, stY = Widgets.StartCard(parent, width, yOffset)

		local stSwitch = Widgets.CreateCheckButton(stInner, 'Show Stacks', function(checked)
			update('showStacks', checked)
		end)
		stSwitch:SetChecked(data.showStacks == true)
		stY = placeWidget(stSwitch, stInner, stY, CHECK_H)

		yOffset = Widgets.EndCard(stCard, parent, stY)

		if(data.showStacks) then
			yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Stack Font', 'stackFont', get, set)
		end

		-- Glow card
		yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = true })

		-- Position card
		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set)

	elseif(iType == C.IndicatorType.BAR or iType == C.IndicatorType.BARS) then
		-- Size card
		yOffset = placeHeading(parent, 'Size', 2, yOffset)
		local szCard, szInner, szY = Widgets.StartCard(parent, width, yOffset)

		local bwSlider = Widgets.CreateSlider(szInner, 'Width', WIDGET_W, 3, 500, 1)
		bwSlider:SetValue(data.barWidth or 100)
		bwSlider:SetAfterValueChanged(function(v) update('barWidth', v) end)
		szY = placeWidget(bwSlider, szInner, szY, SLIDER_H)

		local bhSlider = Widgets.CreateSlider(szInner, 'Height', WIDGET_W, 3, 500, 1)
		bhSlider:SetValue(data.barHeight or 4)
		bhSlider:SetAfterValueChanged(function(v) update('barHeight', v) end)
		szY = placeWidget(bhSlider, szInner, szY, SLIDER_H)

		local barOriDD = Widgets.CreateDropdown(szInner, WIDGET_W)
		barOriDD:SetItems(BAR_ORIENTATION_ITEMS)
		barOriDD:SetValue(data.barOrientation or 'Horizontal')
		barOriDD:SetOnSelect(function(v) update('barOrientation', v) end)
		szY = placeWidget(barOriDD, szInner, szY, DROPDOWN_H)

		yOffset = Widgets.EndCard(szCard, parent, szY)

		-- Layout card (Bars only)
		if(iType == C.IndicatorType.BARS) then
			yOffset = placeHeading(parent, 'Layout', 2, yOffset)
			local layCard, layInner, layY = Widgets.StartCard(parent, width, yOffset)

			local mxSlider = Widgets.CreateSlider(layInner, 'Max Displayed', WIDGET_W, 1, 10, 1)
			mxSlider:SetValue(data.maxDisplayed or 3)
			mxSlider:SetAfterValueChanged(function(v) update('maxDisplayed', v) end)
			layY = placeWidget(mxSlider, layInner, layY, SLIDER_H)

			local nplSlider = Widgets.CreateSlider(layInner, 'Num Per Line', WIDGET_W, 0, 10, 1)
			nplSlider:SetValue(data.numPerLine or 0)
			nplSlider:SetAfterValueChanged(function(v) update('numPerLine', v) end)
			layY = placeWidget(nplSlider, layInner, layY, SLIDER_H)

			local spxSlider = Widgets.CreateSlider(layInner, 'Spacing X', WIDGET_W, -1, 50, 1)
			spxSlider:SetValue(data.spacingX or 2)
			spxSlider:SetAfterValueChanged(function(v) update('spacingX', v) end)
			layY = placeWidget(spxSlider, layInner, layY, SLIDER_H)

			local spySlider = Widgets.CreateSlider(layInner, 'Spacing Y', WIDGET_W, -1, 50, 1)
			spySlider:SetValue(data.spacingY or 2)
			spySlider:SetAfterValueChanged(function(v) update('spacingY', v) end)
			layY = placeWidget(spySlider, layInner, layY, SLIDER_H)

			local dirDD = Widgets.CreateDropdown(layInner, WIDGET_W)
			dirDD:SetItems(ORIENTATION_ITEMS)
			dirDD:SetValue(data.orientation or 'DOWN')
			dirDD:SetOnSelect(function(v) update('orientation', v) end)
			layY = placeWidget(dirDD, layInner, layY, DROPDOWN_H)

			yOffset = Widgets.EndCard(layCard, parent, layY)
		end

		-- Threshold color card
		yOffset = F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set, { showBorderColor = true, showBgColor = true })

		-- Duration dropdown
		yOffset = placeHeading(parent, 'Duration', 2, yOffset)
		local durCard, durInner, durY = Widgets.StartCard(parent, width, yOffset)

		local durDD = Widgets.CreateDropdown(durInner, WIDGET_W)
		durDD:SetItems(DURATION_MODE_ITEMS)
		durDD:SetValue(data.durationMode or 'Never')
		durDD:SetOnSelect(function(v) update('durationMode', v) end)
		durY = placeWidget(durDD, durInner, durY, DROPDOWN_H)

		yOffset = Widgets.EndCard(durCard, parent, durY)

		if(data.durationMode and data.durationMode ~= 'Never') then
			yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Duration Font', 'durationFont', get, set)
		end

		-- Stack card
		yOffset = placeHeading(parent, 'Stacks', 2, yOffset)
		local stCard, stInner, stY = Widgets.StartCard(parent, width, yOffset)

		local stSwitch = Widgets.CreateCheckButton(stInner, 'Show Stacks', function(checked)
			update('showStacks', checked)
		end)
		stSwitch:SetChecked(data.showStacks == true)
		stY = placeWidget(stSwitch, stInner, stY, CHECK_H)

		yOffset = Widgets.EndCard(stCard, parent, stY)

		if(data.showStacks) then
			yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Stack Font', 'stackFont', get, set)
		end

		-- Glow + Position
		yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = true })
		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set)

	elseif(iType == C.IndicatorType.COLOR) then
		-- Size card
		yOffset = placeHeading(parent, 'Size', 2, yOffset)
		local szCard, szInner, szY = Widgets.StartCard(parent, width, yOffset)

		local rwSlider = Widgets.CreateSlider(szInner, 'Width', WIDGET_W, 3, 500, 1)
		rwSlider:SetValue(data.rectWidth or 10)
		rwSlider:SetAfterValueChanged(function(v) update('rectWidth', v) end)
		szY = placeWidget(rwSlider, szInner, szY, SLIDER_H)

		local rhSlider = Widgets.CreateSlider(szInner, 'Height', WIDGET_W, 3, 500, 1)
		rhSlider:SetValue(data.rectHeight or 10)
		rhSlider:SetAfterValueChanged(function(v) update('rectHeight', v) end)
		szY = placeWidget(rhSlider, szInner, szY, SLIDER_H)

		yOffset = Widgets.EndCard(szCard, parent, szY)

		-- Threshold colors with border
		yOffset = F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set, { showBorderColor = true })

		-- Stack card
		yOffset = placeHeading(parent, 'Stacks', 2, yOffset)
		local stCard, stInner, stY = Widgets.StartCard(parent, width, yOffset)

		local stSwitch = Widgets.CreateCheckButton(stInner, 'Show Stacks', function(checked)
			update('showStacks', checked)
		end)
		stSwitch:SetChecked(data.showStacks == true)
		stY = placeWidget(stSwitch, stInner, stY, CHECK_H)

		yOffset = Widgets.EndCard(stCard, parent, stY)

		if(data.showStacks) then
			yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Stack Font', 'stackFont', get, set)
		end

		-- Glow + Position
		yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = true })
		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set)

	elseif(iType == C.IndicatorType.OVERLAY) then
		-- Mode card
		yOffset = placeHeading(parent, 'Overlay Mode', 2, yOffset)
		local modeCard, modeInner, modeY = Widgets.StartCard(parent, width, yOffset)

		local modeDD = Widgets.CreateDropdown(modeInner, WIDGET_W)
		modeDD:SetItems({
			{ text = 'Overlay',  value = 'Overlay' },
			{ text = 'FrameBar', value = 'FrameBar' },
			{ text = 'Both',     value = 'Both' },
		})
		modeDD:SetValue(data.overlayMode or 'Overlay')
		modeDD:SetOnSelect(function(v) update('overlayMode', v) end)
		modeY = placeWidget(modeDD, modeInner, modeY, DROPDOWN_H)

		local ovColor = data.color or { 0, 0, 0, 0.6 }
		local colorPicker = Widgets.CreateColorPicker(modeInner, 'Color', true, function(r, g, b, a)
			update('color', { r, g, b, a })
		end)
		colorPicker:SetColor(ovColor[1], ovColor[2], ovColor[3], ovColor[4] or 1)
		modeY = placeWidget(colorPicker, modeInner, modeY, DROPDOWN_H)

		yOffset = Widgets.EndCard(modeCard, parent, modeY)

		-- Conditional: Overlay or Both — threshold colors + smooth + bar orientation
		local ovMode = data.overlayMode or 'Overlay'
		if(ovMode == 'Overlay' or ovMode == 'Both') then
			yOffset = F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set, {})

			yOffset = placeHeading(parent, 'Animation', 2, yOffset)
			local animCard, animInner, animY = Widgets.StartCard(parent, width, yOffset)

			local smoothSwitch = Widgets.CreateCheckButton(animInner, 'Smooth Animation', function(checked)
				update('smooth', checked)
			end)
			smoothSwitch:SetChecked(data.smooth ~= false)
			animY = placeWidget(smoothSwitch, animInner, animY, CHECK_H)

			local barOriDD = Widgets.CreateDropdown(animInner, WIDGET_W)
			barOriDD:SetItems(BAR_ORIENTATION_ITEMS)
			barOriDD:SetValue(data.barOrientation or 'Horizontal')
			barOriDD:SetOnSelect(function(v) update('barOrientation', v) end)
			animY = placeWidget(barOriDD, animInner, animY, DROPDOWN_H)

			yOffset = Widgets.EndCard(animCard, parent, animY)
		end

		-- Position (frame level only)
		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set, { hidePosition = true })

	elseif(iType == C.IndicatorType.BORDER) then
		-- Border settings card
		yOffset = placeHeading(parent, 'Border Settings', 2, yOffset)
		local borCard, borInner, borY = Widgets.StartCard(parent, width, yOffset)

		local thkSlider = Widgets.CreateSlider(borInner, 'Thickness', WIDGET_W, 1, 15, 1)
		thkSlider:SetValue(data.borderThickness or 2)
		thkSlider:SetAfterValueChanged(function(v) update('borderThickness', v) end)
		borY = placeWidget(thkSlider, borInner, borY, SLIDER_H)

		local borColor = data.color or { 1, 1, 1, 1 }
		local colorPicker = Widgets.CreateColorPicker(borInner, 'Color', true, function(r, g, b, a)
			update('color', { r, g, b, a })
		end)
		colorPicker:SetColor(borColor[1], borColor[2], borColor[3], borColor[4] or 1)
		borY = placeWidget(colorPicker, borInner, borY, DROPDOWN_H)

		local fadeSwitch = Widgets.CreateCheckButton(borInner, 'Fade Out', function(checked)
			update('fadeOut', checked)
		end)
		fadeSwitch:SetChecked(data.fadeOut == true)
		borY = placeWidget(fadeSwitch, borInner, borY, CHECK_H)

		yOffset = Widgets.EndCard(borCard, parent, borY)

		-- Position (frame level only)
		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set, { hidePosition = true })

	elseif(iType == C.IndicatorType.GLOW) then
		-- Fade Out + Glow type card
		yOffset = placeHeading(parent, 'Glow Settings', 2, yOffset)
		local glowSettCard, glowSettInner, glowSettY = Widgets.StartCard(parent, width, yOffset)

		local fadeSwitch = Widgets.CreateCheckButton(glowSettInner, 'Fade Out', function(checked)
			update('fadeOut', checked)
		end)
		fadeSwitch:SetChecked(data.fadeOut == true)
		glowSettY = placeWidget(fadeSwitch, glowSettInner, glowSettY, CHECK_H)

		yOffset = Widgets.EndCard(glowSettCard, parent, glowSettY)

		-- Glow card (no None)
		yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = false })

		-- Position (frame level only)
		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set, { hidePosition = true })

	elseif(iType == C.IndicatorType.FRAME_BAR) then
		-- Legacy Frame Bar — basic bar height + position
		yOffset = placeHeading(parent, 'Bar Settings', 2, yOffset)
		local barCard, barInner, barY = Widgets.StartCard(parent, width, yOffset)

		local bh = Widgets.CreateSlider(barInner, 'Bar Height', WIDGET_W, 2, 20, 1)
		bh:SetValue(data.barHeight or 4)
		bh:SetAfterValueChanged(function(v) update('barHeight', v) end)
		barY = placeWidget(bh, barInner, barY, SLIDER_H)

		yOffset = Widgets.EndCard(barCard, parent, barY)

		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set, { hidePosition = true })
	end

	return yOffset
end
