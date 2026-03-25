local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Dispellable = {}

-- ============================================================
-- Dispel type configuration
-- ============================================================

-- Priority order: Magic(1) > Curse(2) > Disease(3) > Poison(4)
local DISPEL_PRIORITY = {
	Magic   = 1,
	Curse   = 2,
	Disease = 3,
	Poison  = 4,
}

local DISPEL_COLORS = {
	Magic   = { 0.2, 0.6, 1   },
	Curse   = { 0.6, 0,   1   },
	Disease = { 0.6, 0.4, 0   },
	Poison  = { 0,   0.6, 0.1 },
}

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedDispellable
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local bestType     = nil
	local bestPriority = 999

	-- Filter is 'HARMFUL' so all results are harmful — do not read auraData.isHarmful
	local i = 1
	while(true) do
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if(not auraData) then break end

		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local dispelName = auraData.dispelName
			if(dispelName and DISPEL_PRIORITY[dispelName]) then
				local priority = DISPEL_PRIORITY[dispelName]
				if(priority < bestPriority) then
					bestPriority = priority
					bestType     = dispelName
				end
			end
		end

		i = i + 1
	end

	if(bestType) then
		local color = DISPEL_COLORS[bestType]
		element._glow:Start(color, element._glowType)
	else
		element._glow:Stop()
	end
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
	local element = self.FramedDispellable
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedDispellable
	if(not element) then return end

	element._glow:Stop()

	self:UnregisterEvent('UNIT_AURA', Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedDispellable', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create a Dispellable element on a unit frame.
--- Applies a glow to the frame when the unit has a dispellable debuff.
--- Glow color reflects the highest-priority dispel type present.
--- Assigns result to self.FramedDispellable, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: glowType
function F.Elements.Dispellable.Setup(self, config)
	config = config or {}
	config.glowType = config.glowType or C.GlowType.PIXEL

	local glow = F.Indicators.Glow.Create(self, {
		glowType = config.glowType,
		color    = C.Colors.accent,
	})

	local container = {
		_glow     = glow,
		_glowType = config.glowType,
	}

	self.FramedDispellable = container
end
