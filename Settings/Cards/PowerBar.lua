local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}


-- Per-power-type color overrides (filtered by relevance)
local ALL_POWER_TYPES = {
	{ token = 'MANA',         label = 'Mana',         default = { 0.00, 0.44, 0.87 } },
	{ token = 'RAGE',         label = 'Rage',         default = { 1.00, 0.00, 0.00 } },
	{ token = 'ENERGY',       label = 'Energy',       default = { 1.00, 1.00, 0.00 } },
	{ token = 'FOCUS',        label = 'Focus',        default = { 1.00, 0.50, 0.25 } },
	{ token = 'RUNIC_POWER',  label = 'Runic Power',  default = { 0.00, 0.82, 1.00 } },
	{ token = 'INSANITY',     label = 'Insanity',     default = { 0.40, 0.00, 0.80 } },
	{ token = 'FURY',         label = 'Fury',         default = { 0.79, 0.26, 0.99 } },
	{ token = 'MAELSTROM',    label = 'Maelstrom',    default = { 0.00, 0.50, 1.00 } },
	{ token = 'LUNAR_POWER',  label = 'Lunar Power',  default = { 0.30, 0.52, 0.90 } },
}

-- Class -> power types shown on the player frame
local CLASS_POWER_TYPES = {
	WARRIOR     = { RAGE = true },
	PALADIN     = { MANA = true },
	HUNTER      = { FOCUS = true },
	ROGUE       = { ENERGY = true },
	PRIEST      = { MANA = true, INSANITY = true },
	DEATHKNIGHT = { RUNIC_POWER = true },
	SHAMAN      = { MANA = true, MAELSTROM = true },
	MAGE        = { MANA = true },
	WARLOCK     = { MANA = true },
	MONK        = { MANA = true, ENERGY = true },
	DRUID       = { MANA = true, RAGE = true, ENERGY = true, LUNAR_POWER = true },
	DEMONHUNTER = { FURY = true },
	EVOKER      = { MANA = true },
}

function F.SettingsCards.PowerBar(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local showPowerCheck = Widgets.CreateCheckButton(inner, 'Show Power Bar', function(checked)
		setConfig('showPower', checked)
	end)
	showPowerCheck:SetChecked(getConfig('showPower') ~= false)
	cardY = B.PlaceWidget(showPowerCheck, inner, cardY, B.CHECK_H)

	-- Power bar position (top/bottom of health bar)
	cardY = B.PlaceHeading(inner, 'Position', 4, cardY)
	local powerPosSwitch = Widgets.CreateSwitch(inner, widgetW, B.SWITCH_H, {
		{ text = 'Top',    value = 'top' },
		{ text = 'Bottom', value = 'bottom' },
	})
	powerPosSwitch:SetValue(getConfig('power.position') or 'bottom')
	powerPosSwitch:SetOnSelect(function(value)
		setConfig('power.position', value)
	end)
	cardY = B.PlaceWidget(powerPosSwitch, inner, cardY, B.SWITCH_H)

	-- Power bar height slider
	local powerHeightSlider = Widgets.CreateSlider(inner, 'Power Bar Height', widgetW, 1, 20, 1)
	powerHeightSlider:SetValue(getConfig('power.height') or 2)
	powerHeightSlider:SetAfterValueChanged(function(value)
		setConfig('power.height', value)
	end)
	cardY = B.PlaceWidget(powerHeightSlider, inner, cardY, B.SLIDER_H)

	-- Per-power-type color overrides (filtered by relevance)
	local filterTokens
	if(unitType == 'player') then
		local _, playerClass = UnitClass('player')
		filterTokens = playerClass and CLASS_POWER_TYPES[playerClass]
	end

	for _, pt in next, ALL_POWER_TYPES do
		if(not filterTokens or filterTokens[pt.token]) then
			local configKey = 'power.customColors.' .. pt.token
			local picker = Widgets.CreateColorPicker(inner, pt.label, false,
				nil,
				function(r, g, b) setConfig(configKey, { r, g, b }) end)
			local saved = getConfig(configKey) or pt.default
			picker:SetColor(saved[1], saved[2], saved[3], 1)
			cardY = B.PlaceWidget(picker, inner, cardY, 22)
		end
	end

	Widgets.EndCard(card, parent, cardY)
	return card
end
