local addonName, Framed = ...
local F = Framed

F.Indicators = F.Indicators or {}

--- Check whether duration text should be shown given the current mode and values.
--- @param mode string 'Always'|'Never'|'<75'|'<50'|'<25'|'<15s'|'<5s'
--- @param remaining number seconds remaining
--- @param duration number total duration
--- @return boolean
function F.Indicators.ShouldShowDuration(mode, remaining, duration)
	if(mode == 'Always') then return true end
	if(mode == 'Never') then return false end
	if(duration <= 0) then return false end
	-- Percentage-based thresholds
	if(mode == '<75') then return (remaining / duration) < 0.75 end
	if(mode == '<50') then return (remaining / duration) < 0.50 end
	if(mode == '<25') then return (remaining / duration) < 0.25 end
	-- Time-based thresholds
	if(mode == '<15s') then return remaining < 15 end
	if(mode == '<5s') then return remaining < 5 end
	return true
end

--- Update color based on threshold config (low time %, low seconds).
--- @param self table indicator object with _color, _lowTimeColor, _lowSecsColor fields
--- @param remaining number seconds remaining
--- @param duration number total duration
--- @param setColorFn function callback(r, g, b, a) to apply the color
function F.Indicators.UpdateThresholdColor(self, remaining, duration, setColorFn)
	local ltc = self._lowSecsColor
	if(ltc and ltc.enabled and remaining <= ltc.threshold) then
		local c = ltc.color
		setColorFn(c[1], c[2], c[3], c[4] or 1)
		return
	end
	local lpc = self._lowTimeColor
	if(lpc and lpc.enabled and duration > 0) then
		local pct = remaining / duration * 100
		if(pct <= lpc.threshold) then
			local c = lpc.color
			setColorFn(c[1], c[2], c[3], c[4] or 1)
			return
		end
	end
	local base = self._color
	if(base) then
		setColorFn(base[1], base[2], base[3], base[4] or 1)
	end
end

--- Set aura stack/count text without branching on secret AuraData fields.
--- When unit + auraInstanceID are available, the display string comes from
--- C_UnitAuras and is passed straight into FontString:SetText.
--- @param fontString FontString|nil
--- @param unit string|nil
--- @param auraInstanceID number|nil
--- @param fallbackCount number|nil
function F.Indicators.SetAuraStackText(fontString, unit, auraInstanceID, fallbackCount)
	if(not fontString) then return end

	if(unit and auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount) then
		local displayCount = C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 2, 99)
		fontString:SetText(displayCount)
		fontString:Show()
		return
	end

	if(F.IsValueNonSecret(fallbackCount) and fallbackCount and fallbackCount > 1) then
		fontString:SetText(fallbackCount)
		fontString:Show()
	else
		fontString:SetText('')
		fontString:Hide()
	end
end

--- Clear a cooldown and any countdown text that was reparented for styling.
--- Cooldown:Clear() resets the cooldown state, but a moved FontString can keep
--- rendering stale text unless we explicitly blank it.
--- @param cooldown Cooldown|nil
--- @param countdownText FontString|nil
function F.Indicators.ClearCooldownCountdown(cooldown, countdownText)
	if(cooldown) then
		cooldown:Clear()
	end

	local text = countdownText
	if(not text and cooldown and cooldown.GetCountdownFontString) then
		text = cooldown:GetCountdownFontString()
	end
	if(text) then
		text:SetText('')
		text:Hide()
	end
end
