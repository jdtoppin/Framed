local addonName, Framed = ...
local F = Framed

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- Singleton Dropdown List (shared across all dropdowns)
-- ============================================================

local ITEM_HEIGHT   = 22
local MAX_VISIBLE   = 10
local LIST_PAD      = 4     -- inner padding inside the list frame
local SCROLLBAR_W   = 5
local SCROLLBAR_GAP = 2
local SCROLL_STEP   = ITEM_HEIGHT * 2
local THUMB_MIN_H   = 16

local ARROW_ICON    = [[Interface\AddOns\Framed\Media\Icons\ArrowUp1]]

-- Scrollbar auto-hide & hint arrow constants (match ScrollFrame.lua UX)
local FADE_IN_DUR      = 0.15
local FADE_OUT_DUR     = 0.4
local FADE_OUT_DELAY   = 1.0
local HINT_SIZE        = 12
local HINT_PULSE_MIN   = 0.2
local HINT_PULSE_MAX   = 0.7
local HINT_PULSE_SPEED = 1.0

local dropdownList          -- singleton list frame, created lazily
local dropdownBlocker       -- invisible full-screen click-catcher
local currentOwner          -- which dropdown button currently owns the list

-- Forward declarations
local CloseDropdownList
local OpenDropdownList

-- ── Icon-row decoration helpers ─────────────────────────────

--- Lazily create `count` icon textures on `row`, cached in
--- row._customDecorations. Returns the array of textures.
--- @param row Frame
--- @param count number
--- @param iconSize number
--- @return table  Array of count textures, all shown
local function ensureCustomDecorations(row, count, iconSize)
	row._customDecorations = row._customDecorations or {}
	local decorations = row._customDecorations
	for i = 1, count do
		local tex = decorations[i]
		if(not tex) then
			tex = row:CreateTexture(nil, 'OVERLAY')
			decorations[i] = tex
		end
		tex:SetSize(iconSize, iconSize)
		tex:Show()
	end
	return decorations
end

-- ── Scroll helpers ─────────────────────────────────────────

local function Clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

local function GetScrollMax()
	local contentH = dropdownList._content:GetHeight()
	local viewH    = dropdownList._scrollFrame:GetHeight()
	return math.max(0, contentH - viewH)
end

local function UpdateThumb()
	local contentH = dropdownList._content:GetHeight()
	local viewH    = dropdownList._scrollFrame:GetHeight()
	local trackH   = dropdownList._scrollbar:GetHeight()

	if(contentH <= viewH or viewH <= 0) then
		dropdownList._scrollbar:Hide()
		dropdownList._thumb:Hide()
		if(dropdownList._scrollHint) then dropdownList._scrollHint:Hide() end
		return
	end

	-- Show track/thumb frames (alpha controlled by fade logic)
	dropdownList._scrollbar:Show()
	dropdownList._thumb:Show()

	local ratio  = viewH / contentH
	local thumbH = math.max(THUMB_MIN_H, math.floor(ratio * trackH + 0.5))
	dropdownList._thumb:SetHeight(thumbH)

	local maxScroll = contentH - viewH
	local current   = dropdownList._scrollFrame:GetVerticalScroll()
	local frac      = (maxScroll > 0) and (current / maxScroll) or 0
	local maxY      = trackH - thumbH
	local thumbY    = math.floor(frac * maxY + 0.5)

	dropdownList._thumb:ClearAllPoints()
	dropdownList._thumb:SetPoint('TOP', dropdownList._scrollbar, 'TOP', 0, -thumbY)
end

local function ApplyScroll(offset)
	offset = Clamp(offset, 0, GetScrollMax())
	dropdownList._scrollFrame:SetVerticalScroll(offset)
	UpdateThumb()
end

-- ── Scrollbar auto-hide ──────────────────────────────────────

local function FadeDropdownScrollbar(targetAlpha, duration)
	if(not dropdownList) then return end
	local track = dropdownList._scrollbar
	local thumb = dropdownList._thumb
	local startAlpha = track:GetAlpha()
	if(math.abs(startAlpha - targetAlpha) < 0.01) then
		track:SetAlpha(targetAlpha)
		thumb:SetAlpha(targetAlpha)
		return
	end

	local elapsed = 0
	dropdownList._fadeFrame = dropdownList._fadeFrame or CreateFrame('Frame')
	dropdownList._fadeFrame:SetScript('OnUpdate', function(self, dt)
		elapsed = elapsed + dt
		local t = math.min(elapsed / duration, 1)
		local a = startAlpha + (targetAlpha - startAlpha) * t
		track:SetAlpha(a)
		thumb:SetAlpha(a)
		if(t >= 1) then
			self:SetScript('OnUpdate', nil)
		end
	end)
end

local UpdateDropdownHint  -- forward declaration

local function OnDropdownScrollActivity()
	if(not dropdownList) then return end
	local maxScroll = GetScrollMax()
	if(maxScroll <= 0) then return end

	-- Cancel pending fade-out
	if(dropdownList._fadeOutTimer) then
		dropdownList._fadeOutTimer:Cancel()
		dropdownList._fadeOutTimer = nil
	end

	-- Fade in if not already visible
	if(dropdownList._scrollbar:GetAlpha() < 0.9) then
		FadeDropdownScrollbar(1, FADE_IN_DUR)
	end

	-- Schedule fade-out
	dropdownList._fadeOutTimer = C_Timer.NewTimer(FADE_OUT_DELAY, function()
		dropdownList._fadeOutTimer = nil
		if(dropdownList._thumb._dragging) then return end
		FadeDropdownScrollbar(0, FADE_OUT_DUR)
	end)

	-- Update hint arrow
	UpdateDropdownHint()
end

-- ── Scroll hint arrow ────────────────────────────────────────

UpdateDropdownHint = function()
	if(not dropdownList or not dropdownList._scrollHint) then return end
	local hint = dropdownList._scrollHint
	local maxScroll = GetScrollMax()
	if(maxScroll <= 0) then
		hint:Hide()
		return
	end
	local currentOffset = dropdownList._scrollFrame:GetVerticalScroll()
	if(currentOffset >= maxScroll - 1) then
		hint:Hide()
	else
		hint:Show()
	end
end

-- ── Create the singleton ───────────────────────────────────

local function EnsureDropdownList()
	if(dropdownList) then return end

	-- Full-screen invisible blocker behind the list
	dropdownBlocker = CreateFrame('Frame', 'FramedDropdownBlocker', UIParent)
	dropdownBlocker:SetFrameStrata('TOOLTIP')
	dropdownBlocker:SetFrameLevel(90)
	dropdownBlocker:SetAllPoints(UIParent)
	dropdownBlocker:EnableMouse(true)
	dropdownBlocker:Hide()
	dropdownBlocker:SetScript('OnMouseDown', function()
		CloseDropdownList()
	end)

	-- The list frame itself
	dropdownList = CreateFrame('Frame', 'FramedDropdownList', UIParent, 'BackdropTemplate')
	dropdownList:SetFrameStrata('TOOLTIP')
	dropdownList:SetFrameLevel(100)
	dropdownList:SetClampedToScreen(true)
	dropdownList:Hide()

	dropdownList._bgColor     = C.Colors.panel
	dropdownList._borderColor = C.Colors.border
	Widgets.ApplyBackdrop(dropdownList, C.Colors.panel, C.Colors.border)

	-- ScrollFrame for the item rows
	local sf = CreateFrame('ScrollFrame', 'FramedDropdownScrollFrame', dropdownList)
	sf:SetPoint('TOPLEFT', dropdownList, 'TOPLEFT', LIST_PAD, -LIST_PAD)
	sf:SetPoint('BOTTOMRIGHT', dropdownList, 'BOTTOMRIGHT', -LIST_PAD, LIST_PAD)
	dropdownList._scrollFrame = sf

	-- Content child (anchored to scroll frame, rows go here)
	local content = CreateFrame('Frame', nil, sf)
	content:SetPoint('TOPLEFT', sf, 'TOPLEFT', 0, 0)
	sf:SetScrollChild(content)
	dropdownList._content = content

	-- Mouse-wheel scrolling
	sf:EnableMouseWheel(true)
	sf:SetScript('OnMouseWheel', function(self, delta)
		local current = self:GetVerticalScroll()
		ApplyScroll(current - delta * SCROLL_STEP)
		OnDropdownScrollActivity()
	end)

	-- Scrollbar track (right edge, inside the list frame — starts hidden, fades in on scroll)
	local track = CreateFrame('Frame', nil, dropdownList, 'BackdropTemplate')
	track:SetWidth(SCROLLBAR_W)
	track:SetPoint('TOPRIGHT', dropdownList, 'TOPRIGHT', -1, -LIST_PAD)
	track:SetPoint('BOTTOMRIGHT', dropdownList, 'BOTTOMRIGHT', -1, LIST_PAD)
	Widgets.ApplyBackdrop(track, C.Colors.panel, C.Colors.panel)
	track:SetAlpha(0)
	track:Hide()
	dropdownList._scrollbar = track

	-- Scrollbar thumb (starts hidden, fades in on scroll)
	local thumb = CreateFrame('Frame', nil, track)
	thumb:SetWidth(SCROLLBAR_W)
	thumb:SetHeight(THUMB_MIN_H)
	thumb:SetPoint('TOP', track, 'TOP', 0, 0)

	local thumbTex = thumb:CreateTexture(nil, 'OVERLAY')
	thumbTex:SetAllPoints(thumb)
	thumbTex:SetColorTexture(
		C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], C.Colors.accent[4] or 1)
	thumb:SetAlpha(0)
	thumb:Hide()
	dropdownList._thumb = thumb

	-- Scroll hint arrow (pulsing down arrow at bottom-right)
	local hint = CreateFrame('Frame', nil, dropdownList)
	hint:SetSize(HINT_SIZE, HINT_SIZE)
	hint:SetPoint('BOTTOMRIGHT', dropdownList, 'BOTTOMRIGHT', -4, 8)
	hint:SetFrameLevel(dropdownList:GetFrameLevel() + 5)

	local hintTex = hint:CreateTexture(nil, 'OVERLAY')
	hintTex:SetAllPoints(hint)
	hintTex:SetTexture(ARROW_ICON)
	hintTex:SetTexCoord(0.15, 0.85, 0.85, 0.15)  -- flip for down arrow
	local hintColor = C.Colors.accent
	hintTex:SetVertexColor(hintColor[1], hintColor[2], hintColor[3], hintColor[4] or 1)
	hint:Hide()

	local pulseElapsed = 0
	hint:SetScript('OnUpdate', function(self, dt)
		pulseElapsed = pulseElapsed + dt
		local t = (math.sin(pulseElapsed * HINT_PULSE_SPEED * 2 * math.pi) + 1) / 2
		local a = HINT_PULSE_MIN + (HINT_PULSE_MAX - HINT_PULSE_MIN) * t
		hintTex:SetAlpha(a)
	end)
	dropdownList._scrollHint = hint

	-- Thumb dragging
	thumb:EnableMouse(true)
	thumb:SetScript('OnMouseDown', function(self, button)
		if(button ~= 'LeftButton') then return end
		self._dragging = true
		local _, cursorY = GetCursorPosition()
		local scale = track:GetEffectiveScale()
		self._dragStartY = cursorY / scale
		self._dragStartThumbY = select(5, self:GetPoint()) or 0
	end)
	thumb:SetScript('OnMouseUp', function(self)
		self._dragging = false
	end)
	thumb:SetScript('OnUpdate', function(self)
		if(not self._dragging) then return end
		local _, cursorY = GetCursorPosition()
		local scale = track:GetEffectiveScale()
		cursorY = cursorY / scale

		local delta = self._dragStartY - cursorY
		local trackH = track:GetHeight()
		local thumbH = self:GetHeight()
		local maxThumbY = trackH - thumbH
		local newOffset = Clamp((-self._dragStartThumbY) + delta, 0, maxThumbY)

		local maxScroll = GetScrollMax()
		local frac = (maxThumbY > 0) and (newOffset / maxThumbY) or 0
		dropdownList._scrollFrame:SetVerticalScroll(math.floor(frac * maxScroll + 0.5))

		self:ClearAllPoints()
		self:SetPoint('TOP', track, 'TOP', 0, -math.floor(newOffset + 0.5))
		UpdateDropdownHint()
	end)

	-- Pool of item row frames (re-used each open)
	dropdownList._rows = {}
end

CloseDropdownList = function()
	if(dropdownList) then
		dropdownList:Hide()
		if(dropdownList._fadeOutTimer) then
			dropdownList._fadeOutTimer:Cancel()
			dropdownList._fadeOutTimer = nil
		end
		if(dropdownList._scrollHint) then
			dropdownList._scrollHint:Hide()
		end
	end
	if(dropdownBlocker) then dropdownBlocker:Hide() end
	-- Notify the owner so chrome-free triggers can tear down their
	-- "open" state (e.g. inline dropdown fading its underline back out).
	if(currentOwner and currentOwner._onClose) then
		currentOwner:_onClose()
	end
	currentOwner = nil
end

-- Build a single item row inside the content frame.
local function GetOrCreateRow(index)
	local row = dropdownList._rows[index]
	if(row) then return row end

	local content = dropdownList._content

	row = CreateFrame('Frame', nil, content, 'BackdropTemplate')
	row:SetHeight(ITEM_HEIGHT)
	row._bgColor     = C.Colors.panel
	row._borderColor = { 0, 0, 0, 0 }
	Widgets.ApplyBackdrop(row, C.Colors.panel, { 0, 0, 0, 0 })
	row:EnableMouse(true)

	-- Optional preview texture swatch (for texture dropdowns)
	local swatch = row:CreateTexture(nil, 'ARTWORK')
	swatch:SetSize(20, 12)
	swatch:SetPoint('LEFT', row, 'LEFT', 4, 0)
	swatch:Hide()
	row._swatch = swatch

	local label = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textNormal)
	label:SetPoint('LEFT',  row, 'LEFT', 4, 0)
	label:SetPoint('RIGHT', row, 'RIGHT', -4, 0)
	label:SetJustifyH('LEFT')
	row._label = label

	row:SetScript('OnEnter', function(self)
		self:SetBackdropColor(
			C.Colors.widget[1], C.Colors.widget[2], C.Colors.widget[3], C.Colors.widget[4] or 1)
	end)
	row:SetScript('OnLeave', function(self)
		self:SetBackdropColor(
			C.Colors.panel[1], C.Colors.panel[2], C.Colors.panel[3], C.Colors.panel[4] or 0.85)
	end)

	dropdownList._rows[index] = row
	return row
end

OpenDropdownList = function(owner)
	EnsureDropdownList()

	-- Close any existing open list first
	if(currentOwner and currentOwner ~= owner) then
		CloseDropdownList()
	end
	currentOwner = owner

	local items     = owner._items or {}
	local selected  = owner._value
	local totalCount = #items
	local showCount  = math.min(totalCount, MAX_VISIBLE)
	local needsScroll = totalCount > MAX_VISIBLE

	if(showCount == 0) then
		showCount = 1
	end

	-- Convert owner width from owner-scale to list-scale so the list
	-- visually matches the button width across different UI scales.
	local ownerScale = owner:GetEffectiveScale()
	local listScale  = dropdownList:GetEffectiveScale()
	local ownerW     = owner:GetWidth() * ownerScale / listScale
	local listH      = showCount * ITEM_HEIGHT + LIST_PAD * 2
	local scrollbarW = needsScroll and (SCROLLBAR_W + SCROLLBAR_GAP) or 0

	dropdownList:ClearAllPoints()
	dropdownList:SetPoint('TOPLEFT', owner, 'BOTTOMLEFT', 0, -2)
	dropdownList:SetSize(ownerW, listH)
	Widgets.ApplyBackdrop(dropdownList, C.Colors.panel, C.Colors.border)

	local contentW = ownerW - LIST_PAD * 2 - scrollbarW
	dropdownList._scrollFrame:ClearAllPoints()
	dropdownList._scrollFrame:SetPoint('TOPLEFT', dropdownList, 'TOPLEFT', LIST_PAD, -LIST_PAD)
	dropdownList._scrollFrame:SetSize(contentW, listH - LIST_PAD * 2)
	dropdownList._content:SetSize(contentW, listH - LIST_PAD * 2)

	-- Hide all existing rows first
	for _, row in next, dropdownList._rows do
		row:Hide()
	end

	-- Reset scroll position
	dropdownList._scrollFrame:SetVerticalScroll(0)

	if(totalCount == 0) then
		local row = GetOrCreateRow(1)
		row:ClearAllPoints()
		row:SetPoint('TOPLEFT', dropdownList._content, 'TOPLEFT', 0, 0)
		row:SetWidth(contentW)
		row._swatch:Hide()
		row._label:SetPoint('LEFT', row, 'LEFT', 4, 0)
		row._label:SetText('(empty)')
		local ts = C.Colors.textSecondary
		row._label:SetTextColor(ts[1], ts[2], ts[3], ts[4] or 1)
		row:SetScript('OnMouseDown', nil)
		row:Show()
		dropdownList._content:SetHeight(ITEM_HEIGHT)
	else
		for i = 1, totalCount do
			local item = items[i]
			if(not item) then break end

			local row = GetOrCreateRow(i)
			row:ClearAllPoints()
			row:SetPoint('TOPLEFT', dropdownList._content, 'TOPLEFT', 0, -(i - 1) * ITEM_HEIGHT)
			row:SetWidth(contentW)

			-- Reset any custom decorations from previous use
			if(row._customDecorations) then
				for _, tex in next, row._customDecorations do
					tex:Hide()
				end
			end

			-- Reset OnEnter/OnLeave to defaults (decorators may override)
			row:SetScript('OnEnter', function(self)
				self:SetBackdropColor(
					C.Colors.widget[1], C.Colors.widget[2], C.Colors.widget[3], C.Colors.widget[4] or 1)
			end)
			row:SetScript('OnLeave', function(self)
				self:SetBackdropColor(
					C.Colors.panel[1], C.Colors.panel[2], C.Colors.panel[3], C.Colors.panel[4] or 0.85)
			end)

			-- Swatch (texture preview)
			if(item._texturePath) then
				row._swatch:SetTexture(item._texturePath)
				local ac = C.Colors.accent
				row._swatch:SetVertexColor(ac[1], ac[2], ac[3], ac[4] or 1)
				row._swatch:Show()
				row._label:SetPoint('LEFT', row, 'LEFT', 30, 0)
			else
				row._swatch:Hide()
				row._label:SetPoint('LEFT', row, 'LEFT', 4, 0)
			end

			-- Font override for font-type dropdowns
			if(item._fontPath) then
				row._label:SetFont(item._fontPath, C.Font.sizeNormal, '')
			else
				row._label:SetFont(F.Media.GetActiveFont(), C.Font.sizeNormal, '')
			end

			row._label:SetText(item.text or '')

			-- Highlight selected item in accent color
			if(item.value == selected) then
				local ac = C.Colors.accent
				row._label:SetTextColor(ac[1], ac[2], ac[3], ac[4] or 1)
			else
				local tn = C.Colors.textNormal
				row._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)
			end

			-- Custom row decorator (e.g. for icon previews)
			if(item._decorateRow) then
				item._decorateRow(row, item)
			end

			-- Capture item reference for the click handler
			local capturedItem  = item
			local capturedOwner = owner
			row:SetScript('OnMouseDown', function(self, mouseButton)
				if(mouseButton ~= 'LeftButton') then return end
				capturedOwner:_SelectItem(capturedItem)
				CloseDropdownList()
			end)

			row:Show()
		end

		dropdownList._content:SetHeight(totalCount * ITEM_HEIGHT)
	end

	-- ── Pass 2: measure actual labels, expand if needed ─────
	-- Use GetUnboundedStringWidth on each label — returns the natural
	-- text width regardless of anchor constraints or deferred layout.
	if(totalCount > 0) then
		local maxRowW = 0
		for i = 1, totalCount do
			local row = dropdownList._rows[i]
			if(not row or not row:IsShown()) then break end
			local label = row._label
			local labelLeft = row._swatch:IsShown() and 30 or 4
			local tw = label:GetUnboundedStringWidth()
			local rowNeed = tw + labelLeft + 4
			if(rowNeed > maxRowW) then maxRowW = rowNeed end
		end

		local listW = math.max(ownerW, maxRowW + LIST_PAD * 2 + scrollbarW)
		if(listW > ownerW) then
			contentW = listW - LIST_PAD * 2 - scrollbarW
			-- Resize list, scroll frame, content, and all rows
			dropdownList:SetSize(listW, listH)
			Widgets.ApplyBackdrop(dropdownList, C.Colors.panel, C.Colors.border)
			dropdownList._scrollFrame:SetSize(contentW, listH - LIST_PAD * 2)
			dropdownList._content:SetWidth(contentW)
			for i = 1, totalCount do
				local row = dropdownList._rows[i]
				if(not row or not row:IsShown()) then break end
				row:SetWidth(contentW)
			end
		end
	end

	-- Scroll the selected item into view
	if(selected and totalCount > MAX_VISIBLE) then
		for i, item in next, items do
			if(item.value == selected) then
				local targetY = (i - 1) * ITEM_HEIGHT
				local viewH = showCount * ITEM_HEIGHT
				if(targetY > viewH - ITEM_HEIGHT) then
					ApplyScroll(targetY - viewH + ITEM_HEIGHT)
				end
				break
			end
		end
	end

	-- Reset scrollbar to hidden (will fade in on scroll)
	dropdownList._scrollbar:SetAlpha(0)
	dropdownList._thumb:SetAlpha(0)
	if(dropdownList._fadeOutTimer) then
		dropdownList._fadeOutTimer:Cancel()
		dropdownList._fadeOutTimer = nil
	end

	UpdateThumb()
	UpdateDropdownHint()
	dropdownBlocker:Show()
	dropdownList:Show()

end

-- ============================================================
-- OpenPopupMenu — chrome-free menu anchored to an arbitrary frame.
-- Satisfies the OpenDropdownList owner contract without rendering
-- a dropdown button. The caller gets a pure popup list that appears
-- directly below the given anchor frame.
-- ============================================================

local popupOwner

--- Open a popup menu anchored below `anchor`.
--- @param anchor   Frame    Frame the menu appears beneath
--- @param items    table    Dropdown items array
--- @param value    any      Currently-selected value (for highlight)
--- @param onSelect function  Receives (value, ownerFrame)
function Widgets.OpenPopupMenu(anchor, items, value, onSelect)
	if(not popupOwner) then
		popupOwner = CreateFrame('Frame', nil, UIParent)
		function popupOwner:_SelectItem(item)
			self._value = item.value
			if(self._onSelect) then
				self._onSelect(item.value, self)
			end
		end
		-- OpenDropdownList calls _onClose on the owner when the list closes.
		-- Use it to release the anchor so its hover state can return to rest.
		function popupOwner:_onClose()
			local a = self._anchor
			self._anchor = nil
			if(a) then
				a._menuOpen = nil
				local onLeave = a:GetScript('OnLeave')
				if(onLeave) then onLeave(a) end
			end
		end
	end

	popupOwner:SetParent(anchor:GetParent() or UIParent)
	popupOwner:SetFrameStrata('DIALOG')
	popupOwner:ClearAllPoints()
	popupOwner:SetPoint('TOPLEFT',  anchor, 'TOPLEFT',  0, 0)
	popupOwner:SetPoint('TOPRIGHT', anchor, 'TOPRIGHT', 0, 0)
	popupOwner:SetHeight(anchor:GetHeight())

	popupOwner._items    = items or {}
	popupOwner._value    = value
	popupOwner._onSelect = onSelect
	popupOwner._anchor   = anchor

	-- Flag the anchor so its own OnLeave can choose to stay visible while the
	-- menu is open. The anchor's OnLeave opts in by checking `self._menuOpen`.
	anchor._menuOpen = true

	OpenDropdownList(popupOwner)
end

-- ============================================================
-- CreateDropdown — standard dropdown widget
-- ============================================================

--- Create a standard dropdown button.
--- @param parent Frame Parent frame
--- @param width? number Logical width (defaults to 160)
--- @return Frame dropdown
function Widgets.CreateDropdown(parent, width)
	width = width or 160
	local HEIGHT = 22

	local dropdown = CreateFrame('Button', nil, parent, 'BackdropTemplate')
	dropdown._bgColor     = C.Colors.widget
	dropdown._borderColor = C.Colors.border
	dropdown._items       = {}
	dropdown._value       = nil
	dropdown._onSelect    = nil

	Widgets.ApplyBackdrop(dropdown, C.Colors.widget, C.Colors.border)
	Widgets.SetSize(dropdown, width, HEIGHT)
	dropdown:EnableMouse(true)

	-- Selected text label (left-aligned, inset, single-line truncation)
	local label = Widgets.CreateFontString(dropdown, C.Font.sizeNormal, C.Colors.textNormal)
	label:SetPoint('LEFT',  dropdown, 'LEFT',  6, 0)
	label:SetPoint('RIGHT', dropdown, 'RIGHT', -20, 0)
	label:SetJustifyH('LEFT')
	label:SetWordWrap(false)
	label:SetText('')
	dropdown._label = label

	-- Arrow indicator (right-aligned, texture icon)
	local arrow = dropdown:CreateTexture(nil, 'ARTWORK')
	arrow:SetSize(12, 12)
	arrow:SetPoint('RIGHT', dropdown, 'RIGHT', -6, 0)
	arrow:SetTexture(ARROW_ICON)
	arrow:SetTexCoord(0.15, 0.85, 0.85, 0.15)  -- flip vertically for down arrow
	local ts = C.Colors.textSecondary
	arrow:SetVertexColor(ts[1], ts[2], ts[3], ts[4] or 1)
	dropdown._arrow = arrow

	-- Hover/Leave
	dropdown:SetScript('OnEnter', function(self)
		if(not self:IsEnabled()) then return end
		Widgets.SetBackdropHighlight(self, true)
		if(Widgets.ShowTooltip and self._tooltipTitle) then
			Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
		end
	end)

	dropdown:SetScript('OnLeave', function(self)
		Widgets.SetBackdropHighlight(self, false)
		if(Widgets.HideTooltip) then
			Widgets.HideTooltip()
		end
	end)

	-- Click: toggle list
	dropdown:SetScript('OnClick', function(self)
		if(not self:IsEnabled()) then return end
		if(currentOwner == self and dropdownList and dropdownList:IsShown()) then
			CloseDropdownList()
		else
			OpenDropdownList(self)
		end
	end)

	-- --------------------------------------------------------
	-- Internal: select an item and update the button display
	-- --------------------------------------------------------
	function dropdown:_SelectItem(item)
		self._value = item.value

		-- Update label text
		self._label:SetText(item.text or '')
		local tn = C.Colors.textNormal
		self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)

		if(self._onSelect) then
			self._onSelect(item.value, self)
		end
	end

	-- --------------------------------------------------------
	-- Public API
	-- --------------------------------------------------------

	--- Replace the item list.
	--- @param items table Array of {text, value, icon?}
	function dropdown:SetItems(items)
		self._items = items or {}
		-- If current value no longer exists, clear display
		local found = false
		for _, item in next, self._items do
			if(item.value == self._value) then
				found = true
				self._label:SetText(item.text or '')
				break
			end
		end
		if(not found) then
			self._value = nil
			self._label:SetText('')
		end
	end

	--- Register a callback fired on selection: func(value, dropdown).
	--- @param func function
	function dropdown:SetOnSelect(func)
		self._onSelect = func
	end

	--- Get the currently selected value.
	--- @return any
	function dropdown:GetValue()
		return self._value
	end

	--- Programmatically set the selected value and update display.
	--- @param value any
	function dropdown:SetValue(value)
		for _, item in next, self._items do
			if(item.value == value) then
				self._value = value
				self._label:SetText(item.text or '')
				local tn = C.Colors.textNormal
				self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)
				return
			end
		end
		-- Value not found — clear display
		self._value = nil
		self._label:SetText('')
	end

	--- Enable or disable the dropdown.
	--- @param enabled boolean
	function dropdown:SetEnabled(enabled)
		self._enabled = enabled
		if(enabled) then
			self:EnableMouse(true)
			Widgets.ApplyBackdrop(self, C.Colors.widget, C.Colors.border)
			local tn = C.Colors.textNormal
			self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)
			local arrowColor = C.Colors.textSecondary
			self._arrow:SetVertexColor(arrowColor[1], arrowColor[2], arrowColor[3], arrowColor[4] or 1)
		else
			-- Close if open
			if(currentOwner == self) then CloseDropdownList() end
			self:EnableMouse(false)
			local w = C.Colors.widget
			self:SetBackdropColor(w[1] * 0.6, w[2] * 0.6, w[3] * 0.6, w[4] or 1)
			self:SetBackdropBorderColor(0, 0, 0, 1)
			local td = C.Colors.textDisabled
			self._label:SetTextColor(td[1], td[2], td[3], td[4] or 1)
			self._arrow:SetVertexColor(td[1], td[2], td[3], td[4] or 1)
		end
	end

	Widgets.ApplyBaseMixin(dropdown)
	Widgets.AttachTooltipScripts(dropdown)

	return dropdown
end

-- ============================================================
-- CreateInlineDropdown — chrome-free trigger for use inside
-- title bars and breadcrumbs. Renders as a tinted label + chevron
-- with an animated underline on hover / while the menu is open.
-- Satisfies the OpenDropdownList owner contract (_items, _value,
-- _SelectItem) so it reuses the shared list popup.
-- ============================================================

local INLINE_CHEVRON_SIZE   = 10
local INLINE_LABEL_PAD      = 4   -- space between label and chevron
local INLINE_EDGE_PAD       = 2   -- inner padding on both sides of the trigger
local INLINE_UNDERLINE_H    = 1
local INLINE_UNDERLINE_Y    = -9  -- top of underline, offset from trigger's vertical middle (clears descenders)
local INLINE_HOVER_DUR      = 0.12
local INLINE_UNDERLINE_REST = 0    -- hidden at rest
local INLINE_UNDERLINE_HOT  = 1    -- hover / open alpha

--- Create a borderless inline dropdown trigger.
--- @param parent Frame
--- @return Frame trigger
function Widgets.CreateInlineDropdown(parent)
	local HEIGHT = 18

	local trigger = CreateFrame('Button', nil, parent)
	Widgets.SetSize(trigger, 80, HEIGHT)
	trigger:EnableMouse(true)

	trigger._items       = {}
	trigger._value       = nil
	trigger._onSelect    = nil
	-- Default color follows the user's accent. Copied into a local table so
	-- later SetLabelColor overrides can't mutate C.Colors.accent.
	local accent = C.Colors.accent
	trigger._color       = { accent[1], accent[2], accent[3], accent[4] or 1 }
	trigger._labelPrefix = ''

	-- Prefix — breadcrumb separator (e.g. '/ '). Not underlined.
	local prefix = Widgets.CreateFontString(trigger, C.Font.sizeNormal, trigger._color)
	prefix:SetJustifyH('LEFT')
	prefix:SetPoint('LEFT', trigger, 'LEFT', INLINE_EDGE_PAD, 0)
	prefix:SetText('')
	trigger._prefix = prefix

	-- Label — the selected value. Underline hugs this FontString only.
	-- Positioned via autoSize() using explicit pixel math (not a LEFT→RIGHT
	-- anchor on prefix) so trailing whitespace in the prefix can't shift it.
	local label = Widgets.CreateFontString(trigger, C.Font.sizeNormal, trigger._color)
	label:SetJustifyH('LEFT')
	label:SetPoint('LEFT', trigger, 'LEFT', INLINE_EDGE_PAD, 0)
	label:SetText('')
	trigger._label = label

	-- Chevron — right of label, colored to match. Repositioned by autoSize().
	local chevron = trigger:CreateTexture(nil, 'OVERLAY')
	chevron:SetSize(INLINE_CHEVRON_SIZE, INLINE_CHEVRON_SIZE)
	chevron:SetPoint('LEFT', trigger, 'LEFT', INLINE_EDGE_PAD, 0)
	chevron:SetTexture(ARROW_ICON)
	chevron:SetTexCoord(0.15, 0.85, 0.85, 0.15)  -- flip vertically for down arrow
	chevron:SetVertexColor(trigger._color[1], trigger._color[2], trigger._color[3], trigger._color[4] or 1)
	trigger._chevron = chevron

	-- Underline — spans the label's visible glyphs only (not prefix, not
	-- chevron). Width and X offset are set explicitly in autoSize() from
	-- GetStringWidth() so trailing whitespace / shadow / justification can't
	-- leak underline past the glyph bounds.
	local underline = trigger:CreateTexture(nil, 'ARTWORK')
	underline:SetHeight(INLINE_UNDERLINE_H)
	underline:SetPoint('TOPLEFT', trigger, 'LEFT', INLINE_EDGE_PAD, INLINE_UNDERLINE_Y)
	underline:SetWidth(1)
	underline:SetColorTexture(trigger._color[1], trigger._color[2], trigger._color[3], trigger._color[4] or 1)
	underline:SetAlpha(INLINE_UNDERLINE_REST)
	trigger._underline = underline

	-- --------------------------------------------------------
	-- Underline fade helpers
	-- --------------------------------------------------------
	local function fadeUnderlineTo(targetAlpha)
		local startAlpha = underline:GetAlpha()
		if(math.abs(startAlpha - targetAlpha) < 0.01) then
			underline:SetAlpha(targetAlpha)
			return
		end
		Widgets.StartAnimation(
			trigger, 'inlineDDUnderline',
			startAlpha, targetAlpha,
			INLINE_HOVER_DUR,
			function(_, value) underline:SetAlpha(value) end
		)
	end
	trigger._fadeUnderlineTo = fadeUnderlineTo

	--- Recompute layout to hug prefix + label + chevron.
	--- Positions label, chevron, and underline from explicit pixel math so
	--- the underline starts exactly at the first glyph of the label and ends
	--- at its last glyph.
	local function autoSize()
		local prefixW = math.ceil(prefix:GetStringWidth())
		local labelW  = math.ceil(label:GetStringWidth())

		local labelX = INLINE_EDGE_PAD + prefixW
		label:ClearAllPoints()
		label:SetPoint('LEFT', trigger, 'LEFT', labelX, 0)

		local chevronX = labelX + labelW + INLINE_LABEL_PAD
		chevron:ClearAllPoints()
		chevron:SetPoint('LEFT', trigger, 'LEFT', chevronX, 0)

		underline:ClearAllPoints()
		underline:SetPoint('TOPLEFT', trigger, 'LEFT', labelX, INLINE_UNDERLINE_Y)
		underline:SetWidth(math.max(1, labelW + INLINE_LABEL_PAD + INLINE_CHEVRON_SIZE))

		local w = chevronX + INLINE_CHEVRON_SIZE + INLINE_EDGE_PAD
		trigger:SetWidth(w)
	end
	trigger._autoSize = autoSize

	-- Hover state — animates between resting and hot alphas
	trigger:SetScript('OnEnter', function(self)
		if(not self:IsEnabled()) then return end
		fadeUnderlineTo(INLINE_UNDERLINE_HOT)
	end)
	trigger:SetScript('OnLeave', function(self)
		-- Keep the underline hot while the list is open
		if(currentOwner == self and dropdownList and dropdownList:IsShown()) then return end
		fadeUnderlineTo(INLINE_UNDERLINE_REST)
	end)

	-- Click: toggle the shared list popup
	trigger:SetScript('OnClick', function(self)
		if(not self:IsEnabled()) then return end
		if(currentOwner == self and dropdownList and dropdownList:IsShown()) then
			CloseDropdownList()
		else
			OpenDropdownList(self)
		end
	end)

	-- --------------------------------------------------------
	-- OpenDropdownList contract
	-- --------------------------------------------------------
	function trigger:_SelectItem(item)
		self._value = item.value
		self._label:SetText(item.text or '')
		self._label:SetTextColor(self._color[1], self._color[2], self._color[3], self._color[4] or 1)
		autoSize()
		if(self._onSelect) then
			self._onSelect(item.value, self)
		end
	end

	-- --------------------------------------------------------
	-- Public API (matches CreateDropdown where it makes sense)
	-- --------------------------------------------------------
	function trigger:SetItems(items)
		self._items = items or {}
		local found
		for _, item in next, self._items do
			if(item.value == self._value) then
				found = item
				break
			end
		end
		if(found) then
			self._label:SetText(found.text or '')
		else
			self._value = nil
			self._label:SetText('')
		end
		autoSize()
	end

	function trigger:SetOnSelect(func)
		self._onSelect = func
	end

	function trigger:GetValue()
		return self._value
	end

	function trigger:SetValue(value)
		for _, item in next, self._items do
			if(item.value == value) then
				self._value = value
				self._label:SetText(item.text or '')
				self._label:SetTextColor(self._color[1], self._color[2], self._color[3], self._color[4] or 1)
				autoSize()
				return
			end
		end
		self._value = nil
		self._label:SetText('')
		autoSize()
	end

	--- Set a breadcrumb separator prefix that renders to the left of the
	--- selected label (e.g. '/ '). Not underlined and not part of menu rows.
	--- @param prefixText string
	function trigger:SetLabelPrefix(prefixText)
		self._labelPrefix = prefixText or ''
		self._prefix:SetText(self._labelPrefix)
		autoSize()
	end

	--- Override the label/chevron/underline color. Lets the caller tint
	--- the trigger to match surrounding breadcrumb styling.
	function trigger:SetLabelColor(r, g, b, a)
		self._color = { r, g, b, a or 1 }
		self._prefix:SetTextColor(r, g, b, a or 1)
		self._label:SetTextColor(r, g, b, a or 1)
		self._chevron:SetVertexColor(r, g, b, a or 1)
		self._underline:SetColorTexture(r, g, b, a or 1)
	end

	--- Close the list if this trigger owns it.
	function trigger:Close()
		if(currentOwner == self and dropdownList and dropdownList:IsShown()) then
			CloseDropdownList()
		end
	end

	--- Called by CloseDropdownList when this trigger owned the list.
	--- Drops the underline back to resting unless the mouse is still hovering.
	function trigger:_onClose()
		if(self:IsMouseOver()) then return end
		fadeUnderlineTo(INLINE_UNDERLINE_REST)
	end

	Widgets.ApplyBaseMixin(trigger)

	return trigger
end

-- ============================================================
-- CreateTextureDropdown — LSM-backed texture/font picker
-- ============================================================

--- Create a LibSharedMedia-backed dropdown.
--- @param parent Frame Parent frame
--- @param width? number Logical width (defaults to 200)
--- @param mediaType? string LSM media type: 'statusbar'|'font'|etc. (defaults to 'statusbar')
--- @return Frame dropdown
function Widgets.CreateTextureDropdown(parent, width, mediaType)
	width     = width     or 200
	mediaType = mediaType or 'statusbar'

	-- Safe LSM access — may not be loaded yet
	local LSM = LibStub and LibStub('LibSharedMedia-3.0', true)

	-- Build the base dropdown
	local dropdown = Widgets.CreateDropdown(parent, width)
	dropdown._mediaType = mediaType
	dropdown._lsmOnSelect = nil

	-- --------------------------------------------------------
	-- Override _SelectItem to expose texture path + name
	-- --------------------------------------------------------
	function dropdown:_SelectItem(item)
		self._value = item.value  -- stores LSM name as value

		self._label:SetText(item.text or '')
		local tn = C.Colors.textNormal
		self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)

		-- Update button swatch for statusbar type
		if(self._buttonSwatch) then
			if(item._texturePath and self._mediaType == 'statusbar') then
				self._buttonSwatch:SetTexture(item._texturePath)
				local ac = C.Colors.accent
				self._buttonSwatch:SetVertexColor(ac[1], ac[2], ac[3], ac[4] or 1)
				self._buttonSwatch:Show()
				self._label:SetPoint('LEFT', self, 'LEFT', 28, 0)
			else
				self._buttonSwatch:Hide()
				self._label:SetPoint('LEFT', self, 'LEFT', 6, 0)
			end
		end

		if(self._lsmOnSelect) then
			self._lsmOnSelect(item._texturePath or item.value, item.value, self)
		elseif(self._onSelect) then
			self._onSelect(item._texturePath or item.value, self)
		end
	end

	-- Button-level swatch preview (statusbar only)
	if(mediaType == 'statusbar') then
		local swatch = dropdown:CreateTexture(nil, 'ARTWORK')
		swatch:SetSize(20, 12)
		swatch:SetPoint('LEFT', dropdown, 'LEFT', 4, 0)
		swatch:Hide()
		dropdown._buttonSwatch = swatch
	end

	-- --------------------------------------------------------
	-- Populate items from LSM
	-- --------------------------------------------------------
	local function BuildItems(lsm)
		if(not lsm) then return {} end
		local names = lsm:List(mediaType)
		if(not names) then return {} end

		local items = {}
		for _, name in next, names do
			local path = lsm:Fetch(mediaType, name)
			local item = {
				text  = name,
				value = name,
				_texturePath = (mediaType == 'statusbar') and path or nil,
				_fontPath    = (mediaType == 'font')      and path or nil,
			}
			items[#items + 1] = item
		end
		return items
	end

	-- --------------------------------------------------------
	-- Public API overrides / additions
	-- --------------------------------------------------------

	--- Re-populate items from LSM (call after LSM finishes loading).
	function dropdown:Refresh()
		local lsm = LibStub and LibStub('LibSharedMedia-3.0', true)
		if(not lsm) then
			-- No LSM — warn once and leave items empty
			if(not self._lsmWarned) then
				self._lsmWarned = true
				if(DEFAULT_CHAT_FRAME) then
					DEFAULT_CHAT_FRAME:AddMessage(
						'|cffff8800Framed:|r TextureDropdown: LibSharedMedia-3.0 not available.')
				end
			end
			self:SetItems({})
			return
		end
		self:SetItems(BuildItems(lsm))
	end

	--- Override SetOnSelect to capture the LSM-specific signature:
	--- func(texturePath, textureName, dropdown).
	--- @param func function
	function dropdown:SetOnSelect(func)
		self._lsmOnSelect = func
	end

	--- Get the currently selected LSM name.
	--- @return string|nil
	function dropdown:GetValue()
		return self._value
	end

	--- Set the selected item by LSM registered name.
	--- @param textureName string
	function dropdown:SetValue(textureName)
		for _, item in next, self._items do
			if(item.value == textureName) then
				self._value = textureName
				self._label:SetText(item.text or '')
				local tn = C.Colors.textNormal
				self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)

				-- Update button swatch
				if(self._buttonSwatch) then
					if(item._texturePath) then
						self._buttonSwatch:SetTexture(item._texturePath)
						local ac = C.Colors.accent
						self._buttonSwatch:SetVertexColor(ac[1], ac[2], ac[3], ac[4] or 1)
						self._buttonSwatch:Show()
						self._label:SetPoint('LEFT', self, 'LEFT', 28, 0)
					else
						self._buttonSwatch:Hide()
						self._label:SetPoint('LEFT', self, 'LEFT', 6, 0)
					end
				end
				return
			end
		end
		self._value = nil
		self._label:SetText('')
		if(self._buttonSwatch) then
			self._buttonSwatch:Hide()
			self._label:SetPoint('LEFT', self, 'LEFT', 6, 0)
		end
	end

	-- Initial population (LSM may already be present at load time)
	if(LSM) then
		dropdown:SetItems(BuildItems(LSM))
	end

	return dropdown
end

-- ============================================================
-- CreateIconRowDropdown — dropdown with N inline icons per row
-- ============================================================
--
-- Items supply `icons` as an array of { texture, texCoord, label }
-- tuples where `texture` is a path string, `texCoord` is
-- { left, right, top, bottom }, and `label` is the text that goes
-- after the icons (optional; if the item also has `text`, that is
-- used as the primary label instead).
--
-- Layout per row: icon1, icon2, ... iconN, text
-- Icon size matches label font size (16px default).

local ICON_ROW_SIZE    = 16
local ICON_ROW_PADDING = 4
local ICON_ROW_GAP     = 2

--- Factory for a dropdown button whose list rows render a fixed
--- number of inline icons (with tex coords) followed by the label.
--- Shares the singleton dropdown list with Widgets.CreateDropdown.
--- @param parent Frame
--- @param width number
--- @param iconsPerRow number
--- @return Frame dropdown
function Widgets.CreateIconRowDropdown(parent, width, iconsPerRow)
	local dropdown = Widgets.CreateDropdown(parent, width)

	-- Replace the default SetItems with a version that attaches a
	-- per-item _decorateRow callback before delegating.
	local originalSetItems = dropdown.SetItems
	dropdown.SetItems = function(self, items)
		for _, item in next, items do
			item._decorateRow = function(row, itm)
				local decorations = ensureCustomDecorations(row, iconsPerRow, ICON_ROW_SIZE)
				local x = ICON_ROW_PADDING
				for i = 1, iconsPerRow do
					local iconSpec = itm.icons and itm.icons[i]
					local tex = decorations[i]
					if(iconSpec and iconSpec.texture) then
						tex:SetTexture(iconSpec.texture)
						local tc = iconSpec.texCoord
						if(tc) then
							tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
						else
							tex:SetTexCoord(0, 1, 0, 1)
						end
						tex:ClearAllPoints()
						tex:SetPoint('LEFT', row, 'LEFT', x, 0)
						tex:Show()
						x = x + ICON_ROW_SIZE + ICON_ROW_GAP
					else
						tex:Hide()
					end
				end
				-- Shift label to start after the icons
				row._label:ClearAllPoints()
				row._label:SetPoint('LEFT',  row, 'LEFT', x, 0)
				row._label:SetPoint('RIGHT', row, 'RIGHT', -4, 0)
				-- Hide the default swatch since this widget uses custom textures
				row._swatch:Hide()
			end
		end
		originalSetItems(self, items)
	end

	return dropdown
end
