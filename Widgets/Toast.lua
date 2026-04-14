local _, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Transient toast notification.
-- Slides in from the bottom of an anchor frame, holds for a
-- duration, then fades out and releases itself. Optional action
-- button on the right dismisses the toast immediately when clicked.
--
-- No stacking: if a toast is triggered while another is visible,
-- the existing one fast-fades and the new one takes its place.
-- ============================================================

local activeToast

local TOAST_WIDTH    = 320
local TOAST_HEIGHT   = 40
local SLIDE_DURATION = 0.15
local FADE_DURATION  = 0.25
local DEFAULT_HOLD   = 4

local function dismiss(toast, immediate)
	if(not toast) then return end
	if(toast._holdTimer) then
		toast._holdTimer:Cancel()
		toast._holdTimer = nil
	end
	if(immediate) then
		toast:Hide()
		if(activeToast == toast) then activeToast = nil end
		return
	end

	-- Cancel any in-flight entry slide so it doesn't race the dismiss
	-- animation. Both are keyed in the same `_anim` table and the OnUpdate
	-- loop drives them independently, so without this a fast Undo click
	-- during the slide-in would have two animations fighting over y/alpha.
	if(toast._anim) then toast._anim.toastSlide = nil end

	-- Mirror the entry animation: slide back down 20px while fading alpha
	-- from current value to 0. Position and alpha are driven by a single
	-- animation so the two channels stay in sync, matching the slide-in
	-- pattern in ShowToast.
	local targetY = toast._targetY
	local startY  = toast._startY
	local a       = toast._anchor or {}

	if(not targetY or not startY) then
		-- Fallback: no stored geometry (shouldn't happen for toasts created
		-- via ShowToast). Fall back to a plain fade so the toast still
		-- dismisses gracefully.
		Widgets.StartAnimation(
			toast, 'toastFade',
			toast:GetAlpha(), 0,
			FADE_DURATION,
			function(self, value)
				self:SetAlpha(value)
			end,
			function(self)
				self:Hide()
				if(activeToast == self) then activeToast = nil end
			end
		)
		return
	end

	local startAlpha = toast:GetAlpha()

	Widgets.StartAnimation(
		toast, 'toastFade',
		targetY, startY,
		SLIDE_DURATION,
		function(self, value)
			self:ClearAllPoints()
			Widgets.SetPoint(
				self,
				a.point    or 'BOTTOM',
				a.frame    or UIParent,
				a.relPoint or 'BOTTOM',
				a.x        or 0,
				value
			)
			-- Map y-progress to alpha so visual sync matches the entry
			-- animation. At targetY (start of dismiss) alpha = startAlpha;
			-- at startY (end of dismiss) alpha = 0.
			local t = (value - startY) / (targetY - startY)
			self:SetAlpha(startAlpha * t)
		end,
		function(self)
			self:Hide()
			if(activeToast == self) then activeToast = nil end
		end
	)
end

--- Show a transient toast notification.
--- @param opts table
---   .text     string         Message text
---   .style?   string         'info' | 'warning' (default 'info')
---   .duration? number        Hold duration in seconds (default 4)
---   .anchor?  table          { point, frame, relPoint, x, y }
---   .action?  table          { text, onClick } — optional action button
--- @return Frame toast
function Widgets.ShowToast(opts)
	opts = opts or {}

	if(activeToast) then
		dismiss(activeToast, true)
	end

	local borderColor = (opts.style == 'warning') and C.Colors.warning or C.Colors.border

	local a = opts.anchor or {}
	local parent = a.frame or UIParent

	local toast = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Widgets.SetSize(toast, TOAST_WIDTH, TOAST_HEIGHT)
	Widgets.ApplyBackdrop(toast, C.Colors.widget, borderColor)
	toast:SetFrameStrata('DIALOG')

	toast:ClearAllPoints()
	Widgets.SetPoint(
		toast,
		a.point    or 'BOTTOM',
		a.frame    or UIParent,
		a.relPoint or 'BOTTOM',
		a.x        or 0,
		a.y        or 80
	)

	local label = Widgets.CreateFontString(toast, C.Font.sizeNormal, C.Colors.textNormal)
	label:SetPoint('LEFT', toast, 'LEFT', 12, 0)
	toast._label = label

	if(opts.action) then
		local btn = Widgets.CreateButton(toast, opts.action.text or 'Undo', 'accent', 60, 22)
		btn:ClearAllPoints()
		Widgets.SetPoint(btn, 'RIGHT', toast, 'RIGHT', -8, 0)
		btn:SetOnClick(function()
			if(opts.action.onClick) then opts.action.onClick() end
			dismiss(toast, false)
		end)
		toast._action = btn
		label:SetPoint('RIGHT', btn, 'LEFT', -8, 0)
	else
		label:SetPoint('RIGHT', toast, 'RIGHT', -12, 0)
	end

	label:SetText(opts.text or '')

	local targetY = a.y or 80
	local startY  = targetY - 20

	-- Stash geometry so `dismiss` can mirror this animation when fading out.
	toast._targetY = targetY
	toast._startY  = startY
	toast._anchor  = a

	toast:Show()
	toast:SetAlpha(0)

	Widgets.StartAnimation(
		toast, 'toastSlide',
		startY, targetY,
		SLIDE_DURATION,
		function(self, value)
			self:ClearAllPoints()
			Widgets.SetPoint(
				self,
				a.point    or 'BOTTOM',
				a.frame    or UIParent,
				a.relPoint or 'BOTTOM',
				a.x        or 0,
				value
			)
			local t = (value - startY) / (targetY - startY)
			self:SetAlpha(t)
		end,
		function(self)
			self:SetAlpha(1)
		end
	)

	local duration = opts.duration or DEFAULT_HOLD
	toast._holdTimer = C_Timer.NewTimer(duration, function()
		dismiss(toast, false)
	end)

	activeToast = toast
	return toast
end

--- Immediately dismiss the active toast, if any.
function Widgets.DismissToast()
	dismiss(activeToast, true)
end
