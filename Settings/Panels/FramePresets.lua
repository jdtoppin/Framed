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
local TAG_W      = 80
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

local function placeHeading(content, text, level, yOffset)
	local heading, height = Widgets.CreateHeading(content, text, level)
	heading:ClearAllPoints()
	Widgets.SetPoint(heading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height
end

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
	-- Derived preset
	if(F.PresetManager and F.PresetManager.IsCustomized(name)) then
		return 'customized'
	end
	return 'uses: ' .. (info.fallback or '?')
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

		-- ── Outer scroll frame ─────────────────────────────────
		local scroll = Widgets.CreateScrollFrame(
			parent, nil,
			parentW,
			parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ============================================================
		-- Section 1: Preset List
		-- ============================================================
		yOffset = placeHeading(content, 'Preset List', 2, yOffset)

		local presetCard, presetInner, presetCardY
		presetCard, presetInner, presetCardY = Widgets.StartCard(content, width, yOffset)

		local presetRowPool = {}

		local function buildPresetRow(rowParent, presetName, rowY)
			local row = CreateFrame('Frame', nil, rowParent, 'BackdropTemplate')
			row._bgColor     = C.Colors.widget
			row._borderColor = C.Colors.border
			Widgets.ApplyBackdrop(row, C.Colors.widget, C.Colors.border)
			row:ClearAllPoints()
			Widgets.SetPoint(row, 'TOPLEFT', rowParent, 'TOPLEFT', 0, rowY)
			row:SetPoint('TOPRIGHT', rowParent, 'TOPRIGHT', 0, rowY)
			row:SetHeight(ROW_H)

			-- Name label
			local nameFS = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textNormal)
			nameFS:ClearAllPoints()
			Widgets.SetPoint(nameFS, 'LEFT', row, 'LEFT', C.Spacing.tight, 0)
			nameFS:SetText(presetName)
			nameFS:SetJustifyH('LEFT')

			-- Tag label (base / uses: Raid / customized)
			local tagFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
			tagFS:ClearAllPoints()
			Widgets.SetPoint(tagFS, 'LEFT', nameFS, 'RIGHT', C.Spacing.normal, 0)
			tagFS:SetText(getPresetTag(presetName))

			-- Select button
			local selectBtn = Widgets.CreateButton(row, 'Select', 'widget', SELECT_W, ROW_H - 6)
			selectBtn:ClearAllPoints()
			Widgets.SetPoint(selectBtn, 'RIGHT', row, 'RIGHT', -C.Spacing.tight, 0)

			local capturedName = presetName
			selectBtn:SetOnClick(function()
				F.Settings.SetEditingPreset(capturedName)
			end)

			-- Row highlight with child propagation
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

			row.__nameFS   = nameFS
			row.__tagFS    = tagFS
			row.__selectBtn = selectBtn
			row.__presetName = capturedName

			return row
		end

		local function refreshPresetRows()
			-- Hide all pooled rows
			for _, r in next, presetRowPool do
				r:Hide()
				r:SetParent(nil)
			end
			presetRowPool = {}

			local rowY = 0
			local editingPreset = F.Settings.GetEditingPreset()
			for _, name in next, C.PresetOrder do
				local row = buildPresetRow(presetInner, name, presetCardY + rowY)
				presetRowPool[#presetRowPool + 1] = row

				-- Highlight the currently editing preset with accent border
				if(name == editingPreset) then
					Widgets.ApplyBackdrop(row, C.Colors.widget, C.Colors.accent)
				end

				rowY = rowY - ROW_H - 1
			end
			return rowY
		end

		local totalRowY = refreshPresetRows()
		presetCardY = presetCardY + totalRowY - C.Spacing.normal

		yOffset = Widgets.EndCard(presetCard, content, presetCardY)

		-- ============================================================
		-- Section 2: Actions
		-- ============================================================
		yOffset = placeHeading(content, 'Actions', 2, yOffset)

		local actionsCard, actionsInner, actionsCardY
		actionsCard, actionsInner, actionsCardY = Widgets.StartCard(content, width, yOffset)

		-- Copy Settings From: [dropdown] [Copy]
		local copyLabel = Widgets.CreateFontString(actionsInner, C.Font.sizeNormal, C.Colors.textNormal)
		copyLabel:ClearAllPoints()
		Widgets.SetPoint(copyLabel, 'TOPLEFT', actionsInner, 'TOPLEFT', 0, actionsCardY)
		copyLabel:SetText('Copy Settings From:')

		local copyDD = Widgets.CreateDropdown(actionsInner, WIDGET_W)
		copyDD:ClearAllPoints()
		Widgets.SetPoint(copyDD, 'TOPLEFT', actionsInner, 'TOPLEFT', LABEL_W + C.Spacing.normal, actionsCardY)
		copyDD:SetItems(getPresetItems())

		local copyBtn = Widgets.CreateButton(actionsInner, 'Copy', 'accent', 60, BUTTON_H)
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
					-- Refresh tags to reflect customized state
					for _, row in next, presetRowPool do
						row.__tagFS:SetText(getPresetTag(row.__presetName))
					end
				end)
		end)

		actionsCardY = actionsCardY - DROPDOWN_H - C.Spacing.normal

		-- Reset to Default button (shown for derived presets only)
		local resetBtn = Widgets.CreateButton(actionsInner, 'Reset to Default', 'red', 140, BUTTON_H)
		resetBtn:ClearAllPoints()
		Widgets.SetPoint(resetBtn, 'TOPLEFT', actionsInner, 'TOPLEFT', 0, actionsCardY)

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
					-- Refresh tags
					for _, row in next, presetRowPool do
						row.__tagFS:SetText(getPresetTag(row.__presetName))
					end
				end)
		end)

		updateResetVisibility()
		actionsCardY = actionsCardY - BUTTON_H - C.Spacing.normal

		yOffset = Widgets.EndCard(actionsCard, content, actionsCardY)

		-- ============================================================
		-- Section 3: Auto-Switch
		-- ============================================================
		yOffset = placeHeading(content, 'Auto-Switch', 2, yOffset)

		local autoCard, autoInner, autoCardY
		autoCard, autoInner, autoCardY = Widgets.StartCard(content, width, yOffset)

		local autoSwitchDropdowns = {}

		for _, ct in next, CONTENT_TYPES do
			-- Row label
			local rowLabel = Widgets.CreateFontString(autoInner, C.Font.sizeNormal, C.Colors.textNormal)
			rowLabel:ClearAllPoints()
			Widgets.SetPoint(rowLabel, 'TOPLEFT', autoInner, 'TOPLEFT', 0, autoCardY)
			rowLabel:SetText(ct.label)

			-- Preset dropdown
			local dd = Widgets.CreateDropdown(autoInner, WIDGET_W)
			dd:ClearAllPoints()
			Widgets.SetPoint(dd, 'TOPLEFT', autoInner, 'TOPLEFT', LABEL_W + C.Spacing.normal + 40, autoCardY)
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

			autoSwitchDropdowns[ct.key] = dd
			autoCardY = autoCardY - DROPDOWN_H - C.Spacing.normal
		end

		yOffset = Widgets.EndCard(autoCard, content, autoCardY)

		-- ============================================================
		-- Section 4: Spec Overrides
		-- ============================================================
		yOffset = placeHeading(content, 'Spec Overrides', 2, yOffset)

		local specCard, specInner, specCardY
		specCard, specInner, specCardY = Widgets.StartCard(content, width, yOffset)

		-- Get player specializations
		local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0

		for i = 1, numSpecs do
			local specID, specName = GetSpecializationInfo(i)
			if(specID and specName) then
				-- Collapsible header for this spec
				local specHeader = CreateFrame('Frame', nil, specInner, 'BackdropTemplate')
				specHeader._bgColor     = C.Colors.widget
				specHeader._borderColor = C.Colors.border
				Widgets.ApplyBackdrop(specHeader, C.Colors.widget, C.Colors.border)
				specHeader:ClearAllPoints()
				Widgets.SetPoint(specHeader, 'TOPLEFT', specInner, 'TOPLEFT', 0, specCardY)
				specHeader:SetPoint('TOPRIGHT', specInner, 'TOPRIGHT', 0, specCardY)
				specHeader:SetHeight(ROW_H)
				specHeader:EnableMouse(true)

				local arrow = Widgets.CreateFontString(specHeader, C.Font.sizeNormal, C.Colors.textSecondary)
				arrow:ClearAllPoints()
				Widgets.SetPoint(arrow, 'LEFT', specHeader, 'LEFT', C.Spacing.tight, 0)
				arrow:SetText('\226\150\184') -- ▸

				local specLabel = Widgets.CreateFontString(specHeader, C.Font.sizeNormal, C.Colors.textNormal)
				specLabel:ClearAllPoints()
				Widgets.SetPoint(specLabel, 'LEFT', arrow, 'RIGHT', C.Spacing.base, 0)
				specLabel:SetText(specName)

				specCardY = specCardY - ROW_H - 1

				-- Content area for this spec's overrides
				local specContent = CreateFrame('Frame', nil, specInner)
				specContent:ClearAllPoints()
				Widgets.SetPoint(specContent, 'TOPLEFT', specInner, 'TOPLEFT', C.Spacing.loose, specCardY)
				specContent:SetPoint('TOPRIGHT', specInner, 'TOPRIGHT', 0, specCardY)
				specContent:Hide()

				local specContentY = 0
				local capturedSpecID = specID

				-- Build content type → preset dropdowns
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

				-- Toggle collapse
				local expanded = false
				specHeader:SetScript('OnMouseDown', function()
					expanded = not expanded
					if(expanded) then
						arrow:SetText('\226\150\190') -- ▾
						specContent:Show()
						-- Shift everything below down
					else
						arrow:SetText('\226\150\184') -- ▸
						specContent:Hide()
					end
				end)

				-- Row highlight
				specHeader:SetScript('OnEnter', function(self) Widgets.SetBackdropHighlight(self, true) end)
				specHeader:SetScript('OnLeave', function(self)
					if(self:IsMouseOver()) then return end
					Widgets.SetBackdropHighlight(self, false)
				end)

				-- Reserve space for expanded content (hidden by default)
				-- When collapsed, the content is hidden so no extra space is needed
				-- We use a wrapper approach: always reserve the space
				-- For simplicity, always reserve space (content is just hidden/shown)
				specCardY = specCardY - specContentHeight - C.Spacing.base
			end
		end

		-- Fallback if no specs found (not in-game)
		if(numSpecs == 0) then
			local noSpecLabel = Widgets.CreateFontString(specInner, C.Font.sizeNormal, C.Colors.textSecondary)
			noSpecLabel:ClearAllPoints()
			Widgets.SetPoint(noSpecLabel, 'TOPLEFT', specInner, 'TOPLEFT', 0, specCardY)
			noSpecLabel:SetText('Spec overrides available in-game')
			specCardY = specCardY - ROW_H - C.Spacing.normal
		end

		yOffset = Widgets.EndCard(specCard, content, specCardY)

		-- ── Listen for editing preset changes ──────────────────
		if(F.EventBus) then
			F.EventBus:On('EDITING_PRESET_CHANGED', function()
				-- Refresh preset row highlights and tags
				local editingPreset = F.Settings.GetEditingPreset()
				for _, row in next, presetRowPool do
					if(row.__presetName == editingPreset) then
						Widgets.ApplyBackdrop(row, C.Colors.widget, C.Colors.accent)
					else
						Widgets.ApplyBackdrop(row, C.Colors.widget, C.Colors.border)
					end
					row.__tagFS:SetText(getPresetTag(row.__presetName))
				end
				-- Update reset button visibility
				updateResetVisibility()
			end)
		end

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
