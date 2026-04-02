local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings.RegisterPanel({
	id      = 'debuffs',
	label   = 'Debuffs',
	section    = 'PRESET_SCOPED',
	subSection = 'auras',
	order      = 12,
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
		yOffset = F.Settings.BuildAuraUnitTypeRow(content, width, yOffset, 'debuffs', 'debuffs')

		-- Description
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('Debuff indicators displayed on unit frames. Each indicator has its own server-side filter, position, and icon settings.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- Indicator CRUD
		yOffset = F.Settings.Builders.DebuffIndicatorCRUD(content, width, yOffset, {
			unitType = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party',
			scrollFrame = scroll,
			contentFrame = content,
		})

		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
