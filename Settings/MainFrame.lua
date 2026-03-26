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
local function GetWindowMaxH()
	local screenH = UIParent:GetHeight()
	return math.floor(screenH * 0.75)
end

local SIDEBAR_W        = 170
local HEADER_HEIGHT    = 24
local SUB_HEADER_H     = 32
local CLOSE_BTN_SIZE   = 20

-- ============================================================
-- Main Frame Constructor
-- ============================================================

--- Build the full settings window. Called once, lazily on first show.
function Settings.CreateMainFrame()
	if(Settings._mainFrame) then return end

	-- ── Outer window ──────────────────────────────────────────
	local frame, header = Widgets.CreateHeaderedFrame(UIParent, 'Framed', WINDOW_W, WINDOW_H)
	frame:SetFrameStrata('HIGH')
	frame:EnableMouse(true)
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
	local closeBtn = Widgets.CreateIconButton(header, F.Media.GetIcon('Close'), CLOSE_BTN_SIZE)
	closeBtn:ClearAllPoints()
	Widgets.SetPoint(closeBtn, 'RIGHT', header, 'RIGHT', -C.Spacing.base, 0)
	closeBtn:SetOnClick(function()
		Widgets.FadeOut(frame)
	end)
	closeBtn:SetWidgetTooltip('Close')

	-- ── Fullscreen toggle button (left of close) ─────────────
	local FULLSCREEN_PAD = 20
	local fullscreenBtn = Widgets.CreateIconButton(header, F.Media.GetIcon('WindowMaximize'), CLOSE_BTN_SIZE)
	fullscreenBtn:ClearAllPoints()
	Widgets.SetPoint(fullscreenBtn, 'RIGHT', closeBtn, 'LEFT', -C.Spacing.tight, 0)

	local isFullscreen = false
	local savedSize, savedPoint
	local resizeBtn

	fullscreenBtn:SetOnClick(function()
		if(isFullscreen) then
			-- Restore previous size & position
			if(savedSize) then
				frame:SetSize(savedSize[1], savedSize[2])
			end
			if(savedPoint) then
				frame:ClearAllPoints()
				frame:SetPoint(savedPoint[1], UIParent, savedPoint[2], savedPoint[3], savedPoint[4])
			end
			fullscreenBtn._icon:SetTexture(F.Media.GetIcon('WindowMaximize'))
			fullscreenBtn:SetWidgetTooltip('Maximize')
			resizeBtn:Show()
			frame:SetResizable(true)
			isFullscreen = false
		else
			-- Save current size & position, then maximize
			savedSize = { frame:GetSize() }
			local point, _, relPoint, x, y = frame:GetPoint()
			savedPoint = { point, relPoint, x, y }

			local screenW = UIParent:GetWidth()
			local screenH = UIParent:GetHeight()
			local maxW = math.min(screenW - FULLSCREEN_PAD * 2, WINDOW_MAX_W)
			local maxH = math.min(screenH - FULLSCREEN_PAD * 2, GetWindowMaxH())
			frame:ClearAllPoints()
			frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
			frame:SetSize(maxW, maxH)
			fullscreenBtn._icon:SetTexture(F.Media.GetIcon('WindowRestore'))
			fullscreenBtn:SetWidgetTooltip('Restore')
			resizeBtn:Hide()
			frame:SetResizable(false)
			isFullscreen = true
		end

		-- Update stored dimensions
		local w, h = frame:GetSize()
		if(F.Config) then
			F.Config:Set('general.settingsSize', { w, h })
		end
		if(Settings._contentParent) then
			Settings._contentParent._explicitWidth  = w - SIDEBAR_W - C.Spacing.normal
			Settings._contentParent._explicitHeight = h - HEADER_HEIGHT - SUB_HEADER_H
		end
	end)
	fullscreenBtn:SetWidgetTooltip('Maximize')

	-- ── Edit Mode button (header, left of fullscreen) ────────
	local editModeBtn = Widgets.CreateButton(header, 'Edit Mode', 'widget', 80, CLOSE_BTN_SIZE)
	editModeBtn:ClearAllPoints()
	Widgets.SetPoint(editModeBtn, 'RIGHT', fullscreenBtn, 'LEFT', -C.Spacing.tight, 0)
	editModeBtn:SetOnClick(function()
		Settings.Hide()
		if(F.EditMode and F.EditMode.Enter) then
			F.EditMode.Enter()
		end
	end)
	editModeBtn:SetWidgetTooltip('Edit Mode', 'Drag and resize unit frames directly on screen.')

	-- ── Resize button ─────────────────────────────────────────
	resizeBtn = Widgets.CreateResizeButton(frame,
		WINDOW_MIN_W, WINDOW_MIN_H,
		WINDOW_MAX_W, GetWindowMaxH(),
		nil,
		function(f, w, h)
			-- Update max height bounds in case resolution changed
			f:SetResizeBounds(WINDOW_MIN_W, WINDOW_MIN_H, WINDOW_MAX_W, GetWindowMaxH())
			if(F.Config) then
				F.Config:Set('general.settingsSize', { w, h })
			end
			-- Update stored dimensions (anchors handle actual sizing)
			if(Settings._contentParent) then
				Settings._contentParent._explicitWidth  = w - SIDEBAR_W - C.Spacing.normal
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
	Widgets.SetPoint(panelContainer, 'TOPLEFT',     contentArea, 'TOPLEFT',     C.Spacing.normal, 0)
	Widgets.SetPoint(panelContainer, 'BOTTOMRIGHT', contentArea, 'BOTTOMRIGHT', 0, 0)

	Settings._contentParent = panelContainer
	-- Store explicit dimensions for panels to read during create()
	Settings._contentParent._explicitWidth  = WINDOW_W - SIDEBAR_W - C.Spacing.normal
	Settings._contentParent._explicitHeight = WINDOW_H - HEADER_HEIGHT - SUB_HEADER_H

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
				Settings._contentParent._explicitWidth  = sz[1] - SIDEBAR_W - C.Spacing.normal
				Settings._contentParent._explicitHeight = sz[2] - HEADER_HEIGHT - SUB_HEADER_H
			end
		end
	end

	-- ── Store sidebar reference for BuildSidebar ──────────────
	frame._sidebar = sidebar

	-- ── UI scale compensation (ElvUI-safe) ────────────────────
	Widgets.RegisterForUIScale(frame)
	frame:HookScript('OnShow', function()
		Widgets.ApplyUIScale(frame)
	end)

end
