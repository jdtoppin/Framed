local _, Framed = ...
local F = Framed

F.Backups = {}
local B = F.Backups

-- ============================================================
-- Constants
-- ============================================================

B.SCHEMA_VERSION = 1

B.AUTO_LOGIN     = '__auto_login'
B.AUTO_PREIMPORT = '__auto_preimport'
B.AUTO_PRELOAD   = '__auto_preload'

B.AUTO_LABELS = {
	[B.AUTO_LOGIN]     = 'Automatic — Session start',
	[B.AUTO_PREIMPORT] = 'Automatic — Before last import',
	[B.AUTO_PRELOAD]   = 'Automatic — Before last load',
}

B.AUTO_ORDER = {
	B.AUTO_LOGIN,
	B.AUTO_PREIMPORT,
	B.AUTO_PRELOAD,
}

B.NAME_MAX_LEN = 64

-- ============================================================
-- Initialization — called from Init.lua at ADDON_LOADED
-- ============================================================

function B.EnsureDefaults()
	if(type(FramedSnapshotsDB) ~= 'table') then
		FramedSnapshotsDB = {
			schemaVersion = B.SCHEMA_VERSION,
			snapshots     = {},
		}
		return
	end
	if(type(FramedSnapshotsDB.snapshots) ~= 'table') then
		FramedSnapshotsDB.snapshots = {}
	end
	if(not FramedSnapshotsDB.schemaVersion) then
		FramedSnapshotsDB.schemaVersion = B.SCHEMA_VERSION
	end
end

-- ============================================================
-- Stubs for the API — filled in by later tasks
-- ============================================================

--- @return table array of { name, wrapper } pairs
function B.List()
	local out = {}
	for name, wrapper in next, FramedSnapshotsDB.snapshots do
		out[#out + 1] = { name = name, wrapper = wrapper }
	end
	return out
end

--- @param name string
--- @return table|nil wrapper
function B.Get(name)
	return FramedSnapshotsDB.snapshots[name]
end

-- ============================================================
-- Name validation
-- Returns (true) for valid names and (false, errorMessage) otherwise.
-- Trimming is the caller's responsibility — call TrimName first.
-- ============================================================

--- Trim leading/trailing whitespace and return the cleaned name.
function B.TrimName(name)
	if(type(name) ~= 'string') then return '' end
	return (name:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Shared prefix checks used by both public validators.
-- Returns (true, nil) on success or (false, errMsg) on failure.
-- Does NOT call EnsureDefaults — callers handle that themselves.
local function validatePrefix(name)
	if(type(name) ~= 'string' or name == '') then
		return false, "Name can't be empty."
	end
	if(#name > B.NAME_MAX_LEN) then
		return false, 'Name is too long (max ' .. B.NAME_MAX_LEN .. ' characters).'
	end
	if(name:find('^__auto_')) then
		return false, 'Names starting with `__auto_` are reserved for automatic snapshots.'
	end
	for _, label in next, B.AUTO_LABELS do
		if(name:lower() == label:lower()) then
			return false, 'That name is reserved.'
		end
	end
	return true, nil
end

--- Validate a (trimmed) snapshot name.
--- @param name string
--- @return boolean valid, string|nil errMsg
function B.ValidateName(name)
	local ok, err = validatePrefix(name)
	if(not ok) then return ok, err end

	-- Case-insensitive uniqueness against existing user snapshots
	B.EnsureDefaults()
	local lower = name:lower()
	for existingName, wrapper in next, FramedSnapshotsDB.snapshots do
		if(not wrapper.automatic and existingName:lower() == lower) then
			return false, 'A snapshot with that name already exists.'
		end
	end

	return true, nil
end

--- Same as ValidateName but excludes a specific name from the uniqueness
--- check — used by Rename so renaming to the same name (no-op) is valid
--- and so a user can fix casing without tripping the unique check.
function B.ValidateNameForRename(name, excludeName)
	local ok, err = validatePrefix(name)
	if(not ok) then return ok, err end

	B.EnsureDefaults()
	local lower      = name:lower()
	local excludeLow = excludeName and excludeName:lower() or nil
	for existingName, wrapper in next, FramedSnapshotsDB.snapshots do
		local exLow = existingName:lower()
		if(not wrapper.automatic and exLow == lower and exLow ~= excludeLow) then
			return false, 'A snapshot with that name already exists.'
		end
	end

	return true, nil
end

-- ============================================================
-- Internal: build a wrapper table around an already-encoded payload
-- ============================================================

local function buildWrapper(opts)
	return {
		version     = opts.version     or F.version or 'unknown',
		timestamp   = opts.timestamp   or time(),
		automatic   = opts.automatic   or false,
		autoKind    = opts.autoKind    or nil,
		layoutCount = opts.layoutCount or 0,
		sizeBytes   = opts.sizeBytes   or 0,
		payload     = opts.payload,
	}
end

-- ============================================================
-- Save — capture live config and store under a user-named key
-- ============================================================

--- Capture current live FramedDB + FramedCharDB state and save it as a
--- user-named snapshot. Runs name validation and returns (true) on
--- success or (false, errMsg) on failure.
--- @param name string  trimmed snapshot name
--- @return boolean ok, string|nil err
function B.Save(name)
	B.EnsureDefaults()

	local ok, err = B.ValidateName(name)
	if(not ok) then return false, err end

	if(not F.ImportExport or not F.ImportExport.CaptureFullProfileData) then
		return false, 'ImportExport module not ready'
	end

	local payloadTable = F.ImportExport.CaptureFullProfileData()
	local layoutCount  = 0
	if(type(payloadTable.presets) == 'table') then
		for _ in next, payloadTable.presets do
			layoutCount = layoutCount + 1
		end
	end

	local encoded, encErr = F.ImportExport.Export(payloadTable, 'full')
	if(not encoded) then
		return false, encErr or 'Failed to encode snapshot'
	end

	FramedSnapshotsDB.snapshots[name] = buildWrapper({
		version     = F.version,
		timestamp   = time(),
		automatic   = false,
		layoutCount = layoutCount,
		sizeBytes   = #encoded,
		payload     = encoded,
	})

	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_CREATED', name, false)
	end
	return true
end

-- ============================================================
-- SaveFromPayload — store an already-encoded import string as a snapshot
-- ============================================================

--- Save an already-encoded payload string (used by Import as Snapshot).
--- The version, timestamp, and layoutCount are derived from the decoded
--- payload, NOT from the current addon version — this keeps the stale
--- check accurate when a user imports an old string.
--- @param name string
--- @param encoded string
--- @return boolean ok, string|nil err
function B.SaveFromPayload(name, encoded)
	B.EnsureDefaults()

	local ok, err = B.ValidateName(name)
	if(not ok) then return false, err end

	if(not F.ImportExport or not F.ImportExport.Import) then
		return false, 'ImportExport module not ready'
	end

	local parsed, parseErr = F.ImportExport.Import(encoded)
	if(not parsed) then
		return false, parseErr or 'Invalid import string'
	end

	local layoutCount = 0
	if(parsed.scope == 'full' and type(parsed.data) == 'table' and type(parsed.data.presets) == 'table') then
		for _ in next, parsed.data.presets do
			layoutCount = layoutCount + 1
		end
	elseif(parsed.scope == 'layout' and type(parsed.data) == 'table' and parsed.data.layout) then
		layoutCount = 1
	end

	-- Derive the version stored in the import payload itself. The payload's
	-- envelope has a numeric `version` field for the envelope schema; the
	-- snapshot's display `version` should come from payload.data.version if
	-- present. Fall back to 'unknown'.
	local payloadVersion = (type(parsed.data) == 'table' and parsed.data.version) or parsed.sourceVersion or 'unknown'

	FramedSnapshotsDB.snapshots[name] = buildWrapper({
		version     = payloadVersion,
		timestamp   = parsed.timestamp or time(),
		automatic   = false,
		layoutCount = layoutCount,
		sizeBytes   = #encoded,
		payload     = encoded,
	})

	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_CREATED', name, false)
	end
	return true
end

-- ============================================================
-- Delete
-- ============================================================

--- Delete a snapshot. Returns (wrapper) on success so the caller can
--- hold the reference in memory for undo.
--- @param name string
--- @return table|nil removedWrapper
function B.Delete(name)
	B.EnsureDefaults()
	local existing = FramedSnapshotsDB.snapshots[name]
	if(not existing) then return nil end

	FramedSnapshotsDB.snapshots[name] = nil

	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_DELETED', name)
	end
	return existing
end

--- Restore a previously-deleted wrapper under its original name.
--- Used by the undo toast. Returns true if the restore succeeded.
--- @param name string
--- @param wrapper table
--- @return boolean ok
function B.RestoreDeleted(name, wrapper)
	B.EnsureDefaults()
	if(not name or not wrapper) then return false end

	-- If a same-named snapshot has appeared in the meantime (race), bail
	if(FramedSnapshotsDB.snapshots[name]) then return false end

	FramedSnapshotsDB.snapshots[name] = wrapper
	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_CREATED', name, wrapper.automatic and true or false)
	end
	return true
end

-- ============================================================
-- Rename
-- ============================================================

--- Rename a user-named snapshot. Automatic snapshots (name starting with
--- '__auto_') cannot be renamed and the call returns (false, errMsg).
--- @param oldName string
--- @param newName string
--- @return boolean ok, string|nil err
function B.Rename(oldName, newName)
	B.EnsureDefaults()

	local wrapper = FramedSnapshotsDB.snapshots[oldName]
	if(not wrapper) then
		return false, 'Snapshot not found.'
	end
	if(wrapper.automatic) then
		return false, 'Automatic snapshots cannot be renamed.'
	end

	newName = B.TrimName(newName)
	if(newName == oldName) then
		return true -- no-op
	end

	local ok, err = B.ValidateNameForRename(newName, oldName)
	if(not ok) then return false, err end

	FramedSnapshotsDB.snapshots[newName] = wrapper
	FramedSnapshotsDB.snapshots[oldName] = nil

	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_DELETED', oldName)
		F.EventBus:Fire('BACKUP_CREATED', newName, false)
	end
	return true
end
