local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id       = 'targettarget',
	label    = 'Target of Target',
	section  = 'PRESET_SCOPED',
	unitType = 'targettarget',
	order    = 30,
	create   = function(parent)
		return F.FrameSettingsBuilder.Create(parent, 'targettarget')
	end,
})
