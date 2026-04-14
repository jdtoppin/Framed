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

--- Validate a (trimmed) snapshot name.
--- @param name string
--- @return boolean valid, string|nil errMsg
function B.ValidateName(name)
	if(type(name) ~= 'string' or name == '') then
		return false, "Name can't be empty."
	end
	if(#name > B.NAME_MAX_LEN) then
		return false, 'Name is too long (max ' .. B.NAME_MAX_LEN .. ' characters).'
	end
	if(name:find('^__auto_')) then
		return false, 'Names starting with `__auto_` are reserved for automatic snapshots.'
	end

	-- Collision with automatic display labels
	for _, label in next, B.AUTO_LABELS do
		if(name:lower() == label:lower()) then
			return false, 'That name is reserved.'
		end
	end

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

	B.EnsureDefaults()
	local lower       = name:lower()
	local excludeLow  = excludeName and excludeName:lower() or nil
	for existingName, wrapper in next, FramedSnapshotsDB.snapshots do
		if(not wrapper.automatic and existingName:lower() == lower and existingName:lower() ~= excludeLow) then
			return false, 'A snapshot with that name already exists.'
		end
	end

	return true, nil
end
