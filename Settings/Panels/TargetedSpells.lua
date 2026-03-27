local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Widget constants
-- ============================================================

local SLIDER_H     = 26
local DROPDOWN_H   = 22
local WIDGET_W     = 220

-- ============================================================
-- Config helpers
-- ============================================================

local function get(key)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.targetedSpells.' .. key)
end

local function set(key, value)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.targetedSpells.' .. key, value)
	end
	if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.targetedSpells')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'targetedspells',
	label   = 'Targeted Spells',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 14,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll  = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'targetedspells', 'targetedSpells')

		-- ── Description ────────────────────────────────────────
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('Highlight units that are casting targeted spells at the group. Supports icon display, border glow, or both.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.tight

		-- Reload notice
		local reloadInfo = Widgets.CreateInfoIcon(content,
			'Requires /reload',
			'Changing the display mode between Icons, Border Glow, and Both requires a /reload because it creates or destroys icon pools and glow overlays.')
		reloadInfo:ClearAllPoints()
		Widgets.SetPoint(reloadInfo, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - reloadInfo:GetHeight() - C.Spacing.normal

		-- ── Display Mode ───────────────────────────────────────
		local modeHeading, modeHeadingH = Widgets.CreateHeading(content, 'Display Mode', 2)
		modeHeading:ClearAllPoints()
		Widgets.SetPoint(modeHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - modeHeadingH

		local modeCard, modeInner, modeCardY
		modeCard, modeInner, modeCardY = Widgets.StartCard(content, width, yOffset)

		local modeDD = Widgets.CreateDropdown(modeInner, WIDGET_W)
		modeDD:SetItems({
			{ text = 'Icons',       value = 'Icons' },
			{ text = 'Border Glow', value = 'BorderGlow' },
			{ text = 'Both',        value = 'Both' },
		})
		modeDD:SetValue(get('displayMode') or 'Both')
		modeDD:ClearAllPoints()
		Widgets.SetPoint(modeDD, 'TOPLEFT', modeInner, 'TOPLEFT', 0, modeCardY)
		modeCardY = modeCardY - DROPDOWN_H - C.Spacing.normal

		yOffset = Widgets.EndCard(modeCard, content, modeCardY)

		-- ── Icon Settings (shown for Icons or Both) ─────────────
		local iconHeading, iconHeadingH = Widgets.CreateHeading(content, 'Icon Settings', 2)
		iconHeading:ClearAllPoints()
		Widgets.SetPoint(iconHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - iconHeadingH

		local iconCard, iconInner, iconCardY
		iconCard, iconInner, iconCardY = Widgets.StartCard(content, width, yOffset)

		local sizeSlider = Widgets.CreateSlider(iconInner, 'Icon Size', WIDGET_W, 8, 48, 1)
		sizeSlider:SetValue(get('iconSize') or 16)
		sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
		sizeSlider:ClearAllPoints()
		Widgets.SetPoint(sizeSlider, 'TOPLEFT', iconInner, 'TOPLEFT', 0, iconCardY)
		iconCardY = iconCardY - SLIDER_H - C.Spacing.normal

		local maxSlider = Widgets.CreateSlider(iconInner, 'Max Displayed', WIDGET_W, 1, 10, 1)
		maxSlider:SetValue(get('maxDisplayed') or 1)
		maxSlider:SetAfterValueChanged(function(v) set('maxDisplayed', v) end)
		maxSlider:ClearAllPoints()
		Widgets.SetPoint(maxSlider, 'TOPLEFT', iconInner, 'TOPLEFT', 0, iconCardY)
		iconCardY = iconCardY - SLIDER_H - C.Spacing.normal

		local iconLvlSlider = Widgets.CreateSlider(iconInner, 'Frame Level', WIDGET_W, 1, 20, 1)
		iconLvlSlider:SetValue(get('frameLevel') or 5)
		iconLvlSlider:SetAfterValueChanged(function(v) set('frameLevel', v) end)
		iconLvlSlider:ClearAllPoints()
		Widgets.SetPoint(iconLvlSlider, 'TOPLEFT', iconInner, 'TOPLEFT', 0, iconCardY)
		iconCardY = iconCardY - SLIDER_H - C.Spacing.normal

		local iconAnchorPicker = nil
		if(Widgets.CreateAnchorPicker) then
			local anchorData = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
			iconAnchorPicker = Widgets.CreateAnchorPicker(iconInner, width)
			iconAnchorPicker:SetAnchor(anchorData[1], anchorData[4] or 0, anchorData[5] or 0)
			iconAnchorPicker:ClearAllPoints()
			Widgets.SetPoint(iconAnchorPicker, 'TOPLEFT', iconInner, 'TOPLEFT', 0, iconCardY)
			iconAnchorPicker:SetOnChanged(function(point, x, y)
				set('anchor', { point, nil, point, x, y })
			end)
			iconCardY = iconCardY - iconAnchorPicker:GetHeight() - C.Spacing.normal
		end

		yOffset = Widgets.EndCard(iconCard, content, iconCardY)

		-- ── Border Glow Settings (shown for BorderGlow or Both) ─
		local glowHeading, glowHeadingH = Widgets.CreateHeading(content, 'Border Glow Settings', 2)
		glowHeading:ClearAllPoints()
		Widgets.SetPoint(glowHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - glowHeadingH

		local glowCard, glowInner, glowCardY
		glowCard, glowInner, glowCardY = Widgets.StartCard(content, width, yOffset)

		local glowTypeLabel, glowTypeLabelH = Widgets.CreateHeading(glowInner, 'Glow Type', 3)
		glowTypeLabel:ClearAllPoints()
		Widgets.SetPoint(glowTypeLabel, 'TOPLEFT', glowInner, 'TOPLEFT', 0, glowCardY)
		glowCardY = glowCardY - glowTypeLabelH

		local glowDD = Widgets.CreateDropdown(glowInner, WIDGET_W)
		glowDD:SetItems({
			{ text = 'Proc',  value = C.GlowType.PROC },
			{ text = 'Pixel', value = C.GlowType.PIXEL },
			{ text = 'Soft',  value = C.GlowType.SOFT },
			{ text = 'Shine', value = C.GlowType.SHINE },
		})
		glowDD:SetValue(get('glow.type') or C.GlowType.PROC)
		glowDD:SetOnSelect(function(v) set('glow.type', v) end)
		glowDD:ClearAllPoints()
		Widgets.SetPoint(glowDD, 'TOPLEFT', glowInner, 'TOPLEFT', 0, glowCardY)
		glowCardY = glowCardY - DROPDOWN_H - C.Spacing.normal

		local glowColorPicker = nil
		if(Widgets.CreateColorPicker) then
			glowColorPicker = Widgets.CreateColorPicker(glowInner, 'Glow Color')
			glowColorPicker:ClearAllPoints()
			Widgets.SetPoint(glowColorPicker, 'TOPLEFT', glowInner, 'TOPLEFT', 0, glowCardY)
			local savedColor = get('glow.color')
			if(savedColor) then
				glowColorPicker:SetColor(savedColor[1], savedColor[2], savedColor[3])
			end
			glowColorPicker:SetOnColorChanged(function(r, g, b)
				set('glow.color', { r, g, b })
			end)
			glowCardY = glowCardY - glowColorPicker:GetHeight() - C.Spacing.normal
		end

		-- ── Per glow type parameters (match Cell UX) ───────────
		-- Pixel: lines, frequency, length, thickness
		local pixelLinesSlider = Widgets.CreateSlider(glowInner, 'Lines', WIDGET_W, 1, 30, 1)
		pixelLinesSlider:SetValue(get('glow.lines') or 8)
		pixelLinesSlider:SetAfterValueChanged(function(v) set('glow.lines', v) end)
		pixelLinesSlider:ClearAllPoints()
		Widgets.SetPoint(pixelLinesSlider, 'TOPLEFT', glowInner, 'TOPLEFT', 0, glowCardY)

		local pixelFreqSlider = Widgets.CreateSlider(glowInner, 'Speed', WIDGET_W, -2, 2, 0.1)
		pixelFreqSlider:SetValue(get('glow.frequency') or 0.25)
		pixelFreqSlider:SetAfterValueChanged(function(v) set('glow.frequency', v) end)
		pixelFreqSlider:ClearAllPoints()
		Widgets.SetPoint(pixelFreqSlider, 'TOPLEFT', glowInner, 'TOPLEFT', 0, glowCardY - SLIDER_H - C.Spacing.tight)

		local pixelLenSlider = Widgets.CreateSlider(glowInner, 'Length', WIDGET_W, 1, 50, 1)
		pixelLenSlider:SetValue(get('glow.length') or 6)
		pixelLenSlider:SetAfterValueChanged(function(v) set('glow.length', v) end)
		pixelLenSlider:ClearAllPoints()
		Widgets.SetPoint(pixelLenSlider, 'TOPLEFT', glowInner, 'TOPLEFT', 0, glowCardY - (SLIDER_H + C.Spacing.tight) * 2)

		local pixelThickSlider = Widgets.CreateSlider(glowInner, 'Thickness', WIDGET_W, 1, 20, 1)
		pixelThickSlider:SetValue(get('glow.thickness') or 2)
		pixelThickSlider:SetAfterValueChanged(function(v) set('glow.thickness', v) end)
		pixelThickSlider:ClearAllPoints()
		Widgets.SetPoint(pixelThickSlider, 'TOPLEFT', glowInner, 'TOPLEFT', 0, glowCardY - (SLIDER_H + C.Spacing.tight) * 3)

		-- Soft/Shine: particles, frequency, scale
		local softParticlesSlider = Widgets.CreateSlider(glowInner, 'Particles', WIDGET_W, 1, 30, 1)
		softParticlesSlider:SetValue(get('glow.particles') or 4)
		softParticlesSlider:SetAfterValueChanged(function(v) set('glow.particles', v) end)
		softParticlesSlider:ClearAllPoints()
		Widgets.SetPoint(softParticlesSlider, 'TOPLEFT', glowInner, 'TOPLEFT', 0, glowCardY)

		local softFreqSlider = Widgets.CreateSlider(glowInner, 'Speed', WIDGET_W, -2, 2, 0.1)
		softFreqSlider:SetValue(get('glow.frequency') or 0.125)
		softFreqSlider:SetAfterValueChanged(function(v) set('glow.frequency', v) end)
		softFreqSlider:ClearAllPoints()
		Widgets.SetPoint(softFreqSlider, 'TOPLEFT', glowInner, 'TOPLEFT', 0, glowCardY - SLIDER_H - C.Spacing.tight)

		local softScaleSlider = Widgets.CreateSlider(glowInner, 'Scale %', WIDGET_W, 50, 500, 5)
		softScaleSlider:SetValue(math.floor((get('glow.scale') or 1) * 100))
		softScaleSlider:SetAfterValueChanged(function(v) set('glow.scale', v / 100) end)
		softScaleSlider:ClearAllPoints()
		Widgets.SetPoint(softScaleSlider, 'TOPLEFT', glowInner, 'TOPLEFT', 0, glowCardY - (SLIDER_H + C.Spacing.tight) * 2)

		-- Proc: frequency only
		local procFreqSlider = Widgets.CreateSlider(glowInner, 'Speed', WIDGET_W, -2, 2, 0.1)
		procFreqSlider:SetValue(get('glow.frequency') or 0)
		procFreqSlider:SetAfterValueChanged(function(v) set('glow.frequency', v) end)
		procFreqSlider:ClearAllPoints()
		Widgets.SetPoint(procFreqSlider, 'TOPLEFT', glowInner, 'TOPLEFT', 0, glowCardY)

		-- Track per-type widgets for visibility toggling
		local pixelWidgets = { pixelLinesSlider, pixelFreqSlider, pixelLenSlider, pixelThickSlider }
		local softWidgets  = { softParticlesSlider, softFreqSlider, softScaleSlider }
		local procWidgets  = { procFreqSlider }
		local allGlowParamWidgets = {}
		for _, w in next, pixelWidgets do allGlowParamWidgets[#allGlowParamWidgets + 1] = w end
		for _, w in next, softWidgets  do allGlowParamWidgets[#allGlowParamWidgets + 1] = w end
		for _, w in next, procWidgets  do allGlowParamWidgets[#allGlowParamWidgets + 1] = w end

		local function updateGlowParamVisibility(glowType)
			local isPixel = (glowType == C.GlowType.PIXEL)
			local isSoft  = (glowType == C.GlowType.SOFT or glowType == C.GlowType.SHINE)
			local isProc  = (glowType == C.GlowType.PROC)
			for _, w in next, pixelWidgets do w:SetShown(isPixel) end
			for _, w in next, softWidgets  do w:SetShown(isSoft)  end
			for _, w in next, procWidgets  do w:SetShown(isProc)  end

			-- Adjust card height based on visible sliders
			local visibleCount = 0
			if(isPixel) then visibleCount = 4
			elseif(isSoft) then visibleCount = 3
			elseif(isProc) then visibleCount = 1
			end
			-- The card was already ended, but we need to recalculate the
			-- glow card yOffset based on visible params
		end

		updateGlowParamVisibility(get('glow.type') or C.GlowType.PROC)

		-- Determine max slider rows needed for card height (4 = pixel)
		glowCardY = glowCardY - (SLIDER_H + C.Spacing.tight) * 4 - C.Spacing.normal

		yOffset = Widgets.EndCard(glowCard, content, glowCardY)

		-- ── Display mode visibility ─────────────────────────────
		local iconWidgets = { iconHeading, sizeSlider, maxSlider, iconLvlSlider }
		if(iconAnchorPicker) then iconWidgets[#iconWidgets + 1] = iconAnchorPicker end

		local glowWidgets = { glowHeading, glowDD }
		if(glowColorPicker) then glowWidgets[#glowWidgets + 1] = glowColorPicker end
		for _, w in next, allGlowParamWidgets do glowWidgets[#glowWidgets + 1] = w end

		local function updatePaneVisibility(mode)
			local showIcons = (mode == 'Icons' or mode == 'Both')
			local showGlow  = (mode == 'BorderGlow' or mode == 'Both')
			for _, w in next, iconWidgets do w:SetShown(showIcons) end
			for _, w in next, glowWidgets  do w:SetShown(showGlow)  end
			-- Re-apply per-type visibility within the glow section
			if(showGlow) then
				updateGlowParamVisibility(glowDD:GetValue() or C.GlowType.PROC)
			end
		end

		updatePaneVisibility(get('displayMode') or 'Both')

		-- Wire glow type dropdown to update per-type sliders
		glowDD:SetOnSelect(function(v)
			set('glow.type', v)
			updateGlowParamVisibility(v)
		end)

		modeDD:SetOnSelect(function(v)
			set('displayMode', v)
			updatePaneVisibility(v)
		end)

		-- ── Final height ────────────────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
