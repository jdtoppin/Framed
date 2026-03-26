local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Profiles panel
-- Export section: scope dropdown, optional layout picker,
--   Export button, read-only output box.
-- Import section: paste box, Replace/Merge switch,
--   Import button with confirm dialog, status text.
-- ============================================================

-- ── Layout constants ───────────────────────────────────────
local DROPDOWN_H   = 22
local BUTTON_H     = 22
local SWITCH_H     = 22
local EDITBOX_H    = 80      -- multi-line box height
local LABEL_H      = C.Font.sizeSmall + 4
local ROW_H        = 28      -- standard row spacing

-- ── Scope constants ────────────────────────────────────────
local SCOPE_FULL        = 'full'
local SCOPE_LAYOUT      = 'layout'
local SCOPE_RAID_DEBUFF = 'raidDebuffs'

-- ============================================================
-- Helpers
-- ============================================================

--- Return a sorted list of {text, value} items for all presets.
local function getLayoutItems()
	local names = (F.PresetManager and F.PresetManager.GetNames) and
		F.PresetManager.GetNames() or {}
	local items = {}
	for _, name in next, names do
		items[#items + 1] = { text = name, value = name }
	end
	if(#items == 0) then
		-- Fallback if PresetManager not yet ready
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

--- Set font-string text color using a C.Colors table entry.
local function setTextColor(fs, colorTable)
	fs:SetTextColor(
		colorTable[1], colorTable[2], colorTable[3], colorTable[4] or 1)
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'profiles',
	label   = 'Profiles',
	section = 'GLOBAL',
	order   = 30,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(
			parent, nil,
			parentW,
			parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ══════════════════════════════════════════════════════
		-- EXPORT SECTION
		-- ══════════════════════════════════════════════════════

		local exportHeading, exportHeadingH = Widgets.CreateHeading(content, 'Export', 2)
		exportHeading:ClearAllPoints()
		Widgets.SetPoint(exportHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - exportHeadingH

		-- ── Scope label + dropdown ─────────────────────────
		local scopeLabel = Widgets.CreateFontString(
			content, C.Font.sizeSmall, C.Colors.textSecondary)
		scopeLabel:ClearAllPoints()
		Widgets.SetPoint(scopeLabel, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		scopeLabel:SetText('SCOPE')
		yOffset = yOffset - LABEL_H

		local scopeDropdown = Widgets.CreateDropdown(content, width)
		scopeDropdown:ClearAllPoints()
		Widgets.SetPoint(scopeDropdown, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		scopeDropdown:SetItems({
			{ text = 'Full Profile',            value = SCOPE_FULL },
			{ text = 'Single Layout',           value = SCOPE_LAYOUT },
			{ text = 'Raid Debuff Overrides',   value = SCOPE_RAID_DEBUFF },
		})
		yOffset = yOffset - DROPDOWN_H - C.Spacing.normal

		-- ── Layout name dropdown (visible only for Single Layout) ──
		local layoutLabel = Widgets.CreateFontString(
			content, C.Font.sizeSmall, C.Colors.textSecondary)
		layoutLabel:ClearAllPoints()
		Widgets.SetPoint(layoutLabel, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		layoutLabel:SetText('LAYOUT')
		local layoutLabelOffset = yOffset
		yOffset = yOffset - LABEL_H

		local layoutDropdown = Widgets.CreateDropdown(content, width)
		layoutDropdown:ClearAllPoints()
		Widgets.SetPoint(layoutDropdown, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		layoutDropdown:SetItems(getLayoutItems())
		local layoutDropdownOffset = yOffset
		-- Select first item by default
		local layoutItems = getLayoutItems()
		if(#layoutItems > 0) then
			layoutDropdown:SetValue(layoutItems[1].value)
		end
		yOffset = yOffset - DROPDOWN_H - C.Spacing.normal

		-- ── Export button ─────────────────────────────────
		local exportBtn = Widgets.CreateButton(content, 'Export', 'accent', 100, BUTTON_H)
		exportBtn:ClearAllPoints()
		Widgets.SetPoint(exportBtn, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - BUTTON_H - C.Spacing.tight

		-- ── Export output edit box (read-only) ─────────────
		local exportBox = Widgets.CreateEditBox(
			content, nil, width, EDITBOX_H, 'multiline')
		exportBox:ClearAllPoints()
		Widgets.SetPoint(exportBox, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		exportBox:SetPlaceholder('Export string will appear here.')
		-- Make it read-only by clearing the text-changed handler
		-- (user can select-all and copy, but we don't let them type)
		if(exportBox._editbox) then
			exportBox._editbox:SetScript('OnKeyDown', function(self, key)
				if(key == 'ESCAPE') then
					self:ClearFocus()
				end
				-- Ctrl+A to select all for easy copying
				if(IsControlKeyDown() and key == 'A') then
					self:HighlightText()
				end
				-- Block typing by not propagating
			end)
		end
		yOffset = yOffset - EDITBOX_H - C.Spacing.loose

		-- ── Scope visibility logic ─────────────────────────
		local function updateLayoutVisibility(scope)
			if(scope == SCOPE_LAYOUT) then
				layoutLabel:Show()
				layoutDropdown:Show()
			else
				layoutLabel:Hide()
				layoutDropdown:Hide()
			end
		end

		-- Default to Full Profile
		scopeDropdown:SetValue(SCOPE_FULL)
		updateLayoutVisibility(SCOPE_FULL)

		scopeDropdown:SetOnSelect(function(value)
			updateLayoutVisibility(value)
		end)

		-- ── Export button logic ────────────────────────────
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
			elseif(scope == SCOPE_RAID_DEBUFF) then
				encoded, err = ie.ExportRaidDebuffs()
			end

			if(encoded) then
				exportBox:SetText(encoded)
				-- Select all so it's ready to copy
				if(exportBox._editbox) then
					exportBox._editbox:SetFocus()
					exportBox._editbox:HighlightText()
				end
			else
				exportBox:SetText('Export failed: ' .. (err or 'unknown error'))
			end
		end)

		-- ══════════════════════════════════════════════════════
		-- IMPORT SECTION
		-- ══════════════════════════════════════════════════════

		local importHeading, importHeadingH = Widgets.CreateHeading(content, 'Import', 2)
		importHeading:ClearAllPoints()
		Widgets.SetPoint(importHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - importHeadingH

		-- ── Paste box ──────────────────────────────────────
		local importBox = Widgets.CreateEditBox(
			content, nil, width, EDITBOX_H, 'multiline')
		importBox:ClearAllPoints()
		Widgets.SetPoint(importBox, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		importBox:SetPlaceholder('Paste import string here...')
		yOffset = yOffset - EDITBOX_H - C.Spacing.normal

		-- ── Import mode switch: Replace / Merge ────────────
		local modeLabel = Widgets.CreateFontString(
			content, C.Font.sizeSmall, C.Colors.textSecondary)
		modeLabel:ClearAllPoints()
		Widgets.SetPoint(modeLabel, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		modeLabel:SetText('MODE')
		yOffset = yOffset - LABEL_H

		local modeSwitch = Widgets.CreateSwitch(content, width, SWITCH_H, {
			{ text = 'Replace', value = 'replace' },
			{ text = 'Merge',   value = 'merge' },
		})
		modeSwitch:ClearAllPoints()
		Widgets.SetPoint(modeSwitch, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		modeSwitch:SetValue('replace')
		yOffset = yOffset - SWITCH_H - C.Spacing.normal

		-- ── Import button ──────────────────────────────────
		local importBtn = Widgets.CreateButton(content, 'Import', 'accent', 100, BUTTON_H)
		importBtn:ClearAllPoints()
		Widgets.SetPoint(importBtn, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - BUTTON_H - C.Spacing.tight

		-- ── Status text (success / error feedback) ─────────
		local statusFS = Widgets.CreateFontString(
			content, C.Font.sizeNormal, C.Colors.textSecondary)
		statusFS:ClearAllPoints()
		Widgets.SetPoint(statusFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		statusFS:SetWidth(width)
		statusFS:SetWordWrap(true)
		statusFS:SetText('')
		yOffset = yOffset - C.Font.sizeNormal - C.Spacing.loose

		-- ── Import button logic ────────────────────────────
		importBtn:SetOnClick(function()
			local inputStr = importBox:GetText()
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

			-- Parse first, before showing dialog, so we can report errors
			local payload, err = ie.Import(inputStr)
			if(not payload) then
				setTextColor(statusFS, { 1, 0.3, 0.3, 1 })
				statusFS:SetText('Error: ' .. (err or 'unknown error'))
				return
			end

			local mode = modeSwitch:GetValue() or 'replace'

			local scopeLabel2 = payload.scope or 'unknown'
			local modeLabel2  = (mode == 'replace') and 'replace' or 'merge'
			local confirmMsg  = string.format(
				'Apply import?\n\nScope: %s\nMode: %s\n\nThis cannot be undone.',
				scopeLabel2, modeLabel2)

			Widgets.ShowConfirmDialog(
				'Confirm Import',
				confirmMsg,
				function()
					ie.ApplyImport(payload, mode)
					importBox:SetText('')
					setTextColor(statusFS, C.Colors.textActive)
					statusFS:SetText('Import successful.')
				end,
				function()
					setTextColor(statusFS, C.Colors.textSecondary)
					statusFS:SetText('Import cancelled.')
				end
			)
		end)

		-- ── Final content height ───────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
