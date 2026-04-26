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
		version = 'v0.8.17-alpha',
		entries = {
			'**Externals: Symbiotic Relationship leak in M+** — the RAID secret-aura fallback admitted Symbiotic Relationship in secret-active content because it carries the broad `RAID` classification despite being a passive bond rather than a combat-relevant external. Switched the fallback to Blizzard\'s tighter `RAID_IN_COMBAT` curation, which excludes passive bonds while still admitting Power Infusion and similar raid-important buffs',
			'**Icon: secret-safe DurationObject zero check** — `DurationObject:IsZero()` returns a secret boolean for classified combat auras (e.g. Ironbark on player in M+); the Lua test `not durationObj:IsZero()` then crashed mid-`SetSpell`, halting before the icon was rendered. Affected auras silently disappeared in secret content in addition to spamming the error frame. Wrapped the zero check in a helper that falls through to the C-level timer consumers when `IsZero` is secret',
		},
	},
	{
		version = 'v0.8.16-alpha',
		entries = {
			'**Interface bump to 120005** — TOC interface version raised from 120001 to align with WoW 12.0.5',
			'**Settings memory leak fixed (closes #187)** — Framed memory previously climbed toward ~50 MB across settings open/close cycles and never dropped, even after forced GC. Resolved through a chain of fixes: panel teardown infrastructure, weak-key pixel/UI-scale registries, X-button + ESC routing through `Settings.Hide`, snapshot-keys-before-iteration in `TearDownAllPanels`, panel-owned `_eventBusOwners` declarations with recursive tree walk, single-installation OnShow hooks, gated CardGrid rebuilds, and a new `Settings._cachePanelsOnClose = true` policy that retains the cache for fast reopen now that the bounding fixes prevent compounding',
			'**Buffs/Debuffs/Externals/Defensives spec import hitch eliminated** — loading 60+ spec or healer spells via the indicator import button previously caused a visible frame stall. SpellList now virtualizes scrollable lists, chunks flat lists across frames, and bulk-imports via a new `AddSpells` API. ~240× theoretical reduction on the import path',
			'**TrackedSpells improvements (#180)** — import-from-spec button + spec-override hint + dropdown trigger + floating preview + off-spec filter',
			'**Settings panel breadcrumb title card with preset dropdown** — preset switcher promoted to a persistent card at the top of every preset-scoped panel',
			'**Active-preset row** in FramePresets uses an accent bar + tinted fill so the current preset is visually obvious',
			'**Pet-scope aura editing** — Defensives/Externals panels now hide when pet is the editing scope (those auras don\'t apply); other aura panels work for pet',
			'Cross-preset preset switch redirects stale frame panels to a sensible default instead of leaving the panel pointing at config that was just deleted',
			'Sidebar resync fixes for group-frame label and preset-scoped sidebar visibility on panel/preset change',
			'`SpellInput` edit box now shrinks to fit container width (no more overflow)',
			'Settings preset transitions are now transactional and reconcile synchronously, eliminating cross-listener ordering races',
			'**PrivateAuras: GRADIENT_HALF anchor fix (#163)** — dispel highlight overlay no longer renders with a stale baked height after layout changes; switched from imperative `SetHeight` to anchor-based sizing relative to the overlay frame\'s vertical midpoint',
			'**PrivateAuras: Duration Text Scale slider** — Blizzard\'s private-aura duration text uses a fixed FontObject with no anchor-level size override, which renders oversized on small icons. New slider scales 0.5×–1.5× while preserving icon dimensions',
			'**MissingBuffs: default glow type changed to Proc** (#178) — `Pixel` glow had ~20× the per-frame cost; high-CPU glow types now annotated in the dropdown',
			'**StyleBuilder (#165)** — defer `RegisterForClicks` when combat-locked instead of erroring; recovers cleanly out of combat',
			'**Combat lockdown guard** for `SetPropagateKeyboardInput` so settings keyboard input handling doesn\'t taint during combat',
			'**EventBus listener error isolation** — one listener throwing no longer halts the cascade for subsequent listeners; errors surface through the standard error handler',
			'**`UnitGUID` taint on pet tokens** — replaced GUID-based identity tracking with `UNIT_PET` bumps to avoid taint propagation through pet-token GUID reads',
			'**Identity generation split** (#118) — content vs identity generation tracked separately; aura cache invalidates correctly across roster reassignments without trashing the cache on every UNIT_AURA',
			'**LFR raid frame fix** — revert a `_G.CreateFrame` wrapper introduced for memory diagnostics that caused taint cascade across `SecureGroupHeaderTemplate`, ElvUI buff anchors, and nameplate aura calls. Replaced with post-hoc tree walks for the same diagnostic information without taint surface',
			'**BARS indicators** skip auras with infinite duration (couldn\'t be sensibly displayed on a depleting bar)',
			'**Buffs filter widening** — restored conditional filter widening for indicator spell lists so tracked spells outside the default filter set still surface',
			'**TargetedSpells + CastTracker removed** — pre-adoption removal of the runtime-gated TargetedSpells feature plus its only consumer. 14 reference sites pruned across StyleBuilder, LiveUpdate, Preview, AuraDefaults',
			'**Orphan files cleaned up** — `Elements/Core/Absorbs.lua` (superseded by Health.lua\'s inline absorb handling) and `Units/LiveUpdate/FrameConfig.lua` (11-line comment stub left behind by the FrameConfig sub-module split)',
			'**AuraState classified API** — element migration to a shared per-frame classification cache, eliminating per-aura predicate evaluation in the indicator hot path. Migrated: Externals (#137), Defensives (#138), Buffs (#139), Debuffs (#140), MissingBuffs (#141)',
			'**Per-instance classified entry pools** (#144) — bounds allocation churn during aura fan-out by reusing classified-entry tables instead of creating fresh ones per UNIT_AURA event',
			'**FullRefresh varargs elimination** (#155 item 3) — `GetAuraSlots` results now packed via a reused `_slotsScratch` field instead of varargs unpack, eliminating per-call allocations on every full aura refresh',
			'**AuraState helpful presence maps** — `FindHelpfulBySpellId` switches from linear scan to indexed lookup for repeated buff queries',
			'**Buffs `matchAura` hoisted** + `isRaidInCombat` always-gated; avoids redundant per-aura work',
			'**Icon caching** — initial color/threshold paint cached by `auraInstanceID`; threshold re-evaluated only on `SetSpell`; Icon ticker per-frame cost halved (#114)',
			'**Indicators refactor** — read `aura.applications` directly for stack counts (instead of secret-tainted intermediate); drop dead `dispelType` param from `Icon:SetSpell`; route Icons through unit + applications consistently',
			'**AuraState `acquireClassified` split** into helpful/harmful variants — eliminates a branch on every entry acquisition',
			'**MemDiag allocation profiler** — `/framed memdiag [seconds]` measures Lua heap allocation across aura-path hot funnels with ms tracking and tool-self-cost surfacing',
			'**`/framed memusage`** extended with addon-memory breakdown + four leak-shape probes (settings cache count, pixel updater counts, EventBus listener counts, UIParent direct-children count)',
			'**`/framed pools`** — per-instance classified pool inspection (#144 diagnostics)',
			'**`/framed settingsmem`** — opt-in probe with cycle-drift tracking, descendant counts, and ObjectType breakdown for settings memory regression detection',
			'**Tracked pre-commit hook** running luacheck on staged Lua files; install via `tools/install-hooks.sh`',
			'Buffs `matchAura` no longer mutates `AuraData` tables — Blizzard fields stay clean for downstream consumers',
			'Internal MemDiag in-situ probes stripped from `Icon.lua`/`Buffs.lua` hot paths; replaced with broader `OnUpdate` coverage in MemDiag itself',
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
