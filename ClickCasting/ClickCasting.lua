local _, Framed = ...
local F = Framed
local oUF = F.oUF

F.ClickCasting = {}

local combatQueueFrame = nil

-- Cached keyboard binding data built during ApplyBindings,
-- used by OnEnter/OnLeave to activate per-frame override bindings.
-- keyBindings[i] = { key = 'SHIFT-1', virtualBtn = 'FramedKey1' }
local keyBindings = {}

local function trackBindingAttr(frame, key)
	frame.__framedBindingAttrs = frame.__framedBindingAttrs or {}
	frame.__framedBindingAttrs[key] = true
end

local function setTrackedAttribute(frame, key, value)
	frame:SetAttribute(key, value)
	trackBindingAttr(frame, key)
end

local function clearBindingState(frame)
	-- Clear oUF defaults so only explicit click-cast bindings remain.
	frame:SetAttribute('*type1', nil)
	frame:SetAttribute('*type2', nil)

	-- Clear any dynamic override bindings currently active on the frame.
	ClearOverrideBindings(frame)

	-- Remove any secure attributes we previously applied so stale bindings
	-- don't survive when a row is edited, removed, or changes type.
	if(frame.__framedBindingAttrs) then
		for key in next, frame.__framedBindingAttrs do
			frame:SetAttribute(key, nil)
		end
		wipe(frame.__framedBindingAttrs)
	end
end

--- Check if Clique is installed and active.
--- @return boolean
function F.ClickCasting.HasClique()
	return (_G.Clique ~= nil) or (_G.CliqueDB ~= nil)
end

--- Apply click-cast bindings to a unit frame.
--- Mouse bindings are set as attributes (work on click).
--- Keyboard bindings set attributes here but override bindings
--- are activated dynamically on frame enter/leave.
--- @param frame Frame The oUF unit frame
function F.ClickCasting.ApplyBindings(frame)
	clearBindingState(frame)

	if(F.ClickCasting.HasClique()) then
		return
	end

	local bindings = F.ClickCasting.GetBindings()
	if(not bindings) then return end

	for i, binding in next, bindings do
		local prefix = (binding.modifier and binding.modifier ~= '') and (binding.modifier .. '-') or ''
		local button = binding.button or 'LeftButton'

		if(binding.isKey) then
			-- Keyboard binding: set attributes for the virtual button now,
			-- override bindings are activated on frame enter/leave
			local virtualBtn = 'FramedKey' .. i
			local attrKey = 'type-' .. virtualBtn

			if(binding.type == 'spell') then
				setTrackedAttribute(frame, attrKey, 'spell')
				setTrackedAttribute(frame, 'spell-' .. virtualBtn, binding.spell)
			elseif(binding.type == 'macro') then
				local macroIndex = binding.macro and GetMacroIndexByName(binding.macro)
				if(macroIndex and macroIndex > 0) then
					setTrackedAttribute(frame, attrKey, 'macro')
					setTrackedAttribute(frame, 'macro-' .. virtualBtn, macroIndex)
				end
			elseif(binding.type == 'target') then
				setTrackedAttribute(frame, attrKey, 'target')
			elseif(binding.type == 'focus') then
				setTrackedAttribute(frame, attrKey, 'focus')
			elseif(binding.type == 'assist') then
				setTrackedAttribute(frame, attrKey, 'assist')
			elseif(binding.type == 'menu') then
				setTrackedAttribute(frame, attrKey, 'togglemenu')
			end
		else
			-- Mouse button binding
			local buttonNum = (button == 'LeftButton' and '1') or
			                  (button == 'RightButton' and '2') or
			                  (button == 'MiddleButton' and '3') or
			                  (button == 'Button4' and '4') or
			                  (button == 'Button5' and '5') or '1'
			local attrKey = prefix .. 'type' .. buttonNum

			if(binding.type == 'spell') then
				setTrackedAttribute(frame, attrKey, 'spell')
				setTrackedAttribute(frame, prefix .. 'spell-' .. button, binding.spell)
			elseif(binding.type == 'macro') then
				local macroIndex = binding.macro and GetMacroIndexByName(binding.macro)
				if(macroIndex and macroIndex > 0) then
					setTrackedAttribute(frame, attrKey, 'macro')
					setTrackedAttribute(frame, prefix .. 'macro-' .. button, macroIndex)
				end
			elseif(binding.type == 'target') then
				setTrackedAttribute(frame, attrKey, 'target')
			elseif(binding.type == 'focus') then
				setTrackedAttribute(frame, attrKey, 'focus')
			elseif(binding.type == 'assist') then
				setTrackedAttribute(frame, attrKey, 'assist')
			elseif(binding.type == 'menu') then
				setTrackedAttribute(frame, attrKey, 'togglemenu')
			end
		end
	end

	-- Hook enter/leave for keyboard bindings (only if there are any)
	if(#keyBindings > 0 and not frame.__framedKeyHooked) then
		frame.__framedKeyHooked = true

		frame:HookScript('OnEnter', function(self)
			local frameName = self:GetName()
			if(not frameName or InCombatLockdown()) then return end
			for _, kb in next, keyBindings do
				SetOverrideBindingClick(self, false, kb.key, frameName, kb.virtualBtn)
			end
		end)

		frame:HookScript('OnLeave', function(self)
			if(InCombatLockdown()) then return end
			ClearOverrideBindings(self)
		end)
	end
end

--- Build the cached keyboard binding table from current bindings.
--- Called once during RefreshAll before iterating frames.
local function buildKeyBindings()
	keyBindings = {}
	local bindings = F.ClickCasting.GetBindings()
	if(not bindings) then return end

	for i, binding in next, bindings do
		if(binding.isKey) then
			local prefix = (binding.modifier and binding.modifier ~= '') and (binding.modifier:upper() .. '-') or ''
			local key = prefix .. (binding.button or ''):upper()
			keyBindings[#keyBindings + 1] = {
				key = key,
				virtualBtn = 'FramedKey' .. i,
			}
		end
	end
end

--- Get current bindings for the player's active spec.
--- @return table|nil
function F.ClickCasting.GetBindings()
	local specIndex = GetSpecialization and GetSpecialization() or 1
	local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex) or 0
	local specKey = tostring(specID)

	local charBindings = F.Config and F.Config:GetChar('clickCastBindings')
	if(charBindings) then
		-- Check both string and number keys (config stores string keys)
		local specBindings = charBindings[specKey] or charBindings[specID]
		if(specBindings) then return specBindings end
	end

	-- Fall back to defaults
	if(F.ClickCasting.Defaults) then
		return F.ClickCasting.Defaults[specID] or F.ClickCasting.Defaults[specKey] or F.ClickCasting.Defaults['generic']
	end

	return nil
end

--- Refresh all bindings on all spawned frames.
--- Must be called out of combat.
function F.ClickCasting.RefreshAll()
	if(InCombatLockdown()) then
		if(not combatQueueFrame) then
			combatQueueFrame = CreateFrame('Frame')
		end
		combatQueueFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
		combatQueueFrame:SetScript('OnEvent', function(self)
			self:UnregisterAllEvents()
			F.ClickCasting.RefreshAll()
		end)
		return
	end

	if(not oUF or not oUF.objects) then return end

	-- Build keyboard binding cache once before iterating frames
	buildKeyBindings()

	for _, frame in next, oUF.objects do
		F.ClickCasting.ApplyBindings(frame)
	end
end
