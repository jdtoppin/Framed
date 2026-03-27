local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings = F.Settings or {}
F.Settings.Builders = F.Settings.Builders or {}

-- ============================================================
-- Layout constants
-- ============================================================
local SLIDER_H     = 26
local CHECK_H      = 22
local DROPDOWN_H   = 22
local BUTTON_H     = 24
local ROW_HEIGHT   = 28
local LIST_HEIGHT  = 160
local WIDGET_W     = 220
local PAD          = 16
local PAD_H        = 6

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
-- Config helpers
-- ============================================================
local function makeConfigHelpers(unitType, configKey)
	local function basePath()
		local presetName = F.Settings.GetEditingPreset()
		return 'presets.' .. presetName .. '.auras.' .. unitType .. '.' .. configKey .. '.indicators'
	end

	local function getIndicators()
		if(not F.Config) then return {} end
		return F.Config:Get(basePath()) or {}
	end

	local function fireChange()
		if(not F.EventBus) then return end
		local presetName = F.Settings.GetEditingPreset()
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.' .. configKey)
	end

	local function setIndicator(name, data)
		if(not F.Config) then return end
		local presetName = F.Settings.GetEditingPreset()
		F.Config:Set(basePath() .. '.' .. name, data)
		F.PresetManager.MarkCustomized(presetName)
		fireChange()
	end

	local function removeIndicator(name)
		if(not F.Config) then return end
		local presetName = F.Settings.GetEditingPreset()
		F.Config:Set(basePath() .. '.' .. name, nil)
		F.PresetManager.MarkCustomized(presetName)
		fireChange()
	end

	return getIndicators, setIndicator, removeIndicator
end

-- ============================================================
-- Spell name helper
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

local function getSpellName(spellID)
	local name = getSpellInfo(spellID)
	return name
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
-- Indicator type dropdown items
-- ============================================================
local function getTypeItems()
	return {
		{ text = 'Icons',     value = C.IndicatorType.ICONS },
		{ text = 'Icon',      value = C.IndicatorType.ICON },
		{ text = 'Bars',      value = C.IndicatorType.BARS },
		{ text = 'Bar',       value = C.IndicatorType.BAR },
		{ text = 'Frame Bar', value = C.IndicatorType.FRAME_BAR },
		{ text = 'Border',    value = C.IndicatorType.BORDER },
		{ text = 'Color',     value = C.IndicatorType.COLOR },
		{ text = 'Overlay',   value = C.IndicatorType.OVERLAY },
		{ text = 'Glow',      value = C.IndicatorType.GLOW },
	}
end

-- ============================================================
-- Type descriptions for Create card
-- ============================================================
local TYPE_DESCRIPTIONS = {
	Icon    = 'Single spell icon or colored square',
	Icons   = 'Row/grid of spell icons or colored squares',
	Bar     = 'Single depleting status bar',
	Bars    = 'Row/grid of depleting status bars',
	Color   = 'Colored rectangle positioned on frame',
	Overlay = 'Health bar overlay — depleting, static fill, or both',
	Border  = 'Colored border around the frame edge',
	Glow    = 'Glow effect around the frame',
	FrameBar = 'Full-frame status bar overlay',
}

-- ============================================================
-- List row creation
-- ============================================================
local function createListRow(scrollContent)
	local row = CreateFrame('Frame', nil, scrollContent, 'BackdropTemplate')
	Widgets.ApplyBackdrop(row, C.Colors.widget, C.Colors.border)
	row:SetHeight(ROW_HEIGHT)

	local nameFS = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textActive)
	nameFS:SetPoint('LEFT', row, 'LEFT', PAD_H, 0)
	nameFS:SetJustifyH('LEFT')
	nameFS:SetWidth(100)
	row.__nameFS = nameFS

	-- "Editing: name" overlay — wrapper frame for fade animation
	local editingWrap = CreateFrame('Frame', nil, row)
	editingWrap:SetPoint('LEFT', row, 'LEFT', PAD_H, 0)
	editingWrap:SetSize(160, ROW_HEIGHT)
	editingWrap:Hide()
	row.__editingWrap = editingWrap

	local editingFS = Widgets.CreateFontString(editingWrap, C.Font.sizeNormal, { 0.3, 0.9, 0.3, 1 })
	editingFS:SetPoint('LEFT', editingWrap, 'LEFT', 0, 0)
	editingFS:SetJustifyH('LEFT')
	editingFS:SetWidth(160)
	row.__editingFS = editingFS

	local typeFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
	typeFS:SetJustifyH('LEFT')
	row.__typeFS = typeFS

	-- Enabled toggle — callback is updated dynamically via row.__onEnabledChanged
	row.__onEnabledChanged = nil
	local enabledCB = Widgets.CreateCheckButton(row, '', function(checked)
		if(row.__onEnabledChanged) then row.__onEnabledChanged(checked) end
	end)
	enabledCB:SetWidgetTooltip('Enable / Disable')
	row.__enabledCB = enabledCB

	local editBtn = Widgets.CreateButton(row, 'Edit', 'widget', 40, 20)
	row.__editBtn = editBtn
	local deleteBtn = Widgets.CreateButton(row, 'Delete', 'red', 50, 20)
	row.__deleteBtn = deleteBtn

	-- Anchoring: [name] [type] ... [enabled] [delete] [edit]
	editBtn:SetPoint('RIGHT', row, 'RIGHT', -PAD_H, 0)
	deleteBtn:SetPoint('RIGHT', editBtn, 'LEFT', -C.Spacing.base, 0)
	enabledCB:ClearAllPoints()
	Widgets.SetPoint(enabledCB, 'RIGHT', deleteBtn, 'LEFT', -C.Spacing.base, 0)
	typeFS:SetPoint('RIGHT', enabledCB, 'LEFT', -C.Spacing.tight, 0)

	-- Row highlight: persist when hovering child buttons
	row:EnableMouse(true)
	row:SetScript('OnEnter', function(self) Widgets.SetBackdropHighlight(self, true) end)
	row:SetScript('OnLeave', function(self)
		if(self:IsMouseOver()) then return end
		Widgets.SetBackdropHighlight(self, false)
	end)

	-- Propagate row highlight from child interactive widgets
	for _, child in next, { editBtn, deleteBtn, enabledCB } do
		child:HookScript('OnEnter', function() Widgets.SetBackdropHighlight(row, true) end)
		child:HookScript('OnLeave', function()
			if(row:IsMouseOver()) then return end
			Widgets.SetBackdropHighlight(row, false)
		end)
	end

	return row
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
-- Build type-specific indicator settings
-- ============================================================
local function buildIndicatorSettings(parent, width, yOffset, name, data, setIndicator)
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
	spList:SetOnChanged(function(spells) update('spells', spells) end)

	local spInput = Widgets.CreateSpellInput(spInner, width - 24)
	spY = placeWidget(spInput, spInner, spY, 50)
	spInput:SetSpellList(spList)
	spInput:SetOnAdd(function() update('spells', spList:GetSpells()) end)

	local importBtn = Widgets.CreateButton(spInner, 'Import Healer Spells', 'widget', 160, BUTTON_H)
	spY = placeWidget(importBtn, spInner, spY, BUTTON_H)
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

	local deleteAllBtn = Widgets.CreateButton(spInner, 'Delete All Spells', 'red', 140, BUTTON_H)
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
		-- Size card
		yOffset = placeHeading(parent, 'Size', 2, yOffset)
		local szCard, szInner, szY = Widgets.StartCard(parent, width, yOffset)

		local wSlider = Widgets.CreateSlider(szInner, 'Width', WIDGET_W, 8, 48, 1)
		wSlider:SetValue(data.iconWidth or 16)
		wSlider:SetAfterValueChanged(function(v) update('iconWidth', v) end)
		szY = placeWidget(wSlider, szInner, szY, SLIDER_H)

		local hSlider = Widgets.CreateSlider(szInner, 'Height', WIDGET_W, 8, 48, 1)
		hSlider:SetValue(data.iconHeight or 16)
		hSlider:SetAfterValueChanged(function(v) update('iconHeight', v) end)
		szY = placeWidget(hSlider, szInner, szY, SLIDER_H)

		yOffset = Widgets.EndCard(szCard, parent, szY)

		-- Layout card (Icons only)
		if(iType == C.IndicatorType.ICONS) then
			yOffset = placeHeading(parent, 'Layout', 2, yOffset)
			local layCard, layInner, layY = Widgets.StartCard(parent, width, yOffset)

			local mxSlider = Widgets.CreateSlider(layInner, 'Max Displayed', WIDGET_W, 1, 10, 1)
			mxSlider:SetValue(data.maxDisplayed or 3)
			mxSlider:SetAfterValueChanged(function(v) update('maxDisplayed', v) end)
			layY = placeWidget(mxSlider, layInner, layY, SLIDER_H)

			local nplSlider = Widgets.CreateSlider(layInner, 'Num Per Line', WIDGET_W, 0, 10, 1)
			nplSlider:SetValue(data.numPerLine or 0)
			nplSlider:SetAfterValueChanged(function(v) update('numPerLine', v) end)
			layY = placeWidget(nplSlider, layInner, layY, SLIDER_H)

			local spxSlider = Widgets.CreateSlider(layInner, 'Spacing X', WIDGET_W, 0, 20, 1)
			spxSlider:SetValue(data.spacingX or 2)
			spxSlider:SetAfterValueChanged(function(v) update('spacingX', v) end)
			layY = placeWidget(spxSlider, layInner, layY, SLIDER_H)

			local spySlider = Widgets.CreateSlider(layInner, 'Spacing Y', WIDGET_W, 0, 20, 1)
			spySlider:SetValue(data.spacingY or 2)
			spySlider:SetAfterValueChanged(function(v) update('spacingY', v) end)
			layY = placeWidget(spySlider, layInner, layY, SLIDER_H)

			local oriDD = Widgets.CreateDropdown(layInner, WIDGET_W)
			oriDD:SetItems(ORIENTATION_ITEMS)
			oriDD:SetValue(data.orientation or 'RIGHT')
			oriDD:SetOnSelect(function(v) update('orientation', v) end)
			layY = placeWidget(oriDD, layInner, layY, DROPDOWN_H)

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

		local durDD = Widgets.CreateDropdown(cdInner, WIDGET_W)
		durDD:SetItems(DURATION_MODE_ITEMS)
		durDD:SetValue(data.durationMode or 'Never')
		durDD:SetOnSelect(function(v) update('durationMode', v) end)
		cdY = placeWidget(durDD, cdInner, cdY, DROPDOWN_H)

		yOffset = Widgets.EndCard(cdCard, parent, cdY)

		-- Duration font (shown when durationMode != Never)
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

		-- Glow card
		yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = true })

		-- Position card
		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set)

	elseif(iType == C.IndicatorType.BAR or iType == C.IndicatorType.BARS) then
		-- Size card
		yOffset = placeHeading(parent, 'Size', 2, yOffset)
		local szCard, szInner, szY = Widgets.StartCard(parent, width, yOffset)

		local bwSlider = Widgets.CreateSlider(szInner, 'Width', WIDGET_W, 3, 500, 1)
		bwSlider:SetValue(data.barWidth or 100)
		bwSlider:SetAfterValueChanged(function(v) update('barWidth', v) end)
		szY = placeWidget(bwSlider, szInner, szY, SLIDER_H)

		local bhSlider = Widgets.CreateSlider(szInner, 'Height', WIDGET_W, 3, 500, 1)
		bhSlider:SetValue(data.barHeight or 4)
		bhSlider:SetAfterValueChanged(function(v) update('barHeight', v) end)
		szY = placeWidget(bhSlider, szInner, szY, SLIDER_H)

		local barOriDD = Widgets.CreateDropdown(szInner, WIDGET_W)
		barOriDD:SetItems(BAR_ORIENTATION_ITEMS)
		barOriDD:SetValue(data.barOrientation or 'Horizontal')
		barOriDD:SetOnSelect(function(v) update('barOrientation', v) end)
		szY = placeWidget(barOriDD, szInner, szY, DROPDOWN_H)

		yOffset = Widgets.EndCard(szCard, parent, szY)

		-- Layout card (Bars only)
		if(iType == C.IndicatorType.BARS) then
			yOffset = placeHeading(parent, 'Layout', 2, yOffset)
			local layCard, layInner, layY = Widgets.StartCard(parent, width, yOffset)

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

			yOffset = Widgets.EndCard(layCard, parent, layY)
		end

		-- Threshold color card
		yOffset = F.Settings.BuildThresholdColorCard(parent, width, yOffset, get, set, { showBorderColor = true, showBgColor = true })

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

		-- Glow + Position
		yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = true })
		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set)

	elseif(iType == C.IndicatorType.COLOR) then
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
		yOffset = placeHeading(parent, 'Overlay Mode', 2, yOffset)
		local modeCard, modeInner, modeY = Widgets.StartCard(parent, width, yOffset)

		local modeDD = Widgets.CreateDropdown(modeInner, WIDGET_W)
		modeDD:SetItems({
			{ text = 'Overlay',  value = 'Overlay' },
			{ text = 'FrameBar', value = 'FrameBar' },
			{ text = 'Both',     value = 'Both' },
		})
		modeDD:SetValue(data.overlayMode or 'Overlay')
		modeDD:SetOnSelect(function(v) update('overlayMode', v) end)
		modeY = placeWidget(modeDD, modeInner, modeY, DROPDOWN_H)

		local ovColor = data.color or { 0, 0, 0, 0.6 }
		local colorPicker = Widgets.CreateColorPicker(modeInner, 'Color', true, function(r, g, b, a)
			update('color', { r, g, b, a })
		end)
		colorPicker:SetColor(ovColor[1], ovColor[2], ovColor[3], ovColor[4] or 1)
		modeY = placeWidget(colorPicker, modeInner, modeY, DROPDOWN_H)

		yOffset = Widgets.EndCard(modeCard, parent, modeY)

		-- Conditional: Overlay or Both — threshold colors + smooth + bar orientation
		local ovMode = data.overlayMode or 'Overlay'
		if(ovMode == 'Overlay' or ovMode == 'Both') then
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
		-- Border settings card
		yOffset = placeHeading(parent, 'Border Settings', 2, yOffset)
		local borCard, borInner, borY = Widgets.StartCard(parent, width, yOffset)

		local thkSlider = Widgets.CreateSlider(borInner, 'Thickness', WIDGET_W, 1, 15, 1)
		thkSlider:SetValue(data.borderThickness or 2)
		thkSlider:SetAfterValueChanged(function(v) update('borderThickness', v) end)
		borY = placeWidget(thkSlider, borInner, borY, SLIDER_H)

		local borColor = data.color or { 1, 1, 1, 1 }
		local colorPicker = Widgets.CreateColorPicker(borInner, 'Color', true, function(r, g, b, a)
			update('color', { r, g, b, a })
		end)
		colorPicker:SetColor(borColor[1], borColor[2], borColor[3], borColor[4] or 1)
		borY = placeWidget(colorPicker, borInner, borY, DROPDOWN_H)

		local fadeSwitch = Widgets.CreateCheckButton(borInner, 'Fade Out', function(checked)
			update('fadeOut', checked)
		end)
		fadeSwitch:SetChecked(data.fadeOut == true)
		borY = placeWidget(fadeSwitch, borInner, borY, CHECK_H)

		yOffset = Widgets.EndCard(borCard, parent, borY)

		-- Position (frame level only)
		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set, { hidePosition = true })

	elseif(iType == C.IndicatorType.GLOW) then
		-- Fade Out + Glow type card
		yOffset = placeHeading(parent, 'Glow Settings', 2, yOffset)
		local glowSettCard, glowSettInner, glowSettY = Widgets.StartCard(parent, width, yOffset)

		local fadeSwitch = Widgets.CreateCheckButton(glowSettInner, 'Fade Out', function(checked)
			update('fadeOut', checked)
		end)
		fadeSwitch:SetChecked(data.fadeOut == true)
		glowSettY = placeWidget(fadeSwitch, glowSettInner, glowSettY, CHECK_H)

		yOffset = Widgets.EndCard(glowSettCard, parent, glowSettY)

		-- Glow card (no None)
		yOffset = F.Settings.BuildGlowCard(parent, width, yOffset, get, set, { allowNone = false })

		-- Position (frame level only)
		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set, { hidePosition = true })

	elseif(iType == C.IndicatorType.FRAME_BAR) then
		-- Legacy Frame Bar — basic bar height + position
		yOffset = placeHeading(parent, 'Bar Settings', 2, yOffset)
		local barCard, barInner, barY = Widgets.StartCard(parent, width, yOffset)

		local bh = Widgets.CreateSlider(barInner, 'Bar Height', WIDGET_W, 2, 20, 1)
		bh:SetValue(data.barHeight or 4)
		bh:SetAfterValueChanged(function(v) update('barHeight', v) end)
		barY = placeWidget(bh, barInner, barY, SLIDER_H)

		yOffset = Widgets.EndCard(barCard, parent, barY)

		yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set, { hidePosition = true })
	end

	return yOffset
end

-- ============================================================
-- Main Builder
-- ============================================================

--- Create the Indicator CRUD UI.
--- @param parent Frame  The content frame to build into
--- @param width number  Available width
--- @param yOffset number  Starting Y offset
--- @param opts table  { unitType, configKey }
--- @return number yOffset  The final yOffset after all widgets
function F.Settings.Builders.IndicatorCRUD(parent, width, yOffset, opts)
	local getIndicators, setIndicator, removeIndicator = makeConfigHelpers(opts.unitType, opts.configKey)

	local editingName = nil
	local listRowPool = {}
	local indicatorCount = 0  -- track total indicator count for resizing

	-- ── Create section ─────────────────────────────────────
	yOffset = placeHeading(parent, 'Create Indicator', 2, yOffset)

	local createCard, createInner, createY = Widgets.StartCard(parent, width, yOffset)

	local selectedType = C.IndicatorType.ICONS
	local selectedDisplayType = 'spell'  -- 'spell' or 'square'

	local typeDD = Widgets.CreateDropdown(createInner, 120)
	typeDD:SetItems(getTypeItems())
	typeDD:SetValue(C.IndicatorType.ICONS)
	typeDD:ClearAllPoints()
	Widgets.SetPoint(typeDD, 'TOPLEFT', createInner, 'TOPLEFT', 0, createY)

	local nameBox = Widgets.CreateEditBox(createInner, nil, 120, BUTTON_H)
	nameBox:ClearAllPoints()
	Widgets.SetPoint(nameBox, 'LEFT', typeDD, 'RIGHT', C.Spacing.tight, 0)
	nameBox:SetPlaceholder('Indicator name')

	local createBtn = Widgets.CreateButton(createInner, 'Create', 'accent', 60, BUTTON_H)
	createBtn:SetPoint('LEFT', nameBox, 'RIGHT', C.Spacing.tight, 0)
	createY = createY - BUTTON_H - C.Spacing.normal

	-- Type description FontString
	local typeDescFS = Widgets.CreateFontString(createInner, C.Font.sizeSmall, C.Colors.textSecondary)
	typeDescFS:ClearAllPoints()
	Widgets.SetPoint(typeDescFS, 'TOPLEFT', createInner, 'TOPLEFT', 0, createY)
	typeDescFS:SetJustifyH('LEFT')
	typeDescFS:SetText(TYPE_DESCRIPTIONS[selectedType] or '')
	createY = createY - 14 - C.Spacing.tight

	-- displayType toggle row (Spell Icons / Square Colors) — only for Icon/Icons
	local displayTypeRow = CreateFrame('Frame', nil, createInner)
	displayTypeRow:SetSize(width, BUTTON_H)
	displayTypeRow:ClearAllPoints()
	Widgets.SetPoint(displayTypeRow, 'TOPLEFT', createInner, 'TOPLEFT', 0, createY)

	local spellIconsBtn = Widgets.CreateButton(displayTypeRow, 'Spell Icons', 'accent', 100, BUTTON_H)
	spellIconsBtn:SetPoint('TOPLEFT', displayTypeRow, 'TOPLEFT', 0, 0)
	spellIconsBtn.value = 'spell'

	local squareColorsBtn = Widgets.CreateButton(displayTypeRow, 'Square Colors', 'widget', 110, BUTTON_H)
	squareColorsBtn:SetPoint('LEFT', spellIconsBtn, 'RIGHT', C.Spacing.tight, 0)
	squareColorsBtn.value = 'square'

	local displayTypeGroup = Widgets.CreateButtonGroup({ spellIconsBtn, squareColorsBtn }, function(value)
		selectedDisplayType = value
	end)
	displayTypeGroup:SetValue('spell')

	local displayTypeRowH = BUTTON_H + C.Spacing.normal

	-- Show/hide the displayType row based on type
	local function isIconType(t)
		return t == C.IndicatorType.ICON or t == C.IndicatorType.ICONS
	end

	if(isIconType(selectedType)) then
		displayTypeRow:Show()
		createY = createY - displayTypeRowH
	else
		displayTypeRow:Hide()
	end

	-- Hook type dropdown to update description and displayType row
	typeDD:SetOnSelect(function(value)
		selectedType = value
		typeDescFS:SetText(TYPE_DESCRIPTIONS[value] or '')
		if(isIconType(value)) then
			displayTypeRow:Show()
		else
			displayTypeRow:Hide()
		end
	end)

	yOffset = Widgets.EndCard(createCard, parent, createY)

	-- ── Indicator list ─────────────────────────────────────
	yOffset = placeHeading(parent, 'Indicators', 2, yOffset)

	local listTopY = yOffset  -- remember where the list starts
	local listScroll = Widgets.CreateScrollFrame(parent, nil, width, LIST_HEIGHT)
	listScroll:ClearAllPoints()
	Widgets.SetPoint(listScroll, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - LIST_HEIGHT - C.Spacing.normal
	local listContent = listScroll:GetContentFrame()

	local emptyLabel = Widgets.CreateFontString(listScroll, C.Font.sizeNormal, C.Colors.textSecondary)
	emptyLabel:SetPoint('CENTER', listScroll, 'CENTER', 0, 0)
	emptyLabel:SetText('No indicators configured')

	-- ── Settings section (dynamic) ─────────────────────────
	local settingsHeading, settingsHeadingH = Widgets.CreateHeading(parent, 'Indicator Settings', 2)
	settingsHeading:ClearAllPoints()
	Widgets.SetPoint(settingsHeading, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	settingsHeading:Hide()

	local settingsContainer = CreateFrame('Frame', nil, parent)
	settingsContainer:ClearAllPoints()
	Widgets.SetPoint(settingsContainer, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset - settingsHeadingH)
	Widgets.SetSize(settingsContainer, width, 1)
	settingsContainer:Hide()

	--- Resize the list scroll to fit its content and reposition the settings section.
	local function repositionSettings()
		local listH = math.min(LIST_HEIGHT, math.max(ROW_HEIGHT, indicatorCount * ROW_HEIGHT))
		listScroll:SetHeight(listH)
		local settingsY = listTopY - listH - C.Spacing.normal
		settingsHeading:ClearAllPoints()
		Widgets.SetPoint(settingsHeading, 'TOPLEFT', parent, 'TOPLEFT', 0, settingsY)
		settingsContainer:ClearAllPoints()
		Widgets.SetPoint(settingsContainer, 'TOPLEFT', parent, 'TOPLEFT', 0, settingsY - settingsHeadingH)
	end

	-- ── Refresh the indicator list ─────────────────────────
	local function layoutList()
		for _, row in next, listRowPool do row:Hide() end

		local indicators = getIndicators()
		indicatorCount = 0
		for _ in next, indicators do indicatorCount = indicatorCount + 1 end

		if(indicatorCount == 0) then
			emptyLabel:Show()
			listContent:SetHeight(1)
			listScroll:SetHeight(ROW_HEIGHT)
			listScroll:UpdateScrollRange()
			return
		end
		emptyLabel:Hide()

		local idx = 0
		for iName, iData in next, indicators do
			idx = idx + 1
			local row = listRowPool[idx]
			if(not row) then
				row = createListRow(listContent)
				listRowPool[idx] = row
			end
			row:Show()
			row:SetAlpha(1)
			row:ClearAllPoints()
			row:SetPoint('TOPLEFT', listContent, 'TOPLEFT', 0, -(idx - 1) * ROW_HEIGHT)
			row:SetPoint('TOPRIGHT', listContent, 'TOPRIGHT', 0, -(idx - 1) * ROW_HEIGHT)

			-- Reset editing state; re-apply if this row is being edited
			row.__nameFS:SetText(iName)
			row.__nameFS:Show()
			row.__editingWrap:Hide()
			if(editingName == iName) then
				row.__nameFS:Hide()
				row.__editingFS:SetText('Editing: ' .. iName)
				row.__editingWrap:SetAlpha(1)
				row.__editingWrap:Show()
			end
			row.__typeFS:SetText(iData.type or '?')
			row.__enabledCB:SetChecked(iData.enabled ~= false)

			-- Dynamic callback for this row's enabled checkbox
			local capName, capData, capIdx = iName, iData, idx
			row.__onEnabledChanged = function(checked)
				capData.enabled = checked
				setIndicator(capName, capData)
			end

			row.__editBtn:SetOnClick(function()
				editingName = capName

				-- Clear previous settings: hide all child frames AND regions (FontStrings/Textures)
				for _, child in next, { settingsContainer:GetChildren() } do
					child:Hide()
					child:ClearAllPoints()
				end
				for _, region in next, { settingsContainer:GetRegions() } do
					region:Hide()
					region:ClearAllPoints()
				end

				-- Show heading and container
				settingsHeading:Show()
				settingsContainer:Show()

				-- Reset all row editing labels, then show this row's
				for _, r in next, listRowPool do
					if(r.__editingWrap) then
						r.__editingWrap:Hide()
						r.__nameFS:Show()
					end
				end
				row.__nameFS:Hide()
				row.__editingFS:SetText('Editing: ' .. capName)
				row.__editingWrap:SetAlpha(1)
				row.__editingWrap:Show()

				-- Reposition settings snug below the list (uses total indicatorCount)
				repositionSettings()

				local cur = getIndicators()[capName]
				if(not cur) then return end

				-- Build settings into container
				local settingsEndY = buildIndicatorSettings(settingsContainer, width, 0, capName, cur, setIndicator)

				-- Update settingsContainer height
				settingsContainer:SetHeight(math.abs(settingsEndY) + C.Spacing.normal)

				-- Update the scroll content height and scroll range
				local listH = math.min(LIST_HEIGHT, math.max(ROW_HEIGHT, indicatorCount * ROW_HEIGHT))
				local settingsTopY = listTopY - listH - C.Spacing.normal
				local totalH = math.abs(settingsTopY) + settingsHeadingH + math.abs(settingsEndY) + C.Spacing.normal * 2
				parent:SetHeight(totalH)
				if(parent._scrollParent and parent._scrollParent.UpdateScrollRange) then
					parent._scrollParent:UpdateScrollRange()
				end
			end)

			row.__deleteBtn:SetOnClick(function()
				Widgets.ShowConfirmDialog('Delete Indicator', 'Delete "' .. capName .. '"?', function()
					removeIndicator(capName)
					if(editingName == capName) then
						editingName = nil
						settingsHeading:Hide()
						settingsContainer:Hide()
						-- Reset editing labels on all rows
						for _, r in next, listRowPool do
							if(r.__editingWrap) then
								r.__editingWrap:Hide()
								r.__nameFS:Show()
							end
						end
					end
					layoutList()
				end)
			end)
		end

		listContent:SetHeight(idx * ROW_HEIGHT)
		listScroll:UpdateScrollRange()
		-- Only reposition settings section when it's visible
		if(settingsContainer:IsShown()) then
			repositionSettings()
		else
			-- Still resize the list to fit content
			local listH = math.min(LIST_HEIGHT, math.max(ROW_HEIGHT, indicatorCount * ROW_HEIGHT))
			listScroll:SetHeight(listH)
		end
	end

	-- ── Create handler ─────────────────────────────────────
	local function doCreate()
		local iName = nameBox:GetText()
		if(not iName or iName == '') then return end
		local indicators = getIndicators()
		if(indicators[iName]) then return end

		local iType = typeDD:GetValue()
		local data = { type = iType, enabled = true, spells = {} }

		if(iType == C.IndicatorType.ICONS) then
			data.iconWidth = 16
			data.iconHeight = 16
			data.maxDisplayed = 3
			data.orientation = 'RIGHT'
			data.displayType = selectedDisplayType
		elseif(iType == C.IndicatorType.ICON) then
			data.iconWidth = 16
			data.iconHeight = 16
			data.displayType = selectedDisplayType
		elseif(iType == C.IndicatorType.GLOW) then
			data.glowType = C.GlowType.PROC
		elseif(iType == C.IndicatorType.BAR) then
			data.barWidth = 100
			data.barHeight = 4
		elseif(iType == C.IndicatorType.BARS) then
			data.barWidth = 50
			data.barHeight = 4
			data.maxDisplayed = 3
			data.orientation = 'DOWN'
		elseif(iType == C.IndicatorType.FRAME_BAR) then
			data.barHeight = 4
		elseif(iType == C.IndicatorType.COLOR) then
			data.rectWidth = 10
			data.rectHeight = 10
		elseif(iType == C.IndicatorType.OVERLAY) then
			data.overlayMode = 'Overlay'
			data.color = { 0, 0, 0, 0.6 }
		elseif(iType == C.IndicatorType.BORDER) then
			data.borderThickness = 2
			data.color = { 1, 1, 1, 1 }
		end

		setIndicator(iName, data)
		nameBox:SetText('')
		layoutList()
	end

	createBtn:SetOnClick(doCreate)
	nameBox:SetOnEnterPressed(doCreate)

	-- Initial layout
	layoutList()

	return yOffset
end
