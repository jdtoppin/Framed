local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Overlay = {}

-- ============================================================
-- Overlay methods
-- ============================================================

local DURATION_UPDATE_INTERVAL = 0.1

local OverlayMethods = {}

function OverlayMethods:SetDuration(duration, expirationTime)
	self._duration = duration
	self._expirationTime = expirationTime
	self._elapsed = 0

	local mode = self._overlayMode

	-- Color layer: static fill while aura is active
	if(mode == 'Color' or mode == 'Both') then
		self._fbTexture:SetWidth(self._parent:GetWidth())
		self._fbTexture:Show()
		self._fbFrame:Show()
	end

	-- DurationOverlay layer: depleting bar
	if(mode == 'DurationOverlay' or mode == 'Both') then
		self._olStatusBar:SetMinMaxValues(0, duration)
		self._olStatusBar:SetValue(expirationTime - GetTime())
		self._olFrame:Show()
		self._olFrame:SetScript('OnUpdate', self._onUpdate)
	end

	self:Show()
end

function OverlayMethods:SetValue(current, max)
	-- For auras with no duration — show as static
	self._duration = nil
	self._expirationTime = nil

	local mode = self._overlayMode
	if(mode == 'Color' or mode == 'Both') then
		self._fbTexture:SetWidth(self._parent:GetWidth())
		self._fbTexture:Show()
		self._fbFrame:Show()
	end
	if(mode == 'DurationOverlay' or mode == 'Both') then
		self._olStatusBar:SetMinMaxValues(0, 1)
		self._olStatusBar:SetValue(1)
		self._olFrame:Show()
	end
	self:Show()
end

function OverlayMethods:SetColor(r, g, b, a)
	self._color = { r, g, b, a or 1 }
	if(self._fbTexture) then
		self._fbTexture:SetColorTexture(r, g, b, a or 1)
	end
	-- Overlay layer always full opacity in Both mode
	if(self._overlayMode == 'Both') then
		self._olStatusBar:SetStatusBarColor(r, g, b, 1)
	else
		self._olStatusBar:SetStatusBarColor(r, g, b, a or 1)
	end
end

function OverlayMethods:Clear()
	if(self._olFrame) then
		self._olFrame:SetScript('OnUpdate', nil)
		self._olFrame:Hide()
	end
	if(self._fbFrame) then
		self._fbFrame:Hide()
	end
	self._duration = nil
	self._expirationTime = nil
	self._frame:Hide()
end

function OverlayMethods:Show() self._frame:Show() end
function OverlayMethods:Hide() self._frame:Hide() end
function OverlayMethods:GetFrame() return self._frame end

function OverlayMethods:UpdateThresholdColor(remaining, duration)
	local isBoth = self._overlayMode == 'Both'
	F.Indicators.UpdateThresholdColor(self, remaining, duration, function(r, g, b, a)
		self._olStatusBar:SetStatusBarColor(r, g, b, isBoth and 1 or a)
	end)
end

-- ============================================================
-- Factory
-- ============================================================

function F.Indicators.Overlay.Create(parent, config)
	config = config or {}
	local color       = config.color or { 0, 0, 0, 0.6 }
	local mode        = config.overlayMode or 'DurationOverlay'
	local orientation = config.barOrientation or 'Horizontal'
	local smooth      = config.smooth ~= false

	-- Container frame — anchored to parent (health bar)
	local frame = CreateFrame('Frame', nil, parent)
	frame:SetAllPoints(parent)
	frame:SetFrameLevel(parent:GetFrameLevel() + 2)
	frame:Hide()

	-- Color layer (static fill)
	local fbFrame = CreateFrame('Frame', nil, frame)
	fbFrame:SetAllPoints(frame)
	fbFrame:SetFrameLevel(frame:GetFrameLevel())
	fbFrame:Hide()

	local fbTexture = fbFrame:CreateTexture(nil, 'OVERLAY')
	fbTexture:SetPoint('TOPLEFT', fbFrame, 'TOPLEFT', 0, 0)
	fbTexture:SetPoint('BOTTOMLEFT', fbFrame, 'BOTTOMLEFT', 0, 0)
	fbTexture:SetWidth(0.001)
	fbTexture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)

	-- Overlay layer (depleting status bar)
	local olFrame = CreateFrame('Frame', nil, frame)
	olFrame:SetAllPoints(frame)
	olFrame:SetFrameLevel(frame:GetFrameLevel() + 1)
	olFrame:Hide()

	local olBar = Widgets.CreateStatusBar(olFrame, 1, 1)
	olBar:SetAllPoints(olFrame)
	if(mode == 'Both') then
		olBar:SetStatusBarColor(color[1], color[2], color[3], 1)
	else
		olBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
	end
	if(orientation == 'Vertical') then
		olBar:SetOrientation('VERTICAL')
	end

	local overlay = {
		_frame        = frame,
		_parent       = parent,
		_fbFrame      = fbFrame,
		_fbTexture    = fbTexture,
		_olFrame      = olFrame,
		_olStatusBar  = olBar,
		_color        = color,
		_overlayMode  = mode,
		_smooth       = smooth,
		_lowTimeColor = config.lowTimeColor,
		_lowSecsColor = config.lowSecsColor,
	}

	-- OnUpdate for depletion
	local function onOverlayUpdate(self, elapsed)
		if(not overlay._expirationTime) then
			self:SetScript('OnUpdate', nil)
			return
		end
		overlay._elapsed = (overlay._elapsed or 0) + elapsed
		if(overlay._elapsed < DURATION_UPDATE_INTERVAL) then return end
		overlay._elapsed = 0

		local remaining = overlay._expirationTime - GetTime()
		if(remaining <= 0) then
			overlay:Clear()
			return
		end
		overlay._olStatusBar:SetValue(remaining)
		overlay:UpdateThresholdColor(remaining, overlay._duration or 0)
	end
	overlay._onUpdate = onOverlayUpdate

	for k, v in next, OverlayMethods do
		overlay[k] = v
	end

	return overlay
end
