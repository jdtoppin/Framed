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
	local spellColors = self._config.spellColors
	local defaultColor = self._config.color

	for i = 1, count do
		local bar = self:_GetBar(i)
		local aura = auraList[i]
		-- Apply color before showing to prevent flicker
		local sc = spellColors and spellColors[aura.spellId]
		if(sc) then
			bar:SetColor(sc[1], sc[2], sc[3], 1)
		elseif(aura.color) then
			bar:SetColor(aura.color[1], aura.color[2], aura.color[3], aura.color[4] or 1)
		elseif(defaultColor) then
			bar:SetColor(defaultColor[1], defaultColor[2], defaultColor[3], defaultColor[4] or 1)
		end
		if(aura.duration and aura.duration > 0 and aura.expirationTime) then
			bar:SetDuration(aura.duration, aura.expirationTime)
		else
			bar:SetValue(1, 1)
		end
		if(aura.stacks) then
			bar:SetStacks(aura.stacks)
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

		Widgets.SetPoint(frame, 'TOPLEFT', self._frame, 'TOPLEFT', x, y)
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

	-- Compute container size to fit max bars in the grow direction
	local barW      = config.barWidth or 50
	local barH      = config.barHeight or 4
	local spX       = config.spacingX or 1
	local spY       = config.spacingY or 1
	local maxBars   = config.maxDisplayed or 3
	local perLine   = config.numPerLine or 0
	local orient    = config.orientation or 'DOWN'

	local totalWidth, totalHeight
	if(perLine > 0 and maxBars > perLine) then
		local numLines = math.ceil(maxBars / perLine)
		if(orient == 'RIGHT' or orient == 'LEFT') then
			totalWidth  = perLine * barW + math.max(0, perLine - 1) * spX
			totalHeight = numLines * barH + math.max(0, numLines - 1) * spY
		else
			totalWidth  = numLines * barW + math.max(0, numLines - 1) * spX
			totalHeight = perLine * barH + math.max(0, perLine - 1) * spY
		end
	else
		if(orient == 'RIGHT' or orient == 'LEFT') then
			totalWidth  = maxBars * barW + math.max(0, maxBars - 1) * spX
			totalHeight = barH
		else
			totalWidth  = barW
			totalHeight = maxBars * barH + math.max(0, maxBars - 1) * spY
		end
	end

	local frame = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(frame, totalWidth, totalHeight)
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
