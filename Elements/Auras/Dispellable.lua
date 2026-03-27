local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Dispellable = {}

-- ============================================================
-- Dispel type priority
-- ============================================================

-- Priority: Magic(1) > Curse(2) > Disease(3) > Poison(4) > Physical(5)
local DISPEL_PRIORITY = {
	Magic    = 1,
	Curse    = 2,
	Disease  = 3,
	Poison   = 4,
	Physical = 5,
}

-- ============================================================
-- Overlay helpers
-- ============================================================

local OVERLAY_ALPHA = 0.35

local function hideAllOverlays(element)
	if(element._overlayGradientFull) then element._overlayGradientFull:Hide() end
	if(element._overlayGradientHalf) then element._overlayGradientHalf:Hide() end
	if(element._overlaySolidCurrent) then element._overlaySolidCurrent:Hide() end
	if(element._overlaySolidEntire) then element._overlaySolidEntire:Hide() end
end

--- Ensure overlay textures are positioned on first use.
--- SetPoint is deferred from creation because it runs inside
--- CallMethod from SecureGroupHeaderTemplate where SetPoint fails.
local function ensureOverlayPositioned(element)
	if(element._overlaysPositioned) then return end
	element._overlaysPositioned = true

	local gradFull = element._overlayGradientFull
	if(gradFull) then
		-- Position the overlay frame to match the health wrapper
		local overlayFrame = gradFull._overlayFrame
		if(overlayFrame) then
			overlayFrame:SetAllPoints()
		end
		gradFull:SetPoint('TOPLEFT', 1, -1)
		gradFull:SetPoint('BOTTOMRIGHT', -1, 1)
	end

	local gradHalf = element._overlayGradientHalf
	if(gradHalf) then
		gradHalf:SetPoint('TOPLEFT', 1, -1)
		gradHalf:SetPoint('TOPRIGHT', -1, -1)
		-- Use parent height since health bar height is known at this point
		local parent = gradHalf:GetParent()
		if(parent) then
			gradHalf:SetHeight((parent:GetHeight() or 20) * 0.5)
		end
	end

	local solidCur = element._overlaySolidCurrent
	if(solidCur) then
		solidCur:SetPoint('TOPLEFT', 1, -1)
		solidCur:SetPoint('BOTTOMLEFT', 1, 1)
	end

	local solidEnt = element._overlaySolidEntire
	if(solidEnt) then
		solidEnt:SetAllPoints()
	end
end

local function showOverlay(element, highlightType, r, g, b)
	hideAllOverlays(element)
	ensureOverlayPositioned(element)

	local ht = C.HighlightType
	if(highlightType == ht.GRADIENT_FULL and element._overlayGradientFull) then
		local tex = element._overlayGradientFull
		tex:SetVertexColor(r, g, b, OVERLAY_ALPHA)
		tex:SetGradient('VERTICAL', CreateColor(r, g, b, 0), CreateColor(r, g, b, OVERLAY_ALPHA))
		tex:Show()
	elseif(highlightType == ht.GRADIENT_HALF and element._overlayGradientHalf) then
		local tex = element._overlayGradientHalf
		tex:SetVertexColor(r, g, b, OVERLAY_ALPHA)
		tex:SetGradient('VERTICAL', CreateColor(r, g, b, 0), CreateColor(r, g, b, OVERLAY_ALPHA))
		tex:Show()
	elseif(highlightType == ht.SOLID_CURRENT and element._overlaySolidCurrent) then
		local tex = element._overlaySolidCurrent
		tex:SetVertexColor(r, g, b, OVERLAY_ALPHA)
		tex:Show()
	elseif(highlightType == ht.SOLID_ENTIRE and element._overlaySolidEntire) then
		local tex = element._overlaySolidEntire
		tex:SetVertexColor(r, g, b, OVERLAY_ALPHA)
		tex:Show()
	end
end

-- ============================================================
-- Determine if a debuff is Physical/bleed
-- ============================================================

local function isPhysicalOrBleed(dispelName)
	return (not dispelName) or (dispelName == '') or (dispelName == 'Physical')
end

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedDispellable
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local bestType       = nil
	local bestPriority   = 999
	local bestIcon       = nil
	local bestSpellId    = nil
	local bestDuration   = nil
	local bestExpiration = nil
	local bestStacks     = nil

	local onlyDispellableByMe = element._onlyDispellableByMe

	-- Choose filter based on onlyDispellableByMe setting
	local primaryFilter = onlyDispellableByMe and 'HARMFUL|RAID_PLAYER_DISPELLABLE' or 'HARMFUL'
	local dispellableAuras = C_UnitAuras.GetUnitAuras(unit, primaryFilter)

	for _, auraData in next, dispellableAuras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local dispelName = auraData.dispelName
			local dispelSafe = (not dispelName) or F.IsValueNonSecret(dispelName)

			if(dispelSafe) then
				local dispelType = dispelName or 'Physical'
				if(DISPEL_PRIORITY[dispelType]) then
					local priority = DISPEL_PRIORITY[dispelType]
					if(priority < bestPriority) then
						bestPriority   = priority
						bestType       = dispelType
						bestIcon       = auraData.icon
						bestSpellId    = spellId
						bestDuration   = auraData.duration
						bestExpiration = auraData.expirationTime
						bestStacks     = auraData.applications or 0
					end
				end
			end
		end
	end

	-- Supplementary query: Physical/bleed debuffs (not returned by RAID_PLAYER_DISPELLABLE)
	-- Only needed when onlyDispellableByMe is true (plain HARMFUL already includes them)
	local showPhysical = element._showPhysicalDebuffs
	if(onlyDispellableByMe and showPhysical ~= false) then
		local raidAuras = C_UnitAuras.GetUnitAuras(unit, 'HARMFUL|RAID')
		for _, auraData in next, raidAuras do
			local spellId = auraData.spellId
			if(F.IsValueNonSecret(spellId)) then
				local dispelName = auraData.dispelName
				local dispelSafe = (not dispelName) or F.IsValueNonSecret(dispelName)

				if(dispelSafe and isPhysicalOrBleed(dispelName)) then
					local priority = DISPEL_PRIORITY.Physical
					if(priority < bestPriority) then
						bestPriority   = priority
						bestType       = 'Physical'
						bestIcon       = auraData.icon
						bestSpellId    = spellId
						bestDuration   = auraData.duration
						bestExpiration = auraData.expirationTime
						bestStacks     = auraData.applications or 0
					end
				end
			end
		end
	end

	if(bestType) then
		-- Show BorderIcon with the debuff's spell icon
		element._borderIcon:SetAura(
			bestSpellId,
			bestIcon,
			bestDuration,
			bestExpiration,
			bestStacks,
			bestType
		)

		-- Show highlight overlay colored by dispel type
		local color = C.Colors.dispel[bestType]
		if(color and element._highlightType) then
			showOverlay(element, element._highlightType, color[1], color[2], color[3])
		end
	else
		element._borderIcon:Clear()
		hideAllOverlays(element)
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
	local element = self.FramedDispellable
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedDispellable
	if(not element) then return end

	element._borderIcon:Clear()
	hideAllOverlays(element)

	self:UnregisterEvent('UNIT_AURA', Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedDispellable', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create a Dispellable element on a unit frame.
--- Shows a BorderIcon with the highest-priority dispellable debuff icon,
--- plus a highlight overlay on the health bar colored by dispel type.
--- Assigns result to self.FramedDispellable, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  { enabled, onlyDispellableByMe, highlightType, iconSize, anchor, frameLevel }
function F.Elements.Dispellable.Setup(self, config)
	config = config or {}
	local iconSize       = config.iconSize       or 20
	local highlightType  = config.highlightType  or C.HighlightType.GRADIENT_FULL
	local frameLevel     = config.frameLevel     or (self:GetFrameLevel() + 6)
	local anchor         = config.anchor

	-- 1. Create BorderIcon (always-on icon showing the highest-priority dispellable debuff)
	local borderIcon = F.Indicators.BorderIcon.Create(self, iconSize, {
		showCooldown = true,
		showStacks   = true,
		showDuration = true,
		frameLevel   = frameLevel,
	})

	-- Apply anchor
	if(anchor) then
		borderIcon:SetPoint(unpack(anchor))
	else
		borderIcon:SetPoint('TOPRIGHT', self, 'TOPRIGHT', -2, -2)
	end

	-- 2. Create overlay textures on the health bar
	-- All overlays use a simple white texture colored at runtime
	local healthBar = self.Health

	-- In the restricted secure header, SetPoint cannot reference a
	-- StatusBar. Use the wrapper Frame (health._wrapper) instead.
	local healthWrapper = healthBar and healthBar._wrapper

	-- Overlay textures for dispellable debuff highlights.
	-- IMPORTANT: NO SetPoint/SetAllPoints calls here — this code runs
	-- inside CallMethod from SecureGroupHeaderTemplate, where ALL
	-- SetPoint calls fail. Positioning is deferred to showOverlay().
	local gradientFull
	if(healthWrapper) then
		local overlayFrame = CreateFrame('Frame', nil, healthWrapper)
		overlayFrame:SetFrameLevel(healthBar:GetFrameLevel() + 2)

		gradientFull = overlayFrame:CreateTexture(nil, 'OVERLAY')
		gradientFull:SetTexture([[Interface\BUTTONS\WHITE8x8]])
		gradientFull:SetBlendMode('ADD')
		gradientFull:Hide()

		-- Store frame ref for deferred positioning
		gradientFull._overlayFrame = overlayFrame
	end

	local gradientHalf
	if(healthWrapper) then
		gradientHalf = gradientFull:GetParent():CreateTexture(nil, 'OVERLAY')
		gradientHalf:SetTexture([[Interface\BUTTONS\WHITE8x8]])
		gradientHalf:SetBlendMode('ADD')
		gradientHalf:Hide()
	end

	local solidCurrent
	if(healthWrapper) then
		solidCurrent = gradientFull:GetParent():CreateTexture(nil, 'OVERLAY')
		solidCurrent:SetTexture([[Interface\BUTTONS\WHITE8x8]])
		solidCurrent:SetWidth(1)
		solidCurrent:SetBlendMode('ADD')
		solidCurrent:Hide()
		healthBar._dispelOverlay = solidCurrent
	end

	-- solid_entire: Solid color covering entire unit frame
	local solidEntire
	solidEntire = self:CreateTexture(nil, 'OVERLAY')
	solidEntire:SetTexture([[Interface\BUTTONS\WHITE8x8]])
	solidEntire:SetBlendMode('ADD')
	solidEntire:Hide()

	-- 3. Build element container
	local container = {
		_borderIcon            = borderIcon,
		_highlightType         = highlightType,
		_onlyDispellableByMe   = config.onlyDispellableByMe or false,
		_showPhysicalDebuffs   = config.showPhysicalDebuffs ~= false,
		_overlayGradientFull   = gradientFull,
		_overlayGradientHalf   = gradientHalf,
		_overlaySolidCurrent   = solidCurrent,
		_overlaySolidEntire    = solidEntire,
	}

	self.FramedDispellable = container
end
