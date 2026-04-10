local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

-- ============================================================
-- FrameConfigShared — shared infrastructure for LiveUpdate sub-modules
-- ============================================================

F.LiveUpdate = F.LiveUpdate or {}
local Shared = {}
F.LiveUpdate.FrameConfigShared = Shared

Shared.ForEachFrame = F.StyleBuilder.ForEachFrame

-- ============================================================
-- Combat queue for group layout (SetAttribute locked in combat)
-- ============================================================

local pendingGroupChanges = {}
local combatQueueStatus

function Shared.applyOrQueue(header, attr, value)
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

function Shared.debouncedApply(key, applyFn, ...)
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

Shared.STATUS_ELEMENT_MAP = {
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

function Shared.parseUnitConfigPath(path)
	local presetName, unitType, rest = path:match('presets%.([^%.]+)%.unitConfigs%.([^%.]+)%.(.+)$')
	if(not unitType) then
		unitType, rest = path:match('unitConfigs%.([^%.]+)%.(.+)$')
	end
	return unitType, rest, presetName
end

-- ============================================================
-- Group types
-- ============================================================

Shared.GROUP_TYPES = {
	party        = true,
	raid         = true,
	battleground = true,
	worldraid    = true,
}

-- ============================================================
-- Group header lookup
-- ============================================================

function Shared.getGroupHeader(unitType)
	if(unitType == 'party') then
		return F.Units.Party and F.Units.Party.header
	elseif(unitType == 'raid') then
		return F.Units.Raid and F.Units.Raid.header
	end
	return nil
end

-- ============================================================
-- Position / resize helpers
-- ============================================================

function Shared.repositionFrame(frame, config)
	local pos = config.position
	local x = pos.x
	local y = pos.y
	frame:ClearAllPoints()
	Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)
end

function Shared.resizeShift(anchor, dw, dh)
	local dx, dy = 0, 0
	if(anchor == 'TOPLEFT') then       dx, dy =  dw / 2, -dh / 2
	elseif(anchor == 'TOP') then       dx, dy =  0,      -dh / 2
	elseif(anchor == 'TOPRIGHT') then  dx, dy = -dw / 2, -dh / 2
	elseif(anchor == 'LEFT') then      dx, dy =  dw / 2,  0
	elseif(anchor == 'CENTER') then    dx, dy =  0,        0
	elseif(anchor == 'RIGHT') then     dx, dy = -dw / 2,  0
	elseif(anchor == 'BOTTOMLEFT') then  dx, dy =  dw / 2, dh / 2
	elseif(anchor == 'BOTTOM') then      dx, dy =  0,      dh / 2
	elseif(anchor == 'BOTTOMRIGHT') then dx, dy = -dw / 2, dh / 2
	end
	return dx, dy
end

local function anchorFractions(pt)
	local fx, fy = 0.5, 0.5
	if(pt:find('LEFT'))   then fx = 0 end
	if(pt:find('RIGHT'))  then fx = 1 end
	if(pt:find('TOP'))    then fy = 0 end
	if(pt:find('BOTTOM')) then fy = 1 end
	return fx, fy
end

function Shared.groupResizeShift(headerAnchor, resizeAnchor, dw, dh)
	local hx, hy = anchorFractions(headerAnchor)
	local rx, ry = anchorFractions(resizeAnchor)
	local dx = -(rx - hx) * dw
	local dy =  (ry - hy) * dh
	return dx, dy
end

--- Apply group layout attributes to a header based on config.
function Shared.applyGroupLayoutToHeader(header, config)
	local orient  = config.orientation
	local anchor  = config.anchorPoint
	local spacing = config.spacing

	local point, yOff, xOff, colAnchor

	if(orient == 'vertical') then
		local goDown = (anchor == 'TOPLEFT' or anchor == 'TOPRIGHT')
		point  = goDown and 'TOP' or 'BOTTOM'
		yOff   = goDown and -spacing or spacing
		xOff   = 0
		colAnchor = (anchor == 'TOPLEFT' or anchor == 'BOTTOMLEFT') and 'LEFT' or 'RIGHT'
	else
		local goRight = (anchor == 'TOPLEFT' or anchor == 'BOTTOMLEFT')
		point  = goRight and 'LEFT' or 'RIGHT'
		xOff   = goRight and spacing or -spacing
		yOff   = 0
		colAnchor = (anchor == 'TOPLEFT' or anchor == 'TOPRIGHT') and 'TOP' or 'BOTTOM'
	end

	Shared.applyOrQueue(header, 'xOffset', xOff)
	Shared.applyOrQueue(header, 'yOffset', yOff)
	Shared.applyOrQueue(header, 'point', point)
	Shared.applyOrQueue(header, 'columnAnchorPoint', colAnchor)

	if(not InCombatLockdown()) then
		local name = header:GetName()
		if(name and name:find('Party')) then
			header:SetAttribute('showParty', false)
			header:SetAttribute('showParty', true)
		elseif(name and name:find('Raid')) then
			header:SetAttribute('showRaid', false)
			header:SetAttribute('showRaid', true)
		end
	end
end

--- Standard guard: parse path, check active preset, return unitType + key.
--- Returns nil, nil if the event should be skipped.
function Shared.guardConfigChanged(path)
	local unitType, key, presetName = Shared.parseUnitConfigPath(path)
	if(not unitType) then return nil, nil end
	if(presetName and presetName ~= F.AutoSwitch.GetCurrentPreset()) then return nil, nil end
	return unitType, key
end
