local addonName, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units = F.Units or {}
F.Units.Party = {}

-- ============================================================
-- Style
-- ============================================================

local function Style(self, unit)
	local config = F.StyleBuilder.GetConfig('party')
	F.StyleBuilder.Apply(self, unit, config)
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Party.Spawn()
	oUF:RegisterStyle('FramedParty', Style)
	oUF:SetActiveStyle('FramedParty')

	local header = oUF:SpawnHeader(
		'FramedPartyHeader',
		nil,
		'party',
		'showParty', true,
		'showPlayer', true,
		'showSolo', false,
		'point', 'TOP',
		'yOffset', -3,
		'maxColumns', 1,
		'unitsPerColumn', 5,
		'sortMethod', 'INDEX'
	)

	header:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', 20, -200)

	F.Units.Party.header = header
end
