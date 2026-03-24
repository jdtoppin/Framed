local addonName, Framed = ...

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- Dialog — Confirmation and Message dialogs
-- Singleton frame shared between ShowConfirmDialog and
-- ShowMessageDialog. Only one dialog is visible at a time.
-- ============================================================

local DIALOG_WIDTH  = 350
local PAD           = 16   -- padding inside dialog
local BUTTON_WIDTH  = 90
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
    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetAllPoints(UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetFrameLevel(1)

    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints(dimmer)
    dimTex:SetColorTexture(0, 0, 0, 0.5)

    -- Dialog box
    local frame = CreateFrame("Frame", nil, dimmer, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(10)
    Widgets.SetSize(frame, DIALOG_WIDTH, 120)   -- height adjusted on show
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    -- Background: panel color
    local bg = C.Colors.panel
    frame:SetBackdrop({
        bgFile   = "Interface\\BUTTONS\\WHITE8x8",
        edgeFile = "Interface\\BUTTONS\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    -- Accent line on top edge (1px texture overlay)
    local accentBar = frame:CreateTexture(nil, "OVERLAY")
    accentBar:SetHeight(1)
    accentBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    accentBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    local ac = C.Colors.accent
    accentBar:SetColorTexture(ac[1], ac[2], ac[3], ac[4] or 1)

    -- Title
    local title = Widgets.CreateFontString(frame, C.Font.sizeTitle, C.Colors.textActive)
    title:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD, -PAD)
    title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD)
    title:SetJustifyH("LEFT")
    frame._title = title

    -- Message
    local message = Widgets.CreateFontString(frame, C.Font.sizeNormal, C.Colors.textNormal)
    message:SetPoint("TOPLEFT",  title, "BOTTOMLEFT",  0, -TITLE_MSG_GAP)
    message:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -TITLE_MSG_GAP)
    message:SetJustifyH("LEFT")
    message:SetWordWrap(true)
    frame._message = message

    -- Yes button (confirm dialogs)
    local btnYes = Widgets.CreateButton(frame, "Yes", "accent", BUTTON_WIDTH, BUTTON_HEIGHT)
    frame._btnYes = btnYes

    -- No button (confirm dialogs)
    local btnNo = Widgets.CreateButton(frame, "No", "widget", BUTTON_WIDTH, BUTTON_HEIGHT)
    frame._btnNo = btnNo

    -- OK button (message dialogs)
    local btnOK = Widgets.CreateButton(frame, "OK", "accent", BUTTON_WIDTH, BUTTON_HEIGHT)
    frame._btnOK = btnOK

    -- --------------------------------------------------------
    -- Escape / keyboard dismiss
    -- --------------------------------------------------------
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(false)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:_Dismiss("cancel")
        end
    end)

    -- --------------------------------------------------------
    -- Hide clears all callbacks to prevent stale references
    -- --------------------------------------------------------
    frame:HookScript("OnHide", function(self)
        self._onConfirm = nil
        self._onCancel  = nil
        self._onDismiss = nil
        dimmer:Hide()
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
        Widgets.SetSize(self, DIALOG_WIDTH, math.max(total, 100))
    end

    --- Position buttons centered at the bottom of the dialog.
    --- mode: "confirm" shows Yes+No, "message" shows OK only.
    function frame:_LayoutButtons(mode)
        self._btnYes:Hide()
        self._btnNo:Hide()
        self._btnOK:Hide()

        if mode == "confirm" then
            -- Yes left of center, No right of center
            local totalW = BUTTON_WIDTH * 2 + BUTTON_GAP
            local leftX  = -(totalW / 2)
            self._btnYes:ClearAllPoints()
            self._btnYes:SetPoint("BOTTOM", self, "BOTTOM", leftX + BUTTON_WIDTH / 2, PAD)
            self._btnNo:ClearAllPoints()
            self._btnNo:SetPoint("BOTTOM", self, "BOTTOM", leftX + BUTTON_WIDTH + BUTTON_GAP + BUTTON_WIDTH / 2, PAD)
            self._btnYes:Show()
            self._btnNo:Show()
        else
            -- OK centered
            self._btnOK:ClearAllPoints()
            self._btnOK:SetPoint("BOTTOM", self, "BOTTOM", 0, PAD)
            self._btnOK:Show()
        end
    end

    --- Unified dismiss: fires the appropriate callback then hides.
    --- reason: "confirm" | "cancel" | "dismiss"
    function frame:_Dismiss(reason)
        if reason == "confirm" then
            local cb = self._onConfirm
            self:Hide()
            if cb then cb() end
        elseif reason == "cancel" then
            local cb = self._onCancel
            self:Hide()
            if cb then cb() end
        else  -- "dismiss"
            local cb = self._onDismiss
            self:Hide()
            if cb then cb() end
        end
    end

    -- Wire button clicks
    btnYes:SetOnClick(function() frame:_Dismiss("confirm") end)
    btnNo:SetOnClick(function()  frame:_Dismiss("cancel")  end)
    btnOK:SetOnClick(function()  frame:_Dismiss("dismiss") end)

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
    if not dialog then
        dialog = BuildDialog()
    end
    return dialog
end

--- Show the dialog: set text, layout buttons, fade in.
local function ShowDialog(title, message, mode)
    local d = GetDialog()

    -- Cancel any in-progress animation and reset alpha before showing
    if d._anim then d._anim["fade"] = nil end

    d._title:SetText(title or "")
    d._message:SetText(message or "")
    d:_UpdateHeight()
    d:_LayoutButtons(mode)

    d._dimmer:Show()
    d._dimmer:SetAlpha(1)

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
    local d = ShowDialog(title, message, "confirm")
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
    local d = ShowDialog(title, message, "message")
    d._onConfirm = nil
    d._onCancel  = nil
    d._onDismiss = onDismiss
    return d
end
