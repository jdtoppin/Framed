local _, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units        = F.Units        or {}
F.Units.Pinned = F.Units.Pinned or {}

local MAX_SLOTS = 9

-- ============================================================
-- Roster / unit resolution
-- ============================================================

--- Convert UnitName(token) into storage format ('Name' or 'Name-Realm').
local function fullUnitName(token)
	if(not UnitExists(token)) then return nil end
	local name, realm = UnitName(token)
	if(not name) then return nil end
	if(realm and realm ~= '') then
		return name .. '-' .. realm
	end
	return name
end
F.Units.Pinned.FullUnitName = fullUnitName

--- Scan the current group for a player matching storedName.
local function findUnitForName(storedName)
	if(not storedName) then return nil end
	if(IsInRaid()) then
		for i = 1, GetNumGroupMembers() do
			if(fullUnitName('raid' .. i) == storedName) then
				return 'raid' .. i
			end
		end
	elseif(IsInGroup()) then
		for i = 1, GetNumGroupMembers() - 1 do
			if(fullUnitName('party' .. i) == storedName) then
				return 'party' .. i
			end
		end
		if(fullUnitName('player') == storedName) then
			return 'player'
		end
	else
		if(fullUnitName('player') == storedName) then
			return 'player'
		end
	end
	return nil
end
F.Units.Pinned.FindUnitForName = findUnitForName

--- Swap a frame's unit. Updates secure attribute + frame.unit mirror.
--- Combat-safe: returns false if InCombatLockdown prevents SetAttribute.
local function setFrameUnit(frame, token)
	if(InCombatLockdown()) then return false end
	if(token) then
		frame:SetAttribute('unit', token)
		frame.unit = token
	else
		frame:SetAttribute('unit', nil)
		frame.unit = nil
	end
	if(frame.UpdateAllElements) then
		frame:UpdateAllElements('RefreshUnit')
	end
	return true
end

local function slotIdentityText(slot)
	if(not slot) then return nil end
	if(slot.type == 'nametarget') then
		return (slot.value or '?') .. "'s Target"
	elseif(slot.type == 'unit') then
		if(slot.value == 'focus')       then return 'Focus'        end
		if(slot.value == 'focustarget') then return 'Focus Target' end
		return slot.value
	end
	return nil
end

-- ============================================================
-- Derived-unit polling
-- WoW fires no event when a unit's target changes. Polls GUID of each
-- polling slot at 0.2s intervals; fires RefreshUnit on change.
-- ============================================================
local POLL_INTERVAL = 0.2
local pollFrame     = CreateFrame('Frame')
local pollElapsed   = 0
local lastGUIDs     = {}

local function slotNeedsPolling(slot)
	if(not slot) then return false end
	if(slot.type == 'nametarget') then return true end
	if(slot.type == 'unit' and slot.value == 'focustarget') then return true end
	return false
end

local function onPollUpdate(_, elapsed)
	pollElapsed = pollElapsed + elapsed
	if(pollElapsed < POLL_INTERVAL) then return end
	pollElapsed = 0

	local config = F.Units.Pinned.GetConfig()
	local frames = F.Units.Pinned.frames
	if(not config or not frames) then return end
	local slots = config.slots or {}

	for i = 1, MAX_SLOTS do
		local slot  = slots[i]
		local frame = frames[i]
		if(slotNeedsPolling(slot) and frame and frame.unit) then
			local newGUID = UnitGUID(frame.unit)
			if(newGUID ~= lastGUIDs[i]) then
				lastGUIDs[i] = newGUID
				if(frame.UpdateAllElements) then
					frame:UpdateAllElements('RefreshUnit')
				end
			end
		else
			lastGUIDs[i] = nil
		end
	end
end

local function updatePolling()
	local config = F.Units.Pinned.GetConfig()
	if(not config or not config.enabled) then
		pollFrame:SetScript('OnUpdate', nil)
		return
	end

	local slots = config.slots or {}
	for i = 1, MAX_SLOTS do
		if(slotNeedsPolling(slots[i])) then
			pollFrame:SetScript('OnUpdate', onPollUpdate)
			return
		end
	end
	pollFrame:SetScript('OnUpdate', nil)
end
F.Units.Pinned.UpdatePolling = updatePolling

-- ============================================================
-- Config accessor
-- ============================================================
function F.Units.Pinned.GetConfig()
	local presetName = F.PresetManager and F.PresetManager.GetActive()
	if(not presetName) then return nil end
	return F.Config:Get('presets.' .. presetName .. '.unitConfigs.pinned')
end

-- ============================================================
-- Style
-- ============================================================
local function Style(self, unit)
	self:SetFrameStrata('LOW')
	self:RegisterForClicks('AnyUp')
	self._framedUnitType = 'pinned'

	local config = F.StyleBuilder.GetConfig('pinned')
	if(config) then
		F.Widgets.SetSize(self, config.width or 160, config.height or 40)
		F.StyleBuilder.Apply(self, unit, config, 'pinned')
	else
		F.Widgets.SetSize(self, 160, 40)
	end

	if(not self.SlotIdentity) then
		local fs = F.Widgets.CreateFontString(self, F.Constants.Font.sizeSmall, F.Constants.Colors.textSecondary)
		fs:SetPoint('BOTTOM', self, 'TOP', 0, 2)
		fs:SetAlpha(0.7)
		self.SlotIdentity = fs
	end

	if(not self.ReassignGear) then
		local gear = CreateFrame('Button', nil, self)
		gear:SetSize(14, 14)
		gear:SetPoint('TOPRIGHT', self, 'TOPRIGHT', -2, -2)
		gear:SetFrameLevel(self:GetFrameLevel() + 5)

		local icon = gear:CreateTexture(nil, 'OVERLAY')
		icon:SetAllPoints(gear)
		icon:SetTexture(F.Media.GetIcon('Settings'))
		gear._icon = icon

		gear:SetAlpha(0)
		gear:EnableMouse(false)
		gear:RegisterForClicks('LeftButtonUp')

		-- Hide gear during combat
		self:HookScript('OnEnter', function(frame)
			if(InCombatLockdown()) then return end
			if(frame._pinnedSlotIndex) then
				gear:EnableMouse(true)
				gear:SetAlpha(0.8)
			end
		end)
		self:HookScript('OnLeave', function()
			gear:SetAlpha(0)
			gear:EnableMouse(false)
		end)
		gear:SetScript('OnEnter', function(self) self:SetAlpha(1) end)
		gear:SetScript('OnLeave', function(self)
			if(self:GetParent():IsMouseOver()) then
				self:SetAlpha(0.8)
			else
				self:SetAlpha(0)
				self:EnableMouse(false)
			end
		end)

		gear:SetScript('OnClick', function(g)
			local parent = g:GetParent()
			if(parent._pinnedSlotIndex and F.Units.Pinned.OpenAssignmentMenu) then
				F.Units.Pinned.OpenAssignmentMenu(parent._pinnedSlotIndex, parent)
			end
		end)

		self.ReassignGear = gear
	end

	F.Widgets.RegisterForUIScale(self)
end

-- ============================================================
-- Position
-- ============================================================
function F.Units.Pinned.ApplyPosition()
	local anchor = F.Units.Pinned.anchor
	if(not anchor) then return end
	local config = F.Units.Pinned.GetConfig()
	local pos = (config and config.position) or { x = 0, y = 0, anchor = 'CENTER' }
	anchor:ClearAllPoints()
	anchor:SetPoint(pos.anchor or 'CENTER', UIParent, pos.anchor or 'CENTER', pos.x or 0, pos.y or 0)
end

-- ============================================================
-- Empty-slot placeholders
-- Non-secure overlay frames shown when a slot is unassigned.
-- Safe in combat (non-secure, no SetAttribute).
-- ============================================================

local function createPlaceholder(parent, slotIndex)
	local ph = CreateFrame('Button', nil, parent, 'BackdropTemplate')
	ph:SetFrameStrata('MEDIUM')
	ph:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	ph:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
	ph:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)

	local plus = F.Widgets.CreateFontString(ph, 20, F.Constants.Colors.textSecondary)
	plus:SetPoint('CENTER', ph, 'CENTER', 0, 4)
	plus:SetText('+')

	local hint = F.Widgets.CreateFontString(ph, F.Constants.Font.sizeSmall, F.Constants.Colors.textSecondary)
	hint:SetPoint('BOTTOM', ph, 'BOTTOM', 0, 4)
	hint:SetAlpha(0.7)
	hint:SetText('Click to assign')

	ph._slotIndex = slotIndex
	ph:SetAlpha(0)  -- hidden until hover
	ph:RegisterForClicks('LeftButtonUp')

	ph:SetScript('OnEnter', function(self) self:SetAlpha(1) end)
	ph:SetScript('OnLeave', function(self) self:SetAlpha(0) end)

	ph:SetScript('OnClick', function(self)
		if(F.Units.Pinned.OpenAssignmentMenu) then
			F.Units.Pinned.OpenAssignmentMenu(self._slotIndex, self)
		end
	end)

	return ph
end

-- ============================================================
-- Layout (grid)
-- ============================================================
function F.Units.Pinned.Layout()
	local anchor = F.Units.Pinned.anchor
	local frames = F.Units.Pinned.frames
	if(not anchor or not frames) then return end

	local config = F.Units.Pinned.GetConfig()
	if(not config or not config.enabled) then
		anchor:Hide()
		return
	end
	anchor:Show()

	local count   = math.max(1, math.min(config.count   or 3, MAX_SLOTS))
	local columns = math.max(1, math.min(config.columns or 3, count))
	local width   = config.width   or 160
	local height  = config.height  or 40
	local spacing = config.spacing or 2

	for i = 1, MAX_SLOTS do
		local f = frames[i]
		if(f) then
			if(i <= count) then
				local row = math.ceil(i / columns) - 1
				local col = ((i - 1) % columns)
				f:ClearAllPoints()
				f:SetPoint('TOPLEFT', anchor, 'TOPLEFT',
					col * (width + spacing),
					-(row * (height + spacing)))
				F.Widgets.SetSize(f, width, height)
				f:Show()
			else
				f:Hide()
			end
		end
	end

	local rows = math.ceil(count / columns)
	F.Widgets.SetSize(anchor,
		columns * width + (columns - 1) * spacing,
		rows    * height + (rows    - 1) * spacing)

	-- Manage placeholders for active but unassigned slots
	F.Units.Pinned.placeholders = F.Units.Pinned.placeholders or {}
	local phs = F.Units.Pinned.placeholders
	local slots = config.slots or {}

	for i = 1, MAX_SLOTS do
		if(i <= count and not slots[i]) then
			phs[i] = phs[i] or createPlaceholder(anchor, i)
			local f = frames[i]
			phs[i]:ClearAllPoints()
			phs[i]:SetAllPoints(f)
			F.Widgets.SetSize(phs[i], width, height)
			phs[i]:Show()
		elseif(phs[i]) then
			phs[i]:Hide()
		end
	end

	updatePolling()
end

-- ============================================================
-- Resolve
-- ============================================================
local pendingResolve = false

function F.Units.Pinned.Resolve()
	if(InCombatLockdown()) then
		pendingResolve = true
		return
	end
	pendingResolve = false

	local config = F.Units.Pinned.GetConfig()
	local frames = F.Units.Pinned.frames
	if(not config or not frames) then return end

	local slots = config.slots or {}
	for i = 1, MAX_SLOTS do
		local frame = frames[i]
		if(frame) then
			local slot  = slots[i]
			local token = nil
			if(slot) then
				if(slot.type == 'unit') then
					token = slot.value
				elseif(slot.type == 'name') then
					token = findUnitForName(slot.value)
				elseif(slot.type == 'nametarget') then
					local base = findUnitForName(slot.value)
					token = base and (base .. 'target') or nil
				end
			end
			setFrameUnit(frame, token)
			if(frame.SlotIdentity) then
				local labelText = slotIdentityText(slot)
				if(labelText) then
					frame.SlotIdentity:SetText(labelText)
					frame.SlotIdentity:Show()
				else
					frame.SlotIdentity:Hide()
				end
			end
			if(frame.ReassignGear and not slot) then
				frame.ReassignGear:SetAlpha(0)
				frame.ReassignGear:EnableMouse(false)
			end
		end
	end
	updatePolling()
end

-- ============================================================
-- Spawn
-- ============================================================
function F.Units.Pinned.Spawn()
	oUF:RegisterStyle('FramedPinned', Style)
	oUF:SetActiveStyle('FramedPinned')

	local anchor = CreateFrame('Frame', 'FramedPinnedAnchor', UIParent)
	F.Widgets.SetSize(anchor, 1, 1)
	F.Units.Pinned.anchor = anchor
	F.Units.Pinned.ApplyPosition()

	local frames = {}
	for i = 1, MAX_SLOTS do
		local frame = oUF:Spawn('player', 'FramedPinnedFrame' .. i)
		frame:SetParent(anchor)
		frames[i] = frame
		frame._pinnedSlotIndex = i
	end
	F.Units.Pinned.frames = frames

	F.Units.Pinned.Layout()
	F.Units.Pinned.Resolve()
end

--- Placeholder: real implementation lives in Settings/Cards/Pinned.lua
--- and attaches via F.Units.Pinned.OpenAssignmentMenu = ... on card load.
--- When invoked before the card is loaded, print a hint.
function F.Units.Pinned.OpenAssignmentMenu(slotIndex, anchorFrame)
	print('|cff00ccffFramed|r Pinned: open /framed → Pinned to assign slot ' .. slotIndex)
end

-- ============================================================
-- Event registration
-- ============================================================
F.EventBus:Register('GROUP_ROSTER_UPDATE', function()
	F.Units.Pinned.Resolve()
end, 'Pinned.Resolve')

F.EventBus:Register('PLAYER_REGEN_ENABLED', function()
	if(pendingResolve) then
		F.Units.Pinned.Resolve()
	end
end, 'Pinned.CombatFlush')
