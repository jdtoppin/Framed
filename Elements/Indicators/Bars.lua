local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Bars = {}

-- ============================================================
-- Bars methods
-- ============================================================

local BarsMethods = {}

--- Set bars from aura data list. Each entry: { spellId, icon, duration, expirationTime, count, color }
--- @param auraList table[]
function BarsMethods:SetBars(auraList)
	local count = math.min(#auraList, self._maxDisplayed)
	local config = self._config

	for i = 1, count do
		local bar = self:_GetBar(i)
		local aura = auraList[i]
		if(aura.duration and aura.duration > 0 and aura.expirationTime) then
			bar:SetDuration(aura.duration, aura.expirationTime)
		else
			bar:SetValue(1, 1)
		end
		if(aura.color) then
			bar:SetColor(aura.color[1], aura.color[2], aura.color[3], aura.color[4] or 1)
		end
		if(aura.count) then
			bar:SetStacks(aura.count)
		end
		bar:Show()
	end

	-- Hide unused bars
	for i = count + 1, #self._pool do
		self._pool[i]:Clear()
	end

	self._activeCount = count
	self:_Layout(count)
	if(count > 0) then self._frame:Show() end
end

--- Hide all bars.
function BarsMethods:Clear()
	for i = 1, #self._pool do
		self._pool[i]:Clear()
	end
	self._activeCount = 0
	self._frame:Hide()
end

function BarsMethods:Show() self._frame:Show() end
function BarsMethods:Hide() self._frame:Hide() end
function BarsMethods:GetFrame() return self._frame end
function BarsMethods:SetPoint(...) self._frame:SetPoint(...) end
function BarsMethods:ClearAllPoints() self._frame:ClearAllPoints() end
function BarsMethods:GetActiveCount() return self._activeCount end

--- Lazily create or return an existing bar in the pool.
function BarsMethods:_GetBar(index)
	if(not self._pool[index]) then
		self._pool[index] = F.Indicators.Bar.Create(self._frame, self._config)
	end
	return self._pool[index]
end

--- Layout bars in a grid.
function BarsMethods:_Layout(count)
	local barW    = self._config.barWidth or 50
	local barH    = self._config.barHeight or 4
	local spX     = self._config.spacingX or 1
	local spY     = self._config.spacingY or 1
	local perLine = self._config.numPerLine or 0
	local orient  = self._config.orientation or 'DOWN'

	if(perLine <= 0) then perLine = count end

	for i = 1, count do
		local bar = self._pool[i]
		local frame = bar:GetFrame()
		frame:ClearAllPoints()

		local idx = i - 1
		local col = idx % perLine
		local row = math.floor(idx / perLine)

		local x, y = 0, 0
		if(orient == 'RIGHT') then
			x = col * (barW + spX)
			y = -(row * (barH + spY))
		elseif(orient == 'LEFT') then
			x = -(col * (barW + spX))
			y = -(row * (barH + spY))
		elseif(orient == 'DOWN') then
			x = row * (barW + spX)
			y = -(col * (barH + spY))
		elseif(orient == 'UP') then
			x = row * (barW + spX)
			y = col * (barH + spY)
		end

		frame:SetPoint('TOPLEFT', self._frame, 'TOPLEFT', x, y)
	end
end

-- ============================================================
-- Factory
-- ============================================================

--- Create a Bars (multi-bar grid) indicator.
--- @param parent Frame
--- @param config table
--- @return table bars
function F.Indicators.Bars.Create(parent, config)
	config = config or {}

	local frame = CreateFrame('Frame', nil, parent)
	frame:SetFrameLevel(parent:GetFrameLevel() + 5)
	frame:Hide()

	local bars = {
		_frame        = frame,
		_pool         = {},
		_config       = config,
		_activeCount  = 0,
		_maxDisplayed = config.maxDisplayed or 3,
	}

	for k, v in next, BarsMethods do
		bars[k] = v
	end

	return bars
end
