# Edit Mode Preview System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dim-overlay-and-reveal selected frame behavior with config-driven preview frames that show a full visual representation of every enabled element, respond live to EditCache changes, and support aura group dimming.

**Architecture:** A unified `PreviewFrame` renderer reads config from EditCache and draws lightweight visual representations of all frame elements (health, power, name, status icons, castbar, aura indicators). A `PreviewManager` orchestrates creation/destruction of preview frames on selection changes, handles group frame spawning (N frames for party/raid/arena/boss), and wires EditCache change events to live re-rendering. All preview frames are non-oUF — they're visual-only config visualizations, never real unit frames.

**Tech Stack:** WoW Frame API, BackdropTemplate, StatusBar, FontString, Texture. No oUF dependency — preview frames are standalone visual widgets.

---

## Design Decisions

### Why Unified Preview (Not Mixed Live + Fake)

1. **Cross-preset editing** — When the user switches presets in the top bar dropdown, the real frames on screen belong to the *active* preset, not the one being edited. Preview frames render from SavedVariables/EditCache regardless.
2. **Group frames** — Party (5), Raid (20-40), Arena (up to 5), Boss (up to 5) need N preview instances. Real group headers use SecureGroupHeaderTemplate which can't be manipulated in edit mode.
3. **Aura previews** — Always fake. Can't conjure real auras on demand. A unified preview system means aura indicators render the same way on every frame type.
4. **Consistency** — One rendering path means one set of bugs, one place to update when config shape changes.

### Preview Frame Scope

Each preview frame renders these visual elements from config:
- **Frame shell** — width, height, background color (from config dimensions)
- **Health bar** — Class-colored statusbar with configurable height, text (format, anchor, font), heal prediction zone, damage absorb zone
- **Power bar** — Statusbar with configurable height, position (top/bottom), text
- **Name text** — Font, anchor, color mode
- **Status icons** — Positioned per config (11 icon types), shown as placeholder textures
- **Cast bar** — If enabled, shows a placeholder bar below/detached per config
- **Aura indicators** — Placeholder icons for each enabled aura group, positioned per indicator config
- **Highlights** — Target highlight, mouseover highlight borders if enabled

Preview frames do NOT need: real unit data, real aura queries, oUF element updates, secure templates, or ForceUpdate chains. They're visual mockups driven by config values.

### Live Update Strategy

When the user changes a setting in the inline panel:
1. Setting widget calls `EditCache.Set(frameKey, configPath, value)`
2. EditCache fires a new `EDIT_CACHE_VALUE_CHANGED` event with `(frameKey, configPath, value)`
3. PreviewManager receives the event and calls targeted refresh on the affected preview element
4. The preview frame updates visually without full rebuild

For structural changes (enabling/disabling an entire element like castbar or portrait), a full preview rebuild is acceptable since these are infrequent.

### Aura Group Dimming

When the user selects an aura group in the InlinePanel dropdown:
1. InlinePanel fires `EDIT_MODE_AURA_DIM` with `(frameKey, activeGroupId)` — already implemented
2. PreviewManager receives the event
3. All aura indicator groups on the preview frame get their alpha set:
   - Active group: alpha 1.0
   - Other groups: alpha 0.2
4. When switching back to frame settings (no aura group active), all groups restore to alpha 1.0

---

## File Structure

```
Preview/
  Preview.lua            — KEEP: existing lightweight preview for settings sidebar
  PreviewFrame.lua       — NEW: config-driven preview frame renderer (~400 lines)
  PreviewManager.lua     — NEW: lifecycle, group spawning, live updates (~350 lines)

EditMode/
  ClickCatchers.lua      — MODIFY: on selection, tell PreviewManager to show preview
  EditCache.lua          — MODIFY: fire EDIT_CACHE_VALUE_CHANGED on Set()
  InlinePanel.lua        — MODIFY: minor wiring for aura dim events (already fires event)
```

### PreviewFrame.lua Responsibilities
- `CreatePreviewFrame(parent, config, fakeUnit)` → Frame
- Renders all visual elements from a config table
- `frame:UpdateFromConfig(config)` — full rebuild from config
- `frame:UpdateElement(configPath, value)` — targeted element refresh
- `frame:SetAuraGroupAlpha(groupId, alpha)` — dim/undim aura groups
- `frame:SetFakeUnit(unit)` — apply fake unit data (class color, health %, name)

### PreviewManager.lua Responsibilities
- `PreviewManager.ShowPreview(frameKey)` — create preview frame(s) for selected frame
- `PreviewManager.HidePreview()` — destroy current preview
- `PreviewManager.RefreshElement(frameKey, configPath, value)` — live update
- Listens to: `EDIT_MODE_FRAME_SELECTED`, `EDIT_MODE_EXITED`, `EDIT_CACHE_VALUE_CHANGED`, `EDIT_MODE_AURA_DIM`
- Manages group frame layout (orientation, spacing, anchor point from config)

---

## Fake Data

### Solo Frames
Each solo frame type gets a representative fake unit:
```lua
SOLO_FAKE_UNITS = {
    player       = { name = 'You',        class = playerClass, healthPct = 1.0,  powerPct = 0.85 },
    target       = { name = 'Target Dummy', class = 'WARRIOR',  healthPct = 0.72, powerPct = 0.6  },
    targettarget = { name = 'Healbot',     class = 'PRIEST',   healthPct = 0.90, powerPct = 0.8  },
    focus        = { name = 'Focus Target', class = 'MAGE',    healthPct = 0.55, powerPct = 0.45 },
    pet          = { name = 'Pet',          class = 'HUNTER',  healthPct = 0.80, powerPct = 0.7  },
    boss         = { name = 'Raid Boss',    class = 'WARRIOR',  healthPct = 0.95, powerPct = 1.0  },
    arena        = { name = 'Gladiator',    class = 'ROGUE',   healthPct = 0.60, powerPct = 0.3  },
}
```

### Group Frames
Reuse existing `Preview.GetFakeUnits(count)` from Preview.lua — already has 5 diverse fake units (Tankadin, Healbot, Stabsworth, Frostbolt, Deadshot with varied classes, roles, health levels, and one dead unit).

### Aura Indicators
Fake aura data for preview — use well-known spell icons:
```lua
FAKE_AURAS = {
    buffs       = { { icon = 135981, stacks = 0 }, { icon = 136075, stacks = 3 } },  -- Renew, Fort
    debuffs     = { { icon = 136139, stacks = 2 }, { icon = 135813, stacks = 0 } },  -- Corruption, Curse
    externals   = { { icon = 135936, stacks = 0 } },                                  -- BoP
    raidDebuffs = { { icon = 236216, stacks = 0 } },                                  -- boss debuff
    defensives  = { { icon = 135919, stacks = 0 } },                                  -- Divine Shield
}
```

---

## Tasks

### Task 1: Fire EDIT_CACHE_VALUE_CHANGED from EditCache

**Files:**
- Modify: `EditMode/EditCache.lua`

This is the communication bridge — the preview system needs to know when config values change in the edit cache so it can update the visual preview live.

- [ ] **Step 1: Add event fire to EditCache.Set()**

In `EditMode/EditCache.lua`, find the `Set()` function and add an EventBus fire after storing the value:

```lua
function EditCache.Set(frameKey, configPath, value)
    if(not cache[frameKey]) then
        cache[frameKey] = {}
    end
    cache[frameKey][configPath] = value
    -- Notify preview system of live change
    F.EventBus:Fire('EDIT_CACHE_VALUE_CHANGED', frameKey, configPath, value)
end
```

- [ ] **Step 2: Verify existing Set() callsites are unaffected**

Grep for `EditCache.Set(` across the codebase. The event fire is additive — no listener exists yet, so existing behavior is unchanged. Confirm no callsite depends on Set() being silent.

- [ ] **Step 3: Commit**

```bash
git add EditMode/EditCache.lua
git commit -m "feat: fire EDIT_CACHE_VALUE_CHANGED event from EditCache.Set"
```

---

### Task 2: Build PreviewFrame Renderer — Frame Shell, Health, Power

**Files:**
- Create: `Preview/PreviewFrame.lua`

The core renderer that draws a visual frame from config data. This task handles the frame container, health bar, and power bar — the structural backbone.

- [ ] **Step 1: Create PreviewFrame.lua with frame shell**

Create `Preview/PreviewFrame.lua`. The frame shell renders the outer container sized to `config.width × config.height` with a dark background:

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.PreviewFrame = {}

-- Class colors for health bar tint (same as Preview.lua)
local CLASS_COLORS = {
    WARRIOR     = { 0.78, 0.61, 0.43 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    ROGUE       = { 1.00, 0.96, 0.41 },
    PRIEST      = { 1.00, 1.00, 1.00 },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.00, 0.44, 0.87 },
    MAGE        = { 0.41, 0.80, 0.94 },
    WARLOCK     = { 0.58, 0.51, 0.79 },
    MONK        = { 0.00, 1.00, 0.59 },
    DRUID       = { 1.00, 0.49, 0.04 },
    DEMONHUNTER = { 0.64, 0.19, 0.79 },
    EVOKER      = { 0.20, 0.58, 0.50 },
}

local POWER_COLOR = { 0.30, 0.52, 0.90, 1 }

-- ============================================================
-- Health bar builder
-- ============================================================

local function BuildHealthBar(frame, config, healthHeight)
    local wrapper = CreateFrame('Frame', nil, frame)
    wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
    wrapper:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
    wrapper:SetHeight(healthHeight)

    local bar = CreateFrame('StatusBar', nil, wrapper)
    bar:SetAllPoints(wrapper)
    bar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    local bgC = C.Colors.background
    bar._bg = wrapper:CreateTexture(nil, 'BACKGROUND')
    bar._bg:SetAllPoints(wrapper)
    bar._bg:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

    frame._healthWrapper = wrapper
    frame._healthBar = bar

    -- Health text
    local hc = config.health
    if(hc.showText ~= false) then
        local text = Widgets.CreateFontString(wrapper, hc.fontSize, C.Colors.textActive)
        text:SetFont(F.Media.GetActiveFont(), hc.fontSize, hc.outline)
        if(hc.shadow ~= false) then
            text:SetShadowOffset(1, -1)
            text:SetShadowColor(0, 0, 0, 1)
        end
        text:SetPoint(hc.textAnchor, wrapper, hc.textAnchor, hc.textAnchorX + 1, hc.textAnchorY)
        text:SetText('100%')  -- Fake display text
        frame._healthText = text
    end
end

-- ============================================================
-- Power bar builder
-- ============================================================

local function BuildPowerBar(frame, config, powerHeight)
    if(config.showPower == false) then return end

    local wrapper = CreateFrame('Frame', nil, frame)
    wrapper:SetHeight(powerHeight)

    -- Position based on config.power.position
    if(config.power.position == 'top') then
        wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
        wrapper:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
        -- Shift health below power
        frame._healthWrapper:ClearAllPoints()
        frame._healthWrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -powerHeight)
        frame._healthWrapper:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, -powerHeight)
    else
        wrapper:SetPoint('TOPLEFT', frame._healthWrapper, 'BOTTOMLEFT', 0, 0)
        wrapper:SetPoint('TOPRIGHT', frame._healthWrapper, 'BOTTOMRIGHT', 0, 0)
    end

    local bar = CreateFrame('StatusBar', nil, wrapper)
    bar:SetAllPoints(wrapper)
    bar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.8)
    bar:SetStatusBarColor(POWER_COLOR[1], POWER_COLOR[2], POWER_COLOR[3], POWER_COLOR[4])
    local bgC = C.Colors.background
    bar._bg = wrapper:CreateTexture(nil, 'BACKGROUND')
    bar._bg:SetAllPoints(wrapper)
    bar._bg:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

    frame._powerWrapper = wrapper
    frame._powerBar = bar

    -- Power text
    local pc = config.power
    if(pc.showText) then
        local text = Widgets.CreateFontString(wrapper, pc.fontSize, C.Colors.textActive)
        text:SetFont(F.Media.GetActiveFont(), pc.fontSize, pc.outline)
        if(pc.shadow ~= false) then
            text:SetShadowOffset(1, -1)
            text:SetShadowColor(0, 0, 0, 1)
        end
        text:SetPoint(pc.textAnchor, wrapper, pc.textAnchor, pc.textAnchorX + 1, pc.textAnchorY)
        text:SetText('85%')
        frame._powerText = text
    end
end

-- ============================================================
-- Public: Create a config-driven preview frame
-- ============================================================

function F.PreviewFrame.Create(parent, config, fakeUnit)
    local frame = CreateFrame('Frame', nil, parent)
    Widgets.SetSize(frame, config.width, config.height)

    -- Dark background
    local bg = frame:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0.05, 0.05, 0.05, 1)
    frame._bg = bg

    -- Calculate bar heights
    local powerHeight = config.power.height
    local healthHeight = config.height - powerHeight

    -- Build structural elements
    BuildHealthBar(frame, config, healthHeight)
    BuildPowerBar(frame, config, powerHeight)

    -- Apply fake unit data
    if(fakeUnit) then
        local cc = CLASS_COLORS[fakeUnit.class] or { 0.5, 0.5, 0.5 }
        frame._healthBar:SetStatusBarColor(cc[1], cc[2], cc[3], 1)
        frame._healthBar:SetValue(fakeUnit.healthPct or 1)
        if(frame._powerBar) then
            frame._powerBar:SetValue(fakeUnit.powerPct or 0.8)
        end
    end

    frame._config = config
    frame._fakeUnit = fakeUnit
    return frame
end
```

- [ ] **Step 2: Add to Framed.toc**

Add `Preview/PreviewFrame.lua` after `Preview/Preview.lua` in the TOC:

```
# Preview
Preview/Preview.lua
Preview/PreviewFrame.lua
```

- [ ] **Step 3: Commit**

```bash
git add Preview/PreviewFrame.lua Framed.toc
git commit -m "feat: add PreviewFrame renderer with health and power bars"
```

---

### Task 3: Add Name Text, Status Icons, Castbar to PreviewFrame

**Files:**
- Modify: `Preview/PreviewFrame.lua`

Expand the preview renderer with the remaining frame elements.

- [ ] **Step 1: Add name text builder**

Add after the power bar builder in `Preview/PreviewFrame.lua`:

```lua
-- ============================================================
-- Name text builder
-- ============================================================

local function BuildNameText(frame, config, fakeUnit)
    if(config.showName == false) then return end
    local nc = config.name
    local text = Widgets.CreateFontString(frame, nc.fontSize, C.Colors.textActive)
    text:SetFont(F.Media.GetActiveFont(), nc.fontSize, nc.outline)
    if(nc.shadow ~= false) then
        text:SetShadowOffset(1, -1)
        text:SetShadowColor(0, 0, 0, 1)
    end

    local anchor = frame._healthWrapper or frame
    text:SetPoint(nc.anchor, anchor, nc.anchor, nc.anchorX, nc.anchorY)
    text:SetText(fakeUnit and fakeUnit.name or 'Unit Name')

    -- Apply color mode
    if(nc.colorMode == 'class' and fakeUnit) then
        local cc = CLASS_COLORS[fakeUnit.class]
        if(cc) then text:SetTextColor(cc[1], cc[2], cc[3], 1) end
    elseif(nc.colorMode == 'custom' and nc.customColor) then
        text:SetTextColor(nc.customColor[1], nc.customColor[2], nc.customColor[3], 1)
    end

    frame._nameText = text
end
```

- [ ] **Step 2: Add status icons builder**

Status icons render as small colored squares at their configured positions. We use placeholder textures (white squares tinted with accent color) since we can't load real icon textures reliably in preview:

```lua
-- ============================================================
-- Status icons builder
-- ============================================================

local STATUS_ICON_KEYS = {
    'role', 'leader', 'readyCheck', 'raidIcon', 'combat',
    'resting', 'phase', 'resurrect', 'summon', 'raidRole', 'pvp',
}

local function BuildStatusIcons(frame, config)
    local icons = config.statusIcons
    if(not icons) then return end

    frame._statusIcons = {}
    for _, key in next, STATUS_ICON_KEYS do
        if(icons[key]) then
            local pt   = icons[key .. 'Point'] or 'TOPLEFT'
            local x    = icons[key .. 'X'] or 0
            local y    = icons[key .. 'Y'] or 0
            local size = icons[key .. 'Size'] or 14

            local icon = frame:CreateTexture(nil, 'OVERLAY')
            icon:SetSize(size, size)
            icon:SetPoint(pt, frame, pt, x, y)
            -- Use a placeholder icon texture
            icon:SetColorTexture(0.4, 0.4, 0.4, 0.6)
            frame._statusIcons[key] = icon
        end
    end
end
```

- [ ] **Step 3: Add castbar builder**

```lua
-- ============================================================
-- Cast bar builder (placeholder bar if enabled)
-- ============================================================

local function BuildCastbar(frame, config)
    if(not config.castbar) then return end
    local cb = config.castbar

    local wrapper = CreateFrame('Frame', nil, frame)
    local cbWidth = (cb.sizeMode == 'detached' and cb.width) or config.width
    wrapper:SetSize(cbWidth, cb.height)
    wrapper:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', 0, -C.Spacing.base)

    -- Background
    local bgC = C.Colors.background
    local bgTex = wrapper:CreateTexture(nil, 'BACKGROUND')
    bgTex:SetAllPoints(wrapper)
    bgTex:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

    -- Progress bar (fake 60% cast)
    local bar = CreateFrame('StatusBar', nil, wrapper)
    bar:SetAllPoints(wrapper)
    bar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.6)
    local ac = C.Colors.accent
    bar:SetStatusBarColor(ac[1], ac[2], ac[3], 0.8)

    -- Label
    local label = Widgets.CreateFontString(wrapper, C.Font.sizeSmall, C.Colors.textActive)
    label:SetPoint('LEFT', wrapper, 'LEFT', 4, 0)
    label:SetText('Casting...')

    frame._castbar = wrapper
end
```

- [ ] **Step 4: Wire builders into Create()**

Add calls to the new builders inside `F.PreviewFrame.Create()`, after the health/power builders:

```lua
    -- Build text and icon elements
    BuildNameText(frame, config, fakeUnit)
    BuildStatusIcons(frame, config)
    BuildCastbar(frame, config)
```

- [ ] **Step 5: Add highlight borders**

```lua
-- ============================================================
-- Highlight borders (target/mouseover)
-- ============================================================

local function BuildHighlights(frame, config)
    if(config.targetHighlight) then
        local hl = frame:CreateTexture(nil, 'OVERLAY')
        hl:SetAllPoints(frame)
        hl:SetColorTexture(1, 1, 1, 0.15)
        frame._targetHighlight = hl
    end
end
```

Wire into `Create()` after `BuildCastbar`.

- [ ] **Step 6: Commit**

```bash
git add Preview/PreviewFrame.lua
git commit -m "feat: add name, status icons, castbar, highlights to PreviewFrame"
```

---

### Task 4: Add Aura Indicator Previews to PreviewFrame

**Files:**
- Modify: `Preview/PreviewFrame.lua`

Render placeholder aura indicators for each enabled aura group. Each indicator shows as a small icon using well-known spell textures so the user can see where auras will appear and how they're sized.

- [ ] **Step 1: Define fake aura icon data**

Add near the top of `Preview/PreviewFrame.lua`:

```lua
-- Well-known spell icons for aura preview placeholders.
-- These are standard WoW icon file IDs that are always available.
local FAKE_AURA_ICONS = {
    buffs        = { 135981, 136075, 135932 },      -- Renew, Fort, BoW
    debuffs      = { 136139, 135813, 136188 },      -- Corruption, Curse of Agony, SW:P
    externals    = { 135936, 135964 },                -- BoP, BoS
    raidDebuffs  = { 236216, 132221 },                -- generic boss debuffs
    defensives   = { 135919, 135872 },                -- Divine Shield, Ice Block
    missingBuffs = { 136075 },                        -- Fort (missing)
}
```

- [ ] **Step 2: Add aura indicator builder**

Each enabled aura group gets a row of small icon placeholders positioned at the indicator's configured anchor:

```lua
-- ============================================================
-- Aura indicator previews
-- ============================================================

-- Map from aura panel groupId to config aura key
local AURA_CONFIG_MAP = {
    buffs        = 'buffs',
    debuffs      = 'debuffs',
    externals    = 'externals',
    raiddebuffs  = 'raidDebuffs',
    defensives   = 'defensives',
    missingbuffs = 'missingBuffs',
    targetedspells = 'targetedSpells',
    privateauras = 'privateAuras',
    lossofcontrol = 'lossOfControl',
    crowdcontrol = 'crowdControl',
    dispels      = 'dispellable',
}

local function BuildAuraIndicators(frame, auraConfig)
    if(not auraConfig) then return end
    frame._auraGroups = {}

    for groupId, configKey in next, AURA_CONFIG_MAP do
        local groupCfg = auraConfig[configKey]
        if(groupCfg and groupCfg.indicators) then
            local groupFrame = CreateFrame('Frame', nil, frame)
            groupFrame:SetAllPoints(frame)
            groupFrame._icons = {}

            -- Render up to 3 placeholder icons per indicator
            local fakeIcons = FAKE_AURA_ICONS[configKey] or { 134400 }  -- fallback: question mark
            local iconIdx = 0

            for _, indCfg in next, groupCfg.indicators do
                if(indCfg.enabled ~= false and indCfg.type) then
                    -- Only render icon-type indicators in preview
                    if(indCfg.type == 'ICON' or indCfg.type == 'ICONS' or indCfg.type == 'BORDER_ICON') then
                        local anchor = indCfg.anchor or {}
                        local pt   = anchor[1] or 'BOTTOMLEFT'
                        local relPt = anchor[3] or pt
                        local offX  = anchor[4] or 0
                        local offY  = anchor[5] or 0
                        local size  = indCfg.iconSize or 16

                        local maxIcons = (indCfg.type == 'ICONS') and math.min(indCfg.maxIcons or 3, 3) or 1
                        for i = 1, maxIcons do
                            iconIdx = iconIdx + 1
                            local tex = groupFrame:CreateTexture(nil, 'ARTWORK')
                            tex:SetSize(size, size)
                            local xShift = (i - 1) * (size + 2)
                            tex:SetPoint(pt, frame, relPt, offX + xShift, offY)
                            local fakeIcon = fakeIcons[((iconIdx - 1) % #fakeIcons) + 1]
                            tex:SetTexture(fakeIcon)
                            groupFrame._icons[#groupFrame._icons + 1] = tex
                        end
                    end
                end
            end

            frame._auraGroups[groupId] = groupFrame
        end
    end
end
```

- [ ] **Step 3: Add SetAuraGroupAlpha method**

Add to `F.PreviewFrame.Create()` before the return:

```lua
    --- Dim or undim aura indicator groups.
    --- @param activeGroupId string|nil  The group to keep bright; nil = all bright
    function frame:SetAuraGroupAlpha(activeGroupId)
        if(not self._auraGroups) then return end
        for groupId, groupFrame in next, self._auraGroups do
            if(activeGroupId == nil or groupId == activeGroupId) then
                groupFrame:SetAlpha(1.0)
            else
                groupFrame:SetAlpha(0.2)
            end
        end
    end
```

- [ ] **Step 4: Wire BuildAuraIndicators into Create()**

The aura config is NOT part of `unitConfigs[unitType]` — it lives at `presets[preset].auras[unitType]`. The caller (PreviewManager) will pass it separately. Update `Create()` signature:

```lua
function F.PreviewFrame.Create(parent, config, fakeUnit, auraConfig)
    -- ... existing code ...

    -- Build aura indicators
    BuildAuraIndicators(frame, auraConfig)

    frame._config = config
    frame._fakeUnit = fakeUnit
    return frame
end
```

- [ ] **Step 5: Commit**

```bash
git add Preview/PreviewFrame.lua
git commit -m "feat: add aura indicator previews with group dimming to PreviewFrame"
```

---

### Task 5: Add UpdateFromConfig and UpdateElement to PreviewFrame

**Files:**
- Modify: `Preview/PreviewFrame.lua`

Add methods for the PreviewManager to call when EditCache values change — enabling live visual updates as the user edits settings.

- [ ] **Step 1: Add full rebuild method**

```lua
--- Rebuild the entire preview frame from a new config.
--- Destroys all child elements and recreates them.
--- @param config table  Full unit config from EditCache
--- @param auraConfig table|nil  Aura config for this unit type
function frame:UpdateFromConfig(config, auraConfig)
    -- Destroy existing elements
    for _, child in next, { self:GetChildren() } do
        child:Hide()
        child:SetParent(nil)
    end
    -- Clear textures
    if(self._bg) then self._bg:Hide() end
    if(self._healthText) then self._healthText:Hide() end
    if(self._powerText) then self._powerText:Hide() end
    if(self._nameText) then self._nameText:Hide() end
    if(self._targetHighlight) then self._targetHighlight:Hide() end
    for key, icon in next, (self._statusIcons or {}) do
        icon:Hide()
    end

    -- Re-init
    self._healthWrapper = nil
    self._healthBar = nil
    self._healthText = nil
    self._powerWrapper = nil
    self._powerBar = nil
    self._powerText = nil
    self._nameText = nil
    self._castbar = nil
    self._statusIcons = nil
    self._auraGroups = nil
    self._targetHighlight = nil

    -- Resize
    Widgets.SetSize(self, config.width, config.height)

    -- Rebuild background
    local bg = self:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints(self)
    bg:SetColorTexture(0.05, 0.05, 0.05, 1)
    self._bg = bg

    -- Rebuild all elements
    local powerHeight = config.power.height
    local healthHeight = config.height - powerHeight
    BuildHealthBar(self, config, healthHeight)
    BuildPowerBar(self, config, powerHeight)
    BuildNameText(self, config, self._fakeUnit)
    BuildStatusIcons(self, config)
    BuildCastbar(self, config)
    BuildHighlights(self, config)
    BuildAuraIndicators(self, auraConfig)

    -- Re-apply fake unit
    if(self._fakeUnit) then
        local cc = CLASS_COLORS[self._fakeUnit.class] or { 0.5, 0.5, 0.5 }
        self._healthBar:SetStatusBarColor(cc[1], cc[2], cc[3], 1)
        self._healthBar:SetValue(self._fakeUnit.healthPct or 1)
        if(self._powerBar) then
            self._powerBar:SetValue(self._fakeUnit.powerPct or 0.8)
        end
    end

    self._config = config
end
```

- [ ] **Step 2: Add targeted element update method**

For frequent changes (slider drags, text edits), a targeted update avoids full rebuilds:

```lua
--- Update a single element based on a config path change.
--- Falls back to full rebuild for structural changes.
--- @param configPath string  The config path that changed (e.g., 'width', 'health.fontSize')
--- @param value any  The new value
function frame:UpdateElement(configPath, value)
    -- Dimension changes → full rebuild (structural)
    if(configPath == 'width' or configPath == 'height' or configPath == 'power.height'
        or configPath == 'power.position' or configPath == 'showPower'
        or configPath == 'showCastBar' or configPath == 'showName') then
        self._config[configPath] = value  -- not a deep path, but PreviewManager handles deep set
        self:UpdateFromConfig(self._config)
        return
    end

    -- Health text changes
    if(configPath:match('^health%.')) then
        if(self._healthText) then
            local hc = self._config.health
            if(configPath == 'health.fontSize' or configPath == 'health.outline') then
                self._healthText:SetFont(F.Media.GetActiveFont(), hc.fontSize, hc.outline)
            end
        end
        return
    end

    -- Name text changes
    if(configPath:match('^name%.')) then
        if(self._nameText) then
            local nc = self._config.name
            if(configPath == 'name.fontSize' or configPath == 'name.outline') then
                self._nameText:SetFont(F.Media.GetActiveFont(), nc.fontSize, nc.outline)
            end
        end
        return
    end
end
```

- [ ] **Step 3: Commit**

```bash
git add Preview/PreviewFrame.lua
git commit -m "feat: add UpdateFromConfig and UpdateElement methods to PreviewFrame"
```

---

### Task 6: Build PreviewManager — Solo Frame Preview

**Files:**
- Create: `Preview/PreviewManager.lua`
- Modify: `Framed.toc`

The manager handles creating/destroying preview frames when frames are selected in edit mode. This task covers solo frame preview (player, target, targettarget, focus, pet).

- [ ] **Step 1: Create PreviewManager.lua**

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode
local EditCache = F.EditCache

F.PreviewManager = {}
local PM = F.PreviewManager

-- ============================================================
-- State
-- ============================================================

local activeFrameKey = nil
local previewFrames = {}       -- Array of preview frame instances
local previewContainer = nil   -- Parent frame for all previews

-- Solo frame fake unit data
local function GetPlayerClass()
    local _, class = UnitClass('player')
    return class or 'PALADIN'
end

local SOLO_FAKES = {
    player       = function() return { name = UnitName('player') or 'You', class = GetPlayerClass(), healthPct = 1.0,  powerPct = 0.85 } end,
    target       = function() return { name = 'Target Dummy',  class = 'WARRIOR',  healthPct = 0.72, powerPct = 0.6  } end,
    targettarget = function() return { name = 'Healbot',       class = 'PRIEST',   healthPct = 0.90, powerPct = 0.8  } end,
    focus        = function() return { name = 'Focus Target',  class = 'MAGE',     healthPct = 0.55, powerPct = 0.45 } end,
    pet          = function() return { name = 'Pet',           class = 'HUNTER',   healthPct = 0.80, powerPct = 0.7  } end,
    boss         = function() return { name = 'Raid Boss',     class = 'WARRIOR',  healthPct = 0.95, powerPct = 1.0  } end,
    arena        = function() return { name = 'Gladiator',     class = 'ROGUE',    healthPct = 0.60, powerPct = 0.3  } end,
}

local GROUP_TYPES = { party = true, raid = true, arena = true, boss = true }

-- ============================================================
-- Config reading helpers
-- ============================================================

local function GetUnitConfig(frameKey)
    local preset = EditMode.GetSessionPreset()
    -- Read through EditCache so pending edits are reflected
    local configPath = 'presets.' .. preset .. '.unitConfigs.' .. frameKey
    -- Build a merged config table: start with saved, overlay cache
    local saved = F.Config:Get(configPath)
    if(not saved) then return nil end
    local config = F.DeepCopy(saved)
    -- Apply any cached edits
    local edits = EditCache.GetEditsForFrame(frameKey)
    if(edits) then
        for path, value in next, edits do
            -- Set nested value in config
            local keys = {}
            for k in path:gmatch('[^%.]+') do
                keys[#keys + 1] = k
            end
            local target = config
            for i = 1, #keys - 1 do
                if(type(target[keys[i]]) ~= 'table') then
                    target[keys[i]] = {}
                end
                target = target[keys[i]]
            end
            target[keys[#keys]] = value
        end
    end
    return config
end

local function GetAuraConfig(frameKey)
    local preset = EditMode.GetSessionPreset()
    return F.Config:Get('presets.' .. preset .. '.auras.' .. frameKey)
end

-- ============================================================
-- Preview lifecycle
-- ============================================================

local function DestroyPreviews()
    for _, pf in next, previewFrames do
        pf:Hide()
        pf:SetParent(nil)
    end
    previewFrames = {}
    activeFrameKey = nil
end

local function GetPreviewContainer()
    if(not previewContainer) then
        local overlay = EditMode.GetOverlay()
        if(not overlay) then return nil end
        previewContainer = CreateFrame('Frame', nil, overlay)
        previewContainer:SetAllPoints(overlay)
        previewContainer:SetFrameLevel(overlay:GetFrameLevel() + 8)
    end
    return previewContainer
end

-- ============================================================
-- Solo frame preview
-- ============================================================

local function ShowSoloPreview(frameKey)
    local container = GetPreviewContainer()
    if(not container) then return end

    local config = GetUnitConfig(frameKey)
    if(not config) then return end

    local fakeFn = SOLO_FAKES[frameKey]
    local fakeUnit = fakeFn and fakeFn() or { name = frameKey, class = 'WARRIOR', healthPct = 0.8, powerPct = 0.5 }
    local auraConfig = GetAuraConfig(frameKey)

    local pf = F.PreviewFrame.Create(container, config, fakeUnit, auraConfig)

    -- Position at the same screen location as the real frame
    -- Read position from EditCache (may have been dragged)
    local x = EditCache.Get(frameKey, 'position.x') or config.position.x
    local y = EditCache.Get(frameKey, 'position.y') or config.position.y
    pf:SetPoint('CENTER', UIParent, 'CENTER', x, y)

    previewFrames[1] = pf
    pf:Show()
end

-- ============================================================
-- Public API
-- ============================================================

function PM.ShowPreview(frameKey)
    DestroyPreviews()
    activeFrameKey = frameKey

    if(GROUP_TYPES[frameKey]) then
        -- Task 7 will implement group preview
        ShowSoloPreview(frameKey)  -- Temporary fallback
    else
        ShowSoloPreview(frameKey)
    end
end

function PM.HidePreview()
    DestroyPreviews()
end

function PM.GetActiveFrameKey()
    return activeFrameKey
end

-- ============================================================
-- Event listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
    if(frameKey) then
        PM.ShowPreview(frameKey)
    else
        PM.HidePreview()
    end
end, 'PreviewManager.selected')

F.EventBus:Register('EDIT_MODE_EXITED', function()
    PM.HidePreview()
    if(previewContainer) then
        previewContainer:Hide()
        previewContainer = nil
    end
end, 'PreviewManager.exited')

-- Live update from edit cache changes
F.EventBus:Register('EDIT_CACHE_VALUE_CHANGED', function(frameKey, configPath, value)
    if(frameKey ~= activeFrameKey) then return end
    -- For position changes, just reposition (don't rebuild)
    if(configPath == 'position.x' or configPath == 'position.y') then
        if(previewFrames[1]) then
            local config = GetUnitConfig(frameKey)
            if(config) then
                local x = EditCache.Get(frameKey, 'position.x') or config.position.x
                local y = EditCache.Get(frameKey, 'position.y') or config.position.y
                previewFrames[1]:ClearAllPoints()
                previewFrames[1]:SetPoint('CENTER', UIParent, 'CENTER', x, y)
            end
        end
        return
    end
    -- For other changes, rebuild preview
    for _, pf in next, previewFrames do
        local config = GetUnitConfig(frameKey)
        local auraConfig = GetAuraConfig(frameKey)
        if(config) then
            pf:UpdateFromConfig(config, auraConfig)
        end
    end
end, 'PreviewManager.cacheChanged')

-- Aura group dimming
F.EventBus:Register('EDIT_MODE_AURA_DIM', function(frameKey, activeGroupId)
    if(frameKey ~= activeFrameKey) then return end
    for _, pf in next, previewFrames do
        pf:SetAuraGroupAlpha(activeGroupId)
    end
end, 'PreviewManager.auraDim')
```

- [ ] **Step 2: Add to Framed.toc**

```
# Preview
Preview/Preview.lua
Preview/PreviewFrame.lua
Preview/PreviewManager.lua
```

- [ ] **Step 3: Commit**

```bash
git add Preview/PreviewManager.lua Framed.toc
git commit -m "feat: add PreviewManager with solo frame preview and live updates"
```

---

### Task 7: Add Group Frame Preview to PreviewManager

**Files:**
- Modify: `Preview/PreviewManager.lua`

Handle party (5 frames), raid (20-40), arena (up to 5), and boss (up to 5) by spawning N preview frames in the correct layout.

- [ ] **Step 1: Define group frame counts and fake units**

Add constants to `PreviewManager.lua`:

```lua
local GROUP_FRAME_COUNTS = {
    party = 5,
    raid  = 20,   -- Default preview count; actual depends on preset
    arena = 3,
    boss  = 4,
}

-- Raid preset sizes
local RAID_PRESET_COUNTS = {
    ['Raid']        = 20,
    ['Mythic Raid'] = 20,
    ['World Raid']  = 40,
}
```

- [ ] **Step 2: Implement ShowGroupPreview**

```lua
local function ShowGroupPreview(frameKey)
    local container = GetPreviewContainer()
    if(not container) then return end

    local config = GetUnitConfig(frameKey)
    if(not config) then return end

    local auraConfig = GetAuraConfig(frameKey)
    local fakeUnits = F.Preview.GetFakeUnits(5)

    -- Determine frame count
    local count = GROUP_FRAME_COUNTS[frameKey] or 5
    if(frameKey == 'raid') then
        local preset = EditMode.GetSessionPreset()
        count = RAID_PRESET_COUNTS[preset] or 20
    end

    -- Layout params from config
    local orientation = config.orientation or 'vertical'
    local anchorPoint = config.anchorPoint or 'TOPLEFT'
    local spacing = config.spacing or 2

    -- Calculate position offsets based on orientation
    local isVertical = (orientation == 'vertical')
    local stepX = isVertical and 0 or (config.width + spacing)
    local stepY = isVertical and -(config.height + spacing) or 0

    -- Flip direction based on anchor point
    if(anchorPoint == 'TOPRIGHT' or anchorPoint == 'BOTTOMRIGHT') then
        stepX = -stepX
    end
    if(anchorPoint == 'BOTTOMLEFT' or anchorPoint == 'BOTTOMRIGHT') then
        stepY = -stepY
    end

    -- Base position from config
    local baseX = EditCache.Get(frameKey, 'position.x') or config.position.x
    local baseY = EditCache.Get(frameKey, 'position.y') or config.position.y

    for i = 1, count do
        local fakeUnit = fakeUnits[((i - 1) % #fakeUnits) + 1]
        -- Cycle through fake units, vary health for visual interest
        local varied = {
            name = fakeUnit.name .. (i > #fakeUnits and (' ' .. i) or ''),
            class = fakeUnit.class,
            role = fakeUnit.role,
            healthPct = math.max(0.1, fakeUnit.healthPct - (i * 0.03)),
            powerPct = fakeUnit.powerPct,
            isDead = fakeUnit.isDead,
        }

        local pf = F.PreviewFrame.Create(container, config, varied, auraConfig)
        local offX = (i - 1) * stepX
        local offY = (i - 1) * stepY
        pf:SetPoint(anchorPoint, UIParent, 'TOPLEFT', baseX + offX, baseY + offY)
        previewFrames[i] = pf
        pf:Show()
    end
end
```

- [ ] **Step 3: Wire into ShowPreview**

Replace the temporary fallback in `PM.ShowPreview`:

```lua
function PM.ShowPreview(frameKey)
    DestroyPreviews()
    activeFrameKey = frameKey

    if(GROUP_TYPES[frameKey]) then
        ShowGroupPreview(frameKey)
    else
        ShowSoloPreview(frameKey)
    end
end
```

- [ ] **Step 4: Update EDIT_CACHE_VALUE_CHANGED handler for group frames**

The position and layout changes for group frames need to reposition all N frames:

```lua
-- In the EDIT_CACHE_VALUE_CHANGED handler, replace the position block:
    if(configPath == 'position.x' or configPath == 'position.y'
        or configPath == 'spacing' or configPath == 'orientation' or configPath == 'anchorPoint') then
        -- Structural layout change — rebuild all group preview frames
        if(GROUP_TYPES[activeFrameKey]) then
            PM.ShowPreview(activeFrameKey)
        elseif(previewFrames[1]) then
            local config = GetUnitConfig(frameKey)
            if(config) then
                local x = EditCache.Get(frameKey, 'position.x') or config.position.x
                local y = EditCache.Get(frameKey, 'position.y') or config.position.y
                previewFrames[1]:ClearAllPoints()
                previewFrames[1]:SetPoint('CENTER', UIParent, 'CENTER', x, y)
            end
        end
        return
    end
```

- [ ] **Step 5: Commit**

```bash
git add Preview/PreviewManager.lua
git commit -m "feat: add group frame preview (party/raid/arena/boss) to PreviewManager"
```

---

### Task 8: Wire ClickCatchers to Show Preview on Selection

**Files:**
- Modify: `EditMode/ClickCatchers.lua`

Currently, selecting a frame just clears the dim overlay to reveal the real frame underneath. Now it should also trigger the preview. The `EDIT_MODE_FRAME_SELECTED` event already fires and PreviewManager already listens — but the catcher visuals need adjustment so the preview frame is visible above the catcher.

- [ ] **Step 1: Adjust selected frame catcher to be transparent**

The selected catcher currently hides its dim and label (via `ApplySelectedVisuals`). This is correct — the preview frame renders above the catcher at frame level +8, while the catcher is at +10. We need to adjust the z-ordering so the preview is above the catcher.

In `ClickCatchers.lua`, update `CreateCatcher` to lower selected catcher frame level:

```lua
-- In EDIT_MODE_FRAME_SELECTED handler, adjust frame levels:
F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
    for key, catcher in next, catchers do
        local def = -- find def for key
        if(key == frameKey) then
            ApplySelectedVisuals(catcher)
            -- Lower frame level so preview renders above
            catcher:SetFrameLevel(overlay:GetFrameLevel() + 6)
        else
            ApplyDefaultVisuals(catcher, def)
            catcher:SetFrameLevel(overlay:GetFrameLevel() + 10)
        end
        catcher:Show()
    end
end, 'ClickCatchers.selected')
```

Actually, read the existing event handler first and adjust it. The key change: the selected catcher needs a LOWER frame level than the preview container (which is at +8). Set selected catcher to +6, unselected stays at +10.

- [ ] **Step 2: Store def reference on each catcher**

To access `def` in the event handler, store it on the catcher during creation:

```lua
-- In CreateCatcher, after creating catcher:
catcher._def = def
```

Then the event handler can use `catcher._def` instead of looking up the definition.

- [ ] **Step 3: Update the EDIT_MODE_FRAME_SELECTED handler**

Read the existing handler in `ClickCatchers.lua` and modify it to:
1. Use `catcher._def` for ApplyDefaultVisuals
2. Adjust frame levels (selected = +6, others = +10)
3. Keep the selected catcher clickable so the user can still drag the preview frame's position

- [ ] **Step 4: Verify preview renders above selected catcher**

The PreviewManager creates its container at overlay frame level +8. The selected catcher is at +6. The unselected catchers are at +10. This means:
- Preview frame: level 8 (visible above selected catcher at 6)
- Unselected catchers: level 10 (visible above preview)
- Selected catcher: level 6 (below preview, but still receives mouse events for dragging)

This is the correct layering.

- [ ] **Step 5: Commit**

```bash
git add EditMode/ClickCatchers.lua
git commit -m "feat: wire click catchers to preview system with correct z-ordering"
```

---

### Task 9: Integration Testing & Polish

**Files:**
- Modify: `Preview/PreviewFrame.lua` (potential fixes)
- Modify: `Preview/PreviewManager.lua` (potential fixes)
- Modify: `EditMode/ClickCatchers.lua` (potential fixes)

This task covers in-game testing, sync to WoW addon folder, and fixing issues found during testing.

- [ ] **Step 1: Sync to WoW addon folder**

```bash
rsync -av --delete \
  --exclude='.git' --exclude='.worktrees' --exclude='.superpowers' \
  --exclude='.DS_Store' --exclude='docs/' \
  /path/to/worktree/ \
  "/Applications/World of Warcraft/_retail_/Interface/AddOns/Framed/"
```

- [ ] **Step 2: Test solo frame selection**

Enter edit mode (`/framed edit`), click each solo frame type:
- [ ] Player — preview shows with health, power, name, status icons
- [ ] Target — preview shows at correct position
- [ ] Target of Target — smaller preview, no castbar
- [ ] Focus — preview at focus position
- [ ] Pet — smaller preview

Verify:
- Preview appears when selected (not just dim removal)
- Preview disappears when clicking another frame
- Preview disappears when exiting edit mode

- [ ] **Step 3: Test live updates**

With a frame selected, open the inline settings panel and change:
- [ ] Width slider — preview frame width changes live
- [ ] Height slider — preview frame height changes live
- [ ] Health text toggle — text appears/disappears
- [ ] Name font size — font updates live

- [ ] **Step 4: Test group frame selection**

Click on party/raid frames (if visible in current preset):
- [ ] Party — 5 preview frames appear in correct layout
- [ ] Spacing/orientation changes update layout

- [ ] **Step 5: Test aura group dimming**

Select a frame, switch to Buffs in the panel dropdown:
- [ ] Buff indicators stay bright
- [ ] Other aura group indicators dim to 20% alpha
- [ ] Switching back to frame settings restores all to full alpha

- [ ] **Step 6: Fix issues found during testing**

Address any visual glitches, positioning errors, or missing elements.

- [ ] **Step 7: Commit fixes**

```bash
git add -A
git commit -m "fix: polish edit mode preview after integration testing"
```

---

### Task 10: Version Bump

**Files:**
- Modify: `Init.lua`

- [ ] **Step 1: Bump patch version**

Update the version string in `Init.lua`:

```lua
F.version = '0.3.1-alpha'  -- or whatever the next patch version is
```

Check the current version first and increment the patch number.

- [ ] **Step 2: Commit**

```bash
git add Init.lua
git commit -m "chore: bump version to 0.3.X-alpha"
```
