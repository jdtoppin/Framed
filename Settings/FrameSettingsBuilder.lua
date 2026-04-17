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
-- Summary Card
-- ============================================================

local SUMMARY_ROW_H = 16
local DOT_SIZE = 6

local GROUP_ICON_TYPES = { party = true, raid = true, arena = true }

local function getSummaryItems(unitType)
	local items = {
		{ id = 'position',    label = 'Position & Layout' },
		{ id = 'healthColor', label = 'Portrait & Color' },
		{ id = 'shields',     label = 'Shields & Absorbs', keys = { 'health.healPrediction', 'health.damageAbsorb' } },
		{ id = 'power',       label = 'Power Bar',         key = 'showPower' },
		{ id = 'castbar',     label = 'Cast Bar',          key = 'showCastBar' },
		{ id = 'name',        label = 'Name Text',         key = 'showName' },
		{ id = 'healthText',  label = 'Health Text',       key = 'health.showText' },
		{ id = 'powerText',   label = 'Power Text',        key = 'power.showText' },
	}
	if(GROUP_ICON_TYPES[unitType]) then
		items[#items + 1] = { id = 'groupIcons',  label = 'Group Icons' }
		items[#items + 1] = { id = 'statusText',  label = 'Status Text',  key = 'statusText.enabled' }
	end
	items[#items + 1] = { id = 'statusIcons', label = 'Status Icons' }
	items[#items + 1] = { id = 'markers',     label = 'Markers' }
	if(unitType == 'party' or unitType == 'raid') then
		items[#items + 1] = { id = 'sorting', label = 'Sorting' }
	end
	return items
end

local function isFeatureEnabled(getConfig, item)
	if(item.key) then
		return getConfig(item.key) and true or false
	end
	if(item.keys) then
		for _, k in next, item.keys do
			if(getConfig(k)) then return true end
		end
		return false
	end
	return nil
end

function F.FrameSettingsBuilder.BuildSummaryCard(parent, width, unitType, getConfig)
	local card = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	card:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
		insets   = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	local bg = C.Colors.card
	local border = C.Colors.cardBorder
	card:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	card:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
	card:SetWidth(width)

	local pad = 10
	local items = getSummaryItems(unitType)
	local cols = 2
	local colW = math.floor((width - pad * 2 - C.Spacing.tight) / cols)
	local rows = math.ceil(#items / cols)

	local rowFrames = {}

	for i, item in next, items do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local x = pad + col * (colW + C.Spacing.tight)

		local rowFrame = CreateFrame('Button', nil, card)
		rowFrame:SetSize(colW, SUMMARY_ROW_H)
		rowFrame:ClearAllPoints()
		rowFrame:SetPoint('TOPLEFT', card, 'TOPLEFT', x, -pad + (-row * (SUMMARY_ROW_H + 2)))

		local enabled = isFeatureEnabled(getConfig, item)

		local dot = rowFrame:CreateTexture(nil, 'ARTWORK')
		dot:SetSize(DOT_SIZE, DOT_SIZE)
		dot:SetPoint('LEFT', rowFrame, 'LEFT', 0, 0)

		if(enabled == nil) then
			local tc = C.Colors.textNormal
			dot:SetColorTexture(tc[1], tc[2], tc[3], 0.5)
		elseif(enabled) then
			dot:SetColorTexture(0.2, 0.8, 0.3, 1)
		else
			dot:SetColorTexture(0.4, 0.4, 0.4, 0.4)
		end

		local label = Widgets.CreateFontString(rowFrame, C.Font.sizeSmall,
			enabled == false and C.Colors.textDisabled or C.Colors.textNormal)
		label:SetPoint('LEFT', dot, 'RIGHT', 4, 0)
		label:SetText(item.label)

		rowFrame:SetScript('OnClick', function()
			if(card._onItemClicked) then
				card._onItemClicked(item.id)
			end
		end)

		rowFrame:SetScript('OnEnter', function(self)
			label:SetTextColor(1, 1, 1, 1)
		end)
		rowFrame:SetScript('OnLeave', function(self)
			local tc = enabled == false and C.Colors.textDisabled or C.Colors.textNormal
			label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end)

		rowFrame._dot = dot
		rowFrame._label = label
		rowFrame._item = item
		rowFrames[#rowFrames + 1] = rowFrame
	end

	local totalH = pad * 2 + rows * SUMMARY_ROW_H + (rows - 1) * 2
	card:SetHeight(totalH)
	card._rowFrames = rowFrames

	return card
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

	-- ── Pinned preview card (parented to outer scroll container so it doesn't scroll) ──
	local previewCard = F.Settings.FramePreview.BuildPreviewCard(scroll, width, unitType)
	previewCard:ClearAllPoints()
	Widgets.SetPoint(previewCard, 'TOPLEFT', scroll, 'TOPLEFT', 0, -C.Spacing.normal)

	-- ── Summary card (pinned below preview) ──────────────────
	local summaryCard = F.FrameSettingsBuilder.BuildSummaryCard(
		scroll, width, unitType, getConfig
	)
	summaryCard:ClearAllPoints()
	Widgets.SetPoint(summaryCard, 'TOPLEFT', previewCard, 'BOTTOMLEFT', 0, -C.Spacing.tight)

	local pinnedH = previewCard:GetHeight() + C.Spacing.tight + summaryCard:GetHeight() + C.Spacing.normal

	-- Push the internal ScrollFrame down below the pinned cards
	scroll._scrollFrame:ClearAllPoints()
	scroll._scrollFrame:SetPoint('TOPLEFT', scroll, 'TOPLEFT', 0, -(pinnedH + C.Spacing.normal))
	scroll._scrollFrame:SetPoint('BOTTOMRIGHT', scroll, 'BOTTOMRIGHT', -7, 0)

	-- Forward mouse wheel from pinned area to vertical scroll
	local function forwardMouseWheel(_, delta)
		local sf = scroll._scrollFrame
		local maxScroll = math.max(0, content:GetHeight() - sf:GetHeight())
		local cur = sf:GetVerticalScroll()
		sf:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 40)))
		scroll:_UpdateThumb()
	end
	previewCard:EnableMouseWheel(true)
	previewCard:SetScript('OnMouseWheel', forwardMouseWheel)
	summaryCard:EnableMouseWheel(true)
	summaryCard:SetScript('OnMouseWheel', forwardMouseWheel)

	-- ── CardGrid orchestrator ──
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

	-- ── Active card tracking ──────────────────────────────────
	local activeCardId = nil
	local activeAccentBar = nil
	local FADE_DUR = C.Animation.durationFast

	local defaultBg = C.Colors.card
	local activeBg  = { 0.16, 0.16, 0.16, 1 }
	local hoverBg   = { 0.14, 0.14, 0.14, 1 }

	-- Track each card's current visual RGBA so animations always start from truth
	local cardBgState = {}

	local function getCardBg(card)
		return cardBgState[card] or defaultBg
	end

	local function animateCardBg(card, toBg)
		local from = getCardBg(card)
		local to = toBg
		cardBgState[card] = to
		Widgets.StartAnimation(card, 'cardBg', 0, 1, FADE_DUR, function(self, t)
			self:SetBackdropColor(
				from[1] + (to[1] - from[1]) * t,
				from[2] + (to[2] - from[2]) * t,
				from[3] + (to[3] - from[3]) * t,
				(from[4] or 1) + ((to[4] or 1) - (from[4] or 1)) * t
			)
		end)
	end

	local function animateTextColor(card, fs, fromC, toC)
		Widgets.StartAnimation(card, 'textColor', 0, 1, FADE_DUR, function(self, t)
			fs:SetTextColor(
				fromC[1] + (toC[1] - fromC[1]) * t,
				fromC[2] + (toC[2] - fromC[2]) * t,
				fromC[3] + (toC[3] - fromC[3]) * t,
				(fromC[4] or 1) + ((toC[4] or 1) - (fromC[4] or 1)) * t
			)
		end)
	end

	local function setActiveCard(cardId)
		if(activeCardId == cardId) then return end

		local hadPrev = activeCardId ~= nil

		-- Deactivate previous card
		if(activeCardId) then
			local prev = grid._cardIndex[activeCardId]
			if(prev and prev.built and prev.card) then
				animateCardBg(prev.card, defaultBg)
				if(prev._titleFS) then
					animateTextColor(prev.card, prev._titleFS, C.Colors.textActive, C.Colors.textNormal)
				end
			end
		end

		activeCardId = cardId

		-- Activate new card
		if(cardId) then
			local entry = grid._cardIndex[cardId]
			if(entry and entry.built and entry.card) then
				animateCardBg(entry.card, activeBg)
				if(entry._titleFS) then
					animateTextColor(entry.card, entry._titleFS, C.Colors.textNormal, C.Colors.textActive)
				end

				if(not activeAccentBar) then
					activeAccentBar = CreateFrame('Frame', nil, scroll)
					activeAccentBar:SetWidth(3)
					local tex = activeAccentBar:CreateTexture(nil, 'OVERLAY')
					tex:SetAllPoints(activeAccentBar)
					local ac = C.Colors.accent
					tex:SetColorTexture(ac[1], ac[2], ac[3], 1)
					activeAccentBar._tex = tex
				end
				activeAccentBar:SetParent(entry.card)
				activeAccentBar:ClearAllPoints()
				activeAccentBar:SetPoint('TOPLEFT', entry.card, 'TOPLEFT', 0, 0)
				activeAccentBar:SetPoint('BOTTOMLEFT', entry.card, 'BOTTOMLEFT', 0, 0)
				activeAccentBar:SetFrameLevel(entry.card:GetFrameLevel() + 5)

				if(hadPrev) then
					activeAccentBar:SetAlpha(1)
					activeAccentBar:Show()
				else
					activeAccentBar:SetAlpha(0)
					activeAccentBar:Show()
					Widgets.StartAnimation(activeAccentBar, 'fade', 0, 1, FADE_DUR,
						function(self, v) self:SetAlpha(v) end)
				end
			end
		elseif(activeAccentBar) then
			Widgets.StartAnimation(activeAccentBar, 'fade', activeAccentBar:GetAlpha(), 0, FADE_DUR,
				function(self, v) self:SetAlpha(v) end,
				function(self) self:Hide() end)
		end

		-- Spotlight preview elements when focus mode is on
		F.Settings.FramePreview.OnCardFocused(cardId)
	end

	-- Per-card setConfig wrapper that triggers active state on interaction
	local function makeCardSetConfig(cardId)
		return function(key, value)
			setConfig(key, value)
			setActiveCard(cardId)
		end
	end

	-- Register cards in display order
	grid:AddCard('position', 'Position & Layout', F.SettingsCards.PositionAndLayout, { unitType, getConfig, makeCardSetConfig('position'), relayout })
	if(unitType == 'party' or unitType == 'raid') then
		grid:AddCard('sorting', 'Sorting', F.SettingsCards.Sorting, { unitType, getConfig, makeCardSetConfig('sorting') })
	end

	grid:AddCard('healthColor', 'Portrait & Health Color', F.SettingsCards.HealthColor, { unitType, getConfig, makeCardSetConfig('healthColor'), relayout })

	grid:AddCard('shields', 'Shields & Absorbs', F.SettingsCards.ShieldsAndAbsorbs, { unitType, getConfig, makeCardSetConfig('shields') })
	grid:AddCard('power', 'Power Bar', F.SettingsCards.PowerBar, { unitType, getConfig, makeCardSetConfig('power') })
	grid:AddCard('castbar', 'Cast Bar', F.SettingsCards.CastBar, { unitType, getConfig, makeCardSetConfig('castbar'), relayout })
	grid:AddCard('name', 'Name Text', F.SettingsCards.Name, { unitType, getConfig, makeCardSetConfig('name'), relayout })
	grid:AddCard('healthText', 'Health Text', F.SettingsCards.HealthText, { unitType, getConfig, makeCardSetConfig('healthText'), relayout })
	grid:AddCard('powerText', 'Power Text', F.SettingsCards.PowerText, { unitType, getConfig, makeCardSetConfig('powerText'), relayout })
	-- Icon cards — split by category, filtered by unit type relevance
	if(GROUP_ICON_TYPES[unitType]) then
		grid:AddCard('groupIcons', 'Group Icons', F.SettingsCards.GroupIcons, { unitType, getConfig, makeCardSetConfig('groupIcons'), relayout })
	end
	if(GROUP_ICON_TYPES[unitType]) then
		grid:AddCard('statusText', 'Status Text', F.SettingsCards.StatusText, { unitType, getConfig, makeCardSetConfig('statusText'), relayout })
	end
	grid:AddCard('statusIcons', 'Status Icons', F.SettingsCards.StatusIcons, { unitType, getConfig, makeCardSetConfig('statusIcons'), relayout })
	grid:AddCard('markers', 'Markers', F.SettingsCards.Markers, { unitType, getConfig, makeCardSetConfig('markers'), relayout })
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
	grid:Layout(0, parentH)
	content:SetHeight(grid:GetTotalHeight())

	-- ── Card click-to-activate (hooks attached per card on build) ──
	local hookedCards = {}

	local function hookCardInteraction(cid, entry)
		if(hookedCards[cid]) then return end
		hookedCards[cid] = true
		entry.card:HookScript('OnMouseDown', function()
			setActiveCard(cid)
		end)
		entry.card:HookScript('OnEnter', function(self)
			if(activeCardId ~= cid) then
				animateCardBg(self, hoverBg)
			end
		end)
		entry.card:HookScript('OnLeave', function(self)
			if(activeCardId ~= cid) then
				animateCardBg(self, defaultBg)
			end
		end)
	end

	grid._onCardBuilt = function(cardId, entry)
		hookCardInteraction(cardId, entry)
	end

	-- Hook any cards already built in the initial layout
	for cardId, entry in next, grid._cardIndex do
		if(entry.built and entry.card) then
			hookCardInteraction(cardId, entry)
		end
	end

	-- ── Wire summary card click-to-jump ──────────────────────
	local function scrollToCard(cardId)
		local entry = grid._cardIndex[cardId]
		if(not entry) then return end

		local targetY = entry._layoutY or 0
		local sf = scroll._scrollFrame
		local viewH = sf:GetHeight()
		local maxScroll = math.max(0, content:GetHeight() - viewH)
		local newScroll = math.min(math.abs(targetY), maxScroll)
		sf:SetVerticalScroll(newScroll)
		scroll:_UpdateThumb()

		grid:Layout(newScroll, viewH)
		content:SetHeight(grid:GetTotalHeight())

		setActiveCard(cardId)
	end

	summaryCard._onItemClicked = scrollToCard

	-- ── Cancel animations on hide, re-layout on show ──────────
	scroll:HookScript('OnHide', function()
		grid:CancelAnimations()
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
