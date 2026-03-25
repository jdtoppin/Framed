local addonName, Framed = ...
local F = Framed

F.Data = F.Data or {}
F.Data.ExternalSpellIDs = {
	[33206]  = true,  -- Pain Suppression
	[47788]  = true,  -- Guardian Spirit
	[102342] = true,  -- Ironbark
	[97462]  = true,  -- Rallying Cry
	[196718] = true,  -- Darkness
	[6940]   = true,  -- Blessing of Sacrifice
	[31821]  = true,  -- Aura Mastery
	[62618]  = true,  -- Power Word: Barrier
}
F.Data.DefensiveSpellIDs = {
	[45438]  = true,  -- Ice Block
	[642]    = true,  -- Divine Shield
	[31224]  = true,  -- Cloak of Shadows
	[48792]  = true,  -- Icebound Fortitude
	[47585]  = true,  -- Dispersion
	[61336]  = true,  -- Survival Instincts
	[871]    = true,  -- Shield Wall
	[12975]  = true,  -- Last Stand
}
