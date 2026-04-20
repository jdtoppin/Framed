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
	{
		version = 'v0.8.10-alpha',
		entries = {
			'Add **Frame Preview Card** — every Frame settings panel (player/target/party/raid/boss/arena/pet/solo) now renders a live unit frame preview at the top of the panel using your current config, pinned next to a summary card that stays in view while the settings scroll',
			'Raid preview card includes a 1–40 count stepper saved per character, so you can dial the preview to the group size you\'re actually tuning for',
			'Party preview includes a pet toggle to preview pet frames alongside party members',
			'**Focus Mode** — click a settings card (Health Color, Castbar, Auras, etc.) to spotlight the matching element in the preview; other elements dim to 20%. Your selection persists across `/reload`',
			'Preview card and frames animate smoothly when you change count, toggle Focus Mode, or resize the settings window',
			'Preview re-renders live as you edit config — structural changes (count, spacing) rebuild, cosmetic changes (colors, textures) just refresh',
			'Migrate **Defensives** and **Externals** panels to the same pinned Preview | Overview layout for consistency with the Frame panels',
			'Fix boss and arena previews where per-frame castbars overlapped the next frame instead of sitting cleanly below',
			'Fix boss/party/arena preview card titles truncating — fixed-count unit cards now get enough width for the title and Focus Mode toggle; raid keeps its auto-sizing',
			'Scrollbar UX: hover the right-edge strip to reveal the scrollbar (no more stolen clicks from mouse-motion detection), and dragging the thumb keeps it visible and fires lazy-load',
			'**Buffs/Debuffs** panels: auto-select the first enabled indicator on open; add/delete indicators with a cleaner inline form (Plus/Tick icons)',
			'**SpellList**: fix spell ID and name truncation, combine hover tooltip, tighten the ID column',
			'**StatusText**: replace the dead anchor controls with a proper position switch',
			'**Copy To**: move the control into the sub-header with a dropdown + direct-write button (the old standalone dialog is gone)',
			'Fix party pet ghost frames when members joined the group; roster now refreshes properly',
			'Guard party pet cross-zone check against secret values so it doesn\'t error in combat',
			'Fix `RoleIcon` not refreshing on spec change, and fix style 2 to use the correct quadrant overrides',
			'Revert a `PartyMemberFrame` state-visibility driver change that was breaking Blizzard\'s own frame cleanup',
			'Fix `StyleBuilder` preset `groupKey` fallback accidentally applying to derived presets — now scoped to base presets only',
			'Update summon-pending status text and color',
			'Add third-party library attribution to the README and mirror it in the About card',
			'Internal cleanup: drop dead code (`Core/DispelCapability.lua`, `Core/Version.Compare`, `CopyToDialog`), luacheck branch is clean',
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
