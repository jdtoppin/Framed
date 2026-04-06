local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================
local ROW_HEIGHT       = 28
local MAX_VISIBLE_ROWS = 7
local LIST_HEIGHT      = MAX_VISIBLE_ROWS * ROW_HEIGHT
local BUTTON_H         = 24
local DROPDOWN_H       = 22
local SLIDER_H         = 26
local CHECK_H          = 22
local PAD_H            = 6
local WIDGET_W         = 220

-- ============================================================
-- Filter mode items
-- ============================================================
local FILTER_MODE_ITEMS = {
	{ text = 'All Debuffs',      value = 'all' },
	{ text = 'Raid-Relevant',    value = 'raid' },
	{ text = 'Important',        value = 'important' },
	{ text = 'Dispellable',      value = 'dispellable' },
	{ text = 'Raid (In-Combat)', value = 'raidCombat' },
	{ text = 'Encounter Only',   value = 'encounter' },
}

local FILTER_MODE_LABELS = {}
for _, item in next, FILTER_MODE_ITEMS do
	FILTER_MODE_LABELS[item.value] = item.text
end

-- ============================================================
-- Config helpers
-- ============================================================
local function makeConfigHelpers(unitType)
	local function basePath()
		local presetName = F.Settings.GetEditingPreset()
		return 'presets.' .. presetName .. '.auras.' .. unitType .. '.debuffs.indicators'
	end

	local function getIndicators()
		if(not F.Config) then return {} end
		return F.Config:Get(basePath()) or {}
	end

	local function fireChange()
		if(not F.EventBus) then return end
		local presetName = F.Settings.GetEditingPreset()
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.debuffs')
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
	nameFS:SetWidth(120)
	row.__nameFS = nameFS

	-- "Editing: name" overlay
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

	local filterFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
	filterFS:SetJustifyH('LEFT')
	row.__filterFS = filterFS

	-- Enabled toggle
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

	-- Anchoring: [name] [filter] ... [enabled] [delete] [edit]
	editBtn:SetPoint('RIGHT', row, 'RIGHT', -PAD_H, 0)
	deleteBtn:SetPoint('RIGHT', editBtn, 'LEFT', -C.Spacing.base, 0)
	enabledCB:ClearAllPoints()
	Widgets.SetPoint(enabledCB, 'RIGHT', deleteBtn, 'LEFT', -C.Spacing.base, 0)
	filterFS:SetPoint('RIGHT', enabledCB, 'LEFT', -C.Spacing.tight, 0)

	-- Row highlight
	row:EnableMouse(true)
	row:SetScript('OnEnter', function(self) Widgets.SetBackdropHighlight(self, true) end)
	row:SetScript('OnLeave', function(self)
		if(self:IsMouseOver()) then return end
		Widgets.SetBackdropHighlight(self, false)
	end)

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
-- Card builders for debuff indicator settings
-- Each follows CardGrid builder signature:
--   function(parent, width, data, update, get, set, rebuildPanel)
-- ============================================================

local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.tight
end

local function buildFilterModeCard(parent, width, data, update, get, set)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	local filterDD = Widgets.CreateDropdown(inner, WIDGET_W)
	filterDD:SetItems(FILTER_MODE_ITEMS)
	filterDD:SetValue(get('filterMode') or 'all')
	filterDD:SetOnSelect(function(v) update('filterMode', v) end)
	cy = placeWidget(filterDD, inner, cy, DROPDOWN_H)

	return Widgets.EndCard(card, parent, cy)
end

local function buildDisplaySettingsCard(parent, width, data, update, get, set)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	-- Icon Size
	local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', WIDGET_W, 8, 48, 1)
	sizeSlider:SetValue(get('iconSize') or 16)
	sizeSlider:SetAfterValueChanged(function(v) update('iconSize', v) end)
	cy = placeWidget(sizeSlider, inner, cy, SLIDER_H)

	-- Big Icon Size
	local bigSlider = Widgets.CreateSlider(inner, 'Big Icon Size', WIDGET_W, 8, 64, 1)
	bigSlider:SetValue(get('bigIconSize') or 22)
	bigSlider:SetAfterValueChanged(function(v) update('bigIconSize', v) end)
	cy = placeWidget(bigSlider, inner, cy, SLIDER_H)

	-- Max Displayed
	local maxSlider = Widgets.CreateSlider(inner, 'Max Displayed', WIDGET_W, 1, 20, 1)
	maxSlider:SetValue(get('maxDisplayed') or 3)
	maxSlider:SetAfterValueChanged(function(v) update('maxDisplayed', v) end)
	cy = placeWidget(maxSlider, inner, cy, SLIDER_H)

	-- Show Duration
	local durCheck = Widgets.CreateCheckButton(inner, 'Show Duration', function(checked)
		update('showDuration', checked)
	end)
	durCheck:SetChecked(get('showDuration') ~= false)
	cy = placeWidget(durCheck, inner, cy, CHECK_H)

	-- Show Animation
	local animCheck = Widgets.CreateCheckButton(inner, 'Show Animation', function(checked)
		update('showAnimation', checked)
	end)
	animCheck:SetChecked(get('showAnimation') ~= false)
	cy = placeWidget(animCheck, inner, cy, CHECK_H)

	-- Orientation
	local oriDD = Widgets.CreateDropdown(inner, WIDGET_W)
	oriDD:SetItems({
		{ text = 'Right', value = 'RIGHT' },
		{ text = 'Left',  value = 'LEFT' },
		{ text = 'Up',    value = 'UP' },
		{ text = 'Down',  value = 'DOWN' },
	})
	oriDD:SetValue(get('orientation') or 'RIGHT')
	oriDD:SetOnSelect(function(v) update('orientation', v) end)
	cy = placeWidget(oriDD, inner, cy, DROPDOWN_H)

	return Widgets.EndCard(card, parent, cy)
end

local function buildPositionCard(parent, width, data, update, get, set)
	local wrapper = CreateFrame('Frame', nil, parent)
	wrapper:SetWidth(width)
	local yOff = F.Settings.BuildPositionCard(wrapper, width, 0, get, set)
	wrapper:SetHeight(math.abs(yOff))
	return wrapper
end

local function buildDurationFontCard(parent, width, data, update, get, set)
	local wrapper = CreateFrame('Frame', nil, parent)
	wrapper:SetWidth(width)
	local yOff = F.Settings.BuildFontCard(wrapper, width, 0, 'Duration Text Font', 'durationFont', get, set, { showAnchor = true })
	wrapper:SetHeight(math.abs(yOff))
	return wrapper
end

local function buildStackFontCard(parent, width, data, update, get, set)
	local wrapper = CreateFrame('Frame', nil, parent)
	wrapper:SetWidth(width)
	local yOff = F.Settings.BuildFontCard(wrapper, width, 0, 'Stack Count Font', 'stackFont', get, set, { showAnchor = true })
	wrapper:SetHeight(math.abs(yOff))
	return wrapper
end

-- ============================================================
-- Panel Registration
-- ============================================================

F.Settings.RegisterPanel({
	id         = 'debuffs',
	label      = 'Debuffs',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 12,
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
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'debuffs', 'debuffs')

		-- ── Pinned row: Create card + Indicator List card ────────
		local CARD_GAP    = C.Spacing.normal
		local createCardW = math.floor((width - CARD_GAP) * 0.35)
		local listCardW   = width - createCardW - CARD_GAP
		local pinnedRowY  = yOffset

		-- ── Create card ──────────────────────────────────────────
		local selectedFilter = 'all'

		local createCard, createInner, createY = Widgets.StartCard(content, createCardW, pinnedRowY)

		-- Filter mode dropdown
		local filterDD = Widgets.CreateDropdown(createInner, createCardW - Widgets.CARD_PADDING * 2)
		filterDD:SetItems(FILTER_MODE_ITEMS)
		filterDD:SetValue('all')
		filterDD:SetOnSelect(function(v) selectedFilter = v end)
		filterDD:ClearAllPoints()
		Widgets.SetPoint(filterDD, 'TOPLEFT', createInner, 'TOPLEFT', 0, createY)
		createY = createY - DROPDOWN_H - C.Spacing.tight

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
		local listCard, listInner, listY = Widgets.StartCard(content, listCardW, pinnedRowY)
		listCard:ClearAllPoints()
		Widgets.SetPoint(listCard, 'TOPLEFT', content, 'TOPLEFT', createCardW + CARD_GAP, pinnedRowY)
		listCard._startY = pinnedRowY

		local listWidgetW = listCardW - Widgets.CARD_PADDING * 2
		local listScroll = Widgets.CreateScrollFrame(listInner, nil, listWidgetW, LIST_HEIGHT)
		listScroll:ClearAllPoints()
		Widgets.SetPoint(listScroll, 'TOPLEFT', listInner, 'TOPLEFT', 0, listY)
		listY = listY - LIST_HEIGHT
		local listContent = listScroll:GetContentFrame()

		local emptyLabel = Widgets.CreateFontString(listScroll, C.Font.sizeNormal, C.Colors.textSecondary)
		emptyLabel:SetPoint('CENTER', listScroll, 'CENTER', 0, 0)
		emptyLabel:SetText('No indicators configured')

		Widgets.EndCard(listCard, content, listY)

		-- Calculate combined pinned row height (tallest of the two cards)
		local createCardH = createCard:GetHeight()
		local listCardH   = listCard:GetHeight()
		local pinnedRowH  = math.max(createCardH, listCardH)
		yOffset = pinnedRowY - pinnedRowH - C.Spacing.normal

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

			local function update(key, value)
				iData[key] = value
				setIndicator(iName, iData)
			end
			local function get(key) return iData[key] end
			local function set(key, value) update(key, value) end

			grid:AddCard('filterMode',      'Filter Mode',      buildFilterModeCard,      { iData, update, get, set })
			grid:AddCard('displaySettings', 'Display Settings', buildDisplaySettingsCard, { iData, update, get, set })
			grid:AddCard('position',        'Position',         buildPositionCard,        { iData, update, get, set })
			grid:AddCard('durationFont',    nil,                buildDurationFontCard,    { iData, update, get, set })
			grid:AddCard('stackFont',       nil,                buildStackFontCard,       { iData, update, get, set })

			grid:Layout(0, parentH)
			content:SetHeight(grid:GetTotalHeight())
			scroll:UpdateScrollRange()

			-- Update breadcrumb and preview dimming
			F.Settings.UpdateAuraBreadcrumb('Debuffs', iName)
			F.Settings.UpdateAuraPreviewDimming('debuffs', iName)
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
			F.Settings.UpdateAuraBreadcrumb('Debuffs', nil)
			F.Settings.UpdateAuraPreviewDimming('debuffs', nil)
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
				row.__filterFS:SetText(FILTER_MODE_LABELS[iData.filterMode] or iData.filterMode or 'All')
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
			local listH = math.min(LIST_HEIGHT, math.max(ROW_HEIGHT, indicatorCount * ROW_HEIGHT))
			listScroll:SetHeight(listH)
			listScroll:UpdateScrollRange()
		end

		-- ── Create handler ───────────────────────────────────────
		local function doCreate()
			local iName = nameBox:GetText()
			if(not iName or iName == '') then return end
			local indicators = getIndicators()
			if(indicators[iName]) then return end

			local data = {
				enabled       = true,
				filterMode    = selectedFilter,
				iconSize      = 14,
				bigIconSize   = 18,
				maxDisplayed  = 3,
				showDuration  = true,
				showAnimation = true,
				orientation   = 'RIGHT',
				anchor        = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
				frameLevel    = 5,
				stackFont     = { size = 10, outline = 'OUTLINE', shadow = false,
				                  anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
				                  color = { 1, 1, 1, 1 } },
				durationFont  = { size = 10, outline = 'OUTLINE', shadow = false },
			}

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
		local resizeKey = 'Debuffs.resize.' .. unitType
		local function onResize(newW, newH)
			local newWidth = newW - C.Spacing.normal * 2
			local newCreateW = math.floor((newWidth - CARD_GAP) * 0.35)
			local newListW   = newWidth - newCreateW - CARD_GAP

			createCard:SetWidth(newCreateW)
			listCard:SetWidth(newListW)
			listCard:ClearAllPoints()
			Widgets.SetPoint(listCard, 'TOPLEFT', content, 'TOPLEFT', newCreateW + CARD_GAP, pinnedRowY)

			grid:SetWidth(newWidth)
			content:SetWidth(newW)
			content:SetHeight(grid:GetTotalHeight())
		end

		F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)

		-- ── Cleanup on hide, re-register on show ─────────────────
		scroll:HookScript('OnHide', function()
			grid:CancelAnimations()
			F.EventBus:Unregister('SETTINGS_RESIZED', resizeKey)
		end)

		scroll:HookScript('OnShow', function()
			F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)
			grid:Layout(0, parentH, false)
			content:SetHeight(grid:GetTotalHeight())
		end)

		return scroll
	end,
})
