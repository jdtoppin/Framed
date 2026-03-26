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
---   unitType? string   Optional unit type hint for preview ('player','raid',etc.)
---   groupPreview? boolean  True → show multiple preview frames (3-5) instead of 1
---   create    function create(contentParent) → Frame  Panel frame constructor
--- }
function Settings.RegisterPanel(info)
	registeredPanels[#registeredPanels + 1] = info
end

-- ============================================================
-- Editing Unit Type
-- ============================================================

--- Get the unit type whose aura panels are currently being configured.
--- Falls back to 'party' if nothing is explicitly selected.
--- @return string
function Settings.GetEditingUnitType()
	return Settings._editingUnitType or 'party'
end

--- Set the unit type being edited.
--- @param unitType string
function Settings.SetEditingUnitType(unitType)
	Settings._editingUnitType = unitType
end

-- ============================================================
-- Editing Preset
-- ============================================================

local editingPreset = nil

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
	F.EventBus:Fire('EDITING_PRESET_CHANGED', presetName)
end

-- ============================================================
-- Aura Panel: Unit Type Dropdown + Copy-To Button
-- Shared builder used by all aura panels.
-- ============================================================

local DROPDOWN_H = 22

--- Build the unit type items list based on the active preset.
--- @return table[] Array of { text, value }
local function getUnitTypeItems()
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

--- Append a "Configure for:" dropdown and "Copy to..." button to an
--- aura panel's scroll content frame.
--- @param content Frame   The scroll content frame
--- @param width   number  Available content width
--- @param yOffset number  Current vertical cursor
--- @param panelId string  Panel id used for rebuild on change
--- @return number yOffset Updated vertical cursor
function Settings.BuildAuraUnitTypeRow(content, width, yOffset, panelId)
	-- ── "Configure for:" label ───────────────────────────────
	local label = Widgets.CreateFontString(content, C.Font.sizeSmall, C.Colors.textSecondary)
	label:SetText('Configure for:')
	label:ClearAllPoints()
	Widgets.SetPoint(label, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset - 4)

	-- ── Unit type dropdown ───────────────────────────────────
	local unitTypeDD = Widgets.CreateDropdown(content, 180)
	unitTypeDD:SetItems(getUnitTypeItems())
	unitTypeDD:SetValue(Settings.GetEditingUnitType() or getDefaultUnitType())
	unitTypeDD:ClearAllPoints()
	Widgets.SetPoint(unitTypeDD, 'TOPLEFT', content, 'TOPLEFT', 90, yOffset)
	unitTypeDD:SetOnSelect(function(value)
		Settings.SetEditingUnitType(value)
		-- Invalidate and rebuild the current panel
		Settings._panelFrames[panelId] = nil
		Settings.SetActivePanel(panelId)
	end)

	-- ── "Copy to..." button ──────────────────────────────────
	local copyBtn = Widgets.CreateButton(content, 'Copy to...', 'widget', 90, DROPDOWN_H)
	copyBtn:ClearAllPoints()
	Widgets.SetPoint(copyBtn, 'TOPLEFT', content, 'TOPLEFT', 280, yOffset)
	copyBtn:SetScript('OnClick', function()
		print('Framed: Copy to... (coming soon)')
	end)

	yOffset = yOffset - DROPDOWN_H - C.Spacing.normal

	-- ── Scoped preset banner ─────────────────────────────────
	local banner = Widgets.CreateFontString(content, C.Font.sizeSmall, C.Colors.accent)
	banner:SetText('Editing: ' .. Settings.GetEditingPreset() .. ' / ' .. (Settings.GetEditingUnitType() or getDefaultUnitType()))
	banner:ClearAllPoints()
	Widgets.SetPoint(banner, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - 16 - C.Spacing.tight

	return yOffset
end

-- ============================================================
-- Shared State
-- Populated by MainFrame.lua and Sidebar.lua at creation time.
-- ============================================================

Settings._mainFrame      = nil
Settings._sidebarBuilt   = false
Settings._activePanelId  = nil
Settings._activePanelFrame = nil
Settings._panelFrames    = {}
Settings._sidebarButtons = {}
Settings._contentParent  = nil
Settings._headerPanelText = nil
Settings._previewVisible = true

-- Function refs set by MainFrame.lua and Sidebar.lua
Settings._setSidebarSelected = nil   -- function(btn, selected)
Settings._refreshPreview     = nil   -- function()

-- ============================================================
-- Panel Switching
-- ============================================================

--- Switch to the given panel, building its frame on first visit.
--- @param panelId string
function Settings.SetActivePanel(panelId)
	-- Hide current
	if(Settings._activePanelFrame) then
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

	-- Build panel frame if not yet created
	if(not Settings._panelFrames[panelId]) then
		if(info.create and Settings._contentParent) then
			local pFrame = info.create(Settings._contentParent)
			if(pFrame) then
				pFrame:ClearAllPoints()
				pFrame:SetAllPoints(Settings._contentParent)
				-- Clear stored size so pixel updater's ReSize doesn't
				-- call SetSize() and conflict with SetAllPoints anchoring
				pFrame._width = nil
				pFrame._height = nil
				pFrame:Hide()
				Settings._panelFrames[panelId] = pFrame
			end
		end
	end

	Settings._activePanelFrame = Settings._panelFrames[panelId]
	if(Settings._activePanelFrame) then
		Settings._activePanelFrame:Show()
	end

	-- Update sidebar selection
	if(Settings._sidebarButtons[panelId]) then
		if(Settings._setSidebarSelected) then
			Settings._setSidebarSelected(Settings._sidebarButtons[panelId], true)
		end
	end

	-- Update sub-header text
	if(Settings._headerPanelText) then
		Settings._headerPanelText:SetText(info.label or '')
	end

	-- Refresh preview
	if(Settings._refreshPreview) then
		Settings._refreshPreview()
	end
end

-- ============================================================
-- Show / Hide / Toggle
-- ============================================================

--- Show the settings window (fade in).
function Settings.Show()
	if(not Settings._mainFrame) then
		Settings.CreateMainFrame()
	end
	Widgets.FadeIn(Settings._mainFrame)
	if(not Settings._sidebarBuilt) then
		Settings.BuildSidebar()
	end
end

--- Hide the settings window (fade out).
function Settings.Hide()
	if(Settings._mainFrame and Settings._mainFrame:IsShown()) then
		Widgets.FadeOut(Settings._mainFrame)
	end
end

--- Toggle the settings window open or closed.
function Settings.Toggle()
	if(not Settings._mainFrame) then
		Settings.CreateMainFrame()
	end
	if(Settings._mainFrame:IsShown()) then
		Widgets.FadeOut(Settings._mainFrame)
	else
		Widgets.FadeIn(Settings._mainFrame)
		if(not Settings._sidebarBuilt) then
			Settings.BuildSidebar()
		end
	end
end
