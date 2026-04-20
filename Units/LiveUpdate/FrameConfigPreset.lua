local _, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

local Shared = F.LiveUpdate.FrameConfigShared
local ForEachFrame = Shared.ForEachFrame
local STATUS_ELEMENT_MAP = Shared.STATUS_ELEMENT_MAP
local GROUP_TYPES = Shared.GROUP_TYPES
local PSEUDO_GROUPS = Shared.PSEUDO_GROUPS
local getGroupHeader = Shared.getGroupHeader
local repositionFrame = Shared.repositionFrame
local cascadePseudoGroup = Shared.cascadePseudoGroup
local applyOrQueue = Shared.applyOrQueue
local applyGroupLayoutToHeader = Shared.applyGroupLayoutToHeader

-- ============================================================
-- Preset change — re-apply stored element properties from the
-- new preset's config so frames reflect the correct values.
-- ============================================================

--- Apply the full config from the active preset to a single frame.
--- Called on preset switch so frames reflect the correct values after
--- they were initially spawned with a different preset's config.
local function applyFullConfig(frame, config)
	-- Header buttons may exist in oUF.objects before oUF has fully
	-- initialized them (activeElements not yet set). EnableElement
	-- would crash. Health is always present after init, so use it
	-- as a sentinel.
	if(not frame:IsElementEnabled('Health')) then return end

	local unitType = frame._framedUnitType
	-- ── Position (solo frames only) ──────────────────────────
	-- Pinned frames position via Layout() grid, not per-frame SetPoint.
	-- Pseudo-groups (boss/arena) cascade together after the per-frame loop.
	if(not GROUP_TYPES[unitType] and not PSEUDO_GROUPS[unitType] and unitType ~= 'pinned') then
		repositionFrame(frame, config)
	end

	-- ── Dimensions ───────────────────────────────────────────
	local powerHeight = config.power.height
	local healthHeight = config.height - powerHeight
	Widgets.SetSize(frame, config.width, config.height)

	if(frame.Health and frame.Health._wrapper) then
		Widgets.SetSize(frame.Health._wrapper, config.width, healthHeight)
	end

	if(frame.Power and frame.Power._wrapper) then
		Widgets.SetSize(frame.Power._wrapper, config.width, powerHeight)
		local pos = config.power.position
		frame.Power._wrapper:ClearAllPoints()
		frame.Health._wrapper:ClearAllPoints()
		if(pos == 'top') then
			frame.Power._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
			frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -powerHeight)
		else
			frame.Health._wrapper:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
			frame.Power._wrapper:SetPoint('TOPLEFT', frame.Health._wrapper, 'BOTTOMLEFT', 0, 0)
		end
		-- Update which border edge is removed for the shared edge
		if(frame.Power.SetSharedEdge) then
			frame.Power:SetSharedEdge(pos)
		end
	end

	-- ── Show/hide power ──────────────────────────────────────
	if(frame.Power) then
		if(config.showPower ~= false) then
			frame:EnableElement('Power')
			frame.Power:Show()
		else
			frame:DisableElement('Power')
			frame.Power:Hide()
		end
	end

	-- ── Health element ───────────────────────────────────────
	local h = frame.Health
	if(h) then
		local hc = config.health

		-- Text format and color
		h._textFormat      = hc.textFormat
		h._textColorMode   = hc.textColorMode
		h._textCustomColor = hc.textCustomColor
		h._attachedToName  = hc.attachedToName

		-- Show/hide health text (create on demand if preset switch enables it)
		local wantText = hc.showText or hc.attachedToName
		if(wantText and not h.text) then
			local textOverlay = frame._textOverlay
			if(not textOverlay) then
				textOverlay = CreateFrame('Frame', nil, frame)
				textOverlay:SetAllPoints(frame)
				textOverlay:SetFrameLevel(frame:GetFrameLevel() + 5)
				frame._textOverlay = textOverlay
			end
			h.text = Widgets.CreateFontString(textOverlay, hc.fontSize, C.Colors.textActive, hc.outline, hc.shadow ~= false)
		end
		if(h.text) then
			h.text:SetShown(wantText)
		end

		-- Text font / outline / shadow
		if(h.text) then
			h.text:SetFont(F.Media.GetActiveFont(), hc.fontSize, hc.outline)
			if(hc.shadow == false) then
				h.text:SetShadowOffset(0, 0)
			else
				h.text:SetShadowOffset(1, -1)
			end
		end

		-- Text anchor
		if(h.text) then
			h.text:ClearAllPoints()
			if(h._attachedToName and frame.Name) then
				h.text:SetPoint('LEFT', frame.Name, 'RIGHT', 2, 0)
			else
				local ap = hc.textAnchor
				local anchor = h._wrapper or h
				h.text:SetPoint(ap, anchor, ap, hc.textAnchorX + 1, hc.textAnchorY)
				h.text._anchorPoint = ap
				h.text._anchorX = hc.textAnchorX
				h.text._anchorY = hc.textAnchorY
			end
		end

		-- Color mode
		h._colorMode       = hc.colorMode
		h._customColor     = hc.customColor
		h._lossColorMode   = hc.lossColorMode
		h._lossCustomColor = hc.lossCustomColor

		-- Re-apply health bar color mode flags
		h.colorClass    = nil
		h.colorReaction = nil
		h.colorSmooth   = nil
		h.UpdateColor   = nil

		if(h._isNpcFrame) then
			-- NPC frames (target, focus, pet, boss, targettarget) always use the
			-- full oUF chain regardless of colorMode config.
			h.colorTapping  = true
			h.colorThreat   = true
			h.colorClass    = true
			h.colorReaction = true
			h.UpdateColor   = F.Elements.Health.NpcUpdateColor
		else
			local colorMode = hc.colorMode
			if(colorMode == 'class') then
				h.colorClass    = true
				h.colorReaction = true
			elseif(colorMode == 'gradient') then
				h.colorSmooth = true
			elseif(colorMode == 'dark') then
				h.UpdateColor = function(self)
					self.Health:SetStatusBarColor(0.25, 0.25, 0.25)
				end
			elseif(colorMode == 'custom') then
				h.UpdateColor = function(self)
					local cc = self.Health._customColor
					self.Health:SetStatusBarColor(cc[1], cc[2], cc[3])
				end
			end
		end

		-- Smooth
		local smooth = hc.smooth
		h.smoothing = smooth and Enum.StatusBarInterpolation.ExponentialEaseOut
			or Enum.StatusBarInterpolation.Immediate

		-- Heal prediction mode
		if(h._healPredBar) then
			h.HealingAll    = nil
			h.HealingPlayer = nil
			h.HealingOther  = nil
			local mode = hc.healPredictionMode
			if(mode == 'player') then
				h.HealingPlayer = h._healPredBar
			elseif(mode == 'other') then
				h.HealingOther = h._healPredBar
			else
				h.HealingAll = h._healPredBar
			end

			-- Heal prediction toggle
			if(hc.healPrediction ~= false) then
				h._healPredBar:Show()
			else
				h._healPredBar:Hide()
			end

			-- Heal prediction color
			local hpColor = hc.healPredictionColor
			h._healPredBar:SetStatusBarColor(hpColor[1], hpColor[2], hpColor[3], hpColor[4])
		end

		-- Damage absorb (shields)
		if(hc.damageAbsorb ~= false) then
			if(h._damageAbsorbBar) then
				h.DamageAbsorb = h._damageAbsorbBar
				h._damageAbsorbBar:Show()
				local daColor = hc.damageAbsorbColor
				h._damageAbsorbBar:SetStatusBarColor(daColor[1], daColor[2], daColor[3], daColor[4])
			end
		else
			h.DamageAbsorb = nil
			if(h._damageAbsorbBar) then h._damageAbsorbBar:Hide() end
		end

		-- Heal absorb
		if(hc.healAbsorb ~= false) then
			if(h._healAbsorbBar) then
				h.HealAbsorb = h._healAbsorbBar
				h._healAbsorbBar:Show()
				local haColor = hc.healAbsorbColor
				h._healAbsorbBar:SetStatusBarColor(haColor[1], haColor[2], haColor[3], haColor[4])
			end
			if(h._overHealAbsorbIndicator) then
				h.OverHealAbsorbIndicator = h._overHealAbsorbIndicator
			end
		else
			h.HealAbsorb = nil
			if(h._healAbsorbBar) then h._healAbsorbBar:Hide() end
			h.OverHealAbsorbIndicator = nil
			if(h._overHealAbsorbIndicator) then h._overHealAbsorbIndicator:Hide() end
		end

		-- Overshield
		if(hc.overAbsorb ~= false) then
			if(h._overDamageAbsorbIndicator) then
				h.OverDamageAbsorbIndicator = h._overDamageAbsorbIndicator
			end
		else
			h.OverDamageAbsorbIndicator = nil
			if(h._overDamageAbsorbIndicator) then h._overDamageAbsorbIndicator:Hide() end
		end

		-- Pinned slots without an assigned unit have frame.unit = nil; the
		-- element updaters read UnitHealth/UnitPower which error on nil.
		if(frame.unit) then h:ForceUpdate() end
	end

	-- ── Power element ────────────────────────────────────────
	local p = frame.Power
	if(p) then
		local pc = config.power
		p._textFormat      = pc.textFormat
		p._textColorMode   = pc.textColorMode
		p._textCustomColor = pc.textCustomColor
		p._customColors    = pc.customColors

		-- Show/hide power text
		if(p.text) then
			p.text:SetShown(pc.showText ~= false)
		end

		-- Text font / outline / shadow
		if(p.text) then
			p.text:SetFont(F.Media.GetActiveFont(), pc.fontSize, pc.outline)
			if(pc.shadow == false) then
				p.text:SetShadowOffset(0, 0)
			else
				p.text:SetShadowOffset(1, -1)
			end
		end

		-- Text anchor
		if(p.text) then
			p.text:ClearAllPoints()
			local ap = pc.textAnchor
			local anchor = p._wrapper or p
			p.text:SetPoint(ap, anchor, ap, pc.textAnchorX + 1, pc.textAnchorY)
			p.text._anchorPoint = ap
			p.text._anchorX = pc.textAnchorX
			p.text._anchorY = pc.textAnchorY
		end

		if(frame.unit) then p:ForceUpdate() end
	end

	-- ── Name element ────────────────────────────────────────
	if(frame.Name) then
		frame.Name:SetShown(config.showName)

		local nc = config.name

		-- Font / outline / shadow
		local fontSize = nc.fontSize
		local outline = nc.outline
		frame.Name:SetFont(F.Media.GetActiveFont(), fontSize, outline)
		local shadow = nc.shadow
		if(shadow == false) then
			frame.Name:SetShadowOffset(0, 0)
		else
			frame.Name:SetShadowOffset(1, -1)
		end

		-- Anchor — Name anchors to the health wrapper, not the frame.
		-- When health text is attached to name, the centering code in
		-- Health PostUpdate manages Name's position; only store the
		-- base values here so the centering math has correct inputs.
		local nameAnchor = (frame.Health and frame.Health._wrapper) or frame
		local ap = nc.anchor
		local x = nc.anchorX
		local y = nc.anchorY
		frame.Name._anchorPoint = ap
		frame.Name._anchorX = x
		frame.Name._anchorY = y
		if(not (h and h._attachedToName)) then
			frame.Name:ClearAllPoints()
			Widgets.SetPoint(frame.Name, ap, nameAnchor, ap, x, y)
		end

		-- Color mode
		local mode = nc.colorMode
		local customColor = nc.customColor
		frame.Name._config = frame.Name._config or {}
		frame.Name._config.colorMode = mode
		frame.Name._config.customColor = customColor
		if(mode == 'white') then
			local tc = C.Colors.textActive
			frame.Name:SetTextColor(tc[1], tc[2], tc[3], tc[4])
		elseif(mode == 'dark') then
			frame.Name:SetTextColor(0.25, 0.25, 0.25, 1)
		elseif(mode == 'custom') then
			frame.Name:SetTextColor(customColor[1], customColor[2], customColor[3], 1)
		elseif(mode == 'class') then
			local unit = frame.unit or frame:GetAttribute('unit')
			if(unit) then
				local _, class = UnitClass(unit)
				if(class) then
					local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
					if(classColor) then
						frame.Name:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
					end
				end
			end
		end
	end

	-- ── Re-center attached health text ──────────────────────
	-- The Name section above updated _anchorPoint / _anchorX / _anchorY
	-- but skipped the raw SetPoint when attached.  Clear the shift cache
	-- and re-trigger Health so the centering code repositions Name.
	if(frame.Health and frame.Health._attachedToName and frame.Name) then
		frame.Health._lastAttachShift = nil
		if(frame.unit and frame.Health.ForceUpdate) then
			frame.Health:ForceUpdate()
		end
	end

	-- ── Cast bar ─────────────────────────────────────────────
	if(frame.Castbar) then
		if(config.showCastBar ~= false) then
			frame:EnableElement('Castbar')
		else
			frame:DisableElement('Castbar')
		end

		if(frame.Castbar._wrapper) then
			local cbCfg = config.castbar
			if(cbCfg) then
				local cbWidth = (cbCfg.sizeMode == 'detached' and cbCfg.width) or config.width
				Widgets.SetSize(frame.Castbar._wrapper, cbWidth, cbCfg.height)

				local bgMode = cbCfg.backgroundMode
				frame.Castbar._backgroundMode = bgMode
				if(bgMode == 'always') then
					if(frame.Castbar._bg) then frame.Castbar._bg:Show() end
					local bgC = C.Colors.background
					frame.Castbar._wrapper:SetBackdropColor(bgC[1], bgC[2], bgC[3], bgC[4])
				else
					if(frame.Castbar._bg) then frame.Castbar._bg:Hide() end
					frame.Castbar._wrapper:SetBackdropColor(0, 0, 0, 0)
				end
			end
		end
	end

	-- ── Portrait ────────────────────────────────────────────
	local pCfg = config.portrait
	if(pCfg) then
		local wantType = (type(pCfg) == 'table' and pCfg.type) or '2D'
		local curType = frame._portraitType
		if(not frame.Portrait or curType ~= wantType) then
			if(frame.Portrait) then
				frame:DisableElement('Portrait')
				frame.Portrait:Hide()
				frame.Portrait = nil
			end
			F.Elements.Portrait.Setup(frame, config.height, config.height, pCfg == true and {} or pCfg)
			frame.Portrait:ClearAllPoints()
			Widgets.SetPoint(frame.Portrait, 'TOPRIGHT', frame, 'TOPLEFT', -(C.Spacing.base), 0)
			frame._portraitType = wantType
			frame:EnableElement('Portrait')
		end
		frame.Portrait:Show()
		if(frame.unit and frame.Portrait.ForceUpdate) then frame.Portrait:ForceUpdate() end
	else
		if(frame.Portrait) then
			frame:DisableElement('Portrait')
			frame.Portrait:Hide()
		end
	end

	-- ── Status icons ────────────────────────────────────────
	local icons = config.statusIcons
	for iconKey, elementName in next, STATUS_ELEMENT_MAP do
		local enabled = icons[iconKey]
		if(enabled == nil) then
			-- Default: role, leader, readyCheck, raidIcon on; others off
			enabled = (iconKey == 'role' or iconKey == 'leader' or iconKey == 'readyCheck' or iconKey == 'raidIcon')
		end

		if(enabled) then
			frame:EnableElement(elementName)
			local element = frame[elementName]
			if(element) then
				local pt = icons[iconKey .. 'Point']
				local x  = icons[iconKey .. 'X']
				local y  = icons[iconKey .. 'Y']
				local sz = icons[iconKey .. 'Size']
				if(element.SetSize) then
					element:SetSize(sz, sz)
				elseif(element.GetParent and element:IsObjectType('Texture')) then
					Widgets.SetSize(element, sz, sz)
				end
				element:ClearAllPoints()
				Widgets.SetPoint(element, pt, frame, pt, x, y)
			end
		else
			frame:DisableElement(elementName)
		end
	end

	-- ── Status text ─────────────────────────────────────────
	local stCfg = config.statusText
	if(stCfg == true) then stCfg = { enabled = true } end
	if(type(stCfg) == 'table' and stCfg.enabled ~= false) then
		F.Elements.StatusText.Setup(frame, stCfg)
		frame:EnableElement('FramedStatusText')
	else
		frame:DisableElement('FramedStatusText')
	end

end

-- Aura element map for preset switching
local AURA_ELEMENTS = {
	{ key = 'debuffs',        element = 'FramedDebuffs',        setup = 'Debuffs' },
	{ key = 'externals',      element = 'FramedExternals',      setup = 'Externals' },
	{ key = 'defensives',     element = 'FramedDefensives',     setup = 'Defensives' },
	{ key = 'dispellable',    element = 'FramedDispellable',    setup = 'Dispellable' },
	{ key = 'targetedSpells', element = 'FramedTargetedSpells', setup = 'TargetedSpells' },
	{ key = 'buffs',          element = 'FramedBuffs',          setup = 'Buffs' },
	{ key = 'lossOfControl',  element = 'FramedLossOfControl',  setup = 'LossOfControl' },
	{ key = 'crowdControl',   element = 'FramedCrowdControl',   setup = 'CrowdControl' },
	{ key = 'missingBuffs',   element = 'FramedMissingBuffs',   setup = 'MissingBuffs' },
	{ key = 'privateAuras',   element = 'FramedPrivateAuras',   setup = 'PrivateAuras' },
}

F.EventBus:Register('PRESET_CHANGED', function(presetName)
	for _, frame in next, oUF.objects do
		if(frame._framedUnitType and frame:IsElementEnabled('Health')) then
			local unitType = frame._framedUnitType

			-- Pet frames have their own sync block below; skip generic apply
			if(unitType ~= 'partypet') then
				local config = F.StyleBuilder.GetConfig(unitType)
				if(config) then
					applyFullConfig(frame, config)
				end
			end

			-- Re-apply auras from new preset
			-- Party pets share party aura config
			local auraUnitType = (unitType == 'partypet') and 'party' or unitType
			for _, aura in next, AURA_ELEMENTS do
				local auraCfg = F.StyleBuilder.GetAuraConfig(auraUnitType, aura.key)
				local enabled = auraCfg and auraCfg.enabled

				if(enabled) then
					local el = frame[aura.element]
					if(el and el.Rebuild) then
						el:Rebuild(auraCfg)
					elseif(F.Elements[aura.setup] and F.Elements[aura.setup].Setup) then
						F.Elements[aura.setup].Setup(frame, auraCfg)
					end
					frame:EnableElement(aura.element)
				else
					frame:DisableElement(aura.element)
				end
			end
		end
	end

	-- Apply group layout attributes to headers from new preset
	for groupType in next, GROUP_TYPES do
		local header = getGroupHeader(groupType)
		if(header) then
			local config = F.StyleBuilder.GetConfig(groupType)
			if(config) then
				applyGroupLayoutToHeader(header, config)
				applyOrQueue(header, 'initial-width', config.width)
				applyOrQueue(header, 'initial-height', config.height)
			end
		end
	end

	-- Re-cascade pseudo-groups (boss/arena) from new preset's position + spacing
	for pseudoType in next, PSEUDO_GROUPS do
		local config = F.StyleBuilder.GetConfig(pseudoType)
		if(config) then
			cascadePseudoGroup(pseudoType, config)
		end
	end

	-- Sync pet frames from new preset
	if(F.Units.Party.petFrames) then
		local petCfg = F.Units.Party.GetPetConfig()
		local partyConfig = F.StyleBuilder.GetConfig('party')
		local enabled = petCfg.enabled ~= false

		F.Units.Party.SetPetsEnabled(enabled)

		if(enabled and partyConfig) then
			-- Resize pet frames to match party frame size
			local w = partyConfig.width
			local h = partyConfig.height
			ForEachFrame('partypet', function(frame)
				Widgets.SetSize(frame, w, h)
				if(frame.Health and frame.Health._wrapper) then
					Widgets.SetSize(frame.Health._wrapper, w, h)
				end
			end)
			F.Units.Party.AnchorPetFrames()
		end
	end
end, 'LiveUpdate.PresetChanged')
