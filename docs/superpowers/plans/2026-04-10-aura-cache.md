# Aura Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate redundant `C_UnitAuras.GetUnitAuras` calls by caching results per `(unit, filter)` pair within each UNIT_AURA event cycle, reducing per-event memory allocations by ~60-70%.

**Architecture:** A single new module (`Core/AuraCache.lua`) exposes `F.AuraCache.GetUnitAuras(unit, filter)` as a drop-in replacement for the WoW API. It uses a generation counter per unit (bumped by a raw UNIT_AURA handler) to determine cache freshness. Nine aura elements each swap one line to use the cached version.

**Tech Stack:** WoW Lua, oUF framework, C_UnitAuras API

**Spec:** `docs/superpowers/specs/2026-04-10-aura-cache-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Core/AuraCache.lua` | Create | Generation-counter cache module |
| `Framed.toc` | Modify (line 35) | Add AuraCache.lua to load order |
| `Elements/Auras/Buffs.lua` | Modify (line 142) | Swap to cached query |
| `Elements/Auras/Defensives.lua` | Modify (line 35) | Swap to cached query |
| `Elements/Auras/Externals.lua` | Modify (line 35) | Swap to cached query |
| `Elements/Auras/MissingBuffs.lua` | Modify (line 161) | Swap to cached query |
| `Elements/Auras/Debuffs.lua` | Modify (lines 105, 129) | Swap to cached queries (2 calls) |
| `Elements/Auras/Dispellable.lua` | Modify (line 230) | Swap to cached query |
| `Elements/Status/CrowdControl.lua` | Modify (line 29) | Swap to cached query |
| `Elements/Status/LossOfControl.lua` | Modify (line 106) | Swap to cached query |

---

## Implementation Constraints

**Read the spec** (`docs/superpowers/specs/2026-04-10-aura-cache-design.md`) before starting any task.

- **Do not modify element rendering logic.** Each element's iteration, filtering, classification, and rendering code stays untouched. The only change per element is swapping the `C_UnitAuras.GetUnitAuras` call to `F.AuraCache.GetUnitAuras`.
- **Do not refactor, reorganize, or "improve" surrounding code.** No adding comments, no renaming variables, no restructuring files. One-line swap per element, nothing else.
- **Do not change how elements register for or handle UNIT_AURA events.** oUF's element dispatch stays as-is.

## Code Style

- Tabs for indentation
- Parenthesized conditions: `if(not x) then` not `if not x then`
- Single quotes for strings: `'HELPFUL'` not `"HELPFUL"`
- Iteration: `for _, v in next, tbl do` — never `pairs()` or `ipairs()`
- Namespace: `local _, Framed = ...` then `local F = Framed`

---

### Task 1: Create AuraCache module

**Files:**
- Create: `Core/AuraCache.lua`

- [ ] **Step 1: Create AuraCache.lua**

```lua
local _, Framed = ...
local F = Framed

F.AuraCache = {}

-- Generation counter per unit — bumped on each UNIT_AURA event.
local generation = {}

-- Cache keyed by 'unit\0filter' — each entry is { gen = number, result = table }.
-- Tables are reused across generations to avoid allocation.
local cache = {}

-- Raw frame to catch UNIT_AURA before oUF dispatches to elements.
local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('UNIT_AURA')
eventFrame:SetScript('OnEvent', function(_, _, unit)
	if(unit) then
		generation[unit] = (generation[unit] or 0) + 1
	end
end)

--- Drop-in replacement for C_UnitAuras.GetUnitAuras(unit, filter).
--- Returns the cached result if another element already queried the same
--- (unit, filter) pair during this UNIT_AURA cycle.
--- @param unit string
--- @param filter string
--- @return table
function F.AuraCache.GetUnitAuras(unit, filter)
	local gen = generation[unit] or 0
	local key = unit .. '\0' .. filter
	local entry = cache[key]

	if(entry and entry.gen == gen) then
		return entry.result
	end

	local result = C_UnitAuras.GetUnitAuras(unit, filter)

	if(entry) then
		-- Reuse existing table to avoid allocation
		entry.gen = gen
		entry.result = result
	else
		cache[key] = { gen = gen, result = result }
	end

	return result
end
```

- [ ] **Step 2: Commit**

```bash
git add Core/AuraCache.lua
git commit -m "feat: add AuraCache module for query deduplication"
```

---

### Task 2: Add AuraCache to TOC load order

**Files:**
- Modify: `Framed.toc:35`

- [ ] **Step 1: Add AuraCache.lua after CastTracker.lua in the TOC**

In `Framed.toc`, after line 35 (`Core/CastTracker.lua`), add:

```
Core/AuraCache.lua
```

The Core section should now read:

```
# Core
Init.lua
Core/Constants.lua
Core/ColorUtils.lua
Media/Media.lua
Core/SecretValues.lua
Core/DispelCapability.lua
Core/Utilities.lua
Core/EventBus.lua
Core/Config.lua
Core/CastTracker.lua
Core/AuraCache.lua
```

This ensures `F.AuraCache` is available before any Element files load.

- [ ] **Step 2: Commit**

```bash
git add Framed.toc
git commit -m "chore: add AuraCache.lua to TOC load order"
```

---

### Task 3: Migrate HELPFUL elements (Buffs, Defensives, Externals, MissingBuffs)

These four elements all query `HELPFUL` on the same unit. After this task, they share one cached API call instead of making four.

**Files:**
- Modify: `Elements/Auras/Buffs.lua:142`
- Modify: `Elements/Auras/Defensives.lua:35`
- Modify: `Elements/Auras/Externals.lua:35`
- Modify: `Elements/Auras/MissingBuffs.lua:161`

- [ ] **Step 1: Swap Buffs.lua**

In `Elements/Auras/Buffs.lua`, line 142, change:

```lua
	local auras = C_UnitAuras.GetUnitAuras(unit, buffFilter)
```

to:

```lua
	local auras = F.AuraCache.GetUnitAuras(unit, buffFilter)
```

Note: `buffFilter` is `'HELPFUL'` or `'HELPFUL|RAID_IN_COMBAT'` depending on config. Both values will be cached independently by the cache key.

- [ ] **Step 2: Swap Defensives.lua**

In `Elements/Auras/Defensives.lua`, line 35, change:

```lua
	local rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')
```

to:

```lua
	local rawAuras = F.AuraCache.GetUnitAuras(unit, 'HELPFUL')
```

- [ ] **Step 3: Swap Externals.lua**

In `Elements/Auras/Externals.lua`, line 35, change:

```lua
	local rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')
```

to:

```lua
	local rawAuras = F.AuraCache.GetUnitAuras(unit, 'HELPFUL')
```

- [ ] **Step 4: Swap MissingBuffs.lua**

In `Elements/Auras/MissingBuffs.lua`, line 161, change:

```lua
	local rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')
```

to:

```lua
	local rawAuras = F.AuraCache.GetUnitAuras(unit, 'HELPFUL')
```

- [ ] **Step 5: Commit**

```bash
git add Elements/Auras/Buffs.lua Elements/Auras/Defensives.lua Elements/Auras/Externals.lua Elements/Auras/MissingBuffs.lua
git commit -m "perf: migrate HELPFUL aura elements to AuraCache"
```

---

### Task 4: Migrate HARMFUL elements (Debuffs, Dispellable)

**Files:**
- Modify: `Elements/Auras/Debuffs.lua:105,129`
- Modify: `Elements/Auras/Dispellable.lua:230`

- [ ] **Step 1: Swap Debuffs.lua (first call)**

In `Elements/Auras/Debuffs.lua`, line 105, change:

```lua
	local rawAuras = C_UnitAuras.GetUnitAuras(unit, filter, nil, Enum.UnitAuraSortRule.Default)
```

to:

```lua
	local rawAuras = F.AuraCache.GetUnitAuras(unit, filter)
```

**Important:** The third and fourth arguments (`nil, Enum.UnitAuraSortRule.Default`) are dropped. `F.AuraCache.GetUnitAuras` passes only `(unit, filter)` to the underlying API. The `UnitAuraSortRule.Default` argument requests server-side sorting, but `GetUnitAuras` returns auras in default sort order regardless — `Default` is the default. Verify this does not change debuff display order during in-game testing.

- [ ] **Step 2: Swap Debuffs.lua (second call)**

In `Elements/Auras/Debuffs.lua`, line 129, change:

```lua
		local raidAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|RAID')
```

to:

```lua
		local raidAuras = F.AuraCache.GetUnitAuras(unit, 'HARMFUL|RAID')
```

- [ ] **Step 3: Swap Dispellable.lua**

In `Elements/Auras/Dispellable.lua`, line 230, change:

```lua
	local allAuras = C_UnitAuras.GetUnitAuras(unit, primaryFilter)
```

to:

```lua
	local allAuras = F.AuraCache.GetUnitAuras(unit, primaryFilter)
```

Note: `primaryFilter` is `'HARMFUL|RAID_PLAYER_DISPELLABLE'` or `'HARMFUL'` depending on config.

- [ ] **Step 4: Commit**

```bash
git add Elements/Auras/Debuffs.lua Elements/Auras/Dispellable.lua
git commit -m "perf: migrate HARMFUL aura elements to AuraCache"
```

---

### Task 5: Migrate Status elements (CrowdControl, LossOfControl)

**Files:**
- Modify: `Elements/Status/CrowdControl.lua:29`
- Modify: `Elements/Status/LossOfControl.lua:106`

- [ ] **Step 1: Swap CrowdControl.lua**

In `Elements/Status/CrowdControl.lua`, line 29, change:

```lua
	local ccAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|CROWD_CONTROL|PLAYER')
```

to:

```lua
	local ccAuras = F.AuraCache.GetUnitAuras(unit, 'HARMFUL|CROWD_CONTROL|PLAYER')
```

- [ ] **Step 2: Swap LossOfControl.lua**

In `Elements/Status/LossOfControl.lua`, line 106, change:

```lua
	local ccAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|CROWD_CONTROL')
```

to:

```lua
	local ccAuras = F.AuraCache.GetUnitAuras(unit, 'HARMFUL|CROWD_CONTROL')
```

- [ ] **Step 3: Commit**

```bash
git add Elements/Status/CrowdControl.lua Elements/Status/LossOfControl.lua
git commit -m "perf: migrate Status aura elements to AuraCache"
```

---

### Task 6: In-game verification

This is a manual testing task. Load into WoW and verify all aura elements render correctly.

- [ ] **Step 1: Sync to WoW addon folder and /reload**

The addon folder is symlinked. Run `/reload` in-game.

- [ ] **Step 2: Verify HELPFUL elements**

Test with a party/raid group:
- **Buffs:** Confirm buff indicators appear and update when buffs are gained/lost
- **Defensives:** Pop a defensive cooldown, confirm it appears on your frame
- **Externals:** Have a healer cast an external on you, confirm it appears
- **MissingBuffs:** Confirm missing raid buff icons appear when a class is in group but buff is missing

- [ ] **Step 3: Verify HARMFUL elements**

- **Debuffs:** Stand in something or get a debuff, confirm debuff icons appear with duration
- **Dispellable:** Get a dispellable debuff, confirm the dispel indicator shows
- **CrowdControl:** In PvP or with a friend, get CC'd and confirm the CC indicator appears
- **LossOfControl:** Same as CC — confirm the overlay appears

- [ ] **Step 4: Verify no lua errors**

Check `/framed` or BugSack for any errors related to AuraCache, nil results, or missing aura data.

- [ ] **Step 5: Spot-check memory**

Open `/fstack` or use a memory addon. Cast a few buffs/heals and check if per-cast memory growth has improved from ~0.03MB toward ~0.01MB.
