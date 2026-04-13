local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.AppearanceCards = F.AppearanceCards or {}

local BUTTON_H = 28
local OVERVIEW_TOOLTIP_BODY = 'The overview walks you through Framed\'s core features: layouts, edit mode, settings cards, and aura indicators.'

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

	local overviewBtn = Widgets.CreateButton(inner, 'Take Overview', 'widget', widgetW, BUTTON_H)
	overviewBtn:SetWidgetTooltip('Take Overview', OVERVIEW_TOOLTIP_BODY)
	overviewBtn:SetOnClick(function()
		if(F.Onboarding and F.Onboarding.ShowOverview) then
			F.Onboarding.ShowOverview()
		end
	end)
	cardY = B.PlaceWidget(overviewBtn, inner, cardY, BUTTON_H)

	Widgets.EndCard(card, parent, cardY)
	return card
end
