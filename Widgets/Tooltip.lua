local addonName, Framed = ...
local F = Framed

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- Tooltip system — ported from AbstractFramework (GPL v3)
--
-- Two tiers:
--   1. Widget tooltip: simple title + body (settings panels)
--   2. Game tooltip: GameTooltip-based for spell/item info
-- ============================================================

-- ============================================================
-- Config helpers
-- ============================================================

local function getConfig(key)
	if(F.Config) then
		return F.Config:Get('general.' .. key)
	end
	return nil
end

-- ============================================================
-- Tier 1: Widget tooltip (simple title + body)
-- ============================================================

local widgetTooltip  -- singleton frame, created on first use

local PAD = C.Spacing.tight   -- 8px
local GAP = 4

local function EnsureWidgetTooltip()
	if(widgetTooltip) then return end

	widgetTooltip = CreateFrame('Frame', 'FramedWidgetTooltip', UIParent, 'BackdropTemplate')
	widgetTooltip:SetFrameStrata('TOOLTIP')
	widgetTooltip:SetClampedToScreen(true)
	widgetTooltip:Hide()

	Widgets.ApplyBackdrop(widgetTooltip, C.Colors.panel, C.Colors.accent)

	-- Title font string
	widgetTooltip.titleFS = Widgets.CreateFontString(widgetTooltip, C.Font.sizeNormal, C.Colors.textActive)
	widgetTooltip.titleFS:SetPoint('TOPLEFT', widgetTooltip, 'TOPLEFT', PAD, -PAD)
	widgetTooltip.titleFS:SetWordWrap(false)

	-- Body font string
	widgetTooltip.bodyFS = Widgets.CreateFontString(widgetTooltip, C.Font.sizeSmall, C.Colors.textSecondary)
	widgetTooltip.bodyFS:SetPoint('TOPLEFT', widgetTooltip.titleFS, 'BOTTOMLEFT', 0, -4)
	widgetTooltip.bodyFS:SetWordWrap(false)
end

local function AutoSizeWidgetTooltip()
	local titleW = widgetTooltip.titleFS:GetStringWidth()
	local titleH = widgetTooltip.titleFS:GetStringHeight()

	local hasBody = widgetTooltip.bodyFS:IsShown()
	local bodyW   = hasBody and widgetTooltip.bodyFS:GetStringWidth()  or 0
	local bodyH   = hasBody and widgetTooltip.bodyFS:GetStringHeight() or 0

	local innerW = math.max(titleW, bodyW)
	local innerH = titleH + (hasBody and (4 + bodyH) or 0)

	Widgets.SetSize(widgetTooltip, innerW + PAD * 2, innerH + PAD * 2)
end

-- ============================================================
-- Anchor system (shared by both tiers)
-- ============================================================

--- Given an anchor like 'LEFT', returns the opposing point
--- so the tooltip attaches outside the owner.
local ANCHOR_OVERRIDE = {
	LEFT        = 'RIGHT',
	RIGHT       = 'LEFT',
	TOP         = 'BOTTOM',
	BOTTOM      = 'TOP',
	BOTTOMLEFT  = 'TOPLEFT',
	BOTTOMRIGHT = 'TOPRIGHT',
	TOPLEFT     = 'BOTTOMLEFT',
	TOPRIGHT    = 'BOTTOMRIGHT',
}

--- Standard ANCHOR_X to (tooltipPoint, ownerPoint, xSign, ySign) map
local ANCHOR_MAP = {
	ANCHOR_RIGHT  = { 'LEFT',   'RIGHT',  1,  0 },
	ANCHOR_LEFT   = { 'RIGHT',  'LEFT',  -1,  0 },
	ANCHOR_TOP    = { 'BOTTOM', 'TOP',    0,  1 },
	ANCHOR_BOTTOM = { 'TOP',    'BOTTOM', 0, -1 },
}

local function PositionFrame(frame, owner, anchor)
	frame:ClearAllPoints()

	local cfgOffX = getConfig('tooltipOffsetX') or 0
	local cfgOffY = getConfig('tooltipOffsetY') or 0

	if(anchor == 'ANCHOR_CURSOR') then
		local cx, cy = GetCursorPosition()
		local scale  = UIParent:GetEffectiveScale()
		frame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT',
			cx / scale + GAP + cfgOffX, cy / scale + GAP + cfgOffY)
		return
	end

	-- Check if owner has a custom tooltip owner override
	local anchorTo = owner._tooltipOwner or owner

	-- Handle both 'LEFT' style and 'ANCHOR_RIGHT' style
	if(ANCHOR_OVERRIDE[anchor]) then
		frame:SetPoint(ANCHOR_OVERRIDE[anchor], anchorTo, anchor, cfgOffX, cfgOffY)
		return
	end

	local info = ANCHOR_MAP[anchor] or ANCHOR_MAP['ANCHOR_RIGHT']
	local tooltipPoint, ownerPoint, xSign, ySign = info[1], info[2], info[3], info[4]
	frame:SetPoint(tooltipPoint, anchorTo, ownerPoint,
		xSign * GAP + cfgOffX, ySign * GAP + cfgOffY)
end

-- ============================================================
-- Widget tooltip: Public API
-- ============================================================

--- Show the simple widget tooltip attached to owner.
--- @param owner Frame The frame to anchor against
--- @param title string Tooltip title text
--- @param body? string Optional secondary body text
--- @param anchor? string Anchor direction (default from config or 'ANCHOR_RIGHT')
function Widgets.ShowTooltip(owner, title, body, anchor)
	if(getConfig('tooltipEnabled') == false) then return end
	if(getConfig('tooltipHideInCombat') and InCombatLockdown()) then return end

	EnsureWidgetTooltip()

	anchor = anchor or getConfig('tooltipAnchor') or 'ANCHOR_RIGHT'

	widgetTooltip.titleFS:SetText(title or '')
	widgetTooltip.titleFS:Show()

	if(body and body ~= '') then
		widgetTooltip.bodyFS:SetText(body)
		widgetTooltip.bodyFS:Show()
	else
		widgetTooltip.bodyFS:SetText('')
		widgetTooltip.bodyFS:Hide()
	end

	AutoSizeWidgetTooltip()
	PositionFrame(widgetTooltip, owner, anchor)
	widgetTooltip:Show()
end

--- Show a multi-line tooltip. First line is the title (accent colored),
--- remaining lines are body text. Supports string lines and
--- {left, right} table lines for double-column display.
--- @param owner Frame The frame to anchor against
--- @param anchor string Anchor point (e.g., 'TOP', 'ANCHOR_RIGHT')
--- @param x number X offset
--- @param y number Y offset
--- @param lines table Array of strings or {left, right} tables
function Widgets.ShowMultiLineTooltip(owner, anchor, x, y, lines)
	if(type(lines) ~= 'table' or #lines == 0) then
		Widgets.HideTooltip()
		return
	end

	EnsureWidgetTooltip()

	-- Build combined text
	local titleText = lines[1]
	local bodyParts = {}
	for i = 2, #lines do
		local line = lines[i]
		if(type(line) == 'string') then
			bodyParts[#bodyParts + 1] = line
		elseif(type(line) == 'table') then
			bodyParts[#bodyParts + 1] = line[1] .. '  ' .. line[2]
		end
	end

	local bodyText = #bodyParts > 0 and table.concat(bodyParts, '\n') or nil

	widgetTooltip.titleFS:SetText(titleText or '')
	widgetTooltip.titleFS:Show()

	if(bodyText) then
		widgetTooltip.bodyFS:SetText(bodyText)
		widgetTooltip.bodyFS:SetWordWrap(true)
		widgetTooltip.bodyFS:Show()
	else
		widgetTooltip.bodyFS:SetText('')
		widgetTooltip.bodyFS:Hide()
	end

	AutoSizeWidgetTooltip()
	PositionFrame(widgetTooltip, owner, anchor)
	widgetTooltip:Show()
end

--- Hide the widget tooltip and clear its text.
function Widgets.HideTooltip()
	if(not widgetTooltip) then return end
	widgetTooltip:Hide()
	widgetTooltip.titleFS:SetText('')
	widgetTooltip.bodyFS:SetText('')
	widgetTooltip.bodyFS:SetWordWrap(false)
	widgetTooltip.bodyFS:Hide()
end

-- ============================================================
-- Tier 2: Game tooltip (spell/item info via GameTooltip)
-- ============================================================

local gameTooltip  -- singleton GameTooltip, created on first use

local function EnsureGameTooltip()
	if(gameTooltip) then return end

	gameTooltip = CreateFrame('GameTooltip', 'FramedGameTooltip', UIParent, 'SharedTooltipTemplate,BackdropTemplate')
	gameTooltip:SetFrameStrata('TOOLTIP')
	gameTooltip:SetClampedToScreen(true)

	Widgets.ApplyBackdrop(gameTooltip, { 0.1, 0.1, 0.1, 0.9 }, C.Colors.accent)

	gameTooltip:SetScript('OnHide', function(self)
		self.itemID = nil
		self.spellID = nil
		self:ClearLines()
		GameTooltip_ClearMoney(self)
		if(GameTooltip_ClearStatusBars) then GameTooltip_ClearStatusBars(self) end
		if(GameTooltip_ClearProgressBars) then GameTooltip_ClearProgressBars(self) end
		if(TooltipComparisonManager) then
			TooltipComparisonManager:Clear(self)
		end
		-- Reset border color
		local ac = C.Colors.accent
		self:SetBackdropBorderColor(ac[1], ac[2], ac[3], ac[4] or 1)
	end)

	if(gameTooltip.RegisterEvent) then
		gameTooltip:RegisterEvent('TOOLTIP_DATA_UPDATE')
		gameTooltip:SetScript('OnEvent', function(self, event)
			if(event == 'TOOLTIP_DATA_UPDATE' and self:IsVisible()) then
				if(self.itemID) then
					self:SetItemByID(self.itemID)
				elseif(self.spellID) then
					self:SetSpellByID(self.spellID)
				end
			end
		end)
	end
end

--- Get the Framed GameTooltip (creating if needed).
--- @return GameTooltip
function Widgets.GetGameTooltip()
	EnsureGameTooltip()
	return gameTooltip
end

--- Show a spell tooltip anchored to the given frame.
--- @param owner Frame
--- @param spellID number
--- @param anchor? string
function Widgets.ShowSpellTooltip(owner, spellID, anchor)
	EnsureGameTooltip()
	anchor = anchor or 'ANCHOR_RIGHT'

	gameTooltip:SetOwner(owner, 'ANCHOR_NONE')
	PositionFrame(gameTooltip, owner, anchor)
	gameTooltip.spellID = spellID
	gameTooltip.itemID = nil
	gameTooltip:SetSpellByID(spellID)
	gameTooltip:Show()
end

--- Show an item tooltip anchored to the given frame.
--- @param owner Frame
--- @param itemID number
--- @param anchor? string
function Widgets.ShowItemTooltip(owner, itemID, anchor)
	EnsureGameTooltip()
	anchor = anchor or 'ANCHOR_RIGHT'

	gameTooltip:SetOwner(owner, 'ANCHOR_NONE')
	PositionFrame(gameTooltip, owner, anchor)
	gameTooltip.itemID = itemID
	gameTooltip.spellID = nil
	gameTooltip:SetItemByID(itemID)

	-- Color border by item quality
	local quality = C_Item.GetItemQualityByID(itemID)
	if(quality) then
		local r, g, b = GetItemQualityColor(quality)
		gameTooltip:SetBackdropBorderColor(r, g, b)
	end

	gameTooltip:Show()
end

--- Hide the game tooltip.
function Widgets.HideGameTooltip()
	if(gameTooltip) then
		gameTooltip:Hide()
	end
end

-- ============================================================
-- Declarative tooltip attachment (AF-style SetTooltip)
-- ============================================================

--- Attach tooltip data to a widget. The tooltip will auto-show
--- on mouse enter and hide on mouse leave. Uses HookScript to
--- preserve existing scripts.
---
--- Supports two calling patterns:
---   SetTooltip(widget, 'Title', 'Body')           -- simple
---   SetTooltip(widget, {'Title', 'Line 2', ...})  -- multi-line
---
--- @param widget Frame
--- @param titleOrLines string|table
--- @param body? string
--- @param anchor? string
function Widgets.SetTooltip(widget, titleOrLines, body, anchor)
	if(type(titleOrLines) == 'table') then
		widget._tooltipLines = titleOrLines
		widget._tooltipTitle = titleOrLines[1]
		widget._tooltipBody = nil
	else
		widget._tooltipLines = nil
		widget._tooltipTitle = titleOrLines
		widget._tooltipBody = body
	end
	widget._tooltipAnchor = anchor

	if(not widget._tooltipInited) then
		widget._tooltipInited = true

		widget:HookScript('OnEnter', function(self)
			if(self.IsEnabled and not self:IsEnabled()) then return end
			if(self._tooltipLines) then
				Widgets.ShowMultiLineTooltip(self,
					self._tooltipAnchor or 'ANCHOR_RIGHT', 0, 0,
					self._tooltipLines)
			elseif(self._tooltipTitle) then
				Widgets.ShowTooltip(self, self._tooltipTitle,
					self._tooltipBody, self._tooltipAnchor)
			end
		end)
		widget:HookScript('OnLeave', function()
			Widgets.HideTooltip()
		end)
	end
end

--- Clear tooltip data from a widget.
--- @param widget Frame
function Widgets.ClearTooltip(widget)
	widget._tooltipTitle = nil
	widget._tooltipBody = nil
	widget._tooltipLines = nil
end

--- Hook OnEnter/OnLeave on a frame to auto-show/hide its tooltip.
--- Reads tooltip data from frame._tooltipTitle / frame._tooltipBody.
--- Uses HookScript so existing scripts are preserved.
--- @param frame Frame
function Widgets.AttachTooltipScripts(frame)
	if(frame._tooltipInited) then return end
	frame._tooltipInited = true

	frame:HookScript('OnEnter', function(self)
		if(self._tooltipTitle) then
			Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
		end
	end)

	frame:HookScript('OnLeave', function(self)
		Widgets.HideTooltip()
	end)
end
