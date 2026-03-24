local addonName, Framed = ...

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- CreateSwitch
-- A segmented toggle with an animated bottom-highlight bar.
-- Each option is { text = "Label", value = "someValue" }.
-- The highlight bar slides horizontally between segments on
-- selection change using Widgets.StartAnimation.
-- ============================================================

--- Compute the left-edge X offset (relative to switch) for segment i.
--- @param segWidth number Width of each segment in logical units
--- @param index number 1-based segment index
--- @return number
local function SegmentX(segWidth, index)
    return (index - 1) * segWidth
end

--- Apply the selected visual state to a segment button.
--- @param btn Button
local function ApplySelectedState(btn)
    btn:SetBackdropColor(
        C.Colors.accentDim[1], C.Colors.accentDim[2],
        C.Colors.accentDim[3], C.Colors.accentDim[4] or 0.3)
    btn._label:SetTextColor(
        C.Colors.textActive[1], C.Colors.textActive[2],
        C.Colors.textActive[3], C.Colors.textActive[4] or 1)
end

--- Apply the unselected visual state to a segment button.
--- @param btn Button
local function ApplyUnselectedState(btn)
    local bg = C.Colors.widget
    btn:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    btn._label:SetTextColor(
        C.Colors.textNormal[1], C.Colors.textNormal[2],
        C.Colors.textNormal[3], C.Colors.textNormal[4] or 1)
end

--- Apply the hover visual state to an unselected segment button.
--- @param btn Button
local function ApplyHoverState(btn)
    local bg = C.Colors.widget
    btn:SetBackdropColor(
        bg[1] + 0.07, bg[2] + 0.07, bg[3] + 0.07, bg[4] or 1)
    btn._label:SetTextColor(
        C.Colors.textActive[1], C.Colors.textActive[2],
        C.Colors.textActive[3], C.Colors.textActive[4] or 1)
end

--- Move the shared highlight bar to the target segment (immediate, no anim).
--- @param switch Frame The switch container
--- @param index number 1-based segment index
local function PlaceHighlight(switch, index)
    local bar = switch._highlightBar
    local segWidth = switch._segWidth
    bar:ClearAllPoints()
    Widgets.SetPoint(bar, "BOTTOMLEFT", switch, "BOTTOMLEFT", SegmentX(segWidth, index), 0)
end

--- Animate the highlight bar from its current position to the new segment.
--- @param switch Frame
--- @param fromIndex number
--- @param toIndex number
local function AnimateHighlight(switch, fromIndex, toIndex)
    local segWidth = switch._segWidth
    local fromX = SegmentX(segWidth, fromIndex)
    local toX   = SegmentX(segWidth, toIndex)

    Widgets.StartAnimation(
        switch, "highlightSlide",
        fromX, toX,
        C.Animation.durationFast,
        function(self, value)
            local bar = self._highlightBar
            bar:ClearAllPoints()
            Widgets.SetPoint(bar, "BOTTOMLEFT", self, "BOTTOMLEFT", value, 0)
        end
    )
end

--- Internal: update all segment visuals to reflect the current selection.
--- @param switch Frame
local function RefreshSegments(switch)
    for _, seg in ipairs(switch._segments) do
        if seg._value == switch._selectedValue then
            ApplySelectedState(seg)
        else
            ApplyUnselectedState(seg)
        end
    end
end

--- Internal: select a segment by index, animating the bar and refreshing visuals.
--- @param switch Frame
--- @param index number 1-based index into _segments
--- @param fireCallback boolean
local function SelectIndex(switch, index, fireCallback)
    if index < 1 or index > #switch._segments then return end

    local prevIndex = switch._selectedIndex or index
    local seg = switch._segments[index]

    switch._selectedIndex = index
    switch._selectedValue = seg._value

    -- Slide highlight bar
    if prevIndex ~= index then
        AnimateHighlight(switch, prevIndex, index)
    else
        PlaceHighlight(switch, index)
    end

    RefreshSegments(switch)

    if fireCallback and switch._onSelect then
        switch._onSelect(switch._selectedValue)
    end
end

-- ============================================================
-- Public API
-- ============================================================

--- Called with (value) when the user clicks a segment.
--- @param func function
local function SetOnSelect(switch, func)
    switch._onSelect = func
end

--- Returns the currently selected value.
--- @return any
local function GetValue(switch)
    return switch._selectedValue
end

--- Programmatic selection — updates visual, does NOT fire callback.
--- @param value any
local function SetValue(switch, value)
    for i, seg in ipairs(switch._segments) do
        if seg._value == value then
            SelectIndex(switch, i, false)
            return
        end
    end
end

--- Dims all segments and disables interaction when enabled == false.
--- @param bool boolean
local function SetEnabled(switch, bool)
    switch._enabled = bool
    local alpha = bool and 1 or 0.4
    for _, seg in ipairs(switch._segments) do
        seg:SetAlpha(alpha)
        seg:EnableMouse(bool)
    end
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a segmented toggle switch.
--- @param parent Frame
--- @param width number Logical total width
--- @param height number Logical height
--- @param options table Array of { text = string, value = any }
--- @return Frame switch
function Widgets.CreateSwitch(parent, width, height, options)
    options = options or {}
    local numOptions = #options

    -- Container
    local switch = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Widgets.SetSize(switch, width, height)
    Widgets.ApplyBackdrop(switch, C.Colors.widget, C.Colors.border)

    switch._segments      = {}
    switch._selectedValue = nil
    switch._selectedIndex = nil
    switch._onSelect      = nil

    -- Attach public API as methods
    switch.SetOnSelect = function(self, func) SetOnSelect(self, func) end
    switch.GetValue    = function(self)       return GetValue(self) end
    switch.SetValue    = function(self, v)    SetValue(self, v) end
    switch.SetEnabled  = function(self, bool) SetEnabled(self, bool) end

    Widgets.ApplyBaseMixin(switch)
    Widgets.AttachTooltipScripts(switch)

    if numOptions == 0 then return switch end

    local segWidth = width / numOptions
    switch._segWidth = segWidth

    -- --------------------------------------------------------
    -- Segment buttons
    -- --------------------------------------------------------
    for i, opt in ipairs(options) do
        local seg = CreateFrame("Button", nil, switch, "BackdropTemplate")
        Widgets.SetSize(seg, segWidth, height)
        Widgets.SetPoint(seg, "TOPLEFT", switch, "TOPLEFT", SegmentX(segWidth, i), 0)

        -- Backdrop: black border between segments; left segment gets no left border
        Widgets.ApplyBackdrop(seg, C.Colors.widget, C.Colors.border)

        seg._value = opt.value
        seg._index = i

        -- Label
        local label = Widgets.CreateFontString(seg, C.Font.sizeSmall, C.Colors.textNormal)
        label:SetPoint("CENTER", seg, "CENTER", 0, 0)
        label:SetText(opt.text or "")
        seg._label = label

        -- Hover scripts
        seg:SetScript("OnEnter", function(self)
            if not switch._enabled then return end
            if self._value ~= switch._selectedValue then
                ApplyHoverState(self)
            end
        end)
        seg:SetScript("OnLeave", function(self)
            if self._value ~= switch._selectedValue then
                ApplyUnselectedState(self)
            end
        end)

        -- Click
        seg:SetScript("OnClick", function(self)
            if not switch._enabled then return end
            SelectIndex(switch, self._index, true)
        end)

        switch._segments[i] = seg
    end

    -- --------------------------------------------------------
    -- Shared animated highlight bar (2px bottom accent line)
    -- --------------------------------------------------------
    local bar = switch:CreateTexture(nil, "OVERLAY")
    local accent = C.Colors.accent
    bar:SetColorTexture(accent[1], accent[2], accent[3], accent[4] or 1)
    bar:SetHeight(2)
    -- Width covers one segment; anchored left + right relative to switch left
    -- We use a fixed width equal to segWidth snapped pixels
    local scale = switch:GetEffectiveScale()
    local snappedSegW = Widgets.GetNearestPixelSize(segWidth, scale, 1)
    bar:SetWidth(snappedSegW)
    switch._highlightBar = bar

    -- --------------------------------------------------------
    -- Select first option by default
    -- --------------------------------------------------------
    SelectIndex(switch, 1, false)

    return switch
end
