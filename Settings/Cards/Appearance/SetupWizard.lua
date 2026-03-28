local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local BUTTON_H     = 28

function F.AppearanceCards.SetupWizard(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)

	local wizardBtn = Widgets.CreateButton(inner, 'Re-run Setup Wizard', 'widget', 180, BUTTON_H)
	cardY = B.PlaceWidget(wizardBtn, inner, cardY, BUTTON_H)

	wizardBtn:SetOnClick(function()
		if(F.Onboarding and F.Onboarding.ShowWizard) then
			F.Onboarding.ShowWizard()
		end
	end)

	Widgets.EndCard(card, parent, cardY)
	return card
end
