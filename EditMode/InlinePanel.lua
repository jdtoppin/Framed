local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode
local EditCache = F.EditCache

-- ============================================================
-- InlinePanel — Recycled settings panel attached to selected frame
-- ============================================================

local PANEL_WIDTH    = 380
local PANEL_MIN_H    = 300
local PANEL_MAX_H    = 600
local TAB_HEIGHT     = 28
local TAB_GAP        = 2
local EDGE_MARGIN    = 16

local panel       = nil
local activeTab   = nil   -- 'frame' or 'auras'
local currentKey  = nil
local contentFrame = nil

local function DestroyPanel()
	if(panel) then
		panel:Hide()
		panel:SetParent(nil)
		panel = nil
		contentFrame = nil
		activeTab = nil
		currentKey = nil
	end
end

--- Determine the best side to show the panel relative to the frame.
--- @param targetFrame Frame
--- @return string anchorSide  'RIGHT' or 'LEFT'
local function GetSmartSide(targetFrame)
	local screenW = GetScreenWidth()
	local frameRight = targetFrame:GetRight() or 0
	local frameLeft = targetFrame:GetLeft() or 0

	-- Space available on each side
	local spaceRight = screenW - frameRight
	local spaceLeft = frameLeft

	if(spaceRight >= PANEL_WIDTH + EDGE_MARGIN) then
		return 'RIGHT'
	elseif(spaceLeft >= PANEL_WIDTH + EDGE_MARGIN) then
		return 'LEFT'
	else
		-- Default to right, panel will overlap
		return 'RIGHT'
	end
end

local function BuildPanel(frameKey, targetFrame)
	DestroyPanel()

	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	currentKey = frameKey

	-- Create panel frame
	panel = Widgets.CreateBorderedFrame(overlay, PANEL_WIDTH, PANEL_MIN_H, C.Colors.panel, C.Colors.border)
	panel:SetFrameLevel(overlay:GetFrameLevel() + 30)

	-- Position relative to target frame
	local side = GetSmartSide(targetFrame)
	panel:ClearAllPoints()
	if(side == 'RIGHT') then
		panel:SetPoint('TOPLEFT', targetFrame, 'TOPRIGHT', EDGE_MARGIN, 0)
	else
		panel:SetPoint('TOPRIGHT', targetFrame, 'TOPLEFT', -EDGE_MARGIN, 0)
	end

	-- ── Tab buttons ─────────────────────────────────────────
	local frameDef = nil
	for _, def in next, EditMode.FRAME_KEYS do
		if(def.key == frameKey) then
			frameDef = def
			break
		end
	end

	local frameTabBtn = Widgets.CreateButton(panel, frameDef and frameDef.label or frameKey, 'accent', PANEL_WIDTH / 2 - TAB_GAP, TAB_HEIGHT)
	frameTabBtn:SetPoint('TOPLEFT', panel, 'TOPLEFT', 0, 0)

	local aurasTabBtn = Widgets.CreateButton(panel, 'Auras', 'widget', PANEL_WIDTH / 2 - TAB_GAP, TAB_HEIGHT)
	aurasTabBtn:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', 0, 0)

	-- ── Content area ────────────────────────────────────────
	contentFrame = CreateFrame('Frame', nil, panel)
	contentFrame:SetPoint('TOPLEFT', panel, 'TOPLEFT', 0, -TAB_HEIGHT - 2)
	contentFrame:SetPoint('BOTTOMRIGHT', panel, 'BOTTOMRIGHT', 0, 0)
	contentFrame._explicitWidth = PANEL_WIDTH
	contentFrame._explicitHeight = PANEL_MIN_H - TAB_HEIGHT - 2

	-- ── Build frame settings tab content ────────────────────
	local function ShowFrameTab()
		activeTab = 'frame'
		-- Clear content
		for _, child in next, { contentFrame:GetChildren() } do
			child:Hide()
			child:SetParent(nil)
		end

		-- Use FrameSettingsBuilder to create the same content as sidebar
		local unitType = frameKey
		-- Group frames use their config key
		if(frameDef and frameDef.isGroup) then
			local info = C.PresetInfo[F.Settings.GetEditingPreset()]
			unitType = (info and info.groupKey) or frameKey
		end

		local scrollPanel = F.FrameSettingsBuilder.Create(contentFrame, unitType)
		scrollPanel:SetAllPoints(contentFrame)
		scrollPanel:Show()

		-- Update tab visual
		frameTabBtn._label:SetTextColor(1, 1, 1, 1)
		aurasTabBtn._label:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3], 1)
	end

	local function ShowAurasTab()
		activeTab = 'auras'
		-- Clear content
		for _, child in next, { contentFrame:GetChildren() } do
			child:Hide()
			child:SetParent(nil)
		end

		-- TODO: Build auras dropdown + aura settings panel
		-- For now, show placeholder
		local placeholder = Widgets.CreateFontString(contentFrame, C.Font.sizeNormal, C.Colors.textSecondary)
		placeholder:SetPoint('CENTER', contentFrame, 'CENTER', 0, 0)
		placeholder:SetText('Auras tab - coming soon')

		-- Update tab visual
		aurasTabBtn._label:SetTextColor(1, 1, 1, 1)
		frameTabBtn._label:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3], 1)
	end

	frameTabBtn:SetOnClick(function() ShowFrameTab() end)
	aurasTabBtn:SetOnClick(function() ShowAurasTab() end)

	-- Default to frame tab
	ShowFrameTab()

	-- Slide in animation
	Widgets.FadeIn(panel)
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
	if(not frameKey) then
		DestroyPanel()
		return
	end

	-- Find the target frame
	local targetFrame = nil
	for _, def in next, EditMode.FRAME_KEYS do
		if(def.key == frameKey) then
			targetFrame = def.getter()
			break
		end
	end

	if(not targetFrame) then
		DestroyPanel()
		return
	end

	-- If switching frames, animate out then build new
	if(panel and currentKey ~= frameKey) then
		Widgets.FadeOut(panel, C.Animation.durationFast, function()
			BuildPanel(frameKey, targetFrame)
		end)
	else
		BuildPanel(frameKey, targetFrame)
	end
end, 'InlinePanel')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyPanel()
end, 'InlinePanel')
