local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

local CHECK_H = 22

local AuraPreview = {}
F.Settings.AuraPreview = AuraPreview

-- ── Player class color for preview ──────────────────────────
local function getPlayerClassColor()
	local _, classFile = UnitClass('player')
	if(classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]) then
		local c = RAID_CLASS_COLORS[classFile]
		return c.r, c.g, c.b
	end
	return 0.5, 0.5, 0.5
end

-- ── Read configured frame size for a specific unit type ─────
local function getFrameSize(unitType, maxWidth)
	local w, h = 120, 40
	if(F.Config and F.Config.Get) then
		local presetName = F.Settings and F.Settings.GetEditingPreset and F.Settings.GetEditingPreset()
		if(presetName and unitType) then
			local cw = F.Config:Get('presets.' .. presetName .. '.unitConfigs.' .. unitType .. '.width')
			local ch = F.Config:Get('presets.' .. presetName .. '.unitConfigs.' .. unitType .. '.height')
			if(cw) then w = cw end
			if(ch) then h = ch end
		end
	end
	-- Clamp to card width if provided, preserving aspect ratio
	if(maxWidth and w > maxWidth) then
		local scale = maxWidth / w
		w = maxWidth
		h = math.floor(h * scale + 0.5)
	end
	return w, h
end

-- ── Aura group keys ─────────────────────────────────────────
local AURA_GROUPS = { 'buffs', 'debuffs', 'externals', 'defensives', 'dispellable',
                      'missingBuffs', 'privateAuras', 'lossOfControl', 'crowdControl', 'targetedSpells' }

-- ── Build the preview frame (just the mock unit frame) ──────
local function createPreviewFrame(parent, unitType, maxWidth)
	local fw, fh = getFrameSize(unitType, maxWidth)
	local frame = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	frame:SetSize(fw, fh)
	frame:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	frame:SetBackdropColor(0.1, 0.1, 0.18, 1)
	frame:SetBackdropBorderColor(0.23, 0.23, 0.35, 1)

	-- Health bar (fills the entire frame)
	local health = CreateFrame('StatusBar', nil, frame)
	health:SetPoint('TOPLEFT', frame, 'TOPLEFT', 1, -1)
	health:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -1, 1)
	health:SetStatusBarTexture(F.Media and F.Media.GetActiveBarTexture and F.Media.GetActiveBarTexture() or [[Interface\BUTTONS\WHITE8x8]])
	health:SetMinMaxValues(0, 1)
	health:SetValue(1)
	local r, g, b = getPlayerClassColor()
	health:SetStatusBarColor(r, g, b, 1)
	frame._health = health
	frame._auraGroups = {}

	return frame
end

-- ── Render aura indicators from config (full size, no scaling) ─
function AuraPreview.Render(frame, unitType, activeGroupKey, activeIndicatorName)
	-- Clear existing aura groups (including overlay frames parented elsewhere)
	for _, group in next, frame._auraGroups do
		if(group._healthOverlay) then
			group._healthOverlay:Hide()
			group._healthOverlay:SetParent(nil)
		end
		group:Hide()
		group:SetParent(nil)
	end
	wipe(frame._auraGroups)

	-- Use the frame's stored unit type for sizing (matches "Configure for")
	local sizeUnitType = frame._unitType or unitType
	-- Resize frame to match current config (respect stored max width)
	local fw, fh = getFrameSize(sizeUnitType, frame._maxWidth)
	frame:SetSize(fw, fh)

	-- Read live aura config from active editing preset
	if(not F.Config or not F.Config.Get) then return end
	local presetName = F.Settings and F.Settings.GetEditingPreset and F.Settings.GetEditingPreset()
	if(not presetName) then return end
	local rawAuraConfig = F.Config:Get('presets.' .. presetName .. '.auras.' .. unitType)
	if(not rawAuraConfig) then return end

	-- Wire up frame fields required by PreviewAuras
	frame._healthWrapper = frame._health
	frame._healthBar     = frame._health
	frame._width         = fw
	frame._height        = fh

	-- When "Show All" is active, force-enable every group for the build
	-- so disabled groups still render in the preview.
	local showAll = frame._showAll
	local buildConfig = rawAuraConfig
	if(showAll) then
		buildConfig = {}
		for key, val in next, rawAuraConfig do
			if(type(val) == 'table') then
				buildConfig[key] = setmetatable({ enabled = true }, { __index = val })
			else
				buildConfig[key] = val
			end
		end
	end

	-- Render using PreviewAuras.BuildAll (with animations like edit mode)
	if(F.PreviewAuras and F.PreviewAuras.BuildAll) then
		F.PreviewAuras.BuildAll(frame, buildConfig, true)
	end

	-- Apply dimming based on show-all toggle and active group
	local highlightKey = (showAll or not activeGroupKey) and nil or activeGroupKey
	F.PreviewAuras.SetAuraGroupAlpha(frame, highlightKey)
end

-- ── Card builder for CardGrid ───────────────────────────────
-- Signature: function(parent, width, ...)
-- Stored on Settings so panels can reference it.
function AuraPreview.BuildPreviewCard(parent, width)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)

	-- Capture the unit type from "Configure for" at build time
	local unitType = F.Settings.GetEditingUnitType and F.Settings.GetEditingUnitType() or 'party'

	-- Preview frame, centered horizontally, clamped to card inner width
	local innerWidth = width - Widgets.CARD_PADDING * 2
	local preview = createPreviewFrame(inner, unitType, innerWidth)
	preview._maxWidth = innerWidth
	preview._unitType = unitType
	preview:ClearAllPoints()
	preview:SetPoint('TOP', inner, 'TOP', 0, cy)

	-- Point Settings to this preview so UpdateAuraPreviewDimming can find it.
	-- On panel switch, SetActivePanel restores this from scroll._ownedPreview.
	local Settings = F.Settings
	Settings._auraPreview = preview

	local previewH = preview:GetHeight()
	cy = cy - previewH - C.Spacing.normal

	-- Show All toggle
	local showAllCB = Widgets.CreateCheckButton(inner, 'Show All Auras', function(checked)
		preview._showAll = checked
		-- Re-render with current dimming state
		Settings.UpdateAuraPreviewDimming(Settings._activePreviewGroup, nil)
	end)
	showAllCB:SetChecked(false)
	showAllCB:ClearAllPoints()
	Widgets.SetPoint(showAllCB, 'TOPLEFT', inner, 'TOPLEFT', 0, cy)
	cy = cy - CHECK_H

	-- Initial render
	local panelId = Settings._activePanelId
	AuraPreview.Render(preview, unitType, panelId, nil)
	Settings._activePreviewGroup = panelId

	Widgets.EndCard(card, parent, cy)
	return card
end

-- ── Update dimming (called by panels on config change) ──────
function AuraPreview.UpdateDimming(activeGroupKey, activeIndicatorName)
	local Settings = F.Settings
	if(not Settings._auraPreview) then return end
	Settings._activePreviewGroup = activeGroupKey
	-- Use the preview's stored unit type (matches "Configure for" at build time)
	local unitType = Settings._auraPreview._unitType or (Settings.GetEditingUnitType and Settings.GetEditingUnitType()) or 'player'
	AuraPreview.Render(Settings._auraPreview, unitType, activeGroupKey, activeIndicatorName)
end

-- ── Lightweight dispel overlay alpha update (no rebuild) ────
function AuraPreview.UpdateDispelAlpha(alpha)
	local Settings = F.Settings
	if(not Settings._auraPreview) then return end
	if(F.PreviewAuras and F.PreviewAuras.UpdateDispelOverlayAlpha) then
		F.PreviewAuras.UpdateDispelOverlayAlpha(Settings._auraPreview, alpha)
	end
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
