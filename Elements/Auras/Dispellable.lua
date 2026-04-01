local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Dispellable = {}

-- ============================================================
-- Dispel type definitions
-- ============================================================

-- Maps oUF DispelType enum indices to display names and atlas icons.
-- Order determines icon stacking when bracket curves are used.
local DISPEL_TYPES = {
	{ name = 'Magic',   colorKey = 'Magic',    atlas = 'RaidFrame-Icon-DebuffMagic' },
	{ name = 'Curse',   colorKey = 'Curse',    atlas = 'RaidFrame-Icon-DebuffCurse' },
	{ name = 'Disease', colorKey = 'Disease',  atlas = 'RaidFrame-Icon-DebuffDisease' },
	{ name = 'Poison',  colorKey = 'Poison',   atlas = 'RaidFrame-Icon-DebuffPoison' },
	{ name = 'Bleed',   colorKey = 'Physical', atlas = 'RaidFrame-Icon-DebuffBleed' },
}

-- Gradient texture for secret-safe overlay. The alpha gradient is baked
-- into the texture file; color is applied via SetVertexColor (C-level).
local GRADIENT_TEXTURE = [[Interface\AddOns\Framed\Media\Textures\Gradient_Linear_Bottom]]

-- ============================================================
-- Curve infrastructure (secret-safe, initialized once)
-- ============================================================

local curvesReady = false
local highlightCurve   -- maps dispel type index → display color
local bracketCurves    -- [typeName] → curve that returns alpha=1 for match, alpha=0 for others

do
	if(C_CurveUtil and C_CurveUtil.CreateColorCurve
		and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor
		and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step) then

		local dt = oUF and oUF.Enum and oUF.Enum.DispelType
		if(dt) then
			local stepType = Enum.LuaCurveType.Step
			local transparent = CreateColor(0, 0, 0, 0)

			-- Highlight curve: each dispel type → its display color
			highlightCurve = C_CurveUtil.CreateColorCurve()
			highlightCurve:SetType(stepType)
			highlightCurve:AddPoint(dt.None, transparent)
			for _, t in next, DISPEL_TYPES do
				local idx = dt[t.name]
				if(idx) then
					local rgb = C.Colors.dispel[t.colorKey]
					if(rgb) then
						highlightCurve:AddPoint(idx, CreateColor(rgb[1], rgb[2], rgb[3], 1))
					end
				end
			end
			if(dt.Enrage) then
				highlightCurve:AddPoint(dt.Enrage, transparent)
			end

			-- Bracket curves: isolate each type.
			-- For a given type, the curve returns alpha=1 at that type's index
			-- and alpha=0 at adjacent indices. SetAlpha (C-level) reveals
			-- the correct icon without knowing the type at the Lua level.
			bracketCurves = {}
			local sortedIndices = {}
			for _, t in next, DISPEL_TYPES do
				local idx = dt[t.name]
				if(idx) then
					sortedIndices[#sortedIndices + 1] = { name = t.name, colorKey = t.colorKey, idx = idx }
				end
			end
			table.sort(sortedIndices, function(a, b) return a.idx < b.idx end)

			for i, entry in next, sortedIndices do
				local curve = C_CurveUtil.CreateColorCurve()
				curve:SetType(stepType)
				curve:AddPoint(0, transparent)
				local rgb = C.Colors.dispel[entry.colorKey]
				if(rgb) then
					curve:AddPoint(entry.idx, CreateColor(rgb[1], rgb[2], rgb[3], 1))
				end
				-- Next index closes the bracket (back to transparent)
				local nextEntry = sortedIndices[i + 1]
				if(nextEntry) then
					curve:AddPoint(nextEntry.idx, transparent)
				end
				bracketCurves[entry.name] = curve
			end

			curvesReady = true
		end
	end
end

-- ============================================================
-- Overlay helpers
-- ============================================================

local OVERLAY_ALPHA = 0.8

local function hideAllOverlays(element)
	if(element._overlayGradientFull) then element._overlayGradientFull:Hide() end
	if(element._overlayGradientHalf) then element._overlayGradientHalf:Hide() end
	if(element._overlaySolidCurrent) then element._overlaySolidCurrent:Hide() end
	if(element._overlaySolidEntire) then element._overlaySolidEntire:Hide() end
end

--- Ensure overlay textures are positioned on first use.
--- SetPoint is deferred from creation because it runs inside
--- CallMethod from SecureGroupHeaderTemplate where SetPoint fails.
local function ensureOverlayPositioned(element)
	if(element._overlaysPositioned) then return end
	element._overlaysPositioned = true

	local overlayFrame = element._overlayFrame
	local healthWrapper = element._healthWrapper
	if(overlayFrame and healthWrapper) then
		overlayFrame:SetAllPoints(healthWrapper)
	end

	local gradFull = element._overlayGradientFull
	if(gradFull) then
		gradFull:SetPoint('TOPLEFT', 1, -1)
		gradFull:SetPoint('BOTTOMRIGHT', -1, 1)
	end

	local gradHalf = element._overlayGradientHalf
	if(gradHalf) then
		gradHalf:SetPoint('BOTTOMLEFT', 1, 1)
		gradHalf:SetPoint('BOTTOMRIGHT', -1, 1)
		local parent = gradHalf:GetParent()
		if(parent) then
			gradHalf:SetHeight((parent:GetHeight() or 20) * 0.5)
		end
	end

	local solidCur = element._overlaySolidCurrent
	if(solidCur) then
		solidCur:SetPoint('TOPLEFT', 1, -1)
		solidCur:SetPoint('BOTTOMLEFT', 1, 1)
	end

	local solidEnt = element._overlaySolidEntire
	if(solidEnt) then
		solidEnt:SetAllPoints()
	end
end

--- Show the appropriate overlay. Color applied via SetVertexColor
--- (C-level, accepts secret values). Gradient overlays use a pre-baked
--- gradient texture so no CreateColor is needed at runtime.
local function showOverlay(element, highlightType, r, g, b, a)
	hideAllOverlays(element)
	ensureOverlayPositioned(element)

	local ht = C.HighlightType
	if(highlightType == ht.GRADIENT_FULL and element._overlayGradientFull) then
		local tex = element._overlayGradientFull
		tex:SetVertexColor(r, g, b, a or OVERLAY_ALPHA)
		tex:Show()
	elseif(highlightType == ht.GRADIENT_HALF and element._overlayGradientHalf) then
		local tex = element._overlayGradientHalf
		tex:SetVertexColor(r, g, b, a or OVERLAY_ALPHA)
		tex:Show()
	elseif(highlightType == ht.SOLID_CURRENT and element._overlaySolidCurrent) then
		local tex = element._overlaySolidCurrent
		tex:SetVertexColor(r, g, b, a or OVERLAY_ALPHA)
		tex:Show()
	elseif(highlightType == ht.SOLID_ENTIRE and element._overlaySolidEntire) then
		local tex = element._overlaySolidEntire
		tex:SetVertexColor(r, g, b, a or OVERLAY_ALPHA)
		tex:Show()
	end
end

-- ============================================================
-- Dispel icon helpers
-- ============================================================

local function hideAllIcons(element)
	for _, icon in next, element._icons do
		icon:Hide()
	end
	element._iconFrame:Hide()
end

--- Show dispel type icon via bracket curves. All 5 type icons are
--- pre-created with their atlas. Each icon's alpha is set via the
--- bracket curve for that type — C-level SetAlpha reveals the correct
--- icon (alpha=1) and hides others (alpha=0) without knowing the type.
local function showDispelIcons(element, unit, auraInstanceID)
	if(not curvesReady) then return end

	element._iconFrame:Show()
	for _, entry in next, DISPEL_TYPES do
		local icon = element._icons[entry.name]
		local curve = bracketCurves[entry.name]
		if(icon and curve) then
			local color = C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
			if(color) then
				local _, _, _, a = color:GetRGBA()
				icon:SetAlpha(a)  -- C-level, accepts secret alpha
			else
				icon:SetAlpha(0)
			end
			icon:Show()
		end
	end
end

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedDispellable
	if(not element) then return end

	if(not unit or self.unit ~= unit) then return end
	if(not curvesReady) then return end

	local onlyDispellableByMe = element._onlyDispellableByMe

	-- Find the first dispellable debuff. Non-nil dispelName (may be
	-- secret) means the aura is dispellable. auraInstanceID is
	-- NeverSecret — safe to store and pass to curve APIs.
	local dispelAuraID = nil
	local primaryFilter = onlyDispellableByMe and 'HARMFUL|RAID_PLAYER_DISPELLABLE' or 'HARMFUL'
	local allAuras = C_UnitAuras.GetUnitAuras(unit, primaryFilter)

	for _, auraData in next, allAuras do
		if(auraData.dispelName) then
			dispelAuraID = auraData.auraInstanceID
			break
		end
	end

	if(dispelAuraID) then
		-- Show icon via bracket curves (secret-safe)
		showDispelIcons(element, unit, dispelAuraID)

		-- Show overlay via highlight curve (secret-safe).
		-- Ignore the curve's alpha (1.0) — use our own OVERLAY_ALPHA
		-- to avoid a bright/washed overlay with ADD blend mode.
		local hlColor = C_UnitAuras.GetAuraDispelTypeColor(unit, dispelAuraID, highlightCurve)
		if(hlColor and element._highlightType) then
			local cr, cg, cb = hlColor:GetRGB()
			showOverlay(element, element._highlightType, cr, cg, cb)
		end
	else
		hideAllIcons(element)
		hideAllOverlays(element)
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

	hideAllIcons(element)
	hideAllOverlays(element)

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
--- Shows the highest-priority dispel type icon (via bracket curves)
--- plus a highlight overlay on the health bar (via highlight curve).
--- All display is secret-safe via C-level APIs.
--- @param self Frame  The oUF unit frame
--- @param config? table  { enabled, onlyDispellableByMe, highlightType, iconSize, anchor, frameLevel }
function F.Elements.Dispellable.Setup(self, config)
	config = config or {}
	local iconSize       = config.iconSize       or 10
	local highlightType  = config.highlightType  or C.HighlightType.GRADIENT_FULL
	local frameLevel     = config.frameLevel     or (self:GetFrameLevel() + 6)
	local anchor         = config.anchor

	-- 1. Create icon frame with one texture per dispel type.
	-- All icons are stacked on top of each other; bracket curves
	-- control alpha to reveal only the matching type.
	local iconFrame = CreateFrame('Frame', nil, self)
	Widgets.SetSize(iconFrame, iconSize, iconSize)
	iconFrame:SetFrameLevel(frameLevel)
	iconFrame:Hide()

	if(anchor) then
		iconFrame:SetPoint(anchor[1], self, anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0)
	else
		iconFrame:SetPoint('BOTTOMRIGHT', self, 'BOTTOMRIGHT', -2, 2)
	end

	local icons = {}
	for _, entry in next, DISPEL_TYPES do
		local tex = iconFrame:CreateTexture(nil, 'ARTWORK')
		tex:SetAllPoints(iconFrame)
		tex:SetAtlas(entry.atlas)
		tex:SetAlpha(0)
		tex:Hide()
		icons[entry.name] = tex
	end

	-- 2. Create overlay textures on the health bar
	local healthBar = self.Health
	local healthWrapper = healthBar and healthBar._wrapper

	-- Overlay frame: parented to self (unit frame) so it stacks above
	-- the health StatusBar and its child frames (absorb, heal bars).
	-- IMPORTANT: NO SetPoint/SetAllPoints here — deferred to first use.
	local overlayFrame
	if(healthWrapper) then
		overlayFrame = CreateFrame('Frame', nil, self)
		overlayFrame:SetFrameLevel(healthBar:GetFrameLevel() + 5)
	end

	-- Gradient overlays use a pre-baked gradient texture so the gradient
	-- comes from the texture file. Color is applied via SetVertexColor
	-- (C-level, secret-safe). No CreateColor needed at runtime.
	local gradientFull
	if(overlayFrame) then
		gradientFull = overlayFrame:CreateTexture(nil, 'OVERLAY')
		gradientFull:SetTexture(GRADIENT_TEXTURE)
		gradientFull:SetBlendMode('BLEND')
		gradientFull:Hide()
	end

	local gradientHalf
	if(overlayFrame) then
		gradientHalf = overlayFrame:CreateTexture(nil, 'OVERLAY')
		gradientHalf:SetTexture(GRADIENT_TEXTURE)
		gradientHalf:SetBlendMode('BLEND')
		gradientHalf:Hide()
	end

	local solidCurrent
	if(overlayFrame) then
		solidCurrent = overlayFrame:CreateTexture(nil, 'OVERLAY')
		solidCurrent:SetTexture([[Interface\BUTTONS\WHITE8x8]])
		solidCurrent:SetWidth(1)
		solidCurrent:SetBlendMode('ADD')
		solidCurrent:Hide()
		healthBar._dispelOverlay = solidCurrent
	end

	local solidEntire
	solidEntire = self:CreateTexture(nil, 'OVERLAY')
	solidEntire:SetTexture([[Interface\BUTTONS\WHITE8x8]])
	solidEntire:SetBlendMode('ADD')
	solidEntire:Hide()

	-- 3. Build element container
	local container = {
		_iconFrame             = iconFrame,
		_icons                 = icons,
		_overlayFrame          = overlayFrame,
		_healthWrapper         = healthWrapper,
		_highlightType         = highlightType,
		_onlyDispellableByMe   = config.onlyDispellableByMe or false,
		_overlayGradientFull   = gradientFull,
		_overlayGradientHalf   = gradientHalf,
		_overlaySolidCurrent   = solidCurrent,
		_overlaySolidEntire    = solidEntire,
	}

	self.FramedDispellable = container
end
