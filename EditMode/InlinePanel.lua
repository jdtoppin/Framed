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
local activeAuraGroup = nil  -- current aura group panel id

--- All aura group panels in display order.
local AURA_GROUPS = {
	{ id = 'buffs',          label = 'Buffs' },
	{ id = 'debuffs',        label = 'Debuffs' },
	{ id = 'externals',      label = 'Externals' },
	{ id = 'raiddebuffs',    label = 'Raid Debuffs' },
	{ id = 'defensives',     label = 'Defensives' },
	{ id = 'targetedspells', label = 'Targeted Spells' },
	{ id = 'dispels',        label = 'Dispels' },
	{ id = 'missingbuffs',   label = 'Missing Buffs' },
	{ id = 'privateauras',   label = 'Private Auras' },
	{ id = 'lossofcontrol',  label = 'Loss of Control' },
	{ id = 'crowdcontrol',   label = 'Crowd Control' },
}

--- Find a registered panel's create function by its id.
--- @param panelId string
--- @return function|nil create
local function GetPanelCreate(panelId)
	for _, p in next, F.Settings._panels do
		if(p.id == panelId) then
			return p.create
		end
	end
	return nil
end

--- Dim all aura elements on a frame except the active group.
--- @param frameKey string  The selected frame key
--- @param activeGroup string|nil  The active aura group id, or nil to restore all
local function DimNonActiveAuras(frameKey, activeGroup)
	F.EventBus:Fire('EDIT_MODE_AURA_DIM', frameKey, activeGroup)
end

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
		-- Restore all aura visibility when switching to frame tab
		DimNonActiveAuras(currentKey, nil)
		activeAuraGroup = nil
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

		-- ── Aura group dropdown ─────────────────────────────
		local dropdownItems = {}
		for _, group in next, AURA_GROUPS do
			dropdownItems[#dropdownItems + 1] = { text = group.label, value = group.id }
		end

		local ddLabel = Widgets.CreateFontString(contentFrame, C.Font.sizeSmall, C.Colors.textSecondary)
		ddLabel:SetText('Aura Group:')
		ddLabel:ClearAllPoints()
		Widgets.SetPoint(ddLabel, 'TOPLEFT', contentFrame, 'TOPLEFT', C.Spacing.normal, -C.Spacing.normal)

		local auraDropdown = Widgets.CreateDropdown(contentFrame, PANEL_WIDTH - C.Spacing.normal * 2)
		auraDropdown:SetItems(dropdownItems)
		auraDropdown:ClearAllPoints()
		Widgets.SetPoint(auraDropdown, 'TOPLEFT', ddLabel, 'BOTTOMLEFT', 0, -C.Spacing.small)

		-- ── Aura settings content area ──────────────────────
		local auraContent = CreateFrame('Frame', nil, contentFrame)
		auraContent:ClearAllPoints()
		Widgets.SetPoint(auraContent, 'TOPLEFT', auraDropdown, 'BOTTOMLEFT', 0, -C.Spacing.normal)
		auraContent:SetPoint('BOTTOMRIGHT', contentFrame, 'BOTTOMRIGHT', 0, 0)
		auraContent._explicitWidth = PANEL_WIDTH - C.Spacing.normal * 2
		auraContent._explicitHeight = PANEL_MIN_H - TAB_HEIGHT - 60

		local function LoadAuraGroup(groupId)
			-- Clear previous aura panel
			for _, child in next, { auraContent:GetChildren() } do
				child:Hide()
				child:SetParent(nil)
			end

			activeAuraGroup = groupId

			-- Find the registered panel's create function
			local createFn = GetPanelCreate(groupId)
			if(not createFn) then
				local noPanel = Widgets.CreateFontString(auraContent, C.Font.sizeNormal, C.Colors.textSecondary)
				noPanel:SetPoint('CENTER', auraContent, 'CENTER', 0, 0)
				noPanel:SetText('Panel not available')
				return
			end

			-- Build the aura settings panel inside our content area
			local auraPanel = createFn(auraContent)
			if(auraPanel) then
				auraPanel:ClearAllPoints()
				auraPanel:SetAllPoints(auraContent)
				auraPanel._width = nil
				auraPanel._height = nil
				auraPanel:Show()
			end

			-- Dim non-active aura groups on the live frame
			DimNonActiveAuras(currentKey, groupId)
		end

		auraDropdown:SetOnSelect(function(value)
			LoadAuraGroup(value)
		end)

		-- Default to first group or restore previous selection
		local defaultGroup = activeAuraGroup or AURA_GROUPS[1].id
		auraDropdown:SetValue(defaultGroup)
		LoadAuraGroup(defaultGroup)

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
	-- Restore aura visibility
	if(currentKey) then
		DimNonActiveAuras(currentKey, nil)
	end
	activeAuraGroup = nil
	DestroyPanel()
end, 'InlinePanel')
