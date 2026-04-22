local _, Framed = ...
local F = Framed
local oUF = F.oUF

F.Elements = F.Elements or {}
F.Elements.Defensives = {}

-- ============================================================
-- renderEntry — acquire / position / paint a single BorderIcon slot
-- ============================================================

local function renderEntry(self, element, pool, displayed, iconSize, cfg, orientation,
	anchorPoint, anchorX, anchorY, playerColor, otherColor,
	unit, id, auraData, isPlayerCast)

	if(not pool[displayed]) then
		pool[displayed] = F.Indicators.BorderIcon.Create(self, iconSize, {
			showCooldown = true,
			showStacks   = cfg.showStacks ~= false,
			showDuration = cfg.showDuration ~= false,
			frameLevel   = cfg.frameLevel,
			stackFont    = cfg.stackFont,
			durationFont = cfg.durationFont,
		})
	end

	local bi = pool[displayed]
	bi:ClearAllPoints()
	bi:SetSize(iconSize)

	local offset = (displayed - 1) * (iconSize + 2)
	if(orientation == 'RIGHT') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX + offset, anchorY)
	elseif(orientation == 'LEFT') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX - offset, anchorY)
	elseif(orientation == 'DOWN') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY - offset)
	elseif(orientation == 'UP') then
		bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY + offset)
	end

	local borderColor = isPlayerCast and playerColor or otherColor
	if(bi.SetBorderColor) then
		bi:SetBorderColor(borderColor[1], borderColor[2], borderColor[3])
	end

	bi:SetAura(
		unit, id,
		auraData.spellId,
		auraData.icon,
		auraData.duration,
		auraData.expirationTime,
		auraData.applications,
		nil
	)
	bi:Show()
end

-- ============================================================
-- Update — single-pass filter + display (zero intermediate tables)
-- ============================================================

local function Update(self, event, unit, updateInfo)
	local element = self.FramedDefensives
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local cfg = element._config
	local maxDisplayed   = cfg.maxDisplayed
	local visibilityMode = cfg.visibilityMode
	local playerColor    = cfg.playerColor
	local otherColor     = cfg.otherColor
	local pool           = element._pool
	local iconSize       = cfg.iconSize
	local orientation    = cfg.orientation
	local anchor         = cfg.anchor
	local anchorPoint    = anchor[1]
	local anchorX        = anchor[4]
	local anchorY        = anchor[5]

	local auraState = self.FramedAuraState
	if(auraState) then
		if(event == 'UNIT_AURA') then
			auraState:ApplyUpdateInfo(unit, updateInfo)
		else
			auraState:EnsureInitialized(unit)
		end
	end

	local classified = auraState and auraState:GetHelpfulClassified()
	local rawAuras   = (not classified) and F.AuraCache.GetUnitAuras(unit, 'HELPFUL') or nil

	local displayed = 0

	if(classified) then
		for _, entry in next, classified do
			if(displayed >= maxDisplayed) then break end

			local auraData = entry.aura
			local flags    = entry.flags
			local id       = auraData.auraInstanceID

			-- Primary classification: BIG_DEFENSIVE, excluding EXTERNAL_DEFENSIVE
			-- (those belong in the Externals element).
			local show = flags.isBigDefensive and not flags.isExternalDefensive

			-- Skip long-duration buffs (flasks, food, racials) that aren't real
			-- defensives. duration == 0 means permanent.
			if(show) then
				local dur = auraData.duration
				if(F.IsValueNonSecret(dur) and (dur == 0 or dur >= 600)) then
					show = false
				end
			end

			if(show) then
				local isPlayerCast = flags.isPlayerCast

				if(not ((visibilityMode == 'player' and not isPlayerCast)
					or (visibilityMode == 'others' and isPlayerCast))) then
					displayed = displayed + 1
					renderEntry(self, element, pool, displayed, iconSize, cfg, orientation,
						anchorPoint, anchorX, anchorY, playerColor, otherColor,
						unit, id, auraData, isPlayerCast)
				end
			end
		end
	else
		-- Fallback: no AuraState on this frame. Vestigial in practice — every
		-- aura-tracking frame creates AuraState via the idempotent Setup guard —
		-- preserved to match the element-level pattern used across Auras/.
		for _, auraData in next, rawAuras do
			if(displayed >= maxDisplayed) then break end

			local id = auraData.auraInstanceID

			local show = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
				unit, id, 'HELPFUL|BIG_DEFENSIVE')
			if(show) then
				local isExtDef = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
					unit, id, 'HELPFUL|EXTERNAL_DEFENSIVE')
				if(isExtDef) then show = false end
			end

			if(show) then
				local dur = auraData.duration
				if(F.IsValueNonSecret(dur) and (dur == 0 or dur >= 600)) then
					show = false
				end
			end

			if(show) then
				local isPlayerCast = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
					unit, id, 'HELPFUL|PLAYER')

				if(not ((visibilityMode == 'player' and not isPlayerCast)
					or (visibilityMode == 'others' and isPlayerCast))) then
					displayed = displayed + 1
					renderEntry(self, element, pool, displayed, iconSize, cfg, orientation,
						anchorPoint, anchorX, anchorY, playerColor, otherColor,
						unit, id, auraData, isPlayerCast)
				end
			end
		end
	end

	for idx = displayed + 1, #pool do
		pool[idx]:Clear()
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
	local element = self.FramedDefensives
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedDefensives
	if(not element) then return end

	for _, bi in next, element._pool do
		bi:Clear()
	end

	self:UnregisterEvent('UNIT_AURA', Update)
end

-- ============================================================
-- Rebuild
-- ============================================================

local function Rebuild(element, config)
	if(element._pool) then
		for _, bi in next, element._pool do
			bi:Clear()
			if(bi.Destroy) then bi:Destroy() end
		end
	end

	element._config = config
	element._pool   = {}

	element:ForceUpdate()
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedDefensives', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create a Defensives element on a unit frame.
--- Shows BorderIcons for major personal defensive cooldowns
--- (Ice Block, Divine Shield, Shield Wall, etc.) and IMPORTANT-flagged
--- buffs not already classified as EXTERNAL_DEFENSIVE.
--- Supports visibility modes: 'all' (default), 'player', 'others'.
--- Border color differentiates player-cast (green) from other-cast (yellow).
--- Assigns result to self.FramedDefensives, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: iconSize, maxDisplayed, showDuration,
---                       showStacks, orientation, anchor, frameLevel,
---                       stackFont, durationFont, visibilityMode,
---                       playerColor, otherColor
function F.Elements.Defensives.Setup(self, config)
	config = config or {}

	if(not self.FramedAuraState and F.AuraState) then
		self.FramedAuraState = F.AuraState.Create(self)
	end

	local element = {
		_config    = config,
		_pool      = {},
		Rebuild    = Rebuild,
	}

	self.FramedDefensives = element
end
