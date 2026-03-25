local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Profiles panel
-- Phase 7 will flesh out import/export functionality.
-- For now this is a placeholder that shows the current profile.
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'profiles',
	label   = 'Profiles',
	section = 'GENERAL',
	order   = 30,
	create  = function(parent)
		local scroll = Widgets.CreateScrollFrame(
			parent, nil,
			parent:GetWidth(),
			parent:GetHeight())
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		local width   = parent:GetWidth() - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ── Current profile info ───────────────────────────────
		local pane = Widgets.CreateTitledPane(content, 'Current Profile', width)
		pane:ClearAllPoints()
		Widgets.SetPoint(pane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - 20 - C.Spacing.normal

		local profileName = (F.Config and F.Config:Get('profile')) or 'Default'
		local profileFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textActive)
		profileFS:ClearAllPoints()
		Widgets.SetPoint(profileFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		profileFS:SetText(profileName)
		yOffset = yOffset - C.Font.sizeNormal - C.Spacing.loose

		-- ── Placeholder notice ─────────────────────────────────
		local noticePaneTitle = Widgets.CreateTitledPane(content, 'Import / Export', width)
		noticePaneTitle:ClearAllPoints()
		Widgets.SetPoint(noticePaneTitle, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - 20 - C.Spacing.normal

		local noticeFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		noticeFS:ClearAllPoints()
		Widgets.SetPoint(noticeFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		noticeFS:SetWidth(width)
		noticeFS:SetWordWrap(true)
		noticeFS:SetText('Import/Export functionality coming in a future update.')
		yOffset = yOffset - noticeFS:GetStringHeight() - C.Spacing.normal

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
