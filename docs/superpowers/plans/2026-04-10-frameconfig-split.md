# FrameConfig Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `Units/LiveUpdate/FrameConfig.lua` (1950 lines) into focused sub-modules under `Units/LiveUpdate/`, each ≤500 lines, without changing any behavior.

**Architecture:** FrameConfig.lua is entirely self-contained — it registers EventBus listeners and references `F.StyleBuilder.ForEachFrame()` but no external code imports from it. The split extracts sections of the single CONFIG_CHANGED callback into separate files, each registering their own EventBus listener with the same `parseUnitConfigPath` + preset guard pattern. Shared infrastructure (combat queue, debounce, path parser, helpers) moves to a shared module that the sub-modules require.

**Tech Stack:** Lua 5.1 (WoW addon), oUF framework, Framed EventBus

---

## File Structure

| File | Lines (approx) | Responsibility |
|---|---|---|
| `Units/LiveUpdate/FrameConfigShared.lua` | ~120 | Shared infrastructure: combat queue, debounce, path parser, GROUP_TYPES, STATUS_ELEMENT_MAP, position/resize helpers |
| `Units/LiveUpdate/FrameConfigLayout.lua` | ~200 | CONFIG_CHANGED handlers for position, dimensions, spacing, orientation, anchorPoint |
| `Units/LiveUpdate/FrameConfigElements.lua` | ~200 | CONFIG_CHANGED handlers for power, portrait, castbar, status icons, showName |
| `Units/LiveUpdate/FrameConfigHealth.lua` | ~450 | CONFIG_CHANGED handlers for health coloring, loss color, shields/absorbs, text display, smooth |
| `Units/LiveUpdate/FrameConfigText.lua` | ~200 | CONFIG_CHANGED handlers for health/power/name text formatting, fonts, anchors, colors |
| `Units/LiveUpdate/FrameConfigPreset.lua` | ~350 | PRESET_CHANGED handler (applyFullConfig + aura element map) |
| `Units/LiveUpdate/FrameConfigPets.lua` | ~120 | CONFIG_CHANGED handler for partyPets |
| `Units/LiveUpdate/FrameConfig.lua` | ~5 | Stub: just loads sub-modules (kept for TOC compatibility) |

**Key design decision:** Each sub-module is a standalone file that:
1. Opens with `local addonName, Framed = ...` and the standard `local F = Framed` preamble
2. Calls `local Shared = F.LiveUpdate.FrameConfigShared` to access shared helpers
3. Registers its own `CONFIG_CHANGED` EventBus listener with a unique owner string
4. Uses early-return if the key doesn't match its responsibility

The CONFIG_CHANGED handler currently uses `if(key == ...) then ... return end` chains. Each sub-module takes ownership of its key prefixes and returns early for keys it doesn't handle. Since EventBus fires all listeners for an event, multiple sub-modules receiving the same event is fine — only the one matching the key will act.

---

### Task 1: Create FrameConfigShared — extract shared infrastructure

**Files:**
- Create: `Units/LiveUpdate/FrameConfigShared.lua`
- Modify: `Framed.toc`

This task extracts the shared infrastructure that all sub-modules need: combat queue, debounce, path parser, GROUP_TYPES, STATUS_ELEMENT_MAP, and position/resize helpers.

- [ ] **Step 1: Create FrameConfigShared.lua**

```lua
local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

-- ============================================================
-- FrameConfigShared — shared infrastructure for LiveUpdate sub-modules
-- ============================================================

F.LiveUpdate = F.LiveUpdate or {}
local Shared = {}
F.LiveUpdate.FrameConfigShared = Shared

Shared.ForEachFrame = F.StyleBuilder.ForEachFrame

-- ============================================================
-- Combat queue for group layout (SetAttribute locked in combat)
-- ============================================================

local pendingGroupChanges = {}
local combatQueueStatus

function Shared.applyOrQueue(header, attr, value)
	if(InCombatLockdown()) then
		pendingGroupChanges[#pendingGroupChanges + 1] = { header, attr, value }
		if(combatQueueStatus) then
			combatQueueStatus:SetText('Changes queued — will apply after combat')
			combatQueueStatus:Show()
		end
	else
		header:SetAttribute(attr, value)
	end
end

F.EventBus:Register('PLAYER_REGEN_ENABLED', function()
	for _, change in next, pendingGroupChanges do
		change[1]:SetAttribute(change[2], change[3])
	end
	wipe(pendingGroupChanges)
	if(combatQueueStatus) then
		combatQueueStatus:Hide()
	end
end, 'LiveUpdate.CombatQueue')

-- ============================================================
-- Debounce (Tier 1: 0.05s for non-structural changes)
-- ============================================================

local pendingUpdates = {}

function Shared.debouncedApply(key, applyFn, ...)
	if(pendingUpdates[key]) then
		pendingUpdates[key]:Cancel()
	end
	local args = { ... }
	pendingUpdates[key] = C_Timer.NewTimer(0.05, function()
		pendingUpdates[key] = nil
		applyFn(unpack(args))
	end)
end

-- ============================================================
-- Status icon element map
-- ============================================================

Shared.STATUS_ELEMENT_MAP = {
	role       = 'GroupRoleIndicator',
	leader     = 'LeaderIndicator',
	readyCheck = 'ReadyCheckIndicator',
	raidIcon   = 'RaidTargetIndicator',
	combat     = 'CombatIndicator',
	resting    = 'RestingIndicator',
	phase      = 'PhaseIndicator',
	resurrect  = 'ResurrectIndicator',
	summon     = 'SummonIndicator',
	raidRole   = 'RaidRoleIndicator',
	pvp        = 'PvPIndicator',
}

-- ============================================================
-- Path parser
-- ============================================================

function Shared.parseUnitConfigPath(path)
	local presetName, unitType, rest = path:match('presets%.([^%.]+)%.unitConfigs%.([^%.]+)%.(.+)$')
	if(not unitType) then
		unitType, rest = path:match('unitConfigs%.([^%.]+)%.(.+)$')
	end
	return unitType, rest, presetName
end

-- ============================================================
-- Group types
-- ============================================================

Shared.GROUP_TYPES = {
	party        = true,
	raid         = true,
	battleground = true,
	worldraid    = true,
}

-- ============================================================
-- Group header lookup
-- ============================================================

function Shared.getGroupHeader(unitType)
	if(unitType == 'party') then
		return F.Units.Party and F.Units.Party.header
	elseif(unitType == 'raid') then
		return F.Units.Raid and F.Units.Raid.header
	end
	return nil
end

-- ============================================================
-- Position / resize helpers
-- ============================================================

function Shared.repositionFrame(frame, config)
	local pos = config.position
	local x = pos.x
	local y = pos.y
	frame:ClearAllPoints()
	Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)
end

function Shared.resizeShift(anchor, dw, dh)
	local dx, dy = 0, 0
	if(anchor == 'TOPLEFT') then       dx, dy =  dw / 2, -dh / 2
	elseif(anchor == 'TOP') then       dx, dy =  0,      -dh / 2
	elseif(anchor == 'TOPRIGHT') then  dx, dy = -dw / 2, -dh / 2
	elseif(anchor == 'LEFT') then      dx, dy =  dw / 2,  0
	elseif(anchor == 'CENTER') then    dx, dy =  0,        0
	elseif(anchor == 'RIGHT') then     dx, dy = -dw / 2,  0
	elseif(anchor == 'BOTTOMLEFT') then  dx, dy =  dw / 2, dh / 2
	elseif(anchor == 'BOTTOM') then      dx, dy =  0,      dh / 2
	elseif(anchor == 'BOTTOMRIGHT') then dx, dy = -dw / 2, dh / 2
	end
	return dx, dy
end

local function anchorFractions(pt)
	local fx, fy = 0.5, 0.5
	if(pt:find('LEFT'))   then fx = 0 end
	if(pt:find('RIGHT'))  then fx = 1 end
	if(pt:find('TOP'))    then fy = 0 end
	if(pt:find('BOTTOM')) then fy = 1 end
	return fx, fy
end

function Shared.groupResizeShift(headerAnchor, resizeAnchor, dw, dh)
	local hx, hy = anchorFractions(headerAnchor)
	local rx, ry = anchorFractions(resizeAnchor)
	local dx = -(rx - hx) * dw
	local dy =  (ry - hy) * dh
	return dx, dy
end

--- Apply group layout attributes to a header based on config.
function Shared.applyGroupLayoutToHeader(header, config)
	local orient  = config.orientation
	local anchor  = config.anchorPoint
	local spacing = config.spacing

	local point, yOff, xOff, colAnchor

	if(orient == 'vertical') then
		local goDown = (anchor == 'TOPLEFT' or anchor == 'TOPRIGHT')
		point  = goDown and 'TOP' or 'BOTTOM'
		yOff   = goDown and -spacing or spacing
		xOff   = 0
		colAnchor = (anchor == 'TOPLEFT' or anchor == 'BOTTOMLEFT') and 'LEFT' or 'RIGHT'
	else
		local goRight = (anchor == 'TOPLEFT' or anchor == 'BOTTOMLEFT')
		point  = goRight and 'LEFT' or 'RIGHT'
		xOff   = goRight and spacing or -spacing
		yOff   = 0
		colAnchor = (anchor == 'TOPLEFT' or anchor == 'TOPRIGHT') and 'TOP' or 'BOTTOM'
	end

	Shared.applyOrQueue(header, 'xOffset', xOff)
	Shared.applyOrQueue(header, 'yOffset', yOff)
	Shared.applyOrQueue(header, 'point', point)
	Shared.applyOrQueue(header, 'columnAnchorPoint', colAnchor)

	if(not InCombatLockdown()) then
		local name = header:GetName()
		if(name and name:find('Party')) then
			header:SetAttribute('showParty', false)
			header:SetAttribute('showParty', true)
		elseif(name and name:find('Raid')) then
			header:SetAttribute('showRaid', false)
			header:SetAttribute('showRaid', true)
		end
	end
end

--- Standard guard: parse path, check active preset, return unitType + key.
--- Returns nil, nil if the event should be skipped.
function Shared.guardConfigChanged(path)
	local unitType, key, presetName = Shared.parseUnitConfigPath(path)
	if(not unitType) then return nil, nil end
	if(presetName and presetName ~= F.AutoSwitch.GetCurrentPreset()) then return nil, nil end
	return unitType, key
end
```

- [ ] **Step 2: Add to TOC before FrameConfig.lua**

In `Framed.toc`, insert `Units/LiveUpdate/FrameConfigShared.lua` immediately before the existing `Units/LiveUpdate/FrameConfig.lua` line:

```
Units/LiveUpdate/FrameConfigShared.lua
Units/LiveUpdate/FrameConfig.lua
```

- [ ] **Step 3: Verify load**

Test in-game with `/reload` — no errors. The shared module is loaded but nothing references it yet (FrameConfig.lua still has its original code).

- [ ] **Step 4: Commit**

```bash
git add Units/LiveUpdate/FrameConfigShared.lua Framed.toc
git commit -m "Add FrameConfigShared: extract shared LiveUpdate infrastructure"
```

---

### Task 2: Create FrameConfigLayout — position, dimensions, group layout

**Files:**
- Create: `Units/LiveUpdate/FrameConfigLayout.lua`
- Modify: `Units/LiveUpdate/FrameConfig.lua` (remove lines 246-430)
- Modify: `Framed.toc`

This task extracts the position/dimensions/group-layout handlers (keys: `position.anchor`, `position.x`, `position.y`, `width`, `height`, `spacing`, `orientation`, `anchorPoint`).

- [ ] **Step 1: Create FrameConfigLayout.lua**

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets

local Shared = F.LiveUpdate.FrameConfigShared
local ForEachFrame    = Shared.ForEachFrame
local GROUP_TYPES     = Shared.GROUP_TYPES
local getGroupHeader  = Shared.getGroupHeader
local repositionFrame = Shared.repositionFrame
local resizeShift     = Shared.resizeShift
local groupResizeShift = Shared.groupResizeShift
local applyOrQueue     = Shared.applyOrQueue
local applyGroupLayoutToHeader = Shared.applyGroupLayoutToHeader
local debouncedApply  = Shared.debouncedApply

-- ============================================================
-- CONFIG_CHANGED: position, dimensions, group layout
-- ============================================================

local suppressPositionUpdate = false

-- Expose suppress flag for dimension handler's position writes
F.LiveUpdate = F.LiveUpdate or {}
F.LiveUpdate.suppressPositionUpdate = function() return suppressPositionUpdate end
F.LiveUpdate.setSuppressPositionUpdate = function(val) suppressPositionUpdate = val end

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local unitType, key = Shared.guardConfigChanged(path)
	if(not unitType) then return end

	-- Frame anchor change — resize preference only, no frame movement
	if(key == 'position.anchor') then
		return
	end

	-- Frame position (x, y)
	if(key == 'position.x' or key == 'position.y') then
		if(suppressPositionUpdate) then return end
		local config = F.StyleBuilder.GetConfig(unitType)
		if(GROUP_TYPES[unitType]) then
			local header = getGroupHeader(unitType)
			if(header) then
				local pos = config.position
				local x = pos.x
				local y = pos.y
				header:ClearAllPoints()
				Widgets.SetPoint(header, 'TOPLEFT', UIParent, 'TOPLEFT', x, y)
			end
		else
			ForEachFrame(unitType, function(frame)
				repositionFrame(frame, config)
			end)
		end
		return
	end

	-- Dimensions — resize frame, health wrapper, power wrapper
	if(key == 'width' or key == 'height') then
		local config = F.StyleBuilder.GetConfig(unitType)
		debouncedApply('dimensions.' .. unitType, function()
			local powerHeight = config.power.height
			local healthHeight = config.height - powerHeight

			if(GROUP_TYPES[unitType]) then
				local header = getGroupHeader(unitType)

				local oldW, oldH, numFrames = nil, nil, 0
				ForEachFrame(unitType, function(frame)
					if(not oldW) then
						oldW = frame:GetWidth() or config.width
						oldH = frame:GetHeight() or config.height
					end
					numFrames = numFrames + 1
				end)

				ForEachFrame(unitType, function(frame)
					Widgets.SetSize(frame, config.width, config.height)
					if(frame.Health and frame.Health._wrapper) then
						Widgets.SetSize(frame.Health._wrapper, config.width, healthHeight)
					end
					if(frame.Power and frame.Power._wrapper) then
						Widgets.SetSize(frame.Power._wrapper, config.width, powerHeight)
						local pos = config.power.position
						frame.Power._wrapper:ClearAllPoints()
						frame.Health._wrapper:ClearAllPoints()
						if(pos == 'top') then
							frame.Power._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
							frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -powerHeight)
						else
							frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
							frame.Power._wrapper:SetPoint('TOPLEFT', frame.Health._wrapper, 'BOTTOMLEFT', 0, 0)
						end
						if(frame.Power.SetSharedEdge) then
							frame.Power:SetSharedEdge(pos)
						end
					end
					local cbCfg = config.castbar
					if(cbCfg and frame.Castbar and frame.Castbar._wrapper and cbCfg.sizeMode ~= 'detached') then
						Widgets.SetSize(frame.Castbar._wrapper, config.width, cbCfg.height)
					end
				end)
				if(header and oldW) then
					local anchor = config.position.anchor
					local orient = config.orientation
					local dw = config.width  - oldW
					local dh = config.height - oldH
					if(orient == 'vertical') then
						dh = dh * numFrames
					else
						dw = dw * numFrames
					end
					if(dw ~= 0 or dh ~= 0) then
						local hPt, hRel, hRelPt, hX, hY = header:GetPoint(1)
						if(hPt) then
							local dx, dy = groupResizeShift(hPt, anchor, dw, dh)
							header:ClearAllPoints()
							Widgets.SetPoint(header, hPt, hRel, hRelPt, hX + dx, hY + dy)
						end
					end
					applyOrQueue(header, 'initial-width', config.width)
					applyOrQueue(header, 'initial-height', config.height)
				end

				if(unitType == 'party' and F.Units.Party.petFrames) then
					ForEachFrame('partypet', function(frame)
						Widgets.SetSize(frame, config.width, config.height)
						if(frame.Health and frame.Health._wrapper) then
							Widgets.SetSize(frame.Health._wrapper, config.width, config.height)
						end
					end)
				end
			else
				local anchor = config.position.anchor
				ForEachFrame(unitType, function(frame)
					local oldW = frame._width or frame:GetWidth() or config.width
					local oldH = frame._height or frame:GetHeight() or config.height
					local dw = config.width - oldW
					local dh = config.height - oldH
					if(dw ~= 0 or dh ~= 0) then
						local dx, dy = resizeShift(anchor, dw, dh)
						local pos = config.position
						local curX = pos.x
						local curY = pos.y
						suppressPositionUpdate = true
						local presetName = F.AutoSwitch.GetCurrentPreset()
						local basePath = 'presets.' .. presetName .. '.unitConfigs.' .. unitType .. '.position.'
						F.Config:Set(basePath .. 'x', Widgets.Round(curX + dx))
						F.Config:Set(basePath .. 'y', Widgets.Round(curY + dy))
						suppressPositionUpdate = false
					end
					repositionFrame(frame, F.StyleBuilder.GetConfig(unitType))
					Widgets.SetSize(frame, config.width, config.height)
					if(frame.Health and frame.Health._wrapper) then
						Widgets.SetSize(frame.Health._wrapper, config.width, healthHeight)
					end
					if(frame.Power and frame.Power._wrapper) then
						Widgets.SetSize(frame.Power._wrapper, config.width, powerHeight)
						local pos = config.power.position
						frame.Power._wrapper:ClearAllPoints()
						frame.Health._wrapper:ClearAllPoints()
						if(pos == 'top') then
							frame.Power._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
							frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -powerHeight)
						else
							frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
							frame.Power._wrapper:SetPoint('TOPLEFT', frame.Health._wrapper, 'BOTTOMLEFT', 0, 0)
						end
						if(frame.Power.SetSharedEdge) then
							frame.Power:SetSharedEdge(pos)
						end
					end
					local cbCfg = config.castbar
					if(cbCfg and frame.Castbar and frame.Castbar._wrapper and cbCfg.sizeMode ~= 'detached') then
						Widgets.SetSize(frame.Castbar._wrapper, config.width, cbCfg.height)
					end
				end)
			end
		end)
		return
	end

	-- Group layout: spacing, orientation, anchorPoint
	if(key == 'spacing' or key == 'orientation' or key == 'anchorPoint') then
		if(not GROUP_TYPES[unitType]) then return end
		local header = getGroupHeader(unitType)
		if(not header) then return end
		local config = F.StyleBuilder.GetConfig(unitType)
		applyGroupLayoutToHeader(header, config)

		if(unitType == 'party' and F.Units.Party.petFrames) then
			F.Units.Party.AnchorPetFrames()
		end
		return
	end
end, 'LiveUpdate.FrameConfigLayout')
```

- [ ] **Step 2: Remove the corresponding handlers from FrameConfig.lua**

Remove from FrameConfig.lua:
- The `local suppressPositionUpdate = false` line (line 246)
- The `position.anchor` handler (lines 255-258)
- The `position.x`/`position.y` handler (lines 260-280)
- The `width`/`height` handler (lines 282-415)
- The `spacing`/`orientation`/`anchorPoint` handler (lines 417-430)

Also remove the now-unused locals from the top of FrameConfig.lua that are only used by these handlers: the position/resize helper functions (`repositionFrame`, `resizeShift`, `anchorFractions`, `groupResizeShift`, `applyGroupLayoutToHeader`, `getGroupHeader`), `GROUP_TYPES`, `applyOrQueue`, `debouncedApply`, `pendingGroupChanges`, `combatQueueStatus`, `pendingUpdates`, `ForEachFrame`, `STATUS_ELEMENT_MAP`, `parseUnitConfigPath`. **But be careful:** some of these are still used by the remaining handlers and by `applyFullConfig`. Only remove what is truly unused after extracting this section.

At this point, the remaining FrameConfig.lua CONFIG_CHANGED handler should start at the `showPower` key check.

- [ ] **Step 3: Add to TOC after FrameConfigShared.lua**

```
Units/LiveUpdate/FrameConfigShared.lua
Units/LiveUpdate/FrameConfigLayout.lua
Units/LiveUpdate/FrameConfig.lua
```

- [ ] **Step 4: Test in-game**

Open settings, change frame position, dimensions, and group spacing/orientation. Verify all changes apply live. `/reload` should produce no errors.

- [ ] **Step 5: Commit**

```bash
git add Units/LiveUpdate/FrameConfigLayout.lua Units/LiveUpdate/FrameConfig.lua Framed.toc
git commit -m "Extract layout handlers from FrameConfig into FrameConfigLayout"
```

---

### Task 3: Create FrameConfigElements — power, portrait, castbar, status icons, showName

**Files:**
- Create: `Units/LiveUpdate/FrameConfigElements.lua`
- Modify: `Units/LiveUpdate/FrameConfig.lua` (remove the corresponding handlers)
- Modify: `Framed.toc`

This task extracts handlers for keys: `showPower`, `power.height`, `power.position`, `power.customColors`, `portrait`, `showCastBar`, `castbar.sizeMode`, `castbar.width`, `castbar.height`, `castbar.backgroundMode`, `statusIcons.*`, `statusText.*`, `showName`.

- [ ] **Step 1: Create FrameConfigElements.lua**

The file follows the same pattern: `local Shared = F.LiveUpdate.FrameConfigShared`, register a CONFIG_CHANGED listener with owner `'LiveUpdate.FrameConfigElements'`, use `Shared.guardConfigChanged(path)` for the standard guard, then handle each key with `if(key == ...) then ... return end` chains.

Copy the handler blocks from FrameConfig.lua lines 432-790 (showPower through statusIcons) and line 792-798 (showName). Replace local references (`ForEachFrame`, `STATUS_ELEMENT_MAP`, etc.) with `Shared.*` equivalents.

- [ ] **Step 2: Remove from FrameConfig.lua**

Remove the extracted handler blocks. The remaining CONFIG_CHANGED handler in FrameConfig.lua should now start at the `health.showText` key.

- [ ] **Step 3: Add to TOC**

```
Units/LiveUpdate/FrameConfigShared.lua
Units/LiveUpdate/FrameConfigLayout.lua
Units/LiveUpdate/FrameConfigElements.lua
Units/LiveUpdate/FrameConfig.lua
```

- [ ] **Step 4: Test in-game**

Toggle power bar, change portrait type, toggle castbar, toggle status icons, toggle name. All should apply live.

- [ ] **Step 5: Commit**

```bash
git add Units/LiveUpdate/FrameConfigElements.lua Units/LiveUpdate/FrameConfig.lua Framed.toc
git commit -m "Extract element handlers from FrameConfig into FrameConfigElements"
```

---

### Task 4: Create FrameConfigHealth — health coloring, shields, absorbs

**Files:**
- Create: `Units/LiveUpdate/FrameConfigHealth.lua`
- Modify: `Units/LiveUpdate/FrameConfig.lua`
- Modify: `Framed.toc`

This task extracts handlers for keys: `health.colorMode`, `health.customColor`, `health.lossColorMode`, `health.lossCustomColor`, `health.lossGradient*`, `health.healPrediction`, `health.healPredictionMode`, `health.damageAbsorb`, `health.overAbsorb`, `health.healAbsorb`, `health.healPredictionColor`, `health.damageAbsorbColor`, `health.healAbsorbColor`, `health.smooth`.

- [ ] **Step 1: Create FrameConfigHealth.lua**

Same pattern. Copy handler blocks from FrameConfig.lua for all `health.*` keys listed above (lines 560-714, 953-1096, 1297-1309). Register with owner `'LiveUpdate.FrameConfigHealth'`.

- [ ] **Step 2: Remove from FrameConfig.lua**

- [ ] **Step 3: Add to TOC**

- [ ] **Step 4: Test in-game**

Change health color mode (class/gradient/dark/custom), loss color mode, shield toggles, absorb colors. Verify all apply live.

- [ ] **Step 5: Commit**

```bash
git add Units/LiveUpdate/FrameConfigHealth.lua Units/LiveUpdate/FrameConfig.lua Framed.toc
git commit -m "Extract health handlers from FrameConfig into FrameConfigHealth"
```

---

### Task 5: Create FrameConfigText — text formatting, fonts, anchors

**Files:**
- Create: `Units/LiveUpdate/FrameConfigText.lua`
- Modify: `Units/LiveUpdate/FrameConfig.lua`
- Modify: `Framed.toc`

This task extracts handlers for keys: `health.showText`, `health.attachedToName`, `health.textFormat`, `health.fontSize`, `health.outline`, `health.shadow`, `health.textAnchor`, `health.textAnchorX`, `health.textAnchorY`, `health.textColorMode`, `health.textCustomColor`, `power.showText`, `power.textFormat`, `power.fontSize`, `power.outline`, `power.shadow`, `power.textAnchor*`, `power.textColorMode`, `power.textCustomColor`, `name.fontSize`, `name.outline`, `name.shadow`, `name.anchor`, `name.anchorX`, `name.anchorY`, `name.colorMode`, `name.customColor`.

- [ ] **Step 1: Create FrameConfigText.lua**

Copy handler blocks from FrameConfig.lua for all text-related keys (lines 801-1295). Register with owner `'LiveUpdate.FrameConfigText'`.

- [ ] **Step 2: Remove from FrameConfig.lua**

After this, the CONFIG_CHANGED handler in FrameConfig.lua should be empty or nearly empty. If it is empty, remove it entirely.

- [ ] **Step 3: Add to TOC**

- [ ] **Step 4: Test in-game**

Change health text format, font size, text anchor, text color mode. Same for power and name text. Verify all apply live.

- [ ] **Step 5: Commit**

```bash
git add Units/LiveUpdate/FrameConfigText.lua Units/LiveUpdate/FrameConfig.lua Framed.toc
git commit -m "Extract text handlers from FrameConfig into FrameConfigText"
```

---

### Task 6: Create FrameConfigPreset — preset change handler

**Files:**
- Create: `Units/LiveUpdate/FrameConfigPreset.lua`
- Modify: `Units/LiveUpdate/FrameConfig.lua`
- Modify: `Framed.toc`

This task extracts the `PRESET_CHANGED` handler (lines 1313-1830): `applyFullConfig`, `AURA_ELEMENTS`, and the EventBus listener.

- [ ] **Step 1: Create FrameConfigPreset.lua**

Copy `applyFullConfig` (lines 1321-1741), `AURA_ELEMENTS` (lines 1743-1755), and the `PRESET_CHANGED` listener (lines 1757-1830). The preset handler references `GROUP_TYPES`, `getGroupHeader`, `applyGroupLayoutToHeader`, `applyOrQueue`, `repositionFrame`, `STATUS_ELEMENT_MAP`, and `ForEachFrame` — all available from `Shared`.

Register with owner `'LiveUpdate.PresetChanged'` (same as current).

- [ ] **Step 2: Remove from FrameConfig.lua**

- [ ] **Step 3: Add to TOC**

- [ ] **Step 4: Test in-game**

Switch presets. Verify frame dimensions, health colors, status icons, aura elements all update correctly.

- [ ] **Step 5: Commit**

```bash
git add Units/LiveUpdate/FrameConfigPreset.lua Units/LiveUpdate/FrameConfig.lua Framed.toc
git commit -m "Extract preset handler from FrameConfig into FrameConfigPreset"
```

---

### Task 7: Create FrameConfigPets — party pets handler

**Files:**
- Create: `Units/LiveUpdate/FrameConfigPets.lua`
- Modify: `Units/LiveUpdate/FrameConfig.lua`
- Modify: `Framed.toc`

This task extracts the party pets CONFIG_CHANGED handler (lines 1838-1950).

- [ ] **Step 1: Create FrameConfigPets.lua**

Copy the entire party pets handler block. Register with owner `'LiveUpdate.PartyPets'` (same as current).

- [ ] **Step 2: Remove from FrameConfig.lua**

After this, FrameConfig.lua should be empty of logic. Replace its content with a comment stub:

```lua
-- ============================================================
-- FrameConfig — live-update handlers for unitConfigs.*
-- Split into sub-modules:
--   FrameConfigShared.lua   — shared infrastructure
--   FrameConfigLayout.lua   — position, dimensions, group layout
--   FrameConfigElements.lua — power, portrait, castbar, status icons
--   FrameConfigHealth.lua   — health coloring, shields, absorbs
--   FrameConfigText.lua     — text formatting, fonts, anchors
--   FrameConfigPreset.lua   — preset change handler
--   FrameConfigPets.lua     — party pets handler
-- ============================================================
```

- [ ] **Step 3: Update TOC**

Replace the single `Units/LiveUpdate/FrameConfig.lua` line with all sub-modules:

```
Units/LiveUpdate/FrameConfigShared.lua
Units/LiveUpdate/FrameConfigLayout.lua
Units/LiveUpdate/FrameConfigElements.lua
Units/LiveUpdate/FrameConfigHealth.lua
Units/LiveUpdate/FrameConfigText.lua
Units/LiveUpdate/FrameConfigPreset.lua
Units/LiveUpdate/FrameConfigPets.lua
```

Remove FrameConfig.lua from the TOC entirely (its stub comment is for developer reference only, not loaded).

- [ ] **Step 4: Full test**

1. `/reload` — no errors
2. Open settings, change every category: position, dimensions, power, castbar, portrait, status icons, health colors, text formatting, shields/absorbs
3. Switch presets
4. Toggle party pets
5. Verify luacheck passes on all new files

- [ ] **Step 5: Commit**

```bash
git add Units/LiveUpdate/FrameConfigPets.lua Units/LiveUpdate/FrameConfig.lua Framed.toc
git commit -m "Extract party pets handler, complete FrameConfig split"
```

---

### Task 8: Run luacheck and final cleanup

**Files:**
- Modify: Any new files with lint warnings

- [ ] **Step 1: Run luacheck on all new files**

```bash
luacheck Units/LiveUpdate/FrameConfigShared.lua Units/LiveUpdate/FrameConfigLayout.lua Units/LiveUpdate/FrameConfigElements.lua Units/LiveUpdate/FrameConfigHealth.lua Units/LiveUpdate/FrameConfigText.lua Units/LiveUpdate/FrameConfigPreset.lua Units/LiveUpdate/FrameConfigPets.lua --config .luacheckrc
```

- [ ] **Step 2: Fix any warnings**

Address unused variable warnings (likely `addonName` → `_` in new files). Fix any other issues.

- [ ] **Step 3: Commit**

```bash
git add Units/LiveUpdate/
git commit -m "Clean lint warnings in FrameConfig sub-modules"
```
