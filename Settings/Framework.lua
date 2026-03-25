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

-- Fast lookup: sectionId → order value
local sectionOrder = {}
for _, s in next, SECTIONS do
	sectionOrder[s.id] = s.order
end

-- ============================================================
-- Panel Registry
-- Panels register themselves before the window is created.
-- The sidebar is built lazily on first show.
-- ============================================================

local registeredPanels = {}

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
-- Window Constants
-- ============================================================

local WINDOW_W         = 900
local WINDOW_H         = 600
local WINDOW_MIN_W     = 700
local WINDOW_MIN_H     = 450
local WINDOW_MAX_W     = 1200
local WINDOW_MAX_H     = 900

local SIDEBAR_W        = 170
local PREVIEW_W        = 200
local HEADER_HEIGHT    = 24   -- from CreateHeaderedFrame (inner header bar)
local SUB_HEADER_H     = 32   -- panel title bar below the drag header
local CLOSE_BTN_SIZE   = 20
local RESIZE_BTN_SIZE  = 8    -- matches Widgets.CreateResizeButton

local SIDEBAR_SECTION_H  = 22
local SIDEBAR_BTN_H      = 26
local SIDEBAR_ACCENT_W   = 2  -- left accent border on selected button

local PREVIEW_ITEM_H     = 48
local PREVIEW_ITEM_GAP   = 4

-- ============================================================
-- Window State
-- ============================================================

local mainFrame      = nil
local sidebarBuilt   = false
local activePanelId  = nil
local activePanelFrame = nil
local panelFrames    = {}     -- panelId → created panel frame
local sidebarButtons = {}     -- panelId → sidebar button frame
local contentParent  = nil    -- frame that panel frames are parented to
local previewArea    = nil    -- right side preview container
local previewVisible = true
local headerPanelText = nil   -- FontString showing active panel name
local previewFrames  = {}     -- currently shown preview frame widgets

-- ============================================================
-- Sidebar Accent Border Helper
-- ============================================================

--- Draw or clear the 2px left accent border on a sidebar button.
local function setSidebarSelected(btn, selected)
	if(selected) then
		-- Accent background dim + white text
		btn:SetBackdropColor(
			C.Colors.accentDim[1],
			C.Colors.accentDim[2],
			C.Colors.accentDim[3],
			C.Colors.accentDim[4] or 1)
		btn:SetBackdropBorderColor(0, 0, 0, 1)
		if(btn._label) then
			btn._label:SetTextColor(1, 1, 1, 1)
		end
		if(btn._accentBar) then
			btn._accentBar:Show()
		end
	else
		-- Normal widget background
		btn:SetBackdropColor(
			C.Colors.widget[1],
			C.Colors.widget[2],
			C.Colors.widget[3],
			C.Colors.widget[4] or 1)
		btn:SetBackdropBorderColor(0, 0, 0, 1)
		if(btn._label) then
			local tc = C.Colors.textNormal
			btn._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
		if(btn._accentBar) then
			btn._accentBar:Hide()
		end
	end
end

-- ============================================================
-- Docked Preview
-- ============================================================

--- Clear all current preview frame widgets from the preview area.
local function clearPreviewFrames()
	for _, pf in next, previewFrames do
		pf:Hide()
		pf:SetParent(nil)
	end
	previewFrames = {}
end

--- Refresh the docked preview for the currently active panel.
local function refreshPreview()
	if(not previewArea) then return end
	clearPreviewFrames()

	if(not previewVisible) then
		previewArea:Hide()
		return
	end

	local info = nil
	for _, p in next, registeredPanels do
		if(p.id == activePanelId) then
			info = p
			break
		end
	end

	if(not info) then
		previewArea:Hide()
		return
	end

	previewArea:Show()

	-- Determine how many preview items to show
	local count = 1
	if(info.groupPreview) then
		count = 4
	end

	local fakeUnits = F.Preview.GetFakeUnits(count)
	local itemW = PREVIEW_W - (C.Spacing.tight * 2)
	local yOffset = -C.Spacing.tight

	for i = 1, #fakeUnits do
		local pf = F.Preview.CreatePreviewFrame(previewArea, info.unitType or 'player', itemW, PREVIEW_ITEM_H)
		pf:ClearAllPoints()
		Widgets.SetPoint(pf, 'TOPLEFT', previewArea, 'TOPLEFT', C.Spacing.tight, yOffset)
		pf:SetFakeUnit(fakeUnits[i])
		pf:Show()
		previewFrames[#previewFrames + 1] = pf
		yOffset = yOffset - PREVIEW_ITEM_H - PREVIEW_ITEM_GAP
	end
end

-- ============================================================
-- Panel Switching
-- ============================================================

--- Switch to the given panel, building its frame on first visit.
--- @param panelId string
function Settings.SetActivePanel(panelId)
	-- Hide current
	if(activePanelFrame) then
		activePanelFrame:Hide()
	end

	-- Deselect old sidebar button
	if(activePanelId and sidebarButtons[activePanelId]) then
		setSidebarSelected(sidebarButtons[activePanelId], false)
	end

	activePanelId = panelId

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
	if(not panelFrames[panelId]) then
		if(info.create and contentParent) then
			local pFrame = info.create(contentParent)
			if(pFrame) then
				pFrame:ClearAllPoints()
				pFrame:SetPoint('TOPLEFT',  contentParent, 'TOPLEFT',  0, 0)
				pFrame:SetPoint('TOPRIGHT', contentParent, 'TOPRIGHT', 0, 0)
				pFrame:Hide()
				panelFrames[panelId] = pFrame
			end
		end
	end

	activePanelFrame = panelFrames[panelId]
	if(activePanelFrame) then
		activePanelFrame:Show()
	end

	-- Update sidebar selection
	if(sidebarButtons[panelId]) then
		setSidebarSelected(sidebarButtons[panelId], true)
	end

	-- Update sub-header text
	if(headerPanelText) then
		headerPanelText:SetText(info.label or '')
	end

	-- Refresh preview
	refreshPreview()
end

-- ============================================================
-- Sidebar Builder
-- ============================================================

--- Build the sidebar panel buttons. Called once on first show.
--- @param sidebar Frame
local function buildSidebarContent(sidebar)
	-- Sort panels: section order first, then panel order within section
	table.sort(registeredPanels, function(a, b)
		local sa = sectionOrder[a.section] or 99
		local sb = sectionOrder[b.section] or 99
		if(sa ~= sb) then return sa < sb end
		return (a.order or 0) < (b.order or 0)
	end)

	-- Group panels by section (preserving sort order)
	local sectionPanels = {}
	local sectionsSeen = {}
	local orderedSections = {}

	for _, panel in next, registeredPanels do
		local sid = panel.section or 'GENERAL'
		if(not sectionPanels[sid]) then
			sectionPanels[sid] = {}
			sectionsSeen[#sectionsSeen + 1] = sid
			orderedSections[#orderedSections + 1] = sid
		end
		sectionPanels[sid][#sectionPanels[sid] + 1] = panel
	end

	local yOffset = -C.Spacing.tight
	local sidebarW = SIDEBAR_W

	for i, sectionId in next, orderedSections do
		-- Find section definition
		local sectionLabel = sectionId
		local isBottomSection = false
		for _, s in next, SECTIONS do
			if(s.id == sectionId) then
				sectionLabel = s.label
				if(s.id == 'BOTTOM') then
					isBottomSection = true
				end
				break
			end
		end

		-- Separator line before BOTTOM section
		if(isBottomSection) then
			local sep = sidebar:CreateTexture(nil, 'ARTWORK')
			sep:SetHeight(1)
			sep:SetColorTexture(
				C.Colors.border[1],
				C.Colors.border[2],
				C.Colors.border[3],
				C.Colors.border[4] or 1)
			sep:ClearAllPoints()
			Widgets.SetPoint(sep, 'TOPLEFT',  sidebar, 'TOPLEFT',  0, yOffset)
			Widgets.SetPoint(sep, 'TOPRIGHT', sidebar, 'TOPRIGHT', 0, yOffset)
			yOffset = yOffset - C.Spacing.tight
		end

		-- Section header text (skip empty label for BOTTOM)
		if(sectionLabel ~= '') then
			local headerText = Widgets.CreateFontString(sidebar, C.Font.sizeSmall, C.Colors.textSecondary)
			headerText:ClearAllPoints()
			Widgets.SetPoint(headerText, 'TOPLEFT', sidebar, 'TOPLEFT', C.Spacing.normal, yOffset)
			headerText:SetText(sectionLabel)
			yOffset = yOffset - SIDEBAR_SECTION_H
		end

		-- Panel buttons for this section
		local panels = sectionPanels[sectionId]
		for _, panel in next, panels do
			local btn = Widgets.CreateButton(sidebar, panel.label, 'widget', sidebarW, SIDEBAR_BTN_H)
			btn:ClearAllPoints()
			Widgets.SetPoint(btn, 'TOPLEFT',  sidebar, 'TOPLEFT',  0, yOffset)
			Widgets.SetPoint(btn, 'TOPRIGHT', sidebar, 'TOPRIGHT', 0, yOffset)

			-- Left-align the label
			if(btn._label) then
				btn._label:ClearAllPoints()
				Widgets.SetPoint(btn._label, 'LEFT', btn, 'LEFT', C.Spacing.normal + SIDEBAR_ACCENT_W + C.Spacing.base, 0)
				btn._label:SetJustifyH('LEFT')
			end

			-- 2px accent left bar (hidden by default)
			local accentBar = btn:CreateTexture(nil, 'OVERLAY')
			accentBar:SetWidth(SIDEBAR_ACCENT_W)
			accentBar:SetPoint('TOPLEFT',    btn, 'TOPLEFT',    0, 0)
			accentBar:SetPoint('BOTTOMLEFT', btn, 'BOTTOMLEFT', 0, 0)
			accentBar:SetColorTexture(
				C.Colors.accent[1],
				C.Colors.accent[2],
				C.Colors.accent[3],
				C.Colors.accent[4] or 1)
			accentBar:Hide()
			btn._accentBar = accentBar

			-- Hover override: keep left alignment on highlight
			btn:SetScript('OnEnter', function(self)
				if(self.value ~= activePanelId) then
					Widgets.SetBackdropHighlight(self, true)
				end
				if(Widgets.ShowTooltip and self._tooltipTitle) then
					Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
				end
			end)

			btn:SetScript('OnLeave', function(self)
				if(self.value ~= activePanelId) then
					Widgets.SetBackdropHighlight(self, false)
				end
				if(Widgets.HideTooltip) then
					Widgets.HideTooltip()
				end
			end)

			local panelId = panel.id
			btn.value = panelId
			btn:SetOnClick(function()
				Settings.SetActivePanel(panelId)
			end)

			sidebarButtons[panel.id] = btn
			yOffset = yOffset - SIDEBAR_BTN_H
		end

		-- Gap after each section
		yOffset = yOffset - C.Spacing.tight
	end

end

-- ============================================================
-- Main Frame Constructor
-- ============================================================

--- Build the full settings window. Called once, lazily on first show.
function Settings.CreateMainFrame()
	if(mainFrame) then return end

	-- ── Outer window ──────────────────────────────────────────
	local frame, header = Widgets.CreateHeaderedFrame(UIParent, 'Framed', WINDOW_W, WINDOW_H)
	frame:SetFrameStrata('HIGH')
	frame:Hide()
	mainFrame = frame

	-- Position: centered on first open
	frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)

	-- ── Persist position on drag stop ─────────────────────────
	header:SetScript('OnDragStop', function(self)
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		if(F.Config) then
			F.Config:Set('general.settingsPos', { point, relPoint, x, y })
		end
	end)

	-- ── Close button (top-right of header) ────────────────────
	local closeBtn = Widgets.CreateIconButton(header, [[Interface\BUTTONS\UI-Panel-MinimizeButton-Up]], CLOSE_BTN_SIZE)
	closeBtn:ClearAllPoints()
	Widgets.SetPoint(closeBtn, 'RIGHT', header, 'RIGHT', -C.Spacing.base, 0)
	closeBtn:SetOnClick(function()
		Widgets.FadeOut(frame)
	end)
	closeBtn:SetWidgetTooltip('Close')

	-- ── Resize button ─────────────────────────────────────────
	Widgets.CreateResizeButton(frame,
		WINDOW_MIN_W, WINDOW_MIN_H,
		WINDOW_MAX_W, WINDOW_MAX_H,
		nil,
		function(f, w, h)
			if(F.Config) then
				F.Config:Set('general.settingsSize', { w, h })
			end
		end)

	-- ── ESC closes the window ─────────────────────────────────
	frame:EnableKeyboard(true)
	frame:SetPropagateKeyboardInput(true)
	frame:SetScript('OnKeyDown', function(self, key)
		if(key == 'ESCAPE') then
			self:SetPropagateKeyboardInput(false)
			Widgets.FadeOut(self)
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)

	-- ── Sidebar ───────────────────────────────────────────────
	local sidebar = Widgets.CreateBorderedFrame(frame, SIDEBAR_W, WINDOW_H - HEADER_HEIGHT, C.Colors.background, C.Colors.border)
	sidebar:ClearAllPoints()
	Widgets.SetPoint(sidebar, 'TOPLEFT',    frame, 'TOPLEFT',    0, -HEADER_HEIGHT)
	Widgets.SetPoint(sidebar, 'BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
	sidebar:SetWidth(SIDEBAR_W)

	-- ── Sub-header bar (below title bar, above content) ───────
	local subHeader = Widgets.CreateBorderedFrame(frame, WINDOW_W - SIDEBAR_W, SUB_HEADER_H, C.Colors.widget, C.Colors.border)
	subHeader:ClearAllPoints()
	Widgets.SetPoint(subHeader, 'TOPLEFT',  sidebar, 'TOPRIGHT',  0, 0)
	Widgets.SetPoint(subHeader, 'TOPRIGHT', frame,   'TOPRIGHT',  0, -HEADER_HEIGHT)

	-- Panel title (left of sub-header)
	headerPanelText = Widgets.CreateFontString(subHeader, C.Font.sizeNormal, C.Colors.textActive)
	headerPanelText:ClearAllPoints()
	Widgets.SetPoint(headerPanelText, 'LEFT', subHeader, 'LEFT', C.Spacing.normal, 0)
	headerPanelText:SetText('')

	-- Edit Mode button (right of sub-header)
	local editModeBtn = Widgets.CreateButton(subHeader, 'Edit Mode', 'widget', 80, SUB_HEADER_H - C.Spacing.base)
	editModeBtn:ClearAllPoints()
	Widgets.SetPoint(editModeBtn, 'RIGHT', subHeader, 'RIGHT', -(80 + C.Spacing.tight + C.Spacing.base), 0)
	editModeBtn:SetOnClick(function()
		Settings.Hide()
		if(F.EditMode and F.EditMode.Enter) then
			F.EditMode.Enter()
		end
	end)
	editModeBtn:SetWidgetTooltip('Edit Mode', 'Drag and resize unit frames directly on screen.')

	-- Preview toggle (rightmost in sub-header)
	local previewBtn = Widgets.CreateButton(subHeader, 'Preview', 'widget', 70, SUB_HEADER_H - C.Spacing.base)
	previewBtn:ClearAllPoints()
	Widgets.SetPoint(previewBtn, 'RIGHT', subHeader, 'RIGHT', -C.Spacing.base, 0)
	previewBtn:SetOnClick(function()
		previewVisible = not previewVisible
		if(previewVisible) then
			F.Preview.Enable()
		else
			F.Preview.Disable()
		end
		refreshPreview()
	end)
	previewBtn:SetWidgetTooltip('Toggle Preview', 'Show or hide the docked unit frame preview.')

	-- ── Content area (right of sidebar, below sub-header) ─────
	local contentArea = CreateFrame('Frame', nil, frame)
	contentArea:ClearAllPoints()
	Widgets.SetPoint(contentArea, 'TOPLEFT',     subHeader, 'BOTTOMLEFT',  0,  0)
	Widgets.SetPoint(contentArea, 'BOTTOMRIGHT', frame,     'BOTTOMRIGHT', 0,  0)

	-- Panel scroll container (fills content area minus preview strip)
	local panelScroll = Widgets.CreateScrollFrame(
		contentArea,
		nil,
		WINDOW_W - SIDEBAR_W - PREVIEW_W,
		WINDOW_H - HEADER_HEIGHT - SUB_HEADER_H)
	panelScroll:ClearAllPoints()
	Widgets.SetPoint(panelScroll, 'TOPLEFT',     contentArea, 'TOPLEFT',     0, 0)
	Widgets.SetPoint(panelScroll, 'BOTTOMLEFT',  contentArea, 'BOTTOMLEFT',  0, 0)

	contentParent = panelScroll:GetContentFrame()
	local contentW = WINDOW_W - SIDEBAR_W - PREVIEW_W
	local contentH = WINDOW_H - HEADER_HEIGHT - SUB_HEADER_H
	contentParent:SetWidth(contentW)
	contentParent:SetHeight(contentH)
	-- Store explicit dimensions for panel creators that can't rely on GetWidth/GetHeight
	contentParent._explicitWidth = contentW
	contentParent._explicitHeight = contentH

	-- ── Preview area (right strip) ────────────────────────────
	local preview = Widgets.CreateBorderedFrame(contentArea, PREVIEW_W, WINDOW_H - HEADER_HEIGHT - SUB_HEADER_H, C.Colors.background, C.Colors.border)
	preview:ClearAllPoints()
	Widgets.SetPoint(preview, 'TOPRIGHT',    contentArea, 'TOPRIGHT',    0, 0)
	Widgets.SetPoint(preview, 'BOTTOMRIGHT', contentArea, 'BOTTOMRIGHT', 0, 0)
	preview:SetWidth(PREVIEW_W)
	previewArea = preview

	-- Preview area label
	local previewLabel = Widgets.CreateFontString(preview, C.Font.sizeSmall, C.Colors.textSecondary)
	previewLabel:ClearAllPoints()
	Widgets.SetPoint(previewLabel, 'TOPLEFT', preview, 'TOPLEFT', C.Spacing.tight, -C.Spacing.tight)
	previewLabel:SetText('PREVIEW')

	-- ── Pixel updater ─────────────────────────────────────────
	Widgets.AddToPixelUpdater_OnShow(frame)

	-- ── Restore saved position / size ─────────────────────────
	if(F.Config) then
		local pos = F.Config:Get('general.settingsPos')
		if(pos) then
			frame:ClearAllPoints()
			frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
		end
		local sz = F.Config:Get('general.settingsSize')
		if(sz) then
			frame:SetSize(sz[1], sz[2])
		end
	end

	-- ── Store sidebar reference for BuildSidebar ──────────────
	frame._sidebar = sidebar

	-- Enable preview by default when window is open
	F.Preview.Enable()
end

-- ============================================================
-- Sidebar Build (deferred to first show)
-- ============================================================

--- Build sidebar content. Called once on first show.
function Settings.BuildSidebar()
	if(sidebarBuilt or not mainFrame) then return end
	sidebarBuilt = true

	buildSidebarContent(mainFrame._sidebar)

	-- Auto-select first registered panel
	if(#registeredPanels > 0) then
		Settings.SetActivePanel(registeredPanels[1].id)
	end
end

-- ============================================================
-- Show / Hide / Toggle
-- ============================================================

--- Show the settings window (fade in).
function Settings.Show()
	if(not mainFrame) then
		Settings.CreateMainFrame()
	end
	Widgets.FadeIn(mainFrame)
	if(not sidebarBuilt) then
		Settings.BuildSidebar()
	end
end

--- Hide the settings window (fade out).
function Settings.Hide()
	if(mainFrame and mainFrame:IsShown()) then
		Widgets.FadeOut(mainFrame)
	end
end

--- Toggle the settings window open or closed.
function Settings.Toggle()
	if(not mainFrame) then
		Settings.CreateMainFrame()
	end
	if(mainFrame:IsShown()) then
		Widgets.FadeOut(mainFrame)
	else
		Widgets.FadeIn(mainFrame)
		if(not sidebarBuilt) then
			Settings.BuildSidebar()
		end
	end
end
