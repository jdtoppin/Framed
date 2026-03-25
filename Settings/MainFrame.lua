local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local Settings = F.Settings

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
local HEADER_HEIGHT    = 24
local SUB_HEADER_H     = 32
local CLOSE_BTN_SIZE   = 20

local PREVIEW_ITEM_H   = 48
local PREVIEW_ITEM_GAP = 4

-- ============================================================
-- Preview State
-- ============================================================

local previewArea    = nil
local previewFrames  = {}

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

	if(not Settings._previewVisible) then
		previewArea:Hide()
		return
	end

	local info = nil
	for _, p in next, Settings._panels do
		if(p.id == Settings._activePanelId) then
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

-- Register with Framework so SetActivePanel can trigger preview refresh
Settings._refreshPreview = refreshPreview

-- ============================================================
-- Main Frame Constructor
-- ============================================================

--- Build the full settings window. Called once, lazily on first show.
function Settings.CreateMainFrame()
	if(Settings._mainFrame) then return end

	-- ── Outer window ──────────────────────────────────────────
	local frame, header = Widgets.CreateHeaderedFrame(UIParent, 'Framed', WINDOW_W, WINDOW_H)
	frame:SetFrameStrata('HIGH')
	frame:Hide()
	Settings._mainFrame = frame

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

	-- ── Preview toggle (header, left of close) ───────────────
	local previewBtn = Widgets.CreateButton(header, 'Preview', 'widget', 70, CLOSE_BTN_SIZE)
	previewBtn:ClearAllPoints()
	Widgets.SetPoint(previewBtn, 'RIGHT', closeBtn, 'LEFT', -C.Spacing.tight, 0)
	previewBtn:SetOnClick(function()
		Settings._previewVisible = not Settings._previewVisible
		if(Settings._previewVisible) then
			F.Preview.Enable()
		else
			F.Preview.Disable()
		end
		refreshPreview()
	end)
	previewBtn:SetWidgetTooltip('Toggle Preview', 'Show or hide the docked unit frame preview.')

	-- ── Edit Mode button (header, left of preview) ───────────
	local editModeBtn = Widgets.CreateButton(header, 'Edit Mode', 'widget', 80, CLOSE_BTN_SIZE)
	editModeBtn:ClearAllPoints()
	Widgets.SetPoint(editModeBtn, 'RIGHT', previewBtn, 'LEFT', -C.Spacing.tight, 0)
	editModeBtn:SetOnClick(function()
		Settings.Hide()
		if(F.EditMode and F.EditMode.Enter) then
			F.EditMode.Enter()
		end
	end)
	editModeBtn:SetWidgetTooltip('Edit Mode', 'Drag and resize unit frames directly on screen.')

	-- ── Resize button ─────────────────────────────────────────
	Widgets.CreateResizeButton(frame,
		WINDOW_MIN_W, WINDOW_MIN_H,
		WINDOW_MAX_W, WINDOW_MAX_H,
		nil,
		function(f, w, h)
			if(F.Config) then
				F.Config:Set('general.settingsSize', { w, h })
			end
			-- Update stored dimensions (anchors handle actual sizing)
			if(Settings._contentParent) then
				Settings._contentParent._explicitWidth  = w - SIDEBAR_W - PREVIEW_W
				Settings._contentParent._explicitHeight = h - HEADER_HEIGHT - SUB_HEADER_H
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
	Settings._headerPanelText = Widgets.CreateFontString(subHeader, C.Font.sizeNormal, C.Colors.textActive)
	Settings._headerPanelText:ClearAllPoints()
	Widgets.SetPoint(Settings._headerPanelText, 'LEFT', subHeader, 'LEFT', C.Spacing.normal, 0)
	Settings._headerPanelText:SetText('')

	-- ── Content area (right of sidebar, below sub-header) ─────
	local contentArea = CreateFrame('Frame', nil, frame)
	contentArea:ClearAllPoints()
	Widgets.SetPoint(contentArea, 'TOPLEFT',     subHeader, 'BOTTOMLEFT',  0,  0)
	Widgets.SetPoint(contentArea, 'BOTTOMRIGHT', frame,     'BOTTOMRIGHT', 0,  0)

	-- Panel container (plain Frame — each panel manages its own scrolling)
	-- Uses full anchor-based sizing (TOPLEFT + BOTTOMRIGHT) so child
	-- SetAllPoints resolves correctly in the layout engine.
	local panelContainer = CreateFrame('Frame', nil, contentArea)
	panelContainer:ClearAllPoints()
	Widgets.SetPoint(panelContainer, 'TOPLEFT',     contentArea, 'TOPLEFT',     0, 0)
	Widgets.SetPoint(panelContainer, 'BOTTOMRIGHT', contentArea, 'BOTTOMRIGHT', -PREVIEW_W, 0)

	Settings._contentParent = panelContainer
	-- Store explicit dimensions for panels to read during create()
	Settings._contentParent._explicitWidth  = WINDOW_W - SIDEBAR_W - PREVIEW_W
	Settings._contentParent._explicitHeight = WINDOW_H - HEADER_HEIGHT - SUB_HEADER_H

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
			-- Update stored dimensions (anchors handle actual sizing)
			if(Settings._contentParent) then
				Settings._contentParent._explicitWidth  = sz[1] - SIDEBAR_W - PREVIEW_W
				Settings._contentParent._explicitHeight = sz[2] - HEADER_HEIGHT - SUB_HEADER_H
			end
		end
	end

	-- ── Store sidebar reference for BuildSidebar ──────────────
	frame._sidebar = sidebar

	-- Enable preview by default when window is open
	F.Preview.Enable()
end
