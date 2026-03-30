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
	local x = config.position.x
	local y = config.position.y
	F.Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)

	F.Widgets.RegisterForUIScale(frame)

	F.Units.Target.frame = frame
end
