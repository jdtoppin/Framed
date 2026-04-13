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
		if(key ~= 'enabled' and F.EventBus) then
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
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- ── Filter Mode ─────────────────────────────────────────
	if(opts.showDispellableByMe) then
		local filterLabel, filterLabelH = Widgets.CreateHeading(parent, 'Filter Mode', 2)
		filterLabel:ClearAllPoints()
		Widgets.SetPoint(filterLabel, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - filterLabelH

		local filterCard, filterInner, filterCardY
		filterCard, filterInner, filterCardY = Widgets.StartCard(parent, width, yOffset)

		local filterDD = Widgets.CreateDropdown(filterInner, widgetW)
		filterDD:SetItems({
			{ text = 'All Debuffs',      value = 'all' },
			{ text = 'Raid-Relevant',    value = 'raid' },
			{ text = 'Important',        value = 'important' },
			{ text = 'Dispellable',      value = 'dispellable' },
			{ text = 'Raid (In-Combat)', value = 'raidCombat' },
			{ text = 'Encounter Only',   value = 'encounter' },
		})
		filterDD:SetValue(get('filterMode') or 'all')
		filterDD:SetOnSelect(function(v) set('filterMode', v) end)
		filterDD:ClearAllPoints()
		Widgets.SetPoint(filterDD, 'TOPLEFT', filterInner, 'TOPLEFT', 0, filterCardY)
		filterCardY = filterCardY - DROPDOWN_H - C.Spacing.normal

		yOffset = Widgets.EndCard(filterCard, parent, filterCardY)
	end

	-- ── Visibility Mode (Externals / Defensives) ────────────
	if(opts.showVisibilityMode) then
		local visLabel, visLabelH = Widgets.CreateHeading(parent, 'Visibility', 2)
		visLabel:ClearAllPoints()
		Widgets.SetPoint(visLabel, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - visLabelH

		local visCard, visInner, visCardY
		visCard, visInner, visCardY = Widgets.StartCard(parent, width, yOffset)

		-- Enabled toggle
		local enableCheck = Widgets.CreateCheckButton(visInner, 'Enabled', function(checked)
			set('enabled', checked)
		end)
		enableCheck:SetChecked(get('enabled'))
		enableCheck:ClearAllPoints()
		Widgets.SetPoint(enableCheck, 'TOPLEFT', visInner, 'TOPLEFT', 0, visCardY)
		visCardY = visCardY - CHECK_H - C.Spacing.normal

		local visDD = Widgets.CreateDropdown(visInner, widgetW)
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
	local sizeSlider = Widgets.CreateSlider(displayInner, 'Icon Size', widgetW, 8, 48, 1)
	sizeSlider:SetValue(get('iconSize') or 16)
	sizeSlider:SetAfterValueChanged(function(v) set('iconSize', v) end)
	sizeSlider:ClearAllPoints()
	Widgets.SetPoint(sizeSlider, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
	displayCardY = displayCardY - SLIDER_H - C.Spacing.normal

	-- Big Icon Size (debuffs only)
	if(opts.showBigIconSize) then
		local bigSlider = Widgets.CreateSlider(displayInner, 'Big Icon Size', widgetW, 8, 64, 1)
		bigSlider:SetValue(get('bigIconSize') or 22)
		bigSlider:SetAfterValueChanged(function(v) set('bigIconSize', v) end)
		bigSlider:ClearAllPoints()
		Widgets.SetPoint(bigSlider, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
		displayCardY = displayCardY - SLIDER_H - C.Spacing.normal
	end

	-- Max Displayed
	local maxSlider = Widgets.CreateSlider(displayInner, 'Max Displayed', widgetW, 1, 20, 1)
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
	local oriLabel, oriLabelH = Widgets.CreateHeading(displayInner, 'Orientation', 4)
	oriLabel:ClearAllPoints()
	Widgets.SetPoint(oriLabel, 'TOPLEFT', displayInner, 'TOPLEFT', 0, displayCardY)
	displayCardY = displayCardY - oriLabelH

	local oriDD = Widgets.CreateDropdown(displayInner, widgetW)
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

	yOffset = Widgets.EndCard(displayCard, parent, displayCardY)

	-- ── Position section ────────────────────────────────────
	yOffset = F.Settings.BuildPositionCard(parent, width, yOffset, get, set)

	-- ── Stack Font section ──────────────────────────────────
	yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Stack Count Font', 'stackFont', get, set, { showAnchor = true })

	-- ── Duration Font section ───────────────────────────────
	yOffset = F.Settings.BuildFontCard(parent, width, yOffset, 'Duration Text Font', 'durationFont', get, set, { showAnchor = true })

	return yOffset
end
