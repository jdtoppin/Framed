local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Power = {}

-- ============================================================
-- Power Element Setup
-- ============================================================

--- Configure oUF's built-in Power element on a unit frame.
--- @param self Frame  The oUF unit frame
--- @param width number  Bar width in UI units
--- @param height number  Bar height in UI units
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.Power.Setup(self, width, height, config)

	-- --------------------------------------------------------
	-- Config defaults
	-- --------------------------------------------------------

	config = config or {}
	config.height      = config.height or 2               -- thin power bar default
	config.showText    = config.showText or false
	config.textFormat  = config.textFormat or 'current'   -- 'current', 'percent', 'deficit', 'current-max', 'none'
	config.fontSize    = config.fontSize or C.Font.sizeSmall
	config.textAnchor  = config.textAnchor or 'CENTER'
	config.textAnchorX = config.textAnchorX or 0
	config.textAnchorY = config.textAnchorY or 0
	config.outline     = config.outline or ''
	config.shadow      = (config.shadow == nil) and true or config.shadow
	config.powerFilter = config.powerFilter or nil        -- table of {MANA=true, ENERGY=false, ...} or nil for all

	-- --------------------------------------------------------
	-- Power bar (via Widgets.CreateStatusBar)
	-- Use config.height as the bar height so the power bar can
	-- be thinner than the enclosing health bar.
	-- --------------------------------------------------------

	local power = Widgets.CreateStatusBar(self, width, config.height)

	-- Position the wrapper below the health bar wrapper (caller
	-- is responsible for SetPoint if desired; default to TOPLEFT).
	power._wrapper:SetPoint('TOPLEFT', self, 'TOPLEFT', 0, 0)

	-- --------------------------------------------------------
	-- Color: per-power-type overrides with oUF auto-color fallback
	-- --------------------------------------------------------

	power._customColors = config.customColors or nil

	power.UpdateColor = function(self, event, unit)
		local p = self.Power
		local powerType, powerToken = UnitPowerType(unit)
		local cc = p._customColors and p._customColors[powerToken]
		if(cc) then
			p:SetStatusBarColor(cc[1], cc[2], cc[3])
		else
			local color = self.colors.power[powerToken] or self.colors.power[powerType]
			if(color) then
				p:SetStatusBarColor(color:GetRGB())
			end
		end
	end

	-- --------------------------------------------------------
	-- Background texture behind the power bar fill
	-- --------------------------------------------------------

	local bg = power:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetTexture([[Interface\BUTTONS\WHITE8x8]])
	local bgC = C.Colors.background
	bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

	-- --------------------------------------------------------
	-- Power text (optional)
	-- --------------------------------------------------------

	if(config.showText) then
		local text = Widgets.CreateFontString(power, config.fontSize, C.Colors.textActive, config.outline, config.shadow)
		local ap = config.textAnchor
		text:SetPoint(ap, power._wrapper, ap, config.textAnchorX + 1, config.textAnchorY)
		-- Store for live config updates
		text._anchorPoint = ap
		text._anchorX     = config.textAnchorX
		text._anchorY     = config.textAnchorY
		power.text = text
	end

	-- --------------------------------------------------------
	-- PostUpdate: power filter and text formatting
	-- --------------------------------------------------------

	power.PostUpdate = function(p, unit, cur, max)
		-- Power type filtering
		if(config.powerFilter) then
			-- UnitPowerType returns numeric token and string token
			local _, powerToken = UnitPowerType(unit)
			if(powerToken and config.powerFilter[powerToken] == false) then
				p._wrapper:Hide()
				return
			else
				p._wrapper:Show()
			end
		end

		-- Guard against secret values before Lua arithmetic.
		-- The bar itself handles secrets natively via SetValue().
		if(not F.IsValueNonSecret(cur) or not F.IsValueNonSecret(max)) then
			if(p.text) then p.text:SetText('') end
			return
		end

		-- Power text formatting
		if(config.showText and p.text) then
			local fmt = config.textFormat
			if(fmt == 'none' or max <= 0) then
				p.text:SetText('')
			elseif(fmt == 'percent') then
				local pct = math.floor(cur / max * 100 + 0.5)
				p.text:SetText(pct .. '%')
			elseif(fmt == 'current') then
				p.text:SetText(F.AbbreviateNumber(cur))
			elseif(fmt == 'deficit') then
				local deficit = max - cur
				if(deficit <= 0) then
					p.text:SetText('')
				else
					p.text:SetText('-' .. F.AbbreviateNumber(deficit))
				end
			elseif(fmt == 'current-max') then
				p.text:SetText(F.AbbreviateNumber(cur) .. '/' .. F.AbbreviateNumber(max))
			else
				p.text:SetText('')
			end
		end
	end

	-- --------------------------------------------------------
	-- Assign to oUF — activates the Power element
	-- --------------------------------------------------------

	self.Power = power
end
