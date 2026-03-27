local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Widget constants
-- ============================================================

local SLIDER_H     = 26
local DROPDOWN_H   = 22
local WIDGET_W     = 220

-- ============================================================
-- Config helpers
-- ============================================================

local function get(key)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.missingBuffs.' .. key)
end

local function set(key, value)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.missingBuffs.' .. key, value)
	end
	if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.missingBuffs')
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
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'missingbuffs', 'missingBuffs')

		-- ── Description ────────────────────────────────────────
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('Shows glowing spell icons for missing raid buffs (Fortitude, Intellect, Battle Shout, Mark of the Wild, Skyfury, Blessing of the Bronze). Icons only appear when the providing class is in your group.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.tight

		-- Reload notice
		local reloadInfo = Widgets.CreateInfoIcon(content,
			'Requires /reload',
			'Missing Buffs icons are created at frame setup time. Changes to icon size, position, and other settings require a /reload to take effect.')
		reloadInfo:ClearAllPoints()
		Widgets.SetPoint(reloadInfo, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - reloadInfo:GetHeight() - C.Spacing.normal

		-- ── Icon Settings ─────────────────────────────────────
		local iconHeading, iconHeadingH = Widgets.CreateHeading(content, 'Icon Settings', 2)
		iconHeading:ClearAllPoints()
		Widgets.SetPoint(iconHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - iconHeadingH

		local card, inner, cardY
		card, inner, cardY = Widgets.StartCard(content, width, yOffset)

		-- Icon Size
		local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', WIDGET_W, 8, 32, 1)
		sizeSlider:SetValue(get('iconSize') or 12)
		sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
		sizeSlider:ClearAllPoints()
		Widgets.SetPoint(sizeSlider, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
		cardY = cardY - SLIDER_H - C.Spacing.normal

		-- Frame Level
		local levelSlider = Widgets.CreateSlider(inner, 'Frame Level', WIDGET_W, 1, 10, 1)
		levelSlider:SetValue(get('frameLevel') or 5)
		levelSlider:SetAfterValueChanged(function(v) set('frameLevel', v) end)
		levelSlider:ClearAllPoints()
		Widgets.SetPoint(levelSlider, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
		cardY = cardY - SLIDER_H - C.Spacing.normal

		-- Anchor Point
		local anchorPoints = {
			{ text = 'Top Left',     value = 'TOPLEFT' },
			{ text = 'Top Right',    value = 'TOPRIGHT' },
			{ text = 'Bottom Left',  value = 'BOTTOMLEFT' },
			{ text = 'Bottom Right', value = 'BOTTOMRIGHT' },
			{ text = 'Center',       value = 'CENTER' },
		}
		local anchorDD = Widgets.CreateDropdown(inner, WIDGET_W)
		anchorDD:SetItems(anchorPoints)
		local currentAnchor = get('anchor')
		anchorDD:SetValue(currentAnchor and currentAnchor[1] or 'BOTTOMRIGHT')
		anchorDD:SetOnSelect(function(v)
			local a = get('anchor') or { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 2 }
			set('anchor', { v, nil, v, a[4] or 0, a[5] or 0 })
		end)
		anchorDD:ClearAllPoints()
		Widgets.SetPoint(anchorDD, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
		cardY = cardY - DROPDOWN_H - C.Spacing.normal

		-- Anchor X Offset
		local currentAnchorX = (function()
			local a = get('anchor')
			return a and a[4] or -2
		end)()
		local xSlider = Widgets.CreateSlider(inner, 'X Offset', WIDGET_W, -20, 20, 1)
		xSlider:SetValue(currentAnchorX)
		xSlider:SetAfterValueChanged(function(v)
			local a = get('anchor') or { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 2 }
			set('anchor', { a[1], nil, a[3], v, a[5] })
		end)
		xSlider:ClearAllPoints()
		Widgets.SetPoint(xSlider, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
		cardY = cardY - SLIDER_H - C.Spacing.normal

		-- Anchor Y Offset
		local currentAnchorY = (function()
			local a = get('anchor')
			return a and a[5] or 2
		end)()
		local ySlider = Widgets.CreateSlider(inner, 'Y Offset', WIDGET_W, -20, 20, 1)
		ySlider:SetValue(currentAnchorY)
		ySlider:SetAfterValueChanged(function(v)
			local a = get('anchor') or { 'BOTTOMRIGHT', nil, 'BOTTOMRIGHT', -2, 2 }
			set('anchor', { a[1], nil, a[3], a[4], v })
		end)
		ySlider:ClearAllPoints()
		Widgets.SetPoint(ySlider, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
		cardY = cardY - SLIDER_H - C.Spacing.normal

		yOffset = Widgets.EndCard(card, content, cardY)

		-- ── Final height ────────────────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
