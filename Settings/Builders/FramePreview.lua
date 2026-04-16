local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants

F.Settings = F.Settings or {}
F.Settings.FramePreview = {}
local FP = F.Settings.FramePreview

-- ============================================================
-- Solo fake unit data (mirrors PreviewManager.SOLO_FAKES with
-- health at 0.85 so loss color is passively visible)
-- ============================================================

local function getPlayerClass()
	local _, class = UnitClass('player')
	return class or 'PALADIN'
end

local SOLO_FAKES = {
	player       = function() return {
		name = UnitName('player') or 'You', class = getPlayerClass(),
		healthPct = 0.85, powerPct = 0.7,
		incomingHeal = 0.15, damageAbsorb = 0.10, healAbsorb = 0.05,
	} end,
	target       = function() return {
		name = 'Target Dummy', class = 'WARRIOR',
		healthPct = 0.85, powerPct = 0.7,
		incomingHeal = 0.10, damageAbsorb = 0.12,
	} end,
	targettarget = function() return {
		name = 'Healbot', class = 'PRIEST',
		healthPct = 0.85, powerPct = 0.95,
		incomingHeal = 0.08, overAbsorb = true,
	} end,
	focus        = function() return {
		name = 'Focus Target', class = 'MAGE',
		healthPct = 0.85, powerPct = 0.9,
		damageAbsorb = 0.15,
	} end,
	pet          = function() return {
		name = 'Pet', class = 'HUNTER',
		healthPct = 0.85, powerPct = 0.6,
	} end,
}

-- ============================================================
-- State
-- ============================================================

local activePreview = nil    -- current preview card frame
local activeUnitType = nil   -- 'player', 'target', 'party', etc.
local previewFrames = {}     -- array of child preview frames
local framePool = {}         -- recycled preview frames

-- ============================================================
-- Frame pool
-- ============================================================

local function AcquireFrame(parent)
	local frame = tremove(framePool)
	if(frame) then
		frame:SetParent(parent)
		frame:Show()
		return frame
	end
	return nil
end

local function ReleaseFrame(frame)
	frame:Hide()
	frame:SetParent(nil)
	tinsert(framePool, frame)
end

local function DrainPool()
	for _, frame in next, framePool do
		frame:Hide()
		frame:SetParent(nil)
	end
	wipe(framePool)
end

-- ============================================================
-- Config helpers
-- ============================================================

local function getUnitConfig(unitType)
	local presetName = F.Settings.GetEditingPreset()
	return F.Config:Get('presets.' .. presetName .. '.unitConfigs.' .. unitType)
end

-- ============================================================
-- CONFIG_CHANGED dispatch
-- ============================================================

local STRUCTURAL_KEYS = {
	width = true, height = true, showPower = true,
	orientation = true, unitsPerColumn = true, maxColumns = true, spacing = true,
}

local rebuildPending = false

local function debouncedRebuild()
	if(rebuildPending) then return end
	rebuildPending = true
	C_Timer.After(0.05, function()
		rebuildPending = false
		FP.RebuildPreview()
	end)
end

local function onConfigChanged(path)
	if(not activePreview or not activeUnitType) then return end

	local preset, unit, key = path:match('presets%.([^%.]+)%.unitConfigs%.([^%.]+)%.(.+)')
	if(not preset) then return end

	if(preset ~= F.Settings.GetEditingPreset()) then return end
	if(unit ~= activeUnitType) then return end

	local config = getUnitConfig(activeUnitType)
	if(not config) then return end

	if(STRUCTURAL_KEYS[key:match('^[^%.]+')]) then
		debouncedRebuild()
	else
		for _, frame in next, previewFrames do
			F.PreviewFrame.UpdateFromConfig(frame, config, nil)
		end
	end
end

local configListenerHandle = nil

local function RegisterConfigListener()
	configListenerHandle = F.EventBus:Register('CONFIG_CHANGED', onConfigChanged, 'FramePreview.ConfigListener')
end

local function UnregisterConfigListener()
	if(configListenerHandle) then
		F.EventBus:Unregister('CONFIG_CHANGED', 'FramePreview.ConfigListener')
		configListenerHandle = nil
	end
end

-- ============================================================
-- RebuildPreview
-- ============================================================

function FP.RebuildPreview()
	if(not activePreview or not activeUnitType) then return end

	for _, frame in next, previewFrames do
		ReleaseFrame(frame)
	end
	wipe(previewFrames)

	local viewport = activePreview._viewContent
	local config = getUnitConfig(activeUnitType)
	if(not viewport or not config) then return end

	local viewH = config.height + 20
	activePreview._viewport:SetHeight(viewH)
	viewport:SetHeight(viewH)

	if(SOLO_FAKES[activeUnitType]) then
		RenderSoloPreview(viewport, activeUnitType)
	end
end

-- ============================================================
-- Solo preview rendering
-- ============================================================

local function RenderSoloPreview(viewport, unitType)
	local config = getUnitConfig(unitType)
	if(not config) then return end

	local fakeFn = SOLO_FAKES[unitType]
	local fakeUnit = fakeFn and fakeFn() or { name = 'Unit', class = 'WARRIOR', healthPct = 0.85, powerPct = 0.7 }

	local frame = AcquireFrame(viewport) or F.PreviewFrame.Create(viewport, config, fakeUnit, nil, nil)
	if(frame._config) then
		F.PreviewFrame.UpdateFromConfig(frame, config, nil)
	end

	frame._fakeUnit = fakeUnit
	frame:ClearAllPoints()
	frame:SetPoint('TOPLEFT', viewport, 'TOPLEFT', 0, 0)

	previewFrames[1] = frame
end

-- ============================================================
-- Public: Build the preview card
-- ============================================================

function FP.BuildPreviewCard(parent, width, unitType)
	local card, inner, cy = Widgets.StartCard(parent, width, 0)
	Widgets.CreateAccentBar(card, 'top')

	-- Header row
	local title = Widgets.CreateFontString(inner, C.Font.sizeMedium, C.Colors.textActive)
	title:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cy)
	title:SetText('Preview — ' .. (unitType:sub(1, 1):upper() .. unitType:sub(2)))
	cy = cy - C.Font.sizeMedium - 8

	-- Preview viewport (horizontal scroll for overflow)
	local viewport = CreateFrame('ScrollFrame', nil, inner)
	local viewContent = CreateFrame('Frame', nil, viewport)
	viewport:SetScrollChild(viewContent)
	viewport:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cy)
	viewport:SetPoint('RIGHT', inner, 'RIGHT', 0, 0)

	-- Horizontal mouse wheel scrolling for wide group layouts
	viewport:EnableMouseWheel(true)
	viewport:SetScript('OnMouseWheel', function(self, delta)
		local maxScroll = math.max(0, viewContent:GetWidth() - self:GetWidth())
		local current = self:GetHorizontalScroll()
		self:SetHorizontalScroll(math.max(0, math.min(maxScroll, current - delta * 30)))
	end)

	local config = getUnitConfig(unitType)
	local viewH = config and (config.height + 20) or 60
	viewport:SetHeight(viewH)
	-- Width derived from parent after layout; content sizes to fit frames
	viewContent:SetHeight(viewH)
	cy = cy - viewH - 8

	-- Render the preview
	activeUnitType = unitType
	RenderSoloPreview(viewContent, unitType)

	RegisterConfigListener()

	F.EventBus:Register('EDITING_PRESET_CHANGED', function()
		FP.RebuildPreview()
	end, 'FramePreview.PresetListener')

	Widgets.EndCard(card, parent, cy)

	activePreview = card
	card._viewport = viewport
	card._viewContent = viewContent
	card._unitType = unitType

	return card
end

-- ============================================================
-- Public: Destroy preview
-- ============================================================

function FP.Destroy()
	for _, frame in next, previewFrames do
		ReleaseFrame(frame)
	end
	wipe(previewFrames)
	DrainPool()

	UnregisterConfigListener()
	F.EventBus:Unregister('EDITING_PRESET_CHANGED', 'FramePreview.PresetListener')

	if(activePreview) then
		activePreview:Hide()
		activePreview:SetParent(nil)
		activePreview = nil
	end
	activeUnitType = nil
end
