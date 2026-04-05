local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.PreviewFrame = {}

-- Class colors (reuse oUF's colors when available)
local function getClassColor(class)
	local oUF = F.oUF
	if(oUF and oUF.colors and oUF.colors.class and oUF.colors.class[class]) then
		local c = oUF.colors.class[class]
		return c:GetRGB()
	end
	return 0.5, 0.5, 0.5
end

local POWER_COLOR = { 0.0, 0.44, 0.87, 1 }  -- Match oUF mana override

-- Fake health/power values for text formatting
local FAKE_HEALTH     = 245000
local FAKE_HEALTH_MAX = 245000
local FAKE_POWER      = 180000
local FAKE_POWER_MAX  = 180000

-- Format text based on textFormat config
local function formatHealthText(pct, fmt)
	local cur = math.floor(FAKE_HEALTH * pct)
	if(fmt == 'percent') then
		return math.floor(pct * 100) .. '%'
	elseif(fmt == 'current') then
		return F.AbbreviateNumber and F.AbbreviateNumber(cur) or tostring(cur)
	elseif(fmt == 'currentMax') then
		local abbrev = F.AbbreviateNumber or tostring
		return abbrev(cur) .. '/' .. abbrev(FAKE_HEALTH_MAX)
	elseif(fmt == 'deficit') then
		local missing = FAKE_HEALTH_MAX - cur
		if(missing == 0) then return '' end
		return '-' .. (F.AbbreviateNumber and F.AbbreviateNumber(missing) or tostring(missing))
	elseif(fmt == 'none') then
		return ''
	end
	return math.floor(pct * 100) .. '%'
end

local function formatPowerText(pct, fmt)
	local cur = math.floor(FAKE_POWER * pct)
	if(fmt == 'percent') then
		return math.floor(pct * 100) .. '%'
	elseif(fmt == 'current') then
		return F.AbbreviateNumber and F.AbbreviateNumber(cur) or tostring(cur)
	elseif(fmt == 'currentMax') then
		local abbrev = F.AbbreviateNumber or tostring
		return abbrev(cur) .. '/' .. abbrev(FAKE_POWER_MAX)
	elseif(fmt == 'none') then
		return ''
	end
	return math.floor(pct * 100) .. '%'
end

-- Resolve gradient color for a given health percentage
local function getGradientColor(hc, pct)
	local p = pct * 100
	local t1 = hc.gradientThreshold1 or 95
	local t2 = hc.gradientThreshold2 or 50
	local t3 = hc.gradientThreshold3 or 5
	local c1 = hc.gradientColor1 or { 0.2, 0.8, 0.2, 1 }
	local c2 = hc.gradientColor2 or { 0.9, 0.6, 0.1, 1 }
	local c3 = hc.gradientColor3 or { 0.8, 0.1, 0.1, 1 }
	if(p >= t1) then return c1[1], c1[2], c1[3] end
	if(p >= t2) then
		local t = (p - t2) / (t1 - t2)
		return c2[1] + (c1[1] - c2[1]) * t, c2[2] + (c1[2] - c2[2]) * t, c2[3] + (c1[3] - c2[3]) * t
	end
	if(p >= t3) then
		local t = (p - t3) / (t2 - t3)
		return c3[1] + (c2[1] - c3[1]) * t, c3[2] + (c2[2] - c3[2]) * t, c3[3] + (c2[3] - c3[3]) * t
	end
	return c3[1], c3[2], c3[3]
end

-- Apply health bar color based on config colorMode
local function applyHealthColor(bar, config, fakeUnit)
	local hc = config.health
	local mode = hc and hc.colorMode or 'class'
	local pct = fakeUnit and fakeUnit.healthPct or 1
	if(mode == 'class' and fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		bar:SetStatusBarColor(r, g, b, 1)
	elseif(mode == 'custom' and hc.customColor) then
		bar:SetStatusBarColor(hc.customColor[1], hc.customColor[2], hc.customColor[3], hc.customColor[4] or 1)
	elseif(mode == 'dark') then
		bar:SetStatusBarColor(0.25, 0.25, 0.25, 1)
	elseif(mode == 'gradient') then
		local r, g, b = getGradientColor(hc, pct)
		bar:SetStatusBarColor(r, g, b, 1)
	elseif(fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		bar:SetStatusBarColor(r, g, b, 1)
	end
end

-- ============================================================
-- Health bar builder
-- ============================================================

local function BuildHealthBar(frame, config)
	local wrapper = CreateFrame('Frame', nil, frame)
	-- Points set after power bar is built (health fills remaining space)
	wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
	wrapper:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
	wrapper:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
	wrapper:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)

	local bar = CreateFrame('StatusBar', nil, wrapper)
	bar:SetAllPoints(wrapper)
	bar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	local bgC = C.Colors.background
	bar._bg = wrapper:CreateTexture(nil, 'BACKGROUND')
	bar._bg:SetAllPoints(wrapper)
	bar._bg:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

	frame._healthWrapper = wrapper
	frame._healthBar = bar

	-- Health text — overlay frame above the StatusBar child
	local hc = config.health
	if(hc and hc.showText ~= false) then
		local textOverlay = CreateFrame('Frame', nil, wrapper)
		textOverlay:SetAllPoints(wrapper)
		textOverlay:SetFrameLevel(bar:GetFrameLevel() + 2)
		local text = Widgets.CreateFontString(textOverlay, hc.fontSize, C.Colors.textActive)
		text:SetFont(F.Media.GetActiveFont(), hc.fontSize, hc.outline or '')
		if(hc.shadow ~= false) then
			text:SetShadowOffset(1, -1)
			text:SetShadowColor(0, 0, 0, 1)
		end
		-- Text color mode
		local tcm = hc.textColorMode or 'white'
		if(tcm == 'custom' and hc.textCustomColor) then
			text:SetTextColor(hc.textCustomColor[1], hc.textCustomColor[2], hc.textCustomColor[3], 1)
		elseif(tcm == 'class') then
			frame._healthTextClassColor = true
		elseif(tcm == 'dark') then
			text:SetTextColor(0.25, 0.25, 0.25, 1)
		end
		local anchor = hc.textAnchor or 'RIGHT'
		text:SetPoint(anchor, wrapper, anchor, (hc.textAnchorX or 0) + 1, hc.textAnchorY or 0)
		frame._healthText = text
	end
end

-- ============================================================
-- Power bar builder
-- ============================================================

local function BuildPowerBar(frame, config)
	if(config.showPower == false) then return end

	local powerHeight = (config.power and config.power.height) or 8
	local wrapper = CreateFrame('Frame', nil, frame)
	wrapper:SetHeight(powerHeight)

	if(config.power and config.power.position == 'top') then
		wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
		wrapper:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
		-- Shrink health below power
		frame._healthWrapper:ClearAllPoints()
		frame._healthWrapper:SetPoint('TOPLEFT', wrapper, 'BOTTOMLEFT', 0, 0)
		frame._healthWrapper:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
	else
		wrapper:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
		wrapper:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
		-- Shrink health above power
		frame._healthWrapper:ClearAllPoints()
		frame._healthWrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
		frame._healthWrapper:SetPoint('BOTTOMRIGHT', wrapper, 'TOPRIGHT', 0, 0)
	end

	local bar = CreateFrame('StatusBar', nil, wrapper)
	bar:SetAllPoints(wrapper)
	bar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0.8)
	bar:SetStatusBarColor(POWER_COLOR[1], POWER_COLOR[2], POWER_COLOR[3], POWER_COLOR[4])
	local bgC = C.Colors.background
	bar._bg = wrapper:CreateTexture(nil, 'BACKGROUND')
	bar._bg:SetAllPoints(wrapper)
	bar._bg:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

	frame._powerWrapper = wrapper
	frame._powerBar = bar

	-- Power text
	local pc = config.power
	if(pc and pc.showText) then
		local textOverlay = CreateFrame('Frame', nil, wrapper)
		textOverlay:SetAllPoints(wrapper)
		textOverlay:SetFrameLevel(bar:GetFrameLevel() + 2)
		local text = Widgets.CreateFontString(textOverlay, pc.fontSize, C.Colors.textActive)
		text:SetFont(F.Media.GetActiveFont(), pc.fontSize, pc.outline or '')
		if(pc.shadow ~= false) then
			text:SetShadowOffset(1, -1)
			text:SetShadowColor(0, 0, 0, 1)
		end
		-- Text color mode
		local tcm = pc.textColorMode or 'white'
		if(tcm == 'custom' and pc.textCustomColor) then
			text:SetTextColor(pc.textCustomColor[1], pc.textCustomColor[2], pc.textCustomColor[3], 1)
		elseif(tcm == 'class') then
			frame._powerTextClassColor = true
		elseif(tcm == 'dark') then
			text:SetTextColor(0.25, 0.25, 0.25, 1)
		end
		local anchor = pc.textAnchor or 'CENTER'
		text:SetPoint(anchor, wrapper, anchor, (pc.textAnchorX or 0) + 1, pc.textAnchorY or 0)
		frame._powerText = text
	end
end

-- ============================================================
-- Name text builder
-- ============================================================

local function BuildNameText(frame, config, fakeUnit)
	if(config.name and config.name.showName == false) then return end
	local nc = config.name
	if(not nc) then return end

	local anchorParent = frame._healthWrapper or frame
	local nameOverlay = CreateFrame('Frame', nil, anchorParent)
	nameOverlay:SetAllPoints(anchorParent)
	nameOverlay:SetFrameLevel(frame._healthBar:GetFrameLevel() + 3)
	local text = Widgets.CreateFontString(nameOverlay, nc.fontSize, C.Colors.textActive)
	text:SetFont(F.Media.GetActiveFont(), nc.fontSize, nc.outline or '')
	if(nc.shadow ~= false) then
		text:SetShadowOffset(1, -1)
		text:SetShadowColor(0, 0, 0, 1)
	end

	local pt = nc.anchor or 'LEFT'
	text:SetPoint(pt, anchorParent, pt, nc.anchorX or 0, nc.anchorY or 0)
	text:SetText(fakeUnit and fakeUnit.name or 'Unit Name')

	-- Color mode
	local ncMode = nc.colorMode or 'class'
	if(ncMode == 'class' and fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		text:SetTextColor(r, g, b, 1)
	elseif(ncMode == 'custom' and nc.customColor) then
		text:SetTextColor(nc.customColor[1], nc.customColor[2], nc.customColor[3], 1)
	elseif(ncMode == 'dark') then
		text:SetTextColor(0.25, 0.25, 0.25, 1)
	elseif(ncMode == 'white') then
		text:SetTextColor(1, 1, 1, 1)
	end

	frame._nameText = text
end

-- ============================================================
-- Status icons builder
-- ============================================================

local STATUS_ICON_KEYS = {
	'role', 'leader', 'readyCheck', 'raidIcon', 'combat',
	'resting', 'phase', 'resurrect', 'summon', 'raidRole', 'pvp',
}

-- Textures matching the live frame elements (oUF + custom Elements/Status)
local STATUS_ICON_TEXTURES = {
	-- RoleIcon: uses our custom RoleIcons strip, healer quadrant as preview
	role       = { texFn = function()
		local style = F.Config and F.Config:Get('general.roleIconStyle') or 2
		return F.Media.GetIcon('RoleIcons' .. style), { 0.25, 0.5, 0, 1 }
	end },
	-- LeaderIcon: oUF uses Blizzard atlas
	leader     = { atlas = 'UI-HUD-UnitFrame-Player-Group-LeaderIcon' },
	-- ReadyCheck: our Fluent icons
	readyCheck = { tex = F.Media.GetIcon('Fluent_Color_Yes') },
	-- RaidTargetIcon: oUF uses Blizzard raid targeting sheet, star coords
	raidIcon   = { tex = [[Interface\TargetingFrame\UI-RaidTargetingIcons]], coords = { 0, 0.25, 0, 0.25 } },
	-- CombatIcon: oUF uses Blizzard atlas
	combat     = { atlas = 'UI-HUD-UnitFrame-Player-CombatIcon' },
	-- RestingIcon: oUF uses Blizzard StateIcon sheet
	resting    = { tex = [[Interface\CharacterFrame\UI-StateIcon]], coords = { 0, 0.5, 0, 0.421875 } },
	-- PhaseIcon: oUF uses Blizzard atlas
	phase      = { atlas = 'RaidFrame-Icon-Phasing' },
	-- ResurrectIcon: oUF uses Blizzard atlas
	resurrect  = { atlas = 'RaidFrame-Icon-Rez' },
	-- SummonIcon: oUF uses Blizzard atlas
	summon     = { atlas = 'RaidFrame-Icon-SummonPending' },
	-- RaidRoleIcon: oUF uses Blizzard atlas (main assist)
	raidRole   = { atlas = 'RaidFrame-Icon-MainAssist' },
	-- PvPIcon: our custom Faction2 icons
	pvp        = { tex = F.Media.GetIcon('Faction2_Alliance') },
}

local function BuildStatusIcons(frame, config)
	local icons = config.statusIcons
	if(not icons) then return end

	-- Overlay frame above health/power bars so icons are visible
	local iconOverlay = CreateFrame('Frame', nil, frame)
	iconOverlay:SetAllPoints(frame)
	iconOverlay:SetFrameLevel(frame._healthBar:GetFrameLevel() + 5)
	frame._iconOverlay = iconOverlay

	frame._statusIcons = {}
	for _, key in next, STATUS_ICON_KEYS do
		if(icons[key]) then
			local pt   = icons[key .. 'Point'] or 'TOPLEFT'
			local x    = icons[key .. 'X'] or 0
			local y    = icons[key .. 'Y'] or 0
			local size = icons[key .. 'Size'] or 14

			local icon = iconOverlay:CreateTexture(nil, 'OVERLAY')
			icon:SetSize(size, size)
			icon:SetPoint(pt, frame, pt, x, y)

			local texInfo = STATUS_ICON_TEXTURES[key]
			if(texInfo) then
				if(texInfo.texFn) then
					local tex, coords = texInfo.texFn()
					icon:SetTexture(tex)
					if(coords) then
						icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
					end
				elseif(texInfo.atlas) then
					icon:SetAtlas(texInfo.atlas)
				elseif(texInfo.tex) then
					icon:SetTexture(texInfo.tex)
					if(texInfo.coords) then
						icon:SetTexCoord(texInfo.coords[1], texInfo.coords[2], texInfo.coords[3], texInfo.coords[4])
					end
				end
			else
				icon:SetColorTexture(0.4, 0.4, 0.4, 0.6)
			end

			frame._statusIcons[key] = icon
		end
	end
end

-- ============================================================
-- Castbar builder
-- ============================================================

local function BuildCastbar(frame, config)
	if(not config.castbar) then return end
	if(config.showCastBar == false) then return end
	local cb = config.castbar

	local wrapper = CreateFrame('Frame', nil, frame)
	local cbWidth = (cb.sizeMode == 'detached' and cb.width) or config.width
	wrapper:SetSize(cbWidth, cb.height or 16)
	wrapper:SetPoint('TOP', frame, 'BOTTOM', 0, -C.Spacing.base)

	local bgC = C.Colors.background
	local bgTex = wrapper:CreateTexture(nil, 'BACKGROUND')
	bgTex:SetAllPoints(wrapper)
	bgTex:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

	local bar = CreateFrame('StatusBar', nil, wrapper)
	bar:SetAllPoints(wrapper)
	bar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0.6)
	local ac = C.Colors.accent
	bar:SetStatusBarColor(ac[1], ac[2], ac[3], 0.8)

	local label = Widgets.CreateFontString(wrapper, C.Font.sizeSmall, C.Colors.textActive)
	label:SetPoint('LEFT', wrapper, 'LEFT', 4, 0)
	label:SetText('Casting...')

	frame._castbar = wrapper
end

-- ============================================================
-- Highlights builder
-- ============================================================

local function BuildHighlights(frame, config)
	if(config.targetHighlight) then
		local thColor = F.Config and F.Config:Get('general.targetHighlightColor')
		local thWidth = F.Config and F.Config:Get('general.targetHighlightWidth') or 2

		local hl = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
		hl:SetPoint('TOPLEFT', frame, 'TOPLEFT', -thWidth, thWidth)
		hl:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', thWidth, -thWidth)
		local c = thColor or { 1, 1, 1, 0.8 }
		hl:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = thWidth })
		hl:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 0.8)
		frame._targetHighlight = hl
	end
end

-- ============================================================
-- Aura indicator builders
-- ============================================================

local PI = F.PreviewIndicators

local BUFF_TYPE_MAP = {
	[C.IndicatorType.ICON]      = 'Icon',
	[C.IndicatorType.ICONS]     = 'Icons',
	[C.IndicatorType.BAR]       = 'Bar',
	[C.IndicatorType.BARS]      = 'Bars',
	[C.IndicatorType.BORDER]    = 'BorderGlow',
	[C.IndicatorType.RECTANGLE] = 'ColorRect',
	[C.IndicatorType.OVERLAY]   = 'Overlay',
}

local function BuildBuffIndicators(frame, buffsConfig)
	if(not buffsConfig or not buffsConfig.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}
	local fakeIcons = PI.GetFakeIcons('buffs')

	for name, indCfg in next, buffsConfig.indicators or {} do
		if(indCfg.enabled ~= false) then
			local indType = indCfg.type
			local pt, relFrame, relPt, offX, offY = PI.UnpackAnchor(indCfg.anchor, { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 })

			if(indType == C.IndicatorType.ICON) then
				local icon = PI.CreateIcon(groupFrame, fakeIcons[1], indCfg.iconWidth, indCfg.iconHeight, indCfg)
				icon:SetPoint(pt, frame, relPt, offX, offY)
				groupFrame._elements[#groupFrame._elements + 1] = icon

			elseif(indType == C.IndicatorType.ICONS) then
				local max = math.min(indCfg.maxDisplayed or 3, 5)
				local w = indCfg.iconWidth or 14
				local h = indCfg.iconHeight or 14
				for i = 1, max do
					local icon = PI.CreateIcon(groupFrame, fakeIcons[((i-1) % #fakeIcons) + 1], w, h, indCfg)
					local dx, dy = PI.OrientOffset(indCfg.orientation or 'RIGHT', i, w, h, indCfg.spacingX, indCfg.spacingY)
					icon:SetPoint(pt, frame, relPt, offX + dx, offY + dy)
					groupFrame._elements[#groupFrame._elements + 1] = icon
				end

			elseif(indType == C.IndicatorType.BAR) then
				local bar = PI.CreateBar(groupFrame, indCfg)
				bar:SetPoint(pt, frame, relPt, offX, offY)
				groupFrame._elements[#groupFrame._elements + 1] = bar

			elseif(indType == C.IndicatorType.BARS) then
				local max = math.min(indCfg.maxDisplayed or 3, 5)
				for i = 1, max do
					local bar = PI.CreateBar(groupFrame, indCfg)
					local dx, dy = PI.OrientOffset(indCfg.orientation or 'DOWN', i,
						indCfg.barWidth or 50, indCfg.barHeight or 4, indCfg.spacingX, indCfg.spacingY)
					bar:SetPoint(pt, frame, relPt, offX + dx, offY + dy)
					groupFrame._elements[#groupFrame._elements + 1] = bar
				end

			elseif(indType == C.IndicatorType.BORDER) then
				local bg = PI.CreateBorderGlow(frame, indCfg)
				groupFrame._elements[#groupFrame._elements + 1] = bg

			elseif(indType == C.IndicatorType.RECTANGLE) then
				local rect = PI.CreateColorRect(groupFrame, indCfg)
				rect:SetPoint(pt, frame, relPt, offX, offY)
				groupFrame._elements[#groupFrame._elements + 1] = rect

			elseif(indType == C.IndicatorType.OVERLAY) then
				local overlay = PI.CreateOverlay(frame._healthWrapper, indCfg)
				if(overlay) then
					groupFrame._elements[#groupFrame._elements + 1] = overlay
				end
			end
		end
	end

	return groupFrame
end

local BORDICON_GROUPS = { 'debuffs', 'raidDebuffs', 'externals', 'defensives' }

local GROUP_DISPEL_TYPES = {
	debuffs      = { 'Magic', 'Curse', 'Poison' },
	raidDebuffs  = { 'Magic', 'Magic' },
	externals    = { nil, nil },
	defensives   = { nil, nil },
}

local function BuildBorderIconGroup(frame, groupKey, groupCfg)
	if(not groupCfg or not groupCfg.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}

	local pt, _, relPt, offX, offY = PI.UnpackAnchor(groupCfg.anchor)
	local size = groupCfg.iconSize or 14
	local max = math.min(groupCfg.maxDisplayed or 3, 5)
	local orient = groupCfg.orientation or 'RIGHT'
	local fakeIcons = PI.GetFakeIcons(groupKey)
	local fakeDispels = GROUP_DISPEL_TYPES[groupKey] or {}
	local borderThick = groupCfg.borderThickness or 2

	for i = 1, max do
		local dispel = fakeDispels[((i-1) % math.max(#fakeDispels, 1)) + 1]
		local bi = PI.CreateBorderIcon(groupFrame, fakeIcons[((i-1) % #fakeIcons) + 1], size, borderThick, dispel, groupCfg)
		local dx, dy = PI.OrientOffset(orient, i, size, size, 2, 2)
		bi:SetPoint(pt, frame, relPt, offX + dx, offY + dy)
		groupFrame._elements[#groupFrame._elements + 1] = bi
	end

	return groupFrame
end

local function BuildDispellableGroup(frame, dispCfg)
	if(not dispCfg or not dispCfg.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}

	local pt, _, relPt, offX, offY = PI.UnpackAnchor(dispCfg.anchor)
	local size = dispCfg.iconSize or 14
	local bi = PI.CreateBorderIcon(groupFrame, PI.GetFakeIcons('dispellable')[1], size, 2, 'Magic', dispCfg)
	bi:SetPoint(pt, frame, relPt, offX, offY)
	groupFrame._elements[1] = bi

	-- Health bar overlay (dispel highlight)
	if(frame._healthWrapper and dispCfg.highlightType) then
		local hlType = dispCfg.highlightType
		local hlColor = PI.DISPEL_COLORS.Magic or { 0.2, 0.6, 1.0 }
		local hl = frame._healthWrapper:CreateTexture(nil, 'OVERLAY')
		if(hlType == 'gradient_full' or hlType == 'gradient_half') then
			hl:SetAllPoints(frame._healthWrapper)
			hl:SetColorTexture(hlColor[1], hlColor[2], hlColor[3], 0.3)
			if(hlType == 'gradient_half') then
				hl:ClearAllPoints()
				hl:SetPoint('TOP', frame._healthWrapper, 'TOP', 0, 0)
				hl:SetPoint('BOTTOMRIGHT', frame._healthWrapper, 'BOTTOMRIGHT', 0, 0)
				hl:SetWidth(frame._healthWrapper:GetWidth() * 0.5)
			end
		else
			hl:SetAllPoints(frame._healthWrapper)
			hl:SetColorTexture(hlColor[1], hlColor[2], hlColor[3], 0.2)
		end
		groupFrame._elements[#groupFrame._elements + 1] = hl
	end

	return groupFrame
end

local function BuildSimpleIconGroup(frame, groupKey, cfg)
	if(not cfg or not cfg.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}

	local pt, _, relPt, offX, offY = PI.UnpackAnchor(cfg.anchor)
	local size = cfg.iconSize or 16
	local fakeIcons = PI.GetFakeIcons(groupKey)

	if(groupKey == 'missingBuffs') then
		local bi = PI.CreateBorderIcon(groupFrame, fakeIcons[1], size, 1, nil, { showCooldown = false, showDuration = false })
		bi:SetPoint(pt, frame, relPt, offX, offY)
		groupFrame._elements[1] = bi
	else
		local icon = PI.CreateIcon(groupFrame, fakeIcons[1], size, size, { showCooldown = false, durationMode = 'Never', showStacks = false })
		icon:SetPoint(pt, frame, relPt, offX, offY)
		groupFrame._elements[1] = icon
	end

	return groupFrame
end

-- ============================================================
-- Shared: build all elements and apply fake data
-- ============================================================

local function BuildAllElements(frame, config, fakeUnit, auraConfig)
	-- Dark background (match StyleBuilder)
	local bg = frame:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(frame)
	local bgC = C.Colors.background
	bg:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 1)
	frame._bg = bg

	-- Build structural elements (health fills remaining space, power has fixed height)
	BuildHealthBar(frame, config)
	BuildPowerBar(frame, config)
	BuildNameText(frame, config, fakeUnit)
	BuildStatusIcons(frame, config)
	BuildCastbar(frame, config)
	BuildHighlights(frame, config)

	-- Build aura indicators
	frame._auraGroups = {}
	if(auraConfig) then
		frame._auraGroups.buffs = BuildBuffIndicators(frame, auraConfig.buffs)
		for _, groupKey in next, BORDICON_GROUPS do
			frame._auraGroups[groupKey] = BuildBorderIconGroup(frame, groupKey, auraConfig[groupKey])
		end
		frame._auraGroups.dispellable = BuildDispellableGroup(frame, auraConfig.dispellable)
		frame._auraGroups.missingBuffs = BuildSimpleIconGroup(frame, 'missingBuffs', auraConfig.missingBuffs)
		frame._auraGroups.privateAuras = BuildSimpleIconGroup(frame, 'privateAuras', auraConfig.privateAuras)
		frame._auraGroups.targetedSpells = BuildSimpleIconGroup(frame, 'targetedSpells', auraConfig.targetedSpells)
		frame._auraGroups.lossOfControl = BuildSimpleIconGroup(frame, 'lossOfControl', auraConfig.lossOfControl)
		frame._auraGroups.crowdControl = BuildSimpleIconGroup(frame, 'crowdControl', auraConfig.crowdControl)
	end

	function frame:SetAuraGroupAlpha(activeGroupId)
		if(not self._auraGroups) then return end
		for groupId, groupFrame in next, self._auraGroups do
			if(activeGroupId == nil or groupId == activeGroupId) then
				groupFrame:SetAlpha(1.0)
			else
				groupFrame:SetAlpha(0.2)
			end
		end
	end

	-- Apply fake unit data with config-aware colors and text formats
	if(fakeUnit) then
		applyHealthColor(frame._healthBar, config, fakeUnit)
		frame._healthBar:SetValue(fakeUnit.healthPct or 1)
		if(frame._healthText) then
			local hFmt = (config.health and config.health.textFormat) or 'percent'
			frame._healthText:SetText(formatHealthText(fakeUnit.healthPct or 1, hFmt))
			if(frame._healthTextClassColor) then
				local tr, tg, tb = getClassColor(fakeUnit.class)
				frame._healthText:SetTextColor(tr, tg, tb, 1)
			end
		end
		if(frame._powerBar) then
			frame._powerBar:SetValue(fakeUnit.powerPct or 1)
		end
		if(frame._powerText) then
			local pFmt = (config.power and config.power.textFormat) or 'percent'
			frame._powerText:SetText(formatPowerText(fakeUnit.powerPct or 1, pFmt))
			if(frame._powerTextClassColor) then
				local tr, tg, tb = getClassColor(fakeUnit.class)
				frame._powerText:SetTextColor(tr, tg, tb, 1)
			end
		end
	end

	frame._config = config
	frame._fakeUnit = fakeUnit
end

-- ============================================================
-- Destroy: clean up all child frames and textures for rebuild
-- ============================================================

local function DestroyChildren(frame)
	for _, child in next, { frame:GetChildren() } do
		child:Hide()
		child:SetParent(nil)
	end
	-- Clear references
	local keys = {
		'_bg', '_healthWrapper', '_healthBar', '_healthText', '_healthTextClassColor',
		'_powerWrapper', '_powerBar', '_powerText', '_powerTextClassColor',
		'_nameText', '_castbar', '_targetHighlight', '_iconOverlay', '_auraGroups',
	}
	for _, key in next, keys do
		frame[key] = nil
	end
	if(frame._statusIcons) then
		for _, icon in next, frame._statusIcons do
			icon:Hide()
		end
		frame._statusIcons = nil
	end
end

-- ============================================================
-- Public: Create preview frame
-- ============================================================

function F.PreviewFrame.Create(parent, config, fakeUnit, realFrame, auraConfig)
	local frame = CreateFrame('Frame', nil, parent)

	-- Match effective scale so config dimensions render at the correct visual
	-- size. For solo frames, sync to the real frame's scale. For group frames
	-- (no realFrame), sync to UIParent's scale since headers anchor to UIParent.
	local targetScale = realFrame and realFrame:GetEffectiveScale() or UIParent:GetEffectiveScale()
	local parentScale = frame:GetParent():GetEffectiveScale()
	if(parentScale > 0) then
		frame:SetScale(targetScale / parentScale)
	end
	Widgets.SetSize(frame, config.width, config.height)

	BuildAllElements(frame, config, fakeUnit, auraConfig)

	return frame
end

-- ============================================================
-- Public: Rebuild preview in-place with new config
-- ============================================================

function F.PreviewFrame.UpdateFromConfig(frame, config, auraConfig)
	DestroyChildren(frame)
	Widgets.SetSize(frame, config.width, config.height)
	BuildAllElements(frame, config, frame._fakeUnit, auraConfig)
end
