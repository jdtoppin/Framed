local _, Framed = ...
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

local function refreshAfterImport(scope)
	if(F.Config and F.Config.EnsureDefaults) then
		F.Config:EnsureDefaults()
	end

	if(F.PresetDefaults and F.PresetDefaults.EnsureDefaults) then
		F.PresetDefaults.EnsureDefaults()
	end

	if(F.ClickCasting and F.ClickCasting.RefreshAll) then
		F.ClickCasting.RefreshAll()
	end

	if(F.AutoSwitch and F.AutoSwitch.Check) then
		F.AutoSwitch.Check()
	end

	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'general.targetHighlightColor')
		F.EventBus:Fire('CONFIG_CHANGED', 'general.targetHighlightWidth')
		F.EventBus:Fire('CONFIG_CHANGED', 'general.mouseoverHighlightColor')
		F.EventBus:Fire('CONFIG_CHANGED', 'general.mouseoverHighlightWidth')
		F.EventBus:Fire('CONFIG_CHANGED:autoSwitch')
		F.EventBus:Fire('CONFIG_CHANGED:specOverrides')
		F.EventBus:Fire('CONFIG_CHANGED:clickCasting')

		if(scope == 'full' and F.AutoSwitch and F.AutoSwitch.GetCurrentPreset) then
			F.EventBus:Fire('PRESET_CHANGED', F.AutoSwitch.GetCurrentPreset())
		end
	end
end

-- ============================================================
-- Export
-- Serializes, compresses, and encodes a data table into a
-- printable string prefixed with VERSION_PREFIX.
-- Returns: string | nil, errorString
-- ============================================================

--- Build and encode an export string.
--- @param data table The data payload to export
--- @param scope string A label describing what was exported ('full'|'layout')
--- @return string|nil encoded, string|nil err
function ImportExport.Export(data, scope)
	if(not LibSerialize) then
		return nil, 'LibSerialize is not available'
	end
	if(not LibDeflate) then
		return nil, 'LibDeflate is not available'
	end

	local payload = {
		version       = 1,
		scope         = scope,
		timestamp     = time(),
		sourceVersion = F.version,
		data          = data,
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

	local corruptedMsg = "Couldn't read this import string. It may be corrupted or incomplete — make sure you copied the entire string."

	if(not inputString or inputString == '') then
		return nil, 'Paste an import string to continue.'
	end

	-- Check prefix
	if(inputString:sub(1, #VERSION_PREFIX) ~= VERSION_PREFIX) then
		return nil, "This doesn't look like a Framed import string. Make sure you copied it from the Export card."
	end

	-- Strip prefix
	local encoded = inputString:sub(#VERSION_PREFIX + 1)

	local compressed = LibDeflate:DecodeForPrint(encoded)
	if(not compressed) then
		return nil, corruptedMsg
	end

	local serialized = LibDeflate:DecompressDeflate(compressed)
	if(not serialized) then
		return nil, corruptedMsg
	end

	-- LibSerialize:Deserialize is already pcall-wrapped internally and returns
	-- (success, value). Do NOT add an outer pcall — doing so shifts the return
	-- positions and silently drops the deserialized table.
	local success, payload = LibSerialize:Deserialize(serialized)
	if(not success or type(payload) ~= 'table') then
		return nil, corruptedMsg
	end

	if(payload.version ~= 1) then
		return nil, 'This import string was made by a newer version of Framed. Update the addon and try again.'
	end
	if(not payload.scope) then
		return nil, corruptedMsg
	end

	return payload
end

-- ============================================================
-- Scope helpers — build data tables for export
-- ============================================================

--- Export a single layout table directly (no FramedDB lookup).
--- Used by the Backups row Export action after decoding a snapshot payload.
--- @param layoutName string
--- @param layoutTable table
--- @return string|nil encoded, string|nil err
function ImportExport.ExportLayoutData(layoutName, layoutTable)
	if(not layoutName or layoutName == '') then
		return nil, 'Layout name is required'
	end
	if(type(layoutTable) ~= 'table') then
		return nil, 'Layout data is required'
	end

	local data = {
		name   = layoutName,
		layout = F.DeepCopy(layoutTable) or layoutTable,
	}

	return ImportExport.Export(data, 'layout')
end

--- Export a single layout from live FramedDB by name.
--- @param layoutName string
--- @return string|nil encoded, string|nil err
function ImportExport.ExportLayout(layoutName)
	if(not FramedDB or not FramedDB.presets) then
		return nil, 'SavedVariables not ready'
	end
	if(not layoutName or layoutName == '') then
		return nil, 'Layout name is required'
	end

	local layout = FramedDB.presets[layoutName]
	if(not layout) then
		return nil, 'Layout not found: ' .. layoutName
	end

	return ImportExport.ExportLayoutData(layoutName, layout)
end

--- Build the in-memory full-profile payload table (before serialization).
--- The Backups module calls this to get a snapshot payload without
--- going through the full Export pipeline twice.
--- Note: the `profiles` field from accountDefaults is intentionally NOT
--- included — it was dead storage from an earlier design and is removed
--- in this release.
--- @return table
function ImportExport.CaptureFullProfileData()
	if(not FramedDB) then return {} end

	return {
		general = F.DeepCopy(FramedDB.general) or {},
		minimap = F.DeepCopy(FramedDB.minimap) or {},
		presets = F.DeepCopy(FramedDB.presets) or {},
		char    = F.DeepCopy(FramedCharDB)     or {},
	}
end

--- Export general settings + all layouts.
--- @return string|nil encoded, string|nil err
function ImportExport.ExportFullProfile()
	if(not FramedDB) then
		return nil, 'SavedVariables not ready'
	end

	return ImportExport.Export(ImportExport.CaptureFullProfileData(), 'full')
end

-- ============================================================
-- ApplyImport
-- Applies a validated payload to the live config. Replace-only.
-- ============================================================

--- Apply an import payload to the live config. Replace-only.
--- The legacy merge mode is removed — see the Backups spec.
--- @param payload table A validated payload returned by Import()
function ImportExport.ApplyImport(payload)
	if(not payload or not payload.scope or not payload.data) then return end
	if(not FramedDB) then return end

	-- Capture pre-import automatic snapshot (rotating, 1-deep).
	-- This runs for both the Import card path AND the Backups.Load path
	-- (Backups.Load captures its own __auto_preload separately first).
	if(F.Backups and F.Backups.CaptureAutomatic) then
		F.Backups.CaptureAutomatic(F.Backups.AUTO_PREIMPORT)
	end

	local scope = payload.scope
	local data  = payload.data

	if(scope == 'full') then
		if(data.general)  then FramedDB.general  = F.DeepCopy(data.general) end
		if(data.minimap)  then FramedDB.minimap  = F.DeepCopy(data.minimap) end
		if(data.presets)  then FramedDB.presets  = F.DeepCopy(data.presets) end
		if(data.char)     then FramedCharDB      = F.DeepCopy(data.char)    end

	elseif(scope == 'layout') then
		local name   = data.name
		local layout = data.layout
		if(not name or not layout) then return end

		FramedDB.presets[name] = F.DeepCopy(layout)

		if(F.EventBus) then
			F.EventBus:Fire('LAYOUT_CREATED', name)
		end
	end

	refreshAfterImport(scope)

	if(F.EventBus) then
		F.EventBus:Fire('IMPORT_APPLIED', scope, 'replace')
	end
end
