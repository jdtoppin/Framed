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

local function showOverlay(element, highlightType, r, g, b)
	hideAllOverlays(element)

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

	-- Filter is 'HARMFUL' so all results are harmful — do not read auraData.isHarmful
	local i = 1
	while(true) do
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if(not auraData) then break end

		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local dispelName = auraData.dispelName
			local dispelSafe = (not dispelName) or F.IsValueNonSecret(dispelName)

			if(dispelSafe) then
				local isPhysical = isPhysicalOrBleed(dispelName)
				local dispelType = isPhysical and 'Physical' or dispelName

				-- Apply "only dispellable by me" filter
				-- Physical/bleeds always pass (for healer awareness)
				local passFilter = true
				if(onlyDispellableByMe and not isPhysical) then
					passFilter = F.CanPlayerDispel(dispelType)
				end

				if(passFilter and DISPEL_PRIORITY[dispelType]) then
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

		i = i + 1
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

	-- gradient_full: Full-height gradient over the health bar
	local gradientFull
	if(healthBar) then
		gradientFull = healthBar:CreateTexture(nil, 'OVERLAY')
		gradientFull:SetTexture([[Interface\BUTTONS\WHITE8x8]])
		gradientFull:SetAllPoints(healthBar)
		gradientFull:SetBlendMode('ADD')
		gradientFull:Hide()
	end

	-- gradient_half: Same gradient but only covers top half of health bar
	local gradientHalf
	if(healthBar) then
		gradientHalf = healthBar:CreateTexture(nil, 'OVERLAY')
		gradientHalf:SetTexture([[Interface\BUTTONS\WHITE8x8]])
		gradientHalf:SetPoint('TOPLEFT', healthBar, 'TOPLEFT', 0, 0)
		gradientHalf:SetPoint('TOPRIGHT', healthBar, 'TOPRIGHT', 0, 0)
		gradientHalf:SetHeight(healthBar:GetHeight() * 0.5)
		gradientHalf:SetBlendMode('ADD')
		gradientHalf:Hide()
	end

	-- solid_current: Solid color that follows health bar fill width
	local solidCurrent
	if(healthBar) then
		local statusBarTexture = healthBar:GetStatusBarTexture()
		solidCurrent = healthBar:CreateTexture(nil, 'OVERLAY')
		solidCurrent:SetTexture([[Interface\BUTTONS\WHITE8x8]])
		solidCurrent:SetAllPoints(statusBarTexture)
		solidCurrent:SetBlendMode('ADD')
		solidCurrent:Hide()
	end

	-- solid_entire: Solid color covering entire unit frame
	local solidEntire
	solidEntire = self:CreateTexture(nil, 'OVERLAY')
	solidEntire:SetTexture([[Interface\BUTTONS\WHITE8x8]])
	solidEntire:SetAllPoints(self)
	solidEntire:SetBlendMode('ADD')
	solidEntire:Hide()

	-- 3. Build element container
	local container = {
		_borderIcon          = borderIcon,
		_highlightType       = highlightType,
		_onlyDispellableByMe = config.onlyDispellableByMe or false,
		_overlayGradientFull = gradientFull,
		_overlayGradientHalf = gradientHalf,
		_overlaySolidCurrent = solidCurrent,
		_overlaySolidEntire  = solidEntire,
	}

	self.FramedDispellable = container
end
