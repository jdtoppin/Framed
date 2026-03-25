local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Debuffs = {}

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedDebuffs
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	-- Filter is 'HARMFUL' so all results are harmful — do not read auraData.isHarmful
	local auraList = {}
	local i = 1
	while(true) do
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if(not auraData) then break end
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			auraList[#auraList + 1] = {
				spellID        = spellId,
				icon           = auraData.icon,
				duration       = auraData.duration,
				expirationTime = auraData.expirationTime,
				stacks         = auraData.applications or 0,
				dispelType     = auraData.dispelName,
			}
		end
		if(#auraList >= element._maxIcons) then break end
		i = i + 1
	end

	element._icons:SetIcons(auraList)
end

-- ============================================================
-- ForceUpdate
-- ============================================================

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

-- ============================================================
-- Enable / Disable
-- ============================================================

local function Enable(self, unit)
	local element = self.FramedDebuffs
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedDebuffs
	if(not element) then return end

	element._icons:Hide()

	self:UnregisterEvent('UNIT_AURA', Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedDebuffs', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create the debuff aura Icons grid on a unit frame.
--- Assigns result to self.FramedDebuffs, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: maxIcons, iconSize, growDirection, displayType, anchor
function F.Elements.Debuffs.Setup(self, config)
	config = config or {}
	config.maxIcons      = config.maxIcons      or 6
	config.iconSize      = config.iconSize      or 14
	config.growDirection = config.growDirection or 'RIGHT'
	config.displayType   = config.displayType   or 'SpellIcon'
	config.anchor        = config.anchor        or { 'BOTTOMLEFT', self, 'BOTTOMLEFT', 2, 2 }

	local icons = F.Indicators.Icons.Create(self, config)

	local container = {
		_icons    = icons,
		_maxIcons = config.maxIcons,
	}

	local a = config.anchor
	icons:SetPoint(a[1], a[2], a[3], a[4] or 0, a[5] or 0)

	self.FramedDebuffs = container
end
