local addonName, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units = F.Units or {}
F.Units.Arena = {}

-- ============================================================
-- Style
-- ============================================================

local function Style(self, unit)
	local config = F.StyleBuilder.GetConfig('arena')
	F.StyleBuilder.Apply(self, unit, config, 'arena')

	if(F.Elements.CrowdControl) then
		F.Elements.CrowdControl.Setup(self, { iconSize = 20 })
	end
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Arena.Spawn()
	oUF:RegisterStyle('FramedArena', Style)
	oUF:SetActiveStyle('FramedArena')

	local config = F.StyleBuilder.GetConfig('arena')
	local baseX = config.position.x
	local baseY = config.position.y
	local spacing = config.spacing

	local frames = {}
	for i = 1, 5 do
		local arena = oUF:Spawn('arena' .. i, 'FramedArenaFrame' .. i)
		arena:SetPoint('CENTER', UIParent, 'CENTER', baseX, baseY - (i - 1) * (config.height + spacing))
		F.Widgets.RegisterForUIScale(arena)
		frames[i] = arena
	end

	F.Units.Arena.frames = frames
end
