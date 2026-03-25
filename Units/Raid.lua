local addonName, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units = F.Units or {}
F.Units.Raid = {}

-- ============================================================
-- Style
-- ============================================================

local function Style(self, unit)
	local config = F.StyleBuilder.GetConfig('raid')
	F.StyleBuilder.Apply(self, unit, config)
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Raid.Spawn()
	oUF:RegisterStyle('FramedRaid', Style)
	oUF:SetActiveStyle('FramedRaid')

	local header = oUF:SpawnHeader(
		'FramedRaidHeader',
		nil,
		'showRaid', true,
		'showParty', false,
		'showSolo', false,
		'point', 'LEFT',
		'xOffset', 3,
		'yOffset', -3,
		'maxColumns', 8,
		'unitsPerColumn', 5,
		'columnSpacing', 3,
		'columnAnchorPoint', 'TOP',
		'sortMethod', 'INDEX',
		'groupBy', 'GROUP',
		'groupingOrder', '1,2,3,4,5,6,7,8'
	)

	-- Set visibility separately via the header mixin
	header:SetVisibility('raid')
	header:SetPoint('CENTER', UIParent, 'CENTER', 0, -100)

	F.Units.Raid.header = header
end
