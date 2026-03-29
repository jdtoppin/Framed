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
		if(icon.duration) then
			icon.duration:SetText('')
		end
		icon._durationActive = false
		frame:SetScript('OnUpdate', nil)
		return
	end

	if(icon.duration) then
		local show = F.Indicators.ShouldShowDuration(icon._durationMode, remaining, icon._totalDuration or 0)
		if(show) then
			icon.duration:SetText(F.FormatDuration(remaining))
			icon.duration:Show()
		else
			icon.duration:Hide()
		end
	end
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

	-- Store total duration for ShouldShowDuration
	self._totalDuration = duration

	-- Depletion fill overlay
	if(self._depletionBar) then
		self:SetDepletion(duration, expirationTime)
	end

	-- Stacks
	if(self._config.showStacks) then
		self:SetStacks(stacks)
	end

	-- Per-spell color (ColoredSquare mode)
	if(self._displayType == C.IconDisplay.COLORED_SQUARE and self._spellColors) then
		local sc = self._spellColors[spellID]
		if(sc) then
			self.texture:SetColorTexture(sc[1], sc[2], sc[3], 1)
		end
	end

	-- Duration text
	if(self.duration) then
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
				local show = F.Indicators.ShouldShowDuration(self._durationMode, remaining, duration)
				if(show) then
					self.duration:SetText(F.FormatDuration(remaining))
					self.duration:Show()
				else
					self.duration:Hide()
				end
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

--- Start the depletion fill animation.
--- Value goes from 0 (full duration remaining, no overlay) to 1 (expired, fully covered).
--- @param duration number
--- @param expirationTime number
function IconMethods:SetDepletion(duration, expirationTime)
	if(not self._depletionBar) then return end
	local durationSafe = F.IsValueNonSecret(duration)
	local expirationSafe = F.IsValueNonSecret(expirationTime)

	if(not durationSafe or not expirationSafe or duration == 0) then
		self._depletionBar:SetValue(0)
		self._depletionBar:Hide()
		return
	end

	self._depletionBar:Show()
	self._depletionDuration = duration
	self._depletionExpiration = expirationTime

	-- Initial value
	local remaining = expirationTime - GetTime()
	if(remaining > 0) then
		self._depletionBar:SetValue(1 - (remaining / duration))
	else
		self._depletionBar:SetValue(1)
	end

	self._frame:SetScript('OnUpdate', function(f, elapsed)
		local icon = f._iconRef
		if(not icon or not icon._depletionBar) then return end
		local rem = icon._depletionExpiration - GetTime()
		if(rem <= 0) then
			icon._depletionBar:SetValue(1)
			f:SetScript('OnUpdate', nil)
			return
		end
		icon._depletionBar:SetValue(1 - (rem / icon._depletionDuration))
	end)
end

--- Clear and hide this icon, stopping any active OnUpdate.
function IconMethods:Clear()
	self.texture:SetTexture(nil)
	if(self.stacks) then
		self.stacks:SetText('')
		self.stacks:Hide()
	end
	if(self.duration) then
		self.duration:SetText('')
	end
	if(self._depletionBar) then
		self._depletionBar:SetValue(0)
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

--- Resize the icon frame and re-anchor the texture.
--- @param w number
--- @param h number|nil defaults to w
function IconMethods:SetSize(w, h)
	Widgets.SetSize(self._frame, w, h or w)
	self.texture:SetAllPoints(self._frame)
end

--- Start a glow effect on this icon.
--- @param color table|nil
--- @param glowType string|nil
--- @param glowConfig table|nil
function IconMethods:StartGlow(color, glowType, glowConfig)
	if(not self._glow) then
		self._glow = F.Indicators.Glow.Create(self._frame)
	end
	self._glow:Start(color, glowType, glowConfig)
end

--- Stop any active glow effect on this icon.
function IconMethods:StopGlow()
	if(self._glow) then
		self._glow:Stop()
	end
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a single Icon indicator primitive.
--- @param parent Frame
--- @param size number|nil Pixel size (width = height); overridden by iconWidth/iconHeight in config
--- @param config table { displayType, showCooldown, showStacks, durationMode, durationFont, stackFont, spellColors, iconWidth, iconHeight }
--- @return table icon
function F.Indicators.Icon.Create(parent, size, config)
	config = config or {}
	local displayType  = config.displayType  or C.IconDisplay.SPELL_ICON
	local showCooldown = config.showCooldown ~= false  -- default true
	local showStacks   = config.showStacks   ~= false  -- default true
	local durationMode = config.durationMode or 'Always'
	local showDuration = durationMode ~= 'Never'

	local iconWidth  = config.iconWidth  or size or 14
	local iconHeight = config.iconHeight or size or 14

	-- Container frame
	local frame = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(frame, iconWidth, iconHeight)
	frame:Hide()

	-- Back-reference so OnUpdate can reach the icon table
	-- (assigned below after icon table is built)

	-- 1. Icon texture
	local texture = frame:CreateTexture(nil, 'ARTWORK')
	texture:SetAllPoints(frame)
	-- Trim default icon border
	texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- 2. Depletion bar overlay (dark fill for SpellIcon, white fill for ColoredSquare)
	local depletionBar
	if(showCooldown) then
		local fillDirection = config.fillDirection or 'topToBottom'
		depletionBar = CreateFrame('StatusBar', nil, frame)
		depletionBar:SetAllPoints(frame)

		-- Orientation and fill direction
		if(fillDirection == 'topToBottom') then
			depletionBar:SetOrientation('VERTICAL')
			depletionBar:SetReverseFill(true)
		elseif(fillDirection == 'bottomToTop') then
			depletionBar:SetOrientation('VERTICAL')
			depletionBar:SetReverseFill(false)
		elseif(fillDirection == 'leftToRight') then
			depletionBar:SetOrientation('HORIZONTAL')
			depletionBar:SetReverseFill(false)
		elseif(fillDirection == 'rightToLeft') then
			depletionBar:SetOrientation('HORIZONTAL')
			depletionBar:SetReverseFill(true)
		end

		depletionBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
		depletionBar:SetStatusBarColor(0, 0, 0, 0.6)
		depletionBar:SetMinMaxValues(0, 1)
		depletionBar:SetValue(0)
		depletionBar:Hide()
	end

	-- 3. Stack count text (bottom-right)
	local stacksText
	if(showStacks) then
		local sf = config.stackFont or {}
		stacksText = Widgets.CreateFontString(frame, sf.size or C.Font.sizeSmall, C.Colors.textActive)
		stacksText:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 1, 0)
		stacksText:Hide()
	end

	-- 4. Duration text (bottom)
	local durationText
	if(showDuration) then
		local df = config.durationFont or {}
		durationText = Widgets.CreateFontString(frame, df.size or C.Font.sizeSmall, C.Colors.textActive)
		durationText:SetPoint('BOTTOM', frame, 'BOTTOM', 0, 0)
	end

	-- Build icon object
	local icon = {
		_frame        = frame,
		_config       = {
			showCooldown = showCooldown,
			showStacks   = showStacks,
		},
		_displayType  = displayType,
		_durationMode    = durationMode,
		_spellColors     = config.spellColors,
		_totalDuration   = 0,
		_durationActive  = false,
		_durationElapsed = 0,
		_expirationTime  = 0,

		_depletionBar        = depletionBar,
		_depletionDuration   = 0,
		_depletionExpiration = 0,

		texture  = texture,
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
