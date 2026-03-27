local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Indicators = F.Indicators or {}
F.Indicators.Icons = {}

-- ============================================================
-- Icons methods
-- ============================================================

local IconsMethods = {}

--- Fill icons from the pool with aura data and lay them out.
--- @param auraList table Array of { spellID, icon, duration, expirationTime, stacks, dispelType }
function IconsMethods:SetIcons(auraList)
	local cfg = self._config
	local container = self._frame
	local count = math.min(#auraList, cfg.maxIcons)

	for i = 1, count do
		local aura = auraList[i]

		-- Lazily create icons up to maxIcons
		if(not self._pool[i]) then
			self._pool[i] = F.Indicators.Icon.Create(container, nil, {
				iconWidth    = cfg.iconWidth,
				iconHeight   = cfg.iconHeight,
				displayType  = cfg.displayType,
				showCooldown = cfg.showCooldown,
				showStacks   = cfg.showStacks,
				durationMode = cfg.durationMode,
				durationFont = cfg.durationFont,
				stackFont    = cfg.stackFont,
				spellColors  = cfg.spellColors,
			})
		end

		local icon = self._pool[i]
		icon:ClearAllPoints()

		-- Position based on grow direction + grid
		local numPerLine = cfg.numPerLine
		local row, col

		if(numPerLine > 0) then
			col = (i - 1) % numPerLine
			row = math.floor((i - 1) / numPerLine)
		else
			col = i - 1
			row = 0
		end

		local offsetX = col * (cfg.iconWidth + cfg.spacingX)
		local offsetY = row * (cfg.iconHeight + cfg.spacingY)
		local growDirection = cfg.growDirection or 'RIGHT'

		if(growDirection == 'RIGHT') then
			icon:SetPoint('TOPLEFT', container, 'TOPLEFT', offsetX, -offsetY)
		elseif(growDirection == 'LEFT') then
			icon:SetPoint('TOPRIGHT', container, 'TOPRIGHT', -offsetX, -offsetY)
		elseif(growDirection == 'DOWN') then
			icon:SetPoint('TOPLEFT', container, 'TOPLEFT', offsetY, -offsetX)
		elseif(growDirection == 'UP') then
			icon:SetPoint('BOTTOMLEFT', container, 'BOTTOMLEFT', offsetY, offsetX)
		end

		icon:SetSpell(
			aura.spellID,
			aura.icon,
			aura.duration,
			aura.expirationTime,
			aura.stacks,
			aura.dispelType
		)
		icon:Show()
	end

	-- Hide any pool entries beyond the active count
	for i = count + 1, #self._pool do
		self._pool[i]:Hide()
	end

	self._activeCount = count
end

--- Clear all active icons.
function IconsMethods:Clear()
	for i = 1, #self._pool do
		self._pool[i]:Clear()
	end
	self._activeCount = 0
end

--- Update the maximum number of icons shown.
--- Hides any currently-active icons beyond the new limit.
--- @param n number
function IconsMethods:SetMaxIcons(n)
	self._config.maxIcons = n
	-- Hide pool entries beyond the new limit
	for i = n + 1, #self._pool do
		self._pool[i]:Hide()
	end
	if(self._activeCount > n) then
		self._activeCount = n
	end
end

--- Return the number of icons currently displayed.
--- @return number
function IconsMethods:GetActiveCount()
	return self._activeCount
end

--- Show the container frame.
function IconsMethods:Show()
	self._frame:Show()
end

--- Hide the container frame (also hides all children).
function IconsMethods:Hide()
	self._frame:Hide()
end

--- Set a point on the container frame.
--- @param ... any SetPoint arguments
function IconsMethods:SetPoint(...)
	self._frame:SetPoint(...)
end

--- Clear all points on the container frame.
function IconsMethods:ClearAllPoints()
	self._frame:ClearAllPoints()
end

--- Return the underlying container frame.
--- @return Frame
function IconsMethods:GetFrame()
	return self._frame
end

-- ============================================================
-- Factory
-- ============================================================

--- Create an Icons indicator primitive (pool of Icon objects in a container).
--- @param parent Frame
--- @param config table {
---     maxIcons      number   (default 4),
---     iconWidth     number   (default iconSize or 14),
---     iconHeight    number   (default iconSize or 14),
---     iconSize      number   legacy alias for iconWidth/iconHeight (default 14),
---     spacing       number   (default 1),
---     spacingX      number   per-axis override (default spacing),
---     spacingY      number   per-axis override (default spacing),
---     numPerLine    number   icons per row/column before wrapping; 0 = no wrap (default 0),
---     growDirection string   'RIGHT'|'LEFT'|'DOWN'|'UP' (default 'RIGHT'),
---     displayType   string   C.IconDisplay value (default SpellIcon),
---     showCooldown  boolean  (default true),
---     showStacks    boolean  (default true),
---     durationMode  string   'Always'|'Never'|'<75'|'<50'|'<25'|'<15s'|'<5s' (default 'Always'),
---     durationFont  table|nil,
---     stackFont     table|nil,
---     spellColors   table|nil  map of spellID -> {r,g,b},
--- }
--- @return table icons
function F.Indicators.Icons.Create(parent, config)
	config = config or {}

	local cfg = {
		maxIcons      = config.maxIcons      or 4,
		iconWidth     = config.iconWidth     or config.iconSize or 14,
		iconHeight    = config.iconHeight    or config.iconSize or 14,
		iconSize      = config.iconWidth     or config.iconSize or 14,  -- keep for backward compat
		spacing       = config.spacing       or 1,
		spacingX      = config.spacingX      or config.spacing or 1,
		spacingY      = config.spacingY      or config.spacing or 1,
		numPerLine    = config.numPerLine    or 0,  -- 0 = single row/column (no wrapping)
		growDirection = config.growDirection or 'RIGHT',
		displayType   = config.displayType   or C.IconDisplay.SPELL_ICON,
		showCooldown  = config.showCooldown  ~= false,
		showStacks    = config.showStacks    ~= false,
		durationMode  = config.durationMode  or 'Always',
		durationFont  = config.durationFont,
		stackFont     = config.stackFont,
		spellColors   = config.spellColors,
	}

	-- Container frame — sized to fit max icons in the grow direction
	local totalWidth, totalHeight
	local growDirection = cfg.growDirection
	local numPerLine = cfg.numPerLine
	local maxIcons = cfg.maxIcons

	if(numPerLine > 0 and maxIcons > numPerLine) then
		local numLines = math.ceil(maxIcons / numPerLine)
		if(growDirection == 'RIGHT' or growDirection == 'LEFT') then
			totalWidth  = numPerLine * cfg.iconWidth + math.max(0, numPerLine - 1) * cfg.spacingX
			totalHeight = numLines * cfg.iconHeight + math.max(0, numLines - 1) * cfg.spacingY
		else -- UP / DOWN
			totalWidth  = numLines * cfg.iconWidth + math.max(0, numLines - 1) * cfg.spacingX
			totalHeight = numPerLine * cfg.iconHeight + math.max(0, numPerLine - 1) * cfg.spacingY
		end
	else
		if(growDirection == 'RIGHT' or growDirection == 'LEFT') then
			totalWidth  = maxIcons * cfg.iconWidth + math.max(0, maxIcons - 1) * cfg.spacingX
			totalHeight = cfg.iconHeight
		else
			totalWidth  = cfg.iconWidth
			totalHeight = maxIcons * cfg.iconHeight + math.max(0, maxIcons - 1) * cfg.spacingY
		end
	end

	local frame = CreateFrame('Frame', nil, parent)
	Widgets.SetSize(frame, totalWidth, totalHeight)

	local icons = {
		_frame       = frame,
		_config      = cfg,
		_pool        = {},
		_activeCount = 0,
	}

	-- Apply methods
	for k, v in next, IconsMethods do
		icons[k] = v
	end

	return icons
end
