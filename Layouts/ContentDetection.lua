local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.ContentDetection = {}

-- ============================================================
-- Detect
-- Returns a C.ContentType string based on current game state.
-- Detection priority: most specific first.
-- ============================================================

function F.ContentDetection.Detect()
	local instanceType
	if(GetInstanceInfo) then
		local _, iType = GetInstanceInfo()
		instanceType = iType
	end

	-- 1. Arena
	local isArena = (IsActiveBattlefieldArena and IsActiveBattlefieldArena())
		or (instanceType == 'arena')
	if(isArena) then
		return C.ContentType.ARENA
	end

	-- 2. Battleground
	local isBG = (C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground())
		or (instanceType == 'pvp')
	if(isBG) then
		return C.ContentType.BATTLEGROUND
	end

	-- 3. Mythic Raid (difficulty ID 16 = Mythic)
	local inRaid = IsInRaid and IsInRaid()
	if(inRaid and instanceType == 'raid') then
		local difficultyID = GetRaidDifficultyID and GetRaidDifficultyID()
		if(difficultyID == 16) then
			return C.ContentType.MYTHIC_RAID
		end

		-- 4. Raid
		return C.ContentType.RAID
	end

	-- 5. World Raid (in raid but not an instanced raid zone)
	if(inRaid and instanceType == 'none') then
		return C.ContentType.WORLD_RAID
	end

	-- 6. Party
	local inGroup = IsInGroup and IsInGroup()
	if(inGroup and not inRaid) then
		return C.ContentType.PARTY
	end

	-- 7. Solo fallback
	return C.ContentType.SOLO
end
