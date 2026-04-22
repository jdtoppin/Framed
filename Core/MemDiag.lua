local _, Framed = ...
local F = Framed

-- Diagnostic tool: measure allocation churn in the aura fan-out hot paths.
--
-- Usage: F.MemDiag.Start(seconds)
-- Stops GC for the window so any `collectgarbage('count')` rise is pure
-- allocation (nothing gets freed), wraps each hot funnel to accumulate
-- KB delta + call count, restores originals when the window ends, runs
-- a full collect, and prints a sorted report.
--
-- Not for steady-state use — memory climbs for the duration by design.

F.MemDiag = {
	_active    = false,
	_counters  = nil,
	_originals = nil,
}

local MAX_SECONDS = 30

local function ensureCounter(key)
	local c = F.MemDiag._counters[key]
	if(not c) then
		c = { calls = 0, kb = 0 }
		F.MemDiag._counters[key] = c
	end
	return c
end

--- Build a wrapper that records KB-delta + call count for `fn` under `key`.
local function instrument(key, fn)
	return function(...)
		local before = collectgarbage('count')
		local a, b, c, d, e, f = fn(...)
		local c1 = ensureCounter(key)
		c1.calls = c1.calls + 1
		c1.kb    = c1.kb + (collectgarbage('count') - before)
		return a, b, c, d, e, f
	end
end

local function patchAuraCache()
	local orig = F.AuraCache.GetUnitAuras
	F.MemDiag._originals.GetUnitAuras = orig
	F.AuraCache.GetUnitAuras = instrument('AuraCache.GetUnitAuras', orig)
end

local function patchAuraStateMethods()
	local mt = F.AuraState._mt
	if(not mt) then return end

	local methods = {
		'FullRefresh',
		'ApplyUpdateInfo',
		'GetHelpful',
		'GetHarmful',
		'GetHelpfulClassified',
		'GetHarmfulClassified',
	}

	F.MemDiag._originals.methods = {}
	for _, name in next, methods do
		local orig = mt[name]
		F.MemDiag._originals.methods[name] = orig
		mt[name] = instrument('AuraState:' .. name, orig)
	end
end

--- Hook every oUF unit frame's OnEvent handler so we can attribute the
--- KB delta of each callback to the WoW event name that triggered it.
--- oUF uses a single OnEvent per frame that dispatches internally to all
--- registered element callbacks, so one hook per frame catches every
--- element update cost under that event.
local function patchOUFEvents()
	local oUF = F.oUF
	if(not oUF or not oUF.objects) then return end

	F.MemDiag._originals.frameEvents = {}
	for _, frame in next, oUF.objects do
		local orig = frame:GetScript('OnEvent')
		if(orig) then
			F.MemDiag._originals.frameEvents[frame] = orig
			frame:SetScript('OnEvent', function(self, event, ...)
				local before = collectgarbage('count')
				orig(self, event, ...)
				local c = ensureCounter('event:' .. (event or '?'))
				c.calls = c.calls + 1
				c.kb    = c.kb + (collectgarbage('count') - before)
			end)
		end
	end
end

--- Best-effort frame identifier for OnUpdate attribution.
--- Prefers the explicit name, falls back to parent name + class hint.
local function frameLabel(frame, depth)
	local name = frame:GetName()
	if(name) then return name end
	local parent = frame:GetParent()
	local parentName = parent and parent:GetName() or 'anon'
	return parentName .. ':anon@d' .. depth
end

--- Walk a frame tree up to maxDepth levels and apply fn(frame, depth).
--- Table-packing `{ frame:GetChildren() }` allocates, but this is one-shot
--- setup — fine outside the measurement window proper (we snapshot before
--- patching, so the walk's own allocations are not counted).
local function walkFrames(frame, depth, maxDepth, fn)
	fn(frame, depth)
	if(depth >= maxDepth) then return end
	local kids = { frame:GetChildren() }
	for _, child in next, kids do
		walkFrames(child, depth + 1, maxDepth, fn)
	end
end

--- Hook OnUpdate scripts on all oUF frames and their descendants up to 3
--- levels deep. Castbars, health bars, and similar per-frame animators
--- typically live 1–2 levels below the unit frame.
local function patchOnUpdates()
	local oUF = F.oUF
	if(not oUF or not oUF.objects) then return end

	F.MemDiag._originals.onUpdates = {}
	for _, root in next, oUF.objects do
		walkFrames(root, 0, 3, function(frame, depth)
			local orig = frame:GetScript('OnUpdate')
			if(orig) then
				local label = frameLabel(frame, depth)
				F.MemDiag._originals.onUpdates[frame] = orig
				frame:SetScript('OnUpdate', function(self, elapsed)
					local before = collectgarbage('count')
					orig(self, elapsed)
					local c = ensureCounter('update:' .. label)
					c.calls = c.calls + 1
					c.kb    = c.kb + (collectgarbage('count') - before)
				end)
			end
		end)
	end
end

--- Hook known standalone event/update frames that are not in oUF.objects.
--- Add new entries here as we find them — CastTracker is currently gated
--- off, AuraCache is exposed for diag via F.AuraCache._eventFrame.
local function patchStandaloneFrames()
	F.MemDiag._originals.standalone = {}

	local function hookEvent(frame, label)
		if(not frame) then return end
		local orig = frame:GetScript('OnEvent')
		if(not orig) then return end
		F.MemDiag._originals.standalone[#F.MemDiag._originals.standalone + 1] = {
			frame = frame, script = 'OnEvent', orig = orig,
		}
		frame:SetScript('OnEvent', function(self, event, ...)
			local before = collectgarbage('count')
			orig(self, event, ...)
			local c = ensureCounter('standalone-event:' .. label .. ':' .. (event or '?'))
			c.calls = c.calls + 1
			c.kb    = c.kb + (collectgarbage('count') - before)
		end)
	end

	hookEvent(F.AuraCache and F.AuraCache._eventFrame, 'AuraCache')
end

local function restore()
	F.AuraCache.GetUnitAuras = F.MemDiag._originals.GetUnitAuras

	local mt = F.AuraState._mt
	if(mt and F.MemDiag._originals.methods) then
		for name, orig in next, F.MemDiag._originals.methods do
			mt[name] = orig
		end
	end

	if(F.MemDiag._originals.frameEvents) then
		for frame, orig in next, F.MemDiag._originals.frameEvents do
			frame:SetScript('OnEvent', orig)
		end
	end

	if(F.MemDiag._originals.onUpdates) then
		for frame, orig in next, F.MemDiag._originals.onUpdates do
			frame:SetScript('OnUpdate', orig)
		end
	end

	if(F.MemDiag._originals.standalone) then
		for _, r in next, F.MemDiag._originals.standalone do
			r.frame:SetScript(r.script, r.orig)
		end
	end
end

local function printReport(durationSec, totalStartKB, totalStopKB)
	local totalDelta = totalStopKB - totalStartKB
	print(('|cff00ccff[Framed/memdiag]|r window %.1fs — total allocated %.1f MB (while GC stopped)'):format(
		durationSec, totalDelta / 1024))

	local rows = {}
	for key, c in next, F.MemDiag._counters do
		rows[#rows + 1] = { key = key, calls = c.calls, kb = c.kb }
	end
	table.sort(rows, function(a, b) return a.kb > b.kb end)

	print('|cff00ccff[Framed/memdiag]|r per-hook (sorted by bytes allocated):')
	print('  note: event:* totals nest AuraState:* costs — do not sum both')

	-- Unattributed = totalDelta minus the top-level scopes. event:* wraps
	-- oUF OnEvent dispatch (nests AuraState); update:* wraps per-frame
	-- OnUpdate; standalone-event:* wraps non-oUF event frames. These are
	-- mutually exclusive paths so they sum cleanly. AuraCache.GetUnitAuras
	-- can be called from any path but is negligible post-migration.
	local topLevel = 0
	local byBucket = { event = 0, update = 0, standalone = 0, aura = 0 }
	for key, c in next, F.MemDiag._counters do
		if(key:sub(1, 6) == 'event:') then
			topLevel = topLevel + c.kb
			byBucket.event = byBucket.event + c.kb
		elseif(key:sub(1, 7) == 'update:') then
			topLevel = topLevel + c.kb
			byBucket.update = byBucket.update + c.kb
		elseif(key:sub(1, 17) == 'standalone-event:') then
			topLevel = topLevel + c.kb
			byBucket.standalone = byBucket.standalone + c.kb
		elseif(key == 'AuraCache.GetUnitAuras') then
			topLevel = topLevel + c.kb
			byBucket.aura = byBucket.aura + c.kb
		end
	end

	print(('  --- bucket totals: event=%.1fKB  update=%.1fKB  standalone=%.1fKB  auraCache=%.1fKB ---'):format(
		byBucket.event, byBucket.update, byBucket.standalone, byBucket.aura))

	for _, r in next, rows do
		local perCall = r.calls > 0 and (r.kb * 1024 / r.calls) or 0
		print(('  %-48s  %6d calls  %8.1f KB  (%.0f B/call)'):format(
			r.key, r.calls, r.kb, perCall))
	end

	local unattributed = totalDelta - topLevel
	print(('  %-48s                 %8.1f KB  (%.0f%%)'):format(
		'[unattributed: non-hooked paths]',
		unattributed,
		totalDelta > 0 and (unattributed / totalDelta * 100) or 0))
end

--- Start a measurement window. Stops GC, instruments aura funnels, and
--- prints a sorted report after `seconds` elapse (default 10, max 30).
--- @param seconds? number
function F.MemDiag.Start(seconds)
	if(F.MemDiag._active) then
		print('|cff00ccff[Framed/memdiag]|r already running')
		return
	end

	seconds = math.max(1, math.min(seconds or 10, MAX_SECONDS))

	F.MemDiag._active    = true
	F.MemDiag._counters  = {}
	F.MemDiag._originals = {}

	collectgarbage('collect')
	collectgarbage('stop')

	local startKB = collectgarbage('count')

	patchAuraCache()
	patchAuraStateMethods()
	patchOUFEvents()
	patchOnUpdates()
	patchStandaloneFrames()

	print(('|cff00ccff[Framed/memdiag]|r started — %ds window, GC stopped'):format(seconds))

	C_Timer.After(seconds, function()
		local stopKB = collectgarbage('count')
		restore()
		printReport(seconds, startKB, stopKB)

		collectgarbage('restart')
		collectgarbage('collect')

		F.MemDiag._active    = false
		F.MemDiag._counters  = nil
		F.MemDiag._originals = nil
	end)
end
