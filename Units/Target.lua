local addonName, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units = F.Units or {}
F.Units.Target = {}

-- ============================================================
-- Style
-- ============================================================

local function Style(self, unit)
	local config = F.StyleBuilder.GetConfig('target')
	F.StyleBuilder.Apply(self, unit, config, 'target')
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Target.Spawn()
	oUF:RegisterStyle('FramedTarget', Style)
	oUF:SetActiveStyle('FramedTarget')

	local frame = oUF:Spawn('target', 'FramedTargetFrame')

	local config = F.StyleBuilder.GetConfig('target')
	local pos = config.position
	local x = (pos and pos.x) or 0
	local y = (pos and pos.y) or 0
	F.Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)

	F.Widgets.RegisterForUIScale(frame)

	F.Units.Target.frame = frame
end
