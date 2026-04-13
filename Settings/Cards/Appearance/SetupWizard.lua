local _, Framed = ...
local F = Framed
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local BUTTON_H = 28
local TOUR_TOOLTIP_BODY = 'The guided tour will walk you through Framed\'s features step by step.'

function F.AppearanceCards.SetupWizard(parent, width, getConfig, setConfig, fireChange)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local wizardBtn = Widgets.CreateButton(inner, 'Re-run Setup Wizard', 'widget', widgetW, BUTTON_H)
	wizardBtn:SetOnClick(function()
		if(F.Onboarding and F.Onboarding.ShowWizard) then
			F.Onboarding.ShowWizard()
		end
	end)
	cardY = B.PlaceWidget(wizardBtn, inner, cardY, BUTTON_H)

	local tourBtn = Widgets.CreateButton(inner, 'Take Tour', 'widget', widgetW, BUTTON_H)
	tourBtn:SetWidgetTooltip('Take Tour', TOUR_TOOLTIP_BODY)
	tourBtn:SetOnClick(function()
		if(F.Onboarding and F.Onboarding.StartTour) then
			F.Onboarding.StartTour()
		elseif(DEFAULT_CHAT_FRAME) then
			DEFAULT_CHAT_FRAME:AddMessage('|cff00ccffFramed:|r Guided tour coming in a future update.')
		end
	end)
	cardY = B.PlaceWidget(tourBtn, inner, cardY, BUTTON_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
