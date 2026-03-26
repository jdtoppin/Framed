local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Default player CC spell IDs
-- Polymorph (118), Hex (51514), Freezing Trap (187650),
-- Mind Control (605), Entangling Roots (339),
-- Hibernate (2637), Blind (2094),
-- Intimidating Shout (5246)
-- ============================================================

local DEFAULT_CC_SPELLS = {
	118,     -- Polymorph
	51514,   -- Hex
	187650,  -- Freezing Trap
	605,     -- Mind Control
	339,     -- Entangling Roots
	2094,    -- Blind
	5246,    -- Intimidating Shout
}

-- ============================================================
-- Config helpers
-- ============================================================

local function getCCSpells()
	return (F.Config and F.Config:Get('auras.crowdControl.spells')) or DEFAULT_CC_SPELLS
end
local function setCCSpells(spells)
	if(F.Config) then
		F.Config:Set('auras.crowdControl.spells', spells)
	end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED:auras')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'crowdcontrol',
	label   = 'Crowd Control',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 21,
	parent  = 'lossofcontrol',
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(
			parent, nil,
			parentW,
			parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'crowdcontrol')

		-- ── Header description ─────────────────────────────────
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('Player CC spells to track on enemy targets.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- ── Section heading ────────────────────────────────────
		local ccHeading, ccHeadingH = Widgets.CreateHeading(content, 'Tracked CC Spells', 2)
		ccHeading:ClearAllPoints()
		Widgets.SetPoint(ccHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - ccHeadingH

		-- ── Spell list ─────────────────────────────────────────
		local spellList = Widgets.CreateSpellList(content, width, 200)
		spellList:ClearAllPoints()
		Widgets.SetPoint(spellList, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - 200 - C.Spacing.normal

		spellList:SetSpells(getCCSpells())
		spellList:SetOnChanged(function(spells)
			setCCSpells(spells)
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
