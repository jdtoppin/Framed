local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Default defensive cooldown spell IDs
-- Ice Block (45438), Divine Shield (642),
-- Cloak of Shadows (31224), Icebound Fortitude (48792),
-- Dispersion (47585), Survival Instincts (61336),
-- Shield Wall (871), Last Stand (12975),
-- Netherwalk (196555), Blur (198589)
-- ============================================================

local DEFAULT_DEFENSIVES = {
	45438,   -- Ice Block
	642,     -- Divine Shield
	31224,   -- Cloak of Shadows
	48792,   -- Icebound Fortitude
	47585,   -- Dispersion
	61336,   -- Survival Instincts
	871,     -- Shield Wall
	12975,   -- Last Stand
}

-- ============================================================
-- Config helpers
-- ============================================================

local function getDefensives()
	return (F.Config and F.Config:Get('auras.defensives.spells')) or DEFAULT_DEFENSIVES
end
local function setDefensives(spells)
	if(F.Config) then
		F.Config:Set('auras.defensives.spells', spells)
	end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED:auras')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'defensives',
	label   = 'Defensives',
	section = 'AURAS',
	order   = 12,
	parent  = 'buffsanddebuffs',
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

		-- ── Header description ─────────────────────────────────
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('Personal defensive cooldowns to track on yourself.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- ── Section pane ───────────────────────────────────────
		local pane = Widgets.CreateTitledPane(content, 'Defensive Cooldowns', width)
		pane:ClearAllPoints()
		Widgets.SetPoint(pane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - 20 - C.Spacing.normal

		-- ── Spell list ─────────────────────────────────────────
		local spellList = Widgets.CreateSpellList(content, width, 200)
		spellList:ClearAllPoints()
		Widgets.SetPoint(spellList, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - 200 - C.Spacing.normal

		-- Populate from config or defaults
		spellList:SetSpells(getDefensives())
		spellList:SetOnChanged(function(spells)
			setDefensives(spells)
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
