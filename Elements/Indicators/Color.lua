local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Color = {}

-- ============================================================
-- Color (Positioned Rectangle) methods
-- ============================================================

local DURATION_UPDATE_INTERVAL = 0.1

local onColorUpdate  -- forward declaration

local ColorMethods = {}

function ColorMethods:SetColor(r, g, b, a)
	self._color = { r, g, b, a or 1 }
	self._texture:SetColorTexture(r, g, b, a or 1)
end

function ColorMethods:SetDuration(duration, expirationTime)
	self._duration = duration
	self._expirationTime = expirationTime
	self._elapsed = 0
	self._frame:SetScript('OnUpdate', onColorUpdate)
	self:Show()
end

function ColorMethods:SetValue(current, max)
	self._duration = nil
	self._expirationTime = nil
	self._frame:SetScript('OnUpdate', nil)
	self:Show()
end

function ColorMethods:SetStacks(count)
	if(not self._stackText) then return end
	if(count and count > 1) then
		self._stackText:SetText(count)
		self._stackText:Show()
	else
		self._stackText:Hide()
	end
end

function ColorMethods:Clear()
	self._frame:SetScript('OnUpdate', nil)
	self._duration = nil
	self._expirationTime = nil
	if(self._stackText) then self._stackText:Hide() end
	if(self._durationText) then self._durationText:Hide() end
	self._frame:Hide()
end

function ColorMethods:Show() self._frame:Show() end
function ColorMethods:Hide() self._frame:Hide() end
function ColorMethods:GetFrame() return self._frame end
function ColorMethods:SetPoint(...) self._frame:SetPoint(...) end
function ColorMethods:ClearAllPoints() self._frame:ClearAllPoints() end

function ColorMethods:UpdateThresholdColor(remaining, duration)
	F.Indicators.UpdateThresholdColor(self, remaining, duration, function(r, g, b, a)
		self._texture:SetColorTexture(r, g, b, a)
	end)
end

-- Module-level OnUpdate
onColorUpdate = function(self, elapsed)
	local rect = self._colorRef
	if(not rect or not rect._expirationTime) then
		self:SetScript('OnUpdate', nil)
		return
	end
	rect._elapsed = (rect._elapsed or 0) + elapsed
	if(rect._elapsed < DURATION_UPDATE_INTERVAL) then return end
	rect._elapsed = 0
	local remaining = rect._expirationTime - GetTime()
	if(remaining <= 0) then
		rect:Clear()
		return
	end
	rect:UpdateThresholdColor(remaining, rect._duration or 0)
end

-- ============================================================
-- Factory
-- ============================================================

function F.Indicators.Color.Create(parent, config)
	config = config or {}
	local color   = config.color or { 1, 1, 1, 1 }
	local rectW   = config.rectWidth or 10
	local rectH   = config.rectHeight or 10
	local borderColor = config.borderColor or { 0, 0, 0, 1 }

	local frame = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(frame, rectW, rectH)
	frame:SetFrameLevel(parent:GetFrameLevel() + 5)
	frame:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	frame:SetBackdropColor(0, 0, 0, 0)
	frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
	frame:Hide()

	local texture = frame:CreateTexture(nil, 'ARTWORK')
	texture:SetPoint('TOPLEFT', frame, 'TOPLEFT', 1, -1)
	texture:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -1, 1)
	texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)

	-- Stack text (optional)
	local stackText
	if(config.showStacks ~= false) then
		local sf = config.stackFont or {}
		stackText = Widgets.CreateFontString(frame, sf.size or 10, { 1, 1, 1, 1 })
		stackText:SetPoint('CENTER', frame, 'CENTER', 0, 0)
		stackText:Hide()
	end

	local rect = {
		_frame        = frame,
		_texture      = texture,
		_stackText    = stackText,
		_color        = color,
		_lowTimeColor = config.lowTimeColor,
		_lowSecsColor = config.lowSecsColor,
		_durationMode = config.durationMode or 'Never',
	}

	for k, v in next, ColorMethods do
		rect[k] = v
	end

	frame._colorRef = rect
	return rect
end
