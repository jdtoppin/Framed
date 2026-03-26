local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local CU = F.ColorUtils

-- ============================================================
-- ColorPicker — Ported from AbstractFramework (GPL v3)
-- Two components:
--   1. Swatch button (small color preview, used in settings)
--   2. Singleton color picker frame (HSB plane, sliders, etc.)
-- ============================================================

local Round = Round or function(v) return math.floor(v + 0.5) end
local format = string.format
local floor = math.floor

-- ============================================================
-- Singleton color picker frame (created on first use)
-- ============================================================

local pickerFrame
local currentPane, originalPane, sbPane, hueSlider, alphaSlider, pickerDot
local rEB, gEB, bEB, aEB, hEB, sEB, vEB, hexEB
local confirmBtn, cancelBtn

-- Live callback during color selection
local LiveCallback

-- Saved original color for cancel/restore
local oR, oG, oB, oA

-- Current HSB + Alpha state
local H, S, B, A

-- ============================================================
-- Internal update functions
-- ============================================================

--- Update the RGB/Hex edit boxes and preview pane.
local function UpdateColor_RGBA(r, g, b, a)
	currentPane.solid:SetColorTexture(r, g, b)
	currentPane.alpha:SetColorTexture(r, g, b, a)

	local r256, g256, b256 = Round(r * 255), Round(g * 255), Round(b * 255)
	rEB:SetNumber(r256)
	gEB:SetNumber(g256)
	bEB:SetNumber(b256)
	aEB:SetNumber(Round(a * 100))
	hexEB:SetText(CU.RGB256ToHex(r256, g256, b256))
end

--- Update the HSB edit boxes, SB gradient, and slider/picker positions.
local function UpdateColor_HSBA(h, s, b, a, updateGradient, updatePositions)
	hEB:SetNumber(Round(h))
	sEB:SetNumber(Round(s * 100))
	vEB:SetNumber(Round(b * 100))

	if(updateGradient) then
		local hr, hg, hb = CU.HSBToRGB(h, 1, 1)
		sbPane.colorTex:SetGradient('HORIZONTAL', CreateColor(1, 1, 1, 1), CreateColor(hr, hg, hb, 1))

		local cr, cg, cb = CU.HSBToRGB(h, s, b)
		alphaSlider.gradientTex:SetGradient('VERTICAL', CreateColor(cr, cg, cb, 0), CreateColor(cr, cg, cb, 1))
	end

	if(updatePositions) then
		pickerDot:SetPoint('CENTER', sbPane, 'BOTTOMLEFT', Round(s * sbPane:GetWidth()), Round(b * sbPane:GetHeight()))
		hueSlider:SetValue(h)
		alphaSlider:SetValue(1 - a)
	end
end

--- Master update: convert and update everything.
local function UpdateAll(mode, v1, v2, v3, a, updateGradient, updatePositions)
	if(mode == 'rgb') then
		v1 = tonumber(format('%.3f', v1))
		v2 = tonumber(format('%.3f', v2))
		v3 = tonumber(format('%.3f', v3))
		UpdateColor_RGBA(v1, v2, v3, a)
		local ch, cs, cb = CU.RGBToHSB(v1, v2, v3)
		UpdateColor_HSBA(ch, cs, cb, a, updateGradient, updatePositions)
		if(LiveCallback) then LiveCallback(v1, v2, v3, a) end
	elseif(mode == 'hsb') then
		UpdateColor_HSBA(v1, v2, v3, a, updateGradient, updatePositions)
		local cr, cg, cb = CU.HSBToRGB(v1, v2, v3)
		UpdateColor_RGBA(cr, cg, cb, a)
		if(LiveCallback) then LiveCallback(cr, cg, cb, a) end
	end
end

-- ============================================================
-- Color preview pane (current / original)
-- ============================================================

local function CreateColorPane(parent)
	local pane = Widgets.CreateBorderedFrame(parent, 102, 27, C.Colors.widget, C.Colors.border)

	-- Solid half (left)
	pane.solid = pane:CreateTexture(nil, 'ARTWORK')
	pane.solid:SetPoint('TOPLEFT', 1, -1)
	pane.solid:SetPoint('BOTTOMRIGHT', pane, 'BOTTOMLEFT', 50, 1)

	-- Alpha half (right) — layered over checkerboard
	pane.alphaBG = pane:CreateTexture(nil, 'ARTWORK', nil, -1)
	pane.alphaBG:SetPoint('TOPLEFT', pane.solid, 'TOPRIGHT')
	pane.alphaBG:SetPoint('BOTTOMRIGHT', pane, 'BOTTOMRIGHT', -1, 1)
	pane.alphaBG:SetTexture(F.Media.GetTexture('Checkerboard'), 'REPEAT', 'REPEAT')
	pane.alphaBG:SetHorizTile(true)
	pane.alphaBG:SetVertTile(true)

	pane.alpha = pane:CreateTexture(nil, 'ARTWORK', nil, 1)
	pane.alpha:SetAllPoints(pane.alphaBG)

	function pane:SetColor(r, g, b, a)
		pane.solid:SetColorTexture(r, g, b)
		pane.alpha:SetColorTexture(r, g, b, a)
	end

	return pane
end

-- ============================================================
-- Vertical color slider (hue / alpha)
-- ============================================================

local function CreateColorSlider(parent, onValueChanged)
	local holder = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(holder, 20, 132)
	Widgets.ApplyBackdrop(holder, C.Colors.widget, C.Colors.border)

	local slider = CreateFrame('Slider', nil, holder)
	slider:SetPoint('TOPLEFT', holder, 'TOPLEFT', 1, -1)
	slider:SetPoint('BOTTOMRIGHT', holder, 'BOTTOMRIGHT', -1, 1)
	slider:SetObeyStepOnDrag(true)
	slider:SetOrientation('VERTICAL')
	slider:SetScript('OnValueChanged', onValueChanged)

	-- Invisible thumb (just for tracking)
	local thumb = slider:CreateTexture(nil, 'ARTWORK')
	Widgets.SetSize(thumb, 20, 1)
	slider:SetThumbTexture(thumb)

	-- Visual arrow indicator
	local arrow = slider:CreateTexture(nil, 'ARTWORK')
	arrow:SetTexture(F.Media.GetIcon('ArrowLeft2'))
	Widgets.SetSize(arrow, 16, 16)
	arrow:SetPoint('LEFT', thumb, 'RIGHT', -5, 0)

	holder.slider = slider
	return holder
end

-- ============================================================
-- Small numeric edit box for the picker
-- ============================================================

local function CreatePickerEB(parent, label, width, isNumeric)
	local eb = CreateFrame('EditBox', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(eb, width, 20)
	Widgets.ApplyBackdrop(eb, C.Colors.widget, C.Colors.border)
	eb:SetFont(F.Media.GetActiveFont(), C.Font.sizeSmall, '')
	eb:SetTextColor(1, 1, 1, 1)
	eb:SetJustifyH('CENTER')
	eb:SetAutoFocus(false)
	if(isNumeric) then
		eb:SetNumeric(true)
	end
	eb:SetTextInsets(2, 2, 0, 0)

	-- Label above
	local labelFS = Widgets.CreateFontString(eb, C.Font.sizeSmall, C.Colors.textSecondary)
	labelFS:SetPoint('BOTTOMLEFT', eb, 'TOPLEFT', 0, 2)
	labelFS:SetText(label)

	-- Focus highlight
	eb:SetScript('OnEditFocusGained', function(self)
		self:HighlightText()
		self._oldText = self:GetText()
		local a = C.Colors.accent
		self:SetBackdropBorderColor(a[1], a[2], a[3], a[4] or 1)
	end)

	eb:SetScript('OnEditFocusLost', function(self)
		self:HighlightText(0, 0)
		if(strtrim(self:GetText()) == '') then
			self:SetText(self._oldText or '0')
		end
		self:SetBackdropBorderColor(0, 0, 0, 1)
	end)

	eb:SetScript('OnEscapePressed', function(self)
		self:SetText(self._oldText or '0')
		self:ClearFocus()
	end)

	return eb
end

-- ============================================================
-- Create the singleton picker frame
-- ============================================================

local function CreatePickerFrame()
	local frame, header = Widgets.CreateHeaderedFrame(UIParent, 'Color Picker', 269, 297)
	frame:SetFrameStrata('DIALOG')
	frame:SetToplevel(true)
	frame:SetPoint('CENTER')
	frame:Hide()
	pickerFrame = frame

	-- Close button in header
	local closeBtn = Widgets.CreateIconButton(header, F.Media.GetIcon('Close'), 16)
	closeBtn:ClearAllPoints()
	Widgets.SetPoint(closeBtn, 'RIGHT', header, 'RIGHT', -4, 0)
	closeBtn:SetOnClick(function()
		-- Cancel: restore original and close
		if(LiveCallback) then
			LiveCallback(oR, oG, oB, oA)
		end
		LiveCallback = nil
		pickerFrame:Hide()
	end)

	-- --------------------------------------------------------
	-- Color preview panes
	-- --------------------------------------------------------
	currentPane = CreateColorPane(frame)
	currentPane:ClearAllPoints()
	Widgets.SetPoint(currentPane, 'TOPLEFT', frame, 'TOPLEFT', 7, -31)

	originalPane = CreateColorPane(frame)
	originalPane:ClearAllPoints()
	Widgets.SetPoint(originalPane, 'TOPLEFT', currentPane, 'TOPRIGHT', 7, 0)

	-- --------------------------------------------------------
	-- Saturation/Brightness plane
	-- --------------------------------------------------------
	local sbBorder = Widgets.CreateBorderedFrame(frame, 132, 132, C.Colors.widget, C.Colors.border)
	sbBorder:ClearAllPoints()
	Widgets.SetPoint(sbBorder, 'TOPLEFT', currentPane, 'BOTTOMLEFT', 0, -7)

	sbPane = CreateFrame('Frame', nil, sbBorder)
	sbPane:SetPoint('TOPLEFT', sbBorder, 'TOPLEFT', 1, -1)
	sbPane:SetPoint('BOTTOMRIGHT', sbBorder, 'BOTTOMRIGHT', -1, 1)

	-- Hue-tinted horizontal gradient (white -> pure hue color)
	sbPane.colorTex = sbPane:CreateTexture(nil, 'ARTWORK', nil, 0)
	sbPane.colorTex:SetAllPoints(sbPane)
	sbPane.colorTex:SetTexture(F.Media.GetPlainTexture())

	-- Vertical black gradient overlay (brightness: black at bottom, clear at top)
	local darkOverlay = sbPane:CreateTexture(nil, 'ARTWORK', nil, 1)
	darkOverlay:SetAllPoints(sbPane)
	darkOverlay:SetTexture(F.Media.GetPlainTexture())
	darkOverlay:SetGradient('VERTICAL', CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0))

	-- --------------------------------------------------------
	-- Hue slider
	-- --------------------------------------------------------
	local hueHolder = CreateColorSlider(frame, function(self, value, userChanged)
		if(not userChanged) then return end
		H = value
		if(self.prev == H) then return end
		self.prev = H
		UpdateAll('hsb', H, S, B, A, true)
	end)
	Widgets.SetPoint(hueHolder, 'TOPLEFT', sbBorder, 'TOPRIGHT', 15, 0)
	hueSlider = hueHolder.slider
	hueSlider:SetValueStep(1)
	hueSlider:SetMinMaxValues(0, 360)

	-- Fill hue slider with rainbow gradient sections
	local hueColors = {
		{1, 0, 0}, {1, 1, 0}, {0, 1, 0},
		{0, 1, 1}, {0, 0, 1}, {1, 0, 1}, {1, 0, 0},
	}
	local sectionH = hueSlider:GetHeight() / 6
	for i = 1, 6 do
		local section = hueSlider:CreateTexture(nil, 'ARTWORK')
		section:SetHeight(sectionH)
		if(i == 1) then
			section:SetPoint('TOPLEFT')
		else
			section:SetPoint('TOPLEFT', hueSlider[i - 1], 'BOTTOMLEFT')
		end
		section:SetPoint('RIGHT')
		local top = hueColors[i]
		local bot = hueColors[i + 1]
		section:SetTexture(F.Media.GetPlainTexture())
		section:SetGradient('VERTICAL', CreateColor(bot[1], bot[2], bot[3], 1), CreateColor(top[1], top[2], top[3], 1))
		hueSlider[i] = section
	end

	-- --------------------------------------------------------
	-- Alpha slider
	-- --------------------------------------------------------
	local alphaHolder = CreateColorSlider(frame, function(self, value, userChanged)
		if(not userChanged) then return end
		A = tonumber(format('%.3f', 1 - value))
		if(self.prev == A) then return end
		self.prev = A
		UpdateAll('hsb', H, S, B, A)
	end)
	Widgets.SetPoint(alphaHolder, 'TOPLEFT', hueHolder, 'TOPRIGHT', 15, 0)
	alphaSlider = alphaHolder.slider
	alphaSlider:SetValueStep(0.001)
	alphaSlider:SetMinMaxValues(0, 1)

	-- Checkerboard background for alpha
	local alphaCB = alphaSlider:CreateTexture(nil, 'ARTWORK', nil, 0)
	alphaCB:SetTexture(F.Media.GetTexture('Checkerboard'), 'REPEAT', 'REPEAT')
	alphaCB:SetHorizTile(true)
	alphaCB:SetVertTile(true)
	alphaCB:SetAllPoints(alphaSlider)

	-- Gradient overlay showing the current color fading to transparent
	alphaSlider.gradientTex = alphaSlider:CreateTexture(nil, 'ARTWORK', nil, 1)
	alphaSlider.gradientTex:SetTexture(F.Media.GetPlainTexture())
	alphaSlider.gradientTex:SetAllPoints(alphaSlider)

	-- --------------------------------------------------------
	-- Picker dot (crosshair on SB plane)
	-- --------------------------------------------------------
	pickerDot = CreateFrame('Frame', nil, sbPane)
	Widgets.SetSize(pickerDot, 16, 16)
	pickerDot:SetPoint('CENTER', sbPane, 'BOTTOMLEFT')

	local dotTex = pickerDot:CreateTexture(nil, 'OVERLAY')
	dotTex:SetAllPoints()
	dotTex:SetTexture(F.Media.GetIcon('ColorPickerRing'))

	pickerDot:EnableMouse(true)
	pickerDot:SetMovable(true)

	local function StartPickerDrag(startX, startY, mouseX, mouseY)
		local scale = pickerDot:GetEffectiveScale()
		local lastMX, lastMY
		pickerDot:SetScript('OnUpdate', function()
			local newMX, newMY = GetCursorPosition()
			if(newMX == lastMX and newMY == lastMY) then return end
			lastMX, lastMY = newMX, newMY

			local newX = startX + (newMX - mouseX) / scale
			local newY = startY + (newMY - mouseY) / scale

			local w, h = sbPane:GetWidth(), sbPane:GetHeight()
			newX = CU.Clamp(newX, 0, w)
			newY = CU.Clamp(newY, 0, h)

			pickerDot:SetPoint('CENTER', sbPane, 'BOTTOMLEFT', newX, newY)

			S = newX / w
			B = newY / h
			UpdateAll('hsb', H, S, B, A, true)
		end)
	end

	pickerDot:SetScript('OnMouseDown', function(self, button)
		if(button ~= 'LeftButton') then return end
		local x, y = select(4, pickerDot:GetPoint(1))
		local mx, my = GetCursorPosition()
		StartPickerDrag(x, y, mx, my)
	end)

	pickerDot:SetScript('OnMouseUp', function(self)
		self:SetScript('OnUpdate', nil)
	end)

	-- Click anywhere on the SB plane to jump picker there
	sbPane:SetScript('OnMouseDown', function(self, button)
		if(button ~= 'LeftButton') then return end
		local sbX, sbY = sbPane:GetLeft(), sbPane:GetBottom()
		local mx, my = GetCursorPosition()
		local scale = pickerDot:GetEffectiveScale()
		mx, my = mx / scale, my / scale
		StartPickerDrag(mx - sbX, my - sbY, mx * scale, my * scale)
	end)

	sbPane:SetScript('OnMouseUp', function()
		pickerDot:SetScript('OnUpdate', nil)
	end)

	-- --------------------------------------------------------
	-- Edit boxes
	-- --------------------------------------------------------
	-- RGB row
	rEB = CreatePickerEB(frame, 'R', 40, true)
	Widgets.SetPoint(rEB, 'TOPLEFT', sbBorder, 'BOTTOMLEFT', 0, -25)

	gEB = CreatePickerEB(frame, 'G', 40, true)
	Widgets.SetPoint(gEB, 'TOPLEFT', rEB, 'TOPRIGHT', 7, 0)

	bEB = CreatePickerEB(frame, 'B', 40, true)
	Widgets.SetPoint(bEB, 'TOPLEFT', gEB, 'TOPRIGHT', 7, 0)

	aEB = CreatePickerEB(frame, 'A', 69, true)
	Widgets.SetPoint(aEB, 'TOPLEFT', bEB, 'TOPRIGHT', 7, 0)

	-- HSB row
	hEB = CreatePickerEB(frame, 'H', 40, true)
	Widgets.SetPoint(hEB, 'TOPLEFT', rEB, 'BOTTOMLEFT', 0, -25)

	sEB = CreatePickerEB(frame, 'S', 40, true)
	Widgets.SetPoint(sEB, 'TOPLEFT', hEB, 'TOPRIGHT', 7, 0)

	vEB = CreatePickerEB(frame, 'B', 40, true)
	Widgets.SetPoint(vEB, 'TOPLEFT', sEB, 'TOPRIGHT', 7, 0)

	hexEB = CreatePickerEB(frame, 'Hex', 69, false)
	Widgets.SetPoint(hexEB, 'TOPLEFT', vEB, 'TOPRIGHT', 7, 0)

	-- Wire up RGB edit box enter-press
	local function OnRGBEnter(self)
		local rv = CU.Clamp(rEB:GetNumber(), 0, 255)
		local gv = CU.Clamp(gEB:GetNumber(), 0, 255)
		local bv = CU.Clamp(bEB:GetNumber(), 0, 255)
		rEB:SetNumber(rv)
		gEB:SetNumber(gv)
		bEB:SetNumber(bv)

		local r, g, b = CU.ToNormalized(rv, gv, bv)
		H, S, B = CU.RGBToHSB(r, g, b)
		UpdateAll('rgb', r, g, b, A, true, true)
		self:ClearFocus()
	end
	rEB:SetScript('OnEnterPressed', OnRGBEnter)
	gEB:SetScript('OnEnterPressed', OnRGBEnter)
	bEB:SetScript('OnEnterPressed', OnRGBEnter)

	-- Wire up Alpha edit box
	aEB:SetScript('OnEnterPressed', function(self)
		local av = CU.Clamp(self:GetNumber(), 0, 100)
		self:SetNumber(av)
		A = av / 100
		alphaSlider:SetValue(1 - A)
		UpdateAll('hsb', H, S, B, A)
		self:ClearFocus()
	end)

	-- Wire up HSB edit box enter-press
	local function OnHSBEnter(self)
		local hv = CU.Clamp(hEB:GetNumber(), 0, 360)
		local sv = CU.Clamp(sEB:GetNumber(), 0, 100)
		local bv = CU.Clamp(vEB:GetNumber(), 0, 100)
		hEB:SetNumber(hv)
		sEB:SetNumber(sv)
		vEB:SetNumber(bv)

		H, S, B = hv, sv / 100, bv / 100
		UpdateAll('hsb', H, S, B, A, true, true)
		self:ClearFocus()
	end
	hEB:SetScript('OnEnterPressed', OnHSBEnter)
	sEB:SetScript('OnEnterPressed', OnHSBEnter)
	vEB:SetScript('OnEnterPressed', OnHSBEnter)

	-- Wire up Hex edit box
	hexEB:SetScript('OnEnterPressed', function(self)
		local text = strtrim(self:GetText())
		if(strlen(text) ~= 6 or not strmatch(text, '^[0-9a-fA-F]+$')) then
			self:SetText(self._oldText or 'ffffff')
			self:ClearFocus()
			return
		end
		local r, g, b = CU.HexToRGB(text)
		H, S, B = CU.RGBToHSB(r, g, b)
		UpdateAll('rgb', r, g, b, A, true, true)
		self:ClearFocus()
	end)

	-- --------------------------------------------------------
	-- Confirm / Cancel buttons
	-- --------------------------------------------------------
	confirmBtn = Widgets.CreateButton(frame, OKAY, 'green', 102, 20)
	confirmBtn:ClearAllPoints()
	Widgets.SetPoint(confirmBtn, 'TOPLEFT', hEB, 'BOTTOMLEFT', 0, -7)

	cancelBtn = Widgets.CreateButton(frame, CANCEL, 'red', 102, 20)
	cancelBtn:ClearAllPoints()
	Widgets.SetPoint(cancelBtn, 'TOPLEFT', confirmBtn, 'TOPRIGHT', 7, 0)

	-- Auto-close when owner hides
	frame:SetScript('OnUpdate', nil)
end

-- ============================================================
-- Show / Hide the picker
-- ============================================================

--- Show the color picker frame.
--- @param owner Frame The swatch button that opened the picker
--- @param callback function Called with (r, g, b, a) during live drag
--- @param onConfirm function Called with (r, g, b, a) on OK click
--- @param hasAlpha boolean Whether to enable the alpha slider
--- @param r number [0, 1]
--- @param g number [0, 1]
--- @param b number [0, 1]
--- @param a number [0, 1]
local function ShowColorPicker(owner, callback, onConfirm, hasAlpha, r, g, b, a)
	if(not pickerFrame) then
		CreatePickerFrame()
	end

	pickerFrame:SetFrameStrata('DIALOG')
	pickerFrame:SetToplevel(true)

	-- Clear previous slider state
	hueSlider.prev = nil
	alphaSlider.prev = nil

	-- If already shown, restore previous owner's color
	if(pickerFrame:IsShown() and LiveCallback) then
		LiveCallback(oR, oG, oB, oA)
	end

	-- Backup original color
	oR, oG, oB, oA = r or 1, g or 1, b or 1, a or 1

	-- Set state
	H, S, B = CU.RGBToHSB(oR, oG, oB)
	A = oA
	LiveCallback = callback

	-- Wire confirm button
	confirmBtn:SetOnClick(function()
		LiveCallback = nil
		pickerFrame:Hide()
		local cr, cg, cb = CU.HSBToRGB(H, S, B)
		onConfirm(cr, cg, cb, A)
	end)

	-- Wire cancel button
	cancelBtn:SetOnClick(function()
		pickerFrame:SetScript('OnUpdate', nil)
		local restoreCB = LiveCallback
		LiveCallback = nil
		pickerFrame:Hide()
		if(restoreCB) then restoreCB(oR, oG, oB, oA) end
	end)

	-- Auto-hide if the owner frame becomes hidden
	pickerFrame:SetScript('OnUpdate', function()
		if(owner:IsVisible()) then return end
		pickerFrame:SetScript('OnUpdate', nil)
		local restoreCB = LiveCallback
		LiveCallback = nil
		if(restoreCB) then restoreCB(oR, oG, oB, oA) end
		pickerFrame:Hide()
	end)

	-- Position to the right of the owner swatch
	pickerFrame:ClearAllPoints()
	pickerFrame:SetPoint('LEFT', owner, 'RIGHT', 8, 0)

	-- Update original pane
	originalPane:SetColor(oR, oG, oB, oA)

	-- Update all displays
	UpdateAll('rgb', oR, oG, oB, oA, true, true)

	-- Enable/disable alpha controls
	if(hasAlpha) then
		alphaSlider:Enable()
		alphaSlider:SetAlpha(1)
		aEB:Enable()
		aEB:SetAlpha(1)
	else
		alphaSlider:Disable()
		alphaSlider:SetAlpha(0.25)
		aEB:Disable()
		aEB:SetAlpha(0.25)
	end

	pickerFrame:Show()
end

--- Hide the color picker frame.
local function HideColorPicker()
	if(pickerFrame) then
		pickerFrame:Hide()
	end
end

-- ============================================================
-- Swatch button (the small color preview in settings panels)
-- ============================================================

local SWATCH_SIZE = 14
local DARK_BG = { 0.08, 0.08, 0.08, 1 }

--- Create a color swatch button that opens the custom picker.
--- @param parent Frame Parent frame
--- @param label? string Optional label shown to the right
--- @param alphaEnabled? boolean Whether to show the alpha slider
--- @param onChange? function Called with (r, g, b, a) during live drag
--- @param onConfirm? function Called with (r, g, b, a) on confirm
--- @return Frame picker
function Widgets.CreateColorPicker(parent, label, alphaEnabled, onChange, onConfirm)
	local picker = CreateFrame('Button', nil, parent, 'BackdropTemplate')

	picker._bgColor     = { 1, 1, 1, 1 }
	picker._borderColor = C.Colors.border
	Widgets.ApplyBackdrop(picker, picker._bgColor, picker._borderColor)
	Widgets.SetSize(picker, SWATCH_SIZE, SWATCH_SIZE)
	picker:SetBackdropBorderColor(0, 0, 0, 1)
	picker:EnableMouse(true)

	-- Current color state
	picker.color = { 1, 1, 1, 1 }
	picker.alphaEnabled = alphaEnabled or false
	picker.onChange = onChange
	picker.onConfirm = onConfirm

	-- Label to the right
	if(label) then
		picker._labelFS = Widgets.CreateFontString(picker, C.Font.sizeNormal, C.Colors.textNormal)
		picker._labelFS:SetPoint('LEFT', picker, 'RIGHT', 5, 0)
		picker._labelFS:SetText(label)
		picker:SetHitRectInsets(0, -(picker._labelFS:GetStringWidth() + 5), 0, 0)
	end

	-- Mouseover highlight (1px outside border)
	local highlight = CreateFrame('Frame', nil, picker, 'BackdropTemplate')
	highlight:SetPoint('TOPLEFT', picker, 'TOPLEFT', -1, 1)
	highlight:SetPoint('BOTTOMRIGHT', picker, 'BOTTOMRIGHT', 1, -1)
	highlight:SetBackdrop({
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	local ac = C.Colors.accent
	highlight:SetBackdropBorderColor(ac[1], ac[2], ac[3], 0.9)
	highlight:Hide()
	picker._highlight = highlight

	-- Scripts
	picker:SetScript('OnEnter', function(self)
		self._highlight:Show()
		if(self._labelFS) then
			local a = C.Colors.accent
			self._labelFS:SetTextColor(a[1], a[2], a[3], a[4] or 1)
		end
	end)

	picker:SetScript('OnLeave', function(self)
		self._highlight:Hide()
		if(self._labelFS) then
			local tc = C.Colors.textNormal
			self._labelFS:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
	end)

	picker:SetScript('OnClick', function(self)
		-- Save temp state for live callback comparison
		self._r = self.color[1]
		self._g = self.color[2]
		self._b = self.color[3]
		self._a = self.color[4]

		ShowColorPicker(self, function(r, g, b, a)
			-- Live preview: update swatch visual
			self:SetBackdropColor(r, g, b, a)
			if(self._r ~= r or self._g ~= g or self._b ~= b or self._a ~= a) then
				self._r = r
				self._g = g
				self._b = b
				self._a = a
				if(self.onChange) then
					self.onChange(r, g, b, a)
				end
			end
		end, function(r, g, b, a)
			-- Confirm: commit to stored color
			if(self.color[1] ~= r or self.color[2] ~= g or self.color[3] ~= b or self.color[4] ~= a) then
				self.color[1] = r
				self.color[2] = g
				self.color[3] = b
				self.color[4] = a
				self:SetBackdropColor(r, g, b, a)
				if(self.onConfirm) then
					self.onConfirm(r, g, b, a)
				end
			end
		end, self.alphaEnabled, unpack(self.color))
	end)

	-- Disabled visual
	picker:SetScript('OnEnable', function(self)
		if(self._labelFS) then
			local tc = C.Colors.textNormal
			self._labelFS:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
		self:SetBackdropColor(unpack(self.color))
	end)

	picker:SetScript('OnDisable', function(self)
		if(self._labelFS) then
			local td = C.Colors.textDisabled
			self._labelFS:SetTextColor(td[1], td[2], td[3], td[4] or 1)
		end
		self:SetBackdropColor(0.3, 0.3, 0.3, 1)
	end)

	-- --------------------------------------------------------
	-- Public API
	-- --------------------------------------------------------

	--- Set the swatch color and update visual.
	--- @param r number|table If table, treated as {r, g, b, a}
	--- @param g? number
	--- @param b? number
	--- @param a? number
	function picker:SetColor(r, g, b, a)
		if(type(r) == 'table') then
			self.color[1] = r[1]
			self.color[2] = r[2]
			self.color[3] = r[3]
			self.color[4] = r[4] or 1
		else
			self.color[1] = r
			self.color[2] = g
			self.color[3] = b
			self.color[4] = a or 1
		end
		self:SetBackdropColor(self.color[1], self.color[2], self.color[3], self.color[4])
	end

	--- Get the current color as r, g, b, a.
	--- @return number r, number g, number b, number a
	function picker:GetColor()
		return self.color[1], self.color[2], self.color[3], self.color[4]
	end

	--- Get the current color as a table.
	--- @return table
	function picker:GetColorTable()
		return self.color
	end

	--- Set callback invoked with (r, g, b, a) during live drag.
	--- @param func function
	function picker:SetOnChange(func)
		self.onChange = func
	end

	--- Set callback invoked with (r, g, b, a) on confirm.
	--- @param func function
	function picker:SetOnConfirm(func)
		self.onConfirm = func
	end

	--- Toggle alpha slider in the color picker dialog.
	--- @param enabled boolean
	function picker:SetHasAlpha(enabled)
		self.alphaEnabled = enabled
	end

	--- Alias for backwards compatibility
	function picker:SetOnColorChanged(func)
		self.onConfirm = func
	end

	Widgets.ApplyBaseMixin(picker)

	return picker
end

--- Hide the shared color picker frame (e.g., when a panel hides).
function Widgets.HideColorPicker()
	HideColorPicker()
end
