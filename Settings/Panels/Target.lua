local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'target',
	label   = 'Target',
	section = 'UNIT_FRAMES',
	order   = 20,
	create  = function(parent)
		F.Settings.SetEditingUnitType('target')
		return F.FrameSettingsBuilder.Create(parent, 'target')
	end,
})
