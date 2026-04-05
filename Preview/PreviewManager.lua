local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode
local EditCache = F.EditCache

F.PreviewManager = {}
local PM = F.PreviewManager

-- ============================================================
-- State
-- ============================================================

local activeFrameKey = nil
local previewFrames = {}
local previewContainer = nil

-- Solo frame fake unit data
local function getPlayerClass()
	local _, class = UnitClass('player')
	return class or 'PALADIN'
end

local SOLO_FAKES = {
	player       = function() return { name = UnitName('player') or 'You', class = getPlayerClass(), healthPct = 1.0, powerPct = 1.0 } end,
	target       = function() return { name = 'Target Dummy',  class = 'WARRIOR',  healthPct = 1.0, powerPct = 1.0 } end,
	targettarget = function() return { name = 'Healbot',       class = 'PRIEST',   healthPct = 1.0, powerPct = 1.0 } end,
	focus        = function() return { name = 'Focus Target',  class = 'MAGE',     healthPct = 1.0, powerPct = 1.0 } end,
	pet          = function() return { name = 'Pet',           class = 'HUNTER',   healthPct = 1.0, powerPct = 1.0 } end,
}

local GROUP_TYPES = { party = true, raid = true, arena = true, boss = true }

local GROUP_FRAME_COUNTS = {
	party = 5,
	raid  = 20,
	arena = 3,
	boss  = 4,
}

local GROUP_FAKES = nil  -- Lazy-init from Preview.GetFakeUnits

function PM.GetGroupPreviewCount(frameKey)
	return GROUP_FRAME_COUNTS[frameKey]
end

function PM.SetGroupPreviewCount(frameKey, count)
	GROUP_FRAME_COUNTS[frameKey] = count
	if(activeFrameKey == frameKey) then
		PM.ShowPreview(activeFrameKey)
		-- Rebuild catchers so the overlay resizes to match
		F.EventBus:Fire('EDIT_MODE_PREVIEW_COUNT_CHANGED', frameKey)
	end
end

-- ============================================================
-- Config reading
-- ============================================================

local function getUnitConfig(frameKey)
	local preset = F.Settings.GetEditingPreset()
	local saved = F.Config:Get('presets.' .. preset .. '.unitConfigs.' .. frameKey)
	if(not saved) then return nil end
	local config = F.DeepCopy(saved)
	-- Overlay cached edits
	local edits = EditCache.GetEditsForFrame(frameKey)
	if(edits) then
		for path, value in next, edits do
			local keys = {}
			for k in path:gmatch('[^%.]+') do
				keys[#keys + 1] = k
			end
			local target = config
			for i = 1, #keys - 1 do
				if(type(target[keys[i]]) ~= 'table') then
					target[keys[i]] = {}
				end
				target = target[keys[i]]
			end
			target[keys[#keys]] = value
		end
	end
	return config
end

local function getAuraConfig(frameKey)
	local preset = F.Settings.GetEditingPreset()
	return F.Config:Get('presets.' .. preset .. '.auras.' .. frameKey)
end

-- ============================================================
-- Preview lifecycle
-- ============================================================

local function destroyPreviews()
	for _, pf in next, previewFrames do
		pf:Hide()
		pf:SetParent(nil)
	end
	previewFrames = {}
	activeFrameKey = nil
end

local function getPreviewContainer()
	if(not previewContainer) then
		local overlay = EditMode.GetOverlay()
		if(not overlay) then return nil end
		previewContainer = CreateFrame('Frame', nil, overlay)
		previewContainer:SetAllPoints(overlay)
		previewContainer:SetFrameLevel(overlay:GetFrameLevel() + 8)
	end
	previewContainer:Show()
	return previewContainer
end

-- ============================================================
-- Solo preview
-- ============================================================

-- Look up the real frame for a given frameKey
local function getRealFrame(frameKey)
	for _, def in next, EditMode.FRAME_KEYS do
		if(def.key == frameKey) then
			return def.getter()
		end
	end
	return nil
end

local function showSoloPreview(frameKey)
	local container = getPreviewContainer()
	if(not container) then return end

	local config = getUnitConfig(frameKey)
	if(not config) then return end

	local fakeFn = SOLO_FAKES[frameKey]
	local fakeUnit = fakeFn and fakeFn() or { name = frameKey, class = 'WARRIOR', healthPct = 0.8, powerPct = 0.5 }

	local realFrame = getRealFrame(frameKey)
	local auraConfig = getAuraConfig(frameKey)
	local pf = F.PreviewFrame.Create(container, config, fakeUnit, realFrame, auraConfig)

	-- Position centered on the real frame; size comes from config via Widgets.SetSize
	if(realFrame) then
		pf:SetPoint('CENTER', realFrame, 'CENTER', 0, 0)
	else
		local x = EditCache.Get(frameKey, 'position.x') or (config.position and config.position.x) or 0
		local y = EditCache.Get(frameKey, 'position.y') or (config.position and config.position.y) or 0
		pf:SetPoint('CENTER', UIParent, 'CENTER', x, y)
	end

	previewFrames[1] = pf
	pf:Show()
end

-- ============================================================
-- Group preview
-- ============================================================

local UNITS_PER_COLUMN = 5

local function showGroupPreview(frameKey)
	local container = getPreviewContainer()
	if(not container) then return end

	local config = getUnitConfig(frameKey)
	if(not config) then return end

	if(not GROUP_FAKES) then
		GROUP_FAKES = F.Preview.GetFakeUnits(5)
	end

	local count = GROUP_FRAME_COUNTS[frameKey] or 5

	-- Layout params — match the real header's layout logic (Units/Party.lua, Units/Raid.lua)
	local orientation = config.orientation
	local anchorPoint = config.anchorPoint
	local spacing = config.spacing
	local w = config.width
	local h = config.height
	local isVertical = (orientation == 'vertical')

	-- Primary axis: direction each unit steps within a column/row
	local primaryX, primaryY
	if(isVertical) then
		local goDown = (anchorPoint == 'TOPLEFT' or anchorPoint == 'TOPRIGHT')
		primaryX = 0
		primaryY = goDown and -(h + spacing) or (h + spacing)
	else
		local goRight = (anchorPoint == 'TOPLEFT' or anchorPoint == 'BOTTOMLEFT')
		primaryX = goRight and (w + spacing) or -(w + spacing)
		primaryY = 0
	end

	-- Secondary axis: direction columns/rows grow (perpendicular to primary)
	local colX, colY
	if(isVertical) then
		local goRight = (anchorPoint == 'TOPLEFT' or anchorPoint == 'BOTTOMLEFT')
		colX = goRight and (w + spacing) or -(w + spacing)
		colY = 0
	else
		local goDown = (anchorPoint == 'TOPLEFT' or anchorPoint == 'TOPRIGHT')
		colX = 0
		colY = goDown and -(h + spacing) or (h + spacing)
	end

	-- Position anchor from config (TOPLEFT for party/raid, CENTER for arena/boss)
	local posAnchor = (config.position and config.position.anchor) or 'CENTER'
	local baseX = EditCache.Get(frameKey, 'position.x') or (config.position and config.position.x) or 0
	local baseY = EditCache.Get(frameKey, 'position.y') or (config.position and config.position.y) or 0

	-- Look up real header frame for scale sync
	local realFrame = getRealFrame(frameKey)
	local auraConfig = getAuraConfig(frameKey)

	for i = 1, count do
		local fakeUnit = GROUP_FAKES[((i - 1) % #GROUP_FAKES) + 1]
		local varied = {
			name = fakeUnit.name .. (i > #GROUP_FAKES and (' ' .. i) or ''),
			class = fakeUnit.class,
			healthPct = math.max(0.1, (fakeUnit.healthPct or 0.8) - (i * 0.03)),
			powerPct = fakeUnit.powerPct or 0.5,
		}

		-- Column-based layout: 5 units per column, then wrap to next column
		local idx = i - 1
		local col = math.floor(idx / UNITS_PER_COLUMN)
		local row = idx % UNITS_PER_COLUMN
		local offX = row * primaryX + col * colX
		local offY = row * primaryY + col * colY

		local pf = F.PreviewFrame.Create(container, config, varied, realFrame, auraConfig)
		pf:SetPoint(anchorPoint, UIParent, posAnchor, baseX + offX, baseY + offY)
		previewFrames[i] = pf
		pf:Show()
	end

	-- Party pet preview — anchored beside the first party frame
	if(frameKey == 'party' and previewFrames[1]) then
		local petConfig = getUnitConfig('pet')
		if(petConfig) then
			local petFake = { name = 'Party Pet', class = 'HUNTER', healthPct = 0.75, powerPct = 0.6 }
			local petAuraConfig = getAuraConfig('pet')
			local petPf = F.PreviewFrame.Create(container, petConfig, petFake, realFrame, petAuraConfig)
			-- Match real pet anchor: beside owner (right for vertical TOPLEFT, below for horizontal)
			local gap = 2
			if(isVertical) then
				local onLeft = (anchorPoint == 'TOPRIGHT' or anchorPoint == 'BOTTOMRIGHT')
				if(onLeft) then
					petPf:SetPoint('TOPRIGHT', previewFrames[1], 'TOPLEFT', -gap, 0)
				else
					petPf:SetPoint('TOPLEFT', previewFrames[1], 'TOPRIGHT', gap, 0)
				end
			else
				local above = (anchorPoint == 'BOTTOMLEFT' or anchorPoint == 'BOTTOMRIGHT')
				if(above) then
					petPf:SetPoint('BOTTOMLEFT', previewFrames[1], 'TOPLEFT', 0, gap)
				else
					petPf:SetPoint('TOPLEFT', previewFrames[1], 'BOTTOMLEFT', 0, -gap)
				end
			end
			previewFrames[count + 1] = petPf
			petPf:Show()
		end
	end
end

-- ============================================================
-- Public API
-- ============================================================

function PM.ShowPreview(frameKey)
	destroyPreviews()
	activeFrameKey = frameKey

	if(GROUP_TYPES[frameKey]) then
		showGroupPreview(frameKey)
	else
		showSoloPreview(frameKey)
	end
end

function PM.HidePreview()
	destroyPreviews()
end

function PM.GetActiveFrameKey()
	return activeFrameKey
end

-- ============================================================
-- Events
-- ============================================================

F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
	if(frameKey) then
		PM.ShowPreview(frameKey)
	else
		PM.HidePreview()
	end
end, 'PreviewManager.selected')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	PM.HidePreview()
	if(previewContainer) then
		previewContainer:Hide()
		previewContainer = nil
	end
end, 'PreviewManager.exited')

-- Live update from EditCache
F.EventBus:Register('EDIT_CACHE_VALUE_CHANGED', function(frameKey, configPath, value)
	if(frameKey ~= activeFrameKey) then return end
	PM.ShowPreview(activeFrameKey)
end, 'PreviewManager.cacheChanged')

F.EventBus:Register('EDIT_MODE_AURA_DIM', function(frameKey, activeGroupId)
	if(frameKey ~= activeFrameKey) then return end
	for _, pf in next, previewFrames do
		if(pf.SetAuraGroupAlpha) then
			pf:SetAuraGroupAlpha(activeGroupId)
		end
	end
end, 'PreviewManager.auraDim')
