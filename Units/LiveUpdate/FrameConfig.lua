local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

-- ============================================================
-- FrameConfig — live-update handlers for unitConfigs.*
-- Listens on CONFIG_CHANGED, parses unitConfigs.<unitType>.<key>,
-- iterates matching frames via F.StyleBuilder.ForEachFrame().
-- ============================================================

local ForEachFrame = F.StyleBuilder.ForEachFrame

-- ============================================================
-- Combat queue for group layout (SetAttribute locked in combat)
-- ============================================================

local pendingGroupChanges = {}
local combatQueueStatus

local function applyOrQueue(header, attr, value)
	if(InCombatLockdown()) then
		pendingGroupChanges[#pendingGroupChanges + 1] = { header, attr, value }
		if(combatQueueStatus) then
			combatQueueStatus:SetText('Changes queued — will apply after combat')
			combatQueueStatus:Show()
		end
	else
		header:SetAttribute(attr, value)
	end
end

F.EventBus:Register('PLAYER_REGEN_ENABLED', function()
	for _, change in next, pendingGroupChanges do
		change[1]:SetAttribute(change[2], change[3])
	end
	wipe(pendingGroupChanges)
	if(combatQueueStatus) then
		combatQueueStatus:Hide()
	end
end, 'LiveUpdate.CombatQueue')

-- ============================================================
-- Debounce (Tier 1: 0.05s for non-structural changes)
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
-- Status icon element map
-- ============================================================

local STATUS_ELEMENT_MAP = {
	role       = 'GroupRoleIndicator',
	leader     = 'LeaderIndicator',
	readyCheck = 'ReadyCheckIndicator',
	raidIcon   = 'RaidTargetIndicator',
	combat     = 'CombatIndicator',
	resting    = 'RestingIndicator',
	phase      = 'PhaseIndicator',
	resurrect  = 'ResurrectIndicator',
	summon     = 'SummonIndicator',
	raidRole   = 'RaidRoleIndicator',
	pvp        = 'PvPIndicator',
}

-- ============================================================
-- Path parser
-- ============================================================

local function parseUnitConfigPath(path)
	local unitType, rest = path:match('^unitConfigs%.([^%.]+)%.(.+)$')
	return unitType, rest
end

-- ============================================================
-- Main CONFIG_CHANGED handler
-- ============================================================

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local unitType, key = parseUnitConfigPath(path)
	if(not unitType) then return end

	-- Dimensions
	if(key == 'width') then
		local config = F.StyleBuilder.GetConfig(unitType)
		debouncedApply('width.' .. unitType, function()
			ForEachFrame(unitType, function(frame)
				Widgets.SetSize(frame, config.width, nil)
				frame.Health:SetWidth(config.width)
				if(frame.Power and frame.Power:IsShown()) then
					frame.Power:SetWidth(config.width)
				end
			end)
		end)
		return
	end

	if(key == 'height') then
		local config = F.StyleBuilder.GetConfig(unitType)
		debouncedApply('height.' .. unitType, function()
			ForEachFrame(unitType, function(frame)
				Widgets.SetSize(frame, nil, config.height)
			end)
		end)
		return
	end

	-- Power bar
	if(key == 'showPower') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(config.showPower) then
				frame:EnableElement('Power')
				frame.Power:Show()
			else
				frame:DisableElement('Power')
				frame.Power:Hide()
			end
		end)
		return
	end

	-- Cast bar
	if(key == 'showCastBar') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(config.showCastBar) then
				frame:EnableElement('Castbar')
			else
				frame:DisableElement('Castbar')
			end
		end)
		return
	end

	-- Status icons
	local iconKey = key:match('^statusIcons%.(.+)$')
	if(iconKey) then
		local elementName = STATUS_ELEMENT_MAP[iconKey]
		if(elementName) then
			local config = F.StyleBuilder.GetConfig(unitType)
			local enabled = config.statusIcons and config.statusIcons[iconKey]
			ForEachFrame(unitType, function(frame)
				if(enabled) then
					frame:EnableElement(elementName)
				else
					frame:DisableElement(elementName)
				end
			end)
		end
		return
	end

	-- Show/hide toggles
	if(key == 'showName') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Name) then frame.Name:SetShown(config.showName ~= false) end
		end)
		return
	end

	if(key == 'health.showText') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Health and frame.Health.text) then
				frame.Health.text:SetShown(config.health and config.health.showText)
			end
		end)
		return
	end

	if(key == 'power.showText') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Power and frame.Power.text) then
				frame.Power.text:SetShown(config.power and config.power.showText)
			end
		end)
		return
	end

	-- Health prediction
	if(key:match('^health%.healPrediction')) then
		local config = F.StyleBuilder.GetConfig(unitType)
		local hp = config.health
		ForEachFrame(unitType, function(frame)
			if(hp.healPrediction) then
				frame:EnableElement('HealthPrediction')
			else
				frame:DisableElement('HealthPrediction')
			end
		end)
		return
	end

	-- Health text format
	if(key == 'health.textFormat') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Health) then
				frame.Health._textFormat = config.health and config.health.textFormat
				frame.Health:ForceUpdate()
			end
		end)
		return
	end

	-- Health smooth
	if(key == 'health.smooth') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Health) then
				frame.Health.smoothing = config.health and config.health.smooth
			end
		end)
		return
	end

end, 'LiveUpdate.FrameConfig')
