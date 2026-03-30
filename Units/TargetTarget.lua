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
	local x = config.position.x
	local y = config.position.y
	F.Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)
	F.Widgets.RegisterForUIScale(frame)

	F.Units.TargetTarget.frame = frame
end
