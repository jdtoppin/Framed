local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Defensives = {}

-- ============================================================
-- Reusable table pool — avoids allocations on every UNIT_AURA
-- ============================================================

local auraPool = {}
local auraCount = 0

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedDefensives
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local cfg = element._config
	local maxDisplayed   = cfg.maxDisplayed
	local visibilityMode = cfg.visibilityMode
	local playerColor    = cfg.playerColor
	local otherColor     = cfg.otherColor

	-- BIG_DEFENSIVE is a classification filter, not a query filter —
	-- GetUnitAuras does not support it. Fetch all helpful auras, then
	-- classify each one via IsAuraFilteredOutByInstanceID.
	local rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')

	auraCount = 0
	for _, auraData in next, rawAuras do
		local id = auraData.auraInstanceID -- NeverSecret

		-- Step 1: BIG_DEFENSIVE (primary classification)
		-- Exclude EXTERNAL_DEFENSIVE — those belong in the Externals element.
		local show = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
			unit, id, 'HELPFUL|BIG_DEFENSIVE')
		if(show) then
			local isExtDef = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
				unit, id, 'HELPFUL|EXTERNAL_DEFENSIVE')
			if(isExtDef) then show = false end
		end

		-- Skip long-duration buffs (flasks, food, racials) that aren't
		-- real defensives. duration == 0 means permanent.
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
				auraCount = auraCount + 1
				local entry = auraPool[auraCount]
				if(not entry) then
					entry = {}
					auraPool[auraCount] = entry
				end
				entry.auraInstanceID = id
				entry.spellId        = auraData.spellId
				entry.icon           = auraData.icon
				entry.duration       = auraData.duration
				entry.expirationTime = auraData.expirationTime
				entry.stacks         = auraData.applications
				entry.isPlayerCast   = isPlayerCast
			end
		end
	end

	-- Display up to maxDisplayed using BorderIcon pool
	local count = math.min(auraCount, maxDisplayed)
	local pool = element._pool
	local iconSize    = cfg.iconSize
	local orientation = cfg.orientation
	local anchor      = cfg.anchor
	local anchorPoint = anchor[1]
	local anchorX     = anchor[4]
	local anchorY     = anchor[5]

	for idx = 1, count do
		local aura = auraPool[idx]

		if(not pool[idx]) then
			pool[idx] = F.Indicators.BorderIcon.Create(self, iconSize, {
				showCooldown = true,
				showStacks   = cfg.showStacks ~= false,
				showDuration = cfg.showDuration ~= false,
				frameLevel   = cfg.frameLevel,
				stackFont    = cfg.stackFont,
				durationFont = cfg.durationFont,
			})
		end

		local bi = pool[idx]

		bi:ClearAllPoints()
		bi:SetSize(iconSize)

		-- Position: anchor directly to the unit frame, offset by prior icons
		local offset = (idx - 1) * (iconSize + 2)

		if(orientation == 'RIGHT') then
			bi:SetPoint(anchorPoint, self, anchorPoint, anchorX + offset, anchorY)
		elseif(orientation == 'LEFT') then
			bi:SetPoint(anchorPoint, self, anchorPoint, anchorX - offset, anchorY)
		elseif(orientation == 'DOWN') then
			bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY - offset)
		elseif(orientation == 'UP') then
			bi:SetPoint(anchorPoint, self, anchorPoint, anchorX, anchorY + offset)
		end

		local borderColor = aura.isPlayerCast and playerColor or otherColor
		if(bi.SetBorderColor) then
			bi:SetBorderColor(borderColor[1], borderColor[2], borderColor[3])
		end

		bi:SetAura(
			unit, aura.auraInstanceID,
			aura.spellId,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.stacks,
			nil
		)
		bi:Show()
	end

	for idx = count + 1, #pool do
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

	local element = {
		_config    = config,
		_pool      = {},
		Rebuild    = Rebuild,
	}

	self.FramedDefensives = element
end
