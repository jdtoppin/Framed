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
		overAbsorb = true,
	} end,
	target       = function() return {
		name = 'Target Dummy', class = 'WARRIOR',
		healthPct = 0.85, powerPct = 0.7,
		incomingHeal = 0.10, damageAbsorb = 0.12,
		overAbsorb = true,
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

local PREVIEW_INSET = 4

local function getCastbarExtra(config)
	if(config.showCastBar == false or not config.castbar) then return 0 end
	return config.castbar.height + C.Spacing.base
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

local focusModeEnabled = false
local focusedCardId = nil

local CARD_ELEMENT_MAP = {
	healthColor      = { '_healthBar', '_portrait', '_portraitTex' },
	healthText       = { '_healthText' },
	-- Don't include _powerWrapper here — _powerText is a descendant, and dimming
	-- the wrapper cascades through effective alpha to the text. Keep dimming
	-- scoped to the bar itself so powerText focus can undim the text cleanly.
	power            = { '_powerBar' },
	powerText        = { '_powerText' },
	name             = { '_nameText' },
	castbar          = { '_castbar' },
	statusIcons      = { '_iconOverlay' },
	markers          = { '_markerOverlay' },
	statusText       = { '_statusText', '_statusTextOverlay' },
	shields          = { '_healPredBar', '_damageAbsorbBar', '_healAbsorbBar', '_overAbsorbGlow' },
	partyPets        = {},
}

local function SetElementAlpha(frame, keys, alpha)
	for _, key in next, keys do
		local obj = frame
		for part in key:gmatch('[^%.]+') do
			obj = obj and obj[part]
		end
		if(obj and obj.SetAlpha) then
			obj:SetAlpha(alpha)
		end
	end
end

local function ApplyFocusMode(cardId)
	for _, frame in next, previewFrames do
		for _, keys in next, CARD_ELEMENT_MAP do
			SetElementAlpha(frame, keys, 0.2)
		end

		if(cardId and CARD_ELEMENT_MAP[cardId]) then
			SetElementAlpha(frame, CARD_ELEMENT_MAP[cardId], 1.0)
		end
	end

	local petAlpha = (cardId == 'partyPets') and 1.0 or 0.2
	for _, petFrame in next, petFrames do
		petFrame:SetAlpha(petAlpha)
	end
end

local function ClearFocusMode()
	for _, frame in next, previewFrames do
		for _, keys in next, CARD_ELEMENT_MAP do
			SetElementAlpha(frame, keys, 1.0)
		end
	end
	for _, petFrame in next, petFrames do
		petFrame:SetAlpha(1.0)
	end
end

function FP.OnCardFocused(cardId)
	focusedCardId = cardId
	if(not focusModeEnabled) then return end
	if(cardId) then
		ApplyFocusMode(cardId)
	else
		ClearFocusMode()
	end
end

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

-- Forward declarations for locals referenced before definition
local RenderPetFrames

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
	-- Portrait adds a square to the left of the frame; must re-run RenderSoloPreview
	-- / RenderGroupPreview so leftPad is recomputed and the frame shifts right.
	portrait = true,
	-- Castbar toggle changes the preview viewport height; must resize the card.
	showCastBar = true, castbar = true,
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
		local petPreset = path:match('presets%.([^%.]+)%.partyPets%.')
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
			F.PreviewFrame.UpdateFromConfig(frame, config, nil, nil)
		end
		-- UpdateFromConfig destroys+rebuilds child textures, so focus-mode
		-- alphas from the prior ApplyFocusMode are lost; re-apply here.
		if(focusModeEnabled and focusedCardId) then
			ApplyFocusMode(focusedCardId)
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

-- Fade a frame out, then release it to the pool. Used when the count drops
-- (e.g. raid 15→10 removes five frames) or when switching from group to solo.
local function FadeOutAndRelease(frame)
	Widgets.StartAnimation(frame, 'fade', frame:GetAlpha(), 0, 0.3,
		function(f, a) f:SetAlpha(a) end,
		function(f)
			f:SetAlpha(1)
			ReleaseFrame(f)
		end)
end

-- Fade a frame in at its already-set position. Used for frames newly added
-- to a grid (e.g. raid 10→15 adds five slots).
local function FadeIn(frame)
	frame:SetAlpha(0)
	Widgets.StartAnimation(frame, 'fade', 0, 1, 0.3,
		function(f, a) f:SetAlpha(a) end,
		function(f) f:SetAlpha(1) end)
end

-- Drop any frames whose index exceeds `keep`. Each one fades out then
-- releases; previewFrames[i] is cleared immediately so subsequent renders
-- treat the slot as empty even while the fade is still running.
local function FadeOutExtras(keep)
	for i = #previewFrames, keep + 1, -1 do
		local frame = previewFrames[i]
		previewFrames[i] = nil
		if(frame) then FadeOutAndRelease(frame) end
	end
end

local function RenderSoloPreview(viewport, unitType)
	local config = getUnitConfig(unitType)
	if(not config) then return end

	local fakeFn = SOLO_FAKES[unitType]
	local fakeUnit = fakeFn and fakeFn() or { name = 'Unit', class = 'WARRIOR', healthPct = 0.85, powerPct = 0.7 }

	-- Drop group-count leftovers when switching solo unit types (rare path —
	-- solo preview cards are usually their own instance, but a rebuild can
	-- still hit this when a config change reduces a group preview to one).
	FadeOutExtras(1)

	-- Preview card always animates the health bar so the loss color behind the
	-- fill is visible during drain/refill cycles. The global edit-mode
	-- animation toggle (`IsAnimationEnabled`) does not gate the settings
	-- preview card — the animation is the point of the card.
	local frame = previewFrames[1]
	local isNew = (frame == nil)
	if(isNew) then
		frame = AcquireFrame(viewport) or F.PreviewFrame.Create(viewport, config, fakeUnit, nil, nil, true, unitType)
	end
	frame._fakeUnit = fakeUnit
	frame._unitType = unitType
	if(frame._config) then
		F.PreviewFrame.UpdateFromConfig(frame, config, nil, true, unitType)
	end

	-- Flush-left with title/toggle (no PREVIEW_INSET). Portrait still shifts
	-- the frame right so the portrait box sits in the gutter.
	local leftPad = 0
	if(config.portrait) then
		leftPad = leftPad + config.height + (C.Spacing.base or 4)
	end

	frame:ClearAllPoints()
	frame:SetPoint('TOPLEFT', viewport, 'TOPLEFT', leftPad, -PREVIEW_INSET)

	if(isNew) then FadeIn(frame) end

	frame._lastX = leftPad
	frame._lastY = -PREVIEW_INSET
	previewFrames[1] = frame
end

-- ============================================================
-- Pet frame rendering
-- ============================================================

-- Mirror of Units/Party.lua's computePetAnchorToOwner (kept local there).
-- Vertical party layouts put pets beside owners (left/right); horizontal
-- layouts put them above/below. The chosen side falls out of the owner's
-- anchorPoint so pets grow *away* from the group anchor, not into it.
local function computePetAnchorToOwner(orient, anchor, gap)
	if(orient == 'vertical') then
		local onLeft = (anchor == 'TOPRIGHT' or anchor == 'BOTTOMRIGHT')
		if(onLeft) then
			return 'RIGHT', 'LEFT', -gap, 0
		else
			return 'LEFT', 'RIGHT', gap, 0
		end
	else
		local above = (anchor == 'BOTTOMLEFT' or anchor == 'BOTTOMRIGHT')
		if(above) then
			return 'BOTTOM', 'TOP', 0, gap
		else
			return 'TOP', 'BOTTOM', 0, -gap
		end
	end
end

RenderPetFrames = function(viewport, config)
	for _, frame in next, petFrames do
		ReleaseFrame(frame)
	end
	wipe(petFrames)

	if(not showPets) then return end

	local presetName = F.Settings.GetEditingPreset()
	local petConfig = F.Config:Get('presets.' .. presetName .. '.partyPets')
	if(not petConfig or petConfig.enabled == false) then return end

	local petSpacing = petConfig.spacing or 0
	-- Match live: pets share the owner's dimensions (Units/Party.lua PetStyle).
	local petW = config.width
	local petH = config.height

	local petPt, ownerPt, dx, dy = computePetAnchorToOwner(
		config.orientation, config.anchorPoint, petSpacing)

	for i, ownerFrame in next, previewFrames do
		local petFake = PET_FAKES[((i - 1) % #PET_FAKES) + 1]
		local petFrame = AcquireFrame(viewport) or CreateFrame('Frame', nil, viewport)

		petFrame:SetSize(petW, petH)
		petFrame:ClearAllPoints()
		petFrame:SetPoint(petPt, ownerFrame, ownerPt, dx, dy)

		local bg = petFrame:CreateTexture(nil, 'BACKGROUND')
		bg:SetAllPoints(petFrame)
		bg:SetColorTexture(0.1, 0.12, 0.15, 0.8)

		if(petConfig.showName) then
			local nameAnchor = petConfig.nameAnchor or 'TOP'
			local nameText = Widgets.CreateFontString(petFrame, petConfig.nameFontSize or C.Font.sizeSmall, C.Colors.textActive)
			nameText:SetPoint(nameAnchor, petFrame, nameAnchor,
				petConfig.nameOffsetX or 0, petConfig.nameOffsetY or -2)
			nameText:SetText(petFake.name)
		end

		if(petConfig.showHealthText) then
			local htAnchor = petConfig.healthTextAnchor or 'CENTER'
			local healthText = Widgets.CreateFontString(petFrame, petConfig.healthTextFontSize or C.Font.sizeSmall, C.Colors.textActive)
			healthText:SetPoint(htAnchor, petFrame, htAnchor,
				petConfig.healthTextOffsetX or 0, petConfig.healthTextOffsetY or 0)
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

	-- Flush-left with title/toggle (no PREVIEW_INSET). Portrait still shifts
	-- the frames right so the portrait box sits in the gutter.
	local leftPad = 0
	if(config.portrait) then
		leftPad = leftPad + config.height + (C.Spacing.base or 4)
	end

	-- Drop extras first — going from count 15 to 10 fades slots 11–15 out and
	-- releases them. Must happen before the reuse loop so previewFrames[i] is
	-- nil for removed slots (though here, only the tail beyond count is ever
	-- removed, so this is defensive).
	FadeOutExtras(count)

	for i = 1, count do
		local fakeUnit = sortedFakes[i]
		local frame = previewFrames[i]
		local isNew = (frame == nil)
		if(isNew) then
			frame = AcquireFrame(viewport) or F.PreviewFrame.Create(viewport, config, fakeUnit, nil, nil, nil, unitType)
			-- Pool-acquired frames carry stale _lastX/_lastY from wherever
			-- they lived before release. Wipe so the slot-identity logic
			-- below treats this as a fresh placement (snap + fade-in), not
			-- a reposition sweeping in from some random old coordinate.
			frame._lastX = nil
			frame._lastY = nil
		end

		frame._unitType = unitType
		frame._fakeUnit = fakeUnit
		if(frame._config) then
			F.PreviewFrame.UpdateFromConfig(frame, config, nil, false, unitType)
		end

		local pos = positions[i]
		local px = pos.x + leftPad
		local py = pos.y - PREVIEW_INSET

		if(isNew) then
			-- Freshly filled slot: snap to final position and fade in.
			frame:ClearAllPoints()
			frame:SetPoint('TOPLEFT', viewport, 'TOPLEFT', px, py)
			FadeIn(frame)
		elseif(frame._lastX ~= px or frame._lastY ~= py) then
			-- Existing slot whose position actually changed (e.g. portrait
			-- toggle shifts leftPad, or orientation flip reshuffles cols).
			-- Tween to the new spot so config changes still animate.
			local fromX, fromY = frame._lastX, frame._lastY
			Widgets.StartAnimation(frame, 'reposition', 0, 1, 0.3,
				function(f, t)
					f:ClearAllPoints()
					f:SetPoint('TOPLEFT', viewport, 'TOPLEFT',
						fromX + (px - fromX) * t,
						fromY + (py - fromY) * t)
				end,
				function(f)
					f:ClearAllPoints()
					f:SetPoint('TOPLEFT', viewport, 'TOPLEFT', px, py)
				end
			)
		end
		-- Existing slot at the same position: no animation at all.

		frame._lastX = px
		frame._lastY = py
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
-- Animated viewport resize
-- ============================================================

local RESIZE_DUR = 0.3

-- Animate the outer preview card + its viewport height together so the card
-- grows/shrinks in lockstep when the cast bar toggles.
local function AnimatePreviewHeight(card, viewport, targetViewH, targetCardH, onFrame)
	local fromViewH = viewport:GetHeight()
	local fromCardH = card:GetHeight()

	if(math.abs(fromViewH - targetViewH) < 1 and math.abs(fromCardH - targetCardH) < 1) then
		viewport:SetHeight(targetViewH)
		card:SetHeight(targetCardH)
		if(card.content) then card.content:SetHeight(targetCardH - Widgets.CARD_PADDING * 2) end
		if(onFrame) then onFrame() end
		return
	end

	Widgets.StartAnimation(card, 'previewResize', 0, 1, RESIZE_DUR,
		function(_, t)
			local vH = fromViewH + (targetViewH - fromViewH) * t
			local cH = fromCardH + (targetCardH - fromCardH) * t
			viewport:SetHeight(vH)
			card:SetHeight(cH)
			if(card.content) then card.content:SetHeight(cH - Widgets.CARD_PADDING * 2) end
			if(onFrame) then onFrame() end
		end,
		function()
			viewport:SetHeight(targetViewH)
			card:SetHeight(targetCardH)
			if(card.content) then card.content:SetHeight(targetCardH - Widgets.CARD_PADDING * 2) end
			if(onFrame) then onFrame() end
		end
	)
end

-- Idempotent for the same target: if a 'previewWidth' tween is already in
-- flight toward targetW, do nothing. Otherwise Widgets.StartAnimation would
-- overwrite card._anim['previewWidth'] with elapsed=0 every call — and the
-- caller (`_onResize`) fires on every tick of AnimatePreviewHeight. Without
-- this guard the width tween gets re-seeded ~60×/s and never progresses
-- until the height tween ends, producing a sequential "height then width"
-- animation instead of a concurrent one.
local function AnimatePreviewWidth(card, viewport, targetW, onFrame)
	if(card._previewWidthTarget and math.abs(card._previewWidthTarget - targetW) < 1
		and card._anim and card._anim['previewWidth']) then
		return
	end
	card._previewWidthTarget = targetW

	local fromW = card:GetWidth()
	if(math.abs(fromW - targetW) < 1) then
		card:SetWidth(targetW)
		viewport:SetWidth(targetW - Widgets.CARD_PADDING * 2)
		card._previewWidthTarget = nil
		if(onFrame) then onFrame() end
		return
	end
	Widgets.StartAnimation(card, 'previewWidth', 0, 1, RESIZE_DUR,
		function(_, t)
			local w = fromW + (targetW - fromW) * t
			card:SetWidth(w)
			viewport:SetWidth(w - Widgets.CARD_PADDING * 2)
			if(onFrame) then onFrame() end
		end,
		function()
			card:SetWidth(targetW)
			viewport:SetWidth(targetW - Widgets.CARD_PADDING * 2)
			card._previewWidthTarget = nil
			if(onFrame) then onFrame() end
		end
	)
end

local function AnimateSimpleWidth(card, targetW, onFrame)
	if(card._simpleWidthTarget and math.abs(card._simpleWidthTarget - targetW) < 1
		and card._anim and card._anim['simpleWidth']) then
		return
	end
	card._simpleWidthTarget = targetW

	local fromW = card:GetWidth()
	if(math.abs(fromW - targetW) < 1) then
		card:SetWidth(targetW)
		card._simpleWidthTarget = nil
		if(onFrame) then onFrame() end
		return
	end
	Widgets.StartAnimation(card, 'simpleWidth', 0, 1, RESIZE_DUR,
		function(_, t)
			card:SetWidth(fromW + (targetW - fromW) * t)
			if(onFrame) then onFrame() end
		end,
		function()
			card:SetWidth(targetW)
			card._simpleWidthTarget = nil
			if(onFrame) then onFrame() end
		end
	)
end

-- Public: animate pinned row widths (preview card + its viewport, summary card).
function FP.AnimatePinnedWidths(previewCard, summaryCard, targetPreviewW, targetSummaryW, onFrame)
	AnimatePreviewWidth(previewCard, previewCard._viewport, targetPreviewW, onFrame)
	AnimateSimpleWidth(summaryCard, targetSummaryW)
end

-- Lightweight height refresh used when Focus Mode reflows between rows. The
-- viewport's y-anchor has already been updated by relayoutFocusAndRows, so the
-- only thing left is to reconcile the card height (and the paired summary
-- card) with the new _cyBeforeViewport. Mirrors the height-animation block in
-- RebuildPreview but skips the frame teardown, preventing the cross-fade from
-- replaying on a pure anchor shift.
function FP.UpdateCardHeightLightly()
	if(not activePreview or not activePreview._cyBeforeViewport) then return end
	local viewport = activePreview._viewport
	if(not viewport) then return end

	local viewH = viewport:GetHeight()
	local finalCy = activePreview._cyBeforeViewport - viewH - (activePreview._viewportBottomPad or 8)
	local previewNaturalH = math.abs(finalCy) + F.Widgets.CARD_PADDING * 2
	activePreview._naturalH = previewNaturalH

	local targetCardH = previewNaturalH
	local paired = activePreview._pairedSummaryCard
	if(paired) then
		local summaryNaturalH = paired._naturalH or paired:GetHeight()
		targetCardH = math.max(previewNaturalH, summaryNaturalH)

		local fromSummaryH = paired:GetHeight()
		if(math.abs(fromSummaryH - targetCardH) > 0.5) then
			Widgets.StartAnimation(paired, 'pairedResize', 0, 1, RESIZE_DUR,
				function(f, t)
					f:SetHeight(fromSummaryH + (targetCardH - fromSummaryH) * t)
				end,
				function(f)
					f:SetHeight(targetCardH)
				end)
		end
	end

	AnimatePreviewHeight(activePreview, viewport, viewH, targetCardH, function()
		if(activePreview._onResize) then activePreview._onResize() end
	end)
end

-- ============================================================
-- RebuildPreview (after render functions so locals are in scope)
-- ============================================================

function FP.RebuildPreview()
	if(not activePreview or not activeUnitType) then return end

	-- Do NOT release/wipe previewFrames here. Each render function manages
	-- its own delta (fade out tail on shrink, fade in head on grow, reposition
	-- on config change). Wiping upfront used to push every frame back through
	-- the LIFO pool, and the next acquire would pop frames with stale
	-- _lastX/_lastY — which triggered the reposition tween to sweep across
	-- the viewport (the "shrink to nothing then grow out" artifact).
	local viewport = activePreview._viewContent
	local config = getUnitConfig(activeUnitType)
	if(not viewport or not config) then return end

	local inset2 = PREVIEW_INSET * 2
	local MAX_PREVIEW_H = 120
	local cbExtra = getCastbarExtra(config)
	local naturalH
	if(SOLO_FAKES[activeUnitType]) then
		naturalH = config.height + cbExtra + inset2
	elseif(activeUnitType == 'raid' or GROUP_COUNTS[activeUnitType]) then
		local count
		if(activeUnitType == 'raid') then
			count = F.Config:GetChar('settings.raidPreviewCount')
		else
			count = GROUP_COUNTS[activeUnitType]
		end
		local rows = math.min(count, config.unitsPerColumn)
		naturalH = rows * config.height + (rows - 1) * config.spacing + cbExtra + inset2
	else
		naturalH = config.height + cbExtra + inset2
	end

	local previewScale = 1
	if(naturalH > MAX_PREVIEW_H) then
		previewScale = MAX_PREVIEW_H / naturalH
	end
	local viewH = math.ceil(naturalH * previewScale)

	local outerW = activePreview:GetWidth()
	local innerW = outerW - F.Widgets.CARD_PADDING * 2
	viewport:SetScale(previewScale)
	viewport:SetWidth(innerW / previewScale)
	viewport:SetHeight(naturalH)
	activePreview._previewScale = previewScale

	-- Animate outer card height + its viewport scrollframe height together.
	-- Equalize against the paired summary card using each card's *natural*
	-- height, so either card can shrink back when the other shrinks. Without
	-- natural-height tracking, a one-way grow leaves the pair stuck at the
	-- tallest size forever (e.g. castbar toggled off still leaves the preview
	-- as tall as the summary was with castbar on).
	if(activePreview._cyBeforeViewport) then
		local finalCy = activePreview._cyBeforeViewport - viewH - (activePreview._viewportBottomPad or 8)
		local previewNaturalH = math.abs(finalCy) + F.Widgets.CARD_PADDING * 2
		activePreview._naturalH = previewNaturalH

		local targetCardH = previewNaturalH
		local paired = activePreview._pairedSummaryCard
		if(paired) then
			local summaryNaturalH = paired._naturalH or paired:GetHeight()
			targetCardH = math.max(previewNaturalH, summaryNaturalH)

			-- Animate the paired summary card to match so it grows/shrinks
			-- alongside the preview instead of snapping. Same RESIZE_DUR as
			-- AnimatePreviewHeight so they're perceived as one motion.
			local fromSummaryH = paired:GetHeight()
			if(math.abs(fromSummaryH - targetCardH) > 0.5) then
				Widgets.StartAnimation(paired, 'pairedResize', 0, 1, RESIZE_DUR,
					function(f, t)
						f:SetHeight(fromSummaryH + (targetCardH - fromSummaryH) * t)
					end,
					function(f)
						f:SetHeight(targetCardH)
					end)
			end
		end
		AnimatePreviewHeight(activePreview, activePreview._viewport, viewH, targetCardH, function()
			if(activePreview._onResize) then activePreview._onResize() end
		end)
	end

	if(SOLO_FAKES[activeUnitType]) then
		RenderSoloPreview(viewport, activeUnitType)
	elseif(activeUnitType == 'raid') then
		local count = F.Config:GetChar('settings.raidPreviewCount')
		RenderGroupPreview(viewport, activeUnitType, count)
	elseif(GROUP_COUNTS[activeUnitType]) then
		local count = GROUP_COUNTS[activeUnitType]
		RenderGroupPreview(viewport, activeUnitType, count)
	end

	if(focusModeEnabled and focusedCardId) then
		ApplyFocusMode(focusedCardId)
	end
	-- _onResize is invoked per-frame by AnimatePreviewHeight; no extra call here.
end

-- ============================================================
-- Public: Build the preview card
-- ============================================================

function FP.BuildPreviewCard(parent, width, unitType)
	if(activePreview) then
		FP.Destroy()
	end

	focusModeEnabled = F.Config:Get('general.settingsFocusMode') or false

	local card, inner, cy = Widgets.StartCard(parent, width, 0)
	Widgets.CreateAccentBar(card, 'top')

	-- Add extra right-edge padding so long titles (e.g. "Preview — Targettarget"
	-- on narrow 120px cards) don't sit flush against the card edge. Affects the
	-- viewport too, which is fine — the preview frame is centered/left-anchored
	-- within it and can afford a few pixels.
	local EXTRA_RIGHT_PAD = 6
	inner:ClearAllPoints()
	inner:SetPoint('TOPLEFT', card, 'TOPLEFT', Widgets.CARD_PADDING, -Widgets.CARD_PADDING)
	inner:SetPoint('TOPRIGHT', card, 'TOPRIGHT', -(Widgets.CARD_PADDING + EXTRA_RIGHT_PAD), -Widgets.CARD_PADDING)

	-- Header row
	local title = Widgets.CreateFontString(inner, C.Font.sizeNormal, C.Colors.textActive)
	title:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cy)
	title:SetPoint('TOPRIGHT', inner, 'TOPRIGHT', 0, cy)
	title:SetJustifyH('LEFT')
	title:SetWordWrap(false)
	title:SetText('Preview — ' .. (unitType:sub(1, 1):upper() .. unitType:sub(2)))
	cy = cy - C.Font.sizeNormal - 8

	local focusToggle = Widgets.CreateCheckButton(inner, 'Focus Mode', function(checked)
		focusModeEnabled = checked
		F.Config:Set('general.settingsFocusMode', checked)
		if(checked and focusedCardId) then
			ApplyFocusMode(focusedCardId)
		else
			ClearFocusMode()
		end
	end)
	focusToggle:SetChecked(focusModeEnabled)

	-- Raid stepper widgets — created now so the relayout closure can re-anchor
	-- them whenever Focus Mode reflows between rows. Buttons anchor relative to
	-- countText, so only countText needs re-anchoring during reflow.
	local countText
	local STEP_BTN_SIZE = 16
	if(unitType == 'raid') then
		local count = F.Config:GetChar('settings.raidPreviewCount')
		countText = Widgets.CreateFontString(inner, C.Font.sizeSmall, C.Colors.textSecondary)
		countText:SetText('Frames: ' .. count)

		local STEP = 5
		local MIN_COUNT, MAX_COUNT = 1, 40

		-- After SetChar, resolve the Focus Mode flip *before* rebuild using
		-- the predicted post-change card width. This lets height (from the
		-- new _cyBeforeViewport) and width (from _onResize → AnimatePinnedWidths)
		-- tween concurrently — otherwise the width tween settles first and the
		-- follow-up Focus Mode flip runs a second, opposite-direction height
		-- tween, which reads as "grow then shrink."
		local function applyCountChange(target)
			F.Config:SetChar('settings.raidPreviewCount', target)
			countText:SetText('Frames: ' .. target)
			if(card._predictWidth and card._relayoutFocusAndRows) then
				card._relayoutFocusAndRows(card._predictWidth())
			end
			FP.RebuildPreview()
		end

		local decBtn = Widgets.CreateIconButton(inner, F.Media.GetIcon('ArrowLeft2'), STEP_BTN_SIZE)
		decBtn:SetPoint('LEFT', countText, 'RIGHT', 6, 0)
		decBtn:SetScript('OnClick', function()
			local cur = F.Config:GetChar('settings.raidPreviewCount')
			local target = math.max(MIN_COUNT, math.floor((cur - 1) / STEP) * STEP)
			if(target ~= cur) then applyCountChange(target) end
		end)

		local incBtn = Widgets.CreateIconButton(inner, F.Media.GetIcon('ArrowRight1'), STEP_BTN_SIZE)
		incBtn:SetPoint('LEFT', decBtn, 'RIGHT', 4, 0)
		incBtn:SetScript('OnClick', function()
			local cur = F.Config:GetChar('settings.raidPreviewCount')
			local target = math.min(MAX_COUNT, math.floor(cur / STEP) * STEP + STEP)
			if(target ~= cur) then applyCountChange(target) end
		end)

		card._countText = countText
	end

	-- Party Show Pets toggle — built without anchors so the relayout closure
	-- places it on its own row after Focus Mode, regardless of whether Focus
	-- Mode sits on the title row or wrapped below. Previously this was pinned
	-- to the title row's right edge and overlapped the Focus Mode toggle on
	-- wide cards + encroached on the preview frames' y-space on narrow ones.
	local petToggle
	if(unitType == 'party') then
		petToggle = Widgets.CreateCheckButton(inner, 'Show Pets', function(checked)
			showPets = checked
			local config = getUnitConfig(unitType)
			if(config) then
				RenderPetFrames(card._viewContent, config)
			end
		end)
		petToggle:SetChecked(false)
	end

	-- Preview viewport (horizontal scroll for overflow) — TOPLEFT y is applied
	-- by the relayout closure below so it shifts when Focus Mode reflows.
	local viewport = CreateFrame('ScrollFrame', nil, inner)
	local viewContent = CreateFrame('Frame', nil, viewport)
	viewport:SetScrollChild(viewContent)
	viewport:SetPoint('RIGHT', inner, 'RIGHT', 0, 0)
	viewContent:SetWidth(width)

	-- ── Reflow: Focus Mode + stepper + viewport y-anchors ──
	-- Re-runs when the card resizes (raid count changes, window resize, etc.)
	-- so Focus Mode sits next to the title when there's room and wraps to its
	-- own row otherwise. Consumers:
	--   • focusToggle        — anchor changes based on decision
	--   • countText (raid)   — y shifts when focus row appears/disappears
	--   • viewport           — TOPLEFT y shifts for the same reason
	--   • card._cyBeforeViewport — consumed by RebuildPreview for card height
	local TITLE_GAP = 12
	local cyAfterTitle = cy
	local function relayoutFocusAndRows(cardW)
		local innerMeasuredW = cardW - Widgets.CARD_PADDING * 2 - EXTRA_RIGHT_PAD
		local titleW = title:GetStringWidth() or 0
		local toggleW = focusToggle:GetWidth() or 0
		local onTitleRow = (titleW + TITLE_GAP + toggleW <= innerMeasuredW)

		if(card._focusOnTitleRow == onTitleRow) then return false end
		card._focusOnTitleRow = onTitleRow

		local cyNext = cyAfterTitle
		focusToggle:ClearAllPoints()
		if(onTitleRow) then
			focusToggle:SetPoint('RIGHT', inner, 'TOPRIGHT', 0, cyAfterTitle + C.Font.sizeNormal / 2 + 8)
		else
			focusToggle:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cyAfterTitle)
			cyNext = cyNext - 16
		end

		if(countText) then
			countText:ClearAllPoints()
			countText:SetPoint('LEFT', inner, 'TOPLEFT', 0, cyNext - STEP_BTN_SIZE / 2)
			cyNext = cyNext - STEP_BTN_SIZE - 6
		end

		if(petToggle) then
			petToggle:ClearAllPoints()
			petToggle:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cyNext)
			cyNext = cyNext - 16
		end

		viewport:ClearAllPoints()
		viewport:SetPoint('TOPLEFT', inner, 'TOPLEFT', 0, cyNext)
		viewport:SetPoint('RIGHT', inner, 'RIGHT', 0, 0)

		card._cyBeforeViewport = cyNext
		return true
	end

	relayoutFocusAndRows(width)
	cy = card._cyBeforeViewport
	card._relayoutFocusAndRows = relayoutFocusAndRows

	local config = getUnitConfig(unitType)
	local inset2 = PREVIEW_INSET * 2
	local MAX_PREVIEW_H = 120
	local cbExtra = config and getCastbarExtra(config) or 0
	local naturalH
	if(not config) then
		naturalH = 60
	elseif(SOLO_FAKES[unitType]) then
		naturalH = config.height + cbExtra + inset2
	elseif(unitType == 'raid') then
		local count = F.Config:GetChar('settings.raidPreviewCount')
		local rows = math.min(count, config.unitsPerColumn)
		naturalH = rows * config.height + (rows - 1) * config.spacing + cbExtra + inset2
	elseif(GROUP_COUNTS[unitType]) then
		local count = GROUP_COUNTS[unitType]
		local rows = math.min(count, config.unitsPerColumn)
		naturalH = rows * config.height + (rows - 1) * config.spacing + cbExtra + inset2
	else
		naturalH = config.height + cbExtra + inset2
	end

	local previewScale = 1
	if(naturalH > MAX_PREVIEW_H) then
		previewScale = MAX_PREVIEW_H / naturalH
	end
	local viewH = math.ceil(naturalH * previewScale)

	viewContent:SetScale(previewScale)
	viewContent:SetWidth(width / previewScale)
	viewContent:SetHeight(naturalH)
	viewport:SetHeight(viewH)
	card._previewScale = previewScale
	card._cyBeforeViewport = cy
	card._viewportBottomPad = 0
	card._parent = parent
	cy = cy - viewH

	activeUnitType = unitType
	if(SOLO_FAKES[unitType]) then
		RenderSoloPreview(viewContent, unitType)
	elseif(unitType == 'raid') then
		local count = F.Config:GetChar('settings.raidPreviewCount')
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
	card._naturalH = card:GetHeight()

	activePreview = card
	card._viewport = viewport
	card._viewContent = viewContent
	card._unitType = unitType

	-- Reflow Focus Mode between rows as the card width changes (raid stepper
	-- shifts columns, window resize, pinned split animation). Two guards keep
	-- this from replaying the frame animation:
	--   1) Skip during an active 'previewWidth' tween — OnSizeChanged fires
	--      per-frame during the tween; letting it act mid-tween would kick off
	--      a second full rebuild on top of the one the stepper already ran.
	--      The tween's onComplete fires a final SetWidth that naturally
	--      triggers OnSizeChanged with the settled width.
	--   2) When the decision does flip, only the viewport's y-anchor and the
	--      card height need to change — frame count/config is identical, so
	--      re-rendering frames would replay their cross-fade for no visual
	--      benefit. UpdateCardHeightLightly just animates the card height.
	card:SetScript('OnSizeChanged', function(self)
		if(not card._relayoutFocusAndRows) then return end
		if(card._anim and card._anim['previewWidth']) then return end

		if(card._relayoutFocusAndRows(self:GetWidth())) then
			if(activePreview == self) then FP.UpdateCardHeightLightly() end
		end
	end)

	return card
end

-- ============================================================
-- Public: Restore a previously built preview card as active
-- ============================================================

function FP.RestorePreview(card, unitType)
	if(activePreview and activePreview ~= card) then
		FP.Destroy()
	end

	activePreview = card
	activeUnitType = unitType
	focusModeEnabled = F.Config:Get('general.settingsFocusMode') or false

	RegisterConfigListener()
	F.EventBus:Register('EDITING_PRESET_CHANGED', function()
		FP.RebuildPreview()
	end, 'FramePreview.PresetListener')

	FP.RebuildPreview()
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

	focusModeEnabled = F.Config:Get('general.settingsFocusMode') or false

	UnregisterConfigListener()
	F.EventBus:Unregister('EDITING_PRESET_CHANGED', 'FramePreview.PresetListener')

	activePreview = nil
	activeUnitType = nil
end
