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

	y = placeWrapped(inner, innerW, y,
		'v' .. getVersion() .. '  •  ' .. getAuthor(),
		C.Colors.textNormal)
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
		version = 'v0.8.6-alpha',
		entries = {
			'Fix import/export failing with "Invalid payload structure" on every valid import — a double-pcall was silently dropping the deserialized payload; also rewrite the error messages in plain language',
			'Add tooltips on the Import mode switch explaining what Replace and Merge actually do',
			'Fix **Missing Buffs** indicator running even when disabled in settings',
			'Fix party/raid role sorting occasionally snapping frames to the wrong position on first group spawn — roster events are now bridged through EventBus and the nameList is rebuilt once group membership is fully populated',
			'Backfill aura sub-table defaults into existing saved presets — Arena/Boss/Solo/Minimal frames no longer end up missing dispellable, defensive, external, and missing-buff configuration after upgrading',
			'Guard **Private Auras** and **Targeted Spells** against partial config tables so missing optional sub-tables no longer error during Setup',
			'Reduce cast-tracker broadcast chatter by skipping redundant updates',
			'Polish **Framed Overview** illustrations and dim the background while the Overview is open',
			'Retarget the Setup Wizard card\'s Tour button to the new Overview (old `Onboarding/Tour.lua` removed in v0.8.5-alpha)',
			'Internal cleanup: drop unused imports, rename shadowing locals, fix luacheck warnings across Elements, Settings, Widgets, and builders',
		},
	},
	{
		version = 'v0.8.5-alpha',
		entries = {
			'Add **Framed Overview** — a 6-page illustrated walkthrough covering layouts, edit mode, settings cards, aura indicators, and defensives/externals; auto-shows on first login after the setup wizard and can be relaunched from Appearance → Setup Wizard → Take Overview',
			'Escape collapses the Overview to a top-right pip instead of leaking to the game menu; click the pip to resume',
			'Replace the unreachable guided tour with the new Overview (old `Onboarding/Tour.lua` removed)',
			'Promote `SetupAccentHover` to the shared Widgets library so other panels can reuse the accent fade',
			'Export `F.Preview.ApplyUnitToFrame` so the Overview welcome page can render a live 3-member party sample',
			'Add role sorting for raid and party frames (Tank/Healer/DPS ordering via SecureGroupHeader nameList)',
			'Raid role mode: flat sort across groups, follows orientation and anchor point',
			'Party role mode: single sorted column',
			'Add Sorting settings card with role order presets',
			'Add icon-row dropdown widget showing inline role icon previews',
			'Edit mode preview and click catcher now reflect sort mode layout',
			'Fix edit mode preset switch snapping frames to top-left when target preset had no config for that frame',
			'Post release notes to Discord from the release workflow',
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
