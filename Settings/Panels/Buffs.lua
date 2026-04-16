local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================
local ROW_HEIGHT       = 28
local BUTTON_H         = 24
local DROPDOWN_H       = 22
local PAD_H            = 6

-- Display names for indicator types in the list
local TYPE_DISPLAY = {
	Border  = 'Border / Glow',
	Overlay = 'Color / Duration Overlay',
}

-- Indicator type dropdown items (used by the inline create form)
local function getTypeItems()
	return {
		{ text = 'Icons',                    value = C.IndicatorType.ICONS },
		{ text = 'Icon',                     value = C.IndicatorType.ICON },
		{ text = 'Bars',                     value = C.IndicatorType.BARS },
		{ text = 'Bar',                      value = C.IndicatorType.BAR },
		{ text = 'Color / Duration Overlay', value = C.IndicatorType.OVERLAY },
		{ text = 'Border / Glow',            value = C.IndicatorType.BORDER },
		{ text = 'Rectangle',                value = C.IndicatorType.RECTANGLE },
	}
end

local createDefaultData = F.Settings.Builders.CreateDefaultIndicatorData

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
-- List row creation
-- ============================================================
local function createListRow(scrollContent)
	local row = CreateFrame('Frame', nil, scrollContent, 'BackdropTemplate')
	Widgets.ApplyBackdrop(row, C.Colors.panel, C.Colors.border)
	row:SetHeight(ROW_HEIGHT)

	local nameFS = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textActive)
	nameFS:SetPoint('LEFT', row, 'LEFT', PAD_H, 0)
	nameFS:SetJustifyH('LEFT')
	nameFS:SetWordWrap(false)
	nameFS:SetWidth(100)
	row.__nameFS = nameFS

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

	-- Accent left bar (2px) for selected state
	local selectedBar = row:CreateTexture(nil, 'OVERLAY')
	selectedBar:SetTexture(F.Media.GetPlainTexture())
	selectedBar:SetVertexColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
	selectedBar:SetPoint('TOPLEFT', row, 'TOPLEFT', 0, 0)
	selectedBar:SetPoint('BOTTOMLEFT', row, 'BOTTOMLEFT', 0, 0)
	selectedBar:SetWidth(2)
	selectedBar:Hide()
	row.__selectedBar = selectedBar

	-- Solid lighter tint across the whole row for selected state
	local selectedBg = row:CreateTexture(nil, 'BORDER')
	selectedBg:SetTexture(F.Media.GetPlainTexture())
	selectedBg:SetVertexColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 0.25)
	selectedBg:SetPoint('TOPLEFT', row, 'TOPLEFT', 2, 0)
	selectedBg:SetPoint('BOTTOMRIGHT', row, 'BOTTOMRIGHT', 0, 0)
	selectedBg:Hide()
	row.__selectedBg = selectedBg

	function row:__setSelected(selected)
		if(selected) then
			self.__selectedBar:Show()
			self.__selectedBg:Show()
		else
			self.__selectedBar:Hide()
			self.__selectedBg:Hide()
		end
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
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		local unitType = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
		local getIndicators, setIndicator, removeIndicator = makeConfigHelpers(unitType)

		-- ── Unit type dropdown + copy-to ─────────────────────────
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'buffs', 'buffs')

		-- ── Pinned row: Preview | Indicator List card ───────────────
		local CARD_GAP       = C.Spacing.normal
		local TITLE_ROW_H    = 18
		local FORM_ROW_H     = BUTTON_H
		local FORM_HEIGHT    = FORM_ROW_H + PAD_H * 2
		local previewCardW = math.floor((width - CARD_GAP) * 0.40)
		local listCardW    = width - previewCardW - CARD_GAP
		local pinnedRowY   = yOffset

		-- ── Preview card ─────────────────────────────────────────
		local previewCard = F.Settings.AuraPreview.BuildPreviewCard(content, previewCardW)
		previewCard:ClearAllPoints()
		Widgets.SetPoint(previewCard, 'TOPLEFT', content, 'TOPLEFT', 0, pinnedRowY)
		local previewCardH = previewCard:GetHeight()

		-- ── Indicator List card ──────────────────────────────────
		-- List card height matches the preview card height
		local leftColumnH = previewCardH

		local listCard, listInner = Widgets.StartCard(content, listCardW, pinnedRowY)
		listCard:ClearAllPoints()
		Widgets.SetPoint(listCard, 'TOPLEFT', content, 'TOPLEFT', previewCardW + CARD_GAP, pinnedRowY)
		listCard._startY = pinnedRowY
		local listY = 4  -- align with CardGrid title padding (8px from card edge)

		local listWidgetW = listCardW - Widgets.CARD_PADDING * 2

		-- ── Title row: "Indicators" label + collapse/expand button ──
		local addToggleBtn = Widgets.CreateIconButton(listInner, F.Media.GetIcon('Plus'), TITLE_ROW_H)
		addToggleBtn:SetBackdrop(nil)
		addToggleBtn:EnableMouse(false)
		addToggleBtn:ClearAllPoints()
		Widgets.SetPoint(addToggleBtn, 'TOPRIGHT', listInner, 'TOPRIGHT', 0, listY)

		-- Title + hint anchored to the button row so everything shares the same vertical center
		local titleLabel = Widgets.CreateFontString(listInner, C.Font.sizeNormal, C.Colors.textActive)
		titleLabel:SetJustifyH('LEFT')
		titleLabel:ClearAllPoints()
		titleLabel:SetPoint('LEFT', listInner, 'LEFT', 0, 0)
		titleLabel:SetPoint('TOP', addToggleBtn, 'TOP', 0, 0)
		titleLabel:SetPoint('BOTTOM', addToggleBtn, 'BOTTOM', 0, 0)
		titleLabel:SetText('Indicators')

		local addHintFS = Widgets.CreateFontString(listInner, C.Font.sizeSmall, C.Colors.textSecondary)
		addHintFS:SetJustifyH('RIGHT')
		addHintFS:SetAlpha(0.6)
		addHintFS:SetText('Add new')
		Widgets.SetPoint(addHintFS, 'RIGHT', addToggleBtn, 'LEFT', -C.Spacing.tight, 0)

		-- Hit area spans both the hint text and the icon for unified hover + click
		local addHitArea = CreateFrame('Button', nil, listInner)
		addHitArea:SetFrameLevel(addToggleBtn:GetFrameLevel() + 1)
		addHitArea:SetPoint('LEFT', addHintFS, 'LEFT', -2, 0)
		addHitArea:SetPoint('TOP', addToggleBtn, 'TOP', 0, 0)
		addHitArea:SetPoint('BOTTOMRIGHT', addToggleBtn, 'BOTTOMRIGHT', 0, 0)

		Widgets.SetupAccentHover(addHitArea, {
			{ addToggleBtn._icon, true },
			{ addHintFS, false },
		})

		listY = listY - TITLE_ROW_H - C.Spacing.tight

		-- ── Collapsible create form (hidden by default) ──
		local formFrame = CreateFrame('Frame', nil, listInner, 'BackdropTemplate')
		Widgets.ApplyBackdrop(formFrame, C.Colors.panel, C.Colors.accent)
		formFrame:SetHeight(FORM_HEIGHT)
		formFrame:ClearAllPoints()
		Widgets.SetPoint(formFrame, 'TOPLEFT', listInner, 'TOPLEFT', 0, listY)
		Widgets.SetPoint(formFrame, 'TOPRIGHT', listInner, 'TOPRIGHT', 0, listY)
		formFrame:Hide()

		local CREATE_BTN_SIZE = FORM_ROW_H
		local formInnerW = listCardW - Widgets.CARD_PADDING * 2 - PAD_H * 2
		local fieldW     = formInnerW - CREATE_BTN_SIZE - C.Spacing.normal
		local nameBoxW   = math.floor((fieldW - C.Spacing.normal) * 0.40)
		local typeDDW    = fieldW - nameBoxW - C.Spacing.normal

		local nameBox = Widgets.CreateEditBox(formFrame, nil, nameBoxW, FORM_ROW_H)
		nameBox:SetPlaceholder('Indicator name')
		nameBox:ClearAllPoints()
		Widgets.SetPoint(nameBox, 'TOPLEFT', formFrame, 'TOPLEFT', PAD_H, -PAD_H)

		local typeDD = Widgets.CreateDropdown(formFrame, typeDDW)
		typeDD:SetItems(getTypeItems())
		typeDD:SetValue(C.IndicatorType.ICONS)
		typeDD:ClearAllPoints()
		Widgets.SetPoint(typeDD, 'TOPLEFT', nameBox, 'TOPRIGHT', C.Spacing.normal, -math.floor((FORM_ROW_H - DROPDOWN_H) / 2))

		local createBtn = Widgets.CreateIconButton(formFrame, F.Media.GetIcon('Tick'), CREATE_BTN_SIZE)
		createBtn:ClearAllPoints()
		Widgets.SetPoint(createBtn, 'TOPRIGHT', formFrame, 'TOPRIGHT', -PAD_H, -PAD_H)

		-- ── Indicator list scroll (height recomputes when form toggles) ──
		local function computeListScrollH()
			local usedAbove = TITLE_ROW_H + C.Spacing.tight
			if(formFrame:IsShown()) then
				usedAbove = usedAbove + FORM_HEIGHT + C.Spacing.tight
			end
			return previewCardH - Widgets.CARD_PADDING * 2 - usedAbove
		end

		-- Forward-declare so anchorListScroll can close over it
		local listScroll
		local listScrollBaseY = listY

		local function anchorListScroll()
			local y = listScrollBaseY
			if(formFrame:IsShown()) then
				y = y - FORM_HEIGHT - C.Spacing.tight
			end
			listScroll:ClearAllPoints()
			Widgets.SetPoint(listScroll, 'TOPLEFT', listInner, 'TOPLEFT', 0, y)
			listScroll:SetHeight(computeListScrollH())
			listScroll:UpdateScrollRange()
		end

		listScroll = Widgets.CreateScrollFrame(listInner, nil, listWidgetW, computeListScrollH())
		listScroll:ClearAllPoints()
		Widgets.SetPoint(listScroll, 'TOPLEFT', listInner, 'TOPLEFT', 0, listY)
		listY = listY - computeListScrollH()
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

			-- Reset selected-row highlight
			for _, r in next, listRowPool do
				if(r.__setSelected) then
					r:__setSelected(false)
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

				-- Name + selected state
				row.__nameFS:SetText(iName)
				row:__setSelected(editingName == iName)
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

					-- Reset all row selections
					for _, r in next, listRowPool do
						if(r.__setSelected) then
							r:__setSelected(false)
						end
						if(r.__editBtn) then
							r.__editBtn:SetText('Edit')
						end
					end
					row:__setSelected(true)
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
			local listH = math.min(computeListScrollH(), math.max(ROW_HEIGHT, indicatorCount * ROW_HEIGHT))
			listScroll:SetHeight(listH)
			listScroll:UpdateScrollRange()
		end

		-- ── Inline create form toggle ────────────────────────────
		local function resetForm()
			nameBox:SetText('')
			-- SetText('') clears the placeholder active flag; re-apply so the
			-- hint text returns when the form is reopened or first shown.
			nameBox:SetPlaceholder('Indicator name')
			typeDD:SetValue(C.IndicatorType.ICONS)
		end

		local function setFormOpen(open)
			if(open) then
				formFrame:Show()
				addHintFS:Hide()
				addHitArea:Hide()
				addToggleBtn:EnableMouse(true)
				addToggleBtn._icon:SetTexture(F.Media.GetIcon('Close'))
				Widgets.ApplyBackdrop(addToggleBtn, C.Colors.widget, C.Colors.border)
			else
				formFrame:Hide()
				addHintFS:Show()
				addHitArea:Show()
				addToggleBtn:EnableMouse(false)
				addToggleBtn._icon:SetTexture(F.Media.GetIcon('Plus'))
				addToggleBtn:SetBackdrop(nil)
				resetForm()
			end
			anchorListScroll()
		end

		addHitArea:SetScript('OnClick', function()
			setFormOpen(true)
		end)
		addToggleBtn:SetOnClick(function()
			setFormOpen(false)
		end)

		-- ── Create handler ───────────────────────────────────────
		local function doCreate()
			local iName = nameBox:GetText()
			if(not iName or iName == '') then return end
			local indicators = getIndicators()
			if(indicators[iName]) then return end

			local data = createDefaultData(typeDD:GetValue(), C.IconDisplay.SPELL_ICON, 'Border')
			setIndicator(iName, data)
			layoutList()

			-- Auto-open the new indicator for editing
			editingName = iName
			local freshData = getIndicators()[iName]
			if(freshData) then
				spawnSettingsCards(iName, freshData)
			end
			layoutList()

			-- Collapse the form after successful create
			setFormOpen(false)
		end

		createBtn:SetOnClick(doCreate)
		nameBox:SetOnEnterPressed(doCreate)

		-- ── Initial state ────────────────────────────────────────
		setFormOpen(false)

		-- ── Initial layout ───────────────────────────────────────
		layoutList()

		-- Auto-select the first enabled indicator so the cards area isn't blank
		if(indicatorCount > 0) then
			local indicators = getIndicators()
			local firstName, firstData
			for iName, iData in next, indicators do
				if(not firstName) then firstName, firstData = iName, iData end
				if(iData.enabled ~= false) then
					firstName, firstData = iName, iData
					break
				end
			end
			if(firstName) then
				editingName = firstName
				spawnSettingsCards(firstName, firstData)
				layoutList()
			end
		end

		content:SetHeight(math.abs(gridTopY) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		-- ── Pin cards to the scroll viewport so they never scroll ──
		local previewOrigLevel = previewCard:GetFrameLevel()

		-- Semi-transparent scrim behind the pinned cards so scrolling
		-- content is dimmed rather than clearly visible through the gap.
		local scrim = CreateFrame('Frame', nil, scroll)
		scrim:SetFrameLevel(previewOrigLevel + 49)
		scrim:SetPoint('TOPLEFT', scroll, 'TOPLEFT', 0, 0)
		scrim:SetPoint('TOPRIGHT', scroll, 'TOPRIGHT', 0, 0)
		scrim:SetHeight(math.abs(pinnedRowY) + previewCardH + C.Spacing.normal)
		local scrimBg = scrim:CreateTexture(nil, 'BACKGROUND')
		scrimBg:SetAllPoints(scrim)
		local bg = C.Colors.background
		scrimBg:SetColorTexture(bg[1], bg[2], bg[3], 0.85)

		previewCard:SetParent(scroll)
		previewCard:SetFrameLevel(previewOrigLevel + 50)
		previewCard:ClearAllPoints()
		Widgets.SetPoint(previewCard, 'TOPLEFT', scroll, 'TOPLEFT', 0, pinnedRowY)

		listCard:SetParent(scroll)
		listCard:SetFrameLevel(previewOrigLevel + 50)
		listCard:ClearAllPoints()
		Widgets.SetPoint(listCard, 'TOPLEFT', scroll, 'TOPLEFT', previewCardW + CARD_GAP, pinnedRowY)

		local function onScroll()
			local offset = scroll._scrollFrame:GetVerticalScroll()
			local viewH  = scroll._scrollFrame:GetHeight()
			grid:Layout(offset, viewH)
			content:SetHeight(grid:GetTotalHeight())
		end

		scroll._scrollFrame:HookScript('OnMouseWheel', function()
			C_Timer.After(0, onScroll)
		end)

		-- ── Resize handling ──────────────────────────────────────
		local resizeKey = 'Buffs.resize.' .. unitType
		local function onResize(newW, newH)
			local newWidth    = newW - C.Spacing.normal * 2
			local newPreviewW = math.floor((newWidth - CARD_GAP) * 0.40)
			local newListW    = newWidth - newPreviewW - CARD_GAP
			local newListInnerW = newListW - Widgets.CARD_PADDING * 2

			previewCard:SetWidth(newPreviewW)
			listCard:SetWidth(newListW)
			listCard:ClearAllPoints()
			Widgets.SetPoint(listCard, 'TOPLEFT', scroll, 'TOPLEFT', newPreviewW + CARD_GAP, pinnedRowY)

			-- Preview frame max width
			local preview = F.Settings._auraPreview
			if(preview) then
				preview._maxWidth = newPreviewW - Widgets.CARD_PADDING * 2
			end

			-- List card inner scroll (content width auto-updates via OnSizeChanged)
			listScroll:SetWidth(newListInnerW)

			-- Inline create form widgets
			local newFormInnerW = newListW - Widgets.CARD_PADDING * 2 - PAD_H * 2
			local newFieldW     = newFormInnerW - CREATE_BTN_SIZE - C.Spacing.normal
			local newNameBoxW   = math.floor((newFieldW - C.Spacing.normal) * 0.40)
			local newTypeDDW    = newFieldW - newNameBoxW - C.Spacing.normal
			nameBox:SetWidth(newNameBoxW)
			typeDD:SetWidth(newTypeDDW)
			-- formFrame auto-adjusts via its TOPRIGHT anchor on listInner

			grid:SetWidth(newWidth)
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
			-- Catch up with any resize that happened while hidden
			local curW = parent._explicitWidth  or parent:GetWidth()  or parentW
			local curH = parent._explicitHeight or parent:GetHeight() or parentH
			onResize(curW, curH)
			grid:RebuildCards()
			if(F.Settings._auraPreview) then
				F.Settings.AuraPreview.Rebuild()
			end
			-- Respawn cards for the editing indicator, or auto-select one
			layoutList()
			if(editingName) then
				local freshData = getIndicators()[editingName]
				if(freshData) then
					spawnSettingsCards(editingName, freshData)
					layoutList()
				end
			elseif(indicatorCount > 0) then
				local indicators = getIndicators()
				local firstName, firstData
				for iName, iData in next, indicators do
					if(not firstName) then firstName, firstData = iName, iData end
					if(iData.enabled ~= false) then
						firstName, firstData = iName, iData
						break
					end
				end
				if(firstName) then
					editingName = firstName
					spawnSettingsCards(firstName, firstData)
					layoutList()
				end
			end
		end)

		scroll._ownedPreview = F.Settings._auraPreview
		return scroll
	end,
})
