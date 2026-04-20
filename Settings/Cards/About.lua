local _, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.AboutCards = F.AboutCards or {}

local function getVersion()
	local v = C_AddOns and C_AddOns.GetAddOnMetadata
		and C_AddOns.GetAddOnMetadata('Framed', 'Version')
	return v or (F.VERSION or '1.0.0')
end

local function getAuthor()
	local a = C_AddOns and C_AddOns.GetAddOnMetadata
		and C_AddOns.GetAddOnMetadata('Framed', 'Author')
	return a or 'Moodibs'
end

-- Place a wrapped font string at (indent, y) inside inner, return next y.
local function placeWrapped(inner, innerW, y, text, color, indent)
	indent = indent or 0
	local fs = Widgets.CreateFontString(inner, C.Font.sizeSmall, color or C.Colors.textSecondary)
	fs:SetJustifyH('LEFT')
	fs:ClearAllPoints()
	Widgets.SetPoint(fs, 'TOPLEFT', inner, 'TOPLEFT', indent, y)
	fs:SetWidth(innerW - indent)
	fs:SetWordWrap(true)
	fs:SetText(text)
	return y - fs:GetStringHeight() - C.Spacing.base
end

-- ============================================================
-- About
-- ============================================================

function F.AboutCards.About(parent, width)
	local card, inner, y = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	local a = C.Colors.accent
	local accentHex = F.ColorUtils.RGBToHex(a[1], a[2], a[3])
	local header = '|cff' .. accentHex .. 'v' .. getVersion() .. '|r'
		.. '  •  Made by '
		.. '|cff' .. accentHex .. getAuthor() .. '|r'

	y = placeWrapped(inner, innerW, y, header, C.Colors.textNormal)
	y = y - C.Spacing.tight

	y = placeWrapped(inner, innerW, y,
		'Framed is a modern, customizable unit frame and raid frame addon for World of Warcraft. ' ..
		'It replaces Blizzard\'s default unit frames with fully configurable alternatives for ' ..
		'player, target, focus, party, raid, boss, arena, and pet frames.')

	Widgets.EndCard(card, parent, y)
	return card
end

-- ============================================================
-- Getting Started
-- ============================================================

local GETTING_STARTED_LINES = {
	'|cff00ccff/framed|r or |cff00ccff/fr|r — Open this settings window',
	'|cff00ccff/framed edit|r — Enter edit mode to drag and reposition frames',
	'|cff00ccffLeft-click|r the minimap icon to open settings',
	'|cff00ccffRight-click|r the minimap icon to toggle edit mode',
}

function F.AboutCards.GettingStarted(parent, width)
	local card, inner, y = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	for _, line in next, GETTING_STARTED_LINES do
		y = placeWrapped(inner, innerW, y, line, nil, C.Spacing.tight)
	end

	Widgets.EndCard(card, parent, y)
	return card
end

-- ============================================================
-- Features
-- ============================================================

local FEATURE_LINES = {
	'Fully configurable health, power, and cast bars',
	'Aura indicators: buffs, debuffs, defensives, externals, dispellable, missing buffs, private auras, and targeted spells',
	'Custom indicator system with icons, bars, border glows, color overlays, and border icons',
	'Click casting with per-spec defaults',
	'Preset system with content-based auto-switching (raid, dungeon, PvP)',
	'Drag-and-drop edit mode with snap-to-grid and alignment guides',
	'Profile import and export',
}

function F.AboutCards.Features(parent, width)
	local card, inner, y = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	for _, line in next, FEATURE_LINES do
		y = placeWrapped(inner, innerW, y, '• ' .. line, nil, C.Spacing.tight)
	end

	Widgets.EndCard(card, parent, y)
	return card
end

-- ============================================================
-- Changelog
-- Regenerated from CHANGELOG.md by tools/sync-changelog.lua.
-- Do not edit the block between BEGIN/END markers by hand.
-- ============================================================

-- BEGIN GENERATED CHANGELOG
local CHANGELOG = {
	{
		version = 'v0.8.12-alpha',
		entries = {
			'**Pinned Frames in Edit Mode** — the drag catcher and selected preview now render the full 9-slot grid instead of a single fake frame, so moving pinned frames in edit mode reflects what you\'ll actually see in-game',
			'Pinned anchor convention flipped to TOPLEFT to match boss/arena (drag math, catcher bounds, and live layout now agree); existing CENTER-anchored pinned saves are auto-migrated on load to the equivalent TOPLEFT offset so nothing visually shifts',
			'Pinned geometry edits (width, height, columns, spacing) live-update without the grid flashing during resize, and Resize Anchor compensation keeps the pivot edge visually fixed instead of bouncing back on each slider tick',
			'Pinned placeholder identity labels ("Pin 1" … "Pin 9") and slot name tags ("Click to assign", character name) now scale with `Name font size` (primary and primary−2, floor 8) — previously hardcoded text looked oversized at non-1.0 UI scales',
			'Fix edit-mode first drag doing nothing visible — clicking-and-dragging immediately (without releasing first) now selects the frame so the preview appears as you drag',
			'Fix group position sliders (party, raid, arena, boss) not moving the real frame during slider drag in edit mode — the handler only supported solo CENTER anchoring',
			'Fix edit-mode preview not rebuilding when position/size sliders change — preview now tracks slider motion in real time via the EditCache',
			'Fix inline edit panel sliders and dropdowns sometimes missing clicks — split into a sibling shield + panel so children hit-test uncontested; inline panel rebuilds on preset switch so sliders read the active preset\'s config',
			'Fix boss and arena frames saving off-screen after a drag — they were written as TOPLEFT offsets but reapplied as CENTER offsets on reload/preset change. Now TOPLEFT end-to-end via a `PSEUDO_GROUPS` cascade path; existing saves self-heal because the stored values were already in TOPLEFT space',
			'Narrow pinned settings card keeps a 2-column quick-nav summary (was collapsing to 1 column and pushing most rows below the fold); summary rows reflow mid-animation so labels no longer clip past the card edge while the card width tweens',
			'Preset switches now redirect away from preset-specific panels (e.g. pinned under Solo) even while Settings is hidden, so reopening doesn\'t flash a stale panel',
			'Inline edit panel stripped down to just Position & Layout — edit mode is strictly for positioning; all other settings live in the main Settings window with live previews',
			'Internal cleanup: drop inert `config.count` from pinned (always capped at 9, no UI), consolidate pinned frame-scale handling onto a single anchor-level `RegisterForUIScale` (removes the per-frame gear counter-scale workaround), and rename a shadowed migration local to keep luacheck clean',
		},
	},
	{
		version = 'v0.8.11-alpha',
		entries = {
			'**Pinned Frames** — up to 9 standalone frames that track specific group members by name, following players across roster reshuffles. Supports Focus / Focus Target / name-target slots. Role-grouped class-colored assignment dropdown available from the Settings card, empty-slot placeholder click, and a hover-gear icon on assigned pins (out of combat). First-class aura configuration across all 10 aura sub-panels. Per-preset; absent in Solo',
			'Pinned Frames Settings panel with master enable toggle in the preview card, inline slot assignment, and live-update routing so edits apply without `/reload`',
			'EditMode integration for Pinned Frames — drag to position (CENTER anchor convention matches the settings panel), click in edit mode to open the inline Pinned panel, hide from the sidebar when the active preset has no `pinnedConfig`',
			'Empty-slot placeholders render a dimmed identity label (Pin 1 … Pin 9) and become clickable targets for assignment; placeholder mouse-handling is gated so hidden gear icons don\'t swallow clicks',
			'**FramePreview** now renders the pinned grid alongside the other unit types, and uses `statusText.position` consistently instead of stale anchor keys that caused name tags to drift in the preview',
			'Bridge `PLAYER_REGEN_ENABLED` through `EventBus` so combat-flush listeners can register via `F.EventBus:Register` instead of maintaining their own event frames',
			'Fix pinned gear icon rendering larger on resolved frames than on unresolved (placeholder) frames at non-1.0 UIParent scales — live-frame gears now counter-scale to match the placeholder gear\'s physical size',
			'Fix `attempt to perform arithmetic on local \'x\' (a nil value)` crash in `FrameConfigText.lua` when toggling Health → Attach to name off. The Health element wasn\'t recording detached anchor values at setup when the text was created attached, so the live toggle had no coordinates to restore to',
			'Internal cleanup: drop Cell references from in-code comments (licensing hygiene — Cell is ARR), remove the defensive `SettingsCards.Pinned` existence guard for idiom consistency, collapse empty stub branches in the pinned gear-icon path',
		},
	},
}
-- END GENERATED CHANGELOG

function F.AboutCards.Changelog(parent, width)
	local card, inner, y = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	for i, release in next, CHANGELOG do
		if(i > 1) then y = y - C.Spacing.tight end
		y = placeWrapped(inner, innerW, y, release.version, C.Colors.textNormal)
		for _, line in next, release.entries do
			y = placeWrapped(inner, innerW, y, '• ' .. line, nil, C.Spacing.tight)
		end
	end

	Widgets.EndCard(card, parent, y)
	return card
end

-- ============================================================
-- Credits
-- ============================================================

local CREDIT_LINES = {
	'oUF — Embedded unit frame framework (MIT). Authored by Haste & contributors.',
	'AbstractFramework — UI library design inspiration (GPL v3). Pixel-perfect sizing approach.',
	'LibSharedMedia-3.0 — Font and statusbar texture registry.',
}

function F.AboutCards.Credits(parent, width)
	local card, inner, y = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	for _, line in next, CREDIT_LINES do
		y = placeWrapped(inner, innerW, y, '• ' .. line, nil, C.Spacing.tight)
	end

	Widgets.EndCard(card, parent, y)
	return card
end

-- ============================================================
-- License
-- ============================================================

function F.AboutCards.License(parent, width)
	local card, inner, y = Widgets.StartCard(parent, width, 0)
	local innerW = width - Widgets.CARD_PADDING * 2

	y = placeWrapped(inner, innerW, y,
		'Framed is released under the GNU General Public License v3 (GPL v3). ' ..
		'Framed includes the following third-party libraries, each subject to their own license terms: ' ..
		'oUF, LibStub, CallbackHandler, LibCustomGlow, LibSerialize, LibDeflate, LibSharedMedia, LibDataBroker, and LibDBIcon. ' ..
		'See each respective LICENSE file for full terms.')

	Widgets.EndCard(card, parent, y)
	return card
end
