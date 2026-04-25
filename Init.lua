local addonName, Framed = ...
local F = Framed

-- Version
F.version = C_AddOns.GetAddOnMetadata(addonName, 'Version') or 'unknown'

-- oUF stores itself as ns.oUF in its init.lua (where ns is the second vararg
-- from ..., which is our Framed namespace table). So Framed.oUF is already
-- populated after Libs/oUF/oUF.xml loads — no global oUF variable is needed.
assert(Framed.oUF, 'Framed: oUF failed to load. Check that Libs/oUF/ is intact.')

-- Make namespace accessible for debugging without tainting _G
-- Use rawset to avoid triggering taint propagation
rawset(_G, 'FramedAddon', Framed)

-- Event frame for addon lifecycle
local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('ADDON_LOADED')
eventFrame:RegisterEvent('PLAYER_LOGIN')
eventFrame:RegisterEvent('PLAYER_SPECIALIZATION_CHANGED')

eventFrame:SetScript('OnEvent', function(self, event, arg1)
	if(event == 'ADDON_LOADED' and arg1 == addonName) then
		F.Config:Initialize()
		F.PresetDefaults.EnsureDefaults()
		F.Backups.EnsureDefaults()
		F.Backups.MigrateLegacyBackup()
		F.Backups.CaptureAutomatic(F.Backups.AUTO_LOGIN)
		self:UnregisterEvent('ADDON_LOADED')
	elseif(event == 'PLAYER_LOGIN') then
		-- Post-spawn initialization (runs after oUF:Factory spawns frames)
		-- Disable Blizzard's default frames
		F.DisableBlizzardFrames()

		-- Apply click-cast bindings
		F.ClickCasting.RefreshAll()

		-- Start auto-switching (detects content type and activates preset)
		F.AutoSwitch.Check()

		-- Minimap icon via LibDataBroker + LibDBIcon
		local LDB = LibStub('LibDataBroker-1.1')
		local LDBIcon = LibStub('LibDBIcon-1.0')
		local dataObj = LDB:NewDataObject('Framed', {
			type = 'launcher',
			text = 'Framed',
			icon = [[Interface\AddOns\Framed\Media\Textures\Logo]],
			OnClick = function(_, button)
				if(button == 'LeftButton') then
					if(F.Settings and F.Settings.Toggle) then
						F.Settings.Toggle()
					end
				elseif(button == 'RightButton') then
					if(F.EditMode.IsActive()) then
						F.EditMode.RequestCancel()
					else
						F.EditMode.Enter()
					end
				end
			end,
			OnTooltipShow = function(tip)
				tip:AddLine('|cff00ccffFramed|r')
				tip:AddLine('Left-click to open settings')
				tip:AddLine('Right-click to toggle edit mode')
			end,
		})
		LDBIcon:Register('Framed', dataObj, FramedDB.minimap)

		F.EventBus:Fire('PLAYER_LOGIN')

		-- First-run wizard
		if(not F.Config:Get('general.wizardCompleted')) then
			C_Timer.After(1, function()
				F.Onboarding.ShowWizard()
			end)
		end

		-- First-run overview (shown after wizard on next login)
		if(F.Config:Get('general.wizardCompleted') and not F.Config:Get('general.overviewCompleted')) then
			local function showOverviewDelayed()
				C_Timer.After(1, function()
					if(F.Onboarding and F.Onboarding.ShowOverview) then
						F.Onboarding.ShowOverview()
					end
				end)
			end

			if(InCombatLockdown()) then
				local deferFrame = CreateFrame('Frame')
				deferFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
				deferFrame:SetScript('OnEvent', function(frame)
					frame:UnregisterAllEvents()
					showOverviewDelayed()
				end)
			else
				showOverviewDelayed()
			end
		end

		self:UnregisterEvent('PLAYER_LOGIN')
	elseif(event == 'PLAYER_SPECIALIZATION_CHANGED') then
		F.ClickCasting.RefreshAll()
		F.EventBus:Fire('SPEC_CHANGED')
	end
end)

-- ============================================================
-- Spawn all frames via oUF:Factory
-- This runs in oUF's own PLAYER_LOGIN handler in a clean
-- (untainted) execution context, which is required for
-- SecureGroupHeaderTemplate SetAttribute calls.
-- ============================================================

local oUF = F.oUF
oUF:Factory(function(self)
	-- Register styles and spawn all unit frames
	F.Units.Player.Spawn()
	F.Units.Target.Spawn()
	F.Units.TargetTarget.Spawn()
	F.Units.Focus.Spawn()
	F.Units.Pet.Spawn()
	F.Units.Party.Spawn()
	F.Units.Raid.Spawn()
	F.Units.Boss.Spawn()
	F.Units.Arena.Spawn()
	F.Units.Pinned.Spawn()

	-- Force initial element updates on all spawned frames.
	-- oUF's initObject enables elements but doesn't call UpdateAllElements;
	-- it relies on PLAYER_ENTERING_WORLD which may have already fired.
	for _, object in next, self.objects do
		if(object.unit and object.UpdateAllElements) then
			object:UpdateAllElements('ForceUpdate')
		end
	end
end)

-- ============================================================
-- Debug: synthetic-diff import string generator
-- Builds a payload from the current FramedDB with a curated set of
-- mutations so the verification card shows multiple drops + extras and
-- ApplyImport exercises the EnsureDefaults / DeepMerge backfill path.
-- ============================================================

-- Leaf keys removed from general → appear as drops in the verifier and get
-- backfilled from accountDefaults on apply.
local SYNTHETIC_STRIP_GENERAL = {
	'editModeGridSnap',
	'tooltipMode',
	'mouseoverHighlightWidth',
}

-- Leaf keys removed from every preset's player.health config → broad drops
-- across all presets, exercising DeepMerge inside unit configs.
local SYNTHETIC_STRIP_PLAYER_HEALTH = {
	'smooth',
	'healPredictionMode',
	'damageAbsorbColor',
}

local testImportPopup

local function buildSyntheticPayload()
	local data = F.ImportExport.CaptureFullProfileData()

	if(data.general) then
		for _, key in next, SYNTHETIC_STRIP_GENERAL do
			data.general[key] = nil
		end
		-- Inject an unknown leaf so the verifier's "extras" branch lights up.
		data.general.__syntheticExtra = 'debug-only test value'
	end

	if(data.presets) then
		for _, preset in next, data.presets do
			local player = preset.unitConfigs and preset.unitConfigs.player
			if(player) then
				if(player.health) then
					for _, key in next, SYNTHETIC_STRIP_PLAYER_HEALTH do
						player.health[key] = nil
					end
				end
				-- Remove the entire optional sub-table to test that ApplyImport
				-- restores it (or leaves the feature disabled, depending on the
				-- nil-means-disabled convention).
				player.castbar = nil
			end
		end
	end

	return {
		version       = 1,
		scope         = 'full',
		timestamp     = time(),
		sourceVersion = (F.version or 'unknown') .. '-synthetic',
		data          = data,
	}
end

local function generateSyntheticImportString()
	local LibSerialize = LibStub('LibSerialize', true)
	local LibDeflate   = LibStub('LibDeflate',   true)
	if(not LibSerialize) then return nil, 'LibSerialize not loaded' end
	if(not LibDeflate)   then return nil, 'LibDeflate not loaded'   end

	local payload    = buildSyntheticPayload()
	local serialized = LibSerialize:Serialize(payload)
	local compressed = LibDeflate:CompressDeflate(serialized)
	local encoded    = LibDeflate:EncodeForPrint(compressed)
	return '!FRM1!' .. encoded
end

local function showTestImportPopup(encoded)
	local Widgets = F.Widgets
	local C       = F.Constants

	if(not testImportPopup) then
		local frame = CreateFrame('Frame', nil, UIParent, 'BackdropTemplate')
		Widgets.SetSize(frame, 520, 240)
		frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
		frame:SetFrameStrata('DIALOG')
		frame:SetMovable(true)
		frame:EnableMouse(true)
		frame:RegisterForDrag('LeftButton')
		frame:SetScript('OnDragStart', frame.StartMoving)
		frame:SetScript('OnDragStop',  frame.StopMovingOrSizing)

		frame:SetBackdrop({
			bgFile   = [[Interface\BUTTONS\WHITE8x8]],
			edgeFile = [[Interface\BUTTONS\WHITE8x8]],
			edgeSize = 1,
		})
		local bg = C.Colors.panel
		frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
		frame:SetBackdropBorderColor(0, 0, 0, 1)

		local accentBar = frame:CreateTexture(nil, 'OVERLAY')
		accentBar:SetHeight(1)
		accentBar:SetPoint('TOPLEFT',  frame, 'TOPLEFT',  0, 0)
		accentBar:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
		local ac = C.Colors.accent
		accentBar:SetColorTexture(ac[1], ac[2], ac[3], ac[4] or 1)

		local title = Widgets.CreateFontString(frame, C.Font.sizeTitle, C.Colors.textActive)
		title:SetPoint('TOPLEFT', frame, 'TOPLEFT', 16, -14)
		title:SetText('Test Import String (synthetic diff)')

		local help = Widgets.CreateFontString(frame, C.Font.sizeSmall, C.Colors.textSecondary)
		help:SetPoint('TOPLEFT',  frame, 'TOPLEFT',  16, -38)
		help:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -16, -38)
		help:SetJustifyH('LEFT')
		help:SetWordWrap(true)
		help:SetText('Press Cmd-A to select all, Cmd-C to copy, then paste into the Backups Import card.')

		local box = Widgets.CreateEditBox(frame, nil, 488, 130, 'multiline')
		box:SetPoint('TOPLEFT', frame, 'TOPLEFT', 16, -60)
		frame._box = box

		local closeBtn = Widgets.CreateButton(frame, 'Close', 'widget', 90, 24)
		closeBtn:SetPoint('BOTTOM', frame, 'BOTTOM', 0, 12)
		closeBtn:SetOnClick(function() frame:Hide() end)

		frame:Hide()
		testImportPopup = frame
	end

	testImportPopup._box:SetText(encoded)
	if(testImportPopup._box._editbox) then
		testImportPopup._box._editbox:SetFocus()
		testImportPopup._box._editbox:HighlightText()
	end
	testImportPopup:Show()
end

-- Slash commands
SLASH_FRAMED1 = '/framed'
SLASH_FRAMED2 = '/fr'

SlashCmdList['FRAMED'] = function(msg)
	local trimmed = msg:lower():trim()
	local cmd, arg1 = trimmed:match('^(%S+)%s*(.*)$')
	if(not cmd) then cmd = '' end

	if(cmd == 'version' or cmd == 'v') then
		print('|cff00ccff Framed|r v' .. F.version)
	elseif(cmd == 'config') then
		F.Config:PrintDebug()
	elseif(cmd == 'events') then
		F.EventBus:PrintDebug()
	elseif(cmd == 'pinstate') then
		local stored = FramedCharDB and FramedCharDB.pinnedGroup
		print('|cff00ccff[Framed/pin]|r stored state:')
		if(not stored) then
			print('  (pinnedGroup key missing from FramedCharDB)')
		else
			print('  inGroup = ' .. tostring(stored.inGroup))
			local n = 0
			for name in next, (stored.names or {}) do
				n = n + 1
				print('  name[' .. n .. '] = ' .. tostring(name))
			end
			if(n == 0) then print('  (no names stored)') end
		end
		print('|cff00ccff[Framed/pin]|r live state:')
		print('  IsInGroup = ' .. tostring(IsInGroup()))
		print('  IsInRaid = ' .. tostring(IsInRaid()))
		print('  GetNumGroupMembers = ' .. tostring(GetNumGroupMembers()))
		print('|cff00ccff[Framed/pin]|r saved pinned slots:')
		local presets = F.Config and F.Config:Get('presets')
		if(presets) then
			for presetName, preset in next, presets do
				local pinned = preset.unitConfigs and preset.unitConfigs.pinned
				if(pinned and pinned.slots) then
					local count = 0
					for _ in next, pinned.slots do count = count + 1 end
					print('  ' .. presetName .. ': ' .. count .. ' slot(s)')
				end
			end
		end
	elseif(cmd == 'edit') then
		if(F.EditMode.IsActive()) then
			F.EditMode.RequestCancel()
		else
			F.EditMode.Enter()
		end
	elseif(cmd == 'reset' and arg1 == 'all') then
		local d = F.Widgets.ShowConfirmDialog(
			'Reset All Settings',
			'This will delete ALL Framed settings, presets, and customizations.\nA backup will be saved to the Backups panel — you can restore later.',
			function()
				-- Save a named snapshot before wiping, so the user has a clear
				-- recovery handle.
				local label = 'Before reset (' .. date('%Y-%m-%d %H:%M') .. ')'
				local ok, err = F.Backups.Save(label)
				if(not ok) then
					print('|cff00ccff Framed|r Could not save pre-reset backup: ' .. (err or 'unknown error'))
					return
				end
				FramedDB = nil
				FramedCharDB = nil
				ReloadUI()
			end,
			nil
		)
		d._message:SetTextColor(1, 0.2, 0.2)
		d._btnYes._label:SetText('Yes, Reset Everything')
		d._btnNo._label:SetText('Cancel')
		d._activeWidth = 400
		d:_LayoutButtons('confirm')
		d:_UpdateHeight()
	elseif(cmd == 'restore') then
		-- Find the most recent 'Before reset (...)' snapshot
		local target, targetTs
		for name, wrapper in next, (FramedSnapshotsDB and FramedSnapshotsDB.snapshots or {}) do
			if(name:find('^Before reset')) then
				if(not targetTs or (wrapper.timestamp and wrapper.timestamp > targetTs)) then
					target   = name
					targetTs = wrapper.timestamp
				end
			end
		end

		if(not target) then
			print('|cff00ccff Framed|r No reset backup found. Open the Backups panel to browse all snapshots.')
			return
		end

		local dateStr = targetTs and date('%Y-%m-%d %H:%M', targetTs) or 'unknown date'
		F.Widgets.ShowConfirmDialog(
			'Restore Settings',
			'Restore "' .. target .. '" from ' .. dateStr .. '?\nThis will overwrite your current configuration.',
			function()
				local ok, err = F.Backups.Load(target)
				if(ok) then
					ReloadUI()
				else
					print('|cff00ccff Framed|r Restore failed: ' .. (err or 'unknown error'))
				end
			end,
			nil
		)
	elseif(cmd == 'debugicons') then
		-- Force show all indicator elements on player frame
		local pf = F.Units.Player and F.Units.Player.frame
		if(not pf) then print('|cff00ccff Framed|r No player frame') return end
		print('|cff00ccff Framed|r Player frame unit: ' .. tostring(pf.unit))
		local checks = {
			'GroupRoleIndicator', 'LeaderIndicator', 'AssistantIndicator',
			'CombatIndicator', 'RestingIndicator', 'RaidTargetIndicator',
			'ReadyCheckIndicator', 'PhaseIndicator', 'ResurrectIndicator',
			'SummonIndicator', 'RaidRoleIndicator', 'PvPIndicator',
		}
		for _, name in next, checks do
			local el = pf[name]
			if(el) then
				local w, h = el:GetSize()
				local visible = el:IsVisible()
				local shown = el:IsShown()
				local alpha = el:GetAlpha()
				local tex = el.GetTexture and tostring(el:GetTexture()) or 'n/a'
				local atlas = el.GetAtlas and tostring(el:GetAtlas()) or 'n/a'
				local enabled = pf.IsElementEnabled and pf:IsElementEnabled(name) or '?'
				print(('  %s: enabled=%s vis=%s shown=%s alpha=%.1f size=%dx%d tex=%s atlas=%s'):format(
					name, tostring(enabled), tostring(visible), tostring(shown), alpha, w, h, tex, atlas))
			else
				print('  ' .. name .. ': NOT ON FRAME')
			end
		end
	elseif(cmd == 'testimport') then
		local encoded, err = generateSyntheticImportString()
		if(not encoded) then
			print('|cff00ccff Framed|r testimport failed: ' .. (err or 'unknown error'))
			return
		end
		showTestImportPopup(encoded)
	elseif(cmd == 'aurastate') then
		local unit = arg1:match('^(%S+)') or 'target'
		if(not UnitExists(unit)) then
			print('|cff00ccff Framed|r aurastate: unit "' .. unit .. '" does not exist')
			return
		end

		local state = F.AuraState.Create(nil)
		state:FullRefresh(unit)

		local function formatFlags(flags)
			local active = {}
			for k, v in next, flags do
				if(v) then active[#active + 1] = k end
			end
			if(#active == 0) then return '(none)' end
			table.sort(active)
			return table.concat(active, ' ')
		end

		local function dumpList(label, list)
			print('|cff00ccff Framed|r aurastate ' .. unit .. ' — ' .. label .. ' (' .. #list .. ')')
			for _, entry in next, list do
				local id = entry.aura.auraInstanceID
				local name = F.IsValueNonSecret(entry.aura.name) and entry.aura.name or '<secret>'
				local spellId = F.IsValueNonSecret(entry.aura.spellId) and tostring(entry.aura.spellId) or '?'
				print('  [' .. id .. '] ' .. name .. ' (spellId=' .. spellId .. ') ' .. formatFlags(entry.flags))
			end
		end

		dumpList('HELPFUL', state:GetHelpfulClassified())
		dumpList('HARMFUL', state:GetHarmfulClassified())
	elseif(cmd == 'memdiag') then
		local seconds = tonumber(arg1:match('^(%d+)')) or 10
		F.MemDiag.Start(seconds)
	elseif(cmd == 'settingsmem') then
		F.MemDiag.ToggleSettingsProbe()
	elseif(cmd == 'memusage') then
		-- `raw` suffix skips the forced GC (see live allocated state);
		-- default forces a collect so we see post-GC live footprint.
		local forceGC = (arg1 ~= 'raw')
		if(forceGC) then collectgarbage('collect') end

		UpdateAddOnMemoryUsage()
		local totalKB = collectgarbage('count')
		local framedKB = GetAddOnMemoryUsage('Framed')

		-- Track delta from the previous call for yoyo amplitude sampling.
		local prev = F._lastMemSnapshot
		F._lastMemSnapshot = { total = totalKB, framed = framedKB, t = GetTime() }

		local mode = forceGC and 'post-GC' or 'raw'
		print(('|cff00ccff[Framed/mem]|r (%s) Framed: %.1f MB  |  total: %.1f MB  |  share: %.1f%%'):format(
			mode,
			framedKB / 1024,
			totalKB / 1024,
			totalKB > 0 and (framedKB / totalKB * 100) or 0))

		if(prev) then
			local dt = GetTime() - prev.t
			print(('  delta since last sample (%.1fs ago):  Framed %+.1f MB  |  total %+.1f MB'):format(
				dt,
				(framedKB - prev.framed) / 1024,
				(totalKB - prev.total) / 1024))
		end

		-- Top 10 addons by memory
		local rows = {}
		for i = 1, C_AddOns.GetNumAddOns() do
			local name = C_AddOns.GetAddOnInfo(i)
			local loaded = C_AddOns.IsAddOnLoaded(i)
			if(loaded) then
				local kb = GetAddOnMemoryUsage(name)
				if(kb and kb > 0) then
					rows[#rows + 1] = { name = name, kb = kb }
				end
			end
		end
		table.sort(rows, function(a, b) return a.kb > b.kb end)
		print('|cff00ccff[Framed/mem]|r top 10 addons by memory:')
		for i = 1, math.min(10, #rows) do
			print(('  %2d. %-32s  %7.1f MB'):format(i, rows[i].name, rows[i].kb / 1024))
		end

		-- Classified entry pool aggregate across all live AuraState instances.
		local totalPooled = 0
		local instanceCount = 0
		for instance in next, F.AuraState._instances do
			instanceCount = instanceCount + 1
			totalPooled = totalPooled + #instance._classifiedFreeList
		end
		print(('|cff00ccff[Framed/mem]|r aurastate pool: %d entries across %d instances'):format(
			totalPooled, instanceCount))

		-- Settings cache surface — direct test for "did teardown actually
		-- run?" Cached panel count should be 0 with settings closed, equal
		-- to # visited panels with settings open. _contentParent child count
		-- should match. Either non-zero with settings closed = teardown
		-- bypassed (close path didn't route through Settings.Hide).
		if(F.Settings) then
			local cachedPanels = 0
			for _ in next, F.Settings._panelFrames or {} do
				cachedPanels = cachedPanels + 1
			end
			local contentChildren = 0
			local cp = F.Settings._contentParent
			if(cp and cp.GetChildren) then
				contentChildren = select('#', cp:GetChildren())
			end
			print(('|cff00ccff[Framed/mem]|r settings cache: %d panels, %d content children'):format(
				cachedPanels, contentChildren))
		end

		-- Pixel updater registry growth — direct test for the registry-pinning
		-- leak class fixed in 5e8f974. Healthy: stable across settings cycles.
		-- Growing here = weak-key semantics broke or a new registry was added
		-- with strong keys.
		if(F.Widgets and F.Widgets.GetPixelUpdaterCounts) then
			local autoCount, onShowCount = F.Widgets.GetPixelUpdaterCounts()
			print(('|cff00ccff[Framed/mem]|r pixel updater: %d auto, %d on-show'):format(
				autoCount, onShowCount))
		end

		-- EventBus registry size — leak detector for handlers that fail to
		-- dedupe across panel rebuilds. Healthy: stable across settings cycles.
		if(F.EventBus and F.EventBus.GetRegistrySize) then
			local totalListeners, perEvent = F.EventBus:GetRegistrySize()
			local ebRows = {}
			for eventName, n in next, perEvent do
				ebRows[#ebRows + 1] = { name = eventName, n = n }
			end
			table.sort(ebRows, function(a, b) return a.n > b.n end)
			print(('|cff00ccff[Framed/mem]|r EventBus listeners: %d total across %d events'):format(
				totalListeners, #ebRows))
			for i = 1, math.min(10, #ebRows) do
				print(('  %3d × %s'):format(ebRows[i].n, ebRows[i].name))
			end
		end

		-- UIParent direct children count. Growth here over cycles = orphan
		-- frames leaked outside the settings tree. Stable = any leak is
		-- in non-frame state (tables, closures, textures).
		if(UIParent and UIParent.GetChildren) then
			local uiKids = { UIParent:GetChildren() }
			print(('|cff00ccff[Framed/mem]|r UIParent direct children: %d'):format(#uiKids))
		end
	elseif(cmd == 'pools') then
		local rows = {}
		-- Count observers per unit token first so each row can annotate
		-- how many other AuraState instances share its unit. Drives the
		-- #149 evaluation — central classification cache only helps when
		-- multiple frames observe the same unit token.
		local observersByUnit = {}
		for instance in next, F.AuraState._instances do
			local unit = instance._unit or '?'
			observersByUnit[unit] = (observersByUnit[unit] or 0) + 1
		end
		for instance in next, F.AuraState._instances do
			local owner = instance._owner
			local ownerName = owner and owner.GetName and owner:GetName() or '<anon>'
			local unit = instance._unit or '?'
			local row = {
				name = ownerName,
				unit = unit,
				observers = observersByUnit[unit],
				pooled = #instance._classifiedFreeList,
				helpful = 0,
				harmful = 0,
			}
			for _ in next, instance._helpfulClassifiedById do
				row.helpful = row.helpful + 1
			end
			for _ in next, instance._harmfulClassifiedById do
				row.harmful = row.harmful + 1
			end
			rows[#rows + 1] = row
		end
		-- Sort: highest-observer units first (most relevant to #149), then
		-- by pool size as a secondary key for same-observer-count entries.
		table.sort(rows, function(a, b)
			if(a.observers ~= b.observers) then return a.observers > b.observers end
			return a.pooled > b.pooled
		end)
		print('|cff00ccff Framed|r classified pool per instance:')
		print(('  %-32s %-12s %4s %6s %6s %6s'):format('frame', 'unit', 'obs', 'pooled', 'live+', 'live-'))
		for _, r in next, rows do
			print(('  %-32s %-12s %4d %6d %6d %6d'):format(
				r.name, r.unit, r.observers, r.pooled, r.helpful, r.harmful))
		end

		-- Summary: how many unit tokens have >1 observer? This is the
		-- upper bound on classification dedup savings from #149.
		local totalUnits, duplicatedUnits, totalInstances, dupInstances = 0, 0, 0, 0
		for _, count in next, observersByUnit do
			totalUnits = totalUnits + 1
			totalInstances = totalInstances + count
			if(count > 1) then
				duplicatedUnits = duplicatedUnits + 1
				dupInstances = dupInstances + count
			end
		end
		print(('  %-32s %d unit tokens, %d duplicated (%d instances total, %d on dup units)'):format(
			'[#149 overlap summary]', totalUnits, duplicatedUnits, totalInstances, dupInstances))
	elseif(cmd == 'help') then
		print('|cff00ccff Framed|r v' .. F.version .. ' — Commands:')
		print('  /framed — Open settings')
		print('  /framed version — Show version')
		print('  /framed config — Print config debug info')
		print('  /framed events — Print registered events')
		print('  /framed edit — Toggle Edit Mode')
		print('  /framed reset all — Reset all settings to defaults (saves a Backups snapshot)')
		print('  /framed restore — Restore the most recent reset backup from the Backups panel')
		print('  /framed debugicons — Debug indicator element state')
		print('  /framed testimport — Generate a synthetic-diff import string for testing backfill')
		print('  /framed aurastate [unit] — Dump classified aura flags (default: target)')
		print('  /framed memdiag [seconds] — Measure aura-path allocation churn (default 10s, max 30s; stops GC for the window)')
		print('  /framed memusage [raw] — Framed + total memory snapshot (default forces GC; "raw" skips it)')
		print('  /framed settingsmem — Toggle settings-window memory probe (prints delta on open/close)')
		print('  /framed pools — Dump per-instance classified pool sizes (for #144 diagnostics)')
	else
		-- Default: open settings
		if(F.Settings and F.Settings.Toggle) then
			F.Settings.Toggle()
		end
	end
end
