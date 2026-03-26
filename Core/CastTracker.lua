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

-- ============================================================
-- Secret-safe UnitIsUnit
-- ============================================================

local function SafeUnitIsUnit(a, b)
	local result = UnitIsUnit(a, b)
	if(not F.IsValueNonSecret(result)) then return false end
	return result
end

-- ============================================================
-- Group iteration helper
-- ============================================================

local function GetTargetUnitID_Safe(targetToken)
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
