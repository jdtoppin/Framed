local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- FrameSettingsBuilder
-- Shared factory that builds a scrollable settings panel for a
-- given unit type. Called by each thin panel registration file.
-- Group types (party/raid/battleground/worldraid) show extra
-- group-specific fields (spacing, orientation, growth direction).
-- ============================================================

F.FrameSettingsBuilder = {}

-- ============================================================
-- Constants
-- ============================================================

local GROUP_TYPES = {
	party        = true,
	raid         = true,
	battleground = true,
	worldraid    = true,
}

-- Unit types whose health bar uses oUF's full UpdateColor chain.
-- These frames do NOT show the Health Bar Color section in settings.
local NPC_FRAME_TYPES = {
	target       = true,
	targettarget = true,
	focus        = true,
	pet          = true,
	boss         = true,
}

-- Expose for card builders
F.FrameSettingsBuilder.GROUP_TYPES     = GROUP_TYPES
F.FrameSettingsBuilder.NPC_FRAME_TYPES = NPC_FRAME_TYPES

-- Widget heights (used for vertical layout accounting)
local SLIDER_H       = 26   -- labelH(14) + TRACK_THICKNESS(6) + 6
local SWITCH_H       = 22
local DROPDOWN_H     = 22
local CHECK_H        = 14
local PANE_TITLE_H   = 20   -- approx title font + separator + gap

-- Width for sliders and dropdowns inside the panel
local WIDGET_W       = 220

-- Shared layout constants for card builders
F.FrameSettingsBuilder.SLIDER_H     = SLIDER_H
F.FrameSettingsBuilder.SWITCH_H     = SWITCH_H
F.FrameSettingsBuilder.DROPDOWN_H   = DROPDOWN_H
F.FrameSettingsBuilder.CHECK_H      = CHECK_H
F.FrameSettingsBuilder.PANE_TITLE_H = PANE_TITLE_H
F.FrameSettingsBuilder.WIDGET_W     = WIDGET_W

-- ============================================================
-- Layout helpers
-- ============================================================

--- Place a widget at the running yOffset, anchored to the scroll content frame.
--- Returns the next yOffset after accounting for the widget's height.
--- @param widget  Frame   Widget to position
--- @param content Frame   Scroll content frame
--- @param yOffset number  Running yOffset (negative, relative to content)
--- @param height  number  Widget height
--- @return number nextYOffset
function F.FrameSettingsBuilder.PlaceWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

--- Place a heading at the given level and return the updated yOffset.
--- @param content Frame   Scroll content frame
--- @param text    string  Heading text
--- @param level   number  1, 2, or 3
--- @param yOffset number  Running yOffset
--- @param width?  number  Available width (needed for level 1 separator)
--- @return number nextYOffset
function F.FrameSettingsBuilder.PlaceHeading(content, text, level, yOffset, width)
	local heading, height = Widgets.CreateHeading(content, text, level, width)
	heading:ClearAllPoints()
	Widgets.SetPoint(heading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height
end

-- ============================================================
-- FrameSettingsBuilder.Create
-- ============================================================

--- Build and return a scrollable settings panel for unitType.
--- @param parent   Frame   Content parent provided by Settings.RegisterPanel
--- @param unitType string  Unit identifier (e.g. 'player', 'party', 'raid')
--- @return Frame
function F.FrameSettingsBuilder.Create(parent, unitType)
	-- ── Scroll frame wrapping the whole panel ─────────────────
	local parentW = parent._explicitWidth or parent:GetWidth() or 530
	local parentH = parent._explicitHeight or parent:GetHeight() or 400
	local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
	scroll:SetAllPoints(parent)

	local content = scroll:GetContentFrame()
	local width = parentW - C.Spacing.normal * 2

	-- Tag scroll frame with the preset it was built for (used by callers for invalidation)
	scroll._builtForPreset = F.Settings.GetEditingPreset()

	-- ── Config accessor helpers ────────────────────────────────
	local function getPresetName()
		return F.Settings.GetEditingPreset()
	end

	local function getConfig(key)
		if(F.EditCache and F.EditCache.IsActive()) then
			return F.EditCache.Get(unitType, key)
		end
		return F.Config:Get('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key)
	end
	local function setConfig(key, value)
		if(F.EditCache and F.EditCache.IsActive()) then
			F.EditCache.Set(unitType, key, value)
			return
		end
		F.Config:Set('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key, value)
		F.PresetManager.MarkCustomized(getPresetName())
	end

	-- ── CardGrid orchestrator (created first, positioned later) ──
	local grid = Widgets.CreateCardGrid(content, width)

	local function relayout()
		local oldContentH = content:GetHeight()
		local oldScroll   = scroll._scrollFrame:GetVerticalScroll()

		grid:AnimatedReflow()
		content:SetHeight(grid:GetTotalHeight())
		scroll:UpdateScrollRange()

		local growth = content:GetHeight() - oldContentH
		if(growth > 0) then
			local viewH    = scroll._scrollFrame:GetHeight()
			local maxScroll = math.max(0, content:GetHeight() - viewH)
			local newScroll = math.min(oldScroll + growth, maxScroll)
			scroll._scrollFrame:SetVerticalScroll(newScroll)
			scroll:_UpdateThumb()
		end
	end

	-- ── Pinned row: Preview (left) + Position & Layout (right) ──
	local pinnedRow = CreateFrame('Frame', nil, content)
	pinnedRow:SetPoint('TOPLEFT', content, 'TOPLEFT', 0, 0)
	pinnedRow:SetPoint('RIGHT', content, 'RIGHT', 0, 0)

	local previewCardW = math.floor(width * 0.55)
	local posCardW = width - previewCardW - C.Spacing.normal

	local previewCard = F.Settings.FramePreview.BuildPreviewCard(pinnedRow, previewCardW, unitType)
	if(previewCard) then
		previewCard:SetPoint('TOPLEFT', pinnedRow, 'TOPLEFT', 0, 0)
	end

	local posCard = F.SettingsCards.PositionAndLayout(pinnedRow, posCardW, unitType, getConfig, setConfig, relayout, true)
	posCard:SetPoint('TOPLEFT', pinnedRow, 'TOPLEFT', previewCardW + C.Spacing.normal, 0)

	local function updatePinnedRowHeight()
		local previewH = previewCard and previewCard:GetHeight() or 0
		local posH = posCard:GetHeight()
		pinnedRow:SetHeight(math.max(previewH, posH))
	end
	updatePinnedRowHeight()

	-- Register cards in display order (position card is now in pinned row)
	if(unitType == 'party' or unitType == 'raid') then
		grid:AddCard('sorting', 'Sorting', F.SettingsCards.Sorting, { unitType, getConfig, setConfig })
	end

	grid:AddCard('healthColor', 'Portrait & Health Color', F.SettingsCards.HealthColor, { unitType, getConfig, setConfig, relayout })

	grid:AddCard('shields', 'Shields & Absorbs', F.SettingsCards.ShieldsAndAbsorbs, { unitType, getConfig, setConfig })
	grid:AddCard('power', 'Power Bar', F.SettingsCards.PowerBar, { unitType, getConfig, setConfig })
	grid:AddCard('castbar', 'Cast Bar', F.SettingsCards.CastBar, { unitType, getConfig, setConfig, relayout })
	grid:AddCard('name', 'Name Text', F.SettingsCards.Name, { unitType, getConfig, setConfig, relayout })
	grid:AddCard('healthText', 'Health Text', F.SettingsCards.HealthText, { unitType, getConfig, setConfig, relayout })
	grid:AddCard('powerText', 'Power Text', F.SettingsCards.PowerText, { unitType, getConfig, setConfig, relayout })
	-- Icon cards — split by category, filtered by unit type relevance
	local GROUP_ICON_TYPES = { party = true, raid = true, arena = true }
	if(GROUP_ICON_TYPES[unitType]) then
		grid:AddCard('groupIcons', 'Group Icons', F.SettingsCards.GroupIcons, { unitType, getConfig, setConfig, relayout })
	end
	if(GROUP_ICON_TYPES[unitType]) then
		grid:AddCard('statusText', 'Status Text', F.SettingsCards.StatusText, { unitType, getConfig, setConfig, relayout })
	end
	grid:AddCard('statusIcons', 'Status Icons', F.SettingsCards.StatusIcons, { unitType, getConfig, setConfig, relayout })
	grid:AddCard('markers', 'Markers', F.SettingsCards.Markers, { unitType, getConfig, setConfig, relayout })
	if(unitType == 'party') then
		grid:AddCard('partyPets', 'Party Pets', F.SettingsCards.PartyPets, {})
	end

	-- ── Persist pin state ─────────────────────────────────────
	grid._onPinChanged = function(cardId, pinned)
		local path = 'general.pinnedCards.' .. unitType .. '.' .. cardId
		F.Config:Set(path, pinned or nil)
	end

	-- ── Pin state ──────────────────────────────────────────────
	local pinnedCards = F.Config:Get('general.pinnedCards.' .. unitType) or {}
	for cardId, isPinned in next, pinnedCards do
		if(isPinned) then
			grid:SetPinned(cardId, true)
		end
	end

	-- ── Initial layout ─────────────────────────────────────────
	local pinnedH = pinnedRow:GetHeight()
	grid:SetTopOffset(pinnedH + C.Spacing.normal)
	grid:Layout(0, parentH)
	content:SetHeight(grid:GetTotalHeight())

	-- ── Cancel animations on hide, re-layout on show ──────────
	scroll:HookScript('OnHide', function()
		grid:CancelAnimations()
		F.Settings.FramePreview.Destroy()
	end)
	scroll:HookScript('OnShow', function()
		grid:Layout(0, parentH, false)
		content:SetHeight(grid:GetTotalHeight())
	end)

	-- ── Lazy loading on scroll ─────────────────────────────────
	local function onScroll()
		local offset = scroll._scrollFrame:GetVerticalScroll()
		local viewH  = scroll._scrollFrame:GetHeight()
		grid:Layout(offset, viewH)
		content:SetHeight(grid:GetTotalHeight())
	end

	scroll._scrollFrame:HookScript('OnMouseWheel', function()
		C_Timer.After(0, onScroll)
	end)

	-- ── Re-layout on settings window resize ───────────────────
	F.EventBus:Register('SETTINGS_RESIZED', function(newW, newH)
		local gridW = newW - C.Spacing.normal * 2
		grid:SetWidth(gridW)
		content:SetHeight(grid:GetTotalHeight())
	end, 'FrameSettingsBuilder.resize.' .. unitType)

	F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', function()
		grid:RebuildCards()
		onScroll()
	end, 'FrameSettingsBuilder.resizeComplete.' .. unitType)

	-- ── Invalidate on preset change ────────────────────────────
	-- When the editing preset changes, mark this scroll frame stale so
	-- the Settings framework knows to rebuild on next panel activation.
	F.EventBus:Register('EDITING_PRESET_CHANGED', function(newPreset)
		scroll._builtForPreset = nil
		if(F.Settings and F.Settings._panelFrames) then
			-- Invalidate cache so panel rebuilds with new preset data
			for panelId, frame in next, F.Settings._panelFrames do
				if(frame == scroll) then
					F.Settings._panelFrames[panelId] = nil
					break
				end
			end
		end
	end, 'FrameSettingsBuilder.' .. unitType)

	return scroll
end
