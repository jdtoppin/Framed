local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

-- ============================================================
-- SharedCards — Reusable settings card builders
-- ============================================================

-- ============================================================
-- BuildFontCard
-- ============================================================

function F.Settings.BuildFontCard(parent, width, yOffset, label, configPrefix, get, set)
	local cardW = width
	local innerW = cardW - C.Spacing.tight * 2

	local card, cardH = Widgets.CreateCard(parent, cardW)
	card:ClearAllPoints()
	Widgets.SetPoint(card, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local cy = -C.Spacing.tight

	-- Heading
	local heading = Widgets.CreateFontString(card, C.Font.sizeSmall, C.Colors.textActive)
	heading:SetPoint('TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	heading:SetText(label)
	cy = cy - heading:GetStringHeight() - C.Spacing.base

	-- Font size slider
	local sizeSlider = Widgets.CreateSlider(card, innerW, 'Size', 6, 24, 1)
	Widgets.SetPoint(sizeSlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	sizeSlider:SetValue(get(configPrefix .. '.size') or 10)
	sizeSlider:SetOnValueChanged(function(val)
		set(configPrefix .. '.size', val)
	end)
	cy = cy - sizeSlider._explicitHeight - C.Spacing.base

	-- Outline dropdown
	local outlineItems = {
		{ label = 'None',    value = '' },
		{ label = 'Outline', value = 'OUTLINE' },
		{ label = 'Mono',    value = 'MONOCHROME' },
	}
	local outlineDD = Widgets.CreateDropdown(card, innerW, 'Outline', outlineItems)
	Widgets.SetPoint(outlineDD, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	outlineDD:SetSelectedValue(get(configPrefix .. '.outline') or '')
	outlineDD:SetOnValueChanged(function(val)
		set(configPrefix .. '.outline', val)
	end)
	cy = cy - outlineDD._explicitHeight - C.Spacing.base

	-- Shadow toggle
	local shadowSwitch = Widgets.CreateSwitch(card, 'Shadow')
	Widgets.SetPoint(shadowSwitch, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	shadowSwitch:SetChecked(get(configPrefix .. '.shadow') or false)
	shadowSwitch:SetOnValueChanged(function(val)
		set(configPrefix .. '.shadow', val)
	end)
	cy = cy - shadowSwitch._explicitHeight - C.Spacing.tight

	Widgets.SetCardHeight(card, math.abs(cy))
	return yOffset - math.abs(cy) - C.Spacing.normal
end

-- ============================================================
-- BuildGlowCard
-- ============================================================

function F.Settings.BuildGlowCard(parent, width, yOffset, get, set, opts)
	opts = opts or {}
	local cardW = width
	local innerW = cardW - C.Spacing.tight * 2

	local card, cardH = Widgets.CreateCard(parent, cardW)
	card:ClearAllPoints()
	Widgets.SetPoint(card, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local cy = -C.Spacing.tight

	-- Heading
	local heading = Widgets.CreateFontString(card, C.Font.sizeSmall, C.Colors.textActive)
	heading:SetPoint('TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	heading:SetText('Glow')
	cy = cy - heading:GetStringHeight() - C.Spacing.base

	-- Glow type dropdown
	local typeItems = {}
	if(opts.allowNone) then
		typeItems[#typeItems + 1] = { label = 'None', value = 'None' }
	end
	typeItems[#typeItems + 1] = { label = 'Proc',  value = C.GlowType.PROC }
	typeItems[#typeItems + 1] = { label = 'Pixel', value = C.GlowType.PIXEL }
	typeItems[#typeItems + 1] = { label = 'Soft',  value = C.GlowType.SOFT }
	typeItems[#typeItems + 1] = { label = 'Shine', value = C.GlowType.SHINE }

	local typeDD = Widgets.CreateDropdown(card, innerW, 'Glow Type', typeItems)
	Widgets.SetPoint(typeDD, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	typeDD:SetSelectedValue(get('glowType') or (opts.allowNone and 'None' or C.GlowType.PROC))
	cy = cy - typeDD._explicitHeight - C.Spacing.base

	-- Glow color picker
	local glowColor = get('glowColor') or { 1, 1, 1, 1 }
	local colorPicker = Widgets.CreateColorPicker(card, innerW, 'Color', glowColor)
	Widgets.SetPoint(colorPicker, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	colorPicker:SetOnColorChanged(function(r, g, b, a)
		set('glowColor', { r, g, b, a })
	end)
	if(get('glowType') == 'None') then colorPicker:Hide() end
	cy = cy - colorPicker._explicitHeight - C.Spacing.tight

	-- Wire type dropdown to show/hide color
	typeDD:SetOnValueChanged(function(val)
		set('glowType', val)
		if(val == 'None') then
			colorPicker:Hide()
		else
			colorPicker:Show()
		end
	end)

	Widgets.SetCardHeight(card, math.abs(cy))
	return yOffset - math.abs(cy) - C.Spacing.normal
end

-- ============================================================
-- BuildPositionCard
-- ============================================================

function F.Settings.BuildPositionCard(parent, width, yOffset, get, set, opts)
	opts = opts or {}
	local cardW = width
	local innerW = cardW - C.Spacing.tight * 2

	local card, cardH = Widgets.CreateCard(parent, cardW)
	card:ClearAllPoints()
	Widgets.SetPoint(card, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local cy = -C.Spacing.tight

	-- Heading
	local heading = Widgets.CreateFontString(card, C.Font.sizeSmall, C.Colors.textActive)
	heading:SetPoint('TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	heading:SetText('Position & Layer')
	cy = cy - heading:GetStringHeight() - C.Spacing.base

	if(not opts.hidePosition) then
		-- Anchor picker
		if(Widgets.CreateAnchorPicker) then
			local anchor = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
			local picker = Widgets.CreateAnchorPicker(card, innerW)
			Widgets.SetPoint(picker, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
			picker:SetAnchor(anchor)
			picker:SetOnAnchorChanged(function(a)
				set('anchor', a)
			end)
			cy = cy - picker._explicitHeight - C.Spacing.base
		end

		-- X offset slider
		local xSlider = Widgets.CreateSlider(card, innerW, 'X Offset', -50, 50, 1)
		Widgets.SetPoint(xSlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
		local anchor = get('anchor') or {}
		xSlider:SetValue(anchor[4] or 0)
		xSlider:SetOnValueChanged(function(val)
			local a = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
			a[4] = val
			set('anchor', a)
		end)
		cy = cy - xSlider._explicitHeight - C.Spacing.base

		-- Y offset slider
		local ySlider = Widgets.CreateSlider(card, innerW, 'Y Offset', -50, 50, 1)
		Widgets.SetPoint(ySlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
		ySlider:SetValue(anchor[5] or 0)
		ySlider:SetOnValueChanged(function(val)
			local a = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
			a[5] = val
			set('anchor', a)
		end)
		cy = cy - ySlider._explicitHeight - C.Spacing.base
	end

	-- Frame level slider
	if(not opts.hideFrameLevel) then
		local flSlider = Widgets.CreateSlider(card, innerW, 'Frame Level', 1, 50, 1)
		Widgets.SetPoint(flSlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
		flSlider:SetValue(get('frameLevel') or 5)
		flSlider:SetOnValueChanged(function(val)
			set('frameLevel', val)
		end)
		cy = cy - flSlider._explicitHeight - C.Spacing.tight
	end

	Widgets.SetCardHeight(card, math.abs(cy))
	return yOffset - math.abs(cy) - C.Spacing.normal
end

-- ============================================================
-- BuildThresholdColorCard
-- ============================================================

function F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set, opts)
	opts = opts or {}
	local cardW = width
	local innerW = cardW - C.Spacing.tight * 2

	local card, cardH = Widgets.CreateCard(parent, cardW)
	card:ClearAllPoints()
	Widgets.SetPoint(card, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	local cy = -C.Spacing.tight

	-- Heading
	local heading = Widgets.CreateFontString(card, C.Font.sizeSmall, C.Colors.textActive)
	heading:SetPoint('TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	heading:SetText('Colors')
	cy = cy - heading:GetStringHeight() - C.Spacing.base

	-- Base color
	local baseColor = get('color') or { 1, 1, 1, 1 }
	local basePicker = Widgets.CreateColorPicker(card, innerW, 'Color', baseColor)
	Widgets.SetPoint(basePicker, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	basePicker:SetOnColorChanged(function(r, g, b, a)
		set('color', { r, g, b, a })
	end)
	cy = cy - basePicker._explicitHeight - C.Spacing.base

	-- Low Time % toggle + threshold + color
	local ltc = get('lowTimeColor') or { enabled = false, threshold = 25, color = { 1, 0.5, 0, 1 } }
	local ltSwitch = Widgets.CreateSwitch(card, 'Low Time %')
	Widgets.SetPoint(ltSwitch, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	ltSwitch:SetChecked(ltc.enabled)
	cy = cy - ltSwitch._explicitHeight - C.Spacing.base

	local ltSlider = Widgets.CreateSlider(card, innerW, 'Threshold %', 5, 75, 5)
	Widgets.SetPoint(ltSlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	ltSlider:SetValue(ltc.threshold or 25)
	cy = cy - ltSlider._explicitHeight - C.Spacing.base

	local ltColor = Widgets.CreateColorPicker(card, innerW, 'Low Time Color', ltc.color or { 1, 0.5, 0, 1 })
	Widgets.SetPoint(ltColor, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	cy = cy - ltColor._explicitHeight - C.Spacing.base

	local function updateLowTime()
		set('lowTimeColor', {
			enabled   = ltSwitch:IsChecked(),
			threshold = ltSlider:GetValue(),
			color     = { ltColor:GetColor() },
		})
	end
	ltSwitch:SetOnValueChanged(function(val)
		ltSlider:SetShown(val)
		ltColor:SetShown(val)
		updateLowTime()
	end)
	ltSlider:SetOnValueChanged(function() updateLowTime() end)
	ltColor:SetOnColorChanged(function() updateLowTime() end)
	ltSlider:SetShown(ltc.enabled)
	ltColor:SetShown(ltc.enabled)

	-- Low Seconds toggle + threshold + color
	local lsc = get('lowSecsColor') or { enabled = false, threshold = 5, color = { 1, 0, 0, 1 } }
	local lsSwitch = Widgets.CreateSwitch(card, 'Low Seconds')
	Widgets.SetPoint(lsSwitch, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	lsSwitch:SetChecked(lsc.enabled)
	cy = cy - lsSwitch._explicitHeight - C.Spacing.base

	local lsSlider = Widgets.CreateSlider(card, innerW, 'Threshold (sec)', 1, 30, 1)
	Widgets.SetPoint(lsSlider, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	lsSlider:SetValue(lsc.threshold or 5)
	cy = cy - lsSlider._explicitHeight - C.Spacing.base

	local lsColor = Widgets.CreateColorPicker(card, innerW, 'Low Secs Color', lsc.color or { 1, 0, 0, 1 })
	Widgets.SetPoint(lsColor, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
	cy = cy - lsColor._explicitHeight - C.Spacing.base

	local function updateLowSecs()
		set('lowSecsColor', {
			enabled   = lsSwitch:IsChecked(),
			threshold = lsSlider:GetValue(),
			color     = { lsColor:GetColor() },
		})
	end
	lsSwitch:SetOnValueChanged(function(val)
		lsSlider:SetShown(val)
		lsColor:SetShown(val)
		updateLowSecs()
	end)
	lsSlider:SetOnValueChanged(function() updateLowSecs() end)
	lsColor:SetOnColorChanged(function() updateLowSecs() end)
	lsSlider:SetShown(lsc.enabled)
	lsColor:SetShown(lsc.enabled)

	-- Optional border/bg colors
	if(opts.showBorderColor) then
		local bc = get('borderColor') or { 0, 0, 0, 1 }
		local bcPicker = Widgets.CreateColorPicker(card, innerW, 'Border Color', bc)
		Widgets.SetPoint(bcPicker, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
		bcPicker:SetOnColorChanged(function(r, g, b, a)
			set('borderColor', { r, g, b, a })
		end)
		cy = cy - bcPicker._explicitHeight - C.Spacing.base
	end

	if(opts.showBgColor) then
		local bg = get('bgColor') or { 0, 0, 0, 0.5 }
		local bgPicker = Widgets.CreateColorPicker(card, innerW, 'Background Color', bg)
		Widgets.SetPoint(bgPicker, 'TOPLEFT', card, 'TOPLEFT', C.Spacing.tight, cy)
		bgPicker:SetOnColorChanged(function(r, g, b, a)
			set('bgColor', { r, g, b, a })
		end)
		cy = cy - bgPicker._explicitHeight - C.Spacing.tight
	end

	Widgets.SetCardHeight(card, math.abs(cy))
	return yOffset - math.abs(cy) - C.Spacing.normal
end
