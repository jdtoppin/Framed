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
					local pos = config.power and config.power.position or 'bottom'
					frame.Power._wrapper:ClearAllPoints()
					frame.Health._wrapper:ClearAllPoints()
					if(pos == 'top') then
						frame.Power._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
						frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -powerHeight)
					else
						frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
						frame.Power._wrapper:SetPoint('TOPLEFT', frame.Health._wrapper, 'BOTTOMLEFT', 0, 0)
					end
				end
				-- Sync cast bar width in attached mode
				local cbCfg = config.castbar or {}
				if(frame.Castbar and frame.Castbar._wrapper and cbCfg.sizeMode ~= 'detached') then
					local cbHeight = cbCfg.height or 16
					Widgets.SetSize(frame.Castbar._wrapper, config.width, cbHeight)
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

	-- Power bar height or position
	if(key == 'power.height' or key == 'power.position') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local powerHeight = config.power and config.power.height or 0
		local pos = config.power and config.power.position or 'bottom'
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
		local cbCfg = config.castbar or {}
		local cbWidth = (cbCfg.sizeMode == 'detached' and cbCfg.width) or config.width
		local cbHeight = cbCfg.height or 16
		ForEachFrame(unitType, function(frame)
			local cb = frame.Castbar
			if(not cb or not cb._wrapper) then return end
			Widgets.SetSize(cb._wrapper, cbWidth, cbHeight)
		end)
		return
	end

	-- Cast bar background mode (always / oncast)
	if(key == 'castbar.backgroundMode') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local mode = config.castbar and config.castbar.backgroundMode or 'always'
		ForEachFrame(unitType, function(frame)
			local cb = frame.Castbar
			if(not cb) then return end
			cb._backgroundMode = mode
			if(mode == 'always') then
				if(cb._bg) then cb._bg:Show() end
				local bgC = C.Colors.background
				cb._wrapper:SetBackdropColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1)
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
		-- Position/size changes: rolePoint, roleX, roleY, roleSize
		local baseKey = iconKey:match('^(%a+)Point$')
			or iconKey:match('^(%a+)Size$')
			or iconKey:match('^(%a+)X$')
			or iconKey:match('^(%a+)Y$')
		if(baseKey) then
			local elementName = STATUS_ELEMENT_MAP[baseKey]
			if(elementName) then
				local config = F.StyleBuilder.GetConfig(unitType)
				local icons = config.statusIcons or {}
				local defaults = F.StyleBuilder.ICON_DEFAULTS[baseKey]
				if(defaults) then
					local pt = icons[baseKey .. 'Point'] or defaults.point
					local x  = icons[baseKey .. 'X']     or defaults.x
					local y  = icons[baseKey .. 'Y']     or defaults.y
					local sz = icons[baseKey .. 'Size']  or defaults.size
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
				local hc = config.health or {}
				local text = Widgets.CreateFontString(textOverlay, hc.fontSize or C.Font.sizeSmall, C.Colors.textActive, hc.outline or '', hc.shadow ~= false)
				local ap = hc.textAnchor or 'CENTER'
				local anchor = frame.Health._wrapper or frame.Health
				text:SetPoint(ap, anchor, ap, (hc.textAnchorX or 0) + 1, hc.textAnchorY or 0)
				text._anchorPoint = ap
				text._anchorX = hc.textAnchorX or 0
				text._anchorY = hc.textAnchorY or 0
				frame.Health.text = text
				frame.Health._textFormat = hc.textFormat or 'percent'
				frame.Health._textColorMode = hc.textColorMode or 'white'
				frame.Health._textCustomColor = hc.textCustomColor
				if(frame.Health.ForceUpdate) then frame.Health:ForceUpdate() end
			elseif(frame.Health.text) then
				frame.Health.text:SetShown(show)
				if(show and frame.Health.ForceUpdate) then frame.Health:ForceUpdate() end
			end
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
				local pc = config.power or {}
				local text = Widgets.CreateFontString(frame.Power, pc.fontSize or C.Font.sizeSmall, C.Colors.textActive, pc.outline or '', pc.shadow ~= false)
				local ap = pc.textAnchor or 'CENTER'
				local anchor = frame.Power._wrapper or frame.Power
				text:SetPoint(ap, anchor, ap, (pc.textAnchorX or 0) + 1, pc.textAnchorY or 0)
				text._anchorPoint = ap
				text._anchorX = pc.textAnchorX or 0
				text._anchorY = pc.textAnchorY or 0
				frame.Power.text = text
				frame.Power._textFormat = pc.textFormat or 'current'
				frame.Power._textColorMode = pc.textColorMode or 'white'
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
		local mode = config.health and config.health.healPredictionMode or 'all'
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
		local color = config.health and config.health.healPredictionColor or { 0.6, 0.6, 0.6, 0.4 }
		ForEachFrame(unitType, function(frame)
			if(frame.Health and frame.Health._healPredBar) then
				frame.Health._healPredBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 0.4)
			end
		end)
		return
	end

	-- Damage absorb color
	if(key == 'health.damageAbsorbColor') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local color = config.health and config.health.damageAbsorbColor or { 1, 1, 1, 0.6 }
		ForEachFrame(unitType, function(frame)
			if(frame.Health and frame.Health._damageAbsorbBar) then
				frame.Health._damageAbsorbBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 0.6)
			end
		end)
		return
	end

	-- Heal absorb color
	if(key == 'health.healAbsorbColor') then
		local config = F.StyleBuilder.GetConfig(unitType)
		local color = config.health and config.health.healAbsorbColor or { 0.7, 0.1, 0.1, 0.5 }
		ForEachFrame(unitType, function(frame)
			if(frame.Health and frame.Health._healAbsorbBar) then
				frame.Health._healAbsorbBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 0.5)
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
	local unitType = frame._framedUnitType

	-- ── Position (solo frames only) ──────────────────────────
	if(not GROUP_TYPES[unitType]) then
		repositionFrame(frame, config)
	end

	-- ── Dimensions ───────────────────────────────────────────
	local powerHeight = config.power and config.power.height or 0
	local healthHeight = config.height - powerHeight
	Widgets.SetSize(frame, config.width, config.height)

	if(frame.Health and frame.Health._wrapper) then
		Widgets.SetSize(frame.Health._wrapper, config.width, healthHeight)
	end

	if(frame.Power and frame.Power._wrapper) then
		Widgets.SetSize(frame.Power._wrapper, config.width, powerHeight)
		local pos = config.power and config.power.position or 'bottom'
		frame.Power._wrapper:ClearAllPoints()
		frame.Health._wrapper:ClearAllPoints()
		if(pos == 'top') then
			frame.Power._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
			frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -powerHeight)
		else
			frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
			frame.Power._wrapper:SetPoint('TOPLEFT', frame.Health._wrapper, 'BOTTOMLEFT', 0, 0)
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
		local hc = config.health or {}

		-- Text format and color
		h._textFormat      = hc.textFormat
		h._textColorMode   = hc.textColorMode or 'white'
		h._textCustomColor = hc.textCustomColor

		-- Show/hide health text
		if(h.text) then
			h.text:SetShown(hc.showText ~= false)
		end

		-- Text anchor
		if(h.text and hc.textAnchor) then
			h.text:ClearAllPoints()
			local ap = hc.textAnchor or 'CENTER'
			local anchor = h._wrapper or h
			h.text:SetPoint(ap, anchor, ap, (hc.textAnchorX or 0) + 1, hc.textAnchorY or 0)
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
		local colorMode = hc.colorMode or 'class'
		if(colorMode == 'class') then
			h.colorClass    = true
			h.colorReaction = true
		elseif(colorMode == 'gradient') then
			h.colorSmooth = true
		elseif(colorMode == 'dark') then
			h.UpdateColor = function(self)
				self.Health:SetStatusBarColor(0.25, 0.25, 0.25)
			end
		elseif(colorMode == 'custom') then
			h.UpdateColor = function(self)
				local cc = self.Health._customColor or { 0.2, 0.8, 0.2 }
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
			local mode = hc.healPredictionMode or 'all'
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
			local hpColor = hc.healPredictionColor or { 0.6, 0.6, 0.6, 0.4 }
			h._healPredBar:SetStatusBarColor(hpColor[1], hpColor[2], hpColor[3], hpColor[4] or 0.4)
		end

		-- Damage absorb (shields)
		if(hc.damageAbsorb ~= false) then
			if(h._damageAbsorbBar) then
				h.DamageAbsorb = h._damageAbsorbBar
				h._damageAbsorbBar:Show()
				local daColor = hc.damageAbsorbColor or { 1, 1, 1, 0.6 }
				h._damageAbsorbBar:SetStatusBarColor(daColor[1], daColor[2], daColor[3], daColor[4] or 0.6)
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
				local haColor = hc.healAbsorbColor or { 0.7, 0.1, 0.1, 0.5 }
				h._healAbsorbBar:SetStatusBarColor(haColor[1], haColor[2], haColor[3], haColor[4] or 0.5)
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
		local pc = config.power or {}
		p._textFormat      = pc.textFormat
		p._textColorMode   = pc.textColorMode or 'white'
		p._textCustomColor = pc.textCustomColor
		p._customColors    = pc.customColors

		-- Show/hide power text
		if(p.text) then
			p.text:SetShown(pc.showText ~= false)
		end

		-- Text anchor
		if(p.text and pc.textAnchor) then
			p.text:ClearAllPoints()
			local ap = pc.textAnchor or 'CENTER'
			local anchor = p._wrapper or p
			p.text:SetPoint(ap, anchor, ap, (pc.textAnchorX or 0) + 1, pc.textAnchorY or 0)
		end

		p:ForceUpdate()
	end

	-- ── Cast bar ─────────────────────────────────────────────
	if(frame.Castbar) then
		if(config.showCastBar ~= false) then
			frame:EnableElement('Castbar')
		else
			frame:DisableElement('Castbar')
		end

		if(frame.Castbar._wrapper) then
			local cbCfg = config.castbar or {}
			local cbWidth = (cbCfg.sizeMode == 'detached' and cbCfg.width) or config.width
			local cbHeight = cbCfg.height or 16
			Widgets.SetSize(frame.Castbar._wrapper, cbWidth, cbHeight)

			local bgMode = cbCfg.backgroundMode or 'always'
			frame.Castbar._backgroundMode = bgMode
			if(bgMode == 'always') then
				if(frame.Castbar._bg) then frame.Castbar._bg:Show() end
				local bgC = C.Colors.background
				frame.Castbar._wrapper:SetBackdropColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1)
			else
				if(frame.Castbar._bg) then frame.Castbar._bg:Hide() end
				frame.Castbar._wrapper:SetBackdropColor(0, 0, 0, 0)
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
	local icons = config.statusIcons or {}
	local ICON_DEFAULTS = F.StyleBuilder.ICON_DEFAULTS
	for iconKey, elementName in next, STATUS_ELEMENT_MAP do
		local defaults = ICON_DEFAULTS[iconKey]
		if(not defaults) then break end

		local enabled = icons[iconKey]
		if(enabled == nil) then
			-- Default: role, leader, readyCheck, raidIcon on; others off
			enabled = (iconKey == 'role' or iconKey == 'leader' or iconKey == 'readyCheck' or iconKey == 'raidIcon')
		end

		if(enabled) then
			frame:EnableElement(elementName)
			local element = frame[elementName]
			if(element) then
				local pt = icons[iconKey .. 'Point'] or defaults.point
				local x  = icons[iconKey .. 'X']     or defaults.x
				local y  = icons[iconKey .. 'Y']     or defaults.y
				local sz = icons[iconKey .. 'Size']  or defaults.size
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
	if(config.statusText ~= false) then
		if(not frame.FramedStatusText) then
			F.Elements.StatusText.Setup(frame)
		end
		frame:EnableElement('FramedStatusText')
	else
		frame:DisableElement('FramedStatusText')
	end

	-- ── Name ─────────────────────────────────────────────────
	if(frame.Name) then
		frame.Name:SetShown(config.showName ~= false)

		local nc = config.name or {}
		local colorMode = nc.colorMode or 'class'
		if(colorMode == 'dark') then
			frame.Name:SetTextColor(0.25, 0.25, 0.25, 1)
		elseif(colorMode == 'white') then
			frame.Name:SetTextColor(1, 1, 1, 1)
		elseif(colorMode == 'custom') then
			local cc = nc.customColor or { 1, 1, 1 }
			frame.Name:SetTextColor(cc[1], cc[2], cc[3], 1)
		end

		-- Text anchor
		if(nc.anchor) then
			frame.Name:ClearAllPoints()
			local ap = nc.anchor
			local anchor = h and h._wrapper or frame
			frame.Name:SetPoint(ap, anchor, ap, (nc.anchorX or 0) + 1, nc.anchorY or 0)
		end
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
		if(frame._framedUnitType) then
			local unitType = frame._framedUnitType
			local config = F.StyleBuilder.GetConfig(unitType)
			if(config) then
				applyFullConfig(frame, config)
			end

			-- Re-apply auras from new preset
			for _, aura in next, AURA_ELEMENTS do
				local auraCfg = F.StyleBuilder.GetAuraConfig(unitType, aura.key)
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
end, 'LiveUpdate.PresetChanged')
