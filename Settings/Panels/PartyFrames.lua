local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.Settings.RegisterPanel({
	id           = 'party',
	label        = 'Party Frames',  -- default label, updated dynamically by sidebar
	section      = 'PRESET_SCOPED',
	order        = 70,
	getUnitType  = function()
		local info = C.PresetInfo[F.Settings.GetEditingPreset()]
		return info and info.groupKey or 'party'
	end,
	create       = function(parent)
		local info = C.PresetInfo[F.Settings.GetEditingPreset()]
		local unitType = info and info.groupKey or 'party'
		return F.FrameSettingsBuilder.Create(parent, unitType)
	end,
})
