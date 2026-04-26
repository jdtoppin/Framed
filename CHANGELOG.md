# Framed Changelog

## [Unreleased]

## v0.8.16-alpha

- **Interface bump to 120005** — TOC interface version raised from 120001 to align with WoW 12.0.5

### Settings & UX

- **Settings memory leak fixed (closes #187)** — Framed memory previously climbed toward ~50 MB across settings open/close cycles and never dropped, even after forced GC. Resolved through a chain of fixes: panel teardown infrastructure, weak-key pixel/UI-scale registries, X-button + ESC routing through `Settings.Hide`, snapshot-keys-before-iteration in `TearDownAllPanels`, panel-owned `_eventBusOwners` declarations with recursive tree walk, single-installation OnShow hooks, gated CardGrid rebuilds, and a new `Settings._cachePanelsOnClose = true` policy that retains the cache for fast reopen now that the bounding fixes prevent compounding
- **Buffs/Debuffs/Externals/Defensives spec import hitch eliminated** — loading 60+ spec or healer spells via the indicator import button previously caused a visible frame stall. SpellList now virtualizes scrollable lists, chunks flat lists across frames, and bulk-imports via a new `AddSpells` API. ~240× theoretical reduction on the import path
- **TrackedSpells improvements (#180)** — import-from-spec button + spec-override hint + dropdown trigger + floating preview + off-spec filter
- **Settings panel breadcrumb title card with preset dropdown** — preset switcher promoted to a persistent card at the top of every preset-scoped panel
- **Active-preset row** in FramePresets uses an accent bar + tinted fill so the current preset is visually obvious
- **Pet-scope aura editing** — Defensives/Externals panels now hide when pet is the editing scope (those auras don't apply); other aura panels work for pet
- Cross-preset preset switch redirects stale frame panels to a sensible default instead of leaving the panel pointing at config that was just deleted
- Sidebar resync fixes for group-frame label and preset-scoped sidebar visibility on panel/preset change
- `SpellInput` edit box now shrinks to fit container width (no more overflow)
- Settings preset transitions are now transactional and reconcile synchronously, eliminating cross-listener ordering races

### Bug fixes

- **PrivateAuras: GRADIENT_HALF anchor fix (#163)** — dispel highlight overlay no longer renders with a stale baked height after layout changes; switched from imperative `SetHeight` to anchor-based sizing relative to the overlay frame's vertical midpoint
- **PrivateAuras: Duration Text Scale slider** — Blizzard's private-aura duration text uses a fixed FontObject with no anchor-level size override, which renders oversized on small icons. New slider scales 0.5×–1.5× while preserving icon dimensions
- **MissingBuffs: default glow type changed to Proc** (#178) — `Pixel` glow had ~20× the per-frame cost; high-CPU glow types now annotated in the dropdown
- **StyleBuilder (#165)** — defer `RegisterForClicks` when combat-locked instead of erroring; recovers cleanly out of combat
- **Combat lockdown guard** for `SetPropagateKeyboardInput` so settings keyboard input handling doesn't taint during combat
- **EventBus listener error isolation** — one listener throwing no longer halts the cascade for subsequent listeners; errors surface through the standard error handler
- **`UnitGUID` taint on pet tokens** — replaced GUID-based identity tracking with `UNIT_PET` bumps to avoid taint propagation through pet-token GUID reads
- **Identity generation split** (#118) — content vs identity generation tracked separately; aura cache invalidates correctly across roster reassignments without trashing the cache on every UNIT_AURA
- **LFR raid frame fix** — revert a `_G.CreateFrame` wrapper introduced for memory diagnostics that caused taint cascade across `SecureGroupHeaderTemplate`, ElvUI buff anchors, and nameplate aura calls. Replaced with post-hoc tree walks for the same diagnostic information without taint surface
- **BARS indicators** skip auras with infinite duration (couldn't be sensibly displayed on a depleting bar)
- **Buffs filter widening** — restored conditional filter widening for indicator spell lists so tracked spells outside the default filter set still surface

### Removals

- **TargetedSpells + CastTracker removed** — pre-adoption removal of the runtime-gated TargetedSpells feature plus its only consumer. 14 reference sites pruned across StyleBuilder, LiveUpdate, Preview, AuraDefaults
- **Orphan files cleaned up** — `Elements/Core/Absorbs.lua` (superseded by Health.lua's inline absorb handling) and `Units/LiveUpdate/FrameConfig.lua` (11-line comment stub left behind by the FrameConfig sub-module split)

### Performance

- **AuraState classified API** — element migration to a shared per-frame classification cache, eliminating per-aura predicate evaluation in the indicator hot path. Migrated: Externals (#137), Defensives (#138), Buffs (#139), Debuffs (#140), MissingBuffs (#141)
- **Per-instance classified entry pools** (#144) — bounds allocation churn during aura fan-out by reusing classified-entry tables instead of creating fresh ones per UNIT_AURA event
- **FullRefresh varargs elimination** (#155 item 3) — `GetAuraSlots` results now packed via a reused `_slotsScratch` field instead of varargs unpack, eliminating per-call allocations on every full aura refresh
- **AuraState helpful presence maps** — `FindHelpfulBySpellId` switches from linear scan to indexed lookup for repeated buff queries
- **Buffs `matchAura` hoisted** + `isRaidInCombat` always-gated; avoids redundant per-aura work
- **Icon caching** — initial color/threshold paint cached by `auraInstanceID`; threshold re-evaluated only on `SetSpell`; Icon ticker per-frame cost halved (#114)
- **Indicators refactor** — read `aura.applications` directly for stack counts (instead of secret-tainted intermediate); drop dead `dispelType` param from `Icon:SetSpell`; route Icons through unit + applications consistently
- **AuraState `acquireClassified` split** into helpful/harmful variants — eliminates a branch on every entry acquisition

### Internal & developer tooling

- **MemDiag allocation profiler** — `/framed memdiag [seconds]` measures Lua heap allocation across aura-path hot funnels with ms tracking and tool-self-cost surfacing
- **`/framed memusage`** extended with addon-memory breakdown + four leak-shape probes (settings cache count, pixel updater counts, EventBus listener counts, UIParent direct-children count)
- **`/framed pools`** — per-instance classified pool inspection (#144 diagnostics)
- **`/framed settingsmem`** — opt-in probe with cycle-drift tracking, descendant counts, and ObjectType breakdown for settings memory regression detection
- **Tracked pre-commit hook** running luacheck on staged Lua files; install via `tools/install-hooks.sh`
- Buffs `matchAura` no longer mutates `AuraData` tables — Blizzard fields stay clean for downstream consumers
- Internal MemDiag in-situ probes stripped from `Icon.lua`/`Buffs.lua` hot paths; replaced with broader `OnUpdate` coverage in MemDiag itself

## v0.8.14-alpha

- **12.0.5 compatibility** — fix `bad argument #2 to '?' (Current Field: [isContainer])` error on unit frame spawn; 12.0.5 added a required `isContainer` field to `C_UnitAuras.AddPrivateAuraAnchor`'s args table
- Add `/framed aurastate [unit]` debug slash — dumps the classified aura flag breakdown for a unit (defaults to target), showing which of `external-defensive`, `important`, `player-cast`, `big-defensive`, `raid`, `boss`, `from-player-or-pet` apply to each aura. Useful for verifying classification correctness as #115's B-series migrations land
- Internal: AuraState now exposes shared per-frame classification (`GetHelpfulClassified` / `GetHarmfulClassified` / `GetClassifiedByInstanceID`) with write-path invalidation wired through `FullRefresh` and `ApplyUpdateInfo`. No element yet consumes the new API — infrastructure only in this patch, element migrations follow in subsequent releases (#115 B1-B6)

## v0.8.13-alpha

- **12.0.5 readiness** — fix Buffs `castBy = 'me'` / `'others'` silently filtering to empty when Blizzard marks `sourceUnit` secret in combat (#113); the indicator now falls back to `isFromPlayerOrPlayerPet` when the source is unreachable
- Guard `UnitIsUnit` call sites against compound-token nil returns so 12.0.5's stricter token handling doesn't error (#122)
- Invalidate the aura cache on encounter boundaries so boss-aura changes don't stick across pulls (#123)
- Halve `IconTicker` per-frame cost and skip redundant threshold setters on aura icons (#114)
- Fix `ADDON_ACTION_BLOCKED` on `FramedPinnedAnchor:Hide` when a roster update arrives mid-combat — Pinned `Refresh()` now defers to `PLAYER_REGEN_ENABLED` if combat is locked down (mirrors the existing `pendingResolve` pattern)
- Buffs aura filter is now derived from the indicator set instead of a separate `buffFilterMode` config key — any indicator with a spell list widens the query to `HELPFUL` so specific tracked spells (e.g. follower Rejuvenation) can surface; otherwise stays on `HELPFUL|RAID_IN_COMBAT` to keep trivial raid buffs out. The vestigial `buffFilterMode` key (never had UI) is dropped and migrated out of existing saves

## v0.8.12-alpha

- **Pinned Frames in Edit Mode** — the drag catcher and selected preview now render the full 9-slot grid instead of a single fake frame, so moving pinned frames in edit mode reflects what you'll actually see in-game
- Pinned anchor convention flipped to TOPLEFT to match boss/arena (drag math, catcher bounds, and live layout now agree); existing CENTER-anchored pinned saves are auto-migrated on load to the equivalent TOPLEFT offset so nothing visually shifts
- Pinned geometry edits (width, height, columns, spacing) live-update without the grid flashing during resize, and Resize Anchor compensation keeps the pivot edge visually fixed instead of bouncing back on each slider tick
- Pinned placeholder identity labels ("Pin 1" … "Pin 9") and slot name tags ("Click to assign", character name) now scale with `Name font size` (primary and primary−2, floor 8) — previously hardcoded text looked oversized at non-1.0 UI scales
- Fix edit-mode first drag doing nothing visible — clicking-and-dragging immediately (without releasing first) now selects the frame so the preview appears as you drag
- Fix group position sliders (party, raid, arena, boss) not moving the real frame during slider drag in edit mode — the handler only supported solo CENTER anchoring
- Fix edit-mode preview not rebuilding when position/size sliders change — preview now tracks slider motion in real time via the EditCache
- Fix inline edit panel sliders and dropdowns sometimes missing clicks — split into a sibling shield + panel so children hit-test uncontested; inline panel rebuilds on preset switch so sliders read the active preset's config
- Fix boss and arena frames saving off-screen after a drag — they were written as TOPLEFT offsets but reapplied as CENTER offsets on reload/preset change. Now TOPLEFT end-to-end via a `PSEUDO_GROUPS` cascade path; existing saves self-heal because the stored values were already in TOPLEFT space
- Narrow pinned settings card keeps a 2-column quick-nav summary (was collapsing to 1 column and pushing most rows below the fold); summary rows reflow mid-animation so labels no longer clip past the card edge while the card width tweens
- Preset switches now redirect away from preset-specific panels (e.g. pinned under Solo) even while Settings is hidden, so reopening doesn't flash a stale panel
- Inline edit panel stripped down to just Position & Layout — edit mode is strictly for positioning; all other settings live in the main Settings window with live previews
- Internal cleanup: drop inert `config.count` from pinned (always capped at 9, no UI), consolidate pinned frame-scale handling onto a single anchor-level `RegisterForUIScale` (removes the per-frame gear counter-scale workaround), and rename a shadowed migration local to keep luacheck clean

## v0.8.11-alpha

- **Pinned Frames** — up to 9 standalone frames that track specific group members by name, following players across roster reshuffles. Supports Focus / Focus Target / name-target slots. Role-grouped class-colored assignment dropdown available from the Settings card, empty-slot placeholder click, and a hover-gear icon on assigned pins (out of combat). First-class aura configuration across all 10 aura sub-panels. Per-preset; absent in Solo
- Pinned Frames Settings panel with master enable toggle in the preview card, inline slot assignment, and live-update routing so edits apply without `/reload`
- EditMode integration for Pinned Frames — drag to position (CENTER anchor convention matches the settings panel), click in edit mode to open the inline Pinned panel, hide from the sidebar when the active preset has no `pinnedConfig`
- Empty-slot placeholders render a dimmed identity label (Pin 1 … Pin 9) and become clickable targets for assignment; placeholder mouse-handling is gated so hidden gear icons don't swallow clicks
- **FramePreview** now renders the pinned grid alongside the other unit types, and uses `statusText.position` consistently instead of stale anchor keys that caused name tags to drift in the preview
- Bridge `PLAYER_REGEN_ENABLED` through `EventBus` so combat-flush listeners can register via `F.EventBus:Register` instead of maintaining their own event frames
- Fix pinned gear icon rendering larger on resolved frames than on unresolved (placeholder) frames at non-1.0 UIParent scales — live-frame gears now counter-scale to match the placeholder gear's physical size
- Fix `attempt to perform arithmetic on local 'x' (a nil value)` crash in `FrameConfigText.lua` when toggling Health → Attach to name off. The Health element wasn't recording detached anchor values at setup when the text was created attached, so the live toggle had no coordinates to restore to
- Internal cleanup: drop Cell references from in-code comments (licensing hygiene — Cell is ARR), remove the defensive `SettingsCards.Pinned` existence guard for idiom consistency, collapse empty stub branches in the pinned gear-icon path

## v0.8.10-alpha

- Add **Frame Preview Card** — every Frame settings panel (player/target/party/raid/boss/arena/pet/solo) now renders a live unit frame preview at the top of the panel using your current config, pinned next to a summary card that stays in view while the settings scroll
- Raid preview card includes a 1–40 count stepper saved per character, so you can dial the preview to the group size you're actually tuning for
- Party preview includes a pet toggle to preview pet frames alongside party members
- **Focus Mode** — click a settings card (Health Color, Castbar, Auras, etc.) to spotlight the matching element in the preview; other elements dim to 20%. Your selection persists across `/reload`
- Preview card and frames animate smoothly when you change count, toggle Focus Mode, or resize the settings window
- Preview re-renders live as you edit config — structural changes (count, spacing) rebuild, cosmetic changes (colors, textures) just refresh
- Migrate **Defensives** and **Externals** panels to the same pinned Preview | Overview layout for consistency with the Frame panels
- Fix boss and arena previews where per-frame castbars overlapped the next frame instead of sitting cleanly below
- Fix boss/party/arena preview card titles truncating — fixed-count unit cards now get enough width for the title and Focus Mode toggle; raid keeps its auto-sizing
- Scrollbar UX: hover the right-edge strip to reveal the scrollbar (no more stolen clicks from mouse-motion detection), and dragging the thumb keeps it visible and fires lazy-load
- **Buffs/Debuffs** panels: auto-select the first enabled indicator on open; add/delete indicators with a cleaner inline form (Plus/Tick icons)
- **SpellList**: fix spell ID and name truncation, combine hover tooltip, tighten the ID column
- **StatusText**: replace the dead anchor controls with a proper position switch
- **Copy To**: move the control into the sub-header with a dropdown + direct-write button (the old standalone dialog is gone)
- Fix party pet ghost frames when members joined the group; roster now refreshes properly
- Guard party pet cross-zone check against secret values so it doesn't error in combat
- Fix `RoleIcon` not refreshing on spec change, and fix style 2 to use the correct quadrant overrides
- Revert a `PartyMemberFrame` state-visibility driver change that was breaking Blizzard's own frame cleanup
- Fix `StyleBuilder` preset `groupKey` fallback accidentally applying to derived presets — now scoped to base presets only
- Update summon-pending status text and color
- Add third-party library attribution to the README and mirror it in the About card
- Internal cleanup: drop dead code (`Core/DispelCapability.lua`, `Core/Version.Compare`, `CopyToDialog`), luacheck branch is clean

## v0.8.9-alpha

- Fix party/raid role sorting being silently ignored — the header was writing a nameList but kept `sortMethod='INDEX'`, which falls through Blizzard's sort branches and leaves frames in default order; now uses `sortMethod='NAMELIST'` so role order actually takes effect
- Fix `attempt to compare a secret number value` error from the cast tracker's recheck-skip optimization — the spellId comparison now guards against secret values returned by `UnitCastingInfo`/`UnitChannelInfo` in combat
- Fix `ADDON_ACTION_BLOCKED` on `FramedPartyPet1:ClearAllPoints()` when party composition changed mid-combat — pet re-anchor is now deferred until `PLAYER_REGEN_ENABLED` when the secure frames are locked down
- Internal cleanup: drop hardcoded fallback values in the Dispellable element that duplicated canonical defaults from `Presets/Defaults.lua`

## v0.8.8-alpha

- The new **Backups** system is now feature-complete — save, rename, load, and delete named snapshots, with inline export/import, version and size metadata, stale-version warnings, last-loaded tracking, and roundtrip verification that reports exactly which keys differ from your current config
- Fix Backups snapshot rows overflowing at narrow widths — titles now wrap above the buttons, the metadata line (version · date · layouts · size) wraps below the version when it's too long, and the row grows to fit; very narrow widths stack the buttons under the text
- Fix buttons disappearing from a Backups row when its Export area was opened — buttons are now pinned to the top of the row and the export area expands downward from the row's current height
- Fix auto-backup rows having an empty slot where Rename would be — Export now sits directly next to Delete
- Fix Rename edit box not dismissing when clicking the Rename button again or clicking outside the field; pressing Escape or Enter also closes it cleanly
- Style the version and author name in the About card with the accent color
- Polish inline dropdowns (underline, chevron, accent default) and cascade EditBox width through anchors so nested inputs size correctly
- Fix a race in the Toast dismiss animation that could leave a stale frame visible when a new toast slid in on top of it
- Show the active preset name in accent color in the Settings header

## v0.8.6-alpha

- Fix import/export failing with "Invalid payload structure" on every valid import — a double-pcall was silently dropping the deserialized payload; also rewrite the error messages in plain language
- Add tooltips on the Import mode switch explaining what Replace and Merge actually do
- Fix **Missing Buffs** indicator running even when disabled in settings
- Fix party/raid role sorting occasionally snapping frames to the wrong position on first group spawn — roster events are now bridged through EventBus and the nameList is rebuilt once group membership is fully populated
- Backfill aura sub-table defaults into existing saved presets — Arena/Boss/Solo/Minimal frames no longer end up missing dispellable, defensive, external, and missing-buff configuration after upgrading
- Guard **Private Auras** and **Targeted Spells** against partial config tables so missing optional sub-tables no longer error during Setup
- Reduce cast-tracker broadcast chatter by skipping redundant updates
- Polish **Framed Overview** illustrations and dim the background while the Overview is open
- Retarget the Setup Wizard card's Tour button to the new Overview (old `Onboarding/Tour.lua` removed in v0.8.5-alpha)
- Internal cleanup: drop unused imports, rename shadowing locals, fix luacheck warnings across Elements, Settings, Widgets, and builders

## v0.8.5-alpha

- Add **Framed Overview** — a 6-page illustrated walkthrough covering layouts, edit mode, settings cards, aura indicators, and defensives/externals; auto-shows on first login after the setup wizard and can be relaunched from Appearance → Setup Wizard → Take Overview
- Escape collapses the Overview to a top-right pip instead of leaking to the game menu; click the pip to resume
- Replace the unreachable guided tour with the new Overview (old `Onboarding/Tour.lua` removed)
- Promote `SetupAccentHover` to the shared Widgets library so other panels can reuse the accent fade
- Export `F.Preview.ApplyUnitToFrame` so the Overview welcome page can render a live 3-member party sample
- Add role sorting for raid and party frames (Tank/Healer/DPS ordering via SecureGroupHeader nameList)
- Raid role mode: flat sort across groups, follows orientation and anchor point
- Party role mode: single sorted column
- Add Sorting settings card with role order presets
- Add icon-row dropdown widget showing inline role icon previews
- Edit mode preview and click catcher now reflect sort mode layout
- Fix edit mode preset switch snapping frames to top-left when target preset had no config for that frame
- Post release notes to Discord from the release workflow

## v0.8.4-alpha

- Fix stale target/focus frame auras after retarget — aura cache now invalidates on token reassignment events (PLAYER_TARGET_CHANGED, PLAYER_FOCUS_CHANGED, UNIT_TARGET, group/arena/boss/nameplate updates) instead of only UNIT_AURA
