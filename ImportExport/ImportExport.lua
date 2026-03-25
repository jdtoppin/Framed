local addonName, Framed = ...
local F = Framed

F.ImportExport = {}

local ImportExport = F.ImportExport

-- ============================================================
-- Libraries (safe access — may not be loaded)
-- ============================================================

local LibSerialize = LibStub and LibStub('LibSerialize', true)
local LibDeflate   = LibStub and LibStub('LibDeflate', true)

-- ============================================================
-- Constants
-- ============================================================

local VERSION_PREFIX = '!FRM1!'

-- ============================================================
-- Export
-- Serializes, compresses, and encodes a data table into a
-- printable string prefixed with VERSION_PREFIX.
-- Returns: string | nil, errorString
-- ============================================================

--- Build and encode an export string.
--- @param data table The data payload to export
--- @param scope string A label describing what was exported ('full'|'layout'|'raidDebuffs')
--- @return string|nil encoded, string|nil err
function ImportExport.Export(data, scope)
	if(not LibSerialize) then
		return nil, 'LibSerialize is not available'
	end
	if(not LibDeflate) then
		return nil, 'LibDeflate is not available'
	end

	local payload = {
		version   = 1,
		scope     = scope,
		timestamp = time(),
		data      = data,
	}

	local serialized = LibSerialize:Serialize(payload)
	local compressed = LibDeflate:CompressDeflate(serialized)
	local encoded    = LibDeflate:EncodeForPrint(compressed)

	return VERSION_PREFIX .. encoded
end

-- ============================================================
-- Import
-- Decodes, decompresses, and deserializes an import string.
-- Returns: payload table | nil, errorString
-- ============================================================

--- Parse and validate an import string.
--- @param inputString string The raw import string
--- @return table|nil payload, string|nil err
function ImportExport.Import(inputString)
	if(not LibSerialize) then
		return nil, 'LibSerialize is not available'
	end
	if(not LibDeflate) then
		return nil, 'LibDeflate is not available'
	end

	if(not inputString or inputString == '') then
		return nil, 'Import string is empty'
	end

	-- Check prefix
	if(inputString:sub(1, #VERSION_PREFIX) ~= VERSION_PREFIX) then
		return nil, 'Invalid import string (unrecognised format)'
	end

	-- Strip prefix
	local encoded = inputString:sub(#VERSION_PREFIX + 1)

	local compressed = LibDeflate:DecodeForPrint(encoded)
	if(not compressed) then
		return nil, 'Failed to decode import string'
	end

	local serialized = LibDeflate:DecompressDeflate(compressed)
	if(not serialized) then
		return nil, 'Failed to decompress import string'
	end

	-- pcall IS justified here: untrusted data from user input
	local ok, payload = pcall(LibSerialize.Deserialize, LibSerialize, serialized)
	if(not ok or not payload) then
		return nil, 'Failed to deserialize import string'
	end

	-- Validate version
	if(type(payload) ~= 'table') then
		return nil, 'Invalid payload structure'
	end
	if(payload.version ~= 1) then
		return nil, 'Unsupported import version: ' .. tostring(payload.version)
	end
	if(not payload.scope) then
		return nil, 'Missing scope in import payload'
	end

	return payload
end

-- ============================================================
-- Scope helpers — build data tables for export
-- ============================================================

--- Export general settings + all layouts + raidDebuff overrides.
--- @return string|nil encoded, string|nil err
function ImportExport.ExportFullProfile()
	if(not FramedDB) then
		return nil, 'SavedVariables not ready'
	end

	local data = {
		general    = F.LayoutManager and F.LayoutManager.DeepCopy(FramedDB.general)    or {},
		layouts    = F.LayoutManager and F.LayoutManager.DeepCopy(FramedDB.layouts)    or {},
		raidDebuffs = F.LayoutManager and F.LayoutManager.DeepCopy(FramedDB.raidDebuffs) or {},
	}

	return ImportExport.Export(data, 'full')
end

--- Export a single layout by name.
--- @param layoutName string
--- @return string|nil encoded, string|nil err
function ImportExport.ExportLayout(layoutName)
	if(not FramedDB or not FramedDB.layouts) then
		return nil, 'SavedVariables not ready'
	end
	if(not layoutName or layoutName == '') then
		return nil, 'Layout name is required'
	end

	local layout = FramedDB.layouts[layoutName]
	if(not layout) then
		return nil, 'Layout not found: ' .. layoutName
	end

	local data = {
		name   = layoutName,
		layout = F.LayoutManager and F.LayoutManager.DeepCopy(layout) or layout,
	}

	return ImportExport.Export(data, 'layout')
end

--- Export raid debuff overrides only.
--- @return string|nil encoded, string|nil err
function ImportExport.ExportRaidDebuffs()
	if(not FramedDB or not FramedDB.raidDebuffs) then
		return nil, 'SavedVariables not ready'
	end

	local data = {
		overrides = F.LayoutManager and F.LayoutManager.DeepCopy(FramedDB.raidDebuffs.overrides) or {},
	}

	return ImportExport.Export(data, 'raidDebuffs')
end

-- ============================================================
-- ApplyImport
-- Applies a validated payload to the live config.
-- mode: 'replace' | 'merge'
-- ============================================================

--- Deep-merge src into dst, overwriting scalars and merging tables.
--- @param dst table
--- @param src table
local function deepMerge(dst, src)
	for k, v in next, src do
		if(type(v) == 'table' and type(dst[k]) == 'table') then
			deepMerge(dst[k], v)
		else
			dst[k] = F.LayoutManager and F.LayoutManager.DeepCopy(v) or v
		end
	end
end

--- Apply an import payload to the live config.
--- @param payload table A validated payload returned by Import()
--- @param mode string 'replace' | 'merge'
function ImportExport.ApplyImport(payload, mode)
	if(not payload or not payload.scope or not payload.data) then return end
	if(not FramedDB) then return end

	mode = mode or 'replace'
	local scope = payload.scope
	local data  = payload.data

	-- ── Full profile ──────────────────────────────────────────
	if(scope == 'full') then
		if(mode == 'replace') then
			if(data.general)     then FramedDB.general     = F.LayoutManager.DeepCopy(data.general) end
			if(data.layouts)     then FramedDB.layouts     = F.LayoutManager.DeepCopy(data.layouts) end
			if(data.raidDebuffs) then FramedDB.raidDebuffs = F.LayoutManager.DeepCopy(data.raidDebuffs) end
		else  -- merge
			if(data.general and type(data.general) == 'table') then
				deepMerge(FramedDB.general, data.general)
			end
			if(data.layouts and type(data.layouts) == 'table') then
				deepMerge(FramedDB.layouts, data.layouts)
			end
			if(data.raidDebuffs and type(data.raidDebuffs) == 'table') then
				deepMerge(FramedDB.raidDebuffs, data.raidDebuffs)
			end
		end

	-- ── Single layout ─────────────────────────────────────────
	elseif(scope == 'layout') then
		local name   = data.name
		local layout = data.layout

		if(not name or not layout) then return end

		if(mode == 'replace') then
			FramedDB.layouts[name] = F.LayoutManager.DeepCopy(layout)
		else  -- merge
			-- Append " (imported)" suffix on name conflict
			if(FramedDB.layouts[name]) then
				name = name .. ' (imported)'
			end
			FramedDB.layouts[name] = F.LayoutManager.DeepCopy(layout)
		end

		if(F.EventBus) then
			F.EventBus:Fire('LAYOUT_CREATED', name)
		end

	-- ── Raid debuff overrides ─────────────────────────────────
	elseif(scope == 'raidDebuffs') then
		if(not data.overrides) then return end

		if(mode == 'replace') then
			FramedDB.raidDebuffs.overrides = F.LayoutManager.DeepCopy(data.overrides)
		else  -- merge
			deepMerge(FramedDB.raidDebuffs.overrides, data.overrides)
		end
	end

	-- Fire event so UI panels can refresh
	if(F.EventBus) then
		F.EventBus:Fire('IMPORT_APPLIED', scope, mode)
	end
end
