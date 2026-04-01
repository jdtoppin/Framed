local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.BorderIcon = {}

-- ============================================================
-- Duration OnUpdate handler
-- ============================================================

local DURATION_UPDATE_INTERVAL = 0.1

--- OnUpdate ticker for duration text display.
--- Prefers GetAuraDurationRemainingByAuraInstanceID (12.0.0) when
--- unit + auraInstanceID are available — returns a plain number that
--- may be secret in tainted combat. Falls back to expirationTime - GetTime().
--- In both paths, IsValueNonSecret guards ensure graceful degradation:
--- duration text hides when secret, cooldown swipe still works via DurationObject.
local function DurationOnUpdate(frame, elapsed)
	local bi = frame._biRef
	if(not bi) then return end

	bi._durationElapsed = (bi._durationElapsed or 0) + elapsed
	if(bi._durationElapsed < DURATION_UPDATE_INTERVAL) then return end
	bi._durationElapsed = 0

	local remaining

	-- Preferred: C-level remaining duration query
	if(bi._unit and bi._auraInstanceID and C_UnitAuras.GetAuraDurationRemainingByAuraInstanceID) then
		remaining = C_UnitAuras.GetAuraDurationRemainingByAuraInstanceID(bi._unit, bi._auraInstanceID)
		if(not remaining or not F.IsValueNonSecret(remaining)) then
			-- Secret or nil → hide text, stop ticker
			bi.duration:SetText('')
			bi._durationActive = false
			frame:SetScript('OnUpdate', nil)
			return
		end
	else
		-- Fallback: raw expirationTime calculation
		remaining = bi._expirationTime - GetTime()
	end

	if(remaining <= 0) then
		bi.duration:SetText('')
		bi._durationActive = false
		frame:SetScript('OnUpdate', nil)
		return
	end

	bi.duration:SetText(F.FormatDuration(remaining))
end

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
--- Duration text prefers GetAuraDurationRemainingByAuraInstanceID, falls
--- back to expirationTime; both guard with IsValueNonSecret (hides when secret).
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

	-- Border color from dispel type
	if(unit and auraInstanceID) then
		-- New path: C-level dispel color via curve
		local curve = getDispelColorCurve()
		if(curve) then
			local color = C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
			if(color and F.IsValueNonSecret(color)) then
				self:SetBorderColor(color:GetRGBA())
			end
		end
	elseif(dispelType and F.IsValueNonSecret(dispelType)) then
		-- Legacy path: manual color lookup
		local color = C.Colors.dispel[dispelType]
		if(color) then
			self:SetBorderColor(color[1], color[2], color[3], 1)
		end
	end

	-- Cooldown swipe (fills the border area; icon frame sits above)
	if(self.cooldown) then
		self.cooldown:SetReverse(true)
		if(unit and auraInstanceID) then
			-- New path: DurationObject -> SetCooldownFromDurationObject
			-- This is the ONLY cooldown API available in tainted combat (12.0.1)
			local durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
			if(durationObj) then
				self.cooldown:SetCooldownFromDurationObject(durationObj)
			else
				self.cooldown:Clear()
			end
		else
			-- Legacy path: raw SetCooldown (works in untainted contexts only)
			local durationSafe = F.IsValueNonSecret(duration)
			local expirationSafe = F.IsValueNonSecret(expirationTime)
			if(durationSafe and expirationSafe and duration and duration > 0 and expirationTime and expirationTime > 0) then
				local startTime = expirationTime - duration
				self.cooldown:SetCooldown(startTime, duration)
			else
				self.cooldown:Clear()
			end
		end
	end

	-- Stacks
	if(self.stacks) then
		if(unit and auraInstanceID) then
			-- New path: C-level formatted display count
			local displayCount = C_UnitAuras.GetAuraApplicationDisplayCount(
				unit, auraInstanceID, 2, 99)
			if(displayCount and F.IsValueNonSecret(displayCount)) then
				self.stacks:SetText(displayCount)
				self.stacks:SetShown(displayCount ~= '')
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

	-- Duration text — prefers GetAuraDurationRemainingByAuraInstanceID (12.0.0),
	-- falls back to expirationTime - GetTime(). Both paths guard with IsValueNonSecret.
	-- In tainted combat: text gracefully hides, cooldown swipe still works via DurationObject.
	if(self.duration) then
		local remaining

		-- Preferred: C-level remaining duration (may return secret in tainted combat)
		if(unit and auraInstanceID and C_UnitAuras.GetAuraDurationRemainingByAuraInstanceID) then
			local val = C_UnitAuras.GetAuraDurationRemainingByAuraInstanceID(unit, auraInstanceID)
			if(val and F.IsValueNonSecret(val)) then
				remaining = val
			end
		end

		-- Fallback: raw expirationTime calculation
		if(not remaining) then
			local durationSafe = F.IsValueNonSecret(duration)
			local expirationSafe = F.IsValueNonSecret(expirationTime)
			if(durationSafe and expirationSafe and duration and duration > 0) then
				remaining = expirationTime - GetTime()
			end
		end

		if(remaining and remaining > 0) then
			self._expirationTime = expirationTime
			self._durationActive = true
			self._durationElapsed = 0
			self.duration:SetText(F.FormatDuration(remaining))
			self._frame:SetScript('OnUpdate', DurationOnUpdate)
		else
			self.duration:SetText('')
			self._durationActive = false
			self._frame:SetScript('OnUpdate', nil)
		end
	end

	self._frame:Show()
end

--- Set the border color manually (overrides dispel-type auto-color).
--- @param r number
--- @param g number
--- @param b number
--- @param a? number
function BorderIconMethods:SetBorderColor(r, g, b, a)
	a = a or 1
	-- Swipe color = the border color that fills in over the backdrop
	if(self.cooldown) then
		self.cooldown:SetSwipeColor(r, g, b, a)
	end
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
	if(self.duration) then
		self.duration:SetText('')
	end
	self._durationActive = false
	self._frame:SetScript('OnUpdate', nil)
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
--- Removes OnUpdate, clears back-reference, hides, and orphans the frame.
function BorderIconMethods:Destroy()
	self._frame:SetScript('OnUpdate', nil)
	self._frame._biRef = nil
	self._unit = nil
	self._auraInstanceID = nil
	self._frame:Hide()
	self._frame:SetParent(nil)
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a BorderIcon indicator: BackdropTemplate frame with colored border,
--- inner icon texture, cooldown swipe, and stack/duration text overlays.
--- @param parent Frame
--- @param size number Pixel size (width = height)
--- @param config? table { borderThickness, showCooldown, showStacks, showDuration, borderColor, frameLevel, stackFont, durationFont }
--- @return table borderIcon
function F.Indicators.BorderIcon.Create(parent, size, config)
	config = config or {}
	local borderThickness = config.borderThickness or 2
	local showCooldown    = config.showCooldown ~= false
	local showStacks      = config.showStacks   ~= false
	local showDuration    = config.showDuration  ~= false
	local frameLevel      = config.frameLevel    or (parent:GetFrameLevel() + 5)

	-- 1. Outer frame with backdrop background (border color shows as bg)
	local frame = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(frame, size, size)
	frame:SetFrameLevel(frameLevel)
	frame:SetBackdrop({
		bgFile = [[Interface\BUTTONS\WHITE8x8]],
	})
	-- Default: black background (acts as border color)
	frame:SetBackdropColor(0, 0, 0, 0.85)
	frame:Hide()

	-- 2. Cooldown frame covers the FULL frame (including border area).
	--    The swipe is only visible in the border zone because the icon
	--    sits in a child frame above the cooldown.
	local cooldown
	if(showCooldown) then
		cooldown = CreateFrame('Cooldown', nil, frame)
		cooldown:SetAllPoints(frame)
		cooldown:SetSwipeTexture([[Interface\BUTTONS\WHITE8x8]])
		cooldown:SetSwipeColor(0, 0, 0)
		cooldown:SetDrawBling(false)
		cooldown:SetDrawEdge(false)
		cooldown:SetHideCountdownNumbers(true)
		cooldown.noCooldownCount = true
	end

	-- 3. Icon child frame (above cooldown so swipe only shows in border area)
	local iconFrame = CreateFrame('Frame', nil, frame)
	iconFrame:SetPoint('TOPLEFT', frame, 'TOPLEFT', borderThickness, -borderThickness)
	iconFrame:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -borderThickness, borderThickness)
	if(cooldown) then
		iconFrame:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	end

	local icon = iconFrame:CreateTexture(nil, 'ARTWORK')
	icon:SetAllPoints(iconFrame)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- 4. Stack count text (on icon frame, above cooldown)
	local stacksText
	if(showStacks) then
		local stackFontSize = (config.stackFont and config.stackFont.size) or C.Font.sizeSmall
		local stackFontColor = (config.stackFont and config.stackFont.color) or C.Colors.textActive
		stacksText = Widgets.CreateFontString(iconFrame, stackFontSize, stackFontColor)
		stacksText:SetPoint('BOTTOMRIGHT', iconFrame, 'BOTTOMRIGHT', -1, 1)
		stacksText:Hide()
	end

	-- 5. Duration text (on icon frame, above cooldown)
	local durationText
	if(showDuration) then
		local durFontSize = (config.durationFont and config.durationFont.size) or C.Font.sizeSmall
		durationText = Widgets.CreateFontString(iconFrame, durFontSize, C.Colors.textActive)
		durationText:SetPoint('BOTTOM', iconFrame, 'BOTTOM', 0, 1)
	end

	-- Build object
	local bi = {
		_frame           = frame,
		_borderThickness = borderThickness,
		_durationActive  = false,
		_durationElapsed = 0,
		_expirationTime  = 0,
		_unit            = nil,
		_auraInstanceID  = nil,

		icon     = icon,
		cooldown = cooldown,
		stacks   = stacksText,
		duration = durationText,
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
