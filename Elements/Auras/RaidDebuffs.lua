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

	local minPriority  = element._minPriority
	local filterMode   = element._filterMode
	local customSpells = F.Config:Get('raidDebuffs.custom')

	local bestPriority    = 0
	local bestAura        = nil
	local bestExpirationTime = 0

	-- Filter is 'HARMFUL' so all results are harmful — do not read auraData.isHarmful
	local i = 1
	while(true) do
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if(not auraData) then break end

		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local priority     = 0
			local shouldShow   = false

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
				local expiration = auraData.expirationTime or 0
				-- Prefer highest priority; break ties by most recent (highest expirationTime)
				if(priority > bestPriority or
					(priority == bestPriority and expiration > bestExpirationTime)) then
					bestPriority        = priority
					bestExpirationTime  = expiration
					bestAura            = auraData
				end
			end
		end

		i = i + 1
	end

	if(bestAura) then
		local spellId = bestAura.spellId
		element._icon:SetSpell(
			spellId,
			bestAura.icon,
			bestAura.duration,
			bestAura.expirationTime,
			bestAura.applications or 0,
			bestAura.dispelName
		)
		element._icon:Show()
	else
		element._icon:Clear()
		element._icon:Hide()
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

	element._icon:Clear()
	element._icon:Hide()

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
--- Shows the highest-priority registered raid debuff via a single Icon indicator.
--- Assigns result to self.FramedRaidDebuffs, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: filterMode, minPriority, iconSize, anchor
function F.Elements.RaidDebuffs.Setup(self, config)
	config = config or {}
	config.filterMode   = config.filterMode   or C.DebuffFilterMode.RAID
	config.minPriority  = config.minPriority  or C.DebuffPriority.NORMAL
	config.iconSize     = config.iconSize     or 20
	config.anchor       = config.anchor       or { 'CENTER', self, 'CENTER', 0, 0 }

	local icon = F.Indicators.Icon.Create(self, config.iconSize, {
		displayType  = C.IconDisplay.SPELL_ICON,
		showCooldown = true,
		showStacks   = true,
		showDuration = true,
	})

	local a = config.anchor
	icon:SetPoint(a[1], a[2], a[3], a[4] or 0, a[5] or 0)

	local container = {
		_icon        = icon,
		_filterMode  = config.filterMode,
		_minPriority = config.minPriority,
	}

	self.FramedRaidDebuffs = container
end
