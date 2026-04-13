# Framed Overview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken `Onboarding/Tour.lua` with a new 6-page illustrated walkthrough (`Onboarding/Overview.lua`) that auto-shows on first run after the wizard and can be relaunched manually from the Setup Wizard card.

**Architecture:** A single lazy-built `FULLSCREEN_DIALOG` modal with a static page registry, a 6-slot progress rail, and a minimize-to-pip affordance. Completion is tracked via a single account-wide `general.overviewCompleted` boolean. Auto-show is gated in `Init.lua` with a combat deferral via `PLAYER_REGEN_ENABLED`.

**Tech Stack:** Lua 5.1 (LuaJIT), WoW addon API, Framed widget library, `F.Config`, `F.EventBus`, `F.Media`, `F.Preview`. No test framework — verification is luacheck + manual `/reload` plus `/run` state queries.

**Spec:** `docs/superpowers/specs/2026-04-13-framed-overview-design.md`

**Conventions used throughout this plan:**
- Every Lua file starts with `local addonName, Framed = ...` then `local F = Framed`.
- Tabs for indentation, parenthesized conditions (`if(cond) then`), single-quoted strings, `for _, v in next, t do` iteration.
- Commit after each task with a short subject line and push to `origin/working-testing`. User has a standing feedback rule: "commit + push to feature branch after every task to prevent crash data loss."
- luacheck is wired into CI for changed files. Run `./tools/luacheck.sh <files>` locally if the script exists; otherwise rely on CI. If the project has no local luacheck runner, rely on the CI feedback after push.
- Manual verification in WoW: reload with `/reload`, exercise the feature, and dump state with `/run print(...)`.

---

## File Structure

### New

- `Onboarding/Overview.lua` — ~450 lines target. Module locals → helpers → page registry → illustration builders → modal shell builder → pip builder → page switcher → public API → event registration. If it exceeds ~500 lines during Task 6, split illustration builders out into `Onboarding/OverviewIllustrations.lua` (see Task 6 "Split decision" step).
- `Media/Icons/WindowMinimize.tga` — sourced from AbstractFramework upstream (see Task 8).

### Modified

- `Framed.toc` — remove `Onboarding/Tour.lua` line, add `Onboarding/Overview.lua` line.
- `Init.lua` — extend the `PLAYER_LOGIN` handler with an overview auto-show gate.
- `Core/Config.lua` — add `overviewCompleted = false` to `accountDefaults.general`, remove dead `tourState` from `charDefaults`.
- `Settings/Cards/Appearance/SetupWizard.lua` — rename the second button from "Take Tour" to "Take Overview", retarget its handler to `F.Onboarding.ShowOverview()`, drop the chat-fallback branch.
- `Widgets/Button.lua` — add `Widgets.SetupAccentHover(btn, target, isTexture)` helper (promoted from `Settings/MainFrame.lua`'s local function so Overview.lua can reuse it without duplication).
- `Settings/MainFrame.lua` — delete the local `SetupAccentHover` function, change 3 call sites to `Widgets.SetupAccentHover`.
- `CHANGELOG.md` — add an entry under the in-progress version block (Task 12).

### Deleted

- `Onboarding/Tour.lua` — 336 lines, unused (anchor fields `F.Settings._sidebar`, `_contentArea`, etc. are never populated, so the tour visibly does nothing beyond re-showing the settings window).

---

## Task 1: Config scaffolding, Tour.lua removal, TOC wiring, Overview stub

**Goal:** Get the skeleton in place — account default flag, dead state removed, old file deleted, new file registered and loading cleanly with a no-op public API.

**Files:**
- Modify: `Core/Config.lua` (lines 13-40 region for `accountDefaults`, lines 42-60 region for `charDefaults`)
- Delete: `Onboarding/Tour.lua`
- Modify: `Framed.toc` (line 221)
- Create: `Onboarding/Overview.lua`

- [ ] **Step 1: Add `overviewCompleted` to `accountDefaults.general`**

In `Core/Config.lua`, find the `accountDefaults.general` block (around line 14-36). Add `overviewCompleted = false` immediately after the existing `wizardCompleted = false` line so the two flags sit together:

```lua
-- Before (around line 20):
		wizardCompleted = false,

-- After:
		wizardCompleted = false,
		overviewCompleted = false,
```

- [ ] **Step 2: Remove dead `tourState` from `charDefaults`**

In `Core/Config.lua`, delete the `tourState` table from `charDefaults` (lines 53-56 in the current file). The only code that ever read it was `Onboarding/Tour.lua`, which is being deleted in Step 4.

```lua
-- Delete this block entirely:
	tourState = {
		completed = false,
		lastStep = 0,
	},
```

Confirm no other file references `tourState` before deleting:

Run: grep `tourState` across the codebase. Expected: only matches inside `docs/`, `Onboarding/Tour.lua` (being deleted), and maybe this plan file. No matches in any other `.lua` file under `Core/`, `Settings/`, `Onboarding/`, etc.

- [ ] **Step 3: Remove `Onboarding/Tour.lua` from TOC**

In `Framed.toc`, delete line 221 (`Onboarding/Tour.lua`). Line 220 (`Onboarding/Wizard.lua`) stays. Line 222 should become the new end of the Onboarding section (we'll add `Overview.lua` in Step 5).

```
# Before:
# Onboarding
Onboarding/Wizard.lua
Onboarding/Tour.lua

# After:
# Onboarding
Onboarding/Wizard.lua
```

- [ ] **Step 4: Delete `Onboarding/Tour.lua`**

Run: `rm Onboarding/Tour.lua`

Confirm the file is gone. No other file in the project references `F.Onboarding.StartTour`, `F.Onboarding.EndTour`, or any symbol from Tour.lua except `Settings/Cards/Appearance/SetupWizard.lua:26` (which we'll fix in Task 11).

Run: grep `StartTour` and `EndTour` across the codebase. Expected: only matches in `SetupWizard.lua` and `docs/`.

- [ ] **Step 5: Create `Onboarding/Overview.lua` stub with the full public API**

Create the file with module scaffolding, module locals, and all five API functions as no-ops. This gives us something that loads cleanly and lets later tasks add real behavior without touching module structure.

```lua
local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

F.Onboarding = F.Onboarding or {}
local Onboarding = F.Onboarding

-- ============================================================
-- Constants
-- ============================================================

local MODAL_W        = 540
local MODAL_H        = 380
local HEADER_H       = 40
local FOOTER_H       = 44
local CONTENT_PAD    = 16
local ILLUSTRATION_W = 180
local ILLUSTRATION_H = 220
local PIP_W          = 140
local PIP_H          = 32
local PROGRESS_SLOTS = 6
local PROGRESS_SIZE  = 16
local PROGRESS_GAP   = 6
local BTN_W          = 110
local BTN_H          = 26
local CLOSE_BTN_SIZE = 20

-- ============================================================
-- State
-- ============================================================

local modalFrame  = nil
local pipFrame    = nil
local currentStep = 1
local isMinimized = false

-- ============================================================
-- Public API (stubs — implemented in later tasks)
-- ============================================================

function Onboarding.ShowOverview()
end

function Onboarding.MinimizeOverview()
end

function Onboarding.RestoreOverview()
end

function Onboarding.CloseOverview()
end

function Onboarding.IsOverviewActive()
	return (modalFrame and modalFrame:IsShown()) or (pipFrame and pipFrame:IsShown()) or false
end
```

- [ ] **Step 6: Register `Overview.lua` in TOC**

In `Framed.toc`, add `Onboarding/Overview.lua` after `Onboarding/Wizard.lua`:

```
# Onboarding
Onboarding/Wizard.lua
Onboarding/Overview.lua
```

- [ ] **Step 7: Verify load and baseline state in-game**

In WoW:
1. `/reload`
2. `/run print(FramedDB.general.overviewCompleted)` — expected output: `false`
3. `/run print(FramedCharDB.tourState)` — expected: `nil` (since we removed it from defaults; existing saved values will linger until logout, but new characters will have nothing)
4. `/run print(F.Onboarding.IsOverviewActive())` — expected: `false`
5. `/run F.Onboarding.ShowOverview()` — expected: nothing happens (stub), no error
6. Open Framed settings, navigate to Appearance → Setup Wizard card. The "Take Tour" button should still be present but clicking it should print `Framed: Guided tour coming in a future update.` in chat (because `F.Onboarding.StartTour` is now nil — we'll rewire the button in Task 11). No Lua errors.

If any `/run` prints a Lua error, read it carefully and fix the root cause — usually a typo in the stub or a missing comma after a table entry in Config.lua.

- [ ] **Step 8: Commit and push**

```bash
git add Core/Config.lua Framed.toc Onboarding/Overview.lua
git rm Onboarding/Tour.lua
git commit -m "$(cat <<'EOF'
Add Overview scaffolding and delete dead Tour.lua

Introduces general.overviewCompleted account flag, Overview.lua
stub with public API, and removes the unreachable Tour.lua plus
its orphaned tourState char defaults.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 2: Promote `SetupAccentHover` to `Widgets.SetupAccentHover`

**Goal:** Move the accent-hover helper out of `Settings/MainFrame.lua` (where it's a module local) into the Widgets library so Overview.lua can reuse it. Pure refactor — no behavior change.

**Files:**
- Modify: `Widgets/Button.lua` (append new function)
- Modify: `Settings/MainFrame.lua` (delete local function lines 53-105, update 3 call sites)

- [ ] **Step 1: Add `Widgets.SetupAccentHover` to `Widgets/Button.lua`**

Add this function at the end of `Widgets/Button.lua`, before the final newline. It's a straight port of the MainFrame local, with the module-local `C` reference replaced by `Widgets/Button.lua`'s existing `C` upvalue (already present at the top of that file):

```lua
-- ============================================================
-- Accent hover helper
-- Animates a button's icon or label from textSecondary → accent
-- on enter, and back on leave. Used by icon buttons in the main
-- settings header and the Overview modal.
-- ============================================================

--- Wire up a button so its target texture/fontstring crossfades to
--- the accent color on hover, and back to textSecondary on leave.
--- @param btn Button  The button frame
--- @param target Texture|FontString  The element to tint
--- @param isTexture boolean  true for SetVertexColor, false for SetTextColor
function Widgets.SetupAccentHover(btn, target, isTexture)
	local ac  = C.Colors.accent
	local dim = C.Colors.textSecondary
	local dur = C.Animation.durationFast

	local function setColor(r, g, b)
		if(isTexture) then
			target:SetVertexColor(r, g, b)
		else
			target:SetTextColor(r, g, b)
		end
	end

	local function getColor()
		if(isTexture) then
			return target:GetVertexColor()
		else
			return target:GetTextColor()
		end
	end

	btn:SetScript('OnEnter', function(self)
		local startR, startG, startB = getColor()
		local elapsed = 0
		self:SetScript('OnUpdate', function(_, dt)
			elapsed = elapsed + dt
			local t = math.min(elapsed / dur, 1)
			setColor(
				startR + (ac[1] - startR) * t,
				startG + (ac[2] - startG) * t,
				startB + (ac[3] - startB) * t)
			if(t >= 1) then self:SetScript('OnUpdate', nil) end
		end)
		if(Widgets.ShowTooltip and self._tooltipTitle) then
			Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
		end
	end)

	btn:SetScript('OnLeave', function(self)
		local startR, startG, startB = getColor()
		local elapsed = 0
		self:SetScript('OnUpdate', function(_, dt)
			elapsed = elapsed + dt
			local t = math.min(elapsed / dur, 1)
			setColor(
				startR + (dim[1] - startR) * t,
				startG + (dim[2] - startG) * t,
				startB + (dim[3] - startB) * t)
			if(t >= 1) then self:SetScript('OnUpdate', nil) end
		end)
		if(Widgets.HideTooltip) then Widgets.HideTooltip() end
	end)
end
```

- [ ] **Step 2: Delete the module-local `SetupAccentHover` from `Settings/MainFrame.lua`**

Delete lines ~50-105 (the `SetupAccentHover` function definition and its preceding `---` doc comment block — everything from the `--- Wire up a button` comment through the closing `end`). Leave the `-- ============================================================` separator above it intact if it belongs to the next section (check visually — it may have been heading the deleted function, in which case remove it too).

- [ ] **Step 3: Update call sites in `Settings/MainFrame.lua`**

There are 3 call sites. Change each from the local name to the Widgets-qualified name:

```lua
-- Line 147 area:
-- Before:
	SetupAccentHover(closeBtn, closeBtn._icon, true)
-- After:
	Widgets.SetupAccentHover(closeBtn, closeBtn._icon, true)

-- Line 207 area:
-- Before:
	SetupAccentHover(fullscreenBtn, fullscreenBtn._icon, true)
-- After:
	Widgets.SetupAccentHover(fullscreenBtn, fullscreenBtn._icon, true)

-- Line 221 area:
-- Before:
	SetupAccentHover(editModeBtn, editModeBtn._label, false)
-- After:
	Widgets.SetupAccentHover(editModeBtn, editModeBtn._label, false)
```

Use grep to confirm no other callers remain:

Run: grep `SetupAccentHover` across the entire repo. Expected: one definition in `Widgets/Button.lua`, three call sites in `Settings/MainFrame.lua` (all prefixed with `Widgets.`), and this plan file. No bare `SetupAccentHover(` calls anywhere else.

- [ ] **Step 4: Verify in-game**

1. `/reload`
2. Open Framed settings (`/fr`)
3. Hover over the close button (top-right `×`) — expected: icon fades from grey to accent color, smoothly animated. Move mouse away — fades back to grey.
4. Hover over the maximize button (left of close) — same animation.
5. Hover over the Edit Mode button in the header — its label crossfades grey → accent.
6. No Lua errors in `/console scriptErrors 1` or BugSack.

- [ ] **Step 5: Commit and push**

```bash
git add Widgets/Button.lua Settings/MainFrame.lua
git commit -m "$(cat <<'EOF'
Promote SetupAccentHover to Widgets library

Moves the accent-hover animation helper out of MainFrame.lua so
the upcoming Overview modal can reuse it. Pure refactor — three
existing call sites updated, behavior unchanged.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 3: Modal shell (header + body + footer, no pages yet)

**Goal:** Get an empty modal rendering with working header icon buttons, the two-column body layout prepared for illustrations, and Back/Skip/Next buttons in the footer. No page content, no progress rail, no minimize pip — those come in later tasks.

**Files:**
- Modify: `Onboarding/Overview.lua`

- [ ] **Step 1: Add `buildModalFrame` helper in `Overview.lua`**

Add the builder above the public API section. It constructs the shell lazily on first `ShowOverview()` call.

```lua
-- ============================================================
-- Modal frame construction (lazy)
-- ============================================================

local headerTitle, headerProgress, headerCloseBtn, headerMinimizeBtn
local bodyIllustrationHost, bodyTitle, bodyCopy
local footerBackBtn, footerSkipBtn, footerNextBtn

local showPage  -- forward declaration, defined in Task 4

local function buildModalFrame()
	if(modalFrame) then return end

	-- Outer bordered dialog frame
	local frame = Widgets.CreateBorderedFrame(UIParent, MODAL_W, MODAL_H, C.Colors.panel, C.Colors.border)
	frame:SetFrameStrata('FULLSCREEN_DIALOG')
	frame:SetFrameLevel(10)
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
	frame:EnableMouse(true)
	frame:Hide()

	-- Accent top border (3px) — matches wizard styling
	local accentBorder = frame:CreateTexture(nil, 'OVERLAY')
	accentBorder:SetHeight(3)
	local ac = C.Colors.accent
	accentBorder:SetColorTexture(ac[1], ac[2], ac[3], ac[4] or 1)
	accentBorder:ClearAllPoints()
	accentBorder:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
	accentBorder:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)

	-- ── Header row ────────────────────────────────────────────
	local header = CreateFrame('Frame', nil, frame)
	header:ClearAllPoints()
	Widgets.SetPoint(header, 'TOPLEFT',  frame, 'TOPLEFT',  CONTENT_PAD, -CONTENT_PAD)
	Widgets.SetPoint(header, 'TOPRIGHT', frame, 'TOPRIGHT', -CONTENT_PAD, -CONTENT_PAD)
	Widgets.SetSize(header, MODAL_W - CONTENT_PAD * 2, HEADER_H)

	headerTitle = Widgets.CreateFontString(header, C.Font.sizeTitle, C.Colors.accent)
	headerTitle:ClearAllPoints()
	Widgets.SetPoint(headerTitle, 'LEFT', header, 'LEFT', 0, 0)
	headerTitle:SetText('Framed Overview')

	headerCloseBtn = Widgets.CreateIconButton(header, F.Media.GetIcon('Close'), CLOSE_BTN_SIZE)
	headerCloseBtn:ClearAllPoints()
	Widgets.SetPoint(headerCloseBtn, 'RIGHT', header, 'RIGHT', 0, 0)
	headerCloseBtn:SetWidgetTooltip('Close')
	headerCloseBtn:SetBackdrop(nil)
	Widgets.SetupAccentHover(headerCloseBtn, headerCloseBtn._icon, true)
	headerCloseBtn:SetOnClick(function()
		Onboarding.CloseOverview()
	end)

	-- Minimize button placeholder — uses Close icon temporarily until
	-- WindowMinimize.tga lands in Task 8. Tooltip already says "Minimize".
	headerMinimizeBtn = Widgets.CreateIconButton(header, F.Media.GetIcon('Close'), CLOSE_BTN_SIZE)
	headerMinimizeBtn:ClearAllPoints()
	Widgets.SetPoint(headerMinimizeBtn, 'RIGHT', headerCloseBtn, 'LEFT', -C.Spacing.tight, 0)
	headerMinimizeBtn:SetWidgetTooltip('Minimize')
	headerMinimizeBtn:SetBackdrop(nil)
	Widgets.SetupAccentHover(headerMinimizeBtn, headerMinimizeBtn._icon, true)
	-- Click wiring added in Task 8

	-- Progress rail slot host — populated in Task 7
	headerProgress = CreateFrame('Frame', nil, header)
	headerProgress:ClearAllPoints()
	Widgets.SetPoint(headerProgress, 'RIGHT', headerMinimizeBtn, 'LEFT', -C.Spacing.normal, 0)
	Widgets.SetSize(headerProgress, PROGRESS_SLOTS * PROGRESS_SIZE + (PROGRESS_SLOTS - 1) * PROGRESS_GAP, PROGRESS_SIZE)

	-- ── Footer row ────────────────────────────────────────────
	local footer = CreateFrame('Frame', nil, frame)
	footer:ClearAllPoints()
	Widgets.SetPoint(footer, 'BOTTOMLEFT',  frame, 'BOTTOMLEFT',  CONTENT_PAD, CONTENT_PAD)
	Widgets.SetPoint(footer, 'BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -CONTENT_PAD, CONTENT_PAD)
	Widgets.SetSize(footer, MODAL_W - CONTENT_PAD * 2, FOOTER_H)

	footerBackBtn = Widgets.CreateButton(footer, '← Back', 'widget', BTN_W, BTN_H)
	footerBackBtn:ClearAllPoints()
	Widgets.SetPoint(footerBackBtn, 'LEFT', footer, 'LEFT', 0, 0)
	footerBackBtn:SetOnClick(function()
		if(currentStep > 1) then
			showPage(currentStep - 1)
		end
	end)

	footerSkipBtn = Widgets.CreateButton(footer, 'Skip Overview', 'widget', BTN_W, BTN_H)
	footerSkipBtn:ClearAllPoints()
	Widgets.SetPoint(footerSkipBtn, 'CENTER', footer, 'CENTER', 0, 0)
	footerSkipBtn:SetOnClick(function()
		F.Config:Set('general.overviewCompleted', true)
		Onboarding.CloseOverview()
	end)

	footerNextBtn = Widgets.CreateButton(footer, 'Next →', 'accent', BTN_W, BTN_H)
	footerNextBtn:ClearAllPoints()
	Widgets.SetPoint(footerNextBtn, 'RIGHT', footer, 'RIGHT', 0, 0)
	footerNextBtn:SetOnClick(function()
		-- Real behavior wired in Task 4 once showPage exists.
		-- For this task, just advance step counter if possible.
		if(showPage and currentStep < PROGRESS_SLOTS) then
			showPage(currentStep + 1)
		end
	end)

	-- ── Body ──────────────────────────────────────────────────
	local body = CreateFrame('Frame', nil, frame)
	body:ClearAllPoints()
	Widgets.SetPoint(body, 'TOPLEFT',     header, 'BOTTOMLEFT',  0, -C.Spacing.normal)
	Widgets.SetPoint(body, 'BOTTOMRIGHT', footer, 'TOPRIGHT',    0,  C.Spacing.normal)

	bodyIllustrationHost = CreateFrame('Frame', nil, body)
	bodyIllustrationHost:ClearAllPoints()
	Widgets.SetPoint(bodyIllustrationHost, 'TOPLEFT', body, 'TOPLEFT', 0, 0)
	Widgets.SetSize(bodyIllustrationHost, ILLUSTRATION_W, ILLUSTRATION_H)

	bodyTitle = Widgets.CreateFontString(body, C.Font.sizeTitle, C.Colors.accent)
	bodyTitle:ClearAllPoints()
	Widgets.SetPoint(bodyTitle, 'TOPLEFT', bodyIllustrationHost, 'TOPRIGHT', C.Spacing.normal, 0)

	bodyCopy = Widgets.CreateFontString(body, C.Font.sizeNormal, C.Colors.textNormal)
	bodyCopy:ClearAllPoints()
	Widgets.SetPoint(bodyCopy, 'TOPLEFT', bodyTitle, 'BOTTOMLEFT', 0, -C.Spacing.normal)
	local rightColumnW = MODAL_W - CONTENT_PAD * 2 - ILLUSTRATION_W - C.Spacing.normal
	bodyCopy:SetWidth(rightColumnW)
	bodyCopy:SetWordWrap(true)
	bodyCopy:SetJustifyH('LEFT')
	bodyCopy:SetJustifyV('TOP')

	-- Keyboard handling placeholder (Escape wired in Task 9)
	frame:EnableKeyboard(true)
	frame:SetScript('OnKeyDown', function(self, key)
		if(key == 'ESCAPE') then
			self:SetPropagateKeyboardInput(false)
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)

	Widgets.RegisterForUIScale(frame)

	modalFrame = frame
end
```

- [ ] **Step 2: Implement `ShowOverview` and `CloseOverview`**

Replace the two stubs at the bottom of `Overview.lua`:

```lua
function Onboarding.ShowOverview()
	if(InCombatLockdown()) then
		if(DEFAULT_CHAT_FRAME) then
			DEFAULT_CHAT_FRAME:AddMessage('|cff00ccffFramed:|r Framed Overview cannot be opened in combat.')
		end
		return
	end

	if(not modalFrame) then
		buildModalFrame()
	end

	currentStep = 1
	isMinimized = false
	if(pipFrame) then pipFrame:Hide() end
	Widgets.FadeIn(modalFrame)

	-- Page content wired in Task 4
	if(showPage) then showPage(1) end
end

function Onboarding.CloseOverview()
	if(modalFrame) then
		Widgets.FadeOut(modalFrame)
	end
	if(pipFrame) then
		pipFrame:Hide()
	end
	isMinimized = false
end
```

- [ ] **Step 3: Verify modal renders**

1. `/reload`
2. `/run F.Onboarding.ShowOverview()`
3. Expected: a 540×380 centered dialog appears with:
   - "Framed Overview" title (accent color) at top-left of the header
   - A close button (`×`) at top-right
   - A second icon button immediately left of close (this is the minimize button — it uses the Close icon temporarily and will be updated in Task 8)
   - An empty area in the top-right header where the progress rail will go (Task 7)
   - An empty two-column body
   - Back / Skip Overview / Next → buttons along the bottom
4. Click the `×` button — modal fades out.
5. `/run F.Onboarding.ShowOverview()` again — modal reappears.
6. Click `Skip Overview` — modal fades out, `/run print(FramedDB.general.overviewCompleted)` prints `true`.
7. Reset for next tasks: `/run F.Config:Set('general.overviewCompleted', false)`.
8. No Lua errors.

- [ ] **Step 4: Commit and push**

```bash
git add Onboarding/Overview.lua
git commit -m "$(cat <<'EOF'
Build Overview modal shell

Lazy-built FULLSCREEN_DIALOG frame with header title, close +
minimize icon buttons, two-column body placeholder, and
Back/Skip/Next footer. Skip marks overview completed and closes
per spec.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 4: Page registry + Welcome page (page 1 with live party illustration)

**Goal:** Introduce the `PAGES` table and `showPage(n)` switcher, then implement the Welcome page with a real 3-member party preview as its illustration. After this task, `ShowOverview()` visibly shows page 1 content.

**Files:**
- Modify: `Onboarding/Overview.lua`

- [ ] **Step 1: Add illustration helpers section**

Above the `buildModalFrame` helper, add an illustration section. First helper builds a live 3-member mini party preview using `Preview.GetFakeUnits` and `Preview.CreatePreviewFrame`:

```lua
-- ============================================================
-- Illustration builders
-- Each returns a frame parented to `host`, positioned and sized.
-- Failures (nil deps) return nil — caller hides the left column.
-- ============================================================

local illustrationTrash = CreateFrame('Frame')
illustrationTrash:Hide()

local function buildWelcomeIllustration(host, w, h)
	if(not F.Preview or not F.Preview.GetFakeUnits or not F.Preview.CreatePreviewFrame) then
		return nil
	end

	local container = CreateFrame('Frame', nil, host)
	container:ClearAllPoints()
	container:SetAllPoints(host)

	local units = F.Preview.GetFakeUnits(3)
	if(not units or #units == 0) then return nil end

	local unitW = w - 8
	local unitH = 32
	local gap = 4
	for i, unit in next, units do
		local pf = F.Preview.CreatePreviewFrame(container, 'party', unitW, unitH)
		pf:ClearAllPoints()
		Widgets.SetPoint(pf, 'TOP', container, 'TOP', 0, -((i - 1) * (unitH + gap)))
		-- Apply fake unit data — CreatePreviewFrame exposes _nameText / _healthBar
		-- via Preview's internal ApplyUnitToFrame path. Use the public
		-- F.Preview helper if available, else inline minimal setup.
		if(F.Preview.ApplyUnitToFrame) then
			F.Preview.ApplyUnitToFrame(pf, unit)
		else
			-- Minimal fallback: set name + class color directly
			if(pf._nameText) then pf._nameText:SetText(unit.name or '') end
		end
		pf:Show()
	end

	return container
end
```

Note: `F.Preview.ApplyUnitToFrame` is currently a module local (see `Preview/Preview.lua:103`). If calling it from outside that module fails, the inline fallback path will run — the names won't show but the bars will still render. **If you want proper rendering on page 1, export `ApplyUnitToFrame` on `Preview` in `Preview/Preview.lua`** as a small precursor change (one line: `function Preview.ApplyUnitToFrame(frame, unit)` instead of `local function ApplyUnitToFrame(frame, unit)`, plus updating the one internal call site). Commit that change separately if you do it.

- [ ] **Step 2: Add the `PAGES` registry with one entry**

Below the illustration builders:

```lua
-- ============================================================
-- Page registry
-- ============================================================

local PAGES = {
	{
		id = 'welcome',
		title = 'Welcome to Framed',
		body = 'Modern unit frames and raid frames, built around live previews, presets, and per-unit settings cards. Use this overview to get oriented — you can relaunch it anytime from Appearance → Setup Wizard.',
		buildIllustration = buildWelcomeIllustration,
	},
}
```

- [ ] **Step 3: Implement `showPage(n)`**

Place this right below `PAGES`, above `buildModalFrame` (so `buildModalFrame`'s footer buttons can reference it via the forward-declared `showPage`):

```lua
local activeIllustration = nil

local function clearActiveIllustration()
	if(activeIllustration) then
		activeIllustration:Hide()
		activeIllustration:SetParent(illustrationTrash)
		activeIllustration:ClearAllPoints()
		activeIllustration = nil
	end
end

showPage = function(n)
	if(not modalFrame) then return end
	if(n < 1 or n > #PAGES) then return end

	currentStep = n
	local page = PAGES[n]

	clearActiveIllustration()
	if(page.buildIllustration) then
		activeIllustration = page.buildIllustration(bodyIllustrationHost, ILLUSTRATION_W, ILLUSTRATION_H)
		if(activeIllustration) then
			activeIllustration:ClearAllPoints()
			activeIllustration:SetAllPoints(bodyIllustrationHost)
			activeIllustration:Show()
		end
	end

	bodyTitle:SetText(page.title)
	bodyCopy:SetText(page.body)

	-- Footer button state
	footerBackBtn:SetEnabled(n > 1)
	local isLast = (n == #PAGES)
	footerNextBtn:SetText(isLast and 'Done' or 'Next →')
end
```

- [ ] **Step 4: Wire the Next button to `showPage` and Done handler**

Replace the Next button's `SetOnClick` in `buildModalFrame` (the placeholder body from Task 3):

```lua
	footerNextBtn:SetOnClick(function()
		if(currentStep >= #PAGES) then
			-- Done on last page → mark completed + close
			F.Config:Set('general.overviewCompleted', true)
			Onboarding.CloseOverview()
		else
			showPage(currentStep + 1)
		end
	end)
```

- [ ] **Step 5: Verify page 1 renders**

1. `/reload`
2. `/run F.Config:Set('general.overviewCompleted', false)` (reset from earlier verification)
3. `/run F.Onboarding.ShowOverview()`
4. Expected: modal shows the Welcome title, body copy, and a live 3-unit party preview in the left column.
5. `Back` should be disabled (greyed). `Next →` should say `Done` (because there's only 1 page).
6. Click `Done` — modal closes, `/run print(FramedDB.general.overviewCompleted)` returns `true`.
7. Reset: `/run F.Config:Set('general.overviewCompleted', false)`.
8. No Lua errors.

- [ ] **Step 6: Commit and push**

```bash
git add Onboarding/Overview.lua
# If you exported ApplyUnitToFrame in Preview/Preview.lua, add it too:
git add Preview/Preview.lua
git commit -m "$(cat <<'EOF'
Add page registry and Welcome page with live illustration

Introduces PAGES table, showPage switcher, and the first page
showing a 3-member party preview via Preview.CreatePreviewFrame.
Next → Done flips the completed flag on the last page.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 5: Pages 2 and 3 (Layouts & Auto-Switch, Edit Mode) — atlas illustrations

**Goal:** Add two more pages that use Blizzard atlas icons as their illustrations (simpler than live widgets). Verifies the navigation flow with multiple pages.

**Files:**
- Modify: `Onboarding/Overview.lua`

- [ ] **Step 1: Add atlas illustration helper**

Below `buildWelcomeIllustration`, add a generic atlas helper so the two atlas pages don't duplicate boilerplate:

```lua
local function buildAtlasIllustration(host, atlasName, iconSize)
	local container = CreateFrame('Frame', nil, host)
	container:ClearAllPoints()
	container:SetAllPoints(host)

	local tex = container:CreateTexture(nil, 'ARTWORK')
	tex:SetSize(iconSize or 96, iconSize or 96)
	tex:SetPoint('CENTER', container, 'CENTER', 0, 0)
	local ok = pcall(tex.SetAtlas, tex, atlasName, false)
	if(not ok) then
		-- Fallback: show nothing rather than a broken texture
		container:Hide()
		return nil
	end
	return container
end
```

Note on pcall: per project convention, pcall is generally banned. **Exception:** atlas lookups are exactly the "feature detection against a Blizzard API that varies by patch" case — `SetAtlas` silently fails on missing atlas names in some client builds but can raise in others, and there's no query-before-set API. Add a `-- BUG:` comment justifying it:

```lua
	-- BUG: SetAtlas can raise on missing/renamed atlases in some client
	-- builds; no query-before-set API exists. Guard the call so a bad
	-- atlas name degrades to an empty illustration instead of a hard error.
	local ok = pcall(tex.SetAtlas, tex, atlasName, false)
```

- [ ] **Step 2: Add page entries for Layouts and Edit Mode**

Extend the `PAGES` table:

```lua
local PAGES = {
	{
		id = 'welcome',
		title = 'Welcome to Framed',
		body = 'Modern unit frames and raid frames, built around live previews, presets, and per-unit settings cards. Use this overview to get oriented — you can relaunch it anytime from Appearance → Setup Wizard.',
		buildIllustration = buildWelcomeIllustration,
	},
	{
		id = 'layouts',
		title = 'Layouts & Auto-Switch',
		body = 'Framed ships layouts for Solo, Party, Raid, Mythic Raid, World Raid, Battleground, and Arena — and swaps them automatically when content changes. You can still edit any layout manually from the Layouts sidebar.',
		buildIllustration = function(host, w, h)
			return buildAtlasIllustration(host, 'groupfinder-eye-frame', 96)
		end,
	},
	{
		id = 'editmode',
		title = 'Edit Mode',
		body = 'Drag any frame to reposition it. The inline panel jumps you to that frame\'s settings, and edits stay live until you click Save or Discard.',
		buildIllustration = function(host, w, h)
			return buildAtlasIllustration(host, 'editmode-new-icon', 96)
		end,
	},
}
```

Atlas name notes: `groupfinder-eye-frame` and `editmode-new-icon` are best-effort guesses. If either fails to render in-game, try these known-present alternatives (verified in live 12.0.1 atlas dumps):
- Layouts alternatives: `groupfinder-waitdot`, `Raid-Icon-MainTank`, `communities-icon-searchmagnifyingglass`
- Edit Mode alternatives: `editmode-dropshadow`, `socialqueuing-icon-group`, `Raid-icon-DPS`

Pick whichever looks most thematic and commit the final choice.

- [ ] **Step 3: Verify navigation**

1. `/reload`
2. `/run F.Config:Set('general.overviewCompleted', false); F.Onboarding.ShowOverview()`
3. Page 1 shows with live party preview. `Back` disabled, Next reads `Next →`.
4. Click `Next →` — page 2 (Layouts) shows with atlas icon. `Back` enabled, Next still `Next →`.
5. Click `Next →` — page 3 (Edit Mode) shows. Next now reads `Done` (last page).
6. Click `Back` — page 2 reshown.
7. Click `Back` again — page 1 reshown, `Back` re-disabled.
8. If atlas icons appear broken (missing texture), swap the atlas name per Step 2 notes and `/reload`.
9. No Lua errors.

- [ ] **Step 4: Commit and push**

```bash
git add Onboarding/Overview.lua
git commit -m "$(cat <<'EOF'
Add Layouts and Edit Mode overview pages

Two atlas-icon pages plus a reusable buildAtlasIllustration
helper. Navigation between pages 1-3 verified via Back/Next.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 6: Pages 4, 5, 6 (Settings Cards, Indicators, Defensives) — live illustrations

**Goal:** Add the three remaining pages, each rendering a real Framed widget as the illustration. After this task, all 6 pages are present and the Done flow works end-to-end.

**Files:**
- Modify: `Onboarding/Overview.lua`
- **Possibly create:** `Onboarding/OverviewIllustrations.lua` (see split decision at end of task)

- [ ] **Step 1: Add page 4 illustration — a live Power Bar card**

Add this helper near the other illustration builders:

```lua
local function buildCardsIllustration(host, w, h)
	if(not F.AppearanceCards or not F.AppearanceCards.Tooltips) then
		-- Cards module not loaded; fall back to an atlas icon
		return buildAtlasIllustration(host, 'Garr_BuildingIcon-Barracks', 96)
	end

	-- Use the Tooltips appearance card as a generic "settings card" visual.
	-- It's small, self-contained, and renders in isolation without a
	-- real frame selection. Stub getConfig/setConfig/fireChange since
	-- we only want the visual.
	local container = CreateFrame('Frame', nil, host)
	container:ClearAllPoints()
	container:SetAllPoints(host)

	local cardConfig = {
		tooltipEnabled = true,
		tooltipHideInCombat = false,
		tooltipMode = 'frame',
		tooltipAnchor = 'RIGHT',
		tooltipOffsetX = 0,
		tooltipOffsetY = 0,
	}
	local function getConfig(key) return cardConfig[key] end
	local function setConfig(key, value) cardConfig[key] = value end
	local function fireChange() end
	local function onResize() end

	local ok, card = pcall(F.AppearanceCards.Tooltips, container, w, getConfig, setConfig, fireChange, onResize)
	-- BUG: Appearance card builders can raise if the Widgets library
	-- isn't fully initialized or if an internal dependency is missing.
	-- Guard to degrade to an empty illustration rather than break the overview.
	if(not ok or not card) then
		container:Hide()
		return nil
	end

	card:ClearAllPoints()
	card:SetPoint('TOP', container, 'TOP', 0, 0)
	return container
end
```

- [ ] **Step 2: Add page 5 illustration — a static indicator sample**

The goal is a small visual that reads as "indicators" — a border icon and an overlay icon side-by-side. A full live indicator with cooldown sweeps requires aura data we don't have here. Instead, show two simple icon textures arranged like the real indicators appear on-frame:

```lua
local function buildIndicatorsIllustration(host, w, h)
	local container = CreateFrame('Frame', nil, host)
	container:ClearAllPoints()
	container:SetAllPoints(host)

	-- Two sample icons side by side: a bordered indicator (green border
	-- suggesting "dispellable buff") and an overlay indicator (large icon
	-- suggesting "targeted spell"). Both pulled from the Fluent icon set.
	local iconSize = 48
	local gap = C.Spacing.normal

	local leftBg = CreateFrame('Frame', nil, container, 'BackdropTemplate')
	Widgets.ApplyBackdrop(leftBg, C.Colors.widget, { 0.2, 0.8, 0.3, 1 }) -- green border
	Widgets.SetSize(leftBg, iconSize, iconSize)
	leftBg:ClearAllPoints()
	Widgets.SetPoint(leftBg, 'CENTER', container, 'CENTER', -(iconSize + gap) / 2, 0)
	local leftIcon = leftBg:CreateTexture(nil, 'ARTWORK')
	leftIcon:SetTexture(F.Media.GetIcon('Fluent_Color_Yes'))
	leftIcon:SetPoint('CENTER', leftBg, 'CENTER', 0, 0)
	leftIcon:SetSize(iconSize - 4, iconSize - 4)

	local rightBg = CreateFrame('Frame', nil, container, 'BackdropTemplate')
	Widgets.ApplyBackdrop(rightBg, C.Colors.widget, C.Colors.accent)
	Widgets.SetSize(rightBg, iconSize, iconSize)
	rightBg:ClearAllPoints()
	Widgets.SetPoint(rightBg, 'CENTER', container, 'CENTER', (iconSize + gap) / 2, 0)
	local rightIcon = rightBg:CreateTexture(nil, 'ARTWORK')
	rightIcon:SetTexture(F.Media.GetIcon('Star'))
	rightIcon:SetPoint('CENTER', rightBg, 'CENTER', 0, 0)
	rightIcon:SetSize(iconSize - 4, iconSize - 4)

	return container
end
```

- [ ] **Step 3: Add page 6 illustration — external-style glow icon**

```lua
local function buildDefensivesIllustration(host, w, h)
	local container = CreateFrame('Frame', nil, host)
	container:ClearAllPoints()
	container:SetAllPoints(host)

	local iconSize = 64
	local bg = CreateFrame('Frame', nil, container, 'BackdropTemplate')
	Widgets.ApplyBackdrop(bg, C.Colors.widget, C.Colors.accent)
	Widgets.SetSize(bg, iconSize, iconSize)
	bg:ClearAllPoints()
	Widgets.SetPoint(bg, 'CENTER', container, 'CENTER', 0, 0)

	local icon = bg:CreateTexture(nil, 'ARTWORK')
	icon:SetTexture(F.Media.GetIcon('Mark'))
	icon:SetPoint('CENTER', bg, 'CENTER', 0, 0)
	icon:SetSize(iconSize - 6, iconSize - 6)

	-- Accent glow ring
	local glow = bg:CreateTexture(nil, 'OVERLAY')
	glow:SetTexture(F.Media.GetIcon('Circle'))
	glow:SetPoint('CENTER', bg, 'CENTER', 0, 0)
	glow:SetSize(iconSize + 12, iconSize + 12)
	local ac = C.Colors.accent
	glow:SetVertexColor(ac[1], ac[2], ac[3], 0.5)

	return container
end
```

- [ ] **Step 4: Add the three page entries**

Extend the `PAGES` table (append to the existing 3 entries):

```lua
	{
		id = 'cards',
		title = 'Settings Cards',
		body = 'Each unit has a grid of focused cards — Position, Health, Power, Auras, and more. Pin the ones you use most so they stick to the top of the grid.',
		buildIllustration = buildCardsIllustration,
	},
	{
		id = 'indicators',
		title = 'Buffs, Debuffs & Dispels',
		body = 'Build custom indicators for specific spells — borders, overlays, or icons. Dispellable debuffs get their own highlight system so healers can spot them instantly.',
		buildIllustration = buildIndicatorsIllustration,
	},
	{
		id = 'defensives',
		title = 'Defensives & Externals',
		body = 'Track raid cooldowns cast on units — personal defensives on yourself, externals cast on someone else. Same indicator builder UX as buffs and debuffs.',
		buildIllustration = buildDefensivesIllustration,
	},
```

- [ ] **Step 5: Verify all 6 pages render and Done works**

1. `/reload`
2. `/run F.Config:Set('general.overviewCompleted', false); F.Onboarding.ShowOverview()`
3. Step through all 6 pages via `Next →`. Each page should show its title, body, and illustration. Watch for Lua errors between each step.
4. On page 6, `Next →` reads `Done`.
5. Click `Done`. Modal closes. `/run print(FramedDB.general.overviewCompleted)` returns `true`.
6. `/run F.Config:Set('general.overviewCompleted', false)` to reset.

- [ ] **Step 6: File size check and split decision**

Run: `wc -l Onboarding/Overview.lua`

- **If ≤ 500 lines:** do not split. Skip to Step 7.
- **If > 500 lines:** split illustration builders into a sibling file:
  1. Create `Onboarding/OverviewIllustrations.lua`:
     ```lua
     local addonName, Framed = ...
     local F = Framed

     local Widgets = F.Widgets
     local C = F.Constants

     F.OverviewIllustrations = {}
     local M = F.OverviewIllustrations

     -- [move all buildXxxIllustration functions here, renaming each from
     --  `local function buildFooIllustration` to `function M.BuildFooIllustration`]
     ```
  2. Update `Onboarding/Overview.lua`:
     - Delete the illustration builder functions from Overview.lua
     - Update the PAGES table to reference `F.OverviewIllustrations.BuildWelcomeIllustration` etc.
     - Add `local Illus = F.OverviewIllustrations` at the top of Overview.lua
  3. Add `Onboarding/OverviewIllustrations.lua` to `Framed.toc` immediately before `Onboarding/Overview.lua` (so the illustrations module is available when Overview.lua loads).
  4. Re-run verification from Step 5.

- [ ] **Step 7: Commit and push**

```bash
git add Onboarding/Overview.lua
# If split:
# git add Onboarding/OverviewIllustrations.lua Framed.toc
git commit -m "$(cat <<'EOF'
Add Settings Cards, Indicators, and Defensives overview pages

Completes the 6-page walkthrough. Cards page renders a live
Appearance Tooltips card; Indicators and Defensives use static
icon compositions. Done button on page 6 marks overview completed.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 7: Progress rail

**Goal:** Populate the header's progress rail with 6 checkmark slots and update their state as `currentStep` changes.

**Files:**
- Modify: `Onboarding/Overview.lua`

- [ ] **Step 1: Build progress slot textures in `buildModalFrame`**

Inside `buildModalFrame`, after the `headerProgress` frame is created (where we left a placeholder in Task 3), add slot construction:

```lua
	headerProgress = CreateFrame('Frame', nil, header)
	headerProgress:ClearAllPoints()
	Widgets.SetPoint(headerProgress, 'RIGHT', headerMinimizeBtn, 'LEFT', -C.Spacing.normal, 0)
	Widgets.SetSize(headerProgress, PROGRESS_SLOTS * PROGRESS_SIZE + (PROGRESS_SLOTS - 1) * PROGRESS_GAP, PROGRESS_SIZE)

	-- Build 6 slot textures stored on headerProgress._slots
	headerProgress._slots = {}
	for i = 1, PROGRESS_SLOTS do
		local slot = headerProgress:CreateTexture(nil, 'ARTWORK')
		slot:SetTexture(F.Media.GetIcon('Fluent_Color_Yes'))
		slot:SetSize(PROGRESS_SIZE, PROGRESS_SIZE)
		slot:ClearAllPoints()
		slot:SetPoint('LEFT', headerProgress, 'LEFT', (i - 1) * (PROGRESS_SIZE + PROGRESS_GAP), 0)
		headerProgress._slots[i] = slot
	end
```

- [ ] **Step 2: Add `updateProgressRail` helper**

Above `showPage`:

```lua
local function updateProgressRail()
	if(not headerProgress or not headerProgress._slots) then return end
	local ac = C.Colors.accent
	for i = 1, PROGRESS_SLOTS do
		local slot = headerProgress._slots[i]
		if(i < currentStep) then
			-- Completed: full color, full alpha, no tint
			slot:SetVertexColor(1, 1, 1, 1)
		elseif(i == currentStep) then
			-- Current: accent tinted, full alpha
			slot:SetVertexColor(ac[1], ac[2], ac[3], 1)
		else
			-- Future: desaturated, low alpha
			slot:SetVertexColor(0.6, 0.6, 0.6, 0.3)
		end
	end
end
```

- [ ] **Step 3: Call `updateProgressRail` from `showPage`**

Add the call at the end of `showPage` after the footer button state block:

```lua
	footerBackBtn:SetEnabled(n > 1)
	local isLast = (n == #PAGES)
	footerNextBtn:SetText(isLast and 'Done' or 'Next →')

	updateProgressRail()
end
```

- [ ] **Step 4: Verify progress rail**

1. `/reload`
2. `/run F.Config:Set('general.overviewCompleted', false); F.Onboarding.ShowOverview()`
3. On page 1: slot 1 accent-tinted, slots 2-6 greyed at 0.3 alpha.
4. Click `Next →`. Page 2: slot 1 full white, slot 2 accent-tinted, slots 3-6 greyed.
5. Step through to page 6: slots 1-5 white, slot 6 accent-tinted.
6. Click `Back` a few times — slot states update correctly.
7. No Lua errors.
8. Reset with `/run F.Config:Set('general.overviewCompleted', false)` if you clicked Done.

- [ ] **Step 5: Commit and push**

```bash
git add Onboarding/Overview.lua
git commit -m "$(cat <<'EOF'
Add Overview progress rail

Six Fluent_Color_Yes checkmark slots in the header reflect
completed/current/future state with accent tinting for the
active step.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 8: Asset drop, minimize pip, and restore flow

**Goal:** Add the `WindowMinimize.tga` asset, swap the minimize button's icon to it, build the minimize pip frame, and wire `MinimizeOverview` / `RestoreOverview`.

**Files:**
- Create: `Media/Icons/WindowMinimize.tga`
- Modify: `Onboarding/Overview.lua`

- [ ] **Step 1: Source the `WindowMinimize.tga` asset**

Download `windowminimize.tga` from AbstractFramework's media icons directory: https://github.com/enderneko/AbstractFramework/tree/main/Media/Icons

Place it at `Media/Icons/WindowMinimize.tga` (note the capitalization — matches `WindowMaximize.tga` and `WindowRestore.tga` already in the directory).

Verify:
- Run: `ls Media/Icons/WindowMinimize.tga` — expected: file exists, non-zero size.
- Run: `file Media/Icons/WindowMinimize.tga` — expected output includes "TGA" or "Targa".

**If the asset cannot be obtained** (network issues, license doubt, etc.): STOP and ask the user. Per the spec, a substitution is not acceptable — the user specifically requested this asset.

- [ ] **Step 2: Swap the minimize button icon and wire its click**

In `Overview.lua`, update the minimize button construction in `buildModalFrame`:

```lua
	-- Before:
	headerMinimizeBtn = Widgets.CreateIconButton(header, F.Media.GetIcon('Close'), CLOSE_BTN_SIZE)
	-- After:
	headerMinimizeBtn = Widgets.CreateIconButton(header, F.Media.GetIcon('WindowMinimize'), CLOSE_BTN_SIZE)
```

Wire the click handler (was left unwired in Task 3):

```lua
	headerMinimizeBtn:SetOnClick(function()
		Onboarding.MinimizeOverview()
	end)
```

- [ ] **Step 3: Add `buildPipFrame` helper**

Above the public API section:

```lua
-- ============================================================
-- Minimize pip
-- ============================================================

local pipLabel
local pipIcon

local function buildPipFrame()
	if(pipFrame) then return end

	local pip = Widgets.CreateBorderedFrame(UIParent, PIP_W, PIP_H, C.Colors.panel, C.Colors.border)
	pip:SetFrameStrata('FULLSCREEN_DIALOG')
	pip:SetFrameLevel(20)
	pip:ClearAllPoints()
	pip:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -20, -20)
	pip:EnableMouse(true)
	pip:Hide()

	pipIcon = pip:CreateTexture(nil, 'ARTWORK')
	pipIcon:SetTexture(F.Media.GetIcon('Fluent_Color_Yes'))
	pipIcon:SetSize(16, 16)
	pipIcon:ClearAllPoints()
	pipIcon:SetPoint('LEFT', pip, 'LEFT', 8, 0)

	pipLabel = Widgets.CreateFontString(pip, C.Font.sizeSmall, C.Colors.textNormal)
	pipLabel:ClearAllPoints()
	Widgets.SetPoint(pipLabel, 'LEFT', pipIcon, 'RIGHT', 6, 0)
	pipLabel:SetText('Framed Overview — 1/6')

	-- Click → restore
	pip:SetScript('OnMouseUp', function(_, button)
		if(button == 'LeftButton') then
			Onboarding.RestoreOverview()
		end
	end)

	-- Tooltip
	pip:SetScript('OnEnter', function(self)
		if(Widgets.ShowTooltip) then
			Widgets.ShowTooltip(self, 'Framed Overview', 'Click to resume walkthrough')
		end
	end)
	pip:SetScript('OnLeave', function()
		if(Widgets.HideTooltip) then Widgets.HideTooltip() end
	end)

	pipFrame = pip
end

local function updatePipLabel()
	if(pipLabel) then
		pipLabel:SetText('Framed Overview — ' .. currentStep .. '/' .. PROGRESS_SLOTS)
	end
end
```

- [ ] **Step 4: Implement `MinimizeOverview` and `RestoreOverview`**

Replace the stubs:

```lua
function Onboarding.MinimizeOverview()
	if(not modalFrame or not modalFrame:IsShown()) then return end
	if(not pipFrame) then
		buildPipFrame()
	end
	isMinimized = true
	modalFrame:Hide()
	updatePipLabel()
	pipFrame:Show()
end

function Onboarding.RestoreOverview()
	if(not pipFrame or not pipFrame:IsShown()) then return end
	isMinimized = false
	pipFrame:Hide()
	if(not modalFrame) then
		buildModalFrame()
	end
	modalFrame:Show()
	-- Rebuild current page (fresh illustration) to recover from any
	-- state that might have stale-referenced hidden frames.
	if(showPage) then showPage(currentStep) end
end
```

- [ ] **Step 5: Verify minimize / restore**

1. `/reload`
2. `/run F.Config:Set('general.overviewCompleted', false); F.Onboarding.ShowOverview()`
3. Hover the minimize button (left of close). Expected: proper minimize glyph (not the Close `×`), smooth accent hover fade.
4. Click `Next →` twice to reach page 3.
5. Click the minimize button. Expected: modal disappears, pip appears in the top-right corner with text `Framed Overview — 3/6` and a green checkmark icon.
6. Hover the pip — tooltip says "Click to resume walkthrough".
7. Click the pip. Expected: modal reappears, still on page 3 (progress rail confirms).
8. Click minimize again, then `/run print(F.Onboarding.IsOverviewActive())` — expected: `true`.
9. Click the pip to restore, then close with `×`. Expected: both modal and pip hidden. `/run print(F.Onboarding.IsOverviewActive())` — expected: `false`.
10. `/run print(FramedDB.general.overviewCompleted)` — expected: `false` (close button doesn't set the flag).
11. No Lua errors.

- [ ] **Step 6: Commit and push**

```bash
git add Media/Icons/WindowMinimize.tga Onboarding/Overview.lua
git commit -m "$(cat <<'EOF'
Add Overview minimize pip and WindowMinimize asset

Drops the AbstractFramework minimize icon into Media/Icons and
wires up the minimize → pip → restore flow. Pip renders top-right
of UIParent with a step counter, click-to-restore, and tooltip.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 9: Escape key handling

**Goal:** Make Escape collapse the modal to the pip (rather than closing it outright or leaking to other UI).

**Files:**
- Modify: `Onboarding/Overview.lua`

- [ ] **Step 1: Update the `OnKeyDown` handler in `buildModalFrame`**

Replace the placeholder keyboard handler from Task 3:

```lua
	-- Before:
	frame:SetScript('OnKeyDown', function(self, key)
		if(key == 'ESCAPE') then
			self:SetPropagateKeyboardInput(false)
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)

	-- After:
	frame:SetScript('OnKeyDown', function(self, key)
		if(key == 'ESCAPE') then
			self:SetPropagateKeyboardInput(false)
			Onboarding.MinimizeOverview()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)
```

- [ ] **Step 2: Verify Escape behavior**

1. `/reload`
2. `/run F.Config:Set('general.overviewCompleted', false); F.Onboarding.ShowOverview()`
3. Press `Escape`. Expected: modal minimizes to pip (not closes). Other WoW UI (game menu) should NOT open.
4. Click the pip to restore.
5. Verify other keys still propagate: press `T` (open talents) — expected: talents frame opens normally. Then close talents.
6. Close the overview manually with `×`.
7. No Lua errors.

- [ ] **Step 3: Commit and push**

```bash
git add Onboarding/Overview.lua
git commit -m "$(cat <<'EOF'
Wire Escape to minimize Overview modal

Escape now collapses the overview to its pip instead of leaking
to the game menu, matching the spec. Other keys still propagate.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 10: First-run auto-show in `Init.lua`

**Goal:** Auto-show the overview ~1 second after `PLAYER_LOGIN` when the wizard is already complete and the overview hasn't been seen yet. Defer to `PLAYER_REGEN_ENABLED` when in combat.

**Files:**
- Modify: `Init.lua` (around line 74)

- [ ] **Step 1: Extend the `PLAYER_LOGIN` handler**

Find the existing wizard auto-show block in `Init.lua`:

```lua
		-- First-run wizard
		if(not F.Config:Get('general.wizardCompleted')) then
			C_Timer.After(1, function()
				F.Onboarding.ShowWizard()
			end)
		end
```

Add the overview trigger immediately after it (before `self:UnregisterEvent('PLAYER_LOGIN')`):

```lua
		-- First-run overview (shown after wizard on next login)
		if(F.Config:Get('general.wizardCompleted') and not F.Config:Get('general.overviewCompleted')) then
			local function showOverviewDelayed()
				C_Timer.After(1, function()
					if(F.Onboarding and F.Onboarding.ShowOverview) then
						F.Onboarding.ShowOverview()
					end
				end)
			end

			if(InCombatLockdown()) then
				local deferFrame = CreateFrame('Frame')
				deferFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
				deferFrame:SetScript('OnEvent', function(self)
					self:UnregisterAllEvents()
					showOverviewDelayed()
				end)
			else
				showOverviewDelayed()
			end
		end
```

- [ ] **Step 2: Verify first-run auto-show (out of combat)**

1. `/run F.Config:Set('general.wizardCompleted', true); F.Config:Set('general.overviewCompleted', false); ReloadUI()`
2. Expected: after ~1 second of login, the overview modal appears at page 1.
3. Close it with `×`. `/run print(FramedDB.general.overviewCompleted)` — expected: `false` (still).
4. `/reload` again. Expected: overview appears again (because close didn't flip the flag).
5. Click `Done` through all pages. `/run print(FramedDB.general.overviewCompleted)` — expected: `true`.
6. `/reload`. Expected: overview does NOT appear (already completed).

- [ ] **Step 3: Verify combat-deferred auto-show**

1. `/run F.Config:Set('general.overviewCompleted', false)`
2. Find a training dummy or enter combat (`/startattack` on an enemy, or run into a mob briefly).
3. While still in combat, `/reload`.
4. Expected: no overview appears during combat. The login completes normally.
5. Drop combat (let the mob die or flee). Expected: within ~1 second of leaving combat, the overview appears.
6. Close it (`×`) and reset: `/run F.Config:Set('general.overviewCompleted', false)`.

- [ ] **Step 4: Commit and push**

```bash
git add Init.lua
git commit -m "$(cat <<'EOF'
Auto-show Overview on first login after wizard completes

Extends the PLAYER_LOGIN handler to trigger the Overview modal
~1s post-login when wizardCompleted is true and overviewCompleted
is false. Combat is respected — if the user is locked down, the
trigger defers to PLAYER_REGEN_ENABLED.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 11: Rewire Setup Wizard card button

**Goal:** Rename the "Take Tour" button to "Take Overview", update its tooltip body, and retarget its click handler to `F.Onboarding.ShowOverview()`. Remove the chat-fallback branch — the feature always exists now.

**Files:**
- Modify: `Settings/Cards/Appearance/SetupWizard.lua`

- [ ] **Step 1: Update constants and button copy**

Replace the file body:

```lua
local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local BUTTON_H = 28
local OVERVIEW_TOOLTIP_BODY = 'The overview walks you through Framed\'s core features: layouts, edit mode, settings cards, and aura indicators.'

function F.AppearanceCards.SetupWizard(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local wizardBtn = Widgets.CreateButton(inner, 'Re-run Setup Wizard', 'widget', widgetW, BUTTON_H)
	wizardBtn:SetOnClick(function()
		if(F.Onboarding and F.Onboarding.ShowWizard) then
			F.Onboarding.ShowWizard()
		end
	end)
	cardY = B.PlaceWidget(wizardBtn, inner, cardY, BUTTON_H)

	local overviewBtn = Widgets.CreateButton(inner, 'Take Overview', 'widget', widgetW, BUTTON_H)
	overviewBtn:SetWidgetTooltip('Take Overview', OVERVIEW_TOOLTIP_BODY)
	overviewBtn:SetOnClick(function()
		if(F.Onboarding and F.Onboarding.ShowOverview) then
			F.Onboarding.ShowOverview()
		end
	end)
	cardY = B.PlaceWidget(overviewBtn, inner, cardY, BUTTON_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
```

- [ ] **Step 2: Verify the button**

1. `/reload`
2. Open settings (`/fr`), go to Appearance → Setup Wizard card.
3. Expected: the second button reads `Take Overview`. Hover over it — tooltip says "Take Overview" with the body "The overview walks you through Framed's core features...".
4. Click it — overview modal appears on page 1.
5. Close with `×`.
6. Mark overview as completed: `/run F.Config:Set('general.overviewCompleted', true)`.
7. Click `Take Overview` again — overview should still open (manual relaunch ignores the completed flag and always starts at page 1).
8. Close it. Reset: `/run F.Config:Set('general.overviewCompleted', false)`.
9. No Lua errors.

- [ ] **Step 3: Commit and push**

```bash
git add Settings/Cards/Appearance/SetupWizard.lua
git commit -m "$(cat <<'EOF'
Retarget Setup Wizard card Tour button to Overview

Renames the button label and tooltip, points the click handler
at F.Onboarding.ShowOverview, and drops the dead chat fallback
branch since the feature is now always present.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 12: Final QA pass and CHANGELOG entry

**Goal:** Run the full manual test matrix from the spec, fix any issues found, and add a CHANGELOG entry.

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run the full spec test matrix**

From `docs/superpowers/specs/2026-04-13-framed-overview-design.md` §10. Walk through all 12 items in order. Reset the flag between tests with `/run F.Config:Set('general.overviewCompleted', false)` as needed.

1. **Fresh install path:** `/run FramedDB = nil; ReloadUI()`, complete wizard, `/reload` again. Overview appears ~1s after login on page 1 (Welcome).
2. **Skip:** page 3, click Skip Overview. Modal closes, pip hides, flag = true.
3. **Done:** step through 6 pages, click Done. Flag flips, modal closes.
4. **Close without completing:** page 2, click `×`. Flag stays false. `/reload` → overview auto-shows again.
5. **Minimize / restore:** page 4, click minimize. Pip shows "Framed Overview — 4/6" top-right. Click pip. Modal reopens on page 4.
6. **Escape:** page 5, press Escape. Modal minimizes (not closes). Game menu does not open.
7. **Back button:** page 1, Back disabled. Pages 2-6, Back steps backward and updates the progress rail.
8. **Combat auto-show:** enter combat, `/reload`. No overview during combat. Leave combat — overview appears within ~1s.
9. **Combat manual launch:** in combat, click Take Overview from Setup Wizard card. Chat error `Framed Overview cannot be opened in combat`. No modal.
10. **Manual relaunch after completion:** with flag = true, click Take Overview. Modal opens on page 1.
11. **Progress rail visual states:** at each step, past slots full-color, current accent-tinted, future 0.3 alpha greyed.
12. **Live widget pages:** pages 1, 4, 5, 6 all render their illustrations without errors. Resize WoW window — modal stays centered.

If any step fails, fix the root cause in the appropriate file. If the fix is small, add it to a follow-up commit on this branch. If the fix reveals a deeper design issue, stop and ask the user.

- [ ] **Step 2: Check luacheck**

Push triggers CI luacheck. Watch the CI run on `origin/working-testing` and address any warnings in the changed files. Run locally if possible: look for `.luacheckrc` + any `tools/luacheck.sh` wrapper.

- [ ] **Step 3: Add CHANGELOG entry**

Open `CHANGELOG.md` and find the in-progress version block (the topmost unreleased section). Add a new entry under its `### Added` (creating the subsection if absent):

```markdown
### Added
- New **Framed Overview** — a 6-page illustrated walkthrough covering layouts, edit mode, settings cards, aura indicators, and defensive/external tracking. Auto-shows on first login after the setup wizard and can be relaunched anytime from Appearance → Setup Wizard → Take Overview.

### Changed
- Replaced the unreachable guided tour with the new Overview (old `Onboarding/Tour.lua` removed).
```

- [ ] **Step 4: Regenerate Changelog card if the sync tool exists**

Run: `ls tools/sync-changelog.lua`

- If present: run `./tools/sync-changelog.lua` to regenerate the About card's changelog block.
- If absent: skip this step. The raw `CHANGELOG.md` is authoritative.

- [ ] **Step 5: Final commit and push**

```bash
git add CHANGELOG.md
# If sync-changelog ran:
# git add Settings/Cards/About.lua
git commit -m "$(cat <<'EOF'
Document Overview feature in CHANGELOG

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

- [ ] **Step 6: Final verification**

1. Check `git log --oneline working-testing` — expected: 12 commits from this plan, in order.
2. Check CI status on `origin/working-testing` — expected: green.
3. Do one more full `/reload` + `F.Onboarding.ShowOverview()` + step through all 6 pages to confirm nothing regressed during the later tasks.

---

## Self-Review Notes

Written after the initial draft:

- **Spec coverage:** Every section in the spec maps to at least one task. §1 Files → Tasks 1, 2, 3, 6. §2 State → Task 1. §3 Modal shell → Tasks 3, 7. §4 Minimize pip → Task 8. §5 Page registry → Tasks 4, 5, 6. §6 Lifecycle → Tasks 3, 8, 9, 10. §7 Module API → Tasks 1, 3, 8. §8 Edge cases → handled across Tasks 3, 10, 12. §9 Assets → Tasks 1, 8. §10 Testing → Task 12. §11 Open questions → none. §12 Alignment points → baked into Tasks 3, 6.
- **Placeholder scan:** No "TBD"/"implement later"/"add error handling" phrases. All code steps show complete replacement code blocks.
- **Type consistency:** Module locals (`modalFrame`, `pipFrame`, `currentStep`, `isMinimized`) declared in Task 1, referenced consistently in Tasks 3-10. `showPage` is forward-declared in Task 3 and assigned in Task 4. `PAGES` entries use the same shape (`id`, `title`, `body`, `buildIllustration`) across Tasks 4, 5, 6. Public API names match spec §7 throughout.
- **Known caveats flagged to implementer:**
  1. `F.Preview.ApplyUnitToFrame` is currently module-local; Task 4 suggests exporting it as a precursor if you want proper name/color rendering on page 1.
  2. Atlas names in Task 5 (`groupfinder-eye-frame`, `editmode-new-icon`) are best-effort; alternatives listed if they don't render.
  3. `pcall` usage in Tasks 5 and 6 is justified inline as feature-detection against Blizzard APIs per the project's "No pcall" convention carve-out.
  4. Task 8 is blocked on the `WindowMinimize.tga` asset existing; the task spells out "stop and ask" if it can't be sourced.
  5. File size check in Task 6 Step 6 is the explicit branch-point for splitting illustrations into a sibling file.
