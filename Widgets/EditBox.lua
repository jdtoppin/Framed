local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- EditBox — single-line (text/number) and multi-line inputs
-- Three modes: 'text' (default), 'number', 'multiline'
-- ============================================================

-- Default heights
local HEIGHT_SINGLE    = 24
local HEIGHT_MULTILINE = 100

-- Border colors
local BLACK = { 0, 0, 0, 1 }

-- Placeholder color
local PLACEHOLDER_COLOR = C.Colors.textDisabled

-- ============================================================
-- Shared EditBox mixin (mixed into the container frame)
-- ============================================================

local EditBoxMixin = {}

--- Register a callback fired on every keystroke with (text).
--- @param func function
function EditBoxMixin:SetOnTextChanged(func)
	self._onTextChanged = func
end

--- Register a callback fired on Enter with (text). Single-line only.
--- @param func function
function EditBoxMixin:SetOnEnterPressed(func)
	self._onEnterPressed = func
end

--- Register a callback fired when the edit box loses focus.
--- @param func function
function EditBoxMixin:SetOnFocusLost(func)
	self._onFocusLost = func
end

--- Get the current text content.
--- @return string
function EditBoxMixin:GetText()
	local eb = self._editbox
	if(self._placeholder_active) then return '' end
	return eb:GetText()
end

--- Set the text content programmatically.
--- @param text string
function EditBoxMixin:SetText(text)
	local eb = self._editbox
	self._placeholder_active = false
	eb:SetTextColor(Widgets.UnpackColor(C.Colors.textActive))
	eb:SetText(text or '')
	eb:SetCursorPosition(0)
end

--- Show gray placeholder text when the box is empty.
--- Cleared automatically when the user begins typing.
--- @param text string
function EditBoxMixin:SetPlaceholder(text)
	self._placeholderText = text
	local eb = self._editbox
	-- Only apply if currently empty and not focused
	if((eb:GetText() == '' or self._placeholder_active) and not eb:HasFocus()) then
		self._placeholder_active = true
		eb:SetTextColor(Widgets.UnpackColor(PLACEHOLDER_COLOR))
		eb:SetText(text)
	end
end

-- ============================================================
-- Focus state — accent border when focused, black when not
-- ============================================================

local function OnFocusGained(container)
	local accent = C.Colors.accent
	container:SetBackdropBorderColor(accent[1], accent[2], accent[3], accent[4] or 1)

	-- Clear placeholder on focus
	if(container._placeholder_active) then
		container._placeholder_active = false
		container._editbox:SetText('')
		container._editbox:SetTextColor(Widgets.UnpackColor(C.Colors.textActive))
	end
end

local function OnFocusLost(container)
	container:SetBackdropBorderColor(Widgets.UnpackColor(BLACK))

	-- Restore placeholder if box is empty
	local eb = container._editbox
	if(container._placeholderText and (eb:GetText() == '')) then
		container._placeholder_active = true
		eb:SetTextColor(Widgets.UnpackColor(PLACEHOLDER_COLOR))
		eb:SetText(container._placeholderText)
	end

	if(container._onFocusLost) then
		container._onFocusLost()
	end
end

-- ============================================================
-- Internal: build the raw WoW EditBox and wire scripts
-- ============================================================

--- Create and configure a WoW EditBox inside the given parent.
--- @param container Frame The backdrop container frame
--- @param isMultiLine boolean
--- @param isNumber boolean
--- @return EditBox
local function CreateRawEditBox(container, isMultiLine, isNumber)
	local eb = CreateFrame('EditBox', nil, container)

	eb:SetFont(F.Media.GetActiveFont(), C.Font.sizeNormal, '')
	eb:SetTextColor(Widgets.UnpackColor(C.Colors.textActive))
	eb:SetAutoFocus(false)
	eb:SetMultiLine(isMultiLine)

	if(isNumber) then
		eb:SetNumeric(true)
	end

	-- Enter key
	eb:SetScript('OnEnterPressed', function(self)
		if(not isMultiLine) then
			if(container._onEnterPressed) then
				container._onEnterPressed(container:GetText())
			end
			self:ClearFocus()
		end
	end)

	-- Escape key
	eb:SetScript('OnEscapePressed', function(self)
		self:ClearFocus()
	end)

	-- Tab key: clear focus (standard WoW behavior)
	eb:SetScript('OnTabPressed', function(self)
		self:ClearFocus()
	end)

	-- Focus gained / lost
	eb:SetScript('OnEditFocusGained', function(self)
		OnFocusGained(container)
	end)

	eb:SetScript('OnEditFocusLost', function(self)
		OnFocusLost(container)
	end)

	-- Text changed
	eb:SetScript('OnTextChanged', function(self, userInput)
		if(not userInput) then return end
		-- If user typed, ensure we are not in placeholder state
		if(container._placeholder_active) then
			container._placeholder_active = false
			self:SetTextColor(Widgets.UnpackColor(C.Colors.textActive))
		end
		if(container._onTextChanged) then
			container._onTextChanged(container:GetText())
		end
	end)

	return eb
end

-- ============================================================
-- Single-line constructor (text / number)
-- ============================================================

--- Build a single-line EditBox widget.
--- @param parent Frame
--- @param label string|nil
--- @param width number
--- @param height number
--- @param isNumber boolean
--- @return Frame container
local function CreateSingleLine(parent, label, width, height, isNumber)
	local labelH = (label ~= nil) and (C.Font.sizeSmall + 4) or 0
	local totalH = labelH + height

	-- Outer container (unsized Frame to hold label + input)
	local container = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(container, width, totalH)
	Widgets.ApplyBaseMixin(container)

	for k, v in next, EditBoxMixin do
		container[k] = v
	end

	-- --------------------------------------------------------
	-- Optional label
	-- --------------------------------------------------------
	if(label) then
		local labelFS = Widgets.CreateFontString(container, C.Font.sizeSmall, C.Colors.textSecondary)
		labelFS:SetText(label)
		labelFS:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, 0)
		labelFS:SetJustifyH('LEFT')
		container._labelFS = labelFS
	end

	-- --------------------------------------------------------
	-- Backdrop container for the input area.
	-- Width is driven by two horizontal anchors (not SetSize) so callers
	-- that resize the container via SetWidth cascade automatically to the
	-- visible input chrome.
	-- --------------------------------------------------------
	local inputFrame = CreateFrame('Frame', nil, container, 'BackdropTemplate')
	inputFrame:SetHeight(height)
	inputFrame._height = height

	if(label) then
		inputFrame:SetPoint('TOPLEFT',  container, 'TOPLEFT',  0, -labelH)
		inputFrame:SetPoint('TOPRIGHT', container, 'TOPRIGHT', 0, -labelH)
	else
		inputFrame:SetPoint('TOPLEFT',  container, 'TOPLEFT',  0, 0)
		inputFrame:SetPoint('TOPRIGHT', container, 'TOPRIGHT', 0, 0)
	end

	Widgets.ApplyBackdrop(inputFrame, C.Colors.widget, BLACK)
	-- Store backdrop colors for focus state restoration
	inputFrame._bgColor     = C.Colors.widget
	inputFrame._borderColor = BLACK

	-- Forward backdrop methods so container focus handlers work on inputFrame
	container.SetBackdropBorderColor = function(self, ...)
		inputFrame:SetBackdropBorderColor(...)
	end

	-- --------------------------------------------------------
	-- WoW EditBox inside the input frame
	-- --------------------------------------------------------
	local eb = CreateRawEditBox(container, false, isNumber)
	container._editbox = eb

	local pad = C.Spacing.tight
	eb:SetPoint('LEFT',  inputFrame, 'LEFT',  pad, 0)
	eb:SetPoint('RIGHT', inputFrame, 'RIGHT', -pad, 0)
	eb:SetPoint('TOP',    inputFrame, 'TOP',    0, 0)
	eb:SetPoint('BOTTOM', inputFrame, 'BOTTOM', 0, 0)

	-- --------------------------------------------------------
	-- Tooltip support
	-- --------------------------------------------------------
	Widgets.AttachTooltipScripts(container)

	return container
end

-- ============================================================
-- Multi-line constructor
-- ============================================================

--- Build a multi-line scrollable EditBox widget.
--- @param parent Frame
--- @param label string|nil
--- @param width number
--- @param height number
--- @return Frame container
local function CreateMultiLine(parent, label, width, height)
	local labelH = (label ~= nil) and (C.Font.sizeSmall + 4) or 0
	local totalH = labelH + height

	-- Outer container
	local container = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(container, width, totalH)
	Widgets.ApplyBaseMixin(container)

	for k, v in next, EditBoxMixin do
		container[k] = v
	end

	-- --------------------------------------------------------
	-- Optional label
	-- --------------------------------------------------------
	if(label) then
		local labelFS = Widgets.CreateFontString(container, C.Font.sizeSmall, C.Colors.textSecondary)
		labelFS:SetText(label)
		labelFS:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, 0)
		labelFS:SetJustifyH('LEFT')
		container._labelFS = labelFS
	end

	-- --------------------------------------------------------
	-- Backdrop container for the scrollable area
	-- --------------------------------------------------------
	local inputFrame = CreateFrame('Frame', nil, container, 'BackdropTemplate')
	Widgets.SetSize(inputFrame, width, height)

	if(label) then
		inputFrame:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, -labelH)
	else
		inputFrame:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, 0)
	end

	Widgets.ApplyBackdrop(inputFrame, C.Colors.widget, BLACK)
	inputFrame._bgColor     = C.Colors.widget
	inputFrame._borderColor = BLACK

	container.SetBackdropBorderColor = function(self, ...)
		inputFrame:SetBackdropBorderColor(...)
	end

	-- --------------------------------------------------------
	-- ScrollFrame inside the input frame
	-- --------------------------------------------------------
	local pad = C.Spacing.tight

	local scrollFrame = CreateFrame('ScrollFrame', nil, inputFrame)
	scrollFrame:SetPoint('TOPLEFT',     inputFrame, 'TOPLEFT',     pad,  -pad)
	scrollFrame:SetPoint('BOTTOMRIGHT', inputFrame, 'BOTTOMRIGHT', -pad,  pad)

	-- --------------------------------------------------------
	-- WoW EditBox as the scroll child
	-- --------------------------------------------------------
	local eb = CreateRawEditBox(container, true, false)
	container._editbox = eb

	-- The EditBox must match the scroll child width; height is unrestricted
	-- so it can grow as text is added.
	eb:SetWidth(scrollFrame:GetWidth() > 0 and scrollFrame:GetWidth() or (width - pad * 2))
	eb:SetHeight(height - pad * 2)  -- initial height; grows with content

	scrollFrame:SetScrollChild(eb)

	-- Click anywhere in the visible area to focus the editbox and
	-- park the cursor at the end of the current text.
	inputFrame:EnableMouse(true)
	inputFrame:SetScript('OnMouseDown', function()
		eb:SetFocus()
		eb:SetCursorPosition(#(eb:GetText() or ''))
	end)

	-- Auto-scroll to follow the cursor as text grows
	eb:SetScript('OnCursorChanged', function(self, x, y, w, h)
		local scrollOffset = scrollFrame:GetVerticalScroll()
		local viewH        = scrollFrame:GetHeight()
		-- y is relative to editbox top (negative downward)
		local cursorBottom = -y + h
		if(-y < scrollOffset) then
			scrollFrame:SetVerticalScroll(-y)
		elseif(cursorBottom > scrollOffset + viewH) then
			scrollFrame:SetVerticalScroll(cursorBottom - viewH)
		end
	end)

	container._scrollFrame = scrollFrame

	-- --------------------------------------------------------
	-- Tooltip support
	-- --------------------------------------------------------
	Widgets.AttachTooltipScripts(container)

	return container
end

-- ============================================================
-- Public constructor
-- ============================================================

--- Create a text input widget.
--- @param parent Frame    Parent frame
--- @param label  string|nil  Optional label shown above the input
--- @param width  number   Total width of the widget
--- @param height number|nil  Height of the input area (defaults by mode)
--- @param mode   string|nil  'text' | 'number' | 'multiline' (default 'text')
--- @return Frame container  Widget container with EditBoxMixin API
function Widgets.CreateEditBox(parent, label, width, height, mode)
	mode = mode or 'text'

	local isMultiLine = (mode == 'multiline')
	local isNumber    = (mode == 'number')

	if(not height) then
		height = isMultiLine and HEIGHT_MULTILINE or HEIGHT_SINGLE
	end

	if(isMultiLine) then
		return CreateMultiLine(parent, label, width, height)
	else
		return CreateSingleLine(parent, label, width, height, isNumber)
	end
end
