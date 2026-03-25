local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.RaidDebuffs = {}

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedRaidDebuffs
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local cfg          = element._config
	local minPriority  = cfg.minPriority  or C.DebuffPriority.NORMAL
	local filterMode   = cfg.filterMode   or C.DebuffFilterMode.RAID
	local maxDisplayed = cfg.maxDisplayed or 1
	local customSpells = F.Config:Get('raidDebuffs.custom')

	-- Collect qualifying auras with their effective priority
	local auraList = {}
	local i = 1
	while(true) do
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if(not auraData) then break end

		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local priority  = 0
			local shouldShow = false

			-- Registry lookup
			local registryPriority = F.RaidDebuffRegistry:GetEffectivePriority(spellId)
			if(registryPriority > 0) then
				priority   = registryPriority
				shouldShow = true
			end

			-- Flag-based filtering (may show even without a registry entry)
			if(F.RaidDebuffRegistry:ShouldShow(auraData, filterMode)) then
				shouldShow = true
				if(priority == 0) then
					-- Not in registry but passes flag filter — treat as minPriority
					priority = minPriority
				end
			end

			-- User custom spells (always show regardless of registry/flags)
			if(customSpells and customSpells[spellId]) then
				shouldShow = true
				local customPriority = customSpells[spellId]
				if(type(customPriority) == 'number' and customPriority > priority) then
					priority = customPriority
				elseif(priority == 0) then
					priority = minPriority
				end
			end

			if(shouldShow and priority >= minPriority) then
				auraList[#auraList + 1] = {
					spellId        = spellId,
					icon           = auraData.icon,
					duration       = auraData.duration,
					expirationTime = auraData.expirationTime,
					stacks         = auraData.applications or 0,
					dispelType     = F.IsValueNonSecret(auraData.dispelName) and auraData.dispelName or nil,
					priority       = priority,
				}
			end
		end

		i = i + 1
	end

	-- Sort: highest priority first; break ties by most recent expiration (highest expirationTime)
	table.sort(auraList, function(a, b)
		if(a.priority ~= b.priority) then
			return a.priority > b.priority
		end
		return (a.expirationTime or 0) > (b.expirationTime or 0)
	end)

	-- Display up to maxDisplayed using BorderIcon pool
	local count = math.min(#auraList, maxDisplayed)
	local pool = element._pool
	local iconSize    = cfg.iconSize    or 20
	local bigIconSize = cfg.bigIconSize or iconSize
	local orientation = cfg.orientation or 'RIGHT'
	local importantThreshold = C.DebuffPriority.IMPORTANT

	for idx = 1, count do
		local aura = auraList[idx]

		-- Lazily create pool entries
		if(not pool[idx]) then
			pool[idx] = F.Indicators.BorderIcon.Create(self, iconSize, {
				showCooldown = true,
				showStacks   = cfg.showStacks   ~= false,
				showDuration = cfg.showDuration ~= false,
				frameLevel   = cfg.frameLevel   or 5,
				stackFont    = cfg.stackFont,
				durationFont = cfg.durationFont,
			})
		end

		local bi = pool[idx]

		-- Size: big for high-priority (IMPORTANT and above) auras
		local size = (aura.priority >= importantThreshold) and bigIconSize or iconSize

		bi:ClearAllPoints()
		bi:SetSize(size)

		-- Position relative to container
		local offset = 0
		for j = 1, idx - 1 do
			local prevSize = (auraList[j].priority >= importantThreshold) and bigIconSize or iconSize
			offset = offset + prevSize + 2
		end

		if(orientation == 'RIGHT') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', offset, 0)
		elseif(orientation == 'LEFT') then
			bi:SetPoint('TOPRIGHT', element._container, 'TOPRIGHT', -offset, 0)
		elseif(orientation == 'DOWN') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', 0, -offset)
		elseif(orientation == 'UP') then
			bi:SetPoint('BOTTOMLEFT', element._container, 'BOTTOMLEFT', 0, offset)
		end

		bi:SetAura(
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
-- ForceUpdate
-- ============================================================

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

-- ============================================================
-- Enable / Disable
-- ============================================================

local function Enable(self, unit)
	local element = self.FramedRaidDebuffs
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedRaidDebuffs
	if(not element) then return end

	for _, bi in next, element._pool do
		bi:Clear()
	end

	self:UnregisterEvent('UNIT_AURA', Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedRaidDebuffs', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create a RaidDebuffs element on a unit frame.
--- Shows highest-priority registered raid debuffs via a BorderIcon pool.
--- Assigns result to self.FramedRaidDebuffs, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  New schema: iconSize, bigIconSize, maxDisplayed, showDuration, showStacks,
---                       showAnimation, orientation, anchor, frameLevel, stackFont, durationFont,
---                       filterMode, minPriority
---                       Old schema (backward compat): { iconSize, filterMode, minPriority, anchor }
function F.Elements.RaidDebuffs.Setup(self, config)
	config = config or {}

	-- Backward compatibility: old format was a single-icon config with no pool fields.
	-- Detect by absence of maxDisplayed alongside presence of old-style fields.
	if(not config.maxDisplayed) then
		config.maxDisplayed = 1
	end
	if(not config.orientation and config.growDirection) then
		config.orientation = config.growDirection
	end

	-- Apply defaults for registry filtering
	config.filterMode  = config.filterMode  or C.DebuffFilterMode.RAID
	config.minPriority = config.minPriority or C.DebuffPriority.NORMAL
	config.iconSize    = config.iconSize    or 20

	local container = CreateFrame('Frame', nil, self)
	container:SetAllPoints(self)

	local element = {
		_container = container,
		_config    = config,
		_pool      = {},
	}

	local a = config.anchor
	if(a) then
		container:ClearAllPoints()
		Widgets.SetPoint(container, a[1], a[2] or self, a[3], a[4] or 0, a[5] or 0)
	end

	self.FramedRaidDebuffs = element
end
