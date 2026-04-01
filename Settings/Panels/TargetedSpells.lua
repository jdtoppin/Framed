local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Widget constants
-- ============================================================

local SLIDER_H     = 26
local DROPDOWN_H   = 22
local CHECK_H      = 22
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
	order      = 17,
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

		-- Show Duration
		local durCheck = Widgets.CreateCheckButton(iconInner, 'Show Duration', function(checked) set('showDuration', checked) end)
		durCheck:SetChecked(get('showDuration') ~= false)
		durCheck:ClearAllPoints()
		Widgets.SetPoint(durCheck, 'TOPLEFT', iconInner, 'TOPLEFT', 0, iconCardY)
		iconCardY = iconCardY - CHECK_H - C.Spacing.normal

		yOffset = Widgets.EndCard(iconCard, content, iconCardY)

		-- ── Duration Font ──────────────────────────────────────
		local fontChildrenBefore = { content:GetChildren() }
		local fontChildCountBefore = #fontChildrenBefore
		yOffset = F.Settings.BuildFontCard(content, width, yOffset, 'Duration Text Font', 'durationFont', get, set)
		local durationFontCards = {}
		local fontChildrenAfter = { content:GetChildren() }
		for i = fontChildCountBefore + 1, #fontChildrenAfter do
			durationFontCards[#durationFontCards + 1] = fontChildrenAfter[i]
		end

		-- ── Border Glow Settings (shown for BorderGlow or Both) ─
		local glowHeading, glowHeadingH = Widgets.CreateHeading(content, 'Border Glow Settings', 2)
		glowHeading:ClearAllPoints()
		Widgets.SetPoint(glowHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - glowHeadingH

		local function getGlow(key)
			if(key == 'glowType') then return get('glow.type') end
			if(key == 'glowColor') then return get('glow.color') end
			return get('glow.' .. key)
		end
		local function setGlow(key, value)
			if(key == 'glowType') then set('glow.type', value); return end
			if(key == 'glowColor') then set('glow.color', value); return end
			set('glow.' .. key, value)
		end

		-- Capture child count before building glow card so we can find the new card frame
		local childrenBefore = { content:GetChildren() }
		local childCountBefore = #childrenBefore

		yOffset = F.Settings.BuildGlowCard(content, width, yOffset, getGlow, setGlow, { allowNone = false })

		-- Find the card frame(s) added by BuildGlowCard
		local glowCards = {}
		local childrenAfter = { content:GetChildren() }
		for i = childCountBefore + 1, #childrenAfter do
			glowCards[#glowCards + 1] = childrenAfter[i]
		end

		-- ── Display mode visibility ─────────────────────────────
		local iconWidgets = { iconHeading, sizeSlider, maxSlider, iconLvlSlider, durCheck }
		if(iconAnchorPicker) then iconWidgets[#iconWidgets + 1] = iconAnchorPicker end

		local function updatePaneVisibility(mode)
			local showIcons = (mode == 'Icons' or mode == 'Both')
			local showGlow  = (mode == 'BorderGlow' or mode == 'Both')
			for _, w in next, iconWidgets do w:SetShown(showIcons) end
			for _, card in next, durationFontCards do card:SetShown(showIcons) end
			glowHeading:SetShown(showGlow)
			for _, card in next, glowCards do card:SetShown(showGlow) end
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
