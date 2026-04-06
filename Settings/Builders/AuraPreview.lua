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

-- ── Render aura indicators from config ──────────────────────
function AuraPreview.Render(frame, unitType, activeGroupKey, activeIndicatorName)
	-- Clear existing aura groups
	for _, group in next, frame._auraGroups do
		group:Hide()
		group:SetParent(nil)
	end
	wipe(frame._auraGroups)

	-- Read live config
	local config = F.Config and F.Config:GetUnitConfig and F.Config:GetUnitConfig(unitType)
	if(not config) then return end

	-- Build aura indicators using PreviewAuras if available
	if(F.PreviewAuras and F.PreviewAuras.BuildForSettingsPreview) then
		F.PreviewAuras.BuildForSettingsPreview(frame, config, unitType)
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
