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
local EDGE_MARGIN    = 16

local panel        = nil
local currentKey   = nil
local contentFrame = nil
local activePanelId = nil  -- 'frame' or an aura group id
local currentSide  = nil   -- 'RIGHT' or 'LEFT'
local targetRef    = nil   -- reference to the frame the panel is anchored to
local dragTicker   = nil   -- hidden frame for OnUpdate during drag

--- All aura group panels in display order.
local AURA_GROUPS = {
	{ id = 'buffs',          label = 'Buffs' },
	{ id = 'debuffs',        label = 'Debuffs' },
	{ id = 'externals',      label = 'Externals' },
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
	if(dragTicker) then
		dragTicker:SetScript('OnUpdate', nil)
		dragTicker:Hide()
	end
	if(panel) then
		panel:Hide()
		panel:SetParent(EditMode._trashFrame)
		panel = nil
		contentFrame = nil
		currentKey = nil
		currentSide = nil
		targetRef = nil
	end
end

--- Determine the best side to show the panel relative to the frame.
--- @param targetFrame Frame
--- @return string anchorSide  'RIGHT' or 'LEFT'
local function GetSmartSide(targetFrame)
	local screenW = GetScreenWidth()
	-- Normalize frame edges to UIParent coordinate space so comparisons
	-- with GetScreenWidth() are valid even when the frame has SetScale()
	local scale = targetFrame:GetEffectiveScale()
	local uiScale = UIParent:GetEffectiveScale()
	local ratio = scale / uiScale
	local frameRight = ((targetFrame:GetRight() or 0) * ratio)
	local frameLeft = ((targetFrame:GetLeft() or 0) * ratio)

	-- Space available on each side
	local spaceRight = screenW - frameRight
	local spaceLeft = frameLeft

	if(spaceRight >= PANEL_WIDTH + EDGE_MARGIN) then
		return 'RIGHT'
	elseif(spaceLeft >= PANEL_WIDTH + EDGE_MARGIN) then
		return 'LEFT'
	else
		-- Neither side fits — pick whichever has more room
		return (spaceRight >= spaceLeft) and 'RIGHT' or 'LEFT'
	end
end

--- Compute absolute panel position from target frame and anchor to UIParent.
--- This prevents the panel from moving when the target frame is repositioned.
local function AnchorPanelAbsolute(side)
	if(not panel or not targetRef) then return end
	local tScale = targetRef:GetEffectiveScale()
	local uiScale = UIParent:GetEffectiveScale()
	local ratio = tScale / uiScale

	panel:ClearAllPoints()
	local topY = (targetRef:GetTop() or 0) * ratio
	if(side == 'RIGHT') then
		local rightX = (targetRef:GetRight() or 0) * ratio
		panel:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', rightX + EDGE_MARGIN, topY)
	else
		local leftX = (targetRef:GetLeft() or 0) * ratio
		panel:SetPoint('TOPRIGHT', UIParent, 'BOTTOMLEFT', leftX - EDGE_MARGIN, topY)
	end
end

--- Re-anchor the panel to the opposite side if needed.
local function UpdatePanelSide()
	if(not panel or not targetRef) then return end
	local newSide = GetSmartSide(targetRef)
	currentSide = newSide
	AnchorPanelAbsolute(newSide)
end

local function BuildPanel(frameKey, targetFrame)
	DestroyPanel()

	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	currentKey = frameKey

	-- Create panel frame
	panel = Widgets.CreateBorderedFrame(overlay, PANEL_WIDTH, PANEL_MIN_H, C.Colors.panel, C.Colors.border)
	panel:SetFrameLevel(overlay:GetFrameLevel() + 30)
	panel:SetFrameStrata('TOOLTIP')
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)  -- consume clicks so they don't deselect via overlay

	-- Position relative to target frame (absolute anchor to UIParent so
	-- slider-driven frame moves don't drag the panel along)
	targetRef = targetFrame
	currentSide = GetSmartSide(targetFrame)
	AnchorPanelAbsolute(currentSide)

	-- ── Resolve frame definition ────────────────────────────
	local frameDef = nil
	for _, def in next, EditMode.FRAME_KEYS do
		if(def.key == frameKey) then
			frameDef = def
			break
		end
	end

	local frameLabel = frameDef and frameDef.label or frameKey

	-- ── Panel selector dropdown ─────────────────────────────
	-- First item = frame settings, rest = aura groups
	local ddItems = {
		{ text = frameLabel .. ' Settings', value = 'frame' },
	}
	for _, group in next, AURA_GROUPS do
		ddItems[#ddItems + 1] = { text = group.label, value = group.id }
	end

	local panelDD = Widgets.CreateDropdown(panel, PANEL_WIDTH - C.Spacing.normal * 2)
	panelDD:SetItems(ddItems)
	panelDD:ClearAllPoints()
	panelDD:SetPoint('TOP', panel, 'TOP', 0, -C.Spacing.tight)

	-- ── Content area ────────────────────────────────────────
	local ddHeight = panelDD.GetHeight and panelDD:GetHeight() or 24
	contentFrame = CreateFrame('Frame', nil, panel)
	contentFrame:SetPoint('TOPLEFT', panelDD, 'BOTTOMLEFT', 0, -C.Spacing.tight)
	contentFrame:SetPoint('BOTTOMRIGHT', panel, 'BOTTOMRIGHT', 0, 0)
	contentFrame._explicitWidth = PANEL_WIDTH
	contentFrame._explicitHeight = PANEL_MIN_H - ddHeight - C.Spacing.tight * 2

	-- ── Clear content helper ────────────────────────────────
	local function ClearContent()
		for _, child in next, { contentFrame:GetChildren() } do
			child:Hide()
			child:SetParent(EditMode._trashFrame)
		end
	end

	-- ── Show frame settings ─────────────────────────────────
	local function ShowFrameSettings()
		activePanelId = 'frame'
		DimNonActiveAuras(currentKey, nil)
		ClearContent()

		local unitType = frameKey
		if(frameDef and frameDef.isGroup) then
			local info = C.PresetInfo[F.Settings.GetEditingPreset()]
			unitType = (info and info.groupKey) or frameKey
		end

		local scrollPanel = F.FrameSettingsBuilder.Create(contentFrame, unitType)
		scrollPanel:SetAllPoints(contentFrame)
		scrollPanel:Show()
	end

	-- ── Show aura group settings ────────────────────────────
	local function ShowAuraGroup(groupId)
		activePanelId = groupId
		ClearContent()

		local createFn = GetPanelCreate(groupId)
		if(not createFn) then
			local noPanel = Widgets.CreateFontString(contentFrame, C.Font.sizeNormal, C.Colors.textSecondary)
			noPanel:SetPoint('CENTER', contentFrame, 'CENTER', 0, 0)
			noPanel:SetText('Panel not available')
			DimNonActiveAuras(currentKey, groupId)
			return
		end

		local auraPanel = createFn(contentFrame)
		if(auraPanel) then
			auraPanel:ClearAllPoints()
			auraPanel:SetAllPoints(contentFrame)
			auraPanel._width = nil
			auraPanel._height = nil
			auraPanel:Show()
		end

		DimNonActiveAuras(currentKey, groupId)
	end

	-- ── Dropdown selection handler ──────────────────────────
	panelDD:SetOnSelect(function(value)
		if(value == 'frame') then
			ShowFrameSettings()
		else
			ShowAuraGroup(value)
		end
	end)

	-- Default: restore previous selection or frame settings
	local defaultPanel = activePanelId or 'frame'
	panelDD:SetValue(defaultPanel)
	if(defaultPanel == 'frame') then
		ShowFrameSettings()
	else
		ShowAuraGroup(defaultPanel)
	end

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

	-- Find the target frame — for group frames, use the catcher (which has
	-- correct size/position) since the real header may be tiny when solo
	local targetFrame = nil
	local isGroup = false
	for _, def in next, EditMode.FRAME_KEYS do
		if(def.key == frameKey) then
			isGroup = def.isGroup
			targetFrame = def.getter()
			break
		end
	end

	if(isGroup) then
		local catcher = EditMode.GetCatcher(frameKey)
		if(catcher) then
			targetFrame = catcher
		end
	end

	if(not targetFrame) then
		DestroyPanel()
		return
	end

	-- Already showing for this frame — just update side, don't rebuild
	if(panel and currentKey == frameKey) then
		UpdatePanelSide()
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

F.EventBus:Register('EDIT_MODE_DRAG_STARTED', function(frameKey)
	if(not panel or frameKey ~= currentKey) then return end
	-- Use a separate hidden frame for OnUpdate to avoid clobbering
	-- the panel's animation OnUpdate (Widgets.FadeIn)
	if(not dragTicker) then
		dragTicker = CreateFrame('Frame')
	end
	dragTicker:SetScript('OnUpdate', function()
		UpdatePanelSide()
	end)
	dragTicker:Show()
end, 'InlinePanel.dragStart')

F.EventBus:Register('EDIT_MODE_DRAG_STOPPED', function(frameKey)
	if(dragTicker) then
		dragTicker:SetScript('OnUpdate', nil)
		dragTicker:Hide()
	end
	-- Final side check after drag ends
	UpdatePanelSide()
end, 'InlinePanel.dragStop')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	-- Restore aura visibility
	if(currentKey) then
		DimNonActiveAuras(currentKey, nil)
	end
	activePanelId = nil
	DestroyPanel()
end, 'InlinePanel')
