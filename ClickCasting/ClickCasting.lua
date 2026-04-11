local _, Framed = ...
local F = Framed
local oUF = F.oUF

F.ClickCasting = {}

local combatQueueFrame = nil

-- Secure header for keyboard override bindings.
-- SetOverrideBindingClick is protected from addon Lua in combat, but the
-- restricted environment in RestrictedFrames.lua holds direct C-function
-- references captured at load time, so restricted snippets can call
-- SetBindingClick/ClearBindings during combat lockdown.
local header = CreateFrame('Frame', 'FramedClickCastHeader', UIParent, 'SecureHandlerEnterLeaveTemplate')

-- Cached keyboard binding data built during RefreshAll,
-- used to populate header attributes for restricted snippets.
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

	-- Clear any override bindings owned by the frame (legacy) or header.
	ClearOverrideBindings(frame)
	ClearOverrideBindings(header)

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
--- Keyboard bindings use a secure header with restricted snippets
--- that activate override bindings on frame enter/leave (works in combat).
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
			-- override bindings are activated via secure header on frame enter/leave
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

	-- Wrap frame with secure header for keyboard override bindings (once per frame).
	-- In the restricted environment (from SecureHandlers.lua Wrapped_OnEnter):
	--   self  = the frame being entered (mapped via signature "self")
	--   owner = the header (from ctrlHandle via environment manager)
	-- Bindings are owned by the header so ClearBindings on leave clears all
	-- header-owned bindings regardless of which frame set them.
	if(#keyBindings > 0 and not frame.__framedKeyWrapped) then
		frame.__framedKeyWrapped = true

		SecureHandlerWrapScript(frame, 'OnEnter', header, [[
			owner:ClearBindings()
			local count = owner:GetAttribute('key-count') or 0
			local name = self:GetName()
			if name and count > 0 then
				for i = 1, count do
					local key = owner:GetAttribute('key-' .. i)
					local btn = owner:GetAttribute('btn-' .. i)
					if key and btn then
						owner:SetBindingClick(false, key, name, btn)
					end
				end
			end
		]])

		SecureHandlerWrapScript(frame, 'OnLeave', header, [[
			owner:ClearBindings()
		]])
	end
end

--- Build the cached keyboard binding table from current bindings
--- and push binding data to header attributes for restricted snippets.
--- Called once during RefreshAll before iterating frames.
local function buildKeyBindings()
	local oldCount = #keyBindings
	wipe(keyBindings)

	local bindings = F.ClickCasting.GetBindings()
	if(not bindings) then
		header:SetAttribute('key-count', 0)
		for i = 1, oldCount do
			header:SetAttribute('key-' .. i, nil)
			header:SetAttribute('btn-' .. i, nil)
		end
		return
	end

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

	-- Push binding data to header attributes so restricted snippets can read them
	header:SetAttribute('key-count', #keyBindings)
	for i, kb in next, keyBindings do
		header:SetAttribute('key-' .. i, kb.key)
		header:SetAttribute('btn-' .. i, kb.virtualBtn)
	end
	-- Clear stale attributes from a previous larger binding set
	for i = #keyBindings + 1, oldCount do
		header:SetAttribute('key-' .. i, nil)
		header:SetAttribute('btn-' .. i, nil)
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
--- Must be called out of combat (SetAttribute is protected).
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

	-- Build keyboard binding cache and update header attributes
	buildKeyBindings()

	-- Clear any active header-owned override bindings before re-applying
	ClearOverrideBindings(header)

	for _, frame in next, oUF.objects do
		F.ClickCasting.ApplyBindings(frame)
	end
end

-- Register an init callback so that header-spawned frames (party/raid)
-- that are created asynchronously by SecureGroupHeader also get
-- click-cast bindings applied. This runs after oUF's initialConfigFunction
-- sets *type2='togglemenu', overriding it with the user's bindings.
oUF:RegisterInitCallback(function(frame)
	if(not InCombatLockdown()) then
		F.ClickCasting.ApplyBindings(frame)
	end
end)
