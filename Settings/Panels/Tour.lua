local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Tour panel
-- Single button to start the guided tour (Phase 8).
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'tour',
	label   = 'Tour',
	section = 'BOTTOM',
	order   = 90,
	create  = function(parent)
		local scroll = Widgets.CreateScrollFrame(
			parent, nil,
			parent:GetWidth(),
			parent:GetHeight())
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		local width   = parent:GetWidth() - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ── Description ────────────────────────────────────────
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetWordWrap(true)
		descFS:SetText('The guided tour will walk you through Framed\'s features step by step.')
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- ── Start Guided Tour button ───────────────────────────
		local tourBtn = Widgets.CreateButton(content, 'Start Guided Tour', 'accent', 180, 28)
		tourBtn:ClearAllPoints()
		Widgets.SetPoint(tourBtn, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		tourBtn:SetOnClick(function()
			if(F.Onboarding and F.Onboarding.StartTour) then
				F.Onboarding.StartTour()
			else
				if(DEFAULT_CHAT_FRAME) then
					DEFAULT_CHAT_FRAME:AddMessage('|cff00ccffFramed:|r Guided tour coming in a future update.')
				end
			end
		end)
		yOffset = yOffset - 28 - C.Spacing.normal

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
