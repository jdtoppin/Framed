local _, Framed = ...
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
-- Layout namespace — exposed as F.LiveUpdate.FrameConfigLayout
-- ============================================================

local Layout = {}

--- Produce the SecureGroupHeader attribute set for a given group
--- unit type and its config. Consumed by Units/Raid.lua and
--- Units/Party.lua spawn paths, and by Layout.ApplySortConfig at
--- runtime.
---
--- Role-mode sorting is implemented via `nameList` (computed in
--- Layout.ComputeRoleNameList), NOT via groupBy. SecureGroupHeader's
--- groupBy='ASSIGNEDROLE' always creates one column per role, which
--- is not what we want — we want a flat sort that flows by the
--- orientation/anchor point and breaks columns only at unitsPerColumn.
--- nameList overrides groupBy/sortMethod and renders units in the
--- exact order we provide.
--- @param config table  Unit config from F.StyleBuilder.GetConfig
--- @param unitType string  'raid' or 'party'
--- @return table  Map of SecureGroupHeader attribute → value
function Layout.GroupAttrs(config, unitType)
	if(unitType == 'raid' and config.sortMode == 'group') then
		return {
			sortMethod     = 'INDEX',
			groupBy        = 'GROUP',
			groupingOrder  = '1,2,3,4,5,6,7,8',
			maxColumns     = 8,
			unitsPerColumn = 5,
		}
	elseif(unitType == 'raid') then
		-- Raid role mode — flat flow, column breaks only at unitsPerColumn
		return {
			sortMethod     = 'INDEX',
			maxColumns     = 8,
			unitsPerColumn = 5,
		}
	elseif(unitType == 'party' and config.sortMode == 'role') then
		-- Party role mode — single column sorted by role
		return {
			sortMethod     = 'INDEX',
			maxColumns     = 1,
			unitsPerColumn = 5,
		}
	else -- party / index
		return {
			sortMethod     = 'INDEX',
			maxColumns     = 1,
			unitsPerColumn = 5,
		}
	end
end

--- Compute a comma-separated nameList for the given unit type,
--- ordered by the configured roleOrder. Used only when
--- config.sortMode == 'role'. Returns nil when the roster is empty
--- or unitType doesn't apply (e.g., raid mode while solo).
---
--- Names with cross-realm suffixes are preserved as "Name-Realm"
--- so SecureGroupHeader can disambiguate collisions.
--- @param unitType string  'raid' or 'party'
--- @return string|nil  Comma-separated nameList or nil
function Layout.ComputeRoleNameList(unitType)
	local config = F.StyleBuilder.GetConfig(unitType)
	local roleOrder = config.roleOrder
	if(not roleOrder or roleOrder == '') then return nil end

	local tokens = {}
	for token in roleOrder:gmatch('[^,]+') do
		tokens[#tokens + 1] = token
	end

	local buckets = {}
	for _, token in next, tokens do buckets[token] = {} end
	local leftovers = {}

	local function addUnit(unit)
		if(not UnitExists(unit)) then return end
		local name, realm = UnitName(unit)
		if(not name) then return end
		local full = (realm and realm ~= '') and (name .. '-' .. realm) or name
		local role = UnitGroupRolesAssigned(unit)
		if(role and buckets[role]) then
			local b = buckets[role]
			b[#b + 1] = full
		else
			leftovers[#leftovers + 1] = full
		end
	end

	if(unitType == 'raid') then
		if(not IsInRaid()) then return nil end
		for i = 1, GetNumGroupMembers() do
			addUnit('raid' .. i)
		end
	else -- party
		addUnit('player')
		for i = 1, 4 do
			addUnit('party' .. i)
		end
	end

	local ordered = {}
	for _, token in next, tokens do
		for _, name in next, buckets[token] do
			ordered[#ordered + 1] = name
		end
	end
	for _, name in next, leftovers do
		ordered[#ordered + 1] = name
	end

	if(#ordered == 0) then return nil end
	return table.concat(ordered, ',')
end

--- Push the current sort config to a spawned group header.
--- Re-applies every attribute that GroupAttrs controls, so that
--- switching sortMode from 'group' to 'role' or back produces the
--- correct layout. All writes go through Shared.applyOrQueue to
--- respect combat lockdown.
---
--- Party pets are separate oUF spawns anchored to party header
--- children by unit attribute (see Units/Party.lua AnchorPetFrames).
--- When the secure header re-sorts, its children have their `unit`
--- attribute reassigned, so any pet frame SetPoint'd to a specific
--- child will now visually sit next to the WRONG party member.
--- We re-run AnchorPetFrames on the next frame (C_Timer.After(0))
--- so the secure template has time to finish its attribute-driven
--- re-layout before we re-resolve owners.
--- @param unitType string  'raid' or 'party'
function Layout.ApplySortConfig(unitType)
	local header = getGroupHeader(unitType)
	if(not header) then return end

	local config = F.StyleBuilder.GetConfig(unitType)
	local attrs  = Layout.GroupAttrs(config, unitType)
	local nameList
	if(config.sortMode == 'role') then
		nameList = Layout.ComputeRoleNameList(unitType)
	end

	-- SecureGroupHeaderTemplate re-runs its sort pass on every write to a
	-- sort-related attribute, so every intermediate state must be
	-- self-consistent. Empty string '' is truthy in Lua, so we clear with
	-- real nil rather than ''.
	--
	-- Clear everything sort-related FIRST, then set. This way no transition
	-- leaves stale grouping state visible to an intermediate update pass.
	applyOrQueue(header, 'nameList',      nil)
	applyOrQueue(header, 'groupBy',       nil)
	applyOrQueue(header, 'groupingOrder', nil)

	applyOrQueue(header, 'sortMethod',     attrs.sortMethod)
	applyOrQueue(header, 'maxColumns',     attrs.maxColumns)
	applyOrQueue(header, 'unitsPerColumn', attrs.unitsPerColumn)

	if(nameList) then
		-- Role mode — nameList overrides sortMethod/groupBy
		applyOrQueue(header, 'nameList', nameList)
	elseif(attrs.groupBy) then
		-- Raid group mode — groupBy with groupingOrder
		applyOrQueue(header, 'groupingOrder', attrs.groupingOrder)
		applyOrQueue(header, 'groupBy',       attrs.groupBy)
	end

	-- Re-anchor party pets after the secure header resettles.
	-- C_Timer.After(0, ...) defers one frame so SecureGroupHeader_Update
	-- has finished reassigning unit attributes to its children.
	if(unitType == 'party' and F.Units.Party and F.Units.Party.AnchorPetFrames) then
		C_Timer.After(0, F.Units.Party.AnchorPetFrames)
	end
end

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

	-- Sort config: sortMode, roleOrder
	if(key == 'sortMode' or key == 'roleOrder') then
		if(not GROUP_TYPES[unitType]) then return end
		Layout.ApplySortConfig(unitType)
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

-- ============================================================
-- Roster / role change re-sort
-- ============================================================
--
-- Role mode uses a computed nameList, so any change to the roster
-- or to anyone's assigned role requires rebuilding that list and
-- pushing it to the header. Both PLAYER_ROLES_ASSIGNED and
-- GROUP_ROSTER_UPDATE trigger a full ApplySortConfig for any unit
-- type currently in role mode.

local function resortRoleModeFrames()
	for _, unitType in next, { 'raid', 'party' } do
		local config = F.StyleBuilder.GetConfig(unitType)
		if(config.sortMode == 'role') then
			Layout.ApplySortConfig(unitType)
		end
	end
end

F.EventBus:Register('PLAYER_ROLES_ASSIGNED', resortRoleModeFrames, 'LiveUpdate.RoleResort')
F.EventBus:Register('GROUP_ROSTER_UPDATE',   resortRoleModeFrames, 'LiveUpdate.RosterResort')

-- ============================================================
-- Export
-- ============================================================

F.LiveUpdate.FrameConfigLayout = Layout
