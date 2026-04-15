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
		version = 'v0.8.9-alpha',
		entries = {
			'Fix party/raid role sorting being silently ignored — the header was writing a nameList but kept `sortMethod=\'INDEX\'`, which falls through Blizzard\'s sort branches and leaves frames in default order; now uses `sortMethod=\'NAMELIST\'` so role order actually takes effect',
			'Fix `attempt to compare a secret number value` error from the cast tracker\'s recheck-skip optimization — the spellId comparison now guards against secret values returned by `UnitCastingInfo`/`UnitChannelInfo` in combat',
			'Fix `ADDON_ACTION_BLOCKED` on `FramedPartyPet1:ClearAllPoints()` when party composition changed mid-combat — pet re-anchor is now deferred until `PLAYER_REGEN_ENABLED` when the secure frames are locked down',
			'Internal cleanup: drop hardcoded fallback values in the Dispellable element that duplicated canonical defaults from `Presets/Defaults.lua`',
		},
	},
	{
		version = 'v0.8.8-alpha',
		entries = {
			'The new **Backups** system is now feature-complete — save, rename, load, and delete named snapshots, with inline export/import, version and size metadata, stale-version warnings, last-loaded tracking, and roundtrip verification that reports exactly which keys differ from your current config',
			'Fix Backups snapshot rows overflowing at narrow widths — titles now wrap above the buttons, the metadata line (version · date · layouts · size) wraps below the version when it\'s too long, and the row grows to fit; very narrow widths stack the buttons under the text',
			'Fix buttons disappearing from a Backups row when its Export area was opened — buttons are now pinned to the top of the row and the export area expands downward from the row\'s current height',
			'Fix auto-backup rows having an empty slot where Rename would be — Export now sits directly next to Delete',
			'Fix Rename edit box not dismissing when clicking the Rename button again or clicking outside the field; pressing Escape or Enter also closes it cleanly',
			'Style the version and author name in the About card with the accent color',
			'Polish inline dropdowns (underline, chevron, accent default) and cascade EditBox width through anchors so nested inputs size correctly',
			'Fix a race in the Toast dismiss animation that could leave a stale frame visible when a new toast slid in on top of it',
			'Show the active preset name in accent color in the Settings header',
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
		'The embedded oUF library is released under the MIT License. ' ..
		'See each respective LICENSE file for full terms.')

	Widgets.EndCard(card, parent, y)
	return card
end
