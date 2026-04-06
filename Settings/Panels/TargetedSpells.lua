local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Widget constants
-- ============================================================

local SLIDER_H     = 26
local DROPDOWN_H   = 22
local CHECK_H      = 22

-- ============================================================
-- Config helpers
-- ============================================================

local function get(key)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.targetedSpells.' .. key)
end

local function set(key, value)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.targetedSpells.' .. key, value)
	end
	if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
	if(key ~= 'enabled' and F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.targetedSpells')
	end
	F.Settings.UpdateAuraPreviewDimming('targetedSpells', nil)
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

	-- Description
	local descFS = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textSecondary)
	descFS:SetWidth(width - Widgets.CARD_PADDING * 2)
	descFS:SetText('Highlight units that are casting targeted spells at the group. Supports icon display, border glow, or both.')
	descFS:SetWordWrap(true)
	cy = placeWidget(descFS, inner, cy, descFS:GetStringHeight())

	-- Enabled toggle
	local enableCheck = Widgets.CreateCheckButton(inner, 'Enabled', function(checked)
		set('enabled', checked)
	end)
	enableCheck:SetChecked(get('enabled'))
	cy = placeWidget(enableCheck, inner, cy, CHECK_H)

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildDisplayModeCard(parent, width, updateVisibility)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local modeDD = Widgets.CreateDropdown(inner, widgetW)
	modeDD:SetItems({
		{ text = 'Icons',       value = 'Icons' },
		{ text = 'Border Glow', value = 'BorderGlow' },
		{ text = 'Both',        value = 'Both' },
	})
	modeDD:SetValue(get('displayMode') or 'Both')
	modeDD:SetOnSelect(function(v)
		set('displayMode', v)
		updateVisibility(v)
	end)
	cy = placeWidget(modeDD, inner, cy, DROPDOWN_H)

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildIconSettingsCard(parent, width)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', widgetW, 8, 48, 1)
	sizeSlider:SetValue(get('iconSize') or 16)
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	cy = placeWidget(sizeSlider, inner, cy, SLIDER_H)

	local maxSlider = Widgets.CreateSlider(inner, 'Max Displayed', widgetW, 1, 10, 1)
	maxSlider:SetValue(get('maxDisplayed') or 1)
	maxSlider:SetAfterValueChanged(function(v) set('maxDisplayed', v) end)
	cy = placeWidget(maxSlider, inner, cy, SLIDER_H)

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildLayoutCard(parent, width)
	local _, card = F.Settings.BuildPositionCard(parent, width, 0, get, set, { noHeading = true })
	return card
end

local function buildDurationFontCard(parent, width)
	local _, card = F.Settings.BuildFontCard(parent, width, 0, 'Duration', 'durationFont', get, set, {
		noHeading = true,
		showToggle = {
			label = 'Show Duration',
			get = function() return get('showDuration') ~= false end,
			set = function(checked) set('showDuration', checked) end,
		},
	})
	return card
end

local function buildGlowCard(parent, width)
	local function getGlow(key)
		if(key == 'glowType')  then return get('glow.type') end
		if(key == 'glowColor') then return get('glow.color') end
		return get('glow.' .. key)
	end
	local function setGlow(key, value)
		if(key == 'glowType')  then set('glow.type', value); return end
		if(key == 'glowColor') then set('glow.color', value); return end
		set('glow.' .. key, value)
	end
	local _, card = F.Settings.BuildGlowCard(parent, width, 0, getGlow, setGlow, { allowNone = false, noHeading = true })
	return card
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id         = 'targetedspells',
	label      = 'Targeted Spells',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 17,
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
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'targetedspells', 'targetedSpells')

		-- ── CardGrid ─────────────────────────────────────────────
		local grid = Widgets.CreateCardGrid(content, width)
		grid:SetTopOffset(math.abs(yOffset))

		-- Conditional cards — added/removed based on display mode
		local ICON_CARDS = { 'iconSettings', 'layout', 'durationFont' }
		local GLOW_CARDS = { 'borderGlow' }

		-- Forward-declare so buildDisplayModeCard can reference it
		local updateVisibility

		updateVisibility = function(mode)
			local showIcons = (mode == 'Icons' or mode == 'Both')
			local showGlow  = (mode == 'BorderGlow' or mode == 'Both')

			for _, id in next, ICON_CARDS do
				if(showIcons and not grid._cardIndex[id]) then
					if(id == 'iconSettings') then
						grid:AddCard('iconSettings', 'Icon Settings', buildIconSettingsCard, {})
					elseif(id == 'layout') then
						grid:AddCard('layout', 'Layout', buildLayoutCard, {})
					elseif(id == 'durationFont') then
						grid:AddCard('durationFont', 'Duration', buildDurationFontCard, {})
					end
				elseif(not showIcons and grid._cardIndex[id]) then
					grid:RemoveCard(id)
				end
			end

			for _, id in next, GLOW_CARDS do
				if(showGlow and not grid._cardIndex[id]) then
					grid:AddCard('borderGlow', 'Border Glow', buildGlowCard, {})
				elseif(not showGlow and grid._cardIndex[id]) then
					grid:RemoveCard(id)
				end
			end

			grid:Layout(grid._lastScrollOffset or 0, grid._lastViewHeight or parentH, true)
			content:SetHeight(grid:GetTotalHeight())
			scroll:UpdateScrollRange()
		end

		grid:AddCard('preview',      'Preview',      F.Settings.AuraPreview.BuildPreviewCard, {})
		grid:AddCard('overview',     'Overview',     buildOverviewCard,     {})
		grid:AddCard('displayMode',  'Display Mode', buildDisplayModeCard,  { updateVisibility })

		-- Add conditional cards based on initial mode
		local initialMode = get('displayMode') or 'Both'
		local initIcons = (initialMode == 'Icons' or initialMode == 'Both')
		local initGlow  = (initialMode == 'BorderGlow' or initialMode == 'Both')

		if(initIcons) then
			grid:AddCard('iconSettings', 'Icon Settings', buildIconSettingsCard, {})
			grid:AddCard('layout',       'Layout',        buildLayoutCard,       {})
			grid:AddCard('durationFont', 'Duration',      buildDurationFontCard, {})
		end
		if(initGlow) then
			grid:AddCard('borderGlow', 'Border Glow', buildGlowCard, {})
		end

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
		local resizeKey = 'TargetedSpells.resize'
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
