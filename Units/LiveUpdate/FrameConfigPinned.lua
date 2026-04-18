local _, Framed = ...
local F = Framed

local Shared = F.LiveUpdate and F.LiveUpdate.FrameConfigShared
if(not Shared) then return end

local guardConfigChanged = Shared.guardConfigChanged
local debouncedApply     = Shared.debouncedApply

local MAX_SLOTS = 9

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
	else
		debouncedApply('pinned.style', function()
			local config = F.StyleBuilder.GetConfig('pinned')
			local frames = F.Units.Pinned.frames
			if(not config or not frames) then return end
			for i = 1, MAX_SLOTS do
				local f = frames[i]
				if(f) then
					F.StyleBuilder.Apply(f, f.unit, config, 'pinned')
					if(f.UpdateAllElements) then f:UpdateAllElements('RefreshStyle') end
				end
			end
		end)
	end
end
F.EventBus:Register('CONFIG_CHANGED', onConfigChanged, 'FrameConfigPinned.CC')

F.EventBus:Register('PRESET_CHANGED', function()
	F.Units.Pinned.ApplyPosition()
	F.Units.Pinned.Layout()
	F.Units.Pinned.Resolve()
end, 'FrameConfigPinned.PresetChanged')
