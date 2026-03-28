local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}

local SLIDER_H     = B.SLIDER_H
local SWITCH_H     = B.SWITCH_H
local DROPDOWN_H   = B.DROPDOWN_H
local CHECK_H      = B.CHECK_H
local placeWidget  = B.PlaceWidget
local placeHeading = B.PlaceHeading

function F.SettingsCards.ShieldsAndAbsorbs(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local PICKER_ROW_H = 22

	-- ── Heal Prediction ──
	local healPredCheck = Widgets.CreateCheckButton(inner, 'Heal Prediction', function(checked)
		setConfig('health.healPrediction', checked)
	end)
	healPredCheck:SetChecked(getConfig('health.healPrediction') ~= false)
	cardY = placeWidget(healPredCheck, inner, cardY, CHECK_H)

	local healPredPicker = Widgets.CreateColorPicker(inner, 'Color', true,
		nil,
		function(r, g, b, a) setConfig('health.healPredictionColor', { r, g, b, a }) end)
	local savedHealPred = getConfig('health.healPredictionColor') or { 0.6, 0.6, 0.6, 0.4 }
	healPredPicker:SetColor(savedHealPred[1], savedHealPred[2], savedHealPred[3], savedHealPred[4])
	cardY = placeWidget(healPredPicker, inner, cardY, PICKER_ROW_H)

	-- ── Shields (damage absorbs) ──
	local damageAbsorbCheck = Widgets.CreateCheckButton(inner, 'Shields', function(checked)
		setConfig('health.damageAbsorb', checked)
	end)
	damageAbsorbCheck:SetChecked(getConfig('health.damageAbsorb') ~= false)
	cardY = placeWidget(damageAbsorbCheck, inner, cardY, CHECK_H)

	local damageAbsorbPicker = Widgets.CreateColorPicker(inner, 'Color', true,
		nil,
		function(r, g, b, a) setConfig('health.damageAbsorbColor', { r, g, b, a }) end)
	local savedDamageAbsorb = getConfig('health.damageAbsorbColor') or { 1, 1, 1, 0.6 }
	damageAbsorbPicker:SetColor(savedDamageAbsorb[1], savedDamageAbsorb[2], savedDamageAbsorb[3], savedDamageAbsorb[4])
	cardY = placeWidget(damageAbsorbPicker, inner, cardY, PICKER_ROW_H)

	-- ── Heal Absorbs ──
	local healAbsorbCheck = Widgets.CreateCheckButton(inner, 'Heal Absorbs', function(checked)
		setConfig('health.healAbsorb', checked)
	end)
	healAbsorbCheck:SetChecked(getConfig('health.healAbsorb') ~= false)
	cardY = placeWidget(healAbsorbCheck, inner, cardY, CHECK_H)

	local healAbsorbPicker = Widgets.CreateColorPicker(inner, 'Color', true,
		nil,
		function(r, g, b, a) setConfig('health.healAbsorbColor', { r, g, b, a }) end)
	local savedHealAbsorb = getConfig('health.healAbsorbColor') or { 0.7, 0.1, 0.1, 0.5 }
	healAbsorbPicker:SetColor(savedHealAbsorb[1], savedHealAbsorb[2], savedHealAbsorb[3], savedHealAbsorb[4])
	cardY = placeWidget(healAbsorbPicker, inner, cardY, PICKER_ROW_H)

	-- ── Overshield ──
	local overAbsorbCheck = Widgets.CreateCheckButton(inner, 'Overshield', function(checked)
		setConfig('health.overAbsorb', checked)
	end)
	overAbsorbCheck:SetChecked(getConfig('health.overAbsorb') ~= false)
	cardY = placeWidget(overAbsorbCheck, inner, cardY, CHECK_H)

	Widgets.EndCard(card, parent, cardY)
	card:ClearAllPoints()
	card._startY = 0
	return card
end
