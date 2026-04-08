local addonName, Framed = ...
local F = Framed
local oUF = F.oUF

F.ClickCasting = {}

local combatQueueFrame = nil

--- Check if Clique is installed and active.
--- @return boolean
function F.ClickCasting.HasClique()
	return (_G.Clique ~= nil) or (_G.CliqueDB ~= nil)
end

--- Apply click-cast bindings to a unit frame.
--- @param frame Frame The oUF unit frame
function F.ClickCasting.ApplyBindings(frame)
	if(F.ClickCasting.HasClique()) then
		return
	end

	local bindings = F.ClickCasting.GetBindings()
	if(not bindings) then return end

	-- Clear previous keyboard override bindings
	ClearOverrideBindings(frame)

	for i, binding in next, bindings do
		local prefix = (binding.modifier and binding.modifier ~= '') and (binding.modifier .. '-') or ''
		local button = binding.button or 'LeftButton'

		if(binding.isKey) then
			-- Keyboard binding: map key combo to a virtual button click
			local frameName = frame:GetName()
			if(not frameName) then break end

			local bindKey = prefix:upper() .. button:upper()
			local virtualBtn = 'FramedKey' .. i
			SetOverrideBindingClick(frame, false, bindKey, frameName, virtualBtn)

			-- Set attributes for the virtual button (no modifier prefix needed —
			-- the modifier is already encoded in the key combo)
			local attrKey = 'type-' .. virtualBtn
			if(binding.type == 'spell') then
				frame:SetAttribute(attrKey, 'spell')
				frame:SetAttribute('spell-' .. virtualBtn, binding.spell)
			elseif(binding.type == 'macro') then
				local macroIndex = binding.macro and GetMacroIndexByName(binding.macro)
				if(macroIndex and macroIndex > 0) then
					frame:SetAttribute(attrKey, 'macro')
					frame:SetAttribute('macro-' .. virtualBtn, macroIndex)
				end
			elseif(binding.type == 'target') then
				frame:SetAttribute(attrKey, 'target')
			elseif(binding.type == 'focus') then
				frame:SetAttribute(attrKey, 'focus')
			elseif(binding.type == 'assist') then
				frame:SetAttribute(attrKey, 'assist')
			elseif(binding.type == 'menu') then
				frame:SetAttribute(attrKey, 'togglemenu')
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
				frame:SetAttribute(attrKey, 'spell')
				frame:SetAttribute(prefix .. 'spell-' .. button, binding.spell)
			elseif(binding.type == 'macro') then
				local macroIndex = binding.macro and GetMacroIndexByName(binding.macro)
				if(macroIndex and macroIndex > 0) then
					frame:SetAttribute(attrKey, 'macro')
					frame:SetAttribute(prefix .. 'macro-' .. button, macroIndex)
				end
			elseif(binding.type == 'target') then
				frame:SetAttribute(attrKey, 'target')
			elseif(binding.type == 'focus') then
				frame:SetAttribute(attrKey, 'focus')
			elseif(binding.type == 'assist') then
				frame:SetAttribute(attrKey, 'assist')
			elseif(binding.type == 'menu') then
				frame:SetAttribute(attrKey, 'togglemenu')
			end
		end
	end
end

--- Get current bindings for the player's active spec.
--- @return table|nil
function F.ClickCasting.GetBindings()
	local specIndex = GetSpecialization and GetSpecialization() or 1
	local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex) or 0
	local specKey = tostring(specID)

	local charBindings = F.Config:GetChar('clickCastBindings')
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

	for _, frame in next, oUF.objects do
		F.ClickCasting.ApplyBindings(frame)
	end
end
