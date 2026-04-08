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
		F.PresetDefaults.EnsureDefaults()
		self:UnregisterEvent('ADDON_LOADED')
	elseif(event == 'PLAYER_LOGIN') then
		-- Post-spawn initialization (runs after oUF:Factory spawns frames)
		-- Disable Blizzard's default frames
		F.DisableBlizzardFrames()

		-- Apply click-cast bindings
		F.ClickCasting.RefreshAll()

		-- Start auto-switching (detects content type and activates preset)
		F.AutoSwitch.Check()

		-- Enable cast tracker for targeted spells
		if(F.CastTracker) then
			F.CastTracker:Enable()
		end

		-- Minimap icon via LibDataBroker + LibDBIcon
		local LDB = LibStub('LibDataBroker-1.1')
		local LDBIcon = LibStub('LibDBIcon-1.0')
		local dataObj = LDB:NewDataObject('Framed', {
			type = 'launcher',
			text = 'Framed',
			icon = [[Interface\AddOns\Framed\Media\Textures\Logo]],
			OnClick = function(_, button)
				if(button == 'LeftButton') then
					if(F.Settings and F.Settings.Toggle) then
						F.Settings.Toggle()
					end
				elseif(button == 'RightButton') then
					if(F.EditMode.IsActive()) then
						F.EditMode.RequestCancel()
					else
						F.EditMode.Enter()
					end
				end
			end,
			OnTooltipShow = function(tip)
				tip:AddLine('|cff00ccffFramed|r')
				tip:AddLine('Left-click to open settings')
				tip:AddLine('Right-click to toggle edit mode')
			end,
		})
		LDBIcon:Register('Framed', dataObj, FramedDB.minimap)

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

	-- Force initial element updates on all spawned frames.
	-- oUF's initObject enables elements but doesn't call UpdateAllElements;
	-- it relies on PLAYER_ENTERING_WORLD which may have already fired.
	for _, object in next, self.objects do
		if(object.unit and object.UpdateAllElements) then
			object:UpdateAllElements('ForceUpdate')
		end
	end
end)

-- Slash commands
SLASH_FRAMED1 = '/framed'
SLASH_FRAMED2 = '/fr'

SlashCmdList['FRAMED'] = function(msg)
	local trimmed = msg:lower():trim()
	local cmd, arg1 = trimmed:match('^(%S+)%s*(.*)$')
	if(not cmd) then cmd = '' end

	if(cmd == 'version' or cmd == 'v') then
		print('|cff00ccff Framed|r v' .. F.version)
	elseif(cmd == 'config') then
		F.Config:PrintDebug()
	elseif(cmd == 'events') then
		F.EventBus:PrintDebug()
	elseif(cmd == 'edit') then
		if(F.EditMode.IsActive()) then
			F.EditMode.RequestCancel()
		else
			F.EditMode.Enter()
		end
	elseif(cmd == 'reset' and arg1 == 'all') then
		local d = F.Widgets.ShowConfirmDialog(
			'Reset All Settings',
			'This will delete ALL Framed settings, presets, and customizations.\nA backup will be saved — you can restore later with /framed restore.',
			function()
				FramedBackupDB = {
					db        = FramedDB and F.DeepCopy(FramedDB) or nil,
					char      = FramedCharDB and F.DeepCopy(FramedCharDB) or nil,
					timestamp = time(),
				}
				FramedDB = nil
				FramedCharDB = nil
				ReloadUI()
			end,
			nil
		)
		d._message:SetTextColor(1, 0.2, 0.2)
		d._btnYes._label:SetText('Yes, Reset Everything')
		d._btnNo._label:SetText('Cancel')
		d._activeWidth = 400
		d:_LayoutButtons('confirm')
		d:_UpdateHeight()
	elseif(cmd == 'restore') then
		if(not FramedBackupDB or not FramedBackupDB.db) then
			-- Fall back to legacy backup format (pre-timestamped plain table)
			if(FramedBackupDB and not FramedBackupDB.db) then
				F.Widgets.ShowConfirmDialog('Restore Settings', 'Restore settings from last session backup? This will reload the UI.', function()
					FramedDB = F.DeepCopy(FramedBackupDB)
					ReloadUI()
				end)
			else
				print('|cff00ccff Framed|r No backup found. Nothing to restore.')
			end
			return
		end
		local ts = FramedBackupDB.timestamp
		local dateStr = ts and date('%Y-%m-%d %H:%M', ts) or 'unknown date'
		F.Widgets.ShowConfirmDialog(
			'Restore Settings',
			'Restore settings from backup taken on ' .. dateStr .. '?\nThis will overwrite your current configuration.',
			function()
				FramedDB = F.DeepCopy(FramedBackupDB.db)
				FramedCharDB = FramedBackupDB.char and F.DeepCopy(FramedBackupDB.char) or nil
				ReloadUI()
			end,
			nil
		)
	elseif(cmd == 'debugicons') then
		-- Force show all indicator elements on player frame
		local pf = F.Units.Player and F.Units.Player.frame
		if(not pf) then print('|cff00ccff Framed|r No player frame') return end
		print('|cff00ccff Framed|r Player frame unit: ' .. tostring(pf.unit))
		local checks = {
			'GroupRoleIndicator', 'LeaderIndicator', 'AssistantIndicator',
			'CombatIndicator', 'RestingIndicator', 'RaidTargetIndicator',
			'ReadyCheckIndicator', 'PhaseIndicator', 'ResurrectIndicator',
			'SummonIndicator', 'RaidRoleIndicator', 'PvPIndicator',
		}
		for _, name in next, checks do
			local el = pf[name]
			if(el) then
				local w, h = el:GetSize()
				local visible = el:IsVisible()
				local shown = el:IsShown()
				local alpha = el:GetAlpha()
				local tex = el.GetTexture and tostring(el:GetTexture()) or 'n/a'
				local atlas = el.GetAtlas and tostring(el:GetAtlas()) or 'n/a'
				local enabled = pf.IsElementEnabled and pf:IsElementEnabled(name) or '?'
				print(('  %s: enabled=%s vis=%s shown=%s alpha=%.1f size=%dx%d tex=%s atlas=%s'):format(
					name, tostring(enabled), tostring(visible), tostring(shown), alpha, w, h, tex, atlas))
			else
				print('  ' .. name .. ': NOT ON FRAME')
			end
		end
	elseif(cmd == 'help') then
		print('|cff00ccff Framed|r v' .. F.version .. ' — Commands:')
		print('  /framed — Open settings')
		print('  /framed version — Show version')
		print('  /framed config — Print config debug info')
		print('  /framed events — Print registered events')
		print('  /framed edit — Toggle Edit Mode')
		print('  /framed reset all — Reset all settings to defaults (with backup)')
		print('  /framed restore — Restore settings from last session backup')
		print('  /framed debugicons — Debug indicator element state')
	else
		-- Default: open settings
		if(F.Settings and F.Settings.Toggle) then
			F.Settings.Toggle()
		end
	end
end
