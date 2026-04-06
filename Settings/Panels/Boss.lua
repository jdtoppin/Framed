local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id       = 'boss',
	label    = 'Boss',
	section  = 'PRESET_SCOPED',
	unitType = 'boss',
	order    = 60,
	create   = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'boss')
	end,
})
