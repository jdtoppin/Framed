local addonName, Framed = ...
local F = Framed

-- Mapping of dispel spellIDs to what types they remove.
-- Source: Warcraft Wiki dispel mechanics.
local DISPEL_SPELLS = {
	-- Priest
	[527]    = { Magic = true, Disease = true },  -- Purify
	[528]    = { Disease = true },                 -- Cure Disease (Shadow)
	[32375]  = { Magic = true },                   -- Mass Dispel
	-- Paladin
	[4987]   = { Magic = true, Poison = true, Disease = true }, -- Cleanse
	-- Druid
	[2782]   = { Curse = true, Poison = true },    -- Remove Corruption
	[88423]  = { Magic = true, Curse = true, Poison = true },  -- Nature's Cure (Resto)
	-- Shaman
	[51886]  = { Curse = true },                   -- Cleanse Spirit
	[77130]  = { Magic = true, Curse = true },     -- Purify Spirit (Resto)
	-- Monk
	[115450] = { Magic = true, Poison = true, Disease = true }, -- Detox (MW)
	[218164] = { Poison = true, Disease = true },  -- Detox (BM/WW)
	-- Mage
	[475]    = { Curse = true },                   -- Remove Curse
	-- Evoker
	[365585] = { Magic = true, Poison = true },    -- Expunge (Pres)
	[374251] = { Poison = true },                  -- Cauterizing Flame
}

local canDispel = {}

local function RefreshDispelCapability()
	wipe(canDispel)
	for spellId, types in next, DISPEL_SPELLS do
		if(IsSpellKnown(spellId)) then
			for dispelType in next, types do
				canDispel[dispelType] = true
			end
		end
	end
end

--- Check if the player's current class/spec can dispel a given type.
--- @param dispelType string  'Magic', 'Curse', 'Disease', 'Poison', 'Physical'
--- @return boolean
function F.CanPlayerDispel(dispelType)
	if(not dispelType or dispelType == '' or dispelType == 'Physical') then
		return false  -- Physical/bleeds cannot be dispelled
	end
	return canDispel[dispelType] or false
end

-- Refresh on login and talent changes
local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('ACTIVE_TALENT_GROUP_CHANGED')
frame:SetScript('OnEvent', RefreshDispelCapability)
