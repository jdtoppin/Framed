local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.PreviewIndicators = {}
local PI = F.PreviewIndicators

-- Well-known spell icons for preview placeholders
local FAKE_ICONS = {
	buffs          = { 135981, 136075, 135932 },   -- Renew, Fort, BoW
	debuffs        = { 136139, 135813, 136188 },   -- Corruption, Curse of Agony, SW:P
	externals      = { 135936, 135964 },           -- BoP, BoS
	defensives     = { 135919, 135872 },           -- Divine Shield, Ice Block
	missingBuffs   = { 136075 },                   -- Fort
	targetedSpells = { 136197 },                   -- Shadow Bolt
	privateAuras   = { 134400 },                   -- question mark
	dispellable    = { 136139 },                   -- Corruption
	lossOfControl  = { 132168 },                   -- stun
	crowdControl   = { 118699 },                   -- Polymorph
}

local FAKE_DEPLETION_PCT = 0.6
local FAKE_STACKS = 2
local ANIM_CYCLE = 8  -- seconds for one full depletion loop

-- Dispel colors: canonical source is C.Colors.dispel
PI.DISPEL_COLORS = C.Colors.dispel

------------------------------------------------------------------------
-- Public accessors / helpers
------------------------------------------------------------------------

-- Returns the icon list for the given group key, or a fallback
function PI.GetFakeIcons(groupKey)
	return FAKE_ICONS[groupKey] or { 134400 }
end

-- Anchor unpacking helper
-- anchor = { point, relativeFrame, relativePoint, offsetX, offsetY }
function PI.UnpackAnchor(anchor, default)
	anchor = anchor or default or { 'TOPLEFT', nil, 'TOPLEFT', 0, 0 }
	return anchor[1], anchor[2], anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0
end

-- Orientation offset calculator: returns (dx, dy) for icon index i
function PI.OrientOffset(orient, i, w, h, spacingX, spacingY)
	local dx, dy = 0, 0
	if(orient == 'RIGHT') then     dx =  (i - 1) * (w + (spacingX or 1))
	elseif(orient == 'LEFT') then  dx = -(i - 1) * (w + (spacingX or 1))
	elseif(orient == 'DOWN') then  dy = -(i - 1) * (h + (spacingY or 1))
	elseif(orient == 'UP') then    dy =  (i - 1) * (h + (spacingY or 1))
	end
	return dx, dy
end

------------------------------------------------------------------------
-- Animation helpers
------------------------------------------------------------------------

local Widgets = F.Widgets

-- Looping Cooldown swipe: resets the cooldown each cycle
local function startCooldownLoop(cd, duration)
	cd:SetCooldown(GetTime(), duration)
	C_Timer.After(duration, function()
		if(cd:IsShown()) then startCooldownLoop(cd, duration) end
	end)
end

-- Looping alpha fade: 1 → 0.1 over ANIM_CYCLE, then restarts
local function startAlphaFadeLoop(frame)
	frame:SetAlpha(1)
	Widgets.StartAnimation(frame, 'fade', 1, 0.1, ANIM_CYCLE,
		function(f, v) f:SetAlpha(v) end,
		function(f)
			if(f:IsShown()) then startAlphaFadeLoop(f) end
		end
	)
end

------------------------------------------------------------------------
-- Icon preview builder (linear depletion bar)
-- Matches Elements/Indicators/Icon.lua
------------------------------------------------------------------------

function PI.CreateIcon(parent, iconTexture, w, h, indConfig, animated)
	w = w or 14
	h = h or 14
	local f = CreateFrame('Frame', nil, parent)
	f:SetSize(w, h)

	-- Icon texture (trimmed like real Icon)
	local tex = f:CreateTexture(nil, 'ARTWORK')
	tex:SetAllPoints(f)
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	tex:SetTexture(iconTexture)

	-- 0.5px black border (BackdropTemplate)
	local border = CreateFrame('Frame', nil, f, 'BackdropTemplate')
	border:SetAllPoints(f)
	border:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = 0.5 })
	border:SetBackdropBorderColor(0, 0, 0, 1)

	-- Linear depletion bar (always on)
	local fillDir = indConfig and indConfig.fillDirection or 'topToBottom'
	local depBar = CreateFrame('StatusBar', nil, f)
	depBar:SetAllPoints(f)
	depBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
	depBar:SetStatusBarColor(0, 0, 0, 0.6)
	depBar:SetMinMaxValues(0, 1)
	if(fillDir == 'leftToRight' or fillDir == 'rightToLeft') then
		depBar:SetOrientation('HORIZONTAL')
		if(fillDir == 'rightToLeft') then depBar:SetReverseFill(true) end
	else
		depBar:SetOrientation('VERTICAL')
		if(fillDir == 'topToBottom') then depBar:SetReverseFill(true) end
	end
	depBar:SetFrameLevel(f:GetFrameLevel() + 1)

	-- Leading edge line
	local edge = depBar:CreateTexture(nil, 'OVERLAY')
	edge:SetColorTexture(1, 1, 1, 0.75)
	if(fillDir == 'topToBottom' or fillDir == 'bottomToTop') then
		edge:SetHeight(0.75)
		edge:SetPoint('TOPLEFT',  depBar:GetStatusBarTexture(), 'BOTTOMLEFT',  0, 0)
		edge:SetPoint('TOPRIGHT', depBar:GetStatusBarTexture(), 'BOTTOMRIGHT', 0, 0)
	else
		edge:SetWidth(0.75)
		edge:SetPoint('TOPLEFT',    depBar:GetStatusBarTexture(), 'TOPRIGHT',    0, 0)
		edge:SetPoint('BOTTOMLEFT', depBar:GetStatusBarTexture(), 'BOTTOMRIGHT', 0, 0)
	end

	if(animated) then
		local function startCLevelDepletionLoop()
			local durObj = CreateLuaDurationObject()
			durObj:SetTimeFromStart(GetTime(), ANIM_CYCLE)
			depBar:SetTimerDuration(durObj, nil, Enum.StatusBarTimerDirection.RemainingTime)
			C_Timer.After(ANIM_CYCLE, function()
				if(depBar:IsShown()) then startCLevelDepletionLoop() end
			end)
		end
		startCLevelDepletionLoop()
	else
		depBar:SetValue(1 - FAKE_DEPLETION_PCT)
	end

	-- Stack count text
	if(indConfig and indConfig.showStacks) then
		local sf = indConfig.stackFont or {}
		local stackText = f:CreateFontString(nil, 'OVERLAY')
		stackText:SetFont(F.Media.GetActiveFont(), sf.size or 9, sf.outline or 'OUTLINE')
		stackText:SetPoint(sf.anchor or 'BOTTOMRIGHT', f, sf.anchor or 'BOTTOMRIGHT', sf.offsetX or 0, sf.offsetY or 0)
		stackText:SetText(tostring(FAKE_STACKS))
		if(sf.shadow ~= false) then stackText:SetShadowOffset(1, -1) end
	end

	-- Duration countdown (Blizzard cooldown frame, no swipe)
	if(indConfig and indConfig.durationMode and indConfig.durationMode ~= 'Never') then
		local cd = CreateFrame('Cooldown', nil, f, 'CooldownFrameTemplate')
		cd:SetAllPoints(f)
		cd:SetDrawSwipe(false)
		cd:SetDrawEdge(false)
		cd:SetDrawBling(false)
		cd:SetHideCountdownNumbers(false)
		cd:SetFrameLevel(depBar:GetFrameLevel() + 1)

		if(animated) then
			local function startCooldownCountdownLoop()
				local durObj = CreateLuaDurationObject()
				durObj:SetTimeFromStart(GetTime(), ANIM_CYCLE)
				cd:SetCooldownFromDurationObject(durObj)
				C_Timer.After(ANIM_CYCLE, function()
					if(cd:IsShown()) then startCooldownCountdownLoop() end
				end)
			end
			startCooldownCountdownLoop()
		else
			local durObj = CreateLuaDurationObject()
			durObj:SetTimeFromStart(GetTime() - (ANIM_CYCLE * FAKE_DEPLETION_PCT), ANIM_CYCLE)
			cd:SetCooldownFromDurationObject(durObj)
		end

		-- Style the countdown font string (deferred one frame for lazy creation)
		C_Timer.After(0, function()
			local cdText = cd.GetCountdownFontString and cd:GetCountdownFontString()
			if(cdText) then
				local df = indConfig.durationFont or {}
				cdText:SetParent(f)
				cdText:SetFont(F.Media.GetActiveFont(), df.size or 9, df.outline or 'OUTLINE')
				if(df.shadow == false) then
					cdText:SetShadowOffset(0, 0)
				else
					cdText:SetShadowOffset(1, -1)
				end
				cdText:ClearAllPoints()
				cdText:SetPoint(df.anchor or 'BOTTOM', f, df.anchor or 'BOTTOM', df.offsetX or 0, df.offsetY or 0)
			end
		end)
	end

	return f
end

------------------------------------------------------------------------
-- BorderIcon preview builder (radial cooldown swipe)
-- Matches Elements/Indicators/BorderIcon.lua
------------------------------------------------------------------------

function PI.CreateBorderIcon(parent, iconTexture, size, borderThickness, dispelType, config, animated, borderColor)
	size = size or 16
	borderThickness = borderThickness or 2

	local f = CreateFrame('Frame', nil, parent)
	f:SetSize(size, size)

	local bc = borderColor or PI.DISPEL_COLORS[dispelType] or { 0, 0, 0 }

	-- 1. Border color texture — fills entire frame, sits below cooldown.
	-- The cooldown's black swipe covers this; as it depletes, the color is revealed.
	local borderFrame = CreateFrame('Frame', nil, f)
	borderFrame:SetAllPoints(f)
	local borderBg = borderFrame:CreateTexture(nil, 'ARTWORK')
	borderBg:SetAllPoints(borderFrame)
	borderBg:SetColorTexture(bc[1], bc[2], bc[3], 1)

	-- 2. Cooldown frame covers the FULL frame (including border area).
	-- Solid black swipe depletes over the colored border.
	if(not config or config.showCooldown ~= false) then
		local cd = CreateFrame('Cooldown', nil, f)
		cd:SetAllPoints(f)
		cd:SetSwipeTexture([[Interface\BUTTONS\WHITE8x8]])
		cd:SetSwipeColor(0, 0, 0, 1)
		cd:SetDrawBling(false)
		cd:SetDrawEdge(false)
		cd:SetHideCountdownNumbers(true)
		borderFrame:SetFrameLevel(cd:GetFrameLevel() - 1)

		if(animated) then
			startCooldownLoop(cd, ANIM_CYCLE)
			cd:SetReverse(true)
		else
			local fakeDuration = 30
			local fakeStart = GetTime() - (fakeDuration * (1 - FAKE_DEPLETION_PCT))
			cd:SetCooldown(fakeStart, fakeDuration)
			cd:SetReverse(true)
			cd:Pause()
		end
	end

	-- 3. Icon frame sits ABOVE cooldown so swipe only shows in border area
	local iconFrame = CreateFrame('Frame', nil, f)
	iconFrame:SetPoint('TOPLEFT', f, 'TOPLEFT', borderThickness, -borderThickness)
	iconFrame:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -borderThickness, borderThickness)
	iconFrame:SetFrameLevel(f:GetFrameLevel() + 3)

	local tex = iconFrame:CreateTexture(nil, 'ARTWORK')
	tex:SetAllPoints(iconFrame)
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	tex:SetTexture(iconTexture)

	-- Stack count (on icon frame, above cooldown)
	if(not config or config.showStacks ~= false) then
		local sf = (config and config.stackFont) or {}
		local stackText = iconFrame:CreateFontString(nil, 'OVERLAY')
		stackText:SetFont(F.Media.GetActiveFont(), sf.size or 9, 'OUTLINE')
		stackText:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', 0, 0)
		stackText:SetText(tostring(FAKE_STACKS))
		stackText:SetShadowOffset(1, -1)
	end

	-- Duration text (on icon frame, above cooldown)
	if(config and config.showDuration ~= false) then
		local df = (config and config.durationFont) or {}
		local durText = iconFrame:CreateFontString(nil, 'OVERLAY')
		durText:SetFont(F.Media.GetActiveFont(), df.size or 9, 'OUTLINE')
		durText:SetPoint('BOTTOM', f, 'BOTTOM', 0, 0)
		durText:SetText('18')
		durText:SetShadowOffset(1, -1)
	end

	return f
end

------------------------------------------------------------------------
-- Bar preview builder
------------------------------------------------------------------------

function PI.CreateBar(parent, barConfig, animated)
	barConfig = barConfig or {}
	local w = barConfig.barWidth or 50
	local h = barConfig.barHeight or 4

	local f = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	f:SetSize(w, h)

	local bg = f:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(f)
	bg:SetColorTexture(0, 0, 0, 0.5)

	local bar = CreateFrame('StatusBar', nil, f)
	bar:SetAllPoints(f)
	bar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
	bar:SetMinMaxValues(0, 1)
	local c = barConfig.color or { 1, 1, 1, 1 }
	bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	if(barConfig.barOrientation == 'Vertical') then
		bar:SetOrientation('VERTICAL')
	end

	if(animated) then
		-- Animate depleting from full to empty (value 1 → 0)
		bar:SetValue(1)
		local function loopBarDrain(b)
			Widgets.StartAnimation(b, 'drain', 1, 0, ANIM_CYCLE,
				function(ff, v) ff:SetValue(v) end,
				function(ff)
					if(ff:IsShown()) then loopBarDrain(ff) end
				end
			)
		end
		loopBarDrain(bar)
	else
		bar:SetValue(FAKE_DEPLETION_PCT)
	end

	f:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = 0.5 })
	f:SetBackdropBorderColor(0, 0, 0, 1)

	return f
end

------------------------------------------------------------------------
-- Color (rectangle) preview builder
------------------------------------------------------------------------

function PI.CreateColorRect(parent, rectConfig)
	rectConfig = rectConfig or {}
	local w = rectConfig.rectWidth or 10
	local h = rectConfig.rectHeight or 10

	local f = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	f:SetSize(w, h)
	f:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = 1 })
	f:SetBackdropBorderColor(0, 0, 0, 1)

	local tex = f:CreateTexture(nil, 'ARTWORK')
	tex:SetPoint('TOPLEFT',     1, -1)
	tex:SetPoint('BOTTOMRIGHT', -1, 1)
	local c = rectConfig.color or { 1, 1, 1, 1 }
	tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)

	return f
end

------------------------------------------------------------------------
-- Overlay preview builder (health bar overlay)
------------------------------------------------------------------------

function PI.CreateOverlay(healthWrapper, overlayConfig, animated)
	if(not healthWrapper) then return nil end
	overlayConfig = overlayConfig or {}

	local f = CreateFrame('Frame', nil, healthWrapper)
	f:SetAllPoints(healthWrapper)
	f:SetFrameLevel(healthWrapper:GetFrameLevel() + 2)

	local c = overlayConfig.color or { 0, 0, 0, 0.6 }
	local mode = overlayConfig.overlayMode or 'DurationOverlay'

	if(mode == 'Color' or mode == 'Both') then
		local fill = f:CreateTexture(nil, 'OVERLAY')
		fill:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, 0)
		fill:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 0, 0)
		fill:SetColorTexture(c[1], c[2], c[3], c[4] or 0.6)
		-- Defer SetWidth until the parent has been laid out
		f:HookScript('OnShow', function()
			fill:SetWidth(f:GetWidth() * FAKE_DEPLETION_PCT)
		end)
	end

	if(mode == 'DurationOverlay' or mode == 'Both') then
		local bar = CreateFrame('StatusBar', nil, f)
		bar:SetAllPoints(f)
		bar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
		bar:SetStatusBarColor(c[1], c[2], c[3], mode == 'Both' and 1 or (c[4] or 0.6))
		bar:SetMinMaxValues(0, 1)
		if(animated) then
			bar:SetValue(1)
			local function loopOverlay(b)
				Widgets.StartAnimation(b, 'drain', 1, 0, ANIM_CYCLE,
					function(ff, v) ff:SetValue(v) end,
					function(ff)
						if(ff:IsShown()) then loopOverlay(ff) end
					end
				)
			end
			loopOverlay(bar)
		else
			bar:SetValue(FAKE_DEPLETION_PCT)
		end
	end

	return f
end

------------------------------------------------------------------------
-- BorderGlow preview builder
------------------------------------------------------------------------

function PI.CreateBorderGlow(parent, bgConfig, animated)
	bgConfig = bgConfig or {}
	local mode = bgConfig.borderGlowMode or 'Border'

	if(mode == 'Border') then
		local thickness = bgConfig.borderThickness or 2
		local c = bgConfig.color or { 1, 1, 1, 1 }

		local overlay = CreateFrame('Frame', nil, parent)
		overlay:SetAllPoints(parent)
		overlay:SetFrameLevel(parent:GetFrameLevel() + 10)

		local top = overlay:CreateTexture(nil, 'OVERLAY')
		top:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		top:SetPoint('TOPLEFT',  overlay, 'TOPLEFT',  0, 0)
		top:SetPoint('TOPRIGHT', overlay, 'TOPRIGHT', 0, 0)
		top:SetHeight(thickness)

		local bottom = overlay:CreateTexture(nil, 'OVERLAY')
		bottom:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		bottom:SetPoint('BOTTOMLEFT',  overlay, 'BOTTOMLEFT',  0, 0)
		bottom:SetPoint('BOTTOMRIGHT', overlay, 'BOTTOMRIGHT', 0, 0)
		bottom:SetHeight(thickness)

		local left = overlay:CreateTexture(nil, 'OVERLAY')
		left:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		left:SetPoint('TOPLEFT',    top,    'BOTTOMLEFT',  0, 0)
		left:SetPoint('BOTTOMLEFT', bottom, 'TOPLEFT',     0, 0)
		left:SetWidth(thickness)

		local right = overlay:CreateTexture(nil, 'OVERLAY')
		right:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		right:SetPoint('TOPRIGHT',    top,    'BOTTOMRIGHT', 0, 0)
		right:SetPoint('BOTTOMRIGHT', bottom, 'TOPRIGHT',    0, 0)
		right:SetWidth(thickness)

		if(animated and bgConfig.fadeOut) then
			startAlphaFadeLoop(overlay)
		elseif(bgConfig.fadeOut) then
			overlay:SetAlpha(FAKE_DEPLETION_PCT * 0.9 + 0.1)
		end

		return overlay
	else
		local overlay = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
		overlay:SetAllPoints(parent)
		overlay:SetFrameLevel(parent:GetFrameLevel() + 10)
		local c = bgConfig.glowColor or bgConfig.color or { 1, 1, 1, 1 }
		overlay:SetBackdrop({ edgeFile = [[Interface\BUTTONS\WHITE8x8]], edgeSize = 2 })
		overlay:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
		return overlay
	end
end
