local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Externals = {}

-- ============================================================
-- Update — single-pass filter + display (zero intermediate tables)
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedExternals
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

	-- EXTERNAL_DEFENSIVE is a classification filter, not a query filter —
	-- GetUnitAuras does not support it. Fetch all helpful auras, then
	-- classify each one via IsAuraFilteredOutByInstanceID.
	local rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')

	local displayed = 0
	for _, auraData in next, rawAuras do
		if(displayed >= maxDisplayed) then break end

		local id = auraData.auraInstanceID -- NeverSecret

		-- Step 1: EXTERNAL_DEFENSIVE (primary classification)
		local show = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
			unit, id, 'HELPFUL|EXTERNAL_DEFENSIVE')

		-- Step 2: IMPORTANT fallback — catch spells that aren't classified
		-- as EXTERNAL_DEFENSIVE. Exclude BIG_DEFENSIVE to avoid duplicating
		-- spells that already appear in the Defensives element.
		-- NOTE: IMPORTANT may be removed in 12.0.5 per Blizzard feedback.
		if(not show) then
			local isImportant = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
				unit, id, 'HELPFUL|IMPORTANT')
			if(isImportant) then
				local isBigDef = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
					unit, id, 'HELPFUL|BIG_DEFENSIVE')
				show = not isBigDef
			end
		end

		-- Step 3: RAID fallback — only for secret auras (combat) where
		-- spell-level classification isn't available. Catches Power Infusion
		-- and similar raid-important buffs. Too broad out of combat (catches
		-- basic HoTs like Rejuvenation). Exclude BIG_DEFENSIVE to avoid
		-- duplicating with Defensives.
		if(not show) then
			local isSecret = not F.IsValueNonSecret(auraData.spellId)
			if(isSecret) then
				local isRaid = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
					unit, id, 'HELPFUL|RAID')
				if(isRaid) then
					local isBigDef = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
						unit, id, 'HELPFUL|BIG_DEFENSIVE')
					show = not isBigDef
				end
			end
		end

		-- Skip long-duration buffs (flasks, food, racials) that slip through
		-- classification filters. duration == 0 means permanent.
		if(show) then
			local dur = auraData.duration
			if(F.IsValueNonSecret(dur) and (dur == 0 or dur >= 600)) then
				show = false
			end
		end

		if(show) then
			-- Determine if player-cast via |PLAYER filter (avoids secret sourceUnit)
			local isPlayerCast = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
				unit, id, 'HELPFUL|PLAYER')

			-- Apply visibility mode filter
			if(visibilityMode == 'player' and not isPlayerCast) then
				-- Skip non-player auras in "player" mode
			elseif(visibilityMode == 'others' and isPlayerCast) then
				-- Skip player-cast auras in "others" mode
			else
				-- Display directly — no intermediate table
				displayed = displayed + 1

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
		end
	end

	-- Hide pool entries beyond active count
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
	local element = self.FramedExternals
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedExternals
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

oUF:AddElement('FramedExternals', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create an Externals element on a unit frame.
--- Shows BorderIcons for external defensive buffs (Pain Suppression, Ironbark, etc.)
--- and IMPORTANT-flagged buffs not already classified as BIG_DEFENSIVE.
--- Supports visibility modes: 'all' (default), 'player', 'others'.
--- Border color differentiates player-cast (green) from other-cast (yellow).
--- Assigns result to self.FramedExternals, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: iconSize, maxDisplayed, showDuration,
---                       showStacks, orientation, anchor, frameLevel,
---                       stackFont, durationFont, visibilityMode,
---                       playerColor, otherColor
function F.Elements.Externals.Setup(self, config)
	config = config or {}

	local element = {
		_config    = config,
		_pool      = {},
		Rebuild    = Rebuild,
	}

	self.FramedExternals = element
end
