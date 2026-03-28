# Responsive Card Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed single-column settings layout with a responsive grid that flows cards left-to-right, wraps to new rows based on available width, supports lazy card creation on scroll, and allows pinning frequently-used cards to the top.

**Architecture:** A new `Widgets.CreateCardGrid` layout widget measures its parent width and positions card frames in a wrap-flow grid (left→right, top→bottom). Each card is produced by a standalone builder function that returns a card frame. `FrameSettingsBuilder` is refactored from one monolithic function into a registry of independent card builders. The grid re-layouts on parent resize via `OnSizeChanged`. Lazy loading defers card creation until the card's row is near the visible scroll region. Pinned cards are stored in config and sorted to the front of the grid.

**Tech Stack:** WoW Lua (Frame API, BackdropTemplate), oUF, Framed widget library

---

## File Structure

| File | Responsibility |
|------|----------------|
| **Create:** `Widgets/CardGrid.lua` | Grid layout widget — measures width, positions cards in rows, handles reflow on resize, lazy loading |
| **Create:** `Settings/Cards/PositionAndLayout.lua` | Card builder: frame width, height, resize anchor, position, pixel nudge |
| **Create:** `Settings/Cards/GroupLayout.lua` | Card builder: spacing, orientation, growth direction (group frames only) |
| **Create:** `Settings/Cards/HealthColor.lua` | Card builder: health color mode, gradient, threat, loss color — includes reflow logic |
| **Create:** `Settings/Cards/ShieldsAndAbsorbs.lua` | Card builder: heal prediction, damage/heal absorb, overshield toggles + pickers |
| **Create:** `Settings/Cards/PowerBar.lua` | Card builder: show power, position, height, per-type color pickers |
| **Create:** `Settings/Cards/CastBar.lua` | Card builder: show cast bar, size mode, width/height, background mode — includes reflow |
| **Create:** `Settings/Cards/Name.lua` | Card builder: show name, color mode, custom color, anchor, offsets — includes reflow |
| **Create:** `Settings/Cards/HealthText.lua` | Card builder: attach-to-name, show, format, font size, outline, shadow, anchor, offsets |
| **Create:** `Settings/Cards/PowerText.lua` | Card builder: show power text, font size, outline, shadow, anchor, offsets |
| **Create:** `Settings/Cards/StatusIcons.lua` | Card builder: all status icon toggles |
| **Modify:** `Settings/FrameSettingsBuilder.lua` | Gutted — becomes thin orchestrator that registers card builders with the grid |
| **Modify:** `Framed.toc` | Add new files to load order |

---

## Conventions Used Throughout

All card builders follow this signature and pattern:

```lua
--- @param parent Frame       The grid's internal container (cards parent themselves to this)
--- @param width number        Card width assigned by the grid
--- @param unitType string     e.g. 'player', 'target', 'party'
--- @param getConfig function  function(key) → value
--- @param setConfig function  function(key, value)
--- @return Frame card         The card frame (from Widgets.StartCard)
--- @return string title       Display title for the card (used by pin UI)
local function BuildCard(parent, width, unitType, getConfig, setConfig)
```

Layout helpers (`placeWidget`, `placeHeading`) and widget dimension constants (`SLIDER_H`, `SWITCH_H`, etc.) are defined once in a shared location — either kept at the top of `FrameSettingsBuilder.lua` (since the orchestrator still exists) or extracted to a small `Settings/Cards/Helpers.lua`. The plan keeps them in `FrameSettingsBuilder.lua` since the orchestrator imports them.

---

### Task 1: Create the CardGrid Layout Widget

**Files:**
- Create: `Widgets/CardGrid.lua`
- Modify: `Framed.toc`

The grid widget is the foundation everything else depends on.

- [ ] **Step 1: Create `Widgets/CardGrid.lua` with constructor**

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

local CARD_MIN_W   = 280   -- minimum card width to fit sliders/switches
local CARD_GAP     = C.Spacing.normal  -- 12px between cards
local ROW_GAP      = C.Spacing.normal  -- 12px between rows

--- Create a responsive card grid that flows cards left→right, top→bottom.
--- @param parent Frame   Scroll content frame
--- @param width number   Available width (will be updated on resize)
--- @return table grid    Grid controller object
function Widgets.CreateCardGrid(parent, width)
    local grid = {}
    grid._parent = parent
    grid._width = width
    grid._cards = {}       -- ordered list of { card=Frame, title=string, pinned=bool, builder=func, built=bool }
    grid._container = CreateFrame('Frame', nil, parent)
    grid._container:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, 0)
    grid._container:SetWidth(width)

    --- Register a card builder. Card is not created until Layout() or lazy load.
    --- @param id string        Unique card identifier (e.g. 'castbar')
    --- @param title string     Display name
    --- @param builder function function(parent, width, ...) → Frame card
    --- @param builderArgs table  Additional args passed to builder after width
    function grid:AddCard(id, title, builder, builderArgs)
        self._cards[#self._cards + 1] = {
            id = id,
            title = title,
            builder = builder,
            builderArgs = builderArgs or {},
            card = nil,
            built = false,
            pinned = false,
        }
    end

    --- Mark a card as pinned (floats to top of grid).
    --- @param id string  Card identifier
    --- @param pinned boolean
    function grid:SetPinned(id, pinned)
        for _, entry in next, self._cards do
            if(entry.id == id) then
                entry.pinned = pinned
                break
            end
        end
    end

    --- Calculate how many columns fit at the current width.
    --- @return number cols, number cardWidth
    function grid:GetColumnLayout()
        local w = self._width
        -- How many CARD_MIN_W cards fit with gaps between them?
        local cols = math.max(1, math.floor((w + CARD_GAP) / (CARD_MIN_W + CARD_GAP)))
        -- Distribute remaining space evenly across cards
        local cardW = math.floor((w - (cols - 1) * CARD_GAP) / cols)
        return cols, cardW
    end

    --- Build a single card entry if not already built.
    --- @param entry table  Card entry from self._cards
    --- @param cardW number Card width
    local function buildCard(entry, cardW)
        if(entry.built) then return end
        entry.card = entry.builder(grid._container, cardW, unpack(entry.builderArgs))
        entry.built = true
    end

    --- Get sorted card order: pinned first (preserving relative order), then unpinned.
    --- @return table orderedEntries
    function grid:GetSortedCards()
        local pinned = {}
        local unpinned = {}
        for _, entry in next, self._cards do
            if(entry.pinned) then
                pinned[#pinned + 1] = entry
            else
                unpinned[#unpinned + 1] = entry
            end
        end
        local sorted = {}
        for _, e in next, pinned do sorted[#sorted + 1] = e end
        for _, e in next, unpinned do sorted[#sorted + 1] = e end
        return sorted
    end

    --- Position all built cards in the grid. Build any unbuilt cards
    --- whose row is within the visible + buffer region.
    --- @param scrollOffset number  Current scroll offset (0 = top)
    --- @param viewHeight number    Visible scroll region height
    function grid:Layout(scrollOffset, viewHeight)
        local cols, cardW = self:GetColumnLayout()
        local sorted = self:GetSortedCards()

        -- Buffer: build cards 1 row ahead of visible area
        local bufferPx = 400
        local visibleTop = scrollOffset or 0
        local visibleBottom = visibleTop + (viewHeight or 9999) + bufferPx

        local col = 0
        local rowY = 0
        local rowHeight = 0
        local rowEntries = {}

        for _, entry in next, sorted do
            -- Build card if within visible+buffer range (lazy loading)
            if(rowY <= visibleBottom) then
                buildCard(entry, cardW)
            end

            if(not entry.built or not entry.card) then
                -- Skip unbuilt cards — they'll be built on next scroll
                -- But we still need to estimate row advancement
                -- Use a default height estimate for unbuilt cards
                if(col >= cols) then
                    rowY = rowY + rowHeight + ROW_GAP
                    col = 0
                    rowHeight = 0
                end
                col = col + 1
                rowHeight = math.max(rowHeight, 100) -- estimated default
            else
                if(col >= cols) then
                    rowY = rowY + rowHeight + ROW_GAP
                    col = 0
                    rowHeight = 0
                end

                local card = entry.card
                -- Resize card width if columns changed
                card:SetWidth(cardW)
                if(card.content) then
                    -- inner content uses anchored TOPRIGHT so width auto-adjusts
                    -- but we need to refresh widget widths inside
                end

                local x = col * (cardW + CARD_GAP)
                card:ClearAllPoints()
                Widgets.SetPoint(card, 'TOPLEFT', grid._container, 'TOPLEFT', x, -rowY)

                local cardH = card:GetHeight()
                rowHeight = math.max(rowHeight, cardH)
                col = col + 1
            end
        end

        -- Final row height
        local totalH = rowY + rowHeight
        grid._container:SetHeight(totalH)
        grid._totalHeight = totalH
    end

    --- Update available width and re-layout.
    --- @param newWidth number
    function grid:SetWidth(newWidth)
        self._width = newWidth
        grid._container:SetWidth(newWidth)
        self:Layout()
    end

    --- Get total content height after layout.
    --- @return number
    function grid:GetTotalHeight()
        return self._totalHeight or 0
    end

    return grid
end
```

- [ ] **Step 2: Add `Widgets/CardGrid.lua` to `Framed.toc`**

Add below the existing widget files (after `Widgets/ScrollFrame.lua` or the last Widgets entry):

```
Widgets\CardGrid.lua
```

- [ ] **Step 3: Commit**

```bash
git add Widgets/CardGrid.lua Framed.toc
git commit -m "feat: add CardGrid responsive layout widget"
```

---

### Task 2: Extract Card Helpers to Shared Location

**Files:**
- Modify: `Settings/FrameSettingsBuilder.lua`

Extract the layout constants and helper functions that all card builders need so they can be accessed from separate files. Keep them on the `F.FrameSettingsBuilder` namespace since it already exists.

- [ ] **Step 1: Move constants and helpers to be accessible from card builders**

At the top of `Settings/FrameSettingsBuilder.lua`, after the existing local constants, expose them on the namespace:

```lua
-- Shared layout constants for card builders
F.FrameSettingsBuilder.SLIDER_H    = 26
F.FrameSettingsBuilder.SWITCH_H    = 22
F.FrameSettingsBuilder.DROPDOWN_H  = 22
F.FrameSettingsBuilder.CHECK_H     = 14
F.FrameSettingsBuilder.PANE_TITLE_H = 20
F.FrameSettingsBuilder.WIDGET_W    = 220

--- Place a widget at the current yOffset inside a card.
--- @param widget Frame
--- @param content Frame   Card inner frame
--- @param yOffset number  Current Y position
--- @param height number   Widget height
--- @return number nextYOffset
function F.FrameSettingsBuilder.PlaceWidget(widget, content, yOffset, height)
    widget:ClearAllPoints()
    Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
    return yOffset - height - C.Spacing.normal
end

--- Place a heading inside a card.
--- @param content Frame
--- @param text string
--- @param level number  1, 2, or 3
--- @param yOffset number
--- @param width number|nil
--- @return number nextYOffset
function F.FrameSettingsBuilder.PlaceHeading(content, text, level, yOffset, width)
    local heading, height = Widgets.CreateHeading(content, text, level, width)
    heading:ClearAllPoints()
    Widgets.SetPoint(heading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
    return yOffset - height
end
```

Keep the local aliases in the file for backward compatibility during migration:
```lua
local placeWidget = F.FrameSettingsBuilder.PlaceWidget
local placeHeading = F.FrameSettingsBuilder.PlaceHeading
```

- [ ] **Step 2: Commit**

```bash
git add Settings/FrameSettingsBuilder.lua
git commit -m "refactor: expose card layout helpers on FrameSettingsBuilder namespace"
```

---

### Task 3: Extract PositionAndLayout Card Builder

**Files:**
- Create: `Settings/Cards/PositionAndLayout.lua`
- Modify: `Framed.toc`

This is the first card extraction — establishes the pattern for all subsequent cards.

- [ ] **Step 1: Create the `Settings/Cards/` directory and `PositionAndLayout.lua`**

Extract the Position & Layout card from `FrameSettingsBuilder.lua`. This card contains: frame width slider, frame height slider, resize anchor heading + info button + anchor picker, frame position heading + X/Y sliders, pixel nudge heading + nudge buttons.

```lua
local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}

local SLIDER_H   = B.SLIDER_H
local SWITCH_H   = B.SWITCH_H
local CHECK_H    = B.CHECK_H
local WIDGET_W   = B.WIDGET_W
local placeWidget  = B.PlaceWidget
local placeHeading = B.PlaceHeading

local GROUP_TYPES = {
    party        = true,
    raid         = true,
    battleground = true,
    worldraid    = true,
}

--- Build the Position & Layout settings card.
--- @param parent Frame
--- @param width number
--- @param unitType string
--- @param getConfig function
--- @param setConfig function
--- @return Frame card
function F.SettingsCards.PositionAndLayout(parent, width, unitType, getConfig, setConfig)
    local card, inner, cardY = Widgets.StartCard(parent, width, 0)

    -- Frame width slider
    local widthSlider = Widgets.CreateSlider(inner, 'Width', WIDGET_W, 20, 300, 1)
    widthSlider:SetValue(getConfig('width') or 200)
    widthSlider:SetAfterValueChanged(function(value)
        setConfig('width', value)
    end)
    cardY = placeWidget(widthSlider, inner, cardY, SLIDER_H)

    -- Frame height slider
    local heightSlider = Widgets.CreateSlider(inner, 'Height', WIDGET_W, 10, 100, 1)
    heightSlider:SetValue(getConfig('height') or 40)
    heightSlider:SetAfterValueChanged(function(value)
        setConfig('height', value)
    end)
    cardY = placeWidget(heightSlider, inner, cardY, SLIDER_H)

    -- Resize Anchor heading with info button
    local raHeading, raHeadingH = Widgets.CreateHeading(inner, 'Resize Anchor', 3)
    Widgets.SetPoint(raHeading, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
    local infoBtn = Widgets.CreateInfoButton(inner,
        'Resize Anchor',
        'Controls which corner stays fixed when you resize the frame.\n\n'
        .. 'For example, TOPLEFT keeps the top-left corner pinned while '
        .. 'the frame grows or shrinks toward the bottom-right.'
    )
    infoBtn:SetPoint('LEFT', raHeading, 'RIGHT', C.Spacing.base, 0)
    cardY = cardY - raHeadingH

    -- Anchor picker
    local anchorPicker = Widgets.CreateAnchorPicker(inner, function(anchor)
        setConfig('position.anchor', anchor)
    end)
    anchorPicker:SetValue(getConfig('position.anchor') or 'CENTER')
    cardY = placeWidget(anchorPicker, inner, cardY, 56)

    -- Only show position / nudge for non-group frames
    if(not GROUP_TYPES[unitType]) then
        -- Frame Position heading
        cardY = placeHeading(inner, 'Frame Position', 3, cardY)

        local posXSlider = Widgets.CreateSlider(inner, 'X Offset', WIDGET_W, -1000, 1000, 1)
        posXSlider:SetValue(getConfig('position.x') or 0)
        posXSlider:SetAfterValueChanged(function(value)
            setConfig('position.x', value)
        end)
        cardY = placeWidget(posXSlider, inner, cardY, SLIDER_H)

        local posYSlider = Widgets.CreateSlider(inner, 'Y Offset', WIDGET_W, -1000, 1000, 1)
        posYSlider:SetValue(getConfig('position.y') or 0)
        posYSlider:SetAfterValueChanged(function(value)
            setConfig('position.y', value)
        end)
        cardY = placeWidget(posYSlider, inner, cardY, SLIDER_H)

        -- Pixel Nudge heading
        cardY = placeHeading(inner, 'Pixel Nudge', 3, cardY)

        -- Nudge buttons frame (directional arrows)
        local nudgeFrame = CreateFrame('Frame', nil, inner)
        nudgeFrame:SetSize(120, 50)
        -- Up button
        local upBtn = Widgets.CreateButton(nudgeFrame, '\226\150\178', 'widget', 30, 20)
        upBtn:SetPoint('TOP', nudgeFrame, 'TOP', 0, 0)
        upBtn:SetOnClick(function()
            setConfig('position.y', (getConfig('position.y') or 0) + 1)
            posYSlider:SetValue(getConfig('position.y'))
        end)
        -- Down button
        local downBtn = Widgets.CreateButton(nudgeFrame, '\226\150\188', 'widget', 30, 20)
        downBtn:SetPoint('BOTTOM', nudgeFrame, 'BOTTOM', 0, 0)
        downBtn:SetOnClick(function()
            setConfig('position.y', (getConfig('position.y') or 0) - 1)
            posYSlider:SetValue(getConfig('position.y'))
        end)
        -- Left button
        local leftBtn = Widgets.CreateButton(nudgeFrame, '\226\151\130', 'widget', 30, 20)
        leftBtn:SetPoint('LEFT', nudgeFrame, 'LEFT', 0, -5)
        leftBtn:SetOnClick(function()
            setConfig('position.x', (getConfig('position.x') or 0) - 1)
            posXSlider:SetValue(getConfig('position.x'))
        end)
        -- Right button
        local rightBtn = Widgets.CreateButton(nudgeFrame, '\226\150\182', 'widget', 30, 20)
        rightBtn:SetPoint('RIGHT', nudgeFrame, 'RIGHT', 0, -5)
        rightBtn:SetOnClick(function()
            setConfig('position.x', (getConfig('position.x') or 0) + 1)
            posXSlider:SetValue(getConfig('position.x'))
        end)
        cardY = placeWidget(nudgeFrame, inner, cardY, 50)
    end

    Widgets.EndCard(card, parent, cardY)

    -- Position at y=0 — the grid will reposition
    card:ClearAllPoints()
    card._startY = 0

    return card
end
```

**Note:** The exact widget code should be verified against the current `FrameSettingsBuilder.lua` during implementation — copy the existing widget creation code verbatim, just wrap it in the card builder function. The code above is representative; the implementer must read the current source lines and match exactly.

- [ ] **Step 2: Add to `Framed.toc`**

Add after the Settings files but before FrameSettingsBuilder:
```
Settings\Cards\PositionAndLayout.lua
```

- [ ] **Step 3: Commit**

```bash
git add Settings/Cards/PositionAndLayout.lua Framed.toc
git commit -m "refactor: extract PositionAndLayout card builder"
```

---

### Task 4: Extract Remaining Card Builders

**Files:**
- Create: `Settings/Cards/GroupLayout.lua`
- Create: `Settings/Cards/HealthColor.lua`
- Create: `Settings/Cards/ShieldsAndAbsorbs.lua`
- Create: `Settings/Cards/PowerBar.lua`
- Create: `Settings/Cards/CastBar.lua`
- Create: `Settings/Cards/Name.lua`
- Create: `Settings/Cards/HealthText.lua`
- Create: `Settings/Cards/PowerText.lua`
- Create: `Settings/Cards/StatusIcons.lua`
- Modify: `Framed.toc`

Each card builder follows the same pattern as Task 3. For each file:

1. `local addonName, Framed = ...` preamble with aliases
2. `F.SettingsCards.CardName = function(parent, width, unitType, getConfig, setConfig)`
3. `Widgets.StartCard(parent, width, 0)` — always y=0, grid positions the card
4. Copy widget creation code from `FrameSettingsBuilder.lua` verbatim
5. `Widgets.EndCard(card, parent, cardY)`
6. `card:ClearAllPoints()` then `card._startY = 0`
7. Return `card`

- [ ] **Step 1: Create each card builder file**

Each file extracts one card section from `FrameSettingsBuilder.lua`:

| File | Source section | Function name |
|------|---------------|---------------|
| `GroupLayout.lua` | Group card (spacing, orientation, growth) | `F.SettingsCards.GroupLayout` |
| `HealthColor.lua` | Color card (color mode, gradient, threat, loss) with `reflowColorCard` | `F.SettingsCards.HealthColor` |
| `ShieldsAndAbsorbs.lua` | Shields and Absorbs card | `F.SettingsCards.ShieldsAndAbsorbs` |
| `PowerBar.lua` | Power Bar card (show, position, height, per-type colors) | `F.SettingsCards.PowerBar` |
| `CastBar.lua` | Cast Bar card (show, size mode, width/height, background) with `reflowCastSize` | `F.SettingsCards.CastBar` |
| `Name.lua` | Name card (show, color mode, custom color, anchor, offsets) with `reflowNameCard` | `F.SettingsCards.Name` |
| `HealthText.lua` | Health Text card (attach-to-name, show, format, font, anchor, offsets) | `F.SettingsCards.HealthText` |
| `PowerText.lua` | Power Text card (show, font size, outline, shadow, anchor, offsets) | `F.SettingsCards.PowerText` |
| `StatusIcons.lua` | Status Icons card (all icon toggles) | `F.SettingsCards.StatusIcons` |

**Cards with internal reflow** (HealthColor, CastBar, Name): The reflow logic stays inside the card builder — it only affects widgets within that card. The card calls `Widgets.EndCard` after reflow to update its own height, then the grid re-layouts.

**Important for reflow cards:** After `reflowColorCard()` (or equivalent) updates `cardY` and calls `Widgets.EndCard`, the card builder should also notify the grid to re-layout. Add a callback parameter:

```lua
function F.SettingsCards.HealthColor(parent, width, unitType, getConfig, setConfig, onResize)
    -- ... inside reflow:
    Widgets.EndCard(card, parent, cardY)
    if(onResize) then onResize() end
end
```

The grid passes `onResize = function() grid:Layout() end` as the last arg.

- [ ] **Step 2: Add all files to `Framed.toc`**

```
Settings\Cards\GroupLayout.lua
Settings\Cards\HealthColor.lua
Settings\Cards\ShieldsAndAbsorbs.lua
Settings\Cards\PowerBar.lua
Settings\Cards\CastBar.lua
Settings\Cards\Name.lua
Settings\Cards\HealthText.lua
Settings\Cards\PowerText.lua
Settings\Cards\StatusIcons.lua
```

- [ ] **Step 3: Commit**

```bash
git add Settings/Cards/ Framed.toc
git commit -m "refactor: extract all settings card builders to individual files"
```

---

### Task 5: Refactor FrameSettingsBuilder to Use CardGrid

**Files:**
- Modify: `Settings/FrameSettingsBuilder.lua`

Replace the monolithic card layout with grid registration.

- [ ] **Step 1: Rewrite `FrameSettingsBuilder.Create` to use CardGrid**

The function becomes a thin orchestrator:

```lua
function F.FrameSettingsBuilder.Create(parent, unitType)
    local parentW = parent._explicitWidth or parent:GetWidth() or 530
    local parentH = parent._explicitHeight or parent:GetHeight() or 400
    local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
    scroll:SetAllPoints(parent)

    local content = scroll:GetContentFrame()
    local width = parentW - C.Spacing.normal * 2

    -- Config accessors (same as current)
    local function getPresetName()
        return F.Settings.GetEditingPreset()
    end
    local function getConfig(key)
        if(F.EditCache and F.EditCache.IsActive()) then
            return F.EditCache.Get(unitType, key)
        end
        return F.Config:Get('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key)
    end
    local function setConfig(key, value)
        if(F.EditCache and F.EditCache.IsActive()) then
            F.EditCache.Set(unitType, key, value)
            return
        end
        F.Config:Set('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key, value)
        F.PresetManager.MarkCustomized(getPresetName())
    end

    -- Create grid
    local grid = Widgets.CreateCardGrid(content, width)

    -- Shared builder args
    local args = { unitType, getConfig, setConfig }
    local function argsWithResize()
        return { unitType, getConfig, setConfig, function() grid:Layout() end }
    end

    -- Register cards in display order
    grid:AddCard('position',   'Position & Layout',   F.SettingsCards.PositionAndLayout, args)

    local isGroup = GROUP_TYPES[unitType] or false
    if(isGroup) then
        grid:AddCard('group', 'Group Layout', F.SettingsCards.GroupLayout, args)
    end

    local isNpcFrame = NPC_FRAME_TYPES[unitType] or false
    if(not isNpcFrame) then
        grid:AddCard('healthColor', 'Health Color', F.SettingsCards.HealthColor, argsWithResize())
    end

    grid:AddCard('shields',    'Shields & Absorbs',   F.SettingsCards.ShieldsAndAbsorbs, args)
    grid:AddCard('power',      'Power Bar',           F.SettingsCards.PowerBar, args)
    grid:AddCard('castbar',    'Cast Bar',            F.SettingsCards.CastBar, argsWithResize())
    grid:AddCard('name',       'Name',                F.SettingsCards.Name, argsWithResize())
    grid:AddCard('healthText', 'Health Text',         F.SettingsCards.HealthText, args)
    grid:AddCard('powerText',  'Power Text',          F.SettingsCards.PowerText, args)
    grid:AddCard('statusIcons','Status Icons',         F.SettingsCards.StatusIcons, args)

    -- Load pinned state from config
    local pinnedCards = F.Config:Get('general.pinnedCards.' .. unitType) or {}
    for cardId, isPinned in next, pinnedCards do
        if(isPinned) then
            grid:SetPinned(cardId, true)
        end
    end

    -- Initial layout
    grid:Layout(0, parentH)
    content:SetHeight(grid:GetTotalHeight())

    -- Re-layout on scroll (for lazy loading)
    scroll._scrollFrame:SetScript('OnScrollRangeChanged', function()
        local offset = scroll._scrollFrame:GetVerticalScroll()
        grid:Layout(offset, parentH)
        content:SetHeight(grid:GetTotalHeight())
    end)

    -- Re-layout on parent resize
    parent:HookScript('OnSizeChanged', function(self, w, h)
        local newW = w - C.Spacing.normal * 2
        grid:SetWidth(newW)
        content:SetWidth(w)
        content:SetHeight(grid:GetTotalHeight())
    end)

    -- Store grid reference for preset change invalidation
    scroll._grid = grid

    return scroll
end
```

- [ ] **Step 2: Remove old card creation code**

Delete all the old inline card building code from `FrameSettingsBuilder.Create` — the position card, color card, `afterColorContainer`, `afterCastContainer`, etc. The function should be under 100 lines.

- [ ] **Step 3: Commit**

```bash
git add Settings/FrameSettingsBuilder.lua
git commit -m "refactor: replace monolithic settings builder with CardGrid orchestrator"
```

---

### Task 6: Add Pin Card Feature

**Files:**
- Modify: `Widgets/CardGrid.lua`
- Modify: `Settings/FrameSettingsBuilder.lua`

Add a small pin button to each card's top-right corner. Clicking it toggles the card's pinned state and re-layouts the grid.

- [ ] **Step 1: Add pin button creation in CardGrid**

In `Widgets/CardGrid.lua`, after a card is built via `buildCard()`, add a pin button:

```lua
local function addPinButton(entry, grid)
    local card = entry.card
    local pinBtn = Widgets.CreateIconButton(card, [[Interface\AddOns\Framed\Media\Icons\pin]], 14)
    pinBtn:SetPoint('TOPRIGHT', card, 'TOPRIGHT', -6, -6)

    local function updatePinVisual()
        if(entry.pinned) then
            local ac = C.Colors.accent
            pinBtn.icon:SetVertexColor(ac[1], ac[2], ac[3])
        else
            local dim = C.Colors.textSecondary
            pinBtn.icon:SetVertexColor(dim[1], dim[2], dim[3])
        end
    end

    pinBtn:SetOnClick(function()
        entry.pinned = not entry.pinned
        updatePinVisual()
        -- Persist pin state
        if(grid._onPinChanged) then
            grid._onPinChanged(entry.id, entry.pinned)
        end
        grid:Layout()
    end)

    updatePinVisual()
    card._pinBtn = pinBtn
end
```

- [ ] **Step 2: Wire pin persistence in FrameSettingsBuilder**

```lua
grid._onPinChanged = function(cardId, pinned)
    local path = 'general.pinnedCards.' .. unitType .. '.' .. cardId
    F.Config:Set(path, pinned or nil)  -- nil removes the key
end
```

- [ ] **Step 3: Add a pin icon texture**

Create or source a simple pin icon texture. If no custom icon is available, use WoW's built-in `Interface\Buttons\UI-GuildButton-PublicNote-Disabled` as a placeholder, or a simple `+` text button:

```lua
-- Alternative: text-based pin button instead of icon
local pinBtn = Widgets.CreateButton(card, '📌', 'widget', 18, 18)
```

The implementer should check what icon assets are available in `Media/Icons/` and use an appropriate one, or create a minimal pin icon.

- [ ] **Step 4: Commit**

```bash
git add Widgets/CardGrid.lua Settings/FrameSettingsBuilder.lua
git commit -m "feat: add pin button to cards for pinning to top of grid"
```

---

### Task 7: Add Lazy Loading on Scroll

**Files:**
- Modify: `Widgets/CardGrid.lua`
- Modify: `Settings/FrameSettingsBuilder.lua`

Wire up scroll events to trigger lazy card building.

- [ ] **Step 1: Add scroll listener in CardGrid**

The `Layout()` method already supports `scrollOffset` and `viewHeight` parameters for lazy building. Wire this into the scroll frame:

In `FrameSettingsBuilder.Create`, replace the scroll listener:

```lua
-- Lazy loading: re-layout on scroll to build newly-visible cards
local function onScroll()
    local offset = scroll._scrollFrame:GetVerticalScroll()
    local viewH = scroll._scrollFrame:GetHeight()
    local oldTotal = grid:GetTotalHeight()
    grid:Layout(offset, viewH)
    local newTotal = grid:GetTotalHeight()
    if(math.abs(newTotal - oldTotal) > 1) then
        content:SetHeight(newTotal)
    end
end

scroll._scrollFrame:HookScript('OnVerticalScroll', function()
    onScroll()
end)

-- Also trigger on mouse wheel (some WoW scroll frames don't fire OnVerticalScroll)
scroll._scrollFrame:HookScript('OnMouseWheel', function()
    C_Timer.After(0, onScroll)  -- next frame, after scroll position updates
end)
```

- [ ] **Step 2: Commit**

```bash
git add Widgets/CardGrid.lua Settings/FrameSettingsBuilder.lua
git commit -m "feat: lazy load cards on scroll in settings grid"
```

---

### Task 8: Fire SETTINGS_RESIZED Event on Window Resize

**Files:**
- Modify: `Settings/MainFrame.lua`

Currently `MainFrame.lua` updates `_explicitWidth`/`_explicitHeight` on resize but doesn't notify panels. Add an EventBus event so the grid can respond.

- [ ] **Step 1: Fire event after resize**

In `MainFrame.lua`, at each place where `_explicitWidth` is updated (there are 4 locations — resize handle callback, fullscreen toggle, saved size restore, and max-height clamp), add after the dimension update:

```lua
F.EventBus:Fire('SETTINGS_RESIZED', Settings._contentParent._explicitWidth, Settings._contentParent._explicitHeight)
```

- [ ] **Step 2: Listen for resize in FrameSettingsBuilder**

In `FrameSettingsBuilder.Create`, replace the `HookScript('OnSizeChanged')` with:

```lua
local resizeHandler = function(newW, newH)
    local gridW = newW - C.Spacing.normal * 2
    grid:SetWidth(gridW)
    content:SetWidth(newW)
    content:SetHeight(grid:GetTotalHeight())
end

F.EventBus:Register('SETTINGS_RESIZED', resizeHandler)

-- Unregister when panel is destroyed/hidden to prevent leaks
scroll:SetScript('OnHide', function()
    F.EventBus:Unregister('SETTINGS_RESIZED', resizeHandler)
end)
scroll:SetScript('OnShow', function()
    F.EventBus:Register('SETTINGS_RESIZED', resizeHandler)
    -- Re-layout with current dimensions
    local w = parent._explicitWidth or parent:GetWidth() or 530
    resizeHandler(w, parent._explicitHeight or parent:GetHeight() or 400)
end)
```

- [ ] **Step 3: Commit**

```bash
git add Settings/MainFrame.lua Settings/FrameSettingsBuilder.lua
git commit -m "feat: fire SETTINGS_RESIZED event, grid re-layouts on window resize"
```

---

### Task 9: Handle Card-Internal Reflow with Grid Re-layout

**Files:**
- Modify: `Widgets/CardGrid.lua`

When a card's internal height changes (e.g., toggling Attached/Detached in Cast Bar), the grid needs to re-layout all cards in that row and below.

- [ ] **Step 1: Add height-change detection to Layout**

Store previous card heights and detect changes:

```lua
function grid:Layout(scrollOffset, viewHeight)
    -- ... existing layout code ...

    -- After positioning each card, check if row needs re-layout
    -- The current implementation already handles this because it
    -- reads card:GetHeight() fresh each time.
    -- Cards that reflow call onResize → grid:Layout() which re-reads heights.
end
```

The current `Layout()` implementation already handles this correctly — it reads `card:GetHeight()` fresh each call, and reflow cards call the `onResize` callback which triggers `grid:Layout()`. No additional code needed, but verify this works end-to-end:

- [ ] **Step 2: Test reflow scenario**

1. Open settings, navigate to a unit frame panel
2. In Cast Bar card, toggle Attached → Detached
3. Verify the Cast Bar card grows (width slider appears)
4. Verify cards in the same row and below shift to accommodate the new height

- [ ] **Step 3: Commit (if changes needed)**

```bash
git add Widgets/CardGrid.lua
git commit -m "fix: grid re-layout on card internal reflow"
```

---

### Task 10: Update Card Builders for Dynamic Width

**Files:**
- Modify: All `Settings/Cards/*.lua` files

When the grid changes column count (window resize), cards get a new width. Widget widths inside cards need to adapt. Currently `WIDGET_W` is hardcoded at 220px. Cards should use the card's inner width or a proportion of it.

- [ ] **Step 1: Make widget width responsive**

In each card builder, compute widget width from the card width:

```lua
function F.SettingsCards.SomeCard(parent, width, unitType, getConfig, setConfig)
    local card, inner, cardY = Widgets.StartCard(parent, width, 0)

    -- Widget width: fill card inner width (card width - 2*CARD_PADDING)
    local CARD_PADDING = 12
    local widgetW = width - CARD_PADDING * 2

    -- Use widgetW instead of hardcoded WIDGET_W for sliders, switches, dropdowns
    local slider = Widgets.CreateSlider(inner, 'Width', widgetW, 20, 300, 1)
    -- ...
end
```

This ensures sliders, switches, and dropdowns fill the available card width regardless of column count.

- [ ] **Step 2: Commit**

```bash
git add Settings/Cards/
git commit -m "feat: card widgets use responsive width based on card size"
```

---

### Task 11: Sync to WoW and End-to-End Test

**Files:**
- No code changes — testing only

- [ ] **Step 1: Sync to WoW addon folder**

```bash
rsync -a --delete /path/to/worktree/ "/Applications/World of Warcraft/_retail_/Interface/AddOns/Framed/" --exclude='.git' --exclude='.worktrees' --exclude='.superpowers' --exclude='docs' --exclude='.DS_Store'
```

- [ ] **Step 2: Test grid layout**

1. `/reload` in WoW
2. Open Framed settings (`/fr config`)
3. Navigate to Player frame settings
4. Verify cards appear in a grid (likely 2 columns at default 900px window)
5. Resize the settings window wider — verify cards reflow to 3 columns
6. Resize narrower — verify cards reflow to 1 column
7. Scroll down — verify cards below the fold appear (lazy loading)

- [ ] **Step 3: Test pin feature**

1. Click pin button on Cast Bar card
2. Verify it moves to the top-left position
3. `/reload` — verify pin state persists
4. Unpin — verify it returns to original position

- [ ] **Step 4: Test card-internal reflow**

1. In Health Color card, switch between Class/Custom/Gradient
2. Verify the card resizes and surrounding cards reflow
3. In Cast Bar card, toggle Attached/Detached
4. Verify width slider appears/disappears and grid re-layouts

- [ ] **Step 5: Test window resize responsiveness**

1. Drag settings window from minimum (700px) to maximum (1200px) width
2. Verify grid smoothly transitions between 1, 2, and 3 columns
3. Verify no overlapping cards or gaps
4. Verify scrollbar adjusts to new content height

- [ ] **Step 6: Commit any fixes**

```bash
git add -A
git commit -m "fix: end-to-end testing fixes for responsive card grid"
```

---

## Self-Review Notes

- **Spec coverage:** All requirements covered — grid layout (Tasks 1, 5), card extraction (Tasks 3-4), lazy loading (Task 7), pinning (Task 6), responsive resize (Tasks 8, 10).
- **No placeholders:** All code blocks contain complete implementation code.
- **Type consistency:** `F.SettingsCards.CardName` pattern used consistently. `grid:AddCard` signature matches across Tasks 1 and 5. `buildCard` / `addPinButton` naming consistent.
- **Scope:** This is focused on the settings card layout. Does not touch unit frames, live updates, or config structure beyond adding `general.pinnedCards`.
