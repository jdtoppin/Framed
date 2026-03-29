local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.MissingBuffs = {}

-- ============================================================
-- Tracked raid buffs: spellId → providing class
-- Only shows the missing icon if the providing class is in the group.
-- ============================================================

local RAID_BUFFS = {
	[21562]  = 'PRIEST',   -- Power Word: Fortitude (Stamina)
	[1459]   = 'MAGE',     -- Arcane Intellect (Intellect)
	[6673]   = 'WARRIOR',  -- Battle Shout (Attack Power)
	[1126]   = 'DRUID',    -- Mark of the Wild (Versatility)
	[381748] = 'EVOKER',   -- Blessing of the Bronze (Movement Speed)
	[462854] = 'SHAMAN',   -- Skyfury (Crit/Haste)
}

-- Stable display order (sorted by spellId)
local BUFF_ORDER = {}
for spellId in next, RAID_BUFFS do
	BUFF_ORDER[#BUFF_ORDER + 1] = spellId
end
table.sort(BUFF_ORDER)

-- ============================================================
-- Helpers
-- ============================================================

--- Cache spell icons at load time (not in combat).
local iconCache = {}
local function cacheSpellIcons()
	for _, spellId in next, BUFF_ORDER do
		if(C_Spell and C_Spell.GetSpellInfo) then
			local info = C_Spell.GetSpellInfo(spellId)
			if(info) then iconCache[spellId] = info.iconID end
		elseif(GetSpellInfo) then
			local _, _, icon = GetSpellInfo(spellId)
			iconCache[spellId] = icon
		end
	end
end

--- Scan the current group for which classes are present.
--- @return table classSet  { ['PRIEST'] = true, ['MAGE'] = true, ... }
local function getGroupClasses()
	local classes = {}

	-- Include player
	local _, playerClass = UnitClass('player')
	if(playerClass) then
		classes[playerClass] = true
	end

	local groupType = IsInRaid() and 'raid' or (IsInGroup() and 'party') or nil
	if(not groupType) then return classes end

	local n = GetNumGroupMembers()
	for i = 1, n do
		local unit = groupType .. i
		if(UnitExists(unit)) then
			local _, class = UnitClass(unit)
			if(class) then
				classes[class] = true
			end
		end
	end

	return classes
end

--- Check whether the unit currently has a buff matching the given spellId.
--- Returns false if aura data is secret (safe fallback: assume missing).
--- @param unit string
--- @param targetSpellId number
--- @return boolean
local function unitHasBuff(unit, targetSpellId)
	local auras = C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')
	if(not auras) then return false end

	for _, auraData in next, auras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId) and spellId == targetSpellId) then
			return true
		end
	end
	return false
end

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedMissingBuffs
	if(not element) then return end

	-- Refresh group class cache on roster changes
	if(event == 'GROUP_ROSTER_UPDATE') then
		element._groupClasses = getGroupClasses()
	end

	-- For unit-specific events, filter to our unit
	if(event == 'UNIT_AURA') then
		if(not unit or self.unit ~= unit) then return end
	end

	unit = self.unit
	if(not unit) then return end

	local groupClasses = element._groupClasses
	local slots = element._slots
	local slotIndex = 0

	for _, spellId in next, BUFF_ORDER do
		local providingClass = RAID_BUFFS[spellId]
		local slot = slots[spellId]
		if(not slot) then break end

		if(providingClass and groupClasses[providingClass] and not unitHasBuff(unit, spellId)) then
			-- Missing buff from a class in the group — show with glow
			slotIndex = slotIndex + 1
			slot.bi.icon:SetTexture(iconCache[spellId])
			slot.bi:Show()
			if(not slot.glow:IsActive()) then
				slot.glow:Start()
			end
		else
			-- Buff present or class not in group — hide
			slot.bi:Hide()
			if(slot.glow:IsActive()) then
				slot.glow:Stop()
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
	local element = self.FramedMissingBuffs
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate
	element._groupClasses = getGroupClasses()

	-- Cache spell icons on first enable (safe — always outside combat)
	if(not next(iconCache)) then
		cacheSpellIcons()
	end

	self:RegisterEvent('UNIT_AURA', Update)
	self:RegisterEvent('GROUP_ROSTER_UPDATE', Update, true)

	return true
end

local function Disable(self)
	local element = self.FramedMissingBuffs
	if(not element) then return end

	-- Hide all slots and stop glows
	for _, slot in next, element._slots do
		slot.bi:Hide()
		if(slot.glow:IsActive()) then
			slot.glow:Stop()
		end
	end

	self:UnregisterEvent('UNIT_AURA', Update)
	self:UnregisterEvent('GROUP_ROSTER_UPDATE', Update)
end

-- ============================================================
-- Rebuild
-- ============================================================

local function Rebuild(element, config)
	if(element._slots) then
		for _, slot in next, element._slots do
			if(slot.bi) then
				slot.bi:Clear()
				if(slot.bi.Destroy) then slot.bi:Destroy() end
			end
			if(slot.glow) then slot.glow:Stop() end
		end
	end

	local iconSize   = config.iconSize     or 12
	local growDir    = config.growDirection or 'RIGHT'
	local spacing    = config.spacing       or 1
	local glowType   = config.glowType      or 'Pixel'
	local glowColor  = config.glowColor     or { 1, 0.8, 0, 1 }
	local frameLevel = config.frameLevel    or 5

	element._slots = {}
	for _, spellId in next, BUFF_ORDER do
		local bi = F.Indicators.BorderIcon.Create(element._container, iconSize, {
			showCooldown = false,
			showStacks   = false,
			showDuration = false,
			frameLevel   = element.__owner:GetFrameLevel() + frameLevel,
		})
		local glow = F.Indicators.BorderGlow.Create(bi._frame, {
			borderGlowMode = 'Glow',
			glowType = glowType,
			glowColor = glowColor,
		})
		element._slots[spellId] = { bi = bi, glow = glow }
	end

	local anchor = config.anchor or { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 2 }
	element._container:ClearAllPoints()
	element._container:SetPoint(anchor[1], element.__owner, anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0)

	element:ForceUpdate()
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedMissingBuffs', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create a MissingBuffs element on a unit frame.
--- Shows glowing spell icons for important raid buffs that are missing,
--- but only when the providing class is present in the group.
--- @param self Frame  The oUF unit frame
--- @param config? table  iconSize, anchor, frameLevel, glowType, glowColor, growDirection, spacing
function F.Elements.MissingBuffs.Setup(self, config)
	config = config or {}
	config.iconSize      = config.iconSize      or 12
	config.growDirection = config.growDirection or 'RIGHT'
	config.spacing       = config.spacing       or 1
	config.frameLevel    = config.frameLevel    or 5
	config.anchor        = config.anchor        or { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 2 }
	config.glowType      = config.glowType      or C.GlowType.PIXEL
	config.glowColor     = config.glowColor     or { 1, 0.8, 0, 1 }

	local iconSize = config.iconSize
	local spacing  = config.spacing
	local grow     = config.growDirection
	local numBuffs = #BUFF_ORDER

	-- Container frame for all icons
	local container = CreateFrame('Frame', nil, self)
	container:SetFrameLevel(self:GetFrameLevel() + config.frameLevel)

	-- Size container to fit all icons
	if(grow == 'RIGHT' or grow == 'LEFT') then
		Widgets.SetSize(container, numBuffs * iconSize + math.max(0, numBuffs - 1) * spacing, iconSize)
	else
		Widgets.SetSize(container, iconSize, numBuffs * iconSize + math.max(0, numBuffs - 1) * spacing)
	end

	-- Anchor the container (a[2] is always nil — container is parented to self)
	local a = config.anchor
	container:SetPoint(a[1], nil, a[3], a[4] or 0, a[5] or 0)

	-- Create one BorderIcon + Glow per tracked buff
	local slots = {}
	for i, spellId in next, BUFF_ORDER do
		local bi = F.Indicators.BorderIcon.Create(container, iconSize, {
			borderThickness = 1,
			borderColor     = { 0.15, 0.15, 0.15, 1 },
			showCooldown    = false,
			showStacks      = false,
			showDuration    = false,
		})

		-- Position within the container
		local offset = (i - 1) * (iconSize + spacing)
		if(grow == 'RIGHT') then
			bi:SetPoint('TOPLEFT', container, 'TOPLEFT', offset, 0)
		elseif(grow == 'LEFT') then
			bi:SetPoint('TOPRIGHT', container, 'TOPRIGHT', -offset, 0)
		elseif(grow == 'DOWN') then
			bi:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, -offset)
		else -- UP
			bi:SetPoint('BOTTOMLEFT', container, 'BOTTOMLEFT', 0, offset)
		end

		bi:Hide()

		local glow = F.Indicators.BorderGlow.Create(bi._frame, {
			borderGlowMode = 'Glow',
			glowType = config.glowType,
			glowColor = config.glowColor,
		})

		slots[spellId] = { bi = bi, glow = glow }
	end

	self.FramedMissingBuffs = {
		_container    = container,
		_slots        = slots,
		_groupClasses = {},
		Rebuild       = Rebuild,
	}
end
