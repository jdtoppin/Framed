local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'raid',
	label   = 'Raid Frames',
	section = 'GROUP_FRAMES',
	order   = 20,
	create  = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'raid')
	end,
})
