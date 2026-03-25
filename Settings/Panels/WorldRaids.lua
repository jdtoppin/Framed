local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'worldraid',
	label   = 'World Raids',
	section = 'GROUP_FRAMES',
	order   = 40,
	create  = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'worldraid')
	end,
})
