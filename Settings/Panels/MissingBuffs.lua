local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================

local SLIDER_H     = 26
local CHECK_H      = 22
local DROPDOWN_H   = 22
local WIDGET_W     = 220

-- ============================================================
-- Config helpers
-- ============================================================

local function get(key)
	local layoutName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return F.Config and F.Config:Get('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.missingBuffs.' .. key)
end

local function set(key, value)
	local layoutName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.missingBuffs.' .. key, value)
	end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.missingBuffs')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'missingbuffs',
	label   = 'Missing Buffs',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 16,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll  = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'missingbuffs')

		-- ── Description ────────────────────────────────────────
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('Tracks missing raid buffs: Mark of the Wild, Power Word: Fortitude, Arcane Intellect, and Battle Shout. Shows a colored frame highlight when a buff is missing.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- ── Highlight Type ─────────────────────────────────────
		local highlightHeading, highlightHeadingH = Widgets.CreateHeading(content, 'Frame Highlight', 2)
		highlightHeading:ClearAllPoints()
		Widgets.SetPoint(highlightHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - highlightHeadingH

		local hlCard, hlInner, hlCardY
		hlCard, hlInner, hlCardY = Widgets.StartCard(content, width, yOffset)

		local ht = C.HighlightType
		local highlightDD = Widgets.CreateDropdown(hlInner, WIDGET_W)
		highlightDD:SetItems({
			{ text = 'Gradient - Health Bar (Full)',    value = ht.GRADIENT_FULL },
			{ text = 'Gradient - Health Bar (Half)',    value = ht.GRADIENT_HALF },
			{ text = 'Solid - Health Bar (Current)',    value = ht.SOLID_CURRENT },
			{ text = 'Solid - Entire Frame',            value = ht.SOLID_ENTIRE },
		})
		highlightDD:SetValue(get('highlightType') or ht.GRADIENT_FULL)
		highlightDD:SetOnSelect(function(v) set('highlightType', v) end)
		highlightDD:ClearAllPoints()
		Widgets.SetPoint(highlightDD, 'TOPLEFT', hlInner, 'TOPLEFT', 0, hlCardY)
		hlCardY = hlCardY - DROPDOWN_H - C.Spacing.normal

		yOffset = Widgets.EndCard(hlCard, content, hlCardY)

		-- ── Final height ────────────────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
