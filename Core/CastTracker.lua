local addonName, Framed = ...
local F = Framed

F.CastTracker = {}

-- ============================================================
-- Local state
-- ============================================================

local UnitIsUnit = UnitIsUnit
local UnitExists = UnitExists
local UnitIsEnemy = UnitIsEnemy
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local C_Spell = C_Spell
local strfind = string.find
local wipe = wipe
local GetTime = GetTime

local casts = {}
local registeredFrames = {}
local useSecretPath = false

local eventFrame = CreateFrame('Frame')
eventFrame:Hide()

local recheckFrame = CreateFrame('Frame')
recheckFrame:Hide()

local recheck = {}

-- ============================================================
-- Forward declarations
-- ============================================================

local CheckUnitCast
local Reset
local BroadcastUpdate
local SafeUnitIsUnit
local GetTargetUnitID_Safe

-- ============================================================
-- Check if a source unit is casting at a group member
-- ============================================================

CheckUnitCast = function(sourceUnit, isRecheck)
	if(not UnitIsEnemy('player', sourceUnit)) then return end

	local sourceKey = sourceUnit
	local previousTarget

	if(casts[sourceKey]) then
		previousTarget = casts[sourceKey].targetUnit
		if(casts[sourceKey].endTime <= GetTime()) then
			casts[sourceKey] = nil
			BroadcastUpdate()
			previousTarget = nil
		end
	end

	-- Query cast info: UnitCastingInfo or UnitChannelInfo
	local name, _, texture, startTimeMS, endTimeMS, _, _, _, spellId = UnitCastingInfo(sourceUnit)
	local isChanneling = false
	if(not name) then
		name, _, texture, startTimeMS, endTimeMS, _, _, spellId = UnitChannelInfo(sourceUnit)
		isChanneling = true
	end

	if(not name) then return end

	-- Get icon: C_Spell.GetSpellTexture is C-level and accepts secret spellId
	if(C_Spell and C_Spell.GetSpellTexture and spellId) then
		local tex = C_Spell.GetSpellTexture(spellId)
		if(tex) then texture = tex end
	end

	-- Determine importance (priority signal, not hard filter)
	local isImportant = false
	if(C_Spell and C_Spell.IsSpellImportant and spellId) then
		local result = C_Spell.IsSpellImportant(spellId)
		if(not F.IsValueNonSecret(result)) then
			-- Secret boolean — treat as important
			isImportant = true
		elseif(result) then
			isImportant = true
		end
	end

	-- Time values may be secret
	local startTime, endTime
	if(F.IsValueNonSecret(startTimeMS) and F.IsValueNonSecret(endTimeMS)) then
		startTime = startTimeMS / 1000
		endTime = endTimeMS / 1000
	else
		startTime = GetTime()
		endTime = GetTime() + 3
	end

	-- Update or create cast entry
	if(casts[sourceKey]) then
		casts[sourceKey].startTime = startTime
		casts[sourceKey].endTime = endTime
		casts[sourceKey].icon = texture
		casts[sourceKey].spellId = spellId
		casts[sourceKey].isImportant = isImportant
		casts[sourceKey].isChanneling = isChanneling
	else
		casts[sourceKey] = {
			startTime    = startTime,
			endTime      = endTime,
			icon         = texture,
			isChanneling = isChanneling,
			sourceUnit   = sourceUnit,
			spellId      = spellId,
			isImportant  = isImportant,
			targetUnit   = nil,
			recheck      = 0,
		}
	end

	-- Resolve target
	local targetUnit, isSecret = GetTargetUnitID_Safe(sourceUnit .. 'target')

	if(isSecret) then
		useSecretPath = true
		casts[sourceKey].targetUnit = nil
		BroadcastUpdate()
	else
		casts[sourceKey].targetUnit = targetUnit
		BroadcastUpdate()
	end

	-- Schedule recheck (target can change mid-cast)
	if(not isRecheck) then
		if(not recheck[sourceKey]) then
			recheck[sourceKey] = sourceUnit
		end
		recheckFrame:Show()
	end

	if(not useSecretPath and previousTarget and previousTarget ~= targetUnit) then
		BroadcastUpdate()
	end
end

-- ============================================================
-- Secret-safe UnitIsUnit
-- ============================================================

SafeUnitIsUnit = function(a, b)
	local result = UnitIsUnit(a, b)
	if(not F.IsValueNonSecret(result)) then return false end
	return result
end

-- ============================================================
-- Group iteration helper
-- ============================================================

GetTargetUnitID_Safe = function(targetToken)
	if(SafeUnitIsUnit(targetToken, 'player')) then return 'player', false end
	if(UnitExists('pet') and SafeUnitIsUnit(targetToken, 'pet')) then return 'pet', false end

	if(IsInRaid()) then
		for i = 1, GetNumGroupMembers() do
			local unit = 'raid' .. i
			if(SafeUnitIsUnit(targetToken, unit)) then return unit, false end
			local petUnit = 'raidpet' .. i
			if(UnitExists(petUnit) and SafeUnitIsUnit(targetToken, petUnit)) then return petUnit, false end
		end
	else
		for i = 1, 4 do
			local unit = 'party' .. i
			if(UnitExists(unit) and SafeUnitIsUnit(targetToken, unit)) then return unit, false end
			local petUnit = 'partypet' .. i
			if(UnitExists(petUnit) and SafeUnitIsUnit(targetToken, petUnit)) then return petUnit, false end
		end
	end

	-- Check if UnitIsUnit is returning secrets (not just nil/no target)
	if(UnitExists(targetToken)) then
		local result = UnitIsUnit(targetToken, 'player')
		if(not F.IsValueNonSecret(result)) then
			return nil, true -- target exists but results are secret
		end
	end

	return nil, false
end

-- ============================================================
-- Broadcast ForceUpdate to all registered frames
-- ============================================================

BroadcastUpdate = function()
	for _, frame in next, registeredFrames do
		local element = frame.FramedTargetedSpells
		if(element and element.ForceUpdate) then
			element.ForceUpdate(element)
		end
	end
end

-- ============================================================
-- State reset
-- ============================================================

Reset = function()
	wipe(casts)
	wipe(recheck)
	useSecretPath = false
	recheckFrame:Hide()
	BroadcastUpdate()
end

-- ============================================================
-- Register / Unregister frames
-- ============================================================

function F.CastTracker:Register(frame)
	for _, f in next, registeredFrames do
		if(f == frame) then return end
	end
	registeredFrames[#registeredFrames + 1] = frame
end

function F.CastTracker:Unregister(frame)
	for i, f in next, registeredFrames do
		if(f == frame) then
			table.remove(registeredFrames, i)
			return
		end
	end
end

-- ============================================================
-- Query API
-- ============================================================

function F.CastTracker:IsSecretPath()
	return useSecretPath
end

function F.CastTracker:GetAllActiveCasts()
	local result = {}
	local now = GetTime()
	for sourceKey, castInfo in next, casts do
		if(castInfo.endTime > now) then
			result[#result + 1] = castInfo
		else
			casts[sourceKey] = nil
		end
	end
	table.sort(result, function(a, b)
		if(a.isImportant ~= b.isImportant) then
			return a.isImportant
		end
		return a.startTime < b.startTime
	end)
	return result
end

function F.CastTracker:GetCastsOnUnit(unit)
	local result = {}
	local now = GetTime()
	for sourceKey, castInfo in next, casts do
		if(castInfo.endTime > now) then
			if(castInfo.targetUnit == unit) then
				result[#result + 1] = castInfo
			end
		else
			casts[sourceKey] = nil
		end
	end
	table.sort(result, function(a, b)
		if(a.isImportant ~= b.isImportant) then
			return a.isImportant
		end
		return a.startTime < b.startTime
	end)
	return result
end

-- ============================================================
-- Event handler
-- ============================================================

eventFrame:SetScript('OnEvent', function(_, event, sourceUnit)
	if(event == 'ENCOUNTER_END' or event == 'PLAYER_REGEN_ENABLED' or event == 'PLAYER_ENTERING_WORLD') then
		Reset()
		return
	end

	-- Filter soft-target units
	if(sourceUnit and strfind(sourceUnit, '^soft')) then return end

	if(event == 'PLAYER_TARGET_CHANGED') then
		CheckUnitCast('target')

	elseif(event == 'UNIT_SPELLCAST_START'
		or event == 'UNIT_SPELLCAST_CHANNEL_START'
		or event == 'UNIT_SPELLCAST_DELAYED'
		or event == 'UNIT_SPELLCAST_CHANNEL_UPDATE'
		or event == 'NAME_PLATE_UNIT_ADDED') then
		CheckUnitCast(sourceUnit)

	elseif(event == 'UNIT_SPELLCAST_STOP'
		or event == 'UNIT_SPELLCAST_INTERRUPTED'
		or event == 'UNIT_SPELLCAST_FAILED'
		or event == 'UNIT_SPELLCAST_CHANNEL_STOP') then
		local sourceKey = sourceUnit
		if(casts[sourceKey]) then
			casts[sourceKey] = nil
			BroadcastUpdate()
		end

	elseif(event == 'NAME_PLATE_UNIT_REMOVED') then
		local sourceKey = sourceUnit
		if(casts[sourceKey]) then
			casts[sourceKey] = nil
			BroadcastUpdate()
		end
	end
end)

-- ============================================================
-- Recheck OnUpdate (0.1s interval, up to 6 rechecks)
-- ============================================================

recheckFrame:SetScript('OnUpdate', function(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if(self.elapsed < 0.1) then return end
	self.elapsed = 0

	local empty = true

	for sourceKey, unit in next, recheck do
		if(casts[sourceKey]) then
			casts[sourceKey].recheck = casts[sourceKey].recheck + 1
			if(casts[sourceKey].recheck >= 6) then
				recheck[sourceKey] = nil
			else
				empty = false
				if(useSecretPath) then
					CheckUnitCast(unit, true)
				else
					local recheckRequired
					if(not casts[sourceKey].targetUnit) then
						recheckRequired = UnitExists(unit .. 'target')
					else
						recheckRequired = not SafeUnitIsUnit(unit .. 'target', casts[sourceKey].targetUnit)
					end
					if(recheckRequired) then
						CheckUnitCast(unit, true)
					end
				end
			end
		else
			recheck[sourceKey] = nil
		end
	end

	if(empty) then
		self:Hide()
	end
end)

-- ============================================================
-- Enable / Disable the tracker globally
-- ============================================================

function F.CastTracker:Enable()
	eventFrame:RegisterEvent('UNIT_SPELLCAST_START')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_STOP')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_DELAYED')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_FAILED')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_INTERRUPTED')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_CHANNEL_START')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_CHANNEL_STOP')
	eventFrame:RegisterEvent('UNIT_SPELLCAST_CHANNEL_UPDATE')
	eventFrame:RegisterEvent('PLAYER_TARGET_CHANGED')
	eventFrame:RegisterEvent('NAME_PLATE_UNIT_ADDED')
	eventFrame:RegisterEvent('NAME_PLATE_UNIT_REMOVED')
	eventFrame:RegisterEvent('ENCOUNTER_END')
	eventFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
	eventFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
end

function F.CastTracker:Disable()
	Reset()
	eventFrame:UnregisterAllEvents()
end
