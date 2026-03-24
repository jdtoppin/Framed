local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Power = {}

-- ============================================================
-- Number Abbreviation Helper
-- ============================================================

--- Abbreviate a number: >= 1M -> '1.2M', >= 1K -> '145K', else raw.
--- @param value number
--- @return string
local function AbbreviateNumber(value)
	if(value >= 1000000) then
		return string.format('%.1fM', value / 1000000)
	elseif(value >= 1000) then
		return string.format('%dK', math.floor(value / 1000 + 0.5))
	else
		return tostring(math.floor(value + 0.5))
	end
end

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
	-- Let oUF auto-color the bar by the unit's power type
	-- --------------------------------------------------------

	power.colorPower = true

	-- --------------------------------------------------------
	-- Background texture behind the power bar fill
	-- --------------------------------------------------------

	local bg = power:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(power)
	bg:SetTexture([[Interface\BUTTONS\WHITE8x8]])
	local bgC = C.Colors.background
	bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1)

	-- --------------------------------------------------------
	-- Power text (optional)
	-- --------------------------------------------------------

	if(config.showText) then
		local text = Widgets.CreateFontString(power, C.Font.sizeSmall, C.Colors.textActive)
		text:SetPoint('CENTER', power, 'CENTER', 0, 0)
		power.text = text
	end

	-- --------------------------------------------------------
	-- PostUpdate: power filter and text formatting
	-- --------------------------------------------------------

	power.PostUpdate = function(p, unit, cur, max)
		-- Power type filtering
		if(config.powerFilter) then
			local powerType = UnitPowerType(unit)   -- returns numeric token
			-- Convert numeric token to string key for table lookup
			local _, powerToken = UnitPowerType(unit)
			if(powerToken and config.powerFilter[powerToken] == false) then
				p._wrapper:Hide()
				return
			else
				p._wrapper:Show()
			end
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
				p.text:SetText(AbbreviateNumber(cur))
			elseif(fmt == 'deficit') then
				local deficit = max - cur
				if(deficit <= 0) then
					p.text:SetText('')
				else
					p.text:SetText('-' .. AbbreviateNumber(deficit))
				end
			elseif(fmt == 'current-max') then
				p.text:SetText(AbbreviateNumber(cur) .. '/' .. AbbreviateNumber(max))
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
