local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
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

-- Reusable table pool — avoids allocations on every UNIT_AURA
local auraPool = {}
local auraCount = 0

-- ============================================================
-- Per-indicator update
-- ============================================================

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
			-- Not in an encounter — hide all pool entries and bail
			for idx = 1, #ind._pool do
				ind._pool[idx]:Clear()
			end
			return
		end
	end

	local filter = FILTER_MAP[filterMode] or 'HARMFUL'
	local rawAuras = C_UnitAuras.GetUnitAuras(unit, filter, nil, Enum.UnitAuraSortRule.Default)

	-- Always include auras regardless of secret status.
	-- auraInstanceID is NeverSecret; BorderIcon.SetAura uses C-level APIs
	-- (DurationObject, dispel color curve, etc.) for display when unit +
	-- auraInstanceID are provided. Lua-level fields (spellId, icon, duration)
	-- may be secret in instanced content — SetTexture and other C-level frame
	-- methods accept them directly.
	auraCount = 0
	for _, auraData in next, rawAuras do
		-- Skip long-duration debuffs (Sated, Exhaustion, etc.) that aren't
		-- real combat debuffs. duration == 0 means permanent.
		local dur = auraData.duration
		local skip = F.IsValueNonSecret(dur) and (dur == 0 or dur >= 600)

		if(not skip) then
			auraCount = auraCount + 1
			local entry = auraPool[auraCount]
			if(not entry) then
				entry = {}
				auraPool[auraCount] = entry
			end
			entry.auraInstanceID = auraData.auraInstanceID
			entry.spellId        = auraData.spellId
			entry.icon           = auraData.icon
			entry.duration       = auraData.duration
			entry.expirationTime = auraData.expirationTime
			entry.stacks         = auraData.applications
			entry.dispelType     = auraData.dispelName
			entry.isBossAura     = auraData.isBossAura
		end
	end

	-- When filterMode is 'dispellable', also include Physical/bleed debuffs
	-- from a broader HARMFUL|RAID query (RAID_PLAYER_DISPELLABLE excludes them).
	-- Always included here (unlike Dispellable which has a showPhysicalDebuffs toggle)
	-- because the Debuffs element is a general display and bleeds provide context.
	-- Supplementary results are appended after the server-sorted dispellable set,
	-- so they appear lower priority when maxDisplayed truncates.
	if(filterMode == 'dispellable') then
		local raidAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|RAID')
		for _, auraData in next, raidAuras do
			local dn = auraData.dispelName
			-- Only non-secret dispelName can be string-compared; if secret, skip
			-- (secret Physical debuffs are an edge case — the main HARMFUL query
			-- already captured this aura if it exists)
			local isPhysical = F.IsValueNonSecret(dn) and (not dn or dn == '' or dn == 'Physical')
			if(isPhysical) then
				auraCount = auraCount + 1
				local entry = auraPool[auraCount]
				if(not entry) then
					entry = {}
					auraPool[auraCount] = entry
				end
				entry.auraInstanceID = auraData.auraInstanceID
				entry.spellId        = auraData.spellId
				entry.icon           = auraData.icon
				entry.duration       = auraData.duration
				entry.expirationTime = auraData.expirationTime
				entry.stacks         = auraData.applications
				entry.dispelType     = nil
				entry.isBossAura     = auraData.isBossAura
			end
		end
	end

	-- Display up to maxDisplayed using BorderIcon pool
	local count = math.min(auraCount, maxDisplayed)
	local pool = ind._pool
	local iconSize    = cfg.iconSize
	local bigIconSize = cfg.bigIconSize
	local orientation = cfg.orientation
	local anchor      = cfg.anchor
	local anchorPoint = anchor[1]
	local anchorX     = anchor[4]
	local anchorY     = anchor[5]

	for idx = 1, count do
		local aura = auraPool[idx]

		-- Lazily create pool entries
		if(not pool[idx]) then
			pool[idx] = F.Indicators.BorderIcon.Create(self, iconSize, {
				showCooldown = true,
				showStacks   = cfg.showStacks ~= false,
				showDuration = cfg.showDuration ~= false,
				frameLevel   = cfg.frameLevel,
				stackFont    = cfg.stackFont,
				durationFont = cfg.durationFont,
			})
		end

		local bi = pool[idx]

		-- Size: big for boss auras (isBossAura may be secret in instances)
		local isBoss = F.IsValueNonSecret(aura.isBossAura) and aura.isBossAura
		local size = isBoss and bigIconSize or iconSize

		bi:ClearAllPoints()
		bi:SetSize(size)

		-- Position: anchor directly to the unit frame, offset by prior icons
		local offset = 0
		for j = 1, idx - 1 do
			local prevBoss = F.IsValueNonSecret(auraPool[j].isBossAura) and auraPool[j].isBossAura
			local prevSize = prevBoss and bigIconSize or iconSize
			offset = offset + prevSize + 2
		end

		if(orientation == 'RIGHT') then
			bi:SetPoint(anchorPoint, self, anchorPoint, anchorX + offset, anchorY)
		elseif(orientation == 'LEFT') then
			bi:SetPoint(anchorPoint, self, anchorPoint, anchorX - offset, anchorY)
		elseif(orientation == 'DOWN') then
			bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY - offset)
		elseif(orientation == 'UP') then
			bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY + offset)
		end

		-- Red border as default for debuffs
		bi:SetBorderColor(1, 0, 0, 1)
		bi:SetAura(
			unit, aura.auraInstanceID,
			aura.spellId,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.stacks,
			aura.dispelType
		)
		bi:Show()
	end

	-- Hide pool entries beyond active count
	for idx = count + 1, #pool do
		pool[idx]:Clear()
	end
end

-- ============================================================
-- Update — iterates all indicators
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedDebuffs
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

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
