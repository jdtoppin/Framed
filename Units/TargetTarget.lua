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
	F.StyleBuilder.Apply(self, unit, config, 'targettarget')
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.TargetTarget.Spawn()
	oUF:RegisterStyle('FramedTargetTarget', Style)
	oUF:SetActiveStyle('FramedTargetTarget')

	local frame = oUF:Spawn('targettarget', 'FramedTargetTargetFrame')

	local config = F.StyleBuilder.GetConfig('targettarget')
	local pos = config.position or {}
	local x = (pos and pos.x) or 0
	local y = (pos and pos.y) or 0
	F.Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)
	F.Widgets.RegisterForUIScale(frame)

	F.Units.TargetTarget.frame = frame
end
