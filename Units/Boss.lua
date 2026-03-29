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

	local config = F.StyleBuilder.GetConfig('boss')
	local pos = config.position or {}
	local baseX = (pos and pos.x) or 0
	local baseY = (pos and pos.y) or 0
	local spacing = config.spacing or 4

	local frames = {}
	for i = 1, 5 do
		local boss = oUF:Spawn('boss' .. i, 'FramedBossFrame' .. i)
		boss:SetPoint('CENTER', UIParent, 'CENTER', baseX, baseY - (i - 1) * (config.height + spacing))
		F.Widgets.RegisterForUIScale(boss)
		frames[i] = boss
	end

	F.Units.Boss.frames = frames
end
