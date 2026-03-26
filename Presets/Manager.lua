local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.PresetManager = {}

--- Get all preset names in display order.
function F.PresetManager.GetNames()
	return C.PresetOrder
end

--- Get preset info from Constants.
function F.PresetManager.GetInfo(name)
	return C.PresetInfo[name]
end

--- Check if a preset is a base preset.
function F.PresetManager.IsBase(name)
	local info = C.PresetInfo[name]
	return info and info.isBase or false
end

--- Check if a derived preset has been customized.
function F.PresetManager.IsCustomized(name)
	local preset = F.Config:Get('presets.' .. name)
	if(not preset) then return false end
	return preset.customized == true
end

--- Copy all settings from one preset to another.
--- Copies unitConfigs, auras, and positions. Flips customized=true on derived targets.
function F.PresetManager.CopySettings(sourceName, targetName)
	local presets = F.Config:Get('presets')
	if(not presets or not presets[sourceName] or not presets[targetName]) then return false end

	local source = presets[sourceName]
	-- If source is uncustomized derived, copy from its fallback
	local sourceData = source
	if(source.fallback and source.customized == false) then
		sourceData = presets[source.fallback] or source
	end

	local target = presets[targetName]
	target.unitConfigs = F.DeepCopy(sourceData.unitConfigs)
	target.auras = F.DeepCopy(sourceData.auras)
	target.positions = F.DeepCopy(sourceData.positions)

	-- Mark derived preset as customized
	if(target.fallback) then
		target.customized = true
	end

	F.EventBus:Fire('PRESET_DATA_CHANGED', targetName)
	return true
end

--- Reset a derived preset to its fallback defaults.
function F.PresetManager.ResetToDefault(name)
	local presets = F.Config:Get('presets')
	if(not presets or not presets[name]) then return false end

	local preset = presets[name]
	if(not preset.fallback) then return false end  -- can't reset base presets

	-- Copy fresh defaults from fallback
	local defaults = F.PresetDefaults.GetAll()
	local defaultPreset = defaults[name]
	if(not defaultPreset) then return false end

	preset.unitConfigs = F.DeepCopy(defaultPreset.unitConfigs)
	preset.auras = F.DeepCopy(defaultPreset.auras)
	preset.positions = F.DeepCopy(defaultPreset.positions)
	preset.customized = false

	F.EventBus:Fire('PRESET_DATA_CHANGED', name)
	return true
end

--- Mark a derived preset as customized (called on first settings write).
function F.PresetManager.MarkCustomized(presetName)
	local preset = F.Config:Get('presets.' .. presetName)
	if(not preset or not preset.fallback) then return end
	if(preset.customized) then return end
	preset.customized = true
end

-- No rename/delete for the 7 fixed presets. If custom presets are added later,
-- UpdateAutoSwitchReferences would be needed here.
