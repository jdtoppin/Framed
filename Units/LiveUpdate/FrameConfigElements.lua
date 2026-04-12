local _, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

local Shared = F.LiveUpdate.FrameConfigShared
local ForEachFrame = Shared.ForEachFrame
local STATUS_ELEMENT_MAP = Shared.STATUS_ELEMENT_MAP

-- ============================================================
-- CONFIG_CHANGED: power, portrait, castbar, status icons, showName
-- ============================================================

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local unitType, key = Shared.guardConfigChanged(path)
	if(not unitType) then return end

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
					if(frame.FramedStatusText and frame.FramedStatusText.ForceUpdate) then
						frame.FramedStatusText:ForceUpdate()
					end
				else
					frame:DisableElement('FramedStatusText')
				end
			end)
		else
			-- Font, outline, shadow, anchor, offset changes
			if(stCfg.enabled == false) then return end
			ForEachFrame(unitType, function(frame)
				F.Elements.StatusText.Setup(frame, stCfg)
				if(frame.FramedStatusText and frame.FramedStatusText.ForceUpdate) then
					frame.FramedStatusText:ForceUpdate()
				end
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
					local el = frame[elementName]
					if(el and el.ForceUpdate) then el:ForceUpdate() end
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
			if(frame.Name) then frame.Name:SetShown(config.showName) end
		end)
		return
	end

end, 'LiveUpdate.FrameConfigElements')
