local _, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================

local ROW_H        = 28
local BUTTON_H     = 22
local EDITBOX_H    = 20
local PAD_H        = 6

-- Binding field widths
local CAPTURE_W   = 130
local TYPE_DD_W   = 70
local VALUE_DD_W  = 160
local ADD_BTN_W   = 100
local REM_BTN_W   = 20

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

local ICON_SIZE = 18

local function makeSpellDecorator(iconID, spellID)
	return function(row)
		if(iconID) then
			row._swatch:SetSize(ICON_SIZE, ICON_SIZE)
			row._swatch:SetTexture(iconID)
			row._swatch:SetVertexColor(1, 1, 1, 1)
			row._swatch:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			row._swatch:Show()
			row._label:SetPoint('LEFT', row, 'LEFT', ICON_SIZE + 8, 0)
		end
		row:SetScript('OnEnter', function(self)
			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
			GameTooltip:SetSpellByID(spellID)
			GameTooltip:Show()
			local ac = C.Colors.accent
			self:SetBackdropColor(ac[1] * 0.3, ac[2] * 0.3, ac[3] * 0.3, 0.5)
		end)
		row:SetScript('OnLeave', function(self)
			GameTooltip:Hide()
			self:SetBackdropColor(0, 0, 0, 0)
		end)
	end
end

local function getSpellItems()
	local items = {}
	local seen = {}
	local numTabs = C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines()
	if(not numTabs or numTabs == 0) then return items end

	for tab = 1, numTabs do
		local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tab)
		-- Skip the General tab (tab 1: racials, mounts, etc.)
		if(skillLineInfo and not skillLineInfo.shouldHide and tab > 1) then
			local offset = skillLineInfo.itemIndexOffset or 0
			local count = skillLineInfo.numSpellBookItems or 0
			for i = offset + 1, offset + count do
				local itemInfo = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
				if(itemInfo and itemInfo.spellID) then
					local isSpell = (itemInfo.itemType == Enum.SpellBookItemType.Spell)
					if(isSpell and not itemInfo.isPassive and not itemInfo.isOffSpec) then
						local name = itemInfo.name or (C_Spell.GetSpellName and C_Spell.GetSpellName(itemInfo.spellID))
						if(name and not seen[name]) then
							seen[name] = true
							items[#items + 1] = {
								text = name .. '  |cff888888(' .. itemInfo.spellID .. ')|r',
								value = name,
								_iconTexture = itemInfo.iconID,
								_decorateRow = makeSpellDecorator(itemInfo.iconID, itemInfo.spellID),
							}
						end
					end
				end
			end
		end
	end
	table.sort(items, function(a, b) return a.text < b.text end)
	return items
end

local function makeMacroDecorator(iconTexture)
	return function(row)
		if(iconTexture) then
			row._swatch:SetSize(ICON_SIZE, ICON_SIZE)
			row._swatch:SetTexture(iconTexture)
			row._swatch:SetVertexColor(1, 1, 1, 1)
			row._swatch:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			row._swatch:Show()
			row._label:SetPoint('LEFT', row, 'LEFT', ICON_SIZE + 8, 0)
		end
	end
end

local function getMacroItems()
	local items = {}
	local numGlobal, numChar = GetNumMacros()
	for i = 1, numGlobal do
		local name, iconTexture = GetMacroInfo(i)
		if(name) then
			items[#items + 1] = {
				text = name,
				value = name,
				_iconTexture = iconTexture,
				_decorateRow = makeMacroDecorator(iconTexture),
			}
		end
	end
	for i = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + numChar do
		local name, iconTexture = GetMacroInfo(i)
		if(name) then
			items[#items + 1] = {
				text = name .. ' (char)',
				value = name,
				_iconTexture = iconTexture,
				_decorateRow = makeMacroDecorator(iconTexture),
			}
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

-- Keys that are modifiers only — don't capture these as bindings
local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true,
	LCTRL  = true, RCTRL  = true,
	LALT   = true, RALT   = true,
}

--- Build a display string from modifier + button values.
--- @param modifier string  e.g. '', 'shift', 'ctrl-shift'
--- @param button   string  e.g. 'LeftButton' or 'F' or 'F1'
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
	if(F.ClickCasting and F.ClickCasting.RefreshAll) then
		F.ClickCasting.RefreshAll()
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
		local width   = parentW - C.Spacing.normal * 2
		local innerWidth = width - Widgets.CARD_PADDING * 2
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
		local bindCard, bindInner, bindCardY
		bindCard, bindInner, bindCardY = Widgets.StartCard(content, width, yOffset)

		-- Column headers
		local headerY = bindCardY
		local hdrBind = Widgets.CreateFontString(bindInner, C.Font.sizeSmall, C.Colors.textSecondary)
		hdrBind:SetJustifyH('LEFT')
		hdrBind:ClearAllPoints()
		Widgets.SetPoint(hdrBind, 'TOPLEFT', bindInner, 'TOPLEFT', PAD_H, headerY)
		hdrBind:SetText('Binding')

		local hdrType = Widgets.CreateFontString(bindInner, C.Font.sizeSmall, C.Colors.textSecondary)
		hdrType:SetJustifyH('LEFT')
		hdrType:ClearAllPoints()
		Widgets.SetPoint(hdrType, 'TOPLEFT', bindInner, 'TOPLEFT', PAD_H + CAPTURE_W + C.Spacing.base, headerY)
		hdrType:SetText('Type')

		local hdrValue = Widgets.CreateFontString(bindInner, C.Font.sizeSmall, C.Colors.textSecondary)
		hdrValue:SetJustifyH('LEFT')
		hdrValue:ClearAllPoints()
		Widgets.SetPoint(hdrValue, 'TOPLEFT', bindInner, 'TOPLEFT', PAD_H + CAPTURE_W + TYPE_DD_W + C.Spacing.base * 2, headerY)
		hdrValue:SetText('Value')

		bindCardY = bindCardY - C.Font.sizeSmall - C.Spacing.base
		local rowStartY = bindCardY  -- stable reference for layout calculations

		-- Container for binding rows (grows dynamically)
		local rowContainer = CreateFrame('Frame', nil, bindInner)
		rowContainer:ClearAllPoints()
		Widgets.SetPoint(rowContainer, 'TOPLEFT', bindInner, 'TOPLEFT', 0, bindCardY)
		rowContainer:SetWidth(innerWidth)

		-- Track the list of binding row frames
		local bindingRows = {}

		-- Track which capture button is currently listening (only one at a time)
		local activeCapture = nil
		local updateLayout  -- forward declaration

		local function saveAllBindings()
			local bindings = {}
			for _, row in next, bindingRows do
				local bindType = row._typeDD:GetValue()
				local entry = {
					button   = row._button,
					modifier = row._modifier,
					type     = bindType,
					isKey    = row._isKey or nil,
					enabled  = row._enabled == false and false or nil,
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
			if(updateLayout) then updateLayout() end
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

			-- Listen for keyboard keys
			captureBtn:EnableKeyboard(true)
			captureBtn:SetPropagateKeyboardInput(true)
			captureBtn:SetScript('OnKeyDown', function(self, key)
				if(key == 'ESCAPE') then
					self:SetPropagateKeyboardInput(false)
					stopCapture(self)
				elseif(MODIFIER_KEYS[key]) then
					-- Bare modifier press, keep waiting
					self:SetPropagateKeyboardInput(true)
				else
					-- Capture this key as the binding
					self:SetPropagateKeyboardInput(false)
					local row = self:GetParent()
					row._button   = key
					row._modifier = GetCurrentModifiers()
					row._isKey    = true
					self._displayText = FormatBindText(row._modifier, row._button)
					stopCapture(self)
					saveAllBindings()
				end
			end)
		end

		local function addBindingRow(btnVal, modVal, typeVal, valText, isKey, enabledVal)
			local idx = #bindingRows + 1
			local rowY = -(idx - 1) * (ROW_H + C.Spacing.base)

			local row = CreateFrame('Frame', nil, rowContainer, 'BackdropTemplate')
			Widgets.ApplyBackdrop(row, C.Colors.panel, C.Colors.border)
			row:ClearAllPoints()
			Widgets.SetPoint(row, 'TOPLEFT', rowContainer, 'TOPLEFT', 0, rowY)
			row:SetSize(innerWidth, ROW_H)

			-- Store the binding values on the row
			row._button   = btnVal or 'LeftButton'
			row._modifier = modVal or ''
			row._isKey    = isKey or false
			row._enabled  = enabledVal ~= false

			-- ── Capture button ────────────────────────────────
			local captureBtn = Widgets.CreateButton(row, '', 'widget', CAPTURE_W, EDITBOX_H)
			captureBtn:ClearAllPoints()
			Widgets.SetPoint(captureBtn, 'LEFT', row, 'LEFT', PAD_H, 0)
			captureBtn._displayText = FormatBindText(row._modifier, row._button)
			captureBtn._label:SetText(captureBtn._displayText)
			captureBtn._capturing = false
			row._captureBtn = captureBtn

			-- OnMouseDown captures the bind (fires on press, modifiers still held)
			-- OnClick enters capture mode (fires on release)
			captureBtn:RegisterForClicks('AnyUp')
			captureBtn:SetScript('OnMouseDown', function(self, mouseButton)
				if(self._capturing) then
					row._button   = mouseButton
					row._modifier = GetCurrentModifiers()
					row._isKey    = false
					self._displayText = FormatBindText(row._modifier, row._button)
					stopCapture(self)
					saveAllBindings()
					self._justCaptured = true
				end
			end)
			captureBtn:SetScript('OnClick', function(self)
				if(self._justCaptured) then
					self._justCaptured = nil
					return
				end
				if(not self._capturing) then
					startCapture(self)
				end
			end)

			-- Type dropdown
			local typeDD = Widgets.CreateDropdown(row, TYPE_DD_W)
			typeDD:ClearAllPoints()
			Widgets.SetPoint(typeDD, 'LEFT', captureBtn, 'RIGHT', C.Spacing.base, 0)
			typeDD:SetItems(TYPE_OPTIONS)
			row._typeDD = typeDD

			-- Remove button (created first so value dropdown can anchor to it)
			local remBtn = Widgets.CreateIconButton(row, F.Media.GetIcon('Close'), REM_BTN_W)
			remBtn:ClearAllPoints()
			Widgets.SetPoint(remBtn, 'RIGHT', row, 'RIGHT', -PAD_H, 0)
			local capturedRow = row
			remBtn:SetOnClick(function()
				local bindText = FormatBindText(capturedRow._modifier, capturedRow._button)
				Widgets.ShowConfirmDialog(
					'Remove Binding',
					'Remove the ' .. bindText .. ' binding?',
					function() removeRow(capturedRow) end
				)
			end)

			-- Enabled checkbox (disable without deleting)
			local enabledCB = Widgets.CreateCheckButton(row, '', function(checked)
				row._enabled = checked
				saveAllBindings()
			end)
			enabledCB:SetWidgetTooltip('Enable / Disable')
			enabledCB:SetChecked(row._enabled)
			enabledCB:ClearAllPoints()
			Widgets.SetPoint(enabledCB, 'RIGHT', remBtn, 'LEFT', -C.Spacing.base, 0)
			row._enabledCB = enabledCB

			-- Value dropdown (spell or macro list) — stretches to fill between type and enabled
			local valueDD = Widgets.CreateDropdown(row, VALUE_DD_W)
			valueDD:ClearAllPoints()
			Widgets.SetPoint(valueDD, 'LEFT', typeDD, 'RIGHT', C.Spacing.base, 0)
			Widgets.SetPoint(valueDD, 'RIGHT', enabledCB, 'LEFT', -C.Spacing.base, 0)
			valueDD:SetOnSelect(saveAllBindings)
			row._valueDD = valueDD

			-- Button icon on the dropdown face (shows selected spell/macro icon)
			local btnIcon = valueDD:CreateTexture(nil, 'ARTWORK')
			btnIcon:SetSize(ICON_SIZE - 4, ICON_SIZE - 4)
			btnIcon:SetPoint('LEFT', valueDD, 'LEFT', 4, 0)
			btnIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btnIcon:Hide()
			valueDD._buttonIcon = btnIcon

			--- Update the dropdown button face icon from item data.
			local function updateButtonIcon(dd, value)
				local icon = nil
				if(value and dd._items) then
					for _, itm in next, dd._items do
						if(itm.value == value) then
							icon = itm._iconTexture
							break
						end
					end
				end
				if(icon) then
					dd._buttonIcon:SetTexture(icon)
					dd._buttonIcon:Show()
					dd._label:SetPoint('LEFT', dd, 'LEFT', ICON_SIZE + 4, 0)
				else
					dd._buttonIcon:Hide()
					dd._label:SetPoint('LEFT', dd, 'LEFT', 6, 0)
				end
			end

			-- Hook _SelectItem to also update button icon
			local baseSelectItem = valueDD._SelectItem
			function valueDD:_SelectItem(item)
				baseSelectItem(self, item)
				updateButtonIcon(self, item.value)
			end

			-- Hook SetValue to also update button icon
			local baseSetValue = valueDD.SetValue
			function valueDD:SetValue(value)
				baseSetValue(self, value)
				updateButtonIcon(self, value)
			end

			-- Populate and show/hide value dropdown based on type
			local function updateValueDropdown(bindType)
				if(bindType == 'spell') then
					valueDD:SetItems(getSpellItems())
					valueDD:Show()
				elseif(bindType == 'macro') then
					valueDD:SetItems(getMacroItems())
					valueDD:Show()
				else
					valueDD._buttonIcon:Hide()
					valueDD._label:SetPoint('LEFT', valueDD, 'LEFT', 6, 0)
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

			-- Row hover highlight (matches Buffs/Debuffs table theme)
			row:EnableMouse(true)
			row:SetScript('OnEnter', function(self)
				Widgets.SetBackdropHighlight(self, true)
			end)
			row:SetScript('OnLeave', function(self)
				if(self:IsMouseOver()) then return end
				Widgets.SetBackdropHighlight(self, false)
			end)
			for _, child in next, { captureBtn, typeDD, valueDD, enabledCB, remBtn } do
				child:HookScript('OnEnter', function() Widgets.SetBackdropHighlight(row, true) end)
				child:HookScript('OnLeave', function()
					if(row:IsMouseOver()) then return end
					Widgets.SetBackdropHighlight(row, false)
				end)
			end

			bindingRows[idx] = row

			-- Expand container
			local totalH = idx * (ROW_H + C.Spacing.base)
			rowContainer:SetHeight(totalH)

			return row
		end

		-- Forward-declared layout updater for add/remove
		local addBtn
		function updateLayout()
			local totalH = math.max(#bindingRows * (ROW_H + C.Spacing.base), ROW_H)
			rowContainer:SetHeight(totalH)
			local btnY = rowStartY - totalH - C.Spacing.normal
			addBtn:ClearAllPoints()
			Widgets.SetPoint(addBtn, 'TOPLEFT', bindInner, 'TOPLEFT', 0, btnY)
			-- Update card and content sizing
			bindCardY = btnY - BUTTON_H - C.Spacing.normal
			Widgets.EndCard(bindCard, content, bindCardY)
			content:SetHeight(math.abs(bindCardY) + Widgets.CARD_PADDING * 2 + C.Spacing.normal * 2)
			scroll:UpdateScrollRange()
		end

		-- Populate from saved config
		local savedBindings = getBindings()
		if(#savedBindings > 0) then
			for _, b in next, savedBindings do
				addBindingRow(b.button, b.modifier, b.type, b.spell or b.macro or '', b.isKey, b.enabled)
			end
		else
			-- Start with one empty row
			addBindingRow('LeftButton', '', 'spell', '', false, true)
		end

		-- ── Add Binding button ─────────────────────────────────
		local containerH = math.max(#bindingRows * (ROW_H + C.Spacing.base), ROW_H)
		local addBtnY = bindCardY - containerH - C.Spacing.normal

		addBtn = Widgets.CreateButton(bindInner, 'Add Binding', 'accent', ADD_BTN_W, BUTTON_H)
		addBtn:ClearAllPoints()
		Widgets.SetPoint(addBtn, 'TOPLEFT', bindInner, 'TOPLEFT', 0, addBtnY)
		addBtn:SetOnClick(function()
			addBindingRow('LeftButton', '', 'spell', '', false, true)
			saveAllBindings()
			updateLayout()
		end)
		local finalY = addBtnY - BUTTON_H - C.Spacing.normal
		bindCardY = finalY

		yOffset = Widgets.EndCard(bindCard, content, bindCardY)

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		local function onResize(newW)
			width      = newW - C.Spacing.normal * 2
			innerWidth = width - Widgets.CARD_PADDING * 2
			bindCard:SetWidth(width)
			rowContainer:SetWidth(innerWidth)
			for _, row in next, bindingRows do
				row:SetWidth(innerWidth)
			end
			updateLayout()
		end

		F.EventBus:Register('SETTINGS_RESIZED', onResize, 'ClickCastingPanel.resize')

		scroll:HookScript('OnHide', function()
			F.EventBus:Unregister('SETTINGS_RESIZED', 'ClickCastingPanel.resize')
		end)
		scroll:HookScript('OnShow', function()
			F.EventBus:Register('SETTINGS_RESIZED', onResize, 'ClickCastingPanel.resize')
			local curW = parent._explicitWidth or parent:GetWidth() or parentW
			onResize(curW)
		end)

		return scroll
	end,
})

F.EventBus:Register('SPEC_CHANGED', function()
	if(not F.Settings._panelFrames) then return end
	F.Settings._panelFrames['clickcasting'] = nil
	if(F.Settings._activePanelId == 'clickcasting') then
		F.Settings.SetActivePanel('clickcasting')
	end
end, 'ClickCastingPanel.specChanged')
