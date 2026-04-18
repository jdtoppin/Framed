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
-- CC type definitions
-- ============================================================

local CC_TYPES = {
	{ id = 'stun',        label = 'Stun' },
	{ id = 'silence',     label = 'Silence' },
	{ id = 'fear',        label = 'Fear' },
	{ id = 'root',        label = 'Root' },
	{ id = 'mindControl', label = 'Mind Control' },
}

-- ============================================================
-- Config helpers
-- ============================================================

local function get(key)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.lossOfControl.' .. key)
end

local function set(key, value)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.lossOfControl.' .. key, value)
	end
	if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
	if(key ~= 'enabled' and F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.lossOfControl')
	end
	F.Settings.UpdateAuraPreviewDimming('lossOfControl', nil)
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
	descFS:SetText('Display an overlay icon when a unit is affected by a loss of control effect such as stun, fear, or silence.')
	cy = placeWidget(descFS, inner, cy, descFS:GetStringHeight())

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildCCTypesCard(parent, width)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	for _, cc in next, CC_TYPES do
		local check = Widgets.CreateCheckButton(inner, cc.label, function(checked)
			set('types.' .. cc.id, checked)
		end)
		local savedEnabled = get('types.' .. cc.id)
		if(savedEnabled ~= nil) then
			check:SetChecked(savedEnabled)
		else
			check:SetChecked(true)
		end
		cy = placeWidget(check, inner, cy, CHECK_H)
	end

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildVisualSettingsCard(parent, width)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local alphaSlider = Widgets.CreateSlider(inner, 'Overlay Alpha', widgetW, 0.0, 1.0, 0.05)
	alphaSlider:SetValue(get('overlayAlpha'))
	alphaSlider:SetAfterValueChanged(function(v) set('overlayAlpha', v) end)
	cy = placeWidget(alphaSlider, inner, cy, SLIDER_H)

	local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', widgetW, 12, 64, 1)
	sizeSlider:SetValue(get('iconSize'))
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	cy = placeWidget(sizeSlider, inner, cy, SLIDER_H)

	Widgets.EndCard(card, parent, cy)
	return card
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id         = 'lossofcontrol',
	label      = 'Loss of Control',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 20,
	create     = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll  = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'lossofcontrol')

		-- ── CardGrid ─────────────────────────────────────────────
		local grid = Widgets.CreateCardGrid(content, width)
		grid:SetTopOffset(math.abs(yOffset))

		grid:AddCard('preview',        'Preview',         F.Settings.AuraPreview.BuildPreviewCard, {})
		grid:SetSticky('preview')
		grid:AddCard('overview',       'Overview',        buildOverviewCard,       {})
		grid:AddCard('ccTypes',        'CC Types',        buildCCTypesCard,        {})
		grid:AddCard('visualSettings', 'Visual Settings', buildVisualSettingsCard, {})

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
		local resizeKey = 'LossOfControl.resize'
		local function onResize(newW)
			local newWidth = newW - C.Spacing.normal * 2
			grid:SetWidth(newWidth)
			content:SetHeight(grid:GetTotalHeight())
		end

		F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)
		F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', function()
			grid:RebuildCards()
		end, resizeKey .. '.complete')

		-- ── Cleanup on hide, re-register on show ──────────────────
		scroll:HookScript('OnHide', function()
			grid:CancelAnimations()
			F.EventBus:Unregister('SETTINGS_RESIZED', resizeKey)
			F.EventBus:Unregister('SETTINGS_RESIZE_COMPLETE', resizeKey .. '.complete')
		end)

		scroll:HookScript('OnShow', function()
			F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)
			F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', function()
				grid:RebuildCards()
				if(F.Settings._auraPreview) then
					F.Settings.AuraPreview.Rebuild()
				end
			end, resizeKey .. '.complete')
			-- Catch up with any resize that happened while hidden
			local curW = parent._explicitWidth  or parent:GetWidth()  or parentW
			local curH = parent._explicitHeight or parent:GetHeight() or parentH
			onResize(curW, curH)
			grid:RebuildCards()
			if(F.Settings._auraPreview) then
				F.Settings.AuraPreview.Rebuild()
			end
		end)

		scroll._ownedPreview = F.Settings._auraPreview
		return scroll
	end,
})
