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
	-- DIAGNOSTIC: trace reload-time 0,0 snap on raid frames.
	-- Remove once root cause is identified.
	do
		local preset = F.AutoSwitch.GetCurrentPreset()
		local pos = config.position
		local uiScale = UIParent and UIParent:GetScale() or -1
		print(('|cff00ccff[Framed diag]|r raid spawn preset=%s pos=%s posX=%s(%s) posY=%s(%s) uiScale=%.3f elvui=%s'):format(
			tostring(preset),
			pos and ('{x=' .. tostring(pos.x) .. ',y=' .. tostring(pos.y) .. ',anchor=' .. tostring(pos.anchor) .. '}') or 'nil',
			tostring(posX), type(posX),
			tostring(posY), type(posY),
			uiScale,
			tostring(C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded('ElvUI'))
		))
		-- Dump raid position from every preset so we can see where the
		-- save actually lives (if anywhere) across the preset chain.
		if(FramedDB and FramedDB.presets) then
			for name, data in next, FramedDB.presets do
				local rc = data and data.unitConfigs and data.unitConfigs.raid
				if(rc) then
					local rp = rc.position
					print(('|cff00ccff[Framed diag]|r   preset %s raid.position=%s'):format(
						name,
						rp and ('{x=' .. tostring(rp.x) .. ',y=' .. tostring(rp.y) .. ',anchor=' .. tostring(rp.anchor) .. '}') or 'nil'))
				else
					print(('|cff00ccff[Framed diag]|r   preset %s raid=nil (no raid config)'):format(name))
				end
			end
		end
	end
	header:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', posX, posY)
	-- DIAGNOSTIC: watch for any post-spawn repositioning for 30s.
	-- Prints only when position changes from the baseline; also hooks
	-- SetPoint to capture the stack of whoever moves it.
	do
		local pt, rel, relPt, x, y = header:GetPoint(1)
		print(('|cff00ccff[Framed diag]|r raid post-SetPoint pt=%s rel=%s relPt=%s x=%s y=%s'):format(
			tostring(pt), tostring(rel and rel:GetName() or rel), tostring(relPt), tostring(x), tostring(y)))
		local lastX, lastY, lastPt = x, y, pt
		hooksecurefunc(header, 'SetPoint', function(_, p, r, rp, nx, ny)
			print(('|cff00ccff[Framed diag]|r raid SetPoint HOOK p=%s r=%s rp=%s x=%s y=%s'):format(
				tostring(p), tostring(r and (type(r) == 'table' and r.GetName and r:GetName()) or r), tostring(rp), tostring(nx), tostring(ny)))
			print(debugstack(2, 8, 0))
		end)
		local ticks = 0
		local ticker
		ticker = C_Timer.NewTicker(0.5, function()
			ticks = ticks + 1
			if(ticks > 60) then ticker:Cancel() return end
			if(not header.GetPoint) then ticker:Cancel() return end
			local p2, r2, rp2, x2, y2 = header:GetPoint(1)
			if(p2 ~= lastPt or x2 ~= lastX or y2 ~= lastY) then
				print(('|cff00ccff[Framed diag]|r raid CHANGED @%.1fs pt=%s x=%s y=%s'):format(
					ticks * 0.5, tostring(p2), tostring(x2), tostring(y2)))
				lastPt, lastX, lastY = p2, x2, y2
			end
		end)
	end
	Widgets.RegisterForUIScale(header)

	F.Units.Raid.header = header

	-- Apply the full sort config (nameList for role mode, groupBy for group mode).
	-- Required so the initial nameList is populated on login — GroupAttrs alone
	-- doesn't know about the roster, so the SpawnHeader call above can't set it.
	F.LiveUpdate.FrameConfigLayout.ApplySortConfig('raid')
end
