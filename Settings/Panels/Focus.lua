local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id       = 'focus',
	label    = 'Focus',
	section  = 'PRESET_SCOPED',
	unitType = 'focus',
	order    = 40,
	create   = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'focus')
	end,
})
