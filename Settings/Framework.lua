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
	{ id = 'GENERAL',      label = 'GENERAL',      order = 1 },
	{ id = 'UNIT_FRAMES',  label = 'UNIT FRAMES',  order = 2 },
	{ id = 'GROUP_FRAMES', label = 'GROUP FRAMES',  order = 3 },
	{ id = 'AURAS',        label = 'AURAS',         order = 4 },
	{ id = 'BOTTOM',       label = '',              order = 99 },
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
-- Editing Layout
-- ============================================================

--- Get the layout name currently being edited.
--- Falls back to the currently active layout from AutoSwitch.
--- @return string
function Settings.GetEditingLayout()
	if(Settings._editingLayout) then
		return Settings._editingLayout
	end
	if(F.AutoSwitch and F.AutoSwitch.GetCurrentLayout) then
		return F.AutoSwitch.GetCurrentLayout()
	end
	return nil
end

--- Set the layout name being edited.
--- @param layoutName string
function Settings.SetEditingLayout(layoutName)
	Settings._editingLayout = layoutName
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
