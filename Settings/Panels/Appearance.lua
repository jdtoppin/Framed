local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Widget heights (for vertical layout accounting)
-- ============================================================

local SLIDER_H     = 26
local CHECK_H      = 22
local DROPDOWN_H   = 22
local SWATCH_H     = 20
local BUTTON_H     = 28
local WIDGET_W     = 220

-- ============================================================
-- Section helpers (mirrors FrameSettingsBuilder pattern)
-- ============================================================

local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

local function placeHeading(content, text, level, yOffset, width)
	local heading, height = Widgets.CreateHeading(content, text, level, width)
	heading:ClearAllPoints()
	Widgets.SetPoint(heading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'appearance',
	label   = 'Appearance',
	section = 'GLOBAL',
	order   = 10,
	create  = function(parent)
		-- ── Scroll frame wrapping the whole panel ─────────────
		local parentW = parent._explicitWidth or parent:GetWidth() or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width = parentW - C.Spacing.normal * 2

		-- Running y offset (relative to content top, negative)
		local yOffset = -C.Spacing.normal

		-- ── Config helpers ─────────────────────────────────────
		local function getConfig(key)
			return F.Config and F.Config:Get('general.' .. key)
		end
		local function setConfig(key, value)
			if(F.Config) then
				F.Config:Set('general.' .. key, value)
			end
		end
		local function fireChange()
			if(F.EventBus) then
				F.EventBus:Fire('CONFIG_CHANGED:general')
			end
		end

		-- ── Settings Accent Color ──────────────────────────────
		yOffset = placeHeading(content, 'Settings Accent Color', 2, yOffset)

		local accentCard, accentInner, accentY
		accentCard, accentInner, accentY = Widgets.StartCard(content, width, yOffset)

		local colorPicker = Widgets.CreateColorPicker(accentInner)
		colorPicker:ClearAllPoints()
		Widgets.SetPoint(colorPicker, 'TOPLEFT', accentInner, 'TOPLEFT', 0, accentY)

		local savedColor = getConfig('accentColor')
		if(savedColor) then
			colorPicker:SetColor(savedColor[1], savedColor[2], savedColor[3], savedColor[4] or 1)
		else
			colorPicker:SetColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
		end

		colorPicker:SetOnColorChanged(function(r, g, b, a)
			C.Colors.accent      = { r, g, b, a }
			C.Colors.accentDim   = { r, g, b, 0.3 }
			C.Colors.accentHover = { r, g, b, 0.6 }
			setConfig('accentColor', { r, g, b, a })
			fireChange()
		end)

		accentY = accentY - SWATCH_H - C.Spacing.normal
		yOffset = Widgets.EndCard(accentCard, content, accentY)

		-- ── UI Scale ───────────────────────────────────────────
		yOffset = placeHeading(content, 'UI Scale', 2, yOffset)

		local scaleCard, scaleInner, scaleY
		scaleCard, scaleInner, scaleY = Widgets.StartCard(content, width, yOffset)

		local scaleSlider = Widgets.CreateSlider(scaleInner, 'Scale', WIDGET_W, 0.2, 1.5, 0.01)
		scaleY = placeWidget(scaleSlider, scaleInner, scaleY, SLIDER_H)
		scaleSlider:SetFormat('%.2f')

		local savedScale = getConfig('uiScale')
		if(savedScale) then
			scaleSlider:SetValue(savedScale)
		else
			scaleSlider:SetValue(1.0)
		end

		scaleSlider:SetAfterValueChanged(function(value)
			setConfig('uiScale', value)
			fireChange()
		end)

		yOffset = Widgets.EndCard(scaleCard, content, scaleY)

		-- ── Global Font ────────────────────────────────────────
		yOffset = placeHeading(content, 'Global Font', 2, yOffset)

		local fontCard, fontInner, fontY
		fontCard, fontInner, fontY = Widgets.StartCard(content, width, yOffset)

		local fontDropdown = Widgets.CreateTextureDropdown(fontInner, WIDGET_W, 'font')
		fontY = placeWidget(fontDropdown, fontInner, fontY, DROPDOWN_H)

		local savedFont = getConfig('font')
		if(savedFont) then
			fontDropdown:SetValue(savedFont)
		end

		fontDropdown:SetOnSelect(function(texturePath, name)
			setConfig('font', name)
			fireChange()
		end)

		yOffset = Widgets.EndCard(fontCard, content, fontY)

		-- ── Health Bar Texture ─────────────────────────────────
		yOffset = placeHeading(content, 'Health Bar Texture', 2, yOffset)

		local barCard, barInner, barY
		barCard, barInner, barY = Widgets.StartCard(content, width, yOffset)

		local barDropdown = Widgets.CreateTextureDropdown(barInner, WIDGET_W, 'statusbar')
		barY = placeWidget(barDropdown, barInner, barY, DROPDOWN_H)

		local savedBar = getConfig('barTexture')
		if(savedBar) then
			barDropdown:SetValue(savedBar)
		end

		barDropdown:SetOnSelect(function(texturePath, name)
			setConfig('barTexture', name)
			fireChange()
		end)

		yOffset = Widgets.EndCard(barCard, content, barY)

		-- ── Target Highlight Settings ──────────────────────────
		yOffset = placeHeading(content, 'Target Highlight Settings', 2, yOffset)

		local targetCard, targetInner, targetY
		targetCard, targetInner, targetY = Widgets.StartCard(content, width, yOffset)

		targetY = placeHeading(targetInner, 'Color', 3, targetY)

		local thColorPicker = Widgets.CreateColorPicker(targetInner)
		thColorPicker:SetHasAlpha(true)
		thColorPicker:ClearAllPoints()
		Widgets.SetPoint(thColorPicker, 'TOPLEFT', targetInner, 'TOPLEFT', 0, targetY)

		local savedThColor = getConfig('targetHighlightColor')
		if(savedThColor) then
			thColorPicker:SetColor(savedThColor[1], savedThColor[2], savedThColor[3], savedThColor[4] or 1)
		else
			thColorPicker:SetColor(0.839, 0, 0.075, 1)  -- #d60013
		end

		thColorPicker:SetOnColorChanged(function(r, g, b, a)
			setConfig('targetHighlightColor', { r, g, b, a })
		end)
		targetY = targetY - SWATCH_H - C.Spacing.normal

		local thWidthSlider = Widgets.CreateSlider(targetInner, 'Border Width', WIDGET_W, 1, 4, 1)
		thWidthSlider:SetValue(getConfig('targetHighlightWidth') or 2)
		thWidthSlider:SetAfterValueChanged(function(value)
			setConfig('targetHighlightWidth', value)
		end)
		targetY = placeWidget(thWidthSlider, targetInner, targetY, SLIDER_H)

		yOffset = Widgets.EndCard(targetCard, content, targetY)

		-- ── Mouseover Highlight Settings ──────────────────────
		yOffset = placeHeading(content, 'Mouseover Highlight Settings', 2, yOffset)

		local moCard, moInner, moY
		moCard, moInner, moY = Widgets.StartCard(content, width, yOffset)

		moY = placeHeading(moInner, 'Color', 3, moY)

		local moColorPicker = Widgets.CreateColorPicker(moInner)
		moColorPicker:SetHasAlpha(true)
		moColorPicker:ClearAllPoints()
		Widgets.SetPoint(moColorPicker, 'TOPLEFT', moInner, 'TOPLEFT', 0, moY)

		local savedMoColor = getConfig('mouseoverHighlightColor')
		if(savedMoColor) then
			moColorPicker:SetColor(savedMoColor[1], savedMoColor[2], savedMoColor[3], savedMoColor[4] or 0.6)
		else
			moColorPicker:SetColor(0.969, 0.925, 1, 0.6)  -- #f7ecff @ 60%
		end

		moColorPicker:SetOnColorChanged(function(r, g, b, a)
			setConfig('mouseoverHighlightColor', { r, g, b, a })
		end)
		moY = moY - SWATCH_H - C.Spacing.normal

		local moWidthSlider = Widgets.CreateSlider(moInner, 'Border Width', WIDGET_W, 1, 4, 1)
		moWidthSlider:SetValue(getConfig('mouseoverHighlightWidth') or 2)
		moWidthSlider:SetAfterValueChanged(function(value)
			setConfig('mouseoverHighlightWidth', value)
		end)
		moY = placeWidget(moWidthSlider, moInner, moY, SLIDER_H)

		yOffset = Widgets.EndCard(moCard, content, moY)

		-- ── Tooltips ──────────────────────────────────────────
		yOffset = placeHeading(content, 'Tooltips', 2, yOffset)

		local ttCard, ttInner, ttY
		ttCard, ttInner, ttY = Widgets.StartCard(content, width, yOffset)

		local ttEnabled = Widgets.CreateCheckButton(ttInner, 'Show Tooltips', function(checked)
			setConfig('tooltipEnabled', checked)
			fireChange()
		end)
		ttEnabled:SetChecked(getConfig('tooltipEnabled') ~= false)
		ttY = placeWidget(ttEnabled, ttInner, ttY, CHECK_H)

		local ttCombat = Widgets.CreateCheckButton(ttInner, 'Hide in Combat', function(checked)
			setConfig('tooltipHideInCombat', checked)
			fireChange()
		end)
		ttCombat:SetChecked(getConfig('tooltipHideInCombat') == true)
		ttY = placeWidget(ttCombat, ttInner, ttY, CHECK_H)

		local ttAnchor = Widgets.CreateDropdown(ttInner, WIDGET_W)
		ttAnchor:SetItems({
			{ text = 'Right',  value = 'ANCHOR_RIGHT' },
			{ text = 'Left',   value = 'ANCHOR_LEFT' },
			{ text = 'Top',    value = 'ANCHOR_TOP' },
			{ text = 'Bottom', value = 'ANCHOR_BOTTOM' },
			{ text = 'Cursor', value = 'ANCHOR_CURSOR' },
		})
		ttAnchor:SetValue(getConfig('tooltipAnchor') or 'ANCHOR_RIGHT')
		ttAnchor:SetOnSelect(function(value)
			setConfig('tooltipAnchor', value)
			fireChange()
		end)
		ttY = placeWidget(ttAnchor, ttInner, ttY, DROPDOWN_H)

		local ttOffX = Widgets.CreateSlider(ttInner, 'X Offset', WIDGET_W, -50, 50, 1)
		ttOffX:SetValue(getConfig('tooltipOffsetX') or 0)
		ttOffX:SetAfterValueChanged(function(value)
			setConfig('tooltipOffsetX', value)
			fireChange()
		end)
		ttY = placeWidget(ttOffX, ttInner, ttY, SLIDER_H)

		local ttOffY = Widgets.CreateSlider(ttInner, 'Y Offset', WIDGET_W, -50, 50, 1)
		ttOffY:SetValue(getConfig('tooltipOffsetY') or 0)
		ttOffY:SetAfterValueChanged(function(value)
			setConfig('tooltipOffsetY', value)
			fireChange()
		end)
		ttY = placeWidget(ttOffY, ttInner, ttY, SLIDER_H)

		yOffset = Widgets.EndCard(ttCard, content, ttY)

		-- ── Re-run Setup Wizard ────────────────────────────────
		yOffset = placeHeading(content, 'Setup Wizard', 2, yOffset)

		local wizardCard, wizardInner, wizardY
		wizardCard, wizardInner, wizardY = Widgets.StartCard(content, width, yOffset)

		local wizardBtn = Widgets.CreateButton(wizardInner, 'Re-run Setup Wizard', 'widget', 180, BUTTON_H)
		wizardY = placeWidget(wizardBtn, wizardInner, wizardY, BUTTON_H)

		wizardBtn:SetOnClick(function()
			if(F.Onboarding and F.Onboarding.ShowWizard) then
				F.Onboarding.ShowWizard()
			end
		end)

		yOffset = Widgets.EndCard(wizardCard, content, wizardY)

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
