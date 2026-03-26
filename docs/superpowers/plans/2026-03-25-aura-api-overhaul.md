# Aura API Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate all aura elements from `GetAuraDataByIndex` loops to the new `GetUnitAuras` API with server-side filtering and sorting.

**Architecture:** Each oUF element's `Update` function replaces its while-loop with a single `C_UnitAuras.GetUnitAuras(unit, filterString, ...)` call. Externals and Defensives gain visibility mode + source-based color differentiation. `Data/DefensiveSpells.lua` is deleted — spell ID tables replaced by API filters.

**Tech Stack:** WoW Lua, oUF framework (embedded at `F.oUF`), Framed widget library (`F.Widgets`), Framed config system (`F.Config`)

**Spec:** `docs/superpowers/specs/2026-03-25-aura-api-overhaul-design.md`

**Testing:** All "Verify in-game" steps require syncing files to the WoW addon folder before `/reload`. The sync target is `/Applications/World of Warcraft/_retail_/Interface/AddOns/Framed/`.

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `Framed.toc` | Bump Interface to 120001, remove DefensiveSpells.lua entry |
| Delete | `Data/DefensiveSpells.lua` | Spell ID tables no longer needed |
| Modify | `Elements/Auras/Buffs.lua` | Replace iteration with `GetUnitAuras('HELPFUL')` |
| Modify | `Elements/Auras/Debuffs.lua` | Replace iteration with `GetUnitAuras('HARMFUL', ...)` + sort rule |
| Modify | `Elements/Auras/RaidDebuffs.lua` | Replace iteration with `GetUnitAuras('HARMFUL\|RAID')` |
| Modify | `Elements/Auras/Dispellable.lua` | Replace iteration with `GetUnitAuras('HARMFUL\|RAID_PLAYER_DISPELLABLE')` + Lua priority |
| Modify | `Elements/Auras/Externals.lua` | Replace iteration with `GetUnitAuras('HELPFUL\|EXTERNAL_DEFENSIVE')`, add visibility mode + source colors |
| Modify | `Elements/Auras/Defensives.lua` | Replace iteration with `GetUnitAuras('HELPFUL\|BIG_DEFENSIVE')`, add visibility mode + source colors |
| Modify | `Elements/Status/LossOfControl.lua` | Replace iteration with `GetUnitAuras('HARMFUL\|CROWD_CONTROL', 1)` |
| Modify | `Elements/Status/CrowdControl.lua` | Replace iteration with `GetUnitAuras('HARMFUL\|CROWD_CONTROL\|PLAYER')` |
| Modify | `Settings/Builders/BorderIconSettings.lua` | Add opt-in visibility mode dropdown + two color pickers |
| Modify | `Settings/Panels/Externals.lua` | Pass new visibility/color options to builder |
| Modify | `Settings/Panels/Defensives.lua` | Pass new visibility/color options to builder |

---

### Task 1: TOC and Data Cleanup

Remove `Data/DefensiveSpells.lua` and bump the Interface version.

**Files:**
- Modify: `Framed.toc:1` (Interface line) and `Framed.toc:84` (DefensiveSpells entry)
- Delete: `Data/DefensiveSpells.lua`

- [ ] **Step 1: Bump Interface version**

In `Framed.toc`, change line 1:

```
## Interface: 120001
```

- [ ] **Step 2: Remove DefensiveSpells.lua from TOC**

In `Framed.toc`, remove line 84:

```
Data/DefensiveSpells.lua
```

- [ ] **Step 3: Delete the data file**

```bash
rm Data/DefensiveSpells.lua
```

- [ ] **Step 4: Commit**

```bash
git add Framed.toc && git rm Data/DefensiveSpells.lua
git commit -m "chore: bump Interface to 120001, remove DefensiveSpells.lua"
```

---

### Task 2: Buffs Element Migration

Replace the `GetAuraDataByIndex` while-loop with `GetUnitAuras('HELPFUL')`.

**Files:**
- Modify: `Elements/Auras/Buffs.lua:56-137` (the `Update` function's iteration loop)

**Context:** The Buffs element iterates all helpful auras and matches each against indicator spell lists via `spellLookup` and `hasTrackAll` arrays. The matching logic stays — only the iteration method changes.

- [ ] **Step 1: Replace the iteration loop in Update**

In `Elements/Auras/Buffs.lua`, replace lines 76-137 (from `-- Iterate helpful auras` through the end of the while loop) with:

```lua
	-- Iterate helpful auras
	local auras = C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')
	for _, auraData in next, auras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local auraEntry
			local sourceUnit = auraData.sourceUnit

			-- Check spell-specific indicators
			local indicatorIndices = spellLookup[spellId]
			if(indicatorIndices) then
				for _, idx in next, indicatorIndices do
					local ind = indicators[idx]
					if(passesCastByFilter(sourceUnit, ind._castBy)) then
						if(not auraEntry) then
							auraEntry = {
								spellId        = spellId,
								icon           = auraData.icon,
								duration       = auraData.duration,
								expirationTime = auraData.expirationTime,
								stacks         = auraData.applications or 0,
								dispelType     = auraData.dispelName,
							}
						end
						if(ind._type == C.IndicatorType.ICONS) then
							local list = iconsAuras[idx]
							list[#list + 1] = auraEntry
						elseif(not matched[idx]) then
							matched[idx] = auraEntry
						end
					end
				end
			end

			-- Check track-all indicators (empty spells list)
			for _, idx in next, hasTrackAll do
				local ind = indicators[idx]
				if(passesCastByFilter(sourceUnit, ind._castBy)) then
					if(not auraEntry) then
						auraEntry = {
							spellId        = spellId,
							icon           = auraData.icon,
							duration       = auraData.duration,
							expirationTime = auraData.expirationTime,
							stacks         = auraData.applications or 0,
							dispelType     = auraData.dispelName,
						}
					end
					if(ind._type == C.IndicatorType.ICONS) then
						local list = iconsAuras[idx]
						list[#list + 1] = auraEntry
					elseif(not matched[idx]) then
						matched[idx] = auraEntry
					end
				end
			end
		end
	end
```

- [ ] **Step 2: Verify in-game**

`/reload` — buff indicators on unit frames should display identically to before.

- [ ] **Step 3: Commit**

```bash
git add Elements/Auras/Buffs.lua
git commit -m "feat(buffs): migrate to GetUnitAuras('HELPFUL')"
```

---

### Task 3: Debuffs Element Migration

Replace the iteration loop with `GetUnitAuras` and use server-side sorting via `Enum.UnitAuraSortRule.Default`.

**Files:**
- Modify: `Elements/Auras/Debuffs.lua:14-68` (the `Update` function)

**Context:** Currently iterates all HARMFUL auras, applies a dispellable filter, builds a list, then sorts by boss + duration. The new API can filter and sort server-side. When `onlyDispellableByMe` is on, we use `RAID_PLAYER_DISPELLABLE` but must also include Physical/bleed debuffs (which the API filter excludes) to preserve the existing healer-awareness behavior.

- [ ] **Step 1: Replace the iteration loop and sort in Update**

In `Elements/Auras/Debuffs.lua`, replace lines 24-68 (from `-- Collect auras` through the end of `table.sort`). The existing display code from line 70 onward (`-- Display up to maxDisplayed`) must remain unchanged.

```lua
	-- Collect auras via new API with server-side sorting
	local rawAuras
	if(onlyDispellableByMe) then
		rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|RAID_PLAYER_DISPELLABLE', nil, Enum.UnitAuraSortRule.Default)
	else
		rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL', nil, Enum.UnitAuraSortRule.Default)
	end

	local auraList = {}
	for _, auraData in next, rawAuras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local dispelName = auraData.dispelName
			local dispelSafe = (not dispelName) or F.IsValueNonSecret(dispelName)

			auraList[#auraList + 1] = {
				spellId        = spellId,
				icon           = auraData.icon,
				duration       = auraData.duration,
				expirationTime = auraData.expirationTime,
				stacks         = auraData.applications or 0,
				dispelType     = dispelSafe and dispelName or nil,
				isBossAura     = auraData.isBossAura,
			}
		end
	end

	-- When onlyDispellableByMe is on, also include Physical/bleed debuffs
	-- from a broader HARMFUL|RAID query (RAID_PLAYER_DISPELLABLE excludes them)
	if(onlyDispellableByMe) then
		local raidAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|RAID')
		for _, auraData in next, raidAuras do
			local spellId = auraData.spellId
			if(F.IsValueNonSecret(spellId)) then
				local dispelName = auraData.dispelName
				local dispelSafe = (not dispelName) or F.IsValueNonSecret(dispelName)
				if(dispelSafe and (not dispelName or dispelName == '' or dispelName == 'Physical')) then
					auraList[#auraList + 1] = {
						spellId        = spellId,
						icon           = auraData.icon,
						duration       = auraData.duration,
						expirationTime = auraData.expirationTime,
						stacks         = auraData.applications or 0,
						dispelType     = nil,
						isBossAura     = auraData.isBossAura,
					}
				end
			end
		end
	end
```

**Note:** The server's `Default` sort rule handles boss/duration ordering for the primary query. The manual `table.sort` call is removed. Physical/bleed debuffs from the supplementary query will appear at the end of the list but the server's sort rule on the primary query still drives overall ordering.

- [ ] **Step 2: Verify in-game**

`/reload` — debuff icons should display in correct priority order on unit frames.

- [ ] **Step 3: Commit**

```bash
git add Elements/Auras/Debuffs.lua
git commit -m "feat(debuffs): migrate to GetUnitAuras with server-side sort"
```

---

### Task 4: RaidDebuffs Element Migration

Replace the iteration loop with `GetUnitAuras('HARMFUL|RAID')` to pre-filter to raid-relevant debuffs.

**Files:**
- Modify: `Elements/Auras/RaidDebuffs.lua:14-87` (the `Update` function)

**Context:** Currently iterates ALL harmful auras, checking each against the registry. With `HARMFUL|RAID`, the server pre-filters to raid-relevant debuffs (includes dungeon/M+), giving us a smaller set to run registry/custom logic against. The registry priority matching, flag filtering, and custom overrides all remain in Lua. The existing `table.sort` by priority/expiration (lines 82-87) also remains — registry priority cannot be expressed server-side.

- [ ] **Step 1: Replace the iteration loop in Update**

In `Elements/Auras/RaidDebuffs.lua`, replace lines 27-79 (from `-- Collect qualifying auras` through `i = i + 1; end`) with:

```lua
	-- Collect qualifying auras — server pre-filters to raid-relevant
	local rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|RAID')

	local auraList = {}
	for _, auraData in next, rawAuras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local priority  = 0
			local shouldShow = false

			-- Registry lookup
			local registryPriority = F.RaidDebuffRegistry:GetEffectivePriority(spellId)
			if(registryPriority > 0) then
				priority   = registryPriority
				shouldShow = true
			end

			-- Flag-based filtering (may show even without a registry entry)
			if(F.RaidDebuffRegistry:ShouldShow(auraData, filterMode)) then
				shouldShow = true
				if(priority == 0) then
					-- Not in registry but passes flag filter — treat as minPriority
					priority = minPriority
				end
			end

			-- User custom spells (always show regardless of registry/flags)
			if(customSpells and customSpells[spellId]) then
				shouldShow = true
				local customPriority = customSpells[spellId]
				if(type(customPriority) == 'number' and customPriority > priority) then
					priority = customPriority
				elseif(priority == 0) then
					priority = minPriority
				end
			end

			if(shouldShow and priority >= minPriority) then
				auraList[#auraList + 1] = {
					spellId        = spellId,
					icon           = auraData.icon,
					duration       = auraData.duration,
					expirationTime = auraData.expirationTime,
					stacks         = auraData.applications or 0,
					dispelType     = F.IsValueNonSecret(auraData.dispelName) and auraData.dispelName or nil,
					priority       = priority,
				}
			end
		end
	end
```

- [ ] **Step 2: Verify in-game**

`/reload` — raid debuff icons should display with correct priority ordering in dungeons/raids.

- [ ] **Step 3: Commit**

```bash
git add Elements/Auras/RaidDebuffs.lua
git commit -m "feat(raid-debuffs): migrate to GetUnitAuras('HARMFUL|RAID')"
```

---

### Task 5: Dispellable Element Migration

Replace the iteration loop with `GetUnitAuras('HARMFUL|RAID_PLAYER_DISPELLABLE')`. Retain Lua-side `DISPEL_PRIORITY` ranking and add supplementary Physical/bleed query.

**Files:**
- Modify: `Elements/Auras/Dispellable.lua:73-127` (the `Update` function's iteration loop)

**Context:** The Dispellable element finds the single highest-priority dispellable debuff (Magic > Curse > Disease > Poison > Physical). The API's `RAID_PLAYER_DISPELLABLE` filter gets us dispellable debuffs, but it won't return Physical/bleed debuffs and doesn't sort by our priority ranking. So we fetch all matches and pick the best in Lua. A supplementary `HARMFUL|RAID` query covers Physical debuffs for healer awareness.

- [ ] **Step 1: Replace the iteration loop in Update**

In `Elements/Auras/Dispellable.lua`, replace lines 89-127 (from `-- Filter is 'HARMFUL'` through `i = i + 1; end`) with:

```lua
	-- Choose filter based on onlyDispellableByMe setting
	local primaryFilter = onlyDispellableByMe and 'HARMFUL|RAID_PLAYER_DISPELLABLE' or 'HARMFUL'
	local dispellableAuras = C_UnitAuras.GetUnitAuras(unit, primaryFilter)

	for _, auraData in next, dispellableAuras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local dispelName = auraData.dispelName
			local dispelSafe = (not dispelName) or F.IsValueNonSecret(dispelName)

			if(dispelSafe) then
				local dispelType = dispelName or 'Physical'
				if(DISPEL_PRIORITY[dispelType]) then
					local priority = DISPEL_PRIORITY[dispelType]
					if(priority < bestPriority) then
						bestPriority   = priority
						bestType       = dispelType
						bestIcon       = auraData.icon
						bestSpellId    = spellId
						bestDuration   = auraData.duration
						bestExpiration = auraData.expirationTime
						bestStacks     = auraData.applications or 0
					end
				end
			end
		end
	end

	-- Supplementary query: Physical/bleed debuffs (not returned by RAID_PLAYER_DISPELLABLE)
	-- Only needed when onlyDispellableByMe is true (plain HARMFUL already includes them)
	local showPhysical = element._showPhysicalDebuffs
	if(onlyDispellableByMe and showPhysical ~= false) then
		local raidAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|RAID')
		for _, auraData in next, raidAuras do
			local spellId = auraData.spellId
			if(F.IsValueNonSecret(spellId)) then
				local dispelName = auraData.dispelName
				local dispelSafe = (not dispelName) or F.IsValueNonSecret(dispelName)

				if(dispelSafe and isPhysicalOrBleed(dispelName)) then
					local priority = DISPEL_PRIORITY.Physical
					if(priority < bestPriority) then
						bestPriority   = priority
						bestType       = 'Physical'
						bestIcon       = auraData.icon
						bestSpellId    = spellId
						bestDuration   = auraData.duration
						bestExpiration = auraData.expirationTime
						bestStacks     = auraData.applications or 0
					end
				end
			end
		end
	end
```

- [ ] **Step 2: Add showPhysicalDebuffs to the element container**

In `Elements/Auras/Dispellable.lua`, in the `Setup` function (line 269), add to the container table:

```lua
	local container = {
		_borderIcon            = borderIcon,
		_highlightType         = highlightType,
		_onlyDispellableByMe   = config.onlyDispellableByMe or false,
		_showPhysicalDebuffs   = config.showPhysicalDebuffs ~= false,
		_overlayGradientFull   = gradientFull,
		_overlayGradientHalf   = gradientHalf,
		_overlaySolidCurrent   = solidCurrent,
		_overlaySolidEntire    = solidEntire,
	}
```

- [ ] **Step 3: Confirm onlyDispellableByMe is retained in Update**

The `onlyDispellableByMe` local (line 87) is still used — it drives the filter choice between `HARMFUL|RAID_PLAYER_DISPELLABLE` and plain `HARMFUL`. Do NOT remove it. The supplementary Physical/bleed query only runs when `onlyDispellableByMe` is true (since plain `HARMFUL` already includes them).

- [ ] **Step 4: Verify in-game**

`/reload` — dispellable debuff icon should appear with correct priority. Physical debuffs (bleeds) should still show.

- [ ] **Step 5: Commit**

```bash
git add Elements/Auras/Dispellable.lua
git commit -m "feat(dispellable): migrate to GetUnitAuras with RAID_PLAYER_DISPELLABLE"
```

---

### Task 6: LossOfControl Element Migration

Replace the iteration loop with `GetUnitAuras('HARMFUL|CROWD_CONTROL')`. Keep the CC type lookup table for color classification.

**Files:**
- Modify: `Elements/Status/LossOfControl.lua:91-122` (the `Update` function's iteration loop)

**Context:** The element scans for known CC spells to show an overlay with type-specific colors (red for stun, purple for MC, etc.). The new `CROWD_CONTROL` filter identifies CC auras server-side, but doesn't tell us the CC type. We keep `CC_SPELL_TYPES` as a type classifier only — it no longer drives filtering.

**Spec deviation:** The spec suggests `maxCount = 1` but we intentionally omit it — we need to see all CC auras to compare priorities (Stun > MC > Fear > Silence > Root) and display the highest-priority one.

- [ ] **Step 1: Replace the iteration loop in Update**

In `Elements/Status/LossOfControl.lua`, replace lines 97-122 (from `-- Scan unit debuffs` through `i = i + 1; end`) with:

```lua
	-- Scan for crowd control debuffs — server identifies CC auras
	local ccAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|CROWD_CONTROL')

	for _, auraData in next, ccAuras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			-- Look up CC type for color classification
			local ccType = CC_SPELL_TYPES[spellId]
			if(ccType) then
				-- Lower CC_TYPE value = higher priority
				if(bestPriority == nil or ccType < bestPriority) then
					bestPriority = ccType
					bestIcon     = auraData.icon
					bestExpiry   = auraData.expirationTime
				end
			else
				-- Unknown CC spell (not in our type table) — treat as generic stun
				if(bestPriority == nil or CC_TYPE.STUN < bestPriority) then
					bestPriority = CC_TYPE.STUN
					bestIcon     = auraData.icon
					bestExpiry   = auraData.expirationTime
				end
			end
		end
	end
```

**Note:** Spells returned by `CROWD_CONTROL` that aren't in our lookup table are treated as stuns (highest priority, red overlay) since we know they're CC but can't classify them further.

- [ ] **Step 2: Verify in-game**

`/reload` — CC overlays should display with correct colors when affected by stuns, fears, silences, roots, MC.

- [ ] **Step 3: Commit**

```bash
git add Elements/Status/LossOfControl.lua
git commit -m "feat(loss-of-control): migrate to GetUnitAuras('HARMFUL|CROWD_CONTROL')"
```

---

### Task 7: CrowdControl Element Migration

Replace the iteration loop with `GetUnitAuras('HARMFUL|CROWD_CONTROL|PLAYER')`. Remove the spell ID table and `IsCrowdControl` function.

**Files:**
- Modify: `Elements/Status/CrowdControl.lua:14-87` (spell table, `IsCrowdControl`, and `Update` iteration)

**Context:** The CrowdControl element tracks player-cast CC on enemy targets. The `CROWD_CONTROL|PLAYER` filter combo does both jobs — identifies CC auras AND filters to player-cast. This eliminates the need for `CC_SPELLS` table and `IsCrowdControl()` function.

- [ ] **Step 1: Remove the CC_SPELLS table and IsCrowdControl function**

In `Elements/Status/CrowdControl.lua`, delete everything from the `-- Known player-cast CC spell IDs` section header (line 10) through the end of the `IsCrowdControl` function (line 50). This removes the `CC_SPELLS` table and the `IsCrowdControl` function.

- [ ] **Step 2: Replace the iteration loop in Update**

In `Elements/Status/CrowdControl.lua`, in the `Update` function, replace the iteration block (from `-- Scan unit's debuffs for player-applied CC` through `i = i + 1; end`) with:

**Note:** Line numbers in this step refer to the file AFTER Step 1's deletion. Reference by content markers.

```lua
	-- Scan for player-cast crowd control debuffs
	local ccAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|CROWD_CONTROL|PLAYER')

	for _, auraData in next, ccAuras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			-- Take the first matching CC
			if(foundIcon == nil) then
				foundIcon   = auraData.icon
				foundExpiry = auraData.expirationTime
				foundCount  = auraData.applications or 1
			end
		end
	end
```

- [ ] **Step 3: Verify in-game**

`/reload` — CC tracker on enemy nameplates/targets should show player-cast CC spells with timer.

- [ ] **Step 4: Commit**

```bash
git add Elements/Status/CrowdControl.lua
git commit -m "feat(crowd-control): migrate to GetUnitAuras('HARMFUL|CROWD_CONTROL|PLAYER')"
```

---

### Task 8: Externals Element Migration

Replace the iteration loop with `GetUnitAuras('HELPFUL|EXTERNAL_DEFENSIVE')`. Add visibility mode (all/player/others) and source-based border color differentiation.

**Files:**
- Modify: `Elements/Auras/Externals.lua:13-99` (the `Update` function) and `Elements/Auras/Externals.lua:155-174` (the `Setup` function)

**Context:** Currently uses `F.Data.ExternalSpellIDs` table + `sourceUnit ~= 'player'` filter. The new API's `EXTERNAL_DEFENSIVE` filter replaces the spell table entirely. Visibility mode lets users choose all/player/others. Border color changes based on whether the aura was cast by the player (green) or someone else (yellow), determined via `C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)` with `|PLAYER` suffix — this avoids touching secret `sourceUnit`. This is the same API Cell uses (aliased as `_IsAuraFilteredOut` in Cell's UnitButton.lua:67).

- [ ] **Step 1: Remove the Data.ExternalSpellIDs dependency**

In `Elements/Auras/Externals.lua`, the `Update` function no longer references `F.Data.ExternalSpellIDs`. No import needed.

- [ ] **Step 2: Replace the Update function**

Replace the entire `Update` function (lines 13-100) with:

```lua
local function Update(self, event, unit)
	local element = self.FramedExternals
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local cfg = element._config
	local maxDisplayed   = cfg.maxDisplayed or 3
	local visibilityMode = cfg.visibilityMode or 'all'
	local playerColor    = cfg.playerColor or { 0, 0.8, 0 }
	local otherColor     = cfg.otherColor or { 1, 0.85, 0 }

	-- Build filter string based on visibility mode
	local filter = 'HELPFUL|EXTERNAL_DEFENSIVE'
	if(visibilityMode == 'player') then
		filter = 'HELPFUL|EXTERNAL_DEFENSIVE|PLAYER'
	end

	local rawAuras = C_UnitAuras.GetUnitAuras(unit, filter)

	-- Collect auras with source classification
	local auraList = {}
	for _, auraData in next, rawAuras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			-- Determine if player-cast via |PLAYER filter (avoids secret sourceUnit)
			local isPlayerCast = false
			if(visibilityMode == 'player') then
				-- All results are player-cast (filter already includes |PLAYER)
				isPlayerCast = true
			else
				-- Check via supplementary filter
				isPlayerCast = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
					unit, auraData.auraInstanceID, 'HELPFUL|EXTERNAL_DEFENSIVE|PLAYER')
			end

			-- Apply "others only" filter
			if(visibilityMode == 'others' and isPlayerCast) then
				-- Skip player-cast auras in "others" mode
			else
				auraList[#auraList + 1] = {
					spellId        = spellId,
					icon           = auraData.icon,
					duration       = auraData.duration,
					expirationTime = auraData.expirationTime,
					stacks         = auraData.applications or 0,
					isPlayerCast   = isPlayerCast,
				}
			end
		end
	end

	-- Display up to maxDisplayed using BorderIcon pool
	local count = math.min(#auraList, maxDisplayed)
	local pool = element._pool
	local iconSize = cfg.iconSize or 16
	local orientation = cfg.orientation or 'RIGHT'

	for idx = 1, count do
		local aura = auraList[idx]

		-- Lazily create pool entries
		if(not pool[idx]) then
			pool[idx] = F.Indicators.BorderIcon.Create(self, iconSize, {
				showCooldown = true,
				showStacks   = cfg.showStacks ~= false,
				showDuration = cfg.showDuration ~= false,
				frameLevel   = cfg.frameLevel or 5,
				stackFont    = cfg.stackFont,
				durationFont = cfg.durationFont,
			})
		end

		local bi = pool[idx]

		bi:ClearAllPoints()
		bi:SetSize(iconSize)

		-- Position
		local offset = (idx - 1) * (iconSize + 2)

		if(orientation == 'RIGHT') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', offset, 0)
		elseif(orientation == 'LEFT') then
			bi:SetPoint('TOPRIGHT', element._container, 'TOPRIGHT', -offset, 0)
		elseif(orientation == 'DOWN') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', 0, -offset)
		elseif(orientation == 'UP') then
			bi:SetPoint('BOTTOMLEFT', element._container, 'BOTTOMLEFT', 0, offset)
		end

		-- Set border color based on source
		local borderColor = aura.isPlayerCast and playerColor or otherColor
		if(bi.SetBorderColor) then
			bi:SetBorderColor(borderColor[1], borderColor[2], borderColor[3])
		end

		bi:SetAura(
			aura.spellId,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.stacks,
			nil
		)
		bi:Show()
	end

	-- Hide pool entries beyond active count
	for idx = count + 1, #pool do
		pool[idx]:Clear()
	end
end
```

- [ ] **Step 3: Update the Setup function doc comment**

In `Elements/Auras/Externals.lua`, update the Setup function's doc comment to reflect new config fields:

```lua
--- Create an Externals element on a unit frame.
--- Shows BorderIcons for external defensive buffs (Pain Suppression, Ironbark, etc.).
--- Supports visibility modes: 'all' (default), 'player', 'others'.
--- Border color differentiates player-cast (green) from other-cast (yellow).
--- Assigns result to self.FramedExternals, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: iconSize, maxDisplayed, showDuration,
---                       showStacks, orientation, anchor, frameLevel,
---                       stackFont, durationFont, visibilityMode,
---                       playerColor, otherColor
```

- [ ] **Step 4: Verify in-game**

`/reload` — external cooldown icons should appear on unit frames. With default "all" mode, both player-cast and other-cast externals should show with different border colors.

- [ ] **Step 5: Commit**

```bash
git add Elements/Auras/Externals.lua
git commit -m "feat(externals): migrate to GetUnitAuras with visibility mode + source colors"
```

---

### Task 9: Defensives Element Migration

Same pattern as Externals but with `BIG_DEFENSIVE` filter.

**Files:**
- Modify: `Elements/Auras/Defensives.lua:13-99` (the `Update` function) and `Elements/Auras/Defensives.lua:155-174` (the `Setup` function)

**Context:** Currently uses `F.Data.DefensiveSpellIDs` table + `sourceUnit == 'player'` filter. Identical migration pattern to Externals — replace spell table with `BIG_DEFENSIVE` filter, add visibility mode + source colors.

- [ ] **Step 1: Remove the Data.DefensiveSpellIDs dependency**

In `Elements/Auras/Defensives.lua`, the `Update` function no longer references `F.Data.DefensiveSpellIDs`. No import needed.

- [ ] **Step 2: Replace the Update function**

Replace the entire `Update` function (lines 13-100) with the same pattern as Externals Task 8, but using `BIG_DEFENSIVE` instead of `EXTERNAL_DEFENSIVE`:

```lua
local function Update(self, event, unit)
	local element = self.FramedDefensives
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local cfg = element._config
	local maxDisplayed   = cfg.maxDisplayed or 3
	local visibilityMode = cfg.visibilityMode or 'all'
	local playerColor    = cfg.playerColor or { 0, 0.8, 0 }
	local otherColor     = cfg.otherColor or { 1, 0.85, 0 }

	-- Build filter string based on visibility mode
	local filter = 'HELPFUL|BIG_DEFENSIVE'
	if(visibilityMode == 'player') then
		filter = 'HELPFUL|BIG_DEFENSIVE|PLAYER'
	end

	local rawAuras = C_UnitAuras.GetUnitAuras(unit, filter)

	-- Collect auras with source classification
	local auraList = {}
	for _, auraData in next, rawAuras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			-- Determine if player-cast via |PLAYER filter (avoids secret sourceUnit)
			local isPlayerCast = false
			if(visibilityMode == 'player') then
				isPlayerCast = true
			else
				isPlayerCast = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
					unit, auraData.auraInstanceID, 'HELPFUL|BIG_DEFENSIVE|PLAYER')
			end

			-- Apply "others only" filter
			if(visibilityMode == 'others' and isPlayerCast) then
				-- Skip player-cast auras in "others" mode
			else
				auraList[#auraList + 1] = {
					spellId        = spellId,
					icon           = auraData.icon,
					duration       = auraData.duration,
					expirationTime = auraData.expirationTime,
					stacks         = auraData.applications or 0,
					isPlayerCast   = isPlayerCast,
				}
			end
		end
	end

	-- Display up to maxDisplayed using BorderIcon pool
	local count = math.min(#auraList, maxDisplayed)
	local pool = element._pool
	local iconSize = cfg.iconSize or 16
	local orientation = cfg.orientation or 'RIGHT'

	for idx = 1, count do
		local aura = auraList[idx]

		if(not pool[idx]) then
			pool[idx] = F.Indicators.BorderIcon.Create(self, iconSize, {
				showCooldown = true,
				showStacks   = cfg.showStacks ~= false,
				showDuration = cfg.showDuration ~= false,
				frameLevel   = cfg.frameLevel or 5,
				stackFont    = cfg.stackFont,
				durationFont = cfg.durationFont,
			})
		end

		local bi = pool[idx]

		bi:ClearAllPoints()
		bi:SetSize(iconSize)

		local offset = (idx - 1) * (iconSize + 2)

		if(orientation == 'RIGHT') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', offset, 0)
		elseif(orientation == 'LEFT') then
			bi:SetPoint('TOPRIGHT', element._container, 'TOPRIGHT', -offset, 0)
		elseif(orientation == 'DOWN') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', 0, -offset)
		elseif(orientation == 'UP') then
			bi:SetPoint('BOTTOMLEFT', element._container, 'BOTTOMLEFT', 0, offset)
		end

		local borderColor = aura.isPlayerCast and playerColor or otherColor
		if(bi.SetBorderColor) then
			bi:SetBorderColor(borderColor[1], borderColor[2], borderColor[3])
		end

		bi:SetAura(
			aura.spellId,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.stacks,
			nil
		)
		bi:Show()
	end

	for idx = count + 1, #pool do
		pool[idx]:Clear()
	end
end
```

- [ ] **Step 3: Update the Setup function doc comment**

```lua
--- Create a Defensives element on a unit frame.
--- Shows BorderIcons for major personal defensive cooldowns
--- (Ice Block, Divine Shield, Shield Wall, etc.).
--- Supports visibility modes: 'all' (default), 'player', 'others'.
--- Border color differentiates player-cast (green) from other-cast (yellow).
--- Assigns result to self.FramedDefensives, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: iconSize, maxDisplayed, showDuration,
---                       showStacks, orientation, anchor, frameLevel,
---                       stackFont, durationFont, visibilityMode,
---                       playerColor, otherColor
```

- [ ] **Step 4: Verify in-game**

`/reload` — defensive cooldown icons should appear with correct border colors based on source.

- [ ] **Step 5: Commit**

```bash
git add Elements/Auras/Defensives.lua
git commit -m "feat(defensives): migrate to GetUnitAuras with visibility mode + source colors"
```

---

### Task 10: BorderIconSettings Builder — Visibility Mode + Color Pickers

Add opt-in visibility mode dropdown and two color pickers to the shared BorderIcon settings builder.

**Files:**
- Modify: `Settings/Builders/BorderIconSettings.lua:40-192`

**Context:** The `BorderIconSettings` builder is used by both the Externals and Defensives settings panels. Adding the visibility mode dropdown and color pickers here (behind opt-in flags) keeps DRY. Existing panels (Debuffs, RaidDebuffs, Dispellable) are unaffected because they don't pass the new flags.

- [ ] **Step 1: Add visibility mode dropdown section**

In `Settings/Builders/BorderIconSettings.lua`, after the `showDispellableByMe` block (after line 52) and before the `-- ── Display section` comment (line 54), add:

```lua
	-- ── Visibility Mode (Externals / Defensives) ────────────
	if(opts.showVisibilityMode) then
		local visLabel, visLabelH = Widgets.CreateHeading(parent, 'Visibility', 2)
		visLabel:ClearAllPoints()
		Widgets.SetPoint(visLabel, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - visLabelH

		local visCard, visInner, visCardY
		visCard, visInner, visCardY = Widgets.StartCard(parent, width, yOffset)

		local visDD = Widgets.CreateDropdown(visInner, WIDGET_W)
		visDD:SetItems({
			{ text = 'All',          value = 'all' },
			{ text = 'Player Only',  value = 'player' },
			{ text = 'Others Only',  value = 'others' },
		})
		visDD:SetValue(get('visibilityMode') or 'all')
		visDD:SetOnSelect(function(v) set('visibilityMode', v) end)
		visDD:ClearAllPoints()
		Widgets.SetPoint(visDD, 'TOPLEFT', visInner, 'TOPLEFT', 0, visCardY)
		visCardY = visCardY - DROPDOWN_H - C.Spacing.normal

		yOffset = Widgets.EndCard(visCard, parent, visCardY)
	end

	-- ── Source Colors (Externals / Defensives) ──────────────
	if(opts.showSourceColors and Widgets.CreateColorPicker) then
		local colorHeading, colorHeadingH = Widgets.CreateHeading(parent, 'Border Colors', 2)
		colorHeading:ClearAllPoints()
		Widgets.SetPoint(colorHeading, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - colorHeadingH

		local colorCard, colorInner, colorCardY
		colorCard, colorInner, colorCardY = Widgets.StartCard(parent, width, yOffset)

		-- Player-cast color
		local playerCP = Widgets.CreateColorPicker(colorInner, 'Player Cast')
		playerCP:ClearAllPoints()
		Widgets.SetPoint(playerCP, 'TOPLEFT', colorInner, 'TOPLEFT', 0, colorCardY)
		local savedPlayerColor = get('playerColor')
		if(savedPlayerColor) then
			playerCP:SetColor(savedPlayerColor[1], savedPlayerColor[2], savedPlayerColor[3])
		else
			playerCP:SetColor(0, 0.8, 0)
		end
		playerCP:SetOnColorChanged(function(r, g, b)
			set('playerColor', { r, g, b })
		end)
		colorCardY = colorCardY - playerCP:GetHeight() - C.Spacing.normal

		-- Other-cast color
		local otherCP = Widgets.CreateColorPicker(colorInner, 'Other Cast')
		otherCP:ClearAllPoints()
		Widgets.SetPoint(otherCP, 'TOPLEFT', colorInner, 'TOPLEFT', 0, colorCardY)
		local savedOtherColor = get('otherColor')
		if(savedOtherColor) then
			otherCP:SetColor(savedOtherColor[1], savedOtherColor[2], savedOtherColor[3])
		else
			otherCP:SetColor(1, 0.85, 0)
		end
		otherCP:SetOnColorChanged(function(r, g, b)
			set('otherColor', { r, g, b })
		end)
		colorCardY = colorCardY - otherCP:GetHeight() - C.Spacing.normal

		yOffset = Widgets.EndCard(colorCard, parent, colorCardY)
	end
```

- [ ] **Step 2: Verify in-game**

`/reload` — open the settings panel for Externals or Defensives. The new visibility mode dropdown and color pickers should not yet appear (panels haven't been updated to pass the flags). Existing Debuffs/RaidDebuffs panels should be unchanged.

- [ ] **Step 3: Commit**

```bash
git add Settings/Builders/BorderIconSettings.lua
git commit -m "feat(settings): add visibility mode + source color picker options to BorderIconSettings"
```

---

### Task 11: Externals and Defensives Settings Panels

Wire up the new visibility mode and color picker options in both settings panels.

**Files:**
- Modify: `Settings/Panels/Externals.lua` (the `create` function's `BorderIconSettings` call)
- Modify: `Settings/Panels/Defensives.lua` (the `create` function's `BorderIconSettings` call)

**Context:** Both panels delegate to `F.Settings.Builders.BorderIconSettings`. We just need to pass the new opt-in flags and update the description text.

- [ ] **Step 1: Update Externals panel**

In `Settings/Panels/Externals.lua`, change the description text and the `BorderIconSettings` opts:

Replace the description:
```lua
		descFS:SetText('External defensive cooldowns. Supports visibility modes: show all, player-cast only, or other-cast only. Border color differentiates source.')
```

Replace the `BorderIconSettings` call:
```lua
		yOffset = F.Settings.Builders.BorderIconSettings(content, width, yOffset, {
			unitType           = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party',
			configKey          = 'externals',
			showVisibilityMode = true,
			showSourceColors   = true,
		})
```

- [ ] **Step 2: Update Defensives panel**

In `Settings/Panels/Defensives.lua`, same changes:

Replace the description:
```lua
		descFS:SetText('Major personal defensive cooldowns. Supports visibility modes: show all, player-cast only, or other-cast only. Border color differentiates source.')
```

Replace the `BorderIconSettings` call:
```lua
		yOffset = F.Settings.Builders.BorderIconSettings(content, width, yOffset, {
			unitType           = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party',
			configKey          = 'defensives',
			showVisibilityMode = true,
			showSourceColors   = true,
		})
```

- [ ] **Step 3: Verify in-game**

`/reload` — open Settings > Externals and Settings > Defensives. Both should show:
1. Visibility dropdown with All/Player Only/Others Only
2. Border Colors section with Player Cast (green) and Other Cast (yellow) color pickers
3. All existing settings (icon size, max displayed, orientation, etc.) still present

- [ ] **Step 4: Commit**

```bash
git add Settings/Panels/Externals.lua Settings/Panels/Defensives.lua
git commit -m "feat(settings): wire up visibility mode + source colors for Externals and Defensives"
```
