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

local GROUP_FAKES = {
	{ name = 'Tankadin',   class = 'PALADIN', role = 'TANK',    healthPct = 0.85, powerPct = 0.7,  incomingHeal = 0.10, damageAbsorb = 0.08 },
	{ name = 'Healbot',    class = 'PRIEST',  role = 'HEALER',  healthPct = 0.92, powerPct = 0.95, overAbsorb = true },
	{ name = 'Stabsworth', class = 'ROGUE',   role = 'DAMAGER', healthPct = 0.65, powerPct = 0.4,  healAbsorb = 0.05 },
	{ name = 'Frostbolt',  class = 'MAGE',    role = 'DAMAGER', healthPct = 0.78, powerPct = 0.9,  damageAbsorb = 0.12 },
	{ name = 'Deadshot',   class = 'HUNTER',  role = 'DAMAGER', healthPct = 0,    powerPct = 0,    isDead = true },
}

local BOSS_FAKES = {
	{ name = 'Boss 1', class = 'WARRIOR', healthPct = 0.95, powerPct = 1.0 },
	{ name = 'Boss 2', class = 'WARRIOR', healthPct = 0.72, powerPct = 0.8 },
	{ name = 'Boss 3', class = 'WARRIOR', healthPct = 0.50, powerPct = 0.6 },
	{ name = 'Boss 4', class = 'WARRIOR', healthPct = 0.30, powerPct = 0.4 },
}

local PET_FAKES = {
	{ name = 'Cat',             class = 'HUNTER',  healthPct = 0.90, powerPct = 0.8 },
	{ name = 'Wolf',            class = 'HUNTER',  healthPct = 0.75, powerPct = 0.6 },
	{ name = 'Imp',             class = 'WARLOCK', healthPct = 0.85, powerPct = 0.9 },
	{ name = 'Water Elemental', class = 'MAGE',    healthPct = 0.80, powerPct = 0.7 },
	{ name = 'Treant',          class = 'DRUID',   healthPct = 0.95, powerPct = 1.0 },
}

local showPets = false
local petFrames = {}

local GROUP_COUNTS = {
	party = 5,
	arena = 3,
	boss  = 4,
}

local function getFakeUnit(index)
	local base = GROUP_FAKES[((index - 1) % #GROUP_FAKES) + 1]
	if(index > #GROUP_FAKES) then
		local copy = {}
		for k, v in next, base do copy[k] = v end
		copy.name = base.name .. ' ' .. math.ceil(index / #GROUP_FAKES)
		return copy
	end
	return base
end

local function CalculateGroupLayout(config, count)
	local w = config.width
	local h = config.height
	local spacing = config.spacing
	local upc = config.unitsPerColumn
	local isVertical = config.orientation == 'vertical'

	local positions = {}
	for i = 0, count - 1 do
		local col = math.floor(i / upc)
		local row = i % upc
		local x, y
		if(isVertical) then
			x = col * (w + spacing)
			y = -(row * (h + spacing))
		else
			x = row * (w + spacing)
			y = -(col * (h + spacing))
		end
		positions[i + 1] = { x = x, y = y }
	end
	return positions
end

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

local function SortFakeUnits(units, config)
	local sortMode = config.sortMode
	if(not sortMode or sortMode == 'index') then return units end

	local sorted = {}
	for i, u in next, units do sorted[i] = u end

	if(sortMode == 'role') then
		table.sort(sorted, function(a, b)
			return (ROLE_ORDER[a.role] or 99) < (ROLE_ORDER[b.role] or 99)
		end)
	elseif(sortMode == 'class') then
		table.sort(sorted, function(a, b)
			return (a.class or '') < (b.class or '')
		end)
	elseif(sortMode == 'name') then
		table.sort(sorted, function(a, b)
			return (a.name or '') < (b.name or '')
		end)
	end
	return sorted
end

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
	if(not preset) then
		local petPreset, petKey = path:match('presets%.([^%.]+)%.partyPets%.(.+)')
		if(petPreset and activeUnitType == 'party') then
			if(petPreset ~= F.Settings.GetEditingPreset()) then return end
			if(showPets) then
				local config = getUnitConfig(activeUnitType)
				if(config) then
					RenderPetFrames(activePreview._viewContent, config)
				end
			end
		end
		return
	end

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
-- Pet frame rendering
-- ============================================================

local function RenderPetFrames(viewport, config)
	for _, frame in next, petFrames do
		ReleaseFrame(frame)
	end
	wipe(petFrames)

	if(not showPets) then return end

	local presetName = F.Settings.GetEditingPreset()
	local petConfig = F.Config:Get('presets.' .. presetName .. '.partyPets')
	if(not petConfig or petConfig.enabled == false) then return end

	local petSpacing = petConfig.spacing
	local petH = math.floor(config.height * 0.4)
	local petW = config.width

	for i, ownerFrame in next, previewFrames do
		local petFake = PET_FAKES[((i - 1) % #PET_FAKES) + 1]
		local petFrame = AcquireFrame(viewport) or CreateFrame('Frame', nil, viewport)

		petFrame:SetSize(petW, petH)
		petFrame:ClearAllPoints()
		petFrame:SetPoint('TOPLEFT', ownerFrame, 'BOTTOMLEFT', 0, -petSpacing)

		local bg = petFrame:CreateTexture(nil, 'BACKGROUND')
		bg:SetAllPoints(petFrame)
		bg:SetColorTexture(0.1, 0.12, 0.15, 0.8)

		if(petConfig.showName) then
			local nameText = Widgets.CreateFontString(petFrame, petConfig.nameFontSize, C.Colors.textActive)
			nameText:SetPoint(petConfig.nameAnchor, petFrame, petConfig.nameAnchor,
				petConfig.nameOffsetX, petConfig.nameOffsetY)
			nameText:SetText(petFake.name)
		end

		if(petConfig.showHealthText) then
			local healthText = Widgets.CreateFontString(petFrame, petConfig.healthTextFontSize, C.Colors.textActive)
			healthText:SetPoint(petConfig.healthTextAnchor, petFrame, petConfig.healthTextAnchor,
				petConfig.healthTextOffsetX, petConfig.healthTextOffsetY)
			healthText:SetText(math.floor(petFake.healthPct * 100) .. '%')
		end

		petFrame:Show()
		petFrames[i] = petFrame
	end
end

-- ============================================================
-- Group preview rendering
-- ============================================================

local function RenderGroupPreview(viewport, unitType, count)
	local config = getUnitConfig(unitType)
	if(not config) then return end

	local fakes
	if(unitType == 'boss') then
		fakes = BOSS_FAKES
	end

	local sortedFakes = {}
	for i = 1, count do
		sortedFakes[i] = fakes and fakes[i] or getFakeUnit(i)
	end
	sortedFakes = SortFakeUnits(sortedFakes, config)

	local positions = CalculateGroupLayout(config, count)

	for i = 1, count do
		local fakeUnit = sortedFakes[i]
		local frame = AcquireFrame(viewport) or F.PreviewFrame.Create(viewport, config, fakeUnit, nil, nil)
		if(frame._config) then
			frame._fakeUnit = fakeUnit
			F.PreviewFrame.UpdateFromConfig(frame, config, nil)
		end

		frame:ClearAllPoints()
		frame:SetPoint('TOPLEFT', viewport, 'TOPLEFT', positions[i].x, positions[i].y)

		previewFrames[i] = frame
	end

	local config_w = config.width
	local config_h = config.height
	local spacing = config.spacing
	local upc = config.unitsPerColumn
	local isVertical = config.orientation == 'vertical'

	local cols = math.ceil(count / upc)
	local rows = math.min(count, upc)

	local totalW, totalH
	if(isVertical) then
		totalW = cols * config_w + (cols - 1) * spacing
		totalH = rows * config_h + (rows - 1) * spacing
	else
		totalW = rows * config_w + (rows - 1) * spacing
		totalH = cols * config_h + (cols - 1) * spacing
	end

	viewport:SetSize(math.max(totalW, 1), math.max(totalH, 1))

	if(unitType == 'party') then
		RenderPetFrames(viewport, config)
	end
end

-- ============================================================
-- RebuildPreview (after render functions so locals are in scope)
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

	local viewH
	if(SOLO_FAKES[activeUnitType]) then
		viewH = config.height + 20
	elseif(GROUP_COUNTS[activeUnitType]) then
		local count
		if(activeUnitType == 'raid') then
			count = F.Config:Get('settings.raidPreviewCount')
		else
			count = GROUP_COUNTS[activeUnitType]
		end
		local rows = math.min(count, config.unitsPerColumn)
		viewH = rows * config.height + (rows - 1) * config.spacing + 20
	else
		viewH = config.height + 20
	end
	activePreview._viewport:SetHeight(viewH)
	viewport:SetHeight(viewH)

	if(SOLO_FAKES[activeUnitType]) then
		RenderSoloPreview(viewport, activeUnitType)
	elseif(activeUnitType == 'raid') then
		local count = F.Config:Get('settings.raidPreviewCount')
		RenderGroupPreview(viewport, activeUnitType, count)
	elseif(GROUP_COUNTS[activeUnitType]) then
		local count = GROUP_COUNTS[activeUnitType]
		RenderGroupPreview(viewport, activeUnitType, count)
	end
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

	if(unitType == 'raid') then
		local count = F.Config:Get('settings.raidPreviewCount')

		local countText = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSubtle)
		countText:SetPoint('RIGHT', inner, 'RIGHT', 0, cy + C.Font.sizeMedium / 2)
		countText:SetText('units: ' .. count)

		local decBtn = CreateFrame('Button', nil, inner)
		decBtn:SetSize(16, 16)
		decBtn:SetPoint('RIGHT', countText, 'LEFT', -4, 0)
		decBtn:SetNormalFontObject(GameFontNormalSmall)
		decBtn:SetText('▼')
		decBtn:SetScript('OnClick', function()
			local cur = F.Config:Get('settings.raidPreviewCount')
			if(cur > 1) then
				F.Config:Set('settings.raidPreviewCount', cur - 1)
				countText:SetText('units: ' .. (cur - 1))
				FP.RebuildPreview()
			end
		end)

		local incBtn = CreateFrame('Button', nil, inner)
		incBtn:SetSize(16, 16)
		incBtn:SetPoint('LEFT', countText, 'RIGHT', 4, 0)
		incBtn:SetNormalFontObject(GameFontNormalSmall)
		incBtn:SetText('▲')
		incBtn:SetScript('OnClick', function()
			local cur = F.Config:Get('settings.raidPreviewCount')
			if(cur < 40) then
				F.Config:Set('settings.raidPreviewCount', cur + 1)
				countText:SetText('units: ' .. (cur + 1))
				FP.RebuildPreview()
			end
		end)

		card._countText = countText
	end

	if(unitType == 'party') then
		local petToggle = Widgets.CreateCheckButton(inner, 'Show Pets', function(checked)
			showPets = checked
			local config = getUnitConfig(unitType)
			if(config) then
				RenderPetFrames(card._viewContent, config)
			end
		end)
		petToggle:SetChecked(false)
		petToggle:SetPoint('RIGHT', inner, 'RIGHT', 0, cy + C.Font.sizeMedium / 2)
	end

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
	local viewH
	if(not config) then
		viewH = 60
	elseif(SOLO_FAKES[unitType]) then
		viewH = config.height + 20
	elseif(unitType == 'raid') then
		local count = F.Config:Get('settings.raidPreviewCount')
		local rows = math.min(count, config.unitsPerColumn)
		viewH = rows * config.height + (rows - 1) * config.spacing + 20
	elseif(GROUP_COUNTS[unitType]) then
		local count = GROUP_COUNTS[unitType]
		local rows = math.min(count, config.unitsPerColumn)
		viewH = rows * config.height + (rows - 1) * config.spacing + 20
	else
		viewH = config.height + 20
	end
	viewport:SetHeight(viewH)
	viewContent:SetHeight(viewH)
	cy = cy - viewH - 8

	activeUnitType = unitType
	if(SOLO_FAKES[unitType]) then
		RenderSoloPreview(viewContent, unitType)
	elseif(unitType == 'raid') then
		local count = F.Config:Get('settings.raidPreviewCount')
		RenderGroupPreview(viewContent, unitType, count)
	elseif(GROUP_COUNTS[unitType]) then
		local count = GROUP_COUNTS[unitType]
		RenderGroupPreview(viewContent, unitType, count)
	end

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
	for _, frame in next, petFrames do
		ReleaseFrame(frame)
	end
	wipe(petFrames)
	showPets = false
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
