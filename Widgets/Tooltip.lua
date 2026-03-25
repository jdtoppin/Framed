local addonName, Framed = ...
local F = Framed

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- Tooltip — singleton custom tooltip with Framed design language
-- ============================================================

local tooltip  -- singleton frame, created on first use

-- Padding applied on all sides of the tooltip content
local PAD = C.Spacing.tight   -- 8px
-- Gap between tooltip and its owner frame
local GAP = 4

-- ============================================================
-- Singleton creation
-- ============================================================

local function EnsureTooltip()
	if(tooltip) then return end

	tooltip = CreateFrame('Frame', 'FramedTooltip', UIParent, 'BackdropTemplate')
	tooltip:SetFrameStrata('TOOLTIP')
	tooltip:SetClampedToScreen(true)
	tooltip:Hide()

	Widgets.ApplyBackdrop(tooltip, C.Colors.panel, C.Colors.accent)

	-- Title font string
	tooltip.titleFS = Widgets.CreateFontString(tooltip, C.Font.sizeNormal, C.Colors.textActive)
	tooltip.titleFS:SetPoint('TOPLEFT', tooltip, 'TOPLEFT', PAD, -PAD)
	tooltip.titleFS:SetWordWrap(false)

	-- Body font string
	tooltip.bodyFS = Widgets.CreateFontString(tooltip, C.Font.sizeSmall, C.Colors.textSecondary)
	tooltip.bodyFS:SetPoint('TOPLEFT', tooltip.titleFS, 'BOTTOMLEFT', 0, -4)
	tooltip.bodyFS:SetWordWrap(false)
end

-- ============================================================
-- Auto-size: shrink/grow tooltip to fit its text content
-- ============================================================

local function AutoSize()
	local titleW = tooltip.titleFS:GetStringWidth()
	local titleH = tooltip.titleFS:GetStringHeight()

	local hasBody = tooltip.bodyFS:IsShown()
	local bodyW   = hasBody and tooltip.bodyFS:GetStringWidth()  or 0
	local bodyH   = hasBody and tooltip.bodyFS:GetStringHeight() or 0

	local innerW = math.max(titleW, bodyW)
	local innerH = titleH + (hasBody and (4 + bodyH) or 0)

	Widgets.SetSize(tooltip, innerW + PAD * 2, innerH + PAD * 2)
end

-- ============================================================
-- Positioning helpers
-- ============================================================

-- Maps anchor strings to (tooltipPoint, ownerPoint, xSign, ySign)
local ANCHOR_MAP = {
	ANCHOR_RIGHT  = { 'LEFT',   'RIGHT',  1,  0 },
	ANCHOR_LEFT   = { 'RIGHT',  'LEFT',  -1,  0 },
	ANCHOR_TOP    = { 'BOTTOM', 'TOP',    0,  1 },
	ANCHOR_BOTTOM = { 'TOP',    'BOTTOM', 0, -1 },
}

local function PositionTooltip(owner, anchor)
	tooltip:ClearAllPoints()

	local cfgOffX = getConfig('tooltipOffsetX') or 0
	local cfgOffY = getConfig('tooltipOffsetY') or 0

	if(anchor == 'ANCHOR_CURSOR') then
		-- Follow cursor; GetCursorPosition returns screen coords, convert via UIParent scale
		local cx, cy = GetCursorPosition()
		local scale  = UIParent:GetEffectiveScale()
		tooltip:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT',
			cx / scale + GAP + cfgOffX, cy / scale + GAP + cfgOffY)
		return
	end

	local info = ANCHOR_MAP[anchor] or ANCHOR_MAP['ANCHOR_RIGHT']
	local tooltipPoint, ownerPoint, xSign, ySign = info[1], info[2], info[3], info[4]

	local xOff = xSign * GAP + cfgOffX
	local yOff = ySign * GAP + cfgOffY

	tooltip:SetPoint(tooltipPoint, owner, ownerPoint, xOff, yOff)
end

-- ============================================================
-- Public API
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

--- Show the custom tooltip attached to owner.
--- @param owner Frame The frame to anchor against
--- @param title string Tooltip title text
--- @param body? string Optional secondary body text
--- @param anchor? string Anchor direction (default from config)
function Widgets.ShowTooltip(owner, title, body, anchor)
	-- Respect global toggle
	if(getConfig('tooltipEnabled') == false) then return end

	-- Hide in combat
	if(getConfig('tooltipHideInCombat') and InCombatLockdown()) then return end

	EnsureTooltip()

	anchor = anchor or getConfig('tooltipAnchor') or 'ANCHOR_RIGHT'

	-- Set title
	tooltip.titleFS:SetText(title or '')
	tooltip.titleFS:Show()

	-- Set body (optional)
	if(body and body ~= '') then
		tooltip.bodyFS:SetText(body)
		tooltip.bodyFS:Show()
	else
		tooltip.bodyFS:SetText('')
		tooltip.bodyFS:Hide()
	end

	AutoSize()
	PositionTooltip(owner, anchor)
	tooltip:Show()
end

--- Hide the singleton tooltip and clear its text.
function Widgets.HideTooltip()
	if(not tooltip) then return end
	tooltip:Hide()
	tooltip.titleFS:SetText('')
	tooltip.bodyFS:SetText('')
	tooltip.bodyFS:Hide()
end

--- Hook OnEnter/OnLeave on a frame to auto-show/hide its tooltip.
--- Reads tooltip data from frame._tooltipTitle / frame._tooltipBody.
--- Uses HookScript so existing scripts are preserved.
--- @param frame Frame
function Widgets.AttachTooltipScripts(frame)
	frame:HookScript('OnEnter', function(self)
		if(self._tooltipTitle) then
			Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
		end
	end)

	frame:HookScript('OnLeave', function(self)
		Widgets.HideTooltip()
	end)
end
