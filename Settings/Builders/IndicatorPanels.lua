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
local BUTTON_H     = 24
local WIDGET_W     = 220
local PAD          = 16

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
-- Healer spell data
-- ============================================================
local HEALER_SPELLS = {
	DRUID   = { 774, 155777, 8936, 48438, 33763, 102342, 203651 },
	PALADIN = { 53563, 156910, 200025, 223306, 287280, 6940, 1022 },
	PRIEST  = { 139, 17, 41635, 194384, 33206, 47788, 21562 },
	SHAMAN  = { 61295, 73920, 77472, 974, 198838 },
	MONK    = { 119611, 116849, 124682, 116841, 191840 },
	EVOKER  = { 355941, 376788, 364343, 373861, 360823 },
}
local CLASS_ORDER = { 'DRUID', 'EVOKER', 'MONK', 'PALADIN', 'PRIEST', 'SHAMAN' }

-- ============================================================
-- Spell info helper
-- ============================================================
local function getSpellInfo(spellID)
	if(C_Spell and C_Spell.GetSpellInfo) then
		local info = C_Spell.GetSpellInfo(spellID)
		if(info) then return info.name, info.iconID end
	elseif(GetSpellInfo) then
		local name, _, icon = GetSpellInfo(spellID)
		if(name) then return name, icon end
	end
	return 'Spell ' .. spellID, nil
end

-- ============================================================
-- Import Popup (singleton)
-- ============================================================
local importPopup

local function BuildImportPopup()
	-- Dimmer
	local dimmer = CreateFrame('Frame', nil, UIParent)
	dimmer:SetAllPoints(UIParent)
	dimmer:SetFrameStrata('FULLSCREEN_DIALOG')
	dimmer:SetFrameLevel(1)
	local dimTex = dimmer:CreateTexture(nil, 'BACKGROUND')
	dimTex:SetAllPoints(dimmer)
	dimTex:SetColorTexture(0, 0, 0, 0.5)

	-- Dialog
	local frame = CreateFrame('Frame', nil, dimmer, 'BackdropTemplate')
	frame:SetFrameStrata('FULLSCREEN_DIALOG')
	frame:SetFrameLevel(10)
	Widgets.SetSize(frame, 420, 480)
	frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
	local bg = C.Colors.panel
	frame:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	frame:SetBackdropBorderColor(0, 0, 0, 1)

	-- Accent bar
	local accent = frame:CreateTexture(nil, 'OVERLAY')
	accent:SetHeight(1)
	accent:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
	accent:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
	local ac = C.Colors.accent
	accent:SetColorTexture(ac[1], ac[2], ac[3], ac[4] or 1)

	-- Title
	local title = Widgets.CreateFontString(frame, C.Font.sizeTitle, C.Colors.textActive)
	title:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, -PAD)
	title:SetText('Import Healer Spells')

	-- Select All / Deselect All
	local selAll = Widgets.CreateButton(frame, 'Select All', 'widget', 80, BUTTON_H)
	selAll:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -(PAD + 88), -PAD)
	local deselAll = Widgets.CreateButton(frame, 'Deselect All', 'widget', 80, BUTTON_H)
	deselAll:SetPoint('LEFT', selAll, 'RIGHT', C.Spacing.base, 0)

	-- Scroll area
	local scrollTop = -(PAD + 20 + C.Spacing.normal)
	local scrollH = 480 - 60 - BUTTON_H * 2 - PAD * 2 - C.Spacing.normal * 2
	local scroll = Widgets.CreateScrollFrame(frame, nil, 420 - PAD * 2, scrollH)
	scroll:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, scrollTop)
	local content = scroll:GetContentFrame()

	-- Build checkboxes
	frame.__checkboxes = {}
	local yOff = 0
	for _, cls in next, CLASS_ORDER do
		local spells = HEALER_SPELLS[cls]
		if(spells) then
			local hdr = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.accent)
			hdr:SetPoint('TOPLEFT', content, 'TOPLEFT', 0, yOff)
			hdr:SetJustifyH('LEFT')
			hdr:SetText(cls:sub(1, 1) .. cls:sub(2):lower())
			yOff = yOff - 18
			for _, spellID in next, spells do
				local spName, spIcon = getSpellInfo(spellID)
				local label = spName .. '  (' .. spellID .. ')'
				local cb = Widgets.CreateCheckButton(content, label, function() end)
				cb:SetChecked(true)
				cb:ClearAllPoints()
				Widgets.SetPoint(cb, 'TOPLEFT', content, 'TOPLEFT', 8, yOff)

				-- Insert spell icon between toggle track and label
				if(spIcon) then
					local iconSize = 14
					local icon = cb:CreateTexture(nil, 'ARTWORK')
					icon:SetSize(iconSize, iconSize)
					icon:SetTexture(spIcon)
					icon:SetPoint('LEFT', cb._track, 'RIGHT', 4, 0)
					-- Shift the label to the right of the icon
					cb._labelText:ClearAllPoints()
					Widgets.SetPoint(cb._labelText, 'LEFT', icon, 'RIGHT', 4, 0)
					-- Widen frame to account for icon
					cb:SetWidth(cb:GetWidth() + iconSize + 8)
				end

				yOff = yOff - CHECK_H
				frame.__checkboxes[#frame.__checkboxes + 1] = { checkbox = cb, spellID = spellID }
			end
			yOff = yOff - C.Spacing.tight
		end
	end
	content:SetHeight(math.abs(yOff))
	scroll:UpdateScrollRange()

	selAll:SetOnClick(function()
		for _, e in next, frame.__checkboxes do e.checkbox:SetChecked(true) end
	end)
	deselAll:SetOnClick(function()
		for _, e in next, frame.__checkboxes do e.checkbox:SetChecked(false) end
	end)

	-- Import / Cancel buttons
	local importBtn = Widgets.CreateButton(frame, 'Import Selected', 'accent', 140, BUTTON_H)
	importBtn:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -PAD, PAD)
	local cancelBtn = Widgets.CreateButton(frame, 'Cancel', 'widget', 80, BUTTON_H)
	cancelBtn:SetPoint('RIGHT', importBtn, 'LEFT', -C.Spacing.tight, 0)

	local function dismiss() frame:Hide(); dimmer:Hide() end
	cancelBtn:SetOnClick(dismiss)
	frame:EnableKeyboard(true)
	frame:SetPropagateKeyboardInput(false)
	frame:SetScript('OnKeyDown', function(_, key)
		if(key == 'ESCAPE') then dismiss() end
	end)
	frame:HookScript('OnHide', function() dimmer:Hide() end)

	frame.__importBtn = importBtn
	frame.__dimmer = dimmer
	frame.__dismiss = dismiss
	frame:Hide()
	dimmer:Hide()
	Widgets.AddToPixelUpdater_OnShow(frame)
	return frame
end

local function ShowImportPopup(onImport)
	if(not importPopup) then importPopup = BuildImportPopup() end
	for _, e in next, importPopup.__checkboxes do e.checkbox:SetChecked(true) end
	importPopup.__importBtn:SetOnClick(function()
		local selected = {}
		for _, e in next, importPopup.__checkboxes do
			if(e.checkbox:GetChecked()) then selected[#selected + 1] = e.spellID end
		end
		importPopup.__dismiss()
		if(onImport) then onImport(selected) end
	end)
	importPopup.__dimmer:Show()
	importPopup.__dimmer:SetAlpha(1)
	importPopup:Show()
	Widgets.FadeIn(importPopup, C.Animation.durationNormal)
end

-- ============================================================
-- Build type-specific indicator settings
-- ============================================================
function F.Settings.Builders.BuildIndicatorSettings(parent, width, yOffset, name, data, setIndicator, rebuildPanel)
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
	spList:SetOnChanged(function(spells)
		update('spells', spells)
		-- Sync spell colors when spells change
		if(spList._showColorPicker) then
			update('spellColors', spList:GetSpellColors())
		end
	end)

	-- Show per-spell color pickers for colored square and bars types
	if(data.displayType == C.IconDisplay.COLORED_SQUARE
		or data.type == C.IndicatorType.BAR
		or data.type == C.IndicatorType.BARS) then
		spList:SetSpellColors(data.spellColors or {})
		spList:SetShowColorPicker(true)
	end

	local spInput = Widgets.CreateSpellInput(spInner, width - 24)
	spY = placeWidget(spInput, spInner, spY, 50)
	spInput:SetSpellList(spList)
	spInput:SetOnAdd(function() update('spells', spList:GetSpells()) end)

	local importBtn = Widgets.CreateButton(spInner, 'Import Healer Spells', 'widget', 160, 24)
	spY = placeWidget(importBtn, spInner, spY, 24)
	importBtn:SetOnClick(function()
		ShowImportPopup(function(selectedSpells)
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
		-- Appearance card
		yOffset = placeHeading(parent, 'Appearance', 2, yOffset)
		local appCard, appInner, appY = Widgets.StartCard(parent, width, yOffset)

		local dtLabel = Widgets.CreateFontString(appInner, C.Font.sizeSmall, C.Colors.textSecondary)
		dtLabel:SetText('Display Type')
		appY = placeWidget(dtLabel, appInner, appY, C.Font.sizeSmall)

		local dtSwitch = Widgets.CreateSwitch(appInner, WIDGET_W, BUTTON_H, {
			{ text = 'Spell Icons',    value = C.IconDisplay.SPELL_ICON },
			{ text = 'Color Squares',  value = C.IconDisplay.COLORED_SQUARE },
		})
		dtSwitch:SetValue(data.displayType or C.IconDisplay.SPELL_ICON)
		dtSwitch:SetOnSelect(function(v)
			update('displayType', v)
			if(v == C.IconDisplay.COLORED_SQUARE) then
				spList:SetSpellColors(data.spellColors or {})
				spList:SetShowColorPicker(true)
			else
				spList:SetShowColorPicker(false)
			end
		end)
		appY = placeWidget(dtSwitch, appInner, appY, BUTTON_H)

		local wSlider = Widgets.CreateSlider(appInner, 'Width', WIDGET_W, 8, 48, 1)
		wSlider:SetValue(data.iconWidth or 16)
		wSlider:SetAfterValueChanged(function(v) update('iconWidth', v) end)
		appY = placeWidget(wSlider, appInner, appY, SLIDER_H)

		local hSlider = Widgets.CreateSlider(appInner, 'Height', WIDGET_W, 8, 48, 1)
		hSlider:SetValue(data.iconHeight or 16)
		hSlider:SetAfterValueChanged(function(v) update('iconHeight', v) end)
		appY = placeWidget(hSlider, appInner, appY, SLIDER_H)

		yOffset = Widgets.EndCard(appCard, parent, appY)

		-- Layout card (Icons only)
		if(iType == C.IndicatorType.ICONS) then
			yOffset = placeHeading(parent, 'Layout', 2, yOffset)
			local layCard, layInner, layY = Widgets.StartCard(parent, width, yOffset)

			-- Anchor picker
			if(Widgets.CreateAnchorPicker) then
				local anchor = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
				local picker = Widgets.CreateAnchorPicker(layInner, WIDGET_W, 50)
				picker:SetAnchor(anchor[1] or 'CENTER', anchor[4] or 0, anchor[5] or 0)
				picker:SetOnChanged(function(point, x, y)
					local a = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
					a[1] = point
					a[3] = point
					a[4] = x
					a[5] = y
					set('anchor', a)
				end)
				layY = placeWidget(picker, layInner, layY, picker._height or 91)
			end

			-- Frame level
			local flSlider = Widgets.CreateSlider(layInner, 'Frame Level', WIDGET_W, 1, 50, 1)
			flSlider:SetValue(get('frameLevel') or 5)
			flSlider:SetAfterValueChanged(function(val)
				set('frameLevel', val)
			end)
			layY = placeWidget(flSlider, layInner, layY, SLIDER_H)

			-- Grow direction — default is derived from anchor when not explicitly set
			local anchorData = data.anchor or { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 }
			local anchorH = anchorData[3] or 'TOPLEFT'
			local defaultGrow = (anchorH == 'TOPRIGHT' or anchorH == 'RIGHT' or anchorH == 'BOTTOMRIGHT') and 'LEFT' or 'RIGHT'
			local effectiveGrow = data.orientation or defaultGrow

			local growLabel = Widgets.CreateFontString(layInner, C.Font.sizeSmall, C.Colors.textSecondary)
			growLabel:SetText('Grow Direction')
			layY = placeWidget(growLabel, layInner, layY, C.Font.sizeSmall)

			local oriDD = Widgets.CreateDropdown(layInner, WIDGET_W)
			oriDD:SetItems(ORIENTATION_ITEMS)
			oriDD:SetValue(effectiveGrow)
			oriDD:SetOnSelect(function(v) update('orientation', v) end)
			layY = placeWidget(oriDD, layInner, layY, DROPDOWN_H)

			local mxSlider = Widgets.CreateSlider(layInner, 'Max Displayed', WIDGET_W, 1, 10, 1)
			mxSlider:SetValue(data.maxDisplayed or 3)
			mxSlider:SetAfterValueChanged(function(v) update('maxDisplayed', v) end)
			layY = placeWidget(mxSlider, layInner, layY, SLIDER_H)

			local nplSlider = Widgets.CreateSlider(layInner, 'Num Per Line', WIDGET_W, 0, 10, 1)
			nplSlider:SetValue(data.numPerLine or 0)
			nplSlider:SetAfterValueChanged(function(v) update('numPerLine', v) end)
			layY = placeWidget(nplSlider, layInner, layY, SLIDER_H)

			local spxSlider = Widgets.CreateSlider(layInner, 'Spacing X', WIDGET_W, -20, 20, 1)
			spxSlider:SetValue(data.spacingX or 2)
			spxSlider:SetAfterValueChanged(function(v) update('spacingX', v) end)
			layY = placeWidget(spxSlider, layInner, layY, SLIDER_H)

			local spySlider = Widgets.CreateSlider(layInner, 'Spacing Y', WIDGET_W, -20, 20, 1)
			spySlider:SetValue(data.spacingY or 2)
			spySlider:SetAfterValueChanged(function(v) update('spacingY', v) end)
			layY = placeWidget(spySlider, layInner, layY, SLIDER_H)

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

		local durModeLabel = Widgets.CreateFontString(cdInner, C.Font.sizeSmall, C.Colors.textSecondary)
		durModeLabel:SetText('Duration Text')
		cdY = placeWidget(durModeLabel, cdInner, cdY, C.Font.sizeSmall)

		local durDD = Widgets.CreateDropdown(cdInner, WIDGET_W)
		durDD:SetItems(DURATION_MODE_ITEMS)
		durDD:SetValue(data.durationMode or 'Never')
		durDD:SetOnSelect(function(v) update('durationMode', v) end)
		cdY = placeWidget(durDD, cdInner, cdY, DROPDOWN_H)

		-- Duration font settings (always shown — reflow deferred to grid rework)
		local fontCfg = get('durationFont') or {}

		if(Widgets.CreateAnchorPicker) then
			local dfAnchor = fontCfg.anchor or 'BOTTOM'
			local dfPicker = Widgets.CreateAnchorPicker(cdInner, WIDGET_W, 15)
			dfPicker:SetAnchor(dfAnchor, fontCfg.offsetX or 0, fontCfg.offsetY or 0)
			dfPicker:SetOnChanged(function(point, x, y)
				fontCfg.anchor = point
				fontCfg.offsetX = x
				fontCfg.offsetY = y
				set('durationFont', fontCfg)
			end)
			cdY = placeWidget(dfPicker, cdInner, cdY, dfPicker._height or 91)
		end

		local dfSizeSlider = Widgets.CreateSlider(cdInner, 'Font Size', WIDGET_W, 6, 24, 1)
		dfSizeSlider:SetValue(fontCfg.size or C.Font.sizeSmall)
		dfSizeSlider:SetAfterValueChanged(function(val)
			fontCfg.size = val
			set('durationFont', fontCfg)
		end)
		cdY = placeWidget(dfSizeSlider, cdInner, cdY, SLIDER_H)

		local dfOutlineDD = Widgets.CreateDropdown(cdInner, WIDGET_W)
		dfOutlineDD:SetItems({
			{ text = 'None',    value = '' },
			{ text = 'Outline', value = 'OUTLINE' },
			{ text = 'Mono',    value = 'MONOCHROME' },
		})
		dfOutlineDD:SetValue(fontCfg.outline or '')
		dfOutlineDD:SetOnSelect(function(value)
			fontCfg.outline = value
			set('durationFont', fontCfg)
		end)
		cdY = placeWidget(dfOutlineDD, cdInner, cdY, DROPDOWN_H)

		local dfShadowCB = Widgets.CreateCheckButton(cdInner, 'Shadow', function(checked)
			fontCfg.shadow = checked
			set('durationFont', fontCfg)
		end)
		dfShadowCB:SetChecked(fontCfg.shadow or false)
		cdY = placeWidget(dfShadowCB, cdInner, cdY, CHECK_H)

		local cpCB = Widgets.CreateCheckButton(cdInner, 'Color Progression', function(checked)
			fontCfg.colorProgression = checked
			set('durationFont', fontCfg)
		end)
		cpCB:SetChecked(fontCfg.colorProgression or false)
		cdY = placeWidget(cpCB, cdInner, cdY, CHECK_H)

		local startC = fontCfg.progressionStart or { 0, 1, 0 }
		local startPicker = Widgets.CreateColorPicker(cdInner, 'Full Duration', false, function(r, g, b)
			fontCfg.progressionStart = { r, g, b }
			set('durationFont', fontCfg)
		end)
		startPicker:SetColor(startC[1], startC[2], startC[3], 1)
		cdY = placeWidget(startPicker, cdInner, cdY, DROPDOWN_H)

		local midC = fontCfg.progressionMid or { 1, 1, 0 }
		local midPicker = Widgets.CreateColorPicker(cdInner, 'Half Duration', false, function(r, g, b)
			fontCfg.progressionMid = { r, g, b }
			set('durationFont', fontCfg)
		end)
		midPicker:SetColor(midC[1], midC[2], midC[3], 1)
		cdY = placeWidget(midPicker, cdInner, cdY, DROPDOWN_H)

		local endC = fontCfg.progressionEnd or { 1, 0, 0 }
		local endPicker = Widgets.CreateColorPicker(cdInner, 'Near Expiry', false, function(r, g, b)
			fontCfg.progressionEnd = { r, g, b }
			set('durationFont', fontCfg)
		end)
		endPicker:SetColor(endC[1], endC[2], endC[3], 1)
		cdY = placeWidget(endPicker, cdInner, cdY, DROPDOWN_H)

		yOffset = Widgets.EndCard(cdCard, parent, cdY)

		-- Stack card
		yOffset = placeHeading(parent, 'Stacks', 2, yOffset)
		local stCard, stInner, stY = Widgets.StartCard(parent, width, yOffset)

		local stSwitch = Widgets.CreateCheckButton(stInner, 'Show Stacks', function(checked)
			update('showStacks', checked)
		end)
		stSwitch:SetChecked(data.showStacks == true)
		stY = placeWidget(stSwitch, stInner, stY, CHECK_H)

		-- Stack font settings (always shown — reflow deferred to grid rework)
		local sfCfg = get('stackFont') or {}

		if(Widgets.CreateAnchorPicker) then
			local sfAnchor = sfCfg.anchor or 'BOTTOMRIGHT'
			local sfPicker = Widgets.CreateAnchorPicker(stInner, WIDGET_W, 15)
			sfPicker:SetAnchor(sfAnchor, sfCfg.offsetX or 0, sfCfg.offsetY or 0)
			sfPicker:SetOnChanged(function(point, x, y)
				sfCfg.anchor = point
				sfCfg.offsetX = x
				sfCfg.offsetY = y
				set('stackFont', sfCfg)
			end)
			stY = placeWidget(sfPicker, stInner, stY, sfPicker._height or 91)
		end

		local sfSizeSlider = Widgets.CreateSlider(stInner, 'Font Size', WIDGET_W, 6, 24, 1)
		sfSizeSlider:SetValue(sfCfg.size or C.Font.sizeSmall)
		sfSizeSlider:SetAfterValueChanged(function(val)
			sfCfg.size = val
			set('stackFont', sfCfg)
		end)
		stY = placeWidget(sfSizeSlider, stInner, stY, SLIDER_H)

		local sfOutlineDD = Widgets.CreateDropdown(stInner, WIDGET_W)
		sfOutlineDD:SetItems({
			{ text = 'None',    value = '' },
			{ text = 'Outline', value = 'OUTLINE' },
			{ text = 'Mono',    value = 'MONOCHROME' },
		})
		sfOutlineDD:SetValue(sfCfg.outline or '')
		sfOutlineDD:SetOnSelect(function(value)
			sfCfg.outline = value
			set('stackFont', sfCfg)
		end)
		stY = placeWidget(sfOutlineDD, stInner, stY, DROPDOWN_H)

		local sfShadowCB = Widgets.CreateCheckButton(stInner, 'Shadow', function(checked)
			sfCfg.shadow = checked
			set('stackFont', sfCfg)
		end)
		sfShadowCB:SetChecked(sfCfg.shadow or false)
		stY = placeWidget(sfShadowCB, stInner, stY, CHECK_H)

		yOffset = Widgets.EndCard(stCard, parent, stY)

		-- Glow card
		yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = true })

		-- Position card (single Icon only — Icons has position in Layout card)
		if(iType == C.IndicatorType.ICON) then
			yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set)
		end

	elseif(iType == C.IndicatorType.BAR or iType == C.IndicatorType.BARS) then
		-- Size card
		yOffset = placeHeading(parent, 'Size', 2, yOffset)
		local szCard, szInner, szY = Widgets.StartCard(parent, width, yOffset)

		local bwSlider = Widgets.CreateSlider(szInner, 'Width', WIDGET_W, 3, 100, 1)
		bwSlider:SetValue(data.barWidth or 100)
		bwSlider:SetAfterValueChanged(function(v) update('barWidth', v) end)
		szY = placeWidget(bwSlider, szInner, szY, SLIDER_H)

		local bhSlider = Widgets.CreateSlider(szInner, 'Height', WIDGET_W, 3, 100, 1)
		bhSlider:SetValue(data.barHeight or 4)
		bhSlider:SetAfterValueChanged(function(v) update('barHeight', v) end)
		szY = placeWidget(bhSlider, szInner, szY, SLIDER_H)

		local barOriDD = Widgets.CreateDropdown(szInner, WIDGET_W)
		barOriDD:SetItems(BAR_ORIENTATION_ITEMS)
		barOriDD:SetValue(data.barOrientation or 'Horizontal')
		barOriDD:SetOnSelect(function(v) update('barOrientation', v) end)
		szY = placeWidget(barOriDD, szInner, szY, DROPDOWN_H)

		yOffset = Widgets.EndCard(szCard, parent, szY)

		-- Layout card
		yOffset = placeHeading(parent, 'Layout', 2, yOffset)
		local layCard, layInner, layY = Widgets.StartCard(parent, width, yOffset)

		if(iType == C.IndicatorType.BARS) then
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
		end

		-- Position (anchor picker)
		if(Widgets.CreateAnchorPicker) then
			local anchor = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
			local picker = Widgets.CreateAnchorPicker(layInner, WIDGET_W, 50)
			picker:SetAnchor(anchor[1] or 'CENTER', anchor[4] or 0, anchor[5] or 0)
			picker:SetOnChanged(function(point, x, y)
				local a = get('anchor') or { 'CENTER', nil, 'CENTER', 0, 0 }
				a[1] = point
				a[3] = point
				a[4] = x
				a[5] = y
				set('anchor', a)
			end)
			layY = placeWidget(picker, layInner, layY, picker._height or 91)
		end

		-- Frame level
		local flSlider = Widgets.CreateSlider(layInner, 'Frame Level', WIDGET_W, 1, 50, 1)
		flSlider:SetValue(get('frameLevel') or 5)
		flSlider:SetAfterValueChanged(function(val)
			set('frameLevel', val)
		end)
		layY = placeWidget(flSlider, layInner, layY, SLIDER_H)

		yOffset = Widgets.EndCard(layCard, parent, layY)

		-- Threshold color card (hide base color — set via per-spell color pickers)
		yOffset = F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set, { showBorderColor = true, showBgColor = true, hideBaseColor = true })

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

		-- Glow
		yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = true })

	elseif(iType == C.IndicatorType.RECTANGLE) then
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
		yOffset = placeHeading(parent, 'Mode', 2, yOffset)
		local modeCard, modeInner, modeY = Widgets.StartCard(parent, width, yOffset)

		local modeDD = Widgets.CreateDropdown(modeInner, WIDGET_W)
		modeDD:SetItems({
			{ text = 'Duration Overlay', value = 'DurationOverlay' },
			{ text = 'Color',            value = 'Color' },
			{ text = 'Both',             value = 'Both' },
		})
		modeDD:SetValue(data.overlayMode or 'DurationOverlay')
		modeDD:SetOnSelect(function(v) update('overlayMode', v) end)
		modeY = placeWidget(modeDD, modeInner, modeY, DROPDOWN_H)

		local ovColor = data.color or { 0, 0, 0, 0.6 }
		local colorPicker = Widgets.CreateColorPicker(modeInner, 'Color', true, function(r, g, b, a)
			update('color', { r, g, b, a })
		end)
		colorPicker:SetColor(ovColor[1], ovColor[2], ovColor[3], ovColor[4] or 1)
		modeY = placeWidget(colorPicker, modeInner, modeY, DROPDOWN_H)

		yOffset = Widgets.EndCard(modeCard, parent, modeY)

		-- Conditional: DurationOverlay or Both — threshold colors + smooth + bar orientation
		local ovMode = data.overlayMode or 'DurationOverlay'
		if(ovMode == 'DurationOverlay' or ovMode == 'Both') then
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
		-- Mode switch: Border / Glow
		yOffset = placeHeading(parent, 'Mode', 2, yOffset)
		local modeCard, modeInner, modeY = Widgets.StartCard(parent, width, yOffset)

		local modeSwitch = Widgets.CreateSwitch(modeInner, WIDGET_W, BUTTON_H, {
			{ text = 'Border', value = 'Border' },
			{ text = 'Glow',   value = 'Glow' },
		})
		modeSwitch:SetValue(data.borderGlowMode or 'Border')
		modeSwitch:SetOnSelect(function(v)
			update('borderGlowMode', v)
			if(rebuildPanel) then rebuildPanel() end
		end)
		modeY = placeWidget(modeSwitch, modeInner, modeY, BUTTON_H)

		yOffset = Widgets.EndCard(modeCard, parent, modeY)

		local bgMode = data.borderGlowMode or 'Border'

		if(bgMode == 'Border') then
			-- Border settings card
			yOffset = placeHeading(parent, 'Border Settings', 2, yOffset)
			local borCard, borInner, borY = Widgets.StartCard(parent, width, yOffset)

			local thkSlider = Widgets.CreateSlider(borInner, 'Thickness', WIDGET_W, 1, 15, 1)
			thkSlider:SetValue(data.borderThickness or 2)
			thkSlider:SetAfterValueChanged(function(v) update('borderThickness', v) end)
			borY = placeWidget(thkSlider, borInner, borY, SLIDER_H)

			local borColor = data.color or { 1, 1, 1, 1 }
			local borColorPicker = Widgets.CreateColorPicker(borInner, 'Color', true, function(r, g, b, a)
				update('color', { r, g, b, a })
			end)
			borColorPicker:SetColor(borColor[1], borColor[2], borColor[3], borColor[4] or 1)
			borY = placeWidget(borColorPicker, borInner, borY, DROPDOWN_H)

			local borFade = Widgets.CreateCheckButton(borInner, 'Fade Out', function(checked)
				update('fadeOut', checked)
			end)
			borFade:SetChecked(data.fadeOut == true)
			borY = placeWidget(borFade, borInner, borY, CHECK_H)

			yOffset = Widgets.EndCard(borCard, parent, borY)

		elseif(bgMode == 'Glow') then
			-- Glow settings card
			yOffset = placeHeading(parent, 'Glow Settings', 2, yOffset)
			local glowCard, glowInner, glowY = Widgets.StartCard(parent, width, yOffset)

			local glowFade = Widgets.CreateCheckButton(glowInner, 'Fade Out', function(checked)
				update('fadeOut', checked)
			end)
			glowFade:SetChecked(data.fadeOut == true)
			glowY = placeWidget(glowFade, glowInner, glowY, CHECK_H)

			yOffset = Widgets.EndCard(glowCard, parent, glowY)

			-- Glow type + color (frame-level glows only — Pixel and Shine)
			yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = false, frameGlowOnly = true })
		end

		-- Position (frame level only)
		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set, { hidePosition = true })

	end

	return yOffset
end
