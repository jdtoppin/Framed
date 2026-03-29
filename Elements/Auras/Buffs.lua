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
	[C.IndicatorType.BARS]      = F.Indicators.Bars,
	[C.IndicatorType.FRAME_BAR] = F.Indicators.Overlay,
	[C.IndicatorType.BORDER]    = F.Indicators.Border,
	[C.IndicatorType.COLOR]     = F.Indicators.Color,
	[C.IndicatorType.OVERLAY]   = F.Indicators.Overlay,
	[C.IndicatorType.GLOW]      = F.Indicators.Glow,
}

-- ============================================================
-- Anchor derivation for Icons containers
-- ============================================================

-- Decompose WoW anchor points into vertical/horizontal components
local POINT_V = {
	TOPLEFT = 'TOP', TOP = 'TOP', TOPRIGHT = 'TOP',
	LEFT = '', CENTER = '', RIGHT = '',
	BOTTOMLEFT = 'BOTTOM', BOTTOM = 'BOTTOM', BOTTOMRIGHT = 'BOTTOM',
}
local POINT_H = {
	TOPLEFT = 'LEFT', TOP = '', TOPRIGHT = 'RIGHT',
	LEFT = 'LEFT', CENTER = '', RIGHT = 'RIGHT',
	BOTTOMLEFT = 'LEFT', BOTTOM = '', BOTTOMRIGHT = 'RIGHT',
}

--- Derive the container frame point from the parent anchor point and grow direction.
--- Ensures the first icon appears at the parent anchor point.
--- @param parentPoint string WoW anchor point on the parent frame
--- @param growDirection string 'RIGHT'|'LEFT'|'UP'|'DOWN'
--- @return string containerPoint
local function deriveContainerPoint(parentPoint, growDirection)
	local v = POINT_V[parentPoint] or ''
	local h = POINT_H[parentPoint] or ''
	if(growDirection == 'RIGHT') then h = 'LEFT'
	elseif(growDirection == 'LEFT') then h = 'RIGHT'
	elseif(growDirection == 'DOWN') then v = 'TOP'
	elseif(growDirection == 'UP') then v = 'BOTTOM'
	end
	local pt = v .. h
	return (pt ~= '') and pt or 'CENTER'
end

--- Return a sensible default grow direction for a given parent anchor.
--- Right-side anchors default to LEFT; everything else defaults to RIGHT.
--- @param parentPoint string
--- @return string
local function defaultGrowForAnchor(parentPoint)
	local h = POINT_H[parentPoint] or ''
	if(h == 'RIGHT') then return 'LEFT' end
	return 'RIGHT'
end

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
	local auras = C_UnitAuras.GetUnitAuras(unit, 'HELPFUL')
	for _, auraData in next, auras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			local dominated = false
			if(element._hideUnimportantBuffs) then
				dominated = auraData.duration == 0
					or auraData.duration > 600
					or (not auraData.canApplyAura
						and not auraData.isBossAura
						and auraData.duration > 120)
			end

			if(not dominated) then
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
							if(ind._type == C.IndicatorType.ICONS or ind._type == C.IndicatorType.BARS) then
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
						if(ind._type == C.IndicatorType.ICONS or ind._type == C.IndicatorType.BARS) then
							local list = iconsAuras[idx]
							list[#list + 1] = auraEntry
						elseif(not matched[idx]) then
							matched[idx] = auraEntry
						end
					end
				end
			end
		end
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
				if(aura.duration and aura.duration > 0 and aura.expirationTime) then
					renderer:SetDuration(aura.duration, aura.expirationTime)
				else
					renderer:SetValue(1, 1)
				end
				if(aura.stacks) then renderer:SetStacks(aura.stacks) end
			else
				renderer:Clear()
			end

		elseif(rendererType == C.IndicatorType.BARS) then
			local list = iconsAuras[idx]
			if(#list > 0) then
				renderer:SetBars(list)
				renderer:Show()
			else
				renderer:Clear()
				renderer:Hide()
			end

		elseif(rendererType == C.IndicatorType.FRAME_BAR) then
			local aura = matched[idx]
			if(aura) then
				if(aura.duration and aura.duration > 0 and aura.expirationTime) then
					renderer:SetDuration(aura.duration, aura.expirationTime)
				else
					renderer:SetValue(1, 1)
				end
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
				local color = ind._color or { 1, 1, 1, 1 }
				renderer:SetColor(color[1], color[2], color[3], color[4] or 1)
				if(aura.duration and aura.duration > 0 and aura.expirationTime) then
					renderer:SetDuration(aura.duration, aura.expirationTime)
				else
					renderer:SetValue(1, 1)
				end
				if(aura.stacks) then renderer:SetStacks(aura.stacks) end
			else
				renderer:Clear()
			end

		elseif(rendererType == C.IndicatorType.OVERLAY) then
			local aura = matched[idx]
			if(aura) then
				local color = ind._color
				if(color) then renderer:SetColor(color[1], color[2], color[3], color[4] or 1) end
				if(aura.duration and aura.duration > 0 and aura.expirationTime) then
					renderer:SetDuration(aura.duration, aura.expirationTime)
				else
					renderer:SetValue(1, 1)
				end
			else
				renderer:Clear()
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
		elseif(rendererType == C.IndicatorType.BARS) then
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
			renderer:Clear()
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

	if(indType == C.IndicatorType.ICON or indType == C.IndicatorType.ICONS) then
		local iconConfig = {
			iconWidth    = indConfig.iconWidth or indConfig.iconSize or 14,
			iconHeight   = indConfig.iconHeight or indConfig.iconSize or 14,
			displayType  = indConfig.displayType,
			showCooldown = indConfig.showCooldown,
			showStacks   = indConfig.showStacks,
			durationMode = indConfig.durationMode or 'Never',
			durationFont = indConfig.durationFont,
			stackFont    = indConfig.stackFont,
			spellColors  = indConfig.spellColors,
			glowType     = indConfig.glowType,
			glowColor    = indConfig.glowColor,
			glowConfig   = indConfig.glowConfig,
		}
		if(indType == C.IndicatorType.ICONS) then
			local anchor = indConfig.anchor or { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 }
			local growDir = indConfig.orientation or defaultGrowForAnchor(anchor[3] or 'TOPLEFT')
			iconConfig.maxIcons      = indConfig.maxDisplayed or 4
			iconConfig.numPerLine    = indConfig.numPerLine or 0
			iconConfig.spacingX      = indConfig.spacingX or 1
			iconConfig.spacingY      = indConfig.spacingY or 1
			iconConfig.growDirection = growDir
			return factory.Create(parent, iconConfig)
		else
			return factory.Create(parent, nil, iconConfig)
		end

	elseif(indType == C.IndicatorType.BAR) then
		return factory.Create(parent, {
			barWidth       = indConfig.barWidth or 50,
			barHeight      = indConfig.barHeight or 4,
			barOrientation = indConfig.barOrientation or 'Horizontal',
			color          = indConfig.color,
			borderColor    = indConfig.borderColor,
			bgColor        = indConfig.bgColor,
			lowTimeColor   = indConfig.lowTimeColor,
			lowSecsColor   = indConfig.lowSecsColor,
			showStacks     = indConfig.showStacks,
			durationMode   = indConfig.durationMode,
			durationFont   = indConfig.durationFont,
			stackFont      = indConfig.stackFont,
		})

	elseif(indType == C.IndicatorType.BARS) then
		return F.Indicators.Bars.Create(parent, {
			barWidth       = indConfig.barWidth or 50,
			barHeight      = indConfig.barHeight or 4,
			barOrientation = indConfig.barOrientation or 'Horizontal',
			color          = indConfig.color,
			borderColor    = indConfig.borderColor,
			bgColor        = indConfig.bgColor,
			lowTimeColor   = indConfig.lowTimeColor,
			lowSecsColor   = indConfig.lowSecsColor,
			showStacks     = indConfig.showStacks,
			durationMode   = indConfig.durationMode,
			durationFont   = indConfig.durationFont,
			stackFont      = indConfig.stackFont,
			maxDisplayed   = indConfig.maxDisplayed or 3,
			numPerLine     = indConfig.numPerLine or 0,
			spacingX       = indConfig.spacingX or 1,
			spacingY       = indConfig.spacingY or 1,
			orientation    = indConfig.orientation or 'DOWN',
		})

	elseif(indType == C.IndicatorType.FRAME_BAR) then
		return F.Indicators.Overlay.Create(parent.Health or parent, {
			overlayMode = 'FrameBar',
			color = indConfig.color,
		})

	elseif(indType == C.IndicatorType.BORDER) then
		return factory.Create(parent, {
			borderThickness = indConfig.borderThickness,
			fadeOut          = indConfig.fadeOut,
		})

	elseif(indType == C.IndicatorType.COLOR) then
		return factory.Create(parent, {
			color         = indConfig.color,
			rectWidth     = indConfig.rectWidth or 10,
			rectHeight    = indConfig.rectHeight or 10,
			borderColor   = indConfig.borderColor,
			lowTimeColor  = indConfig.lowTimeColor,
			lowSecsColor  = indConfig.lowSecsColor,
			showStacks    = indConfig.showStacks,
			durationMode  = indConfig.durationMode,
			stackFont     = indConfig.stackFont,
		})

	elseif(indType == C.IndicatorType.OVERLAY) then
		return F.Indicators.Overlay.Create(parent.Health or parent, {
			overlayMode    = indConfig.overlayMode or 'Overlay',
			color          = indConfig.color,
			barOrientation = indConfig.barOrientation or 'Horizontal',
			smooth         = indConfig.smooth,
			lowTimeColor   = indConfig.lowTimeColor,
			lowSecsColor   = indConfig.lowSecsColor,
		})

	elseif(indType == C.IndicatorType.GLOW) then
		return factory.Create(parent, {
			glowType = indConfig.glowType,
			color    = indConfig.color,
			fadeOut  = indConfig.fadeOut,
		})
	end

	return nil
end

-- ============================================================
-- Rebuild
-- ============================================================

--- Structural rebuild: destroy all renderers and recreate from fresh config.
local function Rebuild(element, config)
	if(element._indicators) then
		for _, ind in next, element._indicators do
			if(ind._renderer) then
				ind._renderer:Clear()
				if(ind._renderer.Destroy) then
					ind._renderer:Destroy()
				end
			end
		end
	end

	element._indicators           = {}
	element._spellLookup          = {}
	element._hasTrackAll          = {}
	element._hideUnimportantBuffs = config.hideUnimportantBuffs or false

	local indicators = config.indicators or {}
	for name, indConfig in next, indicators do
		if(indConfig.enabled ~= false) then
			local renderer = createRenderer(element.__owner, indConfig)
			if(renderer) then
				local anchor = indConfig.anchor or { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 }
				if(renderer.ClearAllPoints and renderer.SetPoint) then
					renderer:ClearAllPoints()
					local containerPoint = anchor[1]

					-- For Icons, derive container point so first icon is at the anchor
					if(indConfig.type == C.IndicatorType.ICONS) then
						local growDir = indConfig.orientation or defaultGrowForAnchor(anchor[3] or 'TOPLEFT')
						containerPoint = deriveContainerPoint(anchor[3] or 'TOPLEFT', growDir)
					end

					renderer:SetPoint(containerPoint, element.__owner, anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0)
				end
				if(indConfig.frameLevel and renderer.GetFrame) then
					local frame = renderer:GetFrame()
				if(frame and frame.SetFrameLevel) then
					frame:SetFrameLevel(indConfig.frameLevel)
				end
				end

				local idx = #element._indicators + 1
				element._indicators[idx] = {
					_renderer   = renderer,
					_type       = indConfig.type,
					_castBy     = indConfig.castBy or 'anyone',
					_color      = indConfig.color,
					_glowType   = indConfig.glowType,
					_glowConfig = indConfig.glowConfig,
					_name       = name,
				}

				local spells = indConfig.spells
				if(spells and #spells > 0) then
					for _, spellId in next, spells do
						if(not element._spellLookup[spellId]) then
							element._spellLookup[spellId] = {}
						end
						element._spellLookup[spellId][#element._spellLookup[spellId] + 1] = idx
					end
				else
					element._hasTrackAll[#element._hasTrackAll + 1] = idx
				end
			end
		end
	end

	element:ForceUpdate()
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
				local anchor = indConfig.anchor or { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 }
				if(renderer.SetPoint) then
					local anchorParent = anchor[2] or self
					local containerPoint = anchor[1]

					-- For Icons, derive container point so first icon is at the anchor
					if(indConfig.type == C.IndicatorType.ICONS) then
						local growDir = indConfig.orientation or defaultGrowForAnchor(anchor[3] or 'TOPLEFT')
						containerPoint = deriveContainerPoint(anchor[3] or 'TOPLEFT', growDir)
					end

					renderer:SetPoint(containerPoint, anchorParent, anchor[3], anchor[4] or 0, anchor[5] or 0)
				end

				-- Set frame level if supported
				local fl = indConfig.frameLevel or 5
				if(renderer.GetFrame) then
					local frame = renderer:GetFrame()
					if(frame and frame.SetFrameLevel) then
						frame:SetFrameLevel(fl)
					end
				end

				indicators[idx] = {
					_renderer   = renderer,
					_type       = indConfig.type,
					_castBy     = indConfig.castBy or 'anyone',
					_color      = indConfig.color,
					_glowType   = indConfig.glowType,
					_glowConfig = indConfig.glowConfig,
					_name       = indConfig.name,
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
		_indicators           = indicators,
		_spellLookup          = spellLookup,
		_hasTrackAll          = hasTrackAll,
		_hideUnimportantBuffs = config.hideUnimportantBuffs or false,
	}

	container.Rebuild = Rebuild

	self.FramedBuffs = container
end
