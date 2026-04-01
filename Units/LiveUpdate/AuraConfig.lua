local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

-- ============================================================
-- AuraConfig — live-update handlers for presets.*.auras.*
-- ============================================================

local ForEachFrame = F.StyleBuilder.ForEachFrame

-- ============================================================
-- Aura element name map
-- ============================================================

local AURA_ELEMENT_MAP = {
	debuffs        = 'FramedDebuffs',
	externals      = 'FramedExternals',
	defensives     = 'FramedDefensives',
	raidDebuffs    = 'FramedRaidDebuffs',
	dispellable    = 'FramedDispellable',
	targetedSpells = 'FramedTargetedSpells',
	buffs          = 'FramedBuffs',
	lossOfControl  = 'FramedLossOfControl',
	crowdControl   = 'FramedCrowdControl',
	missingBuffs   = 'FramedMissingBuffs',
	privateAuras   = 'FramedPrivateAuras',
}

-- Elements whose config changes require structural Rebuild
local REBUILD_ELEMENTS = {
	buffs          = true,
	debuffs        = true,
	externals      = true,
	defensives     = true,
	raidDebuffs    = true,
	lossOfControl  = true,
	crowdControl   = true,
	missingBuffs   = true,
	privateAuras   = true,
	targetedSpells = true,
}

-- ============================================================
-- Debounce — Tier 2: 0.15s for structural Rebuild
-- ============================================================

local pendingRebuilds = {}

local function debouncedRebuild(element, config)
	local key = tostring(element)
	if(pendingRebuilds[key]) then
		pendingRebuilds[key]:Cancel()
	end
	pendingRebuilds[key] = C_Timer.NewTimer(0.15, function()
		pendingRebuilds[key] = nil
		if(element.Rebuild) then
			element:Rebuild(config)
		end
	end)
end

-- ============================================================
-- Debounce — Tier 1: 0.05s for non-structural changes
-- ============================================================

local pendingUpdates = {}

local function debouncedApply(key, applyFn, ...)
	if(pendingUpdates[key]) then
		pendingUpdates[key]:Cancel()
	end
	local args = { ... }
	pendingUpdates[key] = C_Timer.NewTimer(0.05, function()
		pendingUpdates[key] = nil
		applyFn(unpack(args))
	end)
end

-- ============================================================
-- Path parser
-- Path: presets.<presetName>.auras.<unitType>.<auraType>[.<key>...]
-- ============================================================

local function parseAuraConfigPath(path)
	local editPreset, unitType, auraType, rest = path:match('^presets%.([^%.]+)%.auras%.([^%.]+)%.([^%.]+)(.*)$')
	if(rest) then rest = rest:match('^%.(.+)$') end
	return unitType, auraType, rest, editPreset
end

-- ============================================================
-- Main CONFIG_CHANGED handler
-- ============================================================

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local unitType, auraType, subKey, editPreset = parseAuraConfigPath(path)
	if(not unitType or not auraType) then return end

	-- Only apply when editing the active preset
	if(editPreset and editPreset ~= F.AutoSwitch.GetCurrentPreset()) then return end

	local elementName = AURA_ELEMENT_MAP[auraType]
	if(not elementName) then return end

	-- Enabled toggle
	if(subKey == 'enabled') then
		local config = F.StyleBuilder.GetAuraConfig(unitType, auraType)
		ForEachFrame(unitType, function(frame)
			if(config and config.enabled) then
				if(not frame[elementName]) then
					local setupFn = F.Elements[auraType:sub(1,1):upper() .. auraType:sub(2)]
					if(setupFn and setupFn.Setup) then
						setupFn.Setup(frame, config)
					end
				end
				frame:EnableElement(elementName)
			else
				frame:DisableElement(elementName)
			end
		end)
		return
	end

	-- Structural rebuild
	if(REBUILD_ELEMENTS[auraType]) then
		local config = F.StyleBuilder.GetAuraConfig(unitType, auraType)
		ForEachFrame(unitType, function(frame)
			local element = frame[elementName]
			if(element and element.Rebuild) then
				debouncedRebuild(element, config)
			end
		end)
		return
	end

	-- Non-structural changes (debuffs, externals, etc.)
	local config = F.StyleBuilder.GetAuraConfig(unitType, auraType)
	debouncedApply(auraType .. '.' .. unitType, function()
		ForEachFrame(unitType, function(frame)
			local element = frame[elementName]
			if(element) then
				-- Sync config reference (may change when preset is customized)
				if(element._config) then element._config = config end
				if(config.iconSize) then element._iconSize = config.iconSize end
				if(config.anchor) then
					local a = config.anchor
					if(element._frame) then
						element._frame:ClearAllPoints()
						element._frame:SetPoint(a[1], frame, a[3] or a[1], a[4] or 0, a[5] or 0)
					end
				end
				if(element.ForceUpdate) then
					element:ForceUpdate()
				end
			end
		end)
	end)
end, 'LiveUpdate.AuraConfig')
