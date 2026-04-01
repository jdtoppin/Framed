local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Debuffs = {}

local FILTER_MAP = {
	all          = 'HARMFUL',
	raid         = 'HARMFUL|RAID',
	important    = 'HARMFUL|IMPORTANT',
	dispellable  = 'HARMFUL|RAID_PLAYER_DISPELLABLE',
	raidCombat   = 'HARMFUL|RAID_IN_COMBAT',
}

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedDebuffs
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local cfg = element._config
	local maxDisplayed = cfg.maxDisplayed

	-- Backward compat: map old boolean to new filterMode
	local filterMode = cfg.filterMode
	if(not filterMode and cfg.onlyDispellableByMe) then
		filterMode = 'dispellable'
	end
	local filter = FILTER_MAP[filterMode] or 'HARMFUL'
	local rawAuras = C_UnitAuras.GetUnitAuras(unit, filter, nil, Enum.UnitAuraSortRule.Default)

	-- Always include auras regardless of secret status.
	-- auraInstanceID is NeverSecret; BorderIcon.SetAura uses C-level APIs
	-- (DurationObject, dispel color curve, etc.) for display when unit +
	-- auraInstanceID are provided. Lua-level fields (spellId, icon, duration)
	-- may be secret in instanced content — SetTexture and other C-level frame
	-- methods accept them directly.
	local auraList = {}
	for _, auraData in next, rawAuras do
		auraList[#auraList + 1] = {
			auraInstanceID = auraData.auraInstanceID,
			spellId        = auraData.spellId,
			icon           = auraData.icon,
			duration       = auraData.duration,
			expirationTime = auraData.expirationTime,
			stacks         = auraData.applications,
			dispelType     = auraData.dispelName,
			isBossAura     = auraData.isBossAura,
		}
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
				auraList[#auraList + 1] = {
					auraInstanceID = auraData.auraInstanceID,
					spellId        = auraData.spellId,
					icon           = auraData.icon,
					duration       = auraData.duration,
					expirationTime = auraData.expirationTime,
					stacks         = auraData.applications,
					dispelType     = nil,
					isBossAura     = auraData.isBossAura,
				}
			end
		end
	end


	-- Display up to maxDisplayed using BorderIcon pool
	local count = math.min(#auraList, maxDisplayed)
	local pool = element._pool
	local iconSize = cfg.iconSize
	local bigIconSize = cfg.bigIconSize
	local orientation = cfg.orientation
	local anchor = cfg.anchor or { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 }
	local anchorPoint = anchor[1]
	local anchorX = anchor[4] or 0
	local anchorY = anchor[5] or 0

	for idx = 1, count do
		local aura = auraList[idx]

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
			local prevBoss = F.IsValueNonSecret(auraList[j].isBossAura) and auraList[j].isBossAura
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

	for _, bi in next, element._pool do
		bi:Clear()
	end

	self:UnregisterEvent('UNIT_AURA', Update)
end

-- ============================================================
-- Rebuild
-- ============================================================

local function Rebuild(element, config)
	-- Destroy existing pool entries so they are recreated with new config
	if(element._pool) then
		for _, bi in next, element._pool do
			bi:Clear()
			if(bi.Destroy) then bi:Destroy() end
		end
	end

	element._config = config
	element._pool   = {}

	element:ForceUpdate()
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedDebuffs', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

function F.Elements.Debuffs.Setup(self, config)
	config = config or {}

	-- Backward compatibility: old format had maxIcons/iconSize/growDirection
	-- New format has maxDisplayed/iconSize/orientation/anchor/etc.
	if(config.maxIcons and not config.maxDisplayed) then
		config.maxDisplayed = config.maxIcons
		config.orientation  = config.growDirection or 'RIGHT'
	end

	local container = CreateFrame('Frame', nil, self)
	container:SetAllPoints(self)

	local element = {
		_container = container,
		_config    = config,
		_pool      = {},
		Rebuild    = Rebuild,
	}

	local a = config.anchor
	if(a) then
		container:ClearAllPoints()
		Widgets.SetPoint(container, a[1], nil, a[3], a[4] or 0, a[5] or 0)
	end

	self.FramedDebuffs = element
end
