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
		local CARD_GAP     = C.Spacing.normal
		local previewCardW = math.floor((width - CARD_GAP) * 0.40)
		local listCardW    = width - previewCardW - CARD_GAP
		local pinnedRowY   = yOffset

		-- ── Preview card ─────────────────────────────────────────
		local previewCard = F.Settings.AuraPreview.BuildPreviewCard(content, previewCardW)
		previewCard:ClearAllPoints()
		Widgets.SetPoint(previewCard, 'TOPLEFT', content, 'TOPLEFT', 0, pinnedRowY)
		local previewAccentBar = Widgets.CreateAccentBar(previewCard)
		local previewCardH = previewCard:GetHeight()

		-- ── Indicator List card ──────────────────────────────────
		-- List card height matches the preview card height
		local leftColumnH = previewCardH
		local listScrollH = leftColumnH - Widgets.CARD_PADDING * 2

		local listCard, listInner, listY = Widgets.StartCard(content, listCardW, pinnedRowY)
		listCard:ClearAllPoints()
		Widgets.SetPoint(listCard, 'TOPLEFT', content, 'TOPLEFT', previewCardW + CARD_GAP, pinnedRowY)
		listCard._startY = pinnedRowY
		Widgets.CreateAccentBar(listCard)

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
			local newWidth    = newW - C.Spacing.normal * 2
			local newPreviewW = math.floor((newWidth - CARD_GAP) * 0.40)
			local newListW    = newWidth - newPreviewW - CARD_GAP
			local newListInnerW = newListW - Widgets.CARD_PADDING * 2

			previewCard:SetWidth(newPreviewW)
			listCard:SetWidth(newListW)
			listCard:ClearAllPoints()
			Widgets.SetPoint(listCard, 'TOPLEFT', content, 'TOPLEFT', newPreviewW + CARD_GAP, pinnedRowY)

			-- Preview frame max width
			local preview = F.Settings._auraPreview
			if(preview) then
				preview._maxWidth = newPreviewW - Widgets.CARD_PADDING * 2
			end

			-- List card inner scroll (content width auto-updates via OnSizeChanged)
			listScroll:SetWidth(newListInnerW)

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
			grid:Layout(0, parentH, false)
			content:SetHeight(grid:GetTotalHeight())
		end)

		scroll._ownedPreview = F.Settings._auraPreview
		return scroll
	end,
})
