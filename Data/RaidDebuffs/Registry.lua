local addonName, Framed = ...
local F = Framed

local Registry = {}
F.RaidDebuffRegistry = Registry

local C = F.Constants
local DebuffFilterMode = C.DebuffFilterMode

-- Internal storage: spellID -> { priority, instanceID, bossID }
local debuffs = {}

-- ============================================================
-- Registration API
-- ============================================================

--- Register a single debuff spell.
--- @param spellID number The spell ID to register
--- @param priority number Priority level (use C.DebuffPriority constants)
--- @param instanceID? number Optional instance ID this debuff belongs to
--- @param bossID? number Optional boss ID within the instance
function Registry:Register(spellID, priority, instanceID, bossID)
	debuffs[spellID] = {
		priority   = priority,
		instanceID = instanceID,
		bossID     = bossID,
	}
end

--- Bulk register all debuffs for an instance.
--- @param instanceID number The instance (dungeon/raid) ID
--- @param instanceName string Human-readable instance name (for documentation)
--- @param debuffList table Array of { spellID, priority, bossID? } entries
function Registry:RegisterInstance(instanceID, instanceName, debuffList)
	for _, entry in next, debuffList do
		local spellID, priority, bossID = entry[1], entry[2], entry[3]
		self:Register(spellID, priority, instanceID, bossID)
	end
end

-- ============================================================
-- Lookup API
-- ============================================================

--- Return the registry entry for a spell, or nil if not registered.
--- @param spellID number
--- @return table|nil
function Registry:GetDebuff(spellID)
	return debuffs[spellID]
end

--- Return the base registered priority for a spell, or 0 if not registered.
--- @param spellID number
--- @return number
function Registry:GetPriority(spellID)
	local entry = debuffs[spellID]
	if(entry) then
		return entry.priority
	end
	return 0
end

--- Return the effective priority for a spell, checking user overrides first.
--- User overrides live at F.Config:Get('raidDebuffs.overrides')[spellID].
--- Returns 0 if neither an override nor a registry entry exists.
--- @param spellID number
--- @return number
function Registry:GetEffectivePriority(spellID)
	local overrides = F.Config:Get('raidDebuffs.overrides')
	if(overrides and overrides[spellID] ~= nil) then
		return overrides[spellID]
	end
	return self:GetPriority(spellID)
end

-- ============================================================
-- Filter API
-- ============================================================

--- Check whether an aura should be shown based on its API flags and the
--- active filter mode. This only inspects isBossAura/isRaid flags — it does
--- NOT consult the registry. The caller (RaidDebuffs element) combines this
--- result with a registry lookup to implement the full display logic.
---
--- ENCOUNTER_ONLY — show when isBossAura is true
--- RAID           — show when isRaid is true (includes boss + trash)
---
--- @param auraData table auraData table from C_UnitAuras (must have isBossAura, isRaid)
--- @param filterMode string One of C.DebuffFilterMode constants
--- @return boolean
function Registry:ShouldShow(auraData, filterMode)
	if(filterMode == DebuffFilterMode.ENCOUNTER_ONLY) then
		return auraData.isBossAura == true
	elseif(filterMode == DebuffFilterMode.RAID) then
		return auraData.isRaid == true
	end
	return false
end
