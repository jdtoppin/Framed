local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- SpellList — scrollable spell list + spell ID input widget
-- Used by Buffs/Debuffs settings panels to configure tracked
-- spells per indicator category.
-- ============================================================

local ROW_HEIGHT   = 28
local ICON_SIZE    = 20
local ICON_GAP     = 4
local REMOVE_SIZE  = 14
local ARROW_SIZE   = 12
local ARROW_GAP    = 2
local PAD_H        = 6   -- horizontal padding inside each row
local SWATCH_SIZE  = 12  -- per-spell color swatch

-- Use a single arrow icon; flip via TexCoord for the other direction
local ARROW_ICON = [[Interface\AddOns\Framed\Media\Icons\ArrowUp1]]

local function GetSpellData(spellID)
	if(C_Spell and C_Spell.GetSpellInfo) then
		local info = C_Spell.GetSpellInfo(spellID)
		if(info) then return info.name, info.iconID end
	elseif(GetSpellInfo) then
		local name, _, icon = GetSpellInfo(spellID)
		if(name) then return name, icon end
	end
	return nil, nil
end

-- Row pool helpers

local function CreateArrowButton(parent, flipped)
	local btn = CreateFrame('Button', nil, parent)
	Widgets.SetSize(btn, ARROW_SIZE, ARROW_SIZE)

	local tex = btn:CreateTexture(nil, 'ARTWORK')
	tex:SetAllPoints(btn)
	tex:SetTexture(ARROW_ICON)
	-- Crop padding; flip vertically for down arrow
	if(flipped) then
		tex:SetTexCoord(0.15, 0.85, 0.85, 0.15)
	else
		tex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
	end
	local ts = C.Colors.textSecondary
	tex:SetVertexColor(ts[1], ts[2], ts[3], 1)
	btn._tex = tex

	btn:SetScript('OnEnter', function(self)
		local ac = C.Colors.accent
		self._tex:SetVertexColor(ac[1], ac[2], ac[3], 1)
	end)
	btn:SetScript('OnLeave', function(self)
		local s = C.Colors.textSecondary
		self._tex:SetVertexColor(s[1], s[2], s[3], 1)
	end)

	return btn
end

local function CreateRow(parent)
	local row = CreateFrame('Frame', nil, parent)
	row:SetHeight(ROW_HEIGHT)

	-- Spell icon
	local icon = row:CreateTexture(nil, 'ARTWORK')
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint('LEFT', row, 'LEFT', PAD_H, 0)
	row._icon = icon

	-- Spell name
	local nameFS = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textActive)
	nameFS:SetPoint('LEFT', icon, 'RIGHT', ICON_GAP, 0)
	nameFS:SetJustifyH('LEFT')
	row._nameFS = nameFS

	-- Right side controls (right to left): remove, down, up, ID

	-- Remove button ("X", 14x14)
	local removeBtn = CreateFrame('Button', nil, row)
	Widgets.SetSize(removeBtn, REMOVE_SIZE, REMOVE_SIZE)
	removeBtn:SetPoint('RIGHT', row, 'RIGHT', -PAD_H, 0)

	local removeLbl = Widgets.CreateFontString(removeBtn, C.Font.sizeSmall, C.Colors.textSecondary)
	removeLbl:SetPoint('CENTER', removeBtn, 'CENTER', 0, 0)
	removeLbl:SetText('X')
	removeBtn._label = removeLbl

	removeBtn:SetScript('OnEnter', function(self)
		local tc = C.Colors.textActive
		self._label:SetTextColor(tc[1], tc[2], tc[3], 1)
	end)
	removeBtn:SetScript('OnLeave', function(self)
		local s = C.Colors.textSecondary
		self._label:SetTextColor(s[1], s[2], s[3], 1)
	end)
	row._removeBtn = removeBtn

	-- Reorder arrows (side by side, vertically centered in row)
	local downBtn = CreateArrowButton(row, true)
	downBtn:SetPoint('RIGHT', removeBtn, 'LEFT', -PAD_H, 0)
	row._downBtn = downBtn

	local upBtn = CreateArrowButton(row, false)
	upBtn:SetPoint('RIGHT', downBtn, 'LEFT', -ARROW_GAP, 0)
	row._upBtn = upBtn

	-- Spell ID (gray, right-aligned before arrows)
	local idFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
	idFS:SetJustifyH('RIGHT')
	idFS:SetPoint('RIGHT', upBtn, 'LEFT', -PAD_H, 0)
	row._idFS = idFS

	-- Hover highlight (accent color)
	local highlight = row:CreateTexture(nil, 'BACKGROUND')
	highlight:SetAllPoints(row)
	local ac = C.Colors.accent
	highlight:SetColorTexture(ac[1], ac[2], ac[3], 0.08)
	highlight:Hide()
	row._highlight = highlight

	row:EnableMouse(true)
	row:SetScript('OnEnter', function(self)
		self._highlight:Show()
	end)
	row:SetScript('OnLeave', function(self)
		self._highlight:Hide()
	end)

	return row
end

local function AcquireRow(pool, parent)
	for _, r in next, pool do
		if(not r:IsShown()) then r:Show(); return r end
	end
	local r = CreateRow(parent)
	pool[#pool + 1] = r
	return r
end

local function ReleaseAllRows(pool)
	for _, r in next, pool do r:Hide() end
end

--- Create a scrollable spell list widget.
--- @param parent Frame   Parent frame
--- @param width  number  Logical width
--- @param height number  Logical height
--- @return Frame spellList
function Widgets.CreateSpellList(parent, width, height)
	-- Outer container
	local spellList = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	spellList._bgColor     = C.Colors.panel
	spellList._borderColor = C.Colors.border
	Widgets.ApplyBackdrop(spellList, C.Colors.panel, C.Colors.border)
	Widgets.SetSize(spellList, width, height)
	Widgets.ApplyBaseMixin(spellList)

	-- Internal state
	spellList._spells           = {}  -- ordered array of spellIDs
	spellList._rowPool          = {}
	spellList._onChanged        = nil
	spellList._showColorPicker  = false
	spellList._spellColors      = {}

	-- ScrollFrame fills the outer container
	local scroll = Widgets.CreateScrollFrame(spellList, nil, width, height)
	scroll:SetPoint('TOPLEFT',     spellList, 'TOPLEFT',     0, 0)
	scroll:SetPoint('BOTTOMRIGHT', spellList, 'BOTTOMRIGHT', 0, 0)
	spellList._scroll = scroll

	local content = scroll:GetContentFrame()

	-- Empty-state label
	local emptyLabel = Widgets.CreateFontString(spellList, C.Font.sizeNormal, C.Colors.textSecondary)
	emptyLabel:SetPoint('CENTER', spellList, 'CENTER', 0, 0)
	emptyLabel:SetText('No spells configured')
	spellList._emptyLabel = emptyLabel

	local function Layout()
		ReleaseAllRows(spellList._rowPool)

		local spells = spellList._spells
		local count  = #spells

		if(count == 0) then
			spellList._emptyLabel:Show()
			content:SetHeight(1)
			scroll:UpdateScrollRange()
			return
		end

		spellList._emptyLabel:Hide()

		local contentWidth = content:GetWidth()
		if(contentWidth <= 0) then contentWidth = width end

		for i, spellID in next, spells do
			local row = AcquireRow(spellList._rowPool, content)
			row:ClearAllPoints()
			row:SetPoint('TOPLEFT',  content, 'TOPLEFT',  0, -(i - 1) * ROW_HEIGHT)
			row:SetPoint('TOPRIGHT', content, 'TOPRIGHT', 0, -(i - 1) * ROW_HEIGHT)
			row:SetHeight(ROW_HEIGHT)

			-- Populate spell data
			local name, icon = GetSpellData(spellID)
			row._nameFS:SetText(name or ('Spell ' .. spellID))
			row._idFS:SetText('ID: ' .. spellID)

			if(icon) then
				row._icon:SetTexture(icon)
				row._icon:Show()
			else
				row._icon:SetTexture([[Interface\Icons\INV_Misc_QuestionMark]])
				row._icon:Show()
			end

			-- Color swatch (shown when _showColorPicker is true)
			local showSwatch = spellList._showColorPicker
			if(showSwatch) then
				-- Create swatch texture on row if not already present
				if(not row._colorSwatch) then
					local swatch = row:CreateTexture(nil, 'ARTWORK')
					Widgets.SetSize(swatch, SWATCH_SIZE, SWATCH_SIZE)
					row._colorSwatch = swatch
				end
				row._colorSwatch:Show()
				-- Position swatch to the left of the up arrow
				row._colorSwatch:ClearAllPoints()
				row._colorSwatch:SetPoint('RIGHT', row._upBtn, 'LEFT', -PAD_H, 0)
				-- Apply spell color or white default
				local colors = spellList._spellColors or {}
				local c = colors[spellID]
				if(c) then
					row._colorSwatch:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
				else
					row._colorSwatch:SetColorTexture(1, 1, 1, 1)
				end
			elseif(row._colorSwatch) then
				row._colorSwatch:Hide()
			end

			-- Clamp name width so it does not overlap controls
			local idWidth = row._idFS:GetStringWidth()
			local swatchUsed = showSwatch and (SWATCH_SIZE + PAD_H) or 0
			local usedRight = PAD_H + REMOVE_SIZE + PAD_H + ARROW_SIZE + ARROW_GAP + ARROW_SIZE + PAD_H + swatchUsed + idWidth + PAD_H
			local usedLeft  = PAD_H + ICON_SIZE + ICON_GAP
			row._nameFS:SetWidth(math.max(1, (contentWidth - usedLeft - usedRight)))

			-- Wire remove button with confirmation
			local capturedID = spellID
			local capturedName = name or ('Spell ' .. spellID)
			row._removeBtn:SetScript('OnClick', function()
				Widgets.ShowConfirmDialog('Remove Spell', 'Remove ' .. capturedName .. ' (ID: ' .. capturedID .. ')?', function()
					spellList:RemoveSpell(capturedID)
				end)
			end)

			-- Wire move up/down arrows
			local capturedIndex = i
			row._upBtn:SetScript('OnClick', function()
				spellList:MoveSpell(capturedIndex, capturedIndex - 1)
			end)
			row._downBtn:SetScript('OnClick', function()
				spellList:MoveSpell(capturedIndex, capturedIndex + 1)
			end)

			-- Dim arrows at list boundaries
			if(i == 1) then
				row._upBtn._tex:SetAlpha(0.3)
			else
				row._upBtn._tex:SetAlpha(1)
			end
			if(i == count) then
				row._downBtn._tex:SetAlpha(0.3)
			else
				row._downBtn._tex:SetAlpha(1)
			end
		end

		content:SetHeight(count * ROW_HEIGHT)
		scroll:UpdateScrollRange()
	end

	spellList._layout = Layout

	local function NotifyChanged()
		if(spellList._onChanged) then
			-- Pass a shallow copy so callers cannot mutate internal state
			local copy = {}
			for i, v in next, spellList._spells do copy[i] = v end
			spellList._onChanged(copy)
		end
		Layout()
	end

	--- Add a spell by ID. Ignores duplicates.
	--- @param spellID number
	function spellList:AddSpell(spellID)
		spellID = tonumber(spellID)
		if(not spellID) then return end
		for _, id in next, self._spells do
			if(id == spellID) then return end
		end
		self._spells[#self._spells + 1] = spellID
		NotifyChanged()
	end

	--- Remove a spell by ID.
	--- @param spellID number
	function spellList:RemoveSpell(spellID)
		spellID = tonumber(spellID)
		if(not spellID) then return end
		for i, id in next, self._spells do
			if(id == spellID) then
				table.remove(self._spells, i)
				NotifyChanged()
				return
			end
		end
	end

	--- Move a spell from one index to another.
	--- @param fromIndex number Current position
	--- @param toIndex number Target position
	function spellList:MoveSpell(fromIndex, toIndex)
		local spells = self._spells
		if(toIndex < 1 or toIndex > #spells) then return end
		if(fromIndex < 1 or fromIndex > #spells) then return end
		local spell = table.remove(spells, fromIndex)
		table.insert(spells, toIndex, spell)
		NotifyChanged()
	end

	--- Replace the entire spell list.
	--- @param spellIDs table Array of spell IDs
	function spellList:SetSpells(spellIDs)
		self._spells = {}
		if(spellIDs) then
			for _, id in next, spellIDs do
				local n = tonumber(id)
				if(n) then
					-- Deduplicate inline
					local dup = false
					for _, existing in next, self._spells do
						if(existing == n) then dup = true; break end
					end
					if(not dup) then
						self._spells[#self._spells + 1] = n
					end
				end
			end
		end
		Layout()
		-- Deferred re-layout: the inner scroll content width may not be
		-- resolved yet on the first frame, causing 0-width rows.
		C_Timer.After(0, function()
			if(spellList and spellList._layout) then
				spellList._layout()
			end
		end)
	end

	--- Get the current array of configured spell IDs.
	--- @return table
	function spellList:GetSpells()
		local copy = {}
		for i, v in next, self._spells do copy[i] = v end
		return copy
	end

	--- Register a callback called with (spellIDs) whenever the list changes.
	--- @param func function
	function spellList:SetOnChanged(func)
		self._onChanged = func
	end

	--- Enable or disable per-spell color swatches.
	--- @param show boolean
	function spellList:SetShowColorPicker(show)
		self._showColorPicker = show
		Layout()
	end

	--- Set the spell color map used by color swatches.
	--- @param colors table  Map of spellID -> { r, g, b }
	function spellList:SetSpellColors(colors)
		self._spellColors = colors or {}
		Layout()
	end

	--- Get the current spell color map.
	--- @return table
	function spellList:GetSpellColors()
		return self._spellColors or {}
	end

	-- Initial layout (empty state)
	Layout()

	spellList:HookScript('OnShow', function(self)
		C_Timer.After(0, function()
			if(spellList and spellList._layout) then
				spellList._layout()
			end
		end)
	end)

	Widgets.AddToPixelUpdater_OnShow(spellList)

	return spellList
end

-- SpellInput — compact spell ID entry with debounced live preview

local PREVIEW_ICON_SIZE = 16
local INPUT_WIDTH       = 170
local ADD_BTN_WIDTH     = 60
local INPUT_ROW_HEIGHT  = 24
local PREVIEW_HEIGHT    = 20
local DEBOUNCE_DELAY    = 0.3

--- Create a spell ID input widget with live preview.
--- @param parent Frame  Parent frame
--- @param width  number Total logical width
--- @return Frame input
function Widgets.CreateSpellInput(parent, width)
	local totalHeight = INPUT_ROW_HEIGHT + C.Spacing.tight + PREVIEW_HEIGHT

	local container = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(container, width, totalHeight)
	Widgets.ApplyBaseMixin(container)

	container._spellList  = nil
	container._onAdd      = nil
	container._debounce   = nil

	local editBox = Widgets.CreateEditBox(container, nil, INPUT_WIDTH, INPUT_ROW_HEIGHT, 'number')
	editBox:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, 0)
	editBox:SetPlaceholder('Spell ID...')
	container._editBox = editBox

	local addBtn = Widgets.CreateButton(container, 'Add', 'accent', ADD_BTN_WIDTH, INPUT_ROW_HEIGHT)
	addBtn:SetPoint('LEFT', editBox, 'RIGHT', C.Spacing.base, 0)
	container._addBtn = addBtn

	local preview = CreateFrame('Frame', nil, container, 'BackdropTemplate')
	preview:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, -(INPUT_ROW_HEIGHT + C.Spacing.tight))
	preview:SetWidth(INPUT_WIDTH)
	preview:SetHeight(PREVIEW_HEIGHT)
	local pvBg = C.Colors.widget
	preview:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
		insets   = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	preview:SetBackdropColor(pvBg[1], pvBg[2], pvBg[3], pvBg[4] or 1)
	preview:SetBackdropBorderColor(0, 0, 0, 0)
	preview._bgColor     = C.Colors.widget
	preview._borderColor = { 0, 0, 0, 0 }
	preview:EnableMouse(true)
	preview:SetScript('OnEnter', function(self) Widgets.SetBackdropHighlight(self, true) end)
	preview:SetScript('OnLeave', function(self) Widgets.SetBackdropHighlight(self, false) end)
	preview:Hide()
	container._preview = preview

	local previewIcon = preview:CreateTexture(nil, 'ARTWORK')
	previewIcon:SetSize(PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
	previewIcon:SetPoint('LEFT', preview, 'LEFT', PAD_H, 0)
	container._previewIcon = previewIcon

	local previewID = Widgets.CreateFontString(preview, C.Font.sizeSmall, C.Colors.textSecondary)
	previewID:SetPoint('RIGHT', preview, 'RIGHT', -PAD_H, 0)
	previewID:SetJustifyH('RIGHT')
	container._previewID = previewID

	local previewName = Widgets.CreateFontString(preview, C.Font.sizeSmall, C.Colors.textNormal)
	previewName:SetPoint('LEFT', previewIcon, 'RIGHT', ICON_GAP, 0)
	previewName:SetPoint('RIGHT', previewID, 'LEFT', -PAD_H, 0)
	previewName:SetJustifyH('LEFT')
	container._previewName = previewName

	local function SetEditBoxError(hasError)
		local color = hasError and { 0.8, 0.2, 0.2, 1 } or { 0, 0, 0, 1 }
		editBox:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
	end

	local function ShowPreview(spellID)
		local name, icon = GetSpellData(spellID)
		if(name) then
			container._previewIcon:SetTexture(icon or [[Interface\Icons\INV_Misc_QuestionMark]])
			container._previewName:SetText(name)
			container._previewID:SetText('ID: ' .. spellID)
			preview:Show()
			SetEditBoxError(false)
		else
			preview:Hide()
			SetEditBoxError(true)
		end
	end

	local function ClearPreview()
		preview:Hide()
		SetEditBoxError(false)
	end

	local function TryAddSpell()
		local text = editBox:GetText()
		local spellID = tonumber(text)
		if(not spellID or spellID <= 0) then
			SetEditBoxError(true)
			return
		end

		local name = GetSpellData(spellID)
		if(not name) then
			SetEditBoxError(true)
			return
		end

		if(container._spellList) then
			container._spellList:AddSpell(spellID)
		end

		if(container._onAdd) then
			container._onAdd(spellID)
		end

		editBox:SetText('')
		ClearPreview()
	end

	editBox:SetOnTextChanged(function(text)
		-- Cancel previous debounce timer
		if(container._debounce) then
			container._debounce:Cancel()
			container._debounce = nil
		end

		local spellID = tonumber(text)
		if(not spellID or spellID <= 0) then
			ClearPreview()
			return
		end

		container._debounce = C_Timer.NewTimer(DEBOUNCE_DELAY, function()
			container._debounce = nil
			ShowPreview(spellID)
		end)
	end)

	editBox:SetOnEnterPressed(function(_text) TryAddSpell() end)
	addBtn:SetOnClick(function() TryAddSpell() end)

	-- Clicking away from the edit box dismisses the preview
	editBox:SetOnFocusLost(function()
		if(container._debounce) then
			container._debounce:Cancel()
			container._debounce = nil
		end
		ClearPreview()
	end)

	--- Link this input to a SpellList for auto-add on confirm.
	--- @param spellList Frame  A SpellList created by Widgets.CreateSpellList
	function container:SetSpellList(spellList)
		self._spellList = spellList
	end

	--- Optional callback called with (spellID) on successful add.
	--- @param func function
	function container:SetOnAdd(func)
		self._onAdd = func
	end

	return container
end
