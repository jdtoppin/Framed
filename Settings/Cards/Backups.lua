local _, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.BackupsCards = F.BackupsCards or {}

-- ── Layout constants ───────────────────────────────────────
local DROPDOWN_H = 22
local BUTTON_H   = 22
local EDITBOX_H  = 80
local LABEL_H    = C.Font.sizeSmall + 4

local SNAPSHOT_ROW_H   = 52
local EMPTY_STATE_H    = 60

local SCOPE_FULL   = 'full'
local SCOPE_LAYOUT = 'layout'

-- ============================================================
-- Verification: flattened key-set derivation from current defaults
-- ============================================================

local flattenedDefaults

local function flattenInto(set, prefix, tbl)
	for k, v in next, tbl do
		local path = prefix == '' and tostring(k) or (prefix .. '.' .. tostring(k))
		if(type(v) == 'table') then
			flattenInto(set, path, v)
		else
			set[path] = true
		end
	end
end

local function buildFlattenedDefaults()
	local set = {}

	if(FramedDB and FramedDB.general) then flattenInto(set, 'general', FramedDB.general) end
	if(FramedDB and FramedDB.minimap) then flattenInto(set, 'minimap', FramedDB.minimap) end
	if(FramedCharDB)                  then flattenInto(set, 'char',    FramedCharDB)     end

	if(F.PresetDefaults and F.PresetDefaults.GetAll) then
		local all = F.PresetDefaults.GetAll()
		local anyPreset = all and next(all) and all[next(all)]
		if(anyPreset) then
			flattenInto(set, 'presets.<name>', anyPreset)
		end
	end

	return set
end

local function getFlattenedDefaults()
	if(not flattenedDefaults) then
		flattenedDefaults = buildFlattenedDefaults()
	end
	return flattenedDefaults
end

local function classifyImportKeys(parsed)
	local defaults = getFlattenedDefaults()
	local importSet = {}
	if(parsed.scope == 'full' and type(parsed.data) == 'table') then
		if(parsed.data.general) then flattenInto(importSet, 'general', parsed.data.general) end
		if(parsed.data.minimap) then flattenInto(importSet, 'minimap', parsed.data.minimap) end
		if(parsed.data.char)    then flattenInto(importSet, 'char',    parsed.data.char)    end
		if(parsed.data.presets) then
			local _, firstLayout = next(parsed.data.presets)
			if(firstLayout) then
				flattenInto(importSet, 'presets.<name>', firstLayout)
			end
		end
	elseif(parsed.scope == 'layout' and parsed.data and parsed.data.layout) then
		flattenInto(importSet, 'presets.<name>', parsed.data.layout)
	end

	local ignored, missing = {}, {}
	for path in next, importSet do
		if(not defaults[path]) then ignored[#ignored + 1] = path end
	end
	for path in next, defaults do
		if(not importSet[path]) then missing[#missing + 1] = path end
	end
	table.sort(ignored)
	table.sort(missing)
	return ignored, missing
end

-- ── Helpers ────────────────────────────────────────────────

local function getLayoutItems()
	local names = (F.PresetManager and F.PresetManager.GetNames)
		and F.PresetManager.GetNames() or {}
	local items = {}
	for _, name in next, names do
		items[#items + 1] = { text = name, value = name }
	end
	if(#items == 0) then
		for _, name in next, {
			'Solo', 'Party', 'Raid',
			'Mythic Raid', 'World Raid',
			'Battleground', 'Arena',
		} do
			items[#items + 1] = { text = name, value = name }
		end
	end
	return items
end

local function setTextColor(fs, colorTable)
	fs:SetTextColor(
		colorTable[1], colorTable[2], colorTable[3], colorTable[4] or 1)
end

local function createLabel(inner, text)
	local fs = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	fs:SetText(text)
	return fs
end

local function placeLabelAt(fs, inner, y)
	fs:ClearAllPoints()
	Widgets.SetPoint(fs, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
	return y - LABEL_H
end

-- ============================================================
-- Inline input flows (Save Current As / Import as Snapshot)
-- ============================================================

local function createInlineNameInput(parent, width, placeholderText, defaultName)
	local INPUT_H = 22
	local container = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(container, width, INPUT_H + LABEL_H + BUTTON_H + 12)

	local input = Widgets.CreateEditBox(container, nil, width, 22)
	input:SetPlaceholder(placeholderText or '')
	input:SetText(defaultName or '')
	input:ClearAllPoints()
	Widgets.SetPoint(input, 'TOPLEFT', container, 'TOPLEFT', 0, 0)

	local errorFS = Widgets.CreateFontString(container, C.Font.sizeSmall, C.Colors.textSecondary)
	errorFS:ClearAllPoints()
	Widgets.SetPoint(errorFS, 'TOPLEFT', input, 'BOTTOMLEFT', 0, -4)
	errorFS:SetWidth(width)
	errorFS:SetWordWrap(true)
	errorFS:SetJustifyH('LEFT')
	errorFS:SetText('')

	local confirmBtn = Widgets.CreateButton(container, 'Save',   'accent',    80, BUTTON_H)
	local cancelBtn  = Widgets.CreateButton(container, 'Cancel', 'secondary', 80, BUTTON_H)

	confirmBtn:ClearAllPoints()
	Widgets.SetPoint(confirmBtn, 'TOPLEFT', errorFS, 'BOTTOMLEFT', 0, -4)

	cancelBtn:ClearAllPoints()
	Widgets.SetPoint(cancelBtn, 'LEFT', confirmBtn, 'RIGHT', 6, 0)

	local function setError(msg)
		if(msg and msg ~= '') then
			errorFS:SetTextColor(1, 0.3, 0.3, 1)
			errorFS:SetText(msg)
			confirmBtn:SetEnabled(false)
		else
			errorFS:SetText('')
			confirmBtn:SetEnabled(true)
		end
	end

	local validateTimer
	local function scheduleValidate(validator)
		if(validateTimer) then validateTimer:Cancel() end
		validateTimer = C_Timer.NewTimer(0.15, function()
			local name = F.Backups.TrimName(input:GetText() or '')
			local ok, err = validator(name)
			setError(ok and nil or err)
		end)
	end

	container._input            = input
	container._confirmBtn       = confirmBtn
	container._cancelBtn        = cancelBtn
	container._setError         = setError
	container._scheduleValidate = scheduleValidate

	return container, input, confirmBtn, cancelBtn
end

-- ============================================================
-- Row rendering helpers
-- ============================================================

local function guardCombat()
	if(InCombatLockdown()) then
		Widgets.ShowToast({
			text     = "Can't load snapshots in combat.",
			duration = 4,
		})
		return false
	end
	return true
end

local function formatTimestamp(ts)
	if(not ts) then return '—' end
	return date('%Y-%m-%d %H:%M', ts)
end

local function buildMetadataParts(wrapper)
	local version = wrapper.version or 'unknown'
	local ts      = formatTimestamp(wrapper.timestamp)
	local count   = wrapper.layoutCount or 0
	local size    = wrapper.sizeBytes   or 0
	local sizeStr = (size < 1024) and (size .. ' B') or string.format('%.1f KB', size / 1024)
	return {
		version = version,
		rest    = ' · ' .. ts .. ' · ' .. count .. ' layouts · ' .. sizeStr,
	}
end

local function createSnapshotRow(parent, width, wrapper, displayName, isAutomatic, relayout)
	local row = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(row, width, SNAPSHOT_ROW_H)
	Widgets.ApplyBackdrop(row, C.Colors.panel, C.Colors.border)

	row:EnableMouse(true)
	row:SetScript('OnEnter', function(self) Widgets.SetBackdropHighlight(self, true) end)
	row:SetScript('OnLeave', function(self)
		if(self:IsMouseOver()) then return end
		Widgets.SetBackdropHighlight(self, false)
	end)

	row._wrapper     = wrapper
	row._name        = displayName
	row._isAutomatic = isAutomatic

	local nameFS = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textActive)
	nameFS:SetPoint('TOPLEFT', row, 'TOPLEFT', 10, -8)
	nameFS:SetText(displayName)
	if(isAutomatic) then
		nameFS:SetTextColor(
			C.Colors.textSecondary[1],
			C.Colors.textSecondary[2],
			C.Colors.textSecondary[3],
			C.Colors.textSecondary[4] or 1)
	end
	row._nameFS = nameFS

	local parts = buildMetadataParts(wrapper)

	local versionFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
	versionFS:SetPoint('TOPLEFT', nameFS, 'BOTTOMLEFT', 0, -2)
	versionFS:SetText(parts.version)
	row._versionFS = versionFS

	local currentVersion = F.version or 'unknown'
	local isStaleOlder = F.Version and F.Version.IsStaleOlder(wrapper.version or 'unknown', currentVersion)
	local isStaleNewer = F.Version and F.Version.IsStaleNewer(wrapper.version or 'unknown', currentVersion)

	local indicator
	if(isStaleOlder or isStaleNewer) then
		versionFS:SetTextColor(1, 0.3, 0.3, 1)
		indicator = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
		indicator:SetPoint('LEFT', versionFS, 'RIGHT', 4, 0)
		indicator:SetText(' [!] ')
		indicator:SetTextColor(1, 0.3, 0.3, 1)

		local tooltipMsg
		if(isStaleOlder) then
			tooltipMsg = 'This snapshot was created with an older version of Framed. It may not restore cleanly.'
		else
			tooltipMsg = 'This snapshot was created with a newer version of Framed. Loading it may corrupt your config.'
		end
		Widgets.SetTooltip(indicator, 'Version warning', tooltipMsg)
	end

	local metaFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
	if(indicator) then
		metaFS:SetPoint('LEFT', indicator, 'RIGHT', 0, 0)
	else
		metaFS:SetPoint('LEFT', versionFS, 'RIGHT', 0, 0)
	end
	metaFS:SetText(parts.rest)
	row._metaFS = metaFS

	local BTN_W, BTN_H = 70, 22
	local PAD          = 4

	local btnLoad   = Widgets.CreateButton(row, 'Load',   'accent',    BTN_W, BTN_H)
	local btnExport = Widgets.CreateButton(row, 'Export', 'widget',    BTN_W, BTN_H)
	local btnRename = Widgets.CreateButton(row, 'Rename', 'widget',    BTN_W, BTN_H)
	local btnDelete = Widgets.CreateButton(row, 'Delete', 'red',       BTN_W, BTN_H)

	local BTN_TOP_OFFSET = -((SNAPSHOT_ROW_H - BTN_H) / 2)

	btnDelete:ClearAllPoints()
	Widgets.SetPoint(btnDelete, 'TOPRIGHT', row, 'TOPRIGHT', -10, BTN_TOP_OFFSET)

	btnRename:ClearAllPoints()
	Widgets.SetPoint(btnRename, 'RIGHT', btnDelete, 'LEFT', -PAD, 0)

	btnExport:ClearAllPoints()
	Widgets.SetPoint(btnExport, 'RIGHT', btnRename, 'LEFT', -PAD, 0)

	btnLoad:ClearAllPoints()
	Widgets.SetPoint(btnLoad, 'RIGHT', btnExport, 'LEFT', -PAD, 0)

	if(isAutomatic) then
		btnRename:Hide()
	end

	row._btnLoad   = btnLoad
	row._btnExport = btnExport
	row._btnRename = btnRename
	row._btnDelete = btnDelete

	for _, child in next, { btnLoad, btnExport, btnRename, btnDelete } do
		child:HookScript('OnEnter', function() Widgets.SetBackdropHighlight(row, true) end)
		child:HookScript('OnLeave', function()
			if(row:IsMouseOver()) then return end
			Widgets.SetBackdropHighlight(row, false)
		end)
	end

	btnLoad:SetOnClick(function()
		if(not guardCombat()) then return end

		local msg = 'Load snapshot "' .. displayName .. '"?\n\n' ..
			'Version: ' .. (wrapper.version or 'unknown') .. '\n' ..
			'Saved: ' .. formatTimestamp(wrapper.timestamp) .. '\n\n' ..
			'This will replace your current Framed settings. ' ..
			'Framed will automatically keep a "Before last load" backup so you can revert.'

		Widgets.ShowConfirmDialog(
			'Confirm Load',
			msg,
			function()
				local ok, err = F.Backups.Load(displayName)
				if(ok) then
					Widgets.ShowToast({
						text     = 'Snapshot loaded.',
						duration = 12,
						action   = {
							text    = 'Undo',
							onClick = function()
								F.Backups.Load(F.Backups.AUTO_PRELOAD)
							end,
						},
					})
				else
					Widgets.ShowToast({
						text     = 'Load failed: ' .. (err or 'unknown error'),
						duration = 6,
					})
					if(err and err:find('corrupted')) then
						row:MarkCorrupted()
					end
				end
			end,
			nil)
	end)

	btnDelete:SetOnClick(function()
		local removed = F.Backups.Delete(displayName)
		if(not removed) then return end

		Widgets.ShowToast({
			text     = 'Deleted ' .. displayName .. '.',
			duration = 10,
			action   = {
				text    = 'Undo',
				onClick = function()
					F.Backups.RestoreDeleted(displayName, removed)
				end,
			},
		})
	end)

	btnRename:SetOnClick(function()
		if(isAutomatic) then return end

		nameFS:Hide()

		local edit = Widgets.CreateEditBox(row, nil, 180, 22)
		edit:SetText(displayName)
		edit:ClearAllPoints()
		Widgets.SetPoint(edit, 'TOPLEFT', row, 'TOPLEFT', 8, -6)

		if(edit._editbox) then
			edit._editbox:SetFocus()
			edit._editbox:HighlightText()
			edit._editbox:SetScript('OnEscapePressed', function()
				edit:Hide()
				nameFS:Show()
			end)
			edit._editbox:SetScript('OnEnterPressed', function()
				local newName = F.Backups.TrimName(edit:GetText() or '')
				local ok, err = F.Backups.Rename(displayName, newName)
				if(ok) then
					edit:Hide()
				else
					Widgets.ShowToast({
						text     = 'Rename failed: ' .. (err or 'unknown error'),
						duration = 5,
					})
				end
			end)
		end
	end)

	btnExport:SetOnClick(function()
		local parsed, decodeErr = F.Backups.DecodeWrapper(wrapper)
		if(not parsed) then
			row:MarkCorrupted()
			Widgets.ShowToast({
				text     = 'This snapshot is corrupted and can\'t be exported.',
				duration = 5,
			})
			return
		end

		if(row._exportArea) then
			row._exportArea:Hide()
			row._exportArea = nil
			row:SetHeight(SNAPSHOT_ROW_H)
			if(relayout) then relayout() end
			return
		end

		local areaW = row:GetWidth() - 16
		local areaH = EDITBOX_H + DROPDOWN_H + 14
		local area = CreateFrame('Frame', nil, row)
		Widgets.SetSize(area, areaW, areaH)
		area:ClearAllPoints()
		Widgets.SetPoint(area, 'TOPLEFT', row, 'TOPLEFT', 8, -(SNAPSHOT_ROW_H - 4))
		row:SetHeight(SNAPSHOT_ROW_H + areaH + 4)

		local scopeDropdown = Widgets.CreateDropdown(area, 220)
		scopeDropdown:ClearAllPoints()
		Widgets.SetPoint(scopeDropdown, 'TOPLEFT', area, 'TOPLEFT', 0, 0)

		local items = { { text = 'Whole snapshot', value = '__whole__' } }
		if(parsed.scope == 'full' and type(parsed.data) == 'table' and type(parsed.data.presets) == 'table') then
			for layoutName in next, parsed.data.presets do
				items[#items + 1] = { text = layoutName, value = layoutName }
			end
		end
		scopeDropdown:SetItems(items)
		scopeDropdown:SetValue('__whole__')

		local copyBox = Widgets.CreateEditBox(area, nil, area:GetWidth(), EDITBOX_H, 'multiline')
		copyBox:ClearAllPoints()
		Widgets.SetPoint(copyBox, 'TOPLEFT', scopeDropdown, 'BOTTOMLEFT', 0, -6)

		local function renderExport(scopeValue)
			if(scopeValue == '__whole__') then
				local encoded = F.ImportExport.Export(parsed.data, 'full')
				copyBox:SetText(encoded or '')
			else
				local layoutTable = parsed.data.presets and parsed.data.presets[scopeValue]
				if(not layoutTable) then
					copyBox:SetText('(layout missing from snapshot)')
					return
				end
				local encoded, err = F.ImportExport.ExportLayoutData(scopeValue, layoutTable)
				copyBox:SetText(encoded or ('Export failed: ' .. (err or 'unknown')))
			end
			if(copyBox._editbox) then
				copyBox._editbox:SetFocus()
				copyBox._editbox:HighlightText()
			end
		end

		scopeDropdown:SetOnSelect(renderExport)
		renderExport('__whole__')

		row._exportArea = area
		if(relayout) then relayout() end
		_ = decodeErr
	end)

	row.MarkCorrupted = function(self)
		if(self._corruptedIcon) then return end
		local icon = Widgets.CreateFontString(self, C.Font.sizeSmall, C.Colors.textSecondary)
		icon:SetPoint('TOPRIGHT', self, 'TOPRIGHT', -10, -8)
		icon:SetText('[!]')
		icon:SetTextColor(1, 0.2, 0.2, 1)
		Widgets.SetTooltip(
			icon,
			'Corrupted snapshot',
			"This snapshot is corrupted. You can delete it but it can't be loaded or exported.")
		self._corruptedIcon = icon

		if(self._btnLoad and self._btnLoad.SetEnabled) then self._btnLoad:SetEnabled(false) end
		if(self._btnExport and self._btnExport.SetEnabled) then self._btnExport:SetEnabled(false) end
	end

	return row
end

-- ============================================================
-- Snapshots card
-- ============================================================

function F.BackupsCards.Snapshots(parent, width, onResize)
	local card, inner = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	-- Top action row (buttons sit side-by-side)
	local saveBtn   = Widgets.CreateButton(inner, 'Save Current As…',   'accent',  160, BUTTON_H)
	local importBtn = Widgets.CreateButton(inner, 'Import as Snapshot…', 'widget', 180, BUTTON_H)

	-- Plain list area (no inner scroll — full height grows with content,
	-- the panel scroll handles overflow)
	local listFrame = CreateFrame('Frame', nil, inner)
	Widgets.SetSize(listFrame, innerW, EMPTY_STATE_H)
	local listContent = listFrame

	-- Empty state text (shown when there are no user snapshots)
	local emptyFS = Widgets.CreateFontString(listContent, C.Font.sizeNormal, C.Colors.textSecondary)
	emptyFS:SetWidth(innerW - 16)
	emptyFS:SetWordWrap(true)
	emptyFS:SetJustifyH('LEFT')
	emptyFS:SetText(
		"You haven't saved any snapshots yet. Click Save Current As… to back up your current Framed settings, " ..
		'or Import as Snapshot… to load someone else\'s config into your list without applying it.')
	emptyFS:ClearAllPoints()
	Widgets.SetPoint(emptyFS, 'TOPLEFT', listContent, 'TOPLEFT', 8, -8)

	-- Footer: using X KB · N snapshots
	local footerFS = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)

	-- Disclaimer block
	local disclaimerFS = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	disclaimerFS:SetWidth(innerW)
	disclaimerFS:SetWordWrap(true)
	disclaimerFS:SetJustifyH('LEFT')
	disclaimerFS:SetText(
		'Snapshots are safe to use day-to-day, but here are some specific cases to watch for. ' ..
		'Loading a snapshot replaces your current Framed settings. ' ..
		"Framed always keeps an automatic \"Before last load\" backup so you can revert the most recent load if something goes wrong. " ..
		'Snapshots from older addon versions may not restore cleanly and can leave Framed in a broken state. ' ..
		"If you load an old snapshot and break the addon, we may not be able to help you recover — " ..
		'report it as feedback but expect to fix it yourself.')

	-- Inline input state
	local saveInputContainer
	local importInputContainer

	-- Reflow layout
	local function formatSize(bytes)
		if(not bytes or bytes < 1024) then return (bytes or 0) .. ' B' end
		return string.format('%.1f KB', bytes / 1024)
	end

	local function updateFooter()
		local total, count = 0, 0
		for _, wrapper in next, (FramedSnapshotsDB and FramedSnapshotsDB.snapshots or {}) do
			if(not wrapper.automatic) then
				count = count + 1
			end
			total = total + (wrapper.sizeBytes or 0)
		end
		footerFS:SetText('Using ' .. formatSize(total) .. ' · ' .. count .. ' snapshots')
	end

	local function hasUserSnapshots()
		for _, wrapper in next, (FramedSnapshotsDB and FramedSnapshotsDB.snapshots or {}) do
			if(not wrapper.automatic) then return true end
		end
		return false
	end

	-- Rendered row cache — reused across reflows so button wiring persists
	local renderedRows = {}

	-- Forward declaration so the row-level relayout callback can see it
	local reflow

	local function relayoutFromRow()
		if(reflow) then reflow(true) end
	end

	local function clearRows()
		for _, row in next, renderedRows do
			row:Hide()
			row:SetParent(nil)
		end
		renderedRows = {}
	end

	local function positionRows()
		local y = -4
		for _, row in next, renderedRows do
			row:ClearAllPoints()
			Widgets.SetPoint(row, 'TOPLEFT', listContent, 'TOPLEFT', 8, y)
			y = y - row:GetHeight() - 4
		end
		local totalH = math.max(EMPTY_STATE_H, (-y) + 4)
		listContent:SetHeight(totalH)
		return totalH
	end

	local function rebuildRows()
		clearRows()

		local snapshots = (FramedSnapshotsDB and FramedSnapshotsDB.snapshots) or {}

		local userList = {}
		local autoMap  = {}
		for name, wrapper in next, snapshots do
			if(wrapper.automatic) then
				autoMap[name] = wrapper
			else
				userList[#userList + 1] = { name = name, wrapper = wrapper }
			end
		end

		table.sort(userList, function(a, b)
			local ta = a.wrapper.timestamp or 0
			local tb = b.wrapper.timestamp or 0
			return ta > tb
		end)

		local rowW = listContent:GetWidth() - 16

		for _, entry in next, userList do
			local row = createSnapshotRow(listContent, rowW, entry.wrapper, entry.name, false, relayoutFromRow)
			row:Show()
			renderedRows[#renderedRows + 1] = row
		end

		for _, autoKey in next, F.Backups.AUTO_ORDER do
			local wrapper = autoMap[autoKey]
			if(wrapper) then
				local label = F.Backups.AUTO_LABELS[autoKey] or autoKey
				local row = createSnapshotRow(listContent, rowW, wrapper, label, true, relayoutFromRow)
				row:Show()
				renderedRows[#renderedRows + 1] = row
			end
		end
	end

	local building = true

	reflow = function(skipRebuild)
		local y = 0

		-- Place save + import buttons side-by-side on a single row
		saveBtn:ClearAllPoints()
		Widgets.SetPoint(saveBtn, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		importBtn:ClearAllPoints()
		Widgets.SetPoint(importBtn, 'LEFT', saveBtn, 'RIGHT', C.Spacing.tight, 0)
		y = y - BUTTON_H - C.Spacing.normal

		if(saveInputContainer) then
			y = B.PlaceWidget(saveInputContainer, inner, y, saveInputContainer:GetHeight())
		end
		if(importInputContainer) then
			y = B.PlaceWidget(importInputContainer, inner, y, importInputContainer:GetHeight())
		end

		if(hasUserSnapshots()) then
			emptyFS:Hide()
		else
			emptyFS:Show()
		end

		if(not skipRebuild) then
			rebuildRows()
		end
		local listH = positionRows()
		listFrame:SetHeight(listH)
		y = B.PlaceWidget(listFrame, inner, y, listH)

		updateFooter()
		y = B.PlaceWidget(footerFS, inner, y, LABEL_H)

		local discH = math.max(LABEL_H, math.ceil(disclaimerFS:GetStringHeight() + 2))
		y = B.PlaceWidget(disclaimerFS, inner, y, discH)

		Widgets.EndCard(card, parent, y)
		if(onResize and not building) then onResize() end
	end

	-- Cache on card for other tasks to re-trigger
	card._reflow      = reflow
	card._rebuildRows = rebuildRows
	card._listFrame   = listFrame
	card._listContent = listContent
	card._saveBtn     = saveBtn
	card._importBtn   = importBtn

	local function closeInputs()
		if(saveInputContainer) then
			saveInputContainer:Hide()
			saveInputContainer = nil
		end
		if(importInputContainer) then
			importInputContainer:Hide()
			importInputContainer = nil
		end
		reflow()
	end

	saveBtn:SetOnClick(function()
		closeInputs()

		local defaultName = 'Snapshot ' .. date('%Y-%m-%d %H:%M')
		local container, input, confirmBtn, cancelBtn = createInlineNameInput(
			inner, innerW,
			'Enter a name for this snapshot',
			defaultName)

		container:SetParent(inner)

		if(input._editbox) then
			input._editbox:SetScript('OnTextChanged', function()
				container._scheduleValidate(F.Backups.ValidateName)
			end)
		end

		confirmBtn:SetOnClick(function()
			local name = F.Backups.TrimName(input:GetText() or '')
			local ok, err = F.Backups.Save(name)
			if(ok) then
				closeInputs()
			else
				container._setError(err)
			end
		end)
		cancelBtn:SetOnClick(closeInputs)

		saveInputContainer = container
		reflow()

		if(input._editbox) then
			input._editbox:SetFocus()
			input._editbox:HighlightText()
		end
	end)

	importBtn:SetOnClick(function()
		closeInputs()

		local defaultName = 'Imported ' .. date('%Y-%m-%d %H:%M')

		local container = CreateFrame('Frame', nil, inner)
		Widgets.SetSize(container, innerW, EDITBOX_H + 22 + LABEL_H + BUTTON_H + 24)

		local pasteBox = Widgets.CreateEditBox(container, nil, innerW, EDITBOX_H, 'multiline')
		pasteBox:SetPlaceholder('Paste import string here…')
		pasteBox:ClearAllPoints()
		Widgets.SetPoint(pasteBox, 'TOPLEFT', container, 'TOPLEFT', 0, 0)

		local nameInput = Widgets.CreateEditBox(container, nil, innerW, 22)
		nameInput:SetPlaceholder('Snapshot name')
		nameInput:SetText(defaultName)
		nameInput:ClearAllPoints()
		Widgets.SetPoint(nameInput, 'TOPLEFT', pasteBox, 'BOTTOMLEFT', 0, -6)

		local errorFS = Widgets.CreateFontString(container, C.Font.sizeSmall, C.Colors.textSecondary)
		errorFS:ClearAllPoints()
		Widgets.SetPoint(errorFS, 'TOPLEFT', nameInput, 'BOTTOMLEFT', 0, -4)
		errorFS:SetWidth(innerW)
		errorFS:SetWordWrap(true)
		errorFS:SetText('')

		local confirmBtn = Widgets.CreateButton(container, 'Save as Snapshot', 'accent',    140, BUTTON_H)
		local cancelBtn  = Widgets.CreateButton(container, 'Cancel',           'secondary',  80, BUTTON_H)

		confirmBtn:ClearAllPoints()
		Widgets.SetPoint(confirmBtn, 'TOPLEFT', errorFS, 'BOTTOMLEFT', 0, -4)
		cancelBtn:ClearAllPoints()
		Widgets.SetPoint(cancelBtn, 'LEFT', confirmBtn, 'RIGHT', 6, 0)

		local function setError(msg)
			if(msg and msg ~= '') then
				errorFS:SetTextColor(1, 0.3, 0.3, 1)
				errorFS:SetText(msg)
			else
				errorFS:SetText('')
			end
		end

		confirmBtn:SetOnClick(function()
			local raw = pasteBox:GetText() or ''
			raw = raw:match('^%s*(.-)%s*$')
			if(raw == '') then
				setError('Paste an import string to continue.')
				return
			end
			local name = F.Backups.TrimName(nameInput:GetText() or '')
			local nameOk, nameErr = F.Backups.ValidateName(name)
			if(not nameOk) then
				setError(nameErr)
				return
			end
			local ok, err = F.Backups.SaveFromPayload(name, raw)
			if(ok) then
				closeInputs()
			else
				setError(err or 'Import failed.')
			end
		end)
		cancelBtn:SetOnClick(closeInputs)

		importInputContainer = container
		reflow()
	end)

	if(F.EventBus) then
		local function onChange() reflow() end
		F.EventBus:Register('BACKUP_CREATED', onChange, 'BackupsCard.created')
		F.EventBus:Register('BACKUP_DELETED', onChange, 'BackupsCard.deleted')
		F.EventBus:Register('BACKUP_LOADED',  onChange, 'BackupsCard.loaded')
	end

	reflow()
	building = false
	return card
end

-- ============================================================
-- Export card
-- ============================================================

function F.BackupsCards.Export(parent, width, onResize)
	local card, inner = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	local scopeLabel = createLabel(inner, 'SCOPE')
	local scopeDropdown = Widgets.CreateDropdown(inner, innerW)
	scopeDropdown:SetItems({
		{ text = 'Everything',   value = SCOPE_FULL },
		{ text = 'Single Layout', value = SCOPE_LAYOUT },
	})

	local layoutLabel = createLabel(inner, 'LAYOUT')
	local layoutDropdown = Widgets.CreateDropdown(inner, innerW)
	layoutDropdown:SetItems(getLayoutItems())
	local initialItems = getLayoutItems()
	if(#initialItems > 0) then
		layoutDropdown:SetValue(initialItems[1].value)
	end

	local exportBtn = Widgets.CreateButton(inner, 'Export', 'accent', 100, BUTTON_H)
	local hintFS = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	hintFS:SetWidth(innerW)
	hintFS:SetWordWrap(true)
	hintFS:SetJustifyH('LEFT')
	hintFS:SetText('To save a copy for yourself, use Save Current As… in the Snapshots card above. Export is for sharing with other users.')

	local exportBox = Widgets.CreateEditBox(inner, nil, innerW, EDITBOX_H, 'multiline')
	exportBox:SetPlaceholder('Export string will appear here.')
	if(exportBox._editbox) then
		exportBox._editbox:SetScript('OnKeyDown', function(self, key)
			if(key == 'ESCAPE') then
				self:ClearFocus()
			end
			if(IsControlKeyDown() and key == 'A') then
				self:HighlightText()
			end
		end)
	end

	local currentScope = SCOPE_FULL
	scopeDropdown:SetValue(currentScope)

	local initialized = false

	local function reflow()
		local y = 0
		y = placeLabelAt(scopeLabel, inner, y)
		y = B.PlaceWidget(scopeDropdown, inner, y, DROPDOWN_H)

		if(currentScope == SCOPE_LAYOUT) then
			layoutLabel:Show()
			layoutDropdown:Show()
			y = placeLabelAt(layoutLabel, inner, y)
			y = B.PlaceWidget(layoutDropdown, inner, y, DROPDOWN_H)
		else
			layoutLabel:Hide()
			layoutDropdown:Hide()
		end

		y = B.PlaceWidget(exportBtn, inner, y, BUTTON_H)
		y = B.PlaceWidget(hintFS, inner, y, LABEL_H * 2)
		y = B.PlaceWidget(exportBox, inner, y, EDITBOX_H)

		Widgets.EndCard(card, parent, y)
		if(initialized and onResize) then onResize() end
	end

	scopeDropdown:SetOnSelect(function(value)
		currentScope = value
		reflow()
	end)

	exportBtn:SetOnClick(function()
		local scope = scopeDropdown:GetValue()
		if(not scope) then
			exportBox:SetText('Select a scope to export.')
			return
		end

		local ie = F.ImportExport
		if(not ie) then
			exportBox:SetText('ImportExport module not loaded.')
			return
		end

		local encoded, err
		if(scope == SCOPE_FULL) then
			encoded, err = ie.ExportFullProfile()
		elseif(scope == SCOPE_LAYOUT) then
			local layoutName = layoutDropdown:GetValue()
			if(not layoutName) then
				exportBox:SetText('Select a layout to export.')
				return
			end
			encoded, err = ie.ExportLayout(layoutName)
		end

		if(encoded) then
			exportBox:SetText(encoded)
			if(exportBox._editbox) then
				exportBox._editbox:SetFocus()
				exportBox._editbox:HighlightText()
			end
		else
			exportBox:SetText('Export failed: ' .. (err or 'unknown error'))
		end
	end)

	reflow()
	initialized = true
	card._reflow = reflow
	return card
end

-- ============================================================
-- Import card
-- ============================================================

function F.BackupsCards.Import(parent, width, onResize)
	local card, inner = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	local importBox = Widgets.CreateEditBox(inner, nil, innerW, EDITBOX_H, 'multiline')
	importBox:SetPlaceholder('Paste import string here…')

	local verifyHeader = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	verifyHeader:SetText('── Verification ──')
	local verifyRowsFS = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	verifyRowsFS:SetWidth(innerW)
	verifyRowsFS:SetWordWrap(true)
	verifyRowsFS:SetJustifyH('LEFT')

	local importBtn = Widgets.CreateButton(inner, 'Import', 'accent', 100, BUTTON_H)

	local statusFS = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textSecondary)
	statusFS:SetWidth(innerW)
	statusFS:SetWordWrap(true)
	statusFS:SetText('')

	local currentParsed
	local initialized = false

	local function reflow()
		local y = 0
		y = B.PlaceWidget(importBox, inner, y, EDITBOX_H)

		if(verifyHeader:IsShown()) then
			y = B.PlaceWidget(verifyHeader, inner, y, LABEL_H)
			local rowsH = math.max(LABEL_H, math.ceil(verifyRowsFS:GetStringHeight() + 2))
			y = B.PlaceWidget(verifyRowsFS, inner, y, rowsH)
		end

		y = B.PlaceWidget(importBtn, inner, y, BUTTON_H)

		if((statusFS:GetText() or '') ~= '') then
			local statusH = math.max(LABEL_H, math.ceil(statusFS:GetStringHeight() + 2))
			y = B.PlaceWidget(statusFS, inner, y, statusH)
		end

		Widgets.EndCard(card, parent, y)
		if(initialized and onResize) then onResize() end
	end

	local function renderVerification(parsed, parseErr)
		if(parseErr) then
			verifyHeader:Show()
			verifyRowsFS:Show()
			verifyRowsFS:SetTextColor(1, 0.3, 0.3, 1)
			verifyRowsFS:SetText('✗ Format invalid: ' .. parseErr)
			importBtn:SetEnabled(false)
			reflow()
			return
		end

		verifyHeader:Show()
		verifyRowsFS:Show()
		verifyRowsFS:SetTextColor(
			C.Colors.textSecondary[1],
			C.Colors.textSecondary[2],
			C.Colors.textSecondary[3],
			C.Colors.textSecondary[4] or 1)

		local lines = {}
		lines[#lines + 1] = '✓ Format valid'

		local version = (parsed.sourceVersion) or (parsed.data and parsed.data.version) or 'unknown'
		local isStale = F.Version and (F.Version.IsStaleOlder(version, F.version) or F.Version.IsStaleNewer(version, F.version))
		lines[#lines + 1] = '✓ Version: ' .. version .. (isStale and ' [!] (stale)' or '')

		local scope = parsed.scope or 'unknown'
		lines[#lines + 1] = '✓ Scope: ' .. (scope == 'full' and 'Everything' or 'Single Layout')

		if(parsed.scope == 'full' and parsed.data and parsed.data.presets) then
			local total, overwrite, add = 0, 0, 0
			for layoutName in next, parsed.data.presets do
				total = total + 1
				if(FramedDB.presets and FramedDB.presets[layoutName]) then
					overwrite = overwrite + 1
				else
					add = add + 1
				end
			end
			lines[#lines + 1] = '✓ Contains ' .. total .. ' layouts, ' .. overwrite .. ' will be overwritten, ' .. add .. ' added'
		end

		local ignored, missing = classifyImportKeys(parsed)
		if(#ignored > 0) then
			lines[#lines + 1] = '⚠ ' .. #ignored .. ' settings will be ignored (from an older version)'
		end
		if(#missing > 0) then
			lines[#lines + 1] = 'ℹ ' .. #missing .. ' new settings will use defaults'
		end

		verifyRowsFS:SetText(table.concat(lines, '\n'))
		importBtn:SetEnabled(true)
		reflow()
	end

	local debounceTimer
	local function scheduleVerify()
		if(debounceTimer) then debounceTimer:Cancel() end
		debounceTimer = C_Timer.NewTimer(0.25, function()
			local raw = importBox:GetText() or ''
			raw = raw:match('^%s*(.-)%s*$') or ''
			if(raw == '') then
				verifyHeader:Hide()
				verifyRowsFS:Hide()
				importBtn:SetEnabled(false)
				currentParsed = nil
				reflow()
				return
			end
			local parsed, err = F.ImportExport.Import(raw)
			currentParsed = parsed
			renderVerification(parsed, err)
		end)
	end

	if(importBox._editbox) then
		importBox._editbox:SetScript('OnTextChanged', scheduleVerify)
	end
	verifyHeader:Hide()
	verifyRowsFS:Hide()
	importBtn:SetEnabled(false)

	importBtn:SetOnClick(function()
		if(InCombatLockdown()) then
			Widgets.ShowToast({ text = "Can't load snapshots in combat.", duration = 4 })
			return
		end
		if(not currentParsed) then return end

		Widgets.ShowConfirmDialog(
			'Confirm Import',
			'Replace your current Framed settings with this import?\nFramed will save an automatic "Before last import" backup first.',
			function()
				F.ImportExport.ApplyImport(currentParsed)
				importBox:SetText('')
				setTextColor(statusFS, C.Colors.textActive)
				statusFS:SetText('Import successful.')
				reflow()
				Widgets.ShowToast({
					text     = 'Import applied.',
					duration = 10,
					action   = {
						text    = 'Undo',
						onClick = function()
							F.Backups.Load(F.Backups.AUTO_PREIMPORT)
						end,
					},
				})
			end,
			function()
				setTextColor(statusFS, C.Colors.textSecondary)
				statusFS:SetText('Import cancelled.')
				reflow()
			end)
	end)

	reflow()
	initialized = true
	card._reflow = reflow
	return card
end

-- ============================================================
-- Export + Import wrapper — two fixed-width sub-cards side-by-side
-- Matches the Auto-Switch / Spec Overrides pattern in FramePresets.
-- ============================================================

local function injectCardTitle(card, titleText)
	if(card._titleAdded) then return end
	local titleFS = Widgets.CreateFontString(card, C.Font.sizeNormal, C.Colors.textNormal)
	titleFS:SetText(titleText)
	titleFS:ClearAllPoints()
	Widgets.SetPoint(titleFS, 'TOPLEFT', card, 'TOPLEFT', 12, -8)

	local titleH = titleFS:GetStringHeight() + C.Spacing.base + 4
	if(card.content) then
		card.content:ClearAllPoints()
		card.content:SetPoint('TOPLEFT',  card, 'TOPLEFT',  12, -(8 + titleH))
		card.content:SetPoint('TOPRIGHT', card, 'TOPRIGHT', -12, -(8 + titleH))
	end
	card._cardGridTitleH = titleH
	card:SetHeight(card:GetHeight() + titleH)
	card._titleAdded = true
end

function F.BackupsCards.ExportImport(parent, width, onResize)
	local CARD_GAP = C.Spacing.normal
	local halfW = math.floor((width - CARD_GAP) / 2)

	local wrapper = CreateFrame('Frame', nil, parent)

	local expCard, impCard
	local building = true

	local function wrapperResize()
		if(building) then return end
		if(not expCard or not impCard) then return end
		local h = math.max(expCard:GetHeight(), impCard:GetHeight())
		wrapper:SetSize(width, h)
		if(onResize) then onResize() end
	end

	expCard = F.BackupsCards.Export(parent, halfW, wrapperResize)
	injectCardTitle(expCard, 'Export')

	impCard = F.BackupsCards.Import(parent, halfW, wrapperResize)
	injectCardTitle(impCard, 'Import')

	-- Re-run each card's reflow so EndCard recalculates with the title height
	if(expCard._reflow) then expCard._reflow() end
	if(impCard._reflow) then impCard._reflow() end

	expCard:SetParent(wrapper)
	impCard:SetParent(wrapper)
	expCard:ClearAllPoints()
	Widgets.SetPoint(expCard, 'TOPLEFT', wrapper, 'TOPLEFT', 0, 0)
	impCard:ClearAllPoints()
	Widgets.SetPoint(impCard, 'TOPLEFT', expCard, 'TOPRIGHT', CARD_GAP, 0)

	wrapper:SetSize(width, math.max(expCard:GetHeight(), impCard:GetHeight()))
	building = false
	return wrapper
end
