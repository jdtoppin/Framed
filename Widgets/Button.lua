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

	-- Label
	local label = Widgets.CreateFontString(button, C.Font.sizeNormal, scheme.textColor)
	label:ClearAllPoints()
	label:SetPoint('CENTER', button, 'CENTER', 0, 0)
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
-- A 14x14 checkbox with a label. Toggles a boolean state.
-- ============================================================

local CHECK_SIZE    = 14
local CHECK_SPACING = 6   -- gap between box and label

--- Create a labeled checkbox.
--- @param parent Frame Parent frame
--- @param label string Label text shown to the right of the box
--- @param callback? function Called with (checked) on toggle
--- @return Frame
function Widgets.CreateCheckButton(parent, label, callback)
	local frame = CreateFrame('Frame', nil, parent)
	frame._checked = false

	-- The checkbox square
	local box = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
	box._bgColor     = C.Colors.widget
	box._borderColor = C.Colors.border
	Widgets.ApplyBackdrop(box, C.Colors.widget, C.Colors.border)
	Widgets.SetSize(box, CHECK_SIZE, CHECK_SIZE)
	box:ClearAllPoints()
	Widgets.SetPoint(box, 'LEFT', frame, 'LEFT', 0, 0)
	frame._box = box

	-- Check mark FontString (hidden when unchecked)
	local checkMark = Widgets.CreateFontString(box, C.Font.sizeSmall, C.Colors.textActive)
	checkMark:ClearAllPoints()
	checkMark:SetPoint('CENTER', box, 'CENTER', 0, 0)
	checkMark:SetText('\226\156\147')  -- UTF-8 for checkmark
	checkMark:Hide()
	frame._checkMark = checkMark

	-- Label FontString to the right of the box
	local labelText = Widgets.CreateFontString(frame, C.Font.sizeNormal, C.Colors.textNormal)
	labelText:ClearAllPoints()
	Widgets.SetPoint(labelText, 'LEFT', box, 'RIGHT', CHECK_SPACING, 0)
	labelText:SetText(label or '')
	frame._labelText = labelText

	-- Size the outer frame to fit box + label
	frame:SetHeight(CHECK_SIZE)
	-- Width is dynamic; rely on label's text width + box
	frame:SetWidth(CHECK_SIZE + CHECK_SPACING + (labelText:GetStringWidth() or 80))

	-- Visual update helper
	local function UpdateVisual()
		if(frame._checked) then
			box:SetBackdropColor(
				C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], C.Colors.accent[4] or 1)
			box:SetBackdropBorderColor(
				C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], C.Colors.accent[4] or 1)
			frame._checkMark:Show()
		else
			box:SetBackdropColor(
				C.Colors.widget[1], C.Colors.widget[2], C.Colors.widget[3], C.Colors.widget[4] or 1)
			box:SetBackdropBorderColor(0, 0, 0, 1)
			frame._checkMark:Hide()
		end
	end

	-- Click handling on the whole frame
	frame:EnableMouse(true)
	frame:SetScript('OnMouseDown', function(self, mouseButton)
		if(mouseButton ~= 'LeftButton') then return end
		if(not self:IsEnabled()) then return end
		self._checked = not self._checked
		UpdateVisual()
		if(callback) then callback(self._checked) end
	end)

	frame:SetScript('OnEnter', function(self)
		Widgets.SetBackdropHighlight(box, true)
		if(Widgets.ShowTooltip and self._tooltipTitle) then
			Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
		end
	end)

	frame:SetScript('OnLeave', function(self)
		Widgets.SetBackdropHighlight(box, false)
		-- Re-apply checked state border after highlight reset
		if(self._checked) then
			box:SetBackdropBorderColor(
				C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], C.Colors.accent[4] or 1)
		end
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
		UpdateVisual()
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
