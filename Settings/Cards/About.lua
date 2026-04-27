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
		version = 'v0.8.18-alpha',
		entries = {
			'**`Bar` depleted area now renders bg color** — the StatusBar frame\'s draw context was masking the parent container\'s BACKGROUND-layer bg texture, so the depleted portion of a bar appeared transparent (no visible "shaded" area) even though the container had a bg texture configured. Adds a second bg texture parented to the StatusBar itself so the depleted portion renders the bg from the StatusBar\'s own draw context. Affects both `BAR` and `BARS` (BARS uses Bar.Create per slot)',
			'**Long-duration aura filter extended** from `BARS` to track-all `OVERLAY`, `RECTANGLE`, `BAR`, and `BORDER` indicators — flask/food/long maintenance buffs no longer pin the indicator at a stale depletion progress in track-all mode. Spell-specific paths unchanged',
			'**`BAR` / `Rectangle` `showStacks` defaults to off** (matches UI checkbox initial state). `ICON` / `ICONS` still default on since the icon itself reveals what\'s matched',
			'**Reparented countdown text on Cooldown:Clear** — moved FontStrings now blank explicitly when the cooldown clears, fixing stale duration text bleeding through in secret content',
			'**`Health` / `Power` percent text** uses C-level `SetFormattedText` so secret curve results don\'t crash Lua-side formatting; renders invisible for secret values rather than throwing',
			'**`Name` element drops Lua-side UTF-8 truncation** in favor of native `SetWordWrap(false)` + bounded width. Avoids touching potentially-restricted name strings in Lua',
			'**`CrowdControl` / `LossOfControl` expiry comparisons** guarded against secret-tagged values; explicit timer stop when expiry is unavailable',
			'**`BorderIcon` dispel-color path** is opt-in via `useDispelColor` flag. `Externals` / `Defensives` keep their custom borders; `Debuffs` opt in and get curve-resolved colors via `C_UnitAuras.GetAuraDispelTypeColor` reusing oUF\'s dispel color table',
			'**Inline position panel shows the frame name** — once a frame is selected its hover highlight is suppressed, so the user lost on-screen confirmation of which frame they were dragging. Title at the top of the panel ("Player Frame", "Boss 1 Frame", etc.) makes it obvious. Settings.GetFrameUnitLabel exported for the lookup',
			'**Group click catchers live-resize from EditCache values** — party/raid/boss/arena/pinned catchers were sized from the real saved config at creation and never re-read, so width/height/columns/spacing edits never propagated to the catcher overlay. After deselect the catcher snapped back to its original size even though the underlying frames advanced. New `applyGroupCatcherLayout` helper runs from both `EDIT_CACHE_VALUE_CHANGED` and `EDIT_MODE_FRAME_SELECTED` so the catcher tracks slider edits in real time and shows the correct size when reshown',
			'**`Rectangle` indicator gets `Cast By` + `Tracked Spells` cards** — the new card-grid panel was missing both card definitions for `RECTANGLE`, so users couldn\'t add spells. The indicator preview rendered fine but the live frame never matched a real aura at runtime',
			'**Centralized `F.Indicators.SetAuraStackText` helper** — secret-safe stack rendering deduplicated across `Bar`, `Bars`, `BorderIcon`, `Color`, `Icon`. Unified `SetStacks(count, unit, auraInstanceID)` signature across all renderer types so callers don\'t need to know the concrete type',
			'**`Elements/Indicators/Color.lua` → `Rectangle.lua`** to match the user-facing label. The file backed the `RECTANGLE` indicator type but its name collided with the user-facing "Color / Duration Overlay" indicator (which is actually backed by `Overlay.lua`). Namespace renamed `F.Indicators.Color` → `F.Indicators.Rectangle`. No behavior change',
		},
	},
	{
		version = 'v0.8.17-alpha',
		entries = {
			'**Externals: Symbiotic Relationship leak in M+** — the RAID secret-aura fallback admitted Symbiotic Relationship in secret-active content because it carries the broad `RAID` classification despite being a passive bond rather than a combat-relevant external. Switched the fallback to Blizzard\'s tighter `RAID_IN_COMBAT` curation, which excludes passive bonds while still admitting Power Infusion and similar raid-important buffs',
			'**Icon: secret-safe DurationObject zero check** — `DurationObject:IsZero()` returns a secret boolean for classified combat auras (e.g. Ironbark on player in M+); the Lua test `not durationObj:IsZero()` then crashed mid-`SetSpell`, halting before the icon was rendered. Affected auras silently disappeared in secret content in addition to spamming the error frame. Wrapped the zero check in a helper that falls through to the C-level timer consumers when `IsZero` is secret',
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
