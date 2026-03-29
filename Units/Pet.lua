local addonName, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units = F.Units or {}
F.Units.Pet = {}

-- ============================================================
-- Style
-- ============================================================

local function Style(self, unit)
	local config = F.StyleBuilder.GetConfig('pet')
	F.StyleBuilder.Apply(self, unit, config, 'pet')
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Pet.Spawn()
	oUF:RegisterStyle('FramedPet', Style)
	oUF:SetActiveStyle('FramedPet')

	local frame = oUF:Spawn('pet', 'FramedPetFrame')

	local config = F.StyleBuilder.GetConfig('pet')
	local pos = config.position or {}
	local x = (pos and pos.x) or 0
	local y = (pos and pos.y) or 0
	F.Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)
	F.Widgets.RegisterForUIScale(frame)

	F.Units.Pet.frame = frame
end
