local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings = F.Settings or {}
F.Settings.Builders = F.Settings.Builders or {}

-- ============================================================
-- Layout constants
-- ============================================================
local CHECK_H      = 22
local BUTTON_H     = 24
local ROW_HEIGHT   = 28
local MAX_VISIBLE_ROWS = 7
local LIST_HEIGHT  = MAX_VISIBLE_ROWS * ROW_HEIGHT
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

-- (per-type indicator panels live in IndicatorPanels.lua)
local buildIndicatorSettings = F.Settings.Builders.BuildIndicatorSettings

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
	local selectedDisplayType = C.IconDisplay.SPELL_ICON

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
	spellIconsBtn.value = C.IconDisplay.SPELL_ICON

	local squareColorsBtn = Widgets.CreateButton(displayTypeRow, 'Square Colors', 'widget', 110, BUTTON_H)
	squareColorsBtn:SetPoint('LEFT', spellIconsBtn, 'RIGHT', C.Spacing.tight, 0)
	squareColorsBtn.value = C.IconDisplay.COLORED_SQUARE

	local displayTypeGroup = Widgets.CreateButtonGroup({ spellIconsBtn, squareColorsBtn }, function(value)
		selectedDisplayType = value
	end)
	displayTypeGroup:SetValue(C.IconDisplay.SPELL_ICON)

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

	local listCard, listInner, listY = Widgets.StartCard(parent, width, yOffset)
	local listWidgetW = width - Widgets.CARD_PADDING * 2

	local listScroll = Widgets.CreateScrollFrame(listInner, nil, listWidgetW, LIST_HEIGHT)
	listScroll:ClearAllPoints()
	Widgets.SetPoint(listScroll, 'TOPLEFT', listInner, 'TOPLEFT', 0, listY)
	listY = listY - LIST_HEIGHT
	local listContent = listScroll:GetContentFrame()

	local emptyLabel = Widgets.CreateFontString(listScroll, C.Font.sizeNormal, C.Colors.textSecondary)
	emptyLabel:SetPoint('CENTER', listScroll, 'CENTER', 0, 0)
	emptyLabel:SetText('No indicators configured')

	yOffset = Widgets.EndCard(listCard, parent, listY)

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
		local settingsY = Widgets.EndCard(listCard, parent, -listH)
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
			Widgets.EndCard(listCard, parent, -ROW_HEIGHT)
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
				local cardEndY = Widgets.EndCard(listCard, parent, -listH)
				local totalH = math.abs(cardEndY) + settingsHeadingH + math.abs(settingsEndY) + C.Spacing.normal * 2
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
		-- Only reposition settings section when it's visible
		if(settingsContainer:IsShown()) then
			repositionSettings()
		else
			-- Still resize the list and card to fit content
			local listH = math.min(LIST_HEIGHT, math.max(ROW_HEIGHT, indicatorCount * ROW_HEIGHT))
			listScroll:SetHeight(listH)
			Widgets.EndCard(listCard, parent, -listH)
		end
		listScroll:UpdateScrollRange()
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
			data.showCooldown = true
			data.durationMode = 'Never'
		elseif(iType == C.IndicatorType.ICON) then
			data.iconWidth = 16
			data.iconHeight = 16
			data.displayType = selectedDisplayType
			data.showCooldown = true
			data.durationMode = 'Never'
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
