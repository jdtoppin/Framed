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
--- If the frame is anonymous, walks up ancestors until a named frame is
--- found so labels like `NamedParent>...@d3` stay attributable even when
--- several nesting layers are anonymous. Caps the walk to avoid pathological
--- infinite ancestry chains.
local function frameLabel(frame, depth)
	local name = frame:GetName()
	if(name) then return name end
	local p = frame
	local hops = 0
	while(hops < 8) do
		p = p:GetParent()
		if(not p) then break end
		local pname = p:GetName()
		if(pname) then
			return pname .. '>anon@d' .. depth .. (hops > 0 and ('/+' .. hops) or '')
		end
		hops = hops + 1
	end
	return 'anon@d' .. depth
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

--- Hook a single frame's current OnUpdate script. Idempotent — skips
--- frames we've already wrapped (tracked via `_originals.onUpdates`).
--- Returns true if a new hook was installed.
local function hookFrameOnUpdate(frame, label)
	if(F.MemDiag._originals.onUpdates[frame]) then return false end
	local orig = frame:GetScript('OnUpdate')
	if(not orig) then return false end
	F.MemDiag._originals.onUpdates[frame] = orig
	frame:SetScript('OnUpdate', function(self, elapsed)
		local before = collectgarbage('count')
		orig(self, elapsed)
		local c = ensureCounter('update:' .. label)
		c.calls = c.calls + 1
		c.kb    = c.kb + (collectgarbage('count') - before)
	end)
	return true
end

--- Walk all oUF frames + descendants and hook their OnUpdate scripts.
--- Safe to call repeatedly — `hookFrameOnUpdate` skips already-wrapped
--- frames. Used both at Start and periodically during the window to
--- catch dynamically-attached OnUpdates (Bar depleting, Color/Overlay
--- animations) that escape the initial walk.
local function walkAndHookOnUpdates()
	local oUF = F.oUF
	if(not oUF or not oUF.objects) then return end

	for _, root in next, oUF.objects do
		walkFrames(root, 0, 5, function(frame, depth)
			hookFrameOnUpdate(frame, frameLabel(frame, depth))
		end)
	end
end

--- Initial OnUpdate hook pass. See walkAndHookOnUpdates for ongoing
--- coverage of dynamically-attached scripts.
local function patchOnUpdates()
	F.MemDiag._originals.onUpdates = {}
	walkAndHookOnUpdates()
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

	local function hookUpdate(frame, label)
		if(not frame) then return end
		local orig = frame:GetScript('OnUpdate')
		if(not orig) then return end
		F.MemDiag._originals.standalone[#F.MemDiag._originals.standalone + 1] = {
			frame = frame, script = 'OnUpdate', orig = orig,
		}
		frame:SetScript('OnUpdate', function(self, elapsed)
			local before = collectgarbage('count')
			orig(self, elapsed)
			local c = ensureCounter('standalone-update:' .. label)
			c.calls = c.calls + 1
			c.kb    = c.kb + (collectgarbage('count') - before)
		end)
	end

	hookEvent(F.AuraCache and F.AuraCache._eventFrame, 'AuraCache')
	hookUpdate(F.Indicators and F.Indicators.IconTicker_Frame, 'IconTicker')
	hookUpdate(F.Status and F.Status.CrowdControl_Ticker, 'CrowdControl')
	hookUpdate(F.Status and F.Status.LossOfControl_Ticker, 'LossOfControl')
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
	print(('|cff00ccff[Framed/memdiag]|r window %.1fs — Framed allocated %.1f MB (GetAddOnMemoryUsage delta, GC stopped)'):format(
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
	-- OnUpdate; standalone-event:* wraps non-oUF event frames;
	-- standalone-update:* wraps non-oUF ticker frames (IconTicker etc.).
	-- These are mutually exclusive paths so they sum cleanly.
	-- AuraCache.GetUnitAuras can be called from any path but is negligible
	-- post-migration.
	local topLevel = 0
	local byBucket = { event = 0, update = 0, standalone = 0, tickers = 0, aura = 0, memdiag = 0 }
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
		elseif(key:sub(1, 18) == 'standalone-update:') then
			topLevel = topLevel + c.kb
			byBucket.tickers = byBucket.tickers + c.kb
		elseif(key == 'AuraCache.GetUnitAuras') then
			topLevel = topLevel + c.kb
			byBucket.aura = byBucket.aura + c.kb
		elseif(key:sub(1, 8) == 'memdiag:') then
			topLevel = topLevel + c.kb
			byBucket.memdiag = byBucket.memdiag + c.kb
		end
	end

	print(('  --- bucket totals: event=%.1fKB  update=%.1fKB  standalone=%.1fKB  tickers=%.1fKB  auraCache=%.1fKB  memdiag=%.1fKB ---'):format(
		byBucket.event, byBucket.update, byBucket.standalone, byBucket.tickers, byBucket.aura, byBucket.memdiag))

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

--- Read Framed-specific heap usage in KB. Blizzard attributes Lua
--- allocations to whichever addon's code was on the call stack at
--- alloc time, so this is the per-addon measurement ElvUI and similar
--- tools display. UpdateAddOnMemoryUsage refreshes the snapshot.
local function framedUsageKB()
	UpdateAddOnMemoryUsage()
	return GetAddOnMemoryUsage('Framed')
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

	local startKB = framedUsageKB()

	patchAuraCache()
	patchAuraStateMethods()
	patchOUFEvents()
	patchOnUpdates()
	patchStandaloneFrames()

	-- Periodic re-walk: catches OnUpdate scripts attached mid-window
	-- (Bar depleting, Color/Overlay/BorderGlow animations) that were not
	-- present at the initial patchOnUpdates sweep. walkAndHookOnUpdates is
	-- idempotent — already-hooked frames are skipped. Limitation: if a
	-- hooked frame's script is later replaced with a new fn, we keep
	-- tracking the old one (rare; noted for follow-up if needed).
	--
	-- The walk itself allocates (table-packed GetChildren results), so we
	-- attribute that cost to a `memdiag:rewalk` counter — keeping it out of
	-- the [unattributed] bucket so the report still reflects real leaks.
	local function scheduleRewalk()
		C_Timer.After(2, function()
			if(not F.MemDiag._active) then return end
			local before = collectgarbage('count')
			walkAndHookOnUpdates()
			local c = ensureCounter('memdiag:rewalk')
			c.calls = c.calls + 1
			c.kb    = c.kb + (collectgarbage('count') - before)
			scheduleRewalk()
		end)
	end
	scheduleRewalk()

	print(('|cff00ccff[Framed/memdiag]|r started — %ds window, GC stopped'):format(seconds))

	C_Timer.After(seconds, function()
		local stopKB = framedUsageKB()
		restore()
		printReport(seconds, startKB, stopKB)

		collectgarbage('restart')
		collectgarbage('collect')

		F.MemDiag._active    = false
		F.MemDiag._counters  = nil
		F.MemDiag._originals = nil
	end)
end
