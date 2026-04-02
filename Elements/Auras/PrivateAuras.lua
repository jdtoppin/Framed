local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.PrivateAuras = {}

-- ============================================================
-- Feature detection
-- ============================================================

local PRIVATE_AURAS_SUPPORTED =
	C_UnitAuras ~= nil and C_UnitAuras.AddPrivateAuraAnchor ~= nil

local DISPEL_TYPE_SUPPORTED =
	C_UnitAuras ~= nil and C_UnitAuras.TriggerPrivateAuraShowDispelType ~= nil

-- ============================================================
-- Helpers
-- ============================================================

--- Register private aura anchors for each slot in the pool.
--- @param element table  The FramedPrivateAuras element
--- @param unit string    Unit token
local function RegisterAnchors(element, unit)
	local iconSize = element._iconSize
	for idx = 1, #element._pool do
		local slot = element._pool[idx]
		if(slot.anchorID) then
			C_UnitAuras.RemovePrivateAuraAnchor(slot.anchorID)
		end
		slot.anchorID = C_UnitAuras.AddPrivateAuraAnchor({
			unitToken            = unit,
			auraIndex            = idx,
			parent               = slot.frame,
			showCountdownFrame   = true,
			showCountdownNumbers = true,
			iconInfo             = {
				iconWidth  = iconSize,
				iconHeight = iconSize,
				iconAnchor = {
					point         = 'CENTER',
					relativeTo    = slot.frame,
					relativePoint = 'CENTER',
					offsetX       = 0,
					offsetY       = 0,
				},
			},
		})
	end
end

--- Remove all registered private aura anchors.
--- @param element table  The FramedPrivateAuras element
local function RemoveAnchors(element)
	for idx = 1, #element._pool do
		local slot = element._pool[idx]
		if(slot.anchorID) then
			C_UnitAuras.RemovePrivateAuraAnchor(slot.anchorID)
			slot.anchorID = nil
		end
	end
end

--- Position pool frames relative to the unit frame using anchor + orientation.
--- @param element table  The FramedPrivateAuras element
--- @param owner Frame    The oUF unit frame
--- @param config table   Element config
local function LayoutPool(element, owner, config)
	local iconSize    = config.iconSize or 20
	local orientation = config.orientation or 'RIGHT'
	local anchor      = config.anchor or { 'TOP', nil, 'TOP', 0, -3 }
	local anchorPoint = anchor[1]
	local anchorX     = anchor[4] or 0
	local anchorY     = anchor[5] or 0
	local spacing     = 2
	local count       = #element._pool

	-- For centered modes, calculate the offset to center the group
	-- around the anchor point. Total span = count * iconSize + (count - 1) * spacing
	local totalSpan = count * iconSize + (count - 1) * spacing
	local centerShift = totalSpan / 2 - iconSize / 2

	for idx = 1, count do
		local slot = element._pool[idx]
		local f = slot.frame
		f:ClearAllPoints()
		Widgets.SetSize(f, iconSize, iconSize)

		local step = (idx - 1) * (iconSize + spacing)

		if(orientation == 'RIGHT') then
			f:SetPoint(anchorPoint, owner, anchorPoint, anchorX + step, anchorY)
		elseif(orientation == 'LEFT') then
			f:SetPoint(anchorPoint, owner, anchorPoint, anchorX - step, anchorY)
		elseif(orientation == 'DOWN') then
			f:SetPoint(anchorPoint, owner, anchorPoint, anchorX, anchorY - step)
		elseif(orientation == 'UP') then
			f:SetPoint(anchorPoint, owner, anchorPoint, anchorX, anchorY + step)
		elseif(orientation == 'CENTER_HORIZONTAL') then
			f:SetPoint(anchorPoint, owner, anchorPoint, anchorX + step - centerShift, anchorY)
		elseif(orientation == 'CENTER_VERTICAL') then
			f:SetPoint(anchorPoint, owner, anchorPoint, anchorX, anchorY - step + centerShift)
		end

	end
end

-- ============================================================
-- Update
-- ============================================================

-- Private auras are managed at the C level once an anchor is registered.
-- The Update callback is kept minimal — it exists primarily so oUF can call
-- it after UNIT_AURA without causing an error, and so ForceUpdate works.

local function Update(self, event, unit)
	local element = self.FramedPrivateAuras
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	-- No Lua-level state to refresh; Blizzard manages the display.
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
	if(not PRIVATE_AURAS_SUPPORTED) then return end

	local element = self.FramedPrivateAuras
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	RegisterAnchors(element, unit)

	if(DISPEL_TYPE_SUPPORTED and element._showDispelType) then
		C_UnitAuras.TriggerPrivateAuraShowDispelType(true)
	end

	return true
end

local function Disable(self)
	if(not PRIVATE_AURAS_SUPPORTED) then return end

	local element = self.FramedPrivateAuras
	if(not element) then return end

	RemoveAnchors(element)

	if(DISPEL_TYPE_SUPPORTED and element._showDispelType) then
		C_UnitAuras.TriggerPrivateAuraShowDispelType(false)
	end
end

-- ============================================================
-- Rebuild
-- ============================================================

local function Rebuild(element, config)
	RemoveAnchors(element)

	element._iconSize       = config.iconSize or 20
	element._showDispelType = config.showDispelType

	-- Resize pool if maxDisplayed changed
	local maxDisplayed = config.maxDisplayed or 3
	while(#element._pool < maxDisplayed) do
		local f = CreateFrame('Frame', nil, element.__owner)
		element._pool[#element._pool + 1] = { frame = f, anchorID = nil }
	end

	LayoutPool(element, element.__owner, config)

	if(element.__owner:IsVisible() and PRIVATE_AURAS_SUPPORTED) then
		RegisterAnchors(element, element.__owner.unit)
	end

	if(DISPEL_TYPE_SUPPORTED) then
		C_UnitAuras.TriggerPrivateAuraShowDispelType(element._showDispelType and true or false)
	end
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedPrivateAuras', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create a PrivateAuras element on a unit frame.
--- Registers Blizzard private aura anchors so the C-level system renders
--- the unit's private auras at the configured position.
--- Assigns result to self.FramedPrivateAuras, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: iconSize, maxDisplayed, orientation,
---                       anchor, showDispelType, frameLevel
function F.Elements.PrivateAuras.Setup(self, config)
	config = config or {}
	config.iconSize     = config.iconSize or 20
	config.maxDisplayed = config.maxDisplayed or 3
	config.orientation  = config.orientation or 'RIGHT'
	config.anchor       = config.anchor or { 'CENTER', nil, 'CENTER', 0, 0 }

	-- Create a pool of anchor frames, one per auraIndex slot
	local pool = {}
	for idx = 1, config.maxDisplayed do
		local frame = CreateFrame('Frame', nil, self)
		pool[idx] = { frame = frame, anchorID = nil }
	end

	local element = {
		_pool           = pool,
		_iconSize       = config.iconSize,
		_showDispelType = config.showDispelType,
		_anchorID       = nil,
		Rebuild         = Rebuild,
	}

	-- Position all frames
	LayoutPool(element, self, config)

	self.FramedPrivateAuras = element
end
