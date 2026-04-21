local addonName, Framed = ...
local F = Framed
local oUF = F.oUF

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

	-- 12.0.5 tightens UnitIsUnit on compound tokens (e.g. 'party2target')
	-- — can return nil rather than resolving. Without a guard, the
	-- non-secret check below early-returns and leaves the highlight in a
	-- stale state. Hide conservatively instead.
	if(frameUnit ~= 'target' and frameUnit ~= 'pet'
		and (frameUnit:match('target$') or frameUnit:match('pet$'))) then
		element:Hide()
		return
	end

	local isTarget = UnitIsUnit(frameUnit, 'target')
	if(not F.IsValueNonSecret(isTarget)) then
		element:Hide()
		return
	end

	if(isTarget) then
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
--- The border is a 2px colored overlay drawn as four edge textures.
--- Assigns result to self.FramedTargetHighlight, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: color, thickness
function F.Elements.TargetHighlight.Setup(self, config)
	local color     = config.color
	local thickness = config.thickness

	-- Container frame that sits above everything in the unit frame
	-- Offset outward so the border renders outside the frame edge
	local border = CreateFrame('Frame', nil, self, 'BackdropTemplate')
	border:SetPoint('TOPLEFT', self, 'TOPLEFT', -thickness, thickness)
	border:SetPoint('BOTTOMRIGHT', self, 'BOTTOMRIGHT', thickness, -thickness)
	border:SetFrameLevel(self:GetFrameLevel() + 10)
	border:SetIgnoreParentAlpha(true)

	-- Apply a backdrop: transparent background, colored edge
	border:SetBackdrop({
		bgFile   = nil,
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = thickness,
	})
	border:SetBackdropColor(0, 0, 0, 0)
	border:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
	border._thickness = thickness
	border:Hide()

	self.FramedTargetHighlight = border
end

--- Update the target highlight appearance from current config.
--- Called when CONFIG_CHANGED fires for relevant keys.
--- @param border Frame  The highlight border frame
function F.Elements.TargetHighlight.UpdateAppearance(border)
	if(not border) then return end
	local color = F.Config:Get('general.targetHighlightColor')
	local thickness = F.Config:Get('general.targetHighlightWidth')
	-- Re-anchor if thickness changed
	if(thickness ~= border._thickness) then
		local owner = border:GetParent()
		border:ClearAllPoints()
		border:SetPoint('TOPLEFT', owner, 'TOPLEFT', -thickness, thickness)
		border:SetPoint('BOTTOMRIGHT', owner, 'BOTTOMRIGHT', thickness, -thickness)
		border:SetBackdrop({
			bgFile   = nil,
			edgeFile = [[Interface\BUTTONS\WHITE8x8]],
			edgeSize = thickness,
		})
		border:SetBackdropColor(0, 0, 0, 0)
		border._thickness = thickness
	end
	border:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
end
