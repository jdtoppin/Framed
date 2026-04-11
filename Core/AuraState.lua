local _, Framed = ...
local F = Framed

F.AuraState = {}

local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID

local function isHelpfulAura(unit, aura)
	if(not aura or not aura.auraInstanceID) then return false end

	if(IsAuraFilteredOutByInstanceID) then
		return not IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, 'HELPFUL')
	end

	return false
end

local function isHarmfulAura(unit, aura)
	if(not aura or not aura.auraInstanceID) then return false end

	if(IsAuraFilteredOutByInstanceID) then
		return not IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, 'HARMFUL')
	end

	return false
end

local AuraState = {}
AuraState.__index = AuraState

function AuraState:MarkHelpfulDirty()
	for _, view in next, self._helpfulViews do
		view.dirty = true
	end
end

function AuraState:MarkHarmfulDirty()
	for _, view in next, self._harmfulViews do
		view.dirty = true
	end
end

function AuraState:EnsureHelpfulView(filter)
	local view = self._helpfulViews[filter]
	if(not view) then
		view = {
			dirty = true,
			list = {},
		}
		self._helpfulViews[filter] = view
	end
	return view
end

function AuraState:EnsureHarmfulView(filter)
	local view = self._harmfulViews[filter]
	if(not view) then
		view = {
			dirty = true,
			list = {},
		}
		self._harmfulViews[filter] = view
	end
	return view
end

function AuraState:FullRefresh(unit)
	self._unit = unit
	self._initialized = true
	wipe(self._helpfulById)
	wipe(self._harmfulById)
	self:MarkHelpfulDirty()
	self:MarkHarmfulDirty()

	if(not unit or not GetAuraSlots or not GetAuraDataBySlot) then return end

	local helpfulResults = { GetAuraSlots(unit, 'HELPFUL') }
	for i = 2, #helpfulResults do
		local aura = GetAuraDataBySlot(unit, helpfulResults[i])
		if(aura and aura.auraInstanceID) then
			self._helpfulById[aura.auraInstanceID] = aura
		end
	end

	local harmfulResults = { GetAuraSlots(unit, 'HARMFUL') }
	for i = 2, #harmfulResults do
		local aura = GetAuraDataBySlot(unit, harmfulResults[i])
		if(aura and aura.auraInstanceID) then
			self._harmfulById[aura.auraInstanceID] = aura
		end
	end
end

function AuraState:EnsureInitialized(unit)
	if(not self._initialized or self._unit ~= unit) then
		self:FullRefresh(unit)
	end
end

function AuraState:ApplyUpdateInfo(unit, updateInfo)
	if(self._lastUpdateInfo == updateInfo and self._lastUpdateUnit == unit) then
		return
	end

	if(not updateInfo or updateInfo.isFullUpdate) then
		self._lastUpdateInfo = updateInfo
		self._lastUpdateUnit = unit
		self:FullRefresh(unit)
		return
	end

	if(not self._initialized or self._unit ~= unit) then
		self._lastUpdateInfo = updateInfo
		self._lastUpdateUnit = unit
		self:FullRefresh(unit)
		return
	end

	self._lastUpdateInfo = updateInfo
	self._lastUpdateUnit = unit

	local helpfulChanged = false
	local harmfulChanged = false

	if(updateInfo.addedAuras) then
		for _, aura in next, updateInfo.addedAuras do
			if(aura and aura.auraInstanceID and isHelpfulAura(unit, aura)) then
				self._helpfulById[aura.auraInstanceID] = aura
				helpfulChanged = true
			end
			if(aura and aura.auraInstanceID and isHarmfulAura(unit, aura)) then
				self._harmfulById[aura.auraInstanceID] = aura
				harmfulChanged = true
			end
		end
	end

	if(updateInfo.updatedAuraInstanceIDs and GetAuraDataByAuraInstanceID) then
		for _, auraInstanceID in next, updateInfo.updatedAuraInstanceIDs do
			local aura = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
			if(aura and aura.auraInstanceID and isHelpfulAura(unit, aura)) then
				self._helpfulById[auraInstanceID] = aura
				helpfulChanged = true
			elseif(self._helpfulById[auraInstanceID]) then
				self._helpfulById[auraInstanceID] = nil
				helpfulChanged = true
			end

			if(aura and aura.auraInstanceID and isHarmfulAura(unit, aura)) then
				self._harmfulById[auraInstanceID] = aura
				harmfulChanged = true
			elseif(self._harmfulById[auraInstanceID]) then
				self._harmfulById[auraInstanceID] = nil
				harmfulChanged = true
			end
		end
	end

	if(updateInfo.removedAuraInstanceIDs) then
		for _, auraInstanceID in next, updateInfo.removedAuraInstanceIDs do
			if(self._helpfulById[auraInstanceID]) then
				self._helpfulById[auraInstanceID] = nil
				helpfulChanged = true
			end
			if(self._harmfulById[auraInstanceID]) then
				self._harmfulById[auraInstanceID] = nil
				harmfulChanged = true
			end
		end
	end

	if(helpfulChanged) then
		self:MarkHelpfulDirty()
	end
	if(harmfulChanged) then
		self:MarkHarmfulDirty()
	end
end

function AuraState:GetHelpful(filter)
	local view = self:EnsureHelpfulView(filter)
	if(not view.dirty) then
		return view.list
	end

	view.dirty = false
	wipe(view.list)

	for auraInstanceID, aura in next, self._helpfulById do
		if(filter == 'HELPFUL'
			or (IsAuraFilteredOutByInstanceID and not IsAuraFilteredOutByInstanceID(self._unit, auraInstanceID, filter))) then
			view.list[#view.list + 1] = aura
		end
	end

	return view.list
end

function AuraState:GetHarmful(filter)
	local view = self:EnsureHarmfulView(filter)
	if(not view.dirty) then
		return view.list
	end

	view.dirty = false
	wipe(view.list)

	for auraInstanceID, aura in next, self._harmfulById do
		if(filter == 'HARMFUL'
			or (IsAuraFilteredOutByInstanceID and not IsAuraFilteredOutByInstanceID(self._unit, auraInstanceID, filter))) then
			view.list[#view.list + 1] = aura
		end
	end

	return view.list
end

function F.AuraState.Create(owner)
	return setmetatable({
		_owner = owner,
		_unit = nil,
		_initialized = false,
		_lastUpdateInfo = nil,
		_lastUpdateUnit = nil,
		_helpfulById = {},
		_helpfulViews = {},
		_harmfulById = {},
		_harmfulViews = {},
	}, AuraState)
end
