local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}

local MAX_SLOTS   = 9
local ROLES       = { 'TANK', 'HEALER', 'DAMAGER' }
local ROLE_LABELS = { TANK = 'Tanks', HEALER = 'Healers', DAMAGER = 'DPS' }

-- ============================================================
-- Helpers
-- ============================================================

local function getClassColor(class)
	local oUF = F.oUF
	if(oUF and oUF.colors and oUF.colors.class and oUF.colors.class[class]) then
		return oUF.colors.class[class]:GetRGB()
	end
	return 0.5, 0.5, 0.5
end

local function fullUnitName(token)
	if(not UnitExists(token)) then return nil end
	local name, realm = UnitName(token)
	if(not name) then return nil end
	if(realm and realm ~= '') then return name .. '-' .. realm end
	return name
end

local function scanRoster()
	local roster = {}
	local function add(token)
		if(not UnitExists(token)) then return end
		roster[#roster + 1] = {
			name  = fullUnitName(token),
			token = token,
			class = select(2, UnitClass(token)),
			role  = UnitGroupRolesAssigned(token) or 'DAMAGER',
		}
	end
	if(IsInRaid()) then
		for i = 1, GetNumGroupMembers() do add('raid' .. i) end
	elseif(IsInGroup()) then
		for i = 1, GetNumGroupMembers() - 1 do add('party' .. i) end
		add('player')
	else
		add('player')
	end
	return roster
end

-- Collect the exact dropdown values already assigned to other slots so only
-- the matching row is hidden — the NAME row and its TARGET sibling are
-- independent selections and must not block each other.
local function assignedValuesSet(slots, excludeIndex)
	local set = {}
	for i = 1, MAX_SLOTS do
		if(i ~= excludeIndex) then
			local s = slots and slots[i]
			if(s and s.value) then
				if(s.type == 'name') then
					set['NAME:' .. s.value] = true
				elseif(s.type == 'nametarget') then
					set['TARGET:' .. s.value] = true
				end
			end
		end
	end
	return set
end

-- ============================================================
-- Row decorators (class colors + non-selectable headers)
-- ============================================================

local HEADER_PREFIX = '__hdr'

local function isHeaderValue(value)
	return type(value) == 'string' and value:sub(1, #HEADER_PREFIX) == HEADER_PREFIX
end

local function headerDecorator(row)
	row._label:SetTextColor(0.6, 0.6, 0.6, 1)
	row:SetScript('OnEnter', function() end)
	row:SetScript('OnLeave', function() end)
	row:SetScript('OnMouseDown', function() end)
end

local function classColorDecorator(classToken, indent)
	return function(row, item)
		if(indent) then
			row._label:SetText('    ' .. (item.text or ''))
		end
		local r, g, b = getClassColor(classToken)
		row._label:SetTextColor(r, g, b, 1)
	end
end

-- ============================================================
-- Build dropdown items from a slots table
-- ============================================================

local function buildItems(slotIndex, slots)
	local blocked = assignedValuesSet(slots, slotIndex)
	local items = {}

	-- Unit references
	items[#items + 1] = { text = '— Unit References —', value = '__hdr_unit', _decorateRow = headerDecorator }
	items[#items + 1] = { text = 'Focus',        value = 'FOCUS' }
	items[#items + 1] = { text = 'Focus Target', value = 'FOCUSTARGET' }

	-- Role-grouped roster
	local roster = scanRoster()
	local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }
	for _, p in next, roster do
		local bucket = byRole[p.role] or byRole.DAMAGER
		bucket[#bucket + 1] = p
	end

	for _, roleToken in next, ROLES do
		local bucket = byRole[roleToken]
		if(bucket and #bucket > 0) then
			items[#items + 1] = {
				text  = '— ' .. ROLE_LABELS[roleToken] .. ' —',
				value = '__hdr_' .. roleToken,
				_decorateRow = headerDecorator,
			}
			for _, p in next, bucket do
				if(p.name) then
					local nameValue   = 'NAME:' .. p.name
					local targetValue = 'TARGET:' .. p.name
					if(not blocked[nameValue]) then
						items[#items + 1] = {
							text  = p.name,
							value = nameValue,
							_decorateRow = classColorDecorator(p.class, false),
						}
					end
					if(not blocked[targetValue]) then
						items[#items + 1] = {
							text  = p.name .. "'s Target",
							value = targetValue,
							_decorateRow = classColorDecorator(p.class, true),
						}
					end
				end
			end
		end
	end

	-- Unassign
	items[#items + 1] = { text = '— None —',  value = '__hdr_none', _decorateRow = headerDecorator }
	items[#items + 1] = { text = '(Unassign)', value = 'UNASSIGN' }

	return items
end

-- ============================================================
-- Value <-> slot conversion
-- ============================================================

-- Return nil for an empty slot so the dropdown treats it as "no value selected"
-- instead of matching the '(Unassign)' row at the bottom of the list — that
-- match would trigger the scroll-to-selected logic and open the list already
-- scrolled past the Unit References / Focus rows at the top.
local function slotToValue(slot)
	if(not slot) then return nil end
	if(slot.type == 'unit' and slot.value == 'focus')       then return 'FOCUS' end
	if(slot.type == 'unit' and slot.value == 'focustarget') then return 'FOCUSTARGET' end
	if(slot.type == 'name')                                 then return 'NAME:' .. slot.value end
	if(slot.type == 'nametarget')                           then return 'TARGET:' .. slot.value end
	return nil
end

local function valueToSlot(value)
	if(value == 'UNASSIGN')    then return nil end
	if(value == 'FOCUS')       then return { type = 'unit', value = 'focus' } end
	if(value == 'FOCUSTARGET') then return { type = 'unit', value = 'focustarget' } end
	local name = value:match('^NAME:(.+)$')
	if(name) then return { type = 'name', value = name } end
	local tgtName = value:match('^TARGET:(.+)$')
	if(tgtName) then return { type = 'nametarget', value = tgtName } end
	return nil
end

-- ============================================================
-- Preset-scoped read/write
-- ============================================================

-- Normalize any legacy string-keyed entries ('1' → 1). Config:Set paths are
-- dot-split into string keys, so earlier builds that wrote slots.<i> through
-- Config:Set left the entries under string keys; readers use numeric keys
-- throughout so those writes were invisible until normalized.
local function normalizeSlotKeys(slots)
	if(type(slots) ~= 'table') then return slots end
	for k, v in next, slots do
		if(type(k) == 'string') then
			local n = tonumber(k)
			if(n and slots[n] == nil) then
				slots[n] = v
			end
			slots[k] = nil
		end
	end
	return slots
end

local function readSlotsFor(presetName)
	if(not presetName) then return nil end
	local cfg = F.Config:Get('presets.' .. presetName .. '.unitConfigs.pinned')
	return cfg and normalizeSlotKeys(cfg.slots)
end

local function writeSlot(presetName, slotIndex, value)
	if(not presetName) then return end
	local basePath = 'presets.' .. presetName .. '.unitConfigs.pinned.slots'
	local slots    = F.Config:Get(basePath)
	if(type(slots) ~= 'table') then
		F.Config:Set(basePath, {})
		slots = F.Config:Get(basePath)
	end
	normalizeSlotKeys(slots)

	local newSlot = valueToSlot(value)
	local oldSlot = slots[slotIndex]
	slots[slotIndex] = newSlot

	-- Mutating the table directly bypasses Config:Set's dot-path expansion,
	-- which would otherwise coerce the slot index to a string key.
	local path = basePath .. '.' .. slotIndex
	F.EventBus:Fire('CONFIG_CHANGED', path, newSlot, oldSlot)
	F.EventBus:Fire('CONFIG_CHANGED:presets', path, newSlot, oldSlot)
	F.PresetManager.MarkCustomized(presetName)
end

-- ============================================================
-- In-world assignment dropdown (overrides Units/Pinned.lua stub)
-- Called from the gear icon on assigned slots and the placeholder
-- on empty slots. Binds to the currently-active preset.
-- ============================================================

function F.Units.Pinned.OpenAssignmentMenu(slotIndex, anchorFrame)
	if(InCombatLockdown()) then
		print('|cff00ccffFramed|r Pinned: cannot reassign during combat')
		return
	end

	local presetName = F.AutoSwitch.GetCurrentPreset()
	if(not presetName) then return end

	local slots = readSlotsFor(presetName) or {}
	Widgets.OpenPopupMenu(anchorFrame, buildItems(slotIndex, slots), slotToValue(slots[slotIndex]), function(value)
		if(isHeaderValue(value)) then return end
		writeSlot(presetName, slotIndex, value)
	end)
end

-- ============================================================
-- Settings card — per-slot list bound to the editing preset
-- ============================================================

local ROW_H = 28

local function renderSlotRow(parent, slotIndex, cardY, width)
	local row = CreateFrame('Frame', nil, parent)
	row:SetSize(width, ROW_H)

	local label = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textPrimary)
	label:SetPoint('LEFT', row, 'LEFT', 0, 0)
	label:SetText('Slot ' .. slotIndex)
	label:SetWidth(60)

	local dd = Widgets.CreateDropdown(row, width - 72)
	dd:ClearAllPoints()
	dd:SetPoint('LEFT', label, 'RIGHT', 12, 0)

	local function refresh()
		local presetName = F.Settings.GetEditingPreset()
		local slots = readSlotsFor(presetName) or {}
		dd:SetItems(buildItems(slotIndex, slots))
		local value = slotToValue(slots[slotIndex])
		dd:SetValue(value)
		-- Empty slots send nil (to avoid auto-scrolling to the '(Unassign)' row);
		-- paint a muted placeholder on the button so the user still sees state.
		if(value == nil) then
			dd._label:SetText('(Unassign)')
			local ts = C.Colors.textSecondary
			dd._label:SetTextColor(ts[1], ts[2], ts[3], ts[4] or 1)
		end
	end

	dd:SetOnSelect(function(value)
		if(isHeaderValue(value)) then
			refresh()
			return
		end
		writeSlot(F.Settings.GetEditingPreset(), slotIndex, value)
	end)

	refresh()
	row._refresh = refresh
	return row
end

function F.SettingsCards.Pinned(parent, width, unitType, getConfig, setConfig)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	local rows = {}

	local function rebuild()
		for _, r in next, rows do r:Hide(); r:SetParent(nil) end
		rows = {}

		local presetName = F.Settings.GetEditingPreset()
		local cfg = presetName and F.Config:Get('presets.' .. presetName .. '.unitConfigs.pinned')
		if(not cfg) then
			Widgets.EndCard(card, parent, cardY)
			return
		end
		local y = cardY
		for i = 1, MAX_SLOTS do
			local row = renderSlotRow(inner, i, y, innerW)
			rows[i] = row
			y = B.PlaceWidget(row, inner, y, ROW_H)
		end

		Widgets.EndCard(card, parent, y)
	end

	rebuild()

	F.EventBus:Register('CONFIG_CHANGED', function(path)
		if(not path) then return end
		-- Slot changes keep the same 9 rows — just refresh their dropdowns.
		-- Destroying and recreating every row on each assign/unassign caused
		-- a visible texture flash across all 9 settings widgets.
		if(path:match('unitConfigs%.pinned%.slots')) then
			for _, r in next, rows do
				if(r._refresh) then r._refresh() end
			end
		end
	end, 'PinnedCard.CC')

	F.EventBus:Register('GROUP_ROSTER_UPDATE', function()
		for _, r in next, rows do
			if(r._refresh) then r._refresh() end
		end
	end, 'PinnedCard.Roster')

	return card
end
