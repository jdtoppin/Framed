local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local PICKER_ROW_H = 22

function F.AppearanceCards.Theme(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- ── Accent Color ────────────────────────────────────────
	cardY = B.PlaceHeading(inner, 'Accent Color', 4, cardY)

	local colorPicker = Widgets.CreateColorPicker(inner, 'Accent', false,
		nil,
		function(r, g, b, a)
			C.Colors.accent      = { r, g, b, a }
			C.Colors.accentDim   = { r, g, b, 0.3 }
			C.Colors.accentHover = { r, g, b, 0.6 }
			setConfig('accentColor', { r, g, b, a })
			fireChange()
		end)

	local savedColor = getConfig('accentColor')
	if(savedColor) then
		colorPicker:SetColor(savedColor[1], savedColor[2], savedColor[3], savedColor[4])
	else
		colorPicker:SetColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
	end
	cardY = B.PlaceWidget(colorPicker, inner, cardY, PICKER_ROW_H)

	-- ── Bar Texture ─────────────────────────────────────────
	cardY = B.PlaceHeading(inner, 'Bar Texture', 4, cardY)

	local barDropdown = Widgets.CreateTextureDropdown(inner, widgetW, 'statusbar')
	barDropdown:SetValue(getConfig('barTexture') or 'Framed')
	barDropdown:SetOnSelect(function(texturePath, name)
		setConfig('barTexture', name)
		fireChange()
	end)
	cardY = B.PlaceWidget(barDropdown, inner, cardY, B.DROPDOWN_H)

	-- ── Font ────────────────────────────────────────────────
	cardY = B.PlaceHeading(inner, 'Font', 4, cardY)

	local fontDropdown = Widgets.CreateTextureDropdown(inner, widgetW, 'font')
	fontDropdown:SetValue(getConfig('font') or 'Expressway')
	fontDropdown:SetOnSelect(function(texturePath, name)
		setConfig('font', name)
		fireChange()
	end)
	cardY = B.PlaceWidget(fontDropdown, inner, cardY, B.DROPDOWN_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
