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
	local orient  = config.orientation
	local anchor  = config.anchorPoint
	local spacing = config.spacing

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

	local attrs = F.LiveUpdate.FrameConfigLayout.GroupAttrs(config, 'raid')

	local header = oUF:SpawnHeader(
		'FramedRaidHeader',
		nil,
		'showRaid', true,
		'showParty', false,
		'showSolo', false,
		'point', point,
		'xOffset', xOff,
		'yOffset', yOff,
		'columnSpacing', spacing,
		'columnAnchorPoint', colAnchor,
		'maxColumns', attrs.maxColumns,
		'unitsPerColumn', attrs.unitsPerColumn,
		'sortMethod', attrs.sortMethod,
		'groupBy', attrs.groupBy,
		'groupingOrder', attrs.groupingOrder,
		'initial-width', config.width,
		'initial-height', config.height
	)

	-- Set visibility separately via the header mixin
	header:SetVisibility('raid')
	local posX = config.position.x
	local posY = config.position.y
	header:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', posX, posY)
	Widgets.RegisterForUIScale(header)

	F.Units.Raid.header = header

	-- Apply the full sort config (nameList for role mode, groupBy for group mode).
	-- Required so the initial nameList is populated on login — GroupAttrs alone
	-- doesn't know about the roster, so the SpawnHeader call above can't set it.
	F.LiveUpdate.FrameConfigLayout.ApplySortConfig('raid')
end
