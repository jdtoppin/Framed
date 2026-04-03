local addonName, Framed = ...
local F = Framed

-- ============================================================
-- EditCache — Shadow config for edit mode
-- Stores pending changes per frame key. Reads check cache first,
-- falls back to F.Config. Writes go to cache only.
-- Commit flushes to real config. Discard clears everything.
-- ============================================================

local EditCache = {}
F.EditCache = EditCache

-- cache[frameKey][configPath] = value
local cache = {}
local active = false
local preEditPositions = {}

--- Activate the edit cache (called on edit mode entry).
function EditCache.Activate()
	active = true
	cache = {}
	preEditPositions = {}
end

--- Deactivate the edit cache (called on edit mode exit).
function EditCache.Deactivate()
	active = false
	cache = {}
	preEditPositions = {}
end

--- Check if the edit cache is active.
--- @return boolean
function EditCache.IsActive()
	return active
end

--- Store a value in the edit cache for a specific frame key.
--- @param frameKey string  Frame identifier (e.g., 'player', 'target', 'party')
--- @param configPath string  Config key relative to the preset (e.g., 'health.height')
--- @param value any  The new value
function EditCache.Set(frameKey, configPath, value)
	if(not cache[frameKey]) then
		cache[frameKey] = {}
	end
	cache[frameKey][configPath] = value
	-- Notify preview system of live change
	F.EventBus:Fire('EDIT_CACHE_VALUE_CHANGED', frameKey, configPath, value)
end

--- Read a value, checking the edit cache first, then falling back to real config.
--- @param frameKey string  Frame identifier
--- @param configPath string  Config key relative to the preset
--- @return any value
function EditCache.Get(frameKey, configPath)
	if(active and cache[frameKey] and cache[frameKey][configPath] ~= nil) then
		return cache[frameKey][configPath]
	end
	-- Fall back to real config
	local presetName = F.Settings.GetEditingPreset()
	return F.Config:Get('presets.' .. presetName .. '.unitConfigs.' .. frameKey .. '.' .. configPath)
end

--- Check if a specific frame has any cached edits.
--- @param frameKey string
--- @return boolean
function EditCache.HasEdits(frameKey)
	return cache[frameKey] ~= nil and next(cache[frameKey]) ~= nil
end

--- Check if any frame has cached edits.
--- @return boolean
function EditCache.HasAnyEdits()
	for _, edits in next, cache do
		if(next(edits)) then return true end
	end
	return false
end

--- Get all cached edits for a specific frame.
--- @param frameKey string
--- @return table|nil  Flat table of { [configPath] = value } or nil
function EditCache.GetEditsForFrame(frameKey)
	return cache[frameKey]
end

--- Flush (remove) cached edits for a specific frame key.
--- @param frameKey string
function EditCache.FlushFrame(frameKey)
	cache[frameKey] = nil
end

--- Commit all cached edits to real config.
function EditCache.Commit()
	local presetName = F.Settings.GetEditingPreset()
	for frameKey, edits in next, cache do
		for configPath, value in next, edits do
			F.Config:Set('presets.' .. presetName .. '.unitConfigs.' .. frameKey .. '.' .. configPath, value)
		end
	end
	F.PresetManager.MarkCustomized(presetName)
	cache = {}
end

--- Discard all cached edits (clear without committing).
function EditCache.Discard()
	cache = {}
end

--- Save a snapshot of frame positions before edit mode starts.
--- @param positions table  { [frameKey] = { point, relativeTo, relPoint, x, y } }
function EditCache.SavePreEditPositions(positions)
	preEditPositions = positions
end

--- Get the pre-edit position snapshot for restoring on discard.
--- @return table
function EditCache.GetPreEditPositions()
	return preEditPositions
end
