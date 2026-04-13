local addonName, Framed = ...
local F = Framed

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- Color Scheme Definitions
-- ============================================================

local function GetColorScheme(colorScheme)
	if(type(colorScheme) == 'table') then
		-- Custom {normalColor, hoverColor} table
		return {
			bg          = colorScheme[1],
			hoverBg     = colorScheme[2],
			border      = C.Colors.border,
			hoverBorder = C.Colors.accent,
			textColor   = C.Colors.textNormal,
		}
	end

	colorScheme = colorScheme or 'widget'

	if(colorScheme == 'accent') then
		return {
			bg          = C.Colors.accentDim,
			hoverBg     = C.Colors.accentHover,
			border      = C.Colors.accent,
			hoverBorder = C.Colors.accent,
			textColor   = C.Colors.textActive,
		}
	elseif(colorScheme == 'green') then
		local bg     = { 0.15, 0.30, 0.15, 1 }
		local hoverBg = { 0.20, 0.38, 0.20, 1 }
		return {
			bg          = bg,
			hoverBg     = hoverBg,
			border      = { 0.2, 0.5, 0.2, 1 },
			hoverBorder = { 0.3, 0.7, 0.3, 1 },
			textColor   = C.Colors.textNormal,
		}
	elseif(colorScheme == 'red') then
		local bg     = { 0.30, 0.15, 0.15, 1 }
		local hoverBg = { 0.38, 0.20, 0.20, 1 }
		return {
			bg          = bg,
			hoverBg     = hoverBg,
			border      = { 0.5, 0.2, 0.2, 1 },
			hoverBorder = { 0.7, 0.3, 0.3, 1 },
			textColor   = C.Colors.textNormal,
		}
	else
		-- 'widget' (default)
		local bg     = C.Colors.widget
		local hoverBg = { bg[1] + 0.07, bg[2] + 0.07, bg[3] + 0.07, bg[4] or 1 }
		return {
			bg          = bg,
			hoverBg     = hoverBg,
			border      = C.Colors.border,
			hoverBorder = C.Colors.accent,
			textColor   = C.Colors.textNormal,
		}
	end
end

-- ============================================================
-- CreateButton
-- A labeled button supporting accent/widget/green/red or custom
-- color schemes, disabled state, and hover highlighting.
-- ============================================================

--- Create a standard labeled button.
--- @param parent Frame Parent frame
--- @param text string Button label
--- @param colorScheme? string|table 'accent'|'widget'|'green'|'red' or {normalColor, hoverColor}
--- @param width? number Logical width (defaults to 120)
--- @param height? number Logical height (defaults to 22)
--- @return Button
function Widgets.CreateButton(parent, text, colorScheme, width, height)
	width  = width  or 120
	height = height or 22

	local scheme = GetColorScheme(colorScheme)

	local button = CreateFrame('Button', nil, parent, 'BackdropTemplate')
	button._bgColor     = scheme.bg
	button._borderColor = scheme.border
	button._scheme      = scheme

	Widgets.ApplyBackdrop(button, scheme.bg, scheme.border)
	Widgets.SetSize(button, width, height)
	button:EnableMouse(true)

	-- Label (two-point anchoring for truncation at small widths)
	local label = Widgets.CreateFontString(button, C.Font.sizeNormal, scheme.textColor)
	label:ClearAllPoints()
	label:SetPoint('LEFT', button, 'LEFT', 4, 0)
	label:SetPoint('RIGHT', button, 'RIGHT', -4, 0)
	label:SetJustifyH('CENTER')
	label:SetWordWrap(false)
	label:SetText(text or '')
	button._label = label

	-- Hover/Leave handlers
	button:SetScript('OnEnter', function(self)
		if(not self:IsEnabled()) then return end
		-- Swap to hover colors directly (SetBackdropHighlight uses accent for all;
		-- buttons with custom hover need their own hoverBg)
		local s = self._scheme
		self:SetBackdropColor(s.hoverBg[1], s.hoverBg[2], s.hoverBg[3], s.hoverBg[4] or 1)
		local hb = s.hoverBorder
		self:SetBackdropBorderColor(hb[1], hb[2], hb[3], hb[4] or 1)
		self._label:SetTextColor(1, 1, 1, 1)
		if(Widgets.ShowTooltip and self._tooltipTitle) then
			Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
		elseif(Widgets.ShowTooltip and self._label:IsTruncated()) then
			Widgets.ShowTooltip(self, self._label:GetText())
		end
	end)

	button:SetScript('OnLeave', function(self)
		-- If this button is selected in a ButtonGroup, don't reset visuals
		if(self._groupSelected) then
			if(Widgets.HideTooltip) then
				Widgets.HideTooltip()
			end
			return
		end
		local s = self._scheme
		self:SetBackdropColor(s.bg[1], s.bg[2], s.bg[3], s.bg[4] or 1)
		local bc = s.border
		self:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
		if(self:IsEnabled()) then
			local tc = s.textColor
			self._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
		if(Widgets.HideTooltip) then
			Widgets.HideTooltip()
		end
	end)

	--- Set the button label text.
	--- @param newText string
	function button:SetText(newText)
		self._label:SetText(newText or '')
	end

	--- Set the click handler.
	--- @param func function
	function button:SetOnClick(func)
		self:SetScript('OnClick', func)
	end

	--- Update visual state to reflect enabled/disabled.
	function button:UpdateEnabledState()
		if(self:IsEnabled()) then
			local s = self._scheme
			self:SetBackdropColor(s.bg[1], s.bg[2], s.bg[3], s.bg[4] or 1)
			local bc = s.border
			self:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
			local tc = s.textColor
			self._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
			self:EnableMouse(true)
		else
			-- Dimmed background
			local s = self._scheme
			self:SetBackdropColor(s.bg[1] * 0.6, s.bg[2] * 0.6, s.bg[3] * 0.6, s.bg[4] or 1)
			local bc = s.border
			self:SetBackdropBorderColor(bc[1] * 0.5, bc[2] * 0.5, bc[3] * 0.5, bc[4] or 1)
			local td = C.Colors.textDisabled
			self._label:SetTextColor(td[1], td[2], td[3], td[4] or 1)
			self:EnableMouse(false)
		end
	end

	Widgets.ApplyBaseMixin(button)

	return button
end

-- ============================================================
-- CreateIconButton
-- A square button showing a tinted icon texture. No label.
-- ============================================================

--- Create a square icon button.
--- @param parent Frame Parent frame
--- @param iconPath string Texture path
--- @param size? number Logical size in pixels (defaults to 20)
--- @return Button
function Widgets.CreateIconButton(parent, iconPath, size)
	size = size or 20

	local button = CreateFrame('Button', nil, parent, 'BackdropTemplate')
	button._bgColor     = C.Colors.widget
	button._borderColor = C.Colors.border

	Widgets.ApplyBackdrop(button, C.Colors.widget, C.Colors.border)
	Widgets.SetSize(button, size, size)
	button:EnableMouse(true)

	-- Icon texture (2px padding on each side)
	local iconSize = size - 4
	local icon = button:CreateTexture(nil, 'ARTWORK')
	icon:SetPoint('CENTER', button, 'CENTER', 0, 0)
	icon:SetSize(iconSize, iconSize)
	icon:SetTexture(iconPath)
	local ts = C.Colors.textSecondary
	icon:SetVertexColor(ts[1], ts[2], ts[3], ts[4] or 1)
	button._icon = icon

	button:SetScript('OnEnter', function(self)
		self._icon:SetVertexColor(1, 1, 1, 1)
		Widgets.SetBackdropHighlight(self, true)
		if(Widgets.ShowTooltip and self._tooltipTitle) then
			Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
		end
	end)

	button:SetScript('OnLeave', function(self)
		local ts2 = C.Colors.textSecondary
		self._icon:SetVertexColor(ts2[1], ts2[2], ts2[3], ts2[4] or 1)
		Widgets.SetBackdropHighlight(self, false)
		if(Widgets.HideTooltip) then
			Widgets.HideTooltip()
		end
	end)

	--- Set the click handler.
	--- @param func function
	function button:SetOnClick(func)
		self:SetScript('OnClick', func)
	end

	Widgets.ApplyBaseMixin(button)

	return button
end

-- ============================================================
-- CreateCheckButton
-- A toggle switch with a label. Slides left/right with animation.
-- Accent color when enabled, grey when disabled.
-- ============================================================

local TOGGLE_W       = 28   -- track width
local TOGGLE_H       = 14   -- track height
local THUMB_SIZE     = 10   -- thumb square size
local THUMB_PAD      = 2    -- padding inside the track
local TOGGLE_SPACING = 6    -- gap between toggle and label
local TOGGLE_TRAVEL  = TOGGLE_W - THUMB_SIZE - THUMB_PAD * 2  -- thumb slide distance

--- Create a labeled toggle switch.
--- @param parent Frame Parent frame
--- @param label string Label text shown to the right of the toggle
--- @param callback? function Called with (checked) on toggle
--- @return Frame
function Widgets.CreateCheckButton(parent, label, callback)
	local frame = CreateFrame('Frame', nil, parent)
	frame._checked = false

	-- Toggle track (rounded-ish via backdrop)
	local track = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
	track:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	Widgets.SetSize(track, TOGGLE_W, TOGGLE_H)
	track:ClearAllPoints()
	Widgets.SetPoint(track, 'LEFT', frame, 'LEFT', 0, 0)
	frame._track = track

	-- Thumb (the sliding knob)
	local thumb = CreateFrame('Frame', nil, track)
	Widgets.SetSize(thumb, THUMB_SIZE, THUMB_SIZE)
	thumb:SetPoint('LEFT', track, 'LEFT', THUMB_PAD, 0)
	frame._thumb = thumb

	local thumbTex = thumb:CreateTexture(nil, 'OVERLAY')
	thumbTex:SetAllPoints(thumb)
	thumbTex:SetColorTexture(1, 1, 1, 1)
	frame._thumbTex = thumbTex

	-- Label FontString to the right of the track
	local labelText = Widgets.CreateFontString(frame, C.Font.sizeSmall, C.Colors.textNormal)
	labelText:ClearAllPoints()
	Widgets.SetPoint(labelText, 'LEFT', track, 'RIGHT', TOGGLE_SPACING, 0)
	labelText:SetText(label or '')
	frame._labelText = labelText

	-- Size the outer frame
	frame:SetHeight(TOGGLE_H)
	frame:SetWidth(TOGGLE_W + TOGGLE_SPACING + (labelText:GetStringWidth() or 80))

	-- Visual update (no animation — used for initial state / SetChecked)
	local function ApplyVisual(checked)
		local ac = C.Colors.accent
		local grey = C.Colors.widget
		if(checked) then
			track:SetBackdropColor(ac[1], ac[2], ac[3], ac[4] or 1)
			track:SetBackdropBorderColor(ac[1], ac[2], ac[3], ac[4] or 1)
			thumb:ClearAllPoints()
			thumb:SetPoint('LEFT', track, 'LEFT', THUMB_PAD + TOGGLE_TRAVEL, 0)
		else
			track:SetBackdropColor(grey[1], grey[2], grey[3], grey[4] or 1)
			track:SetBackdropBorderColor(0, 0, 0, 1)
			thumb:ClearAllPoints()
			thumb:SetPoint('LEFT', track, 'LEFT', THUMB_PAD, 0)
		end
	end

	-- Animated transition
	local function AnimateToggle(checked)
		local ac = C.Colors.accent
		local grey = C.Colors.widget
		local fromX = checked and THUMB_PAD or (THUMB_PAD + TOGGLE_TRAVEL)
		local toX   = checked and (THUMB_PAD + TOGGLE_TRAVEL) or THUMB_PAD

		-- Animate thumb position
		Widgets.StartAnimation(track, 'toggle', fromX, toX, C.Animation.durationFast,
			function(self, value)
				thumb:ClearAllPoints()
				thumb:SetPoint('LEFT', track, 'LEFT', Widgets.Round(value), 0)
				-- Interpolate track color
				local t = (value - THUMB_PAD) / TOGGLE_TRAVEL
				local r = Widgets.Lerp(grey[1], ac[1], t)
				local g = Widgets.Lerp(grey[2], ac[2], t)
				local b = Widgets.Lerp(grey[3], ac[3], t)
				track:SetBackdropColor(r, g, b, 1)
				track:SetBackdropBorderColor(
					checked and Widgets.Lerp(0, ac[1], t) or Widgets.Lerp(ac[1], 0, 1 - t),
					checked and Widgets.Lerp(0, ac[2], t) or Widgets.Lerp(ac[2], 0, 1 - t),
					checked and Widgets.Lerp(0, ac[3], t) or Widgets.Lerp(ac[3], 0, 1 - t), 1)
			end,
			function()
				ApplyVisual(checked)
			end)
	end

	-- Click handling on the whole frame
	frame:EnableMouse(true)
	frame:SetScript('OnMouseDown', function(self, mouseButton)
		if(mouseButton ~= 'LeftButton') then return end
		if(not self:IsEnabled()) then return end
		self._checked = not self._checked
		AnimateToggle(self._checked)
		if(callback) then callback(self._checked) end
	end)

	frame:SetScript('OnEnter', function(self)
		if(Widgets.ShowTooltip and self._tooltipTitle) then
			Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
		end
	end)

	frame:SetScript('OnLeave', function(self)
		if(Widgets.HideTooltip) then
			Widgets.HideTooltip()
		end
	end)

	--- Get the current checked state.
	--- @return boolean
	function frame:GetChecked()
		return self._checked
	end

	--- Set the checked state without firing the callback.
	--- @param checked boolean
	function frame:SetChecked(checked)
		self._checked = checked
		ApplyVisual(checked)
	end

	function frame:UpdateEnabledState()
		local enabled = self:IsEnabled()
		self:SetAlpha(enabled and 1 or 0.35)
		self:EnableMouse(enabled)
	end

	Widgets.ApplyBaseMixin(frame)

	return frame
end

-- ============================================================
-- CreateButtonGroup
-- Wraps existing Button frames into a mutually exclusive
-- (radio-style) selection group.
-- ============================================================

--- Wrap existing buttons as a radio group.
--- Each button must have a `.value` field set by the caller.
--- @param buttons table Array of Button frames
--- @param onSelect? function Called with (value, button) on selection
--- @return table group Controller table (not a frame)
function Widgets.CreateButtonGroup(buttons, onSelect)
	local group = {
		_buttons  = buttons,
		_selected = nil,
		_onSelect = onSelect,
	}

	local function ApplySelected(btn, selected)
		btn._groupSelected = selected
		if(selected) then
			btn:SetBackdropColor(
				C.Colors.accentDim[1], C.Colors.accentDim[2],
				C.Colors.accentDim[3], C.Colors.accentDim[4] or 1)
			btn:SetBackdropBorderColor(
				C.Colors.accent[1], C.Colors.accent[2],
				C.Colors.accent[3], C.Colors.accent[4] or 1)
			if(btn._label) then
				btn._label:SetTextColor(1, 1, 1, 1)
			end
		else
			btn:SetBackdropColor(
				C.Colors.widget[1], C.Colors.widget[2],
				C.Colors.widget[3], C.Colors.widget[4] or 1)
			btn:SetBackdropBorderColor(0, 0, 0, 1)
			if(btn._label) then
				local tc = C.Colors.textNormal
				btn._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
			end
		end
	end

	local function SelectButton(targetBtn)
		for _, btn in next, group._buttons do
			local isSelected = (btn == targetBtn)
			ApplySelected(btn, isSelected)
		end
		group._selected = targetBtn
		if(group._onSelect and targetBtn) then
			group._onSelect(targetBtn.value, targetBtn)
		end
	end

	-- Wire up each button's click to trigger group selection
	for _, btn in next, buttons do
		local existing = btn:GetScript('OnClick')
		btn:SetScript('OnClick', function(self)
			if(not self:IsEnabled()) then return end
			SelectButton(self)
			if(existing) then existing(self) end
		end)
		-- Start in unselected visual state
		ApplySelected(btn, false)
	end

	--- Set the onSelect callback.
	--- @param func function Called with (value, button)
	function group:SetOnSelect(func)
		self._onSelect = func
	end

	--- Get the currently selected value.
	--- @return any
	function group:GetValue()
		return self._selected and self._selected.value or nil
	end

	--- Programmatically select the button matching the given value.
	--- @param value any
	function group:SetValue(value)
		for _, btn in next, self._buttons do
			if(btn.value == value) then
				SelectButton(btn)
				return
			end
		end
	end

	--- Enable or disable all buttons in the group.
	--- @param enabled boolean
	function group:SetEnabled(enabled)
		for _, btn in next, self._buttons do
			btn:SetEnabled(enabled)
			if(not enabled) then
				-- Dim each button
				local td = C.Colors.textDisabled
				btn:SetBackdropColor(
					C.Colors.widget[1] * 0.6, C.Colors.widget[2] * 0.6,
					C.Colors.widget[3] * 0.6, C.Colors.widget[4] or 1)
				if(btn._label) then
					btn._label:SetTextColor(td[1], td[2], td[3], td[4] or 1)
				end
				btn:EnableMouse(false)
			else
				-- Restore normal/selected appearance
				if(btn == self._selected) then
					ApplySelected(btn, true)
				else
					ApplySelected(btn, false)
				end
				btn:EnableMouse(true)
			end
		end
	end

	return group
end

-- ============================================================
-- CreateMultiSelectButtonGroup
-- Like ButtonGroup but allows multiple selections (toggle).
-- ============================================================

--- Wrap existing buttons as a multi-select toggle group.
--- Each button must have a `.value` field set by the caller.
--- @param buttons table Array of Button frames
--- @param onChange? function Called with (selectedValues) on any change
--- @return table group Controller table (not a frame)
function Widgets.CreateMultiSelectButtonGroup(buttons, onChange)
	local group = {
		_buttons   = buttons,
		_selected  = {},    -- [value] = true for selected buttons
		_onChange  = onChange,
	}

	local function ApplyState(btn, selected)
		btn._groupSelected = selected
		if(selected) then
			btn:SetBackdropColor(
				C.Colors.accentDim[1], C.Colors.accentDim[2],
				C.Colors.accentDim[3], C.Colors.accentDim[4] or 1)
			btn:SetBackdropBorderColor(
				C.Colors.accent[1], C.Colors.accent[2],
				C.Colors.accent[3], C.Colors.accent[4] or 1)
			if(btn._label) then
				btn._label:SetTextColor(1, 1, 1, 1)
			end
		else
			btn:SetBackdropColor(
				C.Colors.widget[1], C.Colors.widget[2],
				C.Colors.widget[3], C.Colors.widget[4] or 1)
			btn:SetBackdropBorderColor(0, 0, 0, 1)
			if(btn._label) then
				local tc = C.Colors.textNormal
				btn._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
			end
		end
	end

	local function ToggleButton(btn)
		local val = btn.value
		if(group._selected[val]) then
			group._selected[val] = nil
			ApplyState(btn, false)
		else
			group._selected[val] = true
			ApplyState(btn, true)
		end
		if(group._onChange) then
			group._onChange(group._selected)
		end
	end

	-- Wire up each button
	for _, btn in next, buttons do
		btn:SetScript('OnClick', function(self)
			if(not self:IsEnabled()) then return end
			ToggleButton(self)
		end)
		ApplyState(btn, false)
	end

	--- Get table of selected values { [value] = true, ... }
	function group:GetValues()
		local copy = {}
		for k, v in next, self._selected do
			copy[k] = v
		end
		return copy
	end

	--- Programmatically set selected values.
	--- @param values table { [value] = true, ... }
	function group:SetValues(values)
		self._selected = {}
		for _, btn in next, self._buttons do
			local selected = values[btn.value] == true
			self._selected[btn.value] = selected or nil
			ApplyState(btn, selected)
		end
	end

	--- Set the onChange callback.
	function group:SetOnChange(func)
		self._onChange = func
	end

	return group
end

-- ============================================================
-- CreateInfoButton
-- A small icon button pre-configured as a tooltip trigger.
-- ============================================================

--- Create a small info icon button that shows a tooltip on hover.
--- @param parent Frame Parent frame
--- @param title string Tooltip title
--- @param body? string Tooltip body text
--- @return Button
function Widgets.CreateInfoButton(parent, title, body)
	local button = Widgets.CreateIconButton(
		parent,
		[[Interface\BUTTONS\UI-GuildButton-PublicNote-Up]],
		14)
	button:SetWidgetTooltip(title, body)
	return button
end

-- ============================================================
-- Accent hover helper
-- Animates a button's icon or label from textSecondary → accent
-- on enter, and back on leave. Used by icon buttons in the main
-- settings header and the Overview modal.
-- ============================================================

--- Override a button's hover to smoothly fade between dim and accent color.
--- @param btn Button  The button frame
--- @param target Texture|FontString  The element to tint
--- @param isTexture boolean  true for SetVertexColor, false for SetTextColor
function Widgets.SetupAccentHover(btn, target, isTexture)
	local ac  = C.Colors.accent
	local dim = C.Colors.textSecondary
	local dur = C.Animation.durationFast

	local function setColor(r, g, b)
		if(isTexture) then
			target:SetVertexColor(r, g, b)
		else
			target:SetTextColor(r, g, b)
		end
	end

	local function getColor()
		if(isTexture) then
			return target:GetVertexColor()
		else
			return target:GetTextColor()
		end
	end

	btn:SetScript('OnEnter', function(self)
		local startR, startG, startB = getColor()
		local elapsed = 0
		self:SetScript('OnUpdate', function(_, dt)
			elapsed = elapsed + dt
			local t = math.min(elapsed / dur, 1)
			setColor(
				startR + (ac[1] - startR) * t,
				startG + (ac[2] - startG) * t,
				startB + (ac[3] - startB) * t)
			if(t >= 1) then self:SetScript('OnUpdate', nil) end
		end)
		if(Widgets.ShowTooltip and self._tooltipTitle) then
			Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
		end
	end)

	btn:SetScript('OnLeave', function(self)
		local startR, startG, startB = getColor()
		local elapsed = 0
		self:SetScript('OnUpdate', function(_, dt)
			elapsed = elapsed + dt
			local t = math.min(elapsed / dur, 1)
			setColor(
				startR + (dim[1] - startR) * t,
				startG + (dim[2] - startG) * t,
				startB + (dim[3] - startB) * t)
			if(t >= 1) then self:SetScript('OnUpdate', nil) end
		end)
		if(Widgets.HideTooltip) then Widgets.HideTooltip() end
	end)
end
