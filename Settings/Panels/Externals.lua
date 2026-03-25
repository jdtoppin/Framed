local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Default external cooldown spell IDs
-- Pain Suppression (33206), Guardian Spirit (47788),
-- Ironbark (102342), Rallying Cry (97462),
-- Darkness (196718), Blessing of Sacrifice (6940),
-- Aura Mastery (31821), Devotion Aura (465),
-- Power Word: Barrier (62618), Barrier (115039)
-- ============================================================

local DEFAULT_EXTERNALS = {
	33206,   -- Pain Suppression
	47788,   -- Guardian Spirit
	102342,  -- Ironbark
	97462,   -- Rallying Cry
	196718,  -- Darkness
	6940,    -- Blessing of Sacrifice
	31821,   -- Aura Mastery
	62618,   -- Power Word: Barrier
}

-- ============================================================
-- Config helpers
-- ============================================================

local function getExternals()
	return (F.Config and F.Config:Get('auras.externals.spells')) or DEFAULT_EXTERNALS
end
local function setExternals(spells)
	if(F.Config) then
		F.Config:Set('auras.externals.spells', spells)
	end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED:auras')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'externals',
	label   = 'Externals',
	section = 'AURAS',
	order   = 11,
	parent  = 'buffsanddebuffs',
	create  = function(parent)
		local scroll = Widgets.CreateScrollFrame(
			parent, nil,
			parent:GetWidth(),
			parent:GetHeight())
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		local width   = parent:GetWidth() - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ── Header description ─────────────────────────────────
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('External cooldowns applied to you by other players.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- ── Section pane ───────────────────────────────────────
		local pane = Widgets.CreateTitledPane(content, 'External Cooldowns', width)
		pane:ClearAllPoints()
		Widgets.SetPoint(pane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - 20 - C.Spacing.normal

		-- ── Spell list ─────────────────────────────────────────
		local spellList = Widgets.CreateSpellList(content, width, 200)
		spellList:ClearAllPoints()
		Widgets.SetPoint(spellList, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - 200 - C.Spacing.normal

		-- Populate from config or defaults
		spellList:SetSpells(getExternals())
		spellList:SetOnChanged(function(spells)
			setExternals(spells)
		end)

		-- ── Spell input ────────────────────────────────────────
		local spellInput = Widgets.CreateSpellInput(content, width)
		spellInput:ClearAllPoints()
		Widgets.SetPoint(spellInput, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		spellInput:SetSpellList(spellList)
		yOffset = yOffset - 44 - C.Spacing.normal

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
