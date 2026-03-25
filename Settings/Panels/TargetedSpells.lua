local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================

local PANE_TITLE_H = 20
local SLIDER_H     = 26
local DROPDOWN_H   = 22
local WIDGET_W     = 220

-- ============================================================
-- Config helpers
-- ============================================================

local function get(key)
	local layoutName = F.Settings.GetEditingLayout()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return F.Config and F.Config:Get('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.targetedSpells.' .. key)
end

local function set(key, value)
	local layoutName = F.Settings.GetEditingLayout()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.targetedSpells.' .. key, value)
	end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.targetedSpells')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'targetedspells',
	label   = 'Targeted Spells',
	section = 'AURAS',
	order   = 14,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll  = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ── Description ────────────────────────────────────────
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('Highlight units that are casting targeted spells at the group. Supports icon display, border glow, or both.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- ── Display Mode ───────────────────────────────────────
		local modePane = Widgets.CreateTitledPane(content, 'Display Mode', width)
		modePane:ClearAllPoints()
		Widgets.SetPoint(modePane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

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
		local iconPane = Widgets.CreateTitledPane(content, 'Icon Settings', width)
		iconPane:ClearAllPoints()
		Widgets.SetPoint(iconPane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

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
		local glowPane = Widgets.CreateTitledPane(content, 'Border Glow Settings', width)
		glowPane:ClearAllPoints()
		Widgets.SetPoint(glowPane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

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

		yOffset = Widgets.EndCard(glowCard, content, glowCardY)

		-- ── Display mode visibility ─────────────────────────────
		local iconWidgets = { iconPane, sizeSlider, maxSlider, iconLvlSlider }
		if(iconAnchorPicker) then iconWidgets[#iconWidgets + 1] = iconAnchorPicker end

		local glowWidgets = { glowPane, glowDD }
		if(glowColorPicker) then glowWidgets[#glowWidgets + 1] = glowColorPicker end

		local function updatePaneVisibility(mode)
			local showIcons = (mode == 'Icons' or mode == 'Both')
			local showGlow  = (mode == 'BorderGlow' or mode == 'Both')
			for _, w in next, iconWidgets do w:SetShown(showIcons) end
			for _, w in next, glowWidgets  do w:SetShown(showGlow)  end
		end

		updatePaneVisibility(get('displayMode') or 'Both')

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
