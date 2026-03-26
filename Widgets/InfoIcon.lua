local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- InfoIcon — Small (i) button with hover tooltip
-- ============================================================

local ICON_SIZE = 14

--- Create an info icon that shows a tooltip on hover.
--- @param parent Frame   Parent frame
--- @param tooltipTitle string  Tooltip title text
--- @param tooltipBody  string  Tooltip body text
--- @return Button icon
function Widgets.CreateInfoIcon(parent, tooltipTitle, tooltipBody)
	local btn = CreateFrame('Button', nil, parent)
	btn:SetSize(ICON_SIZE, ICON_SIZE)

	-- Circle background
	local bg = btn:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(btn)
	bg:SetColorTexture(C.Colors.widget[1], C.Colors.widget[2], C.Colors.widget[3], 0.8)

	-- "i" label
	local label = Widgets.CreateFontString(btn, 10, C.Colors.textSecondary)
	label:SetPoint('CENTER', btn, 'CENTER', 0, 0)
	label:SetText('i')
	btn._label = label

	-- Hover: show tooltip
	btn:SetScript('OnEnter', function(self)
		label:SetTextColor(1, 1, 1, 1)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:AddLine(tooltipTitle, 1, 1, 1)
		if(tooltipBody and tooltipBody ~= '') then
			GameTooltip:AddLine(tooltipBody, C.Colors.textNormal[1], C.Colors.textNormal[2], C.Colors.textNormal[3], true)
		end
		GameTooltip:Show()
	end)

	btn:SetScript('OnLeave', function()
		label:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3], 1)
		GameTooltip:Hide()
	end)

	return btn
end
