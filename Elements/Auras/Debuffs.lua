local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Debuffs = {}

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedDebuffs
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local cfg = element._config
	local maxDisplayed = cfg.maxDisplayed or 3
	local onlyDispellableByMe = cfg.onlyDispellableByMe

	-- Collect auras via new API with server-side sorting
	local rawAuras
	if(onlyDispellableByMe) then
		rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|RAID_PLAYER_DISPELLABLE', nil, Enum.UnitAuraSortRule.Default)
	else
		rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL', nil, Enum.UnitAuraSortRule.Default)
	end

	local auraList = {}
	for _, auraData in next, rawAuras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local dispelName = auraData.dispelName
			local dispelSafe = (not dispelName) or F.IsValueNonSecret(dispelName)

			auraList[#auraList + 1] = {
				spellId        = spellId,
				icon           = auraData.icon,
				duration       = auraData.duration,
				expirationTime = auraData.expirationTime,
				stacks         = auraData.applications or 0,
				dispelType     = dispelSafe and dispelName or nil,
				isBossAura     = auraData.isBossAura,
			}
		end
	end

	-- When onlyDispellableByMe is on, also include Physical/bleed debuffs
	-- from a broader HARMFUL|RAID query (RAID_PLAYER_DISPELLABLE excludes them).
	-- Always included here (unlike Dispellable which has a showPhysicalDebuffs toggle)
	-- because the Debuffs element is a general display and bleeds provide context.
	-- Supplementary results are appended after the server-sorted dispellable set,
	-- so they appear lower priority when maxDisplayed truncates.
	if(onlyDispellableByMe) then
		local raidAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|RAID')
		for _, auraData in next, raidAuras do
			local spellId = auraData.spellId
			if(F.IsValueNonSecret(spellId)) then
				local dispelName = auraData.dispelName
				local dispelSafe = (not dispelName) or F.IsValueNonSecret(dispelName)
				if(dispelSafe and (not dispelName or dispelName == '' or dispelName == 'Physical')) then
					auraList[#auraList + 1] = {
						spellId        = spellId,
						icon           = auraData.icon,
						duration       = auraData.duration,
						expirationTime = auraData.expirationTime,
						stacks         = auraData.applications or 0,
						dispelType     = nil,
						isBossAura     = auraData.isBossAura,
					}
				end
			end
		end
	end

	-- Display up to maxDisplayed using BorderIcon pool
	local count = math.min(#auraList, maxDisplayed)
	local pool = element._pool
	local iconSize = cfg.iconSize or 16
	local bigIconSize = cfg.bigIconSize or iconSize
	local orientation = cfg.orientation or 'RIGHT'

	for idx = 1, count do
		local aura = auraList[idx]

		-- Lazily create pool entries
		if(not pool[idx]) then
			pool[idx] = F.Indicators.BorderIcon.Create(self, iconSize, {
				showCooldown = true,
				showStacks   = cfg.showStacks ~= false,
				showDuration = cfg.showDuration ~= false,
				frameLevel   = cfg.frameLevel or 5,
				stackFont    = cfg.stackFont,
				durationFont = cfg.durationFont,
			})
		end

		local bi = pool[idx]

		-- Size: big for boss auras
		local size = aura.isBossAura and bigIconSize or iconSize

		bi:ClearAllPoints()
		bi:SetSize(size)

		-- Position
		local offset = 0
		for j = 1, idx - 1 do
			local prevSize = (auraList[j].isBossAura and bigIconSize or iconSize)
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
	}

	local a = config.anchor
	if(a) then
		container:ClearAllPoints()
		Widgets.SetPoint(container, a[1], nil, a[3], a[4] or 0, a[5] or 0)
	end

	self.FramedDebuffs = element
end
