local _, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

local Shared = F.LiveUpdate.FrameConfigShared
local ForEachFrame = Shared.ForEachFrame

-- ============================================================
-- CONFIG_CHANGED: health/power/name text formatting, fonts, anchors
-- ============================================================

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local unitType, key = Shared.guardConfigChanged(path)
	if(not unitType) then return end

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
				if(show) then
					if(frame.Health.ForceUpdate) then frame.Health:ForceUpdate() end
				elseif(frame.Health._attachedToName and frame.Name) then
					-- Restore Name to un-shifted position
					local nc = config.name
					local nap = frame.Name._anchorPoint
					if(type(nap) == 'table') then nap = nap[1] end
					nap = nap or nc.anchor
					local nx = frame.Name._anchorX or nc.anchorX
					local ny = frame.Name._anchorY or nc.anchorY
					frame.Name:ClearAllPoints()
					Widgets.SetPoint(frame.Name, nap, frame.Health._wrapper or frame.Health, nap, nx, ny)
					frame.Health._lastAttachShift = nil
				end
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

			-- Refresh the Name FontString's width constraint: attach-to-name
			-- mode needs a content-sized Name so the Health text anchor and
			-- centering shift work; detached mode needs a bounded width so
			-- long names ellipsize.
			if(frame._updateNameWidth) then frame._updateNameWidth() end

			-- Create text if it doesn't exist yet (only when showText is also on)
			if(attached and hc.showText and not frame.Health.text) then
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
			if(attached and frame.Name and hc.showText) then
				frame.Health.text:SetPoint('LEFT', frame.Name, 'RIGHT', 2, 0)
				frame.Health.text:Show()
				frame.Health._lastAttachShift = nil
			else
				-- Read from live config rather than stashed fields on the
				-- FontString: earlier text-creation paths may have produced
				-- FontStrings without _anchorPoint/X/Y set, which crashed on
				-- x + 1. The config is the source of truth.
				local ap = hc.textAnchor
				local anchor = frame.Health._wrapper or frame.Health
				local x = hc.textAnchorX
				local y = hc.textAnchorY
				frame.Health.text._anchorPoint = ap
				frame.Health.text._anchorX     = x
				frame.Health.text._anchorY     = y
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

end, 'LiveUpdate.FrameConfigText')
