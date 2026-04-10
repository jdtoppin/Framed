local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local B = F.FrameSettingsBuilder

-- ============================================================
-- Constants
-- ============================================================

local ROW_H      = 28
local DROPDOWN_H = 22
local BUTTON_H   = 22
local WIDGET_W   = 220
local SELECT_W   = 60
local LABEL_W    = 120
local ARROW_RIGHT = [[Interface\AddOns\Framed\Media\Icons\ArrowRight1]]
local ARROW_DOWN  = [[Interface\AddOns\Framed\Media\Icons\ArrowDown1]]
local ARROW_SIZE  = 12
local SPEC_ICON_SIZE = ROW_H - 8

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
	local widgetW = width - Widgets.CARD_PADDING * 2
	local copyLabel = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textNormal)
	copyLabel:ClearAllPoints()
	Widgets.SetPoint(copyLabel, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
	copyLabel:SetText('Copy Settings From:')

	local copyDD = Widgets.CreateDropdown(inner, WIDGET_W)
	copyDD:ClearAllPoints()
	Widgets.SetPoint(copyDD, 'TOPLEFT', inner, 'TOPLEFT', LABEL_W + C.Spacing.normal, cardY)
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

	cardY = cardY - DROPDOWN_H - C.Spacing.normal

	-- Reset to Default
	local resetBtn = Widgets.CreateButton(inner, 'Reset to Default', 'red', 140, BUTTON_H)
	resetBtn:ClearAllPoints()
	Widgets.SetPoint(resetBtn, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)

	local function updateResetVisibility()
		local editing = F.Settings.GetEditingPreset()
		local info = C.PresetInfo[editing]
		if(info and not info.isBase) then
			resetBtn:Show()
		else
			resetBtn:Hide()
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
	cardY = cardY - BUTTON_H - C.Spacing.normal

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
		end)
	end

	Widgets.EndCard(card, parent, cardY)
	return card
end

--- Auto-Switch card: content type → preset dropdowns
local function AutoSwitchCard(parent, width)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	for _, ct in next, CONTENT_TYPES do
		local rowLabel = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textNormal)
		rowLabel:ClearAllPoints()
		Widgets.SetPoint(rowLabel, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
		rowLabel:SetText(ct.label)

		local dd = Widgets.CreateDropdown(inner, WIDGET_W)
		dd:ClearAllPoints()
		Widgets.SetPoint(dd, 'TOPLEFT', inner, 'TOPLEFT', LABEL_W + C.Spacing.normal + 40, cardY)
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

		cardY = cardY - DROPDOWN_H - C.Spacing.normal
	end

	Widgets.EndCard(card, parent, cardY)
	return card
end

--- Spec Overrides card: collapsible per-spec preset overrides
local function SpecOverridesCard(parent, width)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0

	-- Track all spec sections for reflow on expand/collapse
	local specSections = {}

	for i = 1, numSpecs do
		local specID, specName, _, specIcon = GetSpecializationInfo(i)
		if(specID and specName) then
			local section = {}
			section.expanded = false

			local specHeader = CreateFrame('Frame', nil, inner, 'BackdropTemplate')
			specHeader._bgColor     = C.Colors.widget
			specHeader._borderColor = C.Colors.border
			Widgets.ApplyBackdrop(specHeader, C.Colors.widget, C.Colors.border)
			specHeader:SetHeight(ROW_H)
			specHeader:EnableMouse(true)
			section.header = specHeader

			local arrow = specHeader:CreateTexture(nil, 'ARTWORK')
			arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
			arrow:SetPoint('LEFT', specHeader, 'LEFT', C.Spacing.tight, 0)
			arrow:SetTexture(ARROW_RIGHT)
			local ts = C.Colors.textSecondary
			arrow:SetVertexColor(ts[1], ts[2], ts[3], ts[4] or 1)
			section.arrow = arrow

			local labelAnchor = arrow
			if(specIcon) then
				local icon = specHeader:CreateTexture(nil, 'ARTWORK')
				icon:SetSize(SPEC_ICON_SIZE, SPEC_ICON_SIZE)
				icon:SetPoint('LEFT', arrow, 'RIGHT', C.Spacing.base, 0)
				icon:SetTexture(specIcon)
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				labelAnchor = icon
			end

			local specLabel = Widgets.CreateFontString(specHeader, C.Font.sizeNormal, C.Colors.textNormal)
			specLabel:ClearAllPoints()
			Widgets.SetPoint(specLabel, 'LEFT', labelAnchor, 'RIGHT', C.Spacing.base, 0)
			specLabel:SetText(specName)

			local specContent = CreateFrame('Frame', nil, inner)
			specContent:Hide()
			section.content = specContent

			local specContentY = 0
			local capturedSpecID = specID

			for _, ct in next, CONTENT_TYPES do
				local ctLabel = Widgets.CreateFontString(specContent, C.Font.sizeSmall, C.Colors.textSecondary)
				ctLabel:ClearAllPoints()
				Widgets.SetPoint(ctLabel, 'TOPLEFT', specContent, 'TOPLEFT', 0, specContentY)
				ctLabel:SetText(ct.label)

				local ctDD = Widgets.CreateDropdown(specContent, WIDGET_W - C.Spacing.loose)
				ctDD:ClearAllPoints()
				Widgets.SetPoint(ctDD, 'TOPLEFT', specContent, 'TOPLEFT', LABEL_W + C.Spacing.normal + 20, specContentY)
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

				specContentY = specContentY - DROPDOWN_H - C.Spacing.base
			end

			local specContentHeight = math.abs(specContentY)
			specContent:SetHeight(specContentHeight)
			section.contentHeight = specContentHeight

			specSections[#specSections + 1] = section
		end
	end

	-- Reflow all spec sections based on expanded state
	local function reflowSpecs()
		local y = 0
		for _, sec in next, specSections do
			sec.header:ClearAllPoints()
			Widgets.SetPoint(sec.header, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			sec.header:SetPoint('TOPRIGHT', inner, 'TOPRIGHT', 0, y)
			y = y - ROW_H - 1

			sec.content:ClearAllPoints()
			Widgets.SetPoint(sec.content, 'TOPLEFT', inner, 'TOPLEFT', C.Spacing.loose, y)
			sec.content:SetPoint('TOPRIGHT', inner, 'TOPRIGHT', 0, y)

			if(sec.expanded) then
				sec.content:Show()
				y = y - sec.contentHeight - C.Spacing.base
			else
				sec.content:Hide()
			end
		end

		local totalHeight = math.abs(y)
		inner:SetHeight(totalHeight)
		card:SetHeight(totalHeight + Widgets.CARD_PADDING * 2 + (card._cardGridTitleH or 0))
	end

	-- Wire up expand/collapse
	for _, sec in next, specSections do
		sec.header:SetScript('OnMouseDown', function()
			sec.expanded = not sec.expanded
			sec.arrow:SetTexture(sec.expanded and ARROW_DOWN or ARROW_RIGHT)
			reflowSpecs()
		end)

		sec.header:SetScript('OnEnter', function(self) Widgets.SetBackdropHighlight(self, true) end)
		sec.header:SetScript('OnLeave', function(self)
			if(self:IsMouseOver()) then return end
			Widgets.SetBackdropHighlight(self, false)
		end)
	end

	-- Fallback if no specs found
	if(numSpecs == 0) then
		local noSpecLabel = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textSecondary)
		noSpecLabel:ClearAllPoints()
		Widgets.SetPoint(noSpecLabel, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
		noSpecLabel:SetText('Spec overrides available in-game')
		cardY = cardY - ROW_H - C.Spacing.normal
	end

	-- Initial layout
	if(#specSections > 0) then
		cardY = -(#specSections * (ROW_H + 1))
		reflowSpecs()
	end

	Widgets.EndCard(card, parent, cardY)
	return card
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

		grid:AddCard('presets',      'Presets',                                PresetsCard,      {})
		grid:AddCard('autoSwitch',   'Auto-Switch (Character Specific)',       AutoSwitchCard,   {})
		grid:AddCard('specOverrides','Spec Overrides (Character Specific)',    SpecOverridesCard, {})

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
