local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================
local SLIDER_H   = 26
local DROPDOWN_H = 22
local CHECK_H    = 22

-- ============================================================
-- Config helpers
-- ============================================================

local function makeHelpers(unitType)
	local function get(key)
		local presetName = F.Settings.GetEditingPreset()
		return F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.missingBuffs.' .. key)
	end

	local function set(key, value)
		local presetName = F.Settings.GetEditingPreset()
		if(F.Config) then
			F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.missingBuffs.' .. key, value)
		end
		if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
		if(key ~= 'enabled' and F.EventBus) then
			F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.missingBuffs')
		end
		F.Settings.UpdateAuraPreviewDimming('missingBuffs', nil)
	end

	return get, set
end

-- ============================================================
-- Card builders
-- ============================================================

local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

local function buildOverviewCard(parent, width, get, set)
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
	descFS:SetText('Shows glowing spell icons for missing raid buffs (Fortitude, Intellect, Battle Shout, Mark of the Wild, Skyfury, Blessing of the Bronze). Icons only appear when the providing class is in your group.')
	cy = placeWidget(descFS, inner, cy, descFS:GetStringHeight() + C.Spacing.tight)

	-- Reload notice
	local reloadInfo = Widgets.CreateInfoIcon(inner,
		'Requires /reload',
		'Missing Buffs icons are created at frame setup time. Changes to icon size, position, and other settings require a /reload to take effect.')
	cy = placeWidget(reloadInfo, inner, cy, reloadInfo:GetHeight())

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildDisplayCard(parent, width, get, set)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- Icon Size
	local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', widgetW, 8, 32, 1)
	sizeSlider:SetValue(get('iconSize') or 12)
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	cy = placeWidget(sizeSlider, inner, cy, SLIDER_H)

	-- Growth Direction
	local growDD = Widgets.CreateDropdown(inner, widgetW)
	growDD:SetItems({
		{ text = 'Right', value = 'RIGHT' },
		{ text = 'Left',  value = 'LEFT' },
		{ text = 'Up',    value = 'UP' },
		{ text = 'Down',  value = 'DOWN' },
	})
	growDD:SetValue(get('growDirection') or 'LEFT')
	growDD:SetOnSelect(function(v) set('growDirection', v) end)
	cy = placeWidget(growDD, inner, cy, DROPDOWN_H)

	Widgets.EndCard(card, parent, cy)
	return card
end

local function buildPositionCard(parent, width, get, set)
	local _, card = F.Settings.BuildPositionCard(parent, width, 0, get, set, { noHeading = true })
	return card
end

local function buildGlowCard(parent, width, get, set)
	local _, card = F.Settings.BuildGlowCard(parent, width, 0, get, set, { allowNone = false, noHeading = true })
	return card
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id         = 'missingbuffs',
	label      = 'Missing Buffs',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 19,
	create     = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll  = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		local unitType = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
		local get, set = makeHelpers(unitType)

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'missingbuffs', 'missingBuffs')

		-- CardGrid
		local grid = Widgets.CreateCardGrid(content, width)
		grid:SetTopOffset(math.abs(yOffset))

		grid:AddCard('preview',  'Preview',          F.Settings.AuraPreview.BuildPreviewCard, {})
		grid:SetSticky('preview')
		grid:AddCard('overview', 'Overview',         buildOverviewCard, { get, set })
		grid:AddCard('display',  'Display Settings', buildDisplayCard,  { get, set })
		grid:AddCard('layout',   'Layout',           buildPositionCard, { get, set })
		grid:AddCard('glow',     'Border Glow',      buildGlowCard,     { get, set })

		grid:Layout(0, parentH)
		content:SetHeight(grid:GetTotalHeight())
		scroll:UpdateScrollRange()

		-- Scroll integration
		local function onScroll()
			local offset = scroll._scrollFrame:GetVerticalScroll()
			local viewH  = scroll._scrollFrame:GetHeight()
			grid:Layout(offset, viewH)
			content:SetHeight(grid:GetTotalHeight())
		end

		scroll._scrollFrame:HookScript('OnMouseWheel', function()
			C_Timer.After(0, onScroll)
		end)

		-- Resize handling
		local resizeKey = 'MissingBuffs.resize.' .. unitType
		local function onResize(newW)
			local newWidth = newW - C.Spacing.normal * 2
			grid:SetWidth(newWidth)
			content:SetHeight(grid:GetTotalHeight())
		end

		F.EventBus:Register('SETTINGS_RESIZED', onResize, resizeKey)
		F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', function()
			grid:RebuildCards()
		end, resizeKey .. '.complete')

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
