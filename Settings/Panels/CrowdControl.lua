local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Widget constants
-- ============================================================

local SLIDER_H   = 26
local CHECK_H    = 22

-- ============================================================
-- Default player CC spell IDs
-- Polymorph (118), Hex (51514), Freezing Trap (187650),
-- Mind Control (605), Entangling Roots (339),
-- Blind (2094), Intimidating Shout (5246)
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
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return (F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.crowdControl.spells')) or DEFAULT_CC_SPELLS
end

local function setCCSpells(spells)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.crowdControl.spells', spells)
	end
	if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.crowdControl')
	end
end

local function get(key)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.crowdControl.' .. key)
end

local function set(key, value)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.crowdControl.' .. key, value)
	end
	if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
	if(key ~= 'enabled' and F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.crowdControl')
	end
	F.Settings.UpdateAuraPreviewDimming('crowdControl', nil)
end

-- ============================================================
-- Card builders
-- Each follows CardGrid builder signature:
--   function(parent, width)
-- ============================================================

local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

local function buildOverviewCard(parent, width)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	-- Enabled toggle
	local enableCB = Widgets.CreateCheckButton(inner, 'Enabled', function(checked)
		set('enabled', checked)
	end)
	enableCB:SetChecked(get('enabled') or false)
	cy = placeWidget(enableCB, inner, cy, CHECK_H)

	-- Description
	local descFS = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textActive)
	descFS:SetWidth(width - Widgets.CARD_PADDING * 2)
	descFS:SetJustifyH('LEFT')
	descFS:SetWordWrap(true)
	descFS:SetText('Track player CC spells cast on enemy targets. Displays an icon overlay when the tracked debuff is active.')
	cy = placeWidget(descFS, inner, cy, descFS:GetStringHeight())

	Widgets.EndCard(card, parent, cy)
	return card
end

local SPELL_LIST_H  = 200
local SPELL_INPUT_H = 44

local function buildTrackedSpellsCard(parent, width)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	local spellList = Widgets.CreateSpellList(inner, width - Widgets.CARD_PADDING * 2, SPELL_LIST_H)
	spellList:SetSpells(getCCSpells())
	spellList:SetOnChanged(function(spells)
		setCCSpells(spells)
	end)
	cy = placeWidget(spellList, inner, cy, SPELL_LIST_H)

	local spellInput = Widgets.CreateSpellInput(inner, width - Widgets.CARD_PADDING * 2)
	spellInput:SetSpellList(spellList)
	cy = placeWidget(spellInput, inner, cy, SPELL_INPUT_H)

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildDisplayCard(parent, width)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', widgetW, 8, 48, 1)
	sizeSlider:SetValue(get('iconSize') or 16)
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	cy = placeWidget(sizeSlider, inner, cy, SLIDER_H)

	local durCheck = Widgets.CreateCheckButton(inner, 'Show Duration', function(checked)
		set('showDuration', checked)
	end)
	durCheck:SetChecked(get('showDuration') ~= false)
	cy = placeWidget(durCheck, inner, cy, CHECK_H)

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildPositionCard(parent, width)
	local _, card = F.Settings.BuildPositionCard(parent, width, 0, get, set, { noHeading = true })
	return card
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id         = 'crowdcontrol',
	label      = 'Crowd Control',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 21,
	parent     = 'lossofcontrol',
	create     = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll  = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'crowdcontrol')

		-- ── CardGrid ─────────────────────────────────────────────
		local grid = Widgets.CreateCardGrid(content, width)
		grid:SetTopOffset(math.abs(yOffset))

		grid:AddCard('preview',        'Preview',         F.Settings.AuraPreview.BuildPreviewCard, {})
		grid:SetSticky('preview')
		grid:AddCard('overview',       'Overview',        buildOverviewCard,       {})
		grid:AddCard('trackedSpells',  'Tracked Spells',  buildTrackedSpellsCard,  {})
		grid:AddCard('display',        'Display',         buildDisplayCard,        {})
		grid:AddCard('layout',         'Layout',          buildPositionCard,       {})

		-- ── Initial layout ────────────────────────────────────────
		grid:Layout(0, parentH)
		content:SetHeight(grid:GetTotalHeight())
		scroll:UpdateScrollRange()

		-- ── Scroll integration ────────────────────────────────────
		local function onScroll()
			local offset = scroll._scrollFrame:GetVerticalScroll()
			local viewH  = scroll._scrollFrame:GetHeight()
			grid:Layout(offset, viewH)
			content:SetHeight(grid:GetTotalHeight())
		end

		scroll._scrollFrame:HookScript('OnMouseWheel', function()
			C_Timer.After(0, onScroll)
		end)

		-- ── Resize handling ───────────────────────────────────────
		local resizeKey = 'CrowdControl.resize'
		local function onResize(newW)
			local newWidth = newW - C.Spacing.normal * 2
			grid:SetWidth(newWidth)
			content:SetWidth(newW)
			content:SetHeight(grid:GetTotalHeight())
		end

		F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)

		-- ── Cleanup on hide, re-register on show ──────────────────
		scroll:HookScript('OnHide', function()
			grid:CancelAnimations()
			F.EventBus:Unregister('SETTINGS_RESIZED', resizeKey)
		end)

		scroll:HookScript('OnShow', function()
			F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)
			grid:Layout(0, parentH, false)
			content:SetHeight(grid:GetTotalHeight())
		end)

		scroll._ownedPreview = F.Settings._auraPreview
		return scroll
	end,
})
