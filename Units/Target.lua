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
	F.StyleBuilder.Apply(self, unit, config)
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Target.Spawn()
	oUF:RegisterStyle('FramedTarget', Style)
	oUF:SetActiveStyle('FramedTarget')

	local frame = oUF:Spawn('target', 'FramedTargetFrame')
	frame:SetPoint('CENTER', UIParent, 'CENTER', 200, -200)

	F.Units.Target.frame = frame
end
