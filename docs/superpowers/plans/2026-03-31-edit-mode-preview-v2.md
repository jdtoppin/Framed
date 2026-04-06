# Edit Mode Preview System — Implementation Plan (v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace the dim-overlay-and-reveal edit mode behavior with pixel-perfect, config-driven preview frames that respond live to EditCache changes. Precede implementation with an aura testing pass to ensure the real aura elements are bug-free before building previews against them.

**Architecture:** Phase 0 is a manual testing pass for all aura group types (interactive, human-driven). Phases 1-5 build the preview system in layers: foundation → frame elements → group frames → aura indicator previews → polish. A unified `PreviewFrame` renderer reads config from EditCache and draws pixel-perfect visual representations. A `PreviewManager` orchestrates creation/destruction, handles group frame spawning with a count slider, and wires EditCache change events to live re-rendering. All preview frames are non-oUF visual-only config visualizations.

**Tech Stack:** WoW Frame API, BackdropTemplate, StatusBar, FontString, Texture, CooldownFrameTemplate. No oUF dependency for preview frames.

---

## Phased Approach

| Phase | Description | Depends On | Test Checkpoint |
|-------|------------|------------|-----------------|
| **0** | Secret Values & API Modernization | Nothing | All aura elements work in instanced combat (tainted paths); new APIs adopted |
| **0.5** | Aura Testing Pass | Phase 0 | All 11 aura group types verified in-game (validates secret-safe code in real gameplay) |
| **1** | Foundation | Phase 0.5 | Select frame → preview shows health/power/name, slider changes width live |
| **2** | Full Frame Elements | Phase 1 | Status icons, castbar, highlights render; settings update them live |
| **3** | Group Frames | Phase 2 | Party (5+pet), raid (10-40 slider), arena, boss preview correctly |
| **4** | Aura Indicator Previews | Phase 3 + Phase 0.5 | Aura indicators render from config, anchor changes move them, group dimming works |
| **5** | Polish & Version Bump | Phase 4 | Full integration test, version bump |

---

## Phase 0.5: Aura Testing Pass

> **This phase is interactive — human tests in-game, reports bugs, engineer fixes them.**
> Runs AFTER Phase 0 API modernization, so testing validates the secret-safe code in real gameplay.
> Use the HTML dashboard at `localhost:8080/plan.html` for the interactive checklist.

### Testing Protocol

For each aura group, test on the unit types where it's enabled by default (per `Presets/AuraDefaults.lua`).

**Every aura group must be tested twice:**
1. **Normal mode** — verify basic functionality works
2. **Secret CVar mode** — verify no Lua errors in tainted combat:
   ```
   /run SetCVar("secretCombatRestrictionsForced", 1)
   ```
   Enter combat with any mob. All aura fields become secret. Verify: no errors, icons still render (texture may degrade gracefully), cooldown swipes animate via DurationObject, stack counts display. Then disable:
   ```
   /run SetCVar("secretCombatRestrictionsForced", 0)
   ```

This validates the Phase 0 API modernization in real gameplay conditions, not just in the isolated Task 0F integration test.

### Aura Groups to Test

#### Buffs (`Elements/Auras/Buffs.lua`)
**Enabled on:** All unit types (Solo, Minimal, Group, Arena, Boss)
**Default indicator:** "My Buffs" — Icons type, castBy='me', 3 max, TOPLEFT anchor

- [x] **Test 1: Basic buff display on player frame**
  - Cast a self-buff (e.g., Devotion Aura, Blessing of the Bronze)
  - Verify: icon appears at TOPLEFT of frame, cooldown swipe if applicable, stack count if applicable

- [x] **Test 2: castBy='me' filtering**
  - Have another player buff you (Fort, AI, MotW)
  - Verify: other players' buffs do NOT show in "My Buffs" indicator
  - Change indicator castBy to 'anyone' in settings
  - Verify: other players' buffs now appear

- [x] **Test 3: Multiple indicators on same frame**
  - Add a second indicator (e.g., "Party Buffs" with castBy='others')
  - Verify: both indicators render without overlapping

- [x] **Test 4: Indicator types beyond Icons**
  - Test each indicator type: ICON (single), BAR, BARS, BORDER, RECTANGLE, OVERLAY
  - Verify: each type renders correctly with its configured visual

- [x] **Test 5: Settings panel controls**
  - Change iconWidth/iconHeight via settings
  - Change anchor point
  - Toggle showCooldown, showStacks
  - Verify: preview updates reflect changes

- [x] **Test 6: hideUnimportantBuffs (party/raid only)**
  - In a group, verify unimportant buffs are filtered out when flag is true

#### Debuffs (`Elements/Auras/Debuffs.lua`)
**Enabled on:** All unit types
**Filter:** `HARMFUL` with server-side sorting

- [x] **Test 7: Basic debuff display on target frame**
  - Target a mob, apply DoTs (or target a debuffed unit)
  - Verify: debuff icons appear at BOTTOMLEFT anchor

- [x] **Test 8: Boss aura size scaling**
  - In a dungeon/raid, check debuffs from bosses
  - Verify: boss auras render at bigIconSize (18px) vs regular iconSize (14px)

- [x] **Test 9: Duration text and cooldown animation**
  - Apply a DoT, verify duration countdown text appears
  - Verify cooldown swipe animation runs

- [x] **Test 10: onlyDispellableByMe filtering**
  - Toggle onlyDispellableByMe in settings
  - Verify: only debuffs you can dispel are shown (if healing class)

- [x] **Test 11: Stack count display**
  - Find a stacking debuff (e.g., dungeon mechanic)
  - Verify: stack number renders on the icon

#### Raid Debuffs (`Elements/Auras/RaidDebuffs.lua`)
**Enabled on:** Group (party/raid)
**Filter:** `HARMFUL|RAID`

- [x] **Test 12: Raid debuff display in dungeon/raid**
  - In instanced content, verify raid-relevant debuffs appear at CENTER anchor
  - Verify priority sorting (higher priority debuffs shown first)

- [x] **Test 13: bigIconSize for IMPORTANT+ priority**
  - Verify high-priority debuffs render at bigIconSize

- [x] **Test 14: Settings: maxDisplayed, iconSize**
  - Change maxDisplayed to 1 vs 3, verify correct count shown

#### Dispellable (`Elements/Auras/Dispellable.lua`)
**Enabled on:** Group (party/raid), Arena
**Shows:** Highest-priority dispellable debuff + health bar overlay

- [x] **Test 15: Dispellable icon display**
  - In a group, have party member get a dispellable debuff
  - Verify: icon appears at configured anchor (BOTTOMRIGHT for group)

- [x] **Test 16: Health bar overlay highlight**
  - Verify: health bar shows colored overlay matching dispel type (Magic=blue, Curse=purple, Disease=brown, Poison=green)
  - Test all 4 highlightType options: gradient_full, gradient_half, solid_current, solid_entire

- [x] **Test 17: Priority ordering**
  - If unit has multiple dispellable debuffs, verify highest priority shows (Magic > Curse > Disease > Poison > Physical)

- [x] **Test 18: onlyDispellableByMe filtering**
  - Toggle setting, verify only your class's dispellable types show

#### Externals (`Elements/Auras/Externals.lua`)
**Enabled on:** Group (party/raid)
**Filter:** `HELPFUL|EXTERNAL_DEFENSIVE`

- [x] **Test 19: External defensive display**
  - Cast an external defensive on a party member (Pain Sup, Ironbark, BoP, etc.)
  - Verify: icon appears at RIGHT anchor with correct icon texture

- [x] **Test 20: Source color differentiation**
  - Verify: your externals show with playerColor (green), others' with otherColor (yellow)

- [x] **Test 21: visibilityMode filtering**
  - Test 'all', 'player', 'others' modes
  - Verify: correct filtering in each mode

#### Defensives (`Elements/Auras/Defensives.lua`)
**Enabled on:** Group (party/raid)
**Filter:** `HELPFUL|BIG_DEFENSIVE`

- [x] **Test 22: Defensive cooldown display**
  - Pop a personal defensive (Divine Shield, Icebound Fort, Barkskin, etc.)
  - Verify: icon appears at LEFT anchor

- [x] **Test 23: Source color differentiation**
  - Same as externals — player green, others yellow

- [x] **Test 24: visibilityMode filtering**
  - Test all 3 modes

#### Missing Buffs (`Elements/Auras/MissingBuffs.lua`)
**Enabled on:** Group (party/raid) — disabled by default
**Shows:** Glowing icons when a raid buff is missing AND the providing class is in group

- [x] **Test 25: Enable missing buffs, join group without all buff classes**
  - Enable in settings
  - Join a group missing a buff class (e.g., no Mage = missing AI)
  - Verify: glowing icon appears for the missing buff

- [x] **Test 26: Buff class present but buff not applied**
  - Have a Mage in group who hasn't cast AI
  - Verify: missing buff icon shows

- [x] **Test 27: Buff applied → icon disappears**
  - Mage casts AI
  - Verify: icon disappears

- [x] **Test 28: Glow type and color**
  - Test different glowType options (Pixel, Proc, Soft, Shine)
  - Verify glow renders correctly

#### Private Auras (`Elements/Auras/PrivateAuras.lua`)
**Enabled on:** Group (party/raid)
**API:** `C_UnitAuras.AddPrivateAuraAnchor`

- [x] **Test 29: Private aura anchor placement**
  - In content with private auras (M+ affixes, raid mechanics)
  - Verify: private aura renders at configured anchor (TOP, 0, -3)

- [x] **Test 30: Graceful degradation if API unavailable**
  - Verify: no errors if C_UnitAuras.AddPrivateAuraAnchor doesn't exist

#### Targeted Spells (`Elements/Auras/TargetedSpells.lua`)
**Enabled on:** Group (party/raid)
**Source:** F.CastTracker (not aura API)

- [x] **Test 31: Incoming cast indicator**
  - In PvP or dungeon, have enemy cast on a party member
  - Verify: spell icon appears on the target's frame

- [x] **Test 32: Display modes — Icons, BorderGlow, Both**
  - Test each displayMode
  - Verify: Icons shows icon, BorderGlow shows glow, Both shows both

- [x] **Test 33: Glow settings**
  - Adjust glow type, color, frequency
  - Verify: glow renders with new settings

#### Loss of Control (`Elements/Status/LossOfControl.lua`)
**Enabled on:** All unit types — disabled by default
**Shows:** Large icon when unit is CC'd

- [x] **Test 34: Enable LoC, get stunned/feared in PvP or dungeon**
  - Verify: large icon appears at CENTER

- [x] **Test 35: Type filtering**
  - Disable specific types (e.g., uncheck 'root')
  - Verify: roots no longer show LoC icon

#### Crowd Control (`Elements/Status/CrowdControl.lua`)
**Enabled on:** All unit types — disabled by default
**Shows:** Icon for specific tracked CC spells on the target

- [x] **Test 36: Enable CC tracking, add a spell to track**
  - Add a CC spell (e.g., Polymorph, Fear, Sap)
  - Apply it to target
  - Verify: icon appears at CENTER

- [x] **Test 37: Custom spell list**
  - Add/remove spells from the tracking list
  - Verify: only tracked spells show

---

## Phase 0: Secret Values & API Modernization

> **Critical first step.** Our aura elements currently read raw AuraData fields (`duration`, `expirationTime`, `applications`, `spellId`, `dispelName`) and branch on them. In instanced content (M+, rated PvP, raids), tainted execution paths make these fields **secret values**. Branching on secrets (`if duration > 0`) causes Lua errors. We must migrate to the 12.0.0/12.0.1 secret-safe APIs before testing or the preview system.

### API Audit — Current State

**What we use correctly:**
- `C_UnitAuras.GetUnitAuras(unit, filter)` — all elements
- `F.IsValueNonSecret()` wrapping `issecretvalue()` — all elements check `spellId` and `dispelName`
- `C_UnitAuras.IsAuraFilteredOutByInstanceID()` — Externals, Defensives (player-cast detection via filter trick)
- `'HELPFUL|EXTERNAL_DEFENSIVE'` filter — Externals
- `'HELPFUL|BIG_DEFENSIVE'` filter — Defensives
- `'HARMFUL|RAID_PLAYER_DISPELLABLE'` filter — Dispellable, Debuffs
- `'HARMFUL|CROWD_CONTROL'` filter — LossOfControl, CrowdControl
- `C_UnitAuras.AddPrivateAuraAnchor()` — PrivateAuras (fully C-level, no Lua aura data)

**What breaks in tainted combat:**

| Issue | Where | Problem | Fix |
|-------|-------|---------|-----|
| `duration > 0` branch | `BorderIcon.lua:75` | `duration` is secret → error | Use `C_UnitAuras.GetAuraDuration()` directly — if it returns a non-nil `DurationObject`, the aura has a duration. `DoesAuraHaveExpirationTime` is `SecretWhenUnitAuraRestricted` so don't use it as a pre-check. |
| `SetCooldown(startTime, duration)` with raw numbers | `BorderIcon.lua:76-77` | **12.0.1 removed** `SetCooldown`, `SetCooldownFromExpirationTime`, `SetCooldownDuration`, `SetCooldownUNIX` for tainted code with secret values. Only `SetCooldownFromDurationObject` remains. | Use `C_UnitAuras.GetAuraDuration()` → `DurationObject` → `SetCooldownFromDurationObject()` — this is now the **only** cooldown API that works in tainted combat |
| `expirationTime - GetTime()` in OnUpdate | `BorderIcon.lua:15-32` | `expirationTime` may be secret | **Resolved:** Removed custom duration text entirely. Use Blizzard's built-in cooldown countdown numbers via `SetCooldownFromDurationObject()` + `SetHideCountdownNumbers(false)`. Secret-safe, no Lua math needed. `DurationObject:GetClockTime()` exists but returns secret values that can't be formatted in Lua — not usable for text display. |
| `count > 1` branch for stacks | `BorderIcon.lua:85` | `applications` may be secret | Use `C_UnitAuras.GetAuraApplicationDisplayCount()` |
| `auraData.applications or 0` | All aura elements | Value may be secret, `or` branches | Pass through without branching; use display count API |
| `auraData.duration` / `auraData.expirationTime` stored raw | All aura elements | Fields may be secret | Store `auraInstanceID` (NeverSecret) and defer to C-level APIs |
| `auraData.isBossAura` branch for sizing | `Debuffs.lua:104` | May be secret | Use `C_Spell.IsPriorityAura()` (AllowedWhenTainted) or check at setup time |

### Implementation Considerations

**1. `DoesAuraHaveExpirationTime` returns a potentially-secret boolean.** It's marked `SecretWhenUnitAuraRestricted`. So even the "safe check" `if(F.IsValueNonSecret(hasExpiration) and hasExpiration)` may get a secret result. Safer approach: always try `GetAuraDuration()` and check if the DurationObject is non-nil, rather than pre-checking with `DoesAuraHaveExpirationTime`.

**2. `GetAuraDataByAuraInstanceID` is `AllowedWhenUntainted`.** In tainted paths we can't look up individual aura data by instance ID. However, the display-oriented APIs (`GetAuraDuration`, `GetAuraApplicationDisplayCount`, `GetAuraDispelTypeColor`) need their taint annotations verified during implementation. If any are also `AllowedWhenUntainted`, the "defer to C-level" strategy needs adjustment for those specific calls.

**3. Icon textures work with secrets.** `auraData.icon` may be secret, but `SetTexture()` is a C-level widget API that accepts secret values (same as `SetValue()`, `SetStatusBarColor()`). The texture renders correctly — you just can't branch on the value in Lua. So icon display is not a concern.

**4. Dispel color overlays are secret-safe via `GetAuraDispelTypeColor`.** We already use `C_CurveUtil.CreateColorCurve()` in oUF's auras.lua, Icon.lua, Health.lua, and LiveUpdate. The pattern: create a dispel color curve with `C_CurveUtil.CreateColorCurve()` + `SetType(Enum.LuaCurveType.Step)` + add points from `oUF.colors.dispel`. Then call `GetAuraDispelTypeColor(unit, auraInstanceID, curve)` → returns `colorRGBA` → pass to `SetVertexColor()` / `SetColorTexture()`. Fully C-level in, C-level out. This replaces the manual `C.Colors.dispel[dispelName]` lookup that branches on the potentially-secret `dispelName`. Works for both BorderIcon border coloring AND the Dispellable health bar gradient overlay.

**5. The `or` operator on secrets causes errors.** `auraData.applications or 0` evaluates truthiness of `applications`, which is a "boolean test" — prohibited on secret values in tainted code.

**6. Health/Power elements (out of scope but noted).** `UnitHealth`, `UnitPower`, `UnitHealthMax` values are also potentially secret (`ShouldUnitHealthMaxBeSecret`, `ShouldUnitPowerBeSecret` exist). Our oUF Health/Power elements likely branch on these. This is outside Phase 0 aura scope but will need addressing before the addon is fully combat-safe in instanced content.

### New APIs to Adopt

| API | Purpose | Secret Safety | Where to Use |
|-----|---------|--------------|--------------|
| `C_UnitAuras.GetAuraDuration(unit, auraInstanceID)` | Returns `DurationObject` for cooldown frames | Secret-safe (widget binding) | BorderIcon cooldown swipe |
| `DurationObject:GetClockTime()` (12.0.1) | Get remaining time for text display | Returns secret values — **not usable** for Lua formatting (`math.ceil`, `string.format` fail on secrets). Blizzard's countdown numbers via `SetHideCountdownNumbers(false)` are the correct approach instead. | ~~BorderIcon duration text~~ — do NOT use |
| `C_UnitAuras.GetAuraApplicationDisplayCount(unit, id, min, max)` | Formatted stack string | Secret-safe | BorderIcon stack text |
| `C_UnitAuras.DoesAuraHaveExpirationTime(unit, id)` | Safe boolean: does aura expire? | **`SecretWhenUnitAuraRestricted`** — return value can be secret; unreliable as pre-check. Skip it; use `GetAuraDuration()` directly and check for non-nil DurationObject instead. | ~~Replace `duration > 0` check~~ — superseded by direct `GetAuraDuration()` approach |
| `C_Spell.IsPriorityAura(spellId)` | High-priority aura classification | AllowedWhenTainted | Debuff/RaidDebuff sort priority |
| `C_Spell.IsSpellImportant(spellId)` | Important spell classification | AllowedWhenTainted | Already in CastTracker; add to aura filtering |
| `C_UnitAuras.TriggerPrivateAuraShowDispelType(show)` | Show dispel type on private auras | Secret-safe | PrivateAuras element enhancement |
| `C_UnitAuras.GetAuraDispelTypeColor(unit, id, curve)` | Dispel color via curve | Secret-safe | BorderIcon border coloring (replace manual lookup) |
| `C_UnitAuras.GetAuraBaseDuration(unit, id)` | Base duration (pre-haste) | Available | Threshold calculations |
| `C_Spell.GetVisibilityInfo(spellId, type)` | Raid frame visibility rules | AllowedWhenUntainted | Buff filtering (hideUnimportantBuffs) |

### Key Principle: Store `auraInstanceID`, Defer to C-Level

The `auraInstanceID` field is explicitly **NeverSecret**. Our aura elements should:
1. Query auras via `GetUnitAuras()` — returns AuraData with `auraInstanceID`
2. Store the `auraInstanceID` (safe to branch on, use as table key)
3. Use C-level APIs with `(unit, auraInstanceID)` for display: `GetAuraDuration()`, `GetAuraApplicationDisplayCount()`, `GetAuraDispelTypeColor()`, `DoesAuraHaveExpirationTime()`
4. Pass `DurationObject` directly to `CooldownFrame:SetCooldownFromDurationObject()`
5. Only branch on raw AuraData fields after `F.IsValueNonSecret()` check

### Enum Confirmation

`Enum.UnitAuraSortRule` **confirmed to exist** (12.0.0):

| Value | Name | Description |
|-------|------|-------------|
| 0 | Unsorted | No sorting |
| 1 | Default | Player-applied first, then castable, then by instance ID |
| 2 | BigDefensive | Other-player-applied first, expiration longest→shortest |
| 3 | Expiration | Player first, castable first, soonest→longest, permanent last |
| 4 | ExpirationOnly | Expiration time only |
| 5 | Name | Player first, castable first, spell name, instance ID |
| 6 | NameOnly | Spell name only |

`Enum.UnitAuraSortDirection`: `Normal` (0), `Reverse` (1)

### Available Filter Strings (12.0.0 + 12.0.1)

| Filter | Version | Used By Us? |
|--------|---------|-------------|
| `HELPFUL` | Legacy | Yes — Buffs, MissingBuffs |
| `HARMFUL` | Legacy | Yes — Debuffs |
| `PLAYER` | Legacy | Yes — via IsAuraFilteredOutByInstanceID |
| `RAID` | Legacy | Yes — RaidDebuffs, Dispellable supplement |
| `EXTERNAL_DEFENSIVE` | 12.0.0 | Yes — Externals |
| `BIG_DEFENSIVE` | 12.0.1 | Yes — Defensives |
| `CROWD_CONTROL` | 12.0.1 | Yes — LossOfControl, CrowdControl |
| `RAID_PLAYER_DISPELLABLE` | 12.0.1 | Yes — Dispellable, Debuffs |
| `IMPORTANT` | 12.0.1 | **No — could use for priority display** |
| `RAID_IN_COMBAT` | 12.0.1 | **No — could use for hideUnimportantBuffs** |
| `CANCELABLE` / `NOT_CANCELABLE` | Legacy | No |

### Secret Testing CVars

For local testing without entering instanced content:
- `secretCombatRestrictionsForced 1` — Force secrets in any combat
- `secretChallengeModeRestrictionsForced 1` — Force secrets like M+
- `secretEncounterRestrictionsForced 1` — Force secrets like raid encounters
- `secretPvPMatchRestrictionsForced 1` — Force secrets like rated PvP

Use these to verify our elements survive tainted paths before going live.

### Task 0A: Modernize BorderIcon Duration/Stacks (Secret-Safe)

**Files:**
- Modify: `Elements/Indicators/BorderIcon.lua`

This is the critical path — BorderIcon is used by Debuffs, RaidDebuffs, Externals, Defensives, Dispellable, TargetedSpells, MissingBuffs.

- [x] **Step 0: Verify taint annotations on C-level display APIs**

Before building around these APIs, verify their taint annotations in the 12.0.0/12.0.1 API source. The "store auraInstanceID, defer to C-level" strategy depends on these being callable in tainted paths:

| API | Expected | If Restricted |
|-----|----------|---------------|
| `C_UnitAuras.GetAuraDuration(unit, id)` | Should work (returns DurationObject for widget binding) | Entire cooldown strategy breaks — would need raw `SetCooldownFromDurationObject` from AuraData somehow |
| `C_UnitAuras.GetAuraApplicationDisplayCount(unit, id, min, max)` | Should work (display-oriented) | Fall back to hiding stack text in tainted combat |
| `C_UnitAuras.GetAuraDispelTypeColor(unit, id, curve)` | Should work (returns color for widget binding) | Fall back to no dispel coloring in tainted combat |
| `C_UnitAuras.DoesAuraHaveExpirationTime(unit, id)` | `SecretWhenUnitAuraRestricted` — **already confirmed unreliable**, skip it |

Check the local API source at `docs/api/` or the warcraft.wiki.gg annotation pages. If `GetAuraDuration` is restricted, we need an alternative strategy before proceeding.

- [x] **Step 1: Update SetAura to accept and store unit + auraInstanceID**

Change the `SetAura` signature to include `unit` and `auraInstanceID` so the indicator can call C-level APIs:

```lua
function indicator:SetAura(unit, auraInstanceID, spellId, iconTexture, duration, expirationTime, count, dispelType)
```

Store `self._unit` and `self._auraInstanceID` for use by duration/stacks APIs.

- [x] **Step 2: Replace cooldown swipe with DurationObject**

**Critical context:** 12.0.1 **removed** `SetCooldown`, `SetCooldownFromExpirationTime`, `SetCooldownDuration`, and `SetCooldownUNIX` for tainted code with secret values. `SetCooldownFromDurationObject` is now the **only** way to configure cooldown frames in tainted combat. This migration is mandatory, not optional.

Additionally, `DoesAuraHaveExpirationTime` is `SecretWhenUnitAuraRestricted` — its return value can itself be secret, making it unreliable as a pre-check. Skip it and go straight to `GetAuraDuration()`.

Replace:
```lua
-- OLD: branches on potentially-secret duration/expirationTime
-- AND uses SetCooldown which is REMOVED for tainted code in 12.0.1
if(durationSafe and expirationSafe and duration and duration > 0 ...) then
    self.cooldown:SetCooldown(startTime, duration)
```

With:
```lua
-- NEW: secret-safe via C-level DurationObject
-- SetCooldownFromDurationObject is the ONLY cooldown API available in tainted combat
if(unit and auraInstanceID) then
    local durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
    if(durationObj) then
        self.cooldown:SetCooldownFromDurationObject(durationObj)
    else
        self.cooldown:Clear()
    end
end
```

- [x] **Step 3: Duration text — use Blizzard's built-in cooldown countdown**

**DO NOT** use `DurationObject:GetClockTime()` or custom `expirationTime - GetTime()` OnUpdate handlers for duration text. `GetClockTime()` returns secret values that cannot be formatted in Lua (`math.ceil`, `string.format`, `SetFormattedText('%d')` all fail on secrets). Custom duration FontStrings and OnUpdate tickers are unnecessary.

**Correct approach:** Use Blizzard's built-in cooldown countdown numbers:
```lua
cooldown:SetHideCountdownNumbers(not showDuration) -- toggle via config
cooldown:SetCooldownFromDurationObject(durationObj) -- drives both swipe and countdown
```
The `showDuration` config controls whether countdown numbers are visible. Font, size, outline, and shadow can be customized on the countdown's text region. This is the same approach Cell uses on Midnight.

- [x] **Step 4: Replace stack count with GetAuraApplicationDisplayCount**

Replace:
```lua
-- OLD: branches on potentially-secret count
if(count and count > 1) then
    self.stackText:SetText(count)
```

With:
```lua
-- NEW: secret-safe formatted string
if(self._unit and self._auraInstanceID) then
    local displayCount = C_UnitAuras.GetAuraApplicationDisplayCount(
        self._unit, self._auraInstanceID, 2, 99)
    self.stackText:SetText(displayCount or '')
    self.stackText:SetShown(displayCount ~= nil and displayCount ~= '')
end
```

- [x] **Step 5: Replace manual dispel color lookup with GetAuraDispelTypeColor**

Investigate replacing `C.Colors.dispel[dispelType]` with `C_UnitAuras.GetAuraDispelTypeColor()` if a suitable ColorCurve is available. If not, keep the manual lookup (which already guards with `IsValueNonSecret`).

- [x] **Step 6: Run tests, commit**

```bash
git add Elements/Indicators/BorderIcon.lua
git commit -m "feat: modernize BorderIcon to use secret-safe aura APIs"
```

### Task 0B: Update All Aura Elements to Pass unit + auraInstanceID

**Files:**
- Modify: `Elements/Auras/Debuffs.lua`
- Modify: `Elements/Auras/RaidDebuffs.lua`
- Modify: `Elements/Auras/Externals.lua`
- Modify: `Elements/Auras/Defensives.lua`
- Modify: `Elements/Auras/Dispellable.lua`
- Modify: `Elements/Auras/TargetedSpells.lua`
- Modify: `Elements/Auras/MissingBuffs.lua`

Each element currently builds an `aura` table from AuraData and passes fields to `BorderIcon:SetAura()`. Update to:
1. Include `auraInstanceID` in the aura table (it's NeverSecret)
2. Pass `unit` and `auraInstanceID` to the updated `SetAura` signature
3. Remove raw `duration`/`expirationTime`/`applications` from the aura table where possible (defer to C-level)
4. Keep `spellId` and `icon` in aura table (needed for texture, and already guarded by IsValueNonSecret)

**`GetUnitAuraInstanceIDs` optimization:** For elements that only track player-cast auras (Buffs `castBy='me'`), use `C_UnitAuras.GetUnitAuraInstanceIDs(unit, filter)` instead of `GetUnitAuras`. It returns only `auraInstanceID` values (all NeverSecret) and supports server-side sorting via `Enum.UnitAuraSortRule`. This is lighter and fully taint-safe for player-applied auras. However, it's `AllowedWhenTainted` only for player-applied auras — for elements that need to see ALL auras on a unit (Debuffs, Dispellable, etc.), stick with `GetUnitAuras` for discovery + `auraInstanceID` pivot for display.

- [x] **Step 1: Update Debuffs.lua**

Store `auraInstanceID` from `auraData.auraInstanceID` (NeverSecret). Update `SetAura` call:
```lua
bi:SetAura(unit, aura.auraInstanceID, aura.spellId, aura.icon,
    aura.duration, aura.expirationTime, aura.stacks, aura.dispelType)
```

- [x] **Step 2: Update RaidDebuffs.lua** — same pattern

- [x] **Step 3: Update Externals.lua** — same pattern

- [x] **Step 4: Update Defensives.lua** — same pattern

- [x] **Step 5: Update Dispellable.lua** — same auraInstanceID pattern for the single best aura, PLUS replace the health bar overlay highlight. The current code branches on `dispelName` (potentially secret) to look up overlay color from a Lua table. Replace with `C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)` → pass returned color directly to `SetVertexColor()` / `SetColorTexture()`. This is C-level in, C-level out — works for all highlightType options (gradient, solid, border). Create or share a dispel color curve (oUF's `auras.dispelColorCurve` pattern).

- [x] **Step 6: Update TargetedSpells.lua** — uses CastTracker, not aura API; may not have auraInstanceID. Verify and handle gracefully (fallback to raw values if no instance ID).

- [x] **Step 7: Update MissingBuffs.lua** — shows missing buffs (not applied), so no auraInstanceID. Keep raw fallback path.

- [x] **Step 8: Run full test suite, commit**

```bash
git add Elements/Auras/*.lua Elements/Indicators/BorderIcon.lua
git commit -m "feat: pass auraInstanceID through all aura elements for secret-safe display"
```

### Task 0C: Modernize Buffs Indicator System (Secret-Safe)

**Files:**
- Modify: `Elements/Auras/Buffs.lua`
- Modify: `Elements/Indicators/Icon.lua`
- Modify: `Elements/Indicators/Icons.lua`
- Modify: `Elements/Indicators/Bar.lua`
- Modify: `Elements/Indicators/Bars.lua`
- Modify: `Elements/Indicators/BorderGlow.lua`
- Modify: `Elements/Indicators/Color.lua`
- Modify: `Elements/Indicators/Overlay.lua`

Buffs uses a different system from Debuffs — it has a multi-indicator architecture with 7 renderer types. Each renderer receives aura data and sets its own visuals. The same secret-value concerns apply.

- [x] **Step 1: Audit each indicator renderer for secret-unsafe branches**

Check each renderer's display methods for branches on `duration`, `expirationTime`, `stacks`. Document which ones need changes.

- [x] **Step 2: Update Icon.lua** — linear depletion bar uses `SetTimerDuration` or OnUpdate fallback. Migrate to DurationObject approach.

- [x] **Step 3: Update Bar.lua** — StatusBar depletion. Same migration.

- [x] **Step 4: Update Icons.lua** — grid of Icons. Passes through to Icon, so may inherit fixes.

- [x] **Step 5: Update Bars.lua** — grid of Bars. Same.

- [x] **Step 6: Update BorderGlow.lua** — duration-based alpha fade. Uses raw `expirationTime`.

- [x] **Step 7: Update Color.lua and Overlay.lua** — threshold color changes may branch on duration.

- [x] **Step 8: Update Buffs.lua** — pass `unit` + `auraInstanceID` through matched/iconsAuras tables to renderers.

- [x] **Step 9: Run tests, commit**

```bash
git add Elements/Auras/Buffs.lua Elements/Indicators/*.lua
git commit -m "feat: modernize buff indicator renderers for secret-safe display"
```

### Task 0D: Filter-Mode Settings & Server-Side Filtering

**Files:**
- Modify: `Elements/Auras/Debuffs.lua`
- Modify: `Elements/Auras/RaidDebuffs.lua`
- Modify: `Elements/Auras/Buffs.lua`
- Modify: `Presets/AuraDefaults.lua`
- Modify: `Settings/Panels/Debuffs.lua`
- Modify: `Settings/Panels/Buffs.lua`

**Why filter modes instead of blacklists:** In instanced combat (M+, rated PvP, raids), `spellId` is secret on other players' frames. Blacklisting requires `if(blacklist[spellId])` which uses a secret value as a table key — Lua error. The only viable filtering in instanced content is server-side via filter strings (`HARMFUL|RAID`, `IMPORTANT`, etc.), because the C-level does the filtering before data reaches Lua.

**Design:** Expose filter mode choices as settings dropdowns. The filter string is built at query time from the config, no spell-level branching needed.

- [x] **Step 1: Add `filterMode` config key to Debuffs**

Add to `Presets/AuraDefaults.lua` debuff configs:
```lua
filterMode = 'all',  -- 'all' | 'raid' | 'important' | 'dispellable'
```

Map to filter strings in `Debuffs.lua` Update:
```lua
local FILTER_MAP = {
    all          = 'HARMFUL',
    raid         = 'HARMFUL|RAID',
    important    = 'HARMFUL|IMPORTANT',
    dispellable  = 'HARMFUL|RAID_PLAYER_DISPELLABLE',
    raidCombat   = 'HARMFUL|RAID_IN_COMBAT',
}
local filter = FILTER_MAP[cfg.filterMode] or 'HARMFUL'
rawAuras = C_UnitAuras.GetUnitAuras(unit, filter)
```

The existing `onlyDispellableByMe` config key becomes redundant for the `dispellable` mode — consider deprecating in favor of the unified filterMode.

- [x] **Step 2: Add `filterMode` settings dropdown to Debuffs panel**

Replace the `onlyDispellableByMe` checkbox with a dropdown:
- All Debuffs
- Raid-Relevant Only
- Important Only
- Dispellable Only
- Raid (In-Combat)

- [x] **Step 3: Add server-side sorting via `Enum.UnitAuraSortRule`**

Now that we've confirmed the enum exists, add sorting back to Debuffs (was removed during debugging):
```lua
rawAuras = C_UnitAuras.GetUnitAuras(unit, filter, nil, Enum.UnitAuraSortRule.Default)
```

This is particularly valuable because `IsPriorityAura`-based Lua sorting won't work in combat (branches on secret `spellId`), but `UnitAuraSortRule.Default` does the same prioritization at the C level.

- [x] **Step 4: Add `buffFilterMode` for Buffs**

Add to buff config:
```lua
buffFilterMode = 'all',  -- 'all' | 'raidCombat'
```

Map `'raidCombat'` to `'HELPFUL|RAID_IN_COMBAT'` for the `hideUnimportantBuffs` use case — replaces the current Lua-side duration-based filtering (which branches on potentially-secret `duration` and `canApplyAura`).

`GetVisibilityInfo` is `AllowedWhenUntainted` so it can't be used in tainted paths. The `RAID_IN_COMBAT` filter string is the combat-safe equivalent.

- [x] **Step 5: Test IMPORTANT filter for RaidDebuffs**

Test whether `'HARMFUL|RAID|IMPORTANT'` narrows to the most relevant debuffs. If useful, add as a filterMode option for RaidDebuffs. May supplement or eventually replace the RaidDebuffs registry for content where the registry hasn't been updated yet.

- [x] **Step 6: Commit**

```bash
git add Elements/Auras/Debuffs.lua Elements/Auras/RaidDebuffs.lua Elements/Auras/Buffs.lua \
    Presets/AuraDefaults.lua Settings/Panels/Debuffs.lua Settings/Panels/Buffs.lua
git commit -m "feat: add filter-mode settings using server-side filter strings for combat-safe aura filtering"
```

### Task 0E: Enhance Private Auras with Dispel Type Display

**Files:**
- Modify: `Elements/Auras/PrivateAuras.lua`

- [x] **Step 1: Research TriggerPrivateAuraShowDispelType behavior**

Test in-game: call `C_UnitAuras.TriggerPrivateAuraShowDispelType(true)` and verify if it causes the private aura anchor to show dispel-colored borders.

- [x] **Step 2: Wire to Dispellable element**

If functional, trigger dispel type display when the Dispellable element is enabled on the same frame. This gives healers dispel info even for private auras.

- [x] **Step 3: Add config key**

Add `privateAuras.showDispelType` to `Presets/AuraDefaults.lua` defaults so settings can control this.

- [x] **Step 4: Commit**

```bash
git add Elements/Auras/PrivateAuras.lua Presets/AuraDefaults.lua
git commit -m "feat: add private aura dispel type display"
```

### Task 0F: Secret Values Integration Testing

- [x] **Step 1: Enable secret testing CVar**

```
/run SetCVar("secretCombatRestrictionsForced", 1)
```

- [x] **Step 2: Enter combat with any mob**

All aura fields now become secret. Verify:
- No Lua errors in any aura element
- Debuffs still show icons (texture may be blank if spellId is secret — acceptable degradation)
- Duration swipes still animate via DurationObject
- Stack counts display via GetAuraApplicationDisplayCount
- Dispellable highlights still trigger
- Externals/Defensives still show

- [x] **Step 3: Test in M+ or rated PvP (real instanced content)**

This is the real verification. All aura elements must survive without errors.

- [x] **Step 4: Disable testing CVar**

```
/run SetCVar("secretCombatRestrictionsForced", 0)
```

- [x] **Step 5: Commit any final fixes**

### Config Keys to Add (SavedVariables)

New config keys needed in `Presets/AuraDefaults.lua` or `Presets/Defaults.lua`:

| Key | Default | Purpose |
|-----|---------|---------|
| `debuffs.filterMode` | `'all'` | Filter mode: `all` / `raid` / `important` / `dispellable` / `raidCombat` |
| `buffs.buffFilterMode` | `'all'` | Filter mode for buffs: `all` / `raidCombat` |
| `privateAuras.showDispelType` | `true` | Enable dispel type display on private auras |

> **Note on `onlyDispellableByMe`:** The existing `debuffs.onlyDispellableByMe` boolean becomes redundant when `filterMode = 'dispellable'` achieves the same result via server-side filtering. Consider deprecating it in favor of the unified filterMode, or keeping it as a modifier within the `dispellable` mode (i.e., `RAID_PLAYER_DISPELLABLE` vs `HARMFUL` + Lua-side dispel check). The key difference: `RAID_PLAYER_DISPELLABLE` is class-aware at the C level and works in tainted combat; the old Lua-side check doesn't.

> **Note on blacklisting:** Spell-level blacklists (`blacklist[spellId]`) are not viable in instanced combat because `spellId` is secret on other players' frames — using it as a table key causes a Lua error. All debuff filtering must use server-side filter strings. The filter mode dropdown is the combat-safe replacement for per-spell control.

---

## Phase 1: Foundation

### File Structure

```
Preview/
  Preview.lua            — KEEP: existing sidebar preview
  PreviewFrame.lua       — NEW: config-driven preview frame renderer (~400 lines)
  PreviewManager.lua     — NEW: lifecycle, group spawning, live updates (~350 lines)

EditMode/
  ClickCatchers.lua      — MODIFY: z-ordering for preview layer
  EditCache.lua          — MODIFY: fire EDIT_CACHE_VALUE_CHANGED on Set()
```

### Task 1: Fire EDIT_CACHE_VALUE_CHANGED from EditCache

**Files:**
- Modify: `EditMode/EditCache.lua:43-48`

- [x] **Step 1: Add event fire to EditCache.Set()**

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

- [x] **Step 2: Verify no existing callsites break**

Run: `grep -rn 'EditCache.Set(' EditMode/ Settings/ Units/`
The event fire is additive — no listener exists yet. Confirm no callsite depends on Set() being silent.

- [x] **Step 3: Commit**

```bash
git add EditMode/EditCache.lua
git commit -m "feat: fire EDIT_CACHE_VALUE_CHANGED event from EditCache.Set"
```

---

### Task 2: Build PreviewFrame Renderer — Frame Shell, Health, Power

**Files:**
- Create: `Preview/PreviewFrame.lua`
- Modify: `Framed.toc`

Build the core renderer that draws a visual frame from config. Pixel-perfect: uses the same textures, fonts, and sizing as StyleBuilder.

- [x] **Step 1: Create PreviewFrame.lua with frame shell + health bar + power bar**

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.PreviewFrame = {}

-- Class colors (reuse oUF's colors when available)
local function getClassColor(class)
	local oUF = F.oUF
	if(oUF and oUF.colors and oUF.colors.class and oUF.colors.class[class]) then
		local c = oUF.colors.class[class]
		return c[1], c[2], c[3]
	end
	return 0.5, 0.5, 0.5
end

local POWER_COLOR = { 0.0, 0.44, 0.87, 1 }  -- Match oUF mana override

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

	-- Health text (pixel-perfect: match StyleBuilder font, anchor, outline, shadow)
	local hc = config.health
	if(hc and hc.showText ~= false) then
		local text = Widgets.CreateFontString(wrapper, hc.fontSize, C.Colors.textActive)
		text:SetFont(F.Media.GetActiveFont(), hc.fontSize, hc.outline or '')
		if(hc.shadow ~= false) then
			text:SetShadowOffset(1, -1)
			text:SetShadowColor(0, 0, 0, 1)
		end
		local anchor = hc.textAnchor or 'RIGHT'
		text:SetPoint(anchor, wrapper, anchor, (hc.textAnchorX or 0) + 1, hc.textAnchorY or 0)
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

	if(config.power and config.power.position == 'top') then
		wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
		wrapper:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
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
	if(pc and pc.showText) then
		local text = Widgets.CreateFontString(wrapper, pc.fontSize, C.Colors.textActive)
		text:SetFont(F.Media.GetActiveFont(), pc.fontSize, pc.outline or '')
		if(pc.shadow ~= false) then
			text:SetShadowOffset(1, -1)
			text:SetShadowColor(0, 0, 0, 1)
		end
		local anchor = pc.textAnchor or 'CENTER'
		text:SetPoint(anchor, wrapper, anchor, (pc.textAnchorX or 0) + 1, pc.textAnchorY or 0)
		frame._powerText = text
	end
end

-- ============================================================
-- Name text builder
-- ============================================================

local function BuildNameText(frame, config, fakeUnit)
	if(config.name and config.name.showName == false) then return end
	local nc = config.name
	if(not nc) then return end

	local text = Widgets.CreateFontString(frame, nc.fontSize, C.Colors.textActive)
	text:SetFont(F.Media.GetActiveFont(), nc.fontSize, nc.outline or '')
	if(nc.shadow ~= false) then
		text:SetShadowOffset(1, -1)
		text:SetShadowColor(0, 0, 0, 1)
	end

	local anchor = frame._healthWrapper or frame
	local pt = nc.anchor or 'LEFT'
	text:SetPoint(pt, anchor, pt, nc.anchorX or 0, nc.anchorY or 0)
	text:SetText(fakeUnit and fakeUnit.name or 'Unit Name')

	-- Color mode
	if(nc.colorMode == 'class' and fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		text:SetTextColor(r, g, b, 1)
	elseif(nc.colorMode == 'custom' and nc.customColor) then
		text:SetTextColor(nc.customColor[1], nc.customColor[2], nc.customColor[3], 1)
	end

	frame._nameText = text
end

-- ============================================================
-- Public: Create preview frame
-- ============================================================

function F.PreviewFrame.Create(parent, config, fakeUnit)
	local frame = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(frame, config.width, config.height)

	-- Dark background (match StyleBuilder)
	local bg = frame:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(frame)
	local bgC = C.Colors.background
	bg:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 1)
	frame._bg = bg

	-- Calculate bar heights
	local powerHeight = (config.power and config.power.height) or 8
	local healthHeight = config.height - powerHeight

	-- Build structural elements
	BuildHealthBar(frame, config, healthHeight)
	BuildPowerBar(frame, config, powerHeight)
	BuildNameText(frame, config, fakeUnit)

	-- Apply fake unit data
	if(fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		frame._healthBar:SetStatusBarColor(r, g, b, 1)
		frame._healthBar:SetValue(fakeUnit.healthPct or 1)
		if(frame._healthText) then
			frame._healthText:SetText(math.floor((fakeUnit.healthPct or 1) * 100) .. '%')
		end
		if(frame._powerBar) then
			frame._powerBar:SetValue(fakeUnit.powerPct or 0.8)
		end
		if(frame._powerText) then
			frame._powerText:SetText(math.floor((fakeUnit.powerPct or 0.8) * 100) .. '%')
		end
	end

	frame._config = config
	frame._fakeUnit = fakeUnit
	return frame
end
```

- [x] **Step 2: Add to Framed.toc after Preview/Preview.lua**

```
# Preview
Preview/Preview.lua
Preview/PreviewFrame.lua
```

- [x] **Step 3: Commit**

```bash
git add Preview/PreviewFrame.lua Framed.toc
git commit -m "feat: add PreviewFrame renderer with health, power, name"
```

---

### Task 3: Build PreviewManager — Solo Frame Preview

**Files:**
- Create: `Preview/PreviewManager.lua`
- Modify: `Framed.toc`

The manager creates/destroys preview frames on selection, wires EditCache events to live updates.

- [x] **Step 1: Create PreviewManager.lua**

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
local previewFrames = {}
local previewContainer = nil

-- Solo frame fake unit data
local function getPlayerClass()
	local _, class = UnitClass('player')
	return class or 'PALADIN'
end

local SOLO_FAKES = {
	player       = function() return { name = UnitName('player') or 'You', class = getPlayerClass(), healthPct = 1.0,  powerPct = 0.85 } end,
	target       = function() return { name = 'Target Dummy',  class = 'WARRIOR',  healthPct = 0.72, powerPct = 0.6  } end,
	targettarget = function() return { name = 'Healbot',       class = 'PRIEST',   healthPct = 0.90, powerPct = 0.8  } end,
	focus        = function() return { name = 'Focus Target',  class = 'MAGE',     healthPct = 0.55, powerPct = 0.45 } end,
	pet          = function() return { name = 'Pet',           class = 'HUNTER',   healthPct = 0.80, powerPct = 0.7  } end,
}

local GROUP_TYPES = { party = true, raid = true, arena = true, boss = true }

-- ============================================================
-- Config reading
-- ============================================================

local function getUnitConfig(frameKey)
	local preset = F.Settings.GetEditingPreset()
	local saved = F.Config:Get('presets.' .. preset .. '.unitConfigs.' .. frameKey)
	if(not saved) then return nil end
	local config = F.DeepCopy(saved)
	-- Overlay cached edits
	local edits = EditCache.GetEditsForFrame(frameKey)
	if(edits) then
		for path, value in next, edits do
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

-- ============================================================
-- Preview lifecycle
-- ============================================================

local function destroyPreviews()
	for _, pf in next, previewFrames do
		pf:Hide()
		pf:SetParent(nil)
	end
	previewFrames = {}
	activeFrameKey = nil
end

local function getPreviewContainer()
	if(not previewContainer) then
		local overlay = EditMode.GetOverlay()
		if(not overlay) then return nil end
		previewContainer = CreateFrame('Frame', nil, overlay)
		previewContainer:SetAllPoints(overlay)
		previewContainer:SetFrameLevel(overlay:GetFrameLevel() + 8)
	end
	previewContainer:Show()
	return previewContainer
end

-- ============================================================
-- Solo preview
-- ============================================================

local function showSoloPreview(frameKey)
	local container = getPreviewContainer()
	if(not container) then return end

	local config = getUnitConfig(frameKey)
	if(not config) then return end

	local fakeFn = SOLO_FAKES[frameKey]
	local fakeUnit = fakeFn and fakeFn() or { name = frameKey, class = 'WARRIOR', healthPct = 0.8, powerPct = 0.5 }

	local pf = F.PreviewFrame.Create(container, config, fakeUnit)

	-- Position at real frame location
	local x = EditCache.Get(frameKey, 'position.x') or (config.position and config.position.x) or 0
	local y = EditCache.Get(frameKey, 'position.y') or (config.position and config.position.y) or 0
	pf:SetPoint('CENTER', UIParent, 'CENTER', x, y)

	previewFrames[1] = pf
	pf:Show()
end

-- ============================================================
-- Public API
-- ============================================================

function PM.ShowPreview(frameKey)
	destroyPreviews()
	activeFrameKey = frameKey

	if(GROUP_TYPES[frameKey]) then
		showSoloPreview(frameKey)  -- Placeholder until Phase 3
	else
		showSoloPreview(frameKey)
	end
end

function PM.HidePreview()
	destroyPreviews()
end

function PM.GetActiveFrameKey()
	return activeFrameKey
end

-- ============================================================
-- Events
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

-- Live update from EditCache
F.EventBus:Register('EDIT_CACHE_VALUE_CHANGED', function(frameKey, configPath, value)
	if(frameKey ~= activeFrameKey) then return end
	-- Position changes → reposition only
	if(configPath == 'position.x' or configPath == 'position.y') then
		if(previewFrames[1]) then
			local config = getUnitConfig(frameKey)
			if(config) then
				local x = EditCache.Get(frameKey, 'position.x') or (config.position and config.position.x) or 0
				local y = EditCache.Get(frameKey, 'position.y') or (config.position and config.position.y) or 0
				previewFrames[1]:ClearAllPoints()
				previewFrames[1]:SetPoint('CENTER', UIParent, 'CENTER', x, y)
			end
		end
		return
	end
	-- Other changes → rebuild preview
	PM.ShowPreview(activeFrameKey)
end, 'PreviewManager.cacheChanged')
```

- [x] **Step 2: Add to Framed.toc**

```
Preview/PreviewFrame.lua
Preview/PreviewManager.lua
```

- [x] **Step 3: Commit**

```bash
git add Preview/PreviewManager.lua Framed.toc
git commit -m "feat: add PreviewManager with solo frame preview and live updates"
```

---

### Task 4: Wire ClickCatchers to Preview System

**Files:**
- Modify: `EditMode/ClickCatchers.lua`

Adjust z-ordering so preview renders above selected catcher. Store `_def` on each catcher for the event handler.

- [x] **Step 1: Store def reference on catcher**

In `CreateCatcher()`, after `catcher._isGroup = def.isGroup`, add:

```lua
catcher._def = def
```

- [x] **Step 2: Update EDIT_MODE_FRAME_SELECTED handler**

Replace the existing handler with z-ordering logic:

```lua
F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
	local overlay = EditMode.GetOverlay()
	for _, catcher in next, catchers do
		if(catcher._frameKey == frameKey) then
			ApplySelectedVisuals(catcher)
			-- Lower below preview (preview container is at overlay+8)
			catcher:SetFrameLevel(overlay:GetFrameLevel() + 6)
		else
			ApplyDefaultVisuals(catcher, catcher._def)
			-- Keep above preview so unselected frames stay clickable
			catcher:SetFrameLevel(overlay:GetFrameLevel() + 10)
		end
		catcher:Show()
	end
end, 'ClickCatchers')
```

- [x] **Step 3: Commit**

```bash
git add EditMode/ClickCatchers.lua
git commit -m "feat: wire click catchers to preview system with z-ordering"
```

---

### Task 5: Phase 1 Integration Test

- [x] **Step 1: Sync to WoW addon folder**

```bash
rsync -av --delete \
  --exclude='.git' --exclude='.worktrees' --exclude='.superpowers' \
  --exclude='.DS_Store' --exclude='docs/' \
  . "/Applications/World of Warcraft/_retail_/Interface/AddOns/Framed/"
```

- [x] **Step 2: Test in-game**
  - `/framed edit` — enter edit mode
  - Click player frame → preview shows with health bar, power bar, name
  - Click target frame → preview switches to target
  - Change width slider → preview resizes live
  - Change height slider → preview resizes live
  - Drag frame → preview follows
  - Exit edit mode → preview disappears

- [x] **Step 3: Fix any issues found**

- [x] **Step 4: Commit fixes**

```bash
git add -A
git commit -m "fix: phase 1 integration testing fixes"
```

---

## Phase 2: Full Frame Elements

### Task 6: Add Status Icons to PreviewFrame

**Files:**
- Modify: `Preview/PreviewFrame.lua`

- [x] **Step 1: Add BuildStatusIcons()**

11 icon types rendered as small gray placeholder squares at their configured positions:

```lua
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
			icon:SetColorTexture(0.4, 0.4, 0.4, 0.6)
			frame._statusIcons[key] = icon
		end
	end
end
```

- [x] **Step 2: Wire into Create() after BuildNameText**

```lua
BuildStatusIcons(frame, config)
```

- [x] **Step 3: Commit**

```bash
git add Preview/PreviewFrame.lua
git commit -m "feat: add status icon placeholders to PreviewFrame"
```

---

### Task 7: Add Castbar and Highlights to PreviewFrame

**Files:**
- Modify: `Preview/PreviewFrame.lua`

- [x] **Step 1: Add BuildCastbar()**

```lua
local function BuildCastbar(frame, config)
	if(not config.castbar) then return end
	local cb = config.castbar

	local wrapper = CreateFrame('Frame', nil, frame)
	local cbWidth = (cb.sizeMode == 'detached' and cb.width) or config.width
	wrapper:SetSize(cbWidth, cb.height or 16)
	wrapper:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', 0, -C.Spacing.base)

	local bgC = C.Colors.background
	local bgTex = wrapper:CreateTexture(nil, 'BACKGROUND')
	bgTex:SetAllPoints(wrapper)
	bgTex:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

	local bar = CreateFrame('StatusBar', nil, wrapper)
	bar:SetAllPoints(wrapper)
	bar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0.6)
	local ac = C.Colors.accent
	bar:SetStatusBarColor(ac[1], ac[2], ac[3], 0.8)

	local label = Widgets.CreateFontString(wrapper, C.Font.sizeSmall, C.Colors.textActive)
	label:SetPoint('LEFT', wrapper, 'LEFT', 4, 0)
	label:SetText('Casting...')

	frame._castbar = wrapper
end
```

- [x] **Step 2: Add BuildHighlights()**

```lua
local function BuildHighlights(frame, config)
	if(config.targetHighlight) then
		local thColor = F.Config and F.Config:Get('general.targetHighlightColor')
		local thWidth = F.Config and F.Config:Get('general.targetHighlightWidth') or 1

		local hl = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
		hl:SetPoint('TOPLEFT', frame, 'TOPLEFT', -thWidth, thWidth)
		hl:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', thWidth, -thWidth)
		local c = thColor or { 1, 1, 1, 0.8 }
		hl:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = thWidth })
		hl:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 0.8)
		frame._targetHighlight = hl
	end
end
```

- [x] **Step 3: Wire both into Create()**

```lua
BuildCastbar(frame, config)
BuildHighlights(frame, config)
```

- [x] **Step 4: Commit**

```bash
git add Preview/PreviewFrame.lua
git commit -m "feat: add castbar and highlight borders to PreviewFrame"
```

---

### Task 8: Add UpdateFromConfig for Live Rebuilds

**Files:**
- Modify: `Preview/PreviewFrame.lua`

- [x] **Step 1: Add Destroy() helper**

```lua
local function DestroyChildren(frame)
	for _, child in next, { frame:GetChildren() } do
		child:Hide()
		child:SetParent(nil)
	end
	-- Clear textures
	local texKeys = { '_bg', '_healthText', '_powerText', '_nameText', '_targetHighlight' }
	for _, key in next, texKeys do
		if(frame[key]) then
			if(frame[key].Hide) then frame[key]:Hide() end
			frame[key] = nil
		end
	end
	if(frame._statusIcons) then
		for _, icon in next, frame._statusIcons do icon:Hide() end
		frame._statusIcons = nil
	end
	frame._healthWrapper = nil
	frame._healthBar = nil
	frame._powerWrapper = nil
	frame._powerBar = nil
	frame._castbar = nil
	frame._auraGroups = nil
end
```

- [x] **Step 2: Add UpdateFromConfig method to Create()**

Before the return in `F.PreviewFrame.Create()`:

```lua
function frame:UpdateFromConfig(config)
	DestroyChildren(self)
	Widgets.SetSize(self, config.width, config.height)

	-- Rebuild background
	local bg = self:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(self)
	local bgC = C.Colors.background
	bg:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 1)
	self._bg = bg

	-- Rebuild all elements
	local powerHeight = (config.power and config.power.height) or 8
	local healthHeight = config.height - powerHeight
	BuildHealthBar(self, config, healthHeight)
	BuildPowerBar(self, config, powerHeight)
	BuildNameText(self, config, self._fakeUnit)
	BuildStatusIcons(self, config)
	BuildCastbar(self, config)
	BuildHighlights(self, config)

	-- Re-apply fake unit
	if(self._fakeUnit) then
		local r, g, b = getClassColor(self._fakeUnit.class)
		self._healthBar:SetStatusBarColor(r, g, b, 1)
		self._healthBar:SetValue(self._fakeUnit.healthPct or 1)
		if(self._healthText) then
			self._healthText:SetText(math.floor((self._fakeUnit.healthPct or 1) * 100) .. '%')
		end
		if(self._powerBar) then
			self._powerBar:SetValue(self._fakeUnit.powerPct or 0.8)
		end
	end

	self._config = config
end
```

- [x] **Step 3: Commit**

```bash
git add Preview/PreviewFrame.lua
git commit -m "feat: add UpdateFromConfig for live preview rebuilds"
```

---

### Task 9: Phase 2 Integration Test

- [x] **Step 1: Sync and test**
  - Status icons appear at correct positions
  - Castbar renders below frame (only for unit types with castbar config)
  - Target highlight border visible on player preview
  - Changing castbar height/width in settings updates preview
  - Toggling showCastBar removes/adds castbar from preview

- [x] **Step 2: Fix issues, commit**

---

## Phase 3: Group Frames

### Task 10: Add Group Frame Preview to PreviewManager

**Files:**
- Modify: `Preview/PreviewManager.lua`

- [x] **Step 1: Add group constants and fake units**

```lua
local GROUP_FRAME_COUNTS = {
	party = 5,
	raid  = 20,
	arena = 3,
	boss  = 4,
}

local GROUP_FAKES = nil  -- Lazy-init from Preview.GetFakeUnits
```

- [x] **Step 2: Implement showGroupPreview()**

```lua
local function showGroupPreview(frameKey)
	local container = getPreviewContainer()
	if(not container) then return end

	local config = getUnitConfig(frameKey)
	if(not config) then return end

	if(not GROUP_FAKES) then
		GROUP_FAKES = F.Preview.GetFakeUnits(5)
	end

	local count = GROUP_FRAME_COUNTS[frameKey] or 5

	-- Layout params
	local orientation = config.orientation or 'vertical'
	local anchorPoint = config.anchorPoint or 'TOPLEFT'
	local spacing = config.spacing or 2
	local isVertical = (orientation == 'vertical')
	local stepX = isVertical and 0 or (config.width + spacing)
	local stepY = isVertical and -(config.height + spacing) or 0

	if(anchorPoint == 'TOPRIGHT' or anchorPoint == 'BOTTOMRIGHT') then stepX = -stepX end
	if(anchorPoint == 'BOTTOMLEFT' or anchorPoint == 'BOTTOMRIGHT') then stepY = -stepY end

	local baseX = EditCache.Get(frameKey, 'position.x') or (config.position and config.position.x) or 0
	local baseY = EditCache.Get(frameKey, 'position.y') or (config.position and config.position.y) or 0

	for i = 1, count do
		local fakeUnit = GROUP_FAKES[((i - 1) % #GROUP_FAKES) + 1]
		local varied = {
			name = fakeUnit.name .. (i > #GROUP_FAKES and (' ' .. i) or ''),
			class = fakeUnit.class,
			healthPct = math.max(0.1, (fakeUnit.healthPct or 0.8) - (i * 0.03)),
			powerPct = fakeUnit.powerPct or 0.5,
		}

		local pf = F.PreviewFrame.Create(container, config, varied)
		local offX = (i - 1) * stepX
		local offY = (i - 1) * stepY
		pf:SetPoint(anchorPoint, UIParent, 'CENTER', baseX + offX, baseY + offY)
		previewFrames[i] = pf
		pf:Show()
	end
end
```

- [x] **Step 3: Add party pet frame**

After the main party loop, add a single pet frame if `frameKey == 'party'`:

```lua
	-- Party pet preview (single frame showing how pets render)
	if(frameKey == 'party') then
		local petConfig = getUnitConfig('pet')
		if(petConfig) then
			local petFake = { name = 'Party Pet', class = 'HUNTER', healthPct = 0.75, powerPct = 0.6 }
			local petPf = F.PreviewFrame.Create(container, petConfig, petFake)
			-- Position after last party frame
			local petOffX = count * stepX
			local petOffY = count * stepY
			petPf:SetPoint(anchorPoint, UIParent, 'CENTER', baseX + petOffX, baseY + petOffY)
			previewFrames[count + 1] = petPf
			petPf:Show()
		end
	end
```

- [x] **Step 4: Wire into PM.ShowPreview replacing placeholder**

```lua
function PM.ShowPreview(frameKey)
	destroyPreviews()
	activeFrameKey = frameKey

	if(GROUP_TYPES[frameKey]) then
		showGroupPreview(frameKey)
	else
		showSoloPreview(frameKey)
	end
end
```

- [x] **Step 5: Update EDIT_CACHE_VALUE_CHANGED for group layout changes**

```lua
-- Replace position-only block with:
if(configPath == 'position.x' or configPath == 'position.y'
	or configPath == 'spacing' or configPath == 'orientation' or configPath == 'anchorPoint') then
	PM.ShowPreview(activeFrameKey)
	return
end
```

- [x] **Step 6: Commit**

```bash
git add Preview/PreviewManager.lua
git commit -m "feat: add group frame preview (party+pet/raid/arena/boss)"
```

---

### Task 11: Phase 3 Integration Test

- [x] **Step 1: Sync and test**
  - Click party → 5 frames + 1 pet frame in correct layout
  - Click raid → 20 frames in vertical column
  - Change orientation to horizontal → frames switch to horizontal layout
  - Change spacing → gap between frames updates
  - Change anchorPoint → growth direction changes

- [x] **Step 2: Fix issues, commit**

---

## Phase 4: Aura Indicator Previews

> **Prerequisite:** Phase 0 aura testing must be complete before starting this phase.

### Indicator Rendering Reference

The real aura system uses 8 distinct indicator/renderer types. The preview must replicate each one's visual appearance from config. Fake duration data drives cooldown visuals.

| Renderer | Used By | Cooldown Visual | Key Visual Elements |
|----------|---------|----------------|---------------------|
| **Icon** | Buffs (ICON) | **Linear depletion bar** (vertical/horizontal fill + leading edge line) | Icon texture (trimmed TexCoord), 0.5px black border, stack text, duration text with color progression |
| **Icons** | Buffs (ICONS) | Linear depletion per icon | Grid of Icon instances with spacing/numPerLine/orientation layout |
| **Bar** | Buffs (BAR) | **StatusBar depletion** (C-level or OnUpdate) | Colored fill bar, 0.5px border, stack text, duration text, threshold colors |
| **Bars** | Buffs (BARS) | StatusBar per bar | Grid of Bar instances |
| **BorderGlow** | Buffs (BORDER) | Alpha fade over duration | 4 edge textures OR LibCustomGlow (Pixel/Soft/Shine/Proc) |
| **Color** | Buffs (RECTANGLE) | Threshold color change | Colored square, 1px border, stack text |
| **Overlay** | Buffs (OVERLAY) | Health bar overlay fill | Texture/StatusBar on health bar, depletion animation |
| **BorderIcon** | Debuffs, RaidDebuffs, Externals, Defensives, Dispellable | **Radial cooldown swipe** (CooldownFrameTemplate) | Icon + colored border (by dispel type), stack text, duration text |

**Fake Duration Data:** Each preview aura gets a fake duration (e.g., 30s buff at 60% remaining = 18s left) to drive the cooldown visuals at a static frozen point. No animation needed — just set the visual state to represent "mid-duration".

### Task 12: Create Preview Indicator Renderers

**Files:**
- Create: `Preview/PreviewIndicators.lua`
- Modify: `Framed.toc`

Dedicated file for preview-mode indicator rendering. Each builder creates the visual elements that match the real renderer's appearance, frozen at a fake duration point.

- [x] **Step 1: Create PreviewIndicators.lua with fake data and shared helpers**

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.PreviewIndicators = {}
local PI = F.PreviewIndicators

-- Well-known spell icons for preview placeholders
local FAKE_ICONS = {
	buffs        = { 135981, 136075, 135932 },      -- Renew, Fort, BoW
	debuffs      = { 136139, 135813, 136188 },      -- Corruption, Curse of Agony, SW:P
	externals    = { 135936, 135964 },                -- BoP, BoS
	raidDebuffs  = { 236216, 132221 },                -- boss debuffs
	defensives   = { 135919, 135872 },                -- Divine Shield, Ice Block
	missingBuffs = { 136075 },                        -- Fort
	targetedSpells = { 136197 },                      -- Shadow Bolt
	privateAuras = { 134400 },                        -- question mark
	dispellable  = { 136139 },                        -- Corruption
	lossOfControl = { 132168 },                       -- stun
	crowdControl  = { 118699 },                       -- Polymorph
}

-- Fake depletion point: 60% remaining of a 30s aura
local FAKE_DEPLETION_PCT = 0.6
local FAKE_STACKS = 2

-- Anchor unpacking helper
local function unpackAnchor(anchor, default)
	anchor = anchor or default or { 'TOPLEFT', nil, 'TOPLEFT', 0, 0 }
	return anchor[1], anchor[2], anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0
end

-- Orientation offset calculator
local function orientOffset(orient, i, w, h, spacingX, spacingY)
	local dx, dy = 0, 0
	if(orient == 'RIGHT') then     dx = (i - 1) * (w + (spacingX or 1))
	elseif(orient == 'LEFT') then  dx = -(i - 1) * (w + (spacingX or 1))
	elseif(orient == 'DOWN') then  dy = -(i - 1) * (h + (spacingY or 1))
	elseif(orient == 'UP') then    dy = (i - 1) * (h + (spacingY or 1))
	end
	return dx, dy
end
```

- [x] **Step 2: Add Icon preview builder (linear depletion bar)**

Matches `Elements/Indicators/Icon.lua` — spell icon + linear depletion StatusBar overlay + leading edge line + border + stack/duration text:

```lua
-- ============================================================
-- Icon preview: spell icon + linear depletion bar + border
-- Matches F.Indicators.Icon visual output
-- ============================================================

function PI.CreateIcon(parent, iconTexture, w, h, indConfig)
	w = w or 14
	h = h or 14
	local f = CreateFrame('Frame', nil, parent)
	f:SetSize(w, h)

	-- Icon texture (trimmed like real Icon)
	local tex = f:CreateTexture(nil, 'ARTWORK')
	tex:SetAllPoints(f)
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	tex:SetTexture(iconTexture)

	-- 0.5px black border (BackdropTemplate)
	local border = CreateFrame('Frame', nil, f, 'BackdropTemplate')
	border:SetAllPoints(f)
	border:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = 0.5 })
	border:SetBackdropBorderColor(0, 0, 0, 1)

	-- Linear depletion bar (if showCooldown)
	if(indConfig and indConfig.showCooldown ~= false) then
		local fillDir = indConfig.fillDirection or 'topToBottom'
		local depBar = CreateFrame('StatusBar', nil, f)
		depBar:SetAllPoints(f)
		depBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
		depBar:SetStatusBarColor(0, 0, 0, 0.6)
		depBar:SetMinMaxValues(0, 1)
		-- Set orientation based on fillDirection
		if(fillDir == 'leftToRight' or fillDir == 'rightToLeft') then
			depBar:SetOrientation('HORIZONTAL')
			if(fillDir == 'rightToLeft') then depBar:SetReverseFill(true) end
		else
			depBar:SetOrientation('VERTICAL')
			if(fillDir == 'topToBottom') then depBar:SetReverseFill(true) end
		end
		depBar:SetValue(1 - FAKE_DEPLETION_PCT) -- depleted portion
		depBar:SetFrameLevel(f:GetFrameLevel() + 1)

		-- Leading edge line (thin white line at fill boundary)
		local edge = depBar:CreateTexture(nil, 'OVERLAY')
		edge:SetColorTexture(1, 1, 1, 0.75)
		if(fillDir == 'topToBottom' or fillDir == 'bottomToTop') then
			edge:SetHeight(0.75)
			edge:SetPoint('TOPLEFT', depBar:GetStatusBarTexture(), 'BOTTOMLEFT', 0, 0)
			edge:SetPoint('TOPRIGHT', depBar:GetStatusBarTexture(), 'BOTTOMRIGHT', 0, 0)
		else
			edge:SetWidth(0.75)
			edge:SetPoint('TOPLEFT', depBar:GetStatusBarTexture(), 'TOPRIGHT', 0, 0)
			edge:SetPoint('BOTTOMLEFT', depBar:GetStatusBarTexture(), 'BOTTOMRIGHT', 0, 0)
		end
	end

	-- Stack count text
	if(indConfig and indConfig.showStacks) then
		local sf = indConfig.stackFont or {}
		local stackText = f:CreateFontString(nil, 'OVERLAY')
		stackText:SetFont(F.Media.GetActiveFont(), sf.size or 9, sf.outline or 'OUTLINE')
		stackText:SetPoint(sf.anchor or 'BOTTOMRIGHT', f, sf.anchor or 'BOTTOMRIGHT', sf.offsetX or 0, sf.offsetY or 0)
		stackText:SetText(tostring(FAKE_STACKS))
		if(sf.shadow ~= false) then stackText:SetShadowOffset(1, -1) end
	end

	-- Duration text
	if(indConfig and indConfig.durationMode and indConfig.durationMode ~= 'Never') then
		local df = indConfig.durationFont or {}
		local durText = f:CreateFontString(nil, 'OVERLAY')
		durText:SetFont(F.Media.GetActiveFont(), df.size or 9, df.outline or 'OUTLINE')
		durText:SetPoint(df.anchor or 'BOTTOM', f, df.anchor or 'BOTTOM', df.offsetX or 0, df.offsetY or 0)
		durText:SetText('18')  -- fake 18s remaining
		if(df.shadow ~= false) then durText:SetShadowOffset(1, -1) end
		-- Color progression: green → yellow → red
		if(df.colorProgression) then
			-- At 60% remaining: yellowish-green
			durText:SetTextColor(0.6, 1.0, 0.0, 1)
		end
	end

	return f
end
```

- [x] **Step 3: Add BorderIcon preview builder (radial cooldown swipe)**

Matches `Elements/Indicators/BorderIcon.lua` — icon + colored border + CooldownFrame + stack/duration:

```lua
-- ============================================================
-- BorderIcon preview: icon + dispel-colored border + radial swipe
-- Matches F.Indicators.BorderIcon visual output
-- Used by: debuffs, raidDebuffs, externals, defensives, dispellable
-- ============================================================

local DISPEL_COLORS = {
	Magic   = { 0.20, 0.60, 1.00 },
	Curse   = { 0.60, 0.00, 1.00 },
	Disease = { 0.60, 0.40, 0.00 },
	Poison  = { 0.00, 0.60, 0.00 },
	Physical = { 0.50, 0.50, 0.00 },
}

function PI.CreateBorderIcon(parent, iconTexture, size, borderThickness, dispelType, config)
	size = size or 16
	borderThickness = borderThickness or 2

	local f = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	f:SetSize(size, size)

	-- Colored border
	f:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = borderThickness })
	local bc = DISPEL_COLORS[dispelType] or { 0, 0, 0 }
	f:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)

	-- Icon texture (inset by border)
	local tex = f:CreateTexture(nil, 'ARTWORK')
	tex:SetPoint('TOPLEFT', f, 'TOPLEFT', borderThickness, -borderThickness)
	tex:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -borderThickness, borderThickness)
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	tex:SetTexture(iconTexture)

	-- Radial cooldown swipe (CooldownFrameTemplate)
	if(not config or config.showCooldown ~= false) then
		local cd = CreateFrame('Cooldown', nil, f, 'CooldownFrameTemplate')
		cd:SetAllPoints(tex)
		cd:SetDrawBling(false)
		cd:SetDrawEdge(false)
		cd:SetHideCountdownNumbers(true)
		-- Fake cooldown: 30s duration, 60% remaining = started 12s ago
		local fakeDuration = 30
		local fakeStart = GetTime() - (fakeDuration * (1 - FAKE_DEPLETION_PCT))
		cd:SetCooldown(fakeStart, fakeDuration)
		cd:Pause()  -- Freeze at current point
	end

	-- Stack count
	if(not config or config.showStacks ~= false) then
		local sf = (config and config.stackFont) or {}
		local stackText = f:CreateFontString(nil, 'OVERLAY')
		stackText:SetFont(F.Media.GetActiveFont(), sf.size or 9, 'OUTLINE')
		stackText:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', 0, 0)
		stackText:SetText(tostring(FAKE_STACKS))
		stackText:SetShadowOffset(1, -1)
	end

	-- Duration text
	if(config and config.showDuration ~= false) then
		local df = (config and config.durationFont) or {}
		local durText = f:CreateFontString(nil, 'OVERLAY')
		durText:SetFont(F.Media.GetActiveFont(), df.size or 9, 'OUTLINE')
		durText:SetPoint('BOTTOM', f, 'BOTTOM', 0, 0)
		durText:SetText('18')
		durText:SetShadowOffset(1, -1)
	end

	return f
end
```

- [x] **Step 4: Add Bar preview builder**

Matches `Elements/Indicators/Bar.lua` — StatusBar with border, stack/duration text:

```lua
-- ============================================================
-- Bar preview: depleting StatusBar
-- Matches F.Indicators.Bar visual output
-- ============================================================

function PI.CreateBar(parent, barConfig)
	barConfig = barConfig or {}
	local w = barConfig.barWidth or 50
	local h = barConfig.barHeight or 4

	local f = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	f:SetSize(w, h)

	-- Background
	local bg = f:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(f)
	bg:SetColorTexture(0, 0, 0, 0.5)

	-- StatusBar fill
	local bar = CreateFrame('StatusBar', nil, f)
	bar:SetAllPoints(f)
	bar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(FAKE_DEPLETION_PCT)
	local c = barConfig.color or { 1, 1, 1, 1 }
	bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	if(barConfig.barOrientation == 'Vertical') then
		bar:SetOrientation('VERTICAL')
	end

	-- 0.5px border
	f:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = 0.5 })
	f:SetBackdropBorderColor(0, 0, 0, 1)

	return f
end
```

- [x] **Step 5: Add Color (rectangle), Overlay, and BorderGlow preview builders**

```lua
-- ============================================================
-- Color (rectangle) preview
-- Matches F.Indicators.Color visual output
-- ============================================================

function PI.CreateColorRect(parent, rectConfig)
	rectConfig = rectConfig or {}
	local w = rectConfig.rectWidth or 10
	local h = rectConfig.rectHeight or 10

	local f = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	f:SetSize(w, h)
	f:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = 1 })
	f:SetBackdropBorderColor(0, 0, 0, 1)

	local tex = f:CreateTexture(nil, 'ARTWORK')
	tex:SetPoint('TOPLEFT', 1, -1)
	tex:SetPoint('BOTTOMRIGHT', -1, 1)
	local c = rectConfig.color or { 1, 1, 1, 1 }
	tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)

	return f
end

-- ============================================================
-- Overlay preview (health bar overlay)
-- Matches F.Indicators.Overlay visual output
-- ============================================================

function PI.CreateOverlay(healthWrapper, overlayConfig)
	if(not healthWrapper) then return nil end
	overlayConfig = overlayConfig or {}

	local f = CreateFrame('Frame', nil, healthWrapper)
	f:SetAllPoints(healthWrapper)
	f:SetFrameLevel(healthWrapper:GetFrameLevel() + 2)

	local c = overlayConfig.color or { 0, 0, 0, 0.6 }
	local mode = overlayConfig.overlayMode or 'DurationOverlay'

	if(mode == 'Color' or mode == 'Both') then
		local fill = f:CreateTexture(nil, 'OVERLAY')
		fill:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, 0)
		fill:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 0, 0)
		fill:SetWidth(f:GetWidth() * FAKE_DEPLETION_PCT)
		fill:SetColorTexture(c[1], c[2], c[3], c[4] or 0.6)
	end

	if(mode == 'DurationOverlay' or mode == 'Both') then
		local bar = CreateFrame('StatusBar', nil, f)
		bar:SetAllPoints(f)
		bar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
		bar:SetStatusBarColor(c[1], c[2], c[3], mode == 'Both' and 1 or (c[4] or 0.6))
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(FAKE_DEPLETION_PCT)
	end

	return f
end

-- ============================================================
-- BorderGlow preview (border edges or glow placeholder)
-- Matches F.Indicators.BorderGlow visual output
-- ============================================================

function PI.CreateBorderGlow(parent, bgConfig)
	bgConfig = bgConfig or {}
	local mode = bgConfig.borderGlowMode or 'Border'

	if(mode == 'Border') then
		local thickness = bgConfig.borderThickness or 2
		local c = bgConfig.color or { 1, 1, 1, 1 }

		local overlay = CreateFrame('Frame', nil, parent)
		overlay:SetAllPoints(parent)
		overlay:SetFrameLevel(parent:GetFrameLevel() + 10)

		-- Top edge
		local top = overlay:CreateTexture(nil, 'OVERLAY')
		top:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		top:SetPoint('TOPLEFT', overlay, 'TOPLEFT', 0, 0)
		top:SetPoint('TOPRIGHT', overlay, 'TOPRIGHT', 0, 0)
		top:SetHeight(thickness)

		-- Bottom edge
		local bottom = overlay:CreateTexture(nil, 'OVERLAY')
		bottom:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		bottom:SetPoint('BOTTOMLEFT', overlay, 'BOTTOMLEFT', 0, 0)
		bottom:SetPoint('BOTTOMRIGHT', overlay, 'BOTTOMRIGHT', 0, 0)
		bottom:SetHeight(thickness)

		-- Left edge
		local left = overlay:CreateTexture(nil, 'OVERLAY')
		left:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		left:SetPoint('TOPLEFT', top, 'BOTTOMLEFT', 0, 0)
		left:SetPoint('BOTTOMLEFT', bottom, 'TOPLEFT', 0, 0)
		left:SetWidth(thickness)

		-- Right edge
		local right = overlay:CreateTexture(nil, 'OVERLAY')
		right:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		right:SetPoint('TOPRIGHT', top, 'BOTTOMRIGHT', 0, 0)
		right:SetPoint('BOTTOMRIGHT', bottom, 'TOPRIGHT', 0, 0)
		right:SetWidth(thickness)

		-- Fake duration fade (set alpha to 60% to show mid-duration)
		if(bgConfig.fadeOut) then overlay:SetAlpha(FAKE_DEPLETION_PCT * 0.9 + 0.1) end

		return overlay
	else
		-- Glow mode: render as a colored border fallback (can't easily fake LibCustomGlow in preview)
		local overlay = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
		overlay:SetAllPoints(parent)
		overlay:SetFrameLevel(parent:GetFrameLevel() + 10)
		local c = bgConfig.glowColor or bgConfig.color or { 1, 1, 1, 1 }
		overlay:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = 2 })
		overlay:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
		return overlay
	end
end
```

- [x] **Step 6: Add to Framed.toc after PreviewFrame.lua**

```
Preview/PreviewIndicators.lua
```

- [x] **Step 7: Commit**

```bash
git add Preview/PreviewIndicators.lua Framed.toc
git commit -m "feat: add preview indicator renderers matching all 8 real indicator types"
```

---

### Task 13: Wire Indicator Renderers into PreviewFrame

**Files:**
- Modify: `Preview/PreviewFrame.lua`
- Modify: `Preview/PreviewManager.lua`

Connect the indicator renderers to the PreviewFrame so aura config drives visual output.

- [x] **Step 1: Add buff indicator builder using PreviewIndicators**

Buffs use the `indicators` table with per-indicator config. Each indicator's `type` determines which PI builder to call:

```lua
local PI = F.PreviewIndicators

local BUFF_TYPE_MAP = {
	[C.IndicatorType.ICON]      = 'Icon',
	[C.IndicatorType.ICONS]     = 'Icons',
	[C.IndicatorType.BAR]       = 'Bar',
	[C.IndicatorType.BARS]      = 'Bars',
	[C.IndicatorType.BORDER]    = 'BorderGlow',
	[C.IndicatorType.RECTANGLE] = 'ColorRect',
	[C.IndicatorType.OVERLAY]   = 'Overlay',
}

local function BuildBuffIndicators(frame, buffsConfig)
	if(not buffsConfig or not buffsConfig.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}
	local fakeIcons = PI.GetFakeIcons('buffs')

	for name, indCfg in next, buffsConfig.indicators or {} do
		if(indCfg.enabled ~= false) then
			local indType = indCfg.type
			local pt, relFrame, relPt, offX, offY = PI.UnpackAnchor(indCfg.anchor, { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 })

			if(indType == C.IndicatorType.ICON) then
				-- Single icon with linear depletion
				local icon = PI.CreateIcon(groupFrame, fakeIcons[1], indCfg.iconWidth, indCfg.iconHeight, indCfg)
				icon:SetPoint(pt, frame, relPt, offX, offY)
				groupFrame._elements[#groupFrame._elements + 1] = icon

			elseif(indType == C.IndicatorType.ICONS) then
				-- Grid of icons
				local max = math.min(indCfg.maxDisplayed or 3, 5)
				local w = indCfg.iconWidth or 14
				local h = indCfg.iconHeight or 14
				for i = 1, max do
					local icon = PI.CreateIcon(groupFrame, fakeIcons[((i-1) % #fakeIcons) + 1], w, h, indCfg)
					local dx, dy = PI.OrientOffset(indCfg.orientation or 'RIGHT', i, w, h, indCfg.spacingX, indCfg.spacingY)
					icon:SetPoint(pt, frame, relPt, offX + dx, offY + dy)
					groupFrame._elements[#groupFrame._elements + 1] = icon
				end

			elseif(indType == C.IndicatorType.BAR) then
				local bar = PI.CreateBar(groupFrame, indCfg)
				bar:SetPoint(pt, frame, relPt, offX, offY)
				groupFrame._elements[#groupFrame._elements + 1] = bar

			elseif(indType == C.IndicatorType.BARS) then
				local max = math.min(indCfg.maxDisplayed or 3, 5)
				for i = 1, max do
					local bar = PI.CreateBar(groupFrame, indCfg)
					local dx, dy = PI.OrientOffset(indCfg.orientation or 'DOWN', i,
						indCfg.barWidth or 50, indCfg.barHeight or 4, indCfg.spacingX, indCfg.spacingY)
					bar:SetPoint(pt, frame, relPt, offX + dx, offY + dy)
					groupFrame._elements[#groupFrame._elements + 1] = bar
				end

			elseif(indType == C.IndicatorType.BORDER) then
				local bg = PI.CreateBorderGlow(frame, indCfg)
				groupFrame._elements[#groupFrame._elements + 1] = bg

			elseif(indType == C.IndicatorType.RECTANGLE) then
				local rect = PI.CreateColorRect(groupFrame, indCfg)
				rect:SetPoint(pt, frame, relPt, offX, offY)
				groupFrame._elements[#groupFrame._elements + 1] = rect

			elseif(indType == C.IndicatorType.OVERLAY) then
				local overlay = PI.CreateOverlay(frame._healthWrapper, indCfg)
				if(overlay) then
					groupFrame._elements[#groupFrame._elements + 1] = overlay
				end
			end
		end
	end

	return groupFrame
end
```

- [x] **Step 2: Add BorderIcon group builder for debuffs/externals/defensives/raidDebuffs**

```lua
local BORDICON_GROUPS = { 'debuffs', 'raidDebuffs', 'externals', 'defensives' }

-- Fake dispel types for preview variety
local GROUP_DISPEL_TYPES = {
	debuffs      = { 'Magic', 'Curse', 'Poison' },
	raidDebuffs  = { 'Magic', 'Magic' },
	externals    = { nil, nil },  -- no dispel border
	defensives   = { nil, nil },
}

local function BuildBorderIconGroup(frame, groupKey, groupCfg)
	if(not groupCfg or not groupCfg.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}

	local pt, _, relPt, offX, offY = PI.UnpackAnchor(groupCfg.anchor)
	local size = groupCfg.iconSize or 14
	local max = math.min(groupCfg.maxDisplayed or 3, 5)
	local orient = groupCfg.orientation or 'RIGHT'
	local fakeIcons = PI.GetFakeIcons(groupKey)
	local fakeDispels = GROUP_DISPEL_TYPES[groupKey] or {}
	local borderThick = groupCfg.borderThickness or 2

	for i = 1, max do
		local dispel = fakeDispels[((i-1) % math.max(#fakeDispels, 1)) + 1]
		local bi = PI.CreateBorderIcon(groupFrame, fakeIcons[((i-1) % #fakeIcons) + 1], size, borderThick, dispel, groupCfg)
		local dx, dy = PI.OrientOffset(orient, i, size, size, 2, 2)
		bi:SetPoint(pt, frame, relPt, offX + dx, offY + dy)
		groupFrame._elements[#groupFrame._elements + 1] = bi
	end

	return groupFrame
end
```

- [x] **Step 3: Add dispellable, missingBuffs, and other simple group builders**

```lua
local function BuildDispellableGroup(frame, dispCfg)
	if(not dispCfg or not dispCfg.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}

	local pt, _, relPt, offX, offY = PI.UnpackAnchor(dispCfg.anchor)
	local size = dispCfg.iconSize or 14
	local bi = PI.CreateBorderIcon(groupFrame, PI.GetFakeIcons('dispellable')[1], size, 2, 'Magic', dispCfg)
	bi:SetPoint(pt, frame, relPt, offX, offY)
	groupFrame._elements[1] = bi

	-- Health bar overlay (dispel highlight)
	if(frame._healthWrapper and dispCfg.highlightType) then
		local hlType = dispCfg.highlightType
		local hlColor = DISPEL_COLORS.Magic or { 0.2, 0.6, 1.0 }
		local hl = frame._healthWrapper:CreateTexture(nil, 'OVERLAY')
		if(hlType == 'gradient_full' or hlType == 'gradient_half') then
			hl:SetAllPoints(frame._healthWrapper)
			hl:SetColorTexture(hlColor[1], hlColor[2], hlColor[3], 0.3)
			-- gradient_half: only covers right half
			if(hlType == 'gradient_half') then
				hl:ClearAllPoints()
				hl:SetPoint('TOP', frame._healthWrapper, 'TOP', 0, 0)
				hl:SetPoint('BOTTOMRIGHT', frame._healthWrapper, 'BOTTOMRIGHT', 0, 0)
				hl:SetWidth(frame._healthWrapper:GetWidth() * 0.5)
			end
		else
			hl:SetAllPoints(frame._healthWrapper)
			hl:SetColorTexture(hlColor[1], hlColor[2], hlColor[3], 0.2)
		end
		groupFrame._elements[#groupFrame._elements + 1] = hl
	end

	return groupFrame
end

-- Simple single-icon groups (missingBuffs, privateAuras, targetedSpells, LoC, CC)
local function BuildSimpleIconGroup(frame, groupKey, cfg)
	if(not cfg or not cfg.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}

	local pt, _, relPt, offX, offY = PI.UnpackAnchor(cfg.anchor)
	local size = cfg.iconSize or 16
	local fakeIcons = PI.GetFakeIcons(groupKey)

	-- Use BorderIcon for missingBuffs (has glow), plain icon for others
	if(groupKey == 'missingBuffs') then
		local bi = PI.CreateBorderIcon(groupFrame, fakeIcons[1], size, 1, nil, { showCooldown = false, showDuration = false })
		bi:SetPoint(pt, frame, relPt, offX, offY)
		groupFrame._elements[1] = bi
	else
		local icon = PI.CreateIcon(groupFrame, fakeIcons[1], size, size, { showCooldown = false, durationMode = 'Never', showStacks = false })
		icon:SetPoint(pt, frame, relPt, offX, offY)
		groupFrame._elements[1] = icon
	end

	return groupFrame
end
```

- [x] **Step 4: Wire all aura builders into PreviewFrame.Create()**

Update `F.PreviewFrame.Create` to accept `auraConfig` and build all groups:

```lua
function F.PreviewFrame.Create(parent, config, fakeUnit, auraConfig)
	-- ... existing frame shell, health, power, name, icons, castbar, highlights ...

	-- Build aura indicators
	frame._auraGroups = {}
	if(auraConfig) then
		frame._auraGroups.buffs = BuildBuffIndicators(frame, auraConfig.buffs)
		for _, groupKey in next, BORDICON_GROUPS do
			frame._auraGroups[groupKey] = BuildBorderIconGroup(frame, groupKey, auraConfig[groupKey])
		end
		frame._auraGroups.dispellable = BuildDispellableGroup(frame, auraConfig.dispellable)
		frame._auraGroups.missingBuffs = BuildSimpleIconGroup(frame, 'missingBuffs', auraConfig.missingBuffs)
		frame._auraGroups.privateAuras = BuildSimpleIconGroup(frame, 'privateAuras', auraConfig.privateAuras)
		frame._auraGroups.targetedSpells = BuildSimpleIconGroup(frame, 'targetedSpells', auraConfig.targetedSpells)
		frame._auraGroups.lossOfControl = BuildSimpleIconGroup(frame, 'lossOfControl', auraConfig.lossOfControl)
		frame._auraGroups.crowdControl = BuildSimpleIconGroup(frame, 'crowdControl', auraConfig.crowdControl)
	end

	-- Aura group dimming
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

	frame._config = config
	frame._fakeUnit = fakeUnit
	return frame
end
```

- [x] **Step 5: Update PreviewManager to read and pass auraConfig**

```lua
local function getAuraConfig(frameKey)
	local preset = F.Settings.GetEditingPreset()
	return F.Config:Get('presets.' .. preset .. '.auras.' .. frameKey)
end
```

Update `showSoloPreview()` and `showGroupPreview()`:

```lua
local auraConfig = getAuraConfig(frameKey)
local pf = F.PreviewFrame.Create(container, config, fakeUnit, auraConfig)
```

- [x] **Step 6: Wire aura dimming event in PreviewManager**

```lua
F.EventBus:Register('EDIT_MODE_AURA_DIM', function(frameKey, activeGroupId)
	if(frameKey ~= activeFrameKey) then return end
	for _, pf in next, previewFrames do
		if(pf.SetAuraGroupAlpha) then
			pf:SetAuraGroupAlpha(activeGroupId)
		end
	end
end, 'PreviewManager.auraDim')
```

- [x] **Step 7: Commit**

```bash
git add Preview/PreviewFrame.lua Preview/PreviewManager.lua
git commit -m "feat: wire indicator renderers into preview frames with aura config and dimming"
```

---

### Task 14: Phase 4 Integration Test

- [x] **Step 1: Test buff indicator types on solo frames**
  - Player preview: "My Buffs" Icons indicator at TOPLEFT with linear depletion bars
  - Verify: each icon has trimmed texture, 0.5px border, depletion fill at 60%
  - If indicator type is BAR/BARS — verify StatusBar renders correctly

- [x] **Step 2: Test BorderIcon groups on group frames**
  - Party: debuffs at BOTTOMLEFT with dispel-colored borders + radial cooldown swipe
  - RaidDebuffs at CENTER with size scaling
  - Externals at RIGHT, Defensives at LEFT
  - Verify: border colors match dispel type (Magic=blue, Curse=purple, etc.)

- [x] **Step 3: Test dispellable with health bar overlay**
  - Verify: dispellable icon + health bar colored overlay (gradient/solid per config)

- [x] **Step 4: Test aura settings → preview updates**
  - Change buff indicator anchor → icons move on preview
  - Change debuff iconSize → icons resize on preview
  - Change indicator type (Icons→Bar) → visual style changes
  - Toggle aura group enabled/disabled → indicators appear/disappear

- [x] **Step 5: Test aura group dimming**
  - Select frame, switch to "Buffs" panel → buff indicators bright, others 20% alpha
  - Switch to "Debuffs" → debuffs bright, others dim
  - Switch back to "Frame Settings" → all restore to 100%

- [x] **Step 6: Fix issues, commit**

---

## Phase 5: Polish & Version Bump

### Task 15: Final Integration Test

- [x] **Step 1: Full test pass across all frame types**
- [x] **Step 2: Test edit cache flow — edit, save, verify saved values**
- [x] **Step 3: Test edit cache flow — edit, discard, verify reverted**
- [x] **Step 4: Test preset switching in edit mode**
- [x] **Step 5: Fix any remaining issues**

### Task 16: Version Bump

**Files:**
- Modify: `Init.lua`

- [x] **Step 1: Check current version and bump patch**

```bash
grep 'F.version' Init.lua
```

Increment the patch number.

- [x] **Step 2: Commit**

```bash
git add Init.lua
git commit -m "chore: bump version to 0.3.X-alpha"
```
