local addonName, Framed = ...
local F = Framed
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

	-- Remove the shared border edge so health and power bars don't
	-- double up their 1px borders. Which edge to remove depends on
	-- whether the power bar sits above or below the health bar.
	local pos = config.position or 'bottom'
	power:ClearAllPoints()
	if(pos == 'top') then
		-- Shared edge is the bottom — extend inner bar down to 0
		power:SetPoint('TOPLEFT',     power._wrapper, 'TOPLEFT',      1, -1)
		power:SetPoint('BOTTOMRIGHT', power._wrapper, 'BOTTOMRIGHT', -1,  0)
	else
		-- Shared edge is the top — extend inner bar up to 0
		power:SetPoint('TOPLEFT',     power._wrapper, 'TOPLEFT',      1,  0)
		power:SetPoint('BOTTOMRIGHT', power._wrapper, 'BOTTOMRIGHT', -1,  1)
	end

	--- Update which border edge is removed based on power position.
	--- Call this when the position changes at runtime.
	--- @param position string 'top' or 'bottom'
	function power.SetSharedEdge(bar, position)
		bar:ClearAllPoints()
		if(position == 'top') then
			bar:SetPoint('TOPLEFT',     bar._wrapper, 'TOPLEFT',      1, -1)
			bar:SetPoint('BOTTOMRIGHT', bar._wrapper, 'BOTTOMRIGHT', -1,  0)
		else
			bar:SetPoint('TOPLEFT',     bar._wrapper, 'TOPLEFT',      1,  0)
			bar:SetPoint('BOTTOMRIGHT', bar._wrapper, 'BOTTOMRIGHT', -1,  1)
		end
	end

	-- Position the wrapper below the health bar wrapper (caller
	-- is responsible for SetPoint if desired; default to TOPLEFT).
	power._wrapper:SetPoint('TOPLEFT', self, 'TOPLEFT', 0, 0)

	-- --------------------------------------------------------
	-- Color: per-power-type overrides with oUF auto-color fallback
	-- --------------------------------------------------------

	power._customColors = config.customColors or nil

	power.UpdateColor = function(frame, event, unit)
		local p = frame.Power
		local powerType, powerToken = UnitPowerType(unit)
		local cc = p._customColors and p._customColors[powerToken]
		if(cc) then
			p:SetStatusBarColor(cc[1], cc[2], cc[3])
		else
			local color = frame.colors.power[powerToken] or frame.colors.power[powerType]
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

		-- Power text formatting — uses secret-safe APIs throughout.
		-- AbbreviateNumbers (C-level) handles secret values from UnitPower.
		-- UnitPowerPercent (C-level) returns non-secret percentage.
		if(p.text and p.text:IsShown()) then
			local powerType = UnitPowerType(unit)
			local fmt = p._textFormat or config.textFormat
			if(fmt == 'none') then
				p.text:SetText('')
			elseif(fmt == 'percent') then
				local pct = UnitPowerPercent(unit, nil, true, CurveConstants.ScaleTo100)
				p.text:SetText(string.format('%d', pct) .. '%')
			elseif(fmt == 'current') then
				p.text:SetText(F.AbbreviateNumber(UnitPower(unit, powerType)))
			elseif(fmt == 'deficit') then
				p.text:SetText('')
			elseif(fmt == 'currentMax') then
				p.text:SetText(F.AbbreviateNumber(UnitPower(unit, powerType)) .. '/' .. F.AbbreviateNumber(UnitPowerMax(unit, powerType)))
			else
				p.text:SetText('')
			end

			-- Text color
			local colorMode = p._textColorMode or 'white'
			if(colorMode == 'class') then
				local _, class = UnitClass(unit)
				if(class) then
					local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
					if(classColor) then
						p.text:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
					end
				end
			elseif(colorMode == 'dark') then
				p.text:SetTextColor(0.25, 0.25, 0.25, 1)
			elseif(colorMode == 'custom') then
				local cc = p._textCustomColor or { 1, 1, 1 }
				p.text:SetTextColor(cc[1], cc[2], cc[3], 1)
			else
				local tc = C.Colors.textActive
				p.text:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
			end
		end
	end

	-- Store text state for PostUpdate
	power._textFormat      = config.textFormat
	power._textColorMode   = config.textColorMode or 'white'
	power._textCustomColor = config.textCustomColor

	-- --------------------------------------------------------
	-- Assign to oUF — activates the Power element
	-- --------------------------------------------------------

	self.Power = power
end
