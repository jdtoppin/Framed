local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Buffs = {}

-- ============================================================
-- Renderer dispatch table
-- ============================================================

local RENDERERS = {
	[C.IndicatorType.ICON]      = F.Indicators.Icon,
	[C.IndicatorType.ICONS]     = F.Indicators.Icons,
	[C.IndicatorType.BAR]       = F.Indicators.Bar,
	[C.IndicatorType.FRAME_BAR] = F.Indicators.FrameBar,
	[C.IndicatorType.BORDER]    = F.Indicators.Border,
	[C.IndicatorType.COLOR]     = F.Indicators.Color,
	[C.IndicatorType.OVERLAY]   = F.Indicators.Overlay,
	[C.IndicatorType.GLOW]      = F.Indicators.Glow,
}

-- ============================================================
-- castBy filter helper
-- ============================================================

--- Check whether an aura passes the castBy filter.
--- @param sourceUnit string|nil The aura's sourceUnit (may be secret)
--- @param castBy string 'me', 'others', or 'anyone'
--- @return boolean
local function passesCastByFilter(sourceUnit, castBy)
	if(castBy == 'anyone') then return true end

	local sourceIsSafe = F.IsValueNonSecret(sourceUnit)
	if(not sourceIsSafe) then
		-- Secret sourceUnit: cannot determine caster, degrade gracefully
		-- Show for 'anyone' (already handled above), hide for 'me'/'others'
		return false
	end

	if(castBy == 'me') then
		return sourceUnit == 'player'
	elseif(castBy == 'others') then
		return sourceUnit ~= 'player'
	end

	return true
end

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedBuffs
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local indicators = element._indicators
	local spellLookup = element._spellLookup
	local hasTrackAll = element._hasTrackAll

	-- Collect per-indicator aura lists for Icons-type renderers,
	-- and track first-match for single-value renderers.
	local iconsAuras = {}
	local matched = {}

	for idx, _ in next, indicators do
		iconsAuras[idx] = {}
		matched[idx] = false
	end

	-- Iterate helpful auras
	local i = 1
	while(true) do
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HELPFUL')
		if(not auraData) then break end

		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local auraEntry
			local sourceUnit = auraData.sourceUnit

			-- Check spell-specific indicators
			local indicatorIndices = spellLookup[spellId]
			if(indicatorIndices) then
				for _, idx in next, indicatorIndices do
					local ind = indicators[idx]
					if(passesCastByFilter(sourceUnit, ind._castBy)) then
						if(not auraEntry) then
							auraEntry = {
								spellId        = spellId,
								icon           = auraData.icon,
								duration       = auraData.duration,
								expirationTime = auraData.expirationTime,
								stacks         = auraData.applications or 0,
								dispelType     = auraData.dispelName,
							}
						end
						if(ind._type == C.IndicatorType.ICONS) then
							local list = iconsAuras[idx]
							list[#list + 1] = auraEntry
						elseif(not matched[idx]) then
							matched[idx] = auraEntry
						end
					end
				end
			end

			-- Check track-all indicators (empty spells list)
			for _, idx in next, hasTrackAll do
				local ind = indicators[idx]
				if(passesCastByFilter(sourceUnit, ind._castBy)) then
					if(not auraEntry) then
						auraEntry = {
							spellId        = spellId,
							icon           = auraData.icon,
							duration       = auraData.duration,
							expirationTime = auraData.expirationTime,
							stacks         = auraData.applications or 0,
							dispelType     = auraData.dispelName,
						}
					end
					if(ind._type == C.IndicatorType.ICONS) then
						local list = iconsAuras[idx]
						list[#list + 1] = auraEntry
					elseif(not matched[idx]) then
						matched[idx] = auraEntry
					end
				end
			end
		end
		i = i + 1
	end

	-- Dispatch to each renderer
	for idx, ind in next, indicators do
		local renderer = ind._renderer
		local rendererType = ind._type

		if(rendererType == C.IndicatorType.ICONS) then
			local list = iconsAuras[idx]
			if(#list > 0) then
				renderer:SetIcons(list)
				renderer:Show()
			else
				renderer:Clear()
				renderer:Hide()
			end

		elseif(rendererType == C.IndicatorType.ICON) then
			local aura = matched[idx]
			if(aura) then
				renderer:SetSpell(
					aura.spellId,
					aura.icon,
					aura.duration,
					aura.expirationTime,
					aura.stacks,
					aura.dispelType
				)
			else
				renderer:Clear()
			end

		elseif(rendererType == C.IndicatorType.BAR) then
			local aura = matched[idx]
			if(aura) then
				renderer:SetDuration(aura.duration, aura.expirationTime)
			else
				renderer:Clear()
			end

		elseif(rendererType == C.IndicatorType.FRAME_BAR) then
			local aura = matched[idx]
			if(aura) then
				local remaining = aura.expirationTime - GetTime()
				if(aura.duration and aura.duration > 0) then
					renderer:SetValue(remaining, aura.duration)
				else
					renderer:SetValue(1, 1)
				end
				renderer:Show()
			else
				renderer:Clear()
			end

		elseif(rendererType == C.IndicatorType.BORDER) then
			local aura = matched[idx]
			if(aura) then
				local color = ind._color or { 1, 1, 1, 1 }
				renderer:SetColor(color[1], color[2], color[3], color[4])
			else
				renderer:Clear()
			end

		elseif(rendererType == C.IndicatorType.COLOR) then
			local aura = matched[idx]
			if(aura) then
				local color = ind._color or { 0.2, 0.8, 0.2, 1 }
				renderer:Override(color[1], color[2], color[3], color[4])
			else
				renderer:Clear()
			end

		elseif(rendererType == C.IndicatorType.OVERLAY) then
			local aura = matched[idx]
			if(aura) then
				local color = ind._color
				renderer:Show(color)
			else
				renderer:Hide()
			end

		elseif(rendererType == C.IndicatorType.GLOW) then
			local aura = matched[idx]
			if(aura) then
				if(not renderer:IsActive()) then
					renderer:Start(ind._color, ind._glowType, ind._glowConfig)
				end
			else
				renderer:Stop()
			end
		end
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
	local element = self.FramedBuffs
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedBuffs
	if(not element) then return end

	-- Clear all renderers
	for _, ind in next, element._indicators do
		local renderer = ind._renderer
		local rendererType = ind._type

		if(rendererType == C.IndicatorType.ICONS) then
			renderer:Clear()
			renderer:Hide()
		elseif(rendererType == C.IndicatorType.ICON) then
			renderer:Clear()
		elseif(rendererType == C.IndicatorType.BAR) then
			renderer:Clear()
		elseif(rendererType == C.IndicatorType.FRAME_BAR) then
			renderer:Clear()
		elseif(rendererType == C.IndicatorType.BORDER) then
			renderer:Clear()
		elseif(rendererType == C.IndicatorType.COLOR) then
			renderer:Clear()
		elseif(rendererType == C.IndicatorType.OVERLAY) then
			renderer:Hide()
		elseif(rendererType == C.IndicatorType.GLOW) then
			renderer:Stop()
		end
	end

	self:UnregisterEvent('UNIT_AURA', Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedBuffs', Update, Enable, Disable)

-- ============================================================
-- Renderer creation helpers
-- ============================================================

--- Create a renderer instance for the given indicator config.
--- @param parent Frame The unit frame
--- @param indConfig table The indicator config entry
--- @return table|nil renderer The created renderer, or nil if the type is unknown
local function createRenderer(parent, indConfig)
	local indType = indConfig.type
	local factory = RENDERERS[indType]
	if(not factory) then return nil end

	if(indType == C.IndicatorType.ICON) then
		return factory.Create(parent, indConfig.iconSize or 14, {
			displayType  = indConfig.displayType,
			showCooldown = indConfig.showCooldown,
			showStacks   = indConfig.showStacks,
			showDuration = indConfig.showDuration,
		})

	elseif(indType == C.IndicatorType.ICONS) then
		return factory.Create(parent, {
			maxIcons      = indConfig.maxIcons or 4,
			iconSize      = indConfig.iconSize or 14,
			spacing       = indConfig.spacing,
			spacingX      = indConfig.spacingX,
			spacingY      = indConfig.spacingY,
			numPerLine    = indConfig.numPerLine,
			growDirection = indConfig.growDirection or 'RIGHT',
			displayType   = indConfig.displayType,
			showCooldown  = indConfig.showCooldown,
			showStacks    = indConfig.showStacks,
			showDuration  = indConfig.showDuration,
		})

	elseif(indType == C.IndicatorType.BAR) then
		return factory.Create(parent, indConfig.barWidth or 50, indConfig.barHeight or 4, {
			color = indConfig.color,
		})

	elseif(indType == C.IndicatorType.FRAME_BAR) then
		return factory.Create(parent, {
			color = indConfig.color,
		})

	elseif(indType == C.IndicatorType.BORDER) then
		return factory.Create(parent)

	elseif(indType == C.IndicatorType.COLOR) then
		-- Color needs the health bar, fall back to parent if Health not available
		local healthBar = parent.Health or parent
		return factory.Create(healthBar)

	elseif(indType == C.IndicatorType.OVERLAY) then
		return factory.Create(parent)

	elseif(indType == C.IndicatorType.GLOW) then
		return factory.Create(parent, {
			glowType = indConfig.glowType,
			color    = indConfig.color,
		})
	end

	return nil
end

-- ============================================================
-- Setup
-- ============================================================

--- Create and configure buff indicators on a unit frame.
--- Reads from config.indicators[] (new format) or falls back to
--- legacy format with maxIcons for backward compatibility.
--- Assigns result to self.FramedBuffs, activating the element.
--- @param self Frame The oUF unit frame
--- @param config? table Configuration with indicators[] array or legacy fields
function F.Elements.Buffs.Setup(self, config)
	config = config or {}

	-- Normalize: build indicators array from legacy config if needed
	local indicatorConfigs = config.indicators
	if(not indicatorConfigs) then
		-- Backward compatibility: create a single Icons renderer matching old behavior
		indicatorConfigs = {
			{
				name          = 'Buffs',
				type          = C.IndicatorType.ICONS,
				enabled       = true,
				spells        = {},   -- empty = track all helpful auras
				castBy        = 'anyone',
				maxIcons      = config.maxIcons      or 6,
				iconSize      = config.iconSize      or 14,
				growDirection = config.growDirection or 'RIGHT',
				displayType   = config.displayType   or 'SpellIcon',
				anchor        = config.anchor        or { 'TOPLEFT', self, 'TOPLEFT', 2, -2 },
			},
		}
	end

	local indicators = {}
	local spellLookup = {}   -- spellID → { indicatorIndex, ... }
	local hasTrackAll = {}   -- indices of indicators that track all spells (empty spells list)

	for idx, indConfig in next, indicatorConfigs do
		if(indConfig.enabled ~= false) then
			local renderer = createRenderer(self, indConfig)
			if(renderer) then
				-- Position renderers that support SetPoint
				local anchor = indConfig.anchor
				if(anchor and renderer.SetPoint) then
					-- Resolve nil parent ref to self
					local anchorParent = anchor[2] or self
					renderer:SetPoint(anchor[1], anchorParent, anchor[3], anchor[4] or 0, anchor[5] or 0)
				end

				-- Set frame level if supported
				if(indConfig.frameLevel and renderer.GetFrame) then
					local frame = renderer:GetFrame()
					if(frame and frame.SetFrameLevel) then
						frame:SetFrameLevel(indConfig.frameLevel)
					end
				end

				indicators[idx] = {
					_renderer   = renderer,
					_type       = indConfig.type,
					_castBy     = indConfig.castBy or 'anyone',
					_color      = indConfig.color,
					_glowType   = indConfig.glowType,
					_glowConfig = indConfig.glowConfig,
				}

				-- Build spell→indicator lookup
				local spells = indConfig.spells
				if(spells and #spells > 0) then
					for _, spellId in next, spells do
						if(not spellLookup[spellId]) then
							spellLookup[spellId] = {}
						end
						local list = spellLookup[spellId]
						list[#list + 1] = idx
					end
				else
					-- No specific spells = track all helpful auras
					hasTrackAll[#hasTrackAll + 1] = idx
				end
			end
		end
	end

	local container = {
		_indicators  = indicators,
		_spellLookup = spellLookup,
		_hasTrackAll = hasTrackAll,
	}

	self.FramedBuffs = container
end
