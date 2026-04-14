local _, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

F.Settings.RegisterPanel({
	id      = 'backups',
	label   = 'Backups',
	section = 'GLOBAL',
	order   = 30,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		local width   = parentW - C.Spacing.normal * 2

		local grid = Widgets.CreateCardGrid(content, width)
		grid._pinEnabled = false

		local function relayout()
			local oldContentH = content:GetHeight()
			local oldScroll   = scroll._scrollFrame:GetVerticalScroll()

			grid:AnimatedReflow()
			content:SetHeight(grid:GetTotalHeight())
			scroll:UpdateScrollRange()

			local growth = content:GetHeight() - oldContentH
			if(growth > 0) then
				local viewH     = scroll._scrollFrame:GetHeight()
				local maxScroll = math.max(0, content:GetHeight() - viewH)
				local newScroll = math.min(oldScroll + growth, maxScroll)
				scroll._scrollFrame:SetVerticalScroll(newScroll)
				scroll:_UpdateThumb()
			end
		end

		local args = { relayout }

		grid:AddCard('export', 'Export', F.BackupsCards.Export, args)
		grid:AddCard('import', 'Import', F.BackupsCards.Import)
		grid:SetFullWidth('export')
		grid:SetFullWidth('import')

		grid:SetTopOffset(C.Spacing.normal)
		grid:Layout(0, parentH)
		content:SetHeight(grid:GetTotalHeight())

		local function onScroll()
			local offset = scroll._scrollFrame:GetVerticalScroll()
			local viewH = scroll._scrollFrame:GetHeight()
			grid:Layout(offset, viewH)
			content:SetHeight(grid:GetTotalHeight())
		end
		scroll._scrollFrame:HookScript('OnMouseWheel', function()
			C_Timer.After(0, onScroll)
		end)

		F.EventBus:Register('SETTINGS_RESIZED', function(newW, newH)
			local gridW = newW - C.Spacing.normal * 2
			grid:SetWidth(gridW)
			content:SetHeight(grid:GetTotalHeight())
		end, 'BackupsPanel.resize')

		F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', function()
			grid:RebuildCards()
		end, 'BackupsPanel.resizeComplete')

		return scroll
	end,
})
