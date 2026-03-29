local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Bar = {}

-- ============================================================
-- OnUpdate handler for depleting animation (fallback path)
-- Stored as a module-level function; assigned/cleared per bar.
-- ============================================================

local DURATION_UPDATE_INTERVAL = 0.1

local function DepletingOnUpdate(statusBar, elapsed)
	local bar = statusBar._barRef
	if(not bar or not bar._depleting) then
		statusBar:SetScript('OnUpdate', nil)
		return
	end

	bar._elapsed = (bar._elapsed or 0) + elapsed
	if(bar._elapsed < DURATION_UPDATE_INTERVAL) then return end
	bar._elapsed = 0

	local remaining = bar._expirationTime - GetTime()
	if(remaining <= 0) then
		bar:Clear()
		return
	end

	local fraction = remaining / bar._duration
	fraction = math.max(0, math.min(1, fraction))
	statusBar:SetMinMaxValues(0, 1)
	statusBar:SetValue(fraction)

	-- Update threshold colors
	F.Indicators.UpdateThresholdColor(bar, remaining, bar._duration or 0, function(r, g, b, a)
		bar._statusBar:SetStatusBarColor(r, g, b, a)
	end)

	-- Update duration text
	if(bar._durationText and bar._durationMode ~= 'Never') then
		local show = F.Indicators.ShouldShowDuration(bar._durationMode, remaining, bar._duration or 0)
		if(show) then
			bar._durationText:SetText(bar:FormatDuration(remaining))
			bar._durationText:Show()
		else
			bar._durationText:Hide()
		end
	end
end

-- ============================================================
-- Bar methods
-- ============================================================

local BarMethods = {}

--- Start depleting animation from full to 0 over `duration` seconds,
--- expiring at `expirationTime` (GetTime()-relative).
--- Primary path uses C-level SetTimerDuration (12.0.1, secret-safe)
--- with OnUpdate-based depletion as a fallback.
--- @param duration number Total duration in seconds
--- @param expirationTime number Absolute expiration time from GetTime()
function BarMethods:SetDuration(duration, expirationTime)
	if(not duration or duration <= 0) then
		self:Clear()
		return
	end

	-- Skip re-initialization if already tracking the same aura
	if(self._expirationTime == expirationTime and self._duration == duration) then
		self._frame:Show()
		return
	end

	self._duration      = duration
	self._expirationTime = expirationTime
	self._elapsed       = 0

	-- Calculate current fraction immediately to avoid flicker
	local remaining = expirationTime - GetTime()
	local fraction = math.max(0, math.min(1, remaining / duration))

	-- Primary: use C-level SetTimerDuration (12.0.1, secret-safe)
	-- Safe feature detection: check Enum exists before accessing nested fields.
	if(self._statusBar.SetTimerDuration and Enum and Enum.StatusBarTimerDirection) then
		local startTime = expirationTime - duration
		local durObj
		if(CreateLuaDurationObject) then
			durObj = self._durObj or CreateLuaDurationObject()
		end

		if(durObj) then
			self._durObj = durObj
			durObj:SetTimeFromStart(startTime, duration)
			self._statusBar:SetTimerDuration(durObj, nil, Enum.StatusBarTimerDirection.RemainingTime)
			self._depleting = false  -- C-level handles it

			self._statusBar:SetMinMaxValues(0, 1)
			self._statusBar:Show()
			self._statusBar._wrapper:Show()
			self._frame:Show()
			self._statusBar:SetScript('OnUpdate', nil)
			return
		end
	end

	-- Fallback: OnUpdate-based depletion
	self._depleting = true

	self._statusBar:SetMinMaxValues(0, 1)
	self._statusBar:SetValue(fraction)
	self._statusBar:Show()
	self._statusBar._wrapper:Show()
	self._frame:Show()

	self._statusBar:SetScript('OnUpdate', DepletingOnUpdate)
end

--- Set bar to a fixed value (manual mode, no animation).
--- @param current number
--- @param max number
function BarMethods:SetValue(current, max)
	-- Stop any depleting animation
	self._depleting = false
	self._statusBar:SetScript('OnUpdate', nil)

	if(not max or max <= 0) then
		self._statusBar:SetMinMaxValues(0, 1)
		self._statusBar:SetValue(0)
	else
		
		self._statusBar:SetMinMaxValues(0, max)
		self._statusBar:SetValue(current)
	end

	self._statusBar:Show()
	self._statusBar._wrapper:Show()
	self._frame:Show()
end

--- Update the bar fill color.
--- @param r number
--- @param g number
--- @param b number
--- @param a? number
function BarMethods:SetColor(r, g, b, a)
	self._statusBar:SetStatusBarColor(r, g, b, a or 1)
end

--- Hide the bar and stop any active animation.
function BarMethods:Clear()
	self._depleting = false
	self._statusBar:SetScript('OnUpdate', nil)
	self._statusBar:SetValue(0)
	self._statusBar._wrapper:Hide()
	self._statusBar:Hide()
	self._frame:Hide()
	if(self._stackText) then self._stackText:Hide() end
	if(self._durationText) then self._durationText:Hide() end
end

--- Show the bar frame.
function BarMethods:Show()
	self._frame:Show()
end

--- Hide the bar frame.
function BarMethods:Hide()
	self._frame:Hide()
end

--- Position the bar frame.
function BarMethods:SetPoint(...)
	self._frame:SetPoint(...)
end

--- Clear all anchors.
function BarMethods:ClearAllPoints()
	self._frame:ClearAllPoints()
end

--- Start a glow effect on this bar.
function BarMethods:StartGlow(color, glowType, glowConfig)
	if(not self._glow) then
		self._glow = F.Indicators.BorderGlow.Create(self._frame, { borderGlowMode = 'Glow' })
	end
	self._glow:Start(color, glowType, glowConfig)
end

--- Stop any active glow effect on this bar.
function BarMethods:StopGlow()
	if(self._glow) then
		self._glow:Stop()
	end
end

--- Return the underlying container frame.
--- @return Frame
function BarMethods:GetFrame()
	return self._frame
end

--- Return the inner StatusBar widget (for positioning via _wrapper).
--- @return Frame
function BarMethods:GetStatusBar()
	return self._statusBar
end

function BarMethods:SetStacks(count)
	if(not self._stackText) then return end
	if(count and count > 1) then
		self._stackText:SetText(count)
		self._stackText:Show()
	else
		self._stackText:Hide()
	end
end

--- Format duration as seconds (with tenths below 10s).
function BarMethods:FormatDuration(remaining)
	if(remaining >= 60) then
		return math.floor(remaining / 60) .. 'm'
	elseif(remaining >= 10) then
		return math.floor(remaining) .. ''
	else
		return ('%.1f'):format(remaining)
	end
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a small standalone Bar indicator with depleting animation.
--- @param parent Frame
--- @param config table { barWidth, barHeight, barOrientation, color, borderColor, bgColor,
---                        lowTimeColor, lowSecsColor, showStacks, stackFont,
---                        durationMode, durationFont }
--- @return table bar
function F.Indicators.Bar.Create(parent, config)
	config = config or {}
	local barWidth    = config.barWidth or 50
	local barHeight   = config.barHeight or 4
	local orientation = config.barOrientation or 'Horizontal'
	local borderColor = config.borderColor or { 0, 0, 0, 1 }
	local bgColor     = config.bgColor or { 0, 0, 0, 0.5 }

	-- Container frame
	local frame = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(frame, barWidth, barHeight)
	frame:SetFrameLevel(parent:GetFrameLevel() + 5)
	frame:Hide()

	-- Dark background
	local bg = frame:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(frame)
	bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.5)

	-- Status bar (solid color fill)
	local statusBar = CreateFrame('StatusBar', nil, frame)
	statusBar:SetAllPoints(frame)
	statusBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
	statusBar:GetStatusBarTexture():SetHorizTile(false)
	statusBar:GetStatusBarTexture():SetVertTile(false)
	statusBar:SetStatusBarColor(0, 0, 0, 0)
	statusBar:SetMinMaxValues(0, 1)
	statusBar:SetValue(0)

	-- 0.5px border overlay
	local border = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
	border:SetAllPoints(frame)
	border:SetBackdrop({
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 0.5,
	})
	border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
	border:SetFrameLevel(frame:GetFrameLevel() + 2)

	-- Wrapper reference for Show/Hide compatibility
	statusBar._wrapper = statusBar

	if(orientation == 'Vertical') then
		statusBar:SetOrientation('VERTICAL')
	end

	-- Stack text (optional)
	local stackText
	if(config.showStacks ~= false) then
		local sf = config.stackFont or {}
		stackText = Widgets.CreateFontString(frame, sf.size or 10, { 1, 1, 1, 1 })
		stackText:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -1, 1)
		stackText:SetJustifyH('RIGHT')
		stackText:Hide()
	end

	-- Duration text (optional)
	local durationText
	if(config.durationMode and config.durationMode ~= 'Never') then
		local df = config.durationFont or {}
		durationText = Widgets.CreateFontString(frame, df.size or 10, { 1, 1, 1, 1 })
		durationText:SetPoint('LEFT', frame, 'LEFT', 2, 0)
		durationText:SetJustifyH('LEFT')
		durationText:Hide()
	end

	local bar = {
		_frame        = frame,
		_statusBar    = statusBar,
		_stackText    = stackText,
		_durationText = durationText,
		_lowTimeColor = config.lowTimeColor,   -- { enabled, threshold, color }
		_lowSecsColor = config.lowSecsColor,   -- { enabled, threshold, color }
		_durationMode = config.durationMode or 'Never',
		_depleting    = false,
		_duration     = 1,
		_expirationTime = 0,
		_durObj       = nil,
	}

	for k, v in next, BarMethods do
		bar[k] = v
	end

	statusBar._barRef = bar
	frame._barRef = bar
	return bar
end
