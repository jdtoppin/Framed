local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.MissingBuffs = {}

-- ============================================================
-- Default tracked buffs
-- ============================================================

local IMPORTANT_BUFFS = {
	[21562]  = true,  -- Power Word: Fortitude
	[1459]   = true,  -- Arcane Intellect
	[6673]   = true,  -- Battle Shout
	[381748] = true,  -- Blessing of the Bronze
}

-- ============================================================
-- Helpers
-- ============================================================

--- Check whether the unit currently has a buff with the given spellId.
--- Iterates helpful auras and compares spellId; stops when it finds a match.
--- @param unit string
--- @param targetSpellId number
--- @return boolean
local function unitHasBuff(unit, targetSpellId)
	local i = 1
	while(true) do
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HELPFUL')
		if(not auraData) then break end
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId) and spellId == targetSpellId) then
			return true
		end
		i = i + 1
	end
	return false
end

--- Resolve the texture ID for a spell.
--- @param spellId number
--- @return number|nil
local function getSpellIcon(spellId)
	if(C_Spell and C_Spell.GetSpellInfo) then
		local info = C_Spell.GetSpellInfo(spellId)
		if(info) then return info.iconID end
	elseif(GetSpellInfo) then
		local _, _, icon = GetSpellInfo(spellId)
		return icon
	end
	return nil
end

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedMissingBuffs
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local trackedBuffs = element._trackedBuffs
	local dimAlpha     = element._dimAlpha

	-- Build a list of missing buffs in deterministic order (spellId ascending)
	local missingList = {}
	for spellId in next, trackedBuffs do
		if(not unitHasBuff(unit, spellId)) then
			missingList[#missingList + 1] = {
				spellID        = spellId,
				icon           = getSpellIcon(spellId),
				duration       = 0,
				expirationTime = 0,
				stacks         = 0,
				dispelType     = nil,
			}
		end
	end

	-- Sort by spellId for a stable display order
	table.sort(missingList, function(a, b) return a.spellID < b.spellID end)

	element._icons:SetIcons(missingList)

	-- Apply dim alpha to every active pool icon
	local pool = element._icons._pool
	local activeCount = element._icons:GetActiveCount()
	for i = 1, activeCount do
		local icon = pool[i]
		if(icon) then
			icon._frame:SetAlpha(dimAlpha)
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

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedMissingBuffs
	if(not element) then return end

	element._icons:Hide()

	self:UnregisterEvent('UNIT_AURA', Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedMissingBuffs', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create a MissingBuffs element on a unit frame.
--- Shows dimmed icons for each important buff the unit is currently missing.
--- Assigns result to self.FramedMissingBuffs, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: trackedBuffs, iconSize, dimAlpha, growDirection, anchor
function F.Elements.MissingBuffs.Setup(self, config)
	config = config or {}
	config.trackedBuffs  = config.trackedBuffs  or IMPORTANT_BUFFS
	config.iconSize      = config.iconSize      or 14
	config.dimAlpha      = config.dimAlpha      or 0.4
	config.growDirection = config.growDirection or 'RIGHT'
	config.anchor        = config.anchor        or { 'TOPLEFT', self, 'TOPLEFT', 2, -2 }

	-- Count tracked buffs for maxIcons
	local maxIcons = 0
	for _ in next, config.trackedBuffs do
		maxIcons = maxIcons + 1
	end

	local icons = F.Indicators.Icons.Create(self, {
		maxIcons      = maxIcons,
		iconSize      = config.iconSize,
		growDirection = config.growDirection,
		displayType   = C.IconDisplay.SPELL_ICON,
		showCooldown  = false,
		showStacks    = false,
		showDuration  = false,
	})

	local a = config.anchor
	icons:SetPoint(a[1], a[2], a[3], a[4] or 0, a[5] or 0)

	local container = {
		_icons       = icons,
		_trackedBuffs = config.trackedBuffs,
		_dimAlpha    = config.dimAlpha,
	}

	self.FramedMissingBuffs = container
end
