local addonName, Framed = ...
local F = Framed

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- Slider — horizontal and vertical value sliders
-- Custom implementation (no WoW Slider widget) using
-- OnMouseDown/OnMouseUp/OnUpdate on the track frame.
-- Dual-callback pattern for performance:
--   SetOnValueChanged   → lightweight, fires during drag
--   SetAfterValueChanged → full update, fires on release
-- ============================================================

-- Track dimensions
local TRACK_THICKNESS = 6   -- height (horiz) or width (vert)

-- Thumb dimensions
local THUMB_W_HORIZ = 12
local THUMB_H_HORIZ = 16
local THUMB_W_VERT  = 16
local THUMB_H_VERT  = 12

-- Black border color for tracks and thumbs
local BLACK = { 0, 0, 0, 1 }

-- ============================================================
-- Internal helpers
-- ============================================================

--- Snap a value to the nearest step increment within [min, max].
--- @param value number
--- @param min number
--- @param max number
--- @param step number
--- @return number
local function SnapToStep(value, min, max, step)
	value = math.max(min, math.min(max, value))
	if(step and step > 0) then
		local steps = math.floor((value - min) / step + 0.5)
		value = min + steps * step
		value = math.max(min, math.min(max, value))
	end
	return value
end

--- Format a value for display.
--- Uses the slider's custom format if set, otherwise auto-detects.
--- @param value number
--- @param slider? table Optional slider with _format field
--- @return string
local function FormatValue(value, slider)
	if(slider and slider._format) then
		return string.format(slider._format, value)
	end
	if(value == math.floor(value)) then
		return tostring(math.floor(value))
	end
	return string.format('%.2f', value)
end

-- ============================================================
-- Visual update helpers
-- ============================================================

--- Update horizontal fill bar and thumb position from _value.
--- @param slider table
local function UpdateHorizVisuals(slider)
	local range = slider._max - slider._min
	local fraction = (range > 0) and ((slider._value - slider._min) / range) or 0
	fraction = math.max(0, math.min(1, fraction))

	local trackW = slider._track:GetWidth()

	-- Fill bar: anchored LEFT, width proportional
	local fillW = fraction * trackW
	if(fillW < 1) then fillW = 0 end
	slider._fill:SetWidth(fillW > 0 and fillW or 0.01)
	if(fillW > 0) then
		slider._fill:Show()
	else
		slider._fill:Hide()
	end

	-- Thumb: centered on fill position, clamped inside track
	local halfThumb = THUMB_W_HORIZ / 2
	local thumbX = fraction * trackW - halfThumb
	thumbX = math.max(-halfThumb, math.min(trackW - halfThumb, thumbX))
	slider._thumb:ClearAllPoints()
	slider._thumb:SetPoint('LEFT', slider._track, 'LEFT', thumbX, 0)

	-- Value edit box
	slider._valueText:SetText(FormatValue(slider._value, slider))
end

--- Update vertical fill bar and thumb position from _value.
--- @param slider table
local function UpdateVertVisuals(slider)
	local range = slider._max - slider._min
	local fraction = (range > 0) and ((slider._value - slider._min) / range) or 0
	fraction = math.max(0, math.min(1, fraction))

	local trackH = slider._track:GetHeight()

	-- Fill bar: anchored BOTTOM, height proportional
	local fillH = fraction * trackH
	slider._fill:SetHeight(fillH > 0 and fillH or 0.01)
	if(fillH > 0) then
		slider._fill:Show()
	else
		slider._fill:Hide()
	end

	-- Thumb: centered on fill position, clamped inside track
	local halfThumb = THUMB_H_VERT / 2
	local thumbY = fraction * trackH - halfThumb
	thumbY = math.max(-halfThumb, math.min(trackH - halfThumb, thumbY))
	slider._thumb:ClearAllPoints()
	slider._thumb:SetPoint('BOTTOM', slider._track, 'BOTTOM', 0, thumbY)

	-- Value edit box
	slider._valueText:SetText(FormatValue(slider._value, slider))
end

-- ============================================================
-- Shared slider methods (mixed into slider frame)
-- ============================================================

local SliderMixin = {}

--- Get the current slider value.
--- @return number
function SliderMixin:GetValue()
	return self._value
end

--- Set the slider value programmatically.
--- Clamps, snaps, updates visuals. Does NOT fire callbacks.
--- @param val number
function SliderMixin:SetValue(val)
	self._value = SnapToStep(val, self._min, self._max, self._step)
	if(self._orientation == 'HORIZONTAL') then
		UpdateHorizVisuals(self)
	else
		UpdateVertVisuals(self)
	end
end

--- Update the min/max range. Current value is re-clamped.
--- @param min number
--- @param max number
function SliderMixin:SetMinMaxValues(min, max)
	self._min = min
	self._max = max
	self:SetValue(self._value)
end

--- Register a lightweight callback called during drag.
--- @param func function Called with (value)
function SliderMixin:SetOnValueChanged(func)
	self._onValueChanged = func
end

--- Register a full callback called on mouse release.
--- @param func function Called with (value)
function SliderMixin:SetAfterValueChanged(func)
	self._afterValueChanged = func
end

--- Set a custom format string for the value display.
--- @param fmt string Format string (e.g., '%.2f')
function SliderMixin:SetFormat(fmt)
	self._format = fmt
	-- Refresh display with new format
	if(self._orientation == 'HORIZONTAL') then
		UpdateHorizVisuals(self)
	else
		UpdateVertVisuals(self)
	end
end

-- ============================================================
-- Drag interaction — shared between both orientations
-- ============================================================

--- Compute a value from cursor position on the track.
--- @param slider table
--- @param isVertical boolean
--- @return number Raw fraction [0,1]
local function FractionFromCursor(slider, isVertical)
	local cursorX, cursorY = GetCursorPosition()
	local scale = slider._track:GetEffectiveScale()
	cursorX = cursorX / scale
	cursorY = cursorY / scale

	if(isVertical) then
		local trackBottom = slider._track:GetBottom() or 0
		local trackH = slider._track:GetHeight()
		if(trackH <= 0) then return 0 end
		return (cursorY - trackBottom) / trackH
	else
		local trackLeft = slider._track:GetLeft() or 0
		local trackW = slider._track:GetWidth()
		if(trackW <= 0) then return 0 end
		return (cursorX - trackLeft) / trackW
	end
end

--- Apply a new fraction value to the slider and fire the lightweight callback.
--- @param slider table
--- @param fraction number [0,1]
local function ApplyFraction(slider, fraction)
	fraction = math.max(0, math.min(1, fraction))
	local raw = slider._min + fraction * (slider._max - slider._min)
	local snapped = SnapToStep(raw, slider._min, slider._max, slider._step)
	if(snapped == slider._value) then return end
	slider._value = snapped
	if(slider._orientation == 'HORIZONTAL') then
		UpdateHorizVisuals(slider)
	else
		UpdateVertVisuals(slider)
	end
	if(slider._onValueChanged) then
		slider._onValueChanged(snapped)
	end
end

--- Hook interaction scripts onto the track frame.
--- @param slider table The outer container
--- @param isVertical boolean
local function AttachInteraction(slider, isVertical)
	local track = slider._track

	track:EnableMouse(true)

	track:SetScript('OnMouseDown', function(self, button)
		if(button ~= 'LeftButton') then return end
		if(not slider:IsEnabled()) then return end
		slider._dragging = true
		ApplyFraction(slider, FractionFromCursor(slider, isVertical))
	end)

	track:SetScript('OnMouseUp', function(self, button)
		if(button ~= 'LeftButton') then return end
		slider._dragging = false
		if(slider._afterValueChanged) then
			slider._afterValueChanged(slider._value)
		end
	end)

	track:SetScript('OnUpdate', function(self)
		if(not slider._dragging) then return end
		ApplyFraction(slider, FractionFromCursor(slider, isVertical))
	end)

	-- Also allow thumb to receive mouse events and forward to track
	slider._thumb:EnableMouse(true)
	slider._thumb:SetScript('OnMouseDown', function(self, button)
		if(button ~= 'LeftButton') then return end
		if(not slider:IsEnabled()) then return end
		slider._dragging = true
	end)
	slider._thumb:SetScript('OnMouseUp', function(self, button)
		if(button ~= 'LeftButton') then return end
		slider._dragging = false
		if(slider._afterValueChanged) then
			slider._afterValueChanged(slider._value)
		end
	end)
end

-- ============================================================
-- Internal factory
-- ============================================================

--- Create a slider widget.
--- @param parent Frame
--- @param label string
--- @param size number Width (horizontal) or height (vertical)
--- @param minVal number
--- @param maxVal number
--- @param step number
--- @param orientation string 'HORIZONTAL' or 'VERTICAL'
--- @return Frame slider
local function createSliderInternal(parent, label, size, minVal, maxVal, step, orientation)
	local isVertical = (orientation == 'VERTICAL')

	-- Outer container — sized to hold label, value text, and track
	local slider = CreateFrame('Frame', nil, parent)
	Widgets.ApplyBaseMixin(slider)

	-- State
	slider._value       = minVal
	slider._min         = minVal
	slider._max         = maxVal
	slider._step        = step
	slider._dragging    = false
	slider._orientation = orientation

	-- Mix in methods
	for k, v in next, SliderMixin do
		slider[k] = v
	end

	-- --------------------------------------------------------
	-- Label font string
	-- --------------------------------------------------------
	local labelFS = Widgets.CreateFontString(slider, C.Font.sizeSmall, C.Colors.textSecondary)
	slider._labelText = labelFS
	labelFS:SetText(label or '')

	-- --------------------------------------------------------
	-- Value edit box (uses the standard EditBox widget for
	-- consistent border + accent highlight on focus)
	-- --------------------------------------------------------
	local VALUE_BOX_W = 36
	local VALUE_BOX_H = 16
	local valueBox = Widgets.CreateEditBox(slider, nil, VALUE_BOX_W, VALUE_BOX_H, 'text')
	slider._valueText = valueBox
	valueBox._editbox:SetJustifyH('CENTER')
	valueBox:SetText(FormatValue(minVal))

	-- Commit typed value on Enter or focus loss
	local function commitTypedValue()
		local raw = tonumber(valueBox:GetText())
		if(raw) then
			local snapped = SnapToStep(raw, slider._min, slider._max, slider._step)
			slider._value = snapped
			if(slider._orientation == 'HORIZONTAL') then
				UpdateHorizVisuals(slider)
			else
				UpdateVertVisuals(slider)
			end
			if(slider._afterValueChanged) then
				slider._afterValueChanged(snapped)
			end
		else
			-- Invalid input: revert to current value
			valueBox:SetText(FormatValue(slider._value, slider))
		end
	end

	valueBox:SetOnEnterPressed(commitTypedValue)
	valueBox:SetOnFocusLost(commitTypedValue)

	-- --------------------------------------------------------
	-- Track frame
	-- --------------------------------------------------------
	local track = CreateFrame('Frame', nil, slider, 'BackdropTemplate')
	slider._track = track
	Widgets.ApplyBackdrop(track, C.Colors.panel, BLACK)

	-- --------------------------------------------------------
	-- Fill texture (accent colored)
	-- --------------------------------------------------------
	local fill = track:CreateTexture(nil, 'ARTWORK')
	slider._fill = fill
	local ac = C.Colors.accent
	fill:SetColorTexture(ac[1], ac[2], ac[3], ac[4] or 1)

	-- --------------------------------------------------------
	-- Thumb frame
	-- --------------------------------------------------------
	local thumb = CreateFrame('Frame', nil, track, 'BackdropTemplate')
	slider._thumb = thumb
	Widgets.ApplyBackdrop(thumb, C.Colors.accent, BLACK)

	-- --------------------------------------------------------
	-- Layout: position all pieces based on orientation
	-- --------------------------------------------------------
	if(isVertical) then
		-- Container: width provides room for the thumb overhang, height = track + label + value
		local containerW = THUMB_W_VERT + 16  -- thumb width + breathing room
		Widgets.SetSize(slider, containerW, size + 32)  -- +32 for label + value rows

		-- Label: centered at top of container
		labelFS:SetPoint('TOP', slider, 'TOP', 0, 0)
		labelFS:SetJustifyH('CENTER')

		-- Track: centered horizontally, directly below label
		Widgets.SetSize(track, TRACK_THICKNESS, size)
		track:SetPoint('TOP', labelFS, 'BOTTOM', 0, -4)
		track:SetPoint('LEFT', slider, 'LEFT', (containerW - TRACK_THICKNESS) / 2, 0)

		-- Fill: anchored to bottom of track, grows upward
		fill:SetPoint('BOTTOMLEFT', track, 'BOTTOMLEFT', 0, 0)
		fill:SetPoint('BOTTOMRIGHT', track, 'BOTTOMRIGHT', 0, 0)

		-- Thumb: centered horizontally on track, vertical position set by UpdateVertVisuals
		Widgets.SetSize(thumb, THUMB_W_VERT, THUMB_H_VERT)

		-- Value: below track, centered
		valueBox:SetPoint('TOP', track, 'BOTTOM', 0, -4)

	else
		-- Horizontal: container width = size, height = label row + track
		local labelH = 14  -- approximate label row height
		Widgets.SetSize(slider, size, labelH + TRACK_THICKNESS + 6)

		-- Label: top-left
		labelFS:SetPoint('TOPLEFT', slider, 'TOPLEFT', 0, 0)
		labelFS:SetJustifyH('LEFT')

		-- Value: top-right
		valueBox:SetPoint('TOPRIGHT', slider, 'TOPRIGHT', 0, 2)

		-- Track: below the label row
		Widgets.SetSize(track, size, TRACK_THICKNESS)
		track:SetPoint('TOPLEFT', slider, 'TOPLEFT', 0, -(labelH + 4))

		-- Fill: anchored left, grows right
		fill:SetPoint('TOPLEFT', track, 'TOPLEFT', 0, 0)
		fill:SetPoint('BOTTOMLEFT', track, 'BOTTOMLEFT', 0, 0)

		-- Thumb: centered vertically on track
		Widgets.SetSize(thumb, THUMB_W_HORIZ, THUMB_H_HORIZ)
	end

	-- --------------------------------------------------------
	-- Attach interaction
	-- --------------------------------------------------------
	AttachInteraction(slider, isVertical)

	-- --------------------------------------------------------
	-- Tooltip support
	-- --------------------------------------------------------
	Widgets.AttachTooltipScripts(slider)

	-- --------------------------------------------------------
	-- Initial visual state
	-- --------------------------------------------------------
	if(isVertical) then
		UpdateVertVisuals(slider)
	else
		UpdateHorizVisuals(slider)
	end

	return slider
end

-- ============================================================
-- Public constructors
-- ============================================================

--- Create a horizontal slider.
--- @param parent Frame
--- @param label string Display label shown above the track
--- @param width number Total width of the slider widget
--- @param minVal number Minimum value
--- @param maxVal number Maximum value
--- @param step number Snap increment
--- @return Frame slider
function Widgets.CreateSlider(parent, label, width, minVal, maxVal, step)
	return createSliderInternal(parent, label, width, minVal, maxVal, step, 'HORIZONTAL')
end

--- Create a vertical slider.
--- @param parent Frame
--- @param label string Display label shown above the track
--- @param height number Height of the track portion
--- @param minVal number Minimum value
--- @param maxVal number Maximum value
--- @param step number Snap increment
--- @return Frame slider
function Widgets.CreateVerticalSlider(parent, label, height, minVal, maxVal, step)
	return createSliderInternal(parent, label, height, minVal, maxVal, step, 'VERTICAL')
end
