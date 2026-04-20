local _, Framed = ...
local F = Framed

local Shared = F.LiveUpdate and F.LiveUpdate.FrameConfigShared
if(not Shared) then return end

local guardConfigChanged = Shared.guardConfigChanged
local debouncedApply     = Shared.debouncedApply

local function onConfigChanged(path)
	local unitType, key = guardConfigChanged(path)
	if(unitType ~= 'pinned') then return end

	if(key == 'position.x' or key == 'position.y' or key == 'position.anchor') then
		debouncedApply('pinned.position', function()
			F.Units.Pinned.ApplyPosition()
			F.Units.Pinned.Layout()
		end)
	elseif(key == 'enabled' or key == 'count' or key == 'columns'
	    or key == 'width' or key == 'height' or key == 'spacing') then
		-- Refresh = Hide → Layout → Resolve → Show atomic. Keeps the 9
		-- frames invisible through the whole transition so the user
		-- never sees them briefly render with their stale 'player' seed
		-- state before Resolve clears the unit on unassigned slots.
		debouncedApply('pinned.layout', F.Units.Pinned.Refresh)
	elseif(key and key:match('^slots')) then
		-- Single-slot path: `slots.N` or `slots.N.<field>`. Only touch frame N
		-- so the other eight don't re-anchor (which flashed their backdrops).
		local slotIndex = tonumber(key:match('^slots%.(%d+)'))
		if(slotIndex) then
			F.Units.Pinned.ApplySlot(slotIndex)
		else
			F.Units.Pinned.Refresh()
		end
	end
end
F.EventBus:Register('CONFIG_CHANGED', onConfigChanged, 'FrameConfigPinned.CC')

F.EventBus:Register('PRESET_CHANGED', function()
	F.Units.Pinned.ApplyPosition()
	F.Units.Pinned.Refresh()
end, 'FrameConfigPinned.PresetChanged')
