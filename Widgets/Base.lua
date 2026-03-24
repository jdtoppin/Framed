local addonName, Framed = ...

local Widgets = {}
Framed.Widgets = Widgets

local C = Framed.Constants

-- ============================================================
-- Pixel-Perfect Utilities
-- Based on AbstractFramework's approach (GPL v3 compatible).
-- Core idea: 768.0 / physicalScreenHeight gives the pixel factor.
-- Store logical values on frames, derive snapped values on apply.
-- Re-snap when scale changes.
-- ============================================================

local physicalScreenHeight = select(2, GetPhysicalScreenSize())
local pixelFactor = 768.0 / physicalScreenHeight

--- Round a number to the nearest integer.
--- @param value number
--- @return number
function Widgets.Round(value)
    return math.floor(value + 0.5)
end

--- Snap a UI-unit size to the nearest physical pixel boundary.
--- @param uiUnitSize number The logical size in UI units
--- @param layoutScale number The frame's GetEffectiveScale()
--- @param minPixels? number Minimum pixel count (e.g., 1 for borders)
--- @return number The pixel-snapped size in UI units
function Widgets.GetNearestPixelSize(uiUnitSize, layoutScale, minPixels)
    local numPixels = Widgets.Round((uiUnitSize * layoutScale) / pixelFactor)
    if minPixels then
        numPixels = math.max(numPixels, minPixels)
    end
    return numPixels * pixelFactor / layoutScale
end

--- Set point with pixel-perfect snapping.
--- Stores logical values on frame._points for re-snapping on scale change.
--- @param frame Region
--- @param point string Anchor point
--- @param relativeTo? Region Relative frame
--- @param relativePoint? string Relative anchor
--- @param x? number X offset (logical)
--- @param y? number Y offset (logical)
function Widgets.SetPoint(frame, point, relativeTo, relativePoint, x, y)
    x = x or 0
    y = y or 0

    -- Store logical values for re-snapping
    if not frame._points then frame._points = {} end
    frame._points[point] = { point, relativeTo, relativePoint, x, y }

    -- Apply pixel-snapped values
    local scale = frame:GetEffectiveScale()
    frame:SetPoint(point, relativeTo, relativePoint,
        Widgets.GetNearestPixelSize(x, scale),
        Widgets.GetNearestPixelSize(y, scale))
end

--- Set size with pixel-perfect snapping.
--- Stores logical values on frame._width/_height for re-snapping.
--- @param frame Region
--- @param width number Logical width
--- @param height number Logical height
function Widgets.SetSize(frame, width, height)
    frame._width = width
    frame._height = height
    local scale = frame:GetEffectiveScale()
    frame:SetSize(
        Widgets.GetNearestPixelSize(width, scale, 1),
        Widgets.GetNearestPixelSize(height, scale, 1))
end

--- Re-snap all stored points on a frame (call after scale change).
--- @param frame Region
function Widgets.RePoint(frame)
    if not frame._points then return end
    frame:ClearAllPoints()
    local scale = frame:GetEffectiveScale()
    for _, p in pairs(frame._points) do
        frame:SetPoint(p[1], p[2], p[3],
            Widgets.GetNearestPixelSize(p[4], scale),
            Widgets.GetNearestPixelSize(p[5], scale))
    end
end

--- Re-snap stored size on a frame (call after scale change).
--- @param frame Region
function Widgets.ReSize(frame)
    if not frame._width or not frame._height then return end
    local scale = frame:GetEffectiveScale()
    frame:SetSize(
        Widgets.GetNearestPixelSize(frame._width, scale, 1),
        Widgets.GetNearestPixelSize(frame._height, scale, 1))
end

--- Full pixel update for a frame (re-snap points + size).
--- @param frame Region
function Widgets.UpdatePixels(frame)
    Widgets.RePoint(frame)
    Widgets.ReSize(frame)
end

-- ============================================================
-- Pixel Updater Registry
-- Tracks frames that need re-snapping on scale change.
-- Two strategies: Auto (always-visible) and OnShow (intermittent).
-- ============================================================

local pixelUpdaterAuto = {}     -- frames always visible
local pixelUpdaterOnShow = {}   -- frames shown intermittently
local lastPixelUpdateTime = 0

--- Register a frame for automatic pixel updates (always-visible frames).
--- @param frame Region
--- @param updateFunc? function Custom update function (defaults to UpdatePixels)
function Widgets.AddToPixelUpdater_Auto(frame, updateFunc)
    pixelUpdaterAuto[frame] = updateFunc or Widgets.UpdatePixels
end

--- Register a frame for OnShow pixel updates (panels, dialogs).
--- Re-snaps only when shown AND a pixel update has occurred since last show.
--- @param frame Region
--- @param updateFunc? function Custom update function
function Widgets.AddToPixelUpdater_OnShow(frame, updateFunc)
    local fn = updateFunc or Widgets.UpdatePixels
    pixelUpdaterOnShow[frame] = {
        func = fn,
        lastUpdate = 0,
    }
    frame:HookScript("OnShow", function(self)
        local entry = pixelUpdaterOnShow[self]
        if entry and entry.lastUpdate < lastPixelUpdateTime then
            entry.func(self)
            entry.lastUpdate = lastPixelUpdateTime
        end
    end)
end

--- Remove a frame from all pixel updater registries.
--- @param frame Region
function Widgets.RemoveFromPixelUpdater(frame)
    pixelUpdaterAuto[frame] = nil
    pixelUpdaterOnShow[frame] = nil
end

--- Run all auto pixel updates and mark time for OnShow updates.
local function RunPixelUpdates()
    lastPixelUpdateTime = GetTime()
    for frame, fn in pairs(pixelUpdaterAuto) do
        fn(frame)
    end
end

-- Scale change detection: debounced 1-second timer
local scaleChangeTimer

local function OnScaleChanged()
    if scaleChangeTimer then scaleChangeTimer:Cancel() end
    scaleChangeTimer = C_Timer.NewTimer(1, function()
        -- Recalculate pixel factor in case physical resolution changed
        physicalScreenHeight = select(2, GetPhysicalScreenSize())
        pixelFactor = 768.0 / physicalScreenHeight
        RunPixelUpdates()
    end)
end

-- Register for scale change events after first frame renders
local scaleFrame = CreateFrame("Frame")
scaleFrame:RegisterEvent("FIRST_FRAME_RENDERED")
scaleFrame:SetScript("OnEvent", function(self, event)
    if event == "FIRST_FRAME_RENDERED" then
        self:RegisterEvent("UI_SCALE_CHANGED")
        hooksecurefunc(UIParent, "SetScale", OnScaleChanged)
        self:UnregisterEvent("FIRST_FRAME_RENDERED")
    elseif event == "UI_SCALE_CHANGED" then
        OnScaleChanged()
    end
end)

-- ============================================================
-- Backdrop Utilities
-- ============================================================

local backdropInfo = {
    bgFile = "Interface\\BUTTONS\\WHITE8x8",
    edgeFile = "Interface\\BUTTONS\\WHITE8x8",
    edgeSize = 1,
}

--- Apply the standard Framed backdrop to a frame.
--- @param frame Frame Must inherit BackdropTemplate
--- @param bgColor? table {r, g, b, a} defaults to Constants.Colors.panel
--- @param borderColor? table {r, g, b, a} defaults to Constants.Colors.border
function Widgets.ApplyBackdrop(frame, bgColor, borderColor)
    frame:SetBackdrop(backdropInfo)
    bgColor = bgColor or C.Colors.panel
    borderColor = borderColor or C.Colors.border
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
end

--- Set backdrop highlight state (accent border + lighter background).
--- @param frame Frame
--- @param highlighted boolean
function Widgets.SetBackdropHighlight(frame, highlighted)
    if highlighted then
        local accent = C.Colors.accent
        frame:SetBackdropBorderColor(accent[1], accent[2], accent[3], accent[4] or 1)
        -- Lighten background slightly
        local bg = frame._bgColor or C.Colors.panel
        frame:SetBackdropColor(bg[1] + 0.05, bg[2] + 0.05, bg[3] + 0.05, bg[4] or 1)
    else
        local border = frame._borderColor or C.Colors.border
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
        local bg = frame._bgColor or C.Colors.panel
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    end
end

-- ============================================================
-- Color Utilities
-- ============================================================

--- Unpack a color table into r, g, b, a.
--- @param color table {r, g, b, a}
--- @return number, number, number, number
function Widgets.UnpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

--- Interpolate between two values.
--- @param a number Start value
--- @param b number End value
--- @param t number Progress 0-1
--- @return number
function Widgets.Lerp(a, b, t)
    return a + (b - a) * t
end

-- ============================================================
-- Font Utilities
-- ============================================================

--- Create a font string with standard Framed styling.
--- @param parent Frame
--- @param size? number Font size (defaults to Constants.Font.sizeNormal)
--- @param color? table Color table (defaults to Constants.Colors.textNormal)
--- @return FontString
function Widgets.CreateFontString(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    size = size or C.Font.sizeNormal
    fs:SetFont(STANDARD_TEXT_FONT, size, "")
    fs:SetShadowOffset(1, -1)
    color = color or C.Colors.textNormal
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    return fs
end

-- ============================================================
-- Animation Utilities (OnUpdate-based)
-- ============================================================

--- Start a simple fade/interpolation on a frame.
--- Stores animation state on frame._anim table.
--- @param frame Frame
--- @param key string Animation identifier
--- @param fromVal number Start value
--- @param toVal number End value
--- @param duration number Duration in seconds
--- @param onUpdate function Called with (frame, currentValue) each tick
--- @param onComplete? function Called when animation finishes
function Widgets.StartAnimation(frame, key, fromVal, toVal, duration, onUpdate, onComplete)
    if not frame._anim then
        frame._anim = {}
    end

    frame._anim[key] = {
        from = fromVal,
        to = toVal,
        duration = duration,
        elapsed = 0,
        onUpdate = onUpdate,
        onComplete = onComplete,
    }

    -- Only set OnUpdate if not already set for animations
    if not frame._animOnUpdate then
        frame._animOnUpdate = true
        frame:HookScript("OnUpdate", function(self, elapsed)
            if not self._anim then return end
            local hasActive = false
            for animKey, anim in pairs(self._anim) do
                anim.elapsed = anim.elapsed + elapsed
                local progress = math.min(anim.elapsed / anim.duration, 1)
                local value = Widgets.Lerp(anim.from, anim.to, progress)
                anim.onUpdate(self, value)
                if progress >= 1 then
                    self._anim[animKey] = nil
                    if anim.onComplete then
                        anim.onComplete(self)
                    end
                else
                    hasActive = true
                end
            end
        end)
    end
end

-- ============================================================
-- Fade Utilities (built on StartAnimation)
-- ============================================================

--- Fade a frame in (alpha 0 → 1). Shows the frame first.
--- @param frame Frame
--- @param duration? number Defaults to Constants.Animation.durationNormal
--- @param onComplete? function Called when fade finishes
function Widgets.FadeIn(frame, duration, onComplete)
    duration = duration or C.Animation.durationNormal
    frame:SetAlpha(0)
    frame:Show()
    Widgets.StartAnimation(frame, "fade", 0, 1, duration,
        function(self, value) self:SetAlpha(value) end,
        onComplete)
end

--- Fade a frame out (alpha 1 → 0). Hides the frame on complete.
--- @param frame Frame
--- @param duration? number Defaults to Constants.Animation.durationNormal
--- @param onComplete? function Called after hide
function Widgets.FadeOut(frame, duration, onComplete)
    duration = duration or C.Animation.durationNormal
    Widgets.StartAnimation(frame, "fade", frame:GetAlpha(), 0, duration,
        function(self, value) self:SetAlpha(value) end,
        function(self)
            self:Hide()
            if onComplete then onComplete(self) end
        end)
end

--- Cross-fade: fade one frame out while fading another in.
--- @param frameOut Frame Frame to fade out and hide
--- @param frameIn Frame Frame to fade in and show
--- @param duration? number Defaults to Constants.Animation.durationNormal
function Widgets.CrossFade(frameOut, frameIn, duration)
    duration = duration or C.Animation.durationNormal
    Widgets.FadeOut(frameOut, duration)
    Widgets.FadeIn(frameIn, duration)
end

-- ============================================================
-- Drag Utilities
-- ============================================================

--- Make a frame draggable within its parent bounds.
--- Handles RegisterForDrag, clamp-to-parent, and callbacks.
--- @param frame Frame The frame to make draggable
--- @param onDragStart? function Called when drag begins (frame)
--- @param onDragStop? function Called when drag ends (frame, x, y)
--- @param clampToParent? boolean Clamp within parent bounds (default true)
function Widgets.MakeDraggable(frame, onDragStart, onDragStop, clampToParent)
    if clampToParent == nil then clampToParent = true end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    if clampToParent then
        frame:SetClampedToScreen(true)
    end

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
        if onDragStart then onDragStart(self) end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if onDragStop then onDragStop(self, x, y) end
    end)
end

--- Create a reorderable drag-sort list.
--- Items can be dragged up/down to change order. Visual feedback:
--- source item highlights, insertion line shows drop position,
--- items shift to make room.
--- @param parent Frame Container frame
--- @param itemHeight number Height of each item row
--- @param onReorder function Called with (newOrder) when order changes
---        newOrder is an array of the original item indices in new order
--- @return table sorter The drag sorter controller
function Widgets.CreateDragSorter(parent, itemHeight, onReorder)
    local sorter = {
        items = {},       -- array of item frames
        order = {},       -- current order (indices into items)
        itemHeight = itemHeight,
        onReorder = onReorder,
        parent = parent,
    }

    local insertLine = parent:CreateTexture(nil, "OVERLAY")
    insertLine:SetHeight(2)
    insertLine:SetColorTexture(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 0.8)
    insertLine:Hide()
    sorter.insertLine = insertLine

    --- Add an item frame to the sorter.
    --- @param itemFrame Frame The frame representing this item
    function sorter:AddItem(itemFrame)
        local index = #self.items + 1
        self.items[index] = itemFrame
        self.order[index] = index
        itemFrame._sortIndex = index

        itemFrame:EnableMouse(true)
        itemFrame:RegisterForDrag("LeftButton")

        itemFrame:SetScript("OnDragStart", function(item)
            item._dragging = true
            item:SetAlpha(0.5)
            item:SetFrameStrata("TOOLTIP")
            item:StartMoving()
            self.insertLine:Show()
        end)

        itemFrame:SetScript("OnDragStop", function(item)
            item._dragging = false
            item:SetAlpha(1)
            item:SetFrameStrata(self.parent:GetFrameStrata())
            item:StopMovingOrSizing()
            self.insertLine:Hide()

            -- Determine drop position from cursor Y
            local _, cursorY = GetCursorPosition()
            local scale = self.parent:GetEffectiveScale()
            cursorY = cursorY / scale

            local dropIndex = self:GetDropIndex(cursorY)
            self:ReorderItem(item._sortIndex, dropIndex)
        end)

        itemFrame:SetScript("OnUpdate", function(item)
            if not item._dragging then return end
            -- Update insertion line position
            local _, cursorY = GetCursorPosition()
            local scale = self.parent:GetEffectiveScale()
            cursorY = cursorY / scale
            local dropIndex = self:GetDropIndex(cursorY)
            self:UpdateInsertLine(dropIndex)
        end)

        self:Layout()
    end

    --- Get the drop index based on cursor Y position.
    function sorter:GetDropIndex(cursorY)
        local parentBottom = self.parent:GetBottom() or 0
        local relativeY = cursorY - parentBottom
        local index = math.floor((self.parent:GetHeight() - relativeY) / self.itemHeight) + 1
        return math.max(1, math.min(index, #self.items))
    end

    --- Update insertion line visual position.
    function sorter:UpdateInsertLine(dropIndex)
        self.insertLine:ClearAllPoints()
        local yOffset = -(dropIndex - 1) * self.itemHeight
        self.insertLine:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 0, yOffset)
        self.insertLine:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", 0, yOffset)
    end

    --- Move an item from one position to another and re-layout.
    function sorter:ReorderItem(fromIndex, toIndex)
        if fromIndex == toIndex then
            self:Layout()
            return
        end
        local item = table.remove(self.order, fromIndex)
        table.insert(self.order, toIndex, item)
        self:Layout()
        if self.onReorder then
            self.onReorder(self.order)
        end
    end

    --- Re-layout all items in current order.
    function sorter:Layout()
        for i, origIndex in ipairs(self.order) do
            local item = self.items[origIndex]
            item._sortIndex = i
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 0, -(i - 1) * self.itemHeight)
            item:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", 0, -(i - 1) * self.itemHeight)
            item:SetHeight(self.itemHeight)
        end
    end

    return sorter
end

-- ============================================================
-- Base Widget Mixin
-- ============================================================

--- Mixin applied to all Framed widgets. Provides enabled state,
--- tooltip support, and standard script management.
Widgets.BaseWidgetMixin = {}

function Widgets.BaseWidgetMixin:SetEnabled(enabled)
    self._enabled = enabled
    if self.UpdateEnabledState then
        self:UpdateEnabledState()
    end
end

function Widgets.BaseWidgetMixin:IsEnabled()
    return self._enabled ~= false
end

--- Attach a tooltip to this widget.
--- @param title string Tooltip title
--- @param body? string Tooltip body text
function Widgets.BaseWidgetMixin:SetWidgetTooltip(title, body)
    self._tooltipTitle = title
    self._tooltipBody = body
end

--- Apply the base mixin to a frame.
--- @param frame Frame
function Widgets.ApplyBaseMixin(frame)
    for k, v in pairs(Widgets.BaseWidgetMixin) do
        frame[k] = v
    end
    frame._enabled = true
end
