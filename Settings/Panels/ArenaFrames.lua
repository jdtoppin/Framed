local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'arena',
	label   = 'Arena Frames',
	section = 'GROUP_FRAMES',
	order   = 50,
	create  = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'arena')
	end,
})
