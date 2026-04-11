local _, Framed = ...
local F = Framed
local oUF = F.oUF
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Debuffs = {}

-- ============================================================
-- Filter map — server-side aura filter strings
-- ============================================================

local FILTER_MAP = {
	all          = 'HARMFUL',
	raid         = 'HARMFUL|RAID',
	important    = 'HARMFUL|IMPORTANT',
	dispellable  = 'HARMFUL|RAID_PLAYER_DISPELLABLE',
	raidCombat   = 'HARMFUL|RAID_IN_COMBAT',
	encounter    = 'HARMFUL|RAID',
}

-- ============================================================
-- Per-indicator update — single-pass filter + display
-- ============================================================

--- Display one aura directly from auraData fields (no intermediate table).
--- Returns the new running pixel offset for the next icon.
local function displayAura(self, unit, pool, displayed, runOffset, cfg, auraData, dispelType)
	local iconSize    = cfg.iconSize
	local bigIconSize = cfg.bigIconSize
	local orientation = cfg.orientation
	local anchor      = cfg.anchor
	local anchorPoint = anchor[1]
	local anchorX     = anchor[4]
	local anchorY     = anchor[5]

	if(not pool[displayed]) then
		pool[displayed] = F.Indicators.BorderIcon.Create(self, iconSize, {
			showCooldown = true,
			showStacks   = cfg.showStacks ~= false,
			showDuration = cfg.showDuration ~= false,
			frameLevel   = cfg.frameLevel,
			stackFont    = cfg.stackFont,
			durationFont = cfg.durationFont,
		})
	end

	local bi = pool[displayed]

	-- Size: big for boss auras (isBossAura may be secret in instances)
	local isBoss = F.IsValueNonSecret(auraData.isBossAura) and auraData.isBossAura
	local size = isBoss and bigIconSize or iconSize

	bi:ClearAllPoints()
	bi:SetSize(size)

	if(orientation == 'RIGHT') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX + runOffset, anchorY)
	elseif(orientation == 'LEFT') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX - runOffset, anchorY)
	elseif(orientation == 'DOWN') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY - runOffset)
	elseif(orientation == 'UP') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY + runOffset)
	end

	bi:SetBorderColor(1, 0, 0, 1)
	bi:SetAura(
		unit, auraData.auraInstanceID,
		auraData.spellId,
		auraData.icon,
		auraData.duration,
		auraData.expirationTime,
		auraData.applications,
		dispelType
	)
	bi:Show()

	return runOffset + size + 2
end

local function updateIndicator(self, unit, ind)
	local cfg = ind._config
	local maxDisplayed = cfg.maxDisplayed

	-- Backward compat: map old boolean to new filterMode
	local filterMode = cfg.filterMode
	if(not filterMode and cfg.onlyDispellableByMe) then
		filterMode = 'dispellable'
	end

	-- Encounter mode: only show during active boss encounters
	if(filterMode == 'encounter') then
		if(not C_InstanceEncounter or not C_InstanceEncounter.IsEncounterInProgress
			or not C_InstanceEncounter.IsEncounterInProgress()) then
			for idx = 1, #ind._pool do
				ind._pool[idx]:Clear()
			end
			return
		end
	end

	local filter = FILTER_MAP[filterMode] or 'HARMFUL'
	local auraState = self.FramedAuraState
	local rawAuras = auraState and auraState:GetHarmful(filter) or F.AuraCache.GetUnitAuras(unit, filter)
	local pool = ind._pool

	-- Single-pass: filter and display directly from auraData.
	-- auraInstanceID is NeverSecret; BorderIcon.SetAura uses C-level APIs
	-- for secret fields (icon, duration, etc.).
	local displayed = 0
	local runOffset = 0
	for _, auraData in next, rawAuras do
		if(displayed >= maxDisplayed) then break end

		local dur = auraData.duration
		local skip = F.IsValueNonSecret(dur) and (dur == 0 or dur >= 600)

		if(not skip) then
			displayed = displayed + 1
			runOffset = displayAura(self, unit, pool, displayed, runOffset, cfg, auraData, auraData.dispelName)
		end
	end

	-- When filterMode is 'dispellable', also include Physical/bleed debuffs
	-- from a broader HARMFUL|RAID query (RAID_PLAYER_DISPELLABLE excludes them).
	-- Supplementary results appear after the server-sorted dispellable set.
	if(filterMode == 'dispellable' and displayed < maxDisplayed) then
		local raidAuras = auraState and auraState:GetHarmful('HARMFUL|RAID') or F.AuraCache.GetUnitAuras(unit, 'HARMFUL|RAID')
		for _, auraData in next, raidAuras do
			if(displayed >= maxDisplayed) then break end

			local dn = auraData.dispelName
			local isPhysical = F.IsValueNonSecret(dn) and (not dn or dn == '' or dn == 'Physical')
			if(isPhysical) then
				displayed = displayed + 1
				runOffset = displayAura(self, unit, pool, displayed, runOffset, cfg, auraData, nil)
			end
		end
	end

	-- Hide pool entries beyond active count
	for idx = displayed + 1, #pool do
		pool[idx]:Clear()
	end
end

-- ============================================================
-- Update — iterates all indicators
-- ============================================================

local function Update(self, event, unit, updateInfo)
	local element = self.FramedDebuffs
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local auraState = self.FramedAuraState
	if(auraState) then
		if(event == 'UNIT_AURA') then
			auraState:ApplyUpdateInfo(unit, updateInfo)
		else
			auraState:EnsureInitialized(unit)
		end
	end

	for _, ind in next, element._indicators do
		if(ind._config.enabled ~= false) then
			updateIndicator(self, unit, ind)
		else
			-- Disabled indicator — clear its pool
			for idx = 1, #ind._pool do
				ind._pool[idx]:Clear()
			end
		end
	end
end

-- ============================================================
-- ForceUpdate
-- ============================================================

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

-- ============================================================
-- Enable / Disable
-- ============================================================

local function Enable(self, unit)
	local element = self.FramedDebuffs
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedDebuffs
	if(not element) then return end

	for _, ind in next, element._indicators do
		for _, bi in next, ind._pool do
			bi:Clear()
		end
	end

	self:UnregisterEvent('UNIT_AURA', Update)
end

-- ============================================================
-- Rebuild
-- ============================================================

local function Rebuild(element, config)
	local owner = element.__owner

	-- Destroy existing indicator pools
	for _, ind in next, element._indicators do
		for _, bi in next, ind._pool do
			bi:Clear()
			if(bi.Destroy) then bi:Destroy() end
		end
		if(ind._container) then
			ind._container:Hide()
		end
	end

	-- Rebuild indicators from new config
	element._config     = config
	element._indicators = {}

	local indicators = config.indicators or {}
	local idx = 0
	for name, indConfig in next, indicators do
		idx = idx + 1

		local container = CreateFrame('Frame', nil, owner)
		container:SetAllPoints(owner)

		local a = indConfig.anchor
		if(a) then
			container:ClearAllPoints()
			Widgets.SetPoint(container, a[1], nil, a[3], a[4] or 0, a[5] or 0)
		end

		element._indicators[idx] = {
			_name      = name,
			_config    = indConfig,
			_pool      = {},
			_container = container,
		}
	end

	element:ForceUpdate()
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedDebuffs', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create a Debuffs element on a unit frame.
--- Supports multiple named indicators, each with its own server-side
--- filter mode, anchor, icon size, and BorderIcon pool.
--- @param self Frame  The oUF unit frame
--- @param config table  { enabled, indicators = { [name] = indicatorConfig, ... } }
function F.Elements.Debuffs.Setup(self, config)
	config = config or {}

	if(not self.FramedAuraState and F.AuraState) then
		self.FramedAuraState = F.AuraState.Create(self)
	end

	-- Backward compatibility: flat config (no indicators key) → single indicator
	if(not config.indicators) then
		local indConfig = {}
		for k, v in next, config do
			if(k ~= 'enabled') then
				indConfig[k] = v
			end
		end
		-- Old format: maxIcons/growDirection → maxDisplayed/orientation
		if(indConfig.maxIcons and not indConfig.maxDisplayed) then
			indConfig.maxDisplayed = indConfig.maxIcons
			indConfig.orientation  = indConfig.growDirection
		end
		config.indicators = { ['Debuffs'] = indConfig }
	end

	local indicators = {}
	local idx = 0
	for name, indConfig in next, config.indicators do
		idx = idx + 1

		local container = CreateFrame('Frame', nil, self)
		container:SetAllPoints(self)

		local a = indConfig.anchor
		if(a) then
			container:ClearAllPoints()
			Widgets.SetPoint(container, a[1], nil, a[3], a[4] or 0, a[5] or 0)
		end

		indicators[idx] = {
			_name      = name,
			_config    = indConfig,
			_pool      = {},
			_container = container,
		}
	end

	local element = {
		_config     = config,
		_indicators = indicators,
		Rebuild     = Rebuild,
	}

	self.FramedDebuffs = element
end
