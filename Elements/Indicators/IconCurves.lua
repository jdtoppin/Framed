local addonName, Framed = ...
local F = Framed

F.Indicators = F.Indicators or {}

-- ============================================================
-- Cached bracket curves for duration threshold visibility
-- Each curve maps remaining% → alpha (1 = show, 0 = hide)
-- ============================================================

local cachedThresholdCurves = {}

-- Threshold modes that use percentage-based visibility
local THRESHOLD_PERCENTS = {
	['<75']  = 0.75,
	['<50']  = 0.50,
	['<25']  = 0.25,
	['<75%'] = 0.75,
	['<50%'] = 0.50,
	['<25%'] = 0.25,
}

--- Get or create a bracket curve for the given durationMode.
--- Returns nil for 'Always' or 'Never' (no curve needed).
--- For percentage modes: alpha=1 when remaining% < threshold, alpha=0 when above.
--- For time modes ('<15s', '<5s'): returns nil (not percentage-based, needs special handling).
--- @param mode string
--- @return LuaCurveObjectBase|nil
function F.Indicators.GetThresholdCurve(mode)
	if(mode == 'Always' or mode == 'Never') then return nil end

	if(cachedThresholdCurves[mode]) then
		return cachedThresholdCurves[mode]
	end

	local pct = THRESHOLD_PERCENTS[mode]
	if(not pct) then return nil end  -- time-based modes not supported via curves

	local curve = C_CurveUtil.CreateColorCurve()
	-- Below threshold: visible (alpha = 1)
	-- At 0% remaining (expired): visible
	curve:AddPoint(0, CreateColor(1, 1, 1, 1))
	-- Just below threshold: visible
	curve:AddPoint(pct - 0.001, CreateColor(1, 1, 1, 1))
	-- At threshold: hidden
	curve:AddPoint(pct, CreateColor(1, 1, 1, 0))
	-- Full duration remaining: hidden
	curve:AddPoint(1, CreateColor(1, 1, 1, 0))

	cachedThresholdCurves[mode] = curve
	return curve
end

--- Build a color progression curve from user config colors.
--- @param startColor table {r, g, b} color at full duration (remaining% = 1)
--- @param midColor table {r, g, b} color at half duration (remaining% = 0.5)
--- @param endColor table {r, g, b} color near expiry (remaining% = 0)
--- @return LuaCurveObjectBase
function F.Indicators.CreateDurationColorCurve(startColor, midColor, endColor)
	local curve = C_CurveUtil.CreateColorCurve()
	curve:AddPoint(0, CreateColor(endColor[1], endColor[2], endColor[3]))
	curve:AddPoint(0.5, CreateColor(midColor[1], midColor[2], midColor[3]))
	curve:AddPoint(1, CreateColor(startColor[1], startColor[2], startColor[3]))
	return curve
end
