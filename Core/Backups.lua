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
-- Initialization — called from Core/Config.lua or Init.lua at load
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

--- @return table array of wrapper tables (not decoded)
function B.List()
	B.EnsureDefaults()
	local out = {}
	for _, wrapper in next, FramedSnapshotsDB.snapshots do
		out[#out + 1] = wrapper
	end
	return out
end

--- @param name string
--- @return table|nil wrapper
function B.Get(name)
	B.EnsureDefaults()
	return FramedSnapshotsDB.snapshots[name]
end
