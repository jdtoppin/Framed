local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Icon = {}

-- Wrap C.Colors.dispel with a 'none' fallback without mutating the shared constant table
local DEBUFF_TYPE_COLORS = setmetatable({ none = C.Colors.dispel.Physical }, { __index = C.Colors.dispel })

-- ============================================================
-- Combined OnUpdate handler for depletion fill + duration text
-- ============================================================

local DURATION_UPDATE_INTERVAL = 0.1

local function IconOnUpdate(frame, elapsed)
	local icon = frame._iconRef
	if(not icon) then return end

	local now = GetTime()
	local needsUpdate = false

	-- Depletion fill update
	if(icon._depletionActive and icon._depletionBar) then
		local rem = icon._depletionExpiration - now
		if(rem <= 0) then
			icon._depletionBar:SetValue(1)
			icon._depletionActive = false
		else
			icon._depletionBar:SetValue(1 - (rem / icon._depletionDuration))
			needsUpdate = true
		end
	end

	-- Duration text update (throttled)
	if(icon._durationActive and icon.duration) then
		icon._durationElapsed = (icon._durationElapsed or 0) + elapsed
		if(icon._durationElapsed >= DURATION_UPDATE_INTERVAL) then
			icon._durationElapsed = 0
			local remaining = icon._expirationTime - now
			if(remaining <= 0) then
				icon.duration:SetText('')
				icon._durationActive = false
			else
				local show = F.Indicators.ShouldShowDuration(icon._durationMode, remaining, icon._totalDuration or 0)
				if(show) then
					icon.duration:SetText(F.FormatDuration(remaining))
					icon.duration:Show()

					-- Color progression (green → yellow → red)
					if(icon._durationColorCurve and icon._totalDuration and icon._totalDuration > 0) then
						local pct = remaining / icon._totalDuration
						local color = icon._durationColorCurve:Evaluate(pct)
						icon.duration:SetTextColor(color:GetRGB())
					end
				else
					icon.duration:Hide()
				end
				needsUpdate = true
			end
		else
			needsUpdate = true
		end
	end

	if(not needsUpdate) then
		frame:SetScript('OnUpdate', nil)
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
		else
			self._expirationTime = expirationTime
			self._durationElapsed = 0
			local remaining = expirationTime - GetTime()
			if(remaining > 0) then
				self._durationActive = true
				local show = F.Indicators.ShouldShowDuration(self._durationMode, remaining, duration)
				if(show) then
					self.duration:SetText(F.FormatDuration(remaining))
					self.duration:Show()

					-- Initial color progression
					if(self._durationColorCurve and duration > 0) then
						local pct = remaining / duration
						local color = self._durationColorCurve:Evaluate(pct)
						self.duration:SetTextColor(color:GetRGB())
					end
				else
					self.duration:Hide()
				end
			else
				self.duration:SetText('')
				self._durationActive = false
			end
		end
	end

	-- Start combined OnUpdate if either depletion or duration is active
	if(self._depletionActive or self._durationActive) then
		self._frame:SetScript('OnUpdate', IconOnUpdate)
	else
		self._frame:SetScript('OnUpdate', nil)
	end

	-- Glow (auto-start when glowType is configured and not 'None')
	if(self._glowType and self._glowType ~= 'None') then
		self:StartGlow(self._glowColor, self._glowType, self._glowConfig)
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
		self._depletionActive = false
		return
	end

	self._depletionBar:Show()
	self._depletionDuration = duration
	self._depletionExpiration = expirationTime
	self._depletionActive = true

	-- Initial value
	local remaining = expirationTime - GetTime()
	if(remaining > 0) then
		self._depletionBar:SetValue(1 - (remaining / duration))
	else
		self._depletionBar:SetValue(1)
		self._depletionActive = false
	end
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
	self:StopGlow()
	self._durationActive = false
	self._depletionActive = false
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
	-- Texture is point-anchored with inset; re-anchor not needed on resize
end

--- Start a glow effect on this icon.
--- @param color table|nil
--- @param glowType string|nil
--- @param glowConfig table|nil
function IconMethods:StartGlow(color, glowType, glowConfig)
	if(not self._glow) then
		self._glow = F.Indicators.BorderGlow.Create(self._frame, { borderGlowMode = 'Glow' })
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

	-- Container frame (BackdropTemplate for pixel-perfect border)
	local frame = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(frame, iconWidth, iconHeight)
	frame:Hide()

	-- 1. Border via backdrop bg. The bgFile masks overlapping content
	--    when icons use negative spacing. Content inset by 1 physical pixel
	--    so the black bg shows as a border (matching how Cell handles block indicators).
	local scale = parent:GetEffectiveScale()
	local pf = 768.0 / select(2, GetPhysicalScreenSize())
	local P = pf / scale  -- 1 physical pixel for both edge and content inset
	frame:SetBackdrop({
		bgFile = [[Interface\BUTTONS\WHITE8x8]],
	})
	frame:SetBackdropColor(0, 0, 0, 1)

	-- 1a. Icon texture (inset by 1px so black bg shows as border)
	local texture = frame:CreateTexture(nil, 'ARTWORK')
	texture:SetPoint('TOPLEFT', frame, 'TOPLEFT', P, -P)
	texture:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -P, P)
	-- Trim default icon border
	texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	if(displayType == C.IconDisplay.COLORED_SQUARE) then
		texture:SetTexCoord(0, 1, 0, 1)  -- no trim needed for solid color
	end

	-- 2. Depletion bar overlay (inset matches icon; extra 1px on trailing edge
	--    so the fill visibly stops inside the colored area, not at the border)
	local depletionBar
	if(showCooldown) then
		local fillDirection = config.fillDirection or 'topToBottom'
		depletionBar = CreateFrame('StatusBar', nil, frame)

		if(fillDirection == 'topToBottom') then
			depletionBar:SetPoint('TOPLEFT', frame, 'TOPLEFT', P, -P)
			depletionBar:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -P, P + 1)
			depletionBar:SetOrientation('VERTICAL')
			depletionBar:SetReverseFill(true)
		elseif(fillDirection == 'bottomToTop') then
			depletionBar:SetPoint('TOPLEFT', frame, 'TOPLEFT', P, -(P + 1))
			depletionBar:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -P, P)
			depletionBar:SetOrientation('VERTICAL')
			depletionBar:SetReverseFill(false)
		elseif(fillDirection == 'leftToRight') then
			depletionBar:SetPoint('TOPLEFT', frame, 'TOPLEFT', P, -P)
			depletionBar:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -(P + 1), P)
			depletionBar:SetOrientation('HORIZONTAL')
			depletionBar:SetReverseFill(false)
		elseif(fillDirection == 'rightToLeft') then
			depletionBar:SetPoint('TOPLEFT', frame, 'TOPLEFT', P + 1, -P)
			depletionBar:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -P, P)
			depletionBar:SetOrientation('HORIZONTAL')
			depletionBar:SetReverseFill(true)
		end

		depletionBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
		depletionBar:SetStatusBarColor(0, 0, 0, 0.8)
		depletionBar:SetMinMaxValues(0, 1)
		depletionBar:SetValue(0)

		-- Spark line at the fill boundary (ADD blend for glow effect)
		local barTex = depletionBar:GetStatusBarTexture()
		local spark = depletionBar:CreateTexture(nil, 'BORDER')
		spark:SetColorTexture(1, 1, 1, 1)
		spark:SetBlendMode('ADD')

		if(fillDirection == 'topToBottom') then
			spark:SetHeight(P)
			spark:SetPoint('TOPLEFT', barTex, 'BOTTOMLEFT')
			spark:SetPoint('TOPRIGHT', barTex, 'BOTTOMRIGHT')
		elseif(fillDirection == 'bottomToTop') then
			spark:SetHeight(P)
			spark:SetPoint('BOTTOMLEFT', barTex, 'TOPLEFT')
			spark:SetPoint('BOTTOMRIGHT', barTex, 'TOPRIGHT')
		elseif(fillDirection == 'leftToRight') then
			spark:SetWidth(P)
			spark:SetPoint('TOPLEFT', barTex, 'TOPRIGHT')
			spark:SetPoint('BOTTOMLEFT', barTex, 'BOTTOMRIGHT')
		elseif(fillDirection == 'rightToLeft') then
			spark:SetWidth(P)
			spark:SetPoint('TOPRIGHT', barTex, 'TOPLEFT')
			spark:SetPoint('BOTTOMRIGHT', barTex, 'BOTTOMLEFT')
		end
		depletionBar:Hide()
	end

	-- 3. Text overlay frame — renders above the depletion bar
	local textOverlay
	if(showStacks or showDuration) then
		textOverlay = CreateFrame('Frame', nil, frame)
		textOverlay:SetAllPoints(frame)
		textOverlay:SetFrameLevel((depletionBar and depletionBar:GetFrameLevel() or frame:GetFrameLevel()) + 1)
	end

	-- 4. Stack count text (configurable anchor, font, outline, shadow)
	local stacksText
	if(showStacks) then
		local sf = config.stackFont or {}
		local sfAnchor = sf.anchor or 'BOTTOMRIGHT'
		stacksText = Widgets.CreateFontString(textOverlay, sf.size or C.Font.sizeSmall, C.Colors.textActive, sf.outline or '', sf.shadow)
		stacksText:SetPoint(sfAnchor, textOverlay, sfAnchor, sf.offsetX or 0, sf.offsetY or 0)
		stacksText:Hide()
	end

	-- 5. Duration text (configurable anchor, font, outline, shadow)
	local durationText
	local durationColorCurve
	if(showDuration) then
		local df = config.durationFont or {}
		local dfAnchor = df.anchor or 'BOTTOM'
		durationText = Widgets.CreateFontString(textOverlay, df.size or C.Font.sizeSmall, C.Colors.textActive, df.outline or '', df.shadow)
		durationText:SetPoint(dfAnchor, textOverlay, dfAnchor, df.offsetX or 0, df.offsetY or 0)

		-- Color progression curve (green → yellow → red based on remaining %)
		if(df.colorProgression) then
			local startColor = df.progressionStart or { 0, 1, 0 }   -- green (full)
			local midColor   = df.progressionMid   or { 1, 1, 0 }   -- yellow (half)
			local endColor   = df.progressionEnd    or { 1, 0, 0 }   -- red (expired)
			durationColorCurve = C_CurveUtil.CreateColorCurve()
			durationColorCurve:AddPoint(0, CreateColor(endColor[1], endColor[2], endColor[3]))
			durationColorCurve:AddPoint(0.5, CreateColor(midColor[1], midColor[2], midColor[3]))
			durationColorCurve:AddPoint(1, CreateColor(startColor[1], startColor[2], startColor[3]))
		end
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
		_durationColorCurve = durationColorCurve,
		_spellColors     = config.spellColors,
		_totalDuration   = 0,
		_durationActive  = false,
		_durationElapsed = 0,
		_expirationTime  = 0,

		_depletionBar        = depletionBar,
		_depletionDuration   = 0,
		_depletionExpiration = 0,
		_depletionActive     = false,

		_glowType   = config.glowType,
		_glowColor  = config.glowColor,
		_glowConfig = config.glowConfig,

		texture  = texture,
		stacks   = stacksText,
		duration = durationText,
	}

	-- Apply methods
	for k, v in next, IconMethods do
		icon[k] = v
	end

	-- Allow IconOnUpdate to reach icon via frame._iconRef
	frame._iconRef = icon

	return icon
end
