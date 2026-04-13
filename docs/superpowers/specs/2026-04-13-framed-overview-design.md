# Framed Overview — Design

**Status:** Approved 2026-04-13
**Replaces:** `Onboarding/Tour.lua` (deleted — all 336 lines; anchor fields it referenced were never populated, so the tour visibly did nothing beyond re-showing the settings window)

## Goal

Give new users a 6-page illustrated walkthrough of what Framed is and how its major surfaces (layouts, edit mode, settings cards, aura indicators, defensive/external tracking) fit together. Launches automatically on first run after the setup wizard, and can be re-launched manually from the SetupWizard card in Appearance.

## Non-Goals

- Step-by-step anchored tour of the live UI (the previous `Tour.lua` tried this and was broken by design — too tightly coupled to Settings internals).
- Interactive tutorials (“click this button now”). The overview *tells*, it doesn't drive.
- Cross-session resume. Relaunching always starts at page 1.
- Deep-dive documentation. The overview is an orientation, not a manual.

## 1. Files

**New:**
- `Onboarding/Overview.lua` — modal frame, pip frame, page registry, lifecycle, public API. If this file grows beyond the project's ~500-line soft cap, split illustrations into a sibling `Onboarding/OverviewIllustrations.lua`. User has pre-approved that split.

**Deleted:**
- `Onboarding/Tour.lua` — 336 lines, unreachable anchors, dead.

**Modified:**
- `Framed.toc` — remove `Onboarding/Tour.lua`, add `Onboarding/Overview.lua` (and `Onboarding/OverviewIllustrations.lua` if split) after `Onboarding/Wizard.lua`.
- `Init.lua` — in the `PLAYER_LOGIN` handler, after the existing `wizardCompleted` check, chain an `overviewCompleted` check that calls `F.Onboarding.ShowOverview()` on a short `C_Timer.After` delay when not in combat, and defers to `PLAYER_REGEN_ENABLED` when in combat.
- `Core/Config.lua` — add `overviewCompleted = false` to `accountDefaults.general`.
- `Settings/Cards/Appearance/SetupWizard.lua` — rename the "Take Tour" button (and its tooltip body copy) to "Take Overview", retarget `OnClick` to `F.Onboarding.ShowOverview()`. Drop the `coming in a future update` chat fallback — the feature is always present.

## 2. State

**Persistent (account-wide, via `F.Config`):**
- `general.overviewCompleted` — boolean, default `false`. Set to `true` only when the user reaches the final page's "Done" button OR clicks "Skip Overview". The close button (`✕`) and minimize button do **not** flip this flag.

**In-session only (module locals in `Overview.lua`):**
- `currentStep` — integer 1..6
- `isMinimized` — boolean
- `modalFrame`, `pipFrame` — lazy-built frames
- No `/reload` resume. Session state lives and dies with the session.

## 3. Modal shell

Single frame built lazily on first `ShowOverview()`. Reuses Wizard's visual language (same backdrop, title font, button widgets) so they feel like siblings.

**Structure:**
- **Strata:** `FULLSCREEN_DIALOG`
- **Size:** ~540 × 380 px
- **Anchor:** `CENTER, UIParent, CENTER, 0, 0`
- **Backdrop:** match `Onboarding/Wizard.lua` (same `Widgets.StartCard` or direct backdrop construction as the wizard uses — reuse, don't re-theme)

**Header row (top, ~40px tall):**
- Left: `Framed Overview` title — matches wizard title font/color.
- Center (or right-aligned): 6-slot progress rail. Each slot is a 16×16 `F.Media.GetIcon('Fluent_Color_Yes')` texture — same checkmark asset Framed uses everywhere else (see `Elements/Status/ReadyCheck.lua:15`, `Preview/PreviewFrame.lua:305`). States:
  - **Completed** (steps `< currentStep`): full color, alpha 1.0.
  - **Current** (step `== currentStep`): full color, alpha 1.0, accent-tinted (use `C.Colors.accent` via `SetVertexColor`).
  - **Future** (steps `> currentStep`): alpha 0.3, desaturated.
  - Spacing: ~6px between slots.
- Far right: two icon buttons at `CLOSE_BTN_SIZE` (20px, matching `Settings/MainFrame.lua`):
  1. **Minimize** — icon asset `F.Media.GetIcon('WindowMinimize')`. **Asset needs to be added to `Media/Icons/`** (see §9). Tooltip: `Minimize`.
  2. **Close** — icon asset `F.Media.GetIcon('Close')`, same as main settings window close. Tooltip: `Close`.
  Both use `Widgets.CreateIconButton` with `SetBackdrop(nil)` + `SetupAccentHover` for consistency with `MainFrame.lua:139-147`.

**Body (middle, fills the rest minus footer):**
- Two-column layout, 8px inter-column gap.
- Left column: ~180 × 220 fixed-size illustration container. `buildIllustration(parent, 180, 220)` is called per page; whatever it builds lives here. When switching pages, the outgoing illustration's frame is released (`SetParent(trashFrame); Hide()`) and a fresh one is built — no reuse.
- Right column: flex. Contains:
  - Page title (large, ~18pt, accent color), anchored top.
  - Body copy (wrapped `FontString`), anchored below title with tight spacing. Uses `widgetW = rightColumnWidth` so wrapping respects the column.

**Footer row (bottom, ~44px tall, separated by a hairline rule):**
- Left: `← Back` button. Disabled on page 1 (greyed via `SetEnabled(false)`).
- Center: `Skip Overview` — rendered as a small text-only label button, not a primary button. Lower visual weight than Back/Next.
- Right: `Next →` button. Accent-styled (primary action). On the last page, its label flips to `Done` and its click handler marks `overviewCompleted = true`.

**Keyboard:**
- Enable keyboard on the modal. `OnKeyDown`:
  - `ESCAPE` → `MinimizeOverview()` (collapse to pip; do NOT close)
  - Everything else → propagate

## 4. Minimize pip

A tiny always-on-top affordance so the user can get the overview back after minimizing.

- **Parent:** `UIParent`
- **Strata:** `FULLSCREEN_DIALOG`
- **Anchor:** `TOPRIGHT, UIParent, TOPRIGHT, -20, -20`
- **Size:** ~140 × 32 px
- **Backdrop:** same card style as the modal, slightly dimmer
- **Contents (left → right):**
  - `Fluent_Color_Yes` icon, 16×16, 4px left inset
  - Label: `Framed Overview — N/6` (N = current step) using `C.Colors.textNormal`
- **Mouse:** `OnEnter` shows a `GameTooltip` with `Resume walkthrough`. `OnClick` calls `RestoreOverview()`.
- **Visibility:** shown only while a session is active AND `isMinimized == true`. Hidden on Done, Skip, Close, and while the modal is visible.

## 5. Page registry

Static ordered list in `Overview.lua`:

```lua
local PAGES = {
    { id = 'welcome',      title = ..., body = ..., buildIllustration = function(parent, w, h) ... end },
    { id = 'layouts',      title = ..., body = ..., buildIllustration = function(parent, w, h) ... end },
    { id = 'editmode',     title = ..., body = ..., buildIllustration = function(parent, w, h) ... end },
    { id = 'cards',        title = ..., body = ..., buildIllustration = function(parent, w, h) ... end },
    { id = 'indicators',   title = ..., body = ..., buildIllustration = function(parent, w, h) ... end },
    { id = 'defensives',   title = ..., body = ..., buildIllustration = function(parent, w, h) ... end },
}
```

| # | id | Title | Body copy (final wording owned by implementer) | Illustration |
|---|---|---|---|---|
| 1 | `welcome` | **Welcome to Framed** | Modern unit frames and raid frames built around live previews, presets, and per-unit settings cards. Use this overview to get oriented — you can revisit it anytime from **Appearance → Setup Wizard**. | **Live widget:** a 3-member mini party preview built from real Framed widgets (reuse `Preview.GetFakeUnits(3)` and whatever helpers the Setup Wizard already uses to render a mock group). |
| 2 | `layouts` | **Layouts & Auto-Switch** | Framed ships layouts for Solo, Party, Raid, Mythic Raid, World Raid, Battleground, and Arena — and swaps them automatically when content changes. You can still edit any layout manually. | **Atlas icon:** `groupfinder-eye-frame` (or equivalent — implementer picks one that reads as “layouts / groups”). ~96px, centered in the left column. |
| 3 | `editmode` | **Edit Mode** | Drag any frame to reposition it. The inline panel jumps you to that frame's settings, and edits stay live until you Save or Discard. | **Atlas icon:** `editmode-new-icon` or similar `editmode-*` atlas. Centered. |
| 4 | `cards` | **Settings Cards** | Each unit has a grid of focused cards — Position, Health, Power, Auras, and more. Pin the ones you use most so they stick to the top of the grid. | **Live widget:** a real `Power Bar` card rendered at full width of the left column. Uses the same builder the Settings page uses, so the user sees an authentic card. |
| 5 | `indicators` | **Buffs, Debuffs & Dispels** | Build custom indicators for specific spells — borders, overlays, or icons. Dispellable debuffs get their own highlight system. | **Live widget:** a border indicator + an overlay indicator side-by-side, both with running cooldown sweeps. Reuse `Preview/PreviewIndicators.lua`-style rendering if available. |
| 6 | `defensives` | **Defensives & Externals** | Track raid cooldowns cast on units — personal defensives on yourself, externals cast on someone else. Same indicator builder UX as buffs and debuffs. | **Live widget:** a single external-style aura icon with glow border, cooldown sweep running. |

**Illustration failure mode:** each `buildIllustration` is wrapped such that if it returns nil or raises (via defensive nil-checks, not `pcall`), the left column is left empty and the text column expands to fill — the page still renders, just without its visual.

**Copy ownership:** final body strings belong to the implementer. The table above describes intent; the implementation sets the actual wording.

## 6. Lifecycle

### First-run auto-show
In `Init.lua`'s `PLAYER_LOGIN` handler, after the existing `wizardCompleted` check:

```lua
if(F.Config:Get('general.wizardCompleted') and not F.Config:Get('general.overviewCompleted')) then
    local function tryShow()
        if(InCombatLockdown()) then
            -- defer to post-combat
            local deferFrame = CreateFrame('Frame')
            deferFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
            deferFrame:SetScript('OnEvent', function(self)
                self:UnregisterAllEvents()
                F.Onboarding.ShowOverview()
            end)
        else
            C_Timer.After(1, function()
                F.Onboarding.ShowOverview()
            end)
        end
    end
    tryShow()
end
```

The wizard also runs on first login. Because the wizard's “Done” sets `wizardCompleted = true` *this session*, the overview's trigger (`wizardCompleted == true`) won't fire until the **next** login — which is the intended flow: wizard, then log in again, then overview.

### Manual launch
`SetupWizard.lua` card's `Take Overview` button calls `F.Onboarding.ShowOverview()` unconditionally. Always starts at page 1 (resets `currentStep = 1` on each `ShowOverview` entry).

### Next on last page (Done)
- Set `general.overviewCompleted = true` via `F.Config:Set`
- Close modal + hide pip

### Skip Overview
- Set `general.overviewCompleted = true`
- Close modal + hide pip

Rationale: Skip is a decisive "I don't want this right now." Nagging the user on every login is worse than under-surfacing the overview. They can always relaunch from the Setup Wizard card.

### Close (`✕`)
- Close modal + hide pip
- **Do not** change `overviewCompleted`.
- Consequence: first-run will re-prompt on the next login. Manual relaunch restarts at page 1.

### Minimize (`—`) / Escape
- Hide modal
- Show pip
- Preserve `currentStep`

### Restore (pip click)
- Hide pip
- Show modal
- Rebuild page body at `currentStep` (fresh illustration, fresh text)

### Combat during manual launch
- `ShowOverview()` checks `InCombatLockdown()` at entry. If in combat, print `|cff00ccffFramed:|r Framed Overview cannot be opened in combat.` to `DEFAULT_CHAT_FRAME` and return. Mirrors `Settings.Toggle`/`EditMode.Enter` behavior.
- Auto-show at login uses the deferred path above instead.

### Combat entering mid-session
- If combat starts while the modal is visible: leave it alone. The overview is a display, not a secure frame — it doesn't taint.
- Pip is also left alone.

## 7. Module API

```lua
F.Onboarding.ShowOverview()      -- Open modal at page 1 (resets currentStep)
F.Onboarding.MinimizeOverview()  -- Modal → pip, preserves currentStep
F.Onboarding.RestoreOverview()   -- Pip → modal at preserved currentStep
F.Onboarding.CloseOverview()     -- Hide both; no completion change
F.Onboarding.IsOverviewActive()  -- boolean; true if modal OR pip is currently shown
```

All five functions are tolerant of being called in any state (idempotent where sensible — e.g., `CloseOverview` on an already-closed overview is a no-op).

## 8. Edge cases

- **`/reload` mid-session:** session state lost; next session starts fresh from page 1 if `overviewCompleted == false`. `overviewCompleted` persists as it was when the session started.
- **Relaunch after completion:** starts at page 1, does not un-set `overviewCompleted`.
- **Settings window open when overview launches:** overview sits above it via `FULLSCREEN_DIALOG` strata + higher frame level. User can minimize the overview to interact with settings underneath.
- **Pages 4 & 5 & 6 live widgets:** rely on `F.Config` defaults being initialized (they will be — the overview is only shown after `ADDON_LOADED`, which runs `F.Config:Initialize()` + `EnsureDefaults()`). Each `buildIllustration` still guards against missing helpers (e.g., `if(not F.PreviewIndicators) then return end`) and degrades to an empty left column.
- **Locale:** copy is English-only. No L10n plumbing in this iteration — matches the wizard.
- **ElvUI / other UI overhauls:** overview is a standalone modal anchored to `UIParent`. It shouldn't collide with other addons, but it also doesn't try to hide them.

## 9. Assets

**Existing (already in `Media/Icons/`):**
- `Close.tga` — used for the close button via `F.Media.GetIcon('Close')`, same icon the main settings window's close button uses (`Settings/MainFrame.lua:139`).
- `Fluent_Color_Yes.tga` — used for both the header progress rail and the pip's status icon via `F.Media.GetIcon('Fluent_Color_Yes')`. This is the checkmark Framed already uses for ready-check indicators and preview frames, so the progress rail visually ties into the rest of the UI.
- `WindowMaximize.tga`, `WindowRestore.tga` — present but not used by this feature.

**New asset required:**
- `WindowMinimize.tga` — source the asset from AbstractFramework's media icons directory (`https://github.com/enderneko/AbstractFramework/tree/main/Media/Icons`, file `windowminimize.tga`) and drop it into `Media/Icons/WindowMinimize.tga`. Match the capitalization of the sibling `WindowMaximize.tga` / `WindowRestore.tga` files. **Implementer responsibility:** land the asset before wiring up the minimize button. If for any reason the asset can't be obtained during implementation, stop and ask rather than substituting — the user specifically requested this asset.

No other new textures, fonts, or sounds.

## 10. Testing (manual)

1. **Fresh install path:** delete `FramedDB`, reload. Complete the wizard. Reload again. Verify the overview appears ~1 second after login, centered, with page 1 (Welcome) showing.
2. **Skip:** on page 3, click `Skip Overview`. Verify modal closes, pip hides, and `/run print(FramedDB.account.general.overviewCompleted)` prints `true`. Reload — overview should not auto-show again.
3. **Done:** step through all 6 pages and click `Done`. Verify the completion flag flips and the modal closes.
4. **Close without completing:** on page 2, click `✕`. Verify `overviewCompleted` stays `false`. Reload — overview should auto-show again.
5. **Minimize / restore:** click `—` on page 4. Verify pip appears top-right with `Framed Overview — 4/6`. Click the pip. Verify modal reopens on page 4.
6. **Escape:** on page 5, press Escape. Verify minimize (not close).
7. **Back button:** on page 1, Back should be disabled. On page 2+, Back moves you one step and updates the progress rail.
8. **Combat auto-show:** enter combat, reload, verify overview does not appear during combat. Drop combat, verify it appears.
9. **Combat manual launch:** in combat, click `Take Overview` from the Setup Wizard card. Verify chat error, no modal.
10. **Manual relaunch after completion:** with `overviewCompleted == true`, click `Take Overview`. Verify it opens at page 1.
11. **Progress rail visual states:** at each step, verify past slots are full-color, current slot is accent-tinted, and future slots are 0.3 alpha.
12. **Live widget pages (1, 4, 5, 6):** verify the illustrations render real Framed widgets and don't error in the chat frame. Resize the WoW window; the modal stays centered.

## 11. Open questions

None. All design decisions confirmed with user on 2026-04-13.

## 12. Two points of explicit alignment

Both confirmed with user:

1. **Skip marks completed.** Alternative was "Skip just closes without marking completed." Chosen because Skip is a decisive opt-out and we'd rather under-surface than nag. User approved.
2. **File splitting.** If `Overview.lua` exceeds the ~500-line project cap (likely, with six live-widget `buildIllustration` helpers), split illustrations into `Onboarding/OverviewIllustrations.lua` as a sibling. User pre-approved.
