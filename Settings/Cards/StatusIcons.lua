local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}

-- ============================================================
-- Icon section builder
-- Creates: checkbox + collapsible (anchor picker + size slider)
-- Returns table with widgets and heights for reflow.
-- ============================================================

local ANCHOR_PICKER_H = 110 -- AnchorPicker with X/Y sliders (grid 52 + gap 6 + slider 26 + gap 6 + slider 26)
local SIZE_SLIDER_H   = B.SLIDER_H

local function buildIconSection(inner, widgetW, label, iconKey, defaultOn, getConfig, setConfig, reflowRef)
	local defaults = F.StyleBuilder.ICON_DEFAULTS[iconKey]

	-- Checkbox — callback saves config AND triggers reflow
	local check = Widgets.CreateCheckButton(inner, label, function(checked)
		setConfig('statusIcons.' .. iconKey, checked)
		if(reflowRef[1]) then reflowRef[1]() end
	end)
	local savedVal = getConfig('statusIcons.' .. iconKey)
	if(savedVal == nil) then savedVal = defaultOn end
	check:SetChecked(savedVal)

	-- Anchor picker
	local picker = Widgets.CreateAnchorPicker(inner, widgetW)
	local savedPoint = getConfig('statusIcons.' .. iconKey .. 'Point') or defaults.point
	local savedX     = getConfig('statusIcons.' .. iconKey .. 'X')     or defaults.x
	local savedY     = getConfig('statusIcons.' .. iconKey .. 'Y')     or defaults.y
	picker:SetAnchor(savedPoint, savedX, savedY)
	picker:SetOnChanged(function(point, x, y)
		setConfig('statusIcons.' .. iconKey .. 'Point', point)
		setConfig('statusIcons.' .. iconKey .. 'X', x)
		setConfig('statusIcons.' .. iconKey .. 'Y', y)
	end)

	-- Size slider
	local sizeSlider = Widgets.CreateSlider(inner, 'Icon Size', widgetW, 4, 32, 1)
	sizeSlider:SetValue(getConfig('statusIcons.' .. iconKey .. 'Size') or defaults.size)
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

-- ============================================================
-- StatusIcons Card
-- ============================================================

function F.SettingsCards.StatusIcons(parent, width, unitType, getConfig, setConfig, onResize)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- ── Build all icon sections ──────────────────────────────

	local sections = {}
	local reflowRef = {}  -- indirection so builder can call reflow before it's defined

	-- Role icon (special: has style dropdown)
	local roleSection = buildIconSection(inner, widgetW, 'Show Role Icon', 'role', true, getConfig, setConfig, reflowRef)

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

	-- Add 3 role icon previews to the dropdown button face
	local btnIcons = {}
	local btnIconX = 6
	for j = 1, 3 do
		local icon = roleStyleDD:CreateTexture(nil, 'ARTWORK')
		icon:SetSize(ICON_SIZE, ICON_SIZE)
		icon:SetPoint('LEFT', roleStyleDD, 'LEFT', btnIconX, 0)
		btnIcons[j] = icon
		btnIconX = btnIconX + ICON_SIZE + ICON_GAP
	end
	-- Shift the label right to make room for the icons
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
	local currentStyle = (F.Config and F.Config:Get('general.roleIconStyle')) or 2
	roleStyleDD:SetValue(currentStyle)
	updateButtonIcons(currentStyle)
	roleStyleDD:SetOnSelect(function(value)
		if(F.Config) then F.Config:Set('general.roleIconStyle', value) end
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

	-- ── Group headings ──────────────────────────────────────
	local groupHeading, groupHeadingH   = Widgets.CreateHeading(inner, 'Group', 3)
	local statusHeading, statusHeadingH = Widgets.CreateHeading(inner, 'Status', 3)
	local markerHeading, markerHeadingH = Widgets.CreateHeading(inner, 'Markers', 3)

	-- ── Grouped sections ────────────────────────────────────

	-- Group icons
	local groups = {
		{
			heading = groupHeading, headingH = groupHeadingH,
			items = {
				roleSection,
				buildIconSection(inner, widgetW, 'Show Leader Icon', 'leader', true, getConfig, setConfig, reflowRef),
				buildIconSection(inner, widgetW, 'Show Raid Role Icon', 'raidRole', false, getConfig, setConfig, reflowRef),
			},
		},
		{
			heading = statusHeading, headingH = statusHeadingH,
			items = {
				buildIconSection(inner, widgetW, 'Show Ready Check', 'readyCheck', true, getConfig, setConfig, reflowRef),
				buildIconSection(inner, widgetW, 'Show Combat Icon', 'combat', false, getConfig, setConfig, reflowRef),
				buildIconSection(inner, widgetW, 'Show Resting Icon', 'resting', false, getConfig, setConfig, reflowRef),
				buildIconSection(inner, widgetW, 'Show Phase Icon', 'phase', false, getConfig, setConfig, reflowRef),
				buildIconSection(inner, widgetW, 'Show Resurrect Icon', 'resurrect', false, getConfig, setConfig, reflowRef),
				buildIconSection(inner, widgetW, 'Show Summon Icon', 'summon', false, getConfig, setConfig, reflowRef),
			},
		},
		{
			heading = markerHeading, headingH = markerHeadingH,
			items = {
				buildIconSection(inner, widgetW, 'Show Raid Icon', 'raidIcon', true, getConfig, setConfig, reflowRef),
				buildIconSection(inner, widgetW, 'Show PvP Icon', 'pvp', false, getConfig, setConfig, reflowRef),
			},
		},
	}

	-- Flatten into sections for reflow (preserves group order)
	for _, group in next, groups do
		for _, sec in next, group.items do
			sections[#sections + 1] = sec
		end
	end

	-- ── Status text (no positioning — it's a FontString, not an icon) ──

	local showStatusTextCheck = Widgets.CreateCheckButton(inner, 'Show Status Text', function(checked)
		setConfig('statusText', checked)
	end)
	showStatusTextCheck:SetChecked(getConfig('statusText') ~= false)

	-- ── Reflow ───────────────────────────────────────────────

	local initialized = false

	local function reflowCard()
		local y = 0

		for _, group in next, groups do
			-- Group heading
			group.heading:ClearAllPoints()
			Widgets.SetPoint(group.heading, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
			y = y - group.headingH

			for _, sec in next, group.items do
				local enabled = sec.check:GetChecked()

				-- Checkbox (always visible)
				sec.check:ClearAllPoints()
				Widgets.SetPoint(sec.check, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
				y = y - B.CHECK_H - C.Spacing.normal

				if(enabled) then
					-- Anchor picker
					sec.picker:Show()
					sec.picker:ClearAllPoints()
					Widgets.SetPoint(sec.picker, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
					y = y - ANCHOR_PICKER_H - C.Spacing.normal

					-- Size slider
					sec.sizeSlider:Show()
					sec.sizeSlider:ClearAllPoints()
					Widgets.SetPoint(sec.sizeSlider, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
					y = y - SIZE_SLIDER_H - C.Spacing.normal

					-- Extra widgets (e.g., role style dropdown)
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
		end

		-- Status text checkbox (always visible, no sub-controls)
		showStatusTextCheck:ClearAllPoints()
		Widgets.SetPoint(showStatusTextCheck, 'TOPLEFT', inner, 'TOPLEFT', 0, y)
		y = y - B.CHECK_H - C.Spacing.normal

		Widgets.EndCard(card, parent, y)
		if(initialized and onResize) then onResize() end
	end

	-- Set reflowRef so checkbox callbacks can trigger reflow
	reflowRef[1] = reflowCard

	-- Initial reflow
	reflowCard()
	initialized = true

	return card
end
