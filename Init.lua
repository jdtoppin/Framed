local addonName, Framed = ...
local F = Framed

-- Version
F.version = '0.3.0-alpha'

-- oUF stores itself as ns.oUF in its init.lua (where ns is the second vararg
-- from ..., which is our Framed namespace table). So Framed.oUF is already
-- populated after Libs/oUF/oUF.xml loads — no global oUF variable is needed.
assert(Framed.oUF, 'Framed: oUF failed to load. Check that Libs/oUF/ is intact.')

-- Make namespace accessible for debugging without tainting _G
-- Use rawset to avoid triggering taint propagation
rawset(_G, 'FramedAddon', Framed)

-- Event frame for addon lifecycle
local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('ADDON_LOADED')
eventFrame:RegisterEvent('PLAYER_LOGIN')
eventFrame:RegisterEvent('PLAYER_LOGOUT')
eventFrame:RegisterEvent('ACTIVE_TALENT_GROUP_CHANGED')

eventFrame:SetScript('OnEvent', function(self, event, arg1)
	if(event == 'ADDON_LOADED' and arg1 == addonName) then
		F.Config:Initialize()
		self:UnregisterEvent('ADDON_LOADED')
	elseif(event == 'PLAYER_LOGIN') then
		-- Post-spawn initialization (runs after oUF:Factory spawns frames)
		-- Disable Blizzard's default frames
		F.DisableBlizzardFrames()

		-- Apply click-cast bindings
		F.ClickCasting.RefreshAll()

		-- Initialize default presets
		F.PresetDefaults.EnsureDefaults()

		-- Start auto-switching (detects content type and activates preset)
		F.AutoSwitch.Check()

		-- Enable cast tracker for targeted spells
		if(F.CastTracker) then
			F.CastTracker:Enable()
		end

		F.EventBus:Fire('PLAYER_LOGIN')

		-- First-run wizard
		if(not F.Config:Get('general.wizardCompleted')) then
			C_Timer.After(1, function()
				F.Onboarding.ShowWizard()
			end)
		end

		self:UnregisterEvent('PLAYER_LOGIN')
	elseif(event == 'PLAYER_LOGOUT') then
		-- Snapshot config to backup SavedVariable for recovery
		FramedBackupDB = F.DeepCopy(FramedDB)
	elseif(event == 'ACTIVE_TALENT_GROUP_CHANGED') then
		F.ClickCasting.RefreshAll()
	end
end)

-- ============================================================
-- Spawn all frames via oUF:Factory
-- This runs in oUF's own PLAYER_LOGIN handler in a clean
-- (untainted) execution context, which is required for
-- SecureGroupHeaderTemplate SetAttribute calls.
-- ============================================================

local oUF = F.oUF
oUF:Factory(function(self)
	-- Register styles and spawn all unit frames
	F.Units.Player.Spawn()
	F.Units.Target.Spawn()
	F.Units.TargetTarget.Spawn()
	F.Units.Focus.Spawn()
	F.Units.Pet.Spawn()
	F.Units.Party.Spawn()
	F.Units.Raid.Spawn()
	F.Units.Boss.Spawn()
	F.Units.Arena.Spawn()
end)

-- Slash commands
SLASH_FRAMED1 = '/framed'
SLASH_FRAMED2 = '/fr'

SlashCmdList['FRAMED'] = function(msg)
	local cmd = msg:lower():trim()

	if(cmd == 'version' or cmd == 'v') then
		print('|cff00ccff Framed|r v' .. F.version)
	elseif(cmd == 'config') then
		F.Config:PrintDebug()
	elseif(cmd == 'events') then
		F.EventBus:PrintDebug()
	elseif(cmd == 'edit') then
		if(F.EditMode.IsActive()) then
			F.EditMode.Cancel()
		else
			F.EditMode.Enter()
		end
	elseif(cmd == 'restore') then
		if(not FramedBackupDB) then
			print('|cff00ccff Framed|r No backup found. A backup is created each time you log out.')
			return
		end
		F.Widgets.ShowConfirmDialog('Restore Settings', 'Restore settings from your last session? This will reload the UI.', function()
			FramedDB = F.DeepCopy(FramedBackupDB)
			ReloadUI()
		end)
	elseif(cmd == 'help') then
		print('|cff00ccff Framed|r v' .. F.version .. ' — Commands:')
		print('  /framed — Open settings')
		print('  /framed version — Show version')
		print('  /framed config — Print config debug info')
		print('  /framed events — Print registered events')
		print('  /framed edit — Toggle Edit Mode')
		print('  /framed restore — Restore settings from last session backup')
	else
		-- Default: open settings
		if(F.Settings and F.Settings.Toggle) then
			F.Settings.Toggle()
		end
	end
end
