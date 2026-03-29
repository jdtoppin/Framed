local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local Widgets = F.Widgets

F.Units = F.Units or {}
F.Units.Raid = {}

-- ============================================================
-- Style
-- ============================================================

local function Style(self, unit)
	local config = F.StyleBuilder.GetConfig('raid')
	F.StyleBuilder.Apply(self, unit, config, 'raid')
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Raid.Spawn()
	oUF:RegisterStyle('FramedRaid', Style)
	oUF:SetActiveStyle('FramedRaid')

	-- Read layout from saved config so spawn matches user settings
	local config = F.StyleBuilder.GetConfig('raid')
	local orient  = config.orientation or 'vertical'
	local anchor  = config.anchorPoint or 'TOPLEFT'
	local spacing = config.spacing or 2

	local point, xOff, yOff, colAnchor
	if(orient == 'vertical') then
		local goDown = (anchor == 'TOPLEFT' or anchor == 'TOPRIGHT')
		point     = goDown and 'TOP' or 'BOTTOM'
		yOff      = goDown and -spacing or spacing
		xOff      = 0
		colAnchor = (anchor == 'TOPLEFT' or anchor == 'BOTTOMLEFT') and 'LEFT' or 'RIGHT'
	else
		local goRight = (anchor == 'TOPLEFT' or anchor == 'BOTTOMLEFT')
		point     = goRight and 'LEFT' or 'RIGHT'
		xOff      = goRight and spacing or -spacing
		yOff      = 0
		colAnchor = (anchor == 'TOPLEFT' or anchor == 'TOPRIGHT') and 'TOP' or 'BOTTOM'
	end

	local header = oUF:SpawnHeader(
		'FramedRaidHeader',
		nil,
		'showRaid', true,
		'showParty', false,
		'showSolo', false,
		'point', point,
		'xOffset', xOff,
		'yOffset', yOff,
		'maxColumns', 8,
		'unitsPerColumn', 5,
		'columnSpacing', spacing,
		'columnAnchorPoint', colAnchor,
		'sortMethod', 'INDEX',
		'groupBy', 'GROUP',
		'groupingOrder', '1,2,3,4,5,6,7,8',
		'initial-width', config.width or 72,
		'initial-height', config.height or 36
	)

	-- Set visibility separately via the header mixin
	header:SetVisibility('raid')
	local pos = config.position or {}
	local posX = pos.x or 0
	local posY = pos.y or 0
	header:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', posX, posY)
	Widgets.RegisterForUIScale(header)

	F.Units.Raid.header = header
end
