local _, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.CrowdControl = {}

-- Forward declarations for timer functions (defined after Update)
local StartTimer
local StopTimer

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit, updateInfo)
	local element = self.FramedCrowdControl
	if(not element) then return end

	if(unit ~= self.unit) then return end

	local auraState = self.FramedAuraState
	if(auraState) then
		if(event == 'UNIT_AURA') then
			auraState:ApplyUpdateInfo(unit, updateInfo)
		else
			auraState:EnsureInitialized(unit)
		end
	end

	-- Scan for player-cast crowd control debuffs
	local foundIcon   = nil
	local foundExpiry = nil

	local ccAuras = auraState and auraState:GetHarmful('HARMFUL|CROWD_CONTROL|PLAYER') or F.AuraCache.GetUnitAuras(unit, 'HARMFUL|CROWD_CONTROL|PLAYER')

	for _, auraData in next, ccAuras do
		local spellId = auraData.spellId
		if(F.IsValueNonSecret(spellId)) then
			-- Take the first matching CC
			if(foundIcon == nil) then
				foundIcon   = auraData.icon
				foundExpiry = auraData.expirationTime
			end
		end
	end

	if(foundIcon) then
		element.icon:SetTexture(foundIcon)
		element.icon:Show()

		if(foundExpiry and foundExpiry > 0) then
			local remaining = foundExpiry - GetTime()
			if(remaining > 0) then
				element.duration:SetText(F.FormatDuration(remaining))
				element.duration:Show()
			else
				element.duration:Hide()
			end
		else
			element.duration:Hide()
		end

		element._expiry = foundExpiry
		StartTimer(element)
		element:Show()
	else
		element._expiry = nil
		StopTimer(element)
		element:Hide()
	end
end

-- ============================================================
-- Duration ticker — dedicated frame, only runs when active
-- ============================================================

local tickerFrame = CreateFrame('Frame')
tickerFrame:Hide()

local activeTimers = {}

tickerFrame:SetScript('OnUpdate', function(_, elapsed)
	local now = GetTime()
	local anyActive = false
	for element in next, activeTimers do
		if(element._expiry) then
			local remaining = element._expiry - now
			if(remaining > 0) then
				element.duration:SetText(F.FormatDuration(remaining))
				anyActive = true
			else
				element.duration:Hide()
				element._expiry = nil
				activeTimers[element] = nil
			end
		else
			activeTimers[element] = nil
		end
	end
	if(not anyActive) then
		tickerFrame:Hide()
	end
end)

StartTimer = function(element)
	activeTimers[element] = true
	tickerFrame:Show()
end

StopTimer = function(element)
	activeTimers[element] = nil
end

-- ============================================================
-- ForceUpdate
-- ============================================================

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

-- ============================================================
-- Enable / Disable
-- ============================================================

local function Enable(self, unit)
	local element = self.FramedCrowdControl
	if(not element) then return end

	element.__owner     = self
	element.ForceUpdate = ForceUpdate
	element._startTimer = StartTimer
	element._stopTimer  = StopTimer

	self:RegisterEvent('UNIT_AURA', Update)

	return true
end

local function Disable(self)
	local element = self.FramedCrowdControl
	if(not element) then return end

	element:Hide()
	self:UnregisterEvent('UNIT_AURA', Update)
	StopTimer(element)
	element._expiry = nil
end

-- ============================================================
-- Rebuild
-- ============================================================

local function Rebuild(element, config)
	if(element._stopTimer) then element._stopTimer(element) end
	if(element.icon) then element.icon:Hide() end

	local iconSize = config.iconSize
	local point    = config.anchor
	element._spells = config.spells

	if(element.icon) then
		Widgets.SetSize(element.icon, iconSize, iconSize)
	end
	if(element.__owner) then
		element:ClearAllPoints()
		element:SetPoint(point[1], element.__owner, point[3] or point[1], point[4] or 0, point[5] or 0)
	end

	element:ForceUpdate()
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedCrowdControl', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create the player-applied CC tracker widget on a unit frame.
--- Shows a spell icon and live countdown timer for Polymorph, Hex,
--- Sap, Cyclone, Banish, Imprison, and other player-cast CC spells.
--- Assigns result to self.FramedCrowdControl, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: iconSize, point
function F.Elements.CrowdControl.Setup(self, config)
	config = config or {}

	if(not self.FramedAuraState and F.AuraState) then
		self.FramedAuraState = F.AuraState.Create(self)
	end

	local iconSize = config.iconSize or 24
	local point    = config.point    or { 'CENTER', self, 'CENTER', 0, 0 }

	-- Container frame
	local container = CreateFrame('Frame', nil, self)
	container:SetFrameLevel(self:GetFrameLevel() + 15)
	Widgets.SetSize(container, iconSize, iconSize + 14)
	container:Hide()

	-- Position the container
	local p = point
	container:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0)

	-- Spell icon
	local icon = container:CreateTexture(nil, 'ARTWORK')
	Widgets.SetSize(icon, iconSize, iconSize)
	icon:SetPoint('TOP', container, 'TOP', 0, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	container.icon = icon

	-- Thin black border around icon
	local border = CreateFrame('Frame', nil, container, 'BackdropTemplate')
	border:SetAllPoints(icon)
	border:SetFrameLevel(container:GetFrameLevel() + 1)
	border:SetBackdrop({
		bgFile   = nil,
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
	})
	border:SetBackdropColor(0, 0, 0, 0)
	border:SetBackdropBorderColor(0, 0, 0, 1)

	-- Duration text below the icon
	local duration = Widgets.CreateFontString(container, C.Font.sizeSmall, C.Colors.textActive)
	duration:SetFont(F.Media.GetActiveFont(), C.Font.sizeSmall, 'OUTLINE')
	duration:SetPoint('TOP', icon, 'BOTTOM', 0, -1)
	duration:SetJustifyH('CENTER')
	container.duration = duration

	container.Rebuild = Rebuild
	self.FramedCrowdControl = container
end
