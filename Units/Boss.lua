local addonName, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units = F.Units or {}
F.Units.Boss = {}

-- ============================================================
-- Style
-- ============================================================

local function Style(self, unit)
	local config = F.StyleBuilder.GetConfig('boss')
	F.StyleBuilder.Apply(self, unit, config, 'boss')
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Boss.Spawn()
	oUF:RegisterStyle('FramedBoss', Style)
	oUF:SetActiveStyle('FramedBoss')

	local frames = {}
	for i = 1, 5 do
		local boss = oUF:Spawn('boss' .. i, 'FramedBossFrame' .. i)
		boss:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -20, -200 - (i - 1) * 50)
		F.Widgets.RegisterForUIScale(boss)
		frames[i] = boss
	end

	F.Units.Boss.frames = frames
end
