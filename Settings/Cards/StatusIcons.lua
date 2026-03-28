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
local WIDGET_W     = B.WIDGET_W
local placeWidget  = B.PlaceWidget
local placeHeading = B.PlaceHeading

function F.SettingsCards.StatusIcons(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	-- Show role icon checkbox
	local showRoleCheck = Widgets.CreateCheckButton(inner, 'Show Role Icon', function(checked)
		setConfig('statusIcons.role', checked)
	end)
	showRoleCheck:SetChecked(getConfig('statusIcons.role') ~= false)
	cardY = placeWidget(showRoleCheck, inner, cardY, CHECK_H)

	-- Show leader icon checkbox
	local showLeaderCheck = Widgets.CreateCheckButton(inner, 'Show Leader Icon', function(checked)
		setConfig('statusIcons.leader', checked)
	end)
	showLeaderCheck:SetChecked(getConfig('statusIcons.leader') ~= false)
	cardY = placeWidget(showLeaderCheck, inner, cardY, CHECK_H)

	-- Show ready check checkbox
	local showReadyCheckCheck = Widgets.CreateCheckButton(inner, 'Show Ready Check', function(checked)
		setConfig('statusIcons.readyCheck', checked)
	end)
	showReadyCheckCheck:SetChecked(getConfig('statusIcons.readyCheck') ~= false)
	cardY = placeWidget(showReadyCheckCheck, inner, cardY, CHECK_H)

	-- Show raid icon checkbox
	local showRaidIconCheck = Widgets.CreateCheckButton(inner, 'Show Raid Icon', function(checked)
		setConfig('statusIcons.raidIcon', checked)
	end)
	showRaidIconCheck:SetChecked(getConfig('statusIcons.raidIcon') ~= false)
	cardY = placeWidget(showRaidIconCheck, inner, cardY, CHECK_H)

	-- Show combat icon checkbox
	local showCombatIconCheck = Widgets.CreateCheckButton(inner, 'Show Combat Icon', function(checked)
		setConfig('statusIcons.combat', checked)
	end)
	showCombatIconCheck:SetChecked(getConfig('statusIcons.combat') or false)
	cardY = placeWidget(showCombatIconCheck, inner, cardY, CHECK_H)

	-- Show resting icon checkbox
	local showRestingCheck = Widgets.CreateCheckButton(inner, 'Show Resting Icon', function(checked)
		setConfig('statusIcons.resting', checked)
	end)
	showRestingCheck:SetChecked(getConfig('statusIcons.resting') or false)
	cardY = placeWidget(showRestingCheck, inner, cardY, CHECK_H)

	-- Show phase icon checkbox
	local showPhaseCheck = Widgets.CreateCheckButton(inner, 'Show Phase Icon', function(checked)
		setConfig('statusIcons.phase', checked)
	end)
	showPhaseCheck:SetChecked(getConfig('statusIcons.phase') or false)
	cardY = placeWidget(showPhaseCheck, inner, cardY, CHECK_H)

	-- Show resurrect icon checkbox
	local showResurrectCheck = Widgets.CreateCheckButton(inner, 'Show Resurrect Icon', function(checked)
		setConfig('statusIcons.resurrect', checked)
	end)
	showResurrectCheck:SetChecked(getConfig('statusIcons.resurrect') or false)
	cardY = placeWidget(showResurrectCheck, inner, cardY, CHECK_H)

	-- Show summon icon checkbox
	local showSummonCheck = Widgets.CreateCheckButton(inner, 'Show Summon Icon', function(checked)
		setConfig('statusIcons.summon', checked)
	end)
	showSummonCheck:SetChecked(getConfig('statusIcons.summon') or false)
	cardY = placeWidget(showSummonCheck, inner, cardY, CHECK_H)

	-- Show raid role icon checkbox
	local showRaidRoleCheck = Widgets.CreateCheckButton(inner, 'Show Raid Role Icon', function(checked)
		setConfig('statusIcons.raidRole', checked)
	end)
	showRaidRoleCheck:SetChecked(getConfig('statusIcons.raidRole') or false)
	cardY = placeWidget(showRaidRoleCheck, inner, cardY, CHECK_H)

	-- Show PvP icon checkbox
	local showPvPCheck = Widgets.CreateCheckButton(inner, 'Show PvP Icon', function(checked)
		setConfig('statusIcons.pvp', checked)
	end)
	showPvPCheck:SetChecked(getConfig('statusIcons.pvp') or false)
	cardY = placeWidget(showPvPCheck, inner, cardY, CHECK_H)

	-- Show status text checkbox
	local showStatusTextCheck = Widgets.CreateCheckButton(inner, 'Show Status Text', function(checked)
		setConfig('statusText', checked)
	end)
	showStatusTextCheck:SetChecked(getConfig('statusText') ~= false)
	cardY = placeWidget(showStatusTextCheck, inner, cardY, CHECK_H)

	Widgets.EndCard(card, parent, cardY)
	card:ClearAllPoints()
	card._startY = 0
	return card
end
