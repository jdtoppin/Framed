local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Defensives = {}

local DEFAULT_PLAYER_COLOR = { 0, 0.8, 0 }
local DEFAULT_OTHER_COLOR  = { 1, 0.85, 0 }

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedDefensives
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local cfg = element._config
	local maxDisplayed   = cfg.maxDisplayed or 3
	local visibilityMode = cfg.visibilityMode or 'all'
	local playerColor    = cfg.playerColor or DEFAULT_PLAYER_COLOR
	local otherColor     = cfg.otherColor or DEFAULT_OTHER_COLOR

	-- BIG_DEFENSIVE is a classification filter, not a query filter —
	-- GetUnitAuras does not support it. Fetch all helpful auras, then
	-- classify each one via IsAuraFilteredOutByInstanceID.
	local rawAuras = C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')

	local auraList = {}
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

		-- Step 2: IMPORTANT fallback — catch spells like Fade that aren't
		-- classified as BIG_DEFENSIVE. Exclude EXTERNAL_DEFENSIVE to avoid
		-- duplicating spells that already appear in the Externals element.
		-- NOTE: IMPORTANT may be removed in 12.0.5 per Blizzard feedback.
		if(not show) then
			local isImportant = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
				unit, id, 'HELPFUL|IMPORTANT')
			if(isImportant) then
				local isExtDef = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
					unit, id, 'HELPFUL|EXTERNAL_DEFENSIVE')
				show = not isExtDef
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
				auraList[#auraList + 1] = {
					auraInstanceID = id,
					spellId        = auraData.spellId,
					icon           = auraData.icon,
					duration       = auraData.duration,
					expirationTime = auraData.expirationTime,
					stacks         = auraData.applications,
					isPlayerCast   = isPlayerCast,
				}
			end
		end
	end

	-- Display up to maxDisplayed using BorderIcon pool
	local count = math.min(#auraList, maxDisplayed)
	local pool = element._pool
	local iconSize    = cfg.iconSize or 16
	local orientation = cfg.orientation or 'RIGHT'
	local anchor      = cfg.anchor or { 'LEFT', nil, 'LEFT', -2, 5 }
	local anchorPoint = anchor[1]
	local anchorX     = anchor[4] or 0
	local anchorY     = anchor[5] or 0

	for idx = 1, count do
		local aura = auraList[idx]

		if(not pool[idx]) then
			pool[idx] = F.Indicators.BorderIcon.Create(self, iconSize, {
				showCooldown = true,
				showStacks   = cfg.showStacks ~= false,
				showDuration = cfg.showDuration ~= false,
				frameLevel   = cfg.frameLevel or 5,
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
