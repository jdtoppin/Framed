local addonName, Framed = ...
local F = Framed
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

local GROUP_TYPES = { party = true, raid = true, arena = true, boss = true, pinned = true }

local GROUP_FRAME_COUNTS = {
	party  = 5,
	raid   = 20,
	arena  = 3,
	boss   = 4,
	pinned = 9,
}

local GROUP_FAKES = nil  -- Lazy-init from Preview.GetFakeUnits

local UNITS_PER_COLUMN = 5
local PINNED_MAX_SLOTS = 9

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

--- Compute the outer-bounding rectangle a group preview occupies
--- given its unit config. Both sort modes flow the same way — a flat
--- column flow that wraps at UNITS_PER_COLUMN — so the math is the
--- same for role and group/index modes. Single source of truth for
--- ClickCatchers and any future consumer that needs to know how big
--- a group preview is without actually spawning one.
--- @param config table  Unit config (width/height/spacing/orientation)
--- @param frameKey string  'party' | 'raid' | 'arena' | 'boss'
--- @return number? width
--- @return number? height
function PM.GetGroupBounds(config, frameKey)
	local count = GROUP_FRAME_COUNTS[frameKey]
	if(not count) then return nil end

	local w = config.width
	local h = config.height
	local spacing = config.spacing

	-- Pinned uses a row-major grid wrapping at config.columns (user-settable),
	-- not the UNITS_PER_COLUMN=5 column-flow used by party/raid/boss/arena.
	if(frameKey == 'pinned') then
		local cols = config.columns
		local rows = math.ceil(PINNED_MAX_SLOTS / cols)
		return cols * w + (cols - 1) * spacing, rows * h + (rows - 1) * spacing
	end

	local isVertical = (config.orientation == 'vertical')
	local cols = math.ceil(count / UNITS_PER_COLUMN)
	local rows = math.min(count, UNITS_PER_COLUMN)

	if(isVertical) then
		return cols * w + (cols - 1) * spacing, rows * h + (rows - 1) * spacing
	else
		return rows * w + (rows - 1) * spacing, cols * h + (cols - 1) * spacing
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

-- Pinned has a row-major grid (wraps at config.columns) and none of the
-- party/raid concerns (role sort, party-pet, orientation, anchorPoint growth
-- direction). Kept as its own code path so the shared showGroupPreview below
-- stays focused on header-backed groups.
local function showPinnedPreview(container, config, realFrame, auraConfig)
	if(not GROUP_FAKES) then
		GROUP_FAKES = F.Preview.GetFakeUnits(5)
	end

	local cols    = config.columns
	local w       = config.width
	local h       = config.height
	local spacing = config.spacing

	local posAnchor = (config.position and config.position.anchor) or 'TOPLEFT'
	local baseX = EditCache.Get('pinned', 'position.x') or (config.position and config.position.x) or 0
	local baseY = EditCache.Get('pinned', 'position.y') or (config.position and config.position.y) or 0

	for i = 1, PINNED_MAX_SLOTS do
		local row = math.floor((i - 1) / cols)
		local col = (i - 1) % cols
		local offX =  col * (w + spacing)
		local offY = -row * (h + spacing)

		local fakeUnit = GROUP_FAKES[((i - 1) % #GROUP_FAKES) + 1]
		local unit = {
			name      = fakeUnit.name .. (i > #GROUP_FAKES and (' ' .. i) or ''),
			class     = fakeUnit.class,
			role      = fakeUnit.role,
			healthPct = math.max(0.1, (fakeUnit.healthPct or 0.8) - (i * 0.03)),
			powerPct  = fakeUnit.powerPct or 0.5,
		}

		local pf = F.PreviewFrame.Create(container, config, unit, realFrame, auraConfig)
		if(realFrame) then
			pf:SetPoint('TOPLEFT', realFrame, 'TOPLEFT', offX, offY)
		else
			pf:SetPoint('TOPLEFT', UIParent, posAnchor, baseX + offX, baseY + offY)
		end
		previewFrames[i] = pf
		pf:Show()
	end
end

local function showGroupPreview(frameKey)
	local container = getPreviewContainer()
	if(not container) then return end

	local config = getUnitConfig(frameKey)
	if(not config) then return end

	-- Look up real frame for scale sync (needed by every path)
	local realFrame = getRealFrame(frameKey)
	local auraConfig = getAuraConfig(frameKey)

	if(frameKey == 'pinned') then
		showPinnedPreview(container, config, realFrame, auraConfig)
		return
	end

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

	-- Position anchor from config (TOPLEFT for all real/pseudo groups)
	local posAnchor = (config.position and config.position.anchor) or 'CENTER'
	local baseX = EditCache.Get(frameKey, 'position.x') or (config.position and config.position.x) or 0
	local baseY = EditCache.Get(frameKey, 'position.y') or (config.position and config.position.y) or 0

	-- Build full unit list first (so we can bucket by role if needed)
	local units = {}
	for i = 1, count do
		local fakeUnit = GROUP_FAKES[((i - 1) % #GROUP_FAKES) + 1]
		units[i] = {
			name = fakeUnit.name .. (i > #GROUP_FAKES and (' ' .. i) or ''),
			class = fakeUnit.class,
			role = fakeUnit.role,
			healthPct = math.max(0.1, (fakeUnit.healthPct or 0.8) - (i * 0.03)),
			powerPct = fakeUnit.powerPct or 0.5,
		}
	end

	-- Role-aware ordering: flat sort by roleOrder, same as the live header's
	-- computed nameList (Units/LiveUpdate/FrameConfigLayout.ComputeRoleNameList).
	-- Party role mode has maxColumns=1 so it becomes a single sorted column;
	-- raid role mode flows by orientation/anchor and wraps at UNITS_PER_COLUMN.
	local orderedList
	if(config.sortMode == 'role' and config.roleOrder) then
		orderedList = {}
		local tokens = {}
		for token in config.roleOrder:gmatch('[^,]+') do
			tokens[#tokens + 1] = token
		end
		local buckets = {}
		for _, token in next, tokens do
			buckets[token] = {}
		end
		local leftovers = {}
		for _, unit in next, units do
			if(unit.role and buckets[unit.role]) then
				local b = buckets[unit.role]
				b[#b + 1] = unit
			else
				leftovers[#leftovers + 1] = unit
			end
		end
		for _, token in next, tokens do
			for _, u in next, buckets[token] do
				orderedList[#orderedList + 1] = u
			end
		end
		for _, u in next, leftovers do
			orderedList[#orderedList + 1] = u
		end
	else
		orderedList = units
	end

	-- Walk the ordered list, breaking to a new column at UNITS_PER_COLUMN.
	-- Party caps at 5 so it stays a single column; raid wraps as normal.
	local col, row = 0, 0
	for i = 1, #orderedList do
		if(i > 1 and row == UNITS_PER_COLUMN) then
			col = col + 1
			row = 0
		end
		local varied = orderedList[i]
		local offX = row * primaryX + col * colX
		local offY = row * primaryY + col * colY

		local pf = F.PreviewFrame.Create(container, config, varied, realFrame, auraConfig)
		if(realFrame) then
			pf:SetPoint(anchorPoint, realFrame, anchorPoint, offX, offY)
		else
			pf:SetPoint(anchorPoint, UIParent, posAnchor, baseX + offX, baseY + offY)
		end
		previewFrames[i] = pf
		pf:Show()

		row = row + 1
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

function PM.IsAnimationEnabled()
	return F.Config:Get('general.editModeAnimate')
end

function PM.SetAnimationEnabled(enabled)
	if(activeFrameKey) then
		PM.ShowPreview(activeFrameKey)
	end
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

-- Live update from EditCache (skip position/size — they don't affect preview)
F.EventBus:Register('EDIT_CACHE_VALUE_CHANGED', function(frameKey, configPath, value)
	if(frameKey ~= activeFrameKey) then return end
	if(configPath == 'position.x' or configPath == 'position.y'
		or configPath == 'width' or configPath == 'height') then return end
	PM.ShowPreview(activeFrameKey)
end, 'PreviewManager.cacheChanged')

-- Live update from aura config changes (written directly to Config, not EditCache)
F.EventBus:Register('CONFIG_CHANGED', function(path)
	if(not activeFrameKey) then return end
	-- Match aura config paths: presets.<preset>.auras.<unitType>.<rest>
	local unitType = path:match('^presets%.[^%.]+%.auras%.([^%.]+)')
	if(unitType and unitType == activeFrameKey) then
		PM.ShowPreview(activeFrameKey)
	end
end, 'PreviewManager.auraConfig')

