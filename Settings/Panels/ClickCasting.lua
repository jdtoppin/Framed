local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================

local ROW_H        = 28
local BUTTON_H     = 22
local EDITBOX_H    = 22

-- Binding field widths
local CAPTURE_W   = 160
local TYPE_DD_W   = 80
local VALUE_EB_W  = 140
local ADD_BTN_W   = 100
local REM_BTN_W   = 22

-- ============================================================
-- Dropdown option tables
-- ============================================================

local TYPE_OPTIONS = {
	{ text = 'Spell',  value = 'spell' },
	{ text = 'Macro',  value = 'macro' },
	{ text = 'Target', value = 'target' },
	{ text = 'Focus',  value = 'focus' },
	{ text = 'Assist', value = 'assist' },
	{ text = 'Menu',   value = 'menu' },
}

-- Types that need a value dropdown
local VALUE_TYPES = { spell = true, macro = true }

-- ============================================================
-- Spell / Macro data helpers
-- ============================================================

local function getSpellItems()
	local items = {}
	local seen = {}
	for i = 1, (C_SpellBook.GetNumSpellBookItems(Enum.SpellBookSpellBank.Player) or 0) do
		local info = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
		if(info and info.itemType == Enum.SpellBookItemType.Spell and info.name) then
			if(not seen[info.name] and not IsPassiveSpell(info.spellID)) then
				seen[info.name] = true
				items[#items + 1] = { text = info.name, value = info.name }
			end
		end
	end
	table.sort(items, function(a, b) return a.text < b.text end)
	return items
end

local function getMacroItems()
	local items = {}
	local numGlobal, numChar = GetNumMacros()
	for i = 1, numGlobal do
		local name = GetMacroInfo(i)
		if(name) then
			items[#items + 1] = { text = name, value = name }
		end
	end
	for i = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + numChar do
		local name = GetMacroInfo(i)
		if(name) then
			items[#items + 1] = { text = name .. ' (char)', value = name }
		end
	end
	return items
end

-- ============================================================
-- Bind capture formatting
-- ============================================================

local BUTTON_LABELS = {
	LeftButton   = 'Left Click',
	RightButton  = 'Right Click',
	MiddleButton = 'Middle Click',
	Button4      = 'Button 4',
	Button5      = 'Button 5',
}

--- Build a display string from modifier + button values.
--- @param modifier string  e.g. '', 'shift', 'ctrl-shift'
--- @param button   string  e.g. 'LeftButton'
--- @return string
local function FormatBindText(modifier, button)
	local parts = {}
	if(modifier and modifier ~= '') then
		for mod in modifier:gmatch('[^-]+') do
			parts[#parts + 1] = mod:sub(1, 1):upper() .. mod:sub(2)
		end
	end
	parts[#parts + 1] = BUTTON_LABELS[button] or button
	return table.concat(parts, ' + ')
end

--- Read current modifier keys and return a combined modifier string.
--- @return string  e.g. '', 'shift', 'ctrl-alt'
local function GetCurrentModifiers()
	local mods = {}
	if(IsShiftKeyDown()) then mods[#mods + 1] = 'shift' end
	if(IsControlKeyDown()) then mods[#mods + 1] = 'ctrl' end
	if(IsAltKeyDown()) then mods[#mods + 1] = 'alt' end
	return table.concat(mods, '-')
end

-- ============================================================
-- Config helpers
-- ============================================================

local function getSpecID()
	local specIndex = GetSpecialization and GetSpecialization() or 1
	local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex) or 0
	return tostring(specID)
end

local function getBindings()
	local specID = getSpecID()
	local charBindings = F.Config and F.Config:GetChar('clickCastBindings')
	if(charBindings and charBindings[specID]) then
		return charBindings[specID]
	end
	-- Fall back to defaults
	local numSpecID = tonumber(specID)
	if(F.ClickCasting.Defaults) then
		return F.ClickCasting.Defaults[numSpecID] or F.ClickCasting.Defaults['generic'] or {}
	end
	return {}
end

local function setBindings(bindings)
	local specID = getSpecID()
	if(F.Config) then
		F.Config:SetChar('clickCastBindings.' .. specID, bindings)
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
	section = 'GLOBAL',
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
			infoFS:SetText('Clique detected — bindings are managed by Clique.')
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

		-- Track which capture button is currently listening (only one at a time)
		local activeCapture = nil

		local function saveAllBindings()
			local bindings = {}
			for _, row in next, bindingRows do
				local bindType = row._typeDD:GetValue()
				local entry = {
					button   = row._button,
					modifier = row._modifier,
					type     = bindType,
				}
				if(VALUE_TYPES[bindType]) then
					local val = row._valueDD:GetValue()
					if(bindType == 'spell') then
						entry.spell = val
					elseif(bindType == 'macro') then
						entry.macro = val
					end
				end
				bindings[#bindings + 1] = entry
			end
			setBindings(bindings)
		end

		local function removeRow(rowFrame)
			-- Cancel capture if this row is active
			if(activeCapture and activeCapture == rowFrame._captureBtn) then
				activeCapture = nil
			end
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

		--- Exit capture mode on a button, restoring its display text.
		local function stopCapture(captureBtn)
			if(activeCapture == captureBtn) then
				activeCapture = nil
			end
			captureBtn._capturing = false
			captureBtn._label:SetTextColor(Widgets.UnpackColor(C.Colors.textActive))
			captureBtn._label:SetText(captureBtn._displayText)
			captureBtn:EnableKeyboard(false)
			captureBtn:SetScript('OnKeyDown', nil)
		end

		--- Enter capture mode: listen for mouse/key input.
		local function startCapture(captureBtn)
			-- Stop any other active capture first
			if(activeCapture and activeCapture ~= captureBtn) then
				stopCapture(activeCapture)
			end
			activeCapture = captureBtn
			captureBtn._capturing = true
			captureBtn._label:SetTextColor(Widgets.UnpackColor(C.Colors.accent))
			captureBtn._label:SetText('Press a bind...')

			-- Listen for keyboard (Escape to cancel)
			captureBtn:EnableKeyboard(true)
			captureBtn:SetPropagateKeyboardInput(true)
			captureBtn:SetScript('OnKeyDown', function(self, key)
				if(key == 'ESCAPE') then
					self:SetPropagateKeyboardInput(false)
					stopCapture(self)
				else
					self:SetPropagateKeyboardInput(true)
				end
			end)
		end

		local function addBindingRow(btnVal, modVal, typeVal, valText)
			local idx = #bindingRows + 1
			local rowY = -(idx - 1) * (ROW_H + C.Spacing.base)

			local row = CreateFrame('Frame', nil, rowContainer)
			row:ClearAllPoints()
			Widgets.SetPoint(row, 'TOPLEFT', rowContainer, 'TOPLEFT', 0, rowY)
			row:SetSize(width, ROW_H)

			-- Store the binding values on the row
			row._button   = btnVal or 'LeftButton'
			row._modifier = modVal or ''

			-- ── Capture button ────────────────────────────────
			local captureBtn = Widgets.CreateButton(row, '', 'widget', CAPTURE_W, EDITBOX_H)
			captureBtn:ClearAllPoints()
			Widgets.SetPoint(captureBtn, 'LEFT', row, 'LEFT', 0, 0)
			captureBtn._displayText = FormatBindText(row._modifier, row._button)
			captureBtn._label:SetText(captureBtn._displayText)
			captureBtn._capturing = false
			row._captureBtn = captureBtn

			-- Left-click toggles capture mode; any other mouse button is captured
			captureBtn:RegisterForClicks('AnyDown')
			captureBtn:SetOnClick(nil)  -- clear default
			captureBtn:SetScript('OnClick', function(self, mouseButton)
				if(self._capturing) then
					-- Capture this click as the binding
					row._button   = mouseButton
					row._modifier = GetCurrentModifiers()
					self._displayText = FormatBindText(row._modifier, row._button)
					stopCapture(self)
					saveAllBindings()
				else
					-- Enter capture mode
					startCapture(self)
				end
			end)

			-- Type dropdown
			local typeDD = Widgets.CreateDropdown(row, TYPE_DD_W)
			typeDD:ClearAllPoints()
			Widgets.SetPoint(typeDD, 'LEFT', captureBtn, 'RIGHT', C.Spacing.base, 0)
			typeDD:SetItems(TYPE_OPTIONS)
			row._typeDD = typeDD

			-- Value dropdown (spell or macro list)
			local valueDD = Widgets.CreateDropdown(row, VALUE_EB_W)
			valueDD:ClearAllPoints()
			Widgets.SetPoint(valueDD, 'LEFT', typeDD, 'RIGHT', C.Spacing.base, 0)
			valueDD:SetOnSelect(saveAllBindings)
			row._valueDD = valueDD

			-- Populate and show/hide value dropdown based on type
			local function updateValueDropdown(bindType)
				if(bindType == 'spell') then
					valueDD:SetItems(getSpellItems())
					valueDD:Show()
				elseif(bindType == 'macro') then
					valueDD:SetItems(getMacroItems())
					valueDD:Show()
				else
					valueDD:Hide()
				end
			end

			-- Set initial type and value
			local initType = typeVal or 'spell'
			typeDD:SetValue(initType)
			updateValueDropdown(initType)
			if(valText and valText ~= '') then
				valueDD:SetValue(valText)
			end

			typeDD:SetOnSelect(function(value)
				updateValueDropdown(value)
				valueDD:SetValue(nil)
				saveAllBindings()
			end)

			-- Remove button
			local remBtn = Widgets.CreateButton(row, 'X', 'widget', REM_BTN_W, EDITBOX_H)
			remBtn:ClearAllPoints()
			Widgets.SetPoint(remBtn, 'LEFT', valueDD, 'RIGHT', C.Spacing.base, 0)
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
				addBindingRow(b.button, b.modifier, b.type, b.spell or b.macro or '')
			end
		else
			-- Start with one empty row
			addBindingRow('LeftButton', '', 'spell', '')
		end

		-- Update bindCardY past row container
		local containerH = math.max(#bindingRows * (ROW_H + C.Spacing.base), ROW_H)
		bindCardY = bindCardY - containerH - C.Spacing.normal

		-- ── Add Binding button ─────────────────────────────────
		local addBtn = Widgets.CreateButton(bindInner, 'Add Binding', 'accent', ADD_BTN_W, BUTTON_H)
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
