local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Externals = {}

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedExternals
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local cfg = element._config
	local maxDisplayed   = cfg.maxDisplayed or 3
	local visibilityMode = cfg.visibilityMode or 'all'
	local playerColor    = cfg.playerColor or { 0, 0.8, 0 }
	local otherColor     = cfg.otherColor or { 1, 0.85, 0 }

	-- Build filter string based on visibility mode
	local filter = 'HELPFUL|EXTERNAL_DEFENSIVE'
	if(visibilityMode == 'player') then
		filter = 'HELPFUL|EXTERNAL_DEFENSIVE|PLAYER'
	end

	local rawAuras = C_UnitAuras.GetUnitAuras(unit, filter)

	-- Collect auras with source classification
	local auraList = {}
	for _, auraData in next, rawAuras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			-- Determine if player-cast via |PLAYER filter (avoids secret sourceUnit)
			local isPlayerCast = false
			if(visibilityMode == 'player') then
				-- All results are player-cast (filter already includes |PLAYER)
				isPlayerCast = true
			else
				-- Check via supplementary filter
				isPlayerCast = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
					unit, auraData.auraInstanceID, 'HELPFUL|EXTERNAL_DEFENSIVE|PLAYER')
			end

			-- Apply "others only" filter
			if(visibilityMode == 'others' and isPlayerCast) then
				-- Skip player-cast auras in "others" mode
			else
				auraList[#auraList + 1] = {
					spellId        = spellId,
					icon           = auraData.icon,
					duration       = auraData.duration,
					expirationTime = auraData.expirationTime,
					stacks         = auraData.applications or 0,
					isPlayerCast   = isPlayerCast,
				}
			end
		end
	end

	-- Display up to maxDisplayed using BorderIcon pool
	local count = math.min(#auraList, maxDisplayed)
	local pool = element._pool
	local iconSize = cfg.iconSize or 16
	local orientation = cfg.orientation or 'RIGHT'

	for idx = 1, count do
		local aura = auraList[idx]

		-- Lazily create pool entries
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

		-- Position
		local offset = (idx - 1) * (iconSize + 2)

		if(orientation == 'RIGHT') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', offset, 0)
		elseif(orientation == 'LEFT') then
			bi:SetPoint('TOPRIGHT', element._container, 'TOPRIGHT', -offset, 0)
		elseif(orientation == 'DOWN') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', 0, -offset)
		elseif(orientation == 'UP') then
			bi:SetPoint('BOTTOMLEFT', element._container, 'BOTTOMLEFT', 0, offset)
		end

		-- Set border color based on source
		local borderColor = aura.isPlayerCast and playerColor or otherColor
		if(bi.SetBorderColor) then
			bi:SetBorderColor(borderColor[1], borderColor[2], borderColor[3])
		end

		bi:SetAura(
			aura.spellId,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.stacks,
			nil
		)
		bi:Show()
	end

	-- Hide pool entries beyond active count
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
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedExternals', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create an Externals element on a unit frame.
--- Shows BorderIcons for external defensive buffs (Pain Suppression, Ironbark, etc.).
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

	local container = CreateFrame('Frame', nil, self)
	container:SetAllPoints(self)

	local element = {
		_container = container,
		_config    = config,
		_pool      = {},
	}

	local a = config.anchor
	if(a) then
		container:ClearAllPoints()
		Widgets.SetPoint(container, a[1], a[2] or self, a[3], a[4] or 0, a[5] or 0)
	end

	self.FramedExternals = element
end
