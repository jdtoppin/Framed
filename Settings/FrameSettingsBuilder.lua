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
-- Section helpers
-- ============================================================

--- Create a titled section pane, position it, and return it
--- along with the updated yOffset below the pane title.
--- @param content Frame     Scroll content frame
--- @param title   string    Section title (will be uppercased)
--- @param width   number    Available content width
--- @param yOffset number    Current running yOffset
--- @return Frame pane, number newYOffset
local function createSection(content, title, width, yOffset)
	local pane = Widgets.CreateTitledPane(content, title, width)
	pane:ClearAllPoints()
	Widgets.SetPoint(pane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	-- Advance past title + separator (PANE_TITLE_H) + one normal gap
	return pane, yOffset - PANE_TITLE_H - C.Spacing.normal
end

--- Place a widget inside a section pane at the running yOffset.
--- Returns the next yOffset after accounting for the widget's height.
--- @param widget  Frame   Widget to position
--- @param pane    Frame   Parent pane
--- @param yOffset number  Running yOffset (negative, relative to content)
--- @param height  number  Widget height
--- @return number nextYOffset
local function placeWidget(widget, pane, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', pane, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
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

	-- ── Config accessor helpers ────────────────────────────────
	local layoutName = F.AutoSwitch and F.AutoSwitch.GetCurrentLayout() or 'Default Solo'

	local function getConfig(key)
		return F.Config:Get('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. key)
	end
	local function setConfig(key, value)
		F.Config:Set('layouts.' .. layoutName .. '.unitConfigs.' .. unitType .. '.' .. key, value)
	end

	-- Running layout cursor (negative = downward from TOPLEFT)
	local yOffset = -C.Spacing.normal

	-- ============================================================
	-- Section: Frame
	-- ============================================================

	local framePane
	framePane, yOffset = createSection(content, 'Frame', width, yOffset)

	-- Width slider
	local widthSlider = Widgets.CreateSlider(content, 'Width', WIDGET_W, 20, 300, 1)
	widthSlider:SetValue(getConfig('width') or 200)
	widthSlider:SetAfterValueChanged(function(value)
		setConfig('width', value)
	end)
	yOffset = placeWidget(widthSlider, framePane, yOffset, SLIDER_H)

	-- Height slider
	local heightSlider = Widgets.CreateSlider(content, 'Height', WIDGET_W, 16, 100, 1)
	heightSlider:SetValue(getConfig('height') or 36)
	heightSlider:SetAfterValueChanged(function(value)
		setConfig('height', value)
	end)
	yOffset = placeWidget(heightSlider, framePane, yOffset, SLIDER_H)

	if(isGroup) then
		-- Spacing slider
		local spacingSlider = Widgets.CreateSlider(content, 'Spacing', WIDGET_W, 0, 20, 1)
		spacingSlider:SetValue(getConfig('spacing') or 2)
		spacingSlider:SetAfterValueChanged(function(value)
			setConfig('spacing', value)
		end)
		yOffset = placeWidget(spacingSlider, framePane, yOffset, SLIDER_H)

		-- Orientation switch
		local orientSwitch = Widgets.CreateSwitch(content, WIDGET_W, SWITCH_H, {
			{ text = 'Vertical',   value = 'Vertical' },
			{ text = 'Horizontal', value = 'Horizontal' },
		})
		orientSwitch:SetValue(getConfig('orientation') or 'Vertical')
		orientSwitch:SetOnSelect(function(value)
			setConfig('orientation', value)
		end)
		yOffset = placeWidget(orientSwitch, framePane, yOffset, SWITCH_H)

		-- Growth direction dropdown
		local growthDropdown = Widgets.CreateDropdown(content, WIDGET_W)
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
		yOffset = placeWidget(growthDropdown, framePane, yOffset, DROPDOWN_H)
	end

	-- ============================================================
	-- Section: Bars
	-- ============================================================

	local barsPane
	barsPane, yOffset = createSection(content, 'Bars', width, yOffset)

	-- Health color mode switch
	local healthColorSwitch = Widgets.CreateSwitch(content, WIDGET_W, SWITCH_H, {
		{ text = 'Class',    value = 'Class' },
		{ text = 'Gradient', value = 'Gradient' },
		{ text = 'Custom',   value = 'Custom' },
	})
	healthColorSwitch:SetValue(getConfig('healthColorMode') or 'Class')
	healthColorSwitch:SetOnSelect(function(value)
		setConfig('healthColorMode', value)
	end)
	yOffset = placeWidget(healthColorSwitch, barsPane, yOffset, SWITCH_H)

	-- Smooth interpolation checkbox
	local smoothCheck = Widgets.CreateCheckButton(content, 'Smooth Interpolation')
	smoothCheck:SetChecked(getConfig('smoothHealth') ~= false)
	smoothCheck._callback = function(checked)
		setConfig('smoothHealth', checked)
	end
	yOffset = placeWidget(smoothCheck, barsPane, yOffset, CHECK_H)

	-- Show power bar checkbox
	local showPowerCheck = Widgets.CreateCheckButton(content, 'Show Power Bar')
	showPowerCheck:SetChecked(getConfig('showPower') ~= false)
	showPowerCheck._callback = function(checked)
		setConfig('showPower', checked)
	end
	yOffset = placeWidget(showPowerCheck, barsPane, yOffset, CHECK_H)

	-- Power bar height slider
	local powerHeightSlider = Widgets.CreateSlider(content, 'Power Bar Height', WIDGET_W, 1, 20, 1)
	powerHeightSlider:SetValue(getConfig('powerHeight') or 4)
	powerHeightSlider:SetAfterValueChanged(function(value)
		setConfig('powerHeight', value)
	end)
	yOffset = placeWidget(powerHeightSlider, barsPane, yOffset, SLIDER_H)

	-- Show cast bar checkbox
	local showCastCheck = Widgets.CreateCheckButton(content, 'Show Cast Bar')
	showCastCheck:SetChecked(getConfig('showCastBar') ~= false)
	showCastCheck._callback = function(checked)
		setConfig('showCastBar', checked)
	end
	yOffset = placeWidget(showCastCheck, barsPane, yOffset, CHECK_H)

	-- Show absorb bar checkbox
	local showAbsorbCheck = Widgets.CreateCheckButton(content, 'Show Absorb Bar')
	showAbsorbCheck:SetChecked(getConfig('showAbsorbBar') ~= false)
	showAbsorbCheck._callback = function(checked)
		setConfig('showAbsorbBar', checked)
	end
	yOffset = placeWidget(showAbsorbCheck, barsPane, yOffset, CHECK_H)

	-- ============================================================
	-- Section: Text
	-- ============================================================

	local textPane
	textPane, yOffset = createSection(content, 'Text', width, yOffset)

	-- Show name checkbox
	local showNameCheck = Widgets.CreateCheckButton(content, 'Show Name')
	showNameCheck:SetChecked(getConfig('showName') ~= false)
	showNameCheck._callback = function(checked)
		setConfig('showName', checked)
	end
	yOffset = placeWidget(showNameCheck, textPane, yOffset, CHECK_H)

	-- Name color mode switch
	local nameColorSwitch = Widgets.CreateSwitch(content, WIDGET_W, SWITCH_H, {
		{ text = 'Class',  value = 'Class' },
		{ text = 'White',  value = 'White' },
		{ text = 'Custom', value = 'Custom' },
	})
	nameColorSwitch:SetValue(getConfig('nameColorMode') or 'Class')
	nameColorSwitch:SetOnSelect(function(value)
		setConfig('nameColorMode', value)
	end)
	yOffset = placeWidget(nameColorSwitch, textPane, yOffset, SWITCH_H)

	-- Name truncation slider
	local nameTruncSlider = Widgets.CreateSlider(content, 'Name Truncation', WIDGET_W, 4, 20, 1)
	nameTruncSlider:SetValue(getConfig('nameTruncation') or 10)
	nameTruncSlider:SetAfterValueChanged(function(value)
		setConfig('nameTruncation', value)
	end)
	yOffset = placeWidget(nameTruncSlider, textPane, yOffset, SLIDER_H)

	-- Show health text checkbox
	local showHealthTextCheck = Widgets.CreateCheckButton(content, 'Show Health Text')
	showHealthTextCheck:SetChecked(getConfig('showHealthText') ~= false)
	showHealthTextCheck._callback = function(checked)
		setConfig('showHealthText', checked)
	end
	yOffset = placeWidget(showHealthTextCheck, textPane, yOffset, CHECK_H)

	-- Health text format dropdown
	local healthFormatDropdown = Widgets.CreateDropdown(content, WIDGET_W)
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
	yOffset = placeWidget(healthFormatDropdown, textPane, yOffset, DROPDOWN_H)

	-- Show power text checkbox
	local showPowerTextCheck = Widgets.CreateCheckButton(content, 'Show Power Text')
	showPowerTextCheck:SetChecked(getConfig('showPowerText') or false)
	showPowerTextCheck._callback = function(checked)
		setConfig('showPowerText', checked)
	end
	yOffset = placeWidget(showPowerTextCheck, textPane, yOffset, CHECK_H)

	-- ============================================================
	-- Section: Icons
	-- ============================================================

	local iconsPane
	iconsPane, yOffset = createSection(content, 'Icons', width, yOffset)

	-- Show role icon checkbox
	local showRoleCheck = Widgets.CreateCheckButton(content, 'Show Role Icon')
	showRoleCheck:SetChecked(getConfig('showRoleIcon') ~= false)
	showRoleCheck._callback = function(checked)
		setConfig('showRoleIcon', checked)
	end
	yOffset = placeWidget(showRoleCheck, iconsPane, yOffset, CHECK_H)

	-- Show leader icon checkbox
	local showLeaderCheck = Widgets.CreateCheckButton(content, 'Show Leader Icon')
	showLeaderCheck:SetChecked(getConfig('showLeaderIcon') ~= false)
	showLeaderCheck._callback = function(checked)
		setConfig('showLeaderIcon', checked)
	end
	yOffset = placeWidget(showLeaderCheck, iconsPane, yOffset, CHECK_H)

	-- Show ready check checkbox
	local showReadyCheckCheck = Widgets.CreateCheckButton(content, 'Show Ready Check')
	showReadyCheckCheck:SetChecked(getConfig('showReadyCheck') ~= false)
	showReadyCheckCheck._callback = function(checked)
		setConfig('showReadyCheck', checked)
	end
	yOffset = placeWidget(showReadyCheckCheck, iconsPane, yOffset, CHECK_H)

	-- Show raid icon checkbox
	local showRaidIconCheck = Widgets.CreateCheckButton(content, 'Show Raid Icon')
	showRaidIconCheck:SetChecked(getConfig('showRaidIcon') ~= false)
	showRaidIconCheck._callback = function(checked)
		setConfig('showRaidIcon', checked)
	end
	yOffset = placeWidget(showRaidIconCheck, iconsPane, yOffset, CHECK_H)

	-- Show combat icon checkbox
	local showCombatIconCheck = Widgets.CreateCheckButton(content, 'Show Combat Icon')
	showCombatIconCheck:SetChecked(getConfig('showCombatIcon') or false)
	showCombatIconCheck._callback = function(checked)
		setConfig('showCombatIcon', checked)
	end
	yOffset = placeWidget(showCombatIconCheck, iconsPane, yOffset, CHECK_H)

	-- ── Resize content to fit all widgets ─────────────────────
	local totalH = math.abs(yOffset) + C.Spacing.normal
	content:SetHeight(totalH)

	return scroll
end
