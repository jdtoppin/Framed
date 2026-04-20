local _, Framed = ...
local F = Framed

local Shared = F.LiveUpdate and F.LiveUpdate.FrameConfigShared
if(not Shared) then return end

local guardConfigChanged = Shared.guardConfigChanged
local debouncedApply     = Shared.debouncedApply

local function onConfigChanged(path)
	local unitType, key = guardConfigChanged(path)
	if(unitType ~= 'pinned') then return end

	-- position.anchor is resize-preference metadata only — don't re-apply
	-- position or re-layout when it changes (matches party/raid/solo
	-- behavior). Layout reads config.anchorPoint for growth direction.
	if(key == 'position.anchor') then return end

	if(key == 'position.x' or key == 'position.y') then
		debouncedApply('pinned.position', function()
			-- ApplyPosition alone — anchor parents all 9 slots. Calling Layout
			-- here re-Shows unassigned frames (Layout's unconditional f:Show)
			-- and they flash the stale oUF 'player' seed state before anything
			-- hides them again.
			F.Units.Pinned.ApplyPosition()
		end)
	elseif(key == 'enabled' or key == 'count') then
		-- Refresh = Hide → Layout → Resolve → Show atomic. Only for
		-- structural changes (enable toggle, slot count) where we need
		-- Resolve to re-assign/clear units. Geometry-only keys take the
		-- Layout-alone path below — Refresh's anchor:Hide/Show wrapper
		-- creates a brief frames-gone flash that reads as "frames shrank
		-- and bounced back" on a width change.
		debouncedApply('pinned.layout', function()
			F.Units.Pinned.Refresh()
		end)
	elseif(key == 'columns' or key == 'width' or key == 'height'
	    or key == 'spacing' or key == 'anchorPoint') then
		-- Layout alone. Tokens haven't changed, so Resolve has nothing to
		-- do — and skipping Refresh's anchor:Hide/Show wrapper avoids the
		-- flash. Layout's `if(f.unit) then f:Show() end` guard keeps
		-- unassigned frames hidden, so Bug C's 'player' seed flash stays fixed.
		-- Dimension changes (width/height/cols/spacing) also shift x/y
		-- so the Resize Anchor pivot stays visually fixed — without this,
		-- bg growth always cascades from TOPLEFT. anchorPoint doesn't
		-- change bg bounds, so its dw/dh is zero and no shift applies.
		debouncedApply('pinned.layout', function()
			local anchor = F.Units.Pinned.anchor
			local oldBgW = (anchor and anchor._width)  or 0
			local oldBgH = (anchor and anchor._height) or 0

			F.Units.Pinned.Layout()

			local isDim = (key == 'width' or key == 'height'
				or key == 'columns' or key == 'spacing')
			if(not isDim) then return end

			local newBgW = (anchor and anchor._width)  or 0
			local newBgH = (anchor and anchor._height) or 0
			local dw = newBgW - oldBgW
			local dh = newBgH - oldBgH
			if(dw == 0 and dh == 0) then return end

			local config = F.Units.Pinned.GetConfig()
			local resizeAnchor = (config and config.position and config.position.anchor) or 'TOPLEFT'
			if(resizeAnchor == 'TOPLEFT') then return end
			if(not Shared.groupResizeShift) then return end

			local dx, dy = Shared.groupResizeShift('TOPLEFT', resizeAnchor, dw, dh)
			if(dx == 0 and dy == 0) then return end

			local presetName = F.AutoSwitch.GetCurrentPreset()
			local basePath = 'presets.' .. presetName .. '.unitConfigs.pinned.position.'
			local curX = (config.position and config.position.x) or 0
			local curY = (config.position and config.position.y) or 0
			F.Config:Set(basePath .. 'x', F.Widgets.Round(curX + dx))
			F.Config:Set(basePath .. 'y', F.Widgets.Round(curY + dy))

			-- Close the 50ms gap between Layout-writes-position and the
			-- debounced ApplyPosition that position.x's CC handler would
			-- queue. Without this, the anchor stays at the old position
			-- for 50ms while the frames sit at the new size — and with a
			-- non-TOPLEFT resize anchor the pivot edge visibly drifts
			-- before snapping back. The queued debounced ApplyPosition
			-- still fires 50ms later, but it's a visual no-op then.
			F.Units.Pinned.ApplyPosition()
		end)
	elseif(key == 'name.fontSize') then
		debouncedApply('pinned.labelFonts', function()
			F.Units.Pinned.ApplyLabelFonts()
		end)
	elseif(key and key:match('^slots')) then
		-- Single-slot path: `slots.N` or `slots.N.<field>`. Only touch frame N
		-- so the other eight don't re-anchor (which flashed their backdrops).
		local slotIndex = tonumber(key:match('^slots%.(%d+)'))
		if(slotIndex) then
			F.Units.Pinned.ApplySlot(slotIndex)
		else
			F.Units.Pinned.Refresh()
		end
	end
end
F.EventBus:Register('CONFIG_CHANGED', onConfigChanged, 'FrameConfigPinned.CC')

F.EventBus:Register('PRESET_CHANGED', function()
	F.Units.Pinned.ApplyPosition()
	F.Units.Pinned.Refresh()
end, 'FrameConfigPinned.PresetChanged')
