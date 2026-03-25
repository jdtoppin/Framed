local addonName, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units = F.Units or {}
F.Units.Focus = {}

-- ============================================================
-- Style
-- ============================================================

local function Style(self, unit)
	local config = F.StyleBuilder.GetConfig('focus')
	F.StyleBuilder.Apply(self, unit, config)
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Focus.Spawn()
	oUF:RegisterStyle('FramedFocus', Style)
	oUF:SetActiveStyle('FramedFocus')

	local frame = oUF:Spawn('focus', 'FramedFocusFrame')
	frame:SetPoint('CENTER', UIParent, 'CENTER', -300, -100)
	F.Widgets.RegisterForUIScale(frame)

	F.Units.Focus.frame = frame
end
