local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Widget constants
-- ============================================================

local SLIDER_H     = 26
local WIDGET_W     = 220

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
	order      = 17,
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
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'privateauras')

		-- ── Description ────────────────────────────────────────
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetWordWrap(true)
		descFS:SetText('Private auras are Blizzard-controlled aura anchors. Their spells are defined by the game, but you can configure their size and position on unit frames.')
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- ── Display section ────────────────────────────────────
		local displayHeading, displayHeadingH = Widgets.CreateHeading(content, 'Icon Size', 2)
		displayHeading:ClearAllPoints()
		Widgets.SetPoint(displayHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - displayHeadingH

		local sizeCard, sizeInner, sizeCardY
		sizeCard, sizeInner, sizeCardY = Widgets.StartCard(content, width, yOffset)

		-- Icon Size
		local sizeSlider = Widgets.CreateSlider(sizeInner, 'Icon Size', WIDGET_W, 8, 48, 1)
		sizeSlider:SetValue(get('iconSize') or 20)
		sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
		sizeSlider:ClearAllPoints()
		Widgets.SetPoint(sizeSlider, 'TOPLEFT', sizeInner, 'TOPLEFT', 0, sizeCardY)
		sizeCardY = sizeCardY - SLIDER_H - C.Spacing.normal

		yOffset = Widgets.EndCard(sizeCard, content, sizeCardY)

		-- ── Position section ───────────────────────────────────
		local posHeading, posHeadingH = Widgets.CreateHeading(content, 'Icon Position', 2)
		posHeading:ClearAllPoints()
		Widgets.SetPoint(posHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - posHeadingH

		local posCard, posInner, posCardY
		posCard, posInner, posCardY = Widgets.StartCard(content, width, yOffset)

		-- Anchor picker
		if(Widgets.CreateAnchorPicker) then
			local anchor = get('anchor') or { 'TOPRIGHT', nil, 'TOPRIGHT', -2, -2 }
			local picker = Widgets.CreateAnchorPicker(posInner, width)
			picker:SetAnchor(anchor[1], anchor[4] or -2, anchor[5] or -2)
			picker:ClearAllPoints()
			Widgets.SetPoint(picker, 'TOPLEFT', posInner, 'TOPLEFT', 0, posCardY)
			picker:SetOnChanged(function(point, x, y)
				set('anchor', { point, nil, point, x, y })
			end)
			posCardY = posCardY - picker:GetHeight() - C.Spacing.normal
		end

		yOffset = Widgets.EndCard(posCard, content, posCardY)

		-- ── Final height ────────────────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
