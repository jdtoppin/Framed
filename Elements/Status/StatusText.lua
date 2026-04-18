local _, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.StatusText = {}

-- ============================================================
-- Status color constants
-- ============================================================

local COLOR_DEAD     = { 0.8, 0.1, 0.1 }
local COLOR_GHOST    = { 0.6, 0.6, 0.6 }
local COLOR_OFFLINE  = { 0.5, 0.5, 0.5 }
local COLOR_AFK      = { 0.8, 0.1, 0.1 }
local COLOR_FEIGN    = { 1, 1, 0.12 }
local COLOR_DRINKING = { 0.12, 0.75, 1 }
local COLOR_PENDING  = { 1, 1, 0.12 }
local COLOR_ACCEPTED = { 0.2, 0.8, 0.2 }
local COLOR_DECLINED = { 0.8, 0.1, 0.1 }

-- Summon status enum values
local SUMMON_PENDING  = 1
local SUMMON_ACCEPTED = 2
local SUMMON_DECLINED = 3

-- Gradient background texture (dark left → transparent right)
local GRADIENT_TEXTURE = F.Media.GetTexture('GradientH')

-- ============================================================
-- Drink buff detection
-- ============================================================

-- Known drink spell IDs (same list as Cell)
local drinkSpellIds = {
	170906, -- Food & Drink
	167152, -- Refreshment
	430,    -- Drink
	43182,  -- Drink
	172786, -- Drink
	308433, -- Food & Drink
	369162, -- Drink
	456574, -- Cinder Nectar
	461063, -- Quiet Contemplation (Earthen)
}

local drinkNames

local function getDrinkNames()
	if(drinkNames) then return drinkNames end
	drinkNames = {}
	if(not C_Spell or not C_Spell.GetSpellName) then return drinkNames end
	for _, id in next, drinkSpellIds do
		local name = C_Spell.GetSpellName(id)
		if(name) then
			drinkNames[name] = true
		end
	end
	return drinkNames
end

local function checkDrinking(unit)
	-- Player-combat early-out: you can't drink in combat, and if the player
	-- is in combat, party members are almost certainly too (so their aura
	-- names will be secret anyway). Skip the scan entirely.
	if(InCombatLockdown()) then return false end
	local names = getDrinkNames()
	if(not next(names)) then return false end
	local slots = { C_UnitAuras.GetAuraSlots(unit, 'HELPFUL') }
	for i = 2, #slots do
		local aura = C_UnitAuras.GetAuraDataBySlot(unit, slots[i])
		-- A unit can be in combat independently of the player — in that
		-- case aura.name is a secret string (truthy but taints table keys).
		-- Guard per-aura so we gracefully skip units we can't inspect.
		if(aura and F.IsValueNonSecret(aura.name) and names[aura.name]) then
			return true
		end
	end
	return false
end

-- ============================================================
-- Timer tracking
-- ============================================================

-- Start times keyed by GUID for timed statuses (AFK, offline).
local startTimeCache = {}

local function formatElapsed(seconds)
	if(seconds >= 3600) then
		return format('%dh', math.ceil(seconds / 3600))
	elseif(seconds >= 60) then
		return format('%dm', math.ceil(seconds / 60))
	end
	return format('%ds', math.floor(seconds))
end

local function startTimer(element, guid)
	if(not guid or not F.IsValueNonSecret(guid)) then return end
	if(not startTimeCache[guid]) then
		startTimeCache[guid] = GetTime()
	end
	-- Show the timer FontString and start a 1-second ticker
	element._timer:Show()
	if(not element._ticker) then
		element._ticker = C_Timer.NewTicker(1, function()
			if(not element:IsShown()) then return end
			local owner = element.__owner
			if(not owner or not owner.unit) then return end
			local g = UnitGUID(owner.unit)
			if(g and F.IsValueNonSecret(g) and startTimeCache[g]) then
				element._timer:SetText(formatElapsed(GetTime() - startTimeCache[g]))
			end
		end)
	end
end

local function stopTimer(element, guid, reset)
	if(element._ticker) then
		element._ticker:Cancel()
		element._ticker = nil
	end
	if(element._timer) then
		element._timer:Hide()
	end
	if(reset and guid and F.IsValueNonSecret(guid)) then
		startTimeCache[guid] = nil
	end
end

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedStatusText
	if(not element) then return end

	if(unit ~= self.unit) then return end

	local text, color, timed

	-- Unit status APIs return secret booleans in combat; guard with
	-- IsValueNonSecret so we degrade gracefully (hide text) instead of erroring.
	local dead      = UnitIsDeadOrGhost(unit)
	local ghost     = UnitIsGhost(unit)
	local connected = UnitIsConnected(unit)
	local afk       = UnitIsAFK(unit)
	local feign     = UnitIsFeignDeath(unit)

	if(F.IsValueNonSecret(dead) and dead) then
		if(F.IsValueNonSecret(ghost) and ghost) then
			text  = 'GHOST'
			color = COLOR_GHOST
		else
			text  = 'DEAD'
			color = COLOR_DEAD
		end
	elseif(F.IsValueNonSecret(connected) and not connected) then
		text  = 'OFFLINE'
		color = COLOR_OFFLINE
		timed = true
	elseif(F.IsValueNonSecret(afk) and afk) then
		text  = 'AFK'
		color = COLOR_AFK
		timed = true
	elseif(F.IsValueNonSecret(feign) and feign) then
		text  = 'FEIGN'
		color = COLOR_FEIGN
	elseif(C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus) then
		local status = C_IncomingSummon.IncomingSummonStatus(unit)
		if(F.IsValueNonSecret(status)) then
			if(status == SUMMON_PENDING) then
				text  = 'PENDING'
				color = COLOR_PENDING
			elseif(status == SUMMON_ACCEPTED) then
				text  = 'ACCEPTED'
				color = COLOR_ACCEPTED
			elseif(status == SUMMON_DECLINED) then
				text  = 'DECLINED'
				color = COLOR_DECLINED
			end
		end
	end

	-- Drinking — lowest priority, only out of combat (can't drink in combat)
	if(not text and checkDrinking(unit)) then
		text  = 'DRINKING'
		color = COLOR_DRINKING
	end

	local guid = UnitGUID(unit)

	if(text) then
		element._label:SetText(text)
		element._label:SetTextColor(color[1], color[2], color[3], 1)
		element._timer:SetTextColor(color[1], color[2], color[3], 1)
		element:Show()

		if(timed) then
			startTimer(element, guid)
		else
			stopTimer(element, guid, true)
		end
	else
		stopTimer(element, guid, true)
		element:Hide()
	end
end

-- ============================================================
-- ForceUpdate
-- ============================================================

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

-- ============================================================
-- Enable / Disable
-- ============================================================

local function Enable(self, unit)
	local element = self.FramedStatusText
	if(not element) then return end

	element.__owner   = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_HEALTH',            Update)
	self:RegisterEvent('UNIT_CONNECTION',         Update)
	self:RegisterEvent('PLAYER_FLAGS_CHANGED',    Update)
	self:RegisterEvent('INCOMING_SUMMON_CHANGED', Update, true)
	self:RegisterEvent('UNIT_AURA',              Update)

	return true
end

local function Disable(self)
	local element = self.FramedStatusText
	if(not element) then return end

	stopTimer(element, nil, false)
	element:Hide()

	self:UnregisterEvent('UNIT_HEALTH',            Update)
	self:UnregisterEvent('UNIT_CONNECTION',         Update)
	self:UnregisterEvent('PLAYER_FLAGS_CHANGED',    Update)
	self:UnregisterEvent('INCOMING_SUMMON_CHANGED', Update)
	self:UnregisterEvent('UNIT_AURA',              Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedStatusText', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create the status text container with gradient background, label, and timer.
--- Assigns result to self.FramedStatusText, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: fontSize, outline, shadow
function F.Elements.StatusText.Setup(self, config)
	local size    = config.fontSize
	local outline = config.outline ~= '' and config.outline or nil

	-- Container frame — sits above health bar via overlay (same pattern as Name).
	local overlay = self._statusTextOverlay
	if(not overlay) then
		overlay = CreateFrame('Frame', nil, self)
		overlay:SetAllPoints(self)
		overlay:SetFrameLevel(self:GetFrameLevel() + 5)
		self._statusTextOverlay = overlay
	end

	local container = self.FramedStatusText
	local isNew = not container
	if(isNew) then
		container = CreateFrame('Frame', nil, overlay)
	end
	-- Anchor to the health bar (not the unit frame) so the status text sits
	-- above the power bar. Position is configurable: top, center, or bottom.
	local anchorTo = self.Health or self
	container:ClearAllPoints()
	local position = config.position
	if(position == 'top') then
		container:SetPoint('TOPLEFT',  anchorTo, 'TOPLEFT',  0, 0)
		container:SetPoint('TOPRIGHT', anchorTo, 'TOPRIGHT', 0, 0)
	elseif(position == 'center') then
		container:SetPoint('LEFT',  anchorTo, 'LEFT',  0, 0)
		container:SetPoint('RIGHT', anchorTo, 'RIGHT', 0, 0)
	else
		container:SetPoint('BOTTOMLEFT',  anchorTo, 'BOTTOMLEFT',  0, 0)
		container:SetPoint('BOTTOMRIGHT', anchorTo, 'BOTTOMRIGHT', 0, 0)
	end
	container:SetHeight(size + 2)

	-- Gradient background (dark left → transparent right)
	local bg = container._bg
	if(not bg) then
		bg = container:CreateTexture(nil, 'BACKGROUND')
		container._bg = bg
	end
	bg:SetAllPoints(container)
	bg:SetTexture(GRADIENT_TEXTURE)
	bg:SetVertexColor(0, 0, 0, 0.777)

	-- Label FontString (left-justified — "AFK", "DEAD", etc.)
	local label = container._label
	if(not label) then
		label = Widgets.CreateFontString(container, size, C.Colors.textActive)
		container._label = label
	end
	label:SetFont(F.Media.GetActiveFont(), size, outline)
	if(config.shadow) then
		label:SetShadowOffset(1, -1)
		label:SetShadowColor(0, 0, 0, 0.8)
	else
		label:SetShadowOffset(0, 0)
	end
	label:ClearAllPoints()
	label:SetPoint('LEFT', container, 'LEFT', 2, 0)
	label:SetJustifyH('LEFT')

	-- Timer FontString (right-justified — "2m", "5h", etc.)
	local timer = container._timer
	if(not timer) then
		timer = Widgets.CreateFontString(container, size, C.Colors.textActive)
		container._timer = timer
	end
	timer:SetFont(F.Media.GetActiveFont(), size, outline)
	if(config.shadow) then
		timer:SetShadowOffset(1, -1)
		timer:SetShadowColor(0, 0, 0, 0.8)
	else
		timer:SetShadowOffset(0, 0)
	end
	timer:ClearAllPoints()
	timer:SetPoint('RIGHT', container, 'RIGHT', -2, 0)
	timer:SetJustifyH('RIGHT')
	timer:Hide()

	-- Store config for live updates
	container._config = config

	-- Only hide on first-time creation — live reconfig should leave the
	-- current display state alone and let ForceUpdate re-evaluate it.
	if(isNew) then
		container:Hide()
	end

	self.FramedStatusText = container
end
