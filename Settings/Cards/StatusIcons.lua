local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}

-- ============================================================
-- Shared: icon section builder + reflow
-- Used by GroupIcons, StatusIcons, and Markers cards.
-- ============================================================

local ANCHOR_PICKER_H = 110 -- AnchorPicker with X/Y sliders (grid 52 + gap 6 + slider 26 + gap 6 + slider 26)
local SIZE_SLIDER_H   = B.SLIDER_H

local ICON_RELEVANCE = {
	player       = { combat = true, resting = true, raidIcon = true, pvp = true },
	target       = { combat = true, raidIcon = true, pvp = true },
	targettarget = { combat = true, raidIcon = true },
	focus        = { combat = true, raidIcon = true, pvp = true },
	pet          = { combat = true, raidIcon = true },
	party        = { role = true, leader = true, readyCheck = true, combat = true, phase = true, resurrect = true, summon = true, raidIcon = true, pvp = true },
	raid         = { role = true, leader = true, raidRole = true, readyCheck = true, combat = true, phase = true, resurrect = true, summon = true, raidIcon = true, pvp = true },
	boss         = { raidIcon = true },
	arena        = { role = true, combat = true, raidIcon = true, pvp = true },
}

local function isIconRelevant(unitType, iconKey)
	local map = ICON_RELEVANCE[unitType]
	if(not map) then return true end
	return map[iconKey] or false
end

local function buildIconSection(inner, widgetW, label, iconKey, defaultOn, getConfig, setConfig, reflowRef)
	local check = Widgets.CreateCheckButton(inner, label, function(checked)
		setConfig('statusIcons.' .. iconKey, checked)
		if(reflowRef[1]) then reflowRef[1]() end
	end)
	local savedVal = getConfig('statusIcons.' .. iconKey)
	if(savedVal == nil) then savedVal = defaultOn end
	check:SetChecked(savedVal)

	local picker = Widgets.CreateAnchorPicker(inner, widgetW)
	local savedPoint = getConfig('statusIcons.' .. iconKey .. 'Point')
	local savedX     = getConfig('statusIcons.' .. iconKey .. 'X')
	local savedY     = getConfig('statusIcons.' .. iconKey .. 'Y')
	picker:SetAnchor(savedPoint, savedX, savedY)
	picker:SetOnChanged(function(point, x, y)
		setConfig('statusIcons.' .. iconKey .. 'Point', point)
		setConfig('statusIcons.' .. iconKey .. 'X', x)
		setConfig('statusIcons.' .. iconKey .. 'Y', y)
	end)

	local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', widgetW, 4, 32, 1)
	sizeSlider:SetValue(getConfig('statusIcons.' .. iconKey .. 'Size'))
	sizeSlider:SetAfterValueChanged(function(value)
		setConfig('statusIcons.' .. iconKey .. 'Size', value)
	end)

	return {
		key        = iconKey,
		check      = check,
		picker     = picker,
		sizeSlider = sizeSlider,
		extras     = {},
	}
end

--- Build filtered icon sections for a set of icon definitions.
--- @param defs table Array of { label, iconKey, defaultOn }
--- @param unitType string
--- @param inner Frame
--- @param widgetW number
--- @param getConfig function
--- @param setConfig function
--- @param reflowRef table
--- @param existingSections? table Keyed by iconKey, reuse if present
local function buildFilteredSections(defs, unitType, inner, widgetW, getConfig, setConfig, reflowRef, existingSections)
	local items = {}
	for _, def in next, defs do
		if(isIconRelevant(unitType, def[2])) then
			if(existingSections and existingSections[def[2]]) then
				items[#items + 1] = existingSections[def[2]]
			else
				items[#items + 1] = buildIconSection(inner, widgetW, def[1], def[2], def[3], getConfig, setConfig, reflowRef)
			end
		end
	end
	return items
end

--- Shared reflow: positions sections with H3 heading per icon, collapsible sub-controls.
local function reflowIconSections(sections, inner, card, parent, initialized, onResize)
	local y = 0

	for _, sec in next, sections do
		local enabled = sec.check:GetChecked()

		sec.check:ClearAllPoints()
		Widgets.SetPoint(sec.check, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.CHECK_H - C.Spacing.normal

		if(enabled) then
			sec.picker:Show()
			sec.picker:ClearAllPoints()
			Widgets.SetPoint(sec.picker, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - ANCHOR_PICKER_H - C.Spacing.normal

			sec.sizeSlider:Show()
			sec.sizeSlider:ClearAllPoints()
			Widgets.SetPoint(sec.sizeSlider, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - SIZE_SLIDER_H - C.Spacing.normal

			for _, extra in next, sec.extras do
				extra.widget:Show()
				extra.widget:ClearAllPoints()
				Widgets.SetPoint(extra.widget, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
				y = y - extra.height - C.Spacing.normal
			end
		else
			sec.picker:Hide()
			sec.sizeSlider:Hide()
			for _, extra in next, sec.extras do
				extra.widget:Hide()
			end
		end
	end

	return y
end

-- ============================================================
-- Group Icons Card (party/raid/arena only)
-- Role, Leader, Raid Role + Role Style dropdown
-- ============================================================

local GROUP_ICON_DEFS = {
	{ 'Show Role Icon',      'role',     true },
	{ 'Show Leader Icon',    'leader',   true },
	{ 'Show Raid Role Icon', 'raidRole', false },
}

function F.SettingsCards.GroupIcons(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local reflowRef = {}
	local existing = {}

	-- Build role section first so we can attach extras
	if(isIconRelevant(unitType, 'role')) then
		local roleSection = buildIconSection(inner, widgetW, 'Show Role Icon', 'role', true, getConfig, setConfig, reflowRef)
		existing['role'] = roleSection

		-- Role style dropdown with icon previews
		local RoleIcon = F.Elements.RoleIcon
		local oUF = F.oUF
		local ICON_SIZE = 14
		local ICON_GAP = 2
		local TC = RoleIcon.TEXCOORDS
		local PREVIEW_ROLES = { 'TANK', 'HEALER', 'DAMAGER' }

		local roleStyleLabel = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
		roleStyleLabel:SetText('Role Icon Style')

		local function decorateRoleRow(row, item)
			if(not row._roleIcons) then
				row._roleIcons = {}
				row._customDecorations = row._customDecorations or {}
				local iconX = 4
				for j = 1, 3 do
					local icon = row:CreateTexture(nil, 'ARTWORK')
					icon:SetSize(ICON_SIZE, ICON_SIZE)
					icon:SetPoint('LEFT', row, 'LEFT', iconX, 0)
					row._roleIcons[j] = icon
					row._customDecorations[#row._customDecorations + 1] = icon
					iconX = iconX + ICON_SIZE + ICON_GAP
				end
			end
			local texPath = RoleIcon.GetTexturePath(item.value)
			for j, role in next, PREVIEW_ROLES do
				local icon = row._roleIcons[j]
				icon:SetTexture(texPath)
				local tc = TC[role]
				icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
				icon:Show()
			end
			local labelOffset = 4 + 3 * (ICON_SIZE + ICON_GAP) + 4
			row._label:SetPoint('LEFT', row, 'LEFT', labelOffset, 0)
		end

		local roleStyleItems = {
			{ text = 'Style 1', value = 2, _decorateRow = decorateRoleRow },
			{ text = 'Style 2', value = 3, _decorateRow = decorateRoleRow },
			{ text = 'Style 3', value = 4, _decorateRow = decorateRoleRow },
			{ text = 'Style 4', value = 5, _decorateRow = decorateRoleRow },
			{ text = 'Style 5', value = 6, _decorateRow = decorateRoleRow },
			{ text = 'Style 6', value = 7, _decorateRow = decorateRoleRow },
		}
		local roleStyleDD = Widgets.CreateDropdown(inner, widgetW)

		local btnIcons = {}
		local btnIconX = 6
		for j = 1, 3 do
			local icon = roleStyleDD:CreateTexture(nil, 'ARTWORK')
			icon:SetSize(ICON_SIZE, ICON_SIZE)
			icon:SetPoint('LEFT', roleStyleDD, 'LEFT', btnIconX, 0)
			btnIcons[j] = icon
			btnIconX = btnIconX + ICON_SIZE + ICON_GAP
		end
		local btnLabelOffset = btnIconX + 4
		roleStyleDD._label:SetPoint('LEFT', roleStyleDD, 'LEFT', btnLabelOffset, 0)

		local function updateButtonIcons(style)
			local texPath = RoleIcon.GetTexturePath(style)
			for j, role in next, PREVIEW_ROLES do
				local icon = btnIcons[j]
				icon:SetTexture(texPath)
				local tc = TC[role]
				icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
			end
		end

		roleStyleDD:SetItems(roleStyleItems)
		local currentStyle = F.Config:Get('general.roleIconStyle')
		roleStyleDD:SetValue(currentStyle)
		updateButtonIcons(currentStyle)
		roleStyleDD:SetOnSelect(function(value)
			F.Config:Set('general.roleIconStyle', value)
			updateButtonIcons(value)
			if(oUF and oUF.objects) then
				for _, frame in next, oUF.objects do
					local element = frame.GroupRoleIndicator
					if(element and element.ForceUpdate) then
						element:ForceUpdate()
					end
				end
			end
		end)

		roleSection.extras = {
			{ widget = roleStyleLabel, height = C.Font.sizeSmall + 2 },
			{ widget = roleStyleDD,    height = B.DROPDOWN_H },
		}
	end

	local sections = buildFilteredSections(GROUP_ICON_DEFS, unitType, inner, widgetW, getConfig, setConfig, reflowRef, existing)

	local initialized = false
	local function reflowCard()
		local y = reflowIconSections(sections, inner, card, parent, initialized, onResize)
		Widgets.EndCard(card, parent, y)
		if(initialized and onResize) then onResize() end
	end

	reflowRef[1] = reflowCard
	reflowCard()
	initialized = true

	return card
end

-- ============================================================
-- Status Icons Card
-- Ready Check, Combat, Resting, Phase, Resurrect, Summon
-- + Status Text toggle (group frames only)
-- ============================================================

local STATUS_ICON_DEFS = {
	{ 'Show Ready Check',    'readyCheck', true },
	{ 'Show Combat Icon',    'combat',     false },
	{ 'Show Resting Icon',   'resting',    false },
	{ 'Show Phase Icon',     'phase',      false },
	{ 'Show Resurrect Icon', 'resurrect',  false },
	{ 'Show Summon Icon',    'summon',      false },
}

function F.SettingsCards.StatusIcons(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local reflowRef = {}
	local sections = buildFilteredSections(STATUS_ICON_DEFS, unitType, inner, widgetW, getConfig, setConfig, reflowRef)

	local initialized = false
	local function reflowCard()
		local y = reflowIconSections(sections, inner, card, parent, initialized, onResize)

		Widgets.EndCard(card, parent, y)
		if(initialized and onResize) then onResize() end
	end

	reflowRef[1] = reflowCard
	reflowCard()
	initialized = true

	return card
end

-- ============================================================
-- Markers Card
-- Raid Icon, PvP
-- ============================================================

local MARKER_ICON_DEFS = {
	{ 'Show Raid Icon', 'raidIcon', true },
	{ 'Show PvP Icon',  'pvp',      false },
}

function F.SettingsCards.Markers(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	local reflowRef = {}
	local sections = buildFilteredSections(MARKER_ICON_DEFS, unitType, inner, widgetW, getConfig, setConfig, reflowRef)

	local initialized = false
	local function reflowCard()
		local y = reflowIconSections(sections, inner, card, parent, initialized, onResize)
		Widgets.EndCard(card, parent, y)
		if(initialized and onResize) then onResize() end
	end

	reflowRef[1] = reflowCard
	reflowCard()
	initialized = true

	return card
end
