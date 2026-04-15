local _, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

F.Settings.RegisterPanel({
	id      = 'about',
	label   = 'About',
	section = 'BOTTOM',
	order   = 100,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		local width   = parentW - C.Spacing.normal * 2

		local grid = Widgets.CreateCardGrid(content, width)
		grid._pinEnabled = false

		grid:AddCard('about',          'About',           F.AboutCards.About)
		grid:AddCard('gettingStarted', 'Getting Started', F.AboutCards.GettingStarted)
		grid:AddCard('features',       'Features',        F.AboutCards.Features)
		grid:AddCard('changelog',      'Changelog',       F.AboutCards.Changelog)
		grid:AddCard('credits',        'Credits',         F.AboutCards.Credits)
		grid:AddCard('license',        'License',         F.AboutCards.License)

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

		local resizeKey = 'AboutPanel.resize'
		local function onSettingsResize(newW, newH)
			local gridW = newW - C.Spacing.normal * 2
			grid:SetWidth(gridW)
			content:SetHeight(grid:GetTotalHeight())
		end
		local function onSettingsResizeComplete()
			grid:RebuildCards()
		end

		F.EventBus:Register('SETTINGS_RESIZED', onSettingsResize, resizeKey)
		F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', onSettingsResizeComplete, resizeKey .. '.complete')

		scroll:HookScript('OnHide', function()
			F.EventBus:Unregister('SETTINGS_RESIZED', resizeKey)
			F.EventBus:Unregister('SETTINGS_RESIZE_COMPLETE', resizeKey .. '.complete')
		end)
		scroll:HookScript('OnShow', function()
			F.EventBus:Register('SETTINGS_RESIZED', onSettingsResize, resizeKey)
			F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', onSettingsResizeComplete, resizeKey .. '.complete')
		end)

		return scroll
	end,
})
