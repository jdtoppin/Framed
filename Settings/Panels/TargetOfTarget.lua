local addonName, Framed = ...
local F = Framed

F.Settings.RegisterPanel({
	id      = 'targettarget',
	label   = 'Target of Target',
	section = 'PRESET_SCOPED',
	order   = 30,
	create  = function(parent)
		F.Settings.SetEditingUnitType('targettarget')
		return F.FrameSettingsBuilder.Create(parent, 'targettarget')
	end,
})
