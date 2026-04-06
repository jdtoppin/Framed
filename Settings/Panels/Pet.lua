local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id       = 'pet',
	label    = 'Pet',
	section  = 'PRESET_SCOPED',
	unitType = 'pet',
	order    = 50,
	create   = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'pet')
	end,
})
