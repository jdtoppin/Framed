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
	player       = function() return { name = UnitName('player') or 'You', class = getPlayerClass(), healthPct = 1.0,  powerPct = 0.85 } end,
	target       = function() return { name = 'Target Dummy',  class = 'WARRIOR',  healthPct = 0.72, powerPct = 0.6  } end,
	targettarget = function() return { name = 'Healbot',       class = 'PRIEST',   healthPct = 0.90, powerPct = 0.8  } end,
	focus        = function() return { name = 'Focus Target',  class = 'MAGE',     healthPct = 0.55, powerPct = 0.45 } end,
	pet          = function() return { name = 'Pet',           class = 'HUNTER',   healthPct = 0.80, powerPct = 0.7  } end,
}

local GROUP_TYPES = { party = true, raid = true, arena = true, boss = true }

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

local function showSoloPreview(frameKey)
	local container = getPreviewContainer()
	if(not container) then return end

	local config = getUnitConfig(frameKey)
	if(not config) then return end

	local fakeFn = SOLO_FAKES[frameKey]
	local fakeUnit = fakeFn and fakeFn() or { name = frameKey, class = 'WARRIOR', healthPct = 0.8, powerPct = 0.5 }

	local pf = F.PreviewFrame.Create(container, config, fakeUnit)

	-- Position at real frame location
	local x = EditCache.Get(frameKey, 'position.x') or (config.position and config.position.x) or 0
	local y = EditCache.Get(frameKey, 'position.y') or (config.position and config.position.y) or 0
	pf:SetPoint('CENTER', UIParent, 'CENTER', x, y)

	previewFrames[1] = pf
	pf:Show()
end

-- ============================================================
-- Public API
-- ============================================================

function PM.ShowPreview(frameKey)
	destroyPreviews()
	activeFrameKey = frameKey

	if(GROUP_TYPES[frameKey]) then
		showSoloPreview(frameKey)  -- Placeholder until Phase 3
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
	-- Position changes → reposition only
	if(configPath == 'position.x' or configPath == 'position.y') then
		if(previewFrames[1]) then
			local config = getUnitConfig(frameKey)
			if(config) then
				local x = EditCache.Get(frameKey, 'position.x') or (config.position and config.position.x) or 0
				local y = EditCache.Get(frameKey, 'position.y') or (config.position and config.position.y) or 0
				previewFrames[1]:ClearAllPoints()
				previewFrames[1]:SetPoint('CENTER', UIParent, 'CENTER', x, y)
			end
		end
		return
	end
	-- Other changes → rebuild preview
	PM.ShowPreview(activeFrameKey)
end, 'PreviewManager.cacheChanged')
