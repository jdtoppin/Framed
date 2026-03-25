local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Defensives = {}

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedDefensives
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local cfg = element._config
	local maxDisplayed = cfg.maxDisplayed or 3

	-- Collect auras
	local auraList = {}
	local i = 1
	while(true) do
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HELPFUL')
		if(not auraData) then break end

		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId) and F.Data.DefensiveSpellIDs[spellId]) then
			local sourceUnit = auraData.sourceUnit
			-- Only show defensives cast by the player themselves
			if(F.IsValueNonSecret(sourceUnit) and sourceUnit == 'player') then
				auraList[#auraList + 1] = {
					spellId        = spellId,
					icon           = auraData.icon,
					duration       = auraData.duration,
					expirationTime = auraData.expirationTime,
					stacks         = auraData.applications or 0,
				}
			end
		end
		i = i + 1
	end

	-- Display up to maxDisplayed using BorderIcon pool
	local count = math.min(#auraList, maxDisplayed)
	local pool = element._pool
	local iconSize = cfg.iconSize or 16
	local orientation = cfg.orientation or 'RIGHT'

	for idx = 1, count do
		local aura = auraList[idx]

		-- Lazily create pool entries
		if(not pool[idx]) then
			pool[idx] = F.Indicators.BorderIcon.Create(self, iconSize, {
				showCooldown = true,
				showStacks   = cfg.showStacks ~= false,
				showDuration = cfg.showDuration ~= false,
				frameLevel   = cfg.frameLevel or 5,
				stackFont    = cfg.stackFont,
				durationFont = cfg.durationFont,
			})
		end

		local bi = pool[idx]

		bi:ClearAllPoints()
		bi:SetSize(iconSize)

		-- Position
		local offset = (idx - 1) * (iconSize + 2)

		if(orientation == 'RIGHT') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', offset, 0)
		elseif(orientation == 'LEFT') then
			bi:SetPoint('TOPRIGHT', element._container, 'TOPRIGHT', -offset, 0)
		elseif(orientation == 'DOWN') then
			bi:SetPoint('TOPLEFT', element._container, 'TOPLEFT', 0, -offset)
		elseif(orientation == 'UP') then
			bi:SetPoint('BOTTOMLEFT', element._container, 'BOTTOMLEFT', 0, offset)
		end

		bi:SetAura(
			aura.spellId,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.stacks,
			nil
		)
		bi:Show()
	end

	-- Hide pool entries beyond active count
	for idx = count + 1, #pool do
		pool[idx]:Clear()
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
	local element = self.FramedDefensives
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedDefensives
	if(not element) then return end

	for _, bi in next, element._pool do
		bi:Clear()
	end

	self:UnregisterEvent('UNIT_AURA', Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedDefensives', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create a Defensives element on a unit frame.
--- Shows BorderIcons for self-cast defensive cooldowns
--- (Ice Block, Divine Shield, Cloak of Shadows, etc.).
--- Assigns result to self.FramedDefensives, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: iconSize, maxDisplayed, showDuration,
---                       showStacks, orientation, anchor, frameLevel,
---                       stackFont, durationFont
function F.Elements.Defensives.Setup(self, config)
	config = config or {}

	local container = CreateFrame('Frame', nil, self)
	container:SetAllPoints(self)

	local element = {
		_container = container,
		_config    = config,
		_pool      = {},
	}

	local a = config.anchor
	if(a) then
		container:ClearAllPoints()
		Widgets.SetPoint(container, a[1], a[2] or self, a[3], a[4] or 0, a[5] or 0)
	end

	self.FramedDefensives = element
end
