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
	order      = 19,
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

		-- ── Enabled toggle ────────────────────────────────────
		local enableCB = Widgets.CreateCheckButton(content, 'Enabled', function(checked)
			set('enabled', checked)
		end)
		enableCB:SetChecked(get('enabled') or false)
		enableCB:ClearAllPoints()
		Widgets.SetPoint(enableCB, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - CHECK_H - C.Spacing.normal

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

		-- ── Display Settings ──────────────────────────────────
		local displayHeading, displayHeadingH = Widgets.CreateHeading(content, 'Display Settings', 2)
		displayHeading:ClearAllPoints()
		Widgets.SetPoint(displayHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - displayHeadingH

		local card, inner, cardY
		card, inner, cardY = Widgets.StartCard(content, width, yOffset)

		-- Icon Size
		local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', WIDGET_W, 8, 32, 1)
		sizeSlider:SetValue(get('iconSize') or 12)
		sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
		sizeSlider:ClearAllPoints()
		Widgets.SetPoint(sizeSlider, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
		cardY = cardY - SLIDER_H - C.Spacing.normal

		-- Growth Direction
		local growDD = Widgets.CreateDropdown(inner, WIDGET_W)
		growDD:SetItems({
			{ text = 'Right', value = 'RIGHT' },
			{ text = 'Left',  value = 'LEFT' },
			{ text = 'Up',    value = 'UP' },
			{ text = 'Down',  value = 'DOWN' },
		})
		growDD:SetValue(get('growDirection') or 'LEFT')
		growDD:SetOnSelect(function(v) set('growDirection', v) end)
		growDD:ClearAllPoints()
		Widgets.SetPoint(growDD, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)
		cardY = cardY - DROPDOWN_H - C.Spacing.normal

		yOffset = Widgets.EndCard(card, content, cardY)

		-- ── Position & Layer (shared builder) ──────────────────
		yOffset = F.Settings.BuildPositionCard(content, width, yOffset, get, set)

		-- ── Glow Settings ─────────────────────────────────────
		local function getGlow(key)
			if(key == 'glowType') then return get('glowType') end
			if(key == 'glowColor') then return get('glowColor') end
			return get(key)
		end
		local function setGlow(key, value)
			if(key == 'glowType') then set('glowType', value); return end
			if(key == 'glowColor') then set('glowColor', value); return end
			set(key, value)
		end

		yOffset = F.Settings.BuildGlowCard(content, width, yOffset, getGlow, setGlow, { allowNone = false })

		-- ── Final height ────────────────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
