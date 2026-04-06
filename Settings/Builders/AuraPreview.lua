local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets
local PI = F.PreviewIndicators

local PREVIEW_W = 140
local PREVIEW_H = 36
local HEALTH_H  = 18
local POWER_H   = 4
local NAME_SIZE  = 9
local AURA_ICON_SIZE = 10

-- Scale factor applied to configured icon sizes for the mini preview
local MINI_SCALE   = 0.60
local MINI_SIZE_MIN = 6

local AuraPreview = {}
F.Settings.AuraPreview = AuraPreview

-- ── Fake unit data for preview ──────────────────────────────
local FAKE_NAMES = { 'Healbot', 'Tankbro', 'Dpsguy', 'Rangedps', 'Offtank' }
local FAKE_CLASS_COLORS = {
	{ 0.96, 0.55, 0.73 }, -- Paladin pink
	{ 1.00, 0.49, 0.04 }, -- Warrior orange
	{ 0.00, 0.44, 0.87 }, -- Shaman blue
	{ 0.64, 0.19, 0.79 }, -- Warlock purple
	{ 0.00, 0.98, 0.61 }, -- Monk green
}

-- ── Build the preview frame ─────────────────────────────────
function AuraPreview.Create(parent)
	local frame = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	frame:SetSize(PREVIEW_W, PREVIEW_H)
	frame:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	frame:SetBackdropColor(0.1, 0.1, 0.18, 1)
	frame:SetBackdropBorderColor(0.23, 0.23, 0.35, 1)

	-- Health bar
	local health = CreateFrame('StatusBar', nil, frame)
	health:SetPoint('TOPLEFT', frame, 'TOPLEFT', 2, -2)
	health:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -2, -2)
	health:SetHeight(HEALTH_H)
	health:SetStatusBarTexture(F.Media and F.Media.GetActiveBarTexture and F.Media.GetActiveBarTexture() or [[Interface\BUTTONS\WHITE8x8]])
	health:SetMinMaxValues(0, 1)
	health:SetValue(1)
	local classColor = FAKE_CLASS_COLORS[1]
	health:SetStatusBarColor(classColor[1], classColor[2], classColor[3], 1)
	frame._health = health

	-- Name text
	local name = health:CreateFontString(nil, 'OVERLAY')
	name:SetFont(STANDARD_TEXT_FONT, NAME_SIZE, 'OUTLINE')
	name:SetPoint('LEFT', health, 'LEFT', 4, 0)
	name:SetText(FAKE_NAMES[1])
	frame._name = name

	-- Power bar
	local power = CreateFrame('StatusBar', nil, frame)
	power:SetPoint('TOPLEFT', health, 'BOTTOMLEFT', 0, -1)
	power:SetPoint('TOPRIGHT', health, 'BOTTOMRIGHT', 0, -1)
	power:SetHeight(POWER_H)
	power:SetStatusBarTexture(F.Media and F.Media.GetActiveBarTexture and F.Media.GetActiveBarTexture() or [[Interface\BUTTONS\WHITE8x8]])
	power:SetMinMaxValues(0, 1)
	power:SetValue(1)
	power:SetStatusBarColor(0.16, 0.16, 0.5, 1)
	frame._power = power

	-- Aura groups container
	frame._auraGroups = {}

	-- Eye toggle button
	local eye = CreateFrame('Button', nil, frame)
	eye:SetSize(12, 12)
	eye:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -3, -3)
	eye:SetNormalFontObject(GameFontNormalSmall)

	local eyeTex = eye:CreateTexture(nil, 'ARTWORK')
	eyeTex:SetAllPoints()
	eyeTex:SetTexture([[Interface\MINIMAP\Tracking\None]])
	eyeTex:SetVertexColor(0.6, 0.8, 0.6, 0.8)
	frame._eyeIcon = eyeTex

	frame._showAll = false
	eye:SetScript('OnClick', function()
		frame._showAll = not frame._showAll
		if(frame._showAll) then
			eyeTex:SetVertexColor(0.2, 1.0, 0.2, 1)
		else
			eyeTex:SetVertexColor(0.6, 0.8, 0.6, 0.8)
		end
		if(frame.UpdateDimming) then
			frame:UpdateDimming()
		end
	end)
	frame._eyeBtn = eye

	return frame
end

-- ── Scale a size value for the mini preview ─────────────────
local function miniSize(n)
	if(not n) then return MINI_SIZE_MIN end
	return math.max(MINI_SIZE_MIN, math.floor(n * MINI_SCALE + 0.5))
end

-- ── Return a shallow-copied indicator config with scaled sizes ─
local function scaledIndCfg(indCfg)
	local s = {}
	for k, v in next, indCfg do
		s[k] = v
	end
	if(s.iconSize)   then s.iconSize   = miniSize(s.iconSize)   end
	if(s.iconWidth)  then s.iconWidth  = miniSize(s.iconWidth)  end
	if(s.iconHeight) then s.iconHeight = miniSize(s.iconHeight) end
	if(s.barWidth)   then s.barWidth   = miniSize(s.barWidth)   end
	if(s.barHeight)  then s.barHeight  = miniSize(s.barHeight)  end
	if(s.rectWidth)  then s.rectWidth  = miniSize(s.rectWidth)  end
	if(s.rectHeight) then s.rectHeight = miniSize(s.rectHeight) end
	return s
end

-- ── Return a shallow-copied group config with scaled indicators ─
local function scaledGroupCfg(groupCfg)
	if(not groupCfg) then return nil end
	local g = {}
	for k, v in next, groupCfg do
		g[k] = v
	end
	-- Scale top-level size fields (flat groups: externals, defensives, dispellable)
	if(g.iconSize)   then g.iconSize   = miniSize(g.iconSize)   end
	if(g.iconWidth)  then g.iconWidth  = miniSize(g.iconWidth)  end
	if(g.iconHeight) then g.iconHeight = miniSize(g.iconHeight) end
	if(g.barWidth)   then g.barWidth   = miniSize(g.barWidth)   end
	if(g.barHeight)  then g.barHeight  = miniSize(g.barHeight)  end
	-- Scale per-indicator tables (buffs, debuffs)
	if(groupCfg.indicators) then
		local scaled = {}
		for key, indCfg in next, groupCfg.indicators do
			scaled[key] = scaledIndCfg(indCfg)
		end
		g.indicators = scaled
	end
	return g
end

-- ── Build scaled aura config for mini preview ────────────────
local AURA_GROUPS = { 'buffs', 'debuffs', 'externals', 'defensives', 'dispellable',
                      'missingBuffs', 'privateAuras', 'lossOfControl', 'crowdControl', 'targetedSpells' }

local function buildScaledAuraConfig(rawAuraConfig)
	local out = {}
	for _, key in next, AURA_GROUPS do
		out[key] = scaledGroupCfg(rawAuraConfig[key])
	end
	return out
end

-- ── Fallback: plain colored squares per group ────────────────
local GROUP_FALLBACK_COLORS = {
	buffs        = { 0.4, 0.8, 0.4, 0.8 },
	debuffs      = { 0.9, 0.3, 0.3, 0.8 },
	externals    = { 0.4, 0.6, 1.0, 0.8 },
	defensives   = { 1.0, 0.8, 0.2, 0.8 },
	dispellable  = { 0.3, 0.7, 1.0, 0.6 },
	missingBuffs = { 0.8, 0.8, 0.2, 0.8 },
	privateAuras = { 0.8, 0.5, 0.8, 0.8 },
	lossOfControl= { 1.0, 0.4, 0.0, 0.8 },
	crowdControl = { 0.9, 0.6, 0.1, 0.8 },
	targetedSpells={ 0.5, 0.9, 0.9, 0.8 },
}

local function buildFallbackGroup(frame, groupKey, groupCfg)
	local c = GROUP_FALLBACK_COLORS[groupKey] or { 0.5, 0.5, 0.5, 0.8 }
	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)

	local sq = groupFrame:CreateTexture(nil, 'OVERLAY')
	sq:SetSize(MINI_SIZE_MIN, MINI_SIZE_MIN)
	sq:SetColorTexture(c[1], c[2], c[3], c[4])
	sq:SetPoint('TOPLEFT', frame, 'TOPLEFT', 2, -2)

	return groupFrame
end

-- ── Render aura indicators from config ──────────────────────
function AuraPreview.Render(frame, unitType, activeGroupKey, activeIndicatorName)
	-- Clear existing aura groups
	for _, group in next, frame._auraGroups do
		group:Hide()
		group:SetParent(nil)
	end
	wipe(frame._auraGroups)

	-- Read live aura config from active editing preset
	if(not F.Config or not F.Config.Get) then return end
	local presetName = F.Settings and F.Settings.GetEditingPreset and F.Settings.GetEditingPreset()
	if(not presetName) then return end
	local rawAuraConfig = F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType)
	if(not rawAuraConfig) then return end

	-- Wire up frame fields required by PreviewAuras (health wrapper for dispellable overlay)
	frame._healthWrapper = frame._health
	frame._healthBar     = frame._health
	frame._width         = PREVIEW_W
	frame._height        = PREVIEW_H

	-- Build scaled copy of config so icon sizes fit the mini frame
	local scaledConfig = buildScaledAuraConfig(rawAuraConfig)

	-- Render using PreviewAuras.BuildAll when loaded; otherwise simple fallback squares
	if(F.PreviewAuras and F.PreviewAuras.BuildAll) then
		F.PreviewAuras.BuildAll(frame, scaledConfig, false)
	else
		-- PreviewAuras not yet loaded — create simple colored squares as placeholder
		for _, groupKey in next, AURA_GROUPS do
			local groupCfg = rawAuraConfig[groupKey]
			if(groupCfg and groupCfg.enabled) then
				local g = buildFallbackGroup(frame, groupKey, groupCfg)
				frame._auraGroups[groupKey] = g
			end
		end
	end

	-- Apply dimming
	frame.UpdateDimming = function(self)
		local f = self or frame
		if(f._showAll) then
			for _, group in next, f._auraGroups do
				group:SetAlpha(1.0)
			end
		else
			for groupKey, group in next, f._auraGroups do
				if(activeGroupKey and groupKey ~= activeGroupKey) then
					group:SetAlpha(0.2)
				else
					group:SetAlpha(1.0)
				end
			end
		end
	end

	frame:UpdateDimming()
end

-- ── Destroy ─────────────────────────────────────────────────
function AuraPreview.Destroy(frame)
	if(not frame) then return end
	for _, group in next, frame._auraGroups do
		group:Hide()
		group:SetParent(nil)
	end
	wipe(frame._auraGroups)
	frame:Hide()
	frame:SetParent(nil)
end
