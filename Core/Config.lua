local addonName, Framed = ...

local Config = {}
Framed.Config = Config

local Constants = Framed.Constants
local EventBus = Framed.EventBus

-- ============================================================
-- Default Values
-- ============================================================
local accountDefaults = {
    general = {
        accentColor = { 0, 0.8, 1 },  -- cyan default
        uiScale = 1.0,
        wizardCompleted = false,
    },
    layouts = {},       -- populated by Layouts/Defaults.lua in Phase 5
    raidDebuffs = {
        overrides = {},
        custom = {},
    },
    profiles = {},
}

local charDefaults = {
    autoSwitch = {
        [Constants.ContentType.SOLO]         = "Default Solo",
        [Constants.ContentType.PARTY]        = "Default Party",
        [Constants.ContentType.RAID]         = "Default Raid",
        [Constants.ContentType.MYTHIC_RAID]  = "Default Mythic Raid",
        [Constants.ContentType.WORLD_RAID]   = "Default World Raid",
        [Constants.ContentType.BATTLEGROUND]  = "Default Battleground",
        [Constants.ContentType.ARENA]        = "Default Arena",
    },
    specOverrides = {},
    editModePositions = {},
    tourState = {
        completed = false,
        lastStep = 0,
    },
}

-- ============================================================
-- Deep copy utility
-- ============================================================
local function deepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = deepCopy(v)
    end
    return copy
end

-- ============================================================
-- Merge defaults into saved data (non-destructive)
-- Adds missing keys from defaults without overwriting existing values.
-- ============================================================
local function mergeDefaults(saved, defaults)
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = deepCopy(v)
        elseif type(v) == "table" and type(saved[k]) == "table" then
            mergeDefaults(saved[k], v)
        end
    end
end

-- ============================================================
-- Initialize (called on ADDON_LOADED)
-- ============================================================
function Config:Initialize()
    -- Create or restore SavedVariables
    if not FramedDB then
        FramedDB = deepCopy(accountDefaults)
    else
        mergeDefaults(FramedDB, accountDefaults)
    end

    if not FramedCharDB then
        FramedCharDB = deepCopy(charDefaults)
    else
        mergeDefaults(FramedCharDB, charDefaults)
    end

    -- Apply accent color from saved config to Constants
    local accent = FramedDB.general.accentColor
    if accent then
        Constants.Colors.accent      = { accent[1], accent[2], accent[3], 1 }
        Constants.Colors.accentDim   = { accent[1], accent[2], accent[3], 0.3 }
        Constants.Colors.accentHover = { accent[1], accent[2], accent[3], 0.6 }
    end

    EventBus:Fire("CONFIG_INITIALIZED")
end

-- ============================================================
-- Typed Accessors
-- ============================================================

--- Get a value from account-wide config.
--- @param path string Dot-separated path (e.g., "general.accentColor")
--- @return any
function Config:Get(path)
    local current = FramedDB
    for key in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then return nil end
        current = current[key]
    end
    return current
end

--- Get a value from per-character config.
--- @param path string Dot-separated path
--- @return any
function Config:GetChar(path)
    local current = FramedCharDB
    for key in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then return nil end
        current = current[key]
    end
    return current
end

--- Set a value in account-wide config and fire a change event.
--- @param path string Dot-separated path
--- @param value any The value to set
function Config:Set(path, value)
    local keys = {}
    for key in path:gmatch("[^%.]+") do
        keys[#keys + 1] = key
    end

    local current = FramedDB
    for i = 1, #keys - 1 do
        if type(current[keys[i]]) ~= "table" then
            current[keys[i]] = {}
        end
        current = current[keys[i]]
    end

    local lastKey = keys[#keys]
    local oldValue = current[lastKey]
    current[lastKey] = value

    -- Fire change event with the full path and old/new values
    EventBus:Fire("CONFIG_CHANGED", path, value, oldValue)

    -- Fire specific event for the top-level section
    EventBus:Fire("CONFIG_CHANGED:" .. keys[1], path, value, oldValue)
end

--- Set a value in per-character config and fire a change event.
--- @param path string Dot-separated path
--- @param value any The value to set
function Config:SetChar(path, value)
    local keys = {}
    for key in path:gmatch("[^%.]+") do
        keys[#keys + 1] = key
    end

    local current = FramedCharDB
    for i = 1, #keys - 1 do
        if type(current[keys[i]]) ~= "table" then
            current[keys[i]] = {}
        end
        current = current[keys[i]]
    end

    local lastKey = keys[#keys]
    local oldValue = current[lastKey]
    current[lastKey] = value

    EventBus:Fire("CHAR_CONFIG_CHANGED", path, value, oldValue)
end

-- ============================================================
-- Debug
-- ============================================================
function Config:PrintDebug()
    print("|cff00ccffFramed Config|r — Account DB keys:")
    for k, v in pairs(FramedDB) do
        local vtype = type(v)
        if vtype == "table" then
            local count = 0
            for _ in pairs(v) do count = count + 1 end
            print("  " .. k .. ": table (" .. count .. " entries)")
        else
            print("  " .. k .. ": " .. tostring(v))
        end
    end
    print("|cff00ccffFramed Config|r — Character DB keys:")
    for k, v in pairs(FramedCharDB) do
        local vtype = type(v)
        if vtype == "table" then
            local count = 0
            for _ in pairs(v) do count = count + 1 end
            print("  " .. k .. ": table (" .. count .. " entries)")
        else
            print("  " .. k .. ": " .. tostring(v))
        end
    end
end
