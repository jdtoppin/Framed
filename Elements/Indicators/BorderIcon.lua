local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.BorderIcon = {}

-- ============================================================
-- Dispel color curve (lazy-initialized singleton)
-- ============================================================

local dispelColorCurve

--- Build a dispel color curve from C.Colors.dispel using oUF's
--- DispelType enum indices. Lazy-initialized on first use.
local function getDispelColorCurve()
	if(dispelColorCurve) then return dispelColorCurve end
	if(not C_CurveUtil or not C_CurveUtil.CreateColorCurve) then return nil end

	local oUF = F.oUF
	if(not oUF or not oUF.Enum or not oUF.Enum.DispelType) then return nil end

	dispelColorCurve = C_CurveUtil.CreateColorCurve()
	dispelColorCurve:SetType(Enum.LuaCurveType.Step)

	-- Map our C.Colors.dispel string keys to oUF DispelType numeric indices
	local dispelTypes = oUF.Enum.DispelType
	for name, index in next, dispelTypes do
		local rgb = C.Colors.dispel[name]
		if(rgb) then
			dispelColorCurve:AddPoint(index, CreateColor(rgb[1], rgb[2], rgb[3], 1))
		end
	end

	return dispelColorCurve
end

-- ============================================================
-- BorderIcon methods
-- ============================================================

local BorderIconMethods = {}

--- Set the displayed aura data on this border icon.
--- Supports two calling conventions:
---   New (secret-safe): SetAura(unit, auraInstanceID, spellId, iconTexture, duration, expirationTime, count, dispelType)
---   Legacy:            SetAura(spellId, iconTexture, duration, expirationTime, count, dispelType)
--- When unit + auraInstanceID are provided, C-level APIs are used for
--- cooldown (DurationObject), stacks, and dispel color (secret-safe).
--- Duration display is handled by Blizzard's built-in cooldown countdown
--- via SetCooldownFromDurationObject — secret-safe, no Lua math needed.
--- Without unit + auraInstanceID, falls back to legacy behavior.
function BorderIconMethods:SetAura(...)
	local unit, auraInstanceID, spellId, iconTexture, duration, expirationTime, count, dispelType

	local arg1, arg2 = ...
	-- Detect new vs legacy signature: if first arg is a string (unit token)
	-- and second arg is a number (auraInstanceID), it's the new signature.
	if(type(arg1) == 'string' and type(arg2) == 'number') then
		unit, auraInstanceID, spellId, iconTexture, duration, expirationTime, count, dispelType = ...
	else
		spellId, iconTexture, duration, expirationTime, count, dispelType = ...
	end

	-- Store for OnUpdate and other deferred lookups
	self._unit = unit
	self._auraInstanceID = auraInstanceID

	-- Icon texture
	if(iconTexture) then
		self.icon:SetTexture(iconTexture)
	elseif(spellId and F.IsValueNonSecret(spellId)) then
		local tex
		if(C_Spell and C_Spell.GetSpellInfo) then
			local info = C_Spell.GetSpellInfo(spellId)
			if(info) then tex = info.iconID end
		elseif(GetSpellInfo) then
			local _, _, ic = GetSpellInfo(spellId)
			tex = ic
		end
		self.icon:SetTexture(tex)
	end

	-- Border color from dispel type (only when dispelType is non-nil).
	-- Non-dispellable auras have dispelName = nil (not secret-nil), so
	-- the truthiness check safely skips them — callers set their own
	-- default border color before SetAura.
	if(dispelType) then
		if(unit and auraInstanceID) then
			-- New path: C-level dispel color via curve (handles secret dispelType)
			local curve = getDispelColorCurve()
			if(curve) then
				local color = C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
				if(color and F.IsValueNonSecret(color)) then
					self:SetBorderColor(color:GetRGBA())
				end
			end
		elseif(F.IsValueNonSecret(dispelType)) then
			-- Legacy path: manual color lookup
			local color = C.Colors.dispel[dispelType]
			if(color) then
				self:SetBorderColor(color[1], color[2], color[3], 1)
			end
		end
	end

	-- Cooldown swipe + DurationObject for duration text.
	-- SetReverse(true) applied after each cooldown API call because
	-- SetCooldownFromDurationObject/SetCooldown reset the reverse flag.
	-- Callers can override direction after SetAura if needed.
	if(unit and auraInstanceID) then
		local durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
		if(durationObj) then
			if(self.cooldown) then
				self.cooldown:SetCooldownFromDurationObject(durationObj)
				self.cooldown:SetReverse(true)
			end
		elseif(self.cooldown) then
			self.cooldown:Clear()
		end
	elseif(self.cooldown) then
		-- Legacy path: raw SetCooldown (works in untainted contexts only)
		local durationSafe = F.IsValueNonSecret(duration)
		local expirationSafe = F.IsValueNonSecret(expirationTime)
		if(durationSafe and expirationSafe and duration and duration > 0 and expirationTime and expirationTime > 0) then
			local startTime = expirationTime - duration
			self.cooldown:SetCooldown(startTime, duration)
			self.cooldown:SetReverse(true)
		else
			self.cooldown:Clear()
		end
	end

	-- Reparent Blizzard's countdown text to iconFrame (above cooldown).
	-- Blizzard creates the FontString lazily on first cooldown set.
	-- Guard ensures we only reparent once per BorderIcon instance.
	if(self.cooldown and not self._countdownReparented) then
		local cdText = self.cooldown.GetCountdownFontString and self.cooldown:GetCountdownFontString()
		if(cdText) then
			cdText:SetParent(self._iconFrame)
			cdText:ClearAllPoints()
			cdText:SetPoint('CENTER', self._iconFrame, 'CENTER', 0, 0)
			-- Apply our durationFont config (size, outline, shadow)
			local df = self._durationFont
			if(df) then
				local fontFace = F.Media.GetActiveFont()
				cdText:SetFont(fontFace, df.size, df.outline)
				if(df.shadow == false) then
					cdText:SetShadowOffset(0, 0)
				else
					cdText:SetShadowOffset(1, -1)
				end
			end
			self._countdownReparented = true
		end
	end

	-- Stacks
	if(self.stacks) then
		if(unit and auraInstanceID) then
			-- New path: C-level formatted display count.
			-- SetText is a C-level API that accepts secret values, so we
			-- pass the result directly without IsValueNonSecret. Always
			-- show when non-nil — an empty secret string is invisible.
			local displayCount = C_UnitAuras.GetAuraApplicationDisplayCount(
				unit, auraInstanceID, 2, 99)
			if(displayCount) then
				self.stacks:SetText(displayCount)
				self.stacks:Show()
			else
				self.stacks:SetText('')
				self.stacks:Hide()
			end
		else
			-- Legacy path
			if(count and count > 1) then
				self.stacks:SetText(count)
				self.stacks:Show()
			else
				self.stacks:SetText('')
				self.stacks:Hide()
			end
		end
	end

	self._frame:Show()
end

--- Set the border color via the background texture.
--- The black cooldown swipe depletes over this, revealing the color
--- as the aura expires.
--- @param r number
--- @param g number
--- @param b number
--- @param a? number
function BorderIconMethods:SetBorderColor(r, g, b, a)
	a = a or 1
	self._borderBg:SetColorTexture(r, g, b, a)
end

--- Clear and hide this border icon.
function BorderIconMethods:Clear()
	self.icon:SetTexture(nil)
	self._unit = nil
	self._auraInstanceID = nil
	if(self.cooldown) then
		self.cooldown:Clear()
	end
	if(self.stacks) then
		self.stacks:SetText('')
		self.stacks:Hide()
	end
	self._frame:Hide()
end

function BorderIconMethods:Show()
	self._frame:Show()
end

function BorderIconMethods:Hide()
	self._frame:Hide()
end

function BorderIconMethods:SetPoint(...)
	self._frame:SetPoint(...)
end

function BorderIconMethods:ClearAllPoints()
	self._frame:ClearAllPoints()
end

function BorderIconMethods:GetFrame()
	return self._frame
end

function BorderIconMethods:SetFrameLevel(level)
	self._frame:SetFrameLevel(level)
end

function BorderIconMethods:SetSize(size)
	Widgets.SetSize(self._frame, size, size)
	-- iconFrame is point-anchored with inset; auto-adjusts on resize
end

--- Tear down the BorderIcon for pool cleanup.
--- Clears back-reference, hides, and orphans the frame.
function BorderIconMethods:Destroy()
	self._frame._biRef = nil
	self._unit = nil
	self._auraInstanceID = nil
	self._frame:Hide()
	self._frame:SetParent(nil)
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a BorderIcon indicator: outer frame with colored border,
--- inner icon texture, cooldown swipe with Blizzard countdown, and stack text.
--- @param parent Frame
--- @param size number Pixel size (width = height)
--- @param config? table { borderThickness, showCooldown, showStacks, showDuration, borderColor, frameLevel, stackFont }
--- @return table borderIcon
function F.Indicators.BorderIcon.Create(parent, size, config)
	config = config or {}
	local borderThickness = config.borderThickness or 2
	local showCooldown    = config.showCooldown ~= false
	local showStacks      = config.showStacks   ~= false
	local showDuration    = config.showDuration  ~= false
	local frameLevel      = config.frameLevel    or (parent:GetFrameLevel() + 5)

	-- 1. Outer frame
	local frame = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(frame, size, size)
	frame:SetFrameLevel(frameLevel)
	frame:Hide()

	-- 2. Static border color — single texture on a dedicated frame.
	--    Sits below the cooldown so the black swipe covers it initially,
	--    then reveals the color as the swipe depletes.
	--    The icon (on iconFrame above) is opaque and covers the inner area.
	local borderFrame = CreateFrame('Frame', nil, frame)
	borderFrame:SetAllPoints(frame)

	local borderBg = borderFrame:CreateTexture(nil, 'ARTWORK')
	borderBg:SetAllPoints(borderFrame)
	borderBg:SetColorTexture(0, 0, 0, 0.85)

	-- 3. Cooldown frame covers the FULL frame (including border area).
	--    Black swipe depletes over the colored border edges.
	--    The icon sits in a child frame above the cooldown.
	local cooldown
	if(showCooldown) then
		cooldown = CreateFrame('Cooldown', nil, frame)
		cooldown:SetAllPoints(frame)
		cooldown:SetSwipeTexture([[Interface\BUTTONS\WHITE8x8]])
		cooldown:SetSwipeColor(0, 0, 0, 1)
		cooldown:SetDrawBling(false)
		cooldown:SetDrawEdge(false)
		cooldown:SetHideCountdownNumbers(not showDuration)
		if(showDuration and cooldown.SetCountdownAbbrevThreshold) then
			cooldown:SetCountdownAbbrevThreshold(60)
		end
		-- borderFrame below cooldown, cooldown swipe covers the color
		borderFrame:SetFrameLevel(cooldown:GetFrameLevel() - 1)
	end

	-- 4. Icon child frame (above cooldown so swipe only shows in border area)
	local iconFrame = CreateFrame('Frame', nil, frame)
	iconFrame:SetPoint('TOPLEFT', frame, 'TOPLEFT', borderThickness, -borderThickness)
	iconFrame:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -borderThickness, borderThickness)
	if(cooldown) then
		iconFrame:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	end

	local icon = iconFrame:CreateTexture(nil, 'ARTWORK')
	icon:SetAllPoints(iconFrame)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- 5. Stack count text (on icon frame, above cooldown)
	--    Fallbacks needed: factory is called during secure header spawning
	--    where callers may not pass stackFont (e.g. Dispellable).
	local stacksText
	if(showStacks) then
		local sf = config.stackFont or {}
		stacksText = Widgets.CreateFontString(iconFrame,
			sf.size or C.Font.sizeSmall,
			sf.color or C.Colors.textActive,
			sf.outline, sf.shadow)
		local anchor  = sf.anchor  or 'BOTTOMRIGHT'
		local xOffset = sf.xOffset or 0
		local yOffset = sf.yOffset or 0
		stacksText:SetPoint(anchor, frame, anchor, xOffset, yOffset)
		stacksText:Hide()
	end

	-- Build object
	local bi = {
		_frame           = frame,
		_iconFrame       = iconFrame,
		_borderBg        = borderBg,
		_borderThickness = borderThickness,
		_countdownReparented = false,
		_unit            = nil,
		_auraInstanceID  = nil,

		icon          = icon,
		cooldown      = cooldown,
		stacks        = stacksText,
		_durationFont = config.durationFont,
	}

	-- Apply methods
	for k, v in next, BorderIconMethods do
		bi[k] = v
	end

	-- Back-reference for OnUpdate
	frame._biRef = bi

	-- Apply initial border color if provided
	if(config.borderColor) then
		local bc = config.borderColor
		bi:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
	end

	return bi
end
