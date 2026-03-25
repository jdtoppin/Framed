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
		local layoutName = F.Settings.GetEditingLayout()
		return 'layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. configKey .. '.indicators'
	end

	local function getIndicators()
		if(not F.Config) then return {} end
		return F.Config:Get(basePath()) or {}
	end

	local function fireChange()
		if(not F.EventBus) then return end
		local layoutName = F.Settings.GetEditingLayout()
		F.EventBus:Fire('CONFIG_CHANGED', 'layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. configKey)
	end

	local function setIndicator(name, data)
		if(not F.Config) then return end
		F.Config:Set(basePath() .. '.' .. name, data)
		fireChange()
	end

	local function removeIndicator(name)
		if(not F.Config) then return end
		F.Config:Set(basePath() .. '.' .. name, nil)
		fireChange()
	end

	return getIndicators, setIndicator, removeIndicator
end

-- ============================================================
-- Spell name helper
-- ============================================================
local function getSpellName(spellID)
	if(C_Spell and C_Spell.GetSpellInfo) then
		local info = C_Spell.GetSpellInfo(spellID)
		if(info) then return info.name end
	elseif(GetSpellInfo) then
		local name = GetSpellInfo(spellID)
		if(name) then return name end
	end
	return 'Spell ' .. spellID
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
				local label = getSpellName(spellID) .. '  (' .. spellID .. ')'
				local cb = Widgets.CreateCheckButton(content, label, function() end)
				cb:SetChecked(true)
				cb:ClearAllPoints()
				Widgets.SetPoint(cb, 'TOPLEFT', content, 'TOPLEFT', 8, yOff)
				yOff = yOff - CHECK_H
				table.insert(frame.__checkboxes, { checkbox = cb, spellID = spellID })
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
			if(e.checkbox:GetChecked()) then table.insert(selected, e.spellID) end
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
		{ text = 'Frame Bar', value = C.IndicatorType.FRAME_BAR },
		{ text = 'Bar',       value = C.IndicatorType.BAR },
		{ text = 'Border',    value = C.IndicatorType.BORDER },
		{ text = 'Color',     value = C.IndicatorType.COLOR },
		{ text = 'Overlay',   value = C.IndicatorType.OVERLAY },
		{ text = 'Glow',      value = C.IndicatorType.GLOW },
	}
end

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

	-- Enabled checkbox — callback is updated dynamically via row.__onEnabledChanged
	row.__onEnabledChanged = nil
	local enabledCB = Widgets.CreateCheckButton(row, '', function(checked)
		if(row.__onEnabledChanged) then row.__onEnabledChanged(checked) end
	end)
	row.__enabledCB = enabledCB

	local editBtn = Widgets.CreateButton(row, 'Edit', 'widget', 40, 20)
	row.__editBtn = editBtn
	local deleteBtn = Widgets.CreateButton(row, 'Del', 'red', 36, 20)
	row.__deleteBtn = deleteBtn

	-- Anchoring: [name] [type] ... [enabled] [delete] [edit]
	editBtn:SetPoint('RIGHT', row, 'RIGHT', -PAD_H, 0)
	deleteBtn:SetPoint('RIGHT', editBtn, 'LEFT', -C.Spacing.base, 0)
	enabledCB:ClearAllPoints()
	Widgets.SetPoint(enabledCB, 'RIGHT', deleteBtn, 'LEFT', -C.Spacing.base, 0)
	typeFS:SetPoint('RIGHT', enabledCB, 'LEFT', -C.Spacing.tight, 0)

	row:EnableMouse(true)
	row:SetScript('OnEnter', function(self) Widgets.SetBackdropHighlight(self, true) end)
	row:SetScript('OnLeave', function(self) Widgets.SetBackdropHighlight(self, false) end)
	return row
end

-- ============================================================
-- Build type-specific indicator settings
-- ============================================================
local function buildIndicatorSettings(parent, width, yOffset, name, data, setIndicator)
	local function update(key, value)
		data[key] = value
		setIndicator(name, data)
	end

	-- ── General card ──────────────────────────────────────
	local genCard, genInner, genY = Widgets.StartCard(parent, width, yOffset)

	local enCB = Widgets.CreateCheckButton(genInner, 'Enabled', function(checked) update('enabled', checked) end)
	enCB:SetChecked(data.enabled ~= false)
	genY = placeWidget(enCB, genInner, genY, CHECK_H)

	yOffset = Widgets.EndCard(genCard, parent, genY)

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

	yOffset = Widgets.EndCard(spCard, parent, spY)

	-- ── Type-specific settings card ───────────────────────
	local iType = data.type

	if(iType == C.IndicatorType.ICONS or iType == C.IndicatorType.ICON) then
		yOffset = placeHeading(parent, 'Display Settings', 2, yOffset)
		local dispCard, dispInner, dispY = Widgets.StartCard(parent, width, yOffset)

		local sz = Widgets.CreateSlider(dispInner, 'Icon Size', WIDGET_W, 8, 48, 1)
		sz:SetValue(data.iconSize or 16)
		sz:SetAfterValueChanged(function(v) update('iconSize', v) end)
		dispY = placeWidget(sz, dispInner, dispY, SLIDER_H)

		if(iType == C.IndicatorType.ICONS) then
			local mx = Widgets.CreateSlider(dispInner, 'Max Displayed', WIDGET_W, 1, 10, 1)
			mx:SetValue(data.maxDisplayed or 3)
			mx:SetAfterValueChanged(function(v) update('maxDisplayed', v) end)
			dispY = placeWidget(mx, dispInner, dispY, SLIDER_H)

			local ori = Widgets.CreateDropdown(dispInner, WIDGET_W)
			ori:SetItems({
				{ text = 'Right', value = 'RIGHT' }, { text = 'Left', value = 'LEFT' },
				{ text = 'Up', value = 'UP' }, { text = 'Down', value = 'DOWN' },
			})
			ori:SetValue(data.orientation or 'RIGHT')
			ori:SetOnSelect(function(v) update('orientation', v) end)
			dispY = placeWidget(ori, dispInner, dispY, DROPDOWN_H)
		end

		yOffset = Widgets.EndCard(dispCard, parent, dispY)

	elseif(iType == C.IndicatorType.GLOW) then
		yOffset = placeHeading(parent, 'Glow Settings', 2, yOffset)
		local glowCard, glowInner, glowY = Widgets.StartCard(parent, width, yOffset)

		local gdd = Widgets.CreateDropdown(glowInner, WIDGET_W)
		gdd:SetItems({
			{ text = 'Proc', value = C.GlowType.PROC }, { text = 'Pixel', value = C.GlowType.PIXEL },
			{ text = 'Soft', value = C.GlowType.SOFT }, { text = 'Shine', value = C.GlowType.SHINE },
		})
		gdd:SetValue(data.glowType or C.GlowType.PROC)
		gdd:SetOnSelect(function(v) update('glowType', v) end)
		glowY = placeWidget(gdd, glowInner, glowY, DROPDOWN_H)

		yOffset = Widgets.EndCard(glowCard, parent, glowY)

	elseif(iType == C.IndicatorType.BAR or iType == C.IndicatorType.FRAME_BAR) then
		yOffset = placeHeading(parent, 'Bar Settings', 2, yOffset)
		local barCard, barInner, barY = Widgets.StartCard(parent, width, yOffset)

		local bh = Widgets.CreateSlider(barInner, 'Bar Height', WIDGET_W, 2, 20, 1)
		bh:SetValue(data.barHeight or 4)
		bh:SetAfterValueChanged(function(v) update('barHeight', v) end)
		barY = placeWidget(bh, barInner, barY, SLIDER_H)

		yOffset = Widgets.EndCard(barCard, parent, barY)
	end

	-- ── Position card ─────────────────────────────────────
	if(Widgets.CreateAnchorPicker) then
		yOffset = placeHeading(parent, 'Position', 2, yOffset)
		local posCard, posInner, posY = Widgets.StartCard(parent, width, yOffset)

		local anch = data.anchor or { 'TOPLEFT', nil, 'TOPLEFT', 0, 0 }
		local pick = Widgets.CreateAnchorPicker(posInner, width - 24)
		pick:SetAnchor(anch[1], anch[4] or 0, anch[5] or 0)
		posY = placeWidget(pick, posInner, posY, pick:GetHeight())
		pick:SetOnChanged(function(pt, x, y) update('anchor', { pt, nil, pt, x, y }) end)

		yOffset = Widgets.EndCard(posCard, parent, posY)
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

	-- Import button
	local importBtn = Widgets.CreateButton(createInner, 'Import Healer Spells', 'widget', 160, BUTTON_H)
	createY = placeWidget(importBtn, createInner, createY, BUTTON_H)

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
			data.iconSize = 16; data.maxDisplayed = 3; data.orientation = 'RIGHT'
		elseif(iType == C.IndicatorType.ICON) then
			data.iconSize = 16
		elseif(iType == C.IndicatorType.GLOW) then
			data.glowType = C.GlowType.PROC
		elseif(iType == C.IndicatorType.BAR or iType == C.IndicatorType.FRAME_BAR) then
			data.barHeight = 4
		end

		setIndicator(iName, data)
		nameBox:SetText('')
		layoutList()
	end

	createBtn:SetOnClick(doCreate)
	nameBox:SetOnEnterPressed(doCreate)

	-- ── Import handler ─────────────────────────────────────
	importBtn:SetOnClick(function()
		ShowImportPopup(function(selectedSpells)
			if(not selectedSpells or #selectedSpells == 0) then return end
			local indicators = getIndicators()
			local name = 'Healer Spells'
			local n = 1
			while(indicators[name]) do n = n + 1; name = 'Healer Spells ' .. n end

			setIndicator(name, {
				type         = C.IndicatorType.ICONS,
				enabled      = true,
				spells       = selectedSpells,
				iconSize     = 16,
				maxDisplayed = 3,
				orientation  = 'RIGHT',
			})
			layoutList()
		end)
	end)

	-- Initial layout
	layoutList()

	return yOffset
end
