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

-- Evaluate a 3-point color gradient at a given percent.
-- C_CurveUtil.CreateColorCurve returns a curve evaluable only by native
-- consumers (DurationObject:EvaluateRemainingPercent etc.), so preview-side
-- evaluation is done in Lua. Thresholds come in 0–100, points are ordered
-- high → low (t1 > t2 > t3), matching Health.lua's buildCurveTable layout.
local function evalColorGradient(c1, t1, c2, t2, c3, t3, pct)
	local p1, p2, p3 = t1 / 100, t2 / 100, t3 / 100
	if(pct >= p1) then return c1[1], c1[2], c1[3] end
	if(pct <= p3) then return c3[1], c3[2], c3[3] end
	if(pct >= p2) then
		local a = (pct - p2) / (p1 - p2)
		return c2[1] + (c1[1] - c2[1]) * a,
		       c2[2] + (c1[2] - c2[2]) * a,
		       c2[3] + (c1[3] - c2[3]) * a
	end
	local a = (pct - p3) / (p2 - p3)
	return c3[1] + (c2[1] - c3[1]) * a,
	       c3[2] + (c2[2] - c3[2]) * a,
	       c3[3] + (c2[3] - c3[3]) * a
end

-- Apply health bar color based on config colorMode
local function applyHealthColor(bar, config, fakeUnit, overridePct)
	local hc = config.health
	local mode = hc.colorMode
	local pct = overridePct or (fakeUnit and fakeUnit.healthPct) or 1
	if(mode == 'class' and fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		bar:SetStatusBarColor(r, g, b, 1)
	elseif(mode == 'custom' and hc.customColor) then
		bar:SetStatusBarColor(hc.customColor[1], hc.customColor[2], hc.customColor[3], hc.customColor[4] or 1)
	elseif(mode == 'dark') then
		bar:SetStatusBarColor(0.25, 0.25, 0.25, 1)
	elseif(mode == 'gradient') then
		local r, g, b = evalColorGradient(
			hc.gradientColor1, hc.gradientThreshold1,
			hc.gradientColor2, hc.gradientThreshold2,
			hc.gradientColor3, hc.gradientThreshold3,
			pct
		)
		bar:SetStatusBarColor(r, g, b, 1)
	elseif(fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		bar:SetStatusBarColor(r, g, b, 1)
	end
end

-- Apply health loss color (background behind depleted health)
local function applyHealthLossColor(bg, config, fakeUnit, overridePct)
	local hc = config.health
	local lossMode = hc.lossColorMode
	if(lossMode == 'class' and fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		bg:SetVertexColor(r * 0.3, g * 0.3, b * 0.3, 1)
	elseif(lossMode == 'gradient') then
		local pct = overridePct or (fakeUnit and fakeUnit.healthPct) or 1
		local r, g, b = evalColorGradient(
			hc.lossGradientColor1, hc.lossGradientThreshold1,
			hc.lossGradientColor2, hc.lossGradientThreshold2,
			hc.lossGradientColor3, hc.lossGradientThreshold3,
			pct
		)
		bg:SetVertexColor(r, g, b, 1)
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
	-- Match live's Widgets.CreateStatusBar: wrapper has a 1px black border +
	-- panel bg, and the StatusBar sits inset 1px inside. The black border is
	-- load-bearing for dark colorMode — without it, 0.25 gray against the
	-- outer frame bg (0.05 gray) has almost no contrast and reads as washed out.
	local wrapper = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
	wrapper:SetFrameLevel(frame:GetFrameLevel() + config.elementStrata.healthBar)
	-- Points set after power bar is built (health fills remaining space)
	wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
	wrapper:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
	wrapper:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
	wrapper:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
	Widgets.ApplyBackdrop(wrapper, C.Colors.panel, C.Colors.border)

	local bar = CreateFrame('StatusBar', nil, wrapper)
	bar:SetPoint('TOPLEFT',     wrapper, 'TOPLEFT',      1, -1)
	bar:SetPoint('BOTTOMRIGHT', wrapper, 'BOTTOMRIGHT', -1,  1)
	bar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
	-- Match live's Widgets.CreateStatusBar: tile-off so non-square textures
	-- stretch rather than repeat, and push the fill below the ARTWORK sub-level
	-- (-7) used by prediction overlays. Without tile-off, dark colorMode looked
	-- noticeably dimmer in the preview than on the live bar because textures
	-- with soft edges/gradients render differently when tiled.
	bar:GetStatusBarTexture():SetHorizTile(false)
	bar:GetStatusBarTexture():SetVertTile(false)
	bar:GetStatusBarTexture():SetDrawLayer('ARTWORK', -7)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	-- Loss bg is a child of the StatusBar (not the wrapper), matching live
	-- Elements/Core/Health.lua:147. Flat WHITE8x8 tinted via SetVertexColor so
	-- the loss area renders as a solid color behind the textured fill.
	local bg = bar:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(bar)
	bg:SetTexture([[Interface\BUTTONS\WHITE8x8]])
	local bgC = C.Colors.background
	bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1)
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
	if(config.showName == false) then return end
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

local MARKER_ICON_KEYS = { raidIcon = true, pvp = true }

local function BuildStatusIcons(frame, config)
	local icons = config.statusIcons
	if(not icons) then return end

	-- Filter by settings relevance so the preview only shows icons whose unit
	-- type has a toggle in the Settings UI. Without this, player-solo previews
	-- display role/leader/readyCheck/raidIcon (inherited from baseUnitConfig)
	-- despite those icons having no toggles for the player unit type.
	local relevance = frame._unitType and F.Settings and F.Settings.IconRelevance
		and F.Settings.IconRelevance[frame._unitType]

	-- Two overlays so focus-mode can highlight Status Icons and Markers independently:
	-- - _iconOverlay: role/leader/readyCheck/combat/resting/phase/resurrect/summon/raidRole
	-- - _markerOverlay: raidIcon + pvp (the "Markers" card)
	local iconOverlay = CreateFrame('Frame', nil, frame)
	iconOverlay:SetAllPoints(frame)
	iconOverlay:SetFrameLevel(frame:GetFrameLevel() + config.elementStrata.statusIcons)
	frame._iconOverlay = iconOverlay

	local markerOverlay = CreateFrame('Frame', nil, frame)
	markerOverlay:SetAllPoints(frame)
	markerOverlay:SetFrameLevel(frame:GetFrameLevel() + config.elementStrata.statusIcons)
	frame._markerOverlay = markerOverlay

	frame._statusIcons = {}
	for _, key in next, STATUS_ICON_KEYS do
		if(icons[key] and (not relevance or relevance[key])) then
			local pt   = icons[key .. 'Point']
			local x    = icons[key .. 'X']
			local y    = icons[key .. 'Y']
			local size = icons[key .. 'Size']

			local parent = MARKER_ICON_KEYS[key] and markerOverlay or iconOverlay
			local icon = parent:CreateTexture(nil, 'OVERLAY')
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

	local bar = CreateFrame('StatusBar', nil, wrapper)
	bar:SetAllPoints(wrapper)
	bar:SetStatusBarTexture(F.Media.GetActiveBarTexture())
	bar:SetMinMaxValues(0, 1)
	local ac = C.Colors.accent
	bar:SetStatusBarColor(ac[1], ac[2], ac[3], 0.8)

	-- 'always' keeps a dim background bar visible between casts; 'oncast' hides it.
	if(cb.backgroundMode ~= 'oncast') then
		local bgC = C.Colors.background
		local bgTex = wrapper:CreateTexture(nil, 'BACKGROUND')
		bgTex:SetAllPoints(wrapper)
		bgTex:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4])
	end

	local label = Widgets.CreateFontString(wrapper, C.Font.sizeSmall, C.Colors.textActive)
	label:SetPoint('LEFT', wrapper, 'LEFT', 4, 0)
	label:SetText('Casting...')

	-- Animation cycle runs in both modes. Alpha is applied to the fill bar and
	-- label rather than the wrapper so focus-mode dimming (SetAlpha on wrapper)
	-- still takes effect.
	bar:SetValue(0)
	bar:SetAlpha(0)
	label:SetAlpha(0)

	local castDur = 2.0
	local pauseDur = 1.5
	local fadeDur = 0.3
	local totalCycle = fadeDur + castDur + fadeDur + pauseDur
	local elapsed = 0
	wrapper:SetScript('OnUpdate', function(_, dt)
		elapsed = elapsed + dt
		local t = elapsed % totalCycle
		local a
		if(t < fadeDur) then
			a = t / fadeDur
			bar:SetValue(0)
		elseif(t < fadeDur + castDur) then
			a = 1
			bar:SetValue((t - fadeDur) / castDur)
		elseif(t < fadeDur + castDur + fadeDur) then
			a = 1 - (t - fadeDur - castDur) / fadeDur
			bar:SetValue(1)
		else
			a = 0
			bar:SetValue(0)
		end
		bar:SetAlpha(a)
		label:SetAlpha(a)
	end)

	frame._castbar = wrapper
end

-- ============================================================
-- Portrait builder
-- ============================================================

local function BuildPortrait(frame, config, fakeUnit)
	if(not config.portrait) then return end

	local size = config.height

	local wrapper = CreateFrame('Frame', nil, frame)
	wrapper:SetSize(size, size)
	wrapper:SetPoint('TOPRIGHT', frame, 'TOPLEFT', -(C.Spacing.base), 0)
	wrapper:SetFrameLevel(frame:GetFrameLevel() + config.elementStrata.portrait)

	local bg = wrapper:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(wrapper)
	bg:SetColorTexture(0.08, 0.08, 0.08, 1)

	local tex = wrapper:CreateTexture(nil, 'ARTWORK')

	if(fakeUnit and fakeUnit.class) then
		local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[fakeUnit.class]
		if(classColor) then
			bg:SetColorTexture(classColor.r * 0.35, classColor.g * 0.35, classColor.b * 0.35, 1)
		end
		local coords = CLASS_ICON_TCOORDS[fakeUnit.class]
		if(coords) then
			tex:SetTexture([[Interface\GLUES\CHARACTERCREATE\UI-CHARACTERCREATE-CLASSES]])
			tex:SetTexCoord(unpack(coords))
			tex:SetPoint('CENTER', wrapper, 'CENTER', 0, 0)
			tex:SetSize(size * 0.7, size * 0.7)
		end
	end

	frame._portrait = wrapper
	frame._portraitBg = bg
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

	-- Anchor by canonical statusText.position. Mirrors the top/center/bottom
	-- rows used by Elements/Status/StatusText.lua so the preview matches the
	-- live frame layout instead of guessing absolute anchor coordinates.
	local anchorTo = frame._healthBar or overlay
	local position = stConfig.position
	if(position == 'top') then
		text:SetPoint('TOP', anchorTo, 'TOP', 0, 0)
	elseif(position == 'center') then
		text:SetPoint('CENTER', anchorTo, 'CENTER', 0, 0)
	else
		text:SetPoint('BOTTOM', anchorTo, 'BOTTOM', 0, 0)
	end

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
	local wrapper = frame._healthWrapper
	local barWidth = config.width
	local healthPct = fakeUnit and fakeUnit.healthPct or 0.85
	local fillWidth = barWidth * healthPct
	local baseLevel = healthBar:GetFrameLevel()

	-- Shield bars parent to the health wrapper (sibling of healthBar) so that
	-- focus-mode dimming healthBar doesn't also dim the shields via effective
	-- alpha inheritance.
	local shieldParent = wrapper or healthBar

	-- Heal prediction — WHITE8x8 tinted bar, extends right from health fill edge.
	if(hc.healPrediction ~= false and fakeUnit and fakeUnit.incomingHeal) then
		local healBar = CreateFrame('StatusBar', nil, shieldParent)
		healBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
		healBar:SetFrameLevel(baseLevel + config.elementStrata.healPrediction)
		healBar:SetMinMaxValues(0, 1)
		healBar:SetValue(1)
		local hcc = hc.healPredictionColor
		healBar:SetStatusBarColor(hcc[1], hcc[2], hcc[3], hcc[4] or 0.4)
		healBar:SetPoint('TOPLEFT', healthBar, 'TOPLEFT', fillWidth, 0)
		healBar:SetPoint('BOTTOMLEFT', healthBar, 'BOTTOMLEFT', fillWidth, 0)
		healBar:SetWidth(math.max(1, barWidth * fakeUnit.incomingHeal))
		frame._healPredBar = healBar
	end

	-- Damage absorb — tiled stripe texture over the unfilled health region.
	if(hc.damageAbsorb ~= false and fakeUnit and fakeUnit.damageAbsorb) then
		local absorbBar = CreateFrame('Frame', nil, shieldParent)
		absorbBar:SetFrameLevel(baseLevel + config.elementStrata.damageAbsorb)
		local absorbWidth = barWidth * fakeUnit.damageAbsorb
		absorbBar:SetPoint('TOPLEFT', healthBar, 'TOPLEFT', fillWidth, 0)
		absorbBar:SetPoint('BOTTOMLEFT', healthBar, 'BOTTOMLEFT', fillWidth, 0)
		absorbBar:SetWidth(math.max(1, absorbWidth))

		local dc = hc.damageAbsorbColor
		local stripe = absorbBar:CreateTexture(nil, 'OVERLAY')
		stripe:SetTexture([[Interface\AddOns\Framed\Media\Textures\Stripe]])
		stripe:SetVertexColor(dc[1], dc[2], dc[3], dc[4] or 0.6)
		stripe:SetHorizTile(true)
		stripe:SetVertTile(true)
		stripe:SetAllPoints(absorbBar)
		frame._damageAbsorbBar = absorbBar
	end

	-- Heal absorb — same stripe pattern, anchored from the right edge of the fill.
	if(hc.healAbsorb ~= false and fakeUnit and fakeUnit.healAbsorb) then
		local healAbsorbBar = CreateFrame('Frame', nil, shieldParent)
		healAbsorbBar:SetFrameLevel(baseLevel + config.elementStrata.healAbsorb)
		local absorbWidth = barWidth * fakeUnit.healAbsorb
		healAbsorbBar:SetPoint('TOPRIGHT', healthBar, 'TOPLEFT', fillWidth, 0)
		healAbsorbBar:SetPoint('BOTTOMRIGHT', healthBar, 'BOTTOMLEFT', fillWidth, 0)
		healAbsorbBar:SetWidth(math.max(1, absorbWidth))

		local hac = hc.healAbsorbColor
		local stripe = healAbsorbBar:CreateTexture(nil, 'OVERLAY')
		stripe:SetTexture([[Interface\AddOns\Framed\Media\Textures\Stripe]])
		stripe:SetVertexColor(hac[1], hac[2], hac[3], hac[4] or 0.5)
		stripe:SetHorizTile(true)
		stripe:SetVertTile(true)
		stripe:SetAllPoints(healAbsorbBar)
		frame._healAbsorbBar = healAbsorbBar
	end

	-- Overshield — additive glow tile on the right edge of the health bar.
	if(hc.overAbsorb ~= false and fakeUnit and fakeUnit.overAbsorb) then
		local overWrapper = CreateFrame('Frame', nil, shieldParent)
		overWrapper:SetFrameLevel(baseLevel + config.elementStrata.overAbsorb)
		overWrapper:SetPoint('TOPRIGHT', healthBar, 'TOPRIGHT', 0, 0)
		overWrapper:SetPoint('BOTTOMRIGHT', healthBar, 'BOTTOMRIGHT', 0, 0)
		overWrapper:SetWidth(4)

		local overGlow = overWrapper:CreateTexture(nil, 'OVERLAY')
		overGlow:SetTexture([[Interface\AddOns\Framed\Media\Textures\OverAbsorbGlow]])
		overGlow:SetTexCoord(1, 0, 0, 1)
		overGlow:SetVertexColor(1, 1, 1, 1)
		overGlow:SetBlendMode('ADD')
		overGlow:SetAllPoints(overWrapper)
		frame._overAbsorbGlow = overWrapper
	end
end

-- ============================================================
-- Aura indicator builders (extracted to Preview/PreviewAuras.lua)
-- ============================================================

-- ============================================================
-- Shared: build all elements and apply fake data
-- ============================================================

local function BuildAllElements(frame, config, fakeUnit, auraConfig, animated)
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
	BuildPortrait(frame, config, fakeUnit)
	BuildStatusText(frame, config, fakeUnit)
	BuildShieldsAndAbsorbs(frame, config, fakeUnit)

	-- Build aura indicators (delegated to PreviewAuras)
	if(auraConfig) then
		F.PreviewAuras.BuildAll(frame, auraConfig, animated)
	end

	-- Apply fake unit data with config-aware colors and text formats
	if(fakeUnit) then
		applyHealthColor(frame._healthBar, config, fakeUnit)
		applyHealthLossColor(frame._healthBar._bg, config, fakeUnit)

		if(animated) then
			-- Incremental-hit cycle: mimics real combat health — discrete drops
			-- with dwells between, ending in a refill. Each transition respects
			-- config.health.smooth: smooth eases between from/to; instant snaps
			-- and holds for the same duration so cycle length is stable.
			local healthBar = frame._healthBar
			-- from/to identical = hold. Different = transition (smooth or snap).
			local STEPS = {
				{ dur = 0.8,  from = 1.00, to = 1.00 },  -- dwell at full
				{ dur = 0.22, from = 1.00, to = 0.72 },  -- hit
				{ dur = 0.5,  from = 0.72, to = 0.72 },  -- dwell
				{ dur = 0.22, from = 0.72, to = 0.45 },  -- hit
				{ dur = 0.5,  from = 0.45, to = 0.45 },  -- dwell
				{ dur = 0.28, from = 0.45, to = 0.12 },  -- hit (bigger — shows low-end gradient)
				{ dur = 0.8,  from = 0.12, to = 0.12 },  -- low dwell (loss color readable)
				{ dur = 1.2,  from = 0.12, to = 1.00 },  -- refill
			}
			local applyColorsForPct = function(pct)
				applyHealthColor(healthBar, config, fakeUnit, pct)
				applyHealthLossColor(healthBar._bg, config, fakeUnit, pct)
			end
			local setBarTo = function(v)
				healthBar:SetValue(v)
				applyColorsForPct(v)
				if(frame._healthText) then
					frame._healthText:SetText(formatHealthText(v, config.health.textFormat))
				end
			end

			local runStep
			runStep = function(bar, idx)
				if(not bar:IsShown()) then return end
				local step = STEPS[idx]
				if(not step) then runStep(bar, 1); return end

				if(step.from == step.to or not config.health.smooth) then
					-- Hold, or instant snap + hold for the same duration
					setBarTo(step.to)
					Widgets.StartAnimation(bar, 'healthStep', 0, 1, step.dur,
						function() end,
						function(f) runStep(f, idx + 1) end)
				else
					-- Smooth transition with ease-out
					Widgets.StartAnimation(bar, 'healthStep', 0, 1, step.dur,
						function(f, t)
							local inv = 1 - t
							local eased = 1 - inv * inv * inv
							setBarTo(step.from + (step.to - step.from) * eased)
						end,
						function(f) runStep(f, idx + 1) end)
				end
			end
			runStep(healthBar, 1)
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
		'_nameText', '_castbar', '_targetHighlight', '_iconOverlay', '_markerOverlay', '_auraGroups',
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

function F.PreviewFrame.Create(parent, config, fakeUnit, realFrame, auraConfig, animated, unitType)
	local frame = CreateFrame('Frame', nil, parent)

	if(realFrame) then
		-- Edit Mode: match effective scale so config dimensions render at the
		-- correct visual size relative to the real frame.
		local targetScale = realFrame:GetEffectiveScale()
		local parentScale = frame:GetParent():GetEffectiveScale()
		if(parentScale > 0) then
			frame:SetScale(targetScale / parentScale)
		end
	end
	Widgets.SetSize(frame, config.width, config.height)

	-- Edit Mode: gated by the user's animation toggle.
	-- Settings preview / explicit override: caller passes `animated` directly.
	if(animated == nil) then
		animated = realFrame and F.PreviewManager.IsAnimationEnabled() or false
	end
	frame._animated = animated
	frame._unitType = unitType
	BuildAllElements(frame, config, fakeUnit, auraConfig, animated)

	return frame
end

-- ============================================================
-- Public: Rebuild preview in-place with new config
-- ============================================================

function F.PreviewFrame.UpdateFromConfig(frame, config, auraConfig, animated, unitType)
	DestroyChildren(frame)
	Widgets.SetSize(frame, config.width, config.height)
	if(animated == nil) then
		animated = frame._animated
		if(animated == nil) then
			animated = F.PreviewManager.IsAnimationEnabled()
		end
	end
	frame._animated = animated
	if(unitType ~= nil) then
		frame._unitType = unitType
	end
	BuildAllElements(frame, config, frame._fakeUnit, auraConfig, animated)
end
