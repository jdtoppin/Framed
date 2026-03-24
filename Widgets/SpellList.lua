local addonName, Framed = ...

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- SpellList — scrollable spell list + spell ID input widget
-- Used by Buffs/Debuffs settings panels to configure tracked
-- spells per indicator category.
-- ============================================================

local ROW_HEIGHT  = 28
local ICON_SIZE   = 20
local ICON_GAP    = 4
local REMOVE_SIZE = 14
local PAD_H       = 6   -- horizontal padding inside each row

local function GetSpellData(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, info.iconID end
    elseif GetSpellInfo then
        local name, _, icon = GetSpellInfo(spellID)
        if name then return name, icon end
    end
    return nil, nil
end

-- Row pool helpers

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row._bgColor     = C.Colors.widget
    row._borderColor = C.Colors.border
    Widgets.ApplyBackdrop(row, C.Colors.widget, C.Colors.border)

    -- Spell icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", PAD_H, 0)
    row._icon = icon

    -- Spell name
    local nameFS = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textActive)
    nameFS:SetPoint("LEFT", icon, "RIGHT", ICON_GAP, 0)
    nameFS:SetJustifyH("LEFT")
    row._nameFS = nameFS

    -- Spell ID (gray, right-aligned before remove button)
    local idFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
    idFS:SetJustifyH("RIGHT")
    row._idFS = idFS

    -- Remove button ("✕", 14×14)
    local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    removeBtn._bgColor     = C.Colors.widget
    removeBtn._borderColor = C.Colors.border
    Widgets.ApplyBackdrop(removeBtn, C.Colors.widget, C.Colors.border)
    Widgets.SetSize(removeBtn, REMOVE_SIZE, REMOVE_SIZE)
    removeBtn:SetPoint("RIGHT", row, "RIGHT", -PAD_H, 0)

    local removeLbl = Widgets.CreateFontString(removeBtn, C.Font.sizeSmall, C.Colors.textSecondary)
    removeLbl:SetPoint("CENTER", removeBtn, "CENTER", 0, 0)
    removeLbl:SetText("\xE2\x9C\x95")  -- UTF-8 ✕
    removeBtn._label = removeLbl

    removeBtn:SetScript("OnEnter", function(self)
        local tc = C.Colors.textActive
        self._label:SetTextColor(tc[1], tc[2], tc[3], 1)
        local rc = { 0.7, 0.2, 0.2, 1 }
        self:SetBackdropBorderColor(rc[1], rc[2], rc[3], rc[4])
    end)
    removeBtn:SetScript("OnLeave", function(self)
        local ts = C.Colors.textSecondary
        self._label:SetTextColor(ts[1], ts[2], ts[3], 1)
        self:SetBackdropBorderColor(0, 0, 0, 1)
    end)

    row._removeBtn = removeBtn

    -- Anchor ID label between name and remove button
    idFS:SetPoint("RIGHT", removeBtn, "LEFT", -PAD_H, 0)

    -- Hover highlight on the row itself
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        Widgets.SetBackdropHighlight(self, true)
    end)
    row:SetScript("OnLeave", function(self)
        Widgets.SetBackdropHighlight(self, false)
    end)

    return row
end

local function AcquireRow(pool, parent)
    for _, r in ipairs(pool) do
        if not r:IsShown() then r:Show(); return r end
    end
    local r = CreateRow(parent)
    table.insert(pool, r)
    return r
end

local function ReleaseAllRows(pool)
    for _, r in ipairs(pool) do r:Hide() end
end

--- Create a scrollable spell list widget.
--- @param parent Frame   Parent frame
--- @param width  number  Logical width
--- @param height number  Logical height
--- @return Frame spellList
function Widgets.CreateSpellList(parent, width, height)
    -- Outer container
    local spellList = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    spellList._bgColor     = C.Colors.panel
    spellList._borderColor = C.Colors.border
    Widgets.ApplyBackdrop(spellList, C.Colors.panel, C.Colors.border)
    Widgets.SetSize(spellList, width, height)
    Widgets.ApplyBaseMixin(spellList)

    -- Internal state
    spellList._spells    = {}  -- ordered array of spellIDs
    spellList._rowPool   = {}
    spellList._onChanged = nil

    -- ScrollFrame fills the outer container
    local scroll = Widgets.CreateScrollFrame(spellList, nil, width, height)
    scroll:SetPoint("TOPLEFT",     spellList, "TOPLEFT",     0, 0)
    scroll:SetPoint("BOTTOMRIGHT", spellList, "BOTTOMRIGHT", 0, 0)
    spellList._scroll = scroll

    local content = scroll:GetContentFrame()

    -- Empty-state label
    local emptyLabel = Widgets.CreateFontString(spellList, C.Font.sizeNormal, C.Colors.textSecondary)
    emptyLabel:SetPoint("CENTER", spellList, "CENTER", 0, 0)
    emptyLabel:SetText("No spells configured")
    spellList._emptyLabel = emptyLabel

    local function Layout()
        ReleaseAllRows(spellList._rowPool)

        local spells = spellList._spells
        local count  = #spells

        if count == 0 then
            spellList._emptyLabel:Show()
            content:SetHeight(1)
            scroll:UpdateScrollRange()
            return
        end

        spellList._emptyLabel:Hide()

        local contentWidth = content:GetWidth()
        if contentWidth <= 0 then contentWidth = width end

        for i, spellID in ipairs(spells) do
            local row = AcquireRow(spellList._rowPool, content)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * ROW_HEIGHT)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
            row:SetHeight(ROW_HEIGHT)

            -- Populate spell data
            local name, icon = GetSpellData(spellID)
            row._nameFS:SetText(name or ("Spell " .. spellID))
            row._idFS:SetText(tostring(spellID))

            if icon then
                row._icon:SetTexture(icon)
                row._icon:Show()
            else
                row._icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                row._icon:Show()
            end

            -- Clamp name width so it does not overlap the ID / remove button
            local idWidth = row._idFS:GetStringWidth()
            local usedRight = PAD_H + REMOVE_SIZE + PAD_H + idWidth + PAD_H
            local usedLeft  = PAD_H + ICON_SIZE + ICON_GAP
            row._nameFS:SetWidth(math.max(1, (contentWidth - usedLeft - usedRight)))

            -- Wire remove button for this specific spellID
            local capturedID = spellID
            row._removeBtn:SetScript("OnClick", function()
                spellList:RemoveSpell(capturedID)
            end)
        end

        content:SetHeight(count * ROW_HEIGHT)
        scroll:UpdateScrollRange()
    end

    spellList._layout = Layout

    local function NotifyChanged()
        if spellList._onChanged then
            -- Pass a shallow copy so callers cannot mutate internal state
            local copy = {}
            for i, v in ipairs(spellList._spells) do copy[i] = v end
            spellList._onChanged(copy)
        end
        Layout()
    end

    --- Add a spell by ID. Ignores duplicates.
    --- @param spellID number
    function spellList:AddSpell(spellID)
        spellID = tonumber(spellID)
        if not spellID then return end
        for _, id in ipairs(self._spells) do
            if id == spellID then return end
        end
        table.insert(self._spells, spellID)
        NotifyChanged()
    end

    --- Remove a spell by ID.
    --- @param spellID number
    function spellList:RemoveSpell(spellID)
        spellID = tonumber(spellID)
        if not spellID then return end
        for i, id in ipairs(self._spells) do
            if id == spellID then
                table.remove(self._spells, i)
                NotifyChanged()
                return
            end
        end
    end

    --- Replace the entire spell list.
    --- @param spellIDs table Array of spell IDs
    function spellList:SetSpells(spellIDs)
        self._spells = {}
        if spellIDs then
            for _, id in ipairs(spellIDs) do
                local n = tonumber(id)
                if n then
                    -- Deduplicate inline
                    local dup = false
                    for _, existing in ipairs(self._spells) do
                        if existing == n then dup = true; break end
                    end
                    if not dup then
                        table.insert(self._spells, n)
                    end
                end
            end
        end
        Layout()
    end

    --- Get the current array of configured spell IDs.
    --- @return table
    function spellList:GetSpells()
        local copy = {}
        for i, v in ipairs(self._spells) do copy[i] = v end
        return copy
    end

    --- Register a callback called with (spellIDs) whenever the list changes.
    --- @param func function
    function spellList:SetOnChanged(func)
        self._onChanged = func
    end

    -- Initial layout (empty state)
    Layout()

    spellList:HookScript("OnShow", function(self)
        C_Timer.After(0, function()
            if spellList and spellList._layout then
                spellList._layout()
            end
        end)
    end)

    Widgets.AddToPixelUpdater_OnShow(spellList)

    return spellList
end

-- SpellInput — compact spell ID entry with debounced live preview

local PREVIEW_ICON_SIZE = 16
local INPUT_WIDTH       = 170
local ADD_BTN_WIDTH     = 60
local INPUT_ROW_HEIGHT  = 24
local PREVIEW_HEIGHT    = 20
local DEBOUNCE_DELAY    = 0.3

--- Create a spell ID input widget with live preview.
--- @param parent Frame  Parent frame
--- @param width  number Total logical width
--- @return Frame input
function Widgets.CreateSpellInput(parent, width)
    local totalHeight = INPUT_ROW_HEIGHT + C.Spacing.tight + PREVIEW_HEIGHT

    local container = CreateFrame("Frame", nil, parent)
    Widgets.SetSize(container, width, totalHeight)
    Widgets.ApplyBaseMixin(container)

    container._spellList  = nil
    container._onAdd      = nil
    container._debounce   = nil

    local editBox = Widgets.CreateEditBox(container, nil, INPUT_WIDTH, INPUT_ROW_HEIGHT, "number")
    editBox:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    editBox:SetPlaceholder("Spell ID…")
    container._editBox = editBox

    local addBtn = Widgets.CreateButton(container, "Add", "accent", ADD_BTN_WIDTH, INPUT_ROW_HEIGHT)
    addBtn:SetPoint("LEFT", editBox, "RIGHT", C.Spacing.base, 0)
    container._addBtn = addBtn

    local preview = CreateFrame("Frame", nil, container)
    preview:SetPoint("TOPLEFT",  container, "TOPLEFT",  0, -(INPUT_ROW_HEIGHT + C.Spacing.tight))
    preview:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -(INPUT_ROW_HEIGHT + C.Spacing.tight))
    preview:SetHeight(PREVIEW_HEIGHT)
    preview:Hide()
    container._preview = preview

    local previewIcon = preview:CreateTexture(nil, "ARTWORK")
    previewIcon:SetSize(PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
    previewIcon:SetPoint("LEFT", preview, "LEFT", 0, 0)
    container._previewIcon = previewIcon

    local previewName = Widgets.CreateFontString(preview, C.Font.sizeSmall, C.Colors.textNormal)
    previewName:SetPoint("LEFT", previewIcon, "RIGHT", ICON_GAP, 0)
    previewName:SetJustifyH("LEFT")
    container._previewName = previewName

    local function SetEditBoxError(hasError)
        local color = hasError and { 0.8, 0.2, 0.2, 1 } or { 0, 0, 0, 1 }
        editBox:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
    end

    local function ShowPreview(spellID)
        local name, icon = GetSpellData(spellID)
        if name then
            container._previewIcon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            container._previewName:SetText(name)
            preview:Show()
            SetEditBoxError(false)
        else
            preview:Hide()
            SetEditBoxError(true)
        end
    end

    local function ClearPreview()
        preview:Hide()
        SetEditBoxError(false)
    end

    local function TryAddSpell()
        local text = editBox:GetText()
        local spellID = tonumber(text)
        if not spellID or spellID <= 0 then
            SetEditBoxError(true)
            return
        end

        local name = GetSpellData(spellID)
        if not name then
            SetEditBoxError(true)
            return
        end

        if container._spellList then
            container._spellList:AddSpell(spellID)
        end

        if container._onAdd then
            container._onAdd(spellID)
        end

        editBox:SetText("")
        ClearPreview()
    end

    editBox:SetOnTextChanged(function(text)
        -- Cancel previous debounce timer
        if container._debounce then
            container._debounce:Cancel()
            container._debounce = nil
        end

        local spellID = tonumber(text)
        if not spellID or spellID <= 0 then
            ClearPreview()
            return
        end

        container._debounce = C_Timer.NewTimer(DEBOUNCE_DELAY, function()
            container._debounce = nil
            ShowPreview(spellID)
        end)
    end)

    editBox:SetOnEnterPressed(function(_text) TryAddSpell() end)
    addBtn:SetOnClick(function() TryAddSpell() end)

    --- Link this input to a SpellList for auto-add on confirm.
    --- @param spellList Frame  A SpellList created by Widgets.CreateSpellList
    function container:SetSpellList(spellList)
        self._spellList = spellList
    end

    --- Optional callback called with (spellID) on successful add.
    --- @param func function
    function container:SetOnAdd(func)
        self._onAdd = func
    end

    return container
end
