local _, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- CardGrid
-- Responsive masonry grid that positions card frames in columns.
-- Cards flow into the shortest column, stacking tightly with no
-- row alignment. Supports pinned cards (sorted to front), lazy
-- loading, and per-card title headings.
-- ============================================================

local CARD_MIN_W   = 240           -- minimum card width in logical px
local CARD_GAP     = C.Spacing.normal  -- 12px horizontal gap between cards
local CARD_V_GAP   = C.Spacing.normal  -- 12px vertical gap between cards
local BOTTOM_PAD   = C.Spacing.loose   -- 16px breathing room below last card
local LAZY_BUFFER  = 400           -- px ahead of visible area to pre-build
local TITLE_GAP    = C.Spacing.base    -- 4px gap between title and card top

-- ============================================================
-- Internal helpers
-- ============================================================

--- Calculate how many columns fit in the available width.
--- Returns at least 1 column.
--- @param width  number Available total width
--- @return number cols, number cardWidth
local function calcColumnLayout(width)
	if(width <= 0) then
		return 1, CARD_MIN_W
	end
	local cols = math.max(1, math.floor((width + CARD_GAP) / (CARD_MIN_W + CARD_GAP)))
	local cardW = math.floor((width - (cols - 1) * CARD_GAP) / cols)
	return cols, cardW
end

--- Inject a title heading above the card's inner content.
--- The title sits inside the card frame, above the existing inner frame.
--- @param entry table  Card entry with .card and .title
local function addCardTitle(entry)
	local card = entry.card
	if(not card or not entry.title or entry._titleAdded) then return end

	local titleFS = Widgets.CreateFontString(card, C.Font.sizeNormal, C.Colors.textNormal)
	titleFS:SetText(entry.title)
	titleFS:ClearAllPoints()
	Widgets.SetPoint(titleFS, 'TOPLEFT', card, 'TOPLEFT', 12, -8)
	entry._titleFS = titleFS
	entry._titleAdded = true

	-- Shift inner content frame down to make room for the title
	local titleH = titleFS:GetStringHeight() + TITLE_GAP + 4
	if(card.content) then
		card.content:ClearAllPoints()
		card.content:SetPoint('TOPLEFT', card, 'TOPLEFT', 12, -(8 + titleH))
		card.content:SetPoint('TOPRIGHT', card, 'TOPRIGHT', -12, -(8 + titleH))
	end

	-- Store title height on card so EndCard can account for it during reflow
	card._cardGridTitleH = titleH

	-- Increase card height to accommodate title
	local curH = card:GetHeight()
	card:SetHeight(curH + titleH)

	entry._titleHeight = titleH
end

-- ============================================================
-- CardGrid methods (bound as grid:Method())
-- ============================================================

--- Calculate columns and card width for the current grid width.
--- @return number cols, number cardWidth
local function GetColumnLayout(grid)
	return calcColumnLayout(grid._width)
end

--- Return card entries sorted pinned-first, preserving insertion order
--- within each tier.
--- @return table entries  Array of card entry tables
local function GetSortedCards(grid)
	local pinned   = {}
	local unpinned = {}
	for _, entry in next, grid._cards do
		if(entry.pinned) then
			pinned[#pinned + 1] = entry
		else
			unpinned[#unpinned + 1] = entry
		end
	end
	local sorted = {}
	for _, e in next, pinned   do sorted[#sorted + 1] = e end
	for _, e in next, unpinned do sorted[#sorted + 1] = e end
	return sorted
end

--- Add a pin toggle button to the top-right corner of a card.
--- @param entry table  Card entry table
--- @param grid  table  The card grid
local function addPinButton(entry, grid)
	local card = entry.card
	local pinBtn = Widgets.CreateIconButton(card, [[Interface\AddOns\Framed\Media\Icons\pin]], 18)
	pinBtn:SetPoint('TOPRIGHT', card, 'TOPRIGHT', -6, -6)

	local function updatePinVisual()
		if(entry.pinned) then
			local ac = C.Colors.accent
			pinBtn._icon:SetVertexColor(ac[1], ac[2], ac[3], ac[4] or 1)
		else
			local dim = C.Colors.textSecondary
			pinBtn._icon:SetVertexColor(dim[1], dim[2], dim[3], dim[4] or 1)
		end
	end

	pinBtn:SetScript('OnLeave', function(self)
		updatePinVisual()
		Widgets.SetBackdropHighlight(self, false)
		if(Widgets.HideTooltip) then
			Widgets.HideTooltip()
		end
	end)

	pinBtn:SetWidgetTooltip('Pin Card', 'Pinned cards sort to the top of the grid.')

	pinBtn:SetOnClick(function()
		entry.pinned = not entry.pinned
		updatePinVisual()
		if(grid._onPinChanged) then
			grid._onPinChanged(entry.id, entry.pinned)
		end
		grid:Layout(nil, nil, true)
	end)

	updatePinVisual()
	entry._pinBtn = pinBtn
end

local ANIM_DURATION = C.Animation.durationNormal  -- 150ms

--- Masonry layout: place each card in the shortest column.
--- Cards within [scrollOffset - LAZY_BUFFER, scrollOffset + viewHeight + LAZY_BUFFER]
--- are built on demand; cards outside that window are skipped.
--- @param grid         table   The grid object
--- @param scrollOffset number  Current vertical scroll offset (0 = top)
--- @param viewHeight   number  Height of the visible viewport
--- @param animated     boolean If true, animate cards from old to new position
local function Layout(grid, scrollOffset, viewHeight, animated)
	local cols, cardW = calcColumnLayout(grid._width)
	local sorted = GetSortedCards(grid)

	-- Cache scroll params for animated re-layouts triggered outside onScroll
	grid._lastScrollOffset = scrollOffset or grid._lastScrollOffset or 0
	grid._lastViewHeight   = viewHeight   or grid._lastViewHeight   or 0

	local windowTop    = grid._lastScrollOffset - LAZY_BUFFER
	local windowBottom = grid._lastScrollOffset + grid._lastViewHeight + LAZY_BUFFER

	-- Capture old positions before re-layout (for animation)
	local oldPos = {}
	if(animated) then
		for _, entry in next, sorted do
			if(entry.built and entry.card) then
				oldPos[entry.id] = {
					x = entry._layoutX or 0,
					y = entry._layoutY or 0,
				}
			end
		end
	end

	-- Per-column running Y offset (positive, grows downward)
	local topOffset = grid._topOffset or 0
	local colY = {}
	for c = 0, cols - 1 do
		colY[c] = topOffset
	end

	-- Estimated card height: use average of built cards, or fallback
	local EST_CARD_H = grid._avgCardHeight or 150

	for _, entry in next, sorted do
		-- Full-width cards span all columns; start below the tallest column
		local isFullWidth = entry.fullWidth and cols > 1
		local shortestCol, shortestY

		if(isFullWidth) then
			-- Find the tallest column so the full-width card clears everything above
			shortestCol = 0
			shortestY = colY[0]
			for c = 1, cols - 1 do
				if(colY[c] > shortestY) then
					shortestY = colY[c]
				end
			end
		else
			-- Find the shortest column
			shortestCol = 0
			shortestY = colY[0]
			for c = 1, cols - 1 do
				if(colY[c] < shortestY) then
					shortestCol = c
					shortestY = colY[c]
				end
			end
		end

		local cardTopY = shortestY
		local buildW = isFullWidth and grid._width or cardW

		-- Lazy build: only build if within visible window
		if(not entry.built) then
			local estBottom = cardTopY + EST_CARD_H
			if(estBottom >= windowTop and cardTopY <= windowBottom) then
				entry.card  = entry.builder(grid._container, buildW, unpack(entry.builderArgs))
				entry.card:ClearAllPoints()
				entry.built = true
				addCardTitle(entry)
				if(grid._pinEnabled ~= false) then
					addPinButton(entry, grid)
				end
			end
		end

		if(entry.built and entry.card) then
			local x = isFullWidth and 0 or shortestCol * (cardW + CARD_GAP)
			local y = cardTopY

			-- Store natural grid position
			entry._layoutX = x
			entry._layoutY = y

			-- ── Sticky card: reparent to viewport when scrolled past ──
			-- While sticky the card is parented to the scroll container
			-- (non-scrolling), so it stays put with zero per-tick work.
			if(entry.sticky) then
				local sOffset = grid._lastScrollOffset
				local shouldStick = sOffset > y

				if(shouldStick and not entry._stickyActive) then
					-- Transition → sticky: reparent to scroll viewport
					entry._stickyActive = true
					local scrollParent = grid._container:GetParent()._scrollParent
					if(scrollParent) then
						entry._stickyAnchor = scrollParent
						entry._origFrameLevel = entry.card:GetFrameLevel()
						entry.card:SetParent(scrollParent)
						entry.card:SetFrameLevel(entry._origFrameLevel + 50)
						entry.card:ClearAllPoints()
						Widgets.SetPoint(entry.card, 'TOPLEFT', scrollParent, 'TOPLEFT', x, 0)
						entry.card:SetWidth(buildW)
					end
				elseif(not shouldStick and entry._stickyActive) then
					-- Transition → normal: reparent back to grid
					entry._stickyActive = false
					entry.card:SetParent(grid._container)
					if(entry._origFrameLevel) then
						entry.card:SetFrameLevel(entry._origFrameLevel)
						entry._origFrameLevel = nil
					end
					entry.card:ClearAllPoints()
					Widgets.SetPoint(entry.card, 'TOPLEFT', grid._container, 'TOPLEFT', x, -y)
					entry.card:SetWidth(buildW)
				elseif(not shouldStick) then
					-- Normal grid position (not yet scrolled past)
					entry.card:ClearAllPoints()
					Widgets.SetPoint(entry.card, 'TOPLEFT', grid._container, 'TOPLEFT', x, -y)
					entry.card:SetWidth(buildW)
				end
				-- While sticky: do nothing — card is anchored to viewport
			elseif(animated and oldPos[entry.id]) then
				local old = oldPos[entry.id]
				local dx = x - old.x
				local dy = y - old.y

				-- Only animate if position actually changed
				if(math.abs(dx) > 1 or math.abs(dy) > 1) then
					-- Start at old position
					entry.card:ClearAllPoints()
					entry.card:SetPoint('TOPLEFT', grid._container, 'TOPLEFT', old.x, -old.y)
					entry.card:SetWidth(buildW)

					-- Single-channel animation interpolating both axes
					Widgets.StartAnimation(entry.card, 'gridMove', 0, 1, ANIM_DURATION, function(frame, t)
						local curX = Widgets.Lerp(old.x, x, t)
						local curY = Widgets.Lerp(old.y, y, t)
						frame:ClearAllPoints()
						frame:SetPoint('TOPLEFT', grid._container, 'TOPLEFT', curX, -curY)
					end, function(frame)
						frame:ClearAllPoints()
						Widgets.SetPoint(frame, 'TOPLEFT', grid._container, 'TOPLEFT', x, -y)
					end)
				else
					-- No meaningful movement, just snap
					entry.card:ClearAllPoints()
					Widgets.SetPoint(entry.card, 'TOPLEFT', grid._container, 'TOPLEFT', x, -y)
					entry.card:SetWidth(buildW)
				end
			else
				-- No animation: snap directly
				entry.card:ClearAllPoints()
				Widgets.SetPoint(entry.card, 'TOPLEFT', grid._container, 'TOPLEFT', x, -y)
				entry.card:SetWidth(buildW)
			end

			local cardH = entry.card:GetHeight()
			entry._lastHeight = cardH
			-- Full-width cards advance all columns
			if(isFullWidth) then
				local nextY = cardTopY + cardH + CARD_V_GAP
				for c = 0, cols - 1 do
					colY[c] = nextY
				end
			else
				colY[shortestCol] = cardTopY + cardH + CARD_V_GAP
			end
		else
			-- Unbuilt card: advance the column by estimated height
			if(isFullWidth) then
				local nextY = cardTopY + EST_CARD_H + CARD_V_GAP
				for c = 0, cols - 1 do
					colY[c] = nextY
				end
			else
				colY[shortestCol] = cardTopY + EST_CARD_H + CARD_V_GAP
			end
		end
	end

	-- Total height: tallest column
	local maxY = 0
	for c = 0, cols - 1 do
		if(colY[c] > maxY) then
			maxY = colY[c]
		end
	end
	-- Subtract the trailing gap from the last card
	grid._totalHeight = math.max(0, maxY - CARD_V_GAP)

	-- Update average card height for future lazy-load estimates
	local builtCount, totalH = 0, 0
	for _, entry in next, sorted do
		if(entry.built and entry._lastHeight) then
			builtCount = builtCount + 1
			totalH = totalH + entry._lastHeight
		end
	end
	if(builtCount > 0) then
		grid._avgCardHeight = totalH / builtCount
	end

	grid._container:SetHeight(math.max(1, grid._totalHeight + BOTTOM_PAD))
end

--- Register a card builder. The card is not built until Layout is called.
--- @param grid        table
--- @param id          string   Unique card identifier
--- @param title       string   Card title displayed at top of card
--- @param builder     function Called as builder(container, cardW, ...) → Frame
--- @param builderArgs table    Extra args unpacked into builder call
local function AddCard(grid, id, title, builder, builderArgs)
	local entry = {
		id          = id,
		title       = title,
		builder     = builder,
		builderArgs = builderArgs or {},
		card        = nil,
		built       = false,
		pinned      = false,
		_titleAdded = false,
		_titleHeight = 0,
	}
	grid._cards[#grid._cards + 1] = entry
	grid._cardIndex[id] = entry
end

--- Cancel any in-flight animations on a single card frame.
--- Snaps the card to its final position so layout state stays consistent.
--- @param card Frame
local function cancelCardAnims(card)
	if(type(card) ~= 'table' or not card._anim) then return end
	for animKey, anim in next, card._anim do
		if(anim.onComplete) then
			anim.onComplete(card)
		end
		card._anim[animKey] = nil
	end
end

--- Remove a single card by id. Hides and unparents the built frame.
--- @param grid table
--- @param id   string  Card id
local function RemoveCard(grid, id)
	local entry = grid._cardIndex[id]
	if(not entry) then return end

	-- Destroy the built frame
	if(entry.card) then
		cancelCardAnims(entry.card)
		entry.card:Hide()
		entry.card:SetParent(nil)
	end

	-- Remove from ordered array
	for i = #grid._cards, 1, -1 do
		if(grid._cards[i].id == id) then
			table.remove(grid._cards, i)
			break
		end
	end

	grid._cardIndex[id] = nil
end

--- Remove all cards from the grid. Hides and unparents every built frame.
--- @param grid table
local function RemoveAllCards(grid)
	for i = #grid._cards, 1, -1 do
		local entry = grid._cards[i]
		if(entry.card) then
			cancelCardAnims(entry.card)
			entry.card:Hide()
			entry.card:SetParent(nil)
		end
		grid._cardIndex[entry.id] = nil
		grid._cards[i] = nil
	end
	grid._cards        = {}
	grid._cardIndex    = {}
	grid._avgCardHeight = nil
	grid._totalHeight  = 0
end

--- Mark or unmark a card as pinned (pinned cards sort to the front).
--- @param grid   table
--- @param id     string   Card id
--- @param pinned boolean
local function SetPinned(grid, id, pinned)
	local entry = grid._cardIndex[id]
	if(entry) then
		entry.pinned = pinned
	end
end

--- Mark a card as full-width (spans all columns instead of one).
--- @param grid table
--- @param id   string  Card id
local function SetFullWidth(grid, id)
	local entry = grid._cardIndex[id]
	if(entry) then
		entry.fullWidth = true
	end
end

--- Mark a card as sticky (pins at viewport top when scrolled past).
--- @param grid table
--- @param id   string  Card id
local function SetSticky(grid, id)
	local entry = grid._cardIndex[id]
	if(entry) then
		entry.sticky = true
	end
end

local REFLOW_DURATION = 0.2  -- slightly slower than pin animation for visibility

--- Animated reflow: uses the last-known height from the previous Layout
--- (before the card's internal reflow changed it) and the current positions,
--- then runs Layout to get the final state. Animates card heights and
--- surrounding card positions in parallel.
--- @param grid table
local function AnimatedReflow(grid)
	-- 1. Snapshot state from PREVIOUS Layout (before reflow changed heights)
	local oldState = {}
	for _, entry in next, grid._cards do
		if(entry.built and entry.card) then
			local oldH = entry._lastHeight or entry.card:GetHeight()
			oldState[entry.id] = {
				h = oldH,
				x = entry._layoutX or 0,
				y = entry._layoutY or 0,
			}
		end
	end

	-- 2. Non-animated layout to compute final positions with new heights
	Layout(grid, nil, nil, false)

	-- 3. Animate from old to new
	local animCount = 0
	for _, entry in next, grid._cards do
		if(entry.built and entry.card and oldState[entry.id]) then
			local old = oldState[entry.id]
			local newX = entry._layoutX
			local newY = entry._layoutY
			local dx = newX - old.x
			local dy = newY - old.y

			-- Position animation (surrounding cards slide)
			if(math.abs(dx) > 1 or math.abs(dy) > 1) then
				animCount = animCount + 1
				entry.card:ClearAllPoints()
				entry.card:SetPoint('TOPLEFT', grid._container, 'TOPLEFT', old.x, -old.y)
				Widgets.StartAnimation(entry.card, 'gridReflow', 0, 1, REFLOW_DURATION, function(frame, t)
					local curX = Widgets.Lerp(old.x, newX, t)
					local curY = Widgets.Lerp(old.y, newY, t)
					frame:ClearAllPoints()
					frame:SetPoint('TOPLEFT', grid._container, 'TOPLEFT', curX, -curY)
				end, function(frame)
					frame:ClearAllPoints()
					Widgets.SetPoint(frame, 'TOPLEFT', grid._container, 'TOPLEFT', newX, -newY)
				end)
			end
		end
	end
end

--- Cancel all active card animations and snap cards to their final positions.
--- Called when the parent panel is hidden to prevent stale animation state.
--- @param grid table
local function CancelAnimations(grid)
	for _, entry in next, grid._cards do
		if(entry.built and entry.card and entry.card._anim) then
			for animKey, anim in next, entry.card._anim do
				-- Snap to final value
				if(anim.onComplete) then
					anim.onComplete(entry.card)
				end
				entry.card._anim[animKey] = nil
			end
		end
	end
end

--- Update the available width and re-layout.
--- Repositions cards immediately; full rebuild deferred to RebuildCards().
--- @param grid     table
--- @param newWidth number
local function SetWidth(grid, newWidth)
	grid._width = newWidth
	Widgets.SetSize(grid._container, newWidth, math.max(1, grid._totalHeight + BOTTOM_PAD))
	Layout(grid, grid._lastScrollOffset, grid._lastViewHeight)
end

--- Destroy and rebuild all cards at the current width.
--- Call after resize is complete (mouse release) to rebuild widgets
--- at the correct size without per-frame flicker.
--- @param grid table
local function RebuildCards(grid)
	for _, entry in next, grid._cards do
		if(entry.card) then
			cancelCardAnims(entry.card)
			entry.card:Hide()
			entry.card:SetParent(nil)
		end
		entry.card        = nil
		entry.built       = false
		entry._titleAdded = false
		entry._titleHeight = 0
		entry._stickyActive = false
	end
	grid._avgCardHeight = nil
	Layout(grid, grid._lastScrollOffset, grid._lastViewHeight)
end

--- Return the total content height of all positioned cards.
--- @return number
local function GetTotalHeight(grid)
	return grid._totalHeight + BOTTOM_PAD
end

--- Set top offset (margin before first card row).
--- @param grid   table
--- @param offset number
local function SetTopOffset(grid, offset)
	grid._topOffset = offset
end

-- ============================================================
-- Constructor
-- ============================================================

--- Create a responsive masonry card grid layout widget.
--- @param parent Frame  Parent frame (e.g. scroll content frame)
--- @param width  number Initial available width in logical px
--- @return table grid
function Widgets.CreateCardGrid(parent, width)
	local container = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(container, width, 1)
	container:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, 0)

	local grid = {
		_container   = container,
		_width       = width,
		_cards       = {},
		_cardIndex   = {},
		_totalHeight = 0,
		_topOffset   = 0,
	}

	-- Bind methods
	grid.AddCard          = AddCard
	grid.RemoveCard       = RemoveCard
	grid.RemoveAllCards   = RemoveAllCards
	grid.SetPinned        = SetPinned
	grid.SetFullWidth     = SetFullWidth
	grid.SetSticky        = SetSticky
	grid.GetColumnLayout  = GetColumnLayout
	grid.GetSortedCards   = GetSortedCards
	grid.Layout           = Layout
	grid.AnimatedReflow   = AnimatedReflow
	grid.CancelAnimations = CancelAnimations
	grid.SetWidth         = SetWidth
	grid.RebuildCards     = RebuildCards
	grid.GetTotalHeight   = GetTotalHeight
	grid.SetTopOffset     = SetTopOffset

	return grid
end
