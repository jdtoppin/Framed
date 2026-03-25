local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'player',
	label   = 'Player',
	section = 'UNIT_FRAMES',
	order   = 10,
	create  = function(parent)
		F.Settings.SetEditingUnitType('player')
		return F.FrameSettingsBuilder.Create(parent, 'player')
	end,
})
