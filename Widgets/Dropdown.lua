local addonName, Framed = ...

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- Singleton Dropdown List (shared across all dropdowns)
-- ============================================================

local ITEM_HEIGHT   = 22
local MAX_VISIBLE   = 10
local LIST_PAD      = 4     -- inner padding inside the list frame

local dropdownList          -- singleton list frame, created lazily
local dropdownBlocker       -- invisible full-screen click-catcher
local currentOwner          -- which dropdown button currently owns the list

-- Forward declarations
local EnsureDropdownList
local CloseDropdownList
local OpenDropdownList

local function EnsureDropdownList()
    if dropdownList then return end

    -- Full-screen invisible blocker behind the list — clicking it closes the list
    dropdownBlocker = CreateFrame("Frame", "FramedDropdownBlocker", UIParent)
    dropdownBlocker:SetFrameStrata("FULLSCREEN_DIALOG")
    dropdownBlocker:SetFrameLevel(90)
    dropdownBlocker:SetAllPoints(UIParent)
    dropdownBlocker:EnableMouse(true)
    dropdownBlocker:Hide()
    dropdownBlocker:SetScript("OnMouseDown", function()
        CloseDropdownList()
    end)

    -- The list frame itself
    dropdownList = CreateFrame("Frame", "FramedDropdownList", UIParent, "BackdropTemplate")
    dropdownList:SetFrameStrata("FULLSCREEN_DIALOG")
    dropdownList:SetFrameLevel(100)
    dropdownList:SetClampedToScreen(true)
    dropdownList:Hide()

    dropdownList._bgColor     = C.Colors.panel
    dropdownList._borderColor = C.Colors.border
    Widgets.ApplyBackdrop(dropdownList, C.Colors.panel, C.Colors.border)

    -- Container for item rows (inside LIST_PAD margin)
    local container = CreateFrame("Frame", nil, dropdownList)
    container:SetPoint("TOPLEFT",     dropdownList, "TOPLEFT",     LIST_PAD, -LIST_PAD)
    container:SetPoint("BOTTOMRIGHT", dropdownList, "BOTTOMRIGHT", -LIST_PAD, LIST_PAD)
    dropdownList._container = container

    -- Pool of item row frames (re-used each open)
    dropdownList._rows = {}
end

CloseDropdownList = function()
    if dropdownList then dropdownList:Hide() end
    if dropdownBlocker then dropdownBlocker:Hide() end
    currentOwner = nil
end

-- Build a single item row inside the container.
local function GetOrCreateRow(index)
    local row = dropdownList._rows[index]
    if row then return row end

    local container = dropdownList._container

    row = CreateFrame("Frame", nil, container, "BackdropTemplate")
    row:SetHeight(ITEM_HEIGHT)
    row:SetPoint("LEFT",  container, "LEFT",  0, 0)
    row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    row._bgColor     = C.Colors.panel
    row._borderColor = { 0, 0, 0, 0 }   -- transparent border normally
    Widgets.ApplyBackdrop(row, C.Colors.panel, { 0, 0, 0, 0 })
    row:EnableMouse(true)

    -- Optional preview texture swatch (for texture dropdowns)
    local swatch = row:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(20, 12)
    swatch:SetPoint("LEFT", row, "LEFT", 4, 0)
    swatch:Hide()
    row._swatch = swatch

    -- Label
    local label = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textNormal)
    label:SetPoint("LEFT",  row, "LEFT", 4, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    row._label = label

    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(
            C.Colors.widget[1], C.Colors.widget[2], C.Colors.widget[3], C.Colors.widget[4] or 1)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(
            C.Colors.panel[1], C.Colors.panel[2], C.Colors.panel[3], C.Colors.panel[4] or 0.85)
    end)

    dropdownList._rows[index] = row
    return row
end

OpenDropdownList = function(owner)
    EnsureDropdownList()

    -- Close any existing open list first
    if currentOwner and currentOwner ~= owner then
        CloseDropdownList()
    end
    currentOwner = owner

    local items     = owner._items or {}
    local selected  = owner._value
    local showCount = math.min(#items, MAX_VISIBLE)

    if showCount == 0 then
        -- Nothing to show — still allow open to display empty state
        showCount = 1
    end

    local containerW = owner:GetWidth() - LIST_PAD * 2
    local listH = showCount * ITEM_HEIGHT + LIST_PAD * 2

    Widgets.SetSize(dropdownList, owner:GetWidth(), listH)

    -- Position below the owner button
    dropdownList:ClearAllPoints()
    dropdownList:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)

    -- Populate rows
    local container = dropdownList._container

    -- Hide all existing rows first
    for _, row in ipairs(dropdownList._rows) do
        row:Hide()
    end

    if #items == 0 then
        local row = GetOrCreateRow(1)
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        row._swatch:Hide()
        row._label:SetPoint("LEFT", row, "LEFT", 4, 0)
        row._label:SetText("(empty)")
        local ts = C.Colors.textSecondary
        row._label:SetTextColor(ts[1], ts[2], ts[3], ts[4] or 1)
        row:SetScript("OnMouseDown", nil)
        row:Show()
    else
        for i = 1, showCount do
            local item = items[i]
            if not item then break end

            local row = GetOrCreateRow(i)
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * ITEM_HEIGHT)

            -- Swatch (texture preview)
            if item._texturePath then
                row._swatch:SetTexture(item._texturePath)
                local ac = C.Colors.accent
                row._swatch:SetVertexColor(ac[1], ac[2], ac[3], ac[4] or 1)
                row._swatch:Show()
                row._label:SetPoint("LEFT", row, "LEFT", 30, 0)
            else
                row._swatch:Hide()
                row._label:SetPoint("LEFT", row, "LEFT", 4, 0)
            end

            -- Font override for font-type dropdowns
            if item._fontPath then
                row._label:SetFont(item._fontPath, C.Font.sizeNormal, "")
            else
                row._label:SetFont(STANDARD_TEXT_FONT, C.Font.sizeNormal, "")
            end

            row._label:SetText(item.text or "")

            -- Highlight selected item in accent color
            if item.value == selected then
                local ac = C.Colors.accent
                row._label:SetTextColor(ac[1], ac[2], ac[3], ac[4] or 1)
            else
                local tn = C.Colors.textNormal
                row._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)
            end

            -- Capture item reference for the click handler
            local capturedItem  = item
            local capturedOwner = owner
            row:SetScript("OnMouseDown", function(self, mouseButton)
                if mouseButton ~= "LeftButton" then return end
                capturedOwner:_SelectItem(capturedItem)
                CloseDropdownList()
            end)

            row:Show()
        end
    end

    dropdownBlocker:Show()
    dropdownList:Show()
end

-- ============================================================
-- CreateDropdown — standard dropdown widget
-- ============================================================

--- Create a standard dropdown button.
--- @param parent Frame Parent frame
--- @param width? number Logical width (defaults to 160)
--- @return Frame dropdown
function Widgets.CreateDropdown(parent, width)
    width = width or 160
    local HEIGHT = 22

    local dropdown = CreateFrame("Button", nil, parent, "BackdropTemplate")
    dropdown._bgColor     = C.Colors.widget
    dropdown._borderColor = C.Colors.border
    dropdown._items       = {}
    dropdown._value       = nil
    dropdown._onSelect    = nil

    Widgets.ApplyBackdrop(dropdown, C.Colors.widget, C.Colors.border)
    Widgets.SetSize(dropdown, width, HEIGHT)
    dropdown:EnableMouse(true)

    -- Selected text label (left-aligned, inset)
    local label = Widgets.CreateFontString(dropdown, C.Font.sizeNormal, C.Colors.textNormal)
    label:SetPoint("LEFT",  dropdown, "LEFT",  6, 0)
    label:SetPoint("RIGHT", dropdown, "RIGHT", -20, 0)
    label:SetJustifyH("LEFT")
    label:SetText("")
    dropdown._label = label

    -- Arrow indicator (right-aligned)
    local arrow = Widgets.CreateFontString(dropdown, C.Font.sizeNormal, C.Colors.textSecondary)
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)
    arrow:SetText("\226\150\188")   -- UTF-8 for ▼
    dropdown._arrow = arrow

    -- Hover/Leave
    dropdown:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        Widgets.SetBackdropHighlight(self, true)
        if Widgets.ShowTooltip and self._tooltipTitle then
            Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
        end
    end)

    dropdown:SetScript("OnLeave", function(self)
        Widgets.SetBackdropHighlight(self, false)
        if Widgets.HideTooltip then
            Widgets.HideTooltip()
        end
    end)

    -- Click: toggle list
    dropdown:SetScript("OnClick", function(self)
        if not self:IsEnabled() then return end
        if currentOwner == self and dropdownList and dropdownList:IsShown() then
            CloseDropdownList()
        else
            OpenDropdownList(self)
        end
    end)

    -- --------------------------------------------------------
    -- Internal: select an item and update the button display
    -- --------------------------------------------------------
    function dropdown:_SelectItem(item)
        self._value = item.value

        -- Update label text
        self._label:SetText(item.text or "")
        local tn = C.Colors.textNormal
        self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)

        if self._onSelect then
            self._onSelect(item.value, self)
        end
    end

    -- --------------------------------------------------------
    -- Public API
    -- --------------------------------------------------------

    --- Replace the item list.
    --- @param items table Array of {text, value, icon?}
    function dropdown:SetItems(items)
        self._items = items or {}
        -- If current value no longer exists, clear display
        local found = false
        for _, item in ipairs(self._items) do
            if item.value == self._value then
                found = true
                self._label:SetText(item.text or "")
                break
            end
        end
        if not found then
            self._value = nil
            self._label:SetText("")
        end
    end

    --- Register a callback fired on selection: func(value, dropdown).
    --- @param func function
    function dropdown:SetOnSelect(func)
        self._onSelect = func
    end

    --- Get the currently selected value.
    --- @return any
    function dropdown:GetValue()
        return self._value
    end

    --- Programmatically set the selected value and update display.
    --- @param value any
    function dropdown:SetValue(value)
        for _, item in ipairs(self._items) do
            if item.value == value then
                self._value = value
                self._label:SetText(item.text or "")
                local tn = C.Colors.textNormal
                self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)
                return
            end
        end
        -- Value not found — clear display
        self._value = nil
        self._label:SetText("")
    end

    --- Enable or disable the dropdown.
    --- @param enabled boolean
    function dropdown:SetEnabled(enabled)
        self._enabled = enabled
        if enabled then
            self:EnableMouse(true)
            Widgets.ApplyBackdrop(self, C.Colors.widget, C.Colors.border)
            local tn = C.Colors.textNormal
            self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)
            local ts = C.Colors.textSecondary
            self._arrow:SetTextColor(ts[1], ts[2], ts[3], ts[4] or 1)
        else
            -- Close if open
            if currentOwner == self then CloseDropdownList() end
            self:EnableMouse(false)
            local w = C.Colors.widget
            self:SetBackdropColor(w[1] * 0.6, w[2] * 0.6, w[3] * 0.6, w[4] or 1)
            self:SetBackdropBorderColor(0, 0, 0, 1)
            local td = C.Colors.textDisabled
            self._label:SetTextColor(td[1], td[2], td[3], td[4] or 1)
            self._arrow:SetTextColor(td[1], td[2], td[3], td[4] or 1)
        end
    end

    Widgets.ApplyBaseMixin(dropdown)
    Widgets.AttachTooltipScripts(dropdown)

    return dropdown
end

-- ============================================================
-- CreateTextureDropdown — LSM-backed texture/font picker
-- ============================================================

--- Create a LibSharedMedia-backed dropdown.
--- @param parent Frame Parent frame
--- @param width? number Logical width (defaults to 200)
--- @param mediaType? string LSM media type: "statusbar"|"font"|etc. (defaults to "statusbar")
--- @return Frame dropdown
function Widgets.CreateTextureDropdown(parent, width, mediaType)
    width     = width     or 200
    mediaType = mediaType or "statusbar"

    -- Safe LSM access — may not be loaded yet
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    -- Build the base dropdown
    local dropdown = Widgets.CreateDropdown(parent, width)
    dropdown._mediaType = mediaType
    dropdown._lsmOnSelect = nil

    -- --------------------------------------------------------
    -- Override _SelectItem to expose texture path + name
    -- --------------------------------------------------------
    local baseSelectItem = dropdown._SelectItem
    function dropdown:_SelectItem(item)
        self._value = item.value  -- stores LSM name as value

        self._label:SetText(item.text or "")
        local tn = C.Colors.textNormal
        self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)

        -- Update button swatch for statusbar type
        if self._buttonSwatch then
            if item._texturePath and self._mediaType == "statusbar" then
                self._buttonSwatch:SetTexture(item._texturePath)
                local ac = C.Colors.accent
                self._buttonSwatch:SetVertexColor(ac[1], ac[2], ac[3], ac[4] or 1)
                self._buttonSwatch:Show()
                self._label:SetPoint("LEFT", self, "LEFT", 28, 0)
            else
                self._buttonSwatch:Hide()
                self._label:SetPoint("LEFT", self, "LEFT", 6, 0)
            end
        end

        if self._lsmOnSelect then
            self._lsmOnSelect(item._texturePath or item.value, item.value, self)
        elseif self._onSelect then
            self._onSelect(item._texturePath or item.value, self)
        end
    end

    -- Button-level swatch preview (statusbar only)
    if mediaType == "statusbar" then
        local swatch = dropdown:CreateTexture(nil, "ARTWORK")
        swatch:SetSize(20, 12)
        swatch:SetPoint("LEFT", dropdown, "LEFT", 4, 0)
        swatch:Hide()
        dropdown._buttonSwatch = swatch
    end

    -- --------------------------------------------------------
    -- Populate items from LSM
    -- --------------------------------------------------------
    local function BuildItems(lsm)
        if not lsm then return {} end
        local names = lsm:List(mediaType)
        if not names then return {} end

        local items = {}
        for _, name in ipairs(names) do
            local path = lsm:Fetch(mediaType, name)
            local item = {
                text  = name,
                value = name,
                _texturePath = (mediaType == "statusbar") and path or nil,
                _fontPath    = (mediaType == "font")      and path or nil,
            }
            items[#items + 1] = item
        end
        return items
    end

    -- --------------------------------------------------------
    -- Public API overrides / additions
    -- --------------------------------------------------------

    --- Re-populate items from LSM (call after LSM finishes loading).
    function dropdown:Refresh()
        local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
        if not lsm then
            -- No LSM — warn once and leave items empty
            if not self._lsmWarned then
                self._lsmWarned = true
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cffff8800Framed:|r TextureDropdown: LibSharedMedia-3.0 not available.")
                end
            end
            self:SetItems({})
            return
        end
        self:SetItems(BuildItems(lsm))
    end

    --- Override SetOnSelect to capture the LSM-specific signature:
    --- func(texturePath, textureName, dropdown).
    --- @param func function
    function dropdown:SetOnSelect(func)
        self._lsmOnSelect = func
    end

    --- Get the currently selected LSM name.
    --- @return string|nil
    function dropdown:GetValue()
        return self._value
    end

    --- Set the selected item by LSM registered name.
    --- @param textureName string
    function dropdown:SetValue(textureName)
        for _, item in ipairs(self._items) do
            if item.value == textureName then
                self._value = textureName
                self._label:SetText(item.text or "")
                local tn = C.Colors.textNormal
                self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)

                -- Update button swatch
                if self._buttonSwatch then
                    if item._texturePath then
                        self._buttonSwatch:SetTexture(item._texturePath)
                        local ac = C.Colors.accent
                        self._buttonSwatch:SetVertexColor(ac[1], ac[2], ac[3], ac[4] or 1)
                        self._buttonSwatch:Show()
                        self._label:SetPoint("LEFT", self, "LEFT", 28, 0)
                    else
                        self._buttonSwatch:Hide()
                        self._label:SetPoint("LEFT", self, "LEFT", 6, 0)
                    end
                end
                return
            end
        end
        self._value = nil
        self._label:SetText("")
        if self._buttonSwatch then
            self._buttonSwatch:Hide()
            self._label:SetPoint("LEFT", self, "LEFT", 6, 0)
        end
    end

    -- Initial population (LSM may already be present at load time)
    if LSM then
        dropdown:SetItems(BuildItems(LSM))
    end

    return dropdown
end
