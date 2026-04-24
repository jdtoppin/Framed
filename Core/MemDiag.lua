local _, Framed = ...
local F = Framed

-- Diagnostic tool: measure allocation churn AND CPU cost in the aura
-- fan-out hot paths.
--
-- Usage: F.MemDiag.Start(seconds)
-- Stops GC for the window so any `collectgarbage('count')` rise is pure
-- allocation (nothing gets freed), wraps each hot funnel to accumulate
-- KB delta + ms delta + call count, restores originals when the window
-- ends, runs a full collect, and prints a sorted report.
--
-- ms timing via debugprofilestop() requires /console scriptProfile 1 +
-- /reload. Without it, the ms column reads 0.
--
-- Not for steady-state use — memory climbs for the duration by design.

F.MemDiag = {
	_active    = false,
	_counters  = nil,
	_originals = nil,
}

local MAX_SECONDS = 30

-- Cache hot builtins as upvalues — instrumentation wrappers call these
-- on every hot-path invocation, so avoiding the global table lookup
-- matters for the overhead we're adding to the very code we're measuring.
local gc_count     = collectgarbage
local profile_stop = debugprofilestop

local function ensureCounter(key)
	local c = F.MemDiag._counters[key]
	if(not c) then
		c = { calls = 0, kb = 0, ms = 0 }
		F.MemDiag._counters[key] = c
	end
	return c
end

--- Build a wrapper that records KB-delta + ms-delta + call count for `fn` under `key`.
local function instrument(key, fn)
	return function(...)
		local beforeKB = gc_count('count')
		local beforeMS = profile_stop()
		local a, b, c, d, e, f = fn(...)
		local c1 = ensureCounter(key)
		c1.calls = c1.calls + 1
		c1.kb    = c1.kb + (gc_count('count') - beforeKB)
		c1.ms    = c1.ms + (profile_stop() - beforeMS)
		return a, b, c, d, e, f
	end
end

--- In-situ probe API for element modules that want per-expression
--- attribution inside their own hot-path functions. Enter() returns two
--- tokens (or nils when MemDiag is inactive); Leave() uses those tokens
--- to record the bytes- and ms-allocated deltas against `key`. Both are
--- no-ops when the window is closed, so probes compiled into element
--- code impose only a per-call branch + function-call cost in normal
--- operation.
function F.MemDiag.Enter()
	if(not F.MemDiag._active) then return nil, nil end
	return gc_count('count'), profile_stop()
end

function F.MemDiag.Leave(key, beforeKB, beforeMS)
	if(not beforeKB) then return end
	if(not F.MemDiag._active) then return end
	local c = ensureCounter(key)
	c.calls = c.calls + 1
	c.kb    = c.kb + (gc_count('count') - beforeKB)
	if(beforeMS) then
		c.ms = c.ms + (profile_stop() - beforeMS)
	end
end

-- Element containers that expose an indicator list on an oUF frame.
-- Walked by patchIndicatorMethods so renderer SetIcons/SetSpell calls
-- get attributed per-frame. PrivateAuras is included speculatively —
-- the walk no-ops on frames that don't carry the element.
local ELEMENT_NAMES = {
	'FramedBuffs',
	'FramedDebuffs',
	'FramedExternals',
	'FramedDefensives',
	'FramedMissingBuffs',
	'FramedPrivateAuras',
}

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
				local beforeKB = gc_count('count')
				local beforeMS = profile_stop()
				orig(self, event, ...)
				local c = ensureCounter('event:' .. (event or '?'))
				c.calls = c.calls + 1
				c.kb    = c.kb + (gc_count('count') - beforeKB)
				c.ms    = c.ms + (profile_stop() - beforeMS)
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

	-- GetDebugName surfaces Blizzard's internal hierarchical name (e.g.
	-- 'FramedPartyHeaderUnitButton1.HealPredictionBar') even for anonymous
	-- frames. Not available on all versions, so guard with a check.
	if(frame.GetDebugName) then
		local debugName = frame:GetDebugName()
		if(debugName and debugName ~= '') then return debugName end
	end

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
		local beforeKB = gc_count('count')
		local beforeMS = profile_stop()
		orig(self, elapsed)
		local c = ensureCounter('update:' .. label)
		c.calls = c.calls + 1
		c.kb    = c.kb + (gc_count('count') - beforeKB)
		c.ms    = c.ms + (profile_stop() - beforeMS)
	end)
	return true
end

--- One-time catalog walk: descend oUF.objects once, record every reachable
--- frame + its label into _trackedFrames, and hook any OnUpdate scripts
--- present at that moment.
---
--- Labels are computed (and GetDebugName called) exactly once per frame
--- here and cached for the rest of the window — subsequent rewalks reuse
--- the cached label without re-walking the parent chain.
local function walkAndCatalogFrames()
	local oUF = F.oUF
	if(not oUF or not oUF.objects) then return end

	local tracked = F.MemDiag._originals.trackedFrames
	for _, root in next, oUF.objects do
		walkFrames(root, 0, 1, function(frame, depth)
			if(tracked[frame]) then return end
			-- Label + hook only frames that actually have an OnUpdate.
			-- GetDebugName() is expensive in large frame trees; skipping it
			-- for the ~95% of frames with no OnUpdate keeps the catalog walk
			-- under the 10s script watchdog in 40-man raid.
			if(not frame:GetScript('OnUpdate')) then return end
			local label = frameLabel(frame, depth)
			tracked[frame] = label
			hookFrameOnUpdate(frame, label)
		end)
	end
end

--- Cheap rewalk: iterate the cached frame set and hook any OnUpdate that
--- appeared since last pass. No tree traversal, no table packing, no
--- label recomputation. Pure GetScript probe per tracked frame.
---
--- Limitation: frames created after Start are not in the cache and won't
--- be caught. Acceptable — Framed spawns frames at addon load, not in
--- combat, so new-frame emergence inside a 30s window is vanishingly rare.
local function rewalkCachedFrames()
	local tracked = F.MemDiag._originals.trackedFrames
	local hooked  = F.MemDiag._originals.onUpdates
	for frame, label in next, tracked do
		if(not hooked[frame]) then
			hookFrameOnUpdate(frame, label)
		end
	end
end

--- Initial OnUpdate hook pass. Populates the tracked-frame cache used by
--- subsequent rewalks.
local function patchOnUpdates()
	F.MemDiag._originals.onUpdates     = {}
	F.MemDiag._originals.trackedFrames = {}
	walkAndCatalogFrames()
end

--- Hook known standalone event/update frames that are not in oUF.objects.
--- Add new entries here as we find them — AuraCache is exposed for diag
--- via F.AuraCache._eventFrame.
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
			local beforeKB = gc_count('count')
			local beforeMS = profile_stop()
			orig(self, event, ...)
			local c = ensureCounter('standalone-event:' .. label .. ':' .. (event or '?'))
			c.calls = c.calls + 1
			c.kb    = c.kb + (gc_count('count') - beforeKB)
			c.ms    = c.ms + (profile_stop() - beforeMS)
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
			local beforeKB = gc_count('count')
			local beforeMS = profile_stop()
			orig(self, elapsed)
			local c = ensureCounter('standalone-update:' .. label)
			c.calls = c.calls + 1
			c.kb    = c.kb + (gc_count('count') - beforeKB)
			c.ms    = c.ms + (profile_stop() - beforeMS)
		end)
	end

	hookEvent(F.AuraCache and F.AuraCache._eventFrame, 'AuraCache')
	hookUpdate(F.Indicators and F.Indicators.IconTicker_Frame, 'IconTicker')
	hookUpdate(F.Status and F.Status.CrowdControl_Ticker, 'CrowdControl')
	hookUpdate(F.Status and F.Status.LossOfControl_Ticker, 'LossOfControl')
end

--- Wrap SetIcons on ICONS-type renderers and SetSpell on ICON-type
--- renderers across every oUF frame's aura-element indicator list.
--- Methods are copied per-instance by the factory (see Elements/Indicators/*.lua
--- tail `for k, v in next, Methods do icon[k] = v end`), so we patch each
--- instance individually and save originals keyed by renderer reference.
--- Scope-limited to SetIcons + SetSpell for this measurement pass — expand
--- if residual cost in other renderer methods warrants it.
local function patchIndicatorMethods()
	local oUF = F.oUF
	if(not oUF or not oUF.objects) then return end
	local C = F.Constants
	if(not C or not C.IndicatorType) then return end

	F.MemDiag._originals.indicatorMethods = {}

	local function wrapMethod(renderer, name, label)
		local orig = renderer[name]
		if(not orig) then return end
		local saved = F.MemDiag._originals.indicatorMethods[renderer]
		if(not saved) then
			saved = {}
			F.MemDiag._originals.indicatorMethods[renderer] = saved
		end
		saved[name] = orig
		renderer[name] = instrument(label, orig)
	end

	for _, obj in next, oUF.objects do
		for _, elementName in next, ELEMENT_NAMES do
			local element = obj[elementName]
			if(element and element._indicators) then
				for _, ind in next, element._indicators do
					local renderer = ind._renderer
					if(renderer) then
						if(ind._type == C.IndicatorType.ICONS) then
							wrapMethod(renderer, 'SetIcons', 'indicator:Icons:SetIcons')
						elseif(ind._type == C.IndicatorType.ICON) then
							wrapMethod(renderer, 'SetSpell', 'indicator:Icon:SetSpell')
						end
					end
				end
			end
		end
	end
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

	if(F.MemDiag._originals.indicatorMethods) then
		for renderer, methods in next, F.MemDiag._originals.indicatorMethods do
			for name, orig in next, methods do
				renderer[name] = orig
			end
		end
	end
end

local function printReport(durationSec, totalStartKB, totalStopKB)
	local totalDelta = totalStopKB - totalStartKB
	print(('|cff00ccff[Framed/memdiag]|r window %.1fs — Framed allocated %.1f MB (GetAddOnMemoryUsage delta, GC stopped)'):format(
		durationSec, totalDelta / 1024))

	local rows = {}
	for key, c in next, F.MemDiag._counters do
		rows[#rows + 1] = { key = key, calls = c.calls, kb = c.kb, ms = c.ms or 0 }
	end
	table.sort(rows, function(a, b) return a.ms > b.ms end)

	print('|cff00ccff[Framed/memdiag]|r per-hook (sorted by ms spent):')
	print('  note: event:* totals nest AuraState:* costs — do not sum both')
	print('  note: ms column is 0 unless /console scriptProfile 1 + /reload')

	-- Unattributed KB = totalDelta minus the top-level scopes. event:* wraps
	-- oUF OnEvent dispatch (nests AuraState); update:* wraps per-frame
	-- OnUpdate; standalone-event:* wraps non-oUF event frames;
	-- standalone-update:* wraps non-oUF ticker frames (IconTicker etc.).
	-- These are mutually exclusive paths so they sum cleanly.
	-- AuraCache.GetUnitAuras can be called from any path but is negligible
	-- post-migration.
	-- indicator:* and element:* are in-situ probes nested inside event:*;
	-- they attribute sub-paths within element Update handlers, so they are
	-- tracked for informational totals but NOT added to topLevel.
	local topLevelKB = 0
	local topLevelMS = 0
	local bKB = { event = 0, update = 0, standalone = 0, tickers = 0, aura = 0, memdiag = 0, indicator = 0, element = 0 }
	local bMS = { event = 0, update = 0, standalone = 0, tickers = 0, aura = 0, memdiag = 0, indicator = 0, element = 0 }
	for key, c in next, F.MemDiag._counters do
		local ms = c.ms or 0
		if(key:sub(1, 6) == 'event:') then
			topLevelKB = topLevelKB + c.kb; topLevelMS = topLevelMS + ms
			bKB.event = bKB.event + c.kb;    bMS.event = bMS.event + ms
		elseif(key:sub(1, 7) == 'update:') then
			topLevelKB = topLevelKB + c.kb; topLevelMS = topLevelMS + ms
			bKB.update = bKB.update + c.kb;  bMS.update = bMS.update + ms
		elseif(key:sub(1, 17) == 'standalone-event:') then
			topLevelKB = topLevelKB + c.kb; topLevelMS = topLevelMS + ms
			bKB.standalone = bKB.standalone + c.kb; bMS.standalone = bMS.standalone + ms
		elseif(key:sub(1, 18) == 'standalone-update:') then
			topLevelKB = topLevelKB + c.kb; topLevelMS = topLevelMS + ms
			bKB.tickers = bKB.tickers + c.kb; bMS.tickers = bMS.tickers + ms
		elseif(key == 'AuraCache.GetUnitAuras') then
			topLevelKB = topLevelKB + c.kb; topLevelMS = topLevelMS + ms
			bKB.aura = bKB.aura + c.kb;      bMS.aura = bMS.aura + ms
		elseif(key:sub(1, 8) == 'memdiag:') then
			topLevelKB = topLevelKB + c.kb; topLevelMS = topLevelMS + ms
			bKB.memdiag = bKB.memdiag + c.kb; bMS.memdiag = bMS.memdiag + ms
		elseif(key:sub(1, 10) == 'indicator:') then
			bKB.indicator = bKB.indicator + c.kb; bMS.indicator = bMS.indicator + ms
		elseif(key:sub(1, 8) == 'element:') then
			bKB.element = bKB.element + c.kb; bMS.element = bMS.element + ms
		end
	end

	print(('  --- KB by bucket: event=%.1f  update=%.1f  standalone=%.1f  tickers=%.1f  auraCache=%.1f  memdiag=%.1f ---'):format(
		bKB.event, bKB.update, bKB.standalone, bKB.tickers, bKB.aura, bKB.memdiag))
	print(('  --- ms by bucket: event=%.1f  update=%.1f  standalone=%.1f  tickers=%.1f  auraCache=%.1f  memdiag=%.1f ---'):format(
		bMS.event, bMS.update, bMS.standalone, bMS.tickers, bMS.aura, bMS.memdiag))
	print(('  --- nested under event:* — indicator KB=%.1f/ms=%.1f  element KB=%.1f/ms=%.1f ---'):format(
		bKB.indicator, bMS.indicator, bKB.element, bMS.element))

	-- Per-call μs is (ms*1000)/calls — kept in μs to avoid the "0.00 ms/call"
	-- degenerate case that hides real cost on high-frequency hot paths.
	for _, r in next, rows do
		local bPerCall  = r.calls > 0 and (r.kb * 1024 / r.calls) or 0
		local usPerCall = r.calls > 0 and (r.ms * 1000    / r.calls) or 0
		print(('  %-48s  %6d calls  %8.1f ms  %8.1f KB  (%.0f μs/call, %.0f B/call)'):format(
			r.key, r.calls, r.ms, r.kb, usPerCall, bPerCall))
	end

	local unattributedKB = totalDelta - topLevelKB
	print(('  %-48s                 %8.1f KB  (%.0f%%)'):format(
		'[unattributed KB: non-hooked paths]',
		unattributedKB,
		totalDelta > 0 and (unattributedKB / totalDelta * 100) or 0))
	print(('  %-48s                 %8.1f ms  (top-level sum; compare to AddonProfiler Framed Total)'):format(
		'[top-level ms total]',
		topLevelMS))
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
	patchIndicatorMethods()

	-- Periodic re-walk: catches OnUpdate scripts attached mid-window
	-- (Bar depleting, Color/Overlay/BorderGlow animations, glow effects)
	-- that were not present at the initial patchOnUpdates sweep.
	--
	-- rewalkCachedFrames iterates only the frame set collected during the
	-- initial catalog walk — no tree traversal, no table packing, no
	-- GetDebugName recomputation. Per-tick cost is ~one GetScript probe
	-- per tracked frame. Still attributed to `memdiag:rewalk` so the
	-- report reflects remaining self-cost.
	--
	-- Limitation: frames created after Start are not in the cache and
	-- won't be caught. Acceptable — Framed spawns frames at addon load,
	-- not in combat, so new-frame emergence inside a 30s window is rare.
	local function scheduleRewalk()
		C_Timer.After(2, function()
			if(not F.MemDiag._active) then return end
			local beforeKB = gc_count('count')
			local beforeMS = profile_stop()
			rewalkCachedFrames()
			local c = ensureCounter('memdiag:rewalk')
			c.calls = c.calls + 1
			c.kb    = c.kb + (gc_count('count') - beforeKB)
			c.ms    = c.ms + (profile_stop() - beforeMS)
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

-- ============================================================
-- Settings memory probe — measures open/close deltas.
-- Wraps F.Settings.Show and F.Settings.Hide with a toggleable
-- logger. When enabled, prints a baseline on open and a delta
-- on close (both at-hide and post-GC) so we can distinguish
-- "settings held memory but it's now collectable" from "settings
-- retained references that survive GC".
-- ============================================================

local settingsProbeWrapped = false
local settingsProbeOn      = false
local preShowFramedKB      = nil
local preShowTotalKB       = nil
local preShowDescCount     = nil
-- Cross-cycle tracking: post-GC values from the previous close, so each
-- new baseline can report drift relative to last cycle's steady state.
-- That reveals per-cycle retention that accumulates over a session.
local lastPostGCFramedKB   = nil
local lastPostGCTotalKB    = nil
local lastPostGCDescCount  = nil

--- Recursively count a frame and all its descendants (children + regions).
local function countDescendants(f)
	if(not f) then return 0 end
	local n = 1
	-- Child frames (sub-frames with their own frame level)
	local children = { f:GetChildren() }
	for i = 1, #children do
		n = n + countDescendants(children[i])
	end
	-- Regions (textures, fontstrings) — not frames themselves but still
	-- allocations that get retained if the parent is retained.
	if(f.GetRegions) then
		local regions = { f:GetRegions() }
		n = n + #regions
	end
	return n
end

-- Count UIParent's direct children. Orphan frames created during panel
-- builds that don't live inside _mainFrame would show up here.
local function countUIParentChildren()
	if(not UIParent or not UIParent.GetChildren) then return 0 end
	local kids = { UIParent:GetChildren() }
	return #kids
end

local preShowUIParentKids = nil

local function captureBaseline()
	collectgarbage('collect')
	UpdateAddOnMemoryUsage()
	preShowFramedKB  = GetAddOnMemoryUsage('Framed')
	preShowTotalKB   = collectgarbage('count')
	-- Descendant count at baseline (may be 0 if _mainFrame doesn't exist yet).
	local main = F.Settings and F.Settings._mainFrame
	preShowDescCount = main and countDescendants(main) or 0
	preShowUIParentKids = countUIParentChildren()
	print(('|cff00ccff[Framed/mem/settings]|r baseline — Framed %.2f MB | total %.2f MB | _mainFrame descendants: %d | UIParent kids: %d'):format(
		preShowFramedKB / 1024, preShowTotalKB / 1024, preShowDescCount, preShowUIParentKids))
	-- Drift since last cycle's post-GC state. Non-zero here means the
	-- previous teardown left references alive that accumulated across cycles.
	if(lastPostGCFramedKB) then
		print(('  drift since last close (post-GC → post-GC): Framed %+.2f MB | total %+.2f MB | descendants %+d'):format(
			(preShowFramedKB - lastPostGCFramedKB) / 1024,
			(preShowTotalKB  - lastPostGCTotalKB)  / 1024,
			preShowDescCount - lastPostGCDescCount))
	end
end

local function reportCloseDelta()
	if(not preShowFramedKB) then return end
	UpdateAddOnMemoryUsage()
	local atHideFramedKB = GetAddOnMemoryUsage('Framed')
	local atHideTotalKB  = collectgarbage('count')

	collectgarbage('collect')
	UpdateAddOnMemoryUsage()
	local postGCFramedKB = GetAddOnMemoryUsage('Framed')
	local postGCTotalKB  = collectgarbage('count')

	-- Stash for next cycle's drift comparison in captureBaseline.
	lastPostGCFramedKB = postGCFramedKB
	lastPostGCTotalKB  = postGCTotalKB

	local main = F.Settings and F.Settings._mainFrame
	local postDescCount = main and countDescendants(main) or 0
	lastPostGCDescCount = postDescCount

	print(('|cff00ccff[Framed/mem/settings]|r close delta vs baseline:'):format())
	print(('  at-hide:  Framed %+.2f MB  |  total %+.2f MB'):format(
		(atHideFramedKB - preShowFramedKB) / 1024,
		(atHideTotalKB  - preShowTotalKB)  / 1024))
	print(('  post-GC:  Framed %+.2f MB  |  total %+.2f MB'):format(
		(postGCFramedKB - preShowFramedKB) / 1024,
		(postGCTotalKB  - preShowTotalKB)  / 1024))
	print(('  frames:   _mainFrame descendants %+d (%d → %d)'):format(
		postDescCount - preShowDescCount, preShowDescCount, postDescCount))
	local postUIKids = countUIParentChildren()
	print(('  UIParent: direct children %+d (%d → %d) — any growth here is orphan frames leaked outside _mainFrame'):format(
		postUIKids - (preShowUIParentKids or 0), preShowUIParentKids or 0, postUIKids))
	print('  (at-hide = retention before GC; post-GC = genuinely held references)')

	-- Bucket retained descendants by ObjectType and by top-level section
	-- (direct child of _mainFrame) so we see where they're concentrated.
	if(main) then
		local byType = {}
		local bySection = {}
		local function walk(f, sectionLabel)
			-- Count this frame by type
			local t = f.GetObjectType and f:GetObjectType() or '?'
			byType[t] = (byType[t] or 0) + 1
			bySection[sectionLabel] = (bySection[sectionLabel] or 0) + 1
			-- Recurse children
			if(f.GetChildren) then
				local children = { f:GetChildren() }
				for i = 1, #children do walk(children[i], sectionLabel) end
			end
			-- Count regions (textures, fontstrings) but don't recurse
			if(f.GetRegions) then
				local regions = { f:GetRegions() }
				for i = 1, #regions do
					local rt = regions[i].GetObjectType and regions[i]:GetObjectType() or '?'
					byType[rt] = (byType[rt] or 0) + 1
					bySection[sectionLabel] = (bySection[sectionLabel] or 0) + 1
				end
			end
		end
		-- Walk each top-level section separately so we can attribute by section
		local topChildren = { main:GetChildren() }
		for i = 1, #topChildren do
			local child = topChildren[i]
			local label = (child.GetName and child:GetName()) or (child.GetDebugName and child:GetDebugName()) or ('anon#' .. i)
			walk(child, label)
		end

		-- Print top buckets
		local function printTop(label, tbl, n)
			local rows = {}
			for k, v in next, tbl do rows[#rows + 1] = { k = k, v = v } end
			table.sort(rows, function(a, b) return a.v > b.v end)
			print(('  by %s:'):format(label))
			for i = 1, math.min(n or 10, #rows) do
				print(('    %6d × %s'):format(rows[i].v, rows[i].k))
			end
		end
		printTop('ObjectType', byType, 8)
		printTop('top-level section (direct child of _mainFrame)', bySection, 10)

		-- Drill into _contentParent specifically — if it's the leak site, list
		-- its direct children so we see which panels are cached.
		-- Cross-reference Settings._panelFrames (keyed by panelId) to label
		-- each retained panel by its id ('player', 'raid', 'debuffs', etc.)
		-- instead of an anonymous frame address.
		local cp = F.Settings and F.Settings._contentParent
		local panelFrames = F.Settings and F.Settings._panelFrames or {}
		local frameToId = {}
		for id, frame in next, panelFrames do frameToId[frame] = id end
		if(cp) then
			local cpKids = { cp:GetChildren() }
			if(#cpKids > 0) then
				local rows = {}
				for i = 1, #cpKids do
					local child = cpKids[i]
					local label = frameToId[child]
						or (child.GetName and child:GetName())
						or (child.GetDebugName and child:GetDebugName())
						or ('anon#' .. i)
					-- Count descendants of this specific panel
					local c = 0
					local function deepCount(f)
						c = c + 1
						if(f.GetChildren) then
							local k = { f:GetChildren() }
							for j = 1, #k do deepCount(k[j]) end
						end
						if(f.GetRegions) then
							local r = { f:GetRegions() }
							c = c + #r
						end
					end
					deepCount(child)
					rows[#rows + 1] = { label = label, count = c }
				end
				table.sort(rows, function(a, b) return a.count > b.count end)
				print(('  _contentParent direct children (%d total):'):format(#cpKids))
				for i = 1, math.min(15, #rows) do
					print(('    %6d × %s'):format(rows[i].count, rows[i].label))
				end
			end
		end
	end
end

local function settingsProbeInstall()
	if(settingsProbeWrapped) then return true end
	local S = F.Settings
	if(not S or not S.Show or not S.Hide or not S.Toggle) then return false end

	local origShow   = S.Show
	local origHide   = S.Hide
	local origToggle = S.Toggle

	S.Show = function(...)
		if(settingsProbeOn) then captureBaseline() end
		return origShow(...)
	end

	S.Hide = function(...)
		local r = origHide(...)
		if(settingsProbeOn) then reportCloseDelta() end
		return r
	end

	-- Toggle bypasses Show/Hide and calls Widgets.FadeIn/FadeOut directly,
	-- so we need to hook it separately. Capture wasShown BEFORE Toggle runs
	-- so we know which transition the invocation triggered.
	S.Toggle = function(...)
		if(not settingsProbeOn) then return origToggle(...) end
		local wasShown = S._mainFrame and S._mainFrame:IsShown()
		if(not wasShown) then captureBaseline() end
		local r = origToggle(...)
		if(wasShown) then reportCloseDelta() end
		return r
	end

	settingsProbeWrapped = true
	return true
end

--- Toggle the Settings memory probe on/off.
--- On: wraps Show/Hide once (idempotent) and prints deltas on next cycle.
--- Off: leaves wrappers installed but silenced — no lingering overhead.
function F.MemDiag.ToggleSettingsProbe()
	if(not settingsProbeInstall()) then
		print('|cff00ccff[Framed/mem/settings]|r F.Settings not available yet')
		return
	end
	settingsProbeOn = not settingsProbeOn
	print(('|cff00ccff[Framed/mem/settings]|r probe %s — open the settings window to capture a cycle.'):format(
		settingsProbeOn and 'ENABLED' or 'DISABLED'))
end
