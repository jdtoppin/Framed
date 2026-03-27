local addonName, Framed = ...
local F = Framed

function F.DisableBlizzardFrames()
	-- Compact raid frame manager
	if(CompactRaidFrameManager) then
		CompactRaidFrameManager:UnregisterAllEvents()
		CompactRaidFrameManager:Hide()
	end

	if(CompactRaidFrameContainer) then
		CompactRaidFrameContainer:UnregisterAllEvents()
		CompactRaidFrameContainer:Hide()
	end

	-- Party member frames
	for i = 1, 4 do
		local frame = _G['PartyMemberFrame' .. i]
		if(frame) then
			frame:UnregisterAllEvents()
			frame:Hide()
			RegisterAttributeDriver(frame, 'state-visibility', 'hide')
		end
	end

	-- Focus frame
	if(FocusFrame) then
		FocusFrame:UnregisterAllEvents()
		FocusFrame:Hide()
	end

	-- Boss frames
	for i = 1, 5 do
		local frame = _G['Boss' .. i .. 'TargetFrame']
		if(frame) then
			frame:UnregisterAllEvents()
			frame:Hide()
		end
	end

	-- Arena enemy frames (oUF does NOT auto-hide these)
	for i = 1, 5 do
		local frame = _G['ArenaEnemyFrame' .. i]
		if(frame) then
			frame:UnregisterAllEvents()
			frame:Hide()
		end
	end

	-- Arena preparation frames
	for i = 1, 5 do
		local frame = _G['ArenaPrepFrame' .. i]
		if(frame) then
			frame:UnregisterAllEvents()
			frame:Hide()
		end
	end
end
