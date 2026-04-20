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

local panel        = nil
local shield       = nil
local currentKey   = nil
local currentPreset = nil  -- preset the panel was built against
local currentSide  = nil   -- 'RIGHT' or 'LEFT'
local targetRef    = nil   -- reference to the frame the panel is anchored to
local dragTicker   = nil   -- hidden frame for OnUpdate during drag

local function DestroyPanel()
	if(dragTicker) then
		dragTicker:SetScript('OnUpdate', nil)
		dragTicker:Hide()
	end
	if(shield) then
		shield:Hide()
		shield:SetParent(EditMode._trashFrame)
		shield = nil
	end
	if(panel) then
		panel:Hide()
		panel:SetParent(EditMode._trashFrame)
		panel = nil
		currentKey = nil
		currentPreset = nil
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
	if(shield) then
		shield:ClearAllPoints()
		shield:SetAllPoints(panel)
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
	currentPreset = F.Settings.GetEditingPreset()

	-- Shield: SIBLING of the panel (child of overlay) at a strictly LOWER
	-- frame level than the panel. Sized and anchored to match the panel so
	-- it absorbs any click on the panel footprint that misses a widget.
	-- Keeping shield and panel as siblings (not ancestor/descendant) avoids
	-- any chance of the mouse-enabled shield shadowing its own descendant
	-- widgets via WoW's hit-testing quirks.
	shield = CreateFrame('Frame', nil, overlay)
	shield:SetSize(PANEL_WIDTH, PANEL_MIN_H)
	shield:SetFrameLevel(overlay:GetFrameLevel() + 79)
	shield:EnableMouse(true)
	-- Explicit no-op handler so the click is truly consumed — an
	-- EnableMouse(true) frame with no script handler can still let events
	-- fall through in some WoW contexts.
	shield:SetScript('OnMouseDown', function() end)

	-- Transparent container. Lives above the shield; its widget subtree
	-- provides all visuals and hit-testing. Panel itself is NOT mouse-
	-- enabled so it never competes with its own children for clicks.
	panel = CreateFrame('Frame', nil, overlay)
	panel:SetSize(PANEL_WIDTH, PANEL_MIN_H)
	panel:SetFrameLevel(overlay:GetFrameLevel() + 80)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(false)

	-- Position relative to target frame (absolute anchor to UIParent so
	-- slider-driven frame moves don't drag the panel along)
	targetRef = targetFrame
	currentSide = GetSmartSide(targetFrame)
	AnchorPanelAbsolute(currentSide)

	-- ── Render the Position & Layout card directly ──────────
	-- Each frame key owns its own unitConfigs node, so the EditCache is
	-- addressed by frameKey directly — do NOT remap to the preset's
	-- groupKey, or Boss/Pinned/Party/Arena all alias to the same entry.
	local unitType = frameKey
	local widgetW = PANEL_WIDTH - C.Spacing.normal * 2
	local getCfg = function(path) return F.EditCache.Get(unitType, path) end
	local setCfg = function(path, value) F.EditCache.Set(unitType, path, value) end
	local onResize = function() end  -- Preview auto-updates via EDIT_CACHE_VALUE_CHANGED

	local card = F.SettingsCards.PositionAndLayout(panel, widgetW, unitType, getCfg, setCfg, onResize)
	card:ClearAllPoints()
	card:SetPoint('TOPLEFT', panel, 'TOPLEFT', C.Spacing.normal, -C.Spacing.normal)

	-- Fit panel height to card, then sync shield to the final rect
	panel:SetHeight(card:GetHeight() + C.Spacing.normal * 2)
	shield:SetHeight(panel:GetHeight())
	shield:ClearAllPoints()
	shield:SetAllPoints(panel)

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

	-- Already showing for this frame AND preset — just update side, don't
	-- rebuild. If the preset changed (e.g. EDIT_MODE_PRESET_SWITCHED re-
	-- selects the same frame key after a preset swap), fall through and
	-- rebuild so the sliders/anchor/dropdowns read from the new preset's
	-- config instead of the old preset's cached state.
	if(panel and currentKey == frameKey and currentPreset == F.Settings.GetEditingPreset()) then
		UpdatePanelSide()
		return
	end

	-- If switching frames OR the editing preset changed, animate out then
	-- build fresh so the rebuilt panel reads the new preset's config.
	if(panel) then
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
