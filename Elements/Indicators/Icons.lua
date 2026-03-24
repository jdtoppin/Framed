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
			self._pool[i] = F.Indicators.Icon.Create(container, cfg.iconSize, {
				displayType  = cfg.displayType,
				showCooldown = cfg.showCooldown,
				showStacks   = cfg.showStacks,
				showDuration = cfg.showDuration,
			})
		end

		local icon = self._pool[i]
		icon:ClearAllPoints()

		-- Position based on grow direction
		local offset = (i - 1) * (cfg.iconSize + cfg.spacing)
		local growDirection = cfg.growDirection or 'RIGHT'

		if(growDirection == 'RIGHT') then
			icon:SetPoint('TOPLEFT', container, 'TOPLEFT', offset, 0)
		elseif(growDirection == 'LEFT') then
			icon:SetPoint('TOPRIGHT', container, 'TOPRIGHT', -offset, 0)
		elseif(growDirection == 'DOWN') then
			icon:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, -offset)
		elseif(growDirection == 'UP') then
			icon:SetPoint('BOTTOMLEFT', container, 'BOTTOMLEFT', 0, offset)
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
---     iconSize      number   (default 14),
---     spacing       number   (default 1),
---     growDirection string   'RIGHT'|'LEFT'|'DOWN'|'UP' (default 'RIGHT'),
---     displayType   string   C.IconDisplay value (default SpellIcon),
---     showCooldown  boolean  (default true),
---     showStacks    boolean  (default true),
---     showDuration  boolean  (default true),
--- }
--- @return table icons
function F.Indicators.Icons.Create(parent, config)
	config = config or {}

	local cfg = {
		maxIcons      = config.maxIcons      or 4,
		iconSize      = config.iconSize      or 14,
		spacing       = config.spacing       or 1,
		growDirection = config.growDirection or 'RIGHT',
		displayType   = config.displayType   or C.IconDisplay.SPELL_ICON,
		showCooldown  = config.showCooldown  ~= false,
		showStacks    = config.showStacks    ~= false,
		showDuration  = config.showDuration  ~= false,
	}

	-- Container frame — sized to fit max icons in the grow direction
	local totalWidth, totalHeight
	local growDirection = cfg.growDirection
	if(growDirection == 'RIGHT' or growDirection == 'LEFT') then
		totalWidth  = cfg.maxIcons * cfg.iconSize + math.max(0, cfg.maxIcons - 1) * cfg.spacing
		totalHeight = cfg.iconSize
	else -- UP / DOWN
		totalWidth  = cfg.iconSize
		totalHeight = cfg.maxIcons * cfg.iconSize + math.max(0, cfg.maxIcons - 1) * cfg.spacing
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
