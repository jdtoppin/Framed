local _, Framed = ...
local F = Framed

F.AuraCache = {}

-- Content generation — bumps on any UNIT_AURA for the unit. Used by
-- GetUnitAuras() to invalidate filter-result caches when aura set changes.
local generation = {}

-- Identity generation — bumps only when the unit token may now point at
-- a different entity (reassignment events) or when existing auraInstanceIDs
-- are invalidated at encounter boundaries. Used by AuraState to decide
-- whether a FullRefresh is needed vs. a delta apply.
-- See issue #118: single-gen approach forced FullRefresh on every UNIT_AURA.
local identityGeneration = {}

-- Cache keyed by 'unit\0filter' — each entry is { gen = number, result = table }.
-- Tables are reused across generations to avoid allocation.
local cache = {}

-- Pre-computed key strings to avoid per-call string concatenation.
local keyCache = {}

-- Bump content generation for a single unit token.
local function bump(unit)
	if(unit) then
		generation[unit] = (generation[unit] or 0) + 1
	end
end

-- Bump identity generation for a single unit token. Callers should pair
-- this with bump(unit) when the content also changed (most reassignment
-- events imply a content change too, since auraInstanceIDs are re-keyed).
local function bumpIdentity(unit)
	if(unit) then
		identityGeneration[unit] = (identityGeneration[unit] or 0) + 1
	end
end

-- Raw frame to catch UNIT_AURA plus token-reassignment events before oUF
-- dispatches to elements. Reassignment events (e.g., PLAYER_TARGET_CHANGED)
-- don't fire UNIT_AURA on their own, but the unit token now points at a
-- different entity — any cached data for that token is stale.
local eventFrame = CreateFrame('Frame')
-- Exposed for diagnostics (Core/MemDiag.lua hooks OnEvent here).
F.AuraCache._eventFrame = eventFrame
eventFrame:RegisterEvent('UNIT_AURA')
eventFrame:RegisterEvent('PLAYER_TARGET_CHANGED')
eventFrame:RegisterEvent('PLAYER_FOCUS_CHANGED')
eventFrame:RegisterEvent('UNIT_TARGET')
eventFrame:RegisterEvent('GROUP_ROSTER_UPDATE')
eventFrame:RegisterEvent('ARENA_OPPONENT_UPDATE')
eventFrame:RegisterEvent('INSTANCE_ENCOUNTER_ENGAGE_UNIT')
eventFrame:RegisterEvent('ENCOUNTER_START')
eventFrame:RegisterEvent('ENCOUNTER_END')
eventFrame:RegisterEvent('NAME_PLATE_UNIT_ADDED')
eventFrame:RegisterEvent('NAME_PLATE_UNIT_REMOVED')

eventFrame:SetScript('OnEvent', function(_, event, arg1)
	if(event == 'UNIT_AURA') then
		-- Content-only: auras changed on the same entity. No identity bump —
		-- AuraState should take its delta path, not FullRefresh.
		bump(arg1)
	elseif(event == 'PLAYER_TARGET_CHANGED') then
		bump('target')
		bump('targettarget')
		bumpIdentity('target')
		bumpIdentity('targettarget')
	elseif(event == 'PLAYER_FOCUS_CHANGED') then
		bump('focus')
		bump('focustarget')
		bumpIdentity('focus')
		bumpIdentity('focustarget')
	elseif(event == 'UNIT_TARGET') then
		-- arg1 = unit whose target changed; the subunit token (e.g.,
		-- 'targettarget' when arg1 == 'target') now points somewhere new.
		if(arg1) then
			bump(arg1 .. 'target')
			bumpIdentity(arg1 .. 'target')
		end
	elseif(event == 'GROUP_ROSTER_UPDATE') then
		for i = 1, 4 do
			bump('party' .. i)
			bump('partypet' .. i)
			bumpIdentity('party' .. i)
			bumpIdentity('partypet' .. i)
		end
		for i = 1, 40 do
			bump('raid' .. i)
			bump('raidpet' .. i)
			bumpIdentity('raid' .. i)
			bumpIdentity('raidpet' .. i)
		end
	elseif(event == 'ARENA_OPPONENT_UPDATE') then
		for i = 1, 5 do
			bump('arena' .. i)
			bump('arenapet' .. i)
			bumpIdentity('arena' .. i)
			bumpIdentity('arenapet' .. i)
		end
	elseif(event == 'INSTANCE_ENCOUNTER_ENGAGE_UNIT') then
		for i = 1, 8 do
			bump('boss' .. i)
			bumpIdentity('boss' .. i)
		end
	elseif(event == 'ENCOUNTER_START' or event == 'ENCOUNTER_END') then
		-- 12.0.5 re-randomizes aura instance IDs on encounter boundaries.
		-- Bump both content and identity on every tracked unit so the next
		-- read refreshes from the game's aura list instead of trusting
		-- pre-boundary IDs. GUID doesn't change here, so the identity bump
		-- is the only signal AuraState has to discard its auraInstanceID
		-- keyed caches.
		for unit in next, generation do
			bump(unit)
			bumpIdentity(unit)
		end
	elseif(event == 'NAME_PLATE_UNIT_ADDED' or event == 'NAME_PLATE_UNIT_REMOVED') then
		bump(arg1)
		bumpIdentity(arg1)
	end
end)

--- Current content generation counter for a unit token. Bumped on every
--- UNIT_AURA for that unit. Consumers caching filter results (e.g.
--- GetUnitAuras below) compare against this to detect stale results.
--- @param unit string
--- @return number
function F.AuraCache.GetGeneration(unit)
	return generation[unit] or 0
end

--- Current identity generation counter for a unit token. Bumped only on
--- reassignment events (token now points at a different entity) or on
--- encounter boundaries (auraInstanceID re-randomization). Consumers that
--- hold auraInstanceID-keyed state compare against this to decide whether
--- to full-refresh vs. apply a delta. See #118.
--- @param unit string
--- @return number
function F.AuraCache.GetIdentityGeneration(unit)
	return identityGeneration[unit] or 0
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
