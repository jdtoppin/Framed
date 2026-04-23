# Buffs AuraData Mutation Elimination Design

**Issue:** TBD (to be filed for the cf7fabb memory-regression in idle party/raid)
**Related:** #113 (the "show in both panels when sourceUnit is secret" fix — orthogonal, preserved as-is)
**Date:** 2026-04-22

## Goal

Stop mutating Blizzard's `AuraData` tables inside `Elements/Auras/Buffs.lua`'s `matchAura` closure. Source the same values from their native Blizzard fields (`applications`) and from the existing `unit` closure local. Drop the unused `dispelType` plumbing from the Buffs rendering path entirely.

## Background

Current code annotates every matched helpful aura with three Framed-owned keys:

```lua
auraData.unit       = unit
auraData.stacks     = auraData.applications
auraData.dispelType = auraData.dispelName
```

Those annotations surface as:

- `aura.unit` — forwarded to `C_UnitAuras.GetAuraDuration(unit, auraInstanceID)` inside `Icon:SetSpell`.
- `aura.stacks` — forwarded to `Icon:SetStacks` (in the ICON / ICONS dispatches), to `Bar:SetStacks` (BAR / BARS / RECTANGLE dispatches), and directly read inside `Bars:SetBars` and `Icons:SetIcons`.
- `aura.dispelType` — declared in `Icon:SetSpell`'s signature and documented, but **never read** inside its 408-line body. Dead parameter.

Complete production-code reader inventory (confirmed via `rg 'aura\.(stacks|unit|dispelType)'`):

- `Elements/Indicators/Bars.lua:39-40` — internal read inside `Bars:SetBars` loop
- `Elements/Indicators/Icons.lua:74, 80, 81` — internal reads inside `Icons:SetIcons` loop
- `Elements/Auras/Buffs.lua:264, 270, 271` — ICON dispatch (args 1, 7, 8 to `Icon:SetSpell`)
- `Elements/Auras/Buffs.lua:295` — BAR dispatch (direct `Bar:SetStacks` call)
- `Elements/Auras/Buffs.lua:358` — RECTANGLE dispatch (direct `Rectangle:SetStacks` call)

The annotation pattern is Buffs-specific. `Debuffs.lua`, `Externals.lua`, `Defensives.lua`, and `Dispellable.lua` already read `auraData.applications` / `auraData.dispelName` directly and never mutate.

### Why we're removing the mutation

Two motivations, stacked:

1. **Memory regression fix.** `cf7fabb` widens the helpful-aura query from `HELPFUL|RAID_IN_COMBAT` to plain `HELPFUL` whenever any enabled indicator has a non-empty `spells` list. With wider filter, Fort / Int / cosmetic / consumable / world buffs that Blizzard previously stripped server-side now flow through `matchAura` every `UNIT_AURA` tick — and every one gets mutated. The user's `SavedVariables` has custom spell lists on party-preset party frames (Rejuvenation tracking, `spells = { 774 }`), which triggered the widening. Bisect pinned the regression to cf7fabb; HEAD-solo vs cf7fabb-solo measured identical. Removing the mutation eliminates the only plausible Lua-invisible retention mechanism (Blizzard-side caching of enlarged `AuraData` tables) without reverting the filter-widening capability.

2. **Pre-existing hazard documented in `docs/superpowers/plans/2026-04-22-b3-buffs-classified.md:84`.** In the classified path, `entry.aura` is the same `AuraData` reference shared across consumers. Framed's in-place mutation leaks Framed-owned keys onto a shared object that any other consumer (present or future) may inspect. Removing the mutation removes the aliasing risk outright.

## Non-Goals

- **Changing filter semantics.** `computeBuffFilter` behavior is untouched. Users with custom spell lists still get the widened filter and non-RAID_IN_COMBAT visibility they opted into.
- **Option A (restore `buffFilterMode` as explicit config).** Separate future PR if Option C alone doesn't collapse the regression to baseline.
- **Debuffs / Externals / Defensives / Dispellable.** They don't use the annotation pattern. No changes.
- **BorderIcon widget.** It legitimately reads `dispelType` and is used by other elements; this PR doesn't touch it.

## Context

### Current call graph

```
Buffs:Update
  matchAura(auraData)  -- mutates auraData.unit/.stacks/.dispelType
    → appends to iconsAurasPool[idx] or matchedPool[idx]
  dispatch to renderers:
    ICONS      → Icons:SetIcons(list)               → internal loop reads aura.unit, aura.stacks, aura.dispelType
    ICON       → Icon:SetSpell(unit, ..., stacks, dispelType)  -- dispelType param is dead
    BAR        → Bar:SetStacks(aura.stacks)         (direct read in Buffs.lua:295)
    BARS       → Bars:SetBars(list)                 → internal loop reads aura.stacks (Bars.lua:39-40)
    RECTANGLE  → Rectangle:SetStacks(aura.stacks)   (direct read in Buffs.lua:358)
```

### Field equivalence

`AuraData.applications` (Blizzard-native, 12.0+ API) and `auraData.stacks` (Framed annotation) hold the same integer value. `.stacks` is a legacy rename from the pre-`C_UnitAuras` tuple-returning `UnitAura()` era. Embedded oUF already reads `.applications` directly (`Libs/oUF/elements/classpower.lua:117,122,203`).

## Design

### 1. `Elements/Auras/Buffs.lua`

**Delete both annotation blocks** inside `matchAura`:

```lua
-- before
if(not annotated) then
    auraData.unit      = unit
    auraData.stacks    = auraData.applications
    auraData.dispelType = auraData.dispelName
    annotated = true
end
```

— appearing once in the spell-lookup branch (lines 180-185) and once in the trackAll branch (lines 200-205). Drop the `annotated` local along with them.

**Update ICON dispatch (lines 260-276):**

```lua
-- before
renderer:SetSpell(
    aura.unit,
    aura.auraInstanceID,
    aura.spellId,
    aura.icon,
    aura.duration,
    aura.expirationTime,
    aura.stacks,
    aura.dispelType
)

-- after
renderer:SetSpell(
    unit,
    aura.auraInstanceID,
    aura.spellId,
    aura.icon,
    aura.duration,
    aura.expirationTime,
    aura.applications
)
```

The `dispelType` argument is dropped entirely (see Icon.lua change below).

**Update ICONS dispatch (line 253):**

```lua
-- before
renderer:SetIcons(list)

-- after
renderer:SetIcons(unit, list)
```

**Update BAR dispatch (Buffs.lua:295):**

```lua
-- before
if(aura.stacks) then renderer:SetStacks(aura.stacks) end

-- after
if(aura.applications) then renderer:SetStacks(aura.applications) end
```

**Update RECTANGLE dispatch (Buffs.lua:358):** identical substitution to BAR — `aura.stacks` → `aura.applications`. Uses the same `Rectangle:SetStacks` pattern.

**BARS dispatch (Buffs.lua:313):** no change to Buffs.lua — it already passes `list` to `Bars:SetBars`. The `.stacks` → `.applications` substitution happens inside `Bars.lua` (see §3 below).

### 2. `Elements/Indicators/Icons.lua`

**Signature change at line 17:**

```lua
-- before
function IconsMethods:SetIcons(auraList)

-- after
function IconsMethods:SetIcons(unit, auraList)
```

**Body changes:** inside the `for` loop, change the `icon:SetSpell` call (lines 73-82) to read the `unit` param instead of `aura.unit`, read `aura.applications` instead of `aura.stacks`, and drop the `aura.dispelType` argument:

```lua
-- before
icon:SetSpell(
    aura.unit,
    aura.auraInstanceID,
    aura.spellId,
    aura.icon,
    aura.duration,
    aura.expirationTime,
    aura.stacks,
    aura.dispelType
)

-- after
icon:SetSpell(
    unit,
    aura.auraInstanceID,
    aura.spellId,
    aura.icon,
    aura.duration,
    aura.expirationTime,
    aura.applications
)
```

Also update the LuaDoc comment at line 16 — drop `dispelType` from the `@param auraList` field list.

### 3. `Elements/Indicators/Bars.lua`

**Line 39-40:**

```lua
-- before
if(aura.stacks) then
    bar:SetStacks(aura.stacks)
end

-- after
if(aura.applications) then
    bar:SetStacks(aura.applications)
end
```

### 4. `Elements/Indicators/Icon.lua`

**Remove dead parameter at lines 29-30:**

```lua
-- before
--- @param dispelType string|nil Dispel/debuff type ('Magic', 'Curse', etc.)
function IconMethods:SetSpell(unit, auraInstanceID, spellID, iconTexture, duration, expirationTime, stacks, dispelType)

-- after
function IconMethods:SetSpell(unit, auraInstanceID, spellID, iconTexture, duration, expirationTime, stacks)
```

Both callers (`Buffs.lua:263` and `Icons.lua:73`) are updated in this same PR to match the new arity.

## Risk Analysis

**Correctness.** `aura.applications` is the Blizzard-native name for the same integer value Framed renamed to `aura.stacks`. No semantic change. The embedded oUF codebase already reads `.applications` directly for stack-driven logic — confirmed compatible with 12.0+ AuraData.

**Field collision.** `auraData.unit`, `.stacks`, `.dispelType` are Framed-owned annotations. Blizzard's `AuraData` struct doesn't ship those fields, and nothing else in Framed writes them. Deleting the writes also means any speculative reader of those specific keys on a Blizzard `AuraData` table stops finding them — but no such reader exists in the codebase (verified via grep: all reads are in the files listed above, and they're all being updated in this PR).

**`dispelType` cleanup affects other callers?** Icon:SetSpell has exactly two callers (`Buffs.lua:263` and `Icons.lua:73`). Both are updated in this PR. No external plugins depend on the Icon widget signature (Icon.lua is Framed-internal, not part of an exposed API surface).

**Secret-value handling.** `auraData.applications` can be a secret value in combat, same as `.stacks` was. The `renderer:SetStacks` methods already handle secret values correctly (they're C-level calls or Framed widgets that guard via `IsValueNonSecret`). No behavioral change.

**Ghost-aura class of bug.** Removing mutation cannot introduce ghost-aura issues — the mutation was never the mechanism preventing them. Ghost-aura prevention relies on the AuraState classified-entry pool invariants (#144), which this PR doesn't touch.

**Classified-path shared references.** `entry.aura` in the classified path is still the same `AuraData` reference as `_helpfulById[id]`. Post-PR, Framed no longer writes onto that shared object. Any other element reading `entry.aura.applications` / `.dispelName` / the unit-via-parameter path gets clean Blizzard-owned data. Aliasing hazard removed.

**Compound-unit defensiveness.** The outer `Update(self, event, unit, updateInfo)` captures `unit` once. `Icons:SetIcons(unit, list)` receives the same value. If `unit` is a compound token (e.g., mid-retarget transient), `C_UnitAuras.GetAuraDuration(unit, auraInstanceID)` inside `Icon:SetSpell` handles it — same as today.

## Test Gate

**Render correctness (manual):**
- Solo: player buffs render icons + stack counts for stackable buffs (e.g., a trinket proc).
- Party: party-member Rejuv (the user's tracked spell 774) renders with correct icon, duration, stack text.
- Mixed-renderer config: confirm ICONS / ICON / BAR / BARS indicator types all render correctly (user has configs exercising each).

**Memory regression check:**
- Pre-fix baseline: `/reload` with current HEAD, stand idle in a party with Fort+Int active, record `collectgarbage('count')` every 5 s for 30 s.
- Post-fix measurement: same conditions, confirm the per-second growth rate collapses toward 0.8.12 baseline. Direction is the criterion; absolute magnitude is informational.
- If growth persists: the retention mechanism is elsewhere. Next step is Option A (restore explicit `buffFilterMode` config) — separate PR.

**Regression replay:** reload with WeakAuras / MPlusQOL / AbilityTimeline loaded; combat entry + exit + target chains; zero `BugSack` errors.

**Merge criteria:** rendering parity verified, memory A/B shows the expected collapse (or the fallback path to Option A is filed), zero regression errors across the replay.

## References

- `cf7fabb` — the commit that introduced the regression
- `3890b20` — the independent "show when sourceUnit is secret" fix; unchanged by this PR
- `#155` — memory-optimization ranked fix list (Option C is a pre-existing hazard from the list, not a numbered item)
- `docs/superpowers/plans/2026-04-22-b3-buffs-classified.md:84` — prior documentation of the shared-reference hazard
- `Elements/Auras/Buffs.lua` — current annotation site
- `Elements/Indicators/Icons.lua` / `Icon.lua` / `Bars.lua` — consumers updated in this PR
