local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Dialog — Confirmation and Message dialogs
-- Singleton frame shared between ShowConfirmDialog and
-- ShowMessageDialog. Only one dialog is visible at a time.
-- ============================================================

local DIALOG_WIDTH_2  = 350    -- 2-button dialogs
local DIALOG_WIDTH_3  = 420    -- 3-button dialogs
local PAD           = 16   -- padding inside dialog
local BUTTON_MIN_W  = 90
local BUTTON_PAD_H  = 16   -- horizontal text padding per side
local BUTTON_HEIGHT = 24
local BUTTON_GAP    = 8
local TITLE_MSG_GAP = 10   -- gap between title and message
local MSG_BTN_GAP   = 16   -- gap between message and buttons

-- Lazy singleton
local dialog

-- ============================================================
-- Build singleton
-- ============================================================

local function BuildDialog()
	-- Full-screen dimmer anchored to UIParent
	local dimmer = CreateFrame('Frame', nil, UIParent)
	dimmer:SetAllPoints(UIParent)
	dimmer:SetFrameStrata('TOOLTIP')
	dimmer:SetFrameLevel(1)

	local dimTex = dimmer:CreateTexture(nil, 'BACKGROUND')
	dimTex:SetAllPoints(dimmer)
	dimTex:SetColorTexture(0, 0, 0, 0.75)

	-- Dialog box
	local frame = CreateFrame('Frame', nil, dimmer, 'BackdropTemplate')
	frame:SetFrameStrata('TOOLTIP')
	frame:SetFrameLevel(10)
	Widgets.SetSize(frame, DIALOG_WIDTH_2, 120)   -- height adjusted on show
	frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)

	-- Background: panel color
	local bg = C.Colors.panel
	frame:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	frame:SetBackdropBorderColor(0, 0, 0, 1)

	-- Accent line on top edge (1px texture overlay)
	local accentBar = frame:CreateTexture(nil, 'OVERLAY')
	accentBar:SetHeight(1)
	accentBar:SetPoint('TOPLEFT',  frame, 'TOPLEFT',  0, 0)
	accentBar:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
	local ac = C.Colors.accent
	accentBar:SetColorTexture(ac[1], ac[2], ac[3], ac[4] or 1)

	-- Title
	local title = Widgets.CreateFontString(frame, C.Font.sizeTitle, C.Colors.textActive)
	title:SetPoint('TOPLEFT',  frame, 'TOPLEFT',  PAD, -PAD)
	title:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -PAD, -PAD)
	title:SetJustifyH('LEFT')
	frame._title = title

	-- Message
	local message = Widgets.CreateFontString(frame, C.Font.sizeNormal, C.Colors.textNormal)
	message:SetPoint('TOPLEFT',  title, 'BOTTOMLEFT',  0, -TITLE_MSG_GAP)
	message:SetPoint('TOPRIGHT', title, 'BOTTOMRIGHT', 0, -TITLE_MSG_GAP)
	message:SetJustifyH('LEFT')
	message:SetWordWrap(true)
	frame._message = message

	-- Yes button (confirm dialogs)
	local btnYes = Widgets.CreateButton(frame, 'Yes', 'accent', BUTTON_MIN_W, BUTTON_HEIGHT)
	frame._btnYes = btnYes

	-- No button (confirm dialogs)
	local btnNo = Widgets.CreateButton(frame, 'No', 'widget', BUTTON_MIN_W, BUTTON_HEIGHT)
	frame._btnNo = btnNo

	-- Third button (3-button dialogs)
	local btnThird = Widgets.CreateButton(frame, '', 'widget', BUTTON_MIN_W, BUTTON_HEIGHT)
	frame._btnThird = btnThird

	-- OK button (message dialogs)
	local btnOK = Widgets.CreateButton(frame, 'OK', 'accent', BUTTON_MIN_W, BUTTON_HEIGHT)
	frame._btnOK = btnOK

	-- --------------------------------------------------------
	-- Escape / keyboard dismiss
	-- --------------------------------------------------------
	frame:EnableKeyboard(true)
	frame:SetPropagateKeyboardInput(false)
	frame:SetScript('OnKeyDown', function(self, key)
		if(key == 'ESCAPE') then
			if(self._layoutMode == 'three') then
				self:_Dismiss('third')
			else
				self:_Dismiss('cancel')
			end
		end
	end)

	-- --------------------------------------------------------
	-- Hide clears all callbacks to prevent stale references
	-- --------------------------------------------------------
	frame:HookScript('OnHide', function(self)
		self._onConfirm = nil
		self._onCancel  = nil
		self._onThird   = nil
		self._onDismiss = nil
		-- Dimmer hides via its own FadeOut; force-hide as fallback
		if(dimmer:IsShown() and dimmer:GetAlpha() <= 0.01) then
			dimmer:Hide()
		end
	end)

	-- --------------------------------------------------------
	-- Internal helpers
	-- --------------------------------------------------------

	--- Recalculate and set the dialog height based on content.
	function frame:_UpdateHeight()
		-- Force layout so GetStringHeight is accurate
		local msgHeight = self._message:GetStringHeight()
		local total = PAD                  -- top padding
					+ self._title:GetStringHeight()
					+ TITLE_MSG_GAP
					+ msgHeight
					+ MSG_BTN_GAP
					+ BUTTON_HEIGHT
					+ PAD                  -- bottom padding
		Widgets.SetSize(self, self._activeWidth, math.max(total, 100))
	end

	--- Measure a button's text and resize to fit with padding.
	--- Returns the new width.
	local function FitButton(btn)
		local textW = btn._label:GetStringWidth()
		local w = math.max(textW + BUTTON_PAD_H * 2, BUTTON_MIN_W)
		Widgets.SetSize(btn, w, BUTTON_HEIGHT)
		return w
	end

	--- Position buttons centered at the bottom of the dialog.
	--- mode: 'confirm' shows Yes+No, 'three' shows Yes+No+Third, else shows OK only.
	function frame:_LayoutButtons(mode)
		self._layoutMode = mode
		self._btnYes:Hide()
		self._btnNo:Hide()
		self._btnOK:Hide()
		self._btnThird:Hide()

		if(mode == 'confirm') then
			local w1 = FitButton(self._btnYes)
			local w2 = FitButton(self._btnNo)
			local totalW = w1 + w2 + BUTTON_GAP
			local leftX  = -(totalW / 2)
			self._btnYes:ClearAllPoints()
			self._btnYes:SetPoint('BOTTOM', self, 'BOTTOM', leftX + w1 / 2, PAD)
			self._btnNo:ClearAllPoints()
			self._btnNo:SetPoint('BOTTOM', self, 'BOTTOM', leftX + w1 + BUTTON_GAP + w2 / 2, PAD)
			self._btnYes:Show()
			self._btnNo:Show()
		elseif(mode == 'three') then
			local w1 = FitButton(self._btnYes)
			local w2 = FitButton(self._btnNo)
			local w3 = FitButton(self._btnThird)
			local totalW = w1 + w2 + w3 + BUTTON_GAP * 2
			local leftX  = -(totalW / 2)
			self._btnYes:ClearAllPoints()
			self._btnYes:SetPoint('BOTTOM', self, 'BOTTOM', leftX + w1 / 2, PAD)
			self._btnNo:ClearAllPoints()
			self._btnNo:SetPoint('BOTTOM', self, 'BOTTOM', leftX + w1 + BUTTON_GAP + w2 / 2, PAD)
			self._btnThird:ClearAllPoints()
			self._btnThird:SetPoint('BOTTOM', self, 'BOTTOM', leftX + w1 + BUTTON_GAP + w2 + BUTTON_GAP + w3 / 2, PAD)
			self._btnYes:Show()
			self._btnNo:Show()
			self._btnThird:Show()
			-- Widen dialog if buttons exceed it
			local minDialogW = totalW + PAD * 2
			if(minDialogW > self._activeWidth) then
				self._activeWidth = minDialogW
				Widgets.SetSize(self, self._activeWidth, select(2, self:GetSize()))
			end
		else
			local w1 = FitButton(self._btnOK)
			self._btnOK:ClearAllPoints()
			self._btnOK:SetPoint('BOTTOM', self, 'BOTTOM', 0, PAD)
			self._btnOK:Show()
		end
	end

	--- Unified dismiss: fires the appropriate callback then fades out.
	--- reason: 'confirm' | 'cancel' | 'third' | 'dismiss'
	function frame:_Dismiss(reason)
		local cb
		if(reason == 'confirm') then
			cb = self._onConfirm
		elseif(reason == 'cancel') then
			cb = self._onCancel
		elseif(reason == 'third') then
			cb = self._onThird
		else
			cb = self._onDismiss
		end
		-- Fade out both dialog and dimmer, then hide and fire callback
		Widgets.FadeOut(dimmer, C.Animation.durationNormal)
		Widgets.FadeOut(self, C.Animation.durationNormal, function()
			if(cb) then cb() end
		end)
	end

	-- Wire button clicks
	btnYes:SetOnClick(function()   frame:_Dismiss('confirm') end)
	btnNo:SetOnClick(function()    frame:_Dismiss('cancel')  end)
	btnOK:SetOnClick(function()    frame:_Dismiss('dismiss') end)
	btnThird:SetOnClick(function() frame:_Dismiss('third')   end)

	frame._activeWidth = DIALOG_WIDTH_2

	-- Register for pixel updates
	Widgets.AddToPixelUpdater_OnShow(frame)

	frame._dimmer = dimmer
	frame:Hide()
	dimmer:Hide()

	return frame
end

-- ============================================================
-- Show helpers
-- ============================================================

local function GetDialog()
	if(not dialog) then
		dialog = BuildDialog()
	end
	return dialog
end

--- Show the dialog: set text, layout buttons, fade in.
local function ShowDialog(title, message, mode)
	local d = GetDialog()

	-- Cancel any in-progress animation and reset alpha before showing
	if(d._anim) then d._anim['fade'] = nil end

	d._title:SetText(title or '')
	d._message:SetText(message or '')
	d._activeWidth = DIALOG_WIDTH_2
	d:_UpdateHeight()
	d:_LayoutButtons(mode)

	Widgets.FadeIn(d._dimmer, C.Animation.durationNormal)
	Widgets.FadeIn(d, C.Animation.durationNormal)

	return d
end

-- ============================================================
-- Public API
-- ============================================================

--- Show a modal confirmation dialog with Yes / No buttons.
--- @param title     string
--- @param message   string
--- @param onConfirm function  Called when the user clicks Yes
--- @param onCancel? function  Called when the user clicks No or presses Escape
--- @return Frame dialog
function Widgets.ShowConfirmDialog(title, message, onConfirm, onCancel)
	local d = ShowDialog(title, message, 'confirm')
	d._onConfirm = onConfirm
	d._onCancel  = onCancel
	d._onDismiss = nil
	return d
end

--- Show a modal message dialog with a single OK button.
--- @param title      string
--- @param message    string
--- @param onDismiss? function  Called when the user clicks OK or presses Escape
--- @return Frame dialog
function Widgets.ShowMessageDialog(title, message, onDismiss)
	local d = ShowDialog(title, message, 'message')
	d._onConfirm = nil
	d._onCancel  = nil
	d._onDismiss = onDismiss
	return d
end

--- Show a modal dialog with three buttons.
--- @param title      string
--- @param message    string
--- @param btn1Label  string   Left button label (accent style)
--- @param btn2Label  string   Middle button label (widget style)
--- @param btn3Label  string   Right button label (widget style)
--- @param onBtn1     function Called when left button clicked
--- @param onBtn2?    function Called when middle button clicked
--- @param onBtn3?    function Called when right button clicked (or Escape)
--- @return Frame dialog
function Widgets.ShowThreeButtonDialog(title, message, btn1Label, btn2Label, btn3Label, onBtn1, onBtn2, onBtn3)
	local d = GetDialog()

	if(d._anim) then d._anim['fade'] = nil end

	d._title:SetText(title or '')
	d._message:SetText(message or '')

	d._btnYes._label:SetText(btn1Label)
	d._btnNo._label:SetText(btn2Label)
	d._btnThird._label:SetText(btn3Label)

	d._activeWidth = DIALOG_WIDTH_3
	d:_UpdateHeight()
	d:_LayoutButtons('three')

	d._onConfirm = onBtn1
	d._onCancel  = onBtn2
	d._onThird   = onBtn3
	d._onDismiss = nil

	Widgets.FadeIn(d._dimmer, C.Animation.durationNormal)
	Widgets.FadeIn(d, C.Animation.durationNormal)

	return d
end
