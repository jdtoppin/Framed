local addonName, Framed = ...
local F = Framed

-- ============================================================
-- Secret Value Utilities
-- Central location for all secret value checks.
-- Every file uses these — never bare issecretvalue().
-- ============================================================

--- Check if a value is non-secret and safe for Lua-level operations.
--- This is the ONE function all files use for secret checks.
--- @param value any
--- @return boolean true if the value can be used in Lua arithmetic/comparison
function F.IsValueNonSecret(value)
	if(value == nil) then return false end
	if(not issecretvalue) then return true end
	return not issecretvalue(value)
end

--- Check if any values in a table are secret.
--- Wraps Blizzard's hasanysecretvalues() with safe access.
--- @param tbl table
--- @return boolean true if any value in the table is secret
function F.HasAnySecretValues(tbl)
	if(not hasanysecretvalues) then return false end
	return hasanysecretvalues(tbl)
end

--- Check if a spell's aura should be treated as secret.
--- Wraps C_Secrets.ShouldSpellAuraBeSecret() with safe access.
--- @param spellID number
--- @return boolean true if the aura should be secret
function F.ShouldSpellAuraBeSecret(spellID)
	if(not C_Secrets or not C_Secrets.ShouldSpellAuraBeSecret) then
		return false
	end
	if(not F.IsValueNonSecret(spellID)) then return true end
	return C_Secrets.ShouldSpellAuraBeSecret(spellID)
end
