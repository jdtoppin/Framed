local _, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants

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
	[C.IndicatorType.BORDER]    = F.Indicators.BorderGlow,
	[C.IndicatorType.RECTANGLE] = F.Indicators.Color,
	[C.IndicatorType.OVERLAY]   = F.Indicators.Overlay,
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

-- Derive the element's aura-query filter from its indicator set.
--
-- Only a spell list widens the query to HELPFUL. The list itself is an
-- allowlist — so broadening doesn't leak noise onto the indicator, and
-- tracked IDs become visible regardless of Blizzard's RAID_IN_COMBAT
-- curation. Every other configuration (trackAll, any castBy) keeps
-- HELPFUL|RAID_IN_COMBAT so world/cosmetic/consumable buffs stay
-- filtered out by Blizzard before reaching the indicator.
local function computeBuffFilter(indicatorConfigs)
	for _, ind in next, indicatorConfigs do
		if(ind.enabled ~= false and ind.spells and #ind.spells > 0) then
			return 'HELPFUL'
		end
	end
	return 'HELPFUL|RAID_IN_COMBAT'
end

-- Reusable containers — wiped each Update to avoid per-call allocation.
-- Stores auraData references directly (no copy tables).
local iconsAurasPool = {} -- [idx] = reusable sub-array of auraData refs
local matchedPool = {}    -- [idx] = auraData ref or false

-- Pre-created sort comparator (sortPriority set before each sort call)
local sortPriority
local function prioritySort(a, b)
	local pa = sortPriority[a.spellId] or 999
	local pb = sortPriority[b.spellId] or 999
	return pa < pb
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
		-- Secret sourceUnit: caster unknowable, so 'me' and 'others' both
		-- match. Over-matching is strictly better than silent-hiding — the
		-- aura appears in both panels and the user can disambiguate.
		return true
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

local function Update(self, event, unit, updateInfo)
	local element = self.FramedBuffs
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end

	local indicators = element._indicators
	local spellLookup = element._spellLookup
	local hasTrackAll = element._hasTrackAll

	-- Collect per-indicator aura lists for Icons-type renderers,
	-- and track first-match for single-value renderers.
	-- Stores auraData references directly — zero intermediate table allocations.
	for idx in next, indicators do
		local sub = iconsAurasPool[idx]
		if(not sub) then
			sub = {}
			iconsAurasPool[idx] = sub
		else
			wipe(sub)
		end
		matchedPool[idx] = false
	end

	local auraState = self.FramedAuraState
	if(auraState) then
		if(event == 'UNIT_AURA') then
			auraState:ApplyUpdateInfo(unit, updateInfo)
		else
			auraState:EnsureInitialized(unit)
		end
	end

	local filter = element._buffFilter

	-- Per-aura matcher shared between classified and fallback paths.
	-- Captures unit / indicators / spellLookup / hasTrackAll via closure.
	local function matchAura(auraData)
		local spellId = auraData.spellId
		if(not F.IsValueNonSecret(spellId)) then return end

		local sourceUnit = auraData.sourceUnit

		-- Check spell-specific indicators
		local indicatorIndices = spellLookup[spellId]
		if(indicatorIndices) then
			for _, idx in next, indicatorIndices do
				local ind = indicators[idx]
				if(passesCastByFilter(sourceUnit, ind._castBy)) then
					if(ind._type == C.IndicatorType.ICONS or ind._type == C.IndicatorType.BARS) then
						local list = iconsAurasPool[idx]
						list[#list + 1] = auraData
					elseif(not matchedPool[idx]) then
						matchedPool[idx] = auraData
					end
				end
			end
		end

		-- Check track-all indicators (empty spells list)
		for _, idx in next, hasTrackAll do
			local ind = indicators[idx]
			if(passesCastByFilter(sourceUnit, ind._castBy)) then
				if(ind._type == C.IndicatorType.ICONS or ind._type == C.IndicatorType.BARS) then
					local list = iconsAurasPool[idx]
					list[#list + 1] = auraData
				elseif(not matchedPool[idx]) then
					matchedPool[idx] = auraData
				end
			end
		end
	end

	local classified = auraState and auraState:GetHelpfulClassified()

	if(classified) then
		-- Classified path returns ALL helpful auras. When computeBuffFilter
		-- resolved to HELPFUL|RAID_IN_COMBAT (no spell list among indicators),
		-- gate each entry on flags.isRaidInCombat client-side so cosmetic /
		-- consumable / world buffs stay filtered out — matching what the
		-- server-side filter would have done.
		local narrowFilter = filter == 'HELPFUL|RAID_IN_COMBAT'

		for _, entry in next, classified do
			if(not narrowFilter or entry.flags.isRaidInCombat) then
				matchAura(entry.aura)
			end
		end
	else
		-- Vestigial no-AuraState fallback. Every aura-tracking frame creates
		-- AuraState via the idempotent Setup guard — preserved to match the
		-- element-level pattern used across Auras/.
		for _, auraData in next, F.AuraCache.GetUnitAuras(unit, filter) do
			matchAura(auraData)
		end
	end

	-- Dispatch to each renderer
	for idx, ind in next, indicators do
		local renderer = ind._renderer
		local rendererType = ind._type

		if(rendererType == C.IndicatorType.ICONS) then
			local list = iconsAurasPool[idx]
			if(#list > 0) then
				-- Sort by spell list priority (lower index = higher priority)
				if(ind._spellPriority) then
					sortPriority = ind._spellPriority
					table.sort(list, prioritySort)
				end
				renderer:SetIcons(unit, list)
				renderer:Show()
			else
				renderer:Clear()
				renderer:Hide()
			end

		elseif(rendererType == C.IndicatorType.ICON) then
			local aura = matchedPool[idx]
			if(aura) then
				renderer:SetSpell(
					unit,
					aura.auraInstanceID,
					aura.spellId,
					aura.icon,
					aura.duration,
					aura.expirationTime,
					aura.applications
				)
			else
				renderer:Clear()
			end

		elseif(rendererType == C.IndicatorType.BAR) then
			local aura = matchedPool[idx]
			if(aura) then
				-- Apply spell color before showing
				local sc = ind._spellColors and ind._spellColors[aura.spellId]
				if(sc) then
					renderer:SetColor(sc[1], sc[2], sc[3], 1)
				elseif(ind._color) then
					renderer:SetColor(ind._color[1], ind._color[2], ind._color[3], ind._color[4])
				else
					renderer:SetColor(1, 1, 1, 1)
				end
				local hasDuration = F.IsValueNonSecret(aura.duration) and aura.duration > 0
				if(hasDuration and F.IsValueNonSecret(aura.expirationTime) and aura.expirationTime > 0) then
					renderer:SetDuration(aura.duration, aura.expirationTime)
				else
					renderer:SetValue(1, 1)
				end
				if(aura.applications) then renderer:SetStacks(aura.applications) end
				-- Glow
				if(ind._glowType and ind._glowType ~= 'None') then
					renderer:StartGlow(ind._glowColor, ind._glowType, ind._glowConfig)
				end
			else
				renderer:Clear()
				if(renderer.StopGlow) then renderer:StopGlow() end
			end

		elseif(rendererType == C.IndicatorType.BARS) then
			local list = iconsAurasPool[idx]
			if(#list > 0) then
				-- Sort by spell list priority
				if(ind._spellPriority) then
					sortPriority = ind._spellPriority
					table.sort(list, prioritySort)
				end
				renderer:SetBars(list)
				renderer:Show()
				-- Glow
				if(ind._glowType and ind._glowType ~= 'None') then
					renderer:StartGlow(ind._glowColor, ind._glowType, ind._glowConfig)
				end
			else
				renderer:Clear()
				renderer:Hide()
				if(renderer.StopGlow) then renderer:StopGlow() end
			end

		elseif(rendererType == C.IndicatorType.BORDER) then
			local aura = matchedPool[idx]
			if(aura) then
				local mode = ind._borderGlowMode
				if(mode == 'Border') then
					local color = ind._color
					renderer:SetColor(color[1], color[2], color[3], color[4])
				elseif(mode == 'Glow') then
					if(not renderer:IsActive()) then
						renderer:Start(ind._glowColor, ind._glowType, ind._glowConfig)
					end
				end
				local hasDuration = F.IsValueNonSecret(aura.duration) and aura.duration > 0
				if(hasDuration and F.IsValueNonSecret(aura.expirationTime) and aura.expirationTime > 0) then
					renderer:SetCooldown(aura.duration, aura.expirationTime)
				else
					renderer:SetCooldown(0, 0)
				end
			else
				renderer:Clear()
			end

		elseif(rendererType == C.IndicatorType.RECTANGLE) then
			local aura = matchedPool[idx]
			if(aura) then
				local color = ind._color
				renderer:SetColor(color[1], color[2], color[3], color[4])
				local hasDuration = F.IsValueNonSecret(aura.duration) and aura.duration > 0
				if(hasDuration and F.IsValueNonSecret(aura.expirationTime) and aura.expirationTime > 0) then
					renderer:SetDuration(aura.duration, aura.expirationTime)
				else
					renderer:SetValue(1, 1)
				end
				if(aura.applications) then renderer:SetStacks(aura.applications) end
			else
				renderer:Clear()
			end

		elseif(rendererType == C.IndicatorType.OVERLAY) then
			local aura = matchedPool[idx]
			if(aura) then
				local color = ind._color
				if(color) then renderer:SetColor(color[1], color[2], color[3], color[4]) end
				local hasDuration = F.IsValueNonSecret(aura.duration) and aura.duration > 0
				if(hasDuration and F.IsValueNonSecret(aura.expirationTime) and aura.expirationTime > 0) then
					renderer:SetDuration(aura.duration, aura.expirationTime)
				else
					renderer:SetValue(1, 1)
				end
			else
				renderer:Clear()
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
		elseif(rendererType == C.IndicatorType.BORDER) then
			renderer:Clear()
		elseif(rendererType == C.IndicatorType.RECTANGLE) then
			renderer:Clear()
		elseif(rendererType == C.IndicatorType.OVERLAY) then
			renderer:Clear()
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
			iconWidth    = indConfig.iconWidth,
			iconHeight   = indConfig.iconHeight,
			displayType  = indConfig.displayType,
			color        = indConfig.color,
			showCooldown = indConfig.showCooldown,
			showStacks   = indConfig.showStacks,
			durationMode = indConfig.durationMode,
			durationFont = indConfig.durationFont,
			stackFont    = indConfig.stackFont,
			spellColors  = indConfig.spellColors,
			glowType     = indConfig.glowType,
			glowColor    = indConfig.glowColor,
			glowConfig   = indConfig.glowConfig,
		}
		if(indType == C.IndicatorType.ICONS) then
			local anchor = indConfig.anchor
			local growDir = indConfig.orientation or defaultGrowForAnchor(anchor[3])
			iconConfig.maxIcons      = indConfig.maxDisplayed
			iconConfig.numPerLine    = indConfig.numPerLine
			iconConfig.spacingX      = indConfig.spacingX
			iconConfig.spacingY      = indConfig.spacingY
			iconConfig.growDirection = growDir
			return factory.Create(parent, iconConfig)
		else
			return factory.Create(parent, nil, iconConfig)
		end

	elseif(indType == C.IndicatorType.BAR) then
		return factory.Create(parent, {
			barWidth       = indConfig.barWidth,
			barHeight      = indConfig.barHeight,
			barOrientation = indConfig.barOrientation,
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
			barWidth       = indConfig.barWidth,
			barHeight      = indConfig.barHeight,
			barOrientation = indConfig.barOrientation,
			color          = indConfig.color,
			borderColor    = indConfig.borderColor,
			bgColor        = indConfig.bgColor,
			lowTimeColor   = indConfig.lowTimeColor,
			lowSecsColor   = indConfig.lowSecsColor,
			showStacks     = indConfig.showStacks,
			durationMode   = indConfig.durationMode,
			durationFont   = indConfig.durationFont,
			stackFont      = indConfig.stackFont,
			spellColors    = indConfig.spellColors,
			maxDisplayed   = indConfig.maxDisplayed,
			numPerLine     = indConfig.numPerLine,
			spacingX       = indConfig.spacingX,
			spacingY       = indConfig.spacingY,
			orientation    = indConfig.orientation,
		})

	elseif(indType == C.IndicatorType.BORDER) then
		return factory.Create(parent, {
			borderGlowMode  = indConfig.borderGlowMode,
			borderThickness = indConfig.borderThickness,
			fadeOut          = indConfig.fadeOut,
			color            = indConfig.color,
			glowType         = indConfig.glowType,
			glowColor        = indConfig.glowColor,
		})

	elseif(indType == C.IndicatorType.RECTANGLE) then
		return factory.Create(parent, {
			color         = indConfig.color,
			rectWidth     = indConfig.rectWidth,
			rectHeight    = indConfig.rectHeight,
			borderColor   = indConfig.borderColor,
			lowTimeColor  = indConfig.lowTimeColor,
			lowSecsColor  = indConfig.lowSecsColor,
			showStacks    = indConfig.showStacks,
			durationMode  = indConfig.durationMode,
			stackFont     = indConfig.stackFont,
		})

	elseif(indType == C.IndicatorType.OVERLAY) then
		return F.Indicators.Overlay.Create(parent.Health or parent, {
			overlayMode    = indConfig.overlayMode,
			color          = indConfig.color,
			barOrientation = indConfig.barOrientation,
			smooth         = indConfig.smooth,
			lowTimeColor   = indConfig.lowTimeColor,
			lowSecsColor   = indConfig.lowSecsColor,
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
	element._buffFilter           = computeBuffFilter(config.indicators)

	local indicators = config.indicators
	for name, indConfig in next, indicators do
		if(indConfig.enabled ~= false) then
			local renderer = createRenderer(element.__owner, indConfig)
			if(renderer) then
				local anchor = indConfig.anchor
				if(renderer.ClearAllPoints and renderer.SetPoint) then
					renderer:ClearAllPoints()
					local containerPoint = anchor[1]

					-- For Icons, derive container point so first icon is at the anchor
					if(indConfig.type == C.IndicatorType.ICONS) then
						local growDir = indConfig.orientation or defaultGrowForAnchor(anchor[3])
						containerPoint = deriveContainerPoint(anchor[3], growDir)
					end

					renderer:SetPoint(containerPoint, element.__owner, anchor[3], anchor[4], anchor[5])
				end
				if(renderer.GetFrame) then
					local frame = renderer:GetFrame()
				if(frame and frame.SetFrameLevel) then
					frame:SetFrameLevel(indConfig.frameLevel)
				end
				end

				local idx = #element._indicators + 1
				-- Build spell priority map (list order = display priority)
				local spellPriority = {}
				local spells = indConfig.spells
				if(spells and #spells > 0) then
					for pri, spellId in next, spells do
						spellPriority[spellId] = pri
					end
				end

				element._indicators[idx] = {
					_renderer       = renderer,
					_type           = indConfig.type,
					_castBy         = indConfig.castBy,
					_color          = indConfig.color,
					_spellColors    = indConfig.spellColors,
					_glowType       = indConfig.glowType,
					_glowColor      = indConfig.glowColor,
					_glowConfig     = indConfig.glowConfig,
					_borderGlowMode = indConfig.borderGlowMode,
					_name           = name,
					_spellPriority  = spellPriority,
				}

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
--- Reads from config.indicators[] and assigns result to
--- self.FramedBuffs, activating the element.
--- @param self Frame The oUF unit frame
--- @param config table Configuration with indicators[] array
function F.Elements.Buffs.Setup(self, config)
	if(not self.FramedAuraState and F.AuraState) then
		self.FramedAuraState = F.AuraState.Create(self)
	end

	local indicators = {}
	local spellLookup = {}   -- spellID → { indicatorIndex, ... }
	local hasTrackAll = {}   -- indices of indicators that track all spells (empty spells list)

	for idx, indConfig in next, config.indicators do
		if(indConfig.enabled ~= false) then
			local renderer = createRenderer(self, indConfig)
			if(renderer) then
				-- Position renderers that support SetPoint
				local anchor = indConfig.anchor
				if(renderer.SetPoint) then
					local anchorParent = anchor[2] or self
					local containerPoint = anchor[1]

					-- For Icons, derive container point so first icon is at the anchor
					if(indConfig.type == C.IndicatorType.ICONS) then
						local growDir = indConfig.orientation or defaultGrowForAnchor(anchor[3])
						containerPoint = deriveContainerPoint(anchor[3], growDir)
					end

					renderer:SetPoint(containerPoint, anchorParent, anchor[3], anchor[4], anchor[5])
				end

				-- Set frame level if supported
				if(renderer.GetFrame) then
					local frame = renderer:GetFrame()
					if(frame and frame.SetFrameLevel) then
						frame:SetFrameLevel(indConfig.frameLevel)
					end
				end

				indicators[idx] = {
					_renderer   = renderer,
					_type       = indConfig.type,
					_castBy     = indConfig.castBy,
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
		_buffFilter           = computeBuffFilter(config.indicators),
	}

	container.Rebuild = Rebuild

	self.FramedBuffs = container
end
