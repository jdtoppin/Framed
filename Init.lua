local addonName, Framed = ...
local F = Framed

-- Version
F.version = '0.1.0-alpha'

-- oUF reference (populated after oUF loads via TOC order)
F.oUF = oUF

-- Addon namespace is globally accessible for debugging
_G['Framed'] = Framed

-- Event frame for addon lifecycle
local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('ADDON_LOADED')
eventFrame:RegisterEvent('PLAYER_LOGIN')
eventFrame:RegisterEvent('ACTIVE_TALENT_GROUP_CHANGED')

eventFrame:SetScript('OnEvent', function(self, event, arg1)
	if(event == 'ADDON_LOADED' and arg1 == addonName) then
		F.Config:Initialize()
		self:UnregisterEvent('ADDON_LOADED')
	elseif(event == 'PLAYER_LOGIN') then
		-- Spawn all unit frames
		F.Units.Player.Spawn()
		F.Units.Target.Spawn()
		F.Units.TargetTarget.Spawn()
		F.Units.Focus.Spawn()
		F.Units.Pet.Spawn()
		F.Units.Party.Spawn()
		F.Units.Raid.Spawn()
		F.Units.Boss.Spawn()
		F.Units.Arena.Spawn()

		-- Disable Blizzard's default frames
		F.DisableBlizzardFrames()

		-- Apply click-cast bindings
		F.ClickCasting.RefreshAll()

		-- Initialize default layouts
		F.LayoutDefaults.EnsureDefaults()

		-- Start auto-switching (detects content type and activates layout)
		F.AutoSwitch.Check()

		F.EventBus:Fire('PLAYER_LOGIN')
		self:UnregisterEvent('PLAYER_LOGIN')
	elseif(event == 'ACTIVE_TALENT_GROUP_CHANGED') then
		F.ClickCasting.RefreshAll()
	end
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
	elseif(cmd == 'help') then
		print('|cff00ccff Framed|r v' .. F.version .. ' — Commands:')
		print('  /framed — Open settings')
		print('  /framed version — Show version')
		print('  /framed config — Print config debug info')
		print('  /framed events — Print registered events')
		print('  /framed edit — Toggle Edit Mode')
	else
		-- Default: open settings
		if(F.Settings and F.Settings.Toggle) then
			F.Settings.Toggle()
		end
	end
end
