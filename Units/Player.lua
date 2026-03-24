local addonName, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units = F.Units or {}
F.Units.Player = {}

-- ============================================================
-- Style
-- ============================================================

local function Style(self, unit)
	local config = F.StyleBuilder.GetConfig('player')
	F.StyleBuilder.Apply(self, unit, config)
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Player.Spawn()
	oUF:RegisterStyle('FramedPlayer', Style)
	oUF:SetActiveStyle('FramedPlayer')

	local frame = oUF:Spawn('player', 'FramedPlayerFrame')
	frame:SetPoint('CENTER', UIParent, 'CENTER', -200, -200)

	F.Units.Player.frame = frame
end
