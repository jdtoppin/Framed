local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Widget constants
-- ============================================================

local SLIDER_H   = 26
local CHECK_H    = 22
local DROPDOWN_H = 22
local WIDGET_W   = 220

-- ============================================================
-- Config helpers
-- ============================================================

local function get(key)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.dispellable.' .. key)
end

local function set(key, value)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.dispellable.' .. key, value)
	end
	if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
	-- Config:Set already fires CONFIG_CHANGED with the full path;
	-- fire broad event only for non-enabled keys to avoid double-handling
	if(key ~= 'enabled' and F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.dispellable')
	end
end

-- ============================================================
-- Layout helper
-- ============================================================

local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

-- ============================================================
-- Card builders
-- Each follows CardGrid builder signature:
--   function(parent, width, get, set)
-- ============================================================

local function buildOverviewCard(parent, width, get, set)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	-- Description
	local descFS = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textSecondary)
	descFS:SetWidth(width - Widgets.CARD_PADDING * 2)
	descFS:SetText('Highlight units that have dispellable debuffs. Shows an icon and a colored frame highlight.')
	descFS:SetWordWrap(true)
	cy = placeWidget(descFS, inner, cy, descFS:GetStringHeight())

	-- Enabled toggle
	local enableCheck = Widgets.CreateCheckButton(inner, 'Enabled', function(checked)
		set('enabled', checked)
	end)
	enableCheck:SetChecked(get('enabled'))
	cy = placeWidget(enableCheck, inner, cy, CHECK_H)

	-- Only show dispellable by me
	local dispCheck = Widgets.CreateCheckButton(inner, 'Only dispellable by me', function(checked)
		set('onlyDispellableByMe', checked)
	end)
	dispCheck:SetChecked(get('onlyDispellableByMe') == true)
	cy = placeWidget(dispCheck, inner, cy, CHECK_H)

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildHighlightCard(parent, width, get, set)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	local ht = C.HighlightType
	local highlightDD = Widgets.CreateDropdown(inner, WIDGET_W)
	highlightDD:SetItems({
		{ text = 'Gradient - Health Bar (Full)', value = ht.GRADIENT_FULL },
		{ text = 'Gradient - Health Bar (Half)', value = ht.GRADIENT_HALF },
		{ text = 'Solid - Health Bar (Current)', value = ht.SOLID_CURRENT },
		{ text = 'Solid - Entire Frame',          value = ht.SOLID_ENTIRE },
	})
	highlightDD:SetValue(get('highlightType') or ht.GRADIENT_FULL)
	highlightDD:SetOnSelect(function(v) set('highlightType', v) end)
	cy = placeWidget(highlightDD, inner, cy, DROPDOWN_H)

	-- Highlight Alpha (new setting — stored as 0-1, displayed as 0-100)
	local alphaSlider = Widgets.CreateSlider(inner, 'Highlight Alpha', WIDGET_W, 0, 100, 1)
	alphaSlider:SetValue((get('highlightAlpha') or 0.8) * 100)
	alphaSlider:SetAfterValueChanged(function(v) set('highlightAlpha', v / 100) end)
	cy = placeWidget(alphaSlider, inner, cy, SLIDER_H)

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildIconCard(parent, width, get, set)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	-- Icon Size
	local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', WIDGET_W, 8, 48, 1)
	sizeSlider:SetValue(get('iconSize') or 20)
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	cy = placeWidget(sizeSlider, inner, cy, SLIDER_H)

	-- Frame Level
	local lvlSlider = Widgets.CreateSlider(inner, 'Frame Level', WIDGET_W, 1, 20, 1)
	lvlSlider:SetValue(get('frameLevel') or 5)
	lvlSlider:SetAfterValueChanged(function(v) set('frameLevel', v) end)
	cy = placeWidget(lvlSlider, inner, cy, SLIDER_H)

	-- Anchor picker
	if(Widgets.CreateAnchorPicker) then
		local anchorData = get('anchor') or { 'TOPRIGHT', nil, 'TOPRIGHT', -2, -2 }
		local picker = Widgets.CreateAnchorPicker(inner, WIDGET_W)
		picker:SetAnchor(anchorData[1], anchorData[4] or -2, anchorData[5] or -2)
		picker:SetOnChanged(function(point, x, y)
			set('anchor', { point, nil, point, x, y })
		end)
		cy = placeWidget(picker, inner, cy, picker:GetHeight())
	end

	Widgets.EndCard(card, parent, cy)
	return card
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id         = 'dispels',
	label      = 'Dispels',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 13,
	create     = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll  = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ── Unit type dropdown + copy-to ─────────────────────────
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'dispels', 'dispellable')

		-- ── CardGrid ─────────────────────────────────────────────
		local grid = Widgets.CreateCardGrid(content, width)
		grid:SetTopOffset(math.abs(yOffset))

		grid:AddCard('overview',  'Overview',  buildOverviewCard,  { get, set })
		grid:AddCard('highlight', 'Highlight', buildHighlightCard, { get, set })
		grid:AddCard('icon',      'Icon',      buildIconCard,      { get, set })

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
		local resizeKey = 'Dispels.resize'
		local function onResize(newW, newH)
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

		return scroll
	end,
})
