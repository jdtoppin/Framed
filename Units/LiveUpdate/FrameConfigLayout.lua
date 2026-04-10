local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets

local Shared = F.LiveUpdate.FrameConfigShared
local ForEachFrame    = Shared.ForEachFrame
local GROUP_TYPES     = Shared.GROUP_TYPES
local getGroupHeader  = Shared.getGroupHeader
local repositionFrame = Shared.repositionFrame
local resizeShift     = Shared.resizeShift
local groupResizeShift = Shared.groupResizeShift
local applyOrQueue     = Shared.applyOrQueue
local applyGroupLayoutToHeader = Shared.applyGroupLayoutToHeader
local debouncedApply  = Shared.debouncedApply

-- ============================================================
-- CONFIG_CHANGED: position, dimensions, group layout
-- ============================================================

local suppressPositionUpdate = false

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local unitType, key = Shared.guardConfigChanged(path)
	if(not unitType) then return end

	-- Frame anchor change — resize preference only, no frame movement
	if(key == 'position.anchor') then
		return
	end

	-- Frame position (x, y)
	if(key == 'position.x' or key == 'position.y') then
		if(suppressPositionUpdate) then return end
		local config = F.StyleBuilder.GetConfig(unitType)
		if(GROUP_TYPES[unitType]) then
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
				local header = getGroupHeader(unitType)

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
					local cbCfg = config.castbar
					if(cbCfg and frame.Castbar and frame.Castbar._wrapper and cbCfg.sizeMode ~= 'detached') then
						Widgets.SetSize(frame.Castbar._wrapper, config.width, cbCfg.height)
					end
				end)
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

				if(unitType == 'party' and F.Units.Party.petFrames) then
					ForEachFrame('partypet', function(frame)
						Widgets.SetSize(frame, config.width, config.height)
						if(frame.Health and frame.Health._wrapper) then
							Widgets.SetSize(frame.Health._wrapper, config.width, config.height)
						end
					end)
				end
			else
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

		if(unitType == 'party' and F.Units.Party.petFrames) then
			F.Units.Party.AnchorPetFrames()
		end
		return
	end
end, 'LiveUpdate.FrameConfigLayout')
