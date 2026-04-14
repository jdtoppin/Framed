# Backups System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [`docs/superpowers/specs/2026-04-13-backups-design.md`](../specs/2026-04-13-backups-design.md)

**Goal:** Replace the Profiles panel with a Backups system that lets users save, restore, import, and share Framed configs as named snapshots, with automatic backups before risky operations, pre-import verification, corrupted-payload tolerance, and stale-version warnings.

**Architecture:** A new `Core/Backups.lua` module owns a new top-level SavedVariable `FramedSnapshotsDB`. Each snapshot stores its payload pre-serialized (via the existing LibSerialize+LibDeflate pipeline) alongside cached display metadata. The UI is a renamed Backups panel with a headline Snapshots card, a refactored Import card (verification, no merge mode), and a lightly tweaked Export card. A new `Widgets/Toast.lua` primitive provides the transient "Undo" affordances. The existing `FramedBackupDB` one-shot backup is migrated into the new system and removed.

**Tech Stack:** Lua 5.1 (WoW runtime), oUF (embedded), LibSerialize, LibDeflate, LibStub, Framed's in-house Widgets/Core/EventBus modules. No new external libraries.

## Testing approach

Framed has no unit test framework — Lua code runs inside the WoW client. Each task has an explicit `/reload` verification section listing what to click, what to observe, and what the expected behavior is. Static checks run via `luacheck . --config .luacheckrc` locally and in CI. The existing GitHub Actions workflow lints every push.

**Sync for testing:** After editing files, sync the worktree to your WoW AddOns folder so `/reload` picks up changes. The user has a local sync script; confirm with them if the path isn't obvious.

## File structure

**New files:**

- `Core/Version.lua` — Parse `vMAJOR.MINOR.PATCH` strings into a numeric triple and provide `IsOlderBy(a, b, component)` / `IsNewerBy(a, b, component)` helpers gated on MAJOR/MINOR/PATCH granularity.
- `Widgets/Toast.lua` — Transient notification primitive with optional action button, slide-in/fade-out animation, no-stacking behavior.
- `Core/Backups.lua` — Public API for managing `FramedSnapshotsDB`: save, load, delete, rename, list, encode/decode, automatic-snapshot hooks, name validation, migration from `FramedBackupDB`.
- `Settings/Panels/Backups.lua` — Renamed/rewritten `Profiles.lua` panel; hosts Snapshots + Export + Import cards; owns the size-threshold badge trigger.
- `Settings/Cards/Backups.lua` — Renamed/rewritten `Cards/Profiles.lua`; exports `F.BackupsCards.Snapshots`, `F.BackupsCards.Export`, `F.BackupsCards.Import`.

**Files removed (via rename):**

- `Settings/Panels/Profiles.lua` — Replaced by `Backups.lua`.
- `Settings/Cards/Profiles.lua` — Replaced by `Backups.lua`.

**Files modified:**

- `Framed.toc` — Remove `FramedBackupDB` from SavedVariables, add `FramedSnapshotsDB`, add the five new file paths.
- `Init.lua` — Fix `F.version` to read from TOC metadata; remove the `PLAYER_LOGOUT` FramedBackupDB snapshot; rewrite `/framed reset all` to capture a named snapshot; rewrite `/framed restore` to load the most recent reset snapshot; trigger the login auto-snapshot + migration on `ADDON_LOADED`.
- `ImportExport/ImportExport.lua` — Add `ExportLayoutData(name, layoutTable)` helper; `ExportLayout` delegates to it; remove merge-mode branches from `ApplyImport`; remove the `profiles` dead-code field from `ExportFullProfile` and `ApplyImport`; expose a `CaptureFullProfileData()` helper for the Backups module to reuse.
- `Core/Config.lua` — Remove the dead `profiles = {}` field from `accountDefaults`.
- `Settings/Sidebar.lua` — Add a right-side warning badge rendering path plus `F.Settings.SetPanelBadge(panelId, state)` API.
- `Core/EventBus.lua` — Documentation-only: the new events (`BACKUP_CREATED`, `BACKUP_DELETED`, `BACKUP_LOADED`) are self-registering, no wiring change needed.

## Task dependency graph

```
Task 0 (F.version fix)
   │
   ├──▶ Task 1 (Version.lua)
   │
   ├──▶ Task 2 (Toast widget)
   │
   ├──▶ Task 3 (ImportExport refactor)
   │        │
   │        ▼
   │    Task 4 (Backups scaffold)
   │        │
   │        ├──▶ Task 5 (name validation)
   │        ├──▶ Task 6 (Save/Get/List/Delete/Rename)
   │        ├──▶ Task 7 (Load + corrupted-payload)
   │        ├──▶ Task 8 (automatic snapshot hooks)
   │        └──▶ Task 9 (Init.lua migration + slash commands)
   │
   └──▶ Task 10 (Profiles → Backups panel rename)
            │
            ├──▶ Task 11 (Snapshots card scaffold)
            ├──▶ Task 12 (row rendering + sort order)
            ├──▶ Task 13 (stale-version + corrupted rendering)
            ├──▶ Task 14 (Save/Import inline inputs)
            ├──▶ Task 15 (Load/Delete/Rename actions + combat guards)
            ├──▶ Task 16 (Export row action + scope chooser)
            ├──▶ Task 17 (Import card refactor + verification)
            ├──▶ Task 18 (Export card polish + dead code removal)
            └──▶ Task 19 (size-threshold sidebar badge)
                    │
                    ▼
                Task 20 (final smoke test)
```

Tasks 1–9 build the foundation and data layer with no user-visible changes. Tasks 10–19 ship the UI. Task 20 is the end-to-end check.

---

## Task 0: Fix `F.version` to read from TOC metadata

**Why:** The spec says version stamping uses `F.version` as the single canonical source, which is printed by `/framed version` and must match the TOC. Right now `Init.lua:5` hardcodes `F.version = '0.3.0-alpha'` which has drifted nine versions behind. Every snapshot stamped against this would claim to be from v0.3.0 and the stale check would fire against every real snapshot.

**Files:**

- Modify: `Init.lua:5`

- [ ] **Step 1: Read the current declaration**

Run: `grep -n 'F.version' Init.lua`

Expected: line 5 shows the hardcoded assignment, lines 152 and 238 print it.

- [ ] **Step 2: Replace the hardcoded assignment with a TOC read**

Edit `Init.lua` line 5. The new line:

```lua
F.version = C_AddOns.GetAddOnMetadata(addonName, 'Version') or 'unknown'
```

`C_AddOns.GetAddOnMetadata` is the supported API for reading TOC fields at runtime on WoW 12.0.x. `addonName` is the first vararg from the `local addonName, Framed = ...` at the top of the file. The `or 'unknown'` fallback protects us from any edge case where the metadata isn't populated yet (shouldn't happen in practice but costs nothing).

- [ ] **Step 3: Lint**

Run: `luacheck Init.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 4: Reload in WoW and verify**

Run in-game: `/framed version`

Expected: prints `Framed v0.8.6-alpha` (or whatever the current TOC version is), not `v0.3.0-alpha`.

- [ ] **Step 5: Commit**

```bash
git add Init.lua
git commit -m "Read F.version from TOC metadata instead of hardcoding"
```

---

## Task 1: Add `Core/Version.lua` — parse and compare version strings

**Why:** The stale-snapshot check compares semver triples, not raw strings. Needs to live in one place with one test surface so the stale logic can't drift.

**Files:**

- Create: `Core/Version.lua`
- Modify: `Framed.toc` (add the new file to the load order)

- [ ] **Step 1: Create `Core/Version.lua`**

Write the file:

```lua
local _, Framed = ...
local F = Framed

F.Version = {}
local V = F.Version

-- ============================================================
-- Parse 'vMAJOR.MINOR.PATCH[-suffix]' into a numeric triple.
-- Returns nil on inputs that don't match the expected shape.
-- ============================================================
function V.Parse(str)
	if(type(str) ~= 'string') then return nil end

	-- Strip leading 'v' if present, and any pre-release suffix after '-'
	local cleaned = str:match('^v?([%d%.]+)')
	if(not cleaned) then return nil end

	local major, minor, patch = cleaned:match('^(%d+)%.(%d+)%.(%d+)$')
	if(not major) then
		-- Allow MAJOR.MINOR with implicit patch=0
		major, minor = cleaned:match('^(%d+)%.(%d+)$')
		patch = '0'
	end

	if(not major) then return nil end

	return {
		major = tonumber(major),
		minor = tonumber(minor),
		patch = tonumber(patch),
	}
end

-- ============================================================
-- Compare two parsed triples. Returns:
--   -1 if a < b
--    0 if a == b
--   +1 if a > b
-- Both arguments must be triples returned by Parse(); returns nil
-- if either is missing, so the caller can distinguish "unknown" from
-- "equal".
-- ============================================================
function V.Compare(a, b)
	if(type(a) ~= 'table' or type(b) ~= 'table') then return nil end

	if(a.major ~= b.major) then
		return a.major < b.major and -1 or 1
	end
	if(a.minor ~= b.minor) then
		return a.minor < b.minor and -1 or 1
	end
	if(a.patch ~= b.patch) then
		return a.patch < b.patch and -1 or 1
	end
	return 0
end

-- ============================================================
-- Stale-check helper: returns true when snapshotVersion is older than
-- currentVersion by MINOR-or-greater (PATCH-only differences return false).
-- Both inputs are raw version strings like 'v0.8.6-alpha'.
-- ============================================================
function V.IsStaleOlder(snapshotVersion, currentVersion)
	local a = V.Parse(snapshotVersion)
	local b = V.Parse(currentVersion)
	if(not a or not b) then return false end

	if(a.major < b.major) then return true end
	if(a.major == b.major and a.minor < b.minor) then return true end
	return false
end

-- ============================================================
-- Mirror of IsStaleOlder for the newer-than-current case.
-- ============================================================
function V.IsStaleNewer(snapshotVersion, currentVersion)
	local a = V.Parse(snapshotVersion)
	local b = V.Parse(currentVersion)
	if(not a or not b) then return false end

	if(a.major > b.major) then return true end
	if(a.major == b.major and a.minor > b.minor) then return true end
	return false
end
```

- [ ] **Step 2: Register the new file in `Framed.toc`**

Open `Framed.toc` and find the line that loads `Core/Constants.lua` or similar. Add `Core/Version.lua` immediately after `Core/Constants.lua` (before `Core/Config.lua` so Config can use it if needed):

```
Core/Constants.lua
Core/Version.lua
Core/Config.lua
```

Use `Read` on `Framed.toc` first to see the exact current order, then Edit to slot the new line in.

- [ ] **Step 3: Lint**

Run: `luacheck Core/Version.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 4: Smoke-test the helpers via `/framed` slash command**

Temporarily add a debug branch to the slash command in `Init.lua` just for this task's verification. In-game run `/run print(Framed.Version.IsStaleOlder('v0.8.0-alpha', 'v0.9.0-alpha'))` — expected: `true`. Then `/run print(Framed.Version.IsStaleOlder('v0.8.5-alpha', 'v0.8.6-alpha'))` — expected: `false` (PATCH-only delta). Then `/run print(Framed.Version.IsStaleNewer('v1.0.0', 'v0.9.0'))` — expected: `true`.

- [ ] **Step 5: Commit**

```bash
git add Core/Version.lua Framed.toc
git commit -m "Add Core/Version.lua for semver parse/compare and stale checks"
```

---

## Task 2: Add `Widgets/Toast.lua` — transient notification primitive

**Why:** Backups needs four transient notifications (load-undo, delete-undo, combat-lockdown, import-success) and none of the existing widgets fit. See the spec's "New UI primitive: `Widgets/Toast.lua`" section for the full design.

**Files:**

- Create: `Widgets/Toast.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Read an existing widget to confirm file conventions**

Run: `Read Widgets/Dialog.lua` (limit 80) to see how the existing modal-confirmation widget is structured — the same namespace setup, backdrop conventions, and animation approach apply.

- [ ] **Step 2: Create `Widgets/Toast.lua`**

```lua
local _, Framed = ...
local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- Transient toast notification.
-- Slides in from the bottom of an anchor frame, holds for a
-- duration, then fades out and releases itself. Optional action
-- button on the right dismisses the toast immediately when clicked.
--
-- No stacking: if a toast is triggered while another is visible,
-- the existing one fast-fades and the new one takes its place.
-- ============================================================

local activeToast -- module-local; at most one toast at a time

local TOAST_WIDTH    = 320
local TOAST_HEIGHT   = 40
local SLIDE_DURATION = 0.15
local FADE_DURATION  = 0.25
local DEFAULT_HOLD   = 4

--- Release a toast: stop any running timer, fade out, hide, and clear activeToast.
local function dismiss(toast, immediate)
	if(not toast) then return end
	if(toast._holdTimer) then
		toast._holdTimer:Cancel()
		toast._holdTimer = nil
	end
	if(immediate) then
		toast:Hide()
		if(activeToast == toast) then activeToast = nil end
		return
	end

	Widgets.StartAnimation(
		toast, 'toastFade',
		1, 0,
		FADE_DURATION,
		function(self, value)
			self:SetAlpha(value)
			if(value == 0) then
				self:Hide()
				if(activeToast == self) then activeToast = nil end
			end
		end
	)
end

--- Create (or recycle) the shared toast frame and populate it.
--- @param opts table { text, action = { text, onClick }, duration, anchor, style }
function Widgets.ShowToast(opts)
	opts = opts or {}

	-- Dismiss any existing toast immediately so only one is ever visible
	if(activeToast) then
		dismiss(activeToast, true)
	end

	local parent = (opts.anchor and opts.anchor.frame) or UIParent
	local toast = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(toast, TOAST_WIDTH, TOAST_HEIGHT)
	Widgets.ApplyBackdrop(toast, C.Colors.widget, C.Colors.border)
	toast:SetFrameStrata('DIALOG')

	-- Anchor
	local a = opts.anchor or {}
	toast:ClearAllPoints()
	Widgets.SetPoint(
		toast,
		a.point    or 'BOTTOM',
		a.frame    or UIParent,
		a.relPoint or 'BOTTOM',
		a.x        or 0,
		a.y        or 80
	)

	-- Label
	local label = Widgets.CreateFontString(toast, C.Font.sizeNormal, C.Colors.textNormal)
	label:SetPoint('LEFT', toast, 'LEFT', 12, 0)
	label:SetText(opts.text or '')
	toast._label = label

	-- Optional action button
	if(opts.action) then
		local btn = Widgets.CreateButton(toast, opts.action.text or 'Undo', 'accent', 60, 22)
		btn:ClearAllPoints()
		Widgets.SetPoint(btn, 'RIGHT', toast, 'RIGHT', -8, 0)
		btn:SetOnClick(function()
			if(opts.action.onClick) then opts.action.onClick() end
			dismiss(toast, true)
		end)
		toast._action = btn
		label:SetPoint('RIGHT', btn, 'LEFT', -8, 0)
	else
		label:SetPoint('RIGHT', toast, 'RIGHT', -12, 0)
	end

	-- Slide in: start below anchor and slide up to final Y offset
	local targetY = a.y or 80
	local startY  = targetY - 20
	toast:Show()
	toast:SetAlpha(0)
	Widgets.StartAnimation(
		toast, 'toastSlide',
		startY, targetY,
		SLIDE_DURATION,
		function(self, value)
			self:ClearAllPoints()
			Widgets.SetPoint(
				self,
				a.point    or 'BOTTOM',
				a.frame    or UIParent,
				a.relPoint or 'BOTTOM',
				a.x        or 0,
				value
			)
			-- Ramp alpha alongside slide
			local t = (value - startY) / (targetY - startY)
			self:SetAlpha(t)
		end
	)

	-- Hold, then fade out
	local duration = opts.duration or DEFAULT_HOLD
	toast._holdTimer = C_Timer.NewTimer(duration, function()
		dismiss(toast, false)
	end)

	activeToast = toast
	return toast
end

--- External dismiss (e.g. when the user manually triggers the same action again).
function Widgets.DismissToast()
	dismiss(activeToast, true)
end
```

- [ ] **Step 3: Register the new file in `Framed.toc`**

Add `Widgets/Toast.lua` to the TOC load order alongside the other widget files. Find the block where existing widgets load (`Widgets/Button.lua`, `Widgets/Dialog.lua`, etc.) and add the new line in alphabetical order.

- [ ] **Step 4: Lint**

Run: `luacheck Widgets/Toast.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 5: Smoke-test via slash command**

In-game run: `/run Framed.Widgets.ShowToast({ text = 'Test toast', action = { text = 'Undo', onClick = function() print('undo clicked') end }, duration = 6 })`

Expected: A toast slides in at the bottom of the screen with "Test toast" and an "Undo" button, holds for 6 seconds, fades out. Clicking Undo prints "undo clicked" and dismisses immediately.

- [ ] **Step 6: Commit**

```bash
git add Widgets/Toast.lua Framed.toc
git commit -m "Add Widgets/Toast.lua transient notification primitive"
```

---

## Task 3: Refactor `ImportExport/ImportExport.lua`

**Why:** The Backups system needs `ExportLayoutData(name, layoutTable)` as a shared primitive so the row Export action can serialize a layout extracted from a decoded snapshot without detouring through `FramedDB.presets`. Merge mode is removed per the spec (non-goal). Dead `profiles` field is removed. A new `CaptureFullProfileData()` helper returns the in-memory payload table the Backups module will reuse for snapshot capture.

**Files:**

- Modify: `ImportExport/ImportExport.lua`
- Modify: `Settings/Cards/Profiles.lua` (temporarily — remove merge switch usage until Task 10 renames this file; if Task 10 has already run, apply to `Settings/Cards/Backups.lua` instead)

- [ ] **Step 1: Read the current ImportExport.lua to confirm line numbers**

Run: `Read ImportExport/ImportExport.lua`

- [ ] **Step 2: Add `ExportLayoutData` helper and make `ExportLayout` delegate**

Replace the existing `ExportLayout` function with:

```lua
--- Export a single layout table directly (no FramedDB lookup).
--- Used by the Backups row Export action after decoding a snapshot payload.
--- @param layoutName string
--- @param layoutTable table
--- @return string|nil encoded, string|nil err
function ImportExport.ExportLayoutData(layoutName, layoutTable)
	if(not layoutName or layoutName == '') then
		return nil, 'Layout name is required'
	end
	if(type(layoutTable) ~= 'table') then
		return nil, 'Layout data is required'
	end

	local data = {
		name   = layoutName,
		layout = F.DeepCopy(layoutTable) or layoutTable,
	}

	return ImportExport.Export(data, 'layout')
end

--- Export a single layout from live FramedDB by name.
--- @param layoutName string
--- @return string|nil encoded, string|nil err
function ImportExport.ExportLayout(layoutName)
	if(not FramedDB or not FramedDB.presets) then
		return nil, 'SavedVariables not ready'
	end
	if(not layoutName or layoutName == '') then
		return nil, 'Layout name is required'
	end

	local layout = FramedDB.presets[layoutName]
	if(not layout) then
		return nil, 'Layout not found: ' .. layoutName
	end

	return ImportExport.ExportLayoutData(layoutName, layout)
end
```

- [ ] **Step 3: Add `CaptureFullProfileData` helper**

Immediately above `ExportFullProfile`, add:

```lua
--- Build the in-memory full-profile payload table (before serialization).
--- The Backups module calls this to get a snapshot payload without
--- going through the full Export pipeline twice.
--- Note: the `profiles` field from accountDefaults is intentionally NOT
--- included — it was dead storage from an earlier design and is removed
--- in this release.
--- @return table
function ImportExport.CaptureFullProfileData()
	if(not FramedDB) then return {} end

	return {
		general = F.DeepCopy(FramedDB.general) or {},
		minimap = F.DeepCopy(FramedDB.minimap) or {},
		presets = F.DeepCopy(FramedDB.presets) or {},
		char    = F.DeepCopy(FramedCharDB)     or {},
	}
end
```

- [ ] **Step 4: Rewrite `ExportFullProfile` to delegate to the capture helper**

Replace the existing `ExportFullProfile`:

```lua
--- Export general settings + all layouts.
--- @return string|nil encoded, string|nil err
function ImportExport.ExportFullProfile()
	if(not FramedDB) then
		return nil, 'SavedVariables not ready'
	end

	return ImportExport.Export(ImportExport.CaptureFullProfileData(), 'full')
end
```

- [ ] **Step 5: Remove merge mode from `ApplyImport`**

Replace the entire `ApplyImport` function and the `deepMerge` helper above it with:

```lua
--- Apply an import payload to the live config. Replace-only.
--- The legacy merge mode is removed — see the Backups spec.
--- @param payload table A validated payload returned by Import()
function ImportExport.ApplyImport(payload)
	if(not payload or not payload.scope or not payload.data) then return end
	if(not FramedDB) then return end

	local scope = payload.scope
	local data  = payload.data

	if(scope == 'full') then
		if(data.general)  then FramedDB.general  = F.DeepCopy(data.general) end
		if(data.minimap)  then FramedDB.minimap  = F.DeepCopy(data.minimap) end
		if(data.presets)  then FramedDB.presets  = F.DeepCopy(data.presets) end
		if(data.char)     then FramedCharDB      = F.DeepCopy(data.char)    end

	elseif(scope == 'layout') then
		local name   = data.name
		local layout = data.layout
		if(not name or not layout) then return end

		FramedDB.presets[name] = F.DeepCopy(layout)

		if(F.EventBus) then
			F.EventBus:Fire('LAYOUT_CREATED', name)
		end
	end

	refreshAfterImport(scope)

	if(F.EventBus) then
		F.EventBus:Fire('IMPORT_APPLIED', scope, 'replace')
	end
end
```

The `deepMerge` local helper is no longer called — delete it entirely (it was used only by the removed merge branches).

- [ ] **Step 6: Update the Profiles card's Import button to drop the mode switch callsite**

Open `Settings/Cards/Profiles.lua`. Find the `importBtn:SetOnClick` block around line 215. Remove every reference to `modeSwitch:GetValue()` and the `mode` local. The `ApplyImport` call becomes:

```lua
Widgets.ShowConfirmDialog(
	'Confirm Import',
	confirmMsg,
	function()
		ie.ApplyImport(payload)
		importBox:SetText('')
		setTextColor(statusFS, C.Colors.textActive)
		statusFS:SetText('Import successful.')
	end,
	function()
		setTextColor(statusFS, C.Colors.textSecondary)
		statusFS:SetText('Import cancelled.')
	end)
```

Also remove the `modeSwitch` creation block (the `Widgets.CreateSwitch` call and `modeLabel`), and rewrite `confirmMsg` to drop the mode line:

```lua
local confirmMsg = string.format(
	'Apply import?\n\nScope: %s\n\nThis cannot be undone.',
	payload.scope or 'unknown')
```

This temporary edit will be superseded by Task 17 (Import card refactor) but keeps the addon loadable in the interim.

- [ ] **Step 7: Lint both files**

Run: `luacheck ImportExport/ImportExport.lua Settings/Cards/Profiles.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 8: Reload and smoke-test**

In-game: `/reload`. Open Settings → Profiles. Export a full profile (should still work). Paste the export string into the Import box and apply — should succeed, no "invalid payload structure" errors. No mode switch should be visible anymore.

- [ ] **Step 9: Commit**

```bash
git add ImportExport/ImportExport.lua Settings/Cards/Profiles.lua
git commit -m "Refactor ImportExport: add ExportLayoutData + CaptureFullProfileData, remove merge mode"
```

---

## Task 4: `Core/Backups.lua` scaffold + `FramedSnapshotsDB` declaration

**Why:** Stand up the SavedVariable, the module namespace, and the no-op API surface so downstream tasks can call into it. No behavior yet — just the skeleton and schema initialization.

**Files:**

- Create: `Core/Backups.lua`
- Modify: `Framed.toc` (add file + add `FramedSnapshotsDB` to SavedVariables)

- [ ] **Step 1: Create `Core/Backups.lua` with scaffold**

```lua
local _, Framed = ...
local F = Framed

F.Backups = {}
local B = F.Backups

-- ============================================================
-- Constants
-- ============================================================

B.SCHEMA_VERSION = 1

B.AUTO_LOGIN     = '__auto_login'
B.AUTO_PREIMPORT = '__auto_preimport'
B.AUTO_PRELOAD   = '__auto_preload'

B.AUTO_LABELS = {
	[B.AUTO_LOGIN]     = 'Automatic — Session start',
	[B.AUTO_PREIMPORT] = 'Automatic — Before last import',
	[B.AUTO_PRELOAD]   = 'Automatic — Before last load',
}

B.AUTO_ORDER = {
	B.AUTO_LOGIN,
	B.AUTO_PREIMPORT,
	B.AUTO_PRELOAD,
}

B.NAME_MAX_LEN = 64

-- ============================================================
-- Initialization — called from Core/Config.lua or Init.lua at load
-- ============================================================

function B.EnsureDefaults()
	if(type(FramedSnapshotsDB) ~= 'table') then
		FramedSnapshotsDB = {
			schemaVersion = B.SCHEMA_VERSION,
			snapshots     = {},
		}
		return
	end
	if(type(FramedSnapshotsDB.snapshots) ~= 'table') then
		FramedSnapshotsDB.snapshots = {}
	end
	if(not FramedSnapshotsDB.schemaVersion) then
		FramedSnapshotsDB.schemaVersion = B.SCHEMA_VERSION
	end
end

-- ============================================================
-- Stubs for the API — filled in by later tasks
-- ============================================================

--- @return table array of wrapper tables (not decoded)
function B.List()
	B.EnsureDefaults()
	local out = {}
	for _, wrapper in next, FramedSnapshotsDB.snapshots do
		out[#out + 1] = wrapper
	end
	return out
end

--- @param name string
--- @return table|nil wrapper
function B.Get(name)
	B.EnsureDefaults()
	return FramedSnapshotsDB.snapshots[name]
end
```

- [ ] **Step 2: Add `FramedSnapshotsDB` to TOC SavedVariables**

Open `Framed.toc`. The current line:

```
## SavedVariables: FramedDB, FramedBackupDB
```

becomes:

```
## SavedVariables: FramedDB, FramedBackupDB, FramedSnapshotsDB
```

`FramedBackupDB` stays for now — Task 9 removes it as part of the migration commit.

- [ ] **Step 3: Add the file to the TOC load order**

Add `Core/Backups.lua` after `Core/EventBus.lua` and before any file that might call into it. The Backups module depends on `F.DeepCopy`, `F.EventBus`, and `F.Version` — all of those must load first.

- [ ] **Step 4: Wire `EnsureDefaults` into `ADDON_LOADED` in `Init.lua`**

In `Init.lua`, inside the `ADDON_LOADED` handler, add after `F.PresetDefaults.EnsureDefaults()`:

```lua
F.Backups.EnsureDefaults()
```

- [ ] **Step 5: Lint**

Run: `luacheck Core/Backups.lua Init.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 6: Reload and verify the SavedVariable is initialized**

In-game: `/reload`. Then: `/run print(FramedSnapshotsDB and FramedSnapshotsDB.schemaVersion)`

Expected: `1`

Then: `/run print(#Framed.Backups.List())`

Expected: `0` (no snapshots yet).

- [ ] **Step 7: Commit**

```bash
git add Core/Backups.lua Framed.toc Init.lua
git commit -m "Scaffold Core/Backups.lua with FramedSnapshotsDB schema v1"
```

---

## Task 5: Name validation helpers in `Core/Backups.lua`

**Why:** Every user-facing name entry (Save Current As, Import as Snapshot, Rename) uses the same validation rules. Centralizing them as a pure function keeps the rules in one place and lets the UI wire inline validation feedback without duplicating logic.

**Files:**

- Modify: `Core/Backups.lua`

- [ ] **Step 1: Append validation helpers to `Core/Backups.lua`**

Add after the stubs section:

```lua
-- ============================================================
-- Name validation
-- Returns (true) for valid names and (false, errorMessage) otherwise.
-- Trimming is the caller's responsibility — call TrimName first.
-- ============================================================

--- Trim leading/trailing whitespace and return the cleaned name.
function B.TrimName(name)
	if(type(name) ~= 'string') then return '' end
	return (name:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Validate a (trimmed) snapshot name.
--- @param name string
--- @return boolean valid, string|nil errMsg
function B.ValidateName(name)
	if(type(name) ~= 'string' or name == '') then
		return false, "Name can't be empty."
	end
	if(#name > B.NAME_MAX_LEN) then
		return false, 'Name is too long (max ' .. B.NAME_MAX_LEN .. ' characters).'
	end
	if(name:find('^__auto_')) then
		return false, 'Names starting with `__auto_` are reserved for automatic snapshots.'
	end

	-- Collision with automatic display labels
	for _, label in next, B.AUTO_LABELS do
		if(name:lower() == label:lower()) then
			return false, 'That name is reserved.'
		end
	end

	-- Case-insensitive uniqueness against existing user snapshots
	B.EnsureDefaults()
	local lower = name:lower()
	for existingName, wrapper in next, FramedSnapshotsDB.snapshots do
		if(not wrapper.automatic and existingName:lower() == lower) then
			return false, 'A snapshot with that name already exists.'
		end
	end

	return true, nil
end

--- Same as ValidateName but excludes a specific name from the uniqueness
--- check — used by Rename so renaming to the same name (no-op) is valid
--- and so a user can fix casing without tripping the unique check.
function B.ValidateNameForRename(name, excludeName)
	if(type(name) ~= 'string' or name == '') then
		return false, "Name can't be empty."
	end
	if(#name > B.NAME_MAX_LEN) then
		return false, 'Name is too long (max ' .. B.NAME_MAX_LEN .. ' characters).'
	end
	if(name:find('^__auto_')) then
		return false, 'Names starting with `__auto_` are reserved for automatic snapshots.'
	end
	for _, label in next, B.AUTO_LABELS do
		if(name:lower() == label:lower()) then
			return false, 'That name is reserved.'
		end
	end

	B.EnsureDefaults()
	local lower       = name:lower()
	local excludeLow  = excludeName and excludeName:lower() or nil
	for existingName, wrapper in next, FramedSnapshotsDB.snapshots do
		if(not wrapper.automatic and existingName:lower() == lower and existingName:lower() ~= excludeLow) then
			return false, 'A snapshot with that name already exists.'
		end
	end

	return true, nil
end
```

- [ ] **Step 2: Lint**

Run: `luacheck Core/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 3: Verify via slash command**

In-game:

- `/run print(Framed.Backups.ValidateName(''))` → `false   Name can't be empty.`
- `/run print(Framed.Backups.ValidateName(string.rep('a', 65)))` → `false   Name is too long (max 64 characters).`
- `/run print(Framed.Backups.ValidateName('__auto_login'))` → `false   Names starting with ...`
- `/run print(Framed.Backups.ValidateName('Main Config'))` → `true   nil`

- [ ] **Step 4: Commit**

```bash
git add Core/Backups.lua
git commit -m "Add snapshot name validation helpers"
```

---

## Task 6: CRUD primitives — Save, Delete, Rename

**Why:** These are the direct writes to `FramedSnapshotsDB.snapshots`. Load + decode stays in Task 7; automatic snapshot hooks stay in Task 8. This task keeps the scope tight: create/destroy/rename, plus the metadata caching on save.

**Files:**

- Modify: `Core/Backups.lua`

- [ ] **Step 1: Append save/delete/rename primitives**

Add after the validation section:

```lua
-- ============================================================
-- Internal: build a wrapper table around an already-encoded payload
-- ============================================================

local function buildWrapper(opts)
	return {
		version     = opts.version     or F.version or 'unknown',
		timestamp   = opts.timestamp   or time(),
		automatic   = opts.automatic   or false,
		autoKind    = opts.autoKind    or nil,
		layoutCount = opts.layoutCount or 0,
		sizeBytes   = opts.sizeBytes   or 0,
		payload     = opts.payload,
	}
end

-- ============================================================
-- Save — capture live config and store under a user-named key
-- ============================================================

--- Capture current live FramedDB + FramedCharDB state and save it as a
--- user-named snapshot. Runs name validation and returns (true) on
--- success or (false, errMsg) on failure.
--- @param name string  trimmed snapshot name
--- @return boolean ok, string|nil err
function B.Save(name)
	B.EnsureDefaults()

	local ok, err = B.ValidateName(name)
	if(not ok) then return false, err end

	if(not F.ImportExport or not F.ImportExport.CaptureFullProfileData) then
		return false, 'ImportExport module not ready'
	end

	local payloadTable = F.ImportExport.CaptureFullProfileData()
	local layoutCount  = 0
	if(type(payloadTable.presets) == 'table') then
		for _ in next, payloadTable.presets do
			layoutCount = layoutCount + 1
		end
	end

	local encoded, encErr = F.ImportExport.Export(payloadTable, 'full')
	if(not encoded) then
		return false, encErr or 'Failed to encode snapshot'
	end

	FramedSnapshotsDB.snapshots[name] = buildWrapper({
		version     = F.version,
		timestamp   = time(),
		automatic   = false,
		layoutCount = layoutCount,
		sizeBytes   = #encoded,
		payload     = encoded,
	})

	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_CREATED', name, false)
	end
	return true
end

-- ============================================================
-- SaveFromPayload — store an already-encoded import string as a snapshot
-- ============================================================

--- Save an already-encoded payload string (used by Import as Snapshot).
--- The version, timestamp, and layoutCount are derived from the decoded
--- payload, NOT from the current addon version — this keeps the stale
--- check accurate when a user imports an old string.
--- @param name string
--- @param encoded string
--- @return boolean ok, string|nil err
function B.SaveFromPayload(name, encoded)
	B.EnsureDefaults()

	local ok, err = B.ValidateName(name)
	if(not ok) then return false, err end

	if(not F.ImportExport or not F.ImportExport.Import) then
		return false, 'ImportExport module not ready'
	end

	local parsed, parseErr = F.ImportExport.Import(encoded)
	if(not parsed) then
		return false, parseErr or 'Invalid import string'
	end

	local layoutCount = 0
	if(parsed.scope == 'full' and type(parsed.data) == 'table' and type(parsed.data.presets) == 'table') then
		for _ in next, parsed.data.presets do
			layoutCount = layoutCount + 1
		end
	elseif(parsed.scope == 'layout' and type(parsed.data) == 'table' and parsed.data.layout) then
		layoutCount = 1
	end

	-- Derive the version stored in the import payload itself. The payload's
	-- envelope has a numeric `version` field for the envelope schema; the
	-- snapshot's display `version` should come from payload.data.version if
	-- present. Fall back to 'unknown'.
	local payloadVersion = (type(parsed.data) == 'table' and parsed.data.version) or parsed.sourceVersion or 'unknown'

	FramedSnapshotsDB.snapshots[name] = buildWrapper({
		version     = payloadVersion,
		timestamp   = parsed.timestamp or time(),
		automatic   = false,
		layoutCount = layoutCount,
		sizeBytes   = #encoded,
		payload     = encoded,
	})

	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_CREATED', name, false)
	end
	return true
end

-- ============================================================
-- Delete
-- ============================================================

--- Delete a snapshot. Returns (wrapper) on success so the caller can
--- hold the reference in memory for undo.
--- @param name string
--- @return table|nil removedWrapper
function B.Delete(name)
	B.EnsureDefaults()
	local existing = FramedSnapshotsDB.snapshots[name]
	if(not existing) then return nil end

	FramedSnapshotsDB.snapshots[name] = nil

	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_DELETED', name)
	end
	return existing
end

--- Restore a previously-deleted wrapper under its original name.
--- Used by the undo toast. Returns true if the restore succeeded.
--- @param name string
--- @param wrapper table
--- @return boolean ok
function B.RestoreDeleted(name, wrapper)
	B.EnsureDefaults()
	if(not name or not wrapper) then return false end

	-- If a same-named snapshot has appeared in the meantime (race), bail
	if(FramedSnapshotsDB.snapshots[name]) then return false end

	FramedSnapshotsDB.snapshots[name] = wrapper
	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_CREATED', name, wrapper.automatic and true or false)
	end
	return true
end

-- ============================================================
-- Rename
-- ============================================================

--- Rename a user-named snapshot. Automatic snapshots (name starting with
--- '__auto_') cannot be renamed and the call returns (false, errMsg).
--- @param oldName string
--- @param newName string
--- @return boolean ok, string|nil err
function B.Rename(oldName, newName)
	B.EnsureDefaults()

	local wrapper = FramedSnapshotsDB.snapshots[oldName]
	if(not wrapper) then
		return false, 'Snapshot not found.'
	end
	if(wrapper.automatic) then
		return false, 'Automatic snapshots cannot be renamed.'
	end

	newName = B.TrimName(newName)
	if(newName == oldName) then
		return true -- no-op
	end

	local ok, err = B.ValidateNameForRename(newName, oldName)
	if(not ok) then return false, err end

	FramedSnapshotsDB.snapshots[newName] = wrapper
	FramedSnapshotsDB.snapshots[oldName] = nil

	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_DELETED', oldName)
		F.EventBus:Fire('BACKUP_CREATED', newName, false)
	end
	return true
end
```

- [ ] **Step 2: Lint**

Run: `luacheck Core/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 3: Verify save/delete/rename via slash commands**

In-game:

- `/run print(Framed.Backups.Save('Test 1'))` → `true`
- `/run print(FramedSnapshotsDB.snapshots['Test 1'].version)` → current addon version string
- `/run print(Framed.Backups.Save('Test 1'))` → `false   A snapshot with that name already exists.`
- `/run print(Framed.Backups.Rename('Test 1', 'Renamed'))` → `true`
- `/run print(Framed.Backups.Delete('Renamed') ~= nil)` → `true`
- `/run print(Framed.Backups.Get('Renamed'))` → `nil`

- [ ] **Step 4: Commit**

```bash
git add Core/Backups.lua
git commit -m "Add Backups save/delete/rename primitives with metadata caching"
```

---

## Task 7: Load primitive + corrupted payload handling

**Why:** Load decodes the stored payload, runs it through `ApplyImport`, and fires the refresh events. The corrupted-payload pattern from the spec is implemented here: failed decodes return a structured error so the UI can disable Load and flag the row.

**Files:**

- Modify: `Core/Backups.lua`

- [ ] **Step 1: Append the decode helper and Load primitive**

Add to `Core/Backups.lua`:

```lua
-- ============================================================
-- Decode — turn a snapshot's payload string back into a usable table
-- ============================================================

--- Decode a snapshot's payload into its parsed form.
--- @param wrapper table a snapshot wrapper
--- @return table|nil parsedPayload, string|nil err
function B.DecodeWrapper(wrapper)
	if(type(wrapper) ~= 'table' or type(wrapper.payload) ~= 'string') then
		return nil, 'Snapshot has no payload.'
	end

	if(not F.ImportExport or not F.ImportExport.Import) then
		return nil, 'ImportExport module not ready'
	end

	local parsed, err = F.ImportExport.Import(wrapper.payload)
	if(not parsed) then
		return nil, err or 'Payload is corrupted.'
	end
	return parsed
end

-- ============================================================
-- Load — apply a snapshot to live config (captures pre-load auto first)
-- ============================================================

--- Load a snapshot by name. Captures a pre-load automatic snapshot, then
--- applies the payload through ImportExport.ApplyImport (same path the
--- Import card uses), then fires BACKUP_LOADED.
--- @param name string
--- @return boolean ok, string|nil err
function B.Load(name)
	B.EnsureDefaults()

	local wrapper = FramedSnapshotsDB.snapshots[name]
	if(not wrapper) then return false, 'Snapshot not found.' end

	local parsed, err = B.DecodeWrapper(wrapper)
	if(not parsed) then return false, err end

	-- Capture pre-load auto snapshot (rotating, 1-deep)
	B.CaptureAutomatic(B.AUTO_PRELOAD)

	-- Apply via the shared ImportExport path (replace semantics)
	if(not F.ImportExport or not F.ImportExport.ApplyImport) then
		return false, 'ImportExport module not ready'
	end
	F.ImportExport.ApplyImport(parsed)

	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_LOADED', name)
	end
	return true
end
```

- [ ] **Step 2: Lint**

Run: `luacheck Core/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors. The reference to `B.CaptureAutomatic` is a forward reference — it will resolve at call time once Task 8 lands. The lint pass is a syntax and unused-var check, not a dead-code check, so this is fine.

- [ ] **Step 3: Verify decode error handling via slash command**

In-game:

```lua
/run local w = { payload = 'garbage' }; print(Framed.Backups.DecodeWrapper(w))
```

Expected: `nil   Couldn't read this import string...` (or similar friendly error from `ImportExport.Import`).

- [ ] **Step 4: Commit**

```bash
git add Core/Backups.lua
git commit -m "Add Backups decode + load primitives with corruption handling"
```

---

## Task 8: Automatic snapshot hooks

**Why:** The three auto slots (`__auto_login`, `__auto_preimport`, `__auto_preload`) are the safety net for the whole system. This task adds the `CaptureAutomatic` helper and wires the login hook into `ADDON_LOADED` and the pre-import hook into `ImportExport.ApplyImport`.

**Files:**

- Modify: `Core/Backups.lua`
- Modify: `Init.lua`
- Modify: `ImportExport/ImportExport.lua`

- [ ] **Step 1: Append `CaptureAutomatic` to `Core/Backups.lua`**

Add after the Load primitive:

```lua
-- ============================================================
-- Automatic snapshot capture (rotating, 1-deep per slot)
-- ============================================================

--- Capture the current live config as a rotating automatic snapshot.
--- Automatic slots overwrite their previous entry (no growth).
--- @param autoKey string one of B.AUTO_LOGIN / B.AUTO_PREIMPORT / B.AUTO_PRELOAD
--- @return boolean ok
function B.CaptureAutomatic(autoKey)
	B.EnsureDefaults()
	if(not B.AUTO_LABELS[autoKey]) then return false end

	if(not F.ImportExport or not F.ImportExport.CaptureFullProfileData) then
		return false
	end

	local payloadTable = F.ImportExport.CaptureFullProfileData()
	local layoutCount  = 0
	if(type(payloadTable.presets) == 'table') then
		for _ in next, payloadTable.presets do
			layoutCount = layoutCount + 1
		end
	end

	local encoded = F.ImportExport.Export(payloadTable, 'full')
	if(not encoded) then return false end

	local autoKind =
		(autoKey == B.AUTO_LOGIN)     and 'login' or
		(autoKey == B.AUTO_PREIMPORT) and 'preimport' or
		(autoKey == B.AUTO_PRELOAD)   and 'preload' or nil

	FramedSnapshotsDB.snapshots[autoKey] = buildWrapper({
		version     = F.version,
		timestamp   = time(),
		automatic   = true,
		autoKind    = autoKind,
		layoutCount = layoutCount,
		sizeBytes   = #encoded,
		payload     = encoded,
	})
	return true
end
```

- [ ] **Step 2: Wire the login hook in `Init.lua`**

Inside the `ADDON_LOADED` handler, after `F.Backups.EnsureDefaults()`, add:

```lua
F.Backups.CaptureAutomatic(F.Backups.AUTO_LOGIN)
```

Also remove the `PLAYER_LOGOUT` branch entirely:

```lua
elseif(event == 'PLAYER_LOGOUT') then
	-- Snapshot config to backup SavedVariable for recovery
	FramedBackupDB = F.DeepCopy(FramedDB)
```

becomes:

```lua
-- PLAYER_LOGOUT handler removed: Core/Backups now captures a login
-- automatic snapshot on ADDON_LOADED instead.
```

Keep the event registration `eventFrame:RegisterEvent('PLAYER_LOGOUT')` — other code may add handlers later, and the empty branch is cheap.

Actually, delete the `RegisterEvent('PLAYER_LOGOUT')` line too since nothing needs it anymore. The unregister cleanup keeps the event frame minimal.

- [ ] **Step 3: Wire the pre-import hook in `ImportExport.lua`**

In `ImportExport.ApplyImport`, add at the very top (before `if(not payload ...)` checks — no, after those checks but before the scope branches):

```lua
function ImportExport.ApplyImport(payload)
	if(not payload or not payload.scope or not payload.data) then return end
	if(not FramedDB) then return end

	-- Capture pre-import automatic snapshot (rotating, 1-deep).
	-- This runs for both the Import card path AND the Backups.Load path
	-- (Backups.Load captures its own __auto_preload separately first).
	if(F.Backups and F.Backups.CaptureAutomatic) then
		F.Backups.CaptureAutomatic(F.Backups.AUTO_PREIMPORT)
	end

	local scope = payload.scope
	-- (rest unchanged)
```

- [ ] **Step 4: Lint**

Run: `luacheck Core/Backups.lua Init.lua ImportExport/ImportExport.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 5: Reload and verify**

In-game: `/reload`. Then:

- `/run print(FramedSnapshotsDB.snapshots['__auto_login'] ~= nil)` → `true`
- `/run print(FramedSnapshotsDB.snapshots['__auto_login'].automatic)` → `true`
- `/run print(FramedSnapshotsDB.snapshots['__auto_login'].autoKind)` → `login`

Then open Settings → Profiles, paste an export string, click Import, confirm. Check:

- `/run print(FramedSnapshotsDB.snapshots['__auto_preimport'] ~= nil)` → `true`

- [ ] **Step 6: Commit**

```bash
git add Core/Backups.lua Init.lua ImportExport/ImportExport.lua
git commit -m "Hook automatic snapshots on login and pre-import"
```

---

## Task 9: Migrate `FramedBackupDB` and rewrite `/framed reset all` + `/framed restore`

**Why:** The spec calls for the new Backups system to replace `FramedBackupDB` entirely. On first load after the update, if legacy backup data exists, it's migrated into a `"Legacy backup"` snapshot and the old variable is released. The slash commands rewrite to use the new API.

**Files:**

- Modify: `Core/Backups.lua`
- Modify: `Init.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Add `MigrateLegacyBackup` to `Core/Backups.lua`**

```lua
-- ============================================================
-- One-time migration from the legacy FramedBackupDB to a named snapshot
-- ============================================================

--- Migrate FramedBackupDB (if present) into a "Legacy backup" snapshot.
--- Runs once on ADDON_LOADED. Idempotent — a second call is a no-op.
--- @return boolean migrated
function B.MigrateLegacyBackup()
	B.EnsureDefaults()

	if(not FramedBackupDB) then return false end

	-- Legacy backup format is either a plain DeepCopy of FramedDB (pre-reset)
	-- or a wrapper { db, char, timestamp } (post-reset). Treat both.
	local legacyDB, legacyChar, legacyTs
	if(FramedBackupDB.db) then
		legacyDB   = FramedBackupDB.db
		legacyChar = FramedBackupDB.char
		legacyTs   = FramedBackupDB.timestamp
	else
		legacyDB = FramedBackupDB
	end

	if(type(legacyDB) ~= 'table') then
		-- Nothing meaningful to migrate
		FramedBackupDB = nil
		return false
	end

	local payloadTable = {
		general = F.DeepCopy(legacyDB.general) or {},
		minimap = F.DeepCopy(legacyDB.minimap) or {},
		presets = F.DeepCopy(legacyDB.presets) or {},
		char    = legacyChar and F.DeepCopy(legacyChar) or {},
	}

	local layoutCount = 0
	if(type(payloadTable.presets) == 'table') then
		for _ in next, payloadTable.presets do layoutCount = layoutCount + 1 end
	end

	if(not F.ImportExport or not F.ImportExport.Export) then
		return false
	end
	local encoded = F.ImportExport.Export(payloadTable, 'full')
	if(not encoded) then return false end

	-- Pick a non-colliding name
	local baseName = 'Legacy backup'
	local name     = baseName
	local suffix   = 2
	while(FramedSnapshotsDB.snapshots[name]) do
		name = baseName .. ' ' .. suffix
		suffix = suffix + 1
	end

	FramedSnapshotsDB.snapshots[name] = buildWrapper({
		version     = 'unknown',  -- legacy data has no version stamp
		timestamp   = legacyTs or time(),
		automatic   = false,
		layoutCount = layoutCount,
		sizeBytes   = #encoded,
		payload     = encoded,
	})

	-- Release the legacy slot
	FramedBackupDB = nil

	if(F.EventBus) then
		F.EventBus:Fire('BACKUP_CREATED', name, false)
	end
	return true
end
```

- [ ] **Step 2: Wire the migration into `ADDON_LOADED`**

In `Init.lua`, after `F.Backups.EnsureDefaults()` and before `F.Backups.CaptureAutomatic(F.Backups.AUTO_LOGIN)`, add:

```lua
F.Backups.MigrateLegacyBackup()
```

Order matters: migration must happen before the login auto-snapshot so the migrated "Legacy backup" entry is visible from the moment the panel opens.

- [ ] **Step 3: Rewrite `/framed reset all`**

In `Init.lua`, replace the `elseif(cmd == 'reset' and arg1 == 'all') then ... end` block with:

```lua
elseif(cmd == 'reset' and arg1 == 'all') then
	local d = F.Widgets.ShowConfirmDialog(
		'Reset All Settings',
		'This will delete ALL Framed settings, presets, and customizations.\nA backup will be saved to the Backups panel — you can restore later.',
		function()
			-- Save a named snapshot before wiping, so the user has a clear
			-- recovery handle.
			local label = 'Before reset (' .. date('%Y-%m-%d %H:%M') .. ')'
			F.Backups.Save(label)
			FramedDB = nil
			FramedCharDB = nil
			ReloadUI()
		end,
		nil
	)
	d._message:SetTextColor(1, 0.2, 0.2)
	d._btnYes._label:SetText('Yes, Reset Everything')
	d._btnNo._label:SetText('Cancel')
	d._activeWidth = 400
	d:_LayoutButtons('confirm')
	d:_UpdateHeight()
```

- [ ] **Step 4: Rewrite `/framed restore`**

Replace the `elseif(cmd == 'restore') then ... end` block with:

```lua
elseif(cmd == 'restore') then
	-- Find the most recent 'Before reset (...)' snapshot
	local target, targetTs
	for name, wrapper in next, (FramedSnapshotsDB and FramedSnapshotsDB.snapshots or {}) do
		if(name:find('^Before reset')) then
			if(not targetTs or (wrapper.timestamp and wrapper.timestamp > targetTs)) then
				target   = name
				targetTs = wrapper.timestamp
			end
		end
	end

	if(not target) then
		print('|cff00ccff Framed|r No reset backup found. Open the Backups panel to browse all snapshots.')
		return
	end

	local dateStr = targetTs and date('%Y-%m-%d %H:%M', targetTs) or 'unknown date'
	F.Widgets.ShowConfirmDialog(
		'Restore Settings',
		'Restore "' .. target .. '" from ' .. dateStr .. '?\nThis will overwrite your current configuration.',
		function()
			local ok, err = F.Backups.Load(target)
			if(ok) then
				ReloadUI()
			else
				print('|cff00ccff Framed|r Restore failed: ' .. (err or 'unknown error'))
			end
		end,
		nil
	)
```

- [ ] **Step 5: Remove `FramedBackupDB` from the TOC**

In `Framed.toc`, the SavedVariables line:

```
## SavedVariables: FramedDB, FramedBackupDB, FramedSnapshotsDB
```

becomes:

```
## SavedVariables: FramedDB, FramedSnapshotsDB
```

WoW preserves any existing saved-vars data even after a variable is removed from the TOC declaration — the migration step reads `FramedBackupDB` from the global namespace at load time regardless. Declarations matter for initialization, not preservation, so this removal is safe.

- [ ] **Step 6: Lint**

Run: `luacheck Core/Backups.lua Init.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 7: Reload and verify**

In-game: `/reload`. If you had an existing `FramedBackupDB`, check:

- `/run print(FramedBackupDB)` → `nil`
- `/run for k in next, FramedSnapshotsDB.snapshots do print(k) end` → should include a `Legacy backup` entry (plus any autos)

Run `/framed reset all` → dialog appears → confirm → reload. After the reload, check `FramedSnapshotsDB` has a `Before reset (...)` entry. Run `/framed restore` → confirm → the settings should come back.

- [ ] **Step 8: Commit**

```bash
git add Core/Backups.lua Init.lua Framed.toc
git commit -m "Migrate FramedBackupDB into Backups and rewrite reset/restore slash commands"
```

---

## Task 10: Rename Profiles panel → Backups panel

**Why:** Gets the sidebar entry, file names, and `F.ProfilesCards` namespace updated to match the new system before we start adding card content. The rename is mechanical.

**Files:**

- Delete: `Settings/Panels/Profiles.lua`
- Delete: `Settings/Cards/Profiles.lua`
- Create: `Settings/Panels/Backups.lua`
- Create: `Settings/Cards/Backups.lua`
- Modify: `Framed.toc`

- [ ] **Step 1: Copy `Settings/Panels/Profiles.lua` to `Settings/Panels/Backups.lua`**

The content is the same at this point — we only change identifiers. Read the existing file, then Write the new one with the following edits applied:

- `id      = 'profiles'` → `id      = 'backups'`
- `label   = 'Profiles'` → `label   = 'Backups'`
- `F.ProfilesCards.Export` → `F.BackupsCards.Export`
- `F.ProfilesCards.Import` → `F.BackupsCards.Import`
- `'ProfilesPanel.resize'` → `'BackupsPanel.resize'`
- `'ProfilesPanel.resizeComplete'` → `'BackupsPanel.resizeComplete'`

- [ ] **Step 2: Copy `Settings/Cards/Profiles.lua` to `Settings/Cards/Backups.lua`**

Read the current file, then write the new file with:

- `F.ProfilesCards = F.ProfilesCards or {}` → `F.BackupsCards = F.BackupsCards or {}`
- `function F.ProfilesCards.Export(parent, width, onResize)` → `function F.BackupsCards.Export(parent, width, onResize)`
- `function F.ProfilesCards.Import(parent, width)` → `function F.BackupsCards.Import(parent, width)`

- [ ] **Step 3: Delete the old files**

```bash
rm Settings/Panels/Profiles.lua Settings/Cards/Profiles.lua
```

- [ ] **Step 4: Update `Framed.toc` load order**

Find the two lines loading the old Profiles files and replace them:

```
Settings/Cards/Profiles.lua
```
→
```
Settings/Cards/Backups.lua
```

```
Settings/Panels/Profiles.lua
```
→
```
Settings/Panels/Backups.lua
```

- [ ] **Step 5: Lint**

Run: `luacheck Settings/Panels/Backups.lua Settings/Cards/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 6: Reload and verify sidebar**

In-game: `/reload`. Open Settings. The sidebar should show **Backups** where Profiles used to be. Clicking it opens the existing (unchanged) Export + Import cards.

- [ ] **Step 7: Commit**

```bash
git add Settings/Panels/Backups.lua Settings/Cards/Backups.lua Settings/Panels/Profiles.lua Settings/Cards/Profiles.lua Framed.toc
git commit -m "Rename Profiles panel and cards to Backups"
```

Note: `git add` against the deleted files stages the deletion.

---

## Task 11: Snapshots card scaffold

**Why:** Adds the headline Snapshots card above the existing Export/Import cards. Empty state, scroll frame, footer size/count. No rows yet — just the shell.

**Files:**

- Modify: `Settings/Cards/Backups.lua`
- Modify: `Settings/Panels/Backups.lua`

- [ ] **Step 1: Add a `Snapshots` card constructor at the top of `Settings/Cards/Backups.lua`**

At the top of the file, after the existing `local DROPDOWN_H`, etc. constants, add:

```lua
local SNAPSHOT_ROW_H   = 52
local EMPTY_STATE_H    = 60
local LIST_MAX_H       = 320
```

Then add the function, above `function F.BackupsCards.Export`:

```lua
-- ============================================================
-- Snapshots card
-- ============================================================

function F.BackupsCards.Snapshots(parent, width, onResize)
	local card, inner = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	-- Top action row ───────────────────────────────────────────
	local saveBtn   = Widgets.CreateButton(inner, 'Save Current As…',   'accent',   160, BUTTON_H)
	local importBtn = Widgets.CreateButton(inner, 'Import as Snapshot…', 'secondary', 180, BUTTON_H)

	-- Scrollable list area ─────────────────────────────────────
	local listFrame = Widgets.CreateScrollFrame(inner, nil, innerW, LIST_MAX_H)
	local listContent = listFrame:GetContentFrame()
	listContent:SetHeight(EMPTY_STATE_H)

	-- Empty state text (shown when there are no user snapshots) ─
	local emptyFS = Widgets.CreateFontString(listContent, C.Font.sizeNormal, C.Colors.textSecondary)
	emptyFS:SetWidth(innerW - 16)
	emptyFS:SetWordWrap(true)
	emptyFS:SetJustifyH('LEFT')
	emptyFS:SetText(
		"You haven't saved any snapshots yet. Click Save Current As… to back up your current Framed settings, " ..
		'or Import as Snapshot… to load someone else\'s config into your list without applying it.')
	emptyFS:ClearAllPoints()
	Widgets.SetPoint(emptyFS, 'TOPLEFT', listContent, 'TOPLEFT', 8, -8)

	-- Footer: using X KB · N snapshots ─────────────────────────
	local footerFS = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)

	-- Disclaimer block ─────────────────────────────────────────
	local disclaimerFS = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	disclaimerFS:SetWidth(innerW)
	disclaimerFS:SetWordWrap(true)
	disclaimerFS:SetJustifyH('LEFT')
	disclaimerFS:SetText(
		'Snapshots are safe to use day-to-day, but here are some specific cases to watch for. ' ..
		'Loading a snapshot replaces your current Framed settings. ' ..
		"Framed always keeps an automatic \"Before last load\" backup so you can revert the most recent load if something goes wrong. " ..
		'Snapshots from older addon versions may not restore cleanly and can leave Framed in a broken state. ' ..
		"If you load an old snapshot and break the addon, we may not be able to help you recover — " ..
		'report it as feedback but expect to fix it yourself.')

	-- ── Reflow layout ──────────────────────────────────────────
	local function formatSize(bytes)
		if(not bytes or bytes < 1024) then return (bytes or 0) .. ' B' end
		return string.format('%.1f KB', bytes / 1024)
	end

	local function updateFooter()
		local total, count = 0, 0
		for name, wrapper in next, (FramedSnapshotsDB and FramedSnapshotsDB.snapshots or {}) do
			if(not wrapper.automatic) then
				count = count + 1
			end
			total = total + (wrapper.sizeBytes or 0)
		end
		footerFS:SetText('Using ' .. formatSize(total) .. ' · ' .. count .. ' snapshots')
	end

	local function hasUserSnapshots()
		for _, wrapper in next, (FramedSnapshotsDB and FramedSnapshotsDB.snapshots or {}) do
			if(not wrapper.automatic) then return true end
		end
		return false
	end

	local function reflow()
		local y = 0
		y = B.PlaceWidget(saveBtn,   inner, y, BUTTON_H)
		y = B.PlaceWidget(importBtn, inner, y, BUTTON_H)

		-- Show empty state only when there are no user-named snapshots
		if(hasUserSnapshots()) then
			emptyFS:Hide()
		else
			emptyFS:Show()
		end

		y = B.PlaceWidget(listFrame, inner, y, LIST_MAX_H)

		updateFooter()
		y = B.PlaceWidget(footerFS, inner, y, LABEL_H)
		y = B.PlaceWidget(disclaimerFS, inner, y, LABEL_H * 6)

		Widgets.EndCard(card, parent, y)
		if(onResize) then onResize() end
	end

	-- Cache on card for other tasks to re-trigger
	card._reflow      = reflow
	card._listFrame   = listFrame
	card._listContent = listContent
	card._saveBtn     = saveBtn
	card._importBtn   = importBtn

	-- Refresh when Backups API fires events
	if(F.EventBus) then
		local function onChange() reflow() end
		F.EventBus:Register('BACKUP_CREATED', onChange, 'BackupsCard.created')
		F.EventBus:Register('BACKUP_DELETED', onChange, 'BackupsCard.deleted')
		F.EventBus:Register('BACKUP_LOADED',  onChange, 'BackupsCard.loaded')
	end

	reflow()
	return card
end
```

- [ ] **Step 2: Register the Snapshots card in `Settings/Panels/Backups.lua`**

Find the card registration block:

```lua
grid:AddCard('export', 'Export', F.BackupsCards.Export, args)
grid:AddCard('import', 'Import', F.BackupsCards.Import)
grid:SetFullWidth('export')
grid:SetFullWidth('import')
```

Replace with:

```lua
grid:AddCard('snapshots', 'Snapshots', F.BackupsCards.Snapshots, args)
grid:AddCard('export',    'Export',    F.BackupsCards.Export,    args)
grid:AddCard('import',    'Import',    F.BackupsCards.Import)
grid:SetFullWidth('snapshots')
-- export + import are left non-full-width so they can sit side-by-side at wide widths
```

- [ ] **Step 3: Lint**

Run: `luacheck Settings/Cards/Backups.lua Settings/Panels/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 4: Reload and verify**

In-game: `/reload`. Open Settings → Backups. You should see:

- A **Snapshots** card at the top with the Save/Import buttons and the empty-state text
- Below it, the existing Export and Import cards side-by-side at wide widths, stacked at narrow widths
- The footer shows `Using 0 B · 0 snapshots` (or the migrated size if you had a FramedBackupDB legacy backup)

- [ ] **Step 5: Commit**

```bash
git add Settings/Cards/Backups.lua Settings/Panels/Backups.lua
git commit -m "Add Snapshots card scaffold with empty state, scroll list, and footer"
```

---

## Task 12: Snapshot row rendering

**Why:** Brings the list to life. User snapshots render at the top (most-recent-first), automatic snapshots render at the bottom in canonical order with a muted style. Each row shows the metadata line and four action buttons (though the buttons are wired in subsequent tasks).

**Files:**

- Modify: `Settings/Cards/Backups.lua`

- [ ] **Step 1: Add row rendering helpers to `Settings/Cards/Backups.lua`**

Immediately above the `Snapshots` function, add:

```lua
-- ============================================================
-- Row rendering helpers
-- ============================================================

local function formatTimestamp(ts)
	if(not ts) then return '—' end
	return date('%Y-%m-%d %H:%M', ts)
end

local function buildMetadataLine(wrapper)
	local version = wrapper.version or 'unknown'
	local ts      = formatTimestamp(wrapper.timestamp)
	local count   = wrapper.layoutCount or 0
	local size    = wrapper.sizeBytes   or 0
	local sizeStr = (size < 1024) and (size .. ' B') or string.format('%.1f KB', size / 1024)
	return version .. ' · ' .. ts .. ' · ' .. count .. ' layouts · ' .. sizeStr
end

local function createSnapshotRow(parent, width, wrapper, displayName, isAutomatic)
	local row = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(row, width, SNAPSHOT_ROW_H)
	Widgets.ApplyBackdrop(row, C.Colors.cardBg or C.Colors.widget, C.Colors.border)

	row._wrapper     = wrapper
	row._name        = displayName
	row._isAutomatic = isAutomatic

	-- Name label (top line)
	local nameFS = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textActive)
	nameFS:SetPoint('TOPLEFT', row, 'TOPLEFT', 10, -8)
	nameFS:SetText(displayName)
	if(isAutomatic) then
		-- Muted style for auto rows
		nameFS:SetTextColor(
			C.Colors.textSecondary[1],
			C.Colors.textSecondary[2],
			C.Colors.textSecondary[3],
			C.Colors.textSecondary[4] or 1)
	end
	row._nameFS = nameFS

	-- Metadata line (bottom line)
	local metaFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
	metaFS:SetPoint('BOTTOMLEFT', row, 'BOTTOMLEFT', 10, 8)
	metaFS:SetText(buildMetadataLine(wrapper))
	row._metaFS = metaFS

	-- Action buttons: right-aligned in a single row
	-- Layout is Delete · Rename · Export · Load from right to left so Load
	-- is closest to the center of the row for thumb reach.
	local BTN_W, BTN_H = 70, 22
	local PAD          = 4

	local btnLoad   = Widgets.CreateButton(row, 'Load',   'accent',    BTN_W, BTN_H)
	local btnExport = Widgets.CreateButton(row, 'Export', 'secondary', BTN_W, BTN_H)
	local btnRename = Widgets.CreateButton(row, 'Rename', 'secondary', BTN_W, BTN_H)
	local btnDelete = Widgets.CreateButton(row, 'Delete', 'danger',    BTN_W, BTN_H)

	btnDelete:ClearAllPoints()
	Widgets.SetPoint(btnDelete, 'RIGHT', row, 'RIGHT', -10, 0)

	btnRename:ClearAllPoints()
	Widgets.SetPoint(btnRename, 'RIGHT', btnDelete, 'LEFT', -PAD, 0)

	btnExport:ClearAllPoints()
	Widgets.SetPoint(btnExport, 'RIGHT', btnRename, 'LEFT', -PAD, 0)

	btnLoad:ClearAllPoints()
	Widgets.SetPoint(btnLoad, 'RIGHT', btnExport, 'LEFT', -PAD, 0)

	-- Automatic snapshots can't be renamed
	if(isAutomatic) then
		btnRename:Hide()
	end

	row._btnLoad   = btnLoad
	row._btnExport = btnExport
	row._btnRename = btnRename
	row._btnDelete = btnDelete

	return row
end
```

- [ ] **Step 2: Populate the list on reflow**

Inside the `Snapshots` function, after the `local function hasUserSnapshots()` helper, add:

```lua
-- Rendered row cache — reused across reflows so button wiring persists
local renderedRows = {}

local function clearRows()
	for _, row in next, renderedRows do
		row:Hide()
		row:SetParent(nil)
	end
	renderedRows = {}
end

local function rebuildRows()
	clearRows()

	local snapshots = (FramedSnapshotsDB and FramedSnapshotsDB.snapshots) or {}

	-- Partition into user + automatic lists
	local userList = {}
	local autoMap  = {}
	for name, wrapper in next, snapshots do
		if(wrapper.automatic) then
			autoMap[name] = wrapper
		else
			userList[#userList + 1] = { name = name, wrapper = wrapper }
		end
	end

	-- Sort user list most-recent-first
	table.sort(userList, function(a, b)
		local ta = a.wrapper.timestamp or 0
		local tb = b.wrapper.timestamp or 0
		return ta > tb
	end)

	local y = -4
	local rowW = listContent:GetWidth() - 16

	for _, entry in next, userList do
		local row = createSnapshotRow(listContent, rowW, entry.wrapper, entry.name, false)
		row:ClearAllPoints()
		Widgets.SetPoint(row, 'TOPLEFT', listContent, 'TOPLEFT', 8, y)
		row:Show()
		renderedRows[#renderedRows + 1] = row
		y = y - SNAPSHOT_ROW_H - 4
	end

	-- Automatic snapshots in canonical order at the bottom
	for _, autoKey in next, F.Backups.AUTO_ORDER do
		local wrapper = autoMap[autoKey]
		if(wrapper) then
			local label = F.Backups.AUTO_LABELS[autoKey] or autoKey
			local row = createSnapshotRow(listContent, rowW, wrapper, label, true)
			row:ClearAllPoints()
			Widgets.SetPoint(row, 'TOPLEFT', listContent, 'TOPLEFT', 8, y)
			row:Show()
			renderedRows[#renderedRows + 1] = row
			y = y - SNAPSHOT_ROW_H - 4
		end
	end

	-- Resize content to fit all rows
	local totalH = math.max(EMPTY_STATE_H, (-y) + 8)
	listContent:SetHeight(totalH)
end
```

- [ ] **Step 3: Call `rebuildRows()` from `reflow()`**

Inside the existing `reflow` function, before the `y = B.PlaceWidget(listFrame, ...)` line, add:

```lua
rebuildRows()
```

- [ ] **Step 4: Expose a way to refresh rows from outside**

Add to the end of `reflow`, just before `Widgets.EndCard`:

```lua
card._rebuildRows = rebuildRows
```

- [ ] **Step 5: Lint**

Run: `luacheck Settings/Cards/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 6: Reload and verify**

In-game: `/reload`. Open Settings → Backups. You should see:

- The `__auto_login` row at the bottom of the list in muted style, labeled `"Automatic — Session start"`
- If there's a migrated `"Legacy backup"` entry, it appears at the top of the user section
- Action buttons render but don't do anything yet when clicked (wired in later tasks)

Save a test snapshot via `/run Framed.Backups.Save('Test A')`. The row should appear immediately at the top of the user section (EventBus `BACKUP_CREATED` triggers reflow).

- [ ] **Step 7: Commit**

```bash
git add Settings/Cards/Backups.lua
git commit -m "Render snapshot rows with sort order and muted auto styling"
```

---

## Task 13: Stale-version and corrupted-payload rendering

**Why:** Visual affordances for two distinct row states. Stale = version is MINOR-or-greater older/newer than current. Corrupted = payload fails to decode. Both use a `[!]` indicator next to the version string; the color and tooltip differ.

**Files:**

- Modify: `Settings/Cards/Backups.lua`

- [ ] **Step 1: Extend `buildMetadataLine` to return structured parts instead of a single string**

Replace `buildMetadataLine` with:

```lua
local function buildMetadataParts(wrapper)
	local version = wrapper.version or 'unknown'
	local ts      = formatTimestamp(wrapper.timestamp)
	local count   = wrapper.layoutCount or 0
	local size    = wrapper.sizeBytes   or 0
	local sizeStr = (size < 1024) and (size .. ' B') or string.format('%.1f KB', size / 1024)
	return {
		version = version,
		rest    = ' · ' .. ts .. ' · ' .. count .. ' layouts · ' .. sizeStr,
	}
end
```

- [ ] **Step 2: Update `createSnapshotRow` to render version + rest with optional staleness**

Replace the `metaFS` block inside `createSnapshotRow` with:

```lua
local parts = buildMetadataParts(wrapper)

local versionFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
versionFS:SetPoint('BOTTOMLEFT', row, 'BOTTOMLEFT', 10, 8)
versionFS:SetText(parts.version)
row._versionFS = versionFS

-- Stale-version check (MINOR-or-greater gate)
local currentVersion = F.version or 'unknown'
local isStaleOlder = F.Version and F.Version.IsStaleOlder(wrapper.version or 'unknown', currentVersion)
local isStaleNewer = F.Version and F.Version.IsStaleNewer(wrapper.version or 'unknown', currentVersion)

local indicator
if(isStaleOlder or isStaleNewer) then
	versionFS:SetTextColor(1, 0.3, 0.3, 1)
	indicator = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
	indicator:SetPoint('LEFT', versionFS, 'RIGHT', 4, 0)
	indicator:SetText(' [!] ')
	indicator:SetTextColor(1, 0.3, 0.3, 1)

	local tooltipMsg
	if(isStaleOlder) then
		tooltipMsg = 'This snapshot was created with an older version of Framed. It may not restore cleanly.'
	else
		tooltipMsg = 'This snapshot was created with a newer version of Framed. Loading it may corrupt your config.'
	end
	Widgets.SetTooltip(indicator, 'Version warning', tooltipMsg)
end

local metaFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
if(indicator) then
	metaFS:SetPoint('LEFT', indicator, 'RIGHT', 0, 0)
else
	metaFS:SetPoint('LEFT', versionFS, 'RIGHT', 0, 0)
end
metaFS:SetText(parts.rest)
row._metaFS = metaFS
```

- [ ] **Step 3: Add corrupted-payload rendering**

At the bottom of `createSnapshotRow` (just before `return row`), add:

```lua
-- Corrupted-payload indicator: lazy-checked on first action attempt, but
-- we can cheaply test at row render time by trying a decode. For perf,
-- defer this to when the user actually clicks Load/Export — see those
-- tasks for the disabled-state handling. For row-level display, we simply
-- set a row method the action handlers can call to mark it corrupted
-- after a failed decode.
row.MarkCorrupted = function(self)
	if(self._corruptedIcon) then return end
	local icon = Widgets.CreateFontString(self, C.Font.sizeSmall, C.Colors.textSecondary)
	icon:SetPoint('TOPRIGHT', self, 'TOPRIGHT', -10, -8)
	icon:SetText('[!]')
	icon:SetTextColor(1, 0.2, 0.2, 1)
	Widgets.SetTooltip(
		icon,
		'Corrupted snapshot',
		"This snapshot is corrupted. You can delete it but it can't be loaded or exported.")
	self._corruptedIcon = icon

	-- Also disable Load and Export buttons visually
	if(self._btnLoad and self._btnLoad.SetEnabled) then self._btnLoad:SetEnabled(false) end
	if(self._btnExport and self._btnExport.SetEnabled) then self._btnExport:SetEnabled(false) end
end
```

- [ ] **Step 4: Lint**

Run: `luacheck Settings/Cards/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 5: Reload and test stale rendering**

In-game: `/reload`. Open Backups. Then run:

```lua
/run FramedSnapshotsDB.snapshots['Old version test'] = { version = 'v0.5.0-alpha', timestamp = time(), automatic = false, layoutCount = 3, sizeBytes = 2000, payload = 'garbage' }; Framed.EventBus:Fire('BACKUP_CREATED', 'Old version test', false)
```

Expected: The row appears with `v0.5.0-alpha` in red, a red `[!]` next to it, and tooltip text on hover.

- [ ] **Step 6: Commit**

```bash
git add Settings/Cards/Backups.lua
git commit -m "Render stale-version warnings and corrupted-payload indicators on snapshot rows"
```

---

## Task 14: Save Current As + Import as Snapshot inline inputs

**Why:** Wires the two top-row buttons to inline input flows. Pre-filled default names (timestamped), inline validation feedback, confirm-on-Enter behavior.

**Files:**

- Modify: `Settings/Cards/Backups.lua`

- [ ] **Step 1: Add an inline input container helper**

At the top of `Settings/Cards/Backups.lua`, above the row helpers, add:

```lua
-- ============================================================
-- Inline input flows (Save Current As / Import as Snapshot)
-- ============================================================

local function createInlineNameInput(parent, width, placeholderText, defaultName, onConfirm, onCancel)
	local container = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(container, width, EDITBOX_H + LABEL_H + BUTTON_H + 12)

	local input = Widgets.CreateEditBox(container, nil, width, 22)
	input:SetPlaceholder(placeholderText or '')
	input:SetText(defaultName or '')
	input:ClearAllPoints()
	Widgets.SetPoint(input, 'TOPLEFT', container, 'TOPLEFT', 0, 0)

	local errorFS = Widgets.CreateFontString(container, C.Font.sizeSmall, C.Colors.textSecondary)
	errorFS:ClearAllPoints()
	Widgets.SetPoint(errorFS, 'TOPLEFT', input, 'BOTTOMLEFT', 0, -4)
	errorFS:SetWidth(width)
	errorFS:SetWordWrap(true)
	errorFS:SetJustifyH('LEFT')
	errorFS:SetText('')

	local confirmBtn = Widgets.CreateButton(container, 'Save', 'accent',    80, BUTTON_H)
	local cancelBtn  = Widgets.CreateButton(container, 'Cancel', 'secondary', 80, BUTTON_H)

	confirmBtn:ClearAllPoints()
	Widgets.SetPoint(confirmBtn, 'TOPLEFT', errorFS, 'BOTTOMLEFT', 0, -4)

	cancelBtn:ClearAllPoints()
	Widgets.SetPoint(cancelBtn, 'LEFT', confirmBtn, 'RIGHT', 6, 0)

	local function setError(msg)
		if(msg and msg ~= '') then
			errorFS:SetTextColor(1, 0.3, 0.3, 1)
			errorFS:SetText(msg)
			confirmBtn:SetEnabled(false)
		else
			errorFS:SetText('')
			confirmBtn:SetEnabled(true)
		end
	end

	local validateTimer
	local function scheduleValidate(validator)
		if(validateTimer) then validateTimer:Cancel() end
		validateTimer = C_Timer.NewTimer(0.15, function()
			local name = F.Backups.TrimName(input:GetText() or '')
			local ok, err = validator(name)
			setError(ok and nil or err)
		end)
	end

	container._input       = input
	container._confirmBtn  = confirmBtn
	container._cancelBtn   = cancelBtn
	container._setError    = setError
	container._scheduleValidate = scheduleValidate

	return container, input, confirmBtn, cancelBtn
end
```

- [ ] **Step 2: Wire Save Current As**

Inside the `Snapshots` function, after `card._importBtn = importBtn`, add:

```lua
-- Inline input slots (created on demand)
local saveInputContainer
local importInputContainer

local function closeInputs()
	if(saveInputContainer) then
		saveInputContainer:Hide()
		saveInputContainer = nil
	end
	if(importInputContainer) then
		importInputContainer:Hide()
		importInputContainer = nil
	end
	reflow()
end

saveBtn:SetOnClick(function()
	closeInputs()

	local defaultName = 'Snapshot ' .. date('%Y-%m-%d %H:%M')
	local container, input, confirmBtn, cancelBtn = createInlineNameInput(
		inner, innerW,
		'Enter a name for this snapshot',
		defaultName)

	container:SetParent(inner)
	-- reflow will place it via B.PlaceWidget

	input:SetScript('OnTextChanged', function()
		container._scheduleValidate(F.Backups.ValidateName)
	end)
	input:HookScript('OnShow', function()
		if(input._editbox) then
			input._editbox:SetFocus()
			input._editbox:HighlightText()
		end
	end)

	confirmBtn:SetOnClick(function()
		local name = F.Backups.TrimName(input:GetText() or '')
		local ok, err = F.Backups.Save(name)
		if(ok) then
			closeInputs()
		else
			container._setError(err)
		end
	end)
	cancelBtn:SetOnClick(closeInputs)

	saveInputContainer = container
	reflow()
end)
```

- [ ] **Step 3: Wire Import as Snapshot**

The Import-as-Snapshot flow is two inputs (paste box + name field) stacked. Add this block immediately after the Save wiring:

```lua
importBtn:SetOnClick(function()
	closeInputs()

	local defaultName = 'Imported ' .. date('%Y-%m-%d %H:%M')

	local container = CreateFrame('Frame', nil, inner)
	Widgets.SetSize(container, innerW, EDITBOX_H + 22 + LABEL_H + BUTTON_H + 24)

	local pasteBox = Widgets.CreateEditBox(container, nil, innerW, EDITBOX_H, 'multiline')
	pasteBox:SetPlaceholder('Paste import string here…')
	pasteBox:ClearAllPoints()
	Widgets.SetPoint(pasteBox, 'TOPLEFT', container, 'TOPLEFT', 0, 0)

	local nameInput = Widgets.CreateEditBox(container, nil, innerW, 22)
	nameInput:SetPlaceholder('Snapshot name')
	nameInput:SetText(defaultName)
	nameInput:ClearAllPoints()
	Widgets.SetPoint(nameInput, 'TOPLEFT', pasteBox, 'BOTTOMLEFT', 0, -6)

	local errorFS = Widgets.CreateFontString(container, C.Font.sizeSmall, C.Colors.textSecondary)
	errorFS:ClearAllPoints()
	Widgets.SetPoint(errorFS, 'TOPLEFT', nameInput, 'BOTTOMLEFT', 0, -4)
	errorFS:SetWidth(innerW)
	errorFS:SetWordWrap(true)
	errorFS:SetText('')

	local confirmBtn = Widgets.CreateButton(container, 'Save as Snapshot', 'accent',    140, BUTTON_H)
	local cancelBtn  = Widgets.CreateButton(container, 'Cancel',           'secondary',  80, BUTTON_H)

	confirmBtn:ClearAllPoints()
	Widgets.SetPoint(confirmBtn, 'TOPLEFT', errorFS, 'BOTTOMLEFT', 0, -4)
	cancelBtn:ClearAllPoints()
	Widgets.SetPoint(cancelBtn, 'LEFT', confirmBtn, 'RIGHT', 6, 0)

	local function setError(msg)
		if(msg and msg ~= '') then
			errorFS:SetTextColor(1, 0.3, 0.3, 1)
			errorFS:SetText(msg)
		else
			errorFS:SetText('')
		end
	end

	confirmBtn:SetOnClick(function()
		local raw = pasteBox:GetText() or ''
		raw = raw:match('^%s*(.-)%s*$')
		if(raw == '') then
			setError('Paste an import string to continue.')
			return
		end
		local name = F.Backups.TrimName(nameInput:GetText() or '')
		local nameOk, nameErr = F.Backups.ValidateName(name)
		if(not nameOk) then
			setError(nameErr)
			return
		end
		local ok, err = F.Backups.SaveFromPayload(name, raw)
		if(ok) then
			closeInputs()
		else
			setError(err or 'Import failed.')
		end
	end)
	cancelBtn:SetOnClick(closeInputs)

	importInputContainer = container
	reflow()
end)
```

- [ ] **Step 4: Place the input containers in `reflow`**

Inside `reflow`, after `y = B.PlaceWidget(importBtn, inner, y, BUTTON_H)` and before `rebuildRows()`, add:

```lua
if(saveInputContainer) then
	y = B.PlaceWidget(saveInputContainer, inner, y, saveInputContainer:GetHeight())
end
if(importInputContainer) then
	y = B.PlaceWidget(importInputContainer, inner, y, importInputContainer:GetHeight())
end
```

- [ ] **Step 5: Lint**

Run: `luacheck Settings/Cards/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 6: Reload and test both flows**

In-game: `/reload`. Open Settings → Backups.

**Save flow:**
- Click `Save Current As…`
- Input appears pre-filled with `Snapshot 2026-04-13 HH:MM`
- Click Save — the row appears at the top of the user list
- Click `Save Current As…` again, type the same name, press Save — error "A snapshot with that name already exists."
- Click Cancel — the input disappears

**Import-as-Snapshot flow:**
- Export a full profile from the Export card and copy the string
- Click `Import as Snapshot…`
- Paste the string into the top box, keep the default name, click Save as Snapshot
- A new row appears labeled `Imported 2026-04-13 HH:MM`
- Verify `/run print(FramedSnapshotsDB.snapshots['Imported 2026-04-13 HH:MM'].version)` shows the version from the import payload, not the current addon version

- [ ] **Step 7: Commit**

```bash
git add Settings/Cards/Backups.lua
git commit -m "Wire Save Current As and Import as Snapshot inline inputs"
```

---

## Task 15: Load, Delete, Rename row actions with combat guards and undo toasts

**Why:** Completes three of the four row actions. Load needs a confirmation dialog, pre-load auto-snapshot capture, undo toast, and combat lockdown guard. Delete needs an in-memory hold + undo toast. Rename needs inline field editing with validation.

**Files:**

- Modify: `Settings/Cards/Backups.lua`

- [ ] **Step 1: Combat-guard helper**

At the top of the row helpers section in `Settings/Cards/Backups.lua`, add:

```lua
local function guardCombat()
	if(InCombatLockdown()) then
		Widgets.ShowToast({
			text     = "Can't load snapshots in combat.",
			duration = 4,
		})
		return false
	end
	return true
end
```

- [ ] **Step 2: Wire Load action**

Inside `createSnapshotRow`, after the button creation block, add:

```lua
btnLoad:SetOnClick(function()
	if(not guardCombat()) then return end

	local msg = 'Load snapshot "' .. displayName .. '"?\n\n' ..
		'Version: ' .. (wrapper.version or 'unknown') .. '\n' ..
		'Saved: ' .. formatTimestamp(wrapper.timestamp) .. '\n\n' ..
		'This will replace your current Framed settings. ' ..
		'Framed will automatically keep a "Before last load" backup so you can revert.'

	Widgets.ShowConfirmDialog(
		'Confirm Load',
		msg,
		function()
			local ok, err = F.Backups.Load(displayName)
			if(ok) then
				Widgets.ShowToast({
					text     = 'Snapshot loaded.',
					duration = 12,
					action = {
						text    = 'Undo',
						onClick = function()
							F.Backups.Load(F.Backups.AUTO_PRELOAD)
						end,
					},
				})
			else
				Widgets.ShowToast({
					text     = 'Load failed: ' .. (err or 'unknown error'),
					duration = 6,
				})
				-- If the error is specifically a decode failure, mark the row
				if(err and err:find('corrupted')) then
					row:MarkCorrupted()
				end
			end
		end,
		nil)
end)
```

- [ ] **Step 3: Wire Delete action**

Immediately after the Load wiring inside `createSnapshotRow`:

```lua
btnDelete:SetOnClick(function()
	local removed = F.Backups.Delete(displayName)
	if(not removed) then return end

	Widgets.ShowToast({
		text     = 'Deleted ' .. displayName .. '.',
		duration = 10,
		action = {
			text    = 'Undo',
			onClick = function()
				F.Backups.RestoreDeleted(displayName, removed)
			end,
		},
	})
end)
```

Delete is allowed in combat since it only touches SavedVariables, not secure frames.

- [ ] **Step 4: Wire Rename action (inline)**

After the Delete wiring:

```lua
btnRename:SetOnClick(function()
	if(isAutomatic) then return end -- belt-and-suspenders; button is hidden

	-- Convert the name label into an editable input
	nameFS:Hide()

	local edit = Widgets.CreateEditBox(row, nil, 180, 22)
	edit:SetText(displayName)
	edit:ClearAllPoints()
	Widgets.SetPoint(edit, 'TOPLEFT', row, 'TOPLEFT', 8, -6)

	if(edit._editbox) then
		edit._editbox:SetFocus()
		edit._editbox:HighlightText()
		edit._editbox:SetScript('OnEscapePressed', function()
			edit:Hide()
			nameFS:Show()
		end)
		edit._editbox:SetScript('OnEnterPressed', function()
			local newName = F.Backups.TrimName(edit:GetText() or '')
			local ok, err = F.Backups.Rename(displayName, newName)
			if(ok) then
				edit:Hide()
				-- BACKUP_CREATED + BACKUP_DELETED events will trigger rebuildRows
			else
				Widgets.ShowToast({
					text     = 'Rename failed: ' .. (err or 'unknown error'),
					duration = 5,
				})
			end
		end)
	end
end)
```

- [ ] **Step 5: Lint**

Run: `luacheck Settings/Cards/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 6: Reload and test**

In-game: `/reload`. Open Backups. Save a test snapshot.

**Delete + undo:**
- Click Delete on the test snapshot
- Toast appears: "Deleted Test. [Undo]"
- Click Undo within 10 seconds — the row returns
- Delete again and let the toast fade — verify the row is gone and stays gone

**Rename:**
- Click Rename on a user snapshot — name label becomes an editable field, pre-filled and selected
- Type a new name, press Enter — row updates with the new name
- Rename another to something that exists — toast shows "A snapshot with that name already exists."
- Press Escape mid-rename — the input closes and the original name is preserved

**Load + undo:**
- Click Load on a user snapshot
- Confirmation dialog appears — click Yes
- Settings briefly reload (apply fires `IMPORT_APPLIED`), toast appears: "Snapshot loaded. [Undo]"
- Click Undo — the pre-load auto snapshot loads, settings revert

**Combat guard:**
- Enter combat (pull a dummy if needed)
- Click Load on any row — toast says "Can't load snapshots in combat."
- No confirmation dialog opens

- [ ] **Step 7: Commit**

```bash
git add Settings/Cards/Backups.lua
git commit -m "Wire Load, Delete, Rename row actions with undo toasts and combat guard"
```

---

## Task 16: Export row action with scope chooser

**Why:** The row Export action needs to support both whole-snapshot export and single-layout extraction from the snapshot. Payload is decoded once and cached while the export area is open so re-selecting layouts doesn't re-run LibDeflate.

**Files:**

- Modify: `Settings/Cards/Backups.lua`

- [ ] **Step 1: Append Export wiring inside `createSnapshotRow`**

After the Rename wiring:

```lua
btnExport:SetOnClick(function()
	-- Lazy-decode the payload once per export open
	local parsed, decodeErr = F.Backups.DecodeWrapper(wrapper)
	if(not parsed) then
		row:MarkCorrupted()
		Widgets.ShowToast({
			text     = 'This snapshot is corrupted and can\'t be exported.',
			duration = 5,
		})
		return
	end

	-- Close any existing export popup by destroying it
	if(row._exportArea) then
		row._exportArea:Hide()
		row._exportArea = nil
		return
	end

	local area = CreateFrame('Frame', nil, row)
	Widgets.SetSize(area, row:GetWidth() - 16, EDITBOX_H + DROPDOWN_H + 16)
	area:ClearAllPoints()
	Widgets.SetPoint(area, 'TOPLEFT', row, 'BOTTOMLEFT', 8, -4)
	area:SetFrameStrata('DIALOG')

	-- Scope dropdown: 'Whole snapshot' + each layout name
	local scopeDropdown = Widgets.CreateDropdown(area, 220)
	scopeDropdown:ClearAllPoints()
	Widgets.SetPoint(scopeDropdown, 'TOPLEFT', area, 'TOPLEFT', 0, 0)

	local items = { { text = 'Whole snapshot', value = '__whole__' } }
	if(parsed.scope == 'full' and type(parsed.data) == 'table' and type(parsed.data.presets) == 'table') then
		for layoutName in next, parsed.data.presets do
			items[#items + 1] = { text = layoutName, value = layoutName }
		end
	end
	scopeDropdown:SetItems(items)
	scopeDropdown:SetValue('__whole__')

	-- Copyable text box
	local copyBox = Widgets.CreateEditBox(area, nil, area:GetWidth(), EDITBOX_H, 'multiline')
	copyBox:ClearAllPoints()
	Widgets.SetPoint(copyBox, 'TOPLEFT', scopeDropdown, 'BOTTOMLEFT', 0, -6)

	local function renderExport(scopeValue)
		if(scopeValue == '__whole__') then
			-- Whole snapshot: re-encode the already-decoded payload via Export
			-- (we could also just re-emit the stored wrapper.payload string, but
			-- that's the print-encoded Backups-envelope form; callers of the
			-- export string expect a fresh envelope — so re-run Export)
			local encoded = F.ImportExport.Export(parsed.data, 'full')
			copyBox:SetText(encoded or '')
		else
			-- Single layout
			local layoutTable = parsed.data.presets and parsed.data.presets[scopeValue]
			if(not layoutTable) then
				copyBox:SetText('(layout missing from snapshot)')
				return
			end
			local encoded, err = F.ImportExport.ExportLayoutData(scopeValue, layoutTable)
			copyBox:SetText(encoded or ('Export failed: ' .. (err or 'unknown')))
		end
		if(copyBox._editbox) then
			copyBox._editbox:SetFocus()
			copyBox._editbox:HighlightText()
		end
	end

	scopeDropdown:SetOnSelect(renderExport)
	renderExport('__whole__')

	row._exportArea = area
	_ = decodeErr -- suppress unused-local lint
end)
```

- [ ] **Step 2: Lint**

Run: `luacheck Settings/Cards/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 3: Reload and verify**

In-game: `/reload`. Open Backups. Click Export on a user snapshot with a full-profile payload. A dropdown + copyable text box should appear below the row. The dropdown defaults to "Whole snapshot" and the text box holds the encoded string. Switch the dropdown to a specific layout name — the text box updates. Click Export again — the export area closes.

- [ ] **Step 4: Commit**

```bash
git add Settings/Cards/Backups.lua
git commit -m "Add row Export action with scope chooser and decoded payload cache"
```

---

## Task 17: Refactor Import card — verification UI + pre-import capture + combat guard

**Why:** The Import card loses its mode switch entirely, gains a live verification preview that runs on paste (debounced), and always captures a `__auto_preimport` automatic snapshot before applying. The combat guard prevents ApplyImport from firing during lockdown.

**Files:**

- Modify: `Settings/Cards/Backups.lua`

- [ ] **Step 1: Build the flattened key set derivation helper**

Add at the top of `Settings/Cards/Backups.lua`, below the constants:

```lua
-- ============================================================
-- Verification: flattened key-set derivation from current defaults
-- ============================================================

local flattenedDefaults  -- cache; built lazily on first use

local function flattenInto(set, prefix, tbl)
	for k, v in next, tbl do
		local path = prefix == '' and tostring(k) or (prefix .. '.' .. tostring(k))
		if(type(v) == 'table') then
			flattenInto(set, path, v)
		else
			set[path] = true
		end
	end
end

local function buildFlattenedDefaults()
	local set = {}

	-- Config defaults (general, minimap, char)
	-- We approximate by flattening FramedDB's current shape; anything that
	-- EnsureDefaults backfilled is present.
	if(FramedDB and FramedDB.general) then flattenInto(set, 'general', FramedDB.general) end
	if(FramedDB and FramedDB.minimap) then flattenInto(set, 'minimap', FramedDB.minimap) end
	if(FramedCharDB)                  then flattenInto(set, 'char',    FramedCharDB)     end

	-- Preset shape: flatten one representative default preset (Party) so the
	-- per-unit key structure is captured.
	if(F.PresetDefaults and F.PresetDefaults.GetAll) then
		local all = F.PresetDefaults.GetAll()
		local anyPreset = all and next(all) and all[next(all)]
		if(anyPreset) then
			flattenInto(set, 'presets.<name>', anyPreset)
		end
	end

	return set
end

local function getFlattenedDefaults()
	if(not flattenedDefaults) then
		flattenedDefaults = buildFlattenedDefaults()
	end
	return flattenedDefaults
end

local function classifyImportKeys(parsed)
	local defaults = getFlattenedDefaults()
	local importSet = {}
	if(parsed.scope == 'full' and type(parsed.data) == 'table') then
		if(parsed.data.general) then flattenInto(importSet, 'general', parsed.data.general) end
		if(parsed.data.minimap) then flattenInto(importSet, 'minimap', parsed.data.minimap) end
		if(parsed.data.char)    then flattenInto(importSet, 'char',    parsed.data.char)    end
		-- For presets, take the first layout as representative
		if(parsed.data.presets) then
			local _, firstLayout = next(parsed.data.presets)
			if(firstLayout) then
				flattenInto(importSet, 'presets.<name>', firstLayout)
			end
		end
	elseif(parsed.scope == 'layout' and parsed.data and parsed.data.layout) then
		flattenInto(importSet, 'presets.<name>', parsed.data.layout)
	end

	local ignored, missing = {}, {}
	for path in next, importSet do
		if(not defaults[path]) then ignored[#ignored + 1] = path end
	end
	for path in next, defaults do
		if(not importSet[path]) then missing[#missing + 1] = path end
	end
	table.sort(ignored)
	table.sort(missing)
	return ignored, missing
end
```

- [ ] **Step 2: Rewrite `F.BackupsCards.Import` with the verification UI**

Replace the entire `function F.BackupsCards.Import(parent, width)` block with:

```lua
function F.BackupsCards.Import(parent, width)
	local card, inner, y = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	-- Paste box
	local importBox = Widgets.CreateEditBox(inner, nil, innerW, EDITBOX_H, 'multiline')
	importBox:SetPlaceholder('Paste import string here…')
	y = B.PlaceWidget(importBox, inner, y, EDITBOX_H)

	-- Verification section (hidden when paste box is empty)
	local verifyHeader = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	verifyHeader:SetText('── Verification ──')
	local verifyRowsFS = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
	verifyRowsFS:SetWidth(innerW)
	verifyRowsFS:SetWordWrap(true)
	verifyRowsFS:SetJustifyH('LEFT')

	local importBtn = Widgets.CreateButton(inner, 'Import', 'accent', 100, BUTTON_H)

	local statusFS = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textSecondary)
	statusFS:SetWidth(innerW)
	statusFS:SetWordWrap(true)
	statusFS:SetText('')

	local currentParsed  -- cached parsed payload from last successful parse

	local function renderVerification(parsed, parseErr)
		if(parseErr) then
			verifyHeader:Show()
			verifyRowsFS:Show()
			verifyRowsFS:SetTextColor(1, 0.3, 0.3, 1)
			verifyRowsFS:SetText('✗ Format invalid: ' .. parseErr)
			importBtn:SetEnabled(false)
			return
		end

		verifyHeader:Show()
		verifyRowsFS:Show()
		verifyRowsFS:SetTextColor(
			C.Colors.textSecondary[1],
			C.Colors.textSecondary[2],
			C.Colors.textSecondary[3],
			C.Colors.textSecondary[4] or 1)

		local lines = {}
		lines[#lines + 1] = '✓ Format valid'

		local version = (parsed.data and parsed.data.version) or 'unknown'
		local isStale = F.Version and (F.Version.IsStaleOlder(version, F.version) or F.Version.IsStaleNewer(version, F.version))
		lines[#lines + 1] = '✓ Version: ' .. version .. (isStale and ' [!] (stale)' or '')

		local scope = parsed.scope or 'unknown'
		lines[#lines + 1] = '✓ Scope: ' .. (scope == 'full' and 'Everything' or 'Single Layout')

		if(parsed.scope == 'full' and parsed.data and parsed.data.presets) then
			local total, overwrite, add = 0, 0, 0
			for layoutName in next, parsed.data.presets do
				total = total + 1
				if(FramedDB.presets and FramedDB.presets[layoutName]) then
					overwrite = overwrite + 1
				else
					add = add + 1
				end
			end
			lines[#lines + 1] = '✓ Contains ' .. total .. ' layouts, ' .. overwrite .. ' will be overwritten, ' .. add .. ' added'
		end

		local ignored, missing = classifyImportKeys(parsed)
		if(#ignored > 0) then
			lines[#lines + 1] = '⚠ ' .. #ignored .. ' settings will be ignored (from an older version)'
		end
		if(#missing > 0) then
			lines[#lines + 1] = 'ℹ ' .. #missing .. ' new settings will use defaults'
		end

		verifyRowsFS:SetText(table.concat(lines, '\n'))
		importBtn:SetEnabled(true)
	end

	local debounceTimer
	local function scheduleVerify()
		if(debounceTimer) then debounceTimer:Cancel() end
		debounceTimer = C_Timer.NewTimer(0.25, function()
			local raw = importBox:GetText() or ''
			raw = raw:match('^%s*(.-)%s*$') or ''
			if(raw == '') then
				verifyHeader:Hide()
				verifyRowsFS:Hide()
				importBtn:SetEnabled(false)
				currentParsed = nil
				return
			end
			local parsed, err = F.ImportExport.Import(raw)
			currentParsed = parsed
			renderVerification(parsed, err)
		end)
	end

	importBox:SetScript('OnTextChanged', scheduleVerify)
	verifyHeader:Hide()
	verifyRowsFS:Hide()
	importBtn:SetEnabled(false)

	importBtn:SetOnClick(function()
		if(InCombatLockdown()) then
			Widgets.ShowToast({ text = "Can't load snapshots in combat.", duration = 4 })
			return
		end
		if(not currentParsed) then return end

		Widgets.ShowConfirmDialog(
			'Confirm Import',
			'Replace your current Framed settings with this import?\nFramed will save an automatic "Before last import" backup first.',
			function()
				F.ImportExport.ApplyImport(currentParsed)
				importBox:SetText('')
				setTextColor(statusFS, C.Colors.textActive)
				statusFS:SetText('Import successful.')
				Widgets.ShowToast({
					text     = 'Import applied.',
					duration = 10,
					action = {
						text    = 'Undo',
						onClick = function()
							F.Backups.Load(F.Backups.AUTO_PREIMPORT)
						end,
					},
				})
			end,
			function()
				setTextColor(statusFS, C.Colors.textSecondary)
				statusFS:SetText('Import cancelled.')
			end)
	end)

	-- Place verify header + rows + button + status in reflow
	y = B.PlaceWidget(verifyHeader, inner, y, LABEL_H)
	y = B.PlaceWidget(verifyRowsFS, inner, y, LABEL_H * 8)
	y = B.PlaceWidget(importBtn,    inner, y, BUTTON_H)
	y = B.PlaceWidget(statusFS,     inner, y, LABEL_H * 2)

	Widgets.EndCard(card, parent, y)
	return card
end
```

- [ ] **Step 3: Lint**

Run: `luacheck Settings/Cards/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 4: Reload and verify**

In-game: `/reload`. Open Backups. Focus the Import card's paste box. Paste a valid full export string — after 250ms, verification rows appear: Format valid, Version, Scope, Layout counts, possibly Ignored/New defaults. Click Import — confirmation dialog → Yes → toast: "Import applied. [Undo]" with a working Undo. Paste garbage — verification shows "✗ Format invalid" and the Import button is disabled.

- [ ] **Step 5: Commit**

```bash
git add Settings/Cards/Backups.lua
git commit -m "Refactor Import card with live verification, pre-import capture, and combat guard"
```

---

## Task 18: Export card polish and ImportExport cleanup

**Why:** Rename the scope dropdown label `Full Profile → Everything`, add the "use Save Current As to keep a copy" hint, and delete the `profiles = {}` dead field from `Core/Config.lua`.

**Files:**

- Modify: `Settings/Cards/Backups.lua`
- Modify: `Core/Config.lua`

- [ ] **Step 1: Update the Export card scope dropdown label**

In `Settings/Cards/Backups.lua`, find the `scopeDropdown:SetItems` call inside `F.BackupsCards.Export` and update:

```lua
scopeDropdown:SetItems({
	{ text = 'Everything',   value = SCOPE_FULL },
	{ text = 'Single Layout', value = SCOPE_LAYOUT },
})
```

- [ ] **Step 2: Add the hint text below the Export button**

Inside the `Export` function, immediately after `local exportBtn = Widgets.CreateButton(...)`, add:

```lua
local hintFS = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
hintFS:SetWidth(innerW)
hintFS:SetWordWrap(true)
hintFS:SetJustifyH('LEFT')
hintFS:SetText("To save a copy for yourself, use Save Current As\xE2\x80\xA6 in the Snapshots card above. Export is for sharing with other users.")
```

Inside the `reflow` function, after `y = B.PlaceWidget(exportBtn, inner, y, BUTTON_H)` and before `y = B.PlaceWidget(exportBox, ...)`, add:

```lua
y = B.PlaceWidget(hintFS, inner, y, LABEL_H * 2)
```

- [ ] **Step 3: Remove the dead `profiles` field from `Core/Config.lua`**

Open `Core/Config.lua`. Find `accountDefaults`:

```lua
accountDefaults = {
	general  = { ... },
	minimap  = { hide = false },
	presets  = {},
	profiles = {},   -- ← remove this line
}
```

Delete the `profiles = {},` line.

- [ ] **Step 4: Lint**

Run: `luacheck Settings/Cards/Backups.lua Core/Config.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 5: Reload and verify**

In-game: `/reload`. Open Backups → Export. The scope dropdown now reads `Everything`. The hint text sits below the Export button. Run `/run print(FramedDB.profiles)` — should be `nil` (the field is no longer seeded by `EnsureDefaults`, and the existing saved value from prior sessions will be cleaned up on the next save since nothing references it).

- [ ] **Step 6: Commit**

```bash
git add Settings/Cards/Backups.lua Core/Config.lua
git commit -m "Polish Export card labels and remove dead profiles config field"
```

---

## Task 19: Sidebar size-threshold warning badge

**Why:** Visible indicator on the Backups sidebar entry when snapshot storage exceeds 100 KB. Requires extending `Settings/Sidebar.lua` with a badge API and wiring the Backups panel to toggle it.

**Files:**

- Modify: `Settings/Sidebar.lua`
- Modify: `Settings/Panels/Backups.lua`

- [ ] **Step 1: Read the current sidebar button creation code**

Run: `Read Settings/Sidebar.lua` around lines 130–210 to see the button-factory pattern (icon rendering, hover/selected states).

- [ ] **Step 2: Add the badge rendering to sidebar button creation**

In `Settings/Sidebar.lua`, inside the block where each button is built (near the `if(panelInfo.icon) then` block you already have), add after the icon setup:

```lua
-- Right-side warning badge (shown via SetPanelBadge API)
local badge = btn:CreateTexture(nil, 'OVERLAY')
badge:SetSize(10, 10)
badge:SetPoint('RIGHT', btn, 'RIGHT', -8, 0)
badge:SetColorTexture(1, 0.55, 0.1, 1) -- warning orange
badge:Hide()
btn._badge = badge
```

- [ ] **Step 3: Expose a `SetPanelBadge` API**

Still in `Settings/Sidebar.lua`, find the section that exports the Sidebar module (or add a new export at the bottom if none exists). Add:

```lua
local panelButtons = {}

-- Track buttons by panel id so SetPanelBadge can look them up
-- (register this immediately after `btn._badge = badge` in the button
-- factory — use `panelButtons[panelInfo.id] = btn` to store the mapping)
```

Find the spot in the button factory immediately after `btn._badge = badge` and add:

```lua
panelButtons[panelInfo.id] = btn
```

Then at the bottom of `Settings/Sidebar.lua`, add the public function on the Settings namespace:

```lua
function F.Settings.SetPanelBadge(panelId, show)
	local btn = panelButtons[panelId]
	if(not btn or not btn._badge) then return end
	if(show) then
		btn._badge:Show()
	else
		btn._badge:Hide()
	end
end
```

- [ ] **Step 4: Trigger the badge from `Settings/Panels/Backups.lua`**

Inside the panel's `create` callback, after the grid is built and cards are registered, add:

```lua
local BADGE_THRESHOLD = 100 * 1024 -- 100 KB

local function updateBadge()
	if(not FramedSnapshotsDB or not FramedSnapshotsDB.snapshots) then
		F.Settings.SetPanelBadge('backups', false)
		return
	end
	local total = 0
	for _, wrapper in next, FramedSnapshotsDB.snapshots do
		total = total + (wrapper.sizeBytes or 0)
	end
	F.Settings.SetPanelBadge('backups', total >= BADGE_THRESHOLD)
end

updateBadge()

F.EventBus:Register('BACKUP_CREATED', updateBadge, 'BackupsPanel.badge.created')
F.EventBus:Register('BACKUP_DELETED', updateBadge, 'BackupsPanel.badge.deleted')
F.EventBus:Register('BACKUP_LOADED',  updateBadge, 'BackupsPanel.badge.loaded')
```

- [ ] **Step 5: Lint**

Run: `luacheck Settings/Sidebar.lua Settings/Panels/Backups.lua --config .luacheckrc`

Expected: 0 warnings, 0 errors.

- [ ] **Step 6: Reload and verify**

In-game: `/reload`. Check the Backups sidebar entry — no badge yet. Save a big test snapshot to push over 100 KB:

```lua
/run for i = 1, 60 do Framed.Backups.Save('Bulk test ' .. i) end
```

(Each snapshot is ~2 KB; 60 × 2 KB = 120 KB.)

Expected: The Backups sidebar button gains a small orange dot on its right edge. Delete a bunch of snapshots until total is under 100 KB — badge disappears.

- [ ] **Step 7: Commit**

```bash
git add Settings/Sidebar.lua Settings/Panels/Backups.lua
git commit -m "Add sidebar size-threshold badge for Backups panel"
```

---

## Task 20: Final smoke test + help command update

**Why:** End-to-end check that covers every feature path in one session, plus update `/framed help` to reference the new Backups panel (not Profiles). No new code beyond the help text update.

**Files:**

- Modify: `Init.lua` (help text)

- [ ] **Step 1: Update help text**

In `Init.lua`, find the `elseif(cmd == 'help') then` block. Update the lines:

```lua
print('  /framed reset all — Reset all settings to defaults (a backup is saved)')
print('  /framed restore — Restore from the most recent reset backup')
```

to:

```lua
print('  /framed reset all — Reset all settings to defaults (saves a Backups snapshot)')
print('  /framed restore — Restore the most recent reset backup from the Backups panel')
```

- [ ] **Step 2: Lint**

Run: `luacheck . --config .luacheckrc`

Expected: 0 warnings across the entire codebase.

- [ ] **Step 3: Full smoke test walkthrough**

In-game: `/reload`. Execute this sequence and verify each step:

1. **Sidebar rename.** Open Settings. Sidebar shows `Backups` where `Profiles` used to be.
2. **Empty state.** If there are no user snapshots yet (fresh install), the Snapshots card shows the empty-state copy. Automatic snapshots are hidden until a user snapshot exists.
3. **Login auto-snapshot.** `/run print(FramedSnapshotsDB.snapshots['__auto_login'].autoKind)` → `login`.
4. **Save Current As.** Click Save Current As, accept the default name, save. Row appears. Automatic rows now render at the bottom of the list in muted style.
5. **Most-recent-first sort.** Save three more snapshots with different names. Verify they appear top-down newest to oldest.
6. **Name validation.** Try to save an empty name, a 65-char name, `__auto_login`, and an existing name. Each shows the appropriate inline error.
7. **Rename.** Click Rename on a snapshot, type a new name, press Enter. Row updates. Try renaming to an existing name — toast shows error.
8. **Export row action.** Click Export on a snapshot. Scope dropdown + text box appear. Switch between "Whole snapshot" and a specific layout — text box updates. Click Export again — popup closes.
9. **Import as Snapshot.** Copy the Export card's full-profile string. Click Import as Snapshot, paste, save. A new row appears with the `Imported …` label and the version from the payload.
10. **Import card verification.** Paste a full string into the Import card's paste box. After 250ms, verification rows appear. Click Import → confirmation → Yes → toast "Import applied. [Undo]" → click Undo within 10 seconds → settings revert.
11. **Pre-import auto snapshot.** `/run print(FramedSnapshotsDB.snapshots['__auto_preimport'] ~= nil)` → `true`.
12. **Load row action.** Click Load on a user snapshot → confirmation with metadata → Yes → brief reload of settings, then toast "Snapshot loaded. [Undo]" with working Undo.
13. **Combat guard.** Enter combat. Click Load on any row → toast "Can't load snapshots in combat.", no dialog opens.
14. **Delete + undo.** Click Delete on a user snapshot → toast "Deleted …. [Undo]" → click Undo → row returns. Delete again and wait 11 seconds — row is permanently gone.
15. **Stale version rendering.**

```lua
/run FramedSnapshotsDB.snapshots['Stale demo'] = { version = 'v0.5.0-alpha', timestamp = time(), automatic = false, layoutCount = 3, sizeBytes = 2000, payload = 'garbage' }; Framed.EventBus:Fire('BACKUP_CREATED', 'Stale demo', false)
```

Row shows `v0.5.0-alpha` in red with `[!]`. Hover the `[!]` for the tooltip.

16. **Corrupted payload handling.** Click Load on "Stale demo" (payload is `'garbage'`). Toast: "Load failed: …". Row gains a red `[!]` in the top-right and Load/Export buttons disable. Delete still works.
17. **Size threshold badge.** Bulk-save until total exceeds 100 KB. Sidebar Backups button gains a warning dot. Delete down below 100 KB — dot disappears.
18. **`/framed reset all`.** Run it. Dialog appears, confirm. Reload. `FramedSnapshotsDB.snapshots` contains a `Before reset (YYYY-MM-DD HH:MM)` entry. Run `/framed restore` → confirm → settings come back.
19. **Migration.** If you had an existing `FramedBackupDB` before this branch landed, verify the first reload after Task 9 captured it as `Legacy backup` in the snapshot list and `FramedBackupDB` is now `nil`.
20. **Export card hint.** Open the Export card — see the "use Save Current As…" hint below the button.

- [ ] **Step 4: Commit help text and mark plan complete**

```bash
git add Init.lua
git commit -m "Update /framed help to reference the Backups panel"
```

- [ ] **Step 5: Run the final lint check**

```bash
luacheck . --config .luacheckrc
```

Expected: 0 warnings, 0 errors across the entire codebase.

- [ ] **Step 6: Final commit marker**

No additional code; if everything passed the smoke test, the branch is ready to merge.

```bash
git log --oneline main..HEAD | head -25
```

Review the commit list. The 20 task commits should all be present.

---

## Post-implementation checklist (not a task)

Before handing off to the version-bump + release flow:

1. Run `./tools/sync-changelog.lua` — this regenerates the About card's Changelog table (nothing to regenerate yet since the CHANGELOG.md hasn't been updated, but run it to confirm it's a no-op).
2. Update `CHANGELOG.md` with a `## v0.9.0-alpha` block (Backups is a meaningful enough change to justify a MINOR bump per the stale-version release cadence discussion in the spec). The block should at minimum mention: Backups panel (renamed from Profiles), named snapshots with auto login/pre-import/pre-load safety nets, pre-import verification preview, stale-version warnings, corrupted-payload handling, migration from `FramedBackupDB`, and the removal of Import merge mode.
3. Run `./tools/sync-changelog.lua` again to push the new block into the About card.
4. Bump `## Version:` in `Framed.toc` to `0.9.0-alpha`.
5. Fast-forward `working` and `main` to pick up all 20 task commits + the version bump.
6. Push — `auto-tag.yml` creates the `v0.9.0-alpha` tag and `release.yml` triggers CurseForge packaging + Discord post with the trimmed current-version changelog block (from the fix landed in the previous session).
