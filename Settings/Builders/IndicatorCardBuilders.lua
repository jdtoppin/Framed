local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local Settings = F.Settings

-- Shared layout constants (match IndicatorPanels.lua)
local WIDGET_W    = 200
local DROPDOWN_H  = 30
local SLIDER_H    = 36
local CHECK_H     = 22
local BUTTON_H    = 28

local function placeWidget(widget, parent, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.tight
end

local function placeHeading(parent, text, level, yOffset)
	local fs = Widgets.CreateFontString(parent, level == 2 and C.Font.sizeSmall or C.Font.sizeNormal, C.Colors.textSecondary)
	fs:SetText(text)
	fs:ClearAllPoints()
	Widgets.SetPoint(fs, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	return yOffset - (level == 2 and C.Font.sizeSmall or C.Font.sizeNormal) - C.Spacing.tight
end

-- ============================================================
-- Card Builders
-- Each follows the CardGrid builder signature:
--   function(parent, width, data, update, get, set, rebuildPanel)
-- Returns: card frame (from EndCard)
-- ============================================================

local Builders = {}
F.Settings.IndicatorCardBuilders = Builders

-- ── Cast By ─────────────────────────────────────────────────
function Builders.CastBy(parent, width, data, update)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local castByDD = Widgets.CreateDropdown(inner, WIDGET_W)
	castByDD:SetItems({
		{ text = 'Me',      value = C.CastFilter.ME },
		{ text = 'Others',  value = C.CastFilter.OTHERS },
		{ text = 'Anyone',  value = C.CastFilter.ANYONE },
	})
	castByDD:SetValue(data.castBy or C.CastFilter.ME)
	castByDD:SetOnSelect(function(value) update('castBy', value) end)
	cardY = placeWidget(castByDD, inner, cardY, DROPDOWN_H)

	return Widgets.EndCard(card, parent, cardY)
end

-- ── Tracked Spells ──────────────────────────────────────────
function Builders.TrackedSpells(parent, width, data, update, rebuildPanel)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local spList = Widgets.CreateSpellList(inner, width - 24, nil)
	spList:SetSpells(data.spells or {})
	spList:SetOnChanged(function(spells)
		update('spells', spells)
		if(spList._showColorPicker) then
			update('spellColors', spList:GetSpellColors())
		end
	end)

	-- Show per-spell color pickers for colored square and bar types
	if(data.displayType == C.IconDisplay.COLORED_SQUARE
		or data.type == C.IndicatorType.BAR
		or data.type == C.IndicatorType.BARS) then
		spList:SetSpellColors(data.spellColors or {})
		spList:SetShowColorPicker(true)
	end

	-- Calculate spell list height based on spell count
	local spellCount = data.spells and #data.spells or 0
	local spListH = math.max(60, spellCount * 24 + 8)
	cardY = placeWidget(spList, inner, cardY, spListH)

	local spInput = Widgets.CreateSpellInput(inner, width - 24)
	cardY = placeWidget(spInput, inner, cardY, 50)
	spInput:SetSpellList(spList)
	spInput:SetOnAdd(function() update('spells', spList:GetSpells()) end)

	local btnRow = CreateFrame('Frame', nil, inner)
	btnRow:SetHeight(24)
	Widgets.SetPoint(btnRow, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
	btnRow:SetWidth(width - 24)

	local importBtn = Widgets.CreateButton(btnRow, 'Import Healer Spells', 'widget', 160, 24)
	Widgets.SetPoint(importBtn, 'TOPLEFT', btnRow, 'TOPLEFT', 0, 0)
	importBtn:SetOnClick(function()
		F.Settings.Builders.ShowImportPopup(function(selectedSpells)
			if(not selectedSpells or #selectedSpells == 0) then return end
			local existing = spList:GetSpells()
			for _, spellID in next, selectedSpells do
				existing[#existing + 1] = spellID
			end
			spList:SetSpells(existing)
			update('spells', existing)
		end)
	end)

	local deleteAllBtn = Widgets.CreateButton(btnRow, 'Delete All Spells', 'red', 140, 24)
	deleteAllBtn:SetPoint('LEFT', importBtn, 'RIGHT', C.Spacing.tight, 0)
	deleteAllBtn:SetOnClick(function()
		Widgets.ShowConfirmDialog('Delete All Spells', 'Remove all tracked spells from this indicator?', function()
			spList:SetSpells({})
			update('spells', {})
		end)
	end)

	cardY = cardY - 24 - C.Spacing.tight

	return Widgets.EndCard(card, parent, cardY)
end
