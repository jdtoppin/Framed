local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================

local PANE_TITLE_H = 20
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

local function createSection(content, title, width, yOffset)
	local pane = Widgets.CreateTitledPane(content, title, width)
	pane:ClearAllPoints()
	Widgets.SetPoint(pane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return pane, yOffset - PANE_TITLE_H - C.Spacing.normal
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
	return F.Config and F.Config:Get('auras.lossOfControl.' .. key)
end
local function setLoC(key, value)
	if(F.Config) then
		F.Config:Set('auras.lossOfControl.' .. key, value)
	end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED:auras')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'lossofcontrol',
	label   = 'Loss of Control',
	section = 'AURAS',
	order   = 20,
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

		-- ── CC Type Toggles ────────────────────────────────────
		local typePane
		typePane, yOffset = createSection(content, 'CC Types', width, yOffset)

		for _, cc in next, CC_TYPES do
			local check = Widgets.CreateCheckButton(content, cc.label, function(checked)
				setLoC('types.' .. cc.id, checked)
			end)
			yOffset = placeWidget(check, content, yOffset, CHECK_H)

			local savedEnabled = getLoC('types.' .. cc.id)
			if(savedEnabled ~= nil) then
				check:SetChecked(savedEnabled)
			else
				check:SetChecked(true)   -- default enabled
			end
		end

		-- ── Visual Settings ────────────────────────────────────
		local visPane
		visPane, yOffset = createSection(content, 'Visual', width, yOffset)

		-- Overlay alpha
		local alphaSlider = Widgets.CreateSlider(content, 'Overlay Alpha', WIDGET_W, 0.0, 1.0, 0.05)
		yOffset = placeWidget(alphaSlider, content, yOffset, SLIDER_H)
		local savedAlpha = getLoC('overlayAlpha')
		alphaSlider:SetValue(savedAlpha or 0.6)
		alphaSlider:SetAfterValueChanged(function(value)
			setLoC('overlayAlpha', value)
		end)

		-- Icon size
		local sizeSlider = Widgets.CreateSlider(content, 'Icon Size', WIDGET_W, 12, 64, 1)
		yOffset = placeWidget(sizeSlider, content, yOffset, SLIDER_H)
		local savedSize = getLoC('iconSize')
		sizeSlider:SetValue(savedSize or 32)
		sizeSlider:SetAfterValueChanged(function(value)
			setLoC('iconSize', value)
		end)

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
