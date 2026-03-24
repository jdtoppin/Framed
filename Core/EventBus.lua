local addonName, Framed = ...

local EventBus = {}
Framed.EventBus = EventBus

-- Registry: eventName -> { [id] = { callback, owner } }
local registry = {}
local nextId = 1

--- Register a callback for an event.
--- @param eventName string The event to listen for
--- @param callback function The function to call when the event fires
--- @param owner? string Optional owner identifier for debugging/bulk unregister
--- @return number id Registration ID (used for unregistering)
function EventBus:Register(eventName, callback, owner)
    if not registry[eventName] then
        registry[eventName] = {}
    end

    local id = nextId
    nextId = nextId + 1

    registry[eventName][id] = {
        callback = callback,
        owner = owner or "unknown",
    }

    return id
end

--- Unregister a specific callback by ID.
--- @param eventName string The event name
--- @param id number The registration ID returned by Register
function EventBus:Unregister(eventName, id)
    if registry[eventName] then
        registry[eventName][id] = nil
    end
end

--- Unregister all callbacks owned by a specific owner.
--- @param owner string The owner identifier
function EventBus:UnregisterAll(owner)
    for eventName, listeners in pairs(registry) do
        for id, entry in pairs(listeners) do
            if entry.owner == owner then
                listeners[id] = nil
            end
        end
    end
end

--- Fire an event, calling all registered callbacks.
--- @param eventName string The event to fire
--- @param ... any Arguments passed to callbacks
function EventBus:Fire(eventName, ...)
    local listeners = registry[eventName]
    if not listeners then return end

    for id, entry in pairs(listeners) do
        entry.callback(...)
    end
end

--- Debug: print all registered events and listener counts.
function EventBus:PrintDebug()
    print("|cff00ccffFramed EventBus|r — Registered events:")
    local count = 0
    for eventName, listeners in pairs(registry) do
        local n = 0
        for _ in pairs(listeners) do n = n + 1 end
        print("  " .. eventName .. ": " .. n .. " listener(s)")
        count = count + n
    end
    print("  Total: " .. count .. " listeners")
end
