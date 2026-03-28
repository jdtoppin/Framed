local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local SWATCH_H     = 20

function F.AppearanceCards.AccentColor(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local colorPicker = Widgets.CreateColorPicker(inner)
	colorPicker:ClearAllPoints()
	Widgets.SetPoint(colorPicker, 'TOPLEFT', inner, 'TOPLEFT', 0, cardY)

	local savedColor = getConfig('accentColor')
	if(savedColor) then
		colorPicker:SetColor(savedColor[1], savedColor[2], savedColor[3], savedColor[4] or 1)
	else
		colorPicker:SetColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
	end

	colorPicker:SetOnColorChanged(function(r, g, b, a)
		C.Colors.accent      = { r, g, b, a }
		C.Colors.accentDim   = { r, g, b, 0.3 }
		C.Colors.accentHover = { r, g, b, 0.6 }
		setConfig('accentColor', { r, g, b, a })
		fireChange()
	end)

	cardY = cardY - SWATCH_H - C.Spacing.normal

	Widgets.EndCard(card, parent, cardY)
	return card
end
