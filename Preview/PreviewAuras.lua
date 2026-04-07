local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.PreviewAuras = {}
local PA = F.PreviewAuras

local PI = F.PreviewIndicators

-- ============================================================
-- Aura group alpha (dim/highlight)
-- ============================================================

function PA.SetAuraGroupAlpha(frame, activeGroupId)
	if(not frame._auraGroups) then return end
	for groupId, groupFrame in next, frame._auraGroups do
		local alpha = (activeGroupId == nil or groupId == activeGroupId) and 1.0 or 0.2
		groupFrame:SetAlpha(alpha)
		-- Elements parented outside groupFrame (border glows, overlays,
		-- dispel highlights) need alpha set explicitly
		if(groupFrame._healthOverlay) then
			groupFrame._healthOverlay:SetAlpha(alpha)
		end
		if(groupFrame._elements) then
			for _, el in next, groupFrame._elements do
				if(el:GetParent() ~= groupFrame) then
					el:SetAlpha(alpha)
				end
			end
		end
	end
end

--- Update the dispel overlay texture alpha without a full rebuild.
--- @param frame table  The preview frame
--- @param alpha number  New highlight alpha (0-1)
function PA.UpdateDispelOverlayAlpha(frame, alpha)
	if(not frame or not frame._auraGroups) then return end
	local group = frame._auraGroups.dispellable
	if(not group or not group._highlightTexture or not group._highlightColor) then return end
	local c = group._highlightColor
	group._highlightTexture:SetVertexColor(c[1], c[2], c[3], alpha)
end

-- ============================================================
-- Buff indicators (Icon, Icons, Bar, Bars, Border, Rectangle, Overlay)
-- ============================================================

local function BuildBuffIndicators(frame, buffsConfig, animated)
	if(not buffsConfig or not buffsConfig.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}
	local fakeIcons = PI.GetFakeIcons('buffs')

	for _, indCfg in next, buffsConfig.indicators or {} do
		if(indCfg.enabled ~= false) then
			local indType = indCfg.type
			local pt, relFrame, relPt, offX, offY = PI.UnpackAnchor(indCfg.anchor, { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 })

			if(indType == C.IndicatorType.ICON) then
				local w = indCfg.iconWidth or 14
				local h = indCfg.iconHeight or 14
				if(indCfg.displayType == C.IconDisplay.COLORED_SQUARE) then
					local rect = PI.CreateColorRect(groupFrame, { rectWidth = w, rectHeight = h, color = indCfg.color or { 1, 1, 1, 1 } })
					rect:SetPoint(pt, frame, relPt, offX, offY)
					groupFrame._elements[#groupFrame._elements + 1] = rect
				else
					local icon = PI.CreateIcon(groupFrame, fakeIcons[1], w, h, indCfg, animated)
					icon:SetPoint(pt, frame, relPt, offX, offY)
					groupFrame._elements[#groupFrame._elements + 1] = icon
				end

			elseif(indType == C.IndicatorType.ICONS) then
				local max = math.min(indCfg.maxDisplayed or 3, 5)
				local w = indCfg.iconWidth or 14
				local h = indCfg.iconHeight or 14
				local isSquare = (indCfg.displayType == C.IconDisplay.COLORED_SQUARE)
				for i = 1, max do
					local elem
					if(isSquare) then
						elem = PI.CreateColorRect(groupFrame, { rectWidth = w, rectHeight = h, color = indCfg.color or { 1, 1, 1, 1 } })
					else
						elem = PI.CreateIcon(groupFrame, fakeIcons[((i-1) % #fakeIcons) + 1], w, h, indCfg, animated)
					end
					local dx, dy = PI.OrientOffset(indCfg.orientation or 'RIGHT', i, w, h, indCfg.spacingX, indCfg.spacingY)
					elem:SetPoint(pt, frame, relPt, offX + dx, offY + dy)
					groupFrame._elements[#groupFrame._elements + 1] = elem
				end

			elseif(indType == C.IndicatorType.BAR) then
				local bar = PI.CreateBar(groupFrame, indCfg, animated)
				bar:SetPoint(pt, frame, relPt, offX, offY)
				groupFrame._elements[#groupFrame._elements + 1] = bar

			elseif(indType == C.IndicatorType.BARS) then
				local max = math.min(indCfg.maxDisplayed or 3, 5)
				for i = 1, max do
					local bar = PI.CreateBar(groupFrame, indCfg, animated)
					local dx, dy = PI.OrientOffset(indCfg.orientation or 'DOWN', i,
						indCfg.barWidth or 50, indCfg.barHeight or 4, indCfg.spacingX, indCfg.spacingY)
					bar:SetPoint(pt, frame, relPt, offX + dx, offY + dy)
					groupFrame._elements[#groupFrame._elements + 1] = bar
				end

			elseif(indType == C.IndicatorType.BORDER) then
				local bg = PI.CreateBorderGlow(frame, indCfg, animated)
				groupFrame._elements[#groupFrame._elements + 1] = bg

			elseif(indType == C.IndicatorType.RECTANGLE) then
				local rect = PI.CreateColorRect(groupFrame, indCfg)
				rect:SetPoint(pt, frame, relPt, offX, offY)
				groupFrame._elements[#groupFrame._elements + 1] = rect

			elseif(indType == C.IndicatorType.OVERLAY) then
				local overlay = PI.CreateOverlay(frame._healthWrapper, indCfg, animated)
				if(overlay) then
					groupFrame._elements[#groupFrame._elements + 1] = overlay
				end
			end
		end
	end

	return groupFrame
end

-- ============================================================
-- Border icon groups (debuffs, externals, defensives)
-- ============================================================

local BORDICON_GROUPS = { 'debuffs', 'externals', 'defensives', 'targetedSpells' }

local GROUP_DISPEL_TYPES = {
	debuffs        = { 'Magic', 'Curse', 'Poison' },
	externals      = {},
	defensives     = {},
	targetedSpells = {},
}

-- Build alternating border colors for source-colored groups (externals, defensives)
local function getSourceColors(indCfg)
	local playerColor = indCfg.playerColor
	local otherColor = indCfg.otherColor
	if(playerColor and otherColor) then
		return { playerColor, otherColor }
	end
	return nil
end

local function buildBorderIconRow(groupFrame, frame, groupKey, indCfg, animated)
	local pt, _, relPt, offX, offY = PI.UnpackAnchor(indCfg.anchor)
	local size = indCfg.iconSize or 14
	local max = math.min(indCfg.maxDisplayed or 3, 5)
	local orient = indCfg.orientation or 'RIGHT'
	local fakeIcons = PI.GetFakeIcons(groupKey)
	local fakeDispels = GROUP_DISPEL_TYPES[groupKey] or {}
	local borderThick = indCfg.borderThickness or 2
	local sourceColors = getSourceColors(indCfg)

	for i = 1, max do
		local dispel = fakeDispels[((i-1) % math.max(#fakeDispels, 1)) + 1]
		local borderColor = sourceColors and sourceColors[((i-1) % #sourceColors) + 1]
			or indCfg.borderColor
			or nil
		local bi = PI.CreateBorderIcon(groupFrame, fakeIcons[((i-1) % #fakeIcons) + 1], size, borderThick, dispel, indCfg, animated, borderColor)
		local dx, dy = PI.OrientOffset(orient, i, size, size, 2, 2)
		bi:SetPoint(pt, frame, relPt, offX + dx, offY + dy)
		groupFrame._elements[#groupFrame._elements + 1] = bi
	end
end

local function BuildBorderIconGroup(frame, groupKey, groupCfg, animated)
	if(not groupCfg or not groupCfg.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}

	-- Debuffs have named indicators, each with their own anchor/size
	if(groupCfg.indicators) then
		for _, indCfg in next, groupCfg.indicators do
			if(indCfg.enabled ~= false) then
				buildBorderIconRow(groupFrame, frame, groupKey, indCfg, animated)
			end
		end
	else
		-- Flat config (externals, defensives)
		buildBorderIconRow(groupFrame, frame, groupKey, groupCfg, animated)
	end

	return groupFrame
end

-- ============================================================
-- Dispellable group (atlas icon + health bar overlay)
-- ============================================================

local DISPEL_PREVIEW_TYPE = 'Magic'
local DISPEL_ATLASES = {
	Magic   = 'RaidFrame-Icon-DebuffMagic',
	Curse   = 'RaidFrame-Icon-DebuffCurse',
	Disease = 'RaidFrame-Icon-DebuffDisease',
	Poison  = 'RaidFrame-Icon-DebuffPoison',
	Bleed   = 'RaidFrame-Icon-DebuffBleed',
}
local GRADIENT_TEXTURE = [[Interface\AddOns\Framed\Media\Textures\Gradient_Linear_Bottom]]

local function BuildDispellableGroup(frame, dispCfg)
	if(not dispCfg or not dispCfg.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}

	-- 1. Dispel type icon (atlas, not spell texture)
	local pt, _, relPt, offX, offY = PI.UnpackAnchor(dispCfg.anchor)
	local size = dispCfg.iconSize or 14
	local iconFrame = CreateFrame('Frame', nil, groupFrame)
	iconFrame:SetSize(size, size)
	iconFrame:SetPoint(pt, frame, relPt, offX, offY)

	local atlas = DISPEL_ATLASES[DISPEL_PREVIEW_TYPE]
	local tex = iconFrame:CreateTexture(nil, 'ARTWORK')
	tex:SetAllPoints(iconFrame)
	tex:SetAtlas(atlas)
	groupFrame._elements[1] = iconFrame

	-- 2. Health bar overlay matching the user's highlightType setting.
	-- Child frame of health wrapper with explicit size (from frame._width/_height)
	-- so it doesn't depend on anchor resolution. SetClipsChildren prevents any
	-- rendering outside bounds. Tracked via groupFrame._healthOverlay for dim control.
	local hlType = dispCfg.highlightType
	if(frame._healthWrapper and frame._healthBar and hlType) then
		local hlColor = PI.DISPEL_COLORS[DISPEL_PREVIEW_TYPE] or { 0.2, 0.6, 1.0 }
		local hlAlpha = dispCfg.highlightAlpha or 0.8
		local wrapper = frame._healthWrapper
		local fw = frame._width or 120
		local fh = frame._height or 36
		-- Health wrapper height = frame height minus power bar height
		local pwh = (frame._powerWrapper and frame._powerWrapper:GetHeight()) or 0
		local wh = fh - pwh

		local overlayFrame = CreateFrame('Frame', nil, wrapper)
		overlayFrame:SetPoint('TOPLEFT', wrapper, 'TOPLEFT')
		overlayFrame:SetSize(fw, wh)
		overlayFrame:SetFrameLevel(frame._healthBar:GetFrameLevel() + 5)
		overlayFrame:SetClipsChildren(true)

		local hl
		if(hlType == 'gradient_full') then
			hl = overlayFrame:CreateTexture(nil, 'OVERLAY')
			hl:SetPoint('TOPLEFT', 1, -1)
			hl:SetPoint('BOTTOMRIGHT', -1, 1)
			hl:SetTexture(GRADIENT_TEXTURE)
			hl:SetBlendMode('BLEND')
			hl:SetVertexColor(hlColor[1], hlColor[2], hlColor[3], hlAlpha)
		elseif(hlType == 'gradient_half') then
			hl = overlayFrame:CreateTexture(nil, 'OVERLAY')
			hl:SetTexture(GRADIENT_TEXTURE)
			hl:SetBlendMode('BLEND')
			hl:SetVertexColor(hlColor[1], hlColor[2], hlColor[3], hlAlpha)
			hl:SetPoint('BOTTOMLEFT', 1, 1)
			hl:SetPoint('BOTTOMRIGHT', -1, 1)
			hl:SetHeight(wh * 0.5)
		elseif(hlType == 'solid_current') then
			hl = overlayFrame:CreateTexture(nil, 'OVERLAY')
			hl:SetPoint('TOPLEFT', 1, -1)
			hl:SetPoint('BOTTOMLEFT', 1, 1)
			hl:SetTexture([[Interface\BUTTONS\WHITE8x8]])
			hl:SetBlendMode('ADD')
			hl:SetVertexColor(hlColor[1], hlColor[2], hlColor[3], hlAlpha)
			hl:SetWidth(1)
		elseif(hlType == 'solid_entire') then
			hl = overlayFrame:CreateTexture(nil, 'OVERLAY')
			hl:SetAllPoints(overlayFrame)
			hl:SetTexture([[Interface\BUTTONS\WHITE8x8]])
			hl:SetBlendMode('ADD')
			hl:SetVertexColor(hlColor[1], hlColor[2], hlColor[3], hlAlpha)
		end

		if(hl) then
			groupFrame._healthOverlay = overlayFrame
			groupFrame._highlightTexture = hl
			groupFrame._highlightColor = hlColor
		end
	end

	return groupFrame
end

-- ============================================================
-- Simple icon groups (missingBuffs, privateAuras, targetedSpells, etc.)
-- ============================================================

local function BuildSimpleIconGroup(frame, groupKey, cfg)
	if(not cfg or not cfg.enabled) then return nil end

	local groupFrame = CreateFrame('Frame', nil, frame)
	groupFrame:SetAllPoints(frame)
	groupFrame._elements = {}

	local pt, _, relPt, offX, offY = PI.UnpackAnchor(cfg.anchor)
	local size = cfg.iconSize or 16
	local fakeIcons = PI.GetFakeIcons(groupKey)

	if(groupKey == 'missingBuffs') then
		local bi = PI.CreateBorderIcon(groupFrame, fakeIcons[1], size, 1, nil, { showCooldown = false, showDuration = false })
		bi:SetPoint(pt, frame, relPt, offX, offY)
		groupFrame._elements[1] = bi
	else
		local icon = PI.CreateIcon(groupFrame, fakeIcons[1], size, size, { showCooldown = false, durationMode = 'Never', showStacks = false })
		icon:SetPoint(pt, frame, relPt, offX, offY)
		groupFrame._elements[1] = icon
	end

	return groupFrame
end

-- ============================================================
-- Public: build all aura groups for a preview frame
-- ============================================================

function PA.BuildAll(frame, auraConfig, animated)
	-- Clean up previous groups before rebuilding
	if(frame._auraGroups) then
		for _, groupFrame in next, frame._auraGroups do
			-- Elements parented outside groupFrame (border glows, overlays,
			-- dispel highlights) must be explicitly cleaned up
			if(groupFrame._healthOverlay) then
				groupFrame._healthOverlay:Hide()
				groupFrame._healthOverlay:SetParent(nil)
			end
			if(groupFrame._elements) then
				for _, el in next, groupFrame._elements do
					if(el:GetParent() ~= groupFrame) then
						el:Hide()
						el:SetParent(nil)
					end
				end
			end
			groupFrame:Hide()
			groupFrame:SetParent(nil)
		end
	end

	local auraLevel = frame:GetFrameLevel() + 20
	frame._auraGroups = {}
	if(not auraConfig) then return end

	frame._auraGroups.buffs = BuildBuffIndicators(frame, auraConfig.buffs, animated)
	for _, groupKey in next, BORDICON_GROUPS do
		frame._auraGroups[groupKey] = BuildBorderIconGroup(frame, groupKey, auraConfig[groupKey], animated)
	end
	frame._auraGroups.dispellable = BuildDispellableGroup(frame, auraConfig.dispellable)
	frame._auraGroups.missingBuffs = BuildSimpleIconGroup(frame, 'missingBuffs', auraConfig.missingBuffs)
	frame._auraGroups.privateAuras = BuildSimpleIconGroup(frame, 'privateAuras', auraConfig.privateAuras)
	frame._auraGroups.lossOfControl = BuildSimpleIconGroup(frame, 'lossOfControl', auraConfig.lossOfControl)
	frame._auraGroups.crowdControl = BuildSimpleIconGroup(frame, 'crowdControl', auraConfig.crowdControl)
	for _, groupFrame in next, frame._auraGroups do
		groupFrame:SetFrameLevel(auraLevel)
	end

	frame.SetAuraGroupAlpha = PA.SetAuraGroupAlpha
end
