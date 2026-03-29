local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- ScrollFrame
-- A scrollable content container with a thin accent scrollbar.
-- Used by settings panels, spell lists, and dropdown menus.
--
-- Layout:
--   scroll (outer container, transparent)
--   └── scroll._scrollFrame  (WoW ScrollFrame)
--       └── scroll._content  (child content frame, width = SF - 7px)
--   scroll._scrollbar        (5px track, right edge of container)
--   scroll._thumb            (accent-colored draggable thumb)
--   scroll._scrollHint       (pulsing down arrow at bottom center)
-- ============================================================

local SCROLLBAR_WIDTH  = 5   -- track and thumb width in logical px
local SCROLLBAR_GAP    = 2   -- gap between content and scrollbar
local SCROLLBAR_OFFSET = SCROLLBAR_WIDTH + SCROLLBAR_GAP  -- 7px total
local THUMB_MIN_HEIGHT = 20  -- minimum thumb height in logical px
local SCROLL_STEP      = 20  -- px per mouse-wheel tick

local FADE_IN_DUR      = 0.15  -- scrollbar fade-in duration
local FADE_OUT_DUR     = 0.4   -- scrollbar fade-out duration
local FADE_OUT_DELAY   = 1.0   -- seconds idle before scrollbar fades out

local HINT_SIZE        = 12
local HINT_PULSE_MIN   = 0.2
local HINT_PULSE_MAX   = 0.7
local HINT_PULSE_SPEED = 1.0  -- full cycles per second

local ARROW_ICON = [[Interface\AddOns\Framed\Media\Icons\ArrowUp1]]

local uniqueScrollIndex = 0

local function GenerateScrollName()
	uniqueScrollIndex = uniqueScrollIndex + 1
	return 'FramedScrollFrame' .. uniqueScrollIndex
end

-- ============================================================
-- Internal helpers
-- ============================================================

--- Clamp a value between lo and hi.
local function Clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

--- Return the current scroll range max (0 when content fits).
--- Uses the outer container height rather than the anchored ScrollFrame
--- height, because WoW may not have resolved anchor-based sizes yet.
local function GetScrollMax(scroll)
	local contentH = scroll._content:GetHeight()
	local viewH    = scroll:GetHeight()
	return math.max(0, contentH - viewH)
end

-- ============================================================
-- Scrollbar fade helpers
-- ============================================================

--- Fade the scrollbar track + thumb to a target alpha over duration.
--- Uses StartAnimation on the track frame to avoid clobbering HookScript
--- handlers on the scroll frame (which the animation system relies on).
local function FadeScrollbar(scroll, targetAlpha, duration)
	local track = scroll._scrollbar
	local thumb = scroll._thumb
	local startAlpha = track:GetAlpha()
	if(math.abs(startAlpha - targetAlpha) < 0.01) then
		track:SetAlpha(targetAlpha)
		thumb:SetAlpha(targetAlpha)
		return
	end

	scroll._fadeTarget = targetAlpha
	Widgets.StartAnimation(track, 'scrollbarFade', startAlpha, targetAlpha, duration, function(_, a)
		track:SetAlpha(a)
		thumb:SetAlpha(a)
	end)
end

--- Mark scrollbar as active (show it), schedule fade-out after delay.
local function OnScrollActivity(scroll)
	local maxScroll = GetScrollMax(scroll)
	if(maxScroll <= 0) then return end

	-- Cancel pending fade-out
	if(scroll._fadeOutTimer) then
		scroll._fadeOutTimer:Cancel()
		scroll._fadeOutTimer = nil
	end

	-- Fade in if not already visible
	if(scroll._scrollbar:GetAlpha() < 0.9) then
		FadeScrollbar(scroll, 1, FADE_IN_DUR)
	end

	-- Schedule fade-out
	scroll._fadeOutTimer = C_Timer.NewTimer(FADE_OUT_DELAY, function()
		scroll._fadeOutTimer = nil
		-- Don't fade if thumb is being dragged
		if(scroll._thumb._dragging) then return end
		FadeScrollbar(scroll, 0, FADE_OUT_DUR)
	end)
end

-- ============================================================
-- Scroll hint (pulsing down arrow)
-- ============================================================

--- Update the scroll hint visibility: show only when content overflows
--- and the user hasn't scrolled to the bottom.
local function UpdateScrollHint(scroll)
	local hint = scroll._scrollHint
	if(not hint) then return end

	local maxScroll = GetScrollMax(scroll)
	if(maxScroll <= 0) then
		hint:Hide()
		return
	end

	local currentOffset = scroll._scrollFrame:GetVerticalScroll()
	if(currentOffset >= maxScroll - 1) then
		hint:Hide()
	else
		hint:Show()
	end
end

--- Move the WoW ScrollFrame to the given offset and sync the thumb.
local function ApplyScroll(scroll, offset)
	local maxScroll = GetScrollMax(scroll)
	offset = Clamp(offset, 0, maxScroll)
	scroll._scrollFrame:SetVerticalScroll(offset)
	scroll:_UpdateThumb()
	OnScrollActivity(scroll)
	UpdateScrollHint(scroll)
end

-- ============================================================
-- Thumb / scrollbar update
-- ============================================================

--- Recompute thumb height and position from current scroll state.
--- Auto-hides the scrollbar when the content fits within the view.
function Widgets._ScrollFrame_UpdateThumb(scroll)
	local contentH = scroll._content:GetHeight()
	local viewH    = scroll._scrollFrame:GetHeight()
	local trackH   = scroll._scrollbar:GetHeight()

	if(contentH <= viewH or viewH <= 0) then
		-- Content fits: hide scrollbar entirely
		scroll._scrollbar:Hide()
		scroll._thumb:Hide()
		UpdateScrollHint(scroll)
		return
	end

	scroll._scrollbar:Show()
	scroll._thumb:Show()

	-- Thumb height is proportional to the visible fraction
	local ratio     = viewH / contentH
	local thumbH    = math.max(THUMB_MIN_HEIGHT, Widgets.Round(ratio * trackH))
	scroll._thumb:SetHeight(thumbH)

	-- Thumb position: maps scroll offset onto the track
	local maxScroll = contentH - viewH
	local currentOffset = scroll._scrollFrame:GetVerticalScroll()
	local scrollFrac = (maxScroll > 0) and (currentOffset / maxScroll) or 0
	local maxThumbY  = trackH - thumbH
	local thumbY     = Widgets.Round(scrollFrac * maxThumbY)

	scroll._thumb:ClearAllPoints()
	scroll._thumb:SetPoint('TOP', scroll._scrollbar, 'TOP', 0, -thumbY)

	UpdateScrollHint(scroll)
end

-- ============================================================
-- Public API
-- ============================================================

--- Return the child content frame that callers add content to.
function Widgets._ScrollFrame_GetContentFrame(scroll)
	return scroll._content
end

--- Reset scroll position to the top and refresh the hint/thumb.
function Widgets._ScrollFrame_ScrollToTop(scroll)
	scroll._scrollFrame:SetVerticalScroll(0)
	scroll:_UpdateThumb()
	UpdateScrollHint(scroll)
end

--- Recalculate the scroll range.  Call after adding or removing content.
--- Also clamps the current scroll position into the new valid range.
function Widgets._ScrollFrame_UpdateScrollRange(scroll)
	local maxScroll     = GetScrollMax(scroll)
	local currentOffset = scroll._scrollFrame:GetVerticalScroll()
	if(currentOffset > maxScroll) then
		scroll._scrollFrame:SetVerticalScroll(maxScroll)
	end
	scroll:_UpdateThumb()
	UpdateScrollHint(scroll)
end

-- ============================================================
-- Constructor
-- ============================================================

--- Create a scrollable content frame with a thin accent scrollbar.
--- @param parent Frame  Parent frame
--- @param name?  string Global frame name for the WoW ScrollFrame (auto-generated if nil)
--- @param width  number Logical width of the outer container
--- @param height number Logical height of the outer container
--- @return Frame scroll  Outer container; use scroll:GetContentFrame() for child content
function Widgets.CreateScrollFrame(parent, name, width, height)
	name = name or GenerateScrollName()

	-- ── Outer container (transparent) ──────────────────────────
	local scroll = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(scroll, width, height)
	Widgets.ApplyBaseMixin(scroll)

	-- Bind internal helpers as methods
	scroll._UpdateThumb       = Widgets._ScrollFrame_UpdateThumb
	scroll.GetContentFrame    = Widgets._ScrollFrame_GetContentFrame
	scroll.UpdateScrollRange  = Widgets._ScrollFrame_UpdateScrollRange
	scroll.ScrollToTop        = Widgets._ScrollFrame_ScrollToTop

	-- ── WoW ScrollFrame ────────────────────────────────────────
	local sf = CreateFrame('ScrollFrame', name, scroll)
	sf:SetPoint('TOPLEFT',     scroll, 'TOPLEFT',  0,                 0)
	sf:SetPoint('BOTTOMRIGHT', scroll, 'BOTTOMRIGHT', -SCROLLBAR_OFFSET, 0)
	scroll._scrollFrame = sf

	-- ── Content (child of ScrollFrame) ─────────────────────────
	local content = CreateFrame('Frame', nil, sf)
	content:SetPoint('TOPLEFT', sf, 'TOPLEFT', 0, 0)
	-- Set initial width immediately so children have a non-zero anchor target.
	-- The deferred OnShow init below may refine this once layout resolves.
	content:SetWidth(width - SCROLLBAR_OFFSET)
	scroll._content = content

	sf:SetScrollChild(content)

	-- Back-reference so children can find the scroll container
	content._scrollParent = scroll

	-- ── Scrollbar track ────────────────────────────────────────
	local track = CreateFrame('Frame', nil, scroll, 'BackdropTemplate')
	track:SetWidth(SCROLLBAR_WIDTH)
	track:SetPoint('TOPRIGHT',    scroll, 'TOPRIGHT', 0,  0)
	track:SetPoint('BOTTOMRIGHT', scroll, 'BOTTOMRIGHT', 0, 0)
	Widgets.ApplyBackdrop(track, C.Colors.panel, C.Colors.panel)
	track:SetAlpha(0)   -- start hidden, fade in on scroll
	track:Hide()        -- hidden until content overflows
	scroll._scrollbar = track

	-- ── Scrollbar thumb ────────────────────────────────────────
	local thumb = CreateFrame('Frame', nil, track)
	thumb:SetWidth(SCROLLBAR_WIDTH)
	thumb:SetHeight(THUMB_MIN_HEIGHT)
	thumb:SetPoint('TOP', track, 'TOP', 0, 0)

	local thumbTex = thumb:CreateTexture(nil, 'OVERLAY')
	thumbTex:SetAllPoints(thumb)
	thumbTex:SetColorTexture(
		C.Colors.accent[1],
		C.Colors.accent[2],
		C.Colors.accent[3],
		C.Colors.accent[4] or 1)
	thumb:SetAlpha(0)  -- match track initial alpha
	scroll._thumb = thumb

	-- ── Scroll hint (pulsing down arrow) ───────────────────────
	local hint = CreateFrame('Frame', nil, scroll)
	hint:SetSize(HINT_SIZE, HINT_SIZE)
	hint:SetPoint('BOTTOMRIGHT', scroll, 'BOTTOMRIGHT', -4, 8)
	hint:SetFrameLevel(scroll:GetFrameLevel() + 5)

	local hintTex = hint:CreateTexture(nil, 'OVERLAY')
	hintTex:SetAllPoints(hint)
	hintTex:SetTexture(ARROW_ICON)
	hintTex:SetTexCoord(0.15, 0.85, 0.85, 0.15)  -- flip for down arrow
	local ac = C.Colors.accent
	hintTex:SetVertexColor(ac[1], ac[2], ac[3], ac[4] or 1)
	hint:Hide()

	-- Pulse animation via OnUpdate
	local pulseElapsed = 0
	hint:SetScript('OnUpdate', function(self, dt)
		pulseElapsed = pulseElapsed + dt
		local t = (math.sin(pulseElapsed * HINT_PULSE_SPEED * 2 * math.pi) + 1) / 2
		local a = HINT_PULSE_MIN + (HINT_PULSE_MAX - HINT_PULSE_MIN) * t
		hintTex:SetAlpha(a)
	end)

	scroll._scrollHint = hint

	-- ── Mouse-wheel scrolling ───────────────────────────────────
	sf:EnableMouseWheel(true)
	sf:SetScript('OnMouseWheel', function(self, delta)
		local current = self:GetVerticalScroll()
		ApplyScroll(scroll, current - delta * SCROLL_STEP)
	end)

	-- ── Thumb dragging ─────────────────────────────────────────
	thumb:EnableMouse(true)

	thumb:SetScript('OnMouseDown', function(self, button)
		if(button ~= 'LeftButton') then return end
		self._dragging   = true
		local _, cursorY = GetCursorPosition()
		local scale      = track:GetEffectiveScale()
		self._dragStartCursorY = cursorY / scale
		self._dragStartThumbY  = select(5, self:GetPoint()) or 0  -- negative offset from TOP
	end)

	thumb:SetScript('OnMouseUp', function(self, button)
		if(button == 'LeftButton') then
			self._dragging = false
			-- Schedule fade-out now that dragging stopped
			OnScrollActivity(scroll)
		end
	end)

	thumb:SetScript('OnUpdate', function(self)
		if(not self._dragging) then return end

		local _, cursorY = GetCursorPosition()
		local scale      = track:GetEffectiveScale()
		cursorY = cursorY / scale

		local delta = self._dragStartCursorY - cursorY   -- positive = dragged down
		local startY = self._dragStartThumbY             -- negative: offset below TOP

		local trackH  = track:GetHeight()
		local thumbH  = self:GetHeight()
		local maxThumbY = trackH - thumbH

		-- New thumb offset below the track top (clamped)
		local newOffset = Clamp((-startY) + delta, 0, maxThumbY)

		-- Convert thumb position to scroll offset
		local maxScroll = GetScrollMax(scroll)
		local fraction  = (maxThumbY > 0) and (newOffset / maxThumbY) or 0
		local newScroll = Widgets.Round(fraction * maxScroll)

		scroll._scrollFrame:SetVerticalScroll(newScroll)
		-- Reposition thumb directly (skip full UpdateThumb to avoid jitter)
		self:ClearAllPoints()
		self:SetPoint('TOP', track, 'TOP', 0, -Widgets.Round(newOffset))

		UpdateScrollHint(scroll)
	end)

	-- ── Deferred content-width init ────────────────────────────
	-- GetWidth() returns 0 on the first frame; defer to the next tick.
	local widthInitDone = false
	scroll:HookScript('OnShow', function(self)
		if(widthInitDone) then return end
		C_Timer.After(0, function()
			if(not scroll._scrollFrame) then return end
			local sfW = scroll._scrollFrame:GetWidth()
			if(sfW > 0) then
				content:SetWidth(sfW)
				widthInitDone = true
			end
		end)
	end)

	-- ── Pixel updater registration ──────────────────────────────
	Widgets.AddToPixelUpdater_OnShow(scroll)

	return scroll
end
