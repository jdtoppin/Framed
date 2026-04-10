local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

-- ============================================================
-- CONFIG_CHANGED: health coloring, shields, absorbs, smooth
-- ============================================================

local Shared = F.LiveUpdate.FrameConfigShared
local ForEachFrame = Shared.ForEachFrame

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local unitType, key = Shared.guardConfigChanged(path)
	if(not unitType) then return end

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

			-- NPC frames always use the full oUF chain
			if(h._isNpcFrame) then
				h.colorTapping  = true
				h.colorThreat   = true
				h.colorClass    = true
				h.colorReaction = true
				h.UpdateColor   = F.Elements.Health.NpcUpdateColor
			elseif(mode == 'class') then
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
					[hc.gradientThreshold3 / 100]  = CreateColor(unpack(hc.gradientColor3)),
					[hc.gradientThreshold2 / 100] = CreateColor(unpack(hc.gradientColor2)),
					[hc.gradientThreshold1 / 100] = CreateColor(unpack(hc.gradientColor1)),
				})
			elseif(mode == 'dark') then
				h.UpdateColor = function(self)
					self.Health:SetStatusBarColor(0.25, 0.25, 0.25)
				end
			elseif(mode == 'custom') then
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
					h._overDamageAbsorbIndicator:Show()
					h._overDamageAbsorbIndicator:SetAlpha(0)
					h.OverDamageAbsorbIndicator = h._overDamageAbsorbIndicator
				end
				if(not h._overShieldCalc and CreateUnitHealPredictionCalculator) then
					h._overShieldCalc = CreateUnitHealPredictionCalculator()
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

end, 'LiveUpdate.FrameConfigHealth')
