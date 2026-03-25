local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'battleground',
	label   = 'Battlegrounds',
	section = 'GROUP_FRAMES',
	order   = 30,
	create  = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'battleground')
	end,
})
