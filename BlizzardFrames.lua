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

	-- Party member frames. Intentionally NOT calling
	-- RegisterAttributeDriver(frame, 'state-visibility', 'hide') here:
	-- ElvUI (and other unit frame addons) register their own state-visibility
	-- driver on the same PartyMemberFrameN objects. Whichever addon loads
	-- second wins the attribute, and the loser's call can taint the frame
	-- and propagate up the secure-handler chain — which is what caused our
	-- SecureGroupHeader to intermittently drop its layout attrs (party/raid
	-- snapping to 0,0 on reload) and Blizzard defaults to occasionally leak
	-- through. UnregisterAllEvents() alone is enough to neuter these frames;
	-- without PARTY_MEMBERS_CHANGED they can't re-show themselves.
	for i = 1, 4 do
		local frame = _G['PartyMemberFrame' .. i]
		if(frame) then
			frame:UnregisterAllEvents()
			frame:Hide()
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
