local _, Framed = ...
local F = Framed

local Config = {}
F.Config = Config

local Constants = F.Constants
local EventBus = F.EventBus

-- ============================================================
-- Default Values
-- ============================================================
local accountDefaults = {
	general = {
		accentColor = { 0, 0.8, 1, 1 },  -- cyan default
		uiScale = 1.0,
		barTexture = 'Framed',
		font = nil,
		roleIconStyle = 2,
		wizardCompleted = false,
		overviewCompleted = false,
		tooltipEnabled = true,
		tooltipHideInCombat = false,
		tooltipMode = 'frame',
		tooltipAnchor = 'RIGHT',
		tooltipOffsetX = 0,
		tooltipOffsetY = 0,
		targetHighlightColor = { 0.839, 0, 0.075, 1 },   -- #d60013
		targetHighlightWidth = 2,
		mouseoverHighlightColor = { 0.969, 0.925, 1, 0.6 }, -- #f7ecff @ 60%
		mouseoverHighlightWidth = 2,
		pinnedCards = {},
		pinnedAppearanceCards = {},
		pinnedPresetCards = {},
		editModeGridSnap = true,
		editModeAnimate = false,
		settingsPos = nil,
		settingsSize = nil,
	},
	minimap = { hide = false },
	presets = {},       -- populated by Presets/Defaults.lua
}

local charDefaults = {
	autoSwitch = {
		['solo']         = 'Solo',
		['party']        = 'Party',
		['raid']         = 'Raid',
		['mythicRaid']   = 'Mythic Raid',
		['worldRaid']    = 'World Raid',
		['battleground'] = 'Battleground',
		['arena']        = 'Arena',
	},
	specOverrides = {},
	lastPanel = nil,
	lastEditingPreset = nil,
	lastEditingUnitType = nil,
}

local function applyRuntimeConfig()
	-- Clamp UI scale to safe range
	FramedDB.general.uiScale = math.max(0.2, math.min(FramedDB.general.uiScale or 1.0, 1.5))

	-- Apply accent color from saved config to Constants
	local accent = FramedDB.general.accentColor
	if(accent) then
		Constants.Colors.accent      = { accent[1], accent[2], accent[3], 1 }
		Constants.Colors.accentDim   = { accent[1], accent[2], accent[3], 0.3 }
		Constants.Colors.accentHover = { accent[1], accent[2], accent[3], 0.6 }
	end
end

-- ============================================================
-- Merge defaults into saved data (non-destructive)
-- Adds missing keys from defaults without overwriting existing values.
-- ============================================================
local function mergeDefaults(saved, defaults)
	for k, v in next, defaults do
		if(saved[k] == nil) then
			saved[k] = F.DeepCopy(v)
		elseif(type(v) == 'table' and type(saved[k]) == 'table') then
			mergeDefaults(saved[k], v)
		end
	end
end

--- Deep-merge defaults into target, only filling missing keys.
--- Existing values (including explicit false) are never overwritten.
function F.DeepMerge(target, defaults)
	for k, v in next, defaults do
		if(target[k] == nil) then
			target[k] = F.DeepCopy(v)
		elseif(type(v) == 'table' and type(target[k]) == 'table') then
			F.DeepMerge(target[k], v)
		end
	end
end

-- ============================================================
-- Initialize (called on ADDON_LOADED)
-- ============================================================
function Config:Initialize()
	-- Create or restore SavedVariables
	if(not FramedDB) then
		FramedDB = F.DeepCopy(accountDefaults)
	else
		mergeDefaults(FramedDB, accountDefaults)
	end

	if(not FramedCharDB) then
		FramedCharDB = F.DeepCopy(charDefaults)
	else
		mergeDefaults(FramedCharDB, charDefaults)
	end

	applyRuntimeConfig()

	EventBus:Fire('CONFIG_INITIALIZED')
end

--- Ensure current saved data has all defaults and re-apply runtime-derived values.
--- Useful after importing raw tables that bypass Config:Set / SetChar.
function Config:EnsureDefaults()
	if(not FramedDB) then
		FramedDB = F.DeepCopy(accountDefaults)
	else
		mergeDefaults(FramedDB, accountDefaults)
	end

	if(not FramedCharDB) then
		FramedCharDB = F.DeepCopy(charDefaults)
	else
		mergeDefaults(FramedCharDB, charDefaults)
	end

	applyRuntimeConfig()
end

-- ============================================================
-- Typed Accessors
-- ============================================================

--- Get a value from account-wide config.
--- @param path string Dot-separated path (e.g., 'general.accentColor')
--- @return any
function Config:Get(path)
	local current = FramedDB
	for key in path:gmatch('[^%.]+') do
		if(type(current) ~= 'table') then return nil end
		current = current[key]
	end
	return current
end

--- Get a value from per-character config.
--- @param path string Dot-separated path
--- @return any
function Config:GetChar(path)
	local current = FramedCharDB
	for key in path:gmatch('[^%.]+') do
		if(type(current) ~= 'table') then return nil end
		current = current[key]
	end
	return current
end

--- Set a value in account-wide config and fire a change event.
--- @param path string Dot-separated path
--- @param value any The value to set
function Config:Set(path, value)
	local keys = {}
	for key in path:gmatch('[^%.]+') do
		keys[#keys + 1] = key
	end

	local current = FramedDB
	for i = 1, #keys - 1 do
		if(type(current[keys[i]]) ~= 'table') then
			current[keys[i]] = {}
		end
		current = current[keys[i]]
	end

	local lastKey = keys[#keys]
	local oldValue = current[lastKey]
	current[lastKey] = value

	-- Fire change event with the full path and old/new values
	EventBus:Fire('CONFIG_CHANGED', path, value, oldValue)

	-- Fire specific event for the top-level section
	EventBus:Fire('CONFIG_CHANGED:' .. keys[1], path, value, oldValue)
end

--- Set a value in per-character config and fire a change event.
--- @param path string Dot-separated path
--- @param value any The value to set
function Config:SetChar(path, value)
	local keys = {}
	for key in path:gmatch('[^%.]+') do
		keys[#keys + 1] = key
	end

	local current = FramedCharDB
	for i = 1, #keys - 1 do
		if(type(current[keys[i]]) ~= 'table') then
			current[keys[i]] = {}
		end
		current = current[keys[i]]
	end

	local lastKey = keys[#keys]
	local oldValue = current[lastKey]
	current[lastKey] = value

	EventBus:Fire('CHAR_CONFIG_CHANGED', path, value, oldValue)
end

-- ============================================================
-- Debug
-- ============================================================
function Config:PrintDebug()
	print('|cff00ccffFramed Config|r — Account DB keys:')
	for k, v in next, FramedDB do
		local vtype = type(v)
		if(vtype == 'table') then
			local count = 0
			for _ in next, v do count = count + 1 end
			print('  ' .. k .. ': table (' .. count .. ' entries)')
		else
			print('  ' .. k .. ': ' .. tostring(v))
		end
	end
	print('|cff00ccffFramed Config|r — Character DB keys:')
	for k, v in next, FramedCharDB do
		local vtype = type(v)
		if(vtype == 'table') then
			local count = 0
			for _ in next, v do count = count + 1 end
			print('  ' .. k .. ': table (' .. count .. ' entries)')
		else
			print('  ' .. k .. ': ' .. tostring(v))
		end
	end
end
