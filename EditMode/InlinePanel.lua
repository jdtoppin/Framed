local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode

-- ============================================================
-- InlinePanel — Recycled settings panel attached to selected frame
-- ============================================================

local PANEL_WIDTH    = 380
local PANEL_MIN_H    = 300
local EDGE_MARGIN    = 16

local panel       = nil
local currentKey  = nil
local currentSide = nil   -- 'RIGHT' or 'LEFT'
local targetRef   = nil   -- reference to the frame the panel is anchored to
local dragTicker  = nil   -- hidden frame for OnUpdate during drag

local function DestroyPanel()
	if(dragTicker) then
		dragTicker:SetScript('OnUpdate', nil)
		dragTicker:Hide()
	end
	if(panel) then
		panel:Hide()
		panel:SetParent(EditMode._trashFrame)
		panel = nil
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

	-- Transparent container — the single card inside provides the visuals.
	-- The panel exists only to size, anchor, and eat mouse clicks so the
	-- bg click-catcher underneath doesn't deselect the frame.
	panel = CreateFrame('Frame', nil, overlay)
	panel:SetSize(PANEL_WIDTH, PANEL_MIN_H)
	panel:SetFrameLevel(overlay:GetFrameLevel() + 30)
	panel:SetFrameStrata('TOOLTIP')
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)

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

	-- ── Resolve unit type (group frames use their group key) ─
	local unitType = frameKey
	if(frameDef and frameDef.isGroup) then
		local info = C.PresetInfo[F.Settings.GetEditingPreset()]
		unitType = (info and info.groupKey) or frameKey
	end

	-- ── Render the Position & Layout card directly ──────────
	local widgetW = PANEL_WIDTH - C.Spacing.normal * 2
	local getCfg = function(path) return F.EditCache.Get(unitType, path) end
	local setCfg = function(path, value) F.EditCache.Set(unitType, path, value) end
	local onResize = function() end  -- Preview auto-updates via EDIT_CACHE_VALUE_CHANGED

	local card = F.SettingsCards.PositionAndLayout(panel, widgetW, unitType, getCfg, setCfg, onResize)
	card:ClearAllPoints()
	card:SetPoint('TOPLEFT', panel, 'TOPLEFT', C.Spacing.normal, -C.Spacing.normal)

	-- Fit panel height to card
	panel:SetHeight(card:GetHeight() + C.Spacing.normal * 2)

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
	DestroyPanel()
end, 'InlinePanel')
