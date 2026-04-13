local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Threat = {}

-- ============================================================
-- Threat Element Setup
-- ============================================================
-- Uses oUF's ThreatIndicator element. A backdrop-bordered frame
-- is placed over the unit frame; oUF shows/hides it and sets the
-- threat status. PostUpdate applies per-status colors and an
-- optional aggro blink animation.

-- Threat status constants (mirrors oUF ThreatIndicator values)
local STATUS_NONE   = 0
local STATUS_LOW    = 1
local STATUS_MEDIUM = 2
local STATUS_HIGH   = 3

local THREAT_COLORS = {
	[STATUS_LOW]    = { 1, 1,   0 },    -- yellow
	[STATUS_MEDIUM] = { 1, 0.5, 0 },    -- orange
	[STATUS_HIGH]   = { 1, 0,   0 },    -- red
}

-- Blink cycle duration (seconds for one full alpha oscillation)
local BLINK_DURATION = 0.5

--- Configure oUF's ThreatIndicator element on a unit frame.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config; defaults applied if nil
function F.Elements.Threat.Setup(self, config)

	-- --------------------------------------------------------
	-- Config defaults
	-- --------------------------------------------------------

	config = config or {}
	config.aggroBlink = config.aggroBlink or false

	-- --------------------------------------------------------
	-- Border frame (backdrop approach)
	-- Sits over the unit frame; oUF controls Show/Hide.
	-- --------------------------------------------------------

	local border = CreateFrame('Frame', nil, self, 'BackdropTemplate')
	border:SetAllPoints(self)
	border:SetFrameLevel(self:GetFrameLevel() + 5)

	Widgets.ApplyBackdrop(border,
		{ 0, 0, 0, 0 },        -- transparent background
		{ 1, 1, 0, 1 }         -- initial border color (yellow; updated in PostUpdate)
	)

	border:Hide()

	-- --------------------------------------------------------
	-- PostUpdate: per-status color and optional blink
	-- Called by oUF after each threat update.
	-- @param unit string
	-- @param status number  0-3
	-- @param r, g, b number  oUF-supplied color (not used; we apply our own)
	-- --------------------------------------------------------

	border.PostUpdate = function(indicator, unit, status)
		if(status == STATUS_NONE or not status) then
			indicator:Hide()
			-- Clear any running blink so alpha is reset when next shown
			if(indicator._anim) then
				indicator._anim['blink'] = nil
			end
			indicator:SetAlpha(1)
			return
		end

		local color = THREAT_COLORS[status] or THREAT_COLORS[STATUS_LOW]
		indicator:SetBackdropBorderColor(color[1], color[2], color[3], 1)
		indicator:Show()

		if(config.aggroBlink and status == STATUS_HIGH) then
			-- Oscillate alpha between 0.4 and 1 to create a blink effect.
			-- StartAnimation fires one-shot; we loop by restarting in onComplete.
			local function startBlink(frame)
				Widgets.StartAnimation(
					frame, 'blink',
					1, 0.4,
					BLINK_DURATION,
					function(f, value) f:SetAlpha(value) end,
					function(f)
						-- Only restart if still at high threat (frame still shown)
						if(f:IsShown()) then
							Widgets.StartAnimation(
								f, 'blink',
								0.4, 1,
								BLINK_DURATION,
								function(ff, v) ff:SetAlpha(v) end,
								function(ff)
									if(ff:IsShown()) then startBlink(ff) end
								end
							)
						end
					end
				)
			end

			-- Only start a new blink cycle if one is not already running
			if(not (indicator._anim and indicator._anim['blink'])) then
				startBlink(indicator)
			end
		else
			-- Not blinking: stop any running blink and restore full alpha
			if(indicator._anim) then
				indicator._anim['blink'] = nil
			end
			indicator:SetAlpha(1)
		end
	end

	-- --------------------------------------------------------
	-- Assign to oUF — activates the ThreatIndicator element
	-- --------------------------------------------------------

	self.ThreatIndicator = border
end
