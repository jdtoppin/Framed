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
	F.StyleBuilder.Apply(self, unit, config, 'player')
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Player.Spawn()
	oUF:RegisterStyle('FramedPlayer', Style)
	oUF:SetActiveStyle('FramedPlayer')

	local frame = oUF:Spawn('player', 'FramedPlayerFrame')

	-- Read saved position from config, fall back to default
	local config = F.StyleBuilder.GetConfig('player')
	local pos = config.position
	local x = (pos and pos.x) or 0
	local y = (pos and pos.y) or 0
	F.Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)

	F.Widgets.RegisterForUIScale(frame)

	F.Units.Player.frame = frame
end
