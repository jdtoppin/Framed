local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Constants
-- ============================================================

local ROW_H      = 28
local DROPDOWN_H = 22
local BUTTON_H   = 22
local WIDGET_W   = 220
local SELECT_W   = 60
local LABEL_W    = 120

local CONTENT_TYPES = {
	{ key = 'solo',         label = 'Solo Content' },
	{ key = 'party',        label = 'Party Content' },
	{ key = 'raid',         label = 'Raid Content' },
	{ key = 'mythicRaid',   label = 'Mythic Raid Content' },
	{ key = 'worldRaid',    label = 'World Raid Content' },
	{ key = 'battleground', label = 'Battleground Content' },
	{ key = 'arena',        label = 'Arena Content' },
}

-- ============================================================
-- Helpers
-- ============================================================

--- Return a list of {text, value} for all presets.
local function getPresetItems()
	local items = {}
	for _, name in next, C.PresetOrder do
		items[#items + 1] = { text = name, value = name }
	end
	return items
end

--- Return a list of {text, value} for spec override dropdowns (includes "Use default").
local function getPresetItemsWithDefault()
	local items = { { text = 'Use default', value = '' } }
	for _, name in next, C.PresetOrder do
		items[#items + 1] = { text = name, value = name }
	end
	return items
end

--- Get the status tag for a preset.
local function getPresetTag(name)
	local info = C.PresetInfo[name]
	if(not info) then return '' end
	if(info.isBase) then return 'base' end
	if(F.PresetManager and F.PresetManager.IsCustomized(name)) then
		return 'customized'
	end
	return 'uses: ' .. (info.fallback or '?')
end

-- ============================================================
-- Card Builders
-- ============================================================

--- Presets card: preset list + actions (copy, reset)
local function PresetsCard(parent, width)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local presetRowPool = {}

	local function buildPresetRow(rowParent, presetName, rowY)
		local row = CreateFrame('Frame', nil, rowParent, 'BackdropTemplate')
		Widgets.ApplyBackdrop(row, C.Colors.panel, C.Colors.border)
		row:ClearAllPoints()
		Widgets.SetPoint(row, 'TOPLEFT', rowParent, 'TOPLEFT', 0, rowY)
		row:SetPoint('TOPRIGHT', rowParent, 'TOPRIGHT', 0, rowY)
		row:SetHeight(ROW_H)

		local nameFS = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textNormal)
		nameFS:ClearAllPoints()
		Widgets.SetPoint(nameFS, 'LEFT', row, 'LEFT', C.Spacing.tight, 0)
		nameFS:SetText(presetName)
		nameFS:SetJustifyH('LEFT')

		local tagFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
		tagFS:ClearAllPoints()
		Widgets.SetPoint(tagFS, 'LEFT', nameFS, 'RIGHT', C.Spacing.normal, 0)
		tagFS:SetText(getPresetTag(presetName))

		local selectBtn = Widgets.CreateButton(row, 'Select', 'widget', SELECT_W, ROW_H - 6)
		selectBtn:ClearAllPoints()
		Widgets.SetPoint(selectBtn, 'RIGHT', row, 'RIGHT', -C.Spacing.tight, 0)

		local capturedName = presetName
		selectBtn:SetOnClick(function()
			F.Settings.SetEditingPreset(capturedName)
		end)

		row:EnableMouse(true)
		row:SetScript('OnEnter', function(self) Widgets.SetBackdropHighlight(self, true) end)
		row:SetScript('OnLeave', function(self)
			if(self:IsMouseOver()) then return end
			Widgets.SetBackdropHighlight(self, false)
		end)
		selectBtn:HookScript('OnEnter', function() Widgets.SetBackdropHighlight(row, true) end)
		selectBtn:HookScript('OnLeave', function()
			if(row:IsMouseOver()) then return end
			Widgets.SetBackdropHighlight(row, false)
		end)

		row.__nameFS     = nameFS
		row.__tagFS      = tagFS
		row.__selectBtn  = selectBtn
		row.__presetName = capturedName

		return row
	end

	-- Build preset rows
	local editingPreset = F.Settings.GetEditingPreset()
	for _, name in next, C.PresetOrder do
		local row = buildPresetRow(inner, name, cardY)
		presetRowPool[#presetRowPool + 1] = row

		if(name == editingPreset) then
			Widgets.ApplyBackdrop(row, C.Colors.panel, C.Colors.accent)
		end

		cardY = cardY - ROW_H - 1
	end

	cardY = cardY - C.Spacing.normal

	-- ── Actions ────────────────────────────────────────────
	-- Copy Settings From
	local copyLabel = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	copyLabel:ClearAllPoints()
	Widgets.SetPoint(copyLabel, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
	copyLabel:SetText('Copy Settings From')
	cardY = cardY - C.Font.sizeSmall - C.Spacing.tight

	local copyDD = Widgets.CreateDropdown(inner, WIDGET_W)
	copyDD:ClearAllPoints()
	Widgets.SetPoint(copyDD, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
	copyDD:SetItems(getPresetItems())

	local copyBtn = Widgets.CreateButton(inner, 'Copy', 'accent', 60, BUTTON_H)
	copyBtn:ClearAllPoints()
	Widgets.SetPoint(copyBtn, 'LEFT', copyDD, 'RIGHT', C.Spacing.tight, 0)

	copyBtn:SetOnClick(function()
		local source = copyDD:GetValue()
		if(not source) then return end
		local target = F.Settings.GetEditingPreset()
		Widgets.ShowConfirmDialog(
			'Copy Settings',
			'Copy all settings from "' .. source .. '" to "' .. target .. '"? This will overwrite current settings.',
			function()
				if(F.PresetManager and F.PresetManager.CopySettings) then
					F.PresetManager.CopySettings(source, target)
				end
				for _, row in next, presetRowPool do
					row.__tagFS:SetText(getPresetTag(row.__presetName))
				end
			end)
	end)

	cardY = cardY - DROPDOWN_H

	-- Reset to Default
	local resetBtn = Widgets.CreateButton(inner, 'Reset to Default', 'red', 140, BUTTON_H)
	resetBtn:ClearAllPoints()
	Widgets.SetPoint(resetBtn, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)

	local resetCardY = cardY
	cardY = cardY - BUTTON_H

	local function updateResetVisibility()
		local editing = F.Settings.GetEditingPreset()
		local info = C.PresetInfo[editing]
		if(info and not info.isBase) then
			resetBtn:Show()
			Widgets.EndCard(card, parent, cardY)
		else
			resetBtn:Hide()
			Widgets.EndCard(card, parent, resetCardY)
		end
	end

	resetBtn:SetOnClick(function()
		local target = F.Settings.GetEditingPreset()
		Widgets.ShowConfirmDialog(
			'Reset to Default',
			'Reset "' .. target .. '" to its default settings? This cannot be undone.',
			function()
				if(F.PresetManager and F.PresetManager.ResetToDefault) then
					F.PresetManager.ResetToDefault(target)
				end
				for _, row in next, presetRowPool do
					row.__tagFS:SetText(getPresetTag(row.__presetName))
				end
			end)
	end)

	updateResetVisibility()

	-- ── Event listener for editing preset changes ──────────
	if(F.EventBus) then
		F.EventBus:Register('EDITING_PRESET_CHANGED', function()
			local editing = F.Settings.GetEditingPreset()
			for _, row in next, presetRowPool do
				if(row.__presetName == editing) then
					Widgets.ApplyBackdrop(row, C.Colors.panel, C.Colors.accent)
				else
					Widgets.ApplyBackdrop(row, C.Colors.panel, C.Colors.border)
				end
				row.__tagFS:SetText(getPresetTag(row.__presetName))
			end
			updateResetVisibility()
		end, 'FramePresets.editingChanged')
	end

	return card
end

--- Character Settings card: Auto-Switch (left) + Spec Overrides (right) side by side
local function CharacterSettingsCard(parent, width)
	local CARD_GAP = C.Spacing.normal
	local halfW = math.floor((width - CARD_GAP) / 2)

	-- ── Left: Auto-Switch ─────────────────────────────────
	local asCard, asInner, asY = Widgets.StartCard(parent, halfW, 0)

	local asTitle = Widgets.CreateFontString(asInner, C.Font.sizeNormal, C.Colors.textActive)
	asTitle:ClearAllPoints()
	Widgets.SetPoint(asTitle, 'TOPLEFT', asInner, 'TOPLEFT', 0, asY)
	asTitle:SetText('Auto-Switch (Character Specific)')
	asY = asY - C.Font.sizeNormal - C.Spacing.normal

	for _, ct in next, CONTENT_TYPES do
		local rowLabel = Widgets.CreateFontString(asInner, C.Font.sizeSmall, C.Colors.textSecondary)
		rowLabel:ClearAllPoints()
		Widgets.SetPoint(rowLabel, 'TOPLEFT', asInner, 'TOPLEFT', 0, asY)
		rowLabel:SetText(ct.label)
		asY = asY - C.Font.sizeSmall - C.Spacing.tight

		local dd = Widgets.CreateDropdown(asInner, WIDGET_W)
		dd:ClearAllPoints()
		Widgets.SetPoint(dd, 'TOPLEFT', asInner, 'TOPLEFT', 0, asY)
		dd:SetItems(getPresetItems())

		local current = F.Config and F.Config:GetChar('autoSwitch.' .. ct.key)
		if(current) then
			dd:SetValue(current)
		end

		local capturedKey = ct.key
		dd:SetOnSelect(function(value)
			if(F.Config) then
				F.Config:SetChar('autoSwitch.' .. capturedKey, value)
			end
			if(F.EventBus) then
				F.EventBus:Fire('CONFIG_CHANGED:autoSwitch')
			end
		end)

		asY = asY - DROPDOWN_H - C.Spacing.normal
	end

	Widgets.EndCard(asCard, parent, asY)

	-- ── Right: Spec Overrides ─────────────────────────────
	local soCard, soInner, soY = Widgets.StartCard(parent, halfW, 0)
	soCard:ClearAllPoints()
	Widgets.SetPoint(soCard, 'TOPLEFT', asCard, 'TOPRIGHT', CARD_GAP, 0)

	local soTitle = Widgets.CreateFontString(soInner, C.Font.sizeNormal, C.Colors.textActive)
	soTitle:ClearAllPoints()
	Widgets.SetPoint(soTitle, 'TOPLEFT', soInner, 'TOPLEFT', 0, soY)
	soTitle:SetText('Spec Overrides (Character Specific)')
	soY = soY - C.Font.sizeNormal - C.Spacing.normal

	local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0

	if(numSpecs == 0) then
		local noSpecLabel = Widgets.CreateFontString(soInner, C.Font.sizeNormal, C.Colors.textSecondary)
		noSpecLabel:ClearAllPoints()
		Widgets.SetPoint(noSpecLabel, 'TOPLEFT', soInner, 'TOPLEFT', 0, soY)
		noSpecLabel:SetText('Spec overrides available in-game')
		soY = soY - ROW_H - C.Spacing.normal
		Widgets.EndCard(soCard, parent, soY)

		-- Return the taller card as the wrapper height reference
		local wrapperH = math.max(asCard:GetHeight(), soCard:GetHeight())
		local wrapper = CreateFrame('Frame', nil, parent)
		wrapper:SetSize(width, wrapperH)
		asCard:SetParent(wrapper)
		soCard:SetParent(wrapper)
		asCard:ClearAllPoints()
		Widgets.SetPoint(asCard, 'TOPLEFT', wrapper, 'TOPLEFT', 0, 0)
		soCard:ClearAllPoints()
		Widgets.SetPoint(soCard, 'TOPLEFT', asCard, 'TOPRIGHT', CARD_GAP, 0)
		return wrapper
	end

	-- Collect spec data
	local specs = {}
	for i = 1, numSpecs do
		local specID, specName, _, specIcon = GetSpecializationInfo(i)
		if(specID and specName) then
			specs[#specs + 1] = { id = specID, name = specName, icon = specIcon }
		end
	end

	-- Spec selector (segmented switch with icons)
	local SWITCH_H = 26
	local switchOpts = {}
	for _, spec in next, specs do
		switchOpts[#switchOpts + 1] = { text = spec.name, value = #switchOpts + 1, icon = spec.icon }
	end

	local SEG_W = 120
	local switchW = math.min(SEG_W * #specs, halfW - Widgets.CARD_PADDING * 2)
	local specSwitch = Widgets.CreateSwitch(soInner, switchW, SWITCH_H, switchOpts)
	specSwitch:ClearAllPoints()
	Widgets.SetPoint(specSwitch, 'TOPLEFT', soInner, 'TOPLEFT', 0, soY)

	soY = soY - SWITCH_H - C.Spacing.normal

	-- Dropdown panels (one per spec, only active one visible)
	local panels = {}

	for i, spec in next, specs do
		local panel = CreateFrame('Frame', nil, soInner)
		panel:ClearAllPoints()
		Widgets.SetPoint(panel, 'TOPLEFT', soInner, 'TOPLEFT', 0, soY)
		panel:SetPoint('TOPRIGHT', soInner, 'TOPRIGHT', 0, soY)
		panel:Hide()

		local panelY = 0
		local capturedSpecID = spec.id

		for _, ct in next, CONTENT_TYPES do
			local ctLabel = Widgets.CreateFontString(panel, C.Font.sizeSmall, C.Colors.textSecondary)
			ctLabel:ClearAllPoints()
			Widgets.SetPoint(ctLabel, 'TOPLEFT', panel, 'TOPLEFT', 0, panelY)
			ctLabel:SetText(ct.label)
			panelY = panelY - C.Font.sizeSmall - C.Spacing.tight

			local ctDD = Widgets.CreateDropdown(panel, WIDGET_W)
			ctDD:ClearAllPoints()
			Widgets.SetPoint(ctDD, 'TOPLEFT', panel, 'TOPLEFT', 0, panelY)
			ctDD:SetItems(getPresetItemsWithDefault())

			local configPath = 'specOverrides.' .. capturedSpecID .. '.' .. ct.key
			local currentVal = F.Config and F.Config:GetChar(configPath)
			if(currentVal) then
				ctDD:SetValue(currentVal)
			else
				ctDD:SetValue('')
			end

			local capturedCTKey = ct.key
			ctDD:SetOnSelect(function(value)
				if(F.Config) then
					if(value == '') then
						F.Config:SetChar('specOverrides.' .. capturedSpecID .. '.' .. capturedCTKey, nil)
					else
						F.Config:SetChar('specOverrides.' .. capturedSpecID .. '.' .. capturedCTKey, value)
					end
				end
				if(F.EventBus) then
					F.EventBus:Fire('CONFIG_CHANGED:specOverrides')
				end
			end)

			panelY = panelY - DROPDOWN_H - C.Spacing.normal
		end

		panel:SetHeight(math.abs(panelY))
		panels[i] = panel
	end

	-- Switch selection logic
	specSwitch:SetOnSelect(function(index)
		for i, panel in next, panels do
			if(i == index) then
				panel:Show()
			else
				panel:Hide()
			end
		end
	end)

	panels[1]:Show()
	soY = soY - (panels[1] and panels[1]:GetHeight() or 0)

	Widgets.EndCard(soCard, parent, soY)

	-- ── Wrapper: contains both cards, sized to the taller one ──
	local wrapperH = math.max(asCard:GetHeight(), soCard:GetHeight())
	local wrapper = CreateFrame('Frame', nil, parent)
	wrapper:SetSize(width, wrapperH)

	asCard:SetParent(wrapper)
	soCard:SetParent(wrapper)
	asCard:ClearAllPoints()
	Widgets.SetPoint(asCard, 'TOPLEFT', wrapper, 'TOPLEFT', 0, 0)
	soCard:ClearAllPoints()
	Widgets.SetPoint(soCard, 'TOPLEFT', asCard, 'TOPRIGHT', CARD_GAP, 0)

	return wrapper
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'framePresets',
	label   = 'Frame Presets',
	section = 'FRAME_PRESETS',
	order   = 10,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400

		local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width = parentW - C.Spacing.normal * 2

		local grid = Widgets.CreateCardGrid(content, width)

		grid:AddCard('presets',    'Presets',                                    PresetsCard,            {})
		grid:SetFullWidth('presets')
		grid:AddCard('charSettings', '',                                       CharacterSettingsCard,  {})
		grid:SetFullWidth('charSettings')

		grid._pinEnabled = false
		grid:SetTopOffset(C.Spacing.normal)
		grid:Layout(0, parentH)
		content:SetHeight(grid:GetTotalHeight())

		-- Lazy loading on scroll
		local function onScroll()
			local offset = scroll._scrollFrame:GetVerticalScroll()
			local viewH = scroll._scrollFrame:GetHeight()
			grid:Layout(offset, viewH)
			content:SetHeight(grid:GetTotalHeight())
		end
		scroll._scrollFrame:HookScript('OnMouseWheel', function()
			C_Timer.After(0, onScroll)
		end)

		-- Re-layout on settings resize
		F.EventBus:Register('SETTINGS_RESIZED', function(newW, newH)
			local gridW = newW - C.Spacing.normal * 2
			grid:SetWidth(gridW)
			content:SetWidth(newW)
			content:SetHeight(grid:GetTotalHeight())
		end, 'FramePresets.resize')

		F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', function()
			grid:RebuildCards()
		end, 'FramePresets.resizeComplete')

		return scroll
	end,
})
