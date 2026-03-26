local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'party',
	label   = 'Party Frames',
	section = 'PRESET_SCOPED',
	order   = 10,
	create  = function(parent)
		F.Settings.SetEditingUnitType('party')
		return F.FrameSettingsBuilder.Create(parent, 'party')
	end,
})
