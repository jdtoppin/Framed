local addonName, Framed = ...
local F = Framed

--- Secret-safe number abbreviation config (C-level, handles secret values).
--- Uses Blizzard's AbbreviateNumbers API which works with secret numbers.
local _abbreviateConfig = CreateAbbreviateConfig and CreateAbbreviateConfig({
	{ breakpoint = 1000000000, abbreviation = 'B', significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
	{ breakpoint = 1000000,    abbreviation = 'M', significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
	{ breakpoint = 1000,       abbreviation = 'K', significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
})

--- Abbreviate a number for display.  Secret-value safe.
--- @param value number|secretnumber
--- @return string
function F.AbbreviateNumber(value)
	if(_abbreviateConfig) then
		return AbbreviateNumbers(value, { config = _abbreviateConfig })
	end
	-- Fallback for classic or missing API
	if(value >= 1000000) then
		return string.format('%.1fM', value / 1000000)
	elseif(value >= 1000) then
		return string.format('%.0fK', value / 1000)
	else
		return tostring(math.floor(value))
	end
end

--- Format a duration in seconds for display.
--- @param seconds number
--- @return string
function F.FormatDuration(seconds)
	if(seconds >= 3600) then
		return string.format('%dh', math.floor(seconds / 3600))
	elseif(seconds >= 60) then
		return string.format('%dm', math.floor(seconds / 60))
	elseif(seconds >= 1) then
		return string.format('%d', math.ceil(seconds))
	else
		return string.format('%.1f', seconds)
	end
end

--- Deep copy a table recursively.
--- @param src any
--- @return any
function F.DeepCopy(src)
	if(type(src) ~= 'table') then return src end
	local copy = {}
	for k, v in next, src do
		copy[k] = F.DeepCopy(v)
	end
	return copy
end
