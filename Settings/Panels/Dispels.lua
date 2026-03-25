local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================

local PANE_TITLE_H = 20
local SLIDER_H     = 26
local CHECK_H      = 22
local DROPDOWN_H   = 22
local WIDGET_W     = 220

-- ============================================================
-- Config helpers
-- ============================================================

local function get(key)
	local layoutName = F.Settings.GetEditingLayout()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	return F.Config and F.Config:Get('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.dispellable.' .. key)
end

local function set(key, value)
	local layoutName = F.Settings.GetEditingLayout()
	local unitType   = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'
	if(F.Config) then
		F.Config:Set('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.dispellable.' .. key, value)
	end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED', 'layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.dispellable')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'dispels',
	label   = 'Dispels',
	section = 'AURAS',
	order   = 15,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll  = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ── Description ────────────────────────────────────────
		local descFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textSecondary)
		descFS:ClearAllPoints()
		Widgets.SetPoint(descFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		descFS:SetWidth(width)
		descFS:SetText('Highlight units that have dispellable debuffs. Shows an icon and a colored frame highlight.')
		descFS:SetWordWrap(true)
		yOffset = yOffset - descFS:GetStringHeight() - C.Spacing.normal

		-- ── Only show dispellable by me ─────────────────────────
		local dispCheck = Widgets.CreateCheckButton(content, 'Only show dispellable by me', function(checked)
			set('onlyDispellableByMe', checked)
		end)
		dispCheck:SetChecked(get('onlyDispellableByMe') == true)
		dispCheck:ClearAllPoints()
		Widgets.SetPoint(dispCheck, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - CHECK_H - C.Spacing.normal

		-- ── Highlight Type ─────────────────────────────────────
		local highlightPane = Widgets.CreateTitledPane(content, 'Frame Highlight', width)
		highlightPane:ClearAllPoints()
		Widgets.SetPoint(highlightPane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

		local hlCard, hlInner, hlCardY
		hlCard, hlInner, hlCardY = Widgets.StartCard(content, width, yOffset)

		local ht = C.HighlightType
		local highlightDD = Widgets.CreateDropdown(hlInner, WIDGET_W)
		highlightDD:SetItems({
			{ text = 'Gradient - Health Bar (Full)',    value = ht.GRADIENT_FULL },
			{ text = 'Gradient - Health Bar (Half)',    value = ht.GRADIENT_HALF },
			{ text = 'Solid - Health Bar (Current)',    value = ht.SOLID_CURRENT },
			{ text = 'Solid - Entire Frame',            value = ht.SOLID_ENTIRE },
		})
		highlightDD:SetValue(get('highlightType') or ht.GRADIENT_FULL)
		highlightDD:SetOnSelect(function(v) set('highlightType', v) end)
		highlightDD:ClearAllPoints()
		Widgets.SetPoint(highlightDD, 'TOPLEFT', hlInner, 'TOPLEFT', 0, hlCardY)
		hlCardY = hlCardY - DROPDOWN_H - C.Spacing.normal

		yOffset = Widgets.EndCard(hlCard, content, hlCardY)

		-- ── Icon Settings ──────────────────────────────────────
		local iconPane = Widgets.CreateTitledPane(content, 'Icon Settings', width)
		iconPane:ClearAllPoints()
		Widgets.SetPoint(iconPane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

		local iconCard, iconInner, iconCardY
		iconCard, iconInner, iconCardY = Widgets.StartCard(content, width, yOffset)

		-- Icon Size
		local sizeSlider = Widgets.CreateSlider(iconInner, 'Icon Size', WIDGET_W, 8, 48, 1)
		sizeSlider:SetValue(get('iconSize') or 20)
		sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
		sizeSlider:ClearAllPoints()
		Widgets.SetPoint(sizeSlider, 'TOPLEFT', iconInner, 'TOPLEFT', 0, iconCardY)
		iconCardY = iconCardY - SLIDER_H - C.Spacing.normal

		-- Frame Level
		local lvlSlider = Widgets.CreateSlider(iconInner, 'Frame Level', WIDGET_W, 1, 20, 1)
		lvlSlider:SetValue(get('frameLevel') or 5)
		lvlSlider:SetAfterValueChanged(function(v) set('frameLevel', v) end)
		lvlSlider:ClearAllPoints()
		Widgets.SetPoint(lvlSlider, 'TOPLEFT', iconInner, 'TOPLEFT', 0, iconCardY)
		iconCardY = iconCardY - SLIDER_H - C.Spacing.normal

		-- Anchor picker
		if(Widgets.CreateAnchorPicker) then
			local anchorData = get('anchor') or { 'TOPRIGHT', nil, 'TOPRIGHT', -2, -2 }
			local picker = Widgets.CreateAnchorPicker(iconInner, width)
			picker:SetAnchor(anchorData[1], anchorData[4] or -2, anchorData[5] or -2)
			picker:ClearAllPoints()
			Widgets.SetPoint(picker, 'TOPLEFT', iconInner, 'TOPLEFT', 0, iconCardY)
			picker:SetOnChanged(function(point, x, y)
				set('anchor', { point, nil, point, x, y })
			end)
			iconCardY = iconCardY - picker:GetHeight() - C.Spacing.normal
		end

		yOffset = Widgets.EndCard(iconCard, content, iconCardY)

		-- ── Final height ────────────────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()
		return scroll
	end,
})
