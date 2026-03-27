local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

-- ============================================================
-- SharedCards — Reusable settings card builders
-- ============================================================

local SLIDER_H   = 26
local CHECK_H    = 22
local DROPDOWN_H = 22
local WIDGET_W   = 220

local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

local function placeHeading(content, text, yOffset)
	local heading, height = Widgets.CreateHeading(content, text, 3)
	heading:ClearAllPoints()
	Widgets.SetPoint(heading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height
end

-- ============================================================
-- BuildFontCard
-- ============================================================

function F.Settings.BuildFontCard(parent, width, yOffset, label, configPrefix, get, set)
	yOffset = placeHeading(parent, label, yOffset)

	local card, inner, cy = Widgets.StartCard(parent, width, yOffset)

	local fontCfg = get(configPrefix) or {}

	-- Font size slider
	local sizeSlider = Widgets.CreateSlider(inner, 'Size', WIDGET_W, 6, 24, 1)
	sizeSlider:SetValue(fontCfg.size or 10)
	sizeSlider:SetAfterValueChanged(function(val)
		fontCfg.size = val
		set(configPrefix, fontCfg)
	end)
	cy = placeWidget(sizeSlider, inner, cy, SLIDER_H)

	-- Outline dropdown
	local outlineDD = Widgets.CreateDropdown(inner, WIDGET_W)
	outlineDD:SetItems({
		{ text = 'None',    value = '' },
		{ text = 'Outline', value = 'OUTLINE' },
		{ text = 'Mono',    value = 'MONOCHROME' },
	})
	outlineDD:SetValue(fontCfg.outline or '')
	outlineDD:SetOnSelect(function(value)
		fontCfg.outline = value
		set(configPrefix, fontCfg)
	end)
	cy = placeWidget(outlineDD, inner, cy, DROPDOWN_H)

	-- Shadow toggle
	local shadowCB = Widgets.CreateCheckButton(inner, 'Shadow', function(checked)
		fontCfg.shadow = checked
		set(configPrefix, fontCfg)
	end)
	shadowCB:SetChecked(fontCfg.shadow or false)
	cy = placeWidget(shadowCB, inner, cy, CHECK_H)

	return Widgets.EndCard(card, parent, cy)
end

-- ============================================================
-- BuildGlowCard
-- ============================================================

function F.Settings.BuildGlowCard(parent, width, yOffset, get, set, opts)
	opts = opts or {}

	yOffset = placeHeading(parent, 'Glow', yOffset)

	local card, inner, cy = Widgets.StartCard(parent, width, yOffset)

	-- Glow type dropdown
	local typeItems = {}
	if(opts.allowNone) then
		typeItems[#typeItems + 1] = { text = 'None', value = 'None' }
	end
	typeItems[#typeItems + 1] = { text = 'Proc',  value = C.GlowType.PROC }
	typeItems[#typeItems + 1] = { text = 'Pixel', value = C.GlowType.PIXEL }
	typeItems[#typeItems + 1] = { text = 'Soft',  value = C.GlowType.SOFT }
	typeItems[#typeItems + 1] = { text = 'Shine', value = C.GlowType.SHINE }

	local typeDD = Widgets.CreateDropdown(inner, WIDGET_W)
	typeDD:SetItems(typeItems)
	typeDD:SetValue(get('glowType') or (opts.allowNone and 'None' or C.GlowType.PROC))
	cy = placeWidget(typeDD, inner, cy, DROPDOWN_H)

	-- Glow color picker
	local glowColor = get('glowColor') or { 1, 1, 1, 1 }
	local colorPicker = Widgets.CreateColorPicker(inner, 'Color', true, function(r, g, b, a)
		set('glowColor', { r, g, b, a })
	end)
	colorPicker:SetColor(glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 1)
	if(get('glowType') == 'None') then colorPicker:Hide() end
	cy = placeWidget(colorPicker, inner, cy, DROPDOWN_H)

	-- Wire type dropdown to show/hide color
	typeDD:SetOnSelect(function(value)
		set('glowType', value)
		if(value == 'None') then
			colorPicker:Hide()
		else
			colorPicker:Show()
		end
	end)

	return Widgets.EndCard(card, parent, cy)
end

-- ============================================================
-- BuildPositionCard
-- ============================================================

function F.Settings.BuildPositionCard(parent, width, yOffset, get, set, opts)
	opts = opts or {}

	yOffset = placeHeading(parent, 'Position & Layer', yOffset)

	local card, inner, cy = Widgets.StartCard(parent, width, yOffset)

	if(not opts.hidePosition) then
		-- Anchor picker (includes its own X/Y offset inputs)
		if(Widgets.CreateAnchorPicker) then
			local anchor = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
			local picker = Widgets.CreateAnchorPicker(inner, WIDGET_W)
			picker:SetAnchor(anchor[1] or 'CENTER', anchor[4] or 0, anchor[5] or 0)
			picker:SetOnChanged(function(point, x, y)
				local a = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
				a[1] = point
				a[3] = point
				a[4] = x
				a[5] = y
				set('anchor', a)
			end)
			cy = placeWidget(picker, inner, cy, picker._height or 91)
		end
	end

	-- Frame level slider
	if(not opts.hideFrameLevel) then
		local flSlider = Widgets.CreateSlider(inner, 'Frame Level', WIDGET_W, 1, 50, 1)
		flSlider:SetValue(get('frameLevel') or 5)
		flSlider:SetAfterValueChanged(function(val)
			set('frameLevel', val)
		end)
		cy = placeWidget(flSlider, inner, cy, SLIDER_H)
	end

	return Widgets.EndCard(card, parent, cy)
end

-- ============================================================
-- BuildThresholdColorCard
-- ============================================================

function F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set, opts)
	opts = opts or {}

	yOffset = placeHeading(parent, 'Colors', yOffset)

	local card, inner, cy = Widgets.StartCard(parent, width, yOffset)

	-- Base color
	local baseColor = get('color') or { 1, 1, 1, 1 }
	local basePicker = Widgets.CreateColorPicker(inner, 'Color', true, function(r, g, b, a)
		set('color', { r, g, b, a })
	end)
	basePicker:SetColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)
	cy = placeWidget(basePicker, inner, cy, DROPDOWN_H)

	-- Low Time % toggle + threshold + color
	local ltc = get('lowTimeColor') or { enabled = false, threshold = 25, color = { 1, 0.5, 0, 1 } }

	local ltSlider, ltColor

	local ltSwitch = Widgets.CreateCheckButton(inner, 'Low Time %', function(checked)
		ltc.enabled = checked
		if(ltSlider) then ltSlider:SetShown(checked) end
		if(ltColor) then ltColor:SetShown(checked) end
		set('lowTimeColor', ltc)
	end)
	ltSwitch:SetChecked(ltc.enabled)
	cy = placeWidget(ltSwitch, inner, cy, CHECK_H)

	ltSlider = Widgets.CreateSlider(inner, 'Threshold %', WIDGET_W, 5, 75, 5)
	ltSlider:SetValue(ltc.threshold or 25)
	ltSlider:SetAfterValueChanged(function(val)
		ltc.threshold = val
		set('lowTimeColor', ltc)
	end)
	ltSlider:SetShown(ltc.enabled)
	cy = placeWidget(ltSlider, inner, cy, SLIDER_H)

	local ltColorVal = ltc.color or { 1, 0.5, 0, 1 }
	ltColor = Widgets.CreateColorPicker(inner, 'Low Time Color', true, function(r, g, b, a)
		ltc.color = { r, g, b, a }
		set('lowTimeColor', ltc)
	end)
	ltColor:SetColor(ltColorVal[1], ltColorVal[2], ltColorVal[3], ltColorVal[4] or 1)
	ltColor:SetShown(ltc.enabled)
	cy = placeWidget(ltColor, inner, cy, DROPDOWN_H)

	-- Low Seconds toggle + threshold + color
	local lsc = get('lowSecsColor') or { enabled = false, threshold = 5, color = { 1, 0, 0, 1 } }

	local lsSlider, lsColor

	local lsSwitch = Widgets.CreateCheckButton(inner, 'Low Seconds', function(checked)
		lsc.enabled = checked
		if(lsSlider) then lsSlider:SetShown(checked) end
		if(lsColor) then lsColor:SetShown(checked) end
		set('lowSecsColor', lsc)
	end)
	lsSwitch:SetChecked(lsc.enabled)
	cy = placeWidget(lsSwitch, inner, cy, CHECK_H)

	lsSlider = Widgets.CreateSlider(inner, 'Threshold (sec)', WIDGET_W, 1, 30, 1)
	lsSlider:SetValue(lsc.threshold or 5)
	lsSlider:SetAfterValueChanged(function(val)
		lsc.threshold = val
		set('lowSecsColor', lsc)
	end)
	lsSlider:SetShown(lsc.enabled)
	cy = placeWidget(lsSlider, inner, cy, SLIDER_H)

	local lsColorVal = lsc.color or { 1, 0, 0, 1 }
	lsColor = Widgets.CreateColorPicker(inner, 'Low Secs Color', true, function(r, g, b, a)
		lsc.color = { r, g, b, a }
		set('lowSecsColor', lsc)
	end)
	lsColor:SetColor(lsColorVal[1], lsColorVal[2], lsColorVal[3], lsColorVal[4] or 1)
	lsColor:SetShown(lsc.enabled)
	cy = placeWidget(lsColor, inner, cy, DROPDOWN_H)

	-- Optional border/bg colors
	if(opts.showBorderColor) then
		local bc = get('borderColor') or { 0, 0, 0, 1 }
		local bcPicker = Widgets.CreateColorPicker(inner, 'Border Color', true, function(r, g, b, a)
			set('borderColor', { r, g, b, a })
		end)
		bcPicker:SetColor(bc[1], bc[2], bc[3], bc[4] or 1)
		cy = placeWidget(bcPicker, inner, cy, DROPDOWN_H)
	end

	if(opts.showBgColor) then
		local bg = get('bgColor') or { 0, 0, 0, 0.5 }
		local bgPicker = Widgets.CreateColorPicker(inner, 'Background Color', true, function(r, g, b, a)
			set('bgColor', { r, g, b, a })
		end)
		bgPicker:SetColor(bg[1], bg[2], bg[3], bg[4] or 1)
		cy = placeWidget(bgPicker, inner, cy, DROPDOWN_H)
	end

	return Widgets.EndCard(card, parent, cy)
end
