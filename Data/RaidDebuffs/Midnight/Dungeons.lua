local addonName, Framed = ...
local F = Framed
local P = F.Constants.DebuffPriority

-- Placeholder: commonly tracked M+ debuffs
-- Full per-dungeon data will be curated during testing
-- TODO: Add Undermine.lua for raid boss debuffs

F.RaidDebuffRegistry:Register(240443, P.IMPORTANT)   -- Burst (Explosive affix)
F.RaidDebuffRegistry:Register(209858, P.CRITICAL)     -- Necrotic Wound
F.RaidDebuffRegistry:Register(226512, P.SURVIVAL)     -- Sanguine Ichor
