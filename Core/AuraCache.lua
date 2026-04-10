local _, Framed = ...
local F = Framed

F.AuraCache = {}

-- Generation counter per unit — bumped on each UNIT_AURA event.
local generation = {}

-- Cache keyed by 'unit\0filter' — each entry is { gen = number, result = table }.
-- Tables are reused across generations to avoid allocation.
local cache = {}

-- Raw frame to catch UNIT_AURA before oUF dispatches to elements.
local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('UNIT_AURA')
eventFrame:SetScript('OnEvent', function(_, _, unit)
	if(unit) then
		generation[unit] = (generation[unit] or 0) + 1
	end
end)

--- Drop-in replacement for C_UnitAuras.GetUnitAuras(unit, filter).
--- Returns the cached result if another element already queried the same
--- (unit, filter) pair during this UNIT_AURA cycle.
--- @param unit string
--- @param filter string
--- @return table
function F.AuraCache.GetUnitAuras(unit, filter)
	local gen = generation[unit] or 0
	local key = unit .. '\0' .. filter
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
