local _, Framed = ...
local F = Framed

F.AuraCache = {}

-- Generation counter per unit — bumped on each UNIT_AURA event.
local generation = {}

-- Cache keyed by 'unit\0filter' — each entry is { gen = number, result = table }.
-- Tables are reused across generations to avoid allocation.
local cache = {}

-- Pre-computed key strings to avoid per-call string concatenation.
local keyCache = {}

-- Bump generation for a single unit token.
local function bump(unit)
	if(unit) then
		generation[unit] = (generation[unit] or 0) + 1
	end
end

-- Raw frame to catch UNIT_AURA plus token-reassignment events before oUF
-- dispatches to elements. Reassignment events (e.g., PLAYER_TARGET_CHANGED)
-- don't fire UNIT_AURA on their own, but the unit token now points at a
-- different entity — any cached data for that token is stale.
local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('UNIT_AURA')
eventFrame:RegisterEvent('PLAYER_TARGET_CHANGED')
eventFrame:RegisterEvent('PLAYER_FOCUS_CHANGED')
eventFrame:RegisterEvent('UNIT_TARGET')
eventFrame:RegisterEvent('GROUP_ROSTER_UPDATE')
eventFrame:RegisterEvent('ARENA_OPPONENT_UPDATE')
eventFrame:RegisterEvent('INSTANCE_ENCOUNTER_ENGAGE_UNIT')
eventFrame:RegisterEvent('NAME_PLATE_UNIT_ADDED')
eventFrame:RegisterEvent('NAME_PLATE_UNIT_REMOVED')

eventFrame:SetScript('OnEvent', function(_, event, arg1)
	if(event == 'UNIT_AURA') then
		bump(arg1)
	elseif(event == 'PLAYER_TARGET_CHANGED') then
		bump('target')
		bump('targettarget')
	elseif(event == 'PLAYER_FOCUS_CHANGED') then
		bump('focus')
		bump('focustarget')
	elseif(event == 'UNIT_TARGET') then
		-- arg1 = unit whose target changed; the subunit token (e.g.,
		-- 'targettarget' when arg1 == 'target') now points somewhere new.
		if(arg1) then
			bump(arg1 .. 'target')
		end
	elseif(event == 'GROUP_ROSTER_UPDATE') then
		for i = 1, 4 do
			bump('party' .. i)
			bump('partypet' .. i)
		end
		for i = 1, 40 do
			bump('raid' .. i)
			bump('raidpet' .. i)
		end
	elseif(event == 'ARENA_OPPONENT_UPDATE') then
		for i = 1, 5 do
			bump('arena' .. i)
			bump('arenapet' .. i)
		end
	elseif(event == 'INSTANCE_ENCOUNTER_ENGAGE_UNIT') then
		for i = 1, 8 do
			bump('boss' .. i)
		end
	elseif(event == 'NAME_PLATE_UNIT_ADDED' or event == 'NAME_PLATE_UNIT_REMOVED') then
		bump(arg1)
	end
end)

--- Current generation counter for a unit token. Bumped whenever cached
--- data for that token may be stale (UNIT_AURA or token reassignment).
--- Consumers that hold their own cache can compare against this to
--- detect when they need to invalidate.
--- @param unit string
--- @return number
function F.AuraCache.GetGeneration(unit)
	return generation[unit] or 0
end

--- Drop-in replacement for C_UnitAuras.GetUnitAuras(unit, filter).
--- Returns the cached result if another element already queried the same
--- (unit, filter) pair during this UNIT_AURA cycle.
--- @param unit string
--- @param filter string
--- @return table
function F.AuraCache.GetUnitAuras(unit, filter)
	local gen = generation[unit] or 0
	local unitKeys = keyCache[unit]
	if(not unitKeys) then
		unitKeys = {}
		keyCache[unit] = unitKeys
	end
	local key = unitKeys[filter]
	if(not key) then
		key = unit .. '\0' .. filter
		unitKeys[filter] = key
	end
	local entry = cache[key]

	if(entry and entry.gen == gen) then
		return entry.result
	end

	local result = C_UnitAuras.GetUnitAuras(unit, filter)

	if(entry) then
		-- Reuse existing table to avoid allocation
		entry.gen = gen
		entry.result = result
	else
		cache[key] = { gen = gen, result = result }
	end

	return result
end
