local _, Framed = ...
local F = Framed

F.Version = {}
local V = F.Version

-- ============================================================
-- Parse 'vMAJOR.MINOR.PATCH[-suffix]' into a numeric triple.
-- Returns nil on inputs that don't match the expected shape.
-- ============================================================
function V.Parse(str)
	if(type(str) ~= 'string') then return nil end

	-- Strip leading 'v' if present, and any pre-release suffix after '-'
	local cleaned = str:match('^v?([%d%.]+)')
	if(not cleaned) then return nil end

	local major, minor, patch = cleaned:match('^(%d+)%.(%d+)%.(%d+)$')
	if(not major) then
		-- Allow MAJOR.MINOR with implicit patch=0
		major, minor = cleaned:match('^(%d+)%.(%d+)$')
		patch = '0'
	end

	if(not major) then return nil end

	return {
		major = tonumber(major),
		minor = tonumber(minor),
		patch = tonumber(patch),
	}
end

-- ============================================================
-- Compare two parsed triples. Returns:
--   -1 if a < b
--    0 if a == b
--   +1 if a > b
-- Both arguments must be triples returned by Parse(); returns nil
-- if either is missing, so the caller can distinguish "unknown" from
-- "equal".
-- ============================================================
function V.Compare(a, b)
	if(type(a) ~= 'table' or type(b) ~= 'table') then return nil end

	if(a.major ~= b.major) then
		return a.major < b.major and -1 or 1
	end
	if(a.minor ~= b.minor) then
		return a.minor < b.minor and -1 or 1
	end
	if(a.patch ~= b.patch) then
		return a.patch < b.patch and -1 or 1
	end
	return 0
end

-- ============================================================
-- Stale-check helper: returns true when snapshotVersion is older than
-- currentVersion by MINOR-or-greater (PATCH-only differences return false).
-- Both inputs are raw version strings like 'v0.8.6-alpha'.
-- ============================================================
function V.IsStaleOlder(snapshotVersion, currentVersion)
	local a = V.Parse(snapshotVersion)
	local b = V.Parse(currentVersion)
	if(not a or not b) then return false end

	if(a.major < b.major) then return true end
	if(a.major == b.major and a.minor < b.minor) then return true end
	return false
end

-- ============================================================
-- Mirror of IsStaleOlder for the newer-than-current case.
-- ============================================================
function V.IsStaleNewer(snapshotVersion, currentVersion)
	local a = V.Parse(snapshotVersion)
	local b = V.Parse(currentVersion)
	if(not a or not b) then return false end

	if(a.major > b.major) then return true end
	if(a.major == b.major and a.minor > b.minor) then return true end
	return false
end
