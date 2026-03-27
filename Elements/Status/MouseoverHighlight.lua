local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.MouseoverHighlight = {}

-- ============================================================
-- Enable / Disable
-- OnEnter / OnLeave are the sole mechanism — no event polling.
-- Cell uses the same approach: direct Show/Hide, no events.
-- ============================================================

local function Enable(self, unit)
	local element = self.FramedMouseoverHighlight
	if(not element) then return end

	element.__owner = self

	self:HookScript('OnEnter', function(frame)
		local el = frame.FramedMouseoverHighlight
		if(el) then el:Show() end
	end)

	self:HookScript('OnLeave', function(frame)
		local el = frame.FramedMouseoverHighlight
		if(el) then el:Hide() end
	end)

	return true
end

local function Disable(self)
	local element = self.FramedMouseoverHighlight
	if(not element) then return end

	element:Hide()
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedMouseoverHighlight', nil, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Default mouseover highlight color: #f7ecff at 60% opacity
local DEFAULT_COLOR = { 0.969, 0.925, 1, 0.6 }

--- Create the mouseover highlight border frame on a unit frame.
--- The border is a colored overlay drawn around the frame edges (same style
--- as TargetHighlight).
--- Assigns result to self.FramedMouseoverHighlight, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: color, thickness
function F.Elements.MouseoverHighlight.Setup(self, config)
	config = config or {}
	local color     = config.color     or DEFAULT_COLOR
	local thickness = config.thickness or 2

	-- Container frame that sits above most content in the unit frame
	-- Offset outward so the border renders outside the frame edge
	local border = CreateFrame('Frame', nil, self, 'BackdropTemplate')
	border:SetPoint('TOPLEFT', self, 'TOPLEFT', -thickness, thickness)
	border:SetPoint('BOTTOMRIGHT', self, 'BOTTOMRIGHT', thickness, -thickness)
	border:SetFrameLevel(self:GetFrameLevel() + 8)
	border:SetIgnoreParentAlpha(true)

	border:SetBackdrop({
		bgFile   = nil,
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = thickness,
	})
	border:SetBackdropColor(0, 0, 0, 0)
	border:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 0.6)
	border._thickness = thickness
	border:Hide()

	self.FramedMouseoverHighlight = border
end

--- Update the mouseover highlight appearance from current config.
--- Called when CONFIG_CHANGED fires for relevant keys.
--- @param border Frame  The highlight border frame
function F.Elements.MouseoverHighlight.UpdateAppearance(border)
	if(not border) then return end
	local color = DEFAULT_COLOR
	local thickness = 2
	if(F.Config) then
		color = F.Config:Get('general.mouseoverHighlightColor') or DEFAULT_COLOR
		thickness = F.Config:Get('general.mouseoverHighlightWidth') or 2
	end
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
	border:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 0.6)
end
