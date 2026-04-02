local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings = F.Settings or {}
F.Settings.Builders = F.Settings.Builders or {}

-- ============================================================
-- Layout constants
-- ============================================================
local ROW_HEIGHT       = 28
local MAX_VISIBLE_ROWS = 5
local BUTTON_H         = 24
local DROPDOWN_H       = 22
local PAD_H            = 6

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
-- Main Builder
-- ============================================================

--- Create the Debuff Indicator CRUD UI.
--- @param parent Frame  The content frame to build into
--- @param width number  Available width
--- @param yOffset number  Starting Y offset
--- @param opts table  { unitType }
--- @return number yOffset  The final yOffset after all widgets
function F.Settings.Builders.DebuffIndicatorCRUD(parent, width, yOffset, opts)
	local getIndicators, setIndicator, removeIndicator = makeConfigHelpers(opts.unitType)

	local editingName = nil
	local listRowPool = {}

	-- ── Create section ─────────────────────────────────────
	local createHeading, createHeadingH = Widgets.CreateHeading(parent, 'Add Debuff Indicator', 2)
	createHeading:ClearAllPoints()
	Widgets.SetPoint(createHeading, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - createHeadingH

	local createCard, createInner, createY = Widgets.StartCard(parent, width, yOffset)

	local selectedFilter = 'all'

	local filterDD = Widgets.CreateDropdown(createInner, 140)
	filterDD:SetItems(FILTER_MODE_ITEMS)
	filterDD:SetValue('all')
	filterDD:SetOnSelect(function(v) selectedFilter = v end)
	filterDD:ClearAllPoints()
	Widgets.SetPoint(filterDD, 'TOPLEFT', createInner, 'TOPLEFT', 0, createY)

	local nameBox = Widgets.CreateEditBox(createInner, nil, 140, BUTTON_H)
	nameBox:ClearAllPoints()
	Widgets.SetPoint(nameBox, 'LEFT', filterDD, 'RIGHT', C.Spacing.tight, 0)
	nameBox:SetPlaceholder('Indicator name')

	local createBtn = Widgets.CreateButton(createInner, 'Create', 'accent', 60, BUTTON_H)
	createBtn:SetPoint('LEFT', nameBox, 'RIGHT', C.Spacing.tight, 0)
	createY = createY - BUTTON_H - C.Spacing.normal

	yOffset = Widgets.EndCard(createCard, parent, createY)

	-- ── Indicator list section ─────────────────────────────
	local listHeading, listHeadingH = Widgets.CreateHeading(parent, 'Debuff Indicators', 2)
	listHeading:ClearAllPoints()
	Widgets.SetPoint(listHeading, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - listHeadingH

	local listScroll = Widgets.CreateScrollFrame(parent, nil, width, MAX_VISIBLE_ROWS * ROW_HEIGHT)
	listScroll:ClearAllPoints()
	Widgets.SetPoint(listScroll, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	Widgets.SetSize(listScroll, width, MAX_VISIBLE_ROWS * ROW_HEIGHT)
	local listContent = listScroll:GetContentFrame()
	listContent:SetWidth(width)

	yOffset = yOffset - MAX_VISIBLE_ROWS * ROW_HEIGHT - C.Spacing.normal

	-- ── Settings section (shown when editing an indicator) ──
	local settingsHeading, settingsHeadingH = Widgets.CreateHeading(parent, 'Indicator Settings', 2)
	settingsHeading:ClearAllPoints()
	Widgets.SetPoint(settingsHeading, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	settingsHeading:Hide()

	local settingsContainer = CreateFrame('Frame', nil, parent)
	settingsContainer:ClearAllPoints()
	Widgets.SetPoint(settingsContainer, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset - settingsHeadingH)
	settingsContainer:SetWidth(width)
	settingsContainer:Hide()

	-- ── Layout list ────────────────────────────────────────

	local function layoutList()
		local indicators = getIndicators()

		-- Hide all rows first
		for _, row in next, listRowPool do
			row:Hide()
		end

		local rowIdx = 0
		local listY = 0
		for name, indConfig in next, indicators do
			rowIdx = rowIdx + 1

			if(not listRowPool[rowIdx]) then
				listRowPool[rowIdx] = createListRow(listContent)
			end

			local row = listRowPool[rowIdx]
			row:ClearAllPoints()
			row:SetPoint('TOPLEFT', listContent, 'TOPLEFT', 0, listY)
			row:SetPoint('RIGHT', listContent, 'RIGHT', 0, 0)

			row.__nameFS:SetText(name)
			row.__filterFS:SetText(FILTER_MODE_LABELS[indConfig.filterMode] or indConfig.filterMode or 'All')
			row.__enabledCB:SetChecked(indConfig.enabled ~= false)

			row.__onEnabledChanged = function(checked)
				indConfig.enabled = checked
				setIndicator(name, indConfig)
			end

			row.__editBtn:SetScript('OnClick', function()
				editingName = name

				-- Clear and rebuild settings container children
				for _, child in next, { settingsContainer:GetChildren() } do
					child:Hide()
					child:ClearAllPoints()
				end

				settingsHeading:Show()
				settingsHeading:SetText('Editing: ' .. name)
				settingsContainer:Show()

				-- Use BorderIconSettings with the indicator-specific config path
				local configKey = 'debuffs.indicators.' .. name
				local settingsY = 0
				settingsY = F.Settings.Builders.BorderIconSettings(settingsContainer, width, settingsY, {
					unitType            = opts.unitType,
					configKey           = configKey,
					showDispellableByMe = true,
					showBigIconSize     = true,
				})

				local settingsH = math.abs(settingsY) + C.Spacing.normal
				settingsContainer:SetHeight(settingsH)

				-- Update parent scroll frame content height
				if(opts.scrollFrame and opts.contentFrame) then
					local settingsBottom = math.abs(yOffset) + settingsHeadingH + settingsH + C.Spacing.normal
					opts.contentFrame:SetHeight(settingsBottom)
					opts.scrollFrame:UpdateScrollRange()
				end
			end)

			row.__deleteBtn:SetScript('OnClick', function()
				removeIndicator(name)
				if(editingName == name) then
					editingName = nil
					settingsHeading:Hide()
					settingsContainer:Hide()
				end
				layoutList()
			end)

			row:Show()
			listY = listY - ROW_HEIGHT
		end

		listContent:SetHeight(math.max(math.abs(listY), 1))
		listScroll:UpdateScrollRange()
	end

	-- ── Create button handler ──────────────────────────────

	createBtn:SetScript('OnClick', function()
		local name = nameBox:GetText()
		if(not name or name == '') then return end

		-- Check uniqueness
		local indicators = getIndicators()
		if(indicators[name]) then return end

		local newIndicator = {
			enabled      = true,
			filterMode   = selectedFilter,
			iconSize     = 14,
			bigIconSize  = 18,
			maxDisplayed = 3,
			showDuration = true,
			showAnimation = true,
			orientation  = 'RIGHT',
			anchor       = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
			frameLevel   = 5,
		}

		setIndicator(name, newIndicator)
		nameBox:SetText('')
		layoutList()
	end)

	-- Initial layout
	layoutList()

	-- Return yOffset for the static layout (settings area expands dynamically)
	return yOffset
end
