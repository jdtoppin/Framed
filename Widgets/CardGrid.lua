local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- CardGrid
-- Responsive wrap-flow grid that positions card frames in a
-- left-to-right, top-to-bottom layout. Automatically calculates
-- column count from available width, distributes remaining width
-- evenly, and supports pinned cards (sorted to front) and lazy
-- loading (only builds cards near the visible scroll region).
-- ============================================================

local CARD_MIN_W   = 280           -- minimum card width in logical px
local CARD_GAP     = C.Spacing.normal  -- 12px horizontal gap between cards
local ROW_GAP      = C.Spacing.normal  -- 12px vertical gap between rows
local LAZY_BUFFER  = 400           -- px ahead of visible area to pre-build

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
	-- Try to fit as many CARD_MIN_W columns as possible (with gaps between).
	-- For N columns: width = N * cardW + (N - 1) * CARD_GAP
	-- → N = (width + CARD_GAP) / (CARD_MIN_W + CARD_GAP)
	local cols = math.max(1, math.floor((width + CARD_GAP) / (CARD_MIN_W + CARD_GAP)))
	-- Distribute the full width evenly.
	local cardW = math.floor((width - (cols - 1) * CARD_GAP) / cols)
	return cols, cardW
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

--- Build visible cards and position all entries in the grid.
--- Cards within [scrollOffset - LAZY_BUFFER, scrollOffset + viewHeight + LAZY_BUFFER]
--- are built on demand; cards outside that window that haven't been built
--- yet are skipped until they scroll into range.
--- @param grid         table  The grid object
--- @param scrollOffset number Current vertical scroll offset (0 = top)
--- @param viewHeight   number Height of the visible viewport
local function Layout(grid, scrollOffset, viewHeight)
	local cols, cardW = calcColumnLayout(grid._width)
	local sorted = GetSortedCards(grid)

	-- Visible window with lazy buffer
	local windowTop    = (scrollOffset or 0) - LAZY_BUFFER
	local windowBottom = (scrollOffset or 0) + (viewHeight or 0) + LAZY_BUFFER

	-- ── Pass 1: assign col/row to every entry ──────────────────
	-- Build a table of per-row estimated heights so we can derive
	-- approximate Y positions for the lazy-load window check.
	local col        = 0
	local row        = 0
	local rowEstH    = {}   -- estimated height per row (from already-built cards)

	for _, entry in next, sorted do
		entry._col = col
		entry._row = row

		-- Track the tallest card we've seen in this row (for position estimates)
		local h = (entry.built and entry.card) and entry.card:GetHeight() or CARD_MIN_W
		if(not rowEstH[row] or h > rowEstH[row]) then
			rowEstH[row] = h
		end

		col = col + 1
		if(col >= cols) then
			col = 0
			row = row + 1
		end
	end

	local lastUsedRow = row
	local lastUsedCol = col

	-- Build cumulative row Y estimates so we know where each row starts
	local rowEstY = {}
	local cumY    = 0
	for r = 0, lastUsedRow do
		rowEstY[r] = cumY
		cumY = cumY + (rowEstH[r] or CARD_MIN_W) + ROW_GAP
	end

	-- ── Pass 2: lazy-build cards that are in the visible window ─
	for _, entry in next, sorted do
		if(not entry.built) then
			local cardTopY    = rowEstY[entry._row] or 0
			local cardBottomY = cardTopY + (rowEstH[entry._row] or CARD_MIN_W)
			if(cardBottomY >= windowTop and cardTopY <= windowBottom) then
				entry.card  = entry.builder(grid._container, cardW, unpack(entry.builderArgs))
				entry.built = true
			end
		end
	end

	-- ── Pass 3: record true row heights from built cards ────────
	local rowHeights = {}
	for _, entry in next, sorted do
		if(entry.built and entry.card) then
			local h = entry.card:GetHeight()
			local r = entry._row
			if(not rowHeights[r] or h > rowHeights[r]) then
				rowHeights[r] = h
			end
		end
	end

	-- ── Compute cumulative Y offsets per row ────────────────────
	local rowY = {}
	cumY = 0
	for r = 0, lastUsedRow do
		rowY[r] = cumY
		cumY = cumY + (rowHeights[r] or 0) + ROW_GAP
	end

	-- ── Pass 4: apply pixel-snapped positions ───────────────────
	for _, entry in next, sorted do
		if(entry.built and entry.card) then
			local x = entry._col * (cardW + CARD_GAP)
			local y = -(rowY[entry._row] or 0)
			entry.card:ClearAllPoints()
			Widgets.SetPoint(entry.card, 'TOPLEFT', grid._container, 'TOPLEFT', x, y)
			entry.card:SetWidth(cardW)
		end
	end

	-- ── Total content height ────────────────────────────────────
	-- lastUsedRow / lastUsedCol reflect where the loop ended after the last entry.
	-- If lastUsedCol == 0 the last real row was (lastUsedRow - 1);
	-- if lastUsedCol > 0 some cards are in lastUsedRow.
	local lastContentRow = (lastUsedCol > 0) and lastUsedRow or (lastUsedRow - 1)
	if(lastContentRow >= 0 and rowY[lastContentRow]) then
		grid._totalHeight = rowY[lastContentRow] + (rowHeights[lastContentRow] or 0)
	else
		grid._totalHeight = 0
	end

	-- Update container height
	grid._container:SetHeight(math.max(1, grid._totalHeight))
end

--- Register a card builder. The card is not built until Layout is called.
--- @param grid        table
--- @param id          string   Unique card identifier
--- @param title       string   Card title (for pinning/sorting)
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
		_col        = 0,
		_row        = 0,
		_x          = 0,
	}
	grid._cards[#grid._cards + 1] = entry
	grid._cardIndex[id] = entry
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

--- Update the available width and re-layout.
--- @param grid     table
--- @param newWidth number
local function SetWidth(grid, newWidth)
	grid._width = newWidth
	Widgets.SetSize(grid._container, newWidth, math.max(1, grid._totalHeight))
	Layout(grid, 0, 0)
end

--- Return the total content height of all positioned cards.
--- @return number
local function GetTotalHeight(grid)
	return grid._totalHeight
end

-- ============================================================
-- Constructor
-- ============================================================

--- Create a responsive card grid layout widget.
--- @param parent Frame  Parent frame (e.g. scroll content frame)
--- @param width  number Initial available width in logical px
--- @return table grid
function Widgets.CreateCardGrid(parent, width)
	local container = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(container, width, 1)
	container:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, 0)

	local grid = {
		_container  = container,
		_width      = width,
		_cards      = {},      -- ordered array of card entries
		_cardIndex  = {},      -- id → entry
		_totalHeight = 0,
	}

	-- Bind methods
	grid.AddCard         = AddCard
	grid.SetPinned       = SetPinned
	grid.GetColumnLayout = GetColumnLayout
	grid.GetSortedCards  = GetSortedCards
	grid.Layout          = Layout
	grid.SetWidth        = SetWidth
	grid.GetTotalHeight  = GetTotalHeight

	return grid
end
