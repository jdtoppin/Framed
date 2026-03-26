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

	-- Frame Anchor Point picker
	cardY = placeHeading(inner, 'Frame Anchor', 3, cardY)

	local anchorInfo = Widgets.CreateInfoIcon(inner,
		'Frame Anchor',
		'The anchor point determines which corner or edge of the frame is pinned '
		.. 'to its X/Y position on screen. For example, if set to TOPLEFT, the '
		.. 'top-left corner of the frame sits at the X/Y coordinates.')
	anchorInfo:SetPoint('TOPRIGHT', inner, 'TOPRIGHT', -4, cardY + 14)

	local anchorPicker = Widgets.CreateAnchorPicker(inner, WIDGET_W)
	local savedAnchor = getConfig('position.anchor') or 'CENTER'
	anchorPicker._xInput:Hide()
	anchorPicker._yInput:Hide()
	anchorPicker:SetAnchor(savedAnchor, 0, 0)
	anchorPicker:SetOnChanged(function(point)
		setConfig('position.anchor', point)
	end)
	cardY = placeWidget(anchorPicker, inner, cardY, 56)

	-- Frame Position sliders (X / Y)
	cardY = placeHeading(inner, 'Frame Position', 3, cardY)

	-- Read the actual frame position from oUF objects if available
	local actualX = getConfig('position.x') or 0
	local actualY = getConfig('position.y') or 0
	do
		local oUF = F.oUF
		if(oUF and oUF.objects) then
			for _, frame in next, oUF.objects do
				if(frame._framedUnitType == unitType) then
					local _, _, _, fx, fy = frame:GetPoint()
					if(fx) then
						actualX = Widgets.Round(fx)
						actualY = Widgets.Round(fy)
					end
					break
				end
			end
		end
	end

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
	-- Health Bar Color
	-- ============================================================

	yOffset = placeHeading(content, 'Health Bar Color', 2, yOffset)

	local colorCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

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

	-- ── Gradient options (3 color pickers with % threshold sliders) ──
	local gradientSection = CreateFrame('Frame', nil, inner)
	gradientSection:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cardY)
	gradientSection:SetWidth(WIDGET_W)

	local gY = 0
	local _, gHeadH = Widgets.CreateHeading(gradientSection, 'Gradient Colors', 3)

	-- Helper to place a color+threshold row
	local function placeGradientRow(parent, label, colorKey, thresholdKey, defaultColor, defaultPct, rowY)
		local picker = Widgets.CreateColorPicker(parent, label, false,
			nil,
			function(r, g, b) setConfig(colorKey, { r, g, b }) end)
		picker:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, rowY)
		local saved = getConfig(colorKey) or defaultColor
		picker:SetColor(saved[1], saved[2], saved[3], 1)

		local pctSlider = Widgets.CreateSlider(parent, '% Threshold', WIDGET_W - 30, 0, 100, 5)
		pctSlider:SetValue(getConfig(thresholdKey) or defaultPct)
		pctSlider:SetAfterValueChanged(function(value)
			setConfig(thresholdKey, value)
		end)
		pctSlider:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, rowY - 22)
		return rowY - 22 - SLIDER_H - C.Spacing.normal
	end

	gY = -gHeadH
	gY = placeGradientRow(gradientSection, 'Healthy',
		'health.gradientColor1', 'health.gradientThreshold1',
		{ 0.2, 0.8, 0.2 }, 95, gY)
	gY = placeGradientRow(gradientSection, 'Warning',
		'health.gradientColor2', 'health.gradientThreshold2',
		{ 0.9, 0.6, 0.1 }, 50, gY)
	gY = placeGradientRow(gradientSection, 'Critical',
		'health.gradientColor3', 'health.gradientThreshold3',
		{ 0.8, 0.1, 0.1 }, 5, gY)

	local gradientSectionH = math.abs(gY)
	gradientSection:SetHeight(gradientSectionH)

	-- ── Custom color picker ─────────────────────────────────────
	local customSection = CreateFrame('Frame', nil, inner)
	customSection:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cardY)
	customSection:SetWidth(WIDGET_W)

	local customPicker = Widgets.CreateColorPicker(customSection, 'Health Bar Color', false,
		nil,
		function(r, g, b) setConfig('health.customColor', { r, g, b }) end)
	customPicker:SetPoint('TOPLEFT', customSection, 'TOPLEFT', 0, -C.Spacing.tight)
	local savedCustom = getConfig('health.customColor') or { 0.2, 0.8, 0.2 }
	customPicker:SetColor(savedCustom[1], savedCustom[2], savedCustom[3], 1)

	local customSectionH = 22 + C.Spacing.tight
	customSection:SetHeight(customSectionH)

	-- Show/hide sections based on color mode
	local function updateHealthColorSections(mode)
		if(mode == 'gradient') then
			gradientSection:Show()
			customSection:Hide()
			gradientSection:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cardY)
		elseif(mode == 'custom') then
			gradientSection:Hide()
			customSection:Show()
			customSection:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cardY)
		else
			gradientSection:Hide()
			customSection:Hide()
		end
	end

	local currentHealthMode = getConfig('health.colorMode') or 'class'
	updateHealthColorSections(currentHealthMode)

	-- Reserve space for the largest section
	local modeSectionH = math.max(gradientSectionH, customSectionH)
	if(currentHealthMode == 'gradient') then
		cardY = cardY - gradientSectionH
	elseif(currentHealthMode == 'custom') then
		cardY = cardY - customSectionH
	end

	healthColorSwitch:SetOnSelect(function(value)
		setConfig('health.colorMode', value)
		updateHealthColorSections(value)
	end)

	-- Smooth interpolation checkbox
	local smoothCheck = Widgets.CreateCheckButton(inner, 'Smooth Interpolation')
	smoothCheck:SetChecked(getConfig('health.smooth') ~= false)
	smoothCheck._callback = function(checked)
		setConfig('health.smooth', checked)
	end
	cardY = placeWidget(smoothCheck, inner, cardY, CHECK_H)

	-- ── Health Loss Color ─────────────────────────────────────
	cardY = placeHeading(inner, 'Health Loss Color', 3, cardY)

	local lossColorSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
		{ text = 'Dark',   value = 'dark' },
		{ text = 'Class',  value = 'class' },
		{ text = 'Custom', value = 'custom' },
	})
	lossColorSwitch:SetValue(getConfig('health.lossColorMode') or 'dark')
	cardY = placeWidget(lossColorSwitch, inner, cardY, SWITCH_H)

	-- Custom loss color picker
	local lossPicker = Widgets.CreateColorPicker(inner, 'Loss Color', false,
		nil,
		function(r, g, b) setConfig('health.lossCustomColor', { r, g, b }) end)
	local savedLoss = getConfig('health.lossCustomColor') or { 0.15, 0.15, 0.15 }
	lossPicker:SetColor(savedLoss[1], savedLoss[2], savedLoss[3], 1)
	cardY = placeWidget(lossPicker, inner, cardY, 22)

	local function updateLossColorUI(mode)
		if(mode == 'custom') then
			lossPicker:Show()
			lossPicker:Enable()
		else
			lossPicker:Hide()
		end
	end
	updateLossColorUI(getConfig('health.lossColorMode') or 'dark')

	lossColorSwitch:SetOnSelect(function(value)
		setConfig('health.lossColorMode', value)
		updateLossColorUI(value)
	end)

	yOffset = Widgets.EndCard(colorCard, content, cardY)

	-- ── Power Bar ─────────────────────────────────────────────
	yOffset = placeHeading(content, 'Power Bar', 2, yOffset)

	local powerCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	local showPowerCheck = Widgets.CreateCheckButton(inner, 'Show Power Bar')
	showPowerCheck:SetChecked(getConfig('showPower') ~= false)
	showPowerCheck._callback = function(checked)
		setConfig('showPower', checked)
	end
	cardY = placeWidget(showPowerCheck, inner, cardY, CHECK_H)

	-- Power bar height slider
	local powerHeightSlider = Widgets.CreateSlider(inner, 'Power Bar Height', WIDGET_W, 1, 20, 1)
	powerHeightSlider:SetValue(getConfig('power.height') or 2)
	powerHeightSlider:SetAfterValueChanged(function(value)
		setConfig('power.height', value)
	end)
	cardY = placeWidget(powerHeightSlider, inner, cardY, SLIDER_H)

	yOffset = Widgets.EndCard(powerCard, content, cardY)

	-- ── Card: Cast Bar ────────────────────────────────────────
	yOffset = placeHeading(content, 'Cast Bar', 2, yOffset)

	local castCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	local showCastCheck = Widgets.CreateCheckButton(inner, 'Show Cast Bar')
	showCastCheck:SetChecked(getConfig('showCastBar') ~= false)
	showCastCheck._callback = function(checked)
		setConfig('showCastBar', checked)
	end
	cardY = placeWidget(showCastCheck, inner, cardY, CHECK_H)

	-- Show absorb bar checkbox
	local showAbsorbCheck = Widgets.CreateCheckButton(inner, 'Show Absorb Bar')
	showAbsorbCheck:SetChecked(getConfig('showAbsorbBar') ~= false)
	showAbsorbCheck._callback = function(checked)
		setConfig('showAbsorbBar', checked)
	end
	cardY = placeWidget(showAbsorbCheck, inner, cardY, CHECK_H)

	yOffset = Widgets.EndCard(castCard, content, cardY)

	-- ── Name ──────────────────────────────────────────────────
	yOffset = placeHeading(content, 'Name', 2, yOffset)

	local nameCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	local showNameCheck = Widgets.CreateCheckButton(inner, 'Show Name')
	showNameCheck:SetChecked(getConfig('showName') ~= false)
	showNameCheck._callback = function(checked)
		setConfig('showName', checked)
	end
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

	-- Custom name color picker (shown only when 'custom' is selected)
	local nameCustomPicker = Widgets.CreateColorPicker(inner, 'Name Color', false,
		nil,
		function(r, g, b) setConfig('name.customColor', { r, g, b }) end)
	local savedNameColor = getConfig('name.customColor') or { 1, 1, 1 }
	nameCustomPicker:SetColor(savedNameColor[1], savedNameColor[2], savedNameColor[3], 1)
	cardY = placeWidget(nameCustomPicker, inner, cardY, 22)

	local function updateNameColorUI(mode)
		if(mode == 'custom') then
			nameCustomPicker:Show()
		else
			nameCustomPicker:Hide()
		end
	end
	updateNameColorUI(getConfig('name.colorMode') or 'class')

	nameColorSwitch:SetOnSelect(function(value)
		setConfig('name.colorMode', value)
		updateNameColorUI(value)
	end)

	-- Name font size
	local nameFontSize = Widgets.CreateSlider(inner, 'Font Size', WIDGET_W, 6, 24, 1)
	nameFontSize:SetValue(getConfig('name.fontSize') or 0)
	Widgets.SetTooltip(nameFontSize, 'Name Font Size', 'Override the global font size for name text')
	nameFontSize:SetAfterValueChanged(function(value)
		setConfig('name.fontSize', value)
	end)
	cardY = placeWidget(nameFontSize, inner, cardY, SLIDER_H)

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
	cardY = placeWidget(nameOutline, inner, cardY, DROPDOWN_H)

	-- Name shadow
	local nameShadow = Widgets.CreateCheckButton(inner, 'Text Shadow')
	nameShadow:SetChecked(getConfig('name.shadow') ~= false)
	nameShadow._callback = function(checked)
		setConfig('name.shadow', checked)
	end
	cardY = placeWidget(nameShadow, inner, cardY, CHECK_H)

	-- Name truncation slider
	local nameTruncSlider = Widgets.CreateSlider(inner, 'Name Truncation', WIDGET_W, 4, 20, 1)
	nameTruncSlider:SetValue(getConfig('name.truncate') or 10)
	nameTruncSlider:SetAfterValueChanged(function(value)
		setConfig('name.truncate', value)
	end)
	cardY = placeWidget(nameTruncSlider, inner, cardY, SLIDER_H)

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

	yOffset = Widgets.EndCard(nameCard, content, cardY)

	-- ── Card: Health Text ─────────────────────────────────────
	yOffset = placeHeading(content, 'Health Text', 2, yOffset)

	local healthTextCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	-- Attach to Name toggle
	local attachToNameCheck = Widgets.CreateCheckButton(inner, 'Attach to Name')
	local isAttached = getConfig('health.attachedToName') or false
	attachToNameCheck:SetChecked(isAttached)
	cardY = placeWidget(attachToNameCheck, inner, cardY, CHECK_H)

	local showHealthTextCheck = Widgets.CreateCheckButton(inner, 'Show Health Text')
	showHealthTextCheck:SetChecked(getConfig('health.showText') or false)
	showHealthTextCheck._callback = function(checked)
		setConfig('health.showText', checked)
	end
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
	local healthShadow = Widgets.CreateCheckButton(inner, 'Text Shadow')
	healthShadow:SetChecked(getConfig('health.shadow') ~= false)
	healthShadow._callback = function(checked)
		setConfig('health.shadow', checked)
	end
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

	-- Dim/enable health position controls based on "Attach to Name"
	local healthPositionWidgets = { healthTextAnchor, healthOffsetX, healthOffsetY }
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
	updateHealthPositionDimming(isAttached)

	attachToNameCheck._callback = function(checked)
		setConfig('health.attachedToName', checked)
		updateHealthPositionDimming(checked)
	end

	yOffset = Widgets.EndCard(healthTextCard, content, cardY)

	-- ── Card: Power Text ──────────────────────────────────────
	yOffset = placeHeading(content, 'Power Text', 2, yOffset)

	local powerTextCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	local showPowerTextCheck = Widgets.CreateCheckButton(inner, 'Show Power Text')
	showPowerTextCheck:SetChecked(getConfig('power.showText') or false)
	showPowerTextCheck._callback = function(checked)
		setConfig('power.showText', checked)
	end
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
	local powerShadow = Widgets.CreateCheckButton(inner, 'Text Shadow')
	powerShadow:SetChecked(getConfig('power.shadow') ~= false)
	powerShadow._callback = function(checked)
		setConfig('power.shadow', checked)
	end
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

	yOffset = Widgets.EndCard(powerTextCard, content, cardY)

	-- ── Status Icons ──────────────────────────────────────────
	yOffset = placeHeading(content, 'Status Icons', 2, yOffset)

	local iconsCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	-- Show role icon checkbox
	local showRoleCheck = Widgets.CreateCheckButton(inner, 'Show Role Icon')
	showRoleCheck:SetChecked(getConfig('statusIcons.role') ~= false)
	showRoleCheck._callback = function(checked)
		setConfig('statusIcons.role', checked)
	end
	cardY = placeWidget(showRoleCheck, inner, cardY, CHECK_H)

	-- Show leader icon checkbox
	local showLeaderCheck = Widgets.CreateCheckButton(inner, 'Show Leader Icon')
	showLeaderCheck:SetChecked(getConfig('statusIcons.leader') ~= false)
	showLeaderCheck._callback = function(checked)
		setConfig('statusIcons.leader', checked)
	end
	cardY = placeWidget(showLeaderCheck, inner, cardY, CHECK_H)

	-- Show ready check checkbox
	local showReadyCheckCheck = Widgets.CreateCheckButton(inner, 'Show Ready Check')
	showReadyCheckCheck:SetChecked(getConfig('statusIcons.readyCheck') ~= false)
	showReadyCheckCheck._callback = function(checked)
		setConfig('statusIcons.readyCheck', checked)
	end
	cardY = placeWidget(showReadyCheckCheck, inner, cardY, CHECK_H)

	-- Show raid icon checkbox
	local showRaidIconCheck = Widgets.CreateCheckButton(inner, 'Show Raid Icon')
	showRaidIconCheck:SetChecked(getConfig('statusIcons.raidIcon') ~= false)
	showRaidIconCheck._callback = function(checked)
		setConfig('statusIcons.raidIcon', checked)
	end
	cardY = placeWidget(showRaidIconCheck, inner, cardY, CHECK_H)

	-- Show combat icon checkbox
	local showCombatIconCheck = Widgets.CreateCheckButton(inner, 'Show Combat Icon')
	showCombatIconCheck:SetChecked(getConfig('statusIcons.combat') or false)
	showCombatIconCheck._callback = function(checked)
		setConfig('statusIcons.combat', checked)
	end
	cardY = placeWidget(showCombatIconCheck, inner, cardY, CHECK_H)

	yOffset = Widgets.EndCard(iconsCard, content, cardY)

	-- ── Resize content to fit all widgets ─────────────────────
	local totalH = math.abs(yOffset) + C.Spacing.normal
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
