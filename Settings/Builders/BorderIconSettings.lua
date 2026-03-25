local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings = F.Settings or {}
F.Settings.Builders = F.Settings.Builders or {}

-- Layout constants
local PANE_TITLE_H = 20
local SLIDER_H     = 26
local CHECK_H      = 22
local DROPDOWN_H   = 22
local LABEL_H      = 16
local WIDGET_W     = 220

-- Helper: get/set config values scoped to the editing layout + unit type + config key
local function makeConfigHelpers(unitType, configKey)
	local function get(key)
		local layoutName = F.Settings.GetEditingLayout()
		return F.Config and F.Config:Get('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. configKey .. '.' .. key)
	end
	local function set(key, value)
		local layoutName = F.Settings.GetEditingLayout()
		if(F.Config) then
			F.Config:Set('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. configKey .. '.' .. key, value)
		end
		if(F.EventBus) then
			F.EventBus:Fire('CONFIG_CHANGED', 'layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. configKey)
		end
	end
	return get, set
end

--- Create the shared BorderIcon settings UI.
--- @param parent Frame  The content frame to build into
--- @param width number  Available width
--- @param opts table  { unitType, configKey, showDispellableByMe?, showBigIconSize? }
--- @return number yOffset  The final yOffset after all widgets
function F.Settings.Builders.BorderIconSettings(parent, width, yOffset, opts)
	local get, set = makeConfigHelpers(opts.unitType, opts.configKey)

	-- ── Only show dispellable by me ─────────────────────────
	if(opts.showDispellableByMe) then
		local dispCheck = Widgets.CreateCheckButton(parent, 'Only show dispellable by me', function(checked)
			set('onlyDispellableByMe', checked)
		end)
		dispCheck:SetChecked(get('onlyDispellableByMe') == true)
		dispCheck:ClearAllPoints()
		Widgets.SetPoint(dispCheck, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - CHECK_H - C.Spacing.normal
	end

	-- ── Display section ─────────────────────────────────────
	local displayPane = Widgets.CreateTitledPane(parent, 'Display', width)
	displayPane:ClearAllPoints()
	Widgets.SetPoint(displayPane, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

	-- Icon Size
	local sizeSlider = Widgets.CreateSlider(parent, 'Icon Size', WIDGET_W, 8, 48, 1)
	sizeSlider:SetValue(get('iconSize') or 16)
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	sizeSlider:ClearAllPoints()
	Widgets.SetPoint(sizeSlider, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - SLIDER_H - C.Spacing.normal

	-- Big Icon Size (debuffs/raidDebuffs only)
	if(opts.showBigIconSize) then
		local bigSlider = Widgets.CreateSlider(parent, 'Big Icon Size', WIDGET_W, 8, 64, 1)
		bigSlider:SetValue(get('bigIconSize') or 22)
		bigSlider:SetAfterValueChanged(function(v) set('bigIconSize', v) end)
		bigSlider:ClearAllPoints()
		Widgets.SetPoint(bigSlider, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - SLIDER_H - C.Spacing.normal
	end

	-- Max Displayed
	local maxSlider = Widgets.CreateSlider(parent, 'Max Displayed', WIDGET_W, 1, 20, 1)
	maxSlider:SetValue(get('maxDisplayed') or 3)
	maxSlider:SetAfterValueChanged(function(v) set('maxDisplayed', v) end)
	maxSlider:ClearAllPoints()
	Widgets.SetPoint(maxSlider, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - SLIDER_H - C.Spacing.normal

	-- Show Duration
	local durCheck = Widgets.CreateCheckButton(parent, 'Show Duration', function(checked) set('showDuration', checked) end)
	durCheck:SetChecked(get('showDuration') ~= false)
	durCheck:ClearAllPoints()
	Widgets.SetPoint(durCheck, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - CHECK_H - C.Spacing.normal

	-- Show Animation (fade out)
	local animCheck = Widgets.CreateCheckButton(parent, 'Show Animation', function(checked) set('showAnimation', checked) end)
	animCheck:SetChecked(get('showAnimation') ~= false)
	animCheck:ClearAllPoints()
	Widgets.SetPoint(animCheck, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - CHECK_H - C.Spacing.normal

	-- Orientation
	local oriDD = Widgets.CreateDropdown(parent, WIDGET_W)
	oriDD:SetItems({
		{ text = 'Right', value = 'RIGHT' },
		{ text = 'Left',  value = 'LEFT' },
		{ text = 'Up',    value = 'UP' },
		{ text = 'Down',  value = 'DOWN' },
	})
	oriDD:SetValue(get('orientation') or 'RIGHT')
	oriDD:SetOnSelect(function(v) set('orientation', v) end)
	oriDD:ClearAllPoints()
	Widgets.SetPoint(oriDD, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - DROPDOWN_H - C.Spacing.normal

	-- Frame Level
	local lvlSlider = Widgets.CreateSlider(parent, 'Frame Level', WIDGET_W, 1, 20, 1)
	lvlSlider:SetValue(get('frameLevel') or 5)
	lvlSlider:SetAfterValueChanged(function(v) set('frameLevel', v) end)
	lvlSlider:ClearAllPoints()
	Widgets.SetPoint(lvlSlider, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - SLIDER_H - C.Spacing.normal

	-- ── Position section ────────────────────────────────────
	local posPane = Widgets.CreateTitledPane(parent, 'Position', width)
	posPane:ClearAllPoints()
	Widgets.SetPoint(posPane, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

	-- Anchor picker (if available)
	if(Widgets.CreateAnchorPicker) then
		local anchor = get('anchor') or { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 }
		local picker = Widgets.CreateAnchorPicker(parent, width)
		picker:SetAnchor(anchor[1], anchor[4] or 0, anchor[5] or 0)
		picker:ClearAllPoints()
		Widgets.SetPoint(picker, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		picker:SetOnChanged(function(point, x, y)
			set('anchor', { point, nil, point, x, y })
		end)
		yOffset = yOffset - picker:GetHeight() - C.Spacing.normal
	end

	-- ── Stack Font section ──────────────────────────────────
	local stackPane = Widgets.CreateTitledPane(parent, 'Stack Font', width)
	stackPane:ClearAllPoints()
	Widgets.SetPoint(stackPane, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

	local stackSize = Widgets.CreateSlider(parent, 'Size', WIDGET_W, 6, 24, 1)
	stackSize:SetValue(get('stackFont.size') or 10)
	stackSize:SetAfterValueChanged(function(v) set('stackFont.size', v) end)
	stackSize:ClearAllPoints()
	Widgets.SetPoint(stackSize, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - SLIDER_H - C.Spacing.normal

	-- ── Duration Font section ───────────────────────────────
	local durPane = Widgets.CreateTitledPane(parent, 'Duration Font', width)
	durPane:ClearAllPoints()
	Widgets.SetPoint(durPane, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - PANE_TITLE_H - C.Spacing.normal

	local durSize = Widgets.CreateSlider(parent, 'Size', WIDGET_W, 6, 24, 1)
	durSize:SetValue(get('durationFont.size') or 10)
	durSize:SetAfterValueChanged(function(v) set('durationFont.size', v) end)
	durSize:ClearAllPoints()
	Widgets.SetPoint(durSize, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - SLIDER_H - C.Spacing.normal

	return yOffset
end
