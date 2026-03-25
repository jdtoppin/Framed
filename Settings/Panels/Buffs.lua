local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings.RegisterPanel({
	id      = 'buffs',
	label   = 'Buffs',
	section = 'AURAS',
	order   = 11,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- Description
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('Create and configure buff indicators. Each indicator tracks specific spells and renders them using the chosen display type.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- CRUD builder
		yOffset = F.Settings.Builders.IndicatorCRUD(content, width, yOffset, {
			unitType  = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party',
			configKey = 'buffs',
		})

		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
