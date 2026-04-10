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
local EnsureDropdownList
local CloseDropdownList
local OpenDropdownList

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

	-- Selected text label (left-aligned, inset)
	local label = Widgets.CreateFontString(dropdown, C.Font.sizeNormal, C.Colors.textNormal)
	label:SetPoint('LEFT',  dropdown, 'LEFT',  6, 0)
	label:SetPoint('RIGHT', dropdown, 'RIGHT', -20, 0)
	label:SetJustifyH('LEFT')
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
			local ts = C.Colors.textSecondary
			self._arrow:SetVertexColor(ts[1], ts[2], ts[3], ts[4] or 1)
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
	local baseSelectItem = dropdown._SelectItem
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
