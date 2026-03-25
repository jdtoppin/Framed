local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'focus',
	label   = 'Focus',
	section = 'UNIT_FRAMES',
	order   = 40,
	create  = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'focus')
	end,
})
