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

-- Private aura anchoring requires C_UnitAuras.AddPrivateAuraAnchor,
-- introduced in a later patch. Elements will gracefully no-op when absent.
local PRIVATE_AURAS_SUPPORTED =
	C_UnitAuras ~= nil and C_UnitAuras.AddPrivateAuraAnchor ~= nil

-- Dispel type display for private auras (TWW 12.0+).
-- This C-level API tells the anchor to show dispel type info visually.
local DISPEL_TYPE_SUPPORTED =
	C_UnitAuras ~= nil and C_UnitAuras.TriggerPrivateAuraShowDispelType ~= nil

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

	-- Register the private aura anchor with Blizzard's system.
	-- The anchor is tied to auraIndex = 1 (the highest-priority private aura).
	local iconSize = element._iconSize
	local anchorID = C_UnitAuras.AddPrivateAuraAnchor({
		unitToken              = unit,
		auraIndex              = 1,
		parent                 = element._frame,
		showCountdownFrame     = true,
		showCountdownNumbers   = true,
		iconInfo               = {
			iconWidth   = iconSize,
			iconHeight  = iconSize,
			iconAnchor  = {
				point         = 'CENTER',
				relativeTo    = element._frame,
				relativePoint = 'CENTER',
				offsetX       = 0,
				offsetY       = 0,
			},
		},
	})
	element._anchorID = anchorID

	if(DISPEL_TYPE_SUPPORTED and element._showDispelType) then
		C_UnitAuras.TriggerPrivateAuraShowDispelType(true)
	end

	return true
end

local function Disable(self)
	if(not PRIVATE_AURAS_SUPPORTED) then return end

	local element = self.FramedPrivateAuras
	if(not element) then return end

	if(element._anchorID) then
		C_UnitAuras.RemovePrivateAuraAnchor(element._anchorID)
		element._anchorID = nil
	end

	if(DISPEL_TYPE_SUPPORTED and element._showDispelType) then
		C_UnitAuras.TriggerPrivateAuraShowDispelType(false)
	end
end

-- ============================================================
-- Rebuild
-- ============================================================

local function Rebuild(element, config)
	if(element._anchorID and PRIVATE_AURAS_SUPPORTED) then
		C_UnitAuras.RemovePrivateAuraAnchor(element._anchorID)
		element._anchorID = nil
	end

	element._iconSize       = config.iconSize or 20
	element._showDispelType = config.showDispelType

	local anchor = config.anchor or { 'TOP', nil, 'TOP', 0, -3 }
	element._frame:ClearAllPoints()
	element._frame:SetPoint(anchor[1], element.__owner, anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0)

	if(element.__owner:IsVisible() and PRIVATE_AURAS_SUPPORTED) then
		element._anchorID = C_UnitAuras.AddPrivateAuraAnchor({
			unitToken            = element.__owner.unit,
			auraIndex            = 1,
			parent               = element._frame,
			showCountdownFrame   = true,
			showCountdownNumbers = true,
			iconInfo             = {
				iconWidth  = element._iconSize,
				iconHeight = element._iconSize,
				iconAnchor = {
					point         = 'CENTER',
					relativeTo    = element._frame,
					relativePoint = 'CENTER',
					offsetX       = 0,
					offsetY       = 0,
				},
			},
		})
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
--- Registers a Blizzard private aura anchor so the C-level system renders
--- the unit's highest-priority private aura at the configured position.
--- Assigns result to self.FramedPrivateAuras, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: iconSize, anchor, showDispelType
function F.Elements.PrivateAuras.Setup(self, config)
	config = config or {}
	config.iconSize = config.iconSize or 20
	config.anchor   = config.anchor   or { 'CENTER', nil, 'CENTER', 0, 0 }

	-- Container frame — serves as the parent / anchor reference point
	-- for Blizzard's private aura display widget.
	local frame = CreateFrame('Frame', nil, self)
	Widgets.SetSize(frame, config.iconSize, config.iconSize)

	local a = config.anchor
	frame:SetPoint(a[1], nil, a[3], a[4] or 0, a[5] or 0)

	local container = {
		_frame          = frame,
		_iconSize       = config.iconSize,
		_showDispelType = config.showDispelType,
		_anchorID       = nil,
		Rebuild         = Rebuild,
	}

	self.FramedPrivateAuras = container
end
