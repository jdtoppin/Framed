local _, Framed = ...
local F = Framed

F.AuraState = {}

local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID

local function isHelpfulAura(unit, aura)
	if(not aura or not aura.auraInstanceID) then return false end

	if(F.IsValueNonSecret(aura.isHelpful)) then
		return aura.isHelpful
	end

	if(IsAuraFilteredOutByInstanceID) then
		return not IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, 'HELPFUL')
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

function AuraState:FullRefresh(unit)
	self._unit = unit
	self._initialized = true
	wipe(self._helpfulById)
	self:MarkHelpfulDirty()

	if(not unit or not GetAuraSlots or not GetAuraDataBySlot) then return end

	local results = { GetAuraSlots(unit, 'HELPFUL') }
	for i = 2, #results do
		local aura = GetAuraDataBySlot(unit, results[i])
		if(aura and aura.auraInstanceID) then
			self._helpfulById[aura.auraInstanceID] = aura
		end
	end
end

function AuraState:EnsureInitialized(unit)
	if(not self._initialized or self._unit ~= unit) then
		self:FullRefresh(unit)
	end
end

function AuraState:ApplyUpdateInfo(unit, updateInfo)
	if(not updateInfo or updateInfo.isFullUpdate) then
		self:FullRefresh(unit)
		return
	end

	if(not self._initialized or self._unit ~= unit) then
		self:FullRefresh(unit)
		return
	end

	local changed = false

	if(updateInfo.addedAuras) then
		for _, aura in next, updateInfo.addedAuras do
			if(aura and aura.auraInstanceID and isHelpfulAura(unit, aura)) then
				self._helpfulById[aura.auraInstanceID] = aura
				changed = true
			end
		end
	end

	if(updateInfo.updatedAuraInstanceIDs and GetAuraDataByAuraInstanceID) then
		for _, auraInstanceID in next, updateInfo.updatedAuraInstanceIDs do
			local aura = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
			if(aura and aura.auraInstanceID and isHelpfulAura(unit, aura)) then
				self._helpfulById[auraInstanceID] = aura
				changed = true
			elseif(self._helpfulById[auraInstanceID]) then
				self._helpfulById[auraInstanceID] = nil
				changed = true
			end
		end
	end

	if(updateInfo.removedAuraInstanceIDs) then
		for _, auraInstanceID in next, updateInfo.removedAuraInstanceIDs do
			if(self._helpfulById[auraInstanceID]) then
				self._helpfulById[auraInstanceID] = nil
				changed = true
			end
		end
	end

	if(changed) then
		self:MarkHelpfulDirty()
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

function F.AuraState.Create(owner)
	return setmetatable({
		_owner = owner,
		_unit = nil,
		_initialized = false,
		_helpfulById = {},
		_helpfulViews = {},
	}, AuraState)
end
