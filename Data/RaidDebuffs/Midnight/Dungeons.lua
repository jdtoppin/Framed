local addonName, Framed = ...
local F = Framed
local P = F.Constants.DebuffPriority

-- Server-filtered via HARMFUL|RAID flag — debuffs appear without registry entries.
-- Registry entries here provide priority overrides (CRITICAL/IMPORTANT/SURVIVAL)
-- so high-priority debuffs sort above others in the display.
-- TODO: Add priority overrides after testing:
--   Raids: Dreamrift (1 boss), Voidspire (6 bosses), March on Quel'Danas (2 bosses),
--          World Bosses (Cragpine, Lu'ashal, Predaxas, Thorm'belan)
--   M+ S1: Magisters' Terrace, Maisara Caverns, Nexus-Point Xenas, Windrunner Spire,
--           Algeth'ar Academy, Seat of the Triumvirate, Skyreach, Pit of Saron
