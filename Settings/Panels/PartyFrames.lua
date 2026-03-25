local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'party',
	label   = 'Party Frames',
	section = 'GROUP_FRAMES',
	order   = 10,
	create  = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'party')
	end,
})
