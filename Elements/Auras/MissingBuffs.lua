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

--- Cache spell icons and names at load time (not in combat).
local iconCache = {}
local nameCache = {}
local function cacheSpellData()
	for _, spellId in next, BUFF_ORDER do
		if(C_Spell and C_Spell.GetSpellInfo) then
			local info = C_Spell.GetSpellInfo(spellId)
			if(info) then
				iconCache[spellId] = info.iconID
				nameCache[spellId] = info.name
			end
		elseif(GetSpellInfo) then
			local name, _, icon = GetSpellInfo(spellId)
			iconCache[spellId] = icon
			nameCache[spellId] = name
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

--- Ensure a spell's name and icon are cached. C_Spell.GetSpellInfo can
--- return nil if the data hasn't loaded yet (async), so we retry on demand.
local function ensureCached(spellId)
	if(nameCache[spellId]) then return nameCache[spellId] end
	if(C_Spell and C_Spell.GetSpellInfo) then
		local info = C_Spell.GetSpellInfo(spellId)
		if(info) then
			nameCache[spellId] = info.name
			iconCache[spellId] = info.iconID
			return info.name
		end
	end
end

--- Check whether a buff matching targetSpellId exists in the pre-fetched
--- aura list. Avoids any table creation — just iterates the API result
--- and compares spellId/name directly.
--- @param rawAuras table  Result of C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')
--- @param targetSpellId number
--- @return boolean
local function auraListHasBuff(rawAuras, targetSpellId)
	local targetName = ensureCached(targetSpellId)
	for _, auraData in next, rawAuras do
		local sid = auraData.spellId
		if(F.IsValueNonSecret(sid) and sid == targetSpellId) then return true end
		if(targetName) then
			local n = auraData.name
			if(F.IsValueNonSecret(n) and n == targetName) then return true end
		end
	end
	return false
end

--- Fallback for NPC party members (delves) where aura data is fully secret.
--- Uses GetAuraDataBySpellName which is a server-side lookup that works
--- regardless of secret status.
--- @param unit string
--- @param targetSpellId number
--- @return boolean
local function npcUnitHasBuff(unit, targetSpellId)
	local name = ensureCached(targetSpellId)
	if(not name) then return false end
	return C_UnitAuras.GetAuraDataBySpellName(unit, name, 'HELPFUL') ~= nil
end

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedMissingBuffs
	if(not element) then return end

	-- Refresh group class cache on roster changes and ForceUpdate
	-- (GROUP_ROSTER_UPDATE can fire while frames are hidden during zone-in,
	-- so ForceUpdate from PLAYER_ENTERING_WORLD serves as a fallback)
	if(event ~= 'UNIT_AURA') then
		element._groupClasses = getGroupClasses()
	end

	-- For unit-specific events, filter to our unit
	if(event == 'UNIT_AURA') then
		if(not unit or self.unit ~= unit) then return end
	end

	unit = self.unit
	if(not unit) then return end

	-- Pets and dead units don't receive raid buffs — hide all slots
	if(unit:match('pet') or UnitIsDeadOrGhost(unit)) then
		for _, slot in next, element._slots do
			slot.bi:Hide()
			if(slot.glow:IsActive()) then slot.glow:Stop() end
		end
		return
	end

	local cfg          = element._config
	local groupClasses = element._groupClasses
	local slots        = element._slots
	local iconSize     = cfg.iconSize
	local spacing      = cfg.spacing
	local growDir      = cfg.growDirection
	local anchor       = cfg.anchor
	local anchorPoint  = anchor[1]
	local anchorX      = anchor[4]
	local anchorY      = anchor[5]
	local visibleIndex = 0

	-- For real players, raid buff spellIds are non-secret — iterate the
	-- bulk query result (zero extra allocation). For NPC party members
	-- (delves), aura data is fully secret — fall back to server-side
	-- GetAuraDataBySpellName lookups per tracked buff.
	local isNpc = not UnitIsPlayer(unit)
	local rawAuras = not isNpc and C_UnitAuras.GetUnitAuras(unit, 'HELPFUL') or nil

	for _, spellId in next, BUFF_ORDER do
		local providingClass = RAID_BUFFS[spellId]
		local slot = slots[spellId]
		if(not slot) then break end

		local hasBuff
		if(isNpc) then
			hasBuff = npcUnitHasBuff(unit, spellId)
		else
			hasBuff = auraListHasBuff(rawAuras, spellId)
		end
		if(providingClass and groupClasses[providingClass] and not hasBuff) then
			-- Missing buff from a class in the group — show and reposition
			slot.bi.icon:SetTexture(iconCache[spellId])
			slot.bi:ClearAllPoints()

			local offset = visibleIndex * (iconSize + spacing)
			if(growDir == 'RIGHT') then
				slot.bi:SetPoint(anchorPoint, self, anchorPoint, anchorX + offset, anchorY)
			elseif(growDir == 'LEFT') then
				slot.bi:SetPoint(anchorPoint, self, anchorPoint, anchorX - offset, anchorY)
			elseif(growDir == 'DOWN') then
				slot.bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY - offset)
			elseif(growDir == 'UP') then
				slot.bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY + offset)
			end

			slot.bi:Show()
			if(not slot.glow:IsActive()) then
				slot.glow:Start()
			end
			visibleIndex = visibleIndex + 1
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
		cacheSpellData()
	end

	self:RegisterEvent('UNIT_AURA', Update)
	self:RegisterEvent('GROUP_ROSTER_UPDATE', Update, true)
	self:RegisterEvent('PLAYER_ENTERING_WORLD', Update, true)

	-- On first login, group roster and spell data may not be ready when
	-- Enable fires. Schedule a delayed refresh so missing buffs appear
	-- without requiring /reload.
	C_Timer.After(2, function()
		if(self.FramedMissingBuffs and self:IsVisible()) then
			Update(self, 'DelayedInit', self.unit)
		end
	end)

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
	self:UnregisterEvent('PLAYER_ENTERING_WORLD', Update)
end

-- ============================================================
-- Rebuild
-- ============================================================

local function Rebuild(element, config)
	element._config = config
	if(element._slots) then
		for _, slot in next, element._slots do
			if(slot.bi) then
				slot.bi:Clear()
				if(slot.bi.Destroy) then slot.bi:Destroy() end
			end
			if(slot.glow) then slot.glow:Stop() end
		end
	end

	local iconSize   = config.iconSize
	local growDir    = config.growDirection
	local spacing    = config.spacing
	local glowType   = config.glowType
	local glowColor  = config.glowColor
	local frameLevel = config.frameLevel

	local numBuffs = #BUFF_ORDER
	local container = element._container

	-- Resize container
	if(growDir == 'RIGHT' or growDir == 'LEFT') then
		Widgets.SetSize(container, numBuffs * iconSize + math.max(0, numBuffs - 1) * spacing, iconSize)
	else
		Widgets.SetSize(container, iconSize, numBuffs * iconSize + math.max(0, numBuffs - 1) * spacing)
	end
	container:SetFrameLevel(element.__owner:GetFrameLevel() + frameLevel)

	element._slots = {}
	for i, spellId in next, BUFF_ORDER do
		local bi = F.Indicators.BorderIcon.Create(container, iconSize, {
			borderThickness = 1,
			borderColor     = { 0.15, 0.15, 0.15, 1 },
			showCooldown    = false,
			showStacks      = false,
			showDuration    = false,
		})

		-- No cooldown swipe — hide the dark border background so icons are clear
		bi._borderBg:SetColorTexture(0, 0, 0, 0)

		bi:Hide()

		local glow = F.Indicators.BorderGlow.Create(bi._frame, {
			borderGlowMode = 'Glow',
			glowType = glowType,
			glowColor = glowColor,
		})
		element._slots[spellId] = { bi = bi, glow = glow }
	end

	local anchor = config.anchor
	container:ClearAllPoints()
	container:SetPoint(anchor[1], element.__owner, anchor[3], anchor[4], anchor[5])

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
	container:SetPoint(a[1], self, a[3] or a[1], a[4] or 0, a[5] or 0)

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

		-- No cooldown swipe — hide the dark border background so icons are clear
		bi._borderBg:SetColorTexture(0, 0, 0, 0)

		bi:Hide()

		local glow = F.Indicators.BorderGlow.Create(bi._frame, {
			borderGlowMode = 'Glow',
			glowType = config.glowType,
			glowColor = config.glowColor,
		})

		slots[spellId] = { bi = bi, glow = glow }
	end

	self.FramedMissingBuffs = {
		_config       = config,
		_container    = container,
		_slots        = slots,
		_groupClasses = {},
		Rebuild       = Rebuild,
	}
end
