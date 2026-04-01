local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

-- ============================================================
-- FrameConfig — live-update handlers for unitConfigs.*
-- Listens on CONFIG_CHANGED, parses unitConfigs.<unitType>.<key>,
-- iterates matching frames via F.StyleBuilder.ForEachFrame().
-- ============================================================

local ForEachFrame = F.StyleBuilder.ForEachFrame

-- ============================================================
-- Combat queue for group layout (SetAttribute locked in combat)
-- ============================================================

local pendingGroupChanges = {}
local combatQueueStatus

local function applyOrQueue(header, attr, value)
	if(InCombatLockdown()) then
		pendingGroupChanges[#pendingGroupChanges + 1] = { header, attr, value }
		if(combatQueueStatus) then
			combatQueueStatus:SetText('Changes queued — will apply after combat')
			combatQueueStatus:Show()
		end
	else
		header:SetAttribute(attr, value)
	end
end

F.EventBus:Register('PLAYER_REGEN_ENABLED', function()
	for _, change in next, pendingGroupChanges do
		change[1]:SetAttribute(change[2], change[3])
	end
	wipe(pendingGroupChanges)
	if(combatQueueStatus) then
		combatQueueStatus:Hide()
	end
end, 'LiveUpdate.CombatQueue')

-- ============================================================
-- Debounce (Tier 1: 0.05s for non-structural changes)
-- ============================================================

local pendingUpdates = {}

local function debouncedApply(key, applyFn, ...)
	if(pendingUpdates[key]) then
		pendingUpdates[key]:Cancel()
	end
	local args = { ... }
	pendingUpdates[key] = C_Timer.NewTimer(0.05, function()
		pendingUpdates[key] = nil
		applyFn(unpack(args))
	end)
end

-- ============================================================
-- Status icon element map
-- ============================================================

local STATUS_ELEMENT_MAP = {
	role       = 'GroupRoleIndicator',
	leader     = 'LeaderIndicator',
	readyCheck = 'ReadyCheckIndicator',
	raidIcon   = 'RaidTargetIndicator',
	combat     = 'CombatIndicator',
	resting    = 'RestingIndicator',
	phase      = 'PhaseIndicator',
	resurrect  = 'ResurrectIndicator',
	summon     = 'SummonIndicator',
	raidRole   = 'RaidRoleIndicator',
	pvp        = 'PvPIndicator',
}

-- ============================================================
-- Path parser
-- ============================================================

local function parseUnitConfigPath(path)
	-- Extract preset name and unit config from 'presets.<name>.unitConfigs.<unitType>.<key>'
	local presetName, unitType, rest = path:match('presets%.([^%.]+)%.unitConfigs%.([^%.]+)%.(.+)$')
	if(not unitType) then
		-- Fallback: 'unitConfigs.<unitType>.<key>' (no preset prefix)
		unitType, rest = path:match('unitConfigs%.([^%.]+)%.(.+)$')
	end
	return unitType, rest, presetName
end

-- ============================================================
-- Position helper
-- Repositions a solo frame using its config anchor point + x/y.
-- Group frames (party/raid) are managed by SecureGroupHeader and
-- cannot be repositioned individually.
-- ============================================================

local GROUP_TYPES = {
	party        = true,
	raid         = true,
	battleground = true,
	worldraid    = true,
}

--- Look up the SecureGroupHeader for a group unitType.
--- @param unitType string  'party', 'raid', etc.
--- @return Frame|nil header
local function getGroupHeader(unitType)
	if(unitType == 'party') then
		return F.Units.Party and F.Units.Party.header
	elseif(unitType == 'raid') then
		return F.Units.Raid and F.Units.Raid.header
	end
	return nil
end

--- Apply group layout attributes (point, yOffset, xOffset, columnAnchorPoint)
--- to a header based on orientation, anchorPoint, and spacing from config.
---
--- orientation = 'vertical'   → frames stack top-to-bottom or bottom-to-top
--- orientation = 'horizontal' → frames go side-by-side left-to-right or right-to-left
--- anchorPoint = corner the group grows FROM (TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT)
---
--- IMPORTANT: Offsets are set BEFORE point to avoid cascading intermediate
--- layouts — each SetAttribute triggers a header relayout, so if point
--- changes while the old offsets are still active, frames briefly appear
--- in a diagonal/cascading arrangement.
---
--- @param header Frame  SecureGroupHeader
--- @param config table  Unit config table
local function applyGroupLayoutToHeader(header, config)
	local orient  = config.orientation
	local anchor  = config.anchorPoint
	local spacing = config.spacing

	-- Compute all four attributes before applying any
	local point, yOff, xOff, colAnchor

	if(orient == 'vertical') then
		local goDown = (anchor == 'TOPLEFT' or anchor == 'TOPRIGHT')
		point  = goDown and 'TOP' or 'BOTTOM'
		yOff   = goDown and -spacing or spacing
		xOff   = 0
		colAnchor = (anchor == 'TOPLEFT' or anchor == 'BOTTOMLEFT') and 'LEFT' or 'RIGHT'
	else
		local goRight = (anchor == 'TOPLEFT' or anchor == 'BOTTOMLEFT')
		point  = goRight and 'LEFT' or 'RIGHT'
		xOff   = goRight and spacing or -spacing
		yOff   = 0
		colAnchor = (anchor == 'TOPLEFT' or anchor == 'TOPRIGHT') and 'TOP' or 'BOTTOM'
	end

	-- Apply offsets first so the relayout triggered by 'point' already
	-- sees the correct spacing values (avoids cascading visual glitch)
	applyOrQueue(header, 'xOffset', xOff)
	applyOrQueue(header, 'yOffset', yOff)
	applyOrQueue(header, 'point', point)
	applyOrQueue(header, 'columnAnchorPoint', colAnchor)

	-- Force SecureGroupHeader to fully re-layout children.
	-- Setting attributes above should trigger SecureGroupHeader_Update,
	-- but in practice the header sometimes doesn't re-anchor existing
	-- children until a filter toggle forces a complete pass.
	if(not InCombatLockdown()) then
		local name = header:GetName()
		if(name and name:find('Party')) then
			header:SetAttribute('showParty', false)
			header:SetAttribute('showParty', true)
		elseif(name and name:find('Raid')) then
			header:SetAttribute('showRaid', false)
			header:SetAttribute('showRaid', true)
		end
	end
end

--- Reposition a solo frame using CENTER anchor + config offsets.
--- position.x/y are always relative to UIParent CENTER.
local function repositionFrame(frame, config)
	local pos = config.position
	local x = pos.x
	local y = pos.y
	frame:ClearAllPoints()
	Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)
end

--- Compute center offset shift when the frame resizes, keeping the
--- configured anchor corner/edge fixed in place.
--- @param anchor string  Resize anchor preference (e.g. 'TOPLEFT')
--- @param dw number  Width change (new - old)
--- @param dh number  Height change (new - old)
--- @return number dx, number dy  Shift to apply to center x/y
local function resizeShift(anchor, dw, dh)
	-- Each anchor determines which corner stays fixed.
	-- We return the delta to the CENTER offset that compensates.
	local dx, dy = 0, 0
	if(anchor == 'TOPLEFT') then       dx, dy =  dw / 2, -dh / 2
	elseif(anchor == 'TOP') then       dx, dy =  0,      -dh / 2
	elseif(anchor == 'TOPRIGHT') then  dx, dy = -dw / 2, -dh / 2
	elseif(anchor == 'LEFT') then      dx, dy =  dw / 2,  0
	elseif(anchor == 'CENTER') then    dx, dy =  0,        0
	elseif(anchor == 'RIGHT') then     dx, dy = -dw / 2,  0
	elseif(anchor == 'BOTTOMLEFT') then  dx, dy =  dw / 2, dh / 2
	elseif(anchor == 'BOTTOM') then      dx, dy =  0,      dh / 2
	elseif(anchor == 'BOTTOMRIGHT') then dx, dy = -dw / 2, dh / 2
	end
	return dx, dy
end

--- Parse an anchor string into x/y fractions (0=left/top, 0.5=center, 1=right/bottom).
--- @param pt string  Anchor point (e.g. 'TOPLEFT', 'CENTER')
--- @return number fx, number fy
local function anchorFractions(pt)
	local fx, fy = 0.5, 0.5
	if(pt:find('LEFT'))   then fx = 0 end
	if(pt:find('RIGHT'))  then fx = 1 end
	if(pt:find('TOP'))    then fy = 0 end
	if(pt:find('BOTTOM')) then fy = 1 end
	return fx, fy
end

--- Compute shift to a header's SetPoint offsets when its content resizes,
--- keeping the resize-anchor corner fixed.  Works for any header anchor point.
--- @param headerAnchor string  The header's own anchor point (e.g. 'TOPLEFT')
--- @param resizeAnchor string  The user's resize preference (e.g. 'TOPRIGHT')
--- @param dw number  Width change (new - old)
--- @param dh number  Height change (new - old)
--- @return number dx, number dy  Shift to apply to header offsets
local function groupResizeShift(headerAnchor, resizeAnchor, dw, dh)
	local hx, hy = anchorFractions(headerAnchor)
	local rx, ry = anchorFractions(resizeAnchor)
	-- Positive dw means wider; if resize anchor is further right than header
	-- anchor, the header must shift left (negative dx).
	-- Positive dh means taller; if resize anchor is further down than header
	-- anchor, the header must shift up (positive dy in WoW coords).
	local dx = -(rx - hx) * dw
	local dy =  (ry - hy) * dh
	return dx, dy
end

-- ============================================================
-- Main CONFIG_CHANGED handler
-- ============================================================

local suppressPositionUpdate = false

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local unitType, key, presetName = parseUnitConfigPath(path)
	if(not unitType) then return end

	-- Only apply live updates when the changed preset is the active one
	if(presetName and presetName ~= F.AutoSwitch.GetCurrentPreset()) then return end

	-- Frame anchor change — resize preference only, no frame movement
	if(key == 'position.anchor') then
		return
	end

	-- Frame position (x, y)
	if(key == 'position.x' or key == 'position.y') then
		if(suppressPositionUpdate) then return end
		local config = F.StyleBuilder.GetConfig(unitType)
		if(GROUP_TYPES[unitType]) then
			-- Group frames: reposition the header
			local header = getGroupHeader(unitType)
			if(header) then
				local pos = config.position
				local x = pos.x
				local y = pos.y
				header:ClearAllPoints()
				Widgets.SetPoint(header, 'TOPLEFT', UIParent, 'TOPLEFT', x, y)
			end
		else
			ForEachFrame(unitType, function(frame)
				repositionFrame(frame, config)
			end)
		end
		return
	end

	-- Dimensions — resize frame, health wrapper, power wrapper
	if(key == 'width' or key == 'height') then
		local config = F.StyleBuilder.GetConfig(unitType)
		debouncedApply('dimensions.' .. unitType, function()
			local powerHeight = config.power.height
			local healthHeight = config.height - powerHeight

			if(GROUP_TYPES[unitType]) then
				-- Group frames: resize each child, header manages positioning
				local header = getGroupHeader(unitType)

				-- Capture old dimensions and count visible frames BEFORE
				-- resizing (GetWidth returns the current rendered size)
				local oldW, oldH, numFrames = nil, nil, 0
				ForEachFrame(unitType, function(frame)
					if(not oldW) then
						oldW = frame:GetWidth() or config.width
						oldH = frame:GetHeight() or config.height
					end
					numFrames = numFrames + 1
				end)

				ForEachFrame(unitType, function(frame)
					Widgets.SetSize(frame, config.width, config.height)
					if(frame.Health and frame.Health._wrapper) then
						Widgets.SetSize(frame.Health._wrapper, config.width, healthHeight)
					end
					if(frame.Power and frame.Power._wrapper) then
						Widgets.SetSize(frame.Power._wrapper, config.width, powerHeight)
						local pos = config.power.position
						frame.Power._wrapper:ClearAllPoints()
						frame.Health._wrapper:ClearAllPoints()
						if(pos == 'top') then
							frame.Power._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
							frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -powerHeight)
						else
							frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
							frame.Power._wrapper:SetPoint('TOPLEFT', frame.Health._wrapper, 'BOTTOMLEFT', 0, 0)
						end
						if(frame.Power.SetSharedEdge) then
							frame.Power:SetSharedEdge(pos)
						end
					end
					-- Sync cast bar width in attached mode
					local cbCfg = config.castbar
					if(cbCfg and frame.Castbar and frame.Castbar._wrapper and cbCfg.sizeMode ~= 'detached') then
						Widgets.SetSize(frame.Castbar._wrapper, config.width, cbCfg.height)
					end
				end)
				-- Shift header position to keep resize anchor corner fixed.
				-- For the stacking axis, the total group size change is
				-- numFrames * per-frame delta (all children grew).
				if(header and oldW) then
					local anchor = config.position.anchor
					local orient = config.orientation
					local dw = config.width  - oldW
					local dh = config.height - oldH
					if(orient == 'vertical') then
						dh = dh * numFrames
					else
						dw = dw * numFrames
					end
					if(dw ~= 0 or dh ~= 0) then
						local hPt, hRel, hRelPt, hX, hY = header:GetPoint(1)
						if(hPt) then
							local dx, dy = groupResizeShift(hPt, anchor, dw, dh)
							header:ClearAllPoints()
							Widgets.SetPoint(header, hPt, hRel, hRelPt, hX + dx, hY + dy)
						end
					end
					applyOrQueue(header, 'initial-width', config.width)
					applyOrQueue(header, 'initial-height', config.height)
				end

				-- Resize party pet frames to match new owner size
				if(unitType == 'party' and F.Units.Party.petFrames) then
					ForEachFrame('partypet', function(frame)
						Widgets.SetSize(frame, config.width, config.height)
						if(frame.Health and frame.Health._wrapper) then
							Widgets.SetSize(frame.Health._wrapper, config.width, config.height)
						end
					end)
				end
			else
				-- Solo frames: resize + shift position to keep anchor fixed
				local anchor = config.position.anchor
				ForEachFrame(unitType, function(frame)
					local oldW = frame._width or frame:GetWidth() or config.width
					local oldH = frame._height or frame:GetHeight() or config.height
					local dw = config.width - oldW
					local dh = config.height - oldH
					if(dw ~= 0 or dh ~= 0) then
						local dx, dy = resizeShift(anchor, dw, dh)
						local pos = config.position
						local curX = pos.x
						local curY = pos.y
						suppressPositionUpdate = true
						local presetName = F.AutoSwitch.GetCurrentPreset()
						local basePath = 'presets.' .. presetName .. '.unitConfigs.' .. unitType .. '.position.'
						F.Config:Set(basePath .. 'x', Widgets.Round(curX + dx))
						F.Config:Set(basePath .. 'y', Widgets.Round(curY + dy))
						suppressPositionUpdate = false
					end
					repositionFrame(frame, F.StyleBuilder.GetConfig(unitType))
					Widgets.SetSize(frame, config.width, config.height)
					if(frame.Health and frame.Health._wrapper) then
						Widgets.SetSize(frame.Health._wrapper, config.width, healthHeight)
					end
					if(frame.Power and frame.Power._wrapper) then
						Widgets.SetSize(frame.Power._wrapper, config.width, powerHeight)
						local pos = config.power.position
						frame.Power._wrapper:ClearAllPoints()
						frame.Health._wrapper:ClearAllPoints()
						if(pos == 'top') then
							frame.Power._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
							frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -powerHeight)
						else
							frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
							frame.Power._wrapper:SetPoint('TOPLEFT', frame.Health._wrapper, 'BOTTOMLEFT', 0, 0)
						end
						if(frame.Power.SetSharedEdge) then
							frame.Power:SetSharedEdge(pos)
						end
					end
					-- Sync cast bar width in attached mode
					local cbCfg = config.castbar
					if(cbCfg and frame.Castbar and frame.Castbar._wrapper and cbCfg.sizeMode ~= 'detached') then
						Widgets.SetSize(frame.Castbar._wrapper, config.width, cbCfg.height)
					end
				end)
			end
		end)
		return
	end

	-- Group layout: spacing, orientation, anchorPoint
	if(key == 'spacing' or key == 'orientation' or key == 'anchorPoint') then
		if(not GROUP_TYPES[unitType]) then return end
		local header = getGroupHeader(unitType)
		if(not header) then return end
		local config = F.StyleBuilder.GetConfig(unitType)
		applyGroupLayoutToHeader(header, config)

		-- Re-anchor pet frames when party layout changes
		if(unitType == 'party' and F.Units.Party.petFrames) then
			F.Units.Party.AnchorPetFrames()
		end
		return
	end

	-- Power bar
	if(key == 'showPower') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(config.showPower) then
				frame:EnableElement('Power')
				frame.Power:Show()
			else
				frame:DisableElement('Power')
				frame.Power:Hide()
			end
		end)
		return
	end

	-- Power bar height or position
	if(key == 'power.height' or key == 'power.position') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local powerHeight = config.power.height
		local pos = config.power.position
		ForEachFrame(unitType, function(frame)
			local healthH = frame.Health and frame.Health._wrapper and frame.Health._wrapper:GetHeight() or config.height
			Widgets.SetSize(frame, config.width, healthH + powerHeight)
			if(frame.Power and frame.Power._wrapper) then
				Widgets.SetSize(frame.Power._wrapper, config.width, powerHeight)
				frame.Power._wrapper:ClearAllPoints()
				frame.Health._wrapper:ClearAllPoints()
				if(pos == 'top') then
					frame.Power._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
					frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -powerHeight)
				else
					frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
					frame.Power._wrapper:SetPoint('TOPLEFT', frame.Health._wrapper, 'BOTTOMLEFT', 0, 0)
				end
				-- Update which border edge is removed for the shared edge
				if(frame.Power.SetSharedEdge) then
					frame.Power:SetSharedEdge(pos)
				end
			end
		end)
		return
	end

	-- Portrait toggle / type change
	if(key == 'portrait') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local pCfg = config.portrait
		ForEachFrame(unitType, function(frame)
			if(pCfg) then
				local wantType = (type(pCfg) == 'table' and pCfg.type) or '2D'
				local curType = frame._portraitType

				-- Recreate if type changed or not yet created
				if(not frame.Portrait or curType ~= wantType) then
					-- Disconnect oUF from the old element before swapping
					if(frame.Portrait) then
						frame:DisableElement('Portrait')
						frame.Portrait:Hide()
						frame.Portrait = nil
					end
					F.Elements.Portrait.Setup(frame, config.height, config.height, pCfg == true and {} or pCfg)
					frame.Portrait:ClearAllPoints()
					Widgets.SetPoint(frame.Portrait, 'TOPRIGHT', frame, 'TOPLEFT', -(C.Spacing.base), 0)
					frame._portraitType = wantType
					-- Re-enable so oUF sets __owner, ForceUpdate, and registers events
					frame:EnableElement('Portrait')
				end
				frame.Portrait:Show()
				if(frame.Portrait.ForceUpdate) then frame.Portrait:ForceUpdate() end
			else
				if(frame.Portrait) then
					frame:DisableElement('Portrait')
					frame.Portrait:Hide()
				end
			end
		end)
		return
	end

	-- Cast bar
	if(key == 'showCastBar') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(config.showCastBar) then
				frame:EnableElement('Castbar')
			else
				frame:DisableElement('Castbar')
			end
		end)
		return
	end

	-- Cast bar size mode, width, height
	if(key == 'castbar.sizeMode' or key == 'castbar.width' or key == 'castbar.height') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local cbCfg = config.castbar
		if(not cbCfg) then return end
		local cbWidth = (cbCfg.sizeMode == 'detached' and cbCfg.width) or config.width
		ForEachFrame(unitType, function(frame)
			local cb = frame.Castbar
			if(not cb or not cb._wrapper) then return end
			Widgets.SetSize(cb._wrapper, cbWidth, cbCfg.height)
		end)
		return
	end

	-- Cast bar background mode (always / oncast)
	if(key == 'castbar.backgroundMode') then
		local config = F.StyleBuilder.GetConfig(unitType)
		if(not config.castbar) then return end
		local mode = config.castbar.backgroundMode
		ForEachFrame(unitType, function(frame)
			local cb = frame.Castbar
			if(not cb) then return end
			cb._backgroundMode = mode
			if(mode == 'always') then
				if(cb._bg) then cb._bg:Show() end
				local bgC = C.Colors.background
				cb._wrapper:SetBackdropColor(bgC[1], bgC[2], bgC[3], bgC[4])
			else
				if(cb._bg) then cb._bg:Hide() end
				cb._wrapper:SetBackdropColor(0, 0, 0, 0)
			end
		end)
		return
	end

	-- Health bar color mode
	if(key == 'health.colorMode') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local mode = config.health.colorMode
		ForEachFrame(unitType, function(frame)
			local h = frame.Health
			if(not h) then return end

			-- Clear all color flags
			h.colorClass    = nil
			h.colorReaction = nil
			h.colorSmooth   = nil
			h.UpdateColor   = nil

			-- Update stored mode and custom color for PostUpdate
			h._colorMode   = mode
			h._customColor = config.health.customColor

			-- Set flags for new mode
			if(mode == 'class') then
				h.colorClass    = true
				h.colorReaction = true
				-- NPC frames need secret-safe UpdateColor for UnitThreatSituation
				if(h._isNpcFrame) then
					h.UpdateColor = F.Elements.Health.NpcUpdateColor
				end
			elseif(mode == 'gradient') then
				h.colorSmooth = true
				-- NPC frames need secret-safe UpdateColor for UnitThreatSituation
				if(h._isNpcFrame) then
					h.UpdateColor = F.Elements.Health.NpcUpdateColor
				end
				-- Ensure per-frame colors table exists
				if(not rawget(frame, 'colors')) then
					frame.colors = setmetatable({}, { __index = oUF.colors })
				end
				local hc = config.health
				frame.colors.health = oUF:CreateColor(0.2, 0.8, 0.2)
				frame.colors.health:SetCurve({
					[hc.gradientThreshold3 / 100]  = CreateColor(unpack(hc.gradientColor3)),
					[hc.gradientThreshold2 / 100] = CreateColor(unpack(hc.gradientColor2)),
					[hc.gradientThreshold1 / 100] = CreateColor(unpack(hc.gradientColor1)),
				})
			elseif(mode == 'dark') then
				-- Override UpdateColor to directly set dark gray
				h.UpdateColor = function(self)
					self.Health:SetStatusBarColor(0.25, 0.25, 0.25)
				end
			elseif(mode == 'custom') then
				-- Override UpdateColor to directly set the custom color
				h.UpdateColor = function(self)
					local cc = self.Health._customColor
					self.Health:SetStatusBarColor(cc[1], cc[2], cc[3])
				end
			end

			h:ForceUpdate()
		end)
		return
	end

	-- Health custom color (live picker change)
	if(key == 'health.customColor') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local color = config.health.customColor
		ForEachFrame(unitType, function(frame)
			if(frame.Health) then
				frame.Health._customColor = color
				-- Apply immediately if in custom mode
				if(frame.Health._colorMode == 'custom') then
					frame.Health:SetStatusBarColor(color[1], color[2], color[3])
				end
			end
		end)
		return
	end

	-- Health loss color mode
	if(key == 'health.lossColorMode') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local hc = config.health
		local mode = hc.lossColorMode
		ForEachFrame(unitType, function(frame)
			local h = frame.Health
			if(not h or not h._bg) then return end
			h._lossColorMode = mode
			-- Build gradient curve if switching to gradient mode
			if(mode == 'gradient') then
				local curve = C_CurveUtil.CreateColorCurve()
				local t1 = hc.lossGradientThreshold1 / 100
				local t2 = hc.lossGradientThreshold2 / 100
				local t3 = hc.lossGradientThreshold3 / 100
				local c1 = hc.lossGradientColor1
				local c2 = hc.lossGradientColor2
				local c3 = hc.lossGradientColor3
				curve:AddPoint(t3, CreateColor(c3[1], c3[2], c3[3]))
				curve:AddPoint(t2, CreateColor(c2[1], c2[2], c2[3]))
				curve:AddPoint(t1, CreateColor(c1[1], c1[2], c1[3]))
				h._lossGradientCurve = curve
			else
				h._lossGradientCurve = nil
			end
			-- Apply directly, then ForceUpdate to let PostUpdate maintain it
			if(mode == 'dark') then
				h._bg:SetVertexColor(0.15, 0.15, 0.15, 1)
			elseif(mode == 'custom') then
				local lc = h._lossCustomColor
				h._bg:SetVertexColor(lc[1], lc[2], lc[3], 1)
			elseif(mode == 'class') then
				local _, class = UnitClass(frame.unit or 'player')
				if(class) then
					local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
					if(cc) then
						h._bg:SetVertexColor(cc.r * 0.3, cc.g * 0.3, cc.b * 0.3, 1)
					end
				end
			end
			h:ForceUpdate()
		end)
		return
	end

	-- Health loss custom color
	if(key == 'health.lossCustomColor') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local color = config.health.lossCustomColor
		ForEachFrame(unitType, function(frame)
			local h = frame.Health
			if(not h) then return end
			h._lossCustomColor = color
			if(h._lossColorMode == 'custom' and h._bg) then
				h._bg:SetVertexColor(color[1], color[2], color[3], 1)
			end
		end)
		return
	end

	-- Health loss gradient colors/thresholds
	if(key:match('^health%.lossGradient')) then
		local config = F.StyleBuilder.GetConfig(unitType)
		local hc = config.health
		ForEachFrame(unitType, function(frame)
			local h = frame.Health
			if(not h) then return end
			-- Rebuild the curve with updated colors/thresholds
			local curve = C_CurveUtil.CreateColorCurve()
			local t1 = hc.lossGradientThreshold1 / 100
			local t2 = hc.lossGradientThreshold2 / 100
			local t3 = hc.lossGradientThreshold3 / 100
			local c1 = hc.lossGradientColor1
			local c2 = hc.lossGradientColor2
			local c3 = hc.lossGradientColor3
			curve:AddPoint(t3, CreateColor(c3[1], c3[2], c3[3]))
			curve:AddPoint(t2, CreateColor(c2[1], c2[2], c2[3]))
			curve:AddPoint(t1, CreateColor(c1[1], c1[2], c1[3]))
			h._lossGradientCurve = curve
			h:ForceUpdate()
		end)
		return
	end

	-- Status text settings
	local stKey = key:match('^statusText%.(.+)$')
	if(stKey) then
		local config = F.StyleBuilder.GetConfig(unitType)
		local stCfg = config.statusText
		if(stCfg == true) then stCfg = { enabled = true } end
		if(type(stCfg) ~= 'table') then stCfg = { enabled = false } end

		if(stKey == 'enabled') then
			ForEachFrame(unitType, function(frame)
				if(stCfg.enabled ~= false) then
					F.Elements.StatusText.Setup(frame, stCfg)
					frame:EnableElement('FramedStatusText')
				else
					frame:DisableElement('FramedStatusText')
				end
			end)
		else
			-- Font, outline, shadow, anchor, offset changes
			if(stCfg.enabled == false) then return end
			ForEachFrame(unitType, function(frame)
				F.Elements.StatusText.Setup(frame, stCfg)
			end)
		end
		return
	end

	-- Status icons
	local iconKey = key:match('^statusIcons%.(.+)$')
	if(iconKey) then
		-- Position/size changes: rolePoint, roleX, roleY, roleSize
		local baseKey = iconKey:match('^(%a+)Point$')
			or iconKey:match('^(%a+)Size$')
			or iconKey:match('^(%a+)X$')
			or iconKey:match('^(%a+)Y$')
		if(baseKey) then
			local elementName = STATUS_ELEMENT_MAP[baseKey]
			if(elementName) then
				local config = F.StyleBuilder.GetConfig(unitType)
				local icons = config.statusIcons
				local pt = icons[baseKey .. 'Point']
				local x  = icons[baseKey .. 'X']
				local y  = icons[baseKey .. 'Y']
				local sz = icons[baseKey .. 'Size']
				ForEachFrame(unitType, function(frame)
					local element = frame[elementName]
					if(not element) then return end
					-- PhaseIndicator is a Frame (has SetSize); others are textures
					if(element.SetSize) then
						element:SetSize(sz, sz)
					elseif(element.GetParent and element:IsObjectType('Texture')) then
						Widgets.SetSize(element, sz, sz)
					end
					element:ClearAllPoints()
					Widgets.SetPoint(element, pt, frame, pt, x, y)
				end)
			end
			return
		end

		-- Enable/disable toggles (bare keys like 'role', 'leader', etc.)
		local elementName = STATUS_ELEMENT_MAP[iconKey]
		if(elementName) then
			local config = F.StyleBuilder.GetConfig(unitType)
			local enabled = config.statusIcons and config.statusIcons[iconKey]
			ForEachFrame(unitType, function(frame)
				if(enabled) then
					frame:EnableElement(elementName)
				else
					frame:DisableElement(elementName)
				end
			end)
		end
		return
	end

	-- Show/hide toggles
	if(key == 'showName') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Name) then frame.Name:SetShown(config.showName ~= false) end
		end)
		return
	end

	if(key == 'health.showText') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local show = config.health and config.health.showText
		ForEachFrame(unitType, function(frame)
			if(not frame.Health) then return end
			if(show and not frame.Health.text) then
				-- Create the text FontString on first enable
				local textOverlay = frame._textOverlay
				if(not textOverlay) then
					textOverlay = CreateFrame('Frame', nil, frame)
					textOverlay:SetAllPoints(frame)
					textOverlay:SetFrameLevel(frame:GetFrameLevel() + 5)
					frame._textOverlay = textOverlay
				end
				local hc = config.health
				local text = Widgets.CreateFontString(textOverlay, hc.fontSize, C.Colors.textActive, hc.outline, hc.shadow ~= false)
				local ap = hc.textAnchor
				local anchor = frame.Health._wrapper or frame.Health
				text:SetPoint(ap, anchor, ap, hc.textAnchorX + 1, hc.textAnchorY)
				text._anchorPoint = ap
				text._anchorX = hc.textAnchorX
				text._anchorY = hc.textAnchorY
				frame.Health.text = text
				frame.Health._textFormat = hc.textFormat
				frame.Health._textColorMode = hc.textColorMode
				frame.Health._textCustomColor = hc.textCustomColor
				if(frame.Health.ForceUpdate) then frame.Health:ForceUpdate() end
			elseif(frame.Health.text) then
				frame.Health.text:SetShown(show)
				if(show and frame.Health.ForceUpdate) then frame.Health:ForceUpdate() end
			end
		end)
		return
	end

	-- Attach health text to name toggle
	if(key == 'health.attachedToName') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local hc = config.health
		local attached = hc.attachedToName
		ForEachFrame(unitType, function(frame)
			if(not frame.Health) then return end
			frame.Health._attachedToName = attached

			-- Create text if it doesn't exist yet (showText may have been off)
			if(attached and not frame.Health.text) then
				local textOverlay = frame._textOverlay
				if(not textOverlay) then
					textOverlay = CreateFrame('Frame', nil, frame)
					textOverlay:SetAllPoints(frame)
					textOverlay:SetFrameLevel(frame:GetFrameLevel() + 5)
					frame._textOverlay = textOverlay
				end
				local text = Widgets.CreateFontString(textOverlay, hc.fontSize, C.Colors.textActive, hc.outline, hc.shadow ~= false)
				text._anchorPoint = hc.textAnchor
				text._anchorX = hc.textAnchorX
				text._anchorY = hc.textAnchorY
				frame.Health.text = text
				frame.Health._textFormat = hc.textFormat
				frame.Health._textColorMode = hc.textColorMode
				frame.Health._textCustomColor = hc.textCustomColor
			end

			if(not frame.Health.text) then return end
			frame.Health.text:ClearAllPoints()
			if(attached and frame.Name) then
				frame.Health.text:SetPoint('LEFT', frame.Name, 'RIGHT', 2, 0)
				frame.Health.text:Show()
				frame.Health._lastAttachShift = nil
			else
				local ap = frame.Health.text._anchorPoint
				local anchor = frame.Health._wrapper or frame.Health
				local x = frame.Health.text._anchorX
				local y = frame.Health.text._anchorY
				frame.Health.text:SetPoint(ap, anchor, ap, x + 1, y)
				-- If showText is off and we're detaching, hide the text
				if(not hc.showText) then
					frame.Health.text:Hide()
				end
				-- Restore Name to its original (un-shifted) position
				if(frame.Name) then
					local nc = config.name
					local nap = frame.Name._anchorPoint
					if(type(nap) == 'table') then nap = nap[1] end
					nap = nap or nc.anchor
					local nx = frame.Name._anchorX
					local ny = frame.Name._anchorY
					frame.Name:ClearAllPoints()
					Widgets.SetPoint(frame.Name, nap, frame.Health._wrapper or frame.Health, nap, nx, ny)
				end
				frame.Health._lastAttachShift = nil
			end
			if(frame.Health.ForceUpdate) then frame.Health:ForceUpdate() end
		end)
		return
	end

	-- Power bar per-type custom colors
	if(key:match('^power%.customColors%.')) then
		local config = F.StyleBuilder.GetConfig(unitType)
		local customColors = config.power and config.power.customColors
		ForEachFrame(unitType, function(frame)
			local p = frame.Power
			if(not p) then return end
			p._customColors = customColors
			p:ForceUpdate()
		end)
		return
	end

	if(key == 'power.showText') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local show = config.power and config.power.showText
		ForEachFrame(unitType, function(frame)
			if(not frame.Power) then return end
			if(show and not frame.Power.text) then
				-- Create the text FontString on first enable
				local pc = config.power
				local text = Widgets.CreateFontString(frame.Power, pc.fontSize, C.Colors.textActive, pc.outline, pc.shadow ~= false)
				local ap = pc.textAnchor
				local anchor = frame.Power._wrapper or frame.Power
				text:SetPoint(ap, anchor, ap, pc.textAnchorX + 1, pc.textAnchorY)
				text._anchorPoint = ap
				text._anchorX = pc.textAnchorX
				text._anchorY = pc.textAnchorY
				frame.Power.text = text
				frame.Power._textFormat = pc.textFormat
				frame.Power._textColorMode = pc.textColorMode
				frame.Power._textCustomColor = pc.textCustomColor
				if(frame.Power.ForceUpdate) then frame.Power:ForceUpdate() end
			elseif(frame.Power.text) then
				frame.Power.text:SetShown(show)
				if(show and frame.Power.ForceUpdate) then frame.Power:ForceUpdate() end
			end
		end)
		return
	end

	-- Health prediction toggle
	if(key == 'health.healPrediction') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local enabled = config.health and config.health.healPrediction
		ForEachFrame(unitType, function(frame)
			local h = frame.Health
			if(not h or not h._healPredBar) then return end
			if(enabled) then
				h._healPredBar:Show()
			else
				h._healPredBar:Hide()
			end
		end)
		return
	end

	-- Health prediction mode (all / player / other)
	if(key == 'health.healPredictionMode') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local mode = config.health.healPredictionMode
		ForEachFrame(unitType, function(frame)
			local h = frame.Health
			if(not h or not h._healPredBar) then return end
			h.HealingAll    = nil
			h.HealingPlayer = nil
			h.HealingOther  = nil
			if(mode == 'player') then
				h.HealingPlayer = h._healPredBar
			elseif(mode == 'other') then
				h.HealingOther = h._healPredBar
			else
				h.HealingAll = h._healPredBar
			end
			h:ForceUpdate()
		end)
		return
	end

	-- Damage absorb (shields) toggle
	if(key == 'health.damageAbsorb') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local enabled = config.health and config.health.damageAbsorb
		ForEachFrame(unitType, function(frame)
			local h = frame.Health
			if(not h) then return end
			if(enabled) then
				if(h._damageAbsorbBar) then
					h.DamageAbsorb = h._damageAbsorbBar
					h._damageAbsorbBar:Show()
				end
			else
				h.DamageAbsorb = nil
				if(h._damageAbsorbBar) then h._damageAbsorbBar:Hide() end
			end
			h:ForceUpdate()
		end)
		return
	end

	-- Overshield indicator toggle
	if(key == 'health.overAbsorb') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local enabled = config.health and config.health.overAbsorb
		ForEachFrame(unitType, function(frame)
			local h = frame.Health
			if(not h) then return end
			if(enabled) then
				if(h._overDamageAbsorbIndicator) then
					h.OverDamageAbsorbIndicator = h._overDamageAbsorbIndicator
				end
			else
				h.OverDamageAbsorbIndicator = nil
				if(h._overDamageAbsorbIndicator) then h._overDamageAbsorbIndicator:Hide() end
			end
			h:ForceUpdate()
		end)
		return
	end

	-- Heal absorb toggle
	if(key == 'health.healAbsorb') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local enabled = config.health and config.health.healAbsorb
		ForEachFrame(unitType, function(frame)
			local h = frame.Health
			if(not h) then return end
			if(enabled) then
				if(h._healAbsorbBar) then
					h.HealAbsorb = h._healAbsorbBar
					h._healAbsorbBar:Show()
				end
				if(h._overHealAbsorbIndicator) then
					h.OverHealAbsorbIndicator = h._overHealAbsorbIndicator
				end
			else
				h.HealAbsorb = nil
				if(h._healAbsorbBar) then h._healAbsorbBar:Hide() end
				h.OverHealAbsorbIndicator = nil
				if(h._overHealAbsorbIndicator) then h._overHealAbsorbIndicator:Hide() end
			end
			h:ForceUpdate()
		end)
		return
	end

	-- Heal prediction color
	if(key == 'health.healPredictionColor') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local color = config.health.healPredictionColor
		ForEachFrame(unitType, function(frame)
			if(frame.Health and frame.Health._healPredBar) then
				frame.Health._healPredBar:SetStatusBarColor(color[1], color[2], color[3], color[4])
			end
		end)
		return
	end

	-- Damage absorb color
	if(key == 'health.damageAbsorbColor') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local color = config.health.damageAbsorbColor
		ForEachFrame(unitType, function(frame)
			if(frame.Health and frame.Health._damageAbsorbBar) then
				frame.Health._damageAbsorbBar:SetStatusBarColor(color[1], color[2], color[3], color[4])
			end
		end)
		return
	end

	-- Heal absorb color
	if(key == 'health.healAbsorbColor') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local color = config.health.healAbsorbColor
		ForEachFrame(unitType, function(frame)
			if(frame.Health and frame.Health._healAbsorbBar) then
				frame.Health._healAbsorbBar:SetStatusBarColor(color[1], color[2], color[3], color[4])
			end
		end)
		return
	end

	-- Health text format
	if(key == 'health.textFormat') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Health) then
				frame.Health._textFormat = config.health and config.health.textFormat
				frame.Health:ForceUpdate()
			end
		end)
		return
	end

	-- Power text format
	if(key == 'power.textFormat') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Power) then
				frame.Power._textFormat = config.power and config.power.textFormat
				frame.Power:ForceUpdate()
			end
		end)
		return
	end

	-- ── Health text font / outline / shadow ──────────────────
	if(key == 'health.fontSize' or key == 'health.outline' or key == 'health.shadow') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local hc = config.health
		ForEachFrame(unitType, function(frame)
			if(not frame.Health or not frame.Health.text) then return end
			local t = frame.Health.text
			local size = hc.fontSize
			local flags = hc.outline
			t:SetFont(F.Media.GetActiveFont(), size, flags)
			if(hc.shadow == false) then
				t:SetShadowOffset(0, 0)
			else
				t:SetShadowOffset(1, -1)
			end
		end)
		return
	end

	-- ── Health text anchor / offsets ─────────────────────────
	if(key == 'health.textAnchor' or key == 'health.textAnchorX' or key == 'health.textAnchorY') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local hc = config.health
		ForEachFrame(unitType, function(frame)
			if(not frame.Health or not frame.Health.text) then return end
			if(frame.Health._attachedToName) then return end
			local t = frame.Health.text
			local ap = hc.textAnchor
			local x = hc.textAnchorX
			local y = hc.textAnchorY
			t:ClearAllPoints()
			t:SetPoint(ap, frame.Health._wrapper or frame.Health, ap, x + 1, y)
			t._anchorPoint = ap
			t._anchorX = x
			t._anchorY = y
		end)
		return
	end

	-- ── Health text color mode / custom color ────────────────
	if(key == 'health.textColorMode' or key == 'health.textCustomColor') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local hc = config.health
		ForEachFrame(unitType, function(frame)
			if(not frame.Health) then return end
			frame.Health._textColorMode = hc.textColorMode
			frame.Health._textCustomColor = hc.textCustomColor
			if(frame.Health.ForceUpdate) then frame.Health:ForceUpdate() end
		end)
		return
	end

	-- ── Power text font / outline / shadow ──────────────────
	if(key == 'power.fontSize' or key == 'power.outline' or key == 'power.shadow') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local pc = config.power
		ForEachFrame(unitType, function(frame)
			if(not frame.Power or not frame.Power.text) then return end
			local t = frame.Power.text
			local size = pc.fontSize
			local flags = pc.outline
			t:SetFont(F.Media.GetActiveFont(), size, flags)
			if(pc.shadow == false) then
				t:SetShadowOffset(0, 0)
			else
				t:SetShadowOffset(1, -1)
			end
		end)
		return
	end

	-- ── Power text anchor / offsets ─────────────────────────
	if(key == 'power.textAnchor' or key == 'power.textAnchorX' or key == 'power.textAnchorY') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local pc = config.power
		ForEachFrame(unitType, function(frame)
			if(not frame.Power or not frame.Power.text) then return end
			local t = frame.Power.text
			local ap = pc.textAnchor
			local x = pc.textAnchorX
			local y = pc.textAnchorY
			t:ClearAllPoints()
			t:SetPoint(ap, frame.Power._wrapper or frame.Power, ap, x + 1, y)
			t._anchorPoint = ap
			t._anchorX = x
			t._anchorY = y
		end)
		return
	end

	-- ── Power text color mode / custom color ────────────────
	if(key == 'power.textColorMode' or key == 'power.textCustomColor') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local pc = config.power
		ForEachFrame(unitType, function(frame)
			if(not frame.Power) then return end
			frame.Power._textColorMode = pc.textColorMode
			frame.Power._textCustomColor = pc.textCustomColor
			if(frame.Power.ForceUpdate) then frame.Power:ForceUpdate() end
		end)
		return
	end

	-- ── Name text font / outline / shadow ───────────────────
	if(key == 'name.fontSize' or key == 'name.outline' or key == 'name.shadow') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local nc = config.name
		ForEachFrame(unitType, function(frame)
			if(not frame.Name) then return end
			local size = nc.fontSize
			local flags = nc.outline
			frame.Name:SetFont(F.Media.GetActiveFont(), size, flags)
			if(nc.shadow == false) then
				frame.Name:SetShadowOffset(0, 0)
			else
				frame.Name:SetShadowOffset(1, -1)
			end
		end)
		return
	end

	-- ── Name text anchor / offsets ──────────────────────────
	if(key == 'name.anchor' or key == 'name.anchorX' or key == 'name.anchorY') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local nc = config.name
		ForEachFrame(unitType, function(frame)
			if(not frame.Name) then return end
			local nameAnchor = (frame.Health and frame.Health._wrapper) or frame
			local ap = nc.anchor
			local x = nc.anchorX
			local y = nc.anchorY
			frame.Name:ClearAllPoints()
			Widgets.SetPoint(frame.Name, ap, nameAnchor, ap, x, y)
			frame.Name._anchorPoint = ap
			frame.Name._anchorX = x
			frame.Name._anchorY = y
		end)
		return
	end

	-- ── Name text color mode / custom color ─────────────────
	if(key == 'name.colorMode' or key == 'name.customColor') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local nc = config.name
		local mode = nc.colorMode
		ForEachFrame(unitType, function(frame)
			if(not frame.Name) then return end
			frame.Name._config = frame.Name._config or {}
			frame.Name._config.colorMode = mode
			frame.Name._config.customColor = nc.customColor
			if(mode == 'white') then
				local tc = C.Colors.textActive
				frame.Name:SetTextColor(tc[1], tc[2], tc[3], tc[4])
			elseif(mode == 'dark') then
				frame.Name:SetTextColor(0.25, 0.25, 0.25, 1)
			elseif(mode == 'custom') then
				local cc = nc.customColor
				frame.Name:SetTextColor(cc[1], cc[2], cc[3], 1)
			elseif(mode == 'class') then
				local unit = frame.unit or frame:GetAttribute('unit')
				if(unit) then
					local _, class = UnitClass(unit)
					if(class) then
						local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
						if(classColor) then
							frame.Name:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
						end
					end
				end
			end
		end)
		return
	end

	-- Health smooth
	if(key == 'health.smooth') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local smooth = config.health and config.health.smooth
		local mode = smooth and Enum.StatusBarInterpolation.ExponentialEaseOut
			or Enum.StatusBarInterpolation.Immediate
		ForEachFrame(unitType, function(frame)
			if(frame.Health) then
				frame.Health.smoothing = mode
				frame.Health:ForceUpdate()
			end
		end)
		return
	end

end, 'LiveUpdate.FrameConfig')

-- ============================================================
-- Preset change — re-apply stored element properties from the
-- new preset's config so frames reflect the correct values.
-- ============================================================

--- Apply the full config from the active preset to a single frame.
--- Called on preset switch so frames reflect the correct values after
--- they were initially spawned with a different preset's config.
local function applyFullConfig(frame, config)
	-- Header buttons may exist in oUF.objects before oUF has fully
	-- initialized them (activeElements not yet set). EnableElement
	-- would crash. Health is always present after init, so use it
	-- as a sentinel.
	if(not frame:IsElementEnabled('Health')) then return end

	local unitType = frame._framedUnitType
	-- ── Position (solo frames only) ──────────────────────────
	if(not GROUP_TYPES[unitType]) then
		repositionFrame(frame, config)
	end

	-- ── Dimensions ───────────────────────────────────────────
	local powerHeight = config.power.height
	local healthHeight = config.height - powerHeight
	Widgets.SetSize(frame, config.width, config.height)

	if(frame.Health and frame.Health._wrapper) then
		Widgets.SetSize(frame.Health._wrapper, config.width, healthHeight)
	end

	if(frame.Power and frame.Power._wrapper) then
		Widgets.SetSize(frame.Power._wrapper, config.width, powerHeight)
		local pos = config.power.position
		frame.Power._wrapper:ClearAllPoints()
		frame.Health._wrapper:ClearAllPoints()
		if(pos == 'top') then
			frame.Power._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
			frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -powerHeight)
		else
			frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
			frame.Power._wrapper:SetPoint('TOPLEFT', frame.Health._wrapper, 'BOTTOMLEFT', 0, 0)
		end
		-- Update which border edge is removed for the shared edge
		if(frame.Power.SetSharedEdge) then
			frame.Power:SetSharedEdge(pos)
		end
	end

	-- ── Show/hide power ──────────────────────────────────────
	if(frame.Power) then
		if(config.showPower ~= false) then
			frame:EnableElement('Power')
			frame.Power:Show()
		else
			frame:DisableElement('Power')
			frame.Power:Hide()
		end
	end

	-- ── Health element ───────────────────────────────────────
	local h = frame.Health
	if(h) then
		local hc = config.health

		-- Text format and color
		h._textFormat      = hc.textFormat
		h._textColorMode   = hc.textColorMode
		h._textCustomColor = hc.textCustomColor
		h._attachedToName  = hc.attachedToName

		-- Show/hide health text
		if(h.text) then
			h.text:SetShown(hc.showText ~= false or hc.attachedToName)
		end

		-- Text font / outline / shadow
		if(h.text) then
			h.text:SetFont(F.Media.GetActiveFont(), hc.fontSize, hc.outline)
			if(hc.shadow == false) then
				h.text:SetShadowOffset(0, 0)
			else
				h.text:SetShadowOffset(1, -1)
			end
		end

		-- Text anchor
		if(h.text) then
			h.text:ClearAllPoints()
			if(h._attachedToName and frame.Name) then
				h.text:SetPoint('LEFT', frame.Name, 'RIGHT', 2, 0)
			else
				local ap = hc.textAnchor
				local anchor = h._wrapper or h
				h.text:SetPoint(ap, anchor, ap, hc.textAnchorX + 1, hc.textAnchorY)
				h.text._anchorPoint = ap
				h.text._anchorX = hc.textAnchorX
				h.text._anchorY = hc.textAnchorY
			end
		end

		-- Color mode
		h._colorMode       = hc.colorMode
		h._customColor     = hc.customColor
		h._lossColorMode   = hc.lossColorMode
		h._lossCustomColor = hc.lossCustomColor

		-- Re-apply health bar color mode flags
		h.colorClass    = nil
		h.colorReaction = nil
		h.colorSmooth   = nil
		h.UpdateColor   = nil
		local colorMode = hc.colorMode
		if(colorMode == 'class') then
			h.colorClass    = true
			h.colorReaction = true
			if(h._isNpcFrame) then
				h.UpdateColor = F.Elements.Health.NpcUpdateColor
			end
		elseif(colorMode == 'gradient') then
			h.colorSmooth = true
			if(h._isNpcFrame) then
				h.UpdateColor = F.Elements.Health.NpcUpdateColor
			end
		elseif(colorMode == 'dark') then
			h.UpdateColor = function(self)
				self.Health:SetStatusBarColor(0.25, 0.25, 0.25)
			end
		elseif(colorMode == 'custom') then
			h.UpdateColor = function(self)
				local cc = self.Health._customColor
				self.Health:SetStatusBarColor(cc[1], cc[2], cc[3])
			end
		end

		-- Smooth
		local smooth = hc.smooth
		h.smoothing = smooth and Enum.StatusBarInterpolation.ExponentialEaseOut
			or Enum.StatusBarInterpolation.Immediate

		-- Heal prediction mode
		if(h._healPredBar) then
			h.HealingAll    = nil
			h.HealingPlayer = nil
			h.HealingOther  = nil
			local mode = hc.healPredictionMode
			if(mode == 'player') then
				h.HealingPlayer = h._healPredBar
			elseif(mode == 'other') then
				h.HealingOther = h._healPredBar
			else
				h.HealingAll = h._healPredBar
			end

			-- Heal prediction toggle
			if(hc.healPrediction ~= false) then
				h._healPredBar:Show()
			else
				h._healPredBar:Hide()
			end

			-- Heal prediction color
			local hpColor = hc.healPredictionColor
			h._healPredBar:SetStatusBarColor(hpColor[1], hpColor[2], hpColor[3], hpColor[4])
		end

		-- Damage absorb (shields)
		if(hc.damageAbsorb ~= false) then
			if(h._damageAbsorbBar) then
				h.DamageAbsorb = h._damageAbsorbBar
				h._damageAbsorbBar:Show()
				local daColor = hc.damageAbsorbColor
				h._damageAbsorbBar:SetStatusBarColor(daColor[1], daColor[2], daColor[3], daColor[4])
			end
		else
			h.DamageAbsorb = nil
			if(h._damageAbsorbBar) then h._damageAbsorbBar:Hide() end
		end

		-- Heal absorb
		if(hc.healAbsorb ~= false) then
			if(h._healAbsorbBar) then
				h.HealAbsorb = h._healAbsorbBar
				h._healAbsorbBar:Show()
				local haColor = hc.healAbsorbColor
				h._healAbsorbBar:SetStatusBarColor(haColor[1], haColor[2], haColor[3], haColor[4])
			end
			if(h._overHealAbsorbIndicator) then
				h.OverHealAbsorbIndicator = h._overHealAbsorbIndicator
			end
		else
			h.HealAbsorb = nil
			if(h._healAbsorbBar) then h._healAbsorbBar:Hide() end
			h.OverHealAbsorbIndicator = nil
			if(h._overHealAbsorbIndicator) then h._overHealAbsorbIndicator:Hide() end
		end

		-- Overshield
		if(hc.overAbsorb ~= false) then
			if(h._overDamageAbsorbIndicator) then
				h.OverDamageAbsorbIndicator = h._overDamageAbsorbIndicator
			end
		else
			h.OverDamageAbsorbIndicator = nil
			if(h._overDamageAbsorbIndicator) then h._overDamageAbsorbIndicator:Hide() end
		end

		h:ForceUpdate()
	end

	-- ── Power element ────────────────────────────────────────
	local p = frame.Power
	if(p) then
		local pc = config.power
		p._textFormat      = pc.textFormat
		p._textColorMode   = pc.textColorMode
		p._textCustomColor = pc.textCustomColor
		p._customColors    = pc.customColors

		-- Show/hide power text
		if(p.text) then
			p.text:SetShown(pc.showText ~= false)
		end

		-- Text font / outline / shadow
		if(p.text) then
			p.text:SetFont(F.Media.GetActiveFont(), pc.fontSize, pc.outline)
			if(pc.shadow == false) then
				p.text:SetShadowOffset(0, 0)
			else
				p.text:SetShadowOffset(1, -1)
			end
		end

		-- Text anchor
		if(p.text) then
			p.text:ClearAllPoints()
			local ap = pc.textAnchor
			local anchor = p._wrapper or p
			p.text:SetPoint(ap, anchor, ap, pc.textAnchorX + 1, pc.textAnchorY)
			p.text._anchorPoint = ap
			p.text._anchorX = pc.textAnchorX
			p.text._anchorY = pc.textAnchorY
		end

		p:ForceUpdate()
	end

	-- ── Name element ────────────────────────────────────────
	if(frame.Name) then
		frame.Name:SetShown(config.showName ~= false)

		local nc = config.name

		-- Font / outline / shadow
		local fontSize = nc.fontSize
		local outline = nc.outline
		frame.Name:SetFont(F.Media.GetActiveFont(), fontSize, outline)
		local shadow = nc.shadow
		if(shadow == false) then
			frame.Name:SetShadowOffset(0, 0)
		else
			frame.Name:SetShadowOffset(1, -1)
		end

		-- Anchor — Name anchors to the health wrapper, not the frame.
		-- When health text is attached to name, the centering code in
		-- Health PostUpdate manages Name's position; only store the
		-- base values here so the centering math has correct inputs.
		local nameAnchor = (frame.Health and frame.Health._wrapper) or frame
		local ap = nc.anchor
		local x = nc.anchorX
		local y = nc.anchorY
		frame.Name._anchorPoint = ap
		frame.Name._anchorX = x
		frame.Name._anchorY = y
		if(not (h and h._attachedToName)) then
			frame.Name:ClearAllPoints()
			Widgets.SetPoint(frame.Name, ap, nameAnchor, ap, x, y)
		end

		-- Color mode
		local mode = nc.colorMode
		local customColor = nc.customColor
		frame.Name._config = frame.Name._config or {}
		frame.Name._config.colorMode = mode
		frame.Name._config.customColor = customColor
		if(mode == 'white') then
			local tc = C.Colors.textActive
			frame.Name:SetTextColor(tc[1], tc[2], tc[3], tc[4])
		elseif(mode == 'dark') then
			frame.Name:SetTextColor(0.25, 0.25, 0.25, 1)
		elseif(mode == 'custom') then
			frame.Name:SetTextColor(customColor[1], customColor[2], customColor[3], 1)
		elseif(mode == 'class') then
			local unit = frame.unit or frame:GetAttribute('unit')
			if(unit) then
				local _, class = UnitClass(unit)
				if(class) then
					local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
					if(classColor) then
						frame.Name:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
					end
				end
			end
		end
	end

	-- ── Re-center attached health text ──────────────────────
	-- The Name section above updated _anchorPoint / _anchorX / _anchorY
	-- but skipped the raw SetPoint when attached.  Clear the shift cache
	-- and re-trigger Health so the centering code repositions Name.
	if(frame.Health and frame.Health._attachedToName and frame.Name) then
		frame.Health._lastAttachShift = nil
		if(frame.Health.ForceUpdate) then
			frame.Health:ForceUpdate()
		end
	end

	-- ── Cast bar ─────────────────────────────────────────────
	if(frame.Castbar) then
		if(config.showCastBar ~= false) then
			frame:EnableElement('Castbar')
		else
			frame:DisableElement('Castbar')
		end

		if(frame.Castbar._wrapper) then
			local cbCfg = config.castbar
			if(cbCfg) then
				local cbWidth = (cbCfg.sizeMode == 'detached' and cbCfg.width) or config.width
				Widgets.SetSize(frame.Castbar._wrapper, cbWidth, cbCfg.height)

				local bgMode = cbCfg.backgroundMode
				frame.Castbar._backgroundMode = bgMode
				if(bgMode == 'always') then
					if(frame.Castbar._bg) then frame.Castbar._bg:Show() end
					local bgC = C.Colors.background
					frame.Castbar._wrapper:SetBackdropColor(bgC[1], bgC[2], bgC[3], bgC[4])
				else
					if(frame.Castbar._bg) then frame.Castbar._bg:Hide() end
					frame.Castbar._wrapper:SetBackdropColor(0, 0, 0, 0)
				end
			end
		end
	end

	-- ── Portrait ────────────────────────────────────────────
	local pCfg = config.portrait
	if(pCfg) then
		local wantType = (type(pCfg) == 'table' and pCfg.type) or '2D'
		local curType = frame._portraitType
		if(not frame.Portrait or curType ~= wantType) then
			if(frame.Portrait) then
				frame:DisableElement('Portrait')
				frame.Portrait:Hide()
				frame.Portrait = nil
			end
			F.Elements.Portrait.Setup(frame, config.height, config.height, pCfg == true and {} or pCfg)
			frame.Portrait:ClearAllPoints()
			Widgets.SetPoint(frame.Portrait, 'TOPRIGHT', frame, 'TOPLEFT', -(C.Spacing.base), 0)
			frame._portraitType = wantType
			frame:EnableElement('Portrait')
		end
		frame.Portrait:Show()
		if(frame.Portrait.ForceUpdate) then frame.Portrait:ForceUpdate() end
	else
		if(frame.Portrait) then
			frame:DisableElement('Portrait')
			frame.Portrait:Hide()
		end
	end

	-- ── Status icons ────────────────────────────────────────
	local icons = config.statusIcons
	for iconKey, elementName in next, STATUS_ELEMENT_MAP do
		local enabled = icons[iconKey]
		if(enabled == nil) then
			-- Default: role, leader, readyCheck, raidIcon on; others off
			enabled = (iconKey == 'role' or iconKey == 'leader' or iconKey == 'readyCheck' or iconKey == 'raidIcon')
		end

		if(enabled) then
			frame:EnableElement(elementName)
			local element = frame[elementName]
			if(element) then
				local pt = icons[iconKey .. 'Point']
				local x  = icons[iconKey .. 'X']
				local y  = icons[iconKey .. 'Y']
				local sz = icons[iconKey .. 'Size']
				if(element.SetSize) then
					element:SetSize(sz, sz)
				elseif(element.GetParent and element:IsObjectType('Texture')) then
					Widgets.SetSize(element, sz, sz)
				end
				element:ClearAllPoints()
				Widgets.SetPoint(element, pt, frame, pt, x, y)
			end
		else
			frame:DisableElement(elementName)
		end
	end

	-- ── Status text ─────────────────────────────────────────
	local stCfg = config.statusText
	if(stCfg == true) then stCfg = { enabled = true } end
	if(type(stCfg) == 'table' and stCfg.enabled ~= false) then
		F.Elements.StatusText.Setup(frame, stCfg)
		frame:EnableElement('FramedStatusText')
	else
		frame:DisableElement('FramedStatusText')
	end

end

-- Aura element map for preset switching
local AURA_ELEMENTS = {
	{ key = 'debuffs',        element = 'FramedDebuffs',        setup = 'Debuffs' },
	{ key = 'externals',      element = 'FramedExternals',      setup = 'Externals' },
	{ key = 'defensives',     element = 'FramedDefensives',     setup = 'Defensives' },
	{ key = 'raidDebuffs',    element = 'FramedRaidDebuffs',    setup = 'RaidDebuffs' },
	{ key = 'dispellable',    element = 'FramedDispellable',    setup = 'Dispellable' },
	{ key = 'targetedSpells', element = 'FramedTargetedSpells', setup = 'TargetedSpells' },
	{ key = 'buffs',          element = 'FramedBuffs',          setup = 'Buffs' },
	{ key = 'lossOfControl',  element = 'FramedLossOfControl',  setup = 'LossOfControl' },
	{ key = 'crowdControl',   element = 'FramedCrowdControl',   setup = 'CrowdControl' },
	{ key = 'missingBuffs',   element = 'FramedMissingBuffs',   setup = 'MissingBuffs' },
	{ key = 'privateAuras',   element = 'FramedPrivateAuras',   setup = 'PrivateAuras' },
}

F.EventBus:Register('PRESET_CHANGED', function(presetName)
	for _, frame in next, oUF.objects do
		if(frame._framedUnitType and frame:IsElementEnabled('Health')) then
			local unitType = frame._framedUnitType

			-- Pet frames have their own sync block below; skip generic apply
			if(unitType ~= 'partypet') then
				local config = F.StyleBuilder.GetConfig(unitType)
				if(config) then
					applyFullConfig(frame, config)
				end
			end

			-- Re-apply auras from new preset
			-- Party pets share party aura config
			local auraUnitType = (unitType == 'partypet') and 'party' or unitType
			for _, aura in next, AURA_ELEMENTS do
				local auraCfg = F.StyleBuilder.GetAuraConfig(auraUnitType, aura.key)
				local enabled = auraCfg and auraCfg.enabled
				-- missingBuffs uses next() check instead of .enabled
				if(aura.key == 'missingBuffs') then
					enabled = auraCfg and next(auraCfg)
				end

				if(enabled) then
					local el = frame[aura.element]
					if(el and el.Rebuild) then
						el:Rebuild(auraCfg)
					elseif(F.Elements[aura.setup] and F.Elements[aura.setup].Setup) then
						F.Elements[aura.setup].Setup(frame, auraCfg)
					end
					frame:EnableElement(aura.element)
				else
					frame:DisableElement(aura.element)
				end
			end
		end
	end

	-- Apply group layout attributes to headers from new preset
	for groupType in next, GROUP_TYPES do
		local header = getGroupHeader(groupType)
		if(header) then
			local config = F.StyleBuilder.GetConfig(groupType)
			if(config) then
				applyGroupLayoutToHeader(header, config)
				applyOrQueue(header, 'initial-width', config.width)
				applyOrQueue(header, 'initial-height', config.height)
			end
		end
	end

	-- Sync pet frames from new preset
	if(F.Units.Party.petFrames) then
		local petCfg = F.Units.Party.GetPetConfig()
		local partyConfig = F.StyleBuilder.GetConfig('party')
		local enabled = petCfg.enabled ~= false

		F.Units.Party.SetPetsEnabled(enabled)

		if(enabled and partyConfig) then
			-- Resize pet frames to match party frame size
			local w = partyConfig.width
			local h = partyConfig.height
			ForEachFrame('partypet', function(frame)
				Widgets.SetSize(frame, w, h)
				if(frame.Health and frame.Health._wrapper) then
					Widgets.SetSize(frame.Health._wrapper, w, h)
				end
			end)
			F.Units.Party.AnchorPetFrames()
		end
	end
end, 'LiveUpdate.PresetChanged')

-- ============================================================
-- Party Pets live update
-- partyPets config lives at presets.<name>.partyPets, not inside
-- unitConfigs, so it needs its own CONFIG_CHANGED handler.
-- ============================================================

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local presetName, petKey = path:match('presets%.([^%.]+)%.partyPets%.?(.*)$')
	if(not presetName) then return end
	if(presetName ~= F.AutoSwitch.GetCurrentPreset()) then return end

	local petCfg = F.Units.Party.GetPetConfig()

	-- Enabled toggle
	if(petKey == 'enabled') then
		F.Units.Party.SetPetsEnabled(petCfg.enabled ~= false)
		return
	end

	-- Spacing: re-anchor pet frames to owners
	if(petKey == 'spacing') then
		F.Units.Party.AnchorPetFrames()
		return
	end

	-- Health text changes (show, format, fontSize, color, outline, shadow, offsets)
	if(petKey:match('^healthText') or petKey == 'showHealthText') then
		local show     = petCfg.showHealthText ~= false
		local format   = petCfg.healthTextFormat
		local fontSize = petCfg.healthTextFontSize
		local outline  = petCfg.healthTextOutline
		local shadow   = petCfg.healthTextShadow ~= false
		local colorMode = petCfg.healthTextColor
		local offX     = petCfg.healthTextOffsetX
		local offY     = petCfg.healthTextOffsetY

		ForEachFrame('partypet', function(frame)
			if(not frame.Health) then return end
			frame.Health._textFormat    = format
			frame.Health._textColorMode = colorMode

			if(show and not frame.Health.text) then
				-- Create health text on first enable
				local textOverlay = frame._textOverlay
				if(not textOverlay) then
					textOverlay = CreateFrame('Frame', nil, frame)
					textOverlay:SetAllPoints(frame)
					textOverlay:SetFrameLevel(frame:GetFrameLevel() + 5)
					frame._textOverlay = textOverlay
				end
				local text = Widgets.CreateFontString(textOverlay, fontSize, C.Colors.textActive, outline, shadow)
				text:SetPoint('BOTTOM', frame.Health._wrapper or frame.Health, 'BOTTOM', offX, offY)
				frame.Health.text = text
			end

			-- Update font properties and position on existing text
			if(frame.Health.text) then
				frame.Health.text:SetShown(show)
				local fontPath = frame.Health.text:GetFont()
				if(fontPath) then
					frame.Health.text:SetFont(fontPath, fontSize, outline)
				end
				if(shadow) then
					frame.Health.text:SetShadowOffset(1, -1)
					frame.Health.text:SetShadowColor(0, 0, 0, 1)
				else
					frame.Health.text:SetShadowOffset(0, 0)
				end
				-- Reposition for offset changes
				frame.Health.text:ClearAllPoints()
				frame.Health.text:SetPoint('BOTTOM', frame.Health._wrapper or frame.Health, 'BOTTOM', offX, offY)
			end
			if(frame.Health.ForceUpdate) then frame.Health:ForceUpdate() end
		end)
		return
	end
end, 'LiveUpdate.PartyPets')
