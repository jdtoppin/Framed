local addonName, Framed = ...
local F = Framed

--- Abbreviate a large number for display.
--- @param value number
--- @return string
function F.AbbreviateNumber(value)
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
