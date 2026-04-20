local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id       = 'pinned',
	label    = 'Pinned',
	section  = 'PRESET_SCOPED',
	unitType = 'pinned',
	order    = 65,
	create   = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'pinned')
	end,
})
