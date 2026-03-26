local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Health = {}

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
	config.smooth             = config.smooth ~= false             -- default true
	config.customColor        = config.customColor or { 0.2, 0.8, 0.2 }
	config.gradientColor1     = config.gradientColor1 or { 0.2, 0.8, 0.2 }
	config.gradientThreshold1 = config.gradientThreshold1 or 95
	config.gradientColor2     = config.gradientColor2 or { 0.9, 0.6, 0.1 }
	config.gradientThreshold2 = config.gradientThreshold2 or 50
	config.gradientColor3     = config.gradientColor3 or { 0.8, 0.1, 0.1 }
	config.gradientThreshold3 = config.gradientThreshold3 or 5
	config.lossColorMode      = config.lossColorMode or 'dark'    -- 'dark', 'class', 'custom'
	config.lossCustomColor    = config.lossCustomColor or { 0.15, 0.15, 0.15 }
	config.showText           = config.showText or false
	config.textFormat         = config.textFormat or 'percent'
	config.fontSize           = config.fontSize or C.Font.sizeSmall
	config.textAnchor         = config.textAnchor or 'CENTER'
	config.textAnchorX        = config.textAnchorX or 0
	config.textAnchorY        = config.textAnchorY or 0
	config.outline            = config.outline or ''
	config.shadow             = (config.shadow == nil) and true or config.shadow
	config.attachedToName     = config.attachedToName or false
	config.healPrediction     = config.healPrediction ~= false

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
	bg:SetAllPoints(health)
	bg:SetTexture([[Interface\BUTTONS\WHITE8x8]])
	local bgC = C.Colors.background
	bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

	-- --------------------------------------------------------
	-- Color mode
	-- --------------------------------------------------------

	if(config.colorMode == 'class') then
		health.colorClass    = true
		health.colorReaction = true
	end
	-- 'dark', 'gradient', and 'custom' are handled in PostUpdate

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
	-- 'class' loss color is handled in PostUpdate

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
			text:SetPoint(ap, health, ap, config.textAnchorX, config.textAnchorY)
			-- Store for live config updates
			text._anchorPoint = ap
			text._anchorX     = config.textAnchorX
			text._anchorY     = config.textAnchorY
		end
		health.text = text
	end

	-- --------------------------------------------------------
	-- PostUpdate: custom color, threshold override, text formatting
	-- --------------------------------------------------------

	health.PostUpdate = function(h, unit, cur, max)
		-- Guard against secret values before Lua arithmetic.
		-- The bar itself handles secrets natively via SetValue().
		if(not F.IsValueNonSecret(cur) or not F.IsValueNonSecret(max)) then
			if(h.text) then h.text:SetText('') end
			return
		end

		local pct = (max > 0) and (cur / max) or 1

		-- ── Bar color ─────────────────────────────────────
		if(config.colorMode == 'dark') then
			h:SetStatusBarColor(0.25, 0.25, 0.25)
		elseif(config.colorMode == 'custom') then
			h:SetStatusBarColor(unpack(config.customColor))
		elseif(config.colorMode == 'gradient') then
			-- 3-color gradient: interpolate between configured colors/thresholds
			local t1 = (config.gradientThreshold1 or 95) / 100
			local t2 = (config.gradientThreshold2 or 50) / 100
			local t3 = (config.gradientThreshold3 or 5) / 100
			local c1 = config.gradientColor1 or { 0.2, 0.8, 0.2 }
			local c2 = config.gradientColor2 or { 0.9, 0.6, 0.1 }
			local c3 = config.gradientColor3 or { 0.8, 0.1, 0.1 }

			local r, g, b
			if(pct >= t1) then
				r, g, b = c1[1], c1[2], c1[3]
			elseif(pct >= t2) then
				local t = (pct - t2) / (t1 - t2)
				r = c2[1] + (c1[1] - c2[1]) * t
				g = c2[2] + (c1[2] - c2[2]) * t
				b = c2[3] + (c1[3] - c2[3]) * t
			elseif(pct >= t3) then
				local t = (pct - t3) / (t2 - t3)
				r = c3[1] + (c2[1] - c3[1]) * t
				g = c3[2] + (c2[2] - c3[2]) * t
				b = c3[3] + (c2[3] - c3[3]) * t
			else
				r, g, b = c3[1], c3[2], c3[3]
			end
			h:SetStatusBarColor(r, g, b)
		end
		-- 'class' is handled by oUF's built-in colorClass/colorReaction

		-- ── Dead state: dark grey ─────────────────────────
		if(UnitIsDeadOrGhost(unit)) then
			h:SetStatusBarColor(0.2, 0.2, 0.2)
		end

		-- ── Loss color (background) ───────────────────────
		if(config.lossColorMode == 'class' and h._bg) then
			local _, class = UnitClass(unit)
			if(class) then
				local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
				if(cc) then
					h._bg:SetVertexColor(cc.r * 0.3, cc.g * 0.3, cc.b * 0.3, 1)
				end
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
	-- Heal Prediction (uses UnitHealPredictionCalculator in 12.0.1)
	-- --------------------------------------------------------

	if(config.healPrediction) then
		-- Safe feature detection: check if the type exists before creating.
		-- NEVER call CreateFrame with an unverified type — it throws on invalid types.
		local hasHealCalc = false
		local healCalcFrame = nil

		-- Only attempt creation if we have evidence the type exists
		if(type(UnitHealPredictionCalculator) ~= 'nil') then
			hasHealCalc = true
		elseif(C_Widget and C_Widget.IsFrameWidget) then
			-- Alternative check via C_Widget API
			hasHealCalc = C_Widget.IsFrameWidget('UnitHealPredictionCalculator')
		end

		local calculator
		if(hasHealCalc) then
			calculator = CreateFrame('UnitHealPredictionCalculator')
			-- The calculator provides clamped heal/absorb values
			-- that work with secret values natively
		end

		-- Prediction bars for visual display
		local myBar = self:CreateTexture(nil, 'OVERLAY')
		myBar:SetTexture([[Interface\BUTTONS\WHITE8x8]])
		myBar:SetVertexColor(0, 0.8, 0.2, 0.4)

		local otherBar = self:CreateTexture(nil, 'OVERLAY')
		otherBar:SetTexture([[Interface\BUTTONS\WHITE8x8]])
		otherBar:SetVertexColor(0, 0.6, 0.2, 0.3)

		local absorbBar = self:CreateTexture(nil, 'OVERLAY')
		absorbBar:SetTexture([[Interface\BUTTONS\WHITE8x8]])
		absorbBar:SetVertexColor(1, 0.8, 0, 0.4)

		self.HealthPrediction = {
			myBar = myBar,
			otherBar = otherBar,
			absorbBar = absorbBar,
			maxOverflow = 1.05,
			_calculator = calculator,
		}
	end

	-- --------------------------------------------------------
	-- Assign to oUF — activates the Health element
	-- --------------------------------------------------------

	self.Health = health
end
