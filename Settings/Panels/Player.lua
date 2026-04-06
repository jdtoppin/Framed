local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id       = 'player',
	label    = 'Player',
	section  = 'PRESET_SCOPED',
	unitType = 'player',
	order    = 10,
	create   = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'player')
	end,
})
