local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

F.Settings = {}
local Settings = F.Settings

-- ============================================================
-- Section Definitions
-- Ordered list of sidebar section headers.
-- ============================================================

local SECTIONS = {
	{ id = 'GLOBAL',         label = 'GLOBAL',         order = 1 },
	{ id = 'FRAME_PRESETS',  label = 'FRAME PRESETS',  order = 2 },
	{ id = 'PRESET_SCOPED',  label = '',               order = 3 },  -- uses "Editing: X" instead of label
	{ id = 'BOTTOM',         label = '',               order = 99 },
}

local sectionOrder = {}
for _, s in next, SECTIONS do
	sectionOrder[s.id] = s.order
end

-- Expose for Sidebar.lua
Settings._SECTIONS = SECTIONS
Settings._sectionOrder = sectionOrder

-- ============================================================
-- Panel Registry
-- Panels register themselves before the window is created.
-- The sidebar is built lazily on first show.
-- ============================================================

local registeredPanels = {}
Settings._panels = registeredPanels

--- Register a settings panel.
--- @param info table {
---   id        string   Unique panel identifier
---   label     string   Sidebar button label
---   section   string   Section id (matches SECTIONS)
---   order     number   Sort order within the section
---   create    function create(contentParent) → Frame  Panel frame constructor
--- }
function Settings.RegisterPanel(info)
	registeredPanels[#registeredPanels + 1] = info
end

-- ============================================================
-- Editing Unit Type
-- ============================================================

--- Get the unit type whose aura panels are currently being configured.
--- Falls back to a sensible default for the current preset.
--- @return string
function Settings.GetEditingUnitType()
	if(Settings._editingUnitType) then return Settings._editingUnitType end
	local info = C.PresetInfo[Settings.GetEditingPreset()]
	return (info and info.groupKey) or 'player'
end

--- Set the unit type being edited.
--- @param unitType string
function Settings.SetEditingUnitType(unitType)
	Settings._editingUnitType = unitType
	F.EventBus:Fire('EDITING_UNIT_TYPE_CHANGED', unitType)
end

-- ============================================================
-- Editing Preset
-- ============================================================

local editingPreset = nil
local lastKnownContentType = nil

--- Get the preset name currently being edited.
--- Falls back to the currently active preset from AutoSwitch, then 'Solo'.
--- @return string
function Settings.GetEditingPreset()
	return editingPreset or (F.AutoSwitch and F.AutoSwitch.GetCurrentPreset and F.AutoSwitch.GetCurrentPreset()) or 'Solo'
end

--- Set the preset name being edited.
--- @param presetName string
function Settings.SetEditingPreset(presetName)
	if(editingPreset == presetName) then return end
	editingPreset = presetName
	Settings._editingUnitType = nil
	F.EventBus:Fire('EDITING_PRESET_CHANGED', presetName)
	-- Update the sub-header preset indicator live
	if(Settings._updateHeaderPresetText) then Settings._updateHeaderPresetText() end
end

-- ============================================================
-- Aura Panel: Unit Type Dropdown + Copy-To Button
-- Shared builder used by all aura panels.
-- ============================================================

--- Build the unit type items list based on the active preset.
--- @return table[] Array of { text, value }
function Settings._getUnitTypeItems()
	local presetName = Settings.GetEditingPreset()
	local info = C.PresetInfo[presetName]
	local items = {
		{ text = 'Player',           value = 'player' },
		{ text = 'Target',           value = 'target' },
		{ text = 'Target of Target', value = 'targettarget' },
		{ text = 'Focus',            value = 'focus' },
		{ text = 'Pet',              value = 'pet' },
		{ text = 'Boss',             value = 'boss' },
	}
	if(info and info.groupKey) then
		items[#items + 1] = { text = info.groupLabel, value = info.groupKey }
	end
	return items
end

--- Get a sensible default unit type for the current preset.
--- @return string
local function getDefaultUnitType()
	local info = C.PresetInfo[Settings.GetEditingPreset()]
	return (info and info.groupKey) or 'player'
end

-- ── Aura panel config-key registry ───────────────────────────
-- Aura panels register their config key via BuildAuraUnitTypeRow so
-- the title-card Copy-to button knows which config to operate on.
-- `nil` = this panel has no copy affordance (e.g. CrowdControl).
Settings._auraConfigKeys = {}

--- Compatibility entry point for aura panels. The dropdown + Copy-to
--- UI moved into the title card, so this function no longer draws
--- anything — it simply registers the panel's configKey so the header
--- controls can look it up on activation. Returns `yOffset` unchanged
--- so existing callers keep working without edits.
--- @param content Frame
--- @param width number
--- @param yOffset number
--- @param panelId string  Panel id (matches a registered panel)
--- @param configKey? string  Aura config key (nil = hide Copy-to)
--- @return number yOffset Unchanged
function Settings.BuildAuraUnitTypeRow(content, width, yOffset, panelId, configKey)
	Settings._auraConfigKeys[panelId] = configKey
	return yOffset
end

--- Resolve a unit-type key (e.g. 'player') to the display label used in
--- the Configure for dropdown (e.g. 'Target of Target'). Falls back to
--- the key itself if no match is found.
local function unitTypeLabel(unitKey)
	for _, item in next, Settings._getUnitTypeItems() do
		if(item.value == unitKey) then return item.text end
	end
	return unitKey
end

--- Look up the active panel's registration info.
local function getActivePanelInfo()
	local id = Settings._activePanelId
	if(not id) then return nil end
	for _, p in next, registeredPanels do
		if(p.id == id) then return p end
	end
	return nil
end

--- Convert a raw unit label to a "Frame"-decorated variant:
---   'Player'           → 'Player Frame'
---   'Target of Target' → 'Target of Target Frame'
---   'Party Frames'     → 'Party Frames' (unchanged — group labels
---                         already end in "Frames")
local function frameUnitLabel(unitKey)
	local label = unitTypeLabel(unitKey)
	if(not label:match('Frames?$')) then
		label = label .. ' Frame'
	end
	return label
end

--- Build the item list for the header inline dropdown. Reuses the
--- Configure-for items but decorates each label with " Frame" so the
--- menu rows read "Player Frame", "Target Frame", etc.
local function buildHeaderUnitTypeItems()
	local raw = Settings._getUnitTypeItems()
	local items = {}
	for _, item in next, raw do
		items[#items + 1] = { text = frameUnitLabel(item.value), value = item.value }
	end
	return items
end

--- Populate / show / hide the title-card unit-type dropdown, Copy-to
--- button, and drill-in indicator suffix based on the active panel.
--- Called by SetActivePanel after the panel's unit type has been
--- normalized.
local function activateAuraHeaderControls(info)
	local dd        = Settings._headerUnitTypeDD
	local copy      = Settings._headerCopyToBtn
	local indic     = Settings._headerIndicatorText
	local copyDD    = Settings._headerCopyToDD
	if(not dd or not copy or not indic) then return end

	if(not info or info.subSection ~= 'auras') then
		if(dd.Close) then dd:Close() end
		dd:Hide()
		if(copyDD) then
			if(copyDD.Close) then copyDD:Close() end
			copyDD:Hide()
		end
		copy:Hide()
		indic:Hide()
		indic:SetText('')
		return
	end

	-- Populate the inline dropdown with "Player Frame" / "Target Frame" /
	-- etc. items and point its selection at the current unit type. The
	-- '/ ' prefix renders in the trigger only, not in the menu rows.
	dd:SetItems(buildHeaderUnitTypeItems())
	dd:SetLabelPrefix('/ ')
	dd:SetValue(Settings.GetEditingUnitType() or getDefaultUnitType())
	dd:SetOnSelect(function(value)
		local currentId = Settings._activePanelId
		if(not currentId) then return end
		Settings.SetEditingUnitType(value)
		-- Invalidate and rebuild the current panel — matches the
		-- behavior of the old in-panel "Configure for" dropdown.
		Settings._panelFrames[currentId] = nil
		Settings.SetActivePanel(currentId)
	end)
	dd:Show()

	-- Copy-to: visible only when the panel registered a configKey.
	local configKey = Settings._auraConfigKeys[info.id]
	if(configKey) then
		-- Build target list = all unit types EXCEPT the current source.
		local sourceUnit = Settings.GetEditingUnitType()
		local targets = {}
		for _, item in next, Settings._getUnitTypeItems() do
			if(item.value ~= sourceUnit) then
				targets[#targets + 1] = { text = item.text, value = item.value }
			end
		end

		if(#targets == 0) then
			-- Only one unit type exists — nothing to copy to.
			if(copyDD) then copyDD:Hide() end
			copy:Hide()
		else
			if(copyDD) then
				copyDD:SetItems(targets)
				copyDD:SetValue(targets[1].value)
				copyDD:Show()
			end

			copy:SetOnClick(function()
				local target = copyDD:GetValue()
				if(not target) then return end
				if(Settings.CopyTo(configKey, target)) then
					-- Invalidate + refresh so the active panel rebuilds
					-- against the new config.
					Settings._panelFrames[info.id] = nil
					Settings.RefreshActivePanel()
					-- Friendly chat confirmation (mirrors dialog output).
					local targetLabel = target
					for _, item in next, targets do
						if(item.value == target) then targetLabel = item.text; break end
					end
					print('Framed: Copied ' .. (info.label or info.id) .. ' settings to ' .. targetLabel)
				end
			end)
			copy:Enable()
			copy:Show()
		end
	else
		if(copyDD) then
			if(copyDD.Close) then copyDD:Close() end
			copyDD:Hide()
		end
		copy:Hide()
	end

	-- Constrain indicator text width so it truncates before right-side controls.
	local rightAnchor = (copyDD and copy:IsShown()) and copyDD or Settings._headerPresetText
	indic:SetPoint('RIGHT', rightAnchor, 'LEFT', -C.Spacing.normal, 0)

	-- Reset drill-in state — SetActivePanel always lands on the base page.
	indic:Hide()
	indic:SetText('')
end

Settings._activateAuraHeaderControls = activateAuraHeaderControls

--- Recompute the sub-header accent text ("Editing: Preset") and
--- show/hide it based on the active panel's section.
local function updateHeaderPresetText()
	if(not Settings._headerPresetText) then return end
	local info = getActivePanelInfo()
	if(not info or info.section ~= 'PRESET_SCOPED') then
		Settings._headerPresetText:Hide()
		return
	end
	Settings._headerPresetText:SetText('Editing: ' .. Settings.GetEditingPreset())
	Settings._headerPresetText:Show()
end

Settings._updateHeaderPresetText = updateHeaderPresetText

-- ============================================================
-- Shared State
-- Populated by MainFrame.lua and Sidebar.lua at creation time.
-- ============================================================

Settings._mainFrame      = nil
Settings._sidebarBuilt   = false
Settings._activePanelId  = nil
Settings._activePanelFrame = nil
Settings._panelFrames    = {}
Settings._panelRefresh   = {}
Settings._sidebarButtons = {}
Settings._contentParent  = nil
Settings._headerPanelText = nil
-- Function refs set by MainFrame.lua and Sidebar.lua
Settings._setSidebarSelected = nil   -- function(btn, selected)

-- ============================================================
-- Panel Switching
-- ============================================================

--- Switch to the given panel, building its frame on first visit.
--- @param panelId string
function Settings.SetActivePanel(panelId)
	-- Skip if already on this panel and its cached frame is still valid
	if(panelId == Settings._activePanelId and Settings._panelFrames[panelId] and Settings._activePanelFrame and Settings._activePanelFrame:IsShown()) then
		return
	end

	-- Hide current — cancel any in-flight panel transition animation
	if(Settings._activePanelFrame) then
		if(Settings._activePanelFrame._anim and Settings._activePanelFrame._anim['panelTransition']) then
			local anim = Settings._activePanelFrame._anim['panelTransition']
			if(anim.onComplete) then
				anim.onComplete(Settings._activePanelFrame)
			end
			Settings._activePanelFrame._anim['panelTransition'] = nil
		end
		Settings._activePanelFrame:Hide()
	end

	-- Deselect old sidebar button
	if(Settings._activePanelId and Settings._sidebarButtons[Settings._activePanelId]) then
		if(Settings._setSidebarSelected) then
			Settings._setSidebarSelected(Settings._sidebarButtons[Settings._activePanelId], false)
		end
	end

	Settings._activePanelId = panelId

	-- Find panel info
	local info = nil
	for _, p in next, registeredPanels do
		if(p.id == panelId) then
			info = p
			break
		end
	end

	if(not info) then return end

	-- ── Update editing unit type for unit frame panels ──────
	-- Fires every navigation (not just first create) so the
	-- "Configure for" dropdown on aura panels stays in sync.
	if(info.getUnitType) then
		Settings.SetEditingUnitType(info.getUnitType())
	elseif(info.unitType) then
		Settings.SetEditingUnitType(info.unitType)
	end

	-- Invalidate cached aura panels when unit type has changed since build
	if(info.subSection == 'auras' and Settings._panelFrames[panelId]) then
		local builtFor = Settings._panelBuiltUnitType and Settings._panelBuiltUnitType[panelId]
		local current = Settings.GetEditingUnitType()
		if(builtFor and builtFor ~= current) then
			Settings._panelFrames[panelId]:Hide()
			Settings._panelFrames[panelId]:SetParent(nil)
			Settings._panelFrames[panelId] = nil
			Settings._auraPreview = nil
		end
	end

	-- Build panel frame if not yet created
	if(not Settings._panelFrames[panelId]) then
		if(info.create and Settings._contentParent) then
			local pFrame, refreshFn = info.create(Settings._contentParent)
			if(pFrame) then
				pFrame:ClearAllPoints()
				pFrame:SetAllPoints(Settings._contentParent)
				-- Clear stored size so pixel updater's ReSize doesn't
				-- call SetSize() and conflict with SetAllPoints anchoring
				pFrame._width = nil
				pFrame._height = nil
				pFrame:Hide()
				Settings._panelFrames[panelId] = pFrame
				Settings._panelRefresh[panelId] = refreshFn  -- may be nil
				-- Track what unit type this aura panel was built for
				if(info.subSection == 'auras') then
					Settings._panelBuiltUnitType = Settings._panelBuiltUnitType or {}
					Settings._panelBuiltUnitType[panelId] = Settings.GetEditingUnitType()
				end
			end
		end
	end

	Settings._activePanelFrame = Settings._panelFrames[panelId]
	if(Settings._activePanelFrame) then
		-- Clear stale preview pointer before Show.  OnShow for CardGrid
		-- panels will set it to a fresh frame via BuildPreviewCard;
		-- pinned-preview panels leave it nil so the sync below restores
		-- from _ownedPreview instead of keeping the previous panel's ref.
		Settings._auraPreview = nil

		local SLIDE_OFFSET = 20
		Settings._activePanelFrame:SetAlpha(0)
		Settings._activePanelFrame:Show()
		Widgets.StartAnimation(Settings._activePanelFrame, 'panelTransition', 0, 1, C.Animation.durationNormal, function(frame, t)
			frame:SetAlpha(t)
			frame:ClearAllPoints()
			local yOff = -(SLIDE_OFFSET * (1 - t))
			frame:SetPoint('TOPLEFT', Settings._contentParent, 'TOPLEFT', 0, yOff)
			frame:SetPoint('BOTTOMRIGHT', Settings._contentParent, 'BOTTOMRIGHT', 0, yOff)
		end, function(frame)
			frame:SetAlpha(1)
			frame:ClearAllPoints()
			frame:SetAllPoints(Settings._contentParent)
		end)
		-- Track active scroll so sidebar wheel forwarding can find it
		Settings._activeScroll = Settings._activePanelFrame
		-- Reset scroll to top so the hint arrow refreshes for the new panel
		if(Settings._activePanelFrame.ScrollToTop) then
			Settings._activePanelFrame:ScrollToTop()
		end

		-- Restore this panel's owned preview (if it has one) and re-render.
		-- OnShow (triggered by Show above) may have rebuilt the preview via
		-- RebuildCards → BuildPreviewCard, which sets _auraPreview to the
		-- new frame.  In that case, sync _ownedPreview forward rather than
		-- overwriting the fresh reference with the stale one.
		if(Settings._activePanelFrame._ownedPreview) then
			if(Settings._auraPreview) then
				Settings._activePanelFrame._ownedPreview = Settings._auraPreview
			else
				Settings._auraPreview = Settings._activePanelFrame._ownedPreview
			end
			Settings._activePreviewGroup = panelId
			if(F.Settings.AuraPreview) then
				local unitType = Settings._auraPreview._unitType
					or (Settings.GetEditingUnitType and Settings.GetEditingUnitType())
					or 'player'
				F.Settings.AuraPreview.Render(Settings._auraPreview, unitType, panelId, nil)
			end
		end
	end

	-- Update sidebar selection
	if(Settings._sidebarButtons[panelId]) then
		if(Settings._setSidebarSelected) then
			Settings._setSidebarSelected(Settings._sidebarButtons[panelId], true)
		end
	end

	-- ── Clear preview pointer when switching away from aura panels ─
	-- Don't destroy — each preview is parented to its panel's scroll content
	-- and hides naturally. Destroying orphans the frame while _ownedPreview
	-- still references it, breaking restore on return.
	if(info.subSection ~= 'auras') then
		Settings._auraPreview = nil
	end

	-- ── Reset unit type when switching to aura panels ────────
	-- Prevents "pet" (or other frame-only types) from leaking into
	-- the Configure for dropdown on aura panels. Must run before the
	-- header text decorates itself with the unit label.
	if(info.subSection == 'auras') then
		local currentUT = Settings._editingUnitType
		if(currentUT == 'pet') then
			Settings._editingUnitType = nil  -- falls back to preset default
		end
	end

	-- Update sub-header text — the breadcrumb is always just the panel
	-- label now; aura panels get their "/ <Unit> Frame" suffix via the
	-- title-card inline dropdown, not via text concatenation.
	if(Settings._headerPanelText) then
		Settings._headerPanelText:SetText(info.label or '')
	end

	-- Update preset indicator (right side of title card)
	updateHeaderPresetText()

	-- Show/hide and populate the inline unit dropdown + Copy-to button
	activateAuraHeaderControls(info)

	-- Restore drill-in breadcrumb if the panel re-entered with an active indicator
	if(Settings._activePanelFrame and Settings._activePanelFrame._editingIndicatorName) then
		Settings.UpdateAuraBreadcrumb(info.label or '', Settings._activePanelFrame._editingIndicatorName)
	end

	-- ── Show/hide aura sidebar buttons based on active panel ─
	-- Defensives/Externals are hidden only while the Pet page is active.
	F.EventBus:Fire('ACTIVE_PANEL_CHANGED', panelId)

end

--- Update the title card breadcrumb for an aura panel. The base label
--- (e.g. 'Buffs') stays in `_headerPanelText`, the unit-type dropdown
--- stays visible, and the drill-in suffix is rendered in a separate
--- FontString to the right of the dropdown so it reads as:
---     Buffs  / Player Frame ▾   >  Major Cooldowns
--- Copy-to is hidden while drilled in, since it's a base-page action.
--- @param pageLabel string   The panel label (e.g. 'Buffs')
--- @param indicatorName string|nil  Optional indicator sub-page name
function Settings.UpdateAuraBreadcrumb(pageLabel, indicatorName)
	if(not Settings._headerPanelText) then return end
	Settings._headerPanelText:SetText(pageLabel)

	local indic = Settings._headerIndicatorText
	local copy  = Settings._headerCopyToBtn
	local copyDD    = Settings._headerCopyToDD
	if(indicatorName) then
		if(indic) then
			indic:SetText('|cff6688cc>|r  ' .. indicatorName)
			indic:Show()
		end
	else
		if(indic) then
			indic:SetText('')
			indic:Hide()
		end
		-- Restore Copy-to only if this panel has a configKey registered.
		local activeId = Settings._activePanelId
		local configKey = activeId and Settings._auraConfigKeys[activeId]
		if(configKey) then
			if(copyDD) then copyDD:Show() end
			if(copy) then copy:Show() end
		end
	end
end

--- Re-render the live preview for the given aura group, dimming everything
--- except icons belonging to the active indicator.
--- @param activeGroupKey string     Panel id (e.g. 'buffs')
--- @param activeIndicatorName string|nil  Indicator name to highlight, or nil for all
function Settings.UpdateAuraPreviewDimming(activeGroupKey, activeIndicatorName)
	if(not F.Settings.AuraPreview) then return end
	F.Settings.AuraPreview.UpdateDimming(activeGroupKey, activeIndicatorName)
end

--- Full rebuild of the aura preview (call after config changes).
function Settings.RebuildAuraPreview()
	if(not F.Settings.AuraPreview) then return end
	F.Settings.AuraPreview.Rebuild()
end

-- Keep the title-card inline dropdown in sync whenever the editing
-- unit type changes — e.g. when the user switches to a unit frame
-- panel (Target, Focus) and then back to an aura panel.
F.EventBus:Register('EDITING_UNIT_TYPE_CHANGED', function(newType)
	local dd = Settings._headerUnitTypeDD
	if(not dd or not dd:IsShown()) then return end
	dd:SetValue(newType or Settings.GetEditingUnitType() or 'player')
end, 'Settings.HeaderUnitTypeSync')

-- Refresh active panel when the editing preset changes.
-- Invalidate all preset-scoped panels so stale frames are rebuilt
-- when the user navigates to them.
F.EventBus:Register('EDITING_PRESET_CHANGED', function()
	-- Refresh header dropdown items unconditionally — during zone
	-- transitions the main frame may not be :IsShown() yet, but the
	-- items must be correct when it reappears.
	local dd = Settings._headerUnitTypeDD
	if(dd) then
		dd:SetItems(buildHeaderUnitTypeItems())
		dd:SetValue(Settings.GetEditingUnitType() or getDefaultUnitType())
	end

	for _, p in next, registeredPanels do
		if(p.section == 'PRESET_SCOPED' and Settings._panelFrames[p.id]) then
			Settings._panelFrames[p.id] = nil
		end
	end
	-- Only rebuild if settings is visible — entering edit mode hides settings
	-- first, so rebuilding a stale panel would reference a missing unit type
	if(not Settings._mainFrame or not Settings._mainFrame:IsShown()) then return end
	local activeId = Settings._activePanelId
	if(not activeId) then return end
	if(Settings._panelRefresh[activeId]) then
		Settings._panelRefresh[activeId]()
	else
		Settings.SetActivePanel(activeId)
	end
end, 'Settings.PanelRefresh')

--- Call the active panel's Refresh callback, if it has one.
function Settings.RefreshActivePanel()
	local activeId = Settings._activePanelId
	if(not activeId) then return end
	if(Settings._panelRefresh[activeId]) then
		Settings._panelRefresh[activeId]()
	else
		Settings._panelFrames[activeId] = nil
		Settings.SetActivePanel(activeId)
	end
end

-- When the active preset changes (zone/content change), follow it
F.EventBus:Register('PRESET_CHANGED', function(presetName)
	editingPreset = nil
	Settings._editingUnitType = nil
	-- If settings is open, update to the new preset
	if(Settings._mainFrame and Settings._mainFrame:IsShown()) then
		Settings.SetEditingPreset(presetName)
	end
end, 'Settings.FollowAutoSwitch')

-- ============================================================
-- Show / Hide / Toggle
-- ============================================================

--- Sync editing preset only when the detected content type has
--- changed since settings was last opened. Preserves manual
--- preset selection within the same content type.
function Settings._syncPresetIfContentChanged()
	if(not F.AutoSwitch) then return end
	F.AutoSwitch.Check()
	local contentType = F.AutoSwitch.GetCurrentContentType()
	if(contentType ~= lastKnownContentType) then
		lastKnownContentType = contentType
		local activePreset = F.AutoSwitch.GetCurrentPreset()
		editingPreset = nil
		Settings._editingUnitType = nil
		Settings.SetEditingPreset(activePreset)
	end
end

--- Show the settings window (fade in).
function Settings.Show()
	if(not Settings._mainFrame) then
		Settings.CreateMainFrame()
	end
	Widgets.FadeIn(Settings._mainFrame)
	if(not Settings._sidebarBuilt) then
		Settings.BuildSidebar()
	end
	Settings._syncPresetIfContentChanged()
end

--- Hide the settings window (fade out).
function Settings.Hide()
	if(Settings._mainFrame and Settings._mainFrame:IsShown()) then
		Widgets.FadeOut(Settings._mainFrame)
	end
end

--- Toggle the settings window open or closed.
function Settings.Toggle()
	if(InCombatLockdown()) then
		print('|cff00ccffFramed|r Settings cannot be opened in combat.')
		return
	end
	if(not Settings._mainFrame) then
		Settings.CreateMainFrame()
	end
	if(Settings._mainFrame:IsShown()) then
		Widgets.FadeOut(Settings._mainFrame)
	else
		Settings._syncPresetIfContentChanged()
		Widgets.FadeIn(Settings._mainFrame)
		if(not Settings._sidebarBuilt) then
			Settings.BuildSidebar()
		end
	end
end
