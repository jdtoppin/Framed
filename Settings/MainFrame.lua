local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local Settings = F.Settings

-- ============================================================
-- Window Constants
-- ============================================================

local WINDOW_MIN_W     = 700
local WINDOW_MIN_H     = 450

local function GetScreenPixelSize()
	local scale = UIParent:GetEffectiveScale()
	return UIParent:GetWidth() * scale, UIParent:GetHeight() * scale
end

local function GetWindowMaxW()
	local screenPx = select(1, GetScreenPixelSize())
	return math.floor(screenPx * 0.85)
end

local function GetWindowMaxH()
	local screenPx = select(2, GetScreenPixelSize())
	return math.floor(screenPx * 0.85)
end

-- Default size: 50% of screen width/height, clamped to min
local function GetDefaultSize()
	local sw, sh = GetScreenPixelSize()
	local w = math.max(WINDOW_MIN_W, math.floor(sw * 0.5))
	local h = math.max(WINDOW_MIN_H, math.floor(sh * 0.5))
	return w, h
end

local WINDOW_W, WINDOW_H

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
	WINDOW_W, WINDOW_H = GetDefaultSize()
	local initW = math.min(WINDOW_W, GetWindowMaxW())
	local initH = math.min(WINDOW_H, GetWindowMaxH())
	local frame, header = Widgets.CreateHeaderedFrame(UIParent, 'Framed', initW, initH)
	frame:SetFrameStrata('HIGH')
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
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
	closeBtn:SetBackdrop(nil)
	Widgets.SetupAccentHover(closeBtn, closeBtn._icon, true)

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
			local maxW = math.min(screenW - FULLSCREEN_PAD * 2, GetWindowMaxW())
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
			Settings._contentParent._explicitHeight = h - HEADER_HEIGHT - SUB_HEADER_H - C.Spacing.normal
			F.EventBus:Fire('SETTINGS_RESIZED', Settings._contentParent._explicitWidth, Settings._contentParent._explicitHeight)
		end
	end)
	fullscreenBtn:SetWidgetTooltip('Maximize')
	fullscreenBtn:SetBackdrop(nil)
	Widgets.SetupAccentHover(fullscreenBtn, fullscreenBtn._icon, true)

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
	editModeBtn:SetBackdrop(nil)
	Widgets.SetupAccentHover(editModeBtn, editModeBtn._label, false)

	-- ── Resize button ─────────────────────────────────────────
	local lastResizeTime = 0
	local RESIZE_THROTTLE = 0.05
	resizeBtn = Widgets.CreateResizeButton(frame,
		WINDOW_MIN_W, WINDOW_MIN_H,
		GetWindowMaxW(), GetWindowMaxH(),
		function(f, w, h)
			-- Live resize: update dimensions and fire throttled
			if(Settings._contentParent) then
				Settings._contentParent._explicitWidth  = w - SIDEBAR_W - C.Spacing.normal
				Settings._contentParent._explicitHeight = h - HEADER_HEIGHT - SUB_HEADER_H - C.Spacing.normal
				local now = GetTime()
				if(now - lastResizeTime >= RESIZE_THROTTLE) then
					lastResizeTime = now
					F.EventBus:Fire('SETTINGS_RESIZED', Settings._contentParent._explicitWidth, Settings._contentParent._explicitHeight)
				end
			end
		end,
		function(f, w, h)
			-- On release: save size, fire final resize + rebuild
			f:SetResizeBounds(WINDOW_MIN_W, WINDOW_MIN_H, GetWindowMaxW(), GetWindowMaxH())
			if(F.Config) then
				F.Config:Set('general.settingsSize', { w, h })
			end
			if(Settings._contentParent) then
				Settings._contentParent._explicitWidth  = w - SIDEBAR_W - C.Spacing.normal
				Settings._contentParent._explicitHeight = h - HEADER_HEIGHT - SUB_HEADER_H - C.Spacing.normal
				F.EventBus:Fire('SETTINGS_RESIZED', Settings._contentParent._explicitWidth, Settings._contentParent._explicitHeight)
				F.EventBus:Fire('SETTINGS_RESIZE_COMPLETE')
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
	local sidebar = Widgets.CreateBorderedFrame(frame, SIDEBAR_W, initH - HEADER_HEIGHT, C.Colors.background, C.Colors.border)
	sidebar:ClearAllPoints()
	Widgets.SetPoint(sidebar, 'TOPLEFT',     frame, 'TOPLEFT',     0, -HEADER_HEIGHT)
	Widgets.SetPoint(sidebar, 'BOTTOMRIGHT', frame, 'BOTTOMLEFT',  SIDEBAR_W, 0)
	sidebar._height = nil  -- height driven by anchors; prevent ReSize from stomping it
	sidebar:SetClipsChildren(true)

	-- ── Content area (right of sidebar, below title bar) ──────
	local contentArea = CreateFrame('Frame', nil, frame)
	contentArea:ClearAllPoints()
	Widgets.SetPoint(contentArea, 'TOPLEFT',     sidebar, 'TOPRIGHT',   C.Spacing.normal, -C.Spacing.normal)
	Widgets.SetPoint(contentArea, 'BOTTOMRIGHT', frame,   'BOTTOMRIGHT', 0,  0)

	-- ── Panel title card (top of content area) ────────────────
	local titleCard = CreateFrame('Frame', nil, contentArea, 'BackdropTemplate')
	titleCard:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	local bg = C.Colors.card
	local border = C.Colors.cardBorder
	titleCard:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	titleCard:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
	titleCard:ClearAllPoints()
	Widgets.SetPoint(titleCard, 'TOPLEFT',  contentArea, 'TOPLEFT',  0, 0)
	Widgets.SetPoint(titleCard, 'TOPRIGHT', contentArea, 'TOPRIGHT', -C.Spacing.normal * 2, 0)
	titleCard:SetHeight(SUB_HEADER_H)

	-- Faded accent bar underlining the panel title, separating header from content
	Widgets.CreateAccentBar(titleCard, 'bottom')

	Settings._headerPanelText = Widgets.CreateFontString(titleCard, C.Font.sizeNormal, C.Colors.textActive)
	Settings._headerPanelText:ClearAllPoints()
	Widgets.SetPoint(Settings._headerPanelText, 'LEFT', titleCard, 'LEFT', C.Spacing.normal, 0)
	Settings._headerPanelText:SetText('')

	-- ── Inline unit-type dropdown for aura panels ───────────────
	-- Renders as "/ Player Frame ▾" immediately after the breadcrumb.
	-- Hidden by default; Framework toggles visibility per panel.
	Settings._headerUnitTypeDD = Widgets.CreateInlineDropdown(titleCard)
	Settings._headerUnitTypeDD:ClearAllPoints()
	Widgets.SetPoint(Settings._headerUnitTypeDD, 'LEFT', Settings._headerPanelText, 'RIGHT', 4, 0)
	Settings._headerUnitTypeDD:Hide()

	-- ── Copy-to control (label + dropdown + Copy button) ───────
	-- Visible only on aura panels that registered a configKey.
	-- Framework.activateAuraHeaderControls populates the dropdown and
	-- wires the button per panel.
	Settings._headerCopyToLabel = Widgets.CreateFontString(titleCard, C.Font.sizeNormal, C.Colors.textNormal)
	Settings._headerCopyToLabel:ClearAllPoints()
	Widgets.SetPoint(Settings._headerCopyToLabel, 'LEFT', Settings._headerUnitTypeDD, 'RIGHT', 12, 0)
	Settings._headerCopyToLabel:SetText('Copy to')
	Settings._headerCopyToLabel:Hide()

	Settings._headerCopyToDD = Widgets.CreateInlineDropdown(titleCard)
	Settings._headerCopyToDD:ClearAllPoints()
	Widgets.SetPoint(Settings._headerCopyToDD, 'LEFT', Settings._headerCopyToLabel, 'RIGHT', 4, 0)
	Settings._headerCopyToDD:Hide()

	Settings._headerCopyToBtn = Widgets.CreateButton(titleCard, 'Copy', 'accent', 52, 20)
	Settings._headerCopyToBtn:ClearAllPoints()
	Widgets.SetPoint(Settings._headerCopyToBtn, 'LEFT', Settings._headerCopyToDD, 'RIGHT', 6, 0)
	Settings._headerCopyToBtn:Hide()

	-- ── Drill-in breadcrumb suffix (e.g. "  >  Major Cooldowns") ──
	-- Shown only while editing a specific indicator inside an aura panel.
	Settings._headerIndicatorText = Widgets.CreateFontString(titleCard, C.Font.sizeNormal, C.Colors.textActive)
	Settings._headerIndicatorText:ClearAllPoints()
	Widgets.SetPoint(Settings._headerIndicatorText, 'LEFT', Settings._headerUnitTypeDD, 'RIGHT', 8, 0)
	Settings._headerIndicatorText:SetText('')
	Settings._headerIndicatorText:Hide()

	Settings._headerPresetText = Widgets.CreateFontString(titleCard, C.Font.sizeNormal, C.Colors.accent)
	Settings._headerPresetText:ClearAllPoints()
	Widgets.SetPoint(Settings._headerPresetText, 'RIGHT', titleCard, 'RIGHT', -C.Spacing.normal, 0)
	Settings._headerPresetText:SetText('')
	Settings._headerPresetText:Hide()

	-- Preview anchor (populated by AuraPreview when an aura panel is active)
	Settings._headerPreviewAnchor = titleCard

	-- Panel container (below title card — each panel manages its own scrolling)
	-- Uses full anchor-based sizing (TOPLEFT + BOTTOMRIGHT) so child
	-- SetAllPoints resolves correctly in the layout engine.
	local panelContainer = CreateFrame('Frame', nil, contentArea)
	panelContainer:ClearAllPoints()
	Widgets.SetPoint(panelContainer, 'TOPLEFT',     titleCard,   'BOTTOMLEFT',  0, 0)
	Widgets.SetPoint(panelContainer, 'BOTTOMRIGHT', contentArea, 'BOTTOMRIGHT', 0, 0)

	Settings._contentParent = panelContainer
	-- Store explicit dimensions for panels to read during create()
	Settings._contentParent._explicitWidth  = initW - SIDEBAR_W - C.Spacing.normal
	Settings._contentParent._explicitHeight = initH - HEADER_HEIGHT - SUB_HEADER_H - C.Spacing.normal

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
			local maxH = GetWindowMaxH()
			frame:SetSize(math.min(sz[1], GetWindowMaxW()), math.min(sz[2], maxH))
			-- Update stored dimensions (anchors handle actual sizing)
			if(Settings._contentParent) then
				Settings._contentParent._explicitWidth  = sz[1] - SIDEBAR_W - C.Spacing.normal
				Settings._contentParent._explicitHeight = sz[2] - HEADER_HEIGHT - SUB_HEADER_H - C.Spacing.normal
				F.EventBus:Fire('SETTINGS_RESIZED', Settings._contentParent._explicitWidth, Settings._contentParent._explicitHeight)
			end
		end
	end

	-- ── Store sidebar reference for BuildSidebar ──────────────
	frame._sidebar = sidebar

	-- ── UI scale compensation (ElvUI-safe) ────────────────────
	Widgets.RegisterForUIScale(frame)
	frame:HookScript('OnShow', function()
		Widgets.ApplyUIScale(frame)
		-- Clamp height to screen on every show (scale may have changed)
		local maxH = GetWindowMaxH()
		local _, h = frame:GetSize()
		if(h > maxH) then
			frame:SetHeight(maxH)
			if(Settings._contentParent) then
				local contentH = maxH - HEADER_HEIGHT - SUB_HEADER_H - C.Spacing.normal
				Settings._contentParent:SetHeight(contentH)
				Settings._contentParent._explicitHeight = contentH
				F.EventBus:Fire('SETTINGS_RESIZED', Settings._contentParent._explicitWidth, Settings._contentParent._explicitHeight)
			end
		end
	end)

	frame:HookScript('OnHide', function()
		-- Just clear the pointer — previews are parented to their panel's
		-- scroll content and hide with the settings window.  Destroying them
		-- orphans the frame while _ownedPreview still references it.
		Settings._auraPreview = nil
	end)

end
