local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.FrameBar = {}

-- ============================================================
-- FrameBar methods
-- ============================================================

local FrameBarMethods = {}

--- Adjust the overlay width proportionally to current/max.
--- Width clamps between 0 and the parent's width.
--- @param current number
--- @param max number
function FrameBarMethods:SetValue(current, max)
	if(not max or max <= 0) then
		self._texture:SetWidth(0.001)   -- SetWidth(0) is not valid; use a near-zero value
		return
	end

	local fraction = math.max(0, math.min(1, current / max))
	local parentWidth = self._parent:GetWidth()
	local newWidth = parentWidth * fraction

	if(newWidth <= 0) then
		self._texture:SetWidth(0.001)
	else
		self._texture:SetWidth(newWidth)
	end

	self._texture:Show()
	self._frame:Show()
end

--- Update the overlay color.
--- @param r number
--- @param g number
--- @param b number
--- @param a number
function FrameBarMethods:SetColor(r, g, b, a)
	self._texture:SetColorTexture(r, g, b, a or 1)
end

--- Hide the overlay and reset its width.
function FrameBarMethods:Clear()
	self._texture:SetWidth(0.001)
	self._texture:Hide()
	self._frame:Hide()
end

--- Show the overlay frame.
function FrameBarMethods:Show()
	self._frame:Show()
end

--- Hide the overlay frame.
function FrameBarMethods:Hide()
	self._frame:Hide()
end

--- Return the underlying frame.
--- @return Frame
function FrameBarMethods:GetFrame()
	return self._frame
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a FrameBar overlay indicator.
--- Overlays on top of the parent (typically a health bar) and fills
--- proportionally from the left edge.
--- @param parent Frame The frame to overlay (usually a health bar)
--- @param config table { color = {r,g,b,a} }
--- @return table frameBar
function F.Indicators.FrameBar.Create(parent, config)
	config = config or {}
	local color = config.color or { 1, 0.8, 0, 0.4 }

	-- Container frame sits on top of the parent at OVERLAY strata
	local frame = CreateFrame('Frame', nil, parent)
	frame:SetAllPoints(parent)
	frame:SetFrameLevel(parent:GetFrameLevel() + 2)
	frame:Hide()

	-- Overlay texture anchored to the left edge, full height
	local texture = frame:CreateTexture(nil, 'OVERLAY')
	texture:SetPoint('TOPLEFT',    frame, 'TOPLEFT',    0, 0)
	texture:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
	texture:SetWidth(0.001)
	texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	texture:Hide()

	local frameBar = {
		_frame   = frame,
		_texture = texture,
		_parent  = parent,
	}

	for k, v in next, FrameBarMethods do
		frameBar[k] = v
	end

	return frameBar
end
