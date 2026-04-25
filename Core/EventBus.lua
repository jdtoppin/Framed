local _, Framed = ...
local F = Framed

local EventBus = {}
F.EventBus = EventBus

-- Registry: eventName -> { [id] = { callback, owner } }
local registry = {}
local nextId = 1

local function removeByOwner(eventName, owner)
	local listeners = registry[eventName]
	if(not listeners) then return end

	for id, entry in next, listeners do
		if(entry.owner == owner) then
			listeners[id] = nil
		end
	end
end

--- Register a callback for an event.
--- @param eventName string The event to listen for
--- @param callback function The function to call when the event fires
--- @param owner? string Optional owner identifier for debugging/bulk unregister
--- @return number id Registration ID (used for unregistering)
function EventBus:Register(eventName, callback, owner)
	if(not registry[eventName]) then
		registry[eventName] = {}
	end

	-- Treat owner as a stable handle per event. Re-registering the same owner
	-- replaces the old listener instead of accumulating duplicates.
	if(type(owner) == 'string') then
		removeByOwner(eventName, owner)
	end

	local id = nextId
	nextId = nextId + 1

	registry[eventName][id] = {
		callback = callback,
		owner = owner or 'unknown',
	}

	return id
end

--- Unregister a specific callback by ID.
--- Also accepts an owner string to remove all listeners for that owner on the event.
--- @param eventName string The event name
--- @param handle number|string The registration ID returned by Register, or an owner key
function EventBus:Unregister(eventName, handle)
	if(type(handle) == 'string') then
		removeByOwner(eventName, handle)
	elseif(registry[eventName]) then
		registry[eventName][handle] = nil
	end
end

--- Unregister all callbacks owned by a specific owner.
--- @param owner string The owner identifier
function EventBus:UnregisterAll(owner)
	for eventName, listeners in next, registry do
		for id, entry in next, listeners do
			if(entry.owner == owner) then
				listeners[id] = nil
			end
		end
	end
end

--- Fire an event, calling all registered callbacks.
---
--- Each callback runs in its own protected call so a throw in one
--- listener doesn't halt the cascade and silently break every listener
--- registered after it. This is isolation, not suppression — errors
--- still surface through WoW's standard error handler (BugSack /
--- BugGrabber / default error frame), exactly as if the callback ran
--- unprotected. The previous non-isolating implementation caused
--- silent resize + preset-change cascade failures: a single stale
--- reference in any listener would stop all subsequent panels from
--- receiving the event, leaving them "frozen" to future state changes.
---
--- @param eventName string The event to fire
--- @param ... any Arguments passed to callbacks
function EventBus:Fire(eventName, ...)
	local listeners = registry[eventName]
	if(not listeners) then return end

	local errorHandler = geterrorhandler()
	for id, entry in next, listeners do
		local ok, err = pcall(entry.callback, ...)
		if(not ok) then
			errorHandler(('Framed EventBus listener error (event=%s, owner=%s): %s'):format(
				tostring(eventName), tostring(entry.owner), tostring(err)))
		end
	end
end

--- Diagnostic: total count of live listeners across all events.
--- @return number total
--- @return table|nil  Per-event counts: { [eventName] = n }
function EventBus:GetRegistrySize()
	local total = 0
	local perEvent = {}
	for eventName, listeners in next, registry do
		local n = 0
		for _ in next, listeners do n = n + 1 end
		if(n > 0) then
			perEvent[eventName] = n
			total = total + n
		end
	end
	return total, perEvent
end

-- ============================================================
-- WoW event bridge
-- ============================================================
--
-- Forwards a fixed set of WoW game events onto the EventBus so
-- listeners can register via EventBus:Register(<event>, ...) without
-- maintaining their own frame. Only bridged events fire through here —
-- all others remain pure pub/sub.

local BRIDGED_WOW_EVENTS = {
	'GROUP_ROSTER_UPDATE',
	'PLAYER_ROLES_ASSIGNED',
	'PLAYER_REGEN_ENABLED',
	'PLAYER_REGEN_DISABLED',
}

local bridgeFrame = CreateFrame('Frame')
for _, event in next, BRIDGED_WOW_EVENTS do
	bridgeFrame:RegisterEvent(event)
end
bridgeFrame:SetScript('OnEvent', function(_, event, ...)
	EventBus:Fire(event, ...)
end)

--- Debug: print all registered events and listener counts.
function EventBus:PrintDebug()
	print('|cff00ccffFramed EventBus|r — Registered events:')
	local count = 0
	for eventName, listeners in next, registry do
		local n = 0
		for _ in next, listeners do n = n + 1 end
		print('  ' .. eventName .. ': ' .. n .. ' listener(s)')
		count = count + n
	end
	print('  Total: ' .. count .. ' listeners')
end
