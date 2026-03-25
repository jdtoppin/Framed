local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Icon = {}

-- Wrap C.Colors.dispel with a 'none' fallback without mutating the shared constant table
local DEBUFF_TYPE_COLORS = setmetatable({ none = C.Colors.dispel.Physical }, { __index = C.Colors.dispel })

-- ============================================================
-- Duration OnUpdate handler
-- Stored on the frame so it can be set/cleared via SetScript.
-- ============================================================

local DURATION_UPDATE_INTERVAL = 0.1

local function DurationOnUpdate(frame, elapsed)
	local icon = frame._iconRef
	if(not icon) then return end

	icon._durationElapsed = (icon._durationElapsed or 0) + elapsed
	if(icon._durationElapsed < DURATION_UPDATE_INTERVAL) then return end
	icon._durationElapsed = 0

	local remaining = icon._expirationTime - GetTime()
	if(remaining <= 0) then
		icon.duration:SetText('')
		icon._durationActive = false
		frame:SetScript('OnUpdate', nil)
		return
	end

	icon.duration:SetText(F.FormatDuration(remaining))
end

-- ============================================================
-- Icon methods
-- ============================================================

local IconMethods = {}

--- Set the displayed spell/aura data on this icon.
--- @param spellID number
--- @param iconTexture number|string Texture ID or path
--- @param duration number Duration in seconds (may be a secret value)
--- @param expirationTime number Expiration GetTime() value (may be a secret value)
--- @param stacks number Stack count
--- @param dispelType string|nil Dispel/debuff type ('Magic', 'Curse', etc.)
function IconMethods:SetSpell(spellID, iconTexture, duration, expirationTime, stacks, dispelType)
	-- Texture
	if(self._displayType == C.IconDisplay.COLORED_SQUARE) then
		local colorKey = (dispelType and dispelType ~= '') and dispelType or 'none'
		local color = DEBUFF_TYPE_COLORS[colorKey] or DEBUFF_TYPE_COLORS['none']
		self.texture:SetColorTexture(color[1], color[2], color[3])
	else
		-- SpellIcon (default)
		if(iconTexture) then
			self.texture:SetTexture(iconTexture)
		elseif(spellID) then
			local tex
			if(C_Spell and C_Spell.GetSpellInfo) then
				local info = C_Spell.GetSpellInfo(spellID)
				if(info) then tex = info.iconID end
			elseif(GetSpellInfo) then
				local _, _, icon = GetSpellInfo(spellID)
				tex = icon
			end
			self.texture:SetTexture(tex)
		end
	end

	-- Cooldown swipe OR vertical depletion
	if(self._displayType == C.IconDisplay.COLORED_SQUARE and self._depletionBar) then
		self:SetDepletion(duration, expirationTime)
	elseif(self._config.showCooldown and self.cooldown) then
		self:SetCooldown(duration, expirationTime)
	end

	-- Stacks
	if(self._config.showStacks) then
		self:SetStacks(stacks)
	end

	-- Duration text
	if(self._config.showDuration and self.duration) then
		local durationSafe = F.IsValueNonSecret(duration)
		local expirationSafe = F.IsValueNonSecret(expirationTime)
		if(not durationSafe or not expirationSafe or duration == 0) then
			self.duration:SetText('')
			self._durationActive = false
			self._frame:SetScript('OnUpdate', nil)
		else
			self._expirationTime = expirationTime
			self._durationActive = true
			self._durationElapsed = 0
			local remaining = expirationTime - GetTime()
			if(remaining > 0) then
				self.duration:SetText(F.FormatDuration(remaining))
				self._frame:SetScript('OnUpdate', DurationOnUpdate)
			else
				self.duration:SetText('')
				self._durationActive = false
				self._frame:SetScript('OnUpdate', nil)
			end
		end
	end

	self._frame:Show()
end

--- Switch between SpellIcon and ColoredSquare display modes.
--- @param displayType string C.IconDisplay.SPELL_ICON or C.IconDisplay.COLORED_SQUARE
function IconMethods:SetDisplayType(displayType)
	self._displayType = displayType
end

--- Update the cooldown swipe animation.
--- Uses SetCooldownFromDurationObject when available for secret-safe display.
--- @param duration number
--- @param expirationTime number
function IconMethods:SetCooldown(duration, expirationTime)
	if(not self.cooldown) then return end

	local durationSafe = F.IsValueNonSecret(duration)
	local expirationSafe = F.IsValueNonSecret(expirationTime)

	if(not durationSafe or not expirationSafe) then
		-- Secret values: use object-based API if available
		if(self.cooldown.SetCooldownFromDurationObject) then
			-- TODO: verify LuaDurationObject creation API for cooldown secret-safe path
			-- Would need a LuaDurationObject — skip if we cannot create one
			self.cooldown:Clear()
		else
			self.cooldown:Clear()
		end
		return
	end

	if(duration and duration > 0 and expirationTime and expirationTime > 0) then
		local startTime = expirationTime - duration
		self.cooldown:SetCooldown(startTime, duration)
	else
		self.cooldown:Clear()
	end
end

--- Show/update stack count text. Hidden when stacks <= 1.
--- @param count number|nil
function IconMethods:SetStacks(count)
	if(not self.stacks) then return end
	if(count and count > 1) then
		self.stacks:SetText(count)
		self.stacks:Show()
	else
		self.stacks:SetText('')
		self.stacks:Hide()
	end
end

--- Start the vertical depletion animation.
--- @param duration number
--- @param expirationTime number
function IconMethods:SetDepletion(duration, expirationTime)
	if(not self._depletionBar) then return end
	local durationSafe = F.IsValueNonSecret(duration)
	local expirationSafe = F.IsValueNonSecret(expirationTime)

	if(not durationSafe or not expirationSafe or duration == 0) then
		self._depletionBar:SetValue(1)
		self._depletionBar:Hide()
		return
	end

	self._depletionBar:Show()
	self._depletionDuration = duration
	self._depletionExpiration = expirationTime
	self._frame:SetScript('OnUpdate', function(f, elapsed)
		local icon = f._iconRef
		if(not icon or not icon._depletionBar) then return end
		local remaining = icon._depletionExpiration - GetTime()
		if(remaining <= 0) then
			icon._depletionBar:SetValue(0)
			f:SetScript('OnUpdate', nil)
			return
		end
		icon._depletionBar:SetValue(remaining / icon._depletionDuration)
	end)
end

--- Clear and hide this icon, stopping any active OnUpdate.
function IconMethods:Clear()
	self.texture:SetTexture(nil)
	if(self.cooldown) then
		self.cooldown:Clear()
	end
	if(self.stacks) then
		self.stacks:SetText('')
		self.stacks:Hide()
	end
	if(self.duration) then
		self.duration:SetText('')
	end
	if(self._depletionBar) then
		self._depletionBar:SetValue(1)
		self._depletionBar:Hide()
	end
	self._durationActive = false
	self._frame:SetScript('OnUpdate', nil)
	self._frame:Hide()
end

--- Show the icon frame.
function IconMethods:Show()
	self._frame:Show()
end

--- Hide the icon frame.
function IconMethods:Hide()
	self._frame:Hide()
end

--- Set the position of this icon's frame (passthrough to SetPoint).
--- @param ... any SetPoint arguments
function IconMethods:SetPoint(...)
	self._frame:SetPoint(...)
end

--- Clear all points on the frame.
function IconMethods:ClearAllPoints()
	self._frame:ClearAllPoints()
end

--- Return the underlying frame (for parenting/anchoring).
--- @return Frame
function IconMethods:GetFrame()
	return self._frame
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a single Icon indicator primitive.
--- @param parent Frame
--- @param size number Pixel size (width = height)
--- @param config table { displayType, showCooldown, showStacks, showDuration }
--- @return table icon
function F.Indicators.Icon.Create(parent, size, config)
	config = config or {}
	local displayType  = config.displayType  or C.IconDisplay.SPELL_ICON
	local showCooldown = config.showCooldown ~= false  -- default true
	local showStacks   = config.showStacks   ~= false  -- default true
	local showDuration = config.showDuration ~= false  -- default true

	-- Container frame
	local frame = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(frame, size, size)
	frame:Hide()

	-- Back-reference so OnUpdate can reach the icon table
	-- (assigned below after icon table is built)

	-- 1. Icon texture
	local texture = frame:CreateTexture(nil, 'ARTWORK')
	texture:SetAllPoints(frame)
	-- Trim default icon border
	texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- 2. Cooldown frame
	local cooldown
	if(showCooldown) then
		cooldown = CreateFrame('Cooldown', nil, frame, 'CooldownFrameTemplate')
		cooldown:SetAllPoints(frame)
		cooldown:SetDrawBling(false)
		cooldown:SetDrawEdge(false)
		cooldown:SetHideCountdownNumbers(true)
	end

	-- 2a. Vertical depletion bar (for ColoredSquare mode)
	local depletionBar
	if(displayType == C.IconDisplay.COLORED_SQUARE) then
		depletionBar = CreateFrame('StatusBar', nil, frame)
		depletionBar:SetAllPoints(frame)
		depletionBar:SetOrientation('VERTICAL')
		depletionBar:SetFillStyle('REVERSE')  -- depletes from top
		depletionBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
		depletionBar:SetMinMaxValues(0, 1)
		depletionBar:SetValue(1)
		depletionBar:Hide()
		-- Don't create the CooldownFrame when in ColoredSquare mode
		cooldown = nil
	end

	-- 3. Stack count text (bottom-right)
	local stacksText
	if(showStacks) then
		stacksText = Widgets.CreateFontString(frame, C.Font.sizeSmall, C.Colors.textActive)
		stacksText:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 1, 0)
		stacksText:Hide()
	end

	-- 4. Duration text (bottom-left)
	local durationText
	if(showDuration) then
		durationText = Widgets.CreateFontString(frame, C.Font.sizeSmall, C.Colors.textActive)
		durationText:SetPoint('BOTTOM', frame, 'BOTTOM', 0, 0)
	end

	-- Build icon object
	local icon = {
		_frame        = frame,
		_config       = {
			showCooldown = showCooldown,
			showStacks   = showStacks,
			showDuration = showDuration,
		},
		_displayType  = displayType,
		_durationActive  = false,
		_durationElapsed = 0,
		_expirationTime  = 0,

		_depletionBar        = depletionBar,
		_depletionDuration   = 0,
		_depletionExpiration = 0,

		texture  = texture,
		cooldown = cooldown,
		stacks   = stacksText,
		duration = durationText,
	}

	-- Apply methods
	for k, v in next, IconMethods do
		icon[k] = v
	end

	-- Allow DurationOnUpdate to reach icon via frame._iconRef
	frame._iconRef = icon

	return icon
end
