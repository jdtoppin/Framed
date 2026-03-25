local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Overlay = {}

-- ============================================================
-- Overlay methods
-- ============================================================

local OverlayMethods = {}

--- Show the overlay with a tint color and optional centered text.
--- @param color table {r, g, b, a}
--- @param text? string Optional text to display in the center
function OverlayMethods:Show(color, text)
	if(color) then
		self._bg:SetColorTexture(
			color[1] or 0,
			color[2] or 0,
			color[3] or 0,
			color[4] or 0.6)
	end

	if(text) then
		self._label:SetText(text)
	end

	self._frame:Show()
end

--- Hide the overlay frame.
function OverlayMethods:Hide()
	self._frame:Hide()
end

--- Update the centered text without changing the background color.
--- @param text string
function OverlayMethods:SetText(text)
	self._label:SetText(text or '')
end

--- Return the underlying frame (for anchoring/parenting).
--- @return Frame
function OverlayMethods:GetFrame()
	return self._frame
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a full-frame tinted overlay with centered text.
--- Hidden by default; call Show(color, text) to display it.
--- @param parent Frame The frame to cover
--- @return table overlay
function F.Indicators.Overlay.Create(parent)
	-- Overlay frame sits above the parent at OVERLAY strata
	local frame = CreateFrame('Frame', nil, parent)
	frame:SetAllPoints(parent)
	frame:SetFrameStrata('OVERLAY')
	frame:SetFrameLevel(parent:GetFrameLevel() + 10)
	frame:Hide()

	-- Background texture covers the entire overlay frame
	local bg = frame:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(frame)
	bg:SetColorTexture(0, 0, 0, 0.6)   -- default dark semi-transparent

	-- Centered label
	local label = frame:CreateFontString(nil, 'OVERLAY')
	label:SetFont(F.Media.GetActiveFont(), C.Font.sizeNormal, 'OUTLINE')
	label:SetTextColor(1, 1, 1, 1)
	label:SetPoint('CENTER', frame, 'CENTER', 0, 0)
	label:SetJustifyH('CENTER')
	label:SetText('')

	local overlay = {
		_frame = frame,
		_bg    = bg,
		_label = label,
	}

	for k, v in next, OverlayMethods do
		overlay[k] = v
	end

	return overlay
end
