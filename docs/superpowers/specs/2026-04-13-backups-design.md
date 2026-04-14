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

```lua
FramedDB.snapshots = {
  [name] = {
    version   = 'v0.9.0',     -- addon version at capture time
    timestamp = 1743523200,    -- UNIX seconds
    automatic = false,          -- true for login/pre-import/pre-load backups
    autoKind  = nil,            -- 'login' | 'pre-import' | 'pre-load' for automatic snapshots
    data = {
      general  = { ... },
      minimap  = { ... },
      presets  = { ... },
      char     = { ... },
    },
  },
  ...
}
```

All snapshots live in a single flat table keyed by unique name. Automatic snapshots use reserved names (e.g. `'__auto_login'`, `'__auto_preimport'`, `'__auto_preload'`) that the UI renders specially. The `automatic` flag makes them easy to filter and prevents user-named snapshots from colliding with reserved keys.

**Why flat (not `FramedDB.snapshots.user[name]` and `FramedDB.snapshots.auto[...]`):** one lookup, one iteration path, no duplicated helpers for "is this an auto or user snapshot" branches. The `automatic` flag handles the distinction where it matters (UI rendering, size counting, unique-name validation).

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

- **Load** — Confirmation dialog showing snapshot metadata and verification preview (same verification UI as Import card, see below). On confirm, the live config is first captured as the `__auto_preload` automatic snapshot (rotating, 1-deep), then replaced with the snapshot contents. Fires `IMPORT_APPLIED` event so existing refresh code runs.
- **Export** — Routes the snapshot's `data` table through the same `ImportExport.Export` pipeline used by the Export card (serialize → deflate → print-encode) and shows the resulting string in an inline copyable box below the row, or in a small popup if the card width is tight. Lets users share any saved snapshot with someone else without first having to Load it. The existing Export card still handles the "share my current live config" path; this row action handles the "share a config I have saved" path using the same pipeline.
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

Version comparison parses `vMAJOR.MINOR.PATCH` into a numeric triple and compares lexicographically on the triple (not string comparison on the raw version string, which would break on the v0.9 → v0.10 boundary). Pre-release suffixes are stripped before parsing. A helper lives alongside `F.Version` so the comparison logic has one home.

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
- **Snapshot size calculation** — rough estimate via `strlen(serialized_form)` after `LibSerialize`+`LibDeflate`, or approximate via table key counts without serializing? Serialized size is accurate but costs ~30ms per snapshot on refresh. For a list of a dozen snapshots that's ~400ms on panel open, which is perceptible. Approximation via key count × average bytes-per-key is instant but only ballpark-correct. Decide during implementation — start with serialized size and cache it on the snapshot itself so it only recomputes on save, not on every panel open; fall back to approximation if cache invalidation gets complicated.

## Future work (not in scope for this spec)

- **Per-version deprecation metadata.** When we rename or remove a key post-launch, add metadata so the verification UI can show "renamed to X in v0.7" instead of the generic "unknown key" message.
- **Snapshot diff viewer.** Show a side-by-side of two snapshots to compare config values. Useful for "what did I change between these two backups?"
- **Cloud backup integration.** Out of scope — users who want off-machine backups can still use the Export string.
- **Import history.** A log of the last N imports with what changed. Useful for support but adds persistent storage that's only read in edge cases.
