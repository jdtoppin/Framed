local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'pet',
	label   = 'Pet',
	section = 'UNIT_FRAMES',
	order   = 50,
	create  = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'pet')
	end,
})
