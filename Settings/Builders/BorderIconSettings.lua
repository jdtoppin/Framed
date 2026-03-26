local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings = F.Settings or {}
F.Settings.Builders = F.Settings.Builders or {}

-- Widget constants
local SLIDER_H     = 26
local CHECK_H      = 22
local DROPDOWN_H   = 22
local LABEL_H      = 16
local WIDGET_W     = 220

-- Helper: get/set config values scoped to the editing preset + unit type + config key
local function makeConfigHelpers(unitType, configKey)
	local function get(key)
		local presetName = F.Settings.GetEditingPreset()
		return F.Config and F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType .. '.' .. configKey .. '.' .. key)
	end
	local function set(key, value)
		local presetName = F.Settings.GetEditingPreset()
		if(F.Config) then
			F.Config:Set('presets.' .. presetName .. '.auras.' .. unitType .. '.' .. configKey .. '.' .. key, value)
		end
		if(F.PresetManager) then F.PresetManager.MarkCustomized(presetName) end
		if(F.EventBus) then
			F.EventBus:Fire('CONFIG_CHANGED', 'presets.' .. presetName .. '.auras.' .. unitType .. '.' .. configKey)
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

	-- ── Visibility Mode (Externals / Defensives) ────────────
	if(opts.showVisibilityMode) then
		local visLabel, visLabelH = Widgets.CreateHeading(parent, 'Visibility', 2)
		visLabel:ClearAllPoints()
		Widgets.SetPoint(visLabel, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - visLabelH

		local visCard, visInner, visCardY
		visCard, visInner, visCardY = Widgets.StartCard(parent, width, yOffset)

		local visDD = Widgets.CreateDropdown(visInner, WIDGET_W)
		visDD:SetItems({
			{ text = 'All',          value = 'all' },
			{ text = 'Player Only',  value = 'player' },
			{ text = 'Others Only',  value = 'others' },
		})
		visDD:SetValue(get('visibilityMode') or 'all')
		visDD:SetOnSelect(function(v) set('visibilityMode', v) end)
		visDD:ClearAllPoints()
		Widgets.SetPoint(visDD, 'TOPLEFT', visInner, 'TOPLEFT', 0, visCardY)
		visCardY = visCardY - DROPDOWN_H - C.Spacing.normal

		yOffset = Widgets.EndCard(visCard, parent, visCardY)
	end

	-- ── Source Colors (Externals / Defensives) ──────────────
	if(opts.showSourceColors and Widgets.CreateColorPicker) then
		local colorHeading, colorHeadingH = Widgets.CreateHeading(parent, 'Border Colors', 2)
		colorHeading:ClearAllPoints()
		Widgets.SetPoint(colorHeading, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - colorHeadingH

		local colorCard, colorInner, colorCardY
		colorCard, colorInner, colorCardY = Widgets.StartCard(parent, width, yOffset)

		-- Player-cast color
		local playerCP = Widgets.CreateColorPicker(colorInner, 'Player Cast')
		playerCP:ClearAllPoints()
		Widgets.SetPoint(playerCP, 'TOPLEFT', colorInner, 'TOPLEFT', 0, colorCardY)
		local savedPlayerColor = get('playerColor')
		if(savedPlayerColor) then
			playerCP:SetColor(savedPlayerColor[1], savedPlayerColor[2], savedPlayerColor[3])
		else
			playerCP:SetColor(0, 0.8, 0)
		end
		playerCP:SetOnColorChanged(function(r, g, b)
			set('playerColor', { r, g, b })
		end)
		colorCardY = colorCardY - playerCP:GetHeight() - C.Spacing.normal

		-- Other-cast color
		local otherCP = Widgets.CreateColorPicker(colorInner, 'Other Cast')
		otherCP:ClearAllPoints()
		Widgets.SetPoint(otherCP, 'TOPLEFT', colorInner, 'TOPLEFT', 0, colorCardY)
		local savedOtherColor = get('otherColor')
		if(savedOtherColor) then
			otherCP:SetColor(savedOtherColor[1], savedOtherColor[2], savedOtherColor[3])
		else
			otherCP:SetColor(1, 0.85, 0)
		end
		otherCP:SetOnColorChanged(function(r, g, b)
			set('otherColor', { r, g, b })
		end)
		colorCardY = colorCardY - otherCP:GetHeight() - C.Spacing.normal

		yOffset = Widgets.EndCard(colorCard, parent, colorCardY)
	end

	-- ── Display section ─────────────────────────────────────
	local displayHeading, displayHeadingH = Widgets.CreateHeading(parent, 'Display Settings', 2)
	displayHeading:ClearAllPoints()
	Widgets.SetPoint(displayHeading, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - displayHeadingH

	local displayCard, displayInner, displayCardY
	displayCard, displayInner, displayCardY = Widgets.StartCard(parent, width, yOffset)

	-- Icon Size
	local sizeSlider = Widgets.CreateSlider(displayInner, 'Icon Size', WIDGET_W, 8, 48, 1)
	sizeSlider:SetValue(get('iconSize') or 16)
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	sizeSlider:ClearAllPoints()
	Widgets.SetPoint(sizeSlider, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
	displayCardY = displayCardY - SLIDER_H - C.Spacing.normal

	-- Big Icon Size (debuffs/raidDebuffs only)
	if(opts.showBigIconSize) then
		local bigSlider = Widgets.CreateSlider(displayInner, 'Big Icon Size', WIDGET_W, 8, 64, 1)
		bigSlider:SetValue(get('bigIconSize') or 22)
		bigSlider:SetAfterValueChanged(function(v) set('bigIconSize', v) end)
		bigSlider:ClearAllPoints()
		Widgets.SetPoint(bigSlider, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
		displayCardY = displayCardY - SLIDER_H - C.Spacing.normal
	end

	-- Max Displayed
	local maxSlider = Widgets.CreateSlider(displayInner, 'Max Displayed', WIDGET_W, 1, 20, 1)
	maxSlider:SetValue(get('maxDisplayed') or 3)
	maxSlider:SetAfterValueChanged(function(v) set('maxDisplayed', v) end)
	maxSlider:ClearAllPoints()
	Widgets.SetPoint(maxSlider, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
	displayCardY = displayCardY - SLIDER_H - C.Spacing.normal

	-- Show Duration
	local durCheck = Widgets.CreateCheckButton(displayInner, 'Show Duration', function(checked) set('showDuration', checked) end)
	durCheck:SetChecked(get('showDuration') ~= false)
	durCheck:ClearAllPoints()
	Widgets.SetPoint(durCheck, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
	displayCardY = displayCardY - CHECK_H - C.Spacing.normal

	-- Show Animation (fade out)
	local animCheck = Widgets.CreateCheckButton(displayInner, 'Show Animation', function(checked) set('showAnimation', checked) end)
	animCheck:SetChecked(get('showAnimation') ~= false)
	animCheck:ClearAllPoints()
	Widgets.SetPoint(animCheck, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
	displayCardY = displayCardY - CHECK_H - C.Spacing.normal

	-- Orientation
	local oriLabel, oriLabelH = Widgets.CreateHeading(displayInner, 'Orientation', 3)
	oriLabel:ClearAllPoints()
	Widgets.SetPoint(oriLabel, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
	displayCardY = displayCardY - oriLabelH

	local oriDD = Widgets.CreateDropdown(displayInner, WIDGET_W)
	oriDD:SetItems({
		{ text = 'Right', value = 'RIGHT' },
		{ text = 'Left',  value = 'LEFT' },
		{ text = 'Up',    value = 'UP' },
		{ text = 'Down',  value = 'DOWN' },
	})
	oriDD:SetValue(get('orientation') or 'RIGHT')
	oriDD:SetOnSelect(function(v) set('orientation', v) end)
	oriDD:ClearAllPoints()
	Widgets.SetPoint(oriDD, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
	displayCardY = displayCardY - DROPDOWN_H - C.Spacing.normal

	-- Frame Level
	local lvlSlider = Widgets.CreateSlider(displayInner, 'Frame Level', WIDGET_W, 1, 20, 1)
	lvlSlider:SetValue(get('frameLevel') or 5)
	lvlSlider:SetAfterValueChanged(function(v) set('frameLevel', v) end)
	lvlSlider:ClearAllPoints()
	Widgets.SetPoint(lvlSlider, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
	displayCardY = displayCardY - SLIDER_H - C.Spacing.normal

	yOffset = Widgets.EndCard(displayCard, parent, displayCardY)

	-- ── Position section ────────────────────────────────────
	local posHeading, posHeadingH = Widgets.CreateHeading(parent, 'Icon Position', 2)
	posHeading:ClearAllPoints()
	Widgets.SetPoint(posHeading, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - posHeadingH

	local posCard, posInner, posCardY
	posCard, posInner, posCardY = Widgets.StartCard(parent, width, yOffset)

	-- Anchor picker (if available)
	if(Widgets.CreateAnchorPicker) then
		local anchor = get('anchor') or { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 }
		local picker = Widgets.CreateAnchorPicker(posInner, width)
		picker:SetAnchor(anchor[1], anchor[4] or 0, anchor[5] or 0)
		picker:ClearAllPoints()
		Widgets.SetPoint(picker, 'TOPLEFT', posInner, 'TOPLEFT', 0, posCardY)
		picker:SetOnChanged(function(point, x, y)
			set('anchor', { point, nil, point, x, y })
		end)
		posCardY = posCardY - picker:GetHeight() - C.Spacing.normal
	end

	yOffset = Widgets.EndCard(posCard, parent, posCardY)

	-- ── Stack Font section ──────────────────────────────────
	local stackHeading, stackHeadingH = Widgets.CreateHeading(parent, 'Stack Count Font', 2)
	stackHeading:ClearAllPoints()
	Widgets.SetPoint(stackHeading, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - stackHeadingH

	local stackCard, stackInner, stackCardY
	stackCard, stackInner, stackCardY = Widgets.StartCard(parent, width, yOffset)

	local stackSize = Widgets.CreateSlider(stackInner, 'Size', WIDGET_W, 6, 24, 1)
	stackSize:SetValue(get('stackFont.size') or 10)
	stackSize:SetAfterValueChanged(function(v) set('stackFont.size', v) end)
	stackSize:ClearAllPoints()
	Widgets.SetPoint(stackSize, 'TOPLEFT', stackInner, 'TOPLEFT', 0, stackCardY)
	stackCardY = stackCardY - SLIDER_H - C.Spacing.normal

	yOffset = Widgets.EndCard(stackCard, parent, stackCardY)

	-- ── Duration Font section ───────────────────────────────
	local durHeading, durHeadingH = Widgets.CreateHeading(parent, 'Duration Text Font', 2)
	durHeading:ClearAllPoints()
	Widgets.SetPoint(durHeading, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - durHeadingH

	local durFontCard, durFontInner, durFontCardY
	durFontCard, durFontInner, durFontCardY = Widgets.StartCard(parent, width, yOffset)

	local durSize = Widgets.CreateSlider(durFontInner, 'Size', WIDGET_W, 6, 24, 1)
	durSize:SetValue(get('durationFont.size') or 10)
	durSize:SetAfterValueChanged(function(v) set('durationFont.size', v) end)
	durSize:ClearAllPoints()
	Widgets.SetPoint(durSize, 'TOPLEFT', durFontInner, 'TOPLEFT', 0, durFontCardY)
	durFontCardY = durFontCardY - SLIDER_H - C.Spacing.normal

	yOffset = Widgets.EndCard(durFontCard, parent, durFontCardY)

	return yOffset
end
