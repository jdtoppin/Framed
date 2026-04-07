local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

local CHECK_H = 22

local AuraPreview = {}
F.Settings.AuraPreview = AuraPreview

-- Map panel IDs (lowercase) to aura group keys used in _auraGroups
local PANEL_TO_GROUP = {
	targetedspells = 'targetedSpells',
	dispels        = 'dispellable',
	missingbuffs   = 'missingBuffs',
	privateauras   = 'privateAuras',
	lossofcontrol  = 'lossOfControl',
	crowdcontrol   = 'crowdControl',
}

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
	-- Clear existing aura groups (including elements parented elsewhere)
	for _, group in next, frame._auraGroups do
		if(group._healthOverlay) then
			group._healthOverlay:Hide()
			group._healthOverlay:SetParent(nil)
		end
		if(group._elements) then
			for _, el in next, group._elements do
				if(el:GetParent() ~= group) then
					el:Hide()
					el:SetParent(nil)
				end
			end
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

	-- Render using PreviewAuras.BuildAll (animated for live preview)
	if(F.PreviewAuras and F.PreviewAuras.BuildAll) then
		F.PreviewAuras.BuildAll(frame, rawAuraConfig, true)
	end

	-- Apply dimming: "Show All" undims every group, otherwise highlight the active panel
	local highlightKey
	if(not frame._showAll and activeGroupKey) then
		highlightKey = PANEL_TO_GROUP[activeGroupKey] or activeGroupKey
	end
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

-- ── Update dimming (lightweight — only changes group alpha, no rebuild) ──
function AuraPreview.UpdateDimming(activeGroupKey, activeIndicatorName)
	local Settings = F.Settings
	if(not Settings._auraPreview) then return end
	Settings._activePreviewGroup = activeGroupKey
	local highlightKey
	if(not Settings._auraPreview._showAll and activeGroupKey) then
		highlightKey = PANEL_TO_GROUP[activeGroupKey] or activeGroupKey
	end
	F.PreviewAuras.SetAuraGroupAlpha(Settings._auraPreview, highlightKey)
end

-- ── Full rebuild (called after config changes that affect the preview) ──
function AuraPreview.Rebuild()
	local Settings = F.Settings
	if(not Settings._auraPreview) then return end
	local unitType = Settings._auraPreview._unitType or (Settings.GetEditingUnitType and Settings.GetEditingUnitType()) or 'player'
	AuraPreview.Render(Settings._auraPreview, unitType, Settings._activePreviewGroup, nil)
end

-- ── Lightweight dispel overlay alpha update (no rebuild) ────
function AuraPreview.UpdateDispelAlpha(alpha)
	local Settings = F.Settings
	if(not Settings._auraPreview) then return end
	if(F.PreviewAuras and F.PreviewAuras.UpdateDispelOverlayAlpha) then
		F.PreviewAuras.UpdateDispelOverlayAlpha(Settings._auraPreview, alpha)
	end
end

-- ── Auto-rebuild on aura config changes ─────────────────────
F.EventBus:Register('CONFIG_CHANGED', function(path)
	if(not path or not path:find('%.auras%.')) then return end
	if(not F.Settings._auraPreview) then return end
	AuraPreview.Rebuild()
end, 'AuraPreview.AutoRebuild')

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
