local addonName, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units = F.Units or {}
F.Units.TargetTarget = {}

-- ============================================================
-- Style
-- ============================================================

local function Style(self, unit)
	local config = F.StyleBuilder.GetConfig('targettarget')
	F.StyleBuilder.Apply(self, unit, config)
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.TargetTarget.Spawn()
	oUF:RegisterStyle('FramedTargetTarget', Style)
	oUF:SetActiveStyle('FramedTargetTarget')

	local frame = oUF:Spawn('targettarget', 'FramedTargetTargetFrame')
	frame:SetPoint('TOPLEFT', FramedTargetFrame, 'BOTTOMLEFT', 0, -4)
	F.Widgets.RegisterForUIScale(frame)

	F.Units.TargetTarget.frame = frame
end
