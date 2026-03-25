local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'party',
	label   = 'Party Frames',
	section = 'GROUP_FRAMES',
	order   = 10,
	create  = function(parent)
		F.Settings.SetEditingUnitType('party')
		return F.FrameSettingsBuilder.Create(parent, 'party')
	end,
})
