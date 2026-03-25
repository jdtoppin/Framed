local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Widget heights (for vertical layout accounting)
-- ============================================================

local SLIDER_H     = 26
local DROPDOWN_H   = 22
local SWATCH_H     = 20
local PANE_TITLE_H = 20
local BUTTON_H     = 28
local WIDGET_W     = 220

-- ============================================================
-- Section helpers (mirrors FrameSettingsBuilder pattern)
-- ============================================================

local function createSection(content, title, width, yOffset)
	local pane = Widgets.CreateTitledPane(content, title, width)
	pane:ClearAllPoints()
	Widgets.SetPoint(pane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return pane, yOffset - PANE_TITLE_H - C.Spacing.normal
end

local function placeWidget(widget, pane, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', pane, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'appearance',
	label   = 'Appearance',
	section = 'GENERAL',
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
		local pad     = C.Spacing.normal

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

		-- ── Accent Color ───────────────────────────────────────
		local colorPane
		colorPane, yOffset = createSection(content, 'Accent Color', width, yOffset)

		local colorPicker = Widgets.CreateColorPicker(content)
		colorPicker:ClearAllPoints()
		Widgets.SetPoint(colorPicker, 'TOPLEFT', colorPane, 'TOPLEFT', 0, yOffset)

		-- Initialise from config
		local savedColor = getConfig('accentColor')
		if(savedColor) then
			colorPicker:SetColor(savedColor[1], savedColor[2], savedColor[3], savedColor[4] or 1)
		else
			colorPicker:SetColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
		end

		colorPicker:SetOnColorChanged(function(r, g, b, a)
			-- Update runtime accent color tables
			C.Colors.accent      = { r, g, b, a }
			C.Colors.accentDim   = { r, g, b, 0.3 }
			C.Colors.accentHover = { r, g, b, 0.6 }
			setConfig('accentColor', { r, g, b, a })
			fireChange()
		end)

		yOffset = yOffset - SWATCH_H - C.Spacing.normal

		-- ── UI Scale ───────────────────────────────────────────
		local scalePane
		scalePane, yOffset = createSection(content, 'UI Scale', width, yOffset)

		local scaleSlider = Widgets.CreateSlider(content, 'UI Scale', WIDGET_W, 0.5, 2.0, 0.1)
		yOffset = placeWidget(scaleSlider, scalePane, yOffset, SLIDER_H)

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

		-- ── Font ───────────────────────────────────────────────
		local fontPane
		fontPane, yOffset = createSection(content, 'Font', width, yOffset)

		local fontDropdown = Widgets.CreateTextureDropdown(content, WIDGET_W, 'font')
		yOffset = placeWidget(fontDropdown, fontPane, yOffset, DROPDOWN_H)

		local savedFont = getConfig('font')
		if(savedFont) then
			fontDropdown:SetValue(savedFont)
		end

		fontDropdown:SetOnSelect(function(texturePath, name)
			setConfig('font', name)
			fireChange()
		end)

		-- ── Bar Texture ────────────────────────────────────────
		local barPane
		barPane, yOffset = createSection(content, 'Bar Texture', width, yOffset)

		local barDropdown = Widgets.CreateTextureDropdown(content, WIDGET_W, 'statusbar')
		yOffset = placeWidget(barDropdown, barPane, yOffset, DROPDOWN_H)

		local savedBar = getConfig('barTexture')
		if(savedBar) then
			barDropdown:SetValue(savedBar)
		end

		barDropdown:SetOnSelect(function(texturePath, name)
			setConfig('barTexture', name)
			fireChange()
		end)

		-- ── Re-run Setup Wizard ────────────────────────────────
		local wizardPane
		wizardPane, yOffset = createSection(content, 'Setup Wizard', width, yOffset)

		local wizardBtn = Widgets.CreateButton(content, 'Re-run Setup Wizard', 'widget', 180, BUTTON_H)
		yOffset = placeWidget(wizardBtn, wizardPane, yOffset, BUTTON_H)

		wizardBtn:SetOnClick(function()
			if(F.SetupWizard and F.SetupWizard.Show) then
				F.SetupWizard.Show()
			end
		end)

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
