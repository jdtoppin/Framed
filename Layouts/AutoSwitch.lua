local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.AutoSwitch = {}

-- ============================================================
-- State
-- ============================================================

local currentLayout     = nil
local currentContentType = nil
local pendingLayout     = nil
local eventFrame        = nil

-- ============================================================
-- ResolveLayout
-- Fallback chain: Content+Spec → Content+Default → 'Default Solo'
-- ============================================================

function F.AutoSwitch.ResolveLayout(contentType)
	-- Determine current spec ID
	local specID = GetSpecializationInfo and select(1, GetSpecializationInfo(GetSpecialization())) or nil

	-- 1. Content + Spec override
	if(specID and FramedCharDB and FramedCharDB.specOverrides) then
		local key = contentType .. ':' .. tostring(specID)
		local specLayout = FramedCharDB.specOverrides[key]
		if(specLayout and FramedDB and FramedDB.layouts and FramedDB.layouts[specLayout]) then
			return specLayout
		end
	end

	-- 2. Content-based auto-switch mapping
	if(FramedCharDB and FramedCharDB.autoSwitch) then
		local mapped = FramedCharDB.autoSwitch[contentType]
		if(mapped and FramedDB and FramedDB.layouts and FramedDB.layouts[mapped]) then
			return mapped
		end
	end

	-- 3. Final fallback
	return 'Default Solo'
end

-- ============================================================
-- ActivateLayout
-- Switches to the named layout and fires LAYOUT_CHANGED.
-- ============================================================

function F.AutoSwitch.ActivateLayout(layoutName)
	if(currentLayout == layoutName) then return end

	currentLayout = layoutName
	F.EventBus:Fire('LAYOUT_CHANGED', layoutName)
end

-- ============================================================
-- Check
-- Detects current content type, resolves layout, and activates.
-- Defers the switch if the player is in combat.
-- ============================================================

function F.AutoSwitch.Check()
	local contentType = F.ContentDetection.Detect()
	currentContentType = contentType

	local resolved = F.AutoSwitch.ResolveLayout(contentType)

	if(InCombatLockdown and InCombatLockdown()) then
		-- Queue the switch for after combat
		if(resolved ~= currentLayout) then
			pendingLayout = resolved
		end
		return
	end

	pendingLayout = nil
	F.AutoSwitch.ActivateLayout(resolved)
end

-- ============================================================
-- ProcessPending
-- Called on PLAYER_REGEN_ENABLED to apply any queued switch.
-- ============================================================

function F.AutoSwitch.ProcessPending()
	if(not pendingLayout) then return end

	local layout = pendingLayout
	pendingLayout = nil
	F.AutoSwitch.ActivateLayout(layout)
end

-- ============================================================
-- State Getters
-- ============================================================

function F.AutoSwitch.GetCurrentLayout()
	return currentLayout
end

function F.AutoSwitch.GetCurrentContentType()
	return currentContentType
end

-- ============================================================
-- Event Frame
-- ============================================================

eventFrame = CreateFrame('Frame')

eventFrame:RegisterEvent('GROUP_ROSTER_UPDATE')
eventFrame:RegisterEvent('ZONE_CHANGED_NEW_AREA')
eventFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
eventFrame:RegisterEvent('ACTIVE_TALENT_GROUP_CHANGED')
eventFrame:RegisterEvent('PLAYER_REGEN_ENABLED')

eventFrame:SetScript('OnEvent', function(self, event)
	if(event == 'PLAYER_REGEN_ENABLED') then
		F.AutoSwitch.ProcessPending()
	else
		F.AutoSwitch.Check()
	end
end)
