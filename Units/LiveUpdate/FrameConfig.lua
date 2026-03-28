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
	-- Matches both 'presets.<name>.unitConfigs.<unitType>.<key>' and 'unitConfigs.<unitType>.<key>'
	local unitType, rest = path:match('unitConfigs%.([^%.]+)%.(.+)$')
	return unitType, rest
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

--- Reposition a solo frame using CENTER anchor + config offsets.
--- position.x/y are always relative to UIParent CENTER.
local function repositionFrame(frame, config)
	local pos = config.position
	local x = (pos and pos.x) or 0
	local y = (pos and pos.y) or 0
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

-- ============================================================
-- Main CONFIG_CHANGED handler
-- ============================================================

local suppressPositionUpdate = false

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local unitType, key = parseUnitConfigPath(path)
	if(not unitType) then return end

	-- Frame anchor change — resize preference only, no frame movement
	if(key == 'position.anchor') then
		return
	end

	-- Frame position (x, y)
	if(key == 'position.x' or key == 'position.y') then
		if(suppressPositionUpdate) then return end
		if(GROUP_TYPES[unitType]) then return end
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			repositionFrame(frame, config)
		end)
		return
	end

	-- Dimensions — resize frame, health wrapper, power wrapper
	if(key == 'width' or key == 'height') then
		if(GROUP_TYPES[unitType]) then return end
		local config = F.StyleBuilder.GetConfig(unitType)
		debouncedApply('dimensions.' .. unitType, function()
			local powerHeight = config.power and config.power.height or 0
			local healthHeight = config.height - powerHeight
			local anchor = config.position and config.position.anchor or 'CENTER'
			ForEachFrame(unitType, function(frame)
				-- Compute how much the center needs to shift to keep
				-- the configured anchor corner/edge fixed during resize
				local oldW = frame._width or frame:GetWidth() or config.width
				local oldH = frame._height or frame:GetHeight() or config.height
				local dw = config.width - oldW
				local dh = config.height - oldH
				if(dw ~= 0 or dh ~= 0) then
					local dx, dy = resizeShift(anchor, dw, dh)
					local pos = config.position
					local curX = (pos and pos.x) or 0
					local curY = (pos and pos.y) or 0
					suppressPositionUpdate = true
					local presetName = F.AutoSwitch.GetCurrentPreset()
					local basePath = 'presets.' .. presetName .. '.unitConfigs.' .. unitType .. '.position.'
					F.Config:Set(basePath .. 'x', Widgets.Round(curX + dx))
					F.Config:Set(basePath .. 'y', Widgets.Round(curY + dy))
					suppressPositionUpdate = false
				end
				-- Reposition with (possibly shifted) center offsets
				repositionFrame(frame, F.StyleBuilder.GetConfig(unitType))
				Widgets.SetSize(frame, config.width, config.height)
				if(frame.Health and frame.Health._wrapper) then
					Widgets.SetSize(frame.Health._wrapper, config.width, healthHeight)
				end
				if(frame.Power and frame.Power._wrapper) then
					Widgets.SetSize(frame.Power._wrapper, config.width, powerHeight)
					frame.Power._wrapper:ClearAllPoints()
					frame.Power._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -healthHeight)
				end
			end)
		end)
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

	-- Health bar color mode
	if(key == 'health.colorMode') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local mode = config.health and config.health.colorMode or 'class'
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
			h._customColor = config.health and config.health.customColor or { 0.2, 0.8, 0.2 }

			-- Set flags for new mode
			if(mode == 'class') then
				h.colorClass    = true
				h.colorReaction = true
			elseif(mode == 'gradient') then
				h.colorSmooth = true
				-- Ensure per-frame colors table exists
				if(not rawget(frame, 'colors')) then
					frame.colors = setmetatable({}, { __index = oUF.colors })
				end
				local hc = config.health
				frame.colors.health = oUF:CreateColor(0.2, 0.8, 0.2)
				frame.colors.health:SetCurve({
					[(hc.gradientThreshold3 or 5) / 100]  = CreateColor(unpack(hc.gradientColor3 or { 0.8, 0.1, 0.1 })),
					[(hc.gradientThreshold2 or 50) / 100] = CreateColor(unpack(hc.gradientColor2 or { 0.9, 0.6, 0.1 })),
					[(hc.gradientThreshold1 or 95) / 100] = CreateColor(unpack(hc.gradientColor1 or { 0.2, 0.8, 0.2 })),
				})
			elseif(mode == 'dark') then
				-- Override UpdateColor to directly set dark gray
				h.UpdateColor = function(self)
					self.Health:SetStatusBarColor(0.25, 0.25, 0.25)
				end
			elseif(mode == 'custom') then
				-- Override UpdateColor to directly set the custom color
				h.UpdateColor = function(self)
					local cc = self.Health._customColor or { 0.2, 0.8, 0.2 }
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
		local color = config.health and config.health.customColor or { 0.2, 0.8, 0.2 }
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
		local hc = config.health or {}
		local mode = hc.lossColorMode or 'dark'
		ForEachFrame(unitType, function(frame)
			local h = frame.Health
			if(not h or not h._bg) then return end
			h._lossColorMode = mode
			-- Build gradient curve if switching to gradient mode
			if(mode == 'gradient') then
				local curve = C_CurveUtil.CreateColorCurve()
				local t1 = (hc.lossGradientThreshold1 or 95) / 100
				local t2 = (hc.lossGradientThreshold2 or 50) / 100
				local t3 = (hc.lossGradientThreshold3 or 5) / 100
				local c1 = hc.lossGradientColor1 or { 0.1, 0.4, 0.1 }
				local c2 = hc.lossGradientColor2 or { 0.4, 0.25, 0.05 }
				local c3 = hc.lossGradientColor3 or { 0.4, 0.05, 0.05 }
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
				local lc = h._lossCustomColor or { 0.15, 0.15, 0.15 }
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
		local color = config.health and config.health.lossCustomColor or { 0.15, 0.15, 0.15 }
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
		local hc = config.health or {}
		ForEachFrame(unitType, function(frame)
			local h = frame.Health
			if(not h) then return end
			-- Rebuild the curve with updated colors/thresholds
			local curve = C_CurveUtil.CreateColorCurve()
			local t1 = (hc.lossGradientThreshold1 or 95) / 100
			local t2 = (hc.lossGradientThreshold2 or 50) / 100
			local t3 = (hc.lossGradientThreshold3 or 5) / 100
			local c1 = hc.lossGradientColor1 or { 0.1, 0.4, 0.1 }
			local c2 = hc.lossGradientColor2 or { 0.4, 0.25, 0.05 }
			local c3 = hc.lossGradientColor3 or { 0.4, 0.05, 0.05 }
			curve:AddPoint(t3, CreateColor(c3[1], c3[2], c3[3]))
			curve:AddPoint(t2, CreateColor(c2[1], c2[2], c2[3]))
			curve:AddPoint(t1, CreateColor(c1[1], c1[2], c1[3]))
			h._lossGradientCurve = curve
			h:ForceUpdate()
		end)
		return
	end

	-- Status icons
	local iconKey = key:match('^statusIcons%.(.+)$')
	if(iconKey) then
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
		ForEachFrame(unitType, function(frame)
			if(frame.Health and frame.Health.text) then
				frame.Health.text:SetShown(config.health and config.health.showText)
			end
		end)
		return
	end

	if(key == 'power.showText') then
		local config = F.StyleBuilder.GetConfig(unitType)
		ForEachFrame(unitType, function(frame)
			if(frame.Power and frame.Power.text) then
				frame.Power.text:SetShown(config.power and config.power.showText)
			end
		end)
		return
	end

	-- Health prediction
	if(key:match('^health%.healPrediction')) then
		local config = F.StyleBuilder.GetConfig(unitType)
		local hp = config.health
		ForEachFrame(unitType, function(frame)
			if(hp.healPrediction) then
				frame:EnableElement('HealthPrediction')
			else
				frame:DisableElement('HealthPrediction')
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
