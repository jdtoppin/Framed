local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.TargetHighlight = {}

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedTargetHighlight
	if(not element) then return end

	-- PLAYER_TARGET_CHANGED is a unitless event; always re-check against
	-- this frame's unit.
	local frameUnit = self.unit
	if(not frameUnit) then return end

	if(UnitIsUnit(frameUnit, 'target')) then
		element:Show()
	else
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
	local element = self.FramedTargetHighlight
	if(not element) then return end

	element.__owner   = self
	element.ForceUpdate = ForceUpdate

	-- PLAYER_TARGET_CHANGED is unitless (true)
	self:RegisterEvent('PLAYER_TARGET_CHANGED', Update, true)

	return true
end

local function Disable(self)
	local element = self.FramedTargetHighlight
	if(not element) then return end

	element:Hide()
	self:UnregisterEvent('PLAYER_TARGET_CHANGED', Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedTargetHighlight', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create the target highlight border frame on a unit frame.
--- The border is a 2px accent-colored overlay drawn as four edge textures.
--- Assigns result to self.FramedTargetHighlight, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: color, thickness
function F.Elements.TargetHighlight.Setup(self, config)
	config = config or {}
	local color     = config.color     or C.Colors.accent
	local thickness = config.thickness or 2

	-- Container frame that sits above everything in the unit frame
	local border = CreateFrame('Frame', nil, self, 'BackdropTemplate')
	border:SetAllPoints(self)
	border:SetFrameLevel(self:GetFrameLevel() + 10)

	-- Apply a backdrop: transparent background, accent-colored 2px edge
	border:SetBackdrop({
		bgFile   = nil,
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = thickness,
	})
	border:SetBackdropColor(0, 0, 0, 0)
	border:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
	border:Hide()

	self.FramedTargetHighlight = border
end
