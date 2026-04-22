local _, Framed = ...
local F = Framed

F.AuraState = {}

local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID

-- Classify a single aura into a wrapper entry { aura, flags }.
-- Tier 1 flags are structural AuraData booleans. Per Blizzard's 12.0.x
-- changes, isHelpful / isHarmful / isRaid / isNameplateOnly /
-- isFromPlayerOrPlayerPet are non-secret. isBossAura remains secret on
-- encounter auras and must be guarded with F.IsValueNonSecret to avoid
-- tainted boolean tests.
-- Tier 2 flags use C_UnitAuras filter probes (secret-safe C API).
local function classify(unit, aura, isHelpful)
	local id = aura.auraInstanceID
	local prefix = isHelpful and 'HELPFUL' or 'HARMFUL'

	local flags = {
		isHelpful         = aura.isHelpful         or false,
		isHarmful         = aura.isHarmful         or false,
		isRaid            = aura.isRaid            or false,
		isBossAura        = F.IsValueNonSecret(aura.isBossAura) and aura.isBossAura or false,
		isFromPlayerOrPet = aura.isFromPlayerOrPlayerPet or false,
	}

	flags.isExternalDefensive = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|EXTERNAL_DEFENSIVE') == false
	flags.isImportant         = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|IMPORTANT')          == false
	flags.isPlayerCast        = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|PLAYER')             == false
	flags.isBigDefensive      = isHelpful
	                            and IsAuraFilteredOutByInstanceID(unit, id, 'HELPFUL|BIG_DEFENSIVE') == false
	                            or false
	flags.isRaidDispellable   = not isHelpful
	                            and IsAuraFilteredOutByInstanceID(unit, id, 'HARMFUL|RAID_PLAYER_DISPELLABLE') == false
	                            or false
	flags.isRaidInCombat      = IsAuraFilteredOutByInstanceID(unit, id, prefix .. '|RAID_IN_COMBAT') == false

	return { aura = aura, flags = flags }
end

-- Compound unit tokens (e.g. 'party2target', 'playertarget', 'focustarget')
-- are rejected by C_UnitAuras.GetAuraSlots. Pinned target-chain slots can
-- produce these tokens — skip aura queries for them rather than erroring.
local function isCompoundUnit(unit)
	if(not unit or unit == 'target' or unit == 'pet') then return false end
	return unit:match('target$') ~= nil or unit:match('pet$') ~= nil
end

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

function AuraState:ResetHelpfulMatches()
	for _, matches in next, self._helpfulMatches do
		wipe(matches)
	end
end

function AuraState:ResetHarmfulMatches()
	for _, matches in next, self._harmfulMatches do
		wipe(matches)
	end
end

function AuraState:InvalidateHelpfulMatch(auraInstanceID)
	for _, matches in next, self._helpfulMatches do
		matches[auraInstanceID] = nil
	end
end

function AuraState:InvalidateHarmfulMatch(auraInstanceID)
	for _, matches in next, self._harmfulMatches do
		matches[auraInstanceID] = nil
	end
end

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

function AuraState:ResetHelpfulClassified()
	wipe(self._helpfulClassifiedById)
end

function AuraState:ResetHarmfulClassified()
	wipe(self._harmfulClassifiedById)
end

function AuraState:InvalidateHelpfulClassified(auraInstanceID)
	self._helpfulClassifiedById[auraInstanceID] = nil
end

function AuraState:InvalidateHarmfulClassified(auraInstanceID)
	self._harmfulClassifiedById[auraInstanceID] = nil
end

function AuraState:MarkHelpfulClassifiedDirty()
	self._helpfulClassifiedView.dirty = true
end

function AuraState:MarkHarmfulClassifiedDirty()
	self._harmfulClassifiedView.dirty = true
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

function AuraState:EnsureHelpfulMatches(filter)
	local matches = self._helpfulMatches[filter]
	if(not matches) then
		matches = {}
		self._helpfulMatches[filter] = matches
	end
	return matches
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

function AuraState:EnsureHarmfulMatches(filter)
	local matches = self._harmfulMatches[filter]
	if(not matches) then
		matches = {}
		self._harmfulMatches[filter] = matches
	end
	return matches
end

function AuraState:FullRefresh(unit)
	self._unit = unit
	self._initialized = true
	self._gen = F.AuraCache.GetGeneration(unit)
	wipe(self._helpfulById)
	wipe(self._harmfulById)
	self:ResetHelpfulMatches()
	self:ResetHarmfulMatches()
	self:ResetHelpfulClassified()
	self:ResetHarmfulClassified()
	self:MarkHelpfulDirty()
	self:MarkHarmfulDirty()
	self:MarkHelpfulClassifiedDirty()
	self:MarkHarmfulClassifiedDirty()

	if(not unit or not GetAuraSlots or not GetAuraDataBySlot) then return end
	if(isCompoundUnit(unit)) then return end

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
	-- Compare generation from AuraCache, not the token string — the token
	-- (e.g. 'target') stays identical on retarget even when it now points
	-- at a different entity. AuraCache bumps generation on reassignment.
	if(not self._initialized or self._unit ~= unit or self._gen ~= F.AuraCache.GetGeneration(unit)) then
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

	if(not self._initialized or self._unit ~= unit or self._gen ~= F.AuraCache.GetGeneration(unit)) then
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
				self:InvalidateHelpfulMatch(aura.auraInstanceID)
				self:InvalidateHelpfulClassified(aura.auraInstanceID)
				helpfulChanged = true
			end
			if(aura and aura.auraInstanceID and isHarmfulAura(unit, aura)) then
				self._harmfulById[aura.auraInstanceID] = aura
				self:InvalidateHarmfulMatch(aura.auraInstanceID)
				self:InvalidateHarmfulClassified(aura.auraInstanceID)
				harmfulChanged = true
			end
		end
	end

	if(updateInfo.updatedAuraInstanceIDs and GetAuraDataByAuraInstanceID) then
		for _, auraInstanceID in next, updateInfo.updatedAuraInstanceIDs do
			local aura = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
			if(aura and aura.auraInstanceID and isHelpfulAura(unit, aura)) then
				self._helpfulById[auraInstanceID] = aura
				self:InvalidateHelpfulMatch(auraInstanceID)
				self:InvalidateHelpfulClassified(auraInstanceID)
				helpfulChanged = true
			elseif(self._helpfulById[auraInstanceID]) then
				self._helpfulById[auraInstanceID] = nil
				self:InvalidateHelpfulMatch(auraInstanceID)
				self:InvalidateHelpfulClassified(auraInstanceID)
				helpfulChanged = true
			end

			if(aura and aura.auraInstanceID and isHarmfulAura(unit, aura)) then
				self._harmfulById[auraInstanceID] = aura
				self:InvalidateHarmfulMatch(auraInstanceID)
				self:InvalidateHarmfulClassified(auraInstanceID)
				harmfulChanged = true
			elseif(self._harmfulById[auraInstanceID]) then
				self._harmfulById[auraInstanceID] = nil
				self:InvalidateHarmfulMatch(auraInstanceID)
				self:InvalidateHarmfulClassified(auraInstanceID)
				harmfulChanged = true
			end
		end
	end

	if(updateInfo.removedAuraInstanceIDs) then
		for _, auraInstanceID in next, updateInfo.removedAuraInstanceIDs do
			if(self._helpfulById[auraInstanceID]) then
				self._helpfulById[auraInstanceID] = nil
				self:InvalidateHelpfulMatch(auraInstanceID)
				self:InvalidateHelpfulClassified(auraInstanceID)
				helpfulChanged = true
			end
			if(self._harmfulById[auraInstanceID]) then
				self._harmfulById[auraInstanceID] = nil
				self:InvalidateHarmfulMatch(auraInstanceID)
				self:InvalidateHarmfulClassified(auraInstanceID)
				harmfulChanged = true
			end
		end
	end

	if(helpfulChanged) then
		self:MarkHelpfulDirty()
		self:MarkHelpfulClassifiedDirty()
	end
	if(harmfulChanged) then
		self:MarkHarmfulDirty()
		self:MarkHarmfulClassifiedDirty()
	end
end

function AuraState:GetHelpful(filter)
	local view = self:EnsureHelpfulView(filter)
	if(not view.dirty) then
		return view.list
	end

	view.dirty = false
	wipe(view.list)

	if(filter == 'HELPFUL') then
		for _, aura in next, self._helpfulById do
			view.list[#view.list + 1] = aura
		end
		return view.list
	end

	local matches = self:EnsureHelpfulMatches(filter)

	for auraInstanceID, aura in next, self._helpfulById do
		local include = matches[auraInstanceID]
		if(include == nil and IsAuraFilteredOutByInstanceID) then
			include = not IsAuraFilteredOutByInstanceID(self._unit, auraInstanceID, filter)
			matches[auraInstanceID] = include
		end
		if(include) then
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

	if(filter == 'HARMFUL') then
		for _, aura in next, self._harmfulById do
			view.list[#view.list + 1] = aura
		end
		return view.list
	end

	local matches = self:EnsureHarmfulMatches(filter)

	for auraInstanceID, aura in next, self._harmfulById do
		local include = matches[auraInstanceID]
		if(include == nil and IsAuraFilteredOutByInstanceID) then
			include = not IsAuraFilteredOutByInstanceID(self._unit, auraInstanceID, filter)
			matches[auraInstanceID] = include
		end
		if(include) then
			view.list[#view.list + 1] = aura
		end
	end

	return view.list
end

function AuraState:GetHelpfulClassified()
	local view = self._helpfulClassifiedView
	if(not view.dirty) then
		return view.list
	end

	view.dirty = false
	wipe(view.list)

	for id, aura in next, self._helpfulById do
		local entry = self._helpfulClassifiedById[id]
		if(not entry) then
			entry = classify(self._unit, aura, true)
			self._helpfulClassifiedById[id] = entry
		end
		view.list[#view.list + 1] = entry
	end

	return view.list
end

function AuraState:GetHarmfulClassified()
	local view = self._harmfulClassifiedView
	if(not view.dirty) then
		return view.list
	end

	view.dirty = false
	wipe(view.list)

	for id, aura in next, self._harmfulById do
		local entry = self._harmfulClassifiedById[id]
		if(not entry) then
			entry = classify(self._unit, aura, false)
			self._harmfulClassifiedById[id] = entry
		end
		view.list[#view.list + 1] = entry
	end

	return view.list
end

function AuraState:GetClassifiedByInstanceID(auraInstanceID)
	local entry = self._helpfulClassifiedById[auraInstanceID]
	if(entry) then
		return entry
	end

	local aura = self._helpfulById[auraInstanceID]
	if(aura) then
		entry = classify(self._unit, aura, true)
		self._helpfulClassifiedById[auraInstanceID] = entry
		return entry
	end

	entry = self._harmfulClassifiedById[auraInstanceID]
	if(entry) then
		return entry
	end

	aura = self._harmfulById[auraInstanceID]
	if(aura) then
		entry = classify(self._unit, aura, false)
		self._harmfulClassifiedById[auraInstanceID] = entry
		return entry
	end

	return nil
end

-- Exposed for diagnostics (e.g. Core/MemDiag.lua monkey-patches methods here).
F.AuraState._mt = AuraState

function F.AuraState.Create(owner)
	return setmetatable({
		_owner = owner,
		_unit = nil,
		_initialized = false,
		_gen = 0,
		_lastUpdateInfo = nil,
		_lastUpdateUnit = nil,
		_helpfulById = {},
		_helpfulViews = {},
		_helpfulMatches = {},
		_helpfulClassifiedById = {},
		_helpfulClassifiedView = { dirty = true, list = {} },
		_harmfulById = {},
		_harmfulViews = {},
		_harmfulMatches = {},
		_harmfulClassifiedById = {},
		_harmfulClassifiedView = { dirty = true, list = {} },
	}, AuraState)
end
