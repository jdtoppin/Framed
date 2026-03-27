local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================

local SLIDER_H     = 26
local CHECK_H      = 14
local WIDGET_W     = 220

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
-- Helpers
-- ============================================================

local function placeHeading(content, text, level, yOffset)
	local heading, height = Widgets.CreateHeading(content, text, level)
	heading:ClearAllPoints()
	Widgets.SetPoint(heading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height
end

local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

-- ============================================================
-- Config helpers
-- ============================================================

local function getLoC(key)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.lossOfControl.' .. key)
end
local function setLoC(key, value)
	local presetName = F.Settings.GetEditingPreset()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.lossOfControl.' .. key, value)
	end
	if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.lossOfControl')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'lossofcontrol',
	label   = 'Loss of Control',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 20,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(
			parent, nil,
			parentW,
			parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'lossofcontrol')

		-- ── CC Type Toggles ────────────────────────────────────
		yOffset = placeHeading(content, 'CC Type Toggles', 2, yOffset)

		local ccCard, ccInner, ccCardY
		ccCard, ccInner, ccCardY = Widgets.StartCard(content, width, yOffset)

		for _, cc in next, CC_TYPES do
			local check = Widgets.CreateCheckButton(ccInner, cc.label, function(checked)
				setLoC('types.' .. cc.id, checked)
			end)
			ccCardY = placeWidget(check, ccInner, ccCardY, CHECK_H)

			local savedEnabled = getLoC('types.' .. cc.id)
			if(savedEnabled ~= nil) then
				check:SetChecked(savedEnabled)
			else
				check:SetChecked(true)   -- default enabled
			end
		end

		yOffset = Widgets.EndCard(ccCard, content, ccCardY)

		-- ── Visual Settings ────────────────────────────────────
		yOffset = placeHeading(content, 'Visual Settings', 2, yOffset)

		local visCard, visInner, visCardY
		visCard, visInner, visCardY = Widgets.StartCard(content, width, yOffset)

		-- Overlay alpha
		local alphaSlider = Widgets.CreateSlider(visInner, 'Overlay Alpha', WIDGET_W, 0.0, 1.0, 0.05)
		visCardY = placeWidget(alphaSlider, visInner, visCardY, SLIDER_H)
		local savedAlpha = getLoC('overlayAlpha')
		alphaSlider:SetValue(savedAlpha or 0.6)
		alphaSlider:SetAfterValueChanged(function(value)
			setLoC('overlayAlpha', value)
		end)

		-- Icon size
		local sizeSlider = Widgets.CreateSlider(visInner, 'Icon Size', WIDGET_W, 12, 64, 1)
		visCardY = placeWidget(sizeSlider, visInner, visCardY, SLIDER_H)
		local savedSize = getLoC('iconSize')
		sizeSlider:SetValue(savedSize or 32)
		sizeSlider:SetAfterValueChanged(function(value)
			setLoC('iconSize', value)
		end)

		yOffset = Widgets.EndCard(visCard, content, visCardY)

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
