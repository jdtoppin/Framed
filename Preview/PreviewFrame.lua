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

-- Build a C_CurveUtil color curve from 3 color/threshold pairs (matches Health.lua)
local function buildColorCurve(c1, t1, c2, t2, c3, t3)
	local curve = C_CurveUtil.CreateColorCurve()
	curve:AddPoint(t3 / 100, CreateColor(c3[1], c3[2], c3[3]))
	curve:AddPoint(t2 / 100, CreateColor(c2[1], c2[2], c2[3]))
	curve:AddPoint(t1 / 100, CreateColor(c1[1], c1[2], c1[3]))
	return curve
end

-- Apply health bar color based on config colorMode
local function applyHealthColor(bar, config, fakeUnit)
	local hc = config.health
	local mode = hc.colorMode
	local pct = fakeUnit and fakeUnit.healthPct or 1
	if(mode == 'class' and fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		bar:SetStatusBarColor(r, g, b, 1)
	elseif(mode == 'custom' and hc.customColor) then
		bar:SetStatusBarColor(hc.customColor[1], hc.customColor[2], hc.customColor[3], hc.customColor[4] or 1)
	elseif(mode == 'dark') then
		bar:SetStatusBarColor(0.25, 0.25, 0.25, 1)
	elseif(mode == 'gradient') then
		local curve = buildColorCurve(
			hc.gradientColor1, hc.gradientThreshold1,
			hc.gradientColor2, hc.gradientThreshold2,
			hc.gradientColor3, hc.gradientThreshold3
		)
		local color = curve:GetColorAtPosition(pct)
		if(color) then
			bar:SetStatusBarColor(color:GetRGBA())
		end
	elseif(fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		bar:SetStatusBarColor(r, g, b, 1)
	end
end

-- Apply health loss color (background behind depleted health)
local function applyHealthLossColor(bg, config, fakeUnit)
	local hc = config.health
	local lossMode = hc.lossColorMode
	if(lossMode == 'class' and fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		bg:SetVertexColor(r * 0.3, g * 0.3, b * 0.3, 1)
	elseif(lossMode == 'gradient') then
		local pct = fakeUnit and fakeUnit.healthPct or 1
		local curve = buildColorCurve(
			hc.lossGradientColor1, hc.lossGradientThreshold1,
			hc.lossGradientColor2, hc.lossGradientThreshold2,
			hc.lossGradientColor3, hc.lossGradientThreshold3
		)
		local color = curve:GetColorAtPosition(pct)
		if(color) then
			bg:SetVertexColor(color:GetRGBA())
		end
	elseif(lossMode == 'custom' and hc.lossCustomColor) then
		local lc = hc.lossCustomColor
		bg:SetVertexColor(lc[1], lc[2], lc[3], 1)
	elseif(lossMode == 'dark') then
		bg:SetVertexColor(0.15, 0.15, 0.15, 1)
	end
end

-- ============================================================
-- Health bar builder
-- ============================================================

local function BuildHealthBar(frame, config)
	local wrapper = CreateFrame('Frame', nil, frame)
	wrapper:SetFrameLevel(frame:GetFrameLevel() + config.elementStrata.healthBar)
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
	-- Background texture for health loss color (SetVertexColor for class/gradient modes)
	local bg = wrapper:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(wrapper)
	bg:SetTexture(F.Media.GetActiveBarTexture())
	bg:SetVertexColor(0.15, 0.15, 0.15, 1)
	bar._bg = bg

	frame._healthWrapper = wrapper
	frame._healthBar = bar

	-- Health text — overlay frame above the StatusBar child
	local hc = config.health
	if(hc.showText ~= false) then
		local textOverlay = CreateFrame('Frame', nil, wrapper)
		textOverlay:SetAllPoints(wrapper)
		textOverlay:SetFrameLevel(bar:GetFrameLevel() + 2)
		local text = Widgets.CreateFontString(textOverlay, hc.fontSize, C.Colors.textActive)
		text:SetFont(F.Media.GetActiveFont(), hc.fontSize, hc.outline)
		if(hc.shadow ~= false) then
			text:SetShadowOffset(1, -1)
			text:SetShadowColor(0, 0, 0, 1)
		end
		-- Text color mode
		local tcm = hc.textColorMode
		if(tcm == 'custom' and hc.textCustomColor) then
			text:SetTextColor(hc.textCustomColor[1], hc.textCustomColor[2], hc.textCustomColor[3], 1)
		elseif(tcm == 'class') then
			frame._healthTextClassColor = true
		elseif(tcm == 'dark') then
			text:SetTextColor(0.25, 0.25, 0.25, 1)
		end
		text:SetPoint(hc.textAnchor, wrapper, hc.textAnchor, hc.textAnchorX + 1, hc.textAnchorY)
		frame._healthText = text
	end
end

-- ============================================================
-- Power bar builder
-- ============================================================

local function BuildPowerBar(frame, config)
	if(config.showPower == false) then return end

	local powerHeight = config.power.height
	local wrapper = CreateFrame('Frame', nil, frame)
	wrapper:SetHeight(powerHeight)

	if(config.power.position == 'top') then
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
	bar._bg:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4])

	frame._powerWrapper = wrapper
	frame._powerBar = bar

	-- Power text
	local pc = config.power
	if(pc.showText) then
		local textOverlay = CreateFrame('Frame', nil, wrapper)
		textOverlay:SetAllPoints(wrapper)
		textOverlay:SetFrameLevel(bar:GetFrameLevel() + 2)
		local text = Widgets.CreateFontString(textOverlay, pc.fontSize, C.Colors.textActive)
		text:SetFont(F.Media.GetActiveFont(), pc.fontSize, pc.outline)
		if(pc.shadow ~= false) then
			text:SetShadowOffset(1, -1)
			text:SetShadowColor(0, 0, 0, 1)
		end
		-- Text color mode
		local tcm = pc.textColorMode
		if(tcm == 'custom' and pc.textCustomColor) then
			text:SetTextColor(pc.textCustomColor[1], pc.textCustomColor[2], pc.textCustomColor[3], 1)
		elseif(tcm == 'class') then
			frame._powerTextClassColor = true
		elseif(tcm == 'dark') then
			text:SetTextColor(0.25, 0.25, 0.25, 1)
		end
		text:SetPoint(pc.textAnchor, wrapper, pc.textAnchor, pc.textAnchorX + 1, pc.textAnchorY)
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
	nameOverlay:SetFrameLevel(frame:GetFrameLevel() + config.elementStrata.nameText)
	local text = Widgets.CreateFontString(nameOverlay, nc.fontSize, C.Colors.textActive)
	text:SetFont(F.Media.GetActiveFont(), nc.fontSize, nc.outline)
	if(nc.shadow ~= false) then
		text:SetShadowOffset(1, -1)
		text:SetShadowColor(0, 0, 0, 1)
	end

	text:SetPoint(nc.anchor, anchorParent, nc.anchor, nc.anchorX, nc.anchorY)
	text:SetText(fakeUnit and fakeUnit.name or 'Unit Name')

	-- Color mode
	local ncMode = nc.colorMode
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
	iconOverlay:SetFrameLevel(frame:GetFrameLevel() + config.elementStrata.statusIcons)
	frame._iconOverlay = iconOverlay

	frame._statusIcons = {}
	for _, key in next, STATUS_ICON_KEYS do
		if(icons[key]) then
			local pt   = icons[key .. 'Point']
			local x    = icons[key .. 'X']
			local y    = icons[key .. 'Y']
			local size = icons[key .. 'Size']

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
	wrapper:SetFrameLevel(frame:GetFrameLevel() + config.elementStrata.castBar)
	local cbWidth = (cb.sizeMode == 'detached' and cb.width) or config.width
	wrapper:SetSize(cbWidth, cb.height)
	wrapper:SetPoint('TOP', frame, 'BOTTOM', 0, -C.Spacing.base)

	local bgC = C.Colors.background
	local bgTex = wrapper:CreateTexture(nil, 'BACKGROUND')
	bgTex:SetAllPoints(wrapper)
	bgTex:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4])

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
-- Portrait builder
-- ============================================================

local function BuildPortrait(frame, config, fakeUnit)
	if(not config.portrait) then return end

	local portraitType = config.portrait.type
	local size = math.min(config.height, config.width) * 0.8

	local wrapper = CreateFrame('Frame', nil, frame)
	wrapper:SetSize(size, size)
	wrapper:SetPoint('LEFT', frame, 'LEFT', 4, 0)
	wrapper:SetFrameLevel(frame:GetFrameLevel() + config.elementStrata.portrait)

	local tex = wrapper:CreateTexture(nil, 'ARTWORK')
	tex:SetAllPoints(wrapper)

	-- Use class icon as portrait stand-in (real portraits need a unit token)
	if(fakeUnit and fakeUnit.class) then
		local coords = CLASS_ICON_TCOORDS[fakeUnit.class]
		tex:SetTexture([[Interface\GLUES\CHARACTERCREATE\UI-CHARACTERCREATE-CLASSES]])
		if(coords) then
			tex:SetTexCoord(unpack(coords))
		end
	end

	frame._portrait = wrapper
	frame._portraitTex = tex
end

-- ============================================================
-- Status text builder
-- ============================================================

local function BuildStatusText(frame, config, fakeUnit)
	local stConfig = config.statusText
	if(not stConfig or stConfig.enabled == false) then return end

	local overlay = CreateFrame('Frame', nil, frame)
	overlay:SetAllPoints(frame)
	overlay:SetFrameLevel(frame:GetFrameLevel() + config.elementStrata.statusText)

	local text = Widgets.CreateFontString(overlay, stConfig.fontSize, C.Colors.textActive)
	text:SetPoint(stConfig.anchor, overlay, stConfig.anchor,
		stConfig.anchorX, stConfig.anchorY)

	-- Show a fake status for dead units
	if(fakeUnit and fakeUnit.isDead) then
		text:SetText('DEAD')
		text:SetTextColor(0.8, 0.2, 0.2, 1)
	else
		text:SetText('')
	end

	frame._statusText = text
	frame._statusTextOverlay = overlay
end

-- ============================================================
-- Shields and absorbs builder
-- ============================================================

local function BuildShieldsAndAbsorbs(frame, config, fakeUnit)
	if(not frame._healthBar) then return end
	local hc = config.health
	local healthBar = frame._healthBar
	local barWidth = config.width
	local healthPct = fakeUnit and fakeUnit.healthPct or 0.85

	-- Heal prediction
	if(hc.healPrediction ~= false and fakeUnit and fakeUnit.incomingHeal) then
		local healBar = CreateFrame('StatusBar', nil, healthBar)
		healBar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
		healBar:SetFrameLevel(healthBar:GetFrameLevel() + config.elementStrata.healPrediction)
		healBar:SetMinMaxValues(0, 1)
		healBar:SetValue(fakeUnit.incomingHeal)

		local healColor = hc.healPredictionColor
		healBar:SetStatusBarColor(healColor[1], healColor[2], healColor[3], healColor[4])

		-- Position after the health fill
		local fillWidth = barWidth * healthPct
		healBar:SetPoint('LEFT', healthBar, 'LEFT', fillWidth, 0)
		healBar:SetSize(barWidth * fakeUnit.incomingHeal, healthBar:GetHeight())

		frame._healPredBar = healBar
	end

	-- Damage absorb (shields)
	if(hc.damageAbsorb ~= false and fakeUnit and fakeUnit.damageAbsorb) then
		local absorbBar = CreateFrame('StatusBar', nil, healthBar)
		absorbBar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
		absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + config.elementStrata.damageAbsorb)
		absorbBar:SetMinMaxValues(0, 1)
		absorbBar:SetValue(1)

		local absorbColor = hc.damageAbsorbColor
		absorbBar:SetStatusBarColor(absorbColor[1], absorbColor[2], absorbColor[3], absorbColor[4])

		local fillWidth = barWidth * healthPct
		absorbBar:SetPoint('LEFT', healthBar, 'LEFT', fillWidth, 0)
		absorbBar:SetSize(barWidth * fakeUnit.damageAbsorb, healthBar:GetHeight())

		frame._damageAbsorbBar = absorbBar
	end

	-- Heal absorb
	if(hc.healAbsorb ~= false and fakeUnit and fakeUnit.healAbsorb) then
		local healAbsorbBar = CreateFrame('StatusBar', nil, healthBar)
		healAbsorbBar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
		healAbsorbBar:SetFrameLevel(healthBar:GetFrameLevel() + config.elementStrata.healAbsorb)
		healAbsorbBar:SetMinMaxValues(0, 1)
		healAbsorbBar:SetValue(1)

		local haColor = hc.healAbsorbColor
		healAbsorbBar:SetStatusBarColor(haColor[1], haColor[2], haColor[3], haColor[4])

		-- Heal absorbs eat into the health bar from the right
		local absorbWidth = barWidth * fakeUnit.healAbsorb
		healAbsorbBar:SetPoint('RIGHT', healthBar, 'LEFT', barWidth * healthPct, 0)
		healAbsorbBar:SetSize(absorbWidth, healthBar:GetHeight())

		frame._healAbsorbBar = healAbsorbBar
	end

	-- Overshield (texture on an OVERLAY-level wrapper frame for strata control)
	if(hc.overAbsorb ~= false and fakeUnit and fakeUnit.overAbsorb) then
		local overWrapper = CreateFrame('Frame', nil, healthBar)
		overWrapper:SetFrameLevel(healthBar:GetFrameLevel() + config.elementStrata.overAbsorb)
		overWrapper:SetPoint('TOPRIGHT', healthBar, 'TOPRIGHT', 4, 2)
		overWrapper:SetPoint('BOTTOMRIGHT', healthBar, 'BOTTOMRIGHT', 4, -2)
		overWrapper:SetWidth(12)

		local overGlow = overWrapper:CreateTexture(nil, 'OVERLAY')
		overGlow:SetAllPoints(overWrapper)
		overGlow:SetTexture([[Interface\RaidFrame\Shield-Overshield]])
		overGlow:SetBlendMode('ADD')
		overGlow:SetAlpha(0.8)

		frame._overAbsorbGlow = overWrapper
	end
end

-- ============================================================
-- Aura indicator builders (extracted to Preview/PreviewAuras.lua)
-- ============================================================

-- ============================================================
-- Shared: build all elements and apply fake data
-- ============================================================

local function BuildAllElements(frame, config, fakeUnit, auraConfig)
	-- Dark background (match StyleBuilder)
	local bg = frame:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(frame)
	local bgC = C.Colors.background
	bg:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4])
	frame._bg = bg

	-- Build structural elements (health fills remaining space, power has fixed height)
	BuildHealthBar(frame, config)
	BuildPowerBar(frame, config)
	BuildNameText(frame, config, fakeUnit)
	BuildStatusIcons(frame, config)
	BuildCastbar(frame, config)
	BuildHighlights(frame, config)
	BuildPortrait(frame, config, fakeUnit)
	BuildStatusText(frame, config, fakeUnit)
	BuildShieldsAndAbsorbs(frame, config, fakeUnit)

	-- Build aura indicators (delegated to PreviewAuras)
	local animated = F.PreviewManager.IsAnimationEnabled()
	if(auraConfig) then
		F.PreviewAuras.BuildAll(frame, auraConfig, animated)
	end

	-- Apply fake unit data with config-aware colors and text formats
	if(fakeUnit) then
		applyHealthColor(frame._healthBar, config, fakeUnit)
		applyHealthLossColor(frame._healthBar._bg, config, fakeUnit)

		if(animated) then
			-- Looping health depletion: 1 → healthPct over 8 seconds, then restart
			local targetPct = fakeUnit.healthPct
			local healthBar = frame._healthBar
			local function loopHealth(bar)
				bar:SetValue(1)
				Widgets.StartAnimation(bar, 'healthDrain', 1, targetPct, 8,
					function(f, v)
						f:SetValue(v)
						if(frame._healthText) then
							frame._healthText:SetText(formatHealthText(v, config.health.textFormat))
						end
					end,
					function(f)
						if(f:IsShown()) then loopHealth(f) end
					end
				)
			end
			loopHealth(healthBar)
		else
			frame._healthBar:SetValue(fakeUnit.healthPct)
			if(frame._healthText) then
				frame._healthText:SetText(formatHealthText(fakeUnit.healthPct, config.health.textFormat))
			end
		end

		if(frame._healthText and frame._healthTextClassColor) then
			local tr, tg, tb = getClassColor(fakeUnit.class)
			frame._healthText:SetTextColor(tr, tg, tb, 1)
		end
		if(frame._powerBar) then
			frame._powerBar:SetValue(fakeUnit.powerPct)
		end
		if(frame._powerText) then
			frame._powerText:SetText(formatPowerText(fakeUnit.powerPct, config.power.textFormat))
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
		'_portrait', '_portraitTex', '_statusText', '_statusTextOverlay',
		'_healPredBar', '_damageAbsorbBar', '_healAbsorbBar', '_overAbsorbGlow',
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
