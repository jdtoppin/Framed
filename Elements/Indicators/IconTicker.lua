local addonName, Framed = ...
local F = Framed

F.Indicators = F.Indicators or {}

-- ============================================================
-- Shared ticker for Icon color progression + threshold visibility
-- One OnUpdate for ALL active icons, throttled to TICKER_INTERVAL
-- ============================================================

-- 1.0s keeps color/threshold updates smooth enough for timers of a few
-- seconds or more while halving the per-tick cost vs. the previous
-- 0.5s. Bracket-curve threshold crossings incur at most one tick of
-- latency (~1s) before countdown numbers show/hide.
local TICKER_INTERVAL = 1.0

local tickerFrame = CreateFrame('Frame')
local activeIcons = {}  -- set: icon = true
local activeCount = 0

tickerFrame:Hide()  -- starts hidden; shown when first icon registers

F.Indicators.IconTicker_Frame = tickerFrame

tickerFrame:SetScript('OnUpdate', function(self, elapsed)
	self._elapsed = (self._elapsed or 0) + elapsed
	if(self._elapsed < TICKER_INTERVAL) then return end
	self._elapsed = 0

	for icon in next, activeIcons do
		-- Color progression
		if(icon._colorCurve and icon._durationObj) then
			local color = icon._durationObj:EvaluateRemainingPercent(icon._colorCurve)
			if(icon._cdText) then
				icon._cdText:SetTextColor(color:GetRGBA())
			end
		end

		-- Threshold visibility — bracket curve returns alpha 1 (show)
		-- or 0 (hide). Cache the last-applied hide state and skip the
		-- C-level setter between crossings; only the eval is unavoidable.
		if(icon._thresholdCurve and icon._durationObj and icon._cooldown) then
			local vis = icon._durationObj:EvaluateRemainingPercent(icon._thresholdCurve)
			local _, _, _, a = vis:GetRGBA()
			if(F.IsValueNonSecret(a)) then
				local hide = a <= 0.5
				if(icon._lastThresholdHide ~= hide) then
					icon._cooldown:SetHideCountdownNumbers(hide)
					icon._lastThresholdHide = hide
				end
			end
		end
	end
end)

--- Register an icon for ticker updates.
--- @param icon table The icon object
function F.Indicators.IconTicker_Register(icon)
	if(not activeIcons[icon]) then
		activeIcons[icon] = true
		activeCount = activeCount + 1
		if(activeCount > 0) then
			tickerFrame:Show()
		end
	end
end

--- Unregister an icon from ticker updates.
--- @param icon table The icon object
function F.Indicators.IconTicker_Unregister(icon)
	if(activeIcons[icon]) then
		activeIcons[icon] = nil
		activeCount = activeCount - 1
		if(activeCount <= 0) then
			activeCount = 0
			tickerFrame:Hide()
		end
	end
	-- Drop the threshold-hide cache so the next active session starts
	-- fresh and the first evaluation asserts state unconditionally.
	icon._lastThresholdHide = nil
end
