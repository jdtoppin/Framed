local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'focus',
	label   = 'Focus',
	section = 'PRESET_SCOPED',
	order   = 40,
	create  = function(parent)
		F.Settings.SetEditingUnitType('focus')
		return F.FrameSettingsBuilder.Create(parent, 'focus')
	end,
})
