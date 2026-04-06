local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id       = 'target',
	label    = 'Target',
	section  = 'PRESET_SCOPED',
	unitType = 'target',
	order    = 20,
	create   = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'target')
	end,
})
