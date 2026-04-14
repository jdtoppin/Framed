# Backups System Design

**Status:** Draft
**Author:** Moodibs
**Date:** 2026-04-13

## Goal

Replace the current Profiles panel with a Backups system that lets users save, restore, and share Framed configurations without losing work. The current Import/Export flow is one-shot: once a user imports a new config, their previous config is gone unless they manually saved the export string somewhere outside WoW. This is fragile and frequently ends in "I imported something and lost all my settings."

## Problem

- **No undo.** Import replaces the live config with no backup of what was there before.
- **Backups require external storage.** To keep a copy of your config you have to export the string and save it in a text file, Discord DM, or pastebin.
- **No visibility into what's about to change.** Pasting an import string is a blind commitment — users don't see what's different from their current config until after applying it.
- **Stale imports silently corrupt.** Loading an export from a much older addon version can leave dead keys in place and miss new required ones, with no warning to the user.
- **"Profiles" is a misnomer.** Framed has no profile data layer — the sidebar entry is named after a concept that doesn't exist in the addon.

## Non-Goals

- **ElvUI/AceDB-style profile data layer.** Framed's content-driven layout system (auto-switching Solo/Party/Raid/etc.) serves the contextual-config use case. Profiles would duplicate this with a parallel concept and would require a significant refactor for marginal benefit. Users who want "Setup A / Setup B" get it via named snapshots instead.
- **Merge mode for imports.** Merge has surprising scope-dependent semantics (deep-merge for full profile, name-suffixed copy for single layout) that can't be cleanly explained in a tooltip. Replace-only with automatic backups covers the same use case more predictably.
- **Auto-rotation of snapshots.** Auto-deletion in a backup system is the exact behavior that makes users stop trusting it. Snapshots grow until the user cleans them up manually. A sidebar indicator warns when they're consuming a lot of space.
- **Per-version deprecation metadata on day one.** The first release ships with generic "unknown key will be ignored" warnings. Named rename/removal metadata gets added only when we actually rename or remove keys post-launch.

## Architecture

### Data model

Snapshots live in their own top-level SavedVariable separate from `FramedDB`. Each snapshot's payload is stored **pre-serialized** as a printable string (the same `LibSerialize`+`LibDeflate`+`EncodeForPrint` pipeline that `ImportExport.Export` uses), not as a live Lua table.

```lua
FramedSnapshotsDB = {
  schemaVersion = 1,           -- bump when the wrapper envelope changes
  snapshots = {
    [name] = {
      version      = 'v0.9.0',      -- addon version at capture time
      timestamp    = 1743523200,     -- UNIX seconds
      automatic    = false,           -- true for login/pre-import/pre-load backups
      autoKind     = nil,             -- 'login' | 'preimport' | 'preload'
      layoutCount  = 6,               -- cached for display (avoids decoding on list render)
      sizeBytes    = 2453,            -- cached serialized size (avoids re-measuring on list render)
      payload      = '!FRM1!...',     -- serialized string, same format as Export
    },
    ...
  },
}
```

**Why pre-serialized strings instead of live tables:** stored as live tables, every snapshot roughly doubles the in-memory footprint of the full FramedDB *and* doubles the logout-time disk serialization cost (Blizzard writes all SavedVariables by walking them and serializing to disk — more keys, more work). Storing the payload as an already-serialized string collapses both costs: the Lua table representation is a single string, and on logout Blizzard writes a known-length string value instead of recursively serializing a nested table. Saving a snapshot costs ~20ms up front (LibSerialize+LibDeflate run once); loading costs the same ~20ms on demand. Display metadata (layoutCount, sizeBytes) is cached in the wrapper so the snapshot list doesn't need to decode payloads to render.

**Why a separate SavedVariable instead of `FramedDB.snapshots`:** snapshots are meaningfully independent from live config. Putting them at the top level means (a) resetting `FramedDB` via `/framed reset all` doesn't nuke the user's backups, (b) the FramedDB disk footprint stays bounded by live config only, and (c) snapshots survive independently of any schema migration work on `FramedDB` itself. Requires adding `FramedSnapshotsDB` to the TOC `## SavedVariables` line.

**Why flat snapshot map keyed by name:** one lookup, one iteration path, no duplicated helpers for "is this an auto or user snapshot" branches. Automatic snapshots use reserved name keys (`__auto_login`, `__auto_preimport`, `__auto_preload`) and the `automatic` flag makes them easy to filter where it matters (UI rendering, size counting, unique-name validation).

### Captured config surface

A snapshot captures the full user-config surface area. The payload (before serialization) is this table:

```lua
{
  general = F.DeepCopy(FramedDB.general),
  minimap = F.DeepCopy(FramedDB.minimap),
  presets = F.DeepCopy(FramedDB.presets),
  char    = F.DeepCopy(FramedCharDB),
}
```

That covers every top-level key currently defined in `Core/Config.lua` `accountDefaults` (general, minimap, presets — plus the dead `profiles` ghost which is removed in this release) and `charDefaults` (autoSwitch, specOverrides, and the transient `lastPanel` / `lastEditingPreset` / `lastEditingUnitType` UI state).

**Known caveats with loading the captured set as-is:**

- **Transient UI state** (`lastPanel`, `lastEditingPreset`, `lastEditingUnitType`) is captured and restored wholesale. Loading a snapshot pops the user back to whatever panel was open when the snapshot was saved. Minor annoyance, not worth special-casing.
- **Onboarding flags** (`general.wizardCompleted`, `general.overviewCompleted`) are captured and restored wholesale. Loading an old snapshot with `wizardCompleted = false` re-triggers the onboarding wizard on next load. Acceptable: the user can dismiss it, and special-casing these keys would be magic behavior that's worse than the annoyance.
- **Click-casting data** lives in `general` (verified during implementation — if any click-casting state is discovered to live elsewhere, the captured set is extended at implementation time without needing a spec revision).

**What's not captured:**
- `FramedSnapshotsDB` itself — a snapshot does not contain other snapshots. This prevents recursive ballooning and keeps "restore this snapshot" semantically clean.
- `FramedBackupDB` (legacy — see Migration section below).
- Addon-side runtime state that isn't persisted to SavedVariables (frame references, animation timers, etc.).

### Relationship to the existing `FramedBackupDB`

Framed already declares a `FramedBackupDB` SavedVariable in `Framed.toc`. It's used for two things:

1. **Automatic logout snapshot** — `Init.lua` writes `FramedBackupDB = F.DeepCopy(FramedDB)` on `PLAYER_LOGOUT` every session.
2. **Reset safety net** — `/framed reset all` wraps the current config in a `{ db, char, timestamp }` envelope and stores it in `FramedBackupDB` before wiping. `/framed restore` reads from it.

This is a primitive version of exactly what the Backups system provides, and keeping both would be confusing. The new Backups system **replaces `FramedBackupDB` entirely**:

- The logout snapshot path is removed from `Init.lua` — the new `__auto_login` snapshot (captured on load, not on logout) covers the same "what was my config last session" use case, with the benefit that it's visible in the UI and user-interactable.
- The `/framed reset all` path is rewritten to capture a normal user-named snapshot (`"Before reset (YYYY-MM-DD HH:MM)"`) via the Backups API before wiping `FramedDB`. The user sees it in the Backups panel and can Load it like any other snapshot.
- The `/framed restore` slash command becomes an alias that loads the most recent reset-backup snapshot if one exists, or surfaces a message telling the user to open the Backups panel.
- On first load after the update, if `FramedBackupDB` exists and has data, it's migrated into a one-time `"Legacy backup"` user-named snapshot in the new system, then `FramedBackupDB` is nil'd out to release the slot. The TOC line removes `FramedBackupDB` and adds `FramedSnapshotsDB`.

### New UI primitive: `Widgets/Toast.lua`

The Backups system introduces several transient, auto-dismissing notifications that don't fit the existing `Widgets/Dialog.lua` modal-confirmation primitive:

- **Undo-after-Load toast** — `"Snapshot loaded. [Undo]"`, 12-second timeout, action button triggers `__auto_preload` restore
- **Undo-after-Delete toast** — `"Deleted <name>. [Undo]"`, 10-second timeout, action button restores the in-memory copy held for the toast duration
- **Combat-lockdown toast** — `"Can't load snapshots in combat."`, ~4-second timeout, no action button
- **Import-successful toast** — replaces the current Import card's inline status text for consistency with the Load flow

None of the existing widgets cover this cleanly — `Dialog.lua` is modal and blocks input, the Import card's existing status `FontString` is persistent and has no dismiss/action concept. Rather than open-coding four one-off frames, the spec adds one new primitive:

```lua
-- Widgets/Toast.lua
-- Widgets.ShowToast({
--   text         = 'Snapshot loaded.',
--   action       = { text = 'Undo', onClick = function() ... end },  -- optional
--   duration     = 12,                                                 -- seconds; default 4
--   anchor       = { frame = cardFrame, point = 'BOTTOM', relPoint = 'BOTTOM', x = 0, y = 12 },  -- default: Settings panel bottom
--   style        = 'info' | 'warning',                                 -- default 'info'
-- })
```

Behavior:

- Slides in from the anchored edge over ~150ms using `Widgets.StartAnimation` (matching existing Framed animation conventions — no raw `SetScript('OnUpdate')` per the `feedback_no_setscript_on_animated.md` rule).
- Holds for `duration` seconds, then fades out over ~250ms and releases itself.
- If an `action` is provided, a small button renders on the right side of the toast. Clicking it invokes `onClick` and immediately dismisses the toast (skipping the hold timer).
- If a second toast is triggered while one is already showing, the existing toast fast-fades and the new one takes its place. No stacking — a queue of toasts in a backup system is its own usability problem.
- Uses the same backdrop/border styling as `Widgets/Dialog.lua` so the visual language is consistent.

**Scope:** ~60–80 lines in a new `Widgets/Toast.lua` file. No external library dependency. Goes in the same PR as the Backups implementation since nothing else in the codebase currently needs it.

### Sidebar entry

The existing **Profiles** sidebar entry is renamed to **Backups**. The panel file and the card module files are renamed to match (`Settings/Panels/Backups.lua`, `Settings/Cards/Backups.lua`, `F.BackupsCards` namespace).

### Three cards on the Backups panel

```
┌─ Backups ────────────────────────────┐
│                                      │
│  ┌─ Snapshots ──────────────────────┐│   ← headline, full width
│  │  [Save Current As...]            ││
│  │  [Import as Snapshot...]         ││
│  │  ───────                         ││
│  │  (list of snapshots)             ││
│  │                                  ││
│  │  Using 4.8 KB · 4 snapshots      ││
│  └──────────────────────────────────┘│
│                                      │
│  ┌─ Export ─────┐  ┌─ Import ──────┐ │   ← side by side at wide widths,
│  │              │  │               │ │      stacked at narrow widths
│  │              │  │               │ │
│  └──────────────┘  └───────────────┘ │
│                                      │
└──────────────────────────────────────┘
```

The Snapshots card is the headline and spans full width. Export and Import are side-by-side at wide windows and stack at the minimum width (same CardGrid responsive behavior used elsewhere).

## Snapshots card

### Visible elements

**Top action row:**
- `[Save Current As...]` — accent button. Clicking reveals an inline text input below the button, not a popup. User types a name, presses Enter or clicks a confirm button to save. Empty name or duplicate name shows inline validation text, doesn't save.
- `[Import as Snapshot...]` — secondary button. Clicking reveals an inline paste box + name input. Saves the pasted import string as a snapshot without applying it to the live config. The user can then Load it later or compare against current state before committing.

**Empty state:**

When `FramedSnapshotsDB.snapshots` has no user-named snapshots (automatic snapshots, if present, are hidden under the empty-state message until a user snapshot exists), the list area shows:

> You haven't saved any snapshots yet. Click **Save Current As...** to back up your current Framed settings, or **Import as Snapshot...** to load someone else's config into your list without applying it.

Once any user-named snapshot exists, the empty-state message is replaced by the normal list rendering and automatic snapshots become visible at the bottom.

**Snapshot list:**

Each row renders as:

```
[icon] Moodibs — Main Config                      [Load] [Export] [Rename] [Delete]
       v0.9.0 · Saved 2026-04-13 14:32 · 6 layouts · 2.4 KB
```

The metadata line shows addon version at capture, save date, layout count, and the snapshot's serialized size. The icon distinguishes user-named snapshots from automatic ones.

Automatic snapshots render in a visually distinct muted row style (dimmer background, italic name) and are grouped at the bottom of the list:

```
[auto-icon] Automatic — Before last import              [Load] [Export] [Delete]
            v0.9.0 · 2026-04-13 14:28 · 6 layouts · 2.4 KB

[auto-icon] Automatic — Session start                   [Load] [Export] [Delete]
            v0.9.0 · 2026-04-13 14:00 · 6 layouts · 2.4 KB
```

Automatic snapshots cannot be Renamed (the name is reserved), but they can be Loaded, Exported, and Deleted.

**Footer:**
- `Using 4.8 KB · 4 snapshots` — total size and count
- A stern disclaimer block, always visible (full wording in Disclaimer section below).

### Row actions

- **Load** — Confirmation dialog showing snapshot metadata and verification preview (same verification UI as Import card, see below). On confirm, the live config is first captured as the `__auto_preload` automatic snapshot (rotating, 1-deep), then replaced with the snapshot contents. Fires `IMPORT_APPLIED` event so existing refresh code runs. After Load, a temporary toast appears: `"Snapshot loaded. [Undo]"` — Undo loads the `__auto_preload` snapshot back. The toast fades after 12 seconds; after that, reverting still works manually by loading the `__auto_preload` entry from the snapshot list.
- **Export** — Clicking opens an inline export area below the row containing a small scope dropdown (defaulting to `Whole snapshot`, followed by each layout name in the snapshot) and a copyable text box. On open, the payload is decoded once and cached in-memory for the row; the encoded string for `Whole snapshot` is generated immediately and shown in the text box. Changing the dropdown to a specific layout re-encodes only that layout's subtree (reusing the decoded cache, so there's no repeated LibDeflate work). Whole-snapshot encoding goes through `ImportExport.Export(data, 'full')`; single-layout encoding goes through a new `ImportExport.ExportLayoutData(name, layoutTable)` helper that wraps the supplied layout table in the same `{ name, layout }` envelope and routes it through `Export(..., 'layout')` — the existing `ImportExport.ExportLayout(name)` delegates to this helper after reading `FramedDB.presets[name]`, so the two code paths share one serialization implementation. Lets users share any saved snapshot (or a single layout inside a saved snapshot) with someone else without first having to Load it.
- **Rename** — Inline rename: the name text becomes an editable field, user types new name, Enter confirms or Escape cancels. Duplicate names show inline validation. Automatic snapshots don't have this button.
- **Delete** — Inline confirmation toast: "Deleted X. [Undo]" with a 10-second window. Undo restores the snapshot from an in-memory copy held for the toast duration. After 10 seconds the copy is dropped and deletion is permanent.

### Stale version handling

When a snapshot's `version` is older than the currently installed addon version:

- The version number in the metadata line is rendered **red**.
- A `[!]` icon appears next to the version number, with a tooltip explaining the snapshot is from an older version and may not restore cleanly.
- On Load, the confirmation dialog prominently displays the version mismatch warning before the Load button.

When a snapshot's version is **newer** than the installed addon version:

- The version number is rendered red with a different `[!]` icon style.
- Load is still allowed but the confirmation dialog leads with: "This snapshot was created with Framed v0.9.0, which is newer than your installed version (v0.5.2). Loading it may corrupt your config. Update the addon first." The Load button is styled as destructive (red) and the dialog's default action is Cancel.

Version comparison parses `vMAJOR.MINOR.PATCH` into a numeric triple and compares lexicographically on the triple (not string comparison on the raw version string, which would break on the v0.9 → v0.10 boundary). Pre-release suffixes are stripped before parsing. A helper lives alongside `F.version` (see Version source of truth section) so the comparison logic has one home.

### Size threshold sidebar indicator

When total snapshots size exceeds **100 KB** (measured as the sum of each snapshot's serialized `LibSerialize`+`LibDeflate` byte length), a warning icon appears on the Backups entry in the settings sidebar. The specific icon is chosen during implementation from the Abstract Framework icon set — see Open Questions. Hovering the icon in the sidebar shows a tooltip: "Snapshots are using X KB. Consider deleting old ones to free up space."

A typical full-profile snapshot is 2–5 KB, so 100 KB allows for roughly 20–50 snapshots before the warning appears. That maps to "you've accumulated more than a reasonable number of backups without ever cleaning up" — visible in normal use, high enough that users with a handful of legitimate snapshots never see it. The threshold lives as a named constant so we can adjust from user feedback.

## Automatic snapshots

Three automatic slots, each reserved and rotating (1-deep):

- **`__auto_login`** — Captured on addon load. Replaces any previous `__auto_login` snapshot. Purpose: even if a user never manually backs up, they always have the state from when they last logged in.
- **`__auto_preimport`** — Captured right before `ImportExport.ApplyImport` runs. Replaces any previous `__auto_preimport`. Purpose: one-click undo for "I just imported something and want my old config back."
- **`__auto_preload`** — Captured right before a Snapshot's Load action runs. Replaces any previous `__auto_preload`. Purpose: same as pre-import but for the internal Load flow.

All three render in the muted automatic row style at the bottom of the snapshot list.

**Why rotating and not stacked:** the automatic slots are safety nets, not history. Growing them unbounded just means the list fills up with `Auto 1`, `Auto 2`, `Auto 3` entries the user doesn't remember generating. One of each kind is enough to cover "I want to undo what just happened."

**Why three slots instead of one unified "auto" slot:** the three events are semantically different. "Login state" and "state before I imported a string" and "state before I loaded a snapshot" are distinct kinds of rollback the user may want to choose between. Keeping them separate costs one extra reserved key each.

## Name validation rules

Snapshot names are validated identically for Save Current As, Import as Snapshot, and Rename. The rules:

- **Trim** leading and trailing whitespace before any other check.
- **Reject empty** (after trim) with inline message: *"Name can't be empty."*
- **Reject > 64 characters** with inline message: *"Name is too long (max 64 characters)."* Measured in Lua string length (bytes), which is conservative for multi-byte UTF-8 but keeps the check trivial.
- **Reject the reserved `__auto_` prefix** with inline message: *"Names starting with `__auto_` are reserved for automatic snapshots."* This prevents users from shadowing the automatic slots.
- **Reject collision with the automatic display labels** (`"Automatic — Session start"`, `"Automatic — Before last import"`, `"Automatic — Before last load"`) with inline message: *"That name is reserved."*
- **Case-insensitive uniqueness.** `"Main"` and `"MAIN"` collide. Inline message: *"A snapshot with that name already exists."* Stored display name preserves the user's original casing; the uniqueness check compares lowercased forms.
- **Unicode allowed.** No character-class restriction beyond the trim. Users can name snapshots with emoji or non-Latin characters.

Validation runs on every keystroke in the inline input (debounced 150ms) so the user sees the error before pressing Enter. The confirm button is disabled while the current input is invalid.

## Combat lockdown

Framed's config apply path writes secure frame attributes, which Blizzard blocks during combat. The Backups system handles this at the UI layer:

- **Save Current As…** is allowed in combat. Saving a snapshot only reads live config and writes to `FramedSnapshotsDB` — no secure attribute writes involved.
- **Import as Snapshot…** is allowed in combat for the same reason. The import is parsed and stored, not applied.
- **Load** is blocked in combat. Clicking Load while `InCombatLockdown()` is true shows a toast: *"Can't load snapshots in combat."* The confirmation dialog does not open. The user has to wait until combat ends and click Load again.
- **Import card's Import button** is likewise blocked in combat with the same toast.
- **Delete / Rename / Export row actions** are allowed in combat — none of them touch live config.

No queue-and-retry after combat: silently applying a config change the moment combat ends is exactly the kind of surprise the Backups system is meant to prevent. If the user wants the snapshot loaded, they click Load again when they're out of combat.

## Version source of truth

Version stamping uses `F.version` (the lowercase `version` field on the `Framed` namespace), which is populated at addon load from `C_AddOns.GetAddOnMetadata('Framed', 'Version')` and printed by the `/framed version` slash command (`Init.lua`). This is the single canonical source — no separate version field in `FramedSnapshotsDB`, no hardcoded string in the Backups module.

When a snapshot is saved, its `version` field is set to `F.version`. When comparing for stale-version handling, the parsed numeric triple of the snapshot's stored version is compared against the parsed numeric triple of `F.version`. The comparison helper lives alongside `F.version` so it has one home and one test surface.

## Import card

### Behavior changes from current

- **Merge mode is removed.** The mode switch disappears entirely. All imports are Replace.
- **Paste triggers verification automatically** (debounced ~250ms after the last keystroke).
- **`__auto_preimport` snapshot is captured before `ApplyImport` runs.**

### Layout

```
┌─ Import ─────────────────────────────┐
│                                      │
│  [ paste import string here... ]     │
│                                      │
│  ─── Verification ───                │
│  ✓ Format valid                      │
│  ✓ Version: v0.5.2 [!] (stale)       │
│  ✓ Scope: Everything                 │
│  ✓ Contains 6 layouts, 4 will be     │
│    overwritten, 2 added              │
│  ⚠ 3 settings will be ignored  [▸]   │
│  ℹ 8 new settings will use           │
│    defaults  [▸]                     │
│                                      │
│  [Import]                            │
└──────────────────────────────────────┘
```

When the paste box is empty, the verification section is hidden. Once content is pasted and parsed, the section slides in showing the check results.

### Verification check rows

1. **Format valid** — can be parsed by `ImportExport.Import`. If not, this is the only row shown and the message from the Import function is displayed.
2. **Version** — shows the version the import was created with. Red + `[!]` if older or newer than live addon.
3. **Scope** — `Everything` or `Single Layout`. For single-layout imports, also shows the layout name.
4. **Layout breakdown** — for full imports, shows counts: N total in import, M will overwrite existing by name, K are new. For single-layout imports, shows whether the name conflicts with an existing layout.
5. **Ignored keys** — keys in the import that don't exist in the current defaults schema. Collapsed by default, expandable to show paths. Footer text explains: "These settings are from an older version of Framed and no longer exist in the current schema. They won't break the import — Framed will just skip them."
6. **New defaults** — keys in the current defaults schema that are missing from the import. Collapsed by default, expandable to show paths. Footer text: "These settings didn't exist when this import was created. Framed will use default values for them. If your import looks wrong after loading, check these settings first."

### Verification implementation

Verification runs against a pre-computed flattened key set derived from `Presets/Defaults.lua` and `Core/Config.lua` defaults. The flattened set is built once at addon load (not per verification run) and cached. Each verification pass walks the import payload and classifies keys into:

- **Matched** (count only, not displayed)
- **Ignored** (in import, not in defaults)
- **Missing** (in defaults, not in import)

Total cost is O(N) over the flattened import payload, expected sub-50ms for a full profile. Debouncing 250ms after the last keystroke prevents running on every character of a large paste.

**Why flattening instead of tree-walking both sides:** flattening both the defaults and the import into dotted-path sets makes set difference trivial. Recursive tree walks get tangled when one side has structural keys the other doesn't (e.g. a nested table on one side and a scalar on the other). Flat sets handle all shapes uniformly.

## Export card

Minimal changes from the current implementation:

- **Scope dropdown label `'Full Profile'` → `'Everything'`.** Reflects the removal of the profile misnomer.
- **Add a one-line hint** below the Export button: *"To save a copy for yourself, use Save Current As... in the Snapshots card above. Export is for sharing with other users."*
- **Dead code removal.** The `profiles` field in `ImportExport.ExportFullProfile` and `ApplyImport` is removed — nothing else in the codebase reads or writes `FramedDB.profiles`.

## Migration path

Existing users hit this on first load after the update:

1. Any existing `FramedDB.profiles` field is ignored and deleted on first load (dead code, not user-visible).
2. The existing Profiles panel is replaced by the Backups panel. Users looking for "Profiles" in the sidebar see "Backups" instead. No in-game notification — users will find the renamed entry next time they open settings.
3. A `__auto_login` snapshot is captured on first load after the update, so users have at least one safety net immediately.
4. No data migration required — the existing SavedVariables shape is the same as the Backups system uses for its `data` field.

## Disclaimer wording (reference)

Shown permanently in the Snapshots card footer:

> Snapshots are safe to use day-to-day, but here are some specific cases to watch for. Loading a snapshot replaces your current Framed settings. Framed always keeps an automatic "Before last load" backup so you can revert the most recent load if something goes wrong. Snapshots from older addon versions may not restore cleanly and can leave Framed in a broken state. **If you load an old snapshot and break the addon, we may not be able to help you recover — report it as feedback but expect to fix it yourself.**

Shown in the Load confirmation dialog when the snapshot's version is stale:

> This snapshot was created with Framed **v0.5.2**, which is older than your installed version (**v0.9.0**). Some settings may have changed since then and may not restore cleanly. If loading breaks Framed, open the Backups panel and load the automatic "Before last load" snapshot to revert.

Shown in the Load confirmation dialog when the snapshot's version is newer:

> This snapshot was created with Framed **v0.9.0**, which is newer than your installed version (**v0.5.2**). Loading it may corrupt your Framed config. Update the addon first, or proceed at your own risk.

## Events

- `BACKUP_CREATED` — fired after a snapshot is successfully saved. Payload: `name`, `automatic`.
- `BACKUP_DELETED` — fired after a snapshot is deleted. Payload: `name`.
- `BACKUP_LOADED` — fired after a snapshot is successfully loaded. Payload: `name`.
- Existing `IMPORT_APPLIED` continues to fire on both Import-card applies and Snapshot loads, so existing refresh code runs in both paths.

## Open questions

- **Sidebar warning icon** — which Abstract Framework icon specifically? Decided during implementation once we see the set and can match style to existing sidebar icons.
- **Snapshot size calculation** — rough estimate via `strlen(serialized_form)` after `LibSerialize`+`LibDeflate`, or approximate via table key counts without serializing? Serialized size is accurate but costs ~30ms per snapshot on refresh. For a list of a dozen snapshots that's ~400ms on panel open, which is perceptible. Approximation via key count × average bytes-per-key is instant but only ballpark-correct. The pre-serialized storage format already answers most of this — `#payload` is free, cached on save in `sizeBytes`. Remaining question is whether the displayed number should be the serialized size (what we store) or a rough decoded size (what the user might intuit as "how big is my config"). Default: show serialized size, label it plainly.
- **Expand/collapse primitive** — the verification rows (`[▸]` expandable) and potentially the snapshot row itself need a collapsible-panel affordance. Check `Widgets/` for an existing primitive during implementation; if none exists, the simplest path is a button that toggles a child frame's visibility and reflows the parent card. Not worth designing a generic widget for this single use case unless a second call-site appears.

## Future work (not in scope for this spec)

- **Per-version deprecation metadata.** When we rename or remove a key post-launch, add metadata so the verification UI can show "renamed to X in v0.7" instead of the generic "unknown key" message.
- **Snapshot diff viewer.** Show a side-by-side of two snapshots to compare config values. Useful for "what did I change between these two backups?"
- **Cloud backup integration.** Out of scope — users who want off-machine backups can still use the Export string.
- **Import history.** A log of the last N imports with what changed. Useful for support but adds persistent storage that's only read in edge cases.
- **Snapshot notes field.** A free-form text field per snapshot (e.g., "setup I used for Liberation of Undermine prog"). Nice to have but adds a second input to the Save flow and another column to the list — defer until users ask for it.
