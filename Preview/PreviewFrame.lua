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
		return c[1], c[2], c[3]
	end
	return 0.5, 0.5, 0.5
end

local POWER_COLOR = { 0.0, 0.44, 0.87, 1 }  -- Match oUF mana override

-- ============================================================
-- Health bar builder
-- ============================================================

local function BuildHealthBar(frame, config, healthHeight)
	local wrapper = CreateFrame('Frame', nil, frame)
	wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
	wrapper:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
	wrapper:SetHeight(healthHeight)

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

	-- Health text (pixel-perfect: match StyleBuilder font, anchor, outline, shadow)
	local hc = config.health
	if(hc and hc.showText ~= false) then
		local text = Widgets.CreateFontString(wrapper, hc.fontSize, C.Colors.textActive)
		text:SetFont(F.Media.GetActiveFont(), hc.fontSize, hc.outline or '')
		if(hc.shadow ~= false) then
			text:SetShadowOffset(1, -1)
			text:SetShadowColor(0, 0, 0, 1)
		end
		local anchor = hc.textAnchor or 'RIGHT'
		text:SetPoint(anchor, wrapper, anchor, (hc.textAnchorX or 0) + 1, hc.textAnchorY or 0)
		frame._healthText = text
	end
end

-- ============================================================
-- Power bar builder
-- ============================================================

local function BuildPowerBar(frame, config, powerHeight)
	if(config.showPower == false) then return end

	local wrapper = CreateFrame('Frame', nil, frame)
	wrapper:SetHeight(powerHeight)

	if(config.power and config.power.position == 'top') then
		wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
		wrapper:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
		frame._healthWrapper:ClearAllPoints()
		frame._healthWrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -powerHeight)
		frame._healthWrapper:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, -powerHeight)
	else
		wrapper:SetPoint('TOPLEFT', frame._healthWrapper, 'BOTTOMLEFT', 0, 0)
		wrapper:SetPoint('TOPRIGHT', frame._healthWrapper, 'BOTTOMRIGHT', 0, 0)
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
		local text = Widgets.CreateFontString(wrapper, pc.fontSize, C.Colors.textActive)
		text:SetFont(F.Media.GetActiveFont(), pc.fontSize, pc.outline or '')
		if(pc.shadow ~= false) then
			text:SetShadowOffset(1, -1)
			text:SetShadowColor(0, 0, 0, 1)
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

	local text = Widgets.CreateFontString(frame, nc.fontSize, C.Colors.textActive)
	text:SetFont(F.Media.GetActiveFont(), nc.fontSize, nc.outline or '')
	if(nc.shadow ~= false) then
		text:SetShadowOffset(1, -1)
		text:SetShadowColor(0, 0, 0, 1)
	end

	local anchor = frame._healthWrapper or frame
	local pt = nc.anchor or 'LEFT'
	text:SetPoint(pt, anchor, pt, nc.anchorX or 0, nc.anchorY or 0)
	text:SetText(fakeUnit and fakeUnit.name or 'Unit Name')

	-- Color mode
	if(nc.colorMode == 'class' and fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		text:SetTextColor(r, g, b, 1)
	elseif(nc.colorMode == 'custom' and nc.customColor) then
		text:SetTextColor(nc.customColor[1], nc.customColor[2], nc.customColor[3], 1)
	end

	frame._nameText = text
end

-- ============================================================
-- Public: Create preview frame
-- ============================================================

function F.PreviewFrame.Create(parent, config, fakeUnit)
	local frame = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(frame, config.width, config.height)

	-- Dark background (match StyleBuilder)
	local bg = frame:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(frame)
	local bgC = C.Colors.background
	bg:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 1)
	frame._bg = bg

	-- Calculate bar heights
	local powerHeight = (config.power and config.power.height) or 8
	local healthHeight = config.height - powerHeight

	-- Build structural elements
	BuildHealthBar(frame, config, healthHeight)
	BuildPowerBar(frame, config, powerHeight)
	BuildNameText(frame, config, fakeUnit)

	-- Apply fake unit data
	if(fakeUnit) then
		local r, g, b = getClassColor(fakeUnit.class)
		frame._healthBar:SetStatusBarColor(r, g, b, 1)
		frame._healthBar:SetValue(fakeUnit.healthPct or 1)
		if(frame._healthText) then
			frame._healthText:SetText(math.floor((fakeUnit.healthPct or 1) * 100) .. '%')
		end
		if(frame._powerBar) then
			frame._powerBar:SetValue(fakeUnit.powerPct or 0.8)
		end
		if(frame._powerText) then
			frame._powerText:SetText(math.floor((fakeUnit.powerPct or 0.8) * 100) .. '%')
		end
	end

	frame._config = config
	frame._fakeUnit = fakeUnit
	return frame
end
