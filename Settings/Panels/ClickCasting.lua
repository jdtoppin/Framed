local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================

local ROW_H        = 28
local DROPDOWN_H   = 22
local BUTTON_H     = 22
local EDITBOX_H    = 22

-- Binding field widths
local BTN_DD_W    = 80
local MOD_DD_W    = 70
local TYPE_DD_W   = 80
local VALUE_EB_W  = 100
local ADD_BTN_W   = 60
local REM_BTN_W   = 22

-- ============================================================
-- Dropdown option tables (reused across rows)
-- ============================================================

local BUTTON_OPTIONS = {
	{ text = 'Left',    value = 'LeftButton' },
	{ text = 'Right',   value = 'RightButton' },
	{ text = 'Middle',  value = 'MiddleButton' },
	{ text = 'Button4', value = 'Button4' },
	{ text = 'Button5', value = 'Button5' },
}

local MODIFIER_OPTIONS = {
	{ text = 'None',  value = '' },
	{ text = 'Shift', value = 'shift' },
	{ text = 'Ctrl',  value = 'ctrl' },
	{ text = 'Alt',   value = 'alt' },
}

local TYPE_OPTIONS = {
	{ text = 'Spell',  value = 'spell' },
	{ text = 'Macro',  value = 'macro' },
	{ text = 'Target', value = 'target' },
	{ text = 'Focus',  value = 'focus' },
	{ text = 'Assist', value = 'assist' },
	{ text = 'Menu',   value = 'menu' },
}

-- ============================================================
-- Config helpers
-- ============================================================

local function getBindings()
	return (F.Config and F.Config:Get('clickCasting.bindings')) or {}
end
local function setBindings(bindings)
	if(F.Config) then
		F.Config:Set('clickCasting.bindings', bindings)
	end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED:clickCasting')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'clickcasting',
	label   = 'Click Casting',
	section = 'GENERAL',
	order   = 40,
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

		-- ── Clique detection ───────────────────────────────────
		local hasClique = F.ClickCasting and F.ClickCasting.HasClique and F.ClickCasting.HasClique()

		if(hasClique) then
			-- Show info message only
			local infoFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
			infoFS:ClearAllPoints()
			Widgets.SetPoint(infoFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
			infoFS:SetWidth(width)
			infoFS:SetText('Clique detected \xe2\x80\x94 bindings are managed by Clique.')
			infoFS:SetWordWrap(true)

			content:SetHeight(80)
			scroll:UpdateScrollRange()
			return scroll
		end

		-- ── Binding list ───────────────────────────────────────
		local bindingsHeading, bindingsHeadingH = Widgets.CreateHeading(content, 'Click Bindings', 2)
		bindingsHeading:ClearAllPoints()
		Widgets.SetPoint(bindingsHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - bindingsHeadingH

		local bindCard, bindInner, bindCardY
		bindCard, bindInner, bindCardY = Widgets.StartCard(content, width, yOffset)

		-- Container for binding rows (grows dynamically)
		local rowContainer = CreateFrame('Frame', nil, bindInner)
		rowContainer:ClearAllPoints()
		Widgets.SetPoint(rowContainer, 'TOPLEFT', bindInner, 'TOPLEFT', 0, bindCardY)
		rowContainer:SetWidth(width)

		-- Track the list of binding row frames
		local bindingRows = {}

		local function saveAllBindings()
			local bindings = {}
			for _, row in next, bindingRows do
				bindings[#bindings + 1] = {
					button   = row._btnDD:GetValue(),
					modifier = row._modDD:GetValue(),
					bindType = row._typeDD:GetValue(),
					value    = row._valueEB:GetText(),
				}
			end
			setBindings(bindings)
		end

		local function removeRow(rowFrame)
			for i, r in next, bindingRows do
				if(r == rowFrame) then
					table.remove(bindingRows, i)
					break
				end
			end
			rowFrame:Hide()
			rowFrame:SetParent(nil)
			-- Re-layout remaining rows
			for i, r in next, bindingRows do
				r:ClearAllPoints()
				Widgets.SetPoint(r, 'TOPLEFT', rowContainer, 'TOPLEFT', 0, -(i - 1) * (ROW_H + C.Spacing.base))
			end
			local totalH = #bindingRows * (ROW_H + C.Spacing.base)
			rowContainer:SetHeight(math.max(totalH, 1))
			saveAllBindings()
		end

		local function addBindingRow(btnVal, modVal, typeVal, valText)
			local idx = #bindingRows + 1
			local rowY = -(idx - 1) * (ROW_H + C.Spacing.base)

			local row = CreateFrame('Frame', nil, rowContainer)
			row:ClearAllPoints()
			Widgets.SetPoint(row, 'TOPLEFT', rowContainer, 'TOPLEFT', 0, rowY)
			row:SetHeight(ROW_H)

			-- Button dropdown
			local btnDD = Widgets.CreateDropdown(row, BTN_DD_W)
			btnDD:ClearAllPoints()
			Widgets.SetPoint(btnDD, 'LEFT', row, 'LEFT', 0, 0)
			btnDD:SetItems(BUTTON_OPTIONS)
			btnDD:SetValue(btnVal or 'LeftButton')
			btnDD:SetOnSelect(saveAllBindings)
			row._btnDD = btnDD

			-- Modifier dropdown
			local modDD = Widgets.CreateDropdown(row, MOD_DD_W)
			modDD:ClearAllPoints()
			Widgets.SetPoint(modDD, 'LEFT', btnDD, 'RIGHT', C.Spacing.base, 0)
			modDD:SetItems(MODIFIER_OPTIONS)
			modDD:SetValue(modVal or '')
			modDD:SetOnSelect(saveAllBindings)
			row._modDD = modDD

			-- Type dropdown
			local typeDD = Widgets.CreateDropdown(row, TYPE_DD_W)
			typeDD:ClearAllPoints()
			Widgets.SetPoint(typeDD, 'LEFT', modDD, 'RIGHT', C.Spacing.base, 0)
			typeDD:SetItems(TYPE_OPTIONS)
			typeDD:SetValue(typeVal or 'spell')
			typeDD:SetOnSelect(saveAllBindings)
			row._typeDD = typeDD

			-- Value editbox
			local valueEB = Widgets.CreateEditBox(row, nil, VALUE_EB_W, EDITBOX_H, 'text')
			valueEB:ClearAllPoints()
			Widgets.SetPoint(valueEB, 'LEFT', typeDD, 'RIGHT', C.Spacing.base, 0)
			if(valText and valText ~= '') then
				valueEB:SetText(valText)
			else
				valueEB:SetPlaceholder('Spell / Macro\xe2\x80\xa6')
			end
			valueEB:SetOnTextChanged(saveAllBindings)
			row._valueEB = valueEB

			-- Remove button ("\xC3\x97")
			local remBtn = Widgets.CreateButton(row, '\xC3\x97', 'widget', REM_BTN_W, EDITBOX_H)
			remBtn:ClearAllPoints()
			Widgets.SetPoint(remBtn, 'LEFT', valueEB, 'RIGHT', C.Spacing.base, 0)
			local capturedRow = row
			remBtn:SetOnClick(function()
				removeRow(capturedRow)
			end)

			bindingRows[idx] = row

			-- Expand container
			local totalH = idx * (ROW_H + C.Spacing.base)
			rowContainer:SetHeight(totalH)

			return row
		end

		-- Populate from saved config
		local savedBindings = getBindings()
		if(#savedBindings > 0) then
			for _, b in next, savedBindings do
				addBindingRow(b.button, b.modifier, b.bindType, b.value)
			end
		else
			-- Start with one empty row
			addBindingRow('LeftButton', '', 'spell', '')
		end

		-- Update bindCardY past row container
		local containerH = math.max(#bindingRows * (ROW_H + C.Spacing.base), ROW_H)
		bindCardY = bindCardY - containerH - C.Spacing.normal

		-- ── Add Binding button ─────────────────────────────────
		local addBtn = Widgets.CreateButton(bindInner, 'Add Binding', 'accent', ADD_BTN_W + 40, BUTTON_H)
		addBtn:ClearAllPoints()
		Widgets.SetPoint(addBtn, 'TOPLEFT', bindInner, 'TOPLEFT', 0, bindCardY)
		addBtn:SetOnClick(function()
			addBindingRow('LeftButton', '', 'spell', '')
			-- Shift the button down
			bindCardY = bindCardY - (ROW_H + C.Spacing.base)
			addBtn:ClearAllPoints()
			Widgets.SetPoint(addBtn, 'TOPLEFT', bindInner, 'TOPLEFT', 0, bindCardY)
			content:SetHeight(math.abs(bindCardY) + C.Spacing.normal + BUTTON_H)
			scroll:UpdateScrollRange()
		end)
		bindCardY = bindCardY - BUTTON_H - C.Spacing.normal

		yOffset = Widgets.EndCard(bindCard, content, bindCardY)

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
