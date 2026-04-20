local _, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units        = F.Units        or {}
F.Units.Pinned = F.Units.Pinned or {}

local MAX_SLOTS = 9

-- ============================================================
-- Roster / unit resolution
-- ============================================================

--- Convert UnitName(token) into storage format ('Name' or 'Name-Realm').
local function fullUnitName(token)
	if(not UnitExists(token)) then return nil end
	local name, realm = UnitName(token)
	if(not name) then return nil end
	if(realm and realm ~= '') then
		return name .. '-' .. realm
	end
	return name
end
F.Units.Pinned.FullUnitName = fullUnitName

--- Scan the current group for a player matching storedName.
local function findUnitForName(storedName)
	if(not storedName) then return nil end
	if(IsInRaid()) then
		for i = 1, GetNumGroupMembers() do
			if(fullUnitName('raid' .. i) == storedName) then
				return 'raid' .. i
			end
		end
	elseif(IsInGroup()) then
		for i = 1, GetNumGroupMembers() - 1 do
			if(fullUnitName('party' .. i) == storedName) then
				return 'party' .. i
			end
		end
		if(fullUnitName('player') == storedName) then
			return 'player'
		end
	else
		if(fullUnitName('player') == storedName) then
			return 'player'
		end
	end
	return nil
end
F.Units.Pinned.FindUnitForName = findUnitForName

-- Indicators that resolve self.unit directly inside event paths that don't
-- filter by arg-unit (GROUP_ROSTER_UPDATE / PLAYER_ROLES_ASSIGNED). On an
-- unassigned pinned frame self.unit is nil and UnitIsGroupLeader(nil) etc.
-- raise argument errors, aborting the event mid-flight and starving
-- downstream listeners (Pinned.Resolve, role/color updates) of their run.
-- We toggle them off on unassign and back on when a unit returns.
local NIL_UNSAFE_INDICATORS = {
	'LeaderIndicator',
	'AssistantIndicator',
	'GroupRoleIndicator',
	'RaidRoleIndicator',
}

local function disableNilUnsafeIndicators(frame)
	for _, name in next, NIL_UNSAFE_INDICATORS do
		if(frame[name] and frame.IsElementEnabled and frame:IsElementEnabled(name)) then
			frame:DisableElement(name)
			frame[name]:Hide()
		end
	end
end

local function enableNilUnsafeIndicators(frame)
	for _, name in next, NIL_UNSAFE_INDICATORS do
		if(frame[name] and frame.IsElementEnabled and not frame:IsElementEnabled(name)) then
			frame:EnableElement(name)
		end
	end
end

--- Swap a frame's unit. Updates secure attribute + frame.unit mirror.
--- Combat-safe: returns false if InCombatLockdown prevents SetAttribute.
local function setFrameUnit(frame, token)
	if(InCombatLockdown()) then return false end
	if(frame.unit == token) then return true end
	if(token) then
		frame:SetAttribute('unit', token)
		frame.unit = token
		enableNilUnsafeIndicators(frame)
		if(frame.UpdateAllElements) then
			frame:UpdateAllElements('RefreshUnit')
		end
	else
		disableNilUnsafeIndicators(frame)
		frame:SetAttribute('unit', nil)
		frame.unit = nil
		-- Skip UpdateAllElements on unassign: oUF elements read UnitPower /
		-- UnitHealth / etc., which error on a nil unit. The placeholder covers
		-- the frame visually, so leaving elements with their previous state is
		-- invisible to the user.
	end
	return true
end

local function slotIdentityText(slot)
	if(not slot) then return nil end
	if(slot.type == 'nametarget') then
		return (slot.value or '?') .. "'s Target"
	elseif(slot.type == 'unit') then
		if(slot.value == 'focus')       then return 'Focus'        end
		if(slot.value == 'focustarget') then return 'Focus Target' end
		return slot.value
	end
	return nil
end

-- ============================================================
-- Derived-unit polling
-- WoW fires no event when a unit's target changes. Polls GUID of each
-- polling slot at 0.2s intervals; fires RefreshUnit on change.
-- ============================================================
local POLL_INTERVAL = 0.2
local pollFrame     = CreateFrame('Frame')
local pollElapsed   = 0
local lastGUIDs     = {}

local function slotNeedsPolling(slot)
	if(not slot) then return false end
	if(slot.type == 'nametarget') then return true end
	if(slot.type == 'unit' and slot.value == 'focustarget') then return true end
	return false
end

local function onPollUpdate(_, elapsed)
	pollElapsed = pollElapsed + elapsed
	if(pollElapsed < POLL_INTERVAL) then return end
	pollElapsed = 0

	local config = F.Units.Pinned.GetConfig()
	local frames = F.Units.Pinned.frames
	if(not config or not frames) then return end
	local slots = config.slots or {}

	for i = 1, MAX_SLOTS do
		local slot  = slots[i]
		local frame = frames[i]
		if(slotNeedsPolling(slot) and frame and frame.unit) then
			local newGUID = UnitGUID(frame.unit)
			-- UnitGUID on a compound unit (e.g. 'party2target') can return
			-- a secret-tainted string in combat. Comparing would taint Lua.
			-- When we can't safely diff, refresh unconditionally — the poll
			-- is already rate-limited to 200ms so this is cheap.
			local changed
			if(F.IsValueNonSecret(newGUID)) then
				changed = newGUID ~= lastGUIDs[i]
				if(changed) then lastGUIDs[i] = newGUID end
			else
				changed = true
				lastGUIDs[i] = nil
			end
			if(changed) then
				if(frame.UpdateAllElements) then
					frame:UpdateAllElements('RefreshUnit')
				end
				-- Target went to/from existence — placeholder needs to flip.
				if(F.Units.Pinned.RefreshPlaceholder) then
					F.Units.Pinned.RefreshPlaceholder(i)
				end
			end
		else
			lastGUIDs[i] = nil
		end
	end
end

local function updatePolling()
	local config = F.Units.Pinned.GetConfig()
	if(not config or not config.enabled) then
		pollFrame:SetScript('OnUpdate', nil)
		return
	end

	local slots = config.slots or {}
	for i = 1, MAX_SLOTS do
		if(slotNeedsPolling(slots[i])) then
			pollFrame:SetScript('OnUpdate', onPollUpdate)
			return
		end
	end
	pollFrame:SetScript('OnUpdate', nil)
end
F.Units.Pinned.UpdatePolling = updatePolling

-- ============================================================
-- Config accessor
-- ============================================================

-- Legacy Config:Set writes stored slot entries under string keys (slots['1']);
-- every reader here uses numeric indices, so normalize once per read.
local function normalizeSlotKeys(slots)
	if(type(slots) ~= 'table') then return end
	for k, v in next, slots do
		if(type(k) == 'string') then
			local n = tonumber(k)
			if(n and slots[n] == nil) then
				slots[n] = v
			end
			slots[k] = nil
		end
	end
end

function F.Units.Pinned.GetConfig()
	local config = F.StyleBuilder.GetConfig('pinned')
	if(config and config.slots) then
		normalizeSlotKeys(config.slots)
	end
	return config
end

-- ============================================================
-- Style
-- ============================================================
local function Style(self, unit)
	-- LOW so empty-slot placeholders (MEDIUM) render above and catch hover.
	self:SetFrameStrata('LOW')
	self:RegisterForClicks('AnyUp')
	-- Also set by StyleBuilder.Apply, but Apply is gated on config being
	-- non-nil — cold start under a preset without pinned leaves the tag unset.
	self._framedUnitType = 'pinned'

	local config = F.StyleBuilder.GetConfig('pinned')
	if(config) then
		F.Widgets.SetSize(self, config.width or 160, config.height or 40)
		F.StyleBuilder.Apply(self, unit, config, 'pinned')
	else
		F.Widgets.SetSize(self, 160, 40)
	end

	if(not self.SlotIdentity) then
		local fs = F.Widgets.CreateFontString(self, F.Constants.Font.sizeSmall, F.Constants.Colors.textSecondary)
		-- Two horizontal anchors bound width to the frame so long labels
		-- (e.g. "Some Long Name's Target") truncate with an ellipsis instead
		-- of overflowing past the frame edges.
		fs:SetPoint('BOTTOMLEFT',  self, 'TOPLEFT',  0, 2)
		fs:SetPoint('BOTTOMRIGHT', self, 'TOPRIGHT', 0, 2)
		fs:SetWordWrap(false)
		fs:SetJustifyH('CENTER')
		fs:SetAlpha(0.7)
		self.SlotIdentity = fs
	end

	if(not self.ReassignGear) then
		local gear = CreateFrame('Button', nil, self)
		gear:SetSize(14, 14)
		gear:SetPoint('TOPRIGHT', self, 'TOPRIGHT', -2, -2)
		gear:SetFrameLevel(self:GetFrameLevel() + 5)

		local icon = gear:CreateTexture(nil, 'OVERLAY')
		icon:SetAllPoints(gear)
		icon:SetTexture(F.Media.GetIcon('Settings'))
		gear._icon = icon

		-- Hover visibility is driven by a centralized IsMouseOver() poll
		-- (see anchor OnUpdate in Spawn). HookScript('OnEnter'/'OnLeave')
		-- fires unreliably on pinned frames because aura/overlay children
		-- swallow mouse motion, so we don't register for those here.
		gear:Hide()
		gear:EnableMouse(true)
		gear:RegisterForClicks('LeftButtonUp')

		gear:SetScript('OnClick', function(g)
			local parent = g:GetParent()
			if(InCombatLockdown()) then return end
			if(parent._pinnedSlotIndex and F.Units.Pinned.OpenAssignmentMenu) then
				F.Units.Pinned.OpenAssignmentMenu(parent._pinnedSlotIndex, parent)
			end
		end)

		self.ReassignGear = gear
	end

	F.Widgets.RegisterForUIScale(self)
end

-- ============================================================
-- Position
-- ============================================================
function F.Units.Pinned.ApplyPosition()
	local anchor = F.Units.Pinned.anchor
	if(not anchor) then return end
	local config = F.Units.Pinned.GetConfig()
	local pos = (config and config.position) or { x = 0, y = 0, anchor = 'CENTER' }
	anchor:ClearAllPoints()
	anchor:SetPoint(pos.anchor or 'CENTER', UIParent, pos.anchor or 'CENTER', pos.x or 0, pos.y or 0)
end

-- ============================================================
-- Empty-slot placeholders
-- Non-secure overlay frames shown when a slot is unassigned.
-- Safe in combat (non-secure, no SetAttribute).
-- ============================================================

local function createPlaceholder(parent, slotIndex)
	-- Manual textures via SetColorTexture instead of SetBackdrop + WHITE8x8.
	-- SetBackdrop's bgFile triggers a texture load whose first-paint can
	-- land before SetBackdropColor's tint applies, producing a white flash
	-- on all 9 slots when pinned is first enabled. SetColorTexture creates
	-- a GPU-synthesized solid color with no texture load — correct from
	-- frame 1.
	local ph = CreateFrame('Button', nil, parent)
	ph:Hide()
	ph:SetFrameStrata('MEDIUM')

	local bg = ph:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(ph)
	bg:SetColorTexture(0.08, 0.08, 0.08, 0.6)

	-- 1px border via four solid-color textures
	local br, bgCol, bb, ba = 0.4, 0.4, 0.4, 0.7
	local top = ph:CreateTexture(nil, 'BORDER')
	top:SetColorTexture(br, bgCol, bb, ba)
	top:SetPoint('TOPLEFT',  ph, 'TOPLEFT',  0, 0)
	top:SetPoint('TOPRIGHT', ph, 'TOPRIGHT', 0, 0)
	top:SetHeight(1)
	local bottom = ph:CreateTexture(nil, 'BORDER')
	bottom:SetColorTexture(br, bgCol, bb, ba)
	bottom:SetPoint('BOTTOMLEFT',  ph, 'BOTTOMLEFT',  0, 0)
	bottom:SetPoint('BOTTOMRIGHT', ph, 'BOTTOMRIGHT', 0, 0)
	bottom:SetHeight(1)
	local left = ph:CreateTexture(nil, 'BORDER')
	left:SetColorTexture(br, bgCol, bb, ba)
	left:SetPoint('TOPLEFT',    ph, 'TOPLEFT',    0, 0)
	left:SetPoint('BOTTOMLEFT', ph, 'BOTTOMLEFT', 0, 0)
	left:SetWidth(1)
	local right = ph:CreateTexture(nil, 'BORDER')
	right:SetColorTexture(br, bgCol, bb, ba)
	right:SetPoint('TOPRIGHT',    ph, 'TOPRIGHT',    0, 0)
	right:SetPoint('BOTTOMRIGHT', ph, 'BOTTOMRIGHT', 0, 0)
	right:SetWidth(1)

	local plus = F.Widgets.CreateFontString(ph, 20, F.Constants.Colors.textSecondary)
	plus:SetPoint('CENTER', ph, 'CENTER', 0, 4)
	plus:SetText('+')

	local identity = F.Widgets.CreateFontString(ph, F.Constants.Font.sizeNormal, F.Constants.Colors.textPrimary)
	-- Bound to placeholder width so long identity strings ("Some Long
	-- Name's Target") truncate with an ellipsis instead of spilling past
	-- the placeholder edges.
	identity:SetPoint('LEFT',  ph, 'LEFT',   2, 4)
	identity:SetPoint('RIGHT', ph, 'RIGHT', -2, 4)
	identity:SetWordWrap(false)
	identity:SetJustifyH('CENTER')
	identity:Hide()

	local hint = F.Widgets.CreateFontString(ph, F.Constants.Font.sizeSmall, F.Constants.Colors.textSecondary)
	hint:SetPoint('BOTTOM', ph, 'BOTTOM', 0, 4)
	hint:SetAlpha(0.7)
	hint:SetText('Click to assign')

	-- Gear icon for 'empty' mode: mirrors ReassignGear on live frames so
	-- assigned-but-unresolved target-type slots expose the same gear-on-hover
	-- config entry point as character slots, rather than a different
	-- click-anywhere affordance.
	local gear = CreateFrame('Button', nil, ph)
	gear:SetSize(14, 14)
	gear:SetPoint('TOPRIGHT', ph, 'TOPRIGHT', -2, -2)
	gear:SetFrameLevel(ph:GetFrameLevel() + 5)

	local gearIcon = gear:CreateTexture(nil, 'OVERLAY')
	gearIcon:SetAllPoints(gear)
	gearIcon:SetTexture(F.Media.GetIcon('Settings'))

	-- Hover/alpha is driven by updatePlaceholderGearHover (anchor OnUpdate poll).
	-- No SetScript for OnEnter/OnLeave — let the poll own state.
	gear:Hide()
	gear:EnableMouse(true)
	gear:RegisterForClicks('LeftButtonUp')
	gear:SetScript('OnClick', function(g)
		if(InCombatLockdown()) then return end
		if(F.Units.Pinned.OpenAssignmentMenu) then
			F.Units.Pinned.OpenAssignmentMenu(g:GetParent()._slotIndex, g:GetParent())
		end
	end)

	ph._plusText     = plus
	ph._identityText = identity
	ph._hintText     = hint
	ph._gear         = gear
	ph._slotIndex = slotIndex
	-- Slot 1 is the user's "you are here" anchor — always visible at a dim
	-- alpha so the pinned region is findable even when nothing is assigned.
	-- Remaining slots stay hover-only to avoid visual clutter.
	local restingAlpha = (slotIndex == 1) and 0.5 or 0
	ph._restingAlpha = restingAlpha
	ph:SetAlpha(restingAlpha)
	ph:RegisterForClicks('LeftButtonUp')

	-- Alpha + gear visibility are owned by updatePlaceholderGearHover; see
	-- the anchor OnUpdate poll in F.Units.Pinned.Spawn. OnEnter/OnLeave were
	-- removed because child mouse events (aura overlays on the sibling live
	-- frame) would sometimes leave OnLeave unfired.

	-- 'unassigned' mode uses whole-frame click (no other affordance exists for
	-- an unselected slot). 'empty' mode defers to the gear icon so it matches
	-- the live-frame gear-on-hover pattern. The branch lives in OnClick rather
	-- than swap-in/out scripts because setPlaceholderMode runs frequently and
	-- re-binding scripts would add churn.
	ph:SetScript('OnClick', function(self)
		if(self._mode == 'empty') then return end
		if(F.Units.Pinned.OpenAssignmentMenu) then
			F.Units.Pinned.OpenAssignmentMenu(self._slotIndex, self)
		end
	end)

	return ph
end

-- Placeholder modes:
--   'unassigned' — slot has no selection. Shows "+" + "Click to assign".
--   'empty'      — slot is assigned (e.g. "X's Target") but the underlying
--                  unit doesn't exist right now, so the secure oUF frame is
--                  hidden. The placeholder steps in so the user always has a
--                  hoverable, clickable target for reassigning or unassigning.
local function setPlaceholderMode(ph, mode, identityText)
	local sameMode = (ph._mode == mode)
	-- Idempotency: if mode+text are unchanged, don't touch anything.
	-- RefreshPlaceholder is called from the 0.2s target-GUID poll and
	-- re-setting alpha/visibility here would fight the hover poll,
	-- causing a flash every 200ms.
	if(sameMode and (mode ~= 'empty' or ph._identityText:GetText() == (identityText or ''))) then
		return
	end

	ph._mode = mode
	if(mode == 'empty') then
		ph._plusText:Hide()
		ph._identityText:SetText(identityText or '')
		ph._identityText:Show()
		ph._hintText:Hide()
		ph._restingAlpha = 0.5
	else
		ph._plusText:Show()
		ph._identityText:Hide()
		ph._hintText:SetText('Click to assign')
		ph._hintText:Show()
		ph._restingAlpha = (ph._slotIndex == 1) and 0.5 or 0
	end
	-- Gear visibility + alpha are owned by updatePlaceholderGearHover;
	-- this function only handles mode+text. Hide gear eagerly on mode
	-- change so a stale gear doesn't stick around for 100ms until the
	-- poll catches up.
	if(ph._gear) then ph._gear:Hide() end
end

-- ============================================================
-- Layout (grid)
-- ============================================================
-- @param deferShow  boolean  When true, skip the final anchor:Show() —
-- used by callers that follow Layout with Resolve so the anchor stays
-- hidden through the entire Layout+Resolve transition. Without this,
-- oUF frames briefly render with their stale unit state (spawned as
-- 'player', so all 9 slots flash the player's bars/name) before Resolve
-- clears unit = nil for unassigned slots.
function F.Units.Pinned.Layout(deferShow)
	local anchor = F.Units.Pinned.anchor
	local frames = F.Units.Pinned.frames
	if(not anchor or not frames) then return end

	local config = F.Units.Pinned.GetConfig()
	if(not config or not config.enabled) then
		anchor:Hide()
		return
	end
	-- anchor:Show() deferred to the end of the function so positioning
	-- and placeholder creation happen while the anchor is still hidden.

	local count   = math.max(1, math.min(config.count   or 3, MAX_SLOTS))
	local columns = math.max(1, math.min(config.columns or 3, count))
	local width   = config.width   or 160
	local height  = config.height  or 40
	local spacing = config.spacing or 2

	for i = 1, MAX_SLOTS do
		local f = frames[i]
		if(f) then
			if(i <= count) then
				local row = math.ceil(i / columns) - 1
				local col = ((i - 1) % columns)
				f:ClearAllPoints()
				f:SetPoint('TOPLEFT', anchor, 'TOPLEFT',
					col * (width + spacing),
					-(row * (height + spacing)))
				F.Widgets.SetSize(f, width, height)
				-- The outer frame was originally pixel-snapped at the pre-scale
				-- effective scale. Inner wrappers (health/power) captured that
				-- snap too and were never re-run, so on non-1.0 UI scales they
				-- render ~1px wider than the frame and spill past the dark bg.
				-- Re-snap them at the current (post-SetScale) effective scale.
				if(f.Health and f.Health._wrapper) then F.Widgets.ReSize(f.Health._wrapper) end
				if(f.Power  and f.Power._wrapper)  then F.Widgets.ReSize(f.Power._wrapper)  end
				f:Show()
			else
				f:Hide()
			end
		end
	end

	local rows = math.ceil(count / columns)
	F.Widgets.SetSize(anchor,
		columns * width + (columns - 1) * spacing,
		rows    * height + (rows    - 1) * spacing)

	-- Manage placeholders. Shown for unassigned slots AND for slots whose
	-- unit token doesn't currently resolve to an existing unit — otherwise
	-- the user has no hoverable surface to reopen the assignment menu.
	F.Units.Pinned.placeholders = F.Units.Pinned.placeholders or {}
	local phs = F.Units.Pinned.placeholders
	local slots = config.slots or {}

	for i = 1, MAX_SLOTS do
		local slot = slots[i]
		local f    = frames[i]
		if(i <= count) then
			local unitMissing = slot and f and (not f.unit or not UnitExists(f.unit))
			if(not slot or unitMissing) then
				phs[i] = phs[i] or createPlaceholder(anchor, i)
				phs[i]:ClearAllPoints()
				phs[i]:SetAllPoints(f)
				F.Widgets.SetSize(phs[i], width, height)
				if(slot) then
					setPlaceholderMode(phs[i], 'empty', slotIdentityText(slot))
				else
					setPlaceholderMode(phs[i], 'unassigned')
				end
				phs[i]:Show()
			elseif(phs[i]) then
				phs[i]:Hide()
			end
		elseif(phs[i]) then
			phs[i]:Hide()
		end
	end

	updatePolling()

	if(not deferShow) then
		anchor:Show()
	end
end

--- Convenience wrapper: Hide → Layout → Resolve → Show, atomic from the
--- user's perspective. Used by every call site that needs both a layout
--- refresh AND unit resolution (enable toggle, count/width changes,
--- preset switch). Prevents the stale-state flash described on Layout's
--- deferShow param.
function F.Units.Pinned.Refresh()
	local anchor = F.Units.Pinned.anchor
	if(not anchor) then return end
	anchor:Hide()
	F.Units.Pinned.Layout(true)
	F.Units.Pinned.Resolve()
	local config = F.Units.Pinned.GetConfig()
	if(config and config.enabled) then
		anchor:Show()
	end
end

-- ============================================================
-- Resolve
-- ============================================================
local pendingResolve = false

local function slotToToken(slot)
	if(not slot) then return nil end
	if(slot.type == 'unit') then
		return slot.value
	elseif(slot.type == 'name') then
		return findUnitForName(slot.value)
	elseif(slot.type == 'nametarget') then
		local base = findUnitForName(slot.value)
		return base and (base .. 'target') or nil
	end
	return nil
end

local function applySlotToFrame(frame, slot)
	local token = slotToToken(slot)
	setFrameUnit(frame, token)
	-- Hide live frames with no unit. Layout calls f:Show() on all 9 before
	-- Resolve runs; then anchor:Show() cascades visibility to every child,
	-- and the unassigned frames render their stale oUF seed state (spawned
	-- as 'player' — so a white health/power bar and the player's name) for
	-- the one or two frames it takes oUF's secure unit-watch driver to
	-- hide them. The placeholder's 0.6-alpha background lets that bleed
	-- through as a visible white flash on every enable toggle. Hiding
	-- here — before anchor:Show — eliminates the window.
	-- Guarded on combat because :Show/:Hide on secure buttons is blocked
	-- mid-combat; setFrameUnit has the same guard and would already have
	-- bailed, leaving visibility unchanged, which is safe.
	if(not InCombatLockdown()) then
		if(token and not frame:IsShown()) then
			frame:Show()
		elseif(not token and frame:IsShown()) then
			frame:Hide()
		end
	end
	if(frame.SlotIdentity) then
		local labelText = slotIdentityText(slot)
		-- SlotIdentity is anchored ABOVE the frame (BOTTOM→TOP). In combat,
		-- multiple target-chain frames produce a row of floating labels over
		-- the grid — visual noise when the player is busy and the identity is
		-- redundant anyway (the placeholder shows identity when the target is
		-- missing, and the unit name shows when it's present).
		if(labelText and not InCombatLockdown()) then
			frame.SlotIdentity:SetText(labelText)
			frame.SlotIdentity:Show()
		else
			frame.SlotIdentity:Hide()
		end
	end
end

--- Re-resolve every slot. Used by initial spawn, preset switch, and roster
--- updates — anywhere the tokens may have shifted for reasons other than a
--- single assignment change.
function F.Units.Pinned.Resolve()
	if(InCombatLockdown()) then
		pendingResolve = true
		return
	end
	pendingResolve = false

	local config = F.Units.Pinned.GetConfig()
	local frames = F.Units.Pinned.frames
	if(not config or not frames) then return end

	local slots = config.slots or {}
	for i = 1, MAX_SLOTS do
		local frame = frames[i]
		if(frame) then
			applySlotToFrame(frame, slots[i])
			F.Units.Pinned.RefreshPlaceholder(i)
		end
	end
	updatePolling()
end

--- Apply changes to a single slot only. Used by dropdown assignment so the
--- other eight frames and their placeholders don't re-anchor or redraw.
function F.Units.Pinned.ApplySlot(slotIndex)
	if(InCombatLockdown()) then
		pendingResolve = true
		return
	end
	local config = F.Units.Pinned.GetConfig()
	local frames = F.Units.Pinned.frames
	if(not config or not frames) then return end

	local frame = frames[slotIndex]
	if(not frame) then return end

	local slots = config.slots or {}
	local slot  = slots[slotIndex]

	-- Re-snap the frame and inner wrappers. Health/Power wrappers were
	-- pixel-snapped at the Style-time effective scale; on non-1.0 UI scales
	-- they drift ~1px wider than the outer frame and spill past the dark bg.
	local width  = config.width
	local height = config.height
	F.Widgets.SetSize(frame, width, height)
	if(frame.Health and frame.Health._wrapper) then F.Widgets.ReSize(frame.Health._wrapper) end
	if(frame.Power  and frame.Power._wrapper)  then F.Widgets.ReSize(frame.Power._wrapper)  end

	applySlotToFrame(frame, slot)

	F.Units.Pinned.RefreshPlaceholder(slotIndex)

	updatePolling()
end

--- Re-evaluate placeholder visibility/mode for a single slot. Called from
--- ApplySlot (assignment change) and from the poll loop (target appeared or
--- disappeared for a nametarget/focustarget slot).
function F.Units.Pinned.RefreshPlaceholder(slotIndex)
	local config = F.Units.Pinned.GetConfig()
	local frames = F.Units.Pinned.frames
	if(not config or not frames) then return end
	local frame = frames[slotIndex]
	if(not frame) then return end

	local count = math.max(1, math.min(config.count or 3, MAX_SLOTS))
	local width, height = config.width, config.height
	local slot = (config.slots or {})[slotIndex]
	local unitMissing = slot and (not frame.unit or not UnitExists(frame.unit))

	F.Units.Pinned.placeholders = F.Units.Pinned.placeholders or {}
	local phs = F.Units.Pinned.placeholders

	if(slotIndex > count) then
		if(phs[slotIndex]) then phs[slotIndex]:Hide() end
		return
	end

	-- In combat, the 'empty' placeholder (assigned slot whose target doesn't
	-- currently exist — e.g. "Captain Garrick's Target" when Garrick has no
	-- target) just adds visual noise over the target frame area and can't be
	-- changed anyway. Only show it out of combat; the 'unassigned' mode
	-- (slot 1's always-visible anchor) is still rendered.
	if(slot and unitMissing and InCombatLockdown()) then
		if(phs[slotIndex]) then phs[slotIndex]:Hide() end
		return
	end

	if(not slot or unitMissing) then
		phs[slotIndex] = phs[slotIndex] or createPlaceholder(F.Units.Pinned.anchor, slotIndex)
		phs[slotIndex]:ClearAllPoints()
		phs[slotIndex]:SetAllPoints(frame)
		F.Widgets.SetSize(phs[slotIndex], width, height)
		if(slot) then
			setPlaceholderMode(phs[slotIndex], 'empty', slotIdentityText(slot))
		else
			setPlaceholderMode(phs[slotIndex], 'unassigned')
		end
		phs[slotIndex]:Show()
	elseif(phs[slotIndex]) then
		phs[slotIndex]:Hide()
	end
end

-- ============================================================
-- Gear hover poll
-- Parent OnEnter/OnLeave fire unreliably on live pinned frames — aura
-- icons, overlays, and the MouseoverHighlight child all swallow mouse
-- motion. Poll IsMouseOver() every frame on the (unanimated) anchor instead.
-- ============================================================
local FRAME_HOVER_ALPHA, GEAR_HOVER_ALPHA = 0.8, 1

local function updateGearHover(frame)
	local gear = frame.ReassignGear
	if(not gear) then return end

	-- Hide gear when the frame can't accept one: combat lockdown,
	-- unassigned slot, no unit, or not visible (secure driver hid the
	-- frame because the unit doesn't currently exist).
	if(InCombatLockdown() or not frame._pinnedSlotIndex or not frame.unit or not frame:IsVisible()) then
		if(gear:IsShown()) then gear:Hide() end
		return
	end

	local frameOver = frame:IsMouseOver()
	local gearOver = gear:IsMouseOver()

	if(frameOver or gearOver) then
		if(not gear:IsShown()) then gear:Show() end
		gear:SetAlpha(gearOver and GEAR_HOVER_ALPHA or FRAME_HOVER_ALPHA)
	elseif(gear:IsShown()) then
		gear:Hide()
	end
end

--- Placeholder hover + gear state, driven by the same poll as live frames.
--- HookScript('OnEnter'/'OnLeave') on the placeholder was unreliable — the
--- live frame's aura children can intercept events and leave OnLeave unfired.
local function updatePlaceholderGearHover(ph)
	if(not ph:IsVisible()) then
		if(ph._gear and ph._gear:IsShown()) then ph._gear:Hide() end
		return
	end

	if(ph._menuOpen) then
		ph:SetAlpha(1)
		return
	end

	local gear = ph._gear
	local phOver = ph:IsMouseOver()
	local gearOver = gear and gear:IsMouseOver()
	local canShowGear = gear and ph._mode == 'empty' and not InCombatLockdown()

	if(phOver or gearOver) then
		ph:SetAlpha(1)
		if(canShowGear) then
			if(not gear:IsShown()) then gear:Show() end
			gear:SetAlpha(gearOver and GEAR_HOVER_ALPHA or FRAME_HOVER_ALPHA)
		elseif(gear and gear:IsShown()) then
			gear:Hide()
		end
	else
		ph:SetAlpha(ph._restingAlpha or 0)
		if(gear and gear:IsShown()) then gear:Hide() end
	end
end

-- ============================================================
-- Spawn
-- ============================================================
function F.Units.Pinned.Spawn()
	oUF:RegisterStyle('FramedPinned', Style)
	oUF:SetActiveStyle('FramedPinned')

	local anchor = CreateFrame('Frame', 'FramedPinnedAnchor', UIParent)
	-- Hide immediately — frames will be parented to this anchor and each
	-- oUF:Spawn('player') seeds them with player's bars/name. Without the
	-- pre-hide, all 9 frames briefly render the player's state between
	-- spawn and Resolve setting unit=nil on unassigned slots.
	anchor:Hide()
	F.Widgets.SetSize(anchor, 1, 1)
	F.Units.Pinned.anchor = anchor
	F.Units.Pinned.ApplyPosition()

	local frames = {}
	for i = 1, MAX_SLOTS do
		local frame = oUF:Spawn('player', 'FramedPinnedFrame' .. i)
		frame:SetParent(anchor)
		frames[i] = frame
		frame._pinnedSlotIndex = i
	end
	F.Units.Pinned.frames = frames

	F.Units.Pinned.Refresh()

	anchor:SetScript('OnUpdate', function()
		for _, frame in next, F.Units.Pinned.frames do
			updateGearHover(frame)
		end
		local phs = F.Units.Pinned.placeholders
		if(phs) then
			for _, ph in next, phs do
				updatePlaceholderGearHover(ph)
			end
		end
	end)
end

--- Fallback: the real implementation lives in Settings/Cards/Pinned.lua and
--- overwrites this at load time. This body only runs if that file failed to
--- load — in which case the Settings UI is also unreachable, so don't direct
--- the user there.
function F.Units.Pinned.OpenAssignmentMenu(slotIndex)
	print('|cff00ccffFramed|r Pinned panel is unavailable (slot ' .. slotIndex .. ').')
end

-- ============================================================
-- Event registration
-- ============================================================
F.EventBus:Register('GROUP_ROSTER_UPDATE', function()
	F.Units.Pinned.Resolve()
end, 'Pinned.Resolve')

local function refreshAllPlaceholders()
	for i = 1, MAX_SLOTS do
		F.Units.Pinned.RefreshPlaceholder(i)
	end
end

local function setAllSlotIdentities(visible)
	local frames = F.Units.Pinned.frames
	if(not frames) then return end
	local config = F.Units.Pinned.GetConfig()
	local slots = (config and config.slots) or {}
	for i = 1, MAX_SLOTS do
		local f = frames[i]
		if(f and f.SlotIdentity) then
			local text = visible and slotIdentityText(slots[i])
			if(text) then
				f.SlotIdentity:SetText(text)
				f.SlotIdentity:Show()
			else
				f.SlotIdentity:Hide()
			end
		end
	end
end

F.EventBus:Register('PLAYER_REGEN_ENABLED', function()
	if(pendingResolve) then
		F.Units.Pinned.Resolve()
	end
	-- Empty placeholders and SlotIdentity labels were suppressed in combat.
	refreshAllPlaceholders()
	setAllSlotIdentities(true)
end, 'Pinned.CombatFlush')

F.EventBus:Register('PLAYER_REGEN_DISABLED', function()
	refreshAllPlaceholders()
	setAllSlotIdentities(false)
end, 'Pinned.CombatHidePlaceholders')
