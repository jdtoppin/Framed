local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'boss',
	label   = 'Boss',
	section = 'PRESET_SCOPED',
	order   = 60,
	create  = function(parent)
		F.Settings.SetEditingUnitType('boss')
		return F.FrameSettingsBuilder.Create(parent, 'boss')
	end,
})
