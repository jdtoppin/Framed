local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.PvPIcon = {}

-- ============================================================
-- PvPIcon Element Setup
-- Uses AF's Faction2 textures for a cleaner PvP indicator.
-- ============================================================

local ALLIANCE_TEXTURE = F.Media.GetIcon('Faction2_Alliance')
local HORDE_TEXTURE    = F.Media.GetIcon('Faction2_Horde')

--- Override for oUF's PvPIndicator update.
--- Uses our custom faction textures instead of the Blizzard defaults.
--- @param self Frame  The oUF unit frame
local function Override(self, event, unit)
	if(unit and unit ~= self.unit) then return end

	local element = self.PvPIndicator
	unit = unit or self.unit

	if(element.PreUpdate) then
		element:PreUpdate(unit)
	end

	local status
	local factionGroup = UnitFactionGroup(unit) or 'Neutral'

	if(UnitIsPVPFreeForAll(unit)) then
		status = 'FFA'
	elseif(factionGroup ~= 'Neutral' and UnitIsPVP(unit)) then
		if(unit == 'player' and UnitIsMercenary(unit)) then
			if(factionGroup == 'Horde') then
				factionGroup = 'Alliance'
			elseif(factionGroup == 'Alliance') then
				factionGroup = 'Horde'
			end
		end

		status = factionGroup
	end

	if(status) then
		if(status == 'Alliance') then
			element:SetTexture(ALLIANCE_TEXTURE)
		elseif(status == 'Horde') then
			element:SetTexture(HORDE_TEXTURE)
		else
			-- FFA: fall back to Blizzard FFA texture
			element:SetTexture([[Interface\TargetingFrame\UI-PVP-FFA]])
		end
		element:SetTexCoord(0, 1, 0, 1)
		element:Show()
	else
		element:Hide()
	end

	if(element.PostUpdate) then
		return element:PostUpdate(unit, status)
	end
end

--- Configure oUF's built-in PvPIndicator element on a unit frame.
--- Uses AF's solid faction icons instead of the Blizzard defaults.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.PvPIcon.Setup(self, config)

	-- --------------------------------------------------------
	-- Icon texture
	-- --------------------------------------------------------

	local icon = (self._iconOverlay or self):CreateTexture(nil, 'OVERLAY')
	Widgets.SetSize(icon, config.size, config.size)

	local p = config.point
	Widgets.SetPoint(icon, p[1], p[2], p[3], p[4], p[5])

	-- Use Override to apply our custom textures
	icon.Override = Override

	-- --------------------------------------------------------
	-- Assign to oUF — activates the PvPIndicator element
	-- --------------------------------------------------------

	self.PvPIndicator = icon
end
