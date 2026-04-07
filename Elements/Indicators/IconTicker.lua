local addonName, Framed = ...
local F = Framed

F.Indicators = F.Indicators or {}

-- ============================================================
-- Shared ticker for Icon color progression + threshold visibility
-- One OnUpdate for ALL active icons, throttled to 0.5s
-- ============================================================

local TICKER_INTERVAL = 0.5

local tickerFrame = CreateFrame('Frame')
local activeIcons = {}  -- set: icon = true
local activeCount = 0

tickerFrame:Hide()  -- starts hidden; shown when first icon registers

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

		-- Threshold visibility
		if(icon._thresholdCurve and icon._durationObj) then
			local vis = icon._durationObj:EvaluateRemainingPercent(icon._thresholdCurve)
			if(icon._cdText) then
				-- Bracket curve returns alpha 1 (show) or 0 (hide)
				local _, _, _, a = vis:GetRGBA()
				if(F.IsValueNonSecret(a)) then
					if(a > 0.5) then
						icon._cdText:Show()
					else
						icon._cdText:Hide()
					end
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
end
