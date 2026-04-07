local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================
local ROW_HEIGHT       = 28
local MAX_VISIBLE_ROWS = 5
local LIST_HEIGHT      = MAX_VISIBLE_ROWS * ROW_HEIGHT
local BUTTON_H         = 24
local DROPDOWN_H       = 22
local PAD_H            = 6

-- Display names for indicator types in the list
local TYPE_DISPLAY = {
	Border  = 'Border / Glow',
	Overlay = 'Color / Duration Overlay',
}

-- Type descriptions for the Create card
local TYPE_DESCRIPTIONS = {
	Icon      = 'Single spell icon or colored square',
	Icons     = 'Row/grid of spell icons or colored squares',
	Bar       = 'Single depleting status bar',
	Bars      = 'Row/grid of depleting status bars',
	Rectangle = 'Colored rectangle positioned on frame',
	Overlay   = 'Color fill, depleting overlay, or both',
	Border    = 'Colored border or glow effect around the frame',
}

-- ============================================================
-- Config helpers
-- ============================================================
local function makeConfigHelpers(unitType)
	local function basePath()
		local presetName = F.Settings.GetEditingPreset()
		return 'presets.' .. presetName .. '.auras.' .. unitType .. '.buffs.indicators'
	end

	local function getIndicators()
		if(not F.Config) then return {} end
		return F.Config:Get(basePath()) or {}
	end

	local function fireChange()
		if(F.EventBus) then
			local presetName = F.Settings.GetEditingPreset()
			F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.buffs')
		end
		F.Settings.UpdateAuraPreviewDimming('buffs', nil)
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
		{ text = 'Color / Duration Overlay', value = C.IndicatorType.OVERLAY },
		{ text = 'Border / Glow', value = C.IndicatorType.BORDER },
		{ text = 'Rectangle', value = C.IndicatorType.RECTANGLE },
	}
end

-- ============================================================
-- List row creation
-- ============================================================
local function createListRow(scrollContent)
	local row = CreateFrame('Frame', nil, scrollContent, 'BackdropTemplate')
	Widgets.ApplyBackdrop(row, C.Colors.panel, C.Colors.border)
	row:SetHeight(ROW_HEIGHT)

	local nameFS = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textActive)
	nameFS:SetPoint('LEFT', row, 'LEFT', PAD_H, 0)
	nameFS:SetJustifyH('LEFT')
	nameFS:SetWidth(100)
	row.__nameFS = nameFS

	-- "Editing: name" overlay (RIGHT anchor set after enabledCB is created)
	local editingWrap = CreateFrame('Frame', nil, row)
	editingWrap:SetPoint('LEFT', row, 'LEFT', PAD_H, 0)
	editingWrap:SetHeight(ROW_HEIGHT)
	editingWrap:Hide()
	row.__editingWrap = editingWrap

	local editingFS = Widgets.CreateFontString(editingWrap, C.Font.sizeNormal, { 0.3, 0.9, 0.3, 1 })
	editingFS:SetPoint('LEFT', editingWrap, 'LEFT', 0, 0)
	editingFS:SetPoint('RIGHT', editingWrap, 'RIGHT', 0, 0)
	editingFS:SetJustifyH('LEFT')
	editingFS:SetWordWrap(false)
	row.__editingFS = editingFS

	local typeFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
	typeFS:SetJustifyH('RIGHT')
	typeFS:SetWordWrap(false)
	row.__typeFS = typeFS

	-- Enabled toggle
	row.__onEnabledChanged = nil
	local enabledCB = Widgets.CreateCheckButton(row, '', function(checked)
		if(row.__onEnabledChanged) then row.__onEnabledChanged(checked) end
	end)
	enabledCB:SetWidgetTooltip('Enable / Disable')
	row.__enabledCB = enabledCB

	local editBtn = Widgets.CreateButton(row, 'Edit', 'widget', 44, 20)
	row.__editBtn = editBtn
	local deleteBtn = Widgets.CreateButton(row, 'Delete', 'red', 56, 20)
	row.__deleteBtn = deleteBtn

	-- Anchoring: [name] [type] ... [enabled] [delete] [edit]
	editBtn:SetPoint('RIGHT', row, 'RIGHT', -PAD_H, 0)
	deleteBtn:SetPoint('RIGHT', editBtn, 'LEFT', -C.Spacing.base, 0)
	enabledCB:ClearAllPoints()
	Widgets.SetPoint(enabledCB, 'RIGHT', deleteBtn, 'LEFT', -C.Spacing.base, 0)
	typeFS:SetPoint('LEFT', nameFS, 'RIGHT', C.Spacing.tight, 0)
	typeFS:SetPoint('RIGHT', enabledCB, 'LEFT', -C.Spacing.tight, 0)
	editingWrap:SetPoint('RIGHT', enabledCB, 'LEFT', -C.Spacing.tight, 0)

	-- Row highlight + truncation tooltip
	row:EnableMouse(true)
	row:SetScript('OnEnter', function(self)
		Widgets.SetBackdropHighlight(self, true)
		-- Show tooltip when name or type text is truncated
		if(Widgets.ShowTooltip) then
			local nameTrunc = nameFS:IsTruncated()
			local typeTrunc = typeFS:IsTruncated()
			if(nameTrunc or typeTrunc) then
				local title = nameTrunc and nameFS:GetText() or nil
				local body = typeTrunc and typeFS:GetText() or nil
				Widgets.ShowTooltip(self, title or body, title and body or nil)
			end
		end
	end)
	row:SetScript('OnLeave', function(self)
		if(self:IsMouseOver()) then return end
		Widgets.SetBackdropHighlight(self, false)
		if(Widgets.HideTooltip) then Widgets.HideTooltip() end
	end)

	for _, child in next, { editBtn, deleteBtn, enabledCB } do
		child:HookScript('OnEnter', function() Widgets.SetBackdropHighlight(row, true) end)
		child:HookScript('OnLeave', function()
			if(row:IsMouseOver()) then return end
			Widgets.SetBackdropHighlight(row, false)
			if(Widgets.HideTooltip) then Widgets.HideTooltip() end
		end)
	end

	return row
end

-- ============================================================
-- Resolve card builder: string markers → Builders.SharedXxx
-- ============================================================
local function resolveBuilder(builderOrString)
	if(type(builderOrString) == 'string') then
		local Builders = F.Settings.IndicatorCardBuilders
		return Builders[builderOrString]
	end
	return builderOrString
end

local createDefaultData = F.Settings.Builders.CreateDefaultIndicatorData

-- ============================================================
-- Panel Registration
-- ============================================================

F.Settings.RegisterPanel({
	id         = 'buffs',
	label      = 'Buffs',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 11,
	create     = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll  = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		local unitType = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
		local getIndicators, setIndicator, removeIndicator = makeConfigHelpers(unitType)

		-- ── Unit type dropdown + copy-to ─────────────────────────
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'buffs', 'buffs')

		-- ── Pinned row: Preview + Create card + Indicator List card ─
		local CARD_GAP    = C.Spacing.normal
		local createCardW = math.floor((width - CARD_GAP) * 0.40)
		local listCardW   = width - createCardW - CARD_GAP
		local pinnedRowY  = yOffset

		-- ── Preview card (above create card, same column) ────────
		-- Add accent top border to pinned cards
		local function addAccentBar(card)
			local bar = card:CreateTexture(nil, 'OVERLAY')
			bar:SetHeight(1)
			bar:SetPoint('TOPLEFT', card, 'TOPLEFT', 0, 0)
			bar:SetPoint('TOPRIGHT', card, 'TOPRIGHT', 0, 0)
			local ac = C.Colors.accent
			bar:SetColorTexture(ac[1], ac[2], ac[3], 0.4)
			return bar
		end

		local previewCard = F.Settings.AuraPreview.BuildPreviewCard(content, createCardW)
		previewCard:ClearAllPoints()
		Widgets.SetPoint(previewCard, 'TOPLEFT', content, 'TOPLEFT', 0, pinnedRowY)
		local previewAccentBar = addAccentBar(previewCard)
		local previewCardH = previewCard:GetHeight()
		local createStartY = pinnedRowY - previewCardH - CARD_GAP

		-- ── Create card ──────────────────────────────────────────
		local selectedType = C.IndicatorType.ICONS
		local selectedDisplayType = C.IconDisplay.SPELL_ICON
		local selectedBorderGlowMode = 'Border'

		local createCard, createInner, createY = Widgets.StartCard(content, createCardW, createStartY)
		addAccentBar(createCard)

		-- Type dropdown
		local typeDD = Widgets.CreateDropdown(createInner, createCardW - Widgets.CARD_PADDING * 2)
		typeDD:SetItems(getTypeItems())
		typeDD:SetValue(C.IndicatorType.ICONS)
		typeDD:ClearAllPoints()
		Widgets.SetPoint(typeDD, 'TOPLEFT', createInner, 'TOPLEFT', 0, createY)
		createY = createY - DROPDOWN_H - C.Spacing.tight

		-- Type description
		local typeDescFS = Widgets.CreateFontString(createInner, C.Font.sizeSmall, C.Colors.textSecondary)
		typeDescFS:ClearAllPoints()
		Widgets.SetPoint(typeDescFS, 'TOPLEFT', createInner, 'TOPLEFT', 0, createY)
		typeDescFS:SetJustifyH('LEFT')
		typeDescFS:SetWidth(createCardW - Widgets.CARD_PADDING * 2)
		typeDescFS:SetWordWrap(true)
		typeDescFS:SetText(TYPE_DESCRIPTIONS[selectedType] or '')
		createY = createY - 14 - C.Spacing.tight

		-- Display type toggle (Icon/Icons only)
		local function isIconType(t)
			return t == C.IndicatorType.ICON or t == C.IndicatorType.ICONS
		end

		local displayTypeRow = CreateFrame('Frame', nil, createInner)
		displayTypeRow:SetSize(createCardW - Widgets.CARD_PADDING * 2, BUTTON_H)
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

		-- Border/Glow toggle (Border type only)
		local borderGlowRow = CreateFrame('Frame', nil, createInner)
		borderGlowRow:SetSize(createCardW - Widgets.CARD_PADDING * 2, BUTTON_H)
		borderGlowRow:ClearAllPoints()
		Widgets.SetPoint(borderGlowRow, 'TOPLEFT', createInner, 'TOPLEFT', 0, createY)

		local borderModeBtn = Widgets.CreateButton(borderGlowRow, 'Border', 'accent', 100, BUTTON_H)
		borderModeBtn:SetPoint('TOPLEFT', borderGlowRow, 'TOPLEFT', 0, 0)
		borderModeBtn.value = 'Border'

		local glowModeBtn = Widgets.CreateButton(borderGlowRow, 'Glow', 'widget', 100, BUTTON_H)
		glowModeBtn:SetPoint('LEFT', borderModeBtn, 'RIGHT', C.Spacing.tight, 0)
		glowModeBtn.value = 'Glow'

		local borderGlowGroup = Widgets.CreateButtonGroup({ borderModeBtn, glowModeBtn }, function(value)
			selectedBorderGlowMode = value
		end)
		borderGlowGroup:SetValue('Border')

		if(isIconType(selectedType)) then
			displayTypeRow:Show()
			borderGlowRow:Hide()
			createY = createY - BUTTON_H - C.Spacing.tight
		elseif(selectedType == C.IndicatorType.BORDER) then
			displayTypeRow:Hide()
			borderGlowRow:Show()
			createY = createY - BUTTON_H - C.Spacing.tight
		else
			displayTypeRow:Hide()
			borderGlowRow:Hide()
		end

		typeDD:SetOnSelect(function(value)
			selectedType = value
			typeDescFS:SetText(TYPE_DESCRIPTIONS[value] or '')
			if(isIconType(value)) then
				displayTypeRow:Show()
			else
				displayTypeRow:Hide()
			end
			if(value == C.IndicatorType.BORDER) then
				borderGlowRow:Show()
			else
				borderGlowRow:Hide()
			end
		end)

		-- Name input
		local nameBox = Widgets.CreateEditBox(createInner, nil, createCardW - Widgets.CARD_PADDING * 2, BUTTON_H)
		nameBox:ClearAllPoints()
		Widgets.SetPoint(nameBox, 'TOPLEFT', createInner, 'TOPLEFT', 0, createY)
		nameBox:SetPlaceholder('Indicator name')
		createY = createY - BUTTON_H - C.Spacing.tight

		-- Create button
		local createBtn = Widgets.CreateButton(createInner, 'Create', 'accent', createCardW - Widgets.CARD_PADDING * 2, BUTTON_H)
		createBtn:ClearAllPoints()
		Widgets.SetPoint(createBtn, 'TOPLEFT', createInner, 'TOPLEFT', 0, createY)
		createY = createY - BUTTON_H

		Widgets.EndCard(createCard, content, createY)

		-- ── Indicator List card ──────────────────────────────────
		-- Match list card height to the combined preview + create column
		local leftColumnH = previewCardH + CARD_GAP + createCard:GetHeight()
		local listScrollH = leftColumnH - Widgets.CARD_PADDING * 2

		local listCard, listInner, listY = Widgets.StartCard(content, listCardW, pinnedRowY)
		listCard:ClearAllPoints()
		Widgets.SetPoint(listCard, 'TOPLEFT', content, 'TOPLEFT', createCardW + CARD_GAP, pinnedRowY)
		listCard._startY = pinnedRowY
		addAccentBar(listCard)

		local listWidgetW = listCardW - Widgets.CARD_PADDING * 2
		local listScroll = Widgets.CreateScrollFrame(listInner, nil, listWidgetW, listScrollH)
		listScroll:ClearAllPoints()
		Widgets.SetPoint(listScroll, 'TOPLEFT', listInner, 'TOPLEFT', 0, listY)
		listY = listY - listScrollH
		local listContent = listScroll:GetContentFrame()

		local emptyLabel = Widgets.CreateFontString(listScroll, C.Font.sizeNormal, C.Colors.textSecondary)
		emptyLabel:SetPoint('CENTER', listScroll, 'CENTER', 0, 0)
		emptyLabel:SetText('No indicators configured')

		Widgets.EndCard(listCard, content, listY)
		yOffset = pinnedRowY - leftColumnH - C.Spacing.normal

		-- ── CardGrid for settings cards ──────────────────────────
		local gridTopY = yOffset
		local grid = Widgets.CreateCardGrid(content, width)
		grid:SetTopOffset(math.abs(gridTopY))

		-- ── State ────────────────────────────────────────────────
		local editingName = nil
		local listRowPool = {}
		local indicatorCount = 0

		-- ── Helper: spawn settings cards for an indicator ────────
		local function spawnSettingsCards(iName, iData)
			grid:RemoveAllCards()

			local Builders = F.Settings.IndicatorCardBuilders
			local cardsForType = Builders.CARDS_FOR_TYPE[iData.type]

			local function update(key, value)
				iData[key] = value
				setIndicator(iName, iData)
			end
			local function get(key) return iData[key] end
			local function set(key, value) update(key, value) end

			local function rebuildPanel()
				local cur = getIndicators()[iName]
				if(not cur) then return end
				iData = cur
				spawnSettingsCards(iName, iData)
			end

			if(cardsForType) then
				for _, cardDef in next, cardsForType do
					local cardId    = cardDef[1]
					local cardTitle = cardDef[2]
					local builder   = resolveBuilder(cardDef[3])
					if(builder) then
						grid:AddCard(cardId, cardTitle, builder, { iData, update, get, set, rebuildPanel })
					end
				end
			end

			grid:Layout(0, parentH)
			content:SetHeight(grid:GetTotalHeight())
			scroll:UpdateScrollRange()

			-- Update breadcrumb and preview dimming
			F.Settings.UpdateAuraBreadcrumb('Buffs', iName)
			F.Settings.UpdateAuraPreviewDimming('buffs', iName)
		end

		-- ── Helper: close settings cards ─────────────────────────
		local function closeSettingsCards()
			grid:RemoveAllCards()
			grid:Layout(0, parentH)

			editingName = nil

			-- Reset editing labels
			for _, r in next, listRowPool do
				if(r.__editingWrap) then
					r.__editingWrap:Hide()
					r.__nameFS:Show()
				end
			end

			-- Update content height
			content:SetHeight(math.abs(gridTopY) + C.Spacing.normal)
			scroll:UpdateScrollRange()

			-- Reset breadcrumb and preview
			F.Settings.UpdateAuraBreadcrumb('Buffs', nil)
			F.Settings.UpdateAuraPreviewDimming('buffs', nil)
		end

		-- ── Refresh the indicator list ───────────────────────────
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

				-- Name + editing state
				row.__nameFS:SetText(iName)
				row.__nameFS:Show()
				row.__editingWrap:Hide()
				if(editingName == iName) then
					row.__nameFS:Hide()
					row.__editingFS:SetText('Editing: ' .. iName)
					row.__editingWrap:SetAlpha(1)
					row.__editingWrap:Show()
				end
				row.__typeFS:SetText(TYPE_DISPLAY[iData.type] or iData.type or '?')
				row.__enabledCB:SetChecked(iData.enabled ~= false)

				-- Capture locals for closures
				local capName, capData = iName, iData

				row.__onEnabledChanged = function(checked)
					capData.enabled = checked
					setIndicator(capName, capData)
				end

				row.__editBtn:SetText(editingName == capName and 'Close' or 'Edit')
				row.__editBtn:SetOnClick(function()
					if(editingName == capName) then
						closeSettingsCards()
						row.__editBtn:SetText('Edit')
						layoutList()
						return
					end

					editingName = capName

					-- Reset all row editing labels
					for _, r in next, listRowPool do
						if(r.__editingWrap) then
							r.__editingWrap:Hide()
							r.__nameFS:Show()
						end
						if(r.__editBtn) then
							r.__editBtn:SetText('Edit')
						end
					end
					row.__nameFS:Hide()
					row.__editingFS:SetText('Editing: ' .. capName)
					row.__editingWrap:SetAlpha(1)
					row.__editingWrap:Show()
					row.__editBtn:SetText('Close')

					-- Fetch fresh data and spawn cards
					local freshData = getIndicators()[capName]
					if(freshData) then
						spawnSettingsCards(capName, freshData)
					end
				end)

				row.__deleteBtn:SetOnClick(function()
					Widgets.ShowConfirmDialog('Delete Indicator', 'Delete "' .. capName .. '"?', function()
						removeIndicator(capName)
						if(editingName == capName) then
							closeSettingsCards()
						end
						layoutList()
					end)
				end)
			end

			listContent:SetHeight(idx * ROW_HEIGHT)
			local listH = math.min(listScrollH, math.max(ROW_HEIGHT, indicatorCount * ROW_HEIGHT))
			listScroll:SetHeight(listH)
			listScroll:UpdateScrollRange()
		end

		-- ── Create handler ───────────────────────────────────────
		local function doCreate()
			local iName = nameBox:GetText()
			if(not iName or iName == '') then return end
			local indicators = getIndicators()
			if(indicators[iName]) then return end

			local data = createDefaultData(typeDD:GetValue(), selectedDisplayType, selectedBorderGlowMode)
			setIndicator(iName, data)
			nameBox:SetText('')
			layoutList()

			-- Auto-open for editing
			editingName = iName
			local freshData = getIndicators()[iName]
			if(freshData) then
				spawnSettingsCards(iName, freshData)
			end
			-- Update list to reflect editing state
			layoutList()
		end

		createBtn:SetOnClick(doCreate)
		nameBox:SetOnEnterPressed(doCreate)

		-- ── Initial layout ───────────────────────────────────────
		layoutList()
		content:SetHeight(math.abs(gridTopY) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		-- ── Scroll integration ───────────────────────────────────
		local previewNaturalY = math.abs(pinnedRowY)
		local previewSticky = false
		local previewOrigLevel = previewCard:GetFrameLevel()

		local function onScroll()
			local offset = scroll._scrollFrame:GetVerticalScroll()
			local viewH  = scroll._scrollFrame:GetHeight()
			grid:Layout(offset, viewH)
			content:SetHeight(grid:GetTotalHeight())

			-- Sticky preview: reparent to scroll viewport when scrolled past
			local shouldStick = offset > previewNaturalY
			if(shouldStick and not previewSticky) then
				previewSticky = true
				previewAccentBar:Hide()
				previewCard:SetParent(scroll)
				previewCard:SetFrameLevel(previewOrigLevel + 50)
				previewCard:ClearAllPoints()
				Widgets.SetPoint(previewCard, 'TOPLEFT', scroll, 'TOPLEFT', 0, 0)
			elseif(not shouldStick and previewSticky) then
				previewSticky = false
				previewAccentBar:Show()
				previewCard:SetParent(content)
				previewCard:SetFrameLevel(previewOrigLevel)
				previewCard:ClearAllPoints()
				Widgets.SetPoint(previewCard, 'TOPLEFT', content, 'TOPLEFT', 0, pinnedRowY)
			end
		end

		scroll._scrollFrame:HookScript('OnMouseWheel', function()
			C_Timer.After(0, onScroll)
		end)

		-- ── Resize handling ──────────────────────────────────────
		local resizeKey = 'Buffs.resize.' .. unitType
		local function onResize(newW, newH)
			local newWidth = newW - C.Spacing.normal * 2
			local newCreateW = math.floor((newWidth - CARD_GAP) * 0.40)
			local newListW   = newWidth - newCreateW - CARD_GAP
			local newCreateInnerW = newCreateW - Widgets.CARD_PADDING * 2
			local newListInnerW   = newListW - Widgets.CARD_PADDING * 2

			-- Wrapper card frames
			previewCard:SetWidth(newCreateW)
			createCard:SetWidth(newCreateW)
			listCard:SetWidth(newListW)
			listCard:ClearAllPoints()
			Widgets.SetPoint(listCard, 'TOPLEFT', content, 'TOPLEFT', newCreateW + CARD_GAP, pinnedRowY)

			-- Create card inner widgets
			typeDD:SetWidth(newCreateInnerW)
			typeDescFS:SetWidth(newCreateInnerW)
			displayTypeRow:SetWidth(newCreateInnerW)
			borderGlowRow:SetWidth(newCreateInnerW)
			nameBox:SetWidth(newCreateInnerW)
			createBtn:SetWidth(newCreateInnerW)

			-- Display type toggle buttons (fill row proportionally)
			local halfBtnW = math.floor((newCreateInnerW - C.Spacing.tight) / 2)
			spellIconsBtn:SetWidth(halfBtnW)
			squareColorsBtn:SetWidth(newCreateInnerW - halfBtnW - C.Spacing.tight)
			borderModeBtn:SetWidth(halfBtnW)
			glowModeBtn:SetWidth(newCreateInnerW - halfBtnW - C.Spacing.tight)

			-- Preview frame max width
			local preview = F.Settings._auraPreview
			if(preview) then
				preview._maxWidth = newCreateW - Widgets.CARD_PADDING * 2
			end

			-- List card inner scroll (content width auto-updates via OnSizeChanged)
			listScroll:SetWidth(newListInnerW)

			grid:SetWidth(newWidth)
			content:SetWidth(newW)
			content:SetHeight(grid:GetTotalHeight())
			scroll:UpdateScrollRange()
		end

		F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)
		F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', function()
			grid:RebuildCards()
			if(F.Settings._auraPreview) then
				F.Settings.AuraPreview.Rebuild()
			end
		end, resizeKey .. '.complete')

		-- ── Cleanup on hide, re-register on show ─────────────────
		scroll:HookScript('OnHide', function()
			grid:CancelAnimations()
			F.EventBus:Unregister('SETTINGS_RESIZED', resizeKey)
			F.EventBus:Unregister('SETTINGS_RESIZE_COMPLETE', resizeKey .. '.complete')
		end)

		scroll:HookScript('OnShow', function()
			F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)
			F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', function()
				grid:RebuildCards()
				if(F.Settings._auraPreview) then
					F.Settings.AuraPreview.Rebuild()
				end
			end, resizeKey .. '.complete')
			grid:Layout(0, parentH, false)
			content:SetHeight(grid:GetTotalHeight())
		end)

		scroll._ownedPreview = F.Settings._auraPreview
		return scroll
	end,
})
