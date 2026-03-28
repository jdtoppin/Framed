local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- FrameSettingsBuilder
-- Shared factory that builds a scrollable settings panel for a
-- given unit type. Called by each thin panel registration file.
-- Group types (party/raid/battleground/worldraid) show extra
-- group-specific fields (spacing, orientation, growth direction).
-- ============================================================

F.FrameSettingsBuilder = {}

-- ============================================================
-- Constants
-- ============================================================

local GROUP_TYPES = {
	party        = true,
	raid         = true,
	battleground = true,
	worldraid    = true,
}

-- Unit types whose health bar uses oUF's full UpdateColor chain.
-- These frames do NOT show the Health Bar Color section in settings.
local NPC_FRAME_TYPES = {
	target       = true,
	targettarget = true,
	focus        = true,
	pet          = true,
	boss         = true,
}

-- Widget heights (used for vertical layout accounting)
local SLIDER_H       = 26   -- labelH(14) + TRACK_THICKNESS(6) + 6
local SWITCH_H       = 22
local DROPDOWN_H     = 22
local CHECK_H        = 14
local PANE_TITLE_H   = 20   -- approx title font + separator + gap

-- Width for sliders and dropdowns inside the panel
local WIDGET_W       = 220

-- ============================================================
-- Layout helpers
-- ============================================================

--- Place a widget at the running yOffset, anchored to the scroll content frame.
--- Returns the next yOffset after accounting for the widget's height.
--- @param widget  Frame   Widget to position
--- @param content Frame   Scroll content frame
--- @param yOffset number  Running yOffset (negative, relative to content)
--- @param height  number  Widget height
--- @return number nextYOffset
local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

--- Place a heading at the given level and return the updated yOffset.
--- @param content Frame   Scroll content frame
--- @param text    string  Heading text
--- @param level   number  1, 2, or 3
--- @param yOffset number  Running yOffset
--- @param width?  number  Available width (needed for level 1 separator)
--- @return number nextYOffset
local function placeHeading(content, text, level, yOffset, width)
	local heading, height = Widgets.CreateHeading(content, text, level, width)
	heading:ClearAllPoints()
	Widgets.SetPoint(heading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height
end

-- ============================================================
-- FrameSettingsBuilder.Create
-- ============================================================

--- Build and return a scrollable settings panel for unitType.
--- @param parent   Frame   Content parent provided by Settings.RegisterPanel
--- @param unitType string  Unit identifier (e.g. 'player', 'party', 'raid')
--- @return Frame
function F.FrameSettingsBuilder.Create(parent, unitType)
	local isGroup = GROUP_TYPES[unitType] or false

	-- ── Scroll frame wrapping the whole panel ─────────────────
	local parentW = parent._explicitWidth or parent:GetWidth() or 530
	local parentH = parent._explicitHeight or parent:GetHeight() or 400
	local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
	scroll:SetAllPoints(parent)

	local content = scroll:GetContentFrame()
	content:SetWidth(parentW)
	local width = parentW - C.Spacing.normal * 2

	-- Tag scroll frame with the preset it was built for (used by callers for invalidation)
	scroll._builtForPreset = F.Settings.GetEditingPreset()

	-- ── Config accessor helpers ────────────────────────────────
	local function getPresetName()
		return F.Settings.GetEditingPreset()
	end

	local function getConfig(key)
		if(F.EditCache and F.EditCache.IsActive()) then
			return F.EditCache.Get(unitType, key)
		end
		return F.Config:Get('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key)
	end
	local function setConfig(key, value)
		if(F.EditCache and F.EditCache.IsActive()) then
			F.EditCache.Set(unitType, key, value)
			return
		end
		F.Config:Set('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key, value)
		F.PresetManager.MarkCustomized(getPresetName())
	end

	-- Running layout cursor (negative = downward from TOPLEFT)
	local yOffset = -C.Spacing.normal

	-- ── Scoped preset banner ───────────────────────────────────
	local banner = Widgets.CreateFontString(content, C.Font.sizeSmall, C.Colors.accent)
	banner:SetText('These settings apply to: ' .. getPresetName() .. ' Frame Preset')
	Widgets.SetPoint(banner, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - 16 - C.Spacing.tight

	-- ============================================================
	-- Position & Layout
	-- ============================================================

	yOffset = placeHeading(content, 'Position & Layout', 2, yOffset)

	local posCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	-- Width slider
	local widthSlider = Widgets.CreateSlider(inner, 'Width', WIDGET_W, 20, 300, 1)
	widthSlider:SetValue(getConfig('width') or 200)
	widthSlider:SetAfterValueChanged(function(value)
		setConfig('width', value)
	end)
	cardY = placeWidget(widthSlider, inner, cardY, SLIDER_H)

	-- Height slider
	local heightSlider = Widgets.CreateSlider(inner, 'Height', WIDGET_W, 16, 100, 1)
	heightSlider:SetValue(getConfig('height') or 36)
	heightSlider:SetAfterValueChanged(function(value)
		setConfig('height', value)
	end)
	cardY = placeWidget(heightSlider, inner, cardY, SLIDER_H)

	-- Resize Anchor picker — controls which corner stays fixed during resize
	local raHeading, raHeadingH = Widgets.CreateHeading(inner, 'Resize Anchor', 3)
	raHeading:ClearAllPoints()
	Widgets.SetPoint(raHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
	cardY = cardY - raHeadingH

	local anchorInfo = Widgets.CreateInfoIcon(inner,
		'Resize Anchor',
		'Controls which corner or edge of the frame stays fixed when you change '
		.. 'the width or height. For example, TOPLEFT means the top-left corner '
		.. 'stays pinned and the frame grows right and downward.')
	anchorInfo:SetPoint('LEFT', raHeading, 'RIGHT', 4, 0)

	local anchorPicker = Widgets.CreateAnchorPicker(inner, WIDGET_W)
	local savedAnchor = getConfig('position.anchor') or 'CENTER'
	anchorPicker._xInput:Hide()
	anchorPicker._yInput:Hide()
	anchorPicker:SetAnchor(savedAnchor, 0, 0)
	anchorPicker:SetOnChanged(function(point)
		setConfig('position.anchor', point)
	end)
	cardY = placeWidget(anchorPicker, inner, cardY, 56)

	-- Read the actual frame position from config
	local actualX = getConfig('position.x') or 0
	local actualY = getConfig('position.y') or 0

	-- Frame Position sliders (X / Y)
	cardY = placeHeading(inner, 'Frame Position', 3, cardY)

	local posXSlider = Widgets.CreateSlider(inner, 'X', WIDGET_W, -1000, 1000, 1)
	posXSlider:SetValue(actualX)
	posXSlider:SetAfterValueChanged(function(value)
		setConfig('position.x', value)
	end)
	cardY = placeWidget(posXSlider, inner, cardY, SLIDER_H)

	local posYSlider = Widgets.CreateSlider(inner, 'Y', WIDGET_W, -1000, 1000, 1)
	posYSlider:SetValue(actualY)
	posYSlider:SetAfterValueChanged(function(value)
		setConfig('position.y', value)
	end)
	cardY = placeWidget(posYSlider, inner, cardY, SLIDER_H)

	-- Pixel nudge arrows
	cardY = placeHeading(inner, 'Pixel Nudge', 3, cardY)

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

	cardY = placeWidget(nudgeFrame, inner, cardY, 50)

	yOffset = Widgets.EndCard(posCard, content, cardY)

	if(isGroup) then
		-- ── Group Layout ──────────────────────────────────────
		yOffset = placeHeading(content, 'Group Layout', 2, yOffset)

		local groupCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

		-- Spacing slider
		local spacingSlider = Widgets.CreateSlider(inner, 'Spacing', WIDGET_W, 0, 20, 1)
		spacingSlider:SetValue(getConfig('spacing') or 2)
		spacingSlider:SetAfterValueChanged(function(value)
			setConfig('spacing', value)
		end)
		cardY = placeWidget(spacingSlider, inner, cardY, SLIDER_H)

		-- Orientation switch
		cardY = placeHeading(inner, 'Orientation', 3, cardY)
		local orientSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
			{ text = 'Vertical',   value = 'vertical' },
			{ text = 'Horizontal', value = 'horizontal' },
		})
		orientSwitch:SetValue(getConfig('orientation') or 'vertical')
		orientSwitch:SetOnSelect(function(value)
			setConfig('orientation', value)
		end)
		cardY = placeWidget(orientSwitch, inner, cardY, SWITCH_H)

		-- Growth direction dropdown
		cardY = placeHeading(inner, 'Growth Direction', 3, cardY)
		local growthDropdown = Widgets.CreateDropdown(inner, WIDGET_W)
		growthDropdown:SetItems({
			{ text = 'Top to Bottom',  value = 'topToBottom' },
			{ text = 'Bottom to Top',  value = 'bottomToTop' },
			{ text = 'Left to Right',  value = 'leftToRight' },
			{ text = 'Right to Left',  value = 'rightToLeft' },
		})
		growthDropdown:SetValue(getConfig('growthDirection') or 'topToBottom')
		growthDropdown:SetOnSelect(function(value)
			setConfig('growthDirection', value)
		end)
		cardY = placeWidget(growthDropdown, inner, cardY, DROPDOWN_H)

		yOffset = Widgets.EndCard(groupCard, content, cardY)
	end

	-- ============================================================
	-- Health Bar Color (player/group/arena frames only)
	-- NPC frames use oUF's full UpdateColor chain and skip this.
	-- ============================================================

	local isNpcFrame = NPC_FRAME_TYPES[unitType] or false
	local colorCard  -- used for afterColorContainer anchor

	if(not isNpcFrame) then
		yOffset = placeHeading(content, 'Health Bar Color', 2, yOffset)

		local colorCardLocal, inner, cardY = Widgets.StartCard(content, width, yOffset)
		colorCard = colorCardLocal
		local CARD_PADDING = 12  -- must match Widgets.Frame CARD_PADDING

		-- Health color mode switch
		cardY = placeHeading(inner, 'Color Mode', 3, cardY)
		local healthColorSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
			{ text = 'Class',    value = 'class' },
			{ text = 'Dark',     value = 'dark' },
			{ text = 'Gradient', value = 'gradient' },
			{ text = 'Custom',   value = 'custom' },
		})
		healthColorSwitch:SetValue(getConfig('health.colorMode') or 'class')
		cardY = placeWidget(healthColorSwitch, inner, cardY, SWITCH_H)

		-- Threat color toggle (NPC target frames only — threat is per-unit)
		if(isNpcFrame) then
			local threatCheck = Widgets.CreateCheckButton(inner, 'Color by Threat', function(checked)
				setConfig('health.colorThreat', checked)
			end)
			threatCheck:SetChecked(getConfig('health.colorThreat') or false)
			cardY = placeWidget(threatCheck, inner, cardY, CHECK_H)
		end

		-- Y after the mode switch — reflow starts from here
		local colorSwitchEndY = cardY

		-- ── Helper: build a gradient section (3 color pickers + threshold sliders) ──
		local function buildGradientSection(parent, prefix, defaults)
			local section = CreateFrame('Frame', nil, parent)
			section:SetWidth(WIDGET_W)

			local sY = 0

			for _, row in next, defaults do
				local colorKey = prefix .. row.colorKey
				local thresholdKey = prefix .. row.thresholdKey
				local picker = Widgets.CreateColorPicker(section, row.label, false,
					nil,
					function(r, g, b) setConfig(colorKey, { r, g, b }) end)
				picker:SetPoint('TOPLEFT', section, 'TOPLEFT', 0, sY)
				local saved = getConfig(colorKey) or row.color
				picker:SetColor(saved[1], saved[2], saved[3], 1)

				local pctSlider = Widgets.CreateSlider(section, '% Threshold', WIDGET_W - 30, 0, 100, 5)
				pctSlider:SetValue(getConfig(thresholdKey) or row.pct)
				pctSlider:SetAfterValueChanged(function(value)
					setConfig(thresholdKey, value)
				end)
				pctSlider:SetPoint('TOPLEFT', section, 'TOPLEFT', 0, sY - 22)
				sY = sY - 22 - SLIDER_H - C.Spacing.normal
			end

			local h = math.abs(sY)
			section:SetHeight(h)
			return section, h
		end

		local GRADIENT_ROWS = {
			{ label = 'Healthy',  colorKey = 'gradientColor1', thresholdKey = 'gradientThreshold1', color = { 0.2, 0.8, 0.2 }, pct = 95 },
			{ label = 'Warning',  colorKey = 'gradientColor2', thresholdKey = 'gradientThreshold2', color = { 0.9, 0.6, 0.1 }, pct = 50 },
			{ label = 'Critical', colorKey = 'gradientColor3', thresholdKey = 'gradientThreshold3', color = { 0.8, 0.1, 0.1 }, pct = 5 },
		}

		local LOSS_GRADIENT_ROWS = {
			{ label = 'Healthy',  colorKey = 'lossGradientColor1', thresholdKey = 'lossGradientThreshold1', color = { 0.1, 0.4, 0.1 }, pct = 95 },
			{ label = 'Warning',  colorKey = 'lossGradientColor2', thresholdKey = 'lossGradientThreshold2', color = { 0.4, 0.25, 0.05 }, pct = 50 },
			{ label = 'Critical', colorKey = 'lossGradientColor3', thresholdKey = 'lossGradientThreshold3', color = { 0.4, 0.05, 0.05 }, pct = 5 },
		}

		-- ── Health gradient section ──
		local gradientSection, gradientSectionH = buildGradientSection(inner, 'health.', GRADIENT_ROWS)

		-- ── Health custom picker ──
		local customPicker = Widgets.CreateColorPicker(inner, 'Health Bar Color', false,
			nil,
			function(r, g, b) setConfig('health.customColor', { r, g, b }) end)
		local savedCustom = getConfig('health.customColor') or { 0.2, 0.8, 0.2 }
		customPicker:SetColor(savedCustom[1], savedCustom[2], savedCustom[3], 1)
		local customPickerH = 22

		-- ── Smooth bars checkbox ──
		local smoothCheck = Widgets.CreateCheckButton(inner, 'Smooth Bars', function(checked)
			setConfig('health.smooth', checked)
		end)
		smoothCheck:SetChecked(getConfig('health.smooth') ~= false)

		-- ── Health Loss Color heading ──
		local lossHeading, lossHeadingH = Widgets.CreateHeading(inner, 'Health Loss Color', 3)

		-- ── Loss color mode switch ──
		local lossColorSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
			{ text = 'Class',    value = 'class' },
			{ text = 'Dark',     value = 'dark' },
			{ text = 'Gradient', value = 'gradient' },
			{ text = 'Custom',   value = 'custom' },
		})
		lossColorSwitch:SetValue(getConfig('health.lossColorMode') or 'dark')

		-- ── Loss gradient section ──
		local lossGradientSection, lossGradientSectionH = buildGradientSection(inner, 'health.', LOSS_GRADIENT_ROWS)

		-- ── Loss custom picker ──
		local lossPicker = Widgets.CreateColorPicker(inner, 'Loss Color', false,
			nil,
			function(r, g, b) setConfig('health.lossCustomColor', { r, g, b }) end)
		local savedLoss = getConfig('health.lossCustomColor') or { 0.15, 0.15, 0.15 }
		lossPicker:SetColor(savedLoss[1], savedLoss[2], savedLoss[3], 1)
		local lossPickerH = 22

		-- ── Reflow: position all widgets inside the card based on current modes ──
		local curHealthMode = getConfig('health.colorMode') or 'class'
		local curLossMode = getConfig('health.lossColorMode') or 'dark'

		local function reflowColorCard()
			local y = colorSwitchEndY

			-- Health gradient section
			if(curHealthMode == 'gradient') then
				gradientSection:Show()
				gradientSection:ClearAllPoints()
				Widgets.SetPoint(gradientSection, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
				y = y - gradientSectionH
			else
				gradientSection:Hide()
			end

			-- Health custom picker
			if(curHealthMode == 'custom') then
				customPicker:Show()
				customPicker:ClearAllPoints()
				Widgets.SetPoint(customPicker, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
				y = y - customPickerH - C.Spacing.normal
			else
				customPicker:Hide()
			end

			-- Smooth bars
			smoothCheck:ClearAllPoints()
			Widgets.SetPoint(smoothCheck, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - CHECK_H - C.Spacing.normal

			-- Loss heading
			lossHeading:ClearAllPoints()
			Widgets.SetPoint(lossHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - lossHeadingH

			-- Loss switch
			lossColorSwitch:ClearAllPoints()
			Widgets.SetPoint(lossColorSwitch, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - SWITCH_H - C.Spacing.normal

			-- Loss gradient section
			if(curLossMode == 'gradient') then
				lossGradientSection:Show()
				lossGradientSection:ClearAllPoints()
				Widgets.SetPoint(lossGradientSection, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
				y = y - lossGradientSectionH
			else
				lossGradientSection:Hide()
			end

			-- Loss custom picker
			if(curLossMode == 'custom') then
				lossPicker:Show()
				lossPicker:ClearAllPoints()
				Widgets.SetPoint(lossPicker, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
				y = y - lossPickerH - C.Spacing.normal
			else
				lossPicker:Hide()
			end

			-- Update card height
			local innerH = math.abs(y)
			inner:SetHeight(innerH)
			colorCardLocal:SetHeight(innerH + CARD_PADDING * 2)

			-- Update scroll content height
			local cardBottom = math.abs(colorCardLocal._startY) + colorCardLocal:GetHeight() + C.Spacing.normal
			local restH = scroll._afterColorRestHeight or 0
			content:SetHeight(cardBottom + restH + C.Spacing.normal)
		end

		healthColorSwitch:SetOnSelect(function(value)
			curHealthMode = value
			setConfig('health.colorMode', value)
			reflowColorCard()
		end)

		lossColorSwitch:SetOnSelect(function(value)
			curLossMode = value
			setConfig('health.lossColorMode', value)
			reflowColorCard()
		end)

		-- Initial reflow
		reflowColorCard()

		-- Use the current card height to calculate initial yOffset
		yOffset = colorCardLocal._startY - colorCardLocal:GetHeight() - C.Spacing.normal
	end

	-- ── Wrap everything after the color section in a container ──
	-- For player/group frames this anchors to the color card's bottom
	-- so it shifts when the card resizes. For NPC frames it continues
	-- at the current yOffset with no dynamic anchor.
	local afterColorContainer = CreateFrame('Frame', nil, content)
	if(colorCard) then
		afterColorContainer:SetPoint('TOPLEFT', colorCard, 'BOTTOMLEFT', 0, -C.Spacing.normal)
	else
		Widgets.SetPoint(afterColorContainer, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	end
	afterColorContainer:SetWidth(width)

	-- Reset yOffset for the container-local coordinate system
	local restY = 0

	-- ── Shields and Absorbs ──────────────────────────────────
	restY = placeHeading(afterColorContainer, 'Shields and Absorbs', 2, restY)

	do
		local saCard, inner, cardY = Widgets.StartCard(afterColorContainer, width, restY)
		local PICKER_ROW_H = 22

		-- ── Heal Prediction ──
		local healPredCheck = Widgets.CreateCheckButton(inner, 'Heal Prediction', function(checked)
			setConfig('health.healPrediction', checked)
		end)
		healPredCheck:SetChecked(getConfig('health.healPrediction') ~= false)
		cardY = placeWidget(healPredCheck, inner, cardY, CHECK_H)

		local healPredPicker = Widgets.CreateColorPicker(inner, 'Color', true,
			nil,
			function(r, g, b, a) setConfig('health.healPredictionColor', { r, g, b, a }) end)
		local savedHealPred = getConfig('health.healPredictionColor') or { 0.6, 0.6, 0.6, 0.4 }
		healPredPicker:SetColor(savedHealPred[1], savedHealPred[2], savedHealPred[3], savedHealPred[4])
		cardY = placeWidget(healPredPicker, inner, cardY, PICKER_ROW_H)

		-- ── Shields (damage absorbs) ──
		local damageAbsorbCheck = Widgets.CreateCheckButton(inner, 'Shields', function(checked)
			setConfig('health.damageAbsorb', checked)
		end)
		damageAbsorbCheck:SetChecked(getConfig('health.damageAbsorb') ~= false)
		cardY = placeWidget(damageAbsorbCheck, inner, cardY, CHECK_H)

		local damageAbsorbPicker = Widgets.CreateColorPicker(inner, 'Color', true,
			nil,
			function(r, g, b, a) setConfig('health.damageAbsorbColor', { r, g, b, a }) end)
		local savedDamageAbsorb = getConfig('health.damageAbsorbColor') or { 1, 1, 1, 0.6 }
		damageAbsorbPicker:SetColor(savedDamageAbsorb[1], savedDamageAbsorb[2], savedDamageAbsorb[3], savedDamageAbsorb[4])
		cardY = placeWidget(damageAbsorbPicker, inner, cardY, PICKER_ROW_H)

		-- ── Heal Absorbs ──
		local healAbsorbCheck = Widgets.CreateCheckButton(inner, 'Heal Absorbs', function(checked)
			setConfig('health.healAbsorb', checked)
		end)
		healAbsorbCheck:SetChecked(getConfig('health.healAbsorb') ~= false)
		cardY = placeWidget(healAbsorbCheck, inner, cardY, CHECK_H)

		local healAbsorbPicker = Widgets.CreateColorPicker(inner, 'Color', true,
			nil,
			function(r, g, b, a) setConfig('health.healAbsorbColor', { r, g, b, a }) end)
		local savedHealAbsorb = getConfig('health.healAbsorbColor') or { 0.7, 0.1, 0.1, 0.5 }
		healAbsorbPicker:SetColor(savedHealAbsorb[1], savedHealAbsorb[2], savedHealAbsorb[3], savedHealAbsorb[4])
		cardY = placeWidget(healAbsorbPicker, inner, cardY, PICKER_ROW_H)

		-- ── Overshield ──
		local overAbsorbCheck = Widgets.CreateCheckButton(inner, 'Overshield', function(checked)
			setConfig('health.overAbsorb', checked)
		end)
		overAbsorbCheck:SetChecked(getConfig('health.overAbsorb') ~= false)
		cardY = placeWidget(overAbsorbCheck, inner, cardY, CHECK_H)

		restY = Widgets.EndCard(saCard, afterColorContainer, cardY)
	end

	-- ── Power Bar ─────────────────────────────────────────────
	restY = placeHeading(afterColorContainer, 'Power Bar', 2, restY)

	local powerCard, inner, cardY = Widgets.StartCard(afterColorContainer, width, restY)

	local showPowerCheck = Widgets.CreateCheckButton(inner, 'Show Power Bar', function(checked)
		setConfig('showPower', checked)
	end)
	showPowerCheck:SetChecked(getConfig('showPower') ~= false)
	cardY = placeWidget(showPowerCheck, inner, cardY, CHECK_H)

	-- Power bar position (top/bottom of health bar)
	cardY = placeHeading(inner, 'Position', 3, cardY)
	local powerPosSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
		{ text = 'Bottom', value = 'bottom' },
		{ text = 'Top',    value = 'top' },
	})
	powerPosSwitch:SetValue(getConfig('power.position') or 'bottom')
	powerPosSwitch:SetOnSelect(function(value)
		setConfig('power.position', value)
	end)
	cardY = placeWidget(powerPosSwitch, inner, cardY, SWITCH_H)

	-- Power bar height slider
	local powerHeightSlider = Widgets.CreateSlider(inner, 'Power Bar Height', WIDGET_W, 1, 20, 1)
	powerHeightSlider:SetValue(getConfig('power.height') or 2)
	powerHeightSlider:SetAfterValueChanged(function(value)
		setConfig('power.height', value)
	end)
	cardY = placeWidget(powerHeightSlider, inner, cardY, SLIDER_H)

	-- Per-power-type color overrides (filtered by relevance)
	local ALL_POWER_TYPES = {
		{ token = 'MANA',         label = 'Mana',         default = { 0.00, 0.44, 0.87 } },
		{ token = 'RAGE',         label = 'Rage',         default = { 1.00, 0.00, 0.00 } },
		{ token = 'ENERGY',       label = 'Energy',       default = { 1.00, 1.00, 0.00 } },
		{ token = 'FOCUS',        label = 'Focus',        default = { 1.00, 0.50, 0.25 } },
		{ token = 'RUNIC_POWER',  label = 'Runic Power',  default = { 0.00, 0.82, 1.00 } },
		{ token = 'INSANITY',     label = 'Insanity',     default = { 0.40, 0.00, 0.80 } },
		{ token = 'FURY',         label = 'Fury',         default = { 0.79, 0.26, 0.99 } },
		{ token = 'MAELSTROM',    label = 'Maelstrom',    default = { 0.00, 0.50, 1.00 } },
		{ token = 'LUNAR_POWER',  label = 'Lunar Power',  default = { 0.30, 0.52, 0.90 } },
	}

	-- Class → power types shown on the player frame
	local CLASS_POWER_TYPES = {
		WARRIOR     = { RAGE = true },
		PALADIN     = { MANA = true },
		HUNTER      = { FOCUS = true },
		ROGUE       = { ENERGY = true },
		PRIEST      = { MANA = true, INSANITY = true },
		DEATHKNIGHT = { RUNIC_POWER = true },
		SHAMAN      = { MANA = true, MAELSTROM = true },
		MAGE        = { MANA = true },
		WARLOCK     = { MANA = true },
		MONK        = { MANA = true, ENERGY = true },
		DRUID       = { MANA = true, RAGE = true, ENERGY = true, LUNAR_POWER = true },
		DEMONHUNTER = { FURY = true },
		EVOKER      = { MANA = true },
	}

	local filterTokens
	if(unitType == 'player') then
		local _, playerClass = UnitClass('player')
		filterTokens = playerClass and CLASS_POWER_TYPES[playerClass]
	end

	for _, pt in next, ALL_POWER_TYPES do
		if(not filterTokens or filterTokens[pt.token]) then
			local configKey = 'power.customColors.' .. pt.token
			local picker = Widgets.CreateColorPicker(inner, pt.label, false,
				nil,
				function(r, g, b) setConfig(configKey, { r, g, b }) end)
			local saved = getConfig(configKey) or pt.default
			picker:SetColor(saved[1], saved[2], saved[3], 1)
			cardY = placeWidget(picker, inner, cardY, 22)
		end
	end

	restY = Widgets.EndCard(powerCard, afterColorContainer, cardY)

	-- ── Card: Cast Bar ────────────────────────────────────────
	restY = placeHeading(afterColorContainer, 'Cast Bar', 2, restY)

	local castCard, inner, cardY = Widgets.StartCard(afterColorContainer, width, restY)

	local showCastCheck = Widgets.CreateCheckButton(inner, 'Show Cast Bar', function(checked)
		setConfig('showCastBar', checked)
	end)
	showCastCheck:SetChecked(getConfig('showCastBar') ~= false)
	cardY = placeWidget(showCastCheck, inner, cardY, CHECK_H)

	restY = Widgets.EndCard(castCard, afterColorContainer, cardY)

	-- ── Name ──────────────────────────────────────────────────
	restY = placeHeading(afterColorContainer, 'Name', 2, restY)

	local nameCard, inner, cardY = Widgets.StartCard(afterColorContainer, width, restY)

	local showNameCheck = Widgets.CreateCheckButton(inner, 'Show Name', function(checked)
		setConfig('showName', checked)
	end)
	showNameCheck:SetChecked(getConfig('showName') ~= false)
	cardY = placeWidget(showNameCheck, inner, cardY, CHECK_H)

	-- Name color mode switch
	cardY = placeHeading(inner, 'Name Color', 3, cardY)
	local nameColorSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
		{ text = 'Class',  value = 'class' },
		{ text = 'White',  value = 'white' },
		{ text = 'Custom', value = 'custom' },
	})
	nameColorSwitch:SetValue(getConfig('name.colorMode') or 'class')
	cardY = placeWidget(nameColorSwitch, inner, cardY, SWITCH_H)

	-- Y after the color switch — reflow starts from here
	local nameColorSwitchEndY = cardY

	-- Custom name color picker
	local nameCustomPicker = Widgets.CreateColorPicker(inner, 'Name Color', false,
		nil,
		function(r, g, b) setConfig('name.customColor', { r, g, b }) end)
	local savedNameColor = getConfig('name.customColor') or { 1, 1, 1 }
	nameCustomPicker:SetColor(savedNameColor[1], savedNameColor[2], savedNameColor[3], 1)
	local nameCustomPickerH = 22

	-- Name font size
	local nameFontSize = Widgets.CreateSlider(inner, 'Font Size', WIDGET_W, 6, 24, 1)
	nameFontSize:SetValue(getConfig('name.fontSize') or 0)
	Widgets.SetTooltip(nameFontSize, 'Name Font Size', 'Override the global font size for name text')
	nameFontSize:SetAfterValueChanged(function(value)
		setConfig('name.fontSize', value)
	end)

	-- Name outline
	local nameOutline = Widgets.CreateDropdown(inner, WIDGET_W)
	nameOutline:SetItems({
		{ text = 'None',       value = '' },
		{ text = 'Outline',    value = 'OUTLINE' },
		{ text = 'Monochrome', value = 'MONOCHROME' },
	})
	nameOutline:SetValue(getConfig('name.outline') or '')
	nameOutline:SetOnSelect(function(value)
		setConfig('name.outline', value)
	end)

	-- Name shadow
	local nameShadow = Widgets.CreateCheckButton(inner, 'Text Shadow', function(checked)
		setConfig('name.shadow', checked)
	end)
	nameShadow:SetChecked(getConfig('name.shadow') ~= false)

	-- Reflow name card widgets based on color mode
	local curNameColorMode = getConfig('name.colorMode') or 'class'

	local function reflowNameCard()
		local y = nameColorSwitchEndY

		if(curNameColorMode == 'custom') then
			nameCustomPicker:Show()
			nameCustomPicker:ClearAllPoints()
			Widgets.SetPoint(nameCustomPicker, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - nameCustomPickerH - C.Spacing.normal
		else
			nameCustomPicker:Hide()
		end

		nameFontSize:ClearAllPoints()
		Widgets.SetPoint(nameFontSize, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - SLIDER_H - C.Spacing.normal

		nameOutline:ClearAllPoints()
		Widgets.SetPoint(nameOutline, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - DROPDOWN_H - C.Spacing.normal

		nameShadow:ClearAllPoints()
		Widgets.SetPoint(nameShadow, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - CHECK_H - C.Spacing.normal

		return y
	end

	nameColorSwitch:SetOnSelect(function(value)
		curNameColorMode = value
		setConfig('name.colorMode', value)
		reflowNameCard()
	end)

	cardY = reflowNameCard()

	-- Name text position anchor
	cardY = placeHeading(inner, 'Text Position', 3, cardY)
	local nameAnchor = Widgets.CreateAnchorPicker(inner, WIDGET_W)
	local savedNameAnchor = getConfig('name.anchor') or 'CENTER'
	nameAnchor:SetAnchor(savedNameAnchor, 0, 0)
	nameAnchor:SetOnChanged(function(point)
		setConfig('name.anchor', point)
	end)
	nameAnchor._xInput:Hide()
	nameAnchor._yInput:Hide()
	cardY = placeWidget(nameAnchor, inner, cardY, 56)

	-- Name text offsets
	cardY = placeHeading(inner, 'Text Offsets', 3, cardY)
	local nameOffsetX = Widgets.CreateSlider(inner, 'X Offset', WIDGET_W, -50, 50, 1)
	nameOffsetX:SetValue(getConfig('name.anchorX') or 0)
	nameOffsetX:SetAfterValueChanged(function(value)
		setConfig('name.anchorX', value)
	end)
	cardY = placeWidget(nameOffsetX, inner, cardY, SLIDER_H)

	local nameOffsetY = Widgets.CreateSlider(inner, 'Y Offset', WIDGET_W, -50, 50, 1)
	nameOffsetY:SetValue(getConfig('name.anchorY') or 0)
	nameOffsetY:SetAfterValueChanged(function(value)
		setConfig('name.anchorY', value)
	end)
	cardY = placeWidget(nameOffsetY, inner, cardY, SLIDER_H)

	restY = Widgets.EndCard(nameCard, afterColorContainer, cardY)

	-- ── Card: Health Text ─────────────────────────────────────
	restY = placeHeading(afterColorContainer, 'Health Text', 2, restY)

	local healthTextCard, inner, cardY = Widgets.StartCard(afterColorContainer, width, restY)

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
	cardY = placeWidget(attachToNameCheck, inner, cardY, CHECK_H)

	local showHealthTextCheck = Widgets.CreateCheckButton(inner, 'Show Health Text', function(checked)
		setConfig('health.showText', checked)
	end)
	showHealthTextCheck:SetChecked(getConfig('health.showText') or false)
	cardY = placeWidget(showHealthTextCheck, inner, cardY, CHECK_H)

	-- Health text format dropdown
	cardY = placeHeading(inner, 'Health Text Format', 3, cardY)
	local healthFormatDropdown = Widgets.CreateDropdown(inner, WIDGET_W)
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
	cardY = placeWidget(healthFormatDropdown, inner, cardY, DROPDOWN_H)

	-- Health text font size
	local healthFontSize = Widgets.CreateSlider(inner, 'Font Size', WIDGET_W, 6, 24, 1)
	healthFontSize:SetValue(getConfig('health.fontSize') or 0)
	Widgets.SetTooltip(healthFontSize, 'Health Text Font Size', 'Override the global font size for health text')
	healthFontSize:SetAfterValueChanged(function(value)
		setConfig('health.fontSize', value)
	end)
	cardY = placeWidget(healthFontSize, inner, cardY, SLIDER_H)

	-- Health text outline
	local healthOutline = Widgets.CreateDropdown(inner, WIDGET_W)
	healthOutline:SetItems({
		{ text = 'None',       value = '' },
		{ text = 'Outline',    value = 'OUTLINE' },
		{ text = 'Monochrome', value = 'MONOCHROME' },
	})
	healthOutline:SetValue(getConfig('health.outline') or '')
	healthOutline:SetOnSelect(function(value)
		setConfig('health.outline', value)
	end)
	cardY = placeWidget(healthOutline, inner, cardY, DROPDOWN_H)

	-- Health text shadow
	local healthShadow = Widgets.CreateCheckButton(inner, 'Text Shadow', function(checked)
		setConfig('health.shadow', checked)
	end)
	healthShadow:SetChecked(getConfig('health.shadow') ~= false)
	cardY = placeWidget(healthShadow, inner, cardY, CHECK_H)

	-- Health text position anchor
	cardY = placeHeading(inner, 'Text Position', 3, cardY)
	local healthTextAnchor = Widgets.CreateAnchorPicker(inner, WIDGET_W)
	local savedHealthAnchor = getConfig('health.textAnchor') or 'CENTER'
	healthTextAnchor:SetAnchor(savedHealthAnchor, 0, 0)
	healthTextAnchor:SetOnChanged(function(point)
		setConfig('health.textAnchor', point)
	end)
	healthTextAnchor._xInput:Hide()
	healthTextAnchor._yInput:Hide()
	cardY = placeWidget(healthTextAnchor, inner, cardY, 56)

	-- Health text offsets
	cardY = placeHeading(inner, 'Text Offsets', 3, cardY)
	local healthOffsetX = Widgets.CreateSlider(inner, 'X Offset', WIDGET_W, -50, 50, 1)
	healthOffsetX:SetValue(getConfig('health.textAnchorX') or 0)
	healthOffsetX:SetAfterValueChanged(function(value)
		setConfig('health.textAnchorX', value)
	end)
	cardY = placeWidget(healthOffsetX, inner, cardY, SLIDER_H)

	local healthOffsetY = Widgets.CreateSlider(inner, 'Y Offset', WIDGET_W, -50, 50, 1)
	healthOffsetY:SetValue(getConfig('health.textAnchorY') or 0)
	healthOffsetY:SetAfterValueChanged(function(value)
		setConfig('health.textAnchorY', value)
	end)
	cardY = placeWidget(healthOffsetY, inner, cardY, SLIDER_H)

	-- Populate health position widgets for dimming control
	healthPositionWidgets[1] = healthTextAnchor
	healthPositionWidgets[2] = healthOffsetX
	healthPositionWidgets[3] = healthOffsetY
	updateHealthPositionDimming(isAttached)

	restY = Widgets.EndCard(healthTextCard, afterColorContainer, cardY)

	-- ── Card: Power Text ──────────────────────────────────────
	restY = placeHeading(afterColorContainer, 'Power Text', 2, restY)

	local powerTextCard, inner, cardY = Widgets.StartCard(afterColorContainer, width, restY)

	local showPowerTextCheck = Widgets.CreateCheckButton(inner, 'Show Power Text', function(checked)
		setConfig('power.showText', checked)
	end)
	showPowerTextCheck:SetChecked(getConfig('power.showText') or false)
	cardY = placeWidget(showPowerTextCheck, inner, cardY, CHECK_H)

	-- Power text font size
	local powerFontSize = Widgets.CreateSlider(inner, 'Font Size', WIDGET_W, 6, 24, 1)
	powerFontSize:SetValue(getConfig('power.fontSize') or 0)
	Widgets.SetTooltip(powerFontSize, 'Power Text Font Size', 'Override the global font size for power text')
	powerFontSize:SetAfterValueChanged(function(value)
		setConfig('power.fontSize', value)
	end)
	cardY = placeWidget(powerFontSize, inner, cardY, SLIDER_H)

	-- Power text outline
	local powerOutline = Widgets.CreateDropdown(inner, WIDGET_W)
	powerOutline:SetItems({
		{ text = 'None',       value = '' },
		{ text = 'Outline',    value = 'OUTLINE' },
		{ text = 'Monochrome', value = 'MONOCHROME' },
	})
	powerOutline:SetValue(getConfig('power.outline') or '')
	powerOutline:SetOnSelect(function(value)
		setConfig('power.outline', value)
	end)
	cardY = placeWidget(powerOutline, inner, cardY, DROPDOWN_H)

	-- Power text shadow
	local powerShadow = Widgets.CreateCheckButton(inner, 'Text Shadow', function(checked)
		setConfig('power.shadow', checked)
	end)
	powerShadow:SetChecked(getConfig('power.shadow') ~= false)
	cardY = placeWidget(powerShadow, inner, cardY, CHECK_H)

	-- Power text position anchor
	cardY = placeHeading(inner, 'Text Position', 3, cardY)
	local powerTextAnchor = Widgets.CreateAnchorPicker(inner, WIDGET_W)
	local savedPowerAnchor = getConfig('power.textAnchor') or 'CENTER'
	powerTextAnchor:SetAnchor(savedPowerAnchor, 0, 0)
	powerTextAnchor:SetOnChanged(function(point)
		setConfig('power.textAnchor', point)
	end)
	powerTextAnchor._xInput:Hide()
	powerTextAnchor._yInput:Hide()
	cardY = placeWidget(powerTextAnchor, inner, cardY, 56)

	-- Power text offsets
	cardY = placeHeading(inner, 'Text Offsets', 3, cardY)
	local powerOffsetX = Widgets.CreateSlider(inner, 'X Offset', WIDGET_W, -50, 50, 1)
	powerOffsetX:SetValue(getConfig('power.textAnchorX') or 0)
	powerOffsetX:SetAfterValueChanged(function(value)
		setConfig('power.textAnchorX', value)
	end)
	cardY = placeWidget(powerOffsetX, inner, cardY, SLIDER_H)

	local powerOffsetY = Widgets.CreateSlider(inner, 'Y Offset', WIDGET_W, -50, 50, 1)
	powerOffsetY:SetValue(getConfig('power.textAnchorY') or 0)
	powerOffsetY:SetAfterValueChanged(function(value)
		setConfig('power.textAnchorY', value)
	end)
	cardY = placeWidget(powerOffsetY, inner, cardY, SLIDER_H)

	restY = Widgets.EndCard(powerTextCard, afterColorContainer, cardY)

	-- ── Status Icons ──────────────────────────────────────────
	restY = placeHeading(afterColorContainer, 'Status Icons', 2, restY)

	local iconsCard, inner, cardY = Widgets.StartCard(afterColorContainer, width, restY)

	-- Show role icon checkbox
	local showRoleCheck = Widgets.CreateCheckButton(inner, 'Show Role Icon', function(checked)
		setConfig('statusIcons.role', checked)
	end)
	showRoleCheck:SetChecked(getConfig('statusIcons.role') ~= false)
	cardY = placeWidget(showRoleCheck, inner, cardY, CHECK_H)

	-- Show leader icon checkbox
	local showLeaderCheck = Widgets.CreateCheckButton(inner, 'Show Leader Icon', function(checked)
		setConfig('statusIcons.leader', checked)
	end)
	showLeaderCheck:SetChecked(getConfig('statusIcons.leader') ~= false)
	cardY = placeWidget(showLeaderCheck, inner, cardY, CHECK_H)

	-- Show ready check checkbox
	local showReadyCheckCheck = Widgets.CreateCheckButton(inner, 'Show Ready Check', function(checked)
		setConfig('statusIcons.readyCheck', checked)
	end)
	showReadyCheckCheck:SetChecked(getConfig('statusIcons.readyCheck') ~= false)
	cardY = placeWidget(showReadyCheckCheck, inner, cardY, CHECK_H)

	-- Show raid icon checkbox
	local showRaidIconCheck = Widgets.CreateCheckButton(inner, 'Show Raid Icon', function(checked)
		setConfig('statusIcons.raidIcon', checked)
	end)
	showRaidIconCheck:SetChecked(getConfig('statusIcons.raidIcon') ~= false)
	cardY = placeWidget(showRaidIconCheck, inner, cardY, CHECK_H)

	-- Show combat icon checkbox
	local showCombatIconCheck = Widgets.CreateCheckButton(inner, 'Show Combat Icon', function(checked)
		setConfig('statusIcons.combat', checked)
	end)
	showCombatIconCheck:SetChecked(getConfig('statusIcons.combat') or false)
	cardY = placeWidget(showCombatIconCheck, inner, cardY, CHECK_H)

	-- Show resting icon checkbox
	local showRestingCheck = Widgets.CreateCheckButton(inner, 'Show Resting Icon', function(checked)
		setConfig('statusIcons.resting', checked)
	end)
	showRestingCheck:SetChecked(getConfig('statusIcons.resting') or false)
	cardY = placeWidget(showRestingCheck, inner, cardY, CHECK_H)

	-- Show phase icon checkbox
	local showPhaseCheck = Widgets.CreateCheckButton(inner, 'Show Phase Icon', function(checked)
		setConfig('statusIcons.phase', checked)
	end)
	showPhaseCheck:SetChecked(getConfig('statusIcons.phase') or false)
	cardY = placeWidget(showPhaseCheck, inner, cardY, CHECK_H)

	-- Show resurrect icon checkbox
	local showResurrectCheck = Widgets.CreateCheckButton(inner, 'Show Resurrect Icon', function(checked)
		setConfig('statusIcons.resurrect', checked)
	end)
	showResurrectCheck:SetChecked(getConfig('statusIcons.resurrect') or false)
	cardY = placeWidget(showResurrectCheck, inner, cardY, CHECK_H)

	-- Show summon icon checkbox
	local showSummonCheck = Widgets.CreateCheckButton(inner, 'Show Summon Icon', function(checked)
		setConfig('statusIcons.summon', checked)
	end)
	showSummonCheck:SetChecked(getConfig('statusIcons.summon') or false)
	cardY = placeWidget(showSummonCheck, inner, cardY, CHECK_H)

	-- Show raid role icon checkbox
	local showRaidRoleCheck = Widgets.CreateCheckButton(inner, 'Show Raid Role Icon', function(checked)
		setConfig('statusIcons.raidRole', checked)
	end)
	showRaidRoleCheck:SetChecked(getConfig('statusIcons.raidRole') or false)
	cardY = placeWidget(showRaidRoleCheck, inner, cardY, CHECK_H)

	-- Show PvP icon checkbox
	local showPvPCheck = Widgets.CreateCheckButton(inner, 'Show PvP Icon', function(checked)
		setConfig('statusIcons.pvp', checked)
	end)
	showPvPCheck:SetChecked(getConfig('statusIcons.pvp') or false)
	cardY = placeWidget(showPvPCheck, inner, cardY, CHECK_H)

	-- Show status text checkbox
	local showStatusTextCheck = Widgets.CreateCheckButton(inner, 'Show Status Text', function(checked)
		setConfig('statusText', checked)
	end)
	showStatusTextCheck:SetChecked(getConfig('statusText') ~= false)
	cardY = placeWidget(showStatusTextCheck, inner, cardY, CHECK_H)

	restY = Widgets.EndCard(iconsCard, afterColorContainer, cardY)

	-- ── Resize content to fit all widgets ─────────────────────
	-- Store rest height for dynamic reflow when the color card resizes
	local afterColorRestH = math.abs(restY)
	scroll._afterColorRestHeight = afterColorRestH
	afterColorContainer:SetHeight(afterColorRestH)

	-- Total content height depends on whether the color card exists
	local totalH
	if(colorCard) then
		totalH = math.abs(colorCard._startY) + colorCard:GetHeight() + C.Spacing.normal + afterColorRestH + C.Spacing.normal
	else
		totalH = math.abs(yOffset) + afterColorRestH + C.Spacing.normal
	end
	content:SetHeight(totalH)

	-- ── Invalidate on preset change ────────────────────────────
	-- When the editing preset changes, mark this scroll frame stale so
	-- the Settings framework knows to rebuild on next panel activation.
	F.EventBus:Register('EDITING_PRESET_CHANGED', function(newPreset)
		scroll._builtForPreset = nil
		if(F.Settings and F.Settings._panelFrames) then
			-- Invalidate cache so panel rebuilds with new preset data
			for panelId, frame in next, F.Settings._panelFrames do
				if(frame == scroll) then
					F.Settings._panelFrames[panelId] = nil
					break
				end
			end
		end
	end, 'FrameSettingsBuilder.' .. unitType)

	return scroll
end
