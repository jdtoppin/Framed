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

local function DepletingOnUpdate(statusBar, elapsed)
	local bar = statusBar._barRef
	if(not bar or not bar._depleting) then return end

	local remaining = bar._expirationTime - GetTime()

	if(remaining <= 0) then
		-- Fully depleted
		statusBar:SetMinMaxValues(0, 1)
		statusBar:SetValue(0)
		bar._depleting = false
		statusBar:SetScript('OnUpdate', nil)
		return
	end

	local fraction = remaining / bar._duration
	fraction = math.max(0, math.min(1, fraction))

	statusBar:SetMinMaxValues(0, 1)
	statusBar:SetValue_Raw(fraction)    -- bypass smooth interpolation; we control it here
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

			self._statusBar:SetSmooth(false)
			self._statusBar:SetMinMaxValues(0, 1)
			self._statusBar:Show()
			self._statusBar._wrapper:Show()
			self._frame:Show()
			self._statusBar:SetScript('OnUpdate', nil)
			return
		end
	end

	-- Fallback: OnUpdate-based depletion
	self._duration       = duration
	self._expirationTime = expirationTime
	self._depleting      = true

	self._statusBar:SetSmooth(false)
	self._statusBar:SetMinMaxValues(0, 1)
	self._statusBar:SetValue_Raw(1)
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
		self._statusBar:SetSmooth(false)
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
	self._statusBar:SetBarColor(r, g, b, a or 1)
end

--- Hide the bar and stop any active animation.
function BarMethods:Clear()
	self._depleting = false
	self._statusBar:SetScript('OnUpdate', nil)
	self._statusBar:SetValue(0)
	self._statusBar._wrapper:Hide()
	self._statusBar:Hide()
	self._frame:Hide()
end

--- Show the bar frame.
function BarMethods:Show()
	self._frame:Show()
end

--- Hide the bar frame.
function BarMethods:Hide()
	self._frame:Hide()
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

-- ============================================================
-- Factory
-- ============================================================

--- Create a small standalone Bar indicator with depleting animation.
--- @param parent Frame
--- @param width number Bar width in pixels
--- @param height number Bar height in pixels
--- @param config table { color = {r,g,b,a} }
--- @return table bar
function F.Indicators.Bar.Create(parent, width, height, config)
	config = config or {}
	local color = config.color or C.Colors.accent

	-- Container frame
	local frame = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(frame, width, height)
	frame:Hide()

	-- StatusBar via the Widgets factory (includes backdrop wrapper)
	local statusBar = Widgets.CreateStatusBar(frame, width, height)
	statusBar._wrapper:SetAllPoints(frame)
	statusBar:SetBarColor(color[1], color[2], color[3], color[4] or 1)
	statusBar:SetSmooth(false)
	statusBar:SetMinMaxValues(0, 1)
	statusBar:SetValue(0)
	statusBar:Hide()
	statusBar._wrapper:Hide()

	local bar = {
		_frame       = frame,
		_statusBar   = statusBar,
		_depleting   = false,
		_duration    = 1,
		_expirationTime = 0,
		_durObj      = nil,
	}

	for k, v in next, BarMethods do
		bar[k] = v
	end

	-- Allow DepletingOnUpdate to reach bar via statusBar._barRef
	statusBar._barRef = bar

	return bar
end
