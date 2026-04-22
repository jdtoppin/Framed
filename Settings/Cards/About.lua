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
		version = 'v0.8.14-alpha',
		entries = {
			'**12.0.5 compatibility** — fix `bad argument #2 to \'?\' (Current Field: [isContainer])` error on unit frame spawn; 12.0.5 added a required `isContainer` field to `C_UnitAuras.AddPrivateAuraAnchor`\'s args table',
			'Add `/framed aurastate [unit]` debug slash — dumps the classified aura flag breakdown for a unit (defaults to target), showing which of `external-defensive`, `important`, `player-cast`, `big-defensive`, `raid`, `boss`, `from-player-or-pet` apply to each aura. Useful for verifying classification correctness as #115\'s B-series migrations land',
			'Internal: AuraState now exposes shared per-frame classification (`GetHelpfulClassified` / `GetHarmfulClassified` / `GetClassifiedByInstanceID`) with write-path invalidation wired through `FullRefresh` and `ApplyUpdateInfo`. No element yet consumes the new API — infrastructure only in this patch, element migrations follow in subsequent releases (#115 B1-B6)',
		},
	},
	{
		version = 'v0.8.13-alpha',
		entries = {
			'**12.0.5 readiness** — fix Buffs `castBy = \'me\'` / `\'others\'` silently filtering to empty when Blizzard marks `sourceUnit` secret in combat (#113); the indicator now falls back to `isFromPlayerOrPlayerPet` when the source is unreachable',
			'Guard `UnitIsUnit` call sites against compound-token nil returns so 12.0.5\'s stricter token handling doesn\'t error (#122)',
			'Invalidate the aura cache on encounter boundaries so boss-aura changes don\'t stick across pulls (#123)',
			'Halve `IconTicker` per-frame cost and skip redundant threshold setters on aura icons (#114)',
			'Fix `ADDON_ACTION_BLOCKED` on `FramedPinnedAnchor:Hide` when a roster update arrives mid-combat — Pinned `Refresh()` now defers to `PLAYER_REGEN_ENABLED` if combat is locked down (mirrors the existing `pendingResolve` pattern)',
			'Buffs aura filter is now derived from the indicator set instead of a separate `buffFilterMode` config key — any indicator with a spell list widens the query to `HELPFUL` so specific tracked spells (e.g. follower Rejuvenation) can surface; otherwise stays on `HELPFUL|RAID_IN_COMBAT` to keep trivial raid buffs out. The vestigial `buffFilterMode` key (never had UI) is dropped and migrated out of existing saves',
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
