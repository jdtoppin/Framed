local _, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.ProfilesCards = F.ProfilesCards or {}

-- ── Layout constants ───────────────────────────────────────
local DROPDOWN_H = 22
local BUTTON_H   = 22
local EDITBOX_H  = 80
local LABEL_H    = C.Font.sizeSmall + 4

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
-- Export card
-- ============================================================

function F.ProfilesCards.Export(parent, width, onResize)
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

function F.ProfilesCards.Import(parent, width)
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
