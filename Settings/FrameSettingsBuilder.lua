local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- FrameSettingsBuilder
-- Shared factory that builds a scrollable settings panel for a
-- given unit type. Called by each thin panel registration file.
-- Group types (party/raid/battleground/worldraid) show extra
-- group-specific fields (spacing, orientation, growth direction).
-- ============================================================

F.FrameSettingsBuilder = {}

-- ============================================================
-- Constants
-- ============================================================

local GROUP_TYPES = {
	party        = true,
	raid         = true,
	battleground = true,
	worldraid    = true,
}

-- Widget heights (used for vertical layout accounting)
local SLIDER_H       = 26   -- labelH(14) + TRACK_THICKNESS(6) + 6
local SWITCH_H       = 22
local DROPDOWN_H     = 22
local CHECK_H        = 14
local PANE_TITLE_H   = 20   -- approx title font + separator + gap

-- Width for sliders and dropdowns inside the panel
local WIDGET_W       = 220

-- ============================================================
-- Layout helpers
-- ============================================================

--- Place a widget at the running yOffset, anchored to the scroll content frame.
--- Returns the next yOffset after accounting for the widget's height.
--- @param widget  Frame   Widget to position
--- @param content Frame   Scroll content frame
--- @param yOffset number  Running yOffset (negative, relative to content)
--- @param height  number  Widget height
--- @return number nextYOffset
local function placeWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

--- Place a heading at the given level and return the updated yOffset.
--- @param content Frame   Scroll content frame
--- @param text    string  Heading text
--- @param level   number  1, 2, or 3
--- @param yOffset number  Running yOffset
--- @param width?  number  Available width (needed for level 1 separator)
--- @return number nextYOffset
local function placeHeading(content, text, level, yOffset, width)
	local heading, height = Widgets.CreateHeading(content, text, level, width)
	heading:ClearAllPoints()
	Widgets.SetPoint(heading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height
end

-- ============================================================
-- FrameSettingsBuilder.Create
-- ============================================================

--- Build and return a scrollable settings panel for unitType.
--- @param parent   Frame   Content parent provided by Settings.RegisterPanel
--- @param unitType string  Unit identifier (e.g. 'player', 'party', 'raid')
--- @return Frame
function F.FrameSettingsBuilder.Create(parent, unitType)
	local isGroup = GROUP_TYPES[unitType] or false

	-- ── Scroll frame wrapping the whole panel ─────────────────
	local parentW = parent._explicitWidth or parent:GetWidth() or 530
	local parentH = parent._explicitHeight or parent:GetHeight() or 400
	local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
	scroll:SetAllPoints(parent)

	local content = scroll:GetContentFrame()
	content:SetWidth(parentW)
	local width = parentW - C.Spacing.normal * 2

	-- Tag scroll frame with the preset it was built for (used by callers for invalidation)
	scroll._builtForPreset = F.Settings.GetEditingPreset()

	-- ── Config accessor helpers ────────────────────────────────
	local function getPresetName()
		return F.Settings.GetEditingPreset()
	end

	local function getConfig(key)
		return F.Config:Get('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key)
	end
	local function setConfig(key, value)
		F.Config:Set('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key, value)
		F.PresetManager.MarkCustomized(getPresetName())
	end

	-- Running layout cursor (negative = downward from TOPLEFT)
	local yOffset = -C.Spacing.normal

	-- ── Scoped preset banner ───────────────────────────────────
	local banner = Widgets.CreateFontString(content, C.Font.sizeSmall, C.Colors.accent)
	banner:SetText('These settings apply to: ' .. getPresetName() .. ' Frame Preset')
	Widgets.SetPoint(banner, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	yOffset = yOffset - 16 - C.Spacing.tight

	-- ============================================================
	-- Frame Size
	-- ============================================================

	yOffset = placeHeading(content, 'Frame Size', 2, yOffset)

	local sizeCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	-- Width slider
	local widthSlider = Widgets.CreateSlider(inner, 'Width', WIDGET_W, 20, 300, 1)
	widthSlider:SetValue(getConfig('width') or 200)
	widthSlider:SetAfterValueChanged(function(value)
		setConfig('width', value)
	end)
	cardY = placeWidget(widthSlider, inner, cardY, SLIDER_H)

	-- Height slider
	local heightSlider = Widgets.CreateSlider(inner, 'Height', WIDGET_W, 16, 100, 1)
	heightSlider:SetValue(getConfig('height') or 36)
	heightSlider:SetAfterValueChanged(function(value)
		setConfig('height', value)
	end)
	cardY = placeWidget(heightSlider, inner, cardY, SLIDER_H)

	yOffset = Widgets.EndCard(sizeCard, content, cardY)

	if(isGroup) then
		-- ── Group Layout ──────────────────────────────────────
		yOffset = placeHeading(content, 'Group Layout', 2, yOffset)

		local groupCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

		-- Spacing slider
		local spacingSlider = Widgets.CreateSlider(inner, 'Spacing', WIDGET_W, 0, 20, 1)
		spacingSlider:SetValue(getConfig('spacing') or 2)
		spacingSlider:SetAfterValueChanged(function(value)
			setConfig('spacing', value)
		end)
		cardY = placeWidget(spacingSlider, inner, cardY, SLIDER_H)

		-- Orientation switch
		cardY = placeHeading(inner, 'Orientation', 3, cardY)
		local orientSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
			{ text = 'Vertical',   value = 'Vertical' },
			{ text = 'Horizontal', value = 'Horizontal' },
		})
		orientSwitch:SetValue(getConfig('orientation') or 'Vertical')
		orientSwitch:SetOnSelect(function(value)
			setConfig('orientation', value)
		end)
		cardY = placeWidget(orientSwitch, inner, cardY, SWITCH_H)

		-- Growth direction dropdown
		cardY = placeHeading(inner, 'Growth Direction', 3, cardY)
		local growthDropdown = Widgets.CreateDropdown(inner, WIDGET_W)
		growthDropdown:SetItems({
			{ text = 'Top to Bottom',  value = 'TOP_TO_BOTTOM' },
			{ text = 'Bottom to Top',  value = 'BOTTOM_TO_TOP' },
			{ text = 'Left to Right',  value = 'LEFT_TO_RIGHT' },
			{ text = 'Right to Left',  value = 'RIGHT_TO_LEFT' },
		})
		growthDropdown:SetValue(getConfig('growthDirection') or 'TOP_TO_BOTTOM')
		growthDropdown:SetOnSelect(function(value)
			setConfig('growthDirection', value)
		end)
		cardY = placeWidget(growthDropdown, inner, cardY, DROPDOWN_H)

		yOffset = Widgets.EndCard(groupCard, content, cardY)
	end

	-- ============================================================
	-- Health Color
	-- ============================================================

	yOffset = placeHeading(content, 'Health Color', 2, yOffset)

	local colorCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	-- Health color mode switch
	cardY = placeHeading(inner, 'Color Mode', 3, cardY)
	local healthColorSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
		{ text = 'Class',    value = 'Class' },
		{ text = 'Gradient', value = 'Gradient' },
		{ text = 'Custom',   value = 'Custom' },
	})
	healthColorSwitch:SetValue(getConfig('healthColorMode') or 'Class')
	healthColorSwitch:SetOnSelect(function(value)
		setConfig('healthColorMode', value)
	end)
	cardY = placeWidget(healthColorSwitch, inner, cardY, SWITCH_H)

	-- Smooth interpolation checkbox
	local smoothCheck = Widgets.CreateCheckButton(inner, 'Smooth Interpolation')
	smoothCheck:SetChecked(getConfig('smoothHealth') ~= false)
	smoothCheck._callback = function(checked)
		setConfig('smoothHealth', checked)
	end
	cardY = placeWidget(smoothCheck, inner, cardY, CHECK_H)

	yOffset = Widgets.EndCard(colorCard, content, cardY)

	-- ── Power Bar ─────────────────────────────────────────────
	yOffset = placeHeading(content, 'Power Bar', 2, yOffset)

	local powerCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	local showPowerCheck = Widgets.CreateCheckButton(inner, 'Show Power Bar')
	showPowerCheck:SetChecked(getConfig('showPower') ~= false)
	showPowerCheck._callback = function(checked)
		setConfig('showPower', checked)
	end
	cardY = placeWidget(showPowerCheck, inner, cardY, CHECK_H)

	-- Power bar height slider
	local powerHeightSlider = Widgets.CreateSlider(inner, 'Power Bar Height', WIDGET_W, 1, 20, 1)
	powerHeightSlider:SetValue(getConfig('powerHeight') or 4)
	powerHeightSlider:SetAfterValueChanged(function(value)
		setConfig('powerHeight', value)
	end)
	cardY = placeWidget(powerHeightSlider, inner, cardY, SLIDER_H)

	yOffset = Widgets.EndCard(powerCard, content, cardY)

	-- ── Card: Cast Bar ────────────────────────────────────────
	yOffset = placeHeading(content, 'Cast Bar', 2, yOffset)

	local castCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	local showCastCheck = Widgets.CreateCheckButton(inner, 'Show Cast Bar')
	showCastCheck:SetChecked(getConfig('showCastBar') ~= false)
	showCastCheck._callback = function(checked)
		setConfig('showCastBar', checked)
	end
	cardY = placeWidget(showCastCheck, inner, cardY, CHECK_H)

	-- Show absorb bar checkbox
	local showAbsorbCheck = Widgets.CreateCheckButton(inner, 'Show Absorb Bar')
	showAbsorbCheck:SetChecked(getConfig('showAbsorbBar') ~= false)
	showAbsorbCheck._callback = function(checked)
		setConfig('showAbsorbBar', checked)
	end
	cardY = placeWidget(showAbsorbCheck, inner, cardY, CHECK_H)

	yOffset = Widgets.EndCard(castCard, content, cardY)

	-- ── Name ──────────────────────────────────────────────────
	yOffset = placeHeading(content, 'Name', 2, yOffset)

	local nameCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	local showNameCheck = Widgets.CreateCheckButton(inner, 'Show Name')
	showNameCheck:SetChecked(getConfig('showName') ~= false)
	showNameCheck._callback = function(checked)
		setConfig('showName', checked)
	end
	cardY = placeWidget(showNameCheck, inner, cardY, CHECK_H)

	-- Name color mode switch
	cardY = placeHeading(inner, 'Name Color', 3, cardY)
	local nameColorSwitch = Widgets.CreateSwitch(inner, WIDGET_W, SWITCH_H, {
		{ text = 'Class',  value = 'Class' },
		{ text = 'White',  value = 'White' },
		{ text = 'Custom', value = 'Custom' },
	})
	nameColorSwitch:SetValue(getConfig('nameColorMode') or 'Class')
	nameColorSwitch:SetOnSelect(function(value)
		setConfig('nameColorMode', value)
	end)
	cardY = placeWidget(nameColorSwitch, inner, cardY, SWITCH_H)

	-- Name truncation slider
	local nameTruncSlider = Widgets.CreateSlider(inner, 'Name Truncation', WIDGET_W, 4, 20, 1)
	nameTruncSlider:SetValue(getConfig('nameTruncation') or 10)
	nameTruncSlider:SetAfterValueChanged(function(value)
		setConfig('nameTruncation', value)
	end)
	cardY = placeWidget(nameTruncSlider, inner, cardY, SLIDER_H)

	yOffset = Widgets.EndCard(nameCard, content, cardY)

	-- ── Card: Health Text ─────────────────────────────────────
	yOffset = placeHeading(content, 'Health Text', 2, yOffset)

	local healthTextCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	local showHealthTextCheck = Widgets.CreateCheckButton(inner, 'Show Health Text')
	showHealthTextCheck:SetChecked(getConfig('showHealthText') ~= false)
	showHealthTextCheck._callback = function(checked)
		setConfig('showHealthText', checked)
	end
	cardY = placeWidget(showHealthTextCheck, inner, cardY, CHECK_H)

	-- Health text format dropdown
	cardY = placeHeading(inner, 'Health Text Format', 3, cardY)
	local healthFormatDropdown = Widgets.CreateDropdown(inner, WIDGET_W)
	healthFormatDropdown:SetItems({
		{ text = 'Percentage',   value = 'Percentage' },
		{ text = 'Current',      value = 'Current' },
		{ text = 'Deficit',      value = 'Deficit' },
		{ text = 'Current-Max',  value = 'CurrentMax' },
		{ text = 'None',         value = 'None' },
	})
	healthFormatDropdown:SetValue(getConfig('healthTextFormat') or 'Percentage')
	healthFormatDropdown:SetOnSelect(function(value)
		setConfig('healthTextFormat', value)
	end)
	cardY = placeWidget(healthFormatDropdown, inner, cardY, DROPDOWN_H)

	-- Show power text checkbox
	local showPowerTextCheck = Widgets.CreateCheckButton(inner, 'Show Power Text')
	showPowerTextCheck:SetChecked(getConfig('showPowerText') or false)
	showPowerTextCheck._callback = function(checked)
		setConfig('showPowerText', checked)
	end
	cardY = placeWidget(showPowerTextCheck, inner, cardY, CHECK_H)

	yOffset = Widgets.EndCard(healthTextCard, content, cardY)

	-- ── Status Icons ──────────────────────────────────────────
	yOffset = placeHeading(content, 'Status Icons', 2, yOffset)

	local iconsCard, inner, cardY = Widgets.StartCard(content, width, yOffset)

	-- Show role icon checkbox
	local showRoleCheck = Widgets.CreateCheckButton(inner, 'Show Role Icon')
	showRoleCheck:SetChecked(getConfig('showRoleIcon') ~= false)
	showRoleCheck._callback = function(checked)
		setConfig('showRoleIcon', checked)
	end
	cardY = placeWidget(showRoleCheck, inner, cardY, CHECK_H)

	-- Show leader icon checkbox
	local showLeaderCheck = Widgets.CreateCheckButton(inner, 'Show Leader Icon')
	showLeaderCheck:SetChecked(getConfig('showLeaderIcon') ~= false)
	showLeaderCheck._callback = function(checked)
		setConfig('showLeaderIcon', checked)
	end
	cardY = placeWidget(showLeaderCheck, inner, cardY, CHECK_H)

	-- Show ready check checkbox
	local showReadyCheckCheck = Widgets.CreateCheckButton(inner, 'Show Ready Check')
	showReadyCheckCheck:SetChecked(getConfig('showReadyCheck') ~= false)
	showReadyCheckCheck._callback = function(checked)
		setConfig('showReadyCheck', checked)
	end
	cardY = placeWidget(showReadyCheckCheck, inner, cardY, CHECK_H)

	-- Show raid icon checkbox
	local showRaidIconCheck = Widgets.CreateCheckButton(inner, 'Show Raid Icon')
	showRaidIconCheck:SetChecked(getConfig('showRaidIcon') ~= false)
	showRaidIconCheck._callback = function(checked)
		setConfig('showRaidIcon', checked)
	end
	cardY = placeWidget(showRaidIconCheck, inner, cardY, CHECK_H)

	-- Show combat icon checkbox
	local showCombatIconCheck = Widgets.CreateCheckButton(inner, 'Show Combat Icon')
	showCombatIconCheck:SetChecked(getConfig('showCombatIcon') or false)
	showCombatIconCheck._callback = function(checked)
		setConfig('showCombatIcon', checked)
	end
	cardY = placeWidget(showCombatIconCheck, inner, cardY, CHECK_H)

	yOffset = Widgets.EndCard(iconsCard, content, cardY)

	-- ── Resize content to fit all widgets ─────────────────────
	local totalH = math.abs(yOffset) + C.Spacing.normal
	content:SetHeight(totalH)

	-- ── Invalidate on preset change ────────────────────────────
	-- When the editing preset changes, mark this scroll frame stale so
	-- the Settings framework knows to rebuild on next panel activation.
	F.EventBus:Register('EDITING_PRESET_CHANGED', function(newPreset)
		scroll._builtForPreset = nil
	end, 'FrameSettingsBuilder.' .. unitType)

	return scroll
end
