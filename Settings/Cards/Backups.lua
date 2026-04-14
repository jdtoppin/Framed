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
local LIST_MAX_H       = 320

local SCOPE_FULL   = 'full'
local SCOPE_LAYOUT = 'layout'

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
	local container = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(container, width, EDITBOX_H + LABEL_H + BUTTON_H + 12)

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

local function createSnapshotRow(parent, width, wrapper, displayName, isAutomatic)
	local row = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(row, width, SNAPSHOT_ROW_H)
	Widgets.ApplyBackdrop(row, C.Colors.cardBg or C.Colors.widget, C.Colors.border)

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
	versionFS:SetPoint('BOTTOMLEFT', row, 'BOTTOMLEFT', 10, 8)
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
	local btnExport = Widgets.CreateButton(row, 'Export', 'secondary', BTN_W, BTN_H)
	local btnRename = Widgets.CreateButton(row, 'Rename', 'secondary', BTN_W, BTN_H)
	local btnDelete = Widgets.CreateButton(row, 'Delete', 'danger',    BTN_W, BTN_H)

	btnDelete:ClearAllPoints()
	Widgets.SetPoint(btnDelete, 'RIGHT', row, 'RIGHT', -10, 0)

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

	-- Top action row
	local saveBtn   = Widgets.CreateButton(inner, 'Save Current As…',   'accent',     160, BUTTON_H)
	local importBtn = Widgets.CreateButton(inner, 'Import as Snapshot…', 'secondary', 180, BUTTON_H)

	-- Scrollable list area
	local listFrame = Widgets.CreateScrollFrame(inner, nil, innerW, LIST_MAX_H)
	local listContent = listFrame:GetContentFrame()
	listContent:SetHeight(EMPTY_STATE_H)

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

	local function clearRows()
		for _, row in next, renderedRows do
			row:Hide()
			row:SetParent(nil)
		end
		renderedRows = {}
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

		local y = -4
		local rowW = listContent:GetWidth() - 16

		for _, entry in next, userList do
			local row = createSnapshotRow(listContent, rowW, entry.wrapper, entry.name, false)
			row:ClearAllPoints()
			Widgets.SetPoint(row, 'TOPLEFT', listContent, 'TOPLEFT', 8, y)
			row:Show()
			renderedRows[#renderedRows + 1] = row
			y = y - SNAPSHOT_ROW_H - 4
		end

		for _, autoKey in next, F.Backups.AUTO_ORDER do
			local wrapper = autoMap[autoKey]
			if(wrapper) then
				local label = F.Backups.AUTO_LABELS[autoKey] or autoKey
				local row = createSnapshotRow(listContent, rowW, wrapper, label, true)
				row:ClearAllPoints()
				Widgets.SetPoint(row, 'TOPLEFT', listContent, 'TOPLEFT', 8, y)
				row:Show()
				renderedRows[#renderedRows + 1] = row
				y = y - SNAPSHOT_ROW_H - 4
			end
		end

		local totalH = math.max(EMPTY_STATE_H, (-y) + 8)
		listContent:SetHeight(totalH)
	end

	local function reflow()
		local y = 0
		y = B.PlaceWidget(saveBtn,   inner, y, BUTTON_H)
		y = B.PlaceWidget(importBtn, inner, y, BUTTON_H)

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

		rebuildRows()
		y = B.PlaceWidget(listFrame, inner, y, LIST_MAX_H)

		updateFooter()
		y = B.PlaceWidget(footerFS, inner, y, LABEL_H)
		y = B.PlaceWidget(disclaimerFS, inner, y, LABEL_H * 6)

		Widgets.EndCard(card, parent, y)
		if(onResize) then onResize() end
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
		{ text = 'Full Profile',  value = SCOPE_FULL },
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
	return card
end

-- ============================================================
-- Import card
-- ============================================================

function F.BackupsCards.Import(parent, width)
	local card, inner, y = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	-- Paste box
	local importBox = Widgets.CreateEditBox(inner, nil, innerW, EDITBOX_H, 'multiline')
	importBox:SetPlaceholder('Paste import string here...')
	y = B.PlaceWidget(importBox, inner, y, EDITBOX_H)

	-- Import button
	local importBtn = Widgets.CreateButton(inner, 'Import', 'accent', 100, BUTTON_H)
	y = B.PlaceWidget(importBtn, inner, y, BUTTON_H)

	-- Status text
	local statusFS = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textSecondary)
	statusFS:ClearAllPoints()
	Widgets.SetPoint(statusFS, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
	statusFS:SetWidth(innerW)
	statusFS:SetWordWrap(true)
	statusFS:SetText('')
	y = y - C.Font.sizeNormal - C.Spacing.normal

	importBtn:SetOnClick(function()
		local inputStr = importBox:GetText()
		if(inputStr) then
			inputStr = inputStr:match('^%s*(.-)%s*$')
		end
		if(not inputStr or inputStr == '') then
			setTextColor(statusFS, C.Colors.textSecondary)
			statusFS:SetText('Paste an import string above.')
			return
		end

		local ie = F.ImportExport
		if(not ie) then
			setTextColor(statusFS, { 1, 0.3, 0.3, 1 })
			statusFS:SetText('Error: ImportExport module not loaded.')
			return
		end

		local payload, err = ie.Import(inputStr)
		if(not payload) then
			setTextColor(statusFS, { 1, 0.3, 0.3, 1 })
			statusFS:SetText('Error: ' .. (err or 'unknown error'))
			return
		end

		local confirmMsg = string.format(
			'Apply import?\n\nScope: %s\n\nThis cannot be undone.',
			payload.scope or 'unknown')

		Widgets.ShowConfirmDialog(
			'Confirm Import',
			confirmMsg,
			function()
				ie.ApplyImport(payload)
				importBox:SetText('')
				setTextColor(statusFS, C.Colors.textActive)
				statusFS:SetText('Import successful.')
			end,
			function()
				setTextColor(statusFS, C.Colors.textSecondary)
				statusFS:SetText('Import cancelled.')
			end)
	end)

	Widgets.EndCard(card, parent, y)
	return card
end
