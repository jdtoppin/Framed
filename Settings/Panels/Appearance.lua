local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'appearance',
	label   = 'Appearance',
	section = 'GLOBAL',
	order   = 10,
	create  = function(parent)
		local parentW = parent._explicitWidth or parent:GetWidth() or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width = parentW - C.Spacing.normal * 2

		local function getConfig(key)
			return F.Config and F.Config:Get('general.' .. key)
		end
		local function setConfig(key, value)
			if(F.Config) then F.Config:Set('general.' .. key, value) end
		end
		local function fireChange()
			if(F.EventBus) then F.EventBus:Fire('CONFIG_CHANGED:general') end
		end

		local grid = Widgets.CreateCardGrid(content, width)
		local args = { getConfig, setConfig, fireChange }

		grid:AddCard('accent',      'Accent Color',        F.AppearanceCards.AccentColor,        args)
		grid:AddCard('scale',       'UI Scale',            F.AppearanceCards.UIScale,             args)
		grid:AddCard('font',        'Global Font',         F.AppearanceCards.GlobalFont,          args)
		grid:AddCard('barTexture',  'Bar Texture',         F.AppearanceCards.BarTexture,          args)
		grid:AddCard('targetHL',    'Target Highlight',    F.AppearanceCards.TargetHighlight,     args)
		grid:AddCard('mouseoverHL', 'Mouseover Highlight', F.AppearanceCards.MouseoverHighlight,  args)
		grid:AddCard('tooltips',    'Tooltips',            F.AppearanceCards.Tooltips,            args)
		grid:AddCard('wizard',      'Setup Wizard',        F.AppearanceCards.SetupWizard,         args)

		-- Load pinned state
		local pinnedCards = F.Config and F.Config:Get('general.pinnedAppearanceCards') or {}
		for cardId, isPinned in next, pinnedCards do
			if(isPinned) then grid:SetPinned(cardId, true) end
		end

		grid._onPinChanged = function(cardId, pinned)
			if(F.Config) then
				F.Config:Set('general.pinnedAppearanceCards.' .. cardId, pinned or nil)
			end
		end

		grid:SetTopOffset(C.Spacing.normal)
		grid:Layout(0, parentH)
		content:SetHeight(grid:GetTotalHeight())

		-- Lazy loading on scroll
		local function onScroll()
			local offset = scroll._scrollFrame:GetVerticalScroll()
			local viewH = scroll._scrollFrame:GetHeight()
			grid:Layout(offset, viewH)
			content:SetHeight(grid:GetTotalHeight())
		end
		scroll._scrollFrame:HookScript('OnMouseWheel', function()
			C_Timer.After(0, onScroll)
		end)

		-- Re-layout on settings resize
		F.EventBus:Register('SETTINGS_RESIZED', function(newW, newH)
			local gridW = newW - C.Spacing.normal * 2
			grid:SetWidth(gridW)
			content:SetWidth(newW)
			content:SetHeight(grid:GetTotalHeight())
		end)

		return scroll
	end,
})
