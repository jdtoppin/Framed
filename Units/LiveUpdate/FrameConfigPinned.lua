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
		debouncedApply('pinned.layout', function()
			F.Units.Pinned.Layout()
			F.Units.Pinned.Resolve()
		end)
	elseif(key and key:match('^slots')) then
		F.Units.Pinned.Resolve()
		F.Units.Pinned.Layout()
	end
end
F.EventBus:Register('CONFIG_CHANGED', onConfigChanged, 'FrameConfigPinned.CC')

F.EventBus:Register('PRESET_CHANGED', function()
	F.Units.Pinned.ApplyPosition()
	F.Units.Pinned.Layout()
	F.Units.Pinned.Resolve()
end, 'FrameConfigPinned.PresetChanged')
