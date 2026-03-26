local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.AutoSwitch = {}

local currentPreset
local currentContentType
local pendingPreset

-- ============================================================
-- Resolution chain
-- ============================================================

--- Resolve which preset name to use for a content type.
--- Checks spec overrides first, then autoSwitch mapping.
local function ResolvePresetName(contentType)
	-- 1. Spec override (GetSpecializationInfo returns actual specID like 105, not index 1-4)
	local specIndex = GetSpecialization and GetSpecialization()
	local specID = specIndex and GetSpecializationInfo and select(1, GetSpecializationInfo(specIndex)) or nil
	local specOverrides = F.Config:GetChar('specOverrides')
	if(specOverrides and specID and specOverrides[specID]) then
		local override = specOverrides[specID][contentType]
		if(override) then return override end
	end

	-- 2. Auto-switch mapping
	local autoSwitch = F.Config:GetChar('autoSwitch')
	if(autoSwitch and autoSwitch[contentType]) then
		return autoSwitch[contentType]
	end

	-- 3. Fallback
	return 'Solo'
end

--- Resolve the effective preset data, following derived fallback if needed.
--- Returns presetName (the resolved name) and presetData (the table to use).
--- When a derived preset is not customized, presetName stays as the derived name
--- but presetData points to the fallback's data.
function F.AutoSwitch.ResolvePreset(presetName)
	local presets = F.Config:Get('presets')
	if(not presets) then return presetName, nil end

	local preset = presets[presetName]
	if(not preset) then return presetName, nil end

	-- Derived preset: use fallback data if not customized
	if(preset.fallback and preset.customized == false) then
		local fallbackData = presets[preset.fallback]
		if(fallbackData) then
			return presetName, fallbackData
		end
	end

	return presetName, preset
end

-- ============================================================
-- Activation
-- ============================================================

local function ActivatePreset(presetName)
	if(presetName == currentPreset) then return end
	currentPreset = presetName
	F.EventBus:Fire('PRESET_CHANGED', presetName)
end

function F.AutoSwitch.Check()
	local contentType = F.ContentDetection.Detect()
	currentContentType = contentType

	local presetName = ResolvePresetName(contentType)

	if(InCombatLockdown and InCombatLockdown()) then
		pendingPreset = presetName
		return
	end

	ActivatePreset(presetName)
end

local function ProcessPending()
	if(pendingPreset) then
		ActivatePreset(pendingPreset)
		pendingPreset = nil
	end
end

-- ============================================================
-- Getters
-- ============================================================

function F.AutoSwitch.GetCurrentPreset()
	return currentPreset or 'Solo'
end

function F.AutoSwitch.GetCurrentContentType()
	return currentContentType or C.ContentType.SOLO
end

-- ============================================================
-- Event handling
-- ============================================================

local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('GROUP_ROSTER_UPDATE')
eventFrame:RegisterEvent('ZONE_CHANGED_NEW_AREA')
eventFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
eventFrame:RegisterEvent('ACTIVE_TALENT_GROUP_CHANGED')
eventFrame:RegisterEvent('PLAYER_REGEN_ENABLED')

eventFrame:SetScript('OnEvent', function(self, event)
	if(event == 'PLAYER_REGEN_ENABLED') then
		ProcessPending()
	else
		F.AutoSwitch.Check()
	end
end)

-- Listen for preset data changes (copy/reset) and re-fire PRESET_CHANGED
-- so runtime frames refresh their config
F.EventBus:On('PRESET_DATA_CHANGED', function(presetName)
	if(presetName == currentPreset) then
		F.EventBus:Fire('PRESET_CHANGED', presetName)
	end
end)
