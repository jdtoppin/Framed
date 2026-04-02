local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Widget constants
-- ============================================================

local SLIDER_H = 26
local CHECK_H  = 22
local WIDGET_W = 220

-- ============================================================
-- Config helpers
-- ============================================================

local function get(key)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.privateAuras.' .. key)
end

local function set(key, value)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.privateAuras.' .. key, value)
	end
	if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.privateAuras')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'privateauras',
	label   = 'Private Auras',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 18,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'privateauras', 'privateAuras')

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
		descFS:SetWordWrap(true)
		descFS:SetText('Private auras are Blizzard-controlled aura anchors. Their spells are defined by the game, but you can configure their size and position on unit frames.')
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.tight

		-- Reload notice
		local reloadInfo = Widgets.CreateInfoIcon(content,
			'Requires /reload',
			'Private Auras are registered at the C-level API. Changes to icon size and anchor require a /reload to take effect.')
		reloadInfo:ClearAllPoints()
		Widgets.SetPoint(reloadInfo, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - reloadInfo:GetHeight() - C.Spacing.normal

		-- ── Display section ────────────────────────────────────
		local displayHeading, displayHeadingH = Widgets.CreateHeading(content, 'Display Settings', 2)
		displayHeading:ClearAllPoints()
		Widgets.SetPoint(displayHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - displayHeadingH

		local displayCard, displayInner, displayCardY
		displayCard, displayInner, displayCardY = Widgets.StartCard(content, width, yOffset)

		local sizeSlider = Widgets.CreateSlider(displayInner, 'Icon Size', WIDGET_W, 8, 48, 1)
		sizeSlider:SetValue(get('iconSize') or 20)
		sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
		sizeSlider:ClearAllPoints()
		Widgets.SetPoint(sizeSlider, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
		displayCardY = displayCardY - SLIDER_H - C.Spacing.normal

		local maxSlider = Widgets.CreateSlider(displayInner, 'Max Displayed', WIDGET_W, 1, 5, 1)
		maxSlider:SetValue(get('maxDisplayed') or 3)
		maxSlider:SetAfterValueChanged(function(v) set('maxDisplayed', v) end)
		maxSlider:ClearAllPoints()
		Widgets.SetPoint(maxSlider, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
		displayCardY = displayCardY - SLIDER_H - C.Spacing.normal

		local oriDD = Widgets.CreateDropdown(displayInner, WIDGET_W)
		oriDD:SetItems({
			{ text = 'Right',             value = 'RIGHT' },
			{ text = 'Left',              value = 'LEFT' },
			{ text = 'Up',                value = 'UP' },
			{ text = 'Down',              value = 'DOWN' },
			{ text = 'Center Horizontal', value = 'CENTER_HORIZONTAL' },
			{ text = 'Center Vertical',   value = 'CENTER_VERTICAL' },
		})
		oriDD:SetValue(get('orientation') or 'RIGHT')
		oriDD:SetOnSelect(function(v) set('orientation', v) end)
		oriDD:ClearAllPoints()
		Widgets.SetPoint(oriDD, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
		displayCardY = displayCardY - 22 - C.Spacing.normal

		yOffset = Widgets.EndCard(displayCard, content, displayCardY)

		-- ── Position section (shared builder) ──────────────────
		yOffset = F.Settings.BuildPositionCard(content, width, yOffset, get, set, {
			hideFrameLevel = true,
		})

		-- ── Final height ────────────────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
