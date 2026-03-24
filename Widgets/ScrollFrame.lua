local addonName, Framed = ...

local Widgets = Framed.Widgets
local C = Framed.Constants

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
-- ============================================================

local SCROLLBAR_WIDTH  = 5   -- track and thumb width in logical px
local SCROLLBAR_GAP    = 2   -- gap between content and scrollbar
local SCROLLBAR_OFFSET = SCROLLBAR_WIDTH + SCROLLBAR_GAP  -- 7px total
local THUMB_MIN_HEIGHT = 20  -- minimum thumb height in logical px
local SCROLL_STEP      = 20  -- px per mouse-wheel tick

local uniqueScrollIndex = 0

local function GenerateScrollName()
    uniqueScrollIndex = uniqueScrollIndex + 1
    return "FramedScrollFrame" .. uniqueScrollIndex
end

-- ============================================================
-- Internal helpers
-- ============================================================

--- Clamp a value between lo and hi.
local function Clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

--- Return the current scroll range max (0 when content fits).
local function GetScrollMax(scroll)
    local contentH = scroll._content:GetHeight()
    local viewH    = scroll._scrollFrame:GetHeight()
    return math.max(0, contentH - viewH)
end

--- Move the WoW ScrollFrame to the given offset and sync the thumb.
local function ApplyScroll(scroll, offset)
    local maxScroll = GetScrollMax(scroll)
    offset = Clamp(offset, 0, maxScroll)
    scroll._scrollFrame:SetVerticalScroll(offset)
    scroll:_UpdateThumb()
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

    if contentH <= viewH or viewH <= 0 then
        -- Content fits: hide scrollbar entirely
        scroll._scrollbar:Hide()
        scroll._thumb:Hide()
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
    scroll._thumb:SetPoint("TOP", scroll._scrollbar, "TOP", 0, -thumbY)
end

-- ============================================================
-- Public API
-- ============================================================

--- Return the child content frame that callers add content to.
function Widgets._ScrollFrame_GetContentFrame(scroll)
    return scroll._content
end

--- Recalculate the scroll range.  Call after adding or removing content.
--- Also clamps the current scroll position into the new valid range.
function Widgets._ScrollFrame_UpdateScrollRange(scroll)
    local maxScroll     = GetScrollMax(scroll)
    local currentOffset = scroll._scrollFrame:GetVerticalScroll()
    if currentOffset > maxScroll then
        scroll._scrollFrame:SetVerticalScroll(maxScroll)
    end
    scroll:_UpdateThumb()
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
    local scroll = CreateFrame("Frame", nil, parent)
    Widgets.SetSize(scroll, width, height)
    Widgets.ApplyBaseMixin(scroll)

    -- Bind internal helpers as methods
    scroll._UpdateThumb       = Widgets._ScrollFrame_UpdateThumb
    scroll.GetContentFrame    = Widgets._ScrollFrame_GetContentFrame
    scroll.UpdateScrollRange  = Widgets._ScrollFrame_UpdateScrollRange

    -- ── WoW ScrollFrame ────────────────────────────────────────
    local sf = CreateFrame("ScrollFrame", name, scroll)
    sf:SetPoint("TOPLEFT",     scroll, "TOPLEFT",  0,                 0)
    sf:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -SCROLLBAR_OFFSET, 0)
    scroll._scrollFrame = sf

    -- ── Content (child of ScrollFrame) ─────────────────────────
    local content = CreateFrame("Frame", nil, sf)
    -- Width set deferred (see OnShow); height driven by caller
    content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
    scroll._content = content

    sf:SetScrollChild(content)

    -- ── Scrollbar track ────────────────────────────────────────
    local track = CreateFrame("Frame", nil, scroll, "BackdropTemplate")
    track:SetWidth(SCROLLBAR_WIDTH)
    track:SetPoint("TOPRIGHT",    scroll, "TOPRIGHT", 0,  0)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    Widgets.ApplyBackdrop(track, C.Colors.panel, C.Colors.panel)
    track:Hide()   -- hidden until UpdateScrollRange shows it
    scroll._scrollbar = track

    -- ── Scrollbar thumb ────────────────────────────────────────
    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetHeight(THUMB_MIN_HEIGHT)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)

    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints(thumb)
    thumbTex:SetColorTexture(
        C.Colors.accent[1],
        C.Colors.accent[2],
        C.Colors.accent[3],
        C.Colors.accent[4] or 1)
    scroll._thumb = thumb

    -- ── Mouse-wheel scrolling ───────────────────────────────────
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        ApplyScroll(scroll, current - delta * SCROLL_STEP)
    end)

    -- ── Thumb dragging ─────────────────────────────────────────
    thumb:EnableMouse(true)

    thumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        self._dragging   = true
        local _, cursorY = GetCursorPosition()
        local scale      = track:GetEffectiveScale()
        self._dragStartCursorY = cursorY / scale
        self._dragStartThumbY  = select(5, self:GetPoint()) or 0  -- negative offset from TOP
    end)

    thumb:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self._dragging = false
        end
    end)

    thumb:SetScript("OnUpdate", function(self)
        if not self._dragging then return end

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
        self:SetPoint("TOP", track, "TOP", 0, -Widgets.Round(newOffset))
    end)

    -- ── Deferred content-width init ────────────────────────────
    -- GetWidth() returns 0 on the first frame; defer to the next tick.
    local widthInitDone = false
    scroll:HookScript("OnShow", function(self)
        if widthInitDone then return end
        C_Timer.After(0, function()
            if not scroll._scrollFrame then return end
            local sfW = scroll._scrollFrame:GetWidth()
            if sfW > 0 then
                content:SetWidth(sfW)
                widthInitDone = true
            end
        end)
    end)

    -- ── Pixel updater registration ──────────────────────────────
    Widgets.AddToPixelUpdater_OnShow(scroll)

    return scroll
end
