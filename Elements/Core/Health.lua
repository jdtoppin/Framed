local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Health = {}

-- Unit types whose health bar color is fully managed by oUF's UpdateColor
-- (disconnected → tapped → threat → class → reaction chain).
-- These frames do NOT expose color mode options in the settings UI.
local NPC_FRAME_TYPES = {
	target       = true,
	targettarget = true,
	focus        = true,
	pet          = true,
	boss         = true,
}

-- ============================================================
-- Helpers
-- ============================================================

--- Build a C_CurveUtil color curve from 3 color/threshold pairs.
--- @param c1 table  Color at threshold 1 (highest %)
--- @param t1 number Threshold 1 (0–100)
--- @param c2 table  Color at threshold 2
--- @param t2 number Threshold 2 (0–100)
--- @param c3 table  Color at threshold 3 (lowest %)
--- @param t3 number Threshold 3 (0–100)
local function buildCurveTable(c1, t1, c2, t2, c3, t3)
	return {
		[t3 / 100] = CreateColor(c3[1], c3[2], c3[3]),
		[t2 / 100] = CreateColor(c2[1], c2[2], c2[3]),
		[t1 / 100] = CreateColor(c1[1], c1[2], c1[3]),
	}
end

-- ============================================================
-- UpdateColor override for NPC frames
-- Replicates oUF's UpdateColor chain but handles
-- UnitThreatSituation returning a secret value in TWW.
-- ============================================================

local function NpcUpdateColor(self, event, unit)
	if(not unit or self.unit ~= unit) then return end
	local element = self.Health

	local color

	-- Disconnected / tapped are definitive states — short-circuit.
	if(element.colorDisconnected and not UnitIsConnected(unit)) then
		color = self.colors.disconnected
	elseif(element.colorTapping and not UnitPlayerControlled(unit) and UnitIsTapDenied(unit)) then
		color = self.colors.tapped
	end

	-- Threat: only apply if we can read the status (non-secret).
	-- Separated from the elseif chain so a secret threat value does NOT
	-- prevent the class/reaction fallback from running.
	if(not color and element.colorThreat and not UnitPlayerControlled(unit)) then
		local status = UnitThreatSituation('player', unit)
		if(status and F.IsValueNonSecret(status)) then
			color = self.colors.threat[status]
		end
	end

	-- Class (players / AI party members) → reaction fallback
	if(not color) then
		if(element.colorClass and (UnitIsPlayer(unit) or UnitInPartyIsAI(unit))) then
			local _, class = UnitClass(unit)
			if(class) then
				color = self.colors.class[class]
			end
		elseif(element.colorReaction and UnitReaction(unit, 'player')) then
			color = self.colors.reaction[UnitReaction(unit, 'player')]
		end
	end

	-- Dead override: grey regardless of class/reaction
	if(UnitIsDeadOrGhost(unit)) then
		element:SetStatusBarColor(0.2, 0.2, 0.2)
	elseif(color) then
		element:SetStatusBarColor(color:GetRGB())
	end

	if(element.PostUpdateColor) then
		element:PostUpdateColor(unit, color)
	end
end

--- Exposed for LiveUpdate/StyleBuilder to restore on NPC frames
--- after clearing UpdateColor.
F.Elements.Health.NpcUpdateColor = NpcUpdateColor

-- ============================================================
-- Health Element Setup
-- ============================================================

--- Configure oUF's built-in Health element on a unit frame.
--- @param self Frame  The oUF unit frame
--- @param width number  Bar width in UI units
--- @param height number  Bar height in UI units
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.Health.Setup(self, width, height, config)

	-- --------------------------------------------------------
	-- Config defaults
	-- --------------------------------------------------------

	config = config or {}
	config.colorMode          = config.colorMode or 'class'       -- 'class', 'dark', 'gradient', 'custom'
	config.colorThreat        = config.colorThreat or false
	config.smooth             = config.smooth ~= false             -- default true
	config.customColor        = config.customColor or { 0.2, 0.8, 0.2 }
	config.gradientColor1     = config.gradientColor1 or { 0.2, 0.8, 0.2 }
	config.gradientThreshold1 = config.gradientThreshold1 or 95
	config.gradientColor2     = config.gradientColor2 or { 0.9, 0.6, 0.1 }
	config.gradientThreshold2 = config.gradientThreshold2 or 50
	config.gradientColor3     = config.gradientColor3 or { 0.8, 0.1, 0.1 }
	config.gradientThreshold3 = config.gradientThreshold3 or 5
	config.lossColorMode      = config.lossColorMode or 'dark'    -- 'class', 'dark', 'gradient', 'custom'
	config.lossCustomColor    = config.lossCustomColor or { 0.15, 0.15, 0.15 }
	config.lossGradientColor1     = config.lossGradientColor1 or { 0.1, 0.4, 0.1 }
	config.lossGradientThreshold1 = config.lossGradientThreshold1 or 95
	config.lossGradientColor2     = config.lossGradientColor2 or { 0.4, 0.25, 0.05 }
	config.lossGradientThreshold2 = config.lossGradientThreshold2 or 50
	config.lossGradientColor3     = config.lossGradientColor3 or { 0.4, 0.05, 0.05 }
	config.lossGradientThreshold3 = config.lossGradientThreshold3 or 5
	config.showText           = config.showText or false
	config.textFormat         = config.textFormat or 'percent'
	config.fontSize           = config.fontSize or C.Font.sizeSmall
	config.textAnchor         = config.textAnchor or 'CENTER'
	config.textAnchorX        = config.textAnchorX or 0
	config.textAnchorY        = config.textAnchorY or 0
	config.outline            = config.outline or ''
	config.shadow             = (config.shadow == nil) and true or config.shadow
	config.attachedToName     = config.attachedToName or false
	config.healPrediction      = config.healPrediction ~= false  -- incoming heal bars
	config.healPredictionMode  = config.healPredictionMode or 'all' -- 'all', 'player', 'other'
	config.healPredictionColor = config.healPredictionColor or { 0.6, 0.6, 0.6, 0.4 }
	config.damageAbsorb        = config.damageAbsorb ~= false    -- shield/absorb bar
	config.damageAbsorbColor   = config.damageAbsorbColor or { 1, 1, 1, 0.6 }
	config.healAbsorb          = config.healAbsorb ~= false      -- anti-heal overlay
	config.healAbsorbColor     = config.healAbsorbColor or { 0.7, 0.1, 0.1, 0.5 }
	config.overAbsorb          = config.overAbsorb ~= false      -- overshield indicator

	local unitType = self._framedUnitType
	local isNpcFrame = unitType and NPC_FRAME_TYPES[unitType]

	-- --------------------------------------------------------
	-- Health bar (via Widgets.CreateStatusBar)
	-- StatusBar._wrapper is the backdrop frame; oUF needs the bar itself.
	-- --------------------------------------------------------

	local health = Widgets.CreateStatusBar(self, width, height)

	-- Push the health fill texture to a lower sub-layer so prediction
	-- overlays (absorbs, incoming heals) render on top.
	health:GetStatusBarTexture():SetDrawLayer('ARTWORK', -7)

	-- Position the wrapper (backdrop frame) on the unit frame
	health._wrapper:SetPoint('TOPLEFT', self, 'TOPLEFT', 0, 0)

	-- --------------------------------------------------------
	-- Background texture behind the health bar fill
	-- Sits inside the wrapper, below the bar texture
	-- --------------------------------------------------------

	local bg = health:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetTexture([[Interface\BUTTONS\WHITE8x8]])
	local bgC = C.Colors.background
	bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

	-- --------------------------------------------------------
	-- Color mode — oUF flag setup
	-- NPC frames: use oUF's full UpdateColor chain (disconnected,
	--   tapped, threat, class, reaction) with no override.
	-- Player/group frames: configure flags based on colorMode,
	--   only override UpdateColor for dark/custom (flat colors
	--   that have no oUF concept).
	-- --------------------------------------------------------

	health.colorDisconnected = true  -- always show disconnected state

	if(isNpcFrame) then
		-- Full oUF chain: disconnected → tapped → threat → class → reaction
		-- Override UpdateColor to handle UnitThreatSituation secret values
		health.colorTapping  = true
		health.colorThreat   = true
		health.colorClass    = true
		health.colorReaction = true
		health.UpdateColor   = NpcUpdateColor
	else
		-- Player/group: selective flags
		health.colorThreat   = config.colorThreat

		if(config.colorMode == 'class') then
			health.colorClass    = true
			health.colorReaction = true  -- fallback for non-player units in group
		elseif(config.colorMode == 'gradient') then
			health.colorSmooth = true
			-- Per-frame colors table so we don't pollute oUF's shared colors
			if(not rawget(self, 'colors')) then
				self.colors = setmetatable({}, { __index = oUF.colors })
			end
			self.colors.health = oUF:CreateColor(0.2, 0.8, 0.2)
			self.colors.health:SetCurve(buildCurveTable(
				config.gradientColor1, config.gradientThreshold1,
				config.gradientColor2, config.gradientThreshold2,
				config.gradientColor3, config.gradientThreshold3
			))
		elseif(config.colorMode == 'dark') then
			health.UpdateColor = function(self)
				self.Health:SetStatusBarColor(0.25, 0.25, 0.25)
			end
		elseif(config.colorMode == 'custom') then
			health.UpdateColor = function(self)
				local cc = self.Health._customColor or { 0.2, 0.8, 0.2 }
				self.Health:SetStatusBarColor(cc[1], cc[2], cc[3])
			end
		end
	end

	-- --------------------------------------------------------
	-- Loss color (background behind the health bar fill)
	-- --------------------------------------------------------

	health._bg = bg
	health._lossColorMode = config.lossColorMode
	health._lossCustomColor = config.lossCustomColor

	if(config.lossColorMode == 'dark') then
		bg:SetVertexColor(0.15, 0.15, 0.15, 1)
	elseif(config.lossColorMode == 'custom') then
		local lc = config.lossCustomColor
		bg:SetVertexColor(lc[1], lc[2], lc[3], 1)
	elseif(config.lossColorMode == 'gradient') then
		local curve = C_CurveUtil.CreateColorCurve()
		local curveTable = buildCurveTable(
			config.lossGradientColor1, config.lossGradientThreshold1,
			config.lossGradientColor2, config.lossGradientThreshold2,
			config.lossGradientColor3, config.lossGradientThreshold3
		)
		for x, y in next, curveTable do
			curve:AddPoint(x, y)
		end
		health._lossGradientCurve = curve
	end
	-- 'class' loss color is handled in PostUpdate (needs unit class)

	-- --------------------------------------------------------
	-- Smooth interpolation (oUF passes health.smoothing to SetValue)
	-- --------------------------------------------------------

	if(config.smooth) then
		health.smoothing = Enum.StatusBarInterpolation.ExponentialEaseOut
	else
		health.smoothing = Enum.StatusBarInterpolation.Immediate
	end

	-- --------------------------------------------------------
	-- Health text (optional)
	-- --------------------------------------------------------

	if(config.showText or config.attachedToName) then
		-- Create text on a dedicated overlay so it renders above all bar layers
		local textOverlay = self._textOverlay
		if(not textOverlay) then
			textOverlay = CreateFrame('Frame', nil, self)
			textOverlay:SetAllPoints(self)
			textOverlay:SetFrameLevel(self:GetFrameLevel() + 5)
			self._textOverlay = textOverlay
		end
		local text = Widgets.CreateFontString(textOverlay, config.fontSize, C.Colors.textActive, config.outline, config.shadow)
		if(config.attachedToName) then
			-- Don't anchor here; StyleBuilder will anchor to Name text
			health._attachedToName = true
		else
			local ap = config.textAnchor
			text:SetPoint(ap, health._wrapper, ap, config.textAnchorX + 1, config.textAnchorY)
			-- Store for live config updates
			text._anchorPoint = ap
			text._anchorX     = config.textAnchorX
			text._anchorY     = config.textAnchorY
		end
		health.text = text
	end

	-- Store text state for PostUpdate
	health._textFormat      = config.textFormat
	health._textColorMode   = config.textColorMode or 'white'
	health._textCustomColor = config.textCustomColor

	-- Store mutable color state on the health element for live updates
	health._colorMode      = config.colorMode
	health._customColor    = config.customColor
	health._lossColorMode  = config.lossColorMode
	health._lossCustomColor = config.lossCustomColor
	health._lossGradientColor1     = config.lossGradientColor1
	health._lossGradientThreshold1 = config.lossGradientThreshold1
	health._lossGradientColor2     = config.lossGradientColor2
	health._lossGradientThreshold2 = config.lossGradientThreshold2
	health._lossGradientColor3     = config.lossGradientColor3
	health._lossGradientThreshold3 = config.lossGradientThreshold3
	health._isNpcFrame = isNpcFrame

	-- --------------------------------------------------------
	-- PostUpdate: flat bar colors (dark/custom), loss color, text
	-- --------------------------------------------------------

	health.PostUpdate = function(h, unit, cur, max)
		-- ── Bar color (only for modes oUF can't handle) ──
		-- These use SetStatusBarColor which accepts secret values natively.
		if(not h._isNpcFrame) then
			if(h._colorMode == 'dark') then
				h:SetStatusBarColor(0.25, 0.25, 0.25)
			elseif(h._colorMode == 'custom') then
				h:SetStatusBarColor(unpack(h._customColor))
			end
			-- 'class' and 'gradient' are handled by oUF's UpdateColor
		end

		-- ── Dead state: dark grey ─────────────────────────
		-- NPC frames handle dead in NpcUpdateColor (runs after PostUpdate
		-- via ColorPath) so only non-NPC frames need the override here.
		if(not h._isNpcFrame and UnitIsDeadOrGhost(unit)) then
			h:SetStatusBarColor(0.2, 0.2, 0.2)
		end

		-- ── Loss color (background) ───────────────────────
		-- Uses UnitClass (non-secret) or h.values:EvaluateCurrentHealthPercent
		-- (handles secrets natively), so this runs before the secret guard.
		if(h._bg) then
			if(h._lossColorMode == 'class') then
				local _, class = UnitClass(unit)
				if(class) then
					local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
					if(cc) then
						h._bg:SetVertexColor(cc.r * 0.3, cc.g * 0.3, cc.b * 0.3, 1)
					end
				end
			elseif(h._lossColorMode == 'gradient' and h._lossGradientCurve) then
				local color = h.values:EvaluateCurrentHealthPercent(h._lossGradientCurve)
				if(color) then
					h._bg:SetVertexColor(color:GetRGBA())
				end
			elseif(h._lossColorMode == 'dark') then
				h._bg:SetVertexColor(0.15, 0.15, 0.15, 1)
			elseif(h._lossColorMode == 'custom') then
				local lc = h._lossCustomColor or { 0.15, 0.15, 0.15 }
				h._bg:SetVertexColor(lc[1], lc[2], lc[3], 1)
			end
		end

		-- ── Overshield override ──────────────────────────
		-- oUF's main calculator uses MaximumHealth clamp (for bar display),
		-- so isClamped only fires when shield > maxHealth (extremely rare).
		-- Re-check with default-clamp calculator: isClamped = shield > missing health.
		if(h._overShieldCalc and h.OverDamageAbsorbIndicator) then
			UnitGetDetailedHealPrediction(unit, nil, h._overShieldCalc)
			local _, isClamped = h._overShieldCalc:GetDamageAbsorbs()
			h.OverDamageAbsorbIndicator:SetAlphaFromBoolean(isClamped, 1, 0)
		end

		-- ── Prediction bar positioning (deferred from creation) ──
		-- Dispellable overlay tracks health fill width via C-level safe pct
		if(h._dispelOverlay) then
			local bw = (h._wrapper:GetWidth() or 0) - 2
			if(bw > 0) then
				local safePct = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
				if(F.IsValueNonSecret(safePct)) then
					h._dispelOverlay:SetWidth(math.max(bw * (safePct / 100), 0.001))
				end
			end
		end

		-- Health text formatting — uses secret-safe APIs throughout.
		-- AbbreviateNumbers (C-level) handles secret values from UnitHealth.
		-- UnitHealthPercent (C-level) returns non-secret percentage.
		if(h.text and h.text:IsShown()) then
			local fmt = h._textFormat or config.textFormat
			local prefix = h._attachedToName and ' - ' or ''
			if(fmt == 'none') then
				h.text:SetText('')
			elseif(fmt == 'percent') then
				local pct = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
				h.text:SetText(prefix .. string.format('%d', pct) .. '%')
			elseif(fmt == 'current') then
				h.text:SetText(prefix .. F.AbbreviateNumber(UnitHealth(unit)))
			elseif(fmt == 'deficit') then
				h.text:SetFormattedText('%s-%s', prefix, F.AbbreviateNumber(UnitHealthMissing(unit)))
			elseif(fmt == 'currentMax') then
				h.text:SetText(prefix .. F.AbbreviateNumber(UnitHealth(unit)) .. '/' .. F.AbbreviateNumber(UnitHealthMax(unit)))
			else
				h.text:SetText('')
			end

			-- Text color
			local colorMode = h._textColorMode or 'white'
			if(colorMode == 'class') then
				local _, class = UnitClass(unit)
				if(class) then
					local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
					if(classColor) then
						h.text:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
					end
				end
			elseif(colorMode == 'dark') then
				h.text:SetTextColor(0.25, 0.25, 0.25, 1)
			elseif(colorMode == 'custom') then
				local cc = h._textCustomColor or { 1, 1, 1 }
				h.text:SetTextColor(cc[1], cc[2], cc[3], 1)
			else
				local tc = C.Colors.textActive
				h.text:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
			end

			-- Center the combined Name + Health text as a group.
			-- GetStringWidth() on the health text returns a secret number
			-- (health values are secret) so we measure a hidden proxy
			-- FontString with non-secret representative text instead.
			if(h._attachedToName and self.Name) then
				if(not h._measureProxy) then
					h._measureProxy = (h._wrapper or h):CreateFontString(nil, 'ARTWORK')
					h._measureProxy:Hide()
				end
				local font, size, flags = h.text:GetFont()
				h._measureProxy:SetFont(font, size, flags)

				local proxyStr
				if(fmt == 'percent') then
					-- UnitHealthPercent is C-level and returns non-secret
					local pct = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
					proxyStr = prefix .. string.format('%d', pct) .. '%'
				elseif(fmt == 'currentMax') then
					proxyStr = prefix .. '000k/000k'
				elseif(fmt == 'deficit') then
					proxyStr = prefix .. '-000k'
				else
					proxyStr = prefix .. '000.0k'
				end
				h._measureProxy:SetText(proxyStr)
				local healthW = h._measureProxy:GetStringWidth() or 0

				local gap = 2
				local shift = (gap + healthW) / 2
				if(shift ~= h._lastAttachShift) then
					h._lastAttachShift = shift
					local anchor = h._wrapper or h
					local ap = self.Name._anchorPoint or 'CENTER'
					local baseX = self.Name._anchorX or 0
					local baseY = self.Name._anchorY or 0
					self.Name:ClearAllPoints()
					Widgets.SetPoint(self.Name, ap, anchor, ap, baseX - shift, baseY)
				end
			end
		end
	end

	-- --------------------------------------------------------
	-- Prediction sub-widgets — placed directly on the Health
	-- element using PascalCase names (oUF's Health element API).
	-- oUF's Health Update() drives SetValue/SetAlphaFromBoolean.
	--
	-- Absorb bars use SetAllPoints + SetReverseFill to overlay
	-- the health fill from the right edge inward.
	-- Incoming heal bars use a ClipFrame to clip overflow at the
	-- health bar boundary.
	-- --------------------------------------------------------

	local needsPrediction = config.healPrediction or config.damageAbsorb
		or config.healAbsorb or config.overAbsorb

	if(needsPrediction) then
		local healthBarTexture = health:GetStatusBarTexture()
		health._healBarTexRef = healthBarTexture
		local predWidth = width - 2

		-- Clip frame for forward-fill bars (incoming heals) that extend
		-- right from the fill edge and need clipping at the bar boundary.
		local clipFrame = CreateFrame('Frame', nil, health)
		clipFrame:SetAllPoints(health)
		clipFrame:SetClipsChildren(true)
		clipFrame:SetFrameLevel(health:GetFrameLevel() + 1)

		if(config.healPrediction) then
			local hc = config.healPredictionColor
			local healBar = CreateFrame('StatusBar', nil, clipFrame)
			healBar:SetFrameLevel(health:GetFrameLevel() + 3)
			healBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
			healBar:SetStatusBarColor(hc[1], hc[2], hc[3], hc[4] or 0.4)
			healBar:SetSize(predWidth, height)
			healBar:SetPoint('BOTTOMLEFT', health)
			healBar:SetPoint('LEFT', healthBarTexture, 'RIGHT')
			health._healPredBar = healBar
			local mode = config.healPredictionMode
			if(mode == 'player') then
				health.HealingPlayer = healBar
			elseif(mode == 'other') then
				health.HealingOther = healBar
			else
				health.HealingAll = healBar
			end
		end

		-- Always create absorb bars so live toggles can show/hide them
		local dc = config.damageAbsorbColor
		local absorbBar = CreateFrame('StatusBar', nil, health)
		absorbBar:SetFrameLevel(health:GetFrameLevel() + 2)
		absorbBar:SetStatusBarTexture([[Interface\AddOns\Framed\Media\Textures\Stripe]])
		absorbBar:SetStatusBarColor(dc[1], dc[2], dc[3], dc[4] or 0.6)
		absorbBar:SetAllPoints(health)
		absorbBar:SetReverseFill(true)
		health._damageAbsorbBar = absorbBar

		local overAbsorb = (self._iconOverlay or health._wrapper):CreateTexture(nil, 'OVERLAY')
		overAbsorb:SetTexture([[Interface\AddOns\Framed\Media\Textures\Gradient_Linear_Left]])
		overAbsorb:SetBlendMode('ADD')
		overAbsorb:SetWidth(8)
		overAbsorb:SetAlpha(0)
		overAbsorb:SetPoint('TOP', health)
		overAbsorb:SetPoint('BOTTOM', health)
		overAbsorb:SetPoint('LEFT', health, 'RIGHT')
		health._overDamageAbsorbIndicator = overAbsorb

		if(config.damageAbsorb) then
			health.DamageAbsorb = absorbBar
			health.OverDamageAbsorbIndicator = overAbsorb
		else
			absorbBar:Hide()
			overAbsorb:Hide()
		end

		local hac = config.healAbsorbColor
		local healAbsorbBar = CreateFrame('StatusBar', nil, health)
		healAbsorbBar:SetFrameLevel(health:GetFrameLevel() + 2)
		healAbsorbBar:SetStatusBarTexture([[Interface\AddOns\Framed\Media\Textures\Stripe]])
		healAbsorbBar:SetStatusBarColor(hac[1], hac[2], hac[3], hac[4] or 0.5)
		healAbsorbBar:SetReverseFill(true)
		healAbsorbBar:SetAllPoints(health)
		health._healAbsorbBar = healAbsorbBar

		local overHealAbsorb = (self._iconOverlay or health._wrapper):CreateTexture(nil, 'OVERLAY')
		overHealAbsorb:SetTexture([[Interface\RaidFrame\Absorb-Overabsorb]])
		overHealAbsorb:SetBlendMode('ADD')
		overHealAbsorb:SetWidth(8)
		overHealAbsorb:SetAlpha(0)
		overHealAbsorb:SetPoint('TOP', health)
		overHealAbsorb:SetPoint('BOTTOM', health)
		overHealAbsorb:SetPoint('RIGHT', health, 'LEFT')
		health._overHealAbsorbIndicator = overHealAbsorb

		if(config.healAbsorb) then
			health.HealAbsorb = healAbsorbBar
			health.OverHealAbsorbIndicator = overHealAbsorb
		else
			healAbsorbBar:Hide()
			overHealAbsorb:Hide()
		end

		health.incomingHealOverflow = 1.05

		-- Clamp modes: default clamps absorbs to missing health,
		-- which means absorbs are 0 at full HP.  Use MaximumHealth
		-- so shields are visible regardless of current health.
		health.damageAbsorbClampMode = Enum.UnitDamageAbsorbClampMode.MaximumHealth
		health.healAbsorbClampMode   = Enum.UnitHealAbsorbClampMode.MaximumHealth
		health.incomingHealClampMode  = Enum.UnitIncomingHealClampMode.MaximumHealth

		-- Separate calculator for overshield detection only.
		-- Uses default clamp (missing health) so isClamped triggers when
		-- shield > missing health — the correct "overflow past bar edge" signal.
		-- The main calculator's MaximumHealth clamp only flags shield > maxHealth.
		if(config.overAbsorb and CreateUnitHealPredictionCalculator) then
			health._overShieldCalc = CreateUnitHealPredictionCalculator()
		end
	end

	-- --------------------------------------------------------
	-- Assign to oUF — activates the Health element
	-- --------------------------------------------------------

	self.Health = health
end
