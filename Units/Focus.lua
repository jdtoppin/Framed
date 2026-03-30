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
	F.StyleBuilder.Apply(self, unit, config, 'focus')
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Focus.Spawn()
	oUF:RegisterStyle('FramedFocus', Style)
	oUF:SetActiveStyle('FramedFocus')

	local frame = oUF:Spawn('focus', 'FramedFocusFrame')

	local config = F.StyleBuilder.GetConfig('focus')
	local x = config.position.x
	local y = config.position.y
	F.Widgets.SetPoint(frame, 'CENTER', UIParent, 'CENTER', x, y)

	F.Widgets.RegisterForUIScale(frame)

	F.Units.Focus.frame = frame
end
