local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings.RegisterPanel({
	id      = 'externals',
	label   = 'Externals',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 11,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- Unit type dropdown + copy-to
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'externals', 'externals')

		-- Description
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('External defensive cooldowns. Supports visibility modes: show all, player-cast only, or other-cast only. Border color differentiates source.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- Shared BorderIcon settings
		yOffset = F.Settings.Builders.BorderIconSettings(content, width, yOffset, {
			unitType           = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party',
			configKey          = 'externals',
			showVisibilityMode = true,
			showSourceColors   = true,
		})

		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
