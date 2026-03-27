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
	if(element.colorDisconnected and not UnitIsConnected(unit)) then
		color = self.colors.disconnected
	elseif(element.colorTapping and not UnitPlayerControlled(unit) and UnitIsTapDenied(unit)) then
		color = self.colors.tapped
	elseif(element.colorThreat and not UnitPlayerControlled(unit)) then
		local status = UnitThreatSituation('player', unit)
		if(status and F.IsValueNonSecret(status)) then
			color = self.colors.threat[status]
		end
	elseif(element.colorClass and (UnitIsPlayer(unit) or UnitInPartyIsAI(unit))) then
		local _, class = UnitClass(unit)
		color = self.colors.class[class]
	elseif(element.colorReaction and UnitReaction(unit, 'player')) then
		color = self.colors.reaction[UnitReaction(unit, 'player')]
	end

	if(color) then
		element:SetStatusBarColor(color:GetRGB())
	end

	if(element.PostUpdateColor) then
		element:PostUpdateColor(unit, color)
	end
end

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
		health.colorReaction = true  -- fallback for non-player units in group

		if(config.colorMode == 'class') then
			health.colorClass = true
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
		else
			-- dark / custom — no oUF color concept, override UpdateColor
			health.UpdateColor = function() end
		end
	end

	-- --------------------------------------------------------
	-- Loss color (background behind the health bar fill)
	-- --------------------------------------------------------

	health._bg = bg
	if(config.lossColorMode == 'dark') then
		bg:SetVertexColor(0.15, 0.15, 0.15, 1)
	elseif(config.lossColorMode == 'custom') then
		local lc = config.lossCustomColor
		bg:SetVertexColor(lc[1], lc[2], lc[3], 1)
	end
	-- 'class' and 'gradient' loss colors are handled in PostUpdate

	-- --------------------------------------------------------
	-- Smooth interpolation
	-- --------------------------------------------------------

	health:SetSmooth(config.smooth)

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
		-- Guard against secret values before Lua arithmetic.
		-- The bar itself handles secrets natively via SetValue().
		if(not F.IsValueNonSecret(cur) or not F.IsValueNonSecret(max)) then
			if(h.text) then h.text:SetText('') end
			return
		end

		local pct = (max > 0) and (cur / max) or 1

		-- ── Bar color (only for modes oUF can't handle) ──
		if(not h._isNpcFrame) then
			if(h._colorMode == 'dark') then
				h:SetStatusBarColor(0.25, 0.25, 0.25)
			elseif(h._colorMode == 'custom') then
				h:SetStatusBarColor(unpack(h._customColor))
			end
			-- 'class' and 'gradient' are handled by oUF's UpdateColor
		end

		-- ── Dead state: dark grey ─────────────────────────
		if(UnitIsDeadOrGhost(unit)) then
			h:SetStatusBarColor(0.2, 0.2, 0.2)
		end

		-- ── Prediction bar positioning ───────────────────
		-- PostUpdate runs outside the restricted CallMethod context,
		-- so SetPoint calls work here. On first run, we also set up
		-- the container positioning that was deferred from creation.
		local container = h._predictionContainer
		if(container) then
			-- Deferred container setup: anchor it inside the wrapper
			-- on the first PostUpdate call (outside restricted context).
			if(not container._positioned) then
				container:SetPoint('TOPLEFT', 1, -1)
				container:SetPoint('BOTTOMRIGHT', -1, 1)
				container._positioned = true
			end

			-- Use wrapper width minus 2px inset instead of container:GetWidth()
			-- because container may not have been laid out yet on the first call.
			local barWidth = (h._wrapper:GetWidth() or 0) - 2
			if(barWidth <= 0) then return end
			local fillWidth = barWidth * pct

			if(h.HealingAll) then
				h.HealingAll:SetWidth(barWidth)
				h.HealingAll:ClearAllPoints()
				h.HealingAll:SetPoint('TOP')
				h.HealingAll:SetPoint('BOTTOM')
				h.HealingAll:SetPoint('LEFT', fillWidth, 0)
			end

			if(h.DamageAbsorb) then
				local absorbOffset = fillWidth
				if(h.HealingAll and h.values) then
					local allHeal = h.values:GetIncomingHeals()
					if(F.IsValueNonSecret(allHeal) and max > 0) then
						absorbOffset = absorbOffset + barWidth * (allHeal / max)
					end
				end
				absorbOffset = math.min(absorbOffset, barWidth)
				h.DamageAbsorb:SetWidth(barWidth)
				h.DamageAbsorb:ClearAllPoints()
				h.DamageAbsorb:SetPoint('TOP')
				h.DamageAbsorb:SetPoint('BOTTOM')
				h.DamageAbsorb:SetPoint('LEFT', absorbOffset, 0)
			end

			if(h.HealAbsorb) then
				h.HealAbsorb:SetWidth(barWidth)
				h.HealAbsorb:ClearAllPoints()
				h.HealAbsorb:SetPoint('TOP')
				h.HealAbsorb:SetPoint('BOTTOM')
				-- Anchor RIGHT to parent RIGHT with offset so RIGHT edge
				-- lands at fillWidth from parent LEFT:
				-- parent_RIGHT is at barWidth, so offset = fillWidth - barWidth
				h.HealAbsorb:SetPoint('RIGHT', fillWidth - barWidth, 0)
			end

			-- Position over-absorb indicators (also deferred from creation)
			if(h.OverDamageAbsorbIndicator and not h.OverDamageAbsorbIndicator._positioned) then
				h.OverDamageAbsorbIndicator:SetPoint('TOP')
				h.OverDamageAbsorbIndicator:SetPoint('BOTTOM')
				h.OverDamageAbsorbIndicator:SetPoint('RIGHT', 4, 0)
				h.OverDamageAbsorbIndicator._positioned = true
			end

			if(h.OverHealAbsorbIndicator and not h.OverHealAbsorbIndicator._positioned) then
				h.OverHealAbsorbIndicator:SetPoint('TOP')
				h.OverHealAbsorbIndicator:SetPoint('BOTTOM')
				h.OverHealAbsorbIndicator:SetPoint('LEFT', -4, 0)
				h.OverHealAbsorbIndicator._positioned = true
			end
		end

		-- Dispellable overlay tracks health fill width
		if(h._dispelOverlay) then
			local bw = (h._wrapper:GetWidth() or 0) - 2
			if(bw > 0) then
				h._dispelOverlay:SetWidth(math.max(bw * pct, 0.001))
			end
		end

		-- ── Loss color (background) ───────────────────────
		if(h._bg) then
			if(h._lossColorMode == 'class') then
				local _, class = UnitClass(unit)
				if(class) then
					local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
					if(cc) then
						h._bg:SetVertexColor(cc.r * 0.3, cc.g * 0.3, cc.b * 0.3, 1)
					end
				end
			elseif(h._lossColorMode == 'gradient') then
				local lt1 = (h._lossGradientThreshold1 or 95) / 100
				local lt2 = (h._lossGradientThreshold2 or 50) / 100
				local lt3 = (h._lossGradientThreshold3 or 5) / 100
				local lc1 = h._lossGradientColor1 or { 0.1, 0.4, 0.1 }
				local lc2 = h._lossGradientColor2 or { 0.4, 0.25, 0.05 }
				local lc3 = h._lossGradientColor3 or { 0.4, 0.05, 0.05 }

				local lr, lg, lb
				if(pct >= lt1) then
					lr, lg, lb = lc1[1], lc1[2], lc1[3]
				elseif(pct >= lt2) then
					local t = (pct - lt2) / (lt1 - lt2)
					lr = lc2[1] + (lc1[1] - lc2[1]) * t
					lg = lc2[2] + (lc1[2] - lc2[2]) * t
					lb = lc2[3] + (lc1[3] - lc2[3]) * t
				elseif(pct >= lt3) then
					local t = (pct - lt3) / (lt2 - lt3)
					lr = lc3[1] + (lc2[1] - lc3[1]) * t
					lg = lc3[2] + (lc2[2] - lc3[2]) * t
					lb = lc3[3] + (lc2[3] - lc3[3]) * t
				else
					lr, lg, lb = lc3[1], lc3[2], lc3[3]
				end
				h._bg:SetVertexColor(lr, lg, lb, 1)
			elseif(h._lossColorMode == 'dark') then
				h._bg:SetVertexColor(0.15, 0.15, 0.15, 1)
			elseif(h._lossColorMode == 'custom') then
				local lc = h._lossCustomColor or { 0.15, 0.15, 0.15 }
				h._bg:SetVertexColor(lc[1], lc[2], lc[3], 1)
			end
		end

		-- Health text formatting
		if((config.showText or h._attachedToName) and h.text) then
			local fmt = config.textFormat
			local prefix = h._attachedToName and ' - ' or ''
			if(fmt == 'none' or max <= 0) then
				h.text:SetText('')
			elseif(fmt == 'percent') then
				local pct = math.floor(cur / max * 100 + 0.5)
				h.text:SetText(prefix .. pct .. '%')
			elseif(fmt == 'current') then
				h.text:SetText(prefix .. F.AbbreviateNumber(cur))
			elseif(fmt == 'deficit') then
				local deficit = max - cur
				if(deficit <= 0) then
					h.text:SetText('')
				else
					h.text:SetText(prefix .. '-' .. F.AbbreviateNumber(deficit))
				end
			elseif(fmt == 'current-max') then
				h.text:SetText(prefix .. F.AbbreviateNumber(cur) .. '/' .. F.AbbreviateNumber(max))
			else
				h.text:SetText('')
			end
		end
	end

	-- --------------------------------------------------------
	-- Prediction sub-widgets — placed directly on the Health
	-- element using PascalCase names (oUF's non-deprecated API).
	-- oUF's Health Update() drives SetValue/SetAlphaFromBoolean.
	--
	-- IMPORTANT: Party/raid frames spawn via CallMethod from
	-- SecureGroupHeaderTemplate. ALL SetPoint calls inside that
	-- context fail with "Wrong object type" (RestrictedFrames.lua
	-- intercepts them). We create the bars here (so oUF's Enable
	-- can see them and register events) but do ZERO SetPoint calls.
	-- All positioning is deferred to PostUpdate, which runs outside
	-- the restricted context when health events fire.
	-- --------------------------------------------------------

	local needsPrediction = config.healPrediction or config.damageAbsorb
		or config.healAbsorb or config.overAbsorb

	if(needsPrediction) then
		-- Container Frame inside the wrapper — NO SetPoint here.
		-- PostUpdate will position it on first run.
		local wrapper = health._wrapper
		local container = CreateFrame('Frame', nil, wrapper)
		container:SetFrameLevel(health:GetFrameLevel() + 1)
		health._predictionContainer = container

		if(config.healPrediction) then
			local hc = config.healPredictionColor
			local healBar = CreateFrame('StatusBar', nil, container)
			healBar:SetStatusBarTexture([[Interface\AddOns\Framed\Media\Textures\Gradient_Linear_Right]])
			healBar:SetStatusBarColor(hc[1], hc[2], hc[3], hc[4] or 0.4)
			health.HealingAll = healBar
		end

		if(config.damageAbsorb) then
			local dc = config.damageAbsorbColor
			local absorbBar = CreateFrame('StatusBar', nil, container)
			absorbBar:SetStatusBarTexture([[Interface\AddOns\Framed\Media\Textures\Stripe]])
			absorbBar:SetStatusBarColor(dc[1], dc[2], dc[3], dc[4] or 0.6)
			health.DamageAbsorb = absorbBar
		end

		if(config.overAbsorb) then
			local overAbsorb = container:CreateTexture(nil, 'OVERLAY')
			overAbsorb:SetTexture([[Interface\AddOns\Framed\Media\Textures\StaticGlow]])
			overAbsorb:SetBlendMode('ADD')
			overAbsorb:SetWidth(8)
			overAbsorb:SetAlpha(0)
			health.OverDamageAbsorbIndicator = overAbsorb
		end

		if(config.healAbsorb) then
			local hac = config.healAbsorbColor
			local healAbsorbBar = CreateFrame('StatusBar', nil, container)
			healAbsorbBar:SetStatusBarTexture([[Interface\AddOns\Framed\Media\Textures\Stripe]])
			healAbsorbBar:SetStatusBarColor(hac[1], hac[2], hac[3], hac[4] or 0.5)
			healAbsorbBar:SetReverseFill(true)
			health.HealAbsorb = healAbsorbBar

			local overHealAbsorb = container:CreateTexture(nil, 'OVERLAY')
			overHealAbsorb:SetTexture([[Interface\RaidFrame\Absorb-Overabsorb]])
			overHealAbsorb:SetBlendMode('ADD')
			overHealAbsorb:SetWidth(8)
			overHealAbsorb:SetAlpha(0)
			health.OverHealAbsorbIndicator = overHealAbsorb
		end

		health.incomingHealOverflow = 1.05
	end

	-- --------------------------------------------------------
	-- Assign to oUF — activates the Health element
	-- --------------------------------------------------------

	self.Health = health
end
