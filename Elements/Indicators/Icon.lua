local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Icon = {}

-- ============================================================
-- Duration/depletion driven by C-level APIs (SetTimerDuration,
-- SetCooldownFromDurationObject). Color progression + threshold
-- handled by shared IconTicker module.
-- ============================================================

-- ============================================================
-- Icon methods
-- ============================================================

local IconMethods = {}

--- Set the displayed spell/aura data on this icon.
--- @param unit string|nil Unit token
--- @param auraInstanceID number|nil Aura instance ID
--- @param spellID number
--- @param iconTexture number|string Texture ID or path
--- @param duration number Duration in seconds (may be a secret value)
--- @param expirationTime number Expiration GetTime() value (may be a secret value)
--- @param stacks number Stack count
function IconMethods:SetSpell(unit, auraInstanceID, spellID, iconTexture, duration, expirationTime, stacks)
	local mdBefore = F.MemDiag.Enter()
	-- Texture
	if(self._displayType == C.IconDisplay.COLORED_SQUARE) then
		-- Per-spell color first, then base indicator color
		local sc = self._spellColors and self._spellColors[spellID]
		if(sc) then
			self.texture:SetColorTexture(sc[1], sc[2], sc[3], 1)
		elseif(self._config.color) then
			local color = self._config.color
			self.texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
		end
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

	-- Stacks
	if(self._config.showStacks) then
		self:SetStacks(stacks)
	end

	-- Get DurationObject
	local mdDur = F.MemDiag.Enter()
	local durationObj
	if(unit and auraInstanceID) then
		durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
	else
		durationObj = self._manualDurObj
	end
	self._durationObj = durationObj
	F.MemDiag.Leave('element:Icon.SetSpell.getDuration', mdDur)

	-- Depletion bar
	if(self._depletionBar) then
		if(durationObj and not durationObj:IsZero()) then
			self._depletionBar:SetTimerDuration(durationObj, nil, Enum.StatusBarTimerDirection.ElapsedTime)
			self._depletionBar:Show()
		else
			self._depletionBar:SetValue(0)
			self._depletionBar:Hide()
		end
	end

	-- Duration countdown via Cooldown frame
	if(self._cooldown) then
		local mdCD = F.MemDiag.Enter()
		if(durationObj and not durationObj:IsZero()) then
			self._cooldown:SetCooldownFromDurationObject(durationObj)

			-- Reparent and style Blizzard's countdown text once (lazy creation),
			-- then re-apply anchor after every cooldown set (Blizzard re-centers it).
			local cdText = self._cooldown.GetCountdownFontString and self._cooldown:GetCountdownFontString()
			if(cdText) then
				if(not self._countdownReparented) then
					cdText:SetParent(self._textOverlay)
					local df = self._durationFont
					if(df) then
						local fontFace = F.Media.GetActiveFont()
						cdText:SetFont(fontFace, df.size, df.outline)
						if(df.shadow == false) then
							cdText:SetShadowOffset(0, 0)
						else
							cdText:SetShadowOffset(1, -1)
						end
					end
					self._countdownReparented = true
				end
				-- Re-apply position after every cooldown set (Blizzard resets to CENTER)
				cdText:ClearAllPoints()
				local df = self._durationFont
				if(df) then
					cdText:SetPoint(df.anchor or 'BOTTOM', self._textOverlay, df.anchor or 'BOTTOM', df.xOffset or 0, df.yOffset or 0)
				end
				self._cdText = cdText

				-- Initial paint — skip repeat renders of the same aura.
				-- IconTicker owns ongoing color updates; this block only
				-- bootstraps so new auras don't show white cdText before the
				-- first ticker tick. On a refresh of the same aura (same ID,
				-- new duration), color may lag up to one ticker interval.
				local mdEval = F.MemDiag.Enter()
				if(auraInstanceID == nil or self._lastPaintedAuraID ~= auraInstanceID) then
					self._lastPaintedAuraID = auraInstanceID

					-- Apply initial color so first frame isn't white
					if(self._colorCurve and durationObj) then
						local color = durationObj:EvaluateRemainingPercent(self._colorCurve)
						cdText:SetTextColor(color:GetRGBA())
					end

					-- Apply initial threshold so first frame doesn't flash
					if(self._thresholdCurve and durationObj) then
						local vis = durationObj:EvaluateRemainingPercent(self._thresholdCurve)
						local _, _, _, a = vis:GetRGBA()
						if(F.IsValueNonSecret(a)) then
							self._cooldown:SetHideCountdownNumbers(a <= 0.5)
						end
					end
				end
				F.MemDiag.Leave('element:Icon.SetSpell.evaluate', mdEval)
			end

			-- Register with shared ticker if color/threshold curves exist
			if(self._colorCurve or self._thresholdCurve) then
				F.Indicators.IconTicker_Register(self)
			end
		else
			self._cooldown:Clear()
			F.Indicators.IconTicker_Unregister(self)
		end
		F.MemDiag.Leave('element:Icon.SetSpell.cooldown', mdCD)
	end

	-- Glow (auto-start when glowType is configured and not 'None')
	if(self._glowType and self._glowType ~= 'None') then
		self:StartGlow(self._glowColor, self._glowType, self._glowConfig)
	end

	self._frame:Show()
	F.MemDiag.Leave('element:Icon.SetSpell', mdBefore)
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

--- Set up a manual DurationObject for preview/manual use.
--- @param duration number
--- @param expirationTime number
function IconMethods:SetDepletion(duration, expirationTime)
	if(not duration or duration <= 0) then
		self._manualDurObj = nil
		return
	end
	if(not self._manualDurObj) then
		self._manualDurObj = CreateLuaDurationObject()
	end
	local startTime = expirationTime - duration
	self._manualDurObj:SetTimeFromStart(startTime, duration)
end

--- Clear and hide this icon.
function IconMethods:Clear()
	self.texture:SetTexture(nil)
	if(self.stacks) then
		self.stacks:SetText('')
		self.stacks:Hide()
	end
	if(self._depletionBar) then
		self._depletionBar:SetValue(0)
		self._depletionBar:Hide()
	end
	if(self._cooldown) then
		self._cooldown:Clear()
	end
	self:StopGlow()
	self._durationObj = nil
	self._lastPaintedAuraID = nil
	F.Indicators.IconTicker_Unregister(self)
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
--- @param config table { displayType, showStacks, durationMode, durationFont, stackFont, spellColors, iconWidth, iconHeight }
--- @return table icon
function F.Indicators.Icon.Create(parent, size, config)
	config = config or {}
	local displayType  = config.displayType  or C.IconDisplay.SPELL_ICON
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
	--    so the black bg shows as a border.
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
		stacksText:SetPoint(sfAnchor, textOverlay, sfAnchor, sf.xOffset or 0, sf.yOffset or 0)
		stacksText:Hide()
	end

	-- 5. Cooldown frame for Blizzard countdown text (no swipe)
	local cooldown
	local durationColorCurve
	local thresholdCurve
	if(showDuration) then
		cooldown = CreateFrame('Cooldown', nil, frame, 'CooldownFrameTemplate')
		cooldown:SetAllPoints(frame)
		cooldown:SetDrawSwipe(false)
		cooldown:SetDrawEdge(false)
		cooldown:SetDrawBling(false)
		cooldown:SetHideCountdownNumbers(false)
		cooldown:SetFrameLevel((depletionBar and depletionBar:GetFrameLevel() or frame:GetFrameLevel()) + 2)

		-- Color progression curve
		local df = config.durationFont or {}
		if(df.colorProgression) then
			local startColor = df.progressionStart or { 0, 1, 0 }
			local midColor   = df.progressionMid   or { 1, 1, 0 }
			local endColor   = df.progressionEnd    or { 1, 0, 0 }
			durationColorCurve = F.Indicators.CreateDurationColorCurve(startColor, midColor, endColor)
		end

		-- Threshold curve
		thresholdCurve = F.Indicators.GetThresholdCurve(durationMode)
	end

	-- Build icon object
	local icon = {
		_frame        = frame,
		_config       = {
			showStacks = showStacks,
			color      = config.color,
		},
		_displayType     = displayType,
		_durationMode    = durationMode,
		_durationFont    = config.durationFont,
		_spellColors     = config.spellColors,

		_depletionBar    = depletionBar,
		_cooldown        = cooldown,
		_textOverlay     = textOverlay,
		_colorCurve      = durationColorCurve,
		_thresholdCurve  = thresholdCurve,
		_durationObj     = nil,
		_cdText          = nil,
		_countdownReparented = false,

		_glowType   = config.glowType,
		_glowColor  = config.glowColor,
		_glowConfig = config.glowConfig,

		texture  = texture,
		stacks   = stacksText,
	}

	-- Apply methods
	for k, v in next, IconMethods do
		icon[k] = v
	end

	return icon
end
