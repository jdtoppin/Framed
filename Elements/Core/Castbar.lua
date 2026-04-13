local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Castbar = {}

-- ============================================================
-- Castbar Element Setup
-- ============================================================

--- Configure oUF's built-in Castbar element on a unit frame.
--- @param self Frame  The oUF unit frame
--- @param width number  Bar width in UI units
--- @param height number  Bar height in UI units
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.Castbar.Setup(self, width, height, config)

	-- --------------------------------------------------------
	-- Config defaults
	-- --------------------------------------------------------

	config = config or {}
	config.height               = config.height or 16
	config.interruptibleColor   = config.interruptibleColor or {0.3, 0.7, 1}       -- blue
	config.nonInterruptibleColor = config.nonInterruptibleColor or {0.7, 0.3, 0.3} -- red
	config.showIcon             = config.showIcon ~= false   -- default true
	config.showText             = config.showText ~= false   -- default true
	config.showTime             = config.showTime ~= false   -- default true

	-- --------------------------------------------------------
	-- Cast bar (via Widgets.CreateStatusBar)
	-- --------------------------------------------------------

	local castbar = Widgets.CreateStatusBar(self, width, config.height)

	-- Default fill color: interruptible (blue)
	local ic = config.interruptibleColor
	castbar:SetStatusBarColor(ic[1], ic[2], ic[3], 1)

	-- Background texture (togglable)
	local bg = castbar:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(castbar)
	bg:SetTexture([[Interface\BUTTONS\WHITE8x8]])
	local bgC = C.Colors.background
	bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1)
	castbar._bg = bg
	-- Always hide the wrapper border — cast bar only shows the bg fill
	castbar._wrapper:SetBackdropBorderColor(0, 0, 0, 0)

	castbar._backgroundMode = config.backgroundMode or 'always'
	if(castbar._backgroundMode == 'oncast') then
		bg:Hide()
		castbar._wrapper:SetBackdropColor(0, 0, 0, 0)
	end

	-- --------------------------------------------------------
	-- Spell icon (optional) — positioned to the left of the bar
	-- --------------------------------------------------------

	if(config.showIcon) then
		-- Icon sits outside the wrapper, to its left; size matches bar height
		local iconSize = config.height
		local icon = castbar:CreateTexture(nil, 'ARTWORK')
		Widgets.SetSize(icon, iconSize, iconSize)
		icon:SetPoint('RIGHT', castbar._wrapper, 'LEFT', -C.Spacing.base, 0)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- trim default icon border
		castbar.Icon = icon
	end

	-- --------------------------------------------------------
	-- Spell name text (optional) — left-aligned inside bar
	-- --------------------------------------------------------

	if(config.showText) then
		local nameText = Widgets.CreateFontString(castbar, C.Font.sizeSmall, C.Colors.textActive)
		nameText:SetPoint('LEFT', castbar, 'LEFT', C.Spacing.base, 0)
		nameText:SetJustifyH('LEFT')
		castbar.Text = nameText
	end

	-- --------------------------------------------------------
	-- Cast time text (optional) — right-aligned inside bar
	-- --------------------------------------------------------

	if(config.showTime) then
		local timeText = Widgets.CreateFontString(castbar, C.Font.sizeSmall, C.Colors.textSecondary)
		timeText:SetPoint('RIGHT', castbar, 'RIGHT', -C.Spacing.base, 0)
		timeText:SetJustifyH('RIGHT')
		castbar.Time = timeText
	end

	-- --------------------------------------------------------
	-- PostCastStart hook: set interruptible / non-interruptible color
	-- oUF calls this after it processes a cast start event.
	-- --------------------------------------------------------

	castbar.PostCastStart = function(cb, unit, name)
		-- notInterruptible may be a secret boolean in Midnight — can't branch on it.
		-- Use IsValueNonSecret to safely test; default to interruptible color.
		local ni = cb.notInterruptible
		local isShielded = F.IsValueNonSecret(ni) and ni
		if(isShielded) then
			local nic = config.nonInterruptibleColor
			cb:SetStatusBarColor(nic[1], nic[2], nic[3], 1)
		else
			local icc = config.interruptibleColor
			cb:SetStatusBarColor(icc[1], icc[2], icc[3], 1)
		end
		-- Show background when cast starts (oncast mode)
		if(cb._backgroundMode == 'oncast') then
			if(cb._bg) then cb._bg:Show() end
			local castBgC = C.Colors.background
			cb._wrapper:SetBackdropColor(castBgC[1], castBgC[2], castBgC[3], castBgC[4] or 1)
		end
	end

	-- Channel casts share the same color logic
	castbar.PostChannelStart = castbar.PostCastStart

	-- Hide background when cast ends (oncast mode)
	local function onCastEnd(cb)
		if(cb._backgroundMode == 'oncast') then
			if(cb._bg) then cb._bg:Hide() end
			cb._wrapper:SetBackdropColor(0, 0, 0, 0)
		end
	end
	castbar.PostCastStop    = onCastEnd
	castbar.PostChannelStop = onCastEnd
	castbar.PostCastFail    = onCastEnd

	-- --------------------------------------------------------
	-- Assign to oUF — activates the Castbar element
	-- --------------------------------------------------------

	self.Castbar = castbar
end
