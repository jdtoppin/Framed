local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.StatusText = {}

-- ============================================================
-- Status color constants
-- ============================================================

local COLOR_DEAD     = { 0.8, 0.1, 0.1 }
local COLOR_GHOST    = { 0.6, 0.6, 0.6 }
local COLOR_OFFLINE  = { 0.5, 0.5, 0.5 }
local COLOR_AFK      = { 1,   0.8, 0   }
local COLOR_ACCEPTED = { 0.2, 0.8, 0.2 }
local COLOR_DECLINED = { 0.8, 0.1, 0.1 }

-- Summon status enum values
local SUMMON_NONE     = 0
local SUMMON_PENDING  = 1
local SUMMON_ACCEPTED = 2
local SUMMON_DECLINED = 3

-- ============================================================
-- Update
-- ============================================================

local function Update(self, event, unit)
	local element = self.FramedStatusText
	if(not element) then return end

	if(unit ~= self.unit) then return end

	local text, color

	-- Unit status APIs return secret booleans in combat; guard with
	-- IsValueNonSecret so we degrade gracefully (hide text) instead of erroring.
	local dead      = UnitIsDeadOrGhost(unit)
	local ghost     = UnitIsGhost(unit)
	local connected = UnitIsConnected(unit)
	local afk       = UnitIsAFK(unit)

	if(F.IsValueNonSecret(dead) and dead) then
		if(F.IsValueNonSecret(ghost) and ghost) then
			text  = 'GHOST'
			color = COLOR_GHOST
		else
			text  = 'DEAD'
			color = COLOR_DEAD
		end
	elseif(F.IsValueNonSecret(connected) and not connected) then
		text  = 'OFFLINE'
		color = COLOR_OFFLINE
	elseif(F.IsValueNonSecret(afk) and afk) then
		text  = 'AFK'
		color = COLOR_AFK
	elseif(C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus) then
		local status = C_IncomingSummon.IncomingSummonStatus(unit)
		if(F.IsValueNonSecret(status)) then
			if(status == SUMMON_PENDING) then
				text  = 'SUMMON'
				color = C.Colors.accent
			elseif(status == SUMMON_ACCEPTED) then
				text  = 'ACCEPTED'
				color = COLOR_ACCEPTED
			elseif(status == SUMMON_DECLINED) then
				text  = 'DECLINED'
				color = COLOR_DECLINED
			end
		end
	end

	if(text) then
		element:SetText(text)
		element:SetTextColor(color[1], color[2], color[3], 1)
		element:Show()
	else
		element:Hide()
	end
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
	local element = self.FramedStatusText
	if(not element) then return end

	element.__owner   = self
	element.ForceUpdate = ForceUpdate

	self:RegisterEvent('UNIT_HEALTH',            Update)
	self:RegisterEvent('UNIT_CONNECTION',         Update)
	self:RegisterEvent('PLAYER_FLAGS_CHANGED',    Update)
	self:RegisterEvent('INCOMING_SUMMON_CHANGED', Update, true)

	return true
end

local function Disable(self)
	local element = self.FramedStatusText
	if(not element) then return end

	element:Hide()

	self:UnregisterEvent('UNIT_HEALTH',            Update)
	self:UnregisterEvent('UNIT_CONNECTION',         Update)
	self:UnregisterEvent('PLAYER_FLAGS_CHANGED',    Update)
	self:UnregisterEvent('INCOMING_SUMMON_CHANGED', Update)
end

-- ============================================================
-- Register with oUF
-- ============================================================

oUF:AddElement('FramedStatusText', Update, Enable, Disable)

-- ============================================================
-- Setup
-- ============================================================

--- Create the status text overlay FontString on a unit frame.
--- Assigns result to self.FramedStatusText, activating the element.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config: fontSize, outline, shadow, anchor, anchorX, anchorY
function F.Elements.StatusText.Setup(self, config)
	local size    = config.fontSize
	local outline = config.outline
	local anchor  = config.anchor
	local ax      = config.anchorX
	local ay      = config.anchorY

	-- FontString sits in the OVERLAY layer so it renders above bars/textures
	local fs = self.FramedStatusText
	if(not fs) then
		fs = Widgets.CreateFontString(self, size, C.Colors.textActive)
	end
	fs:SetFont(F.Media.GetActiveFont(), size, outline ~= '' and outline or nil)
	if(config.shadow) then
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 0.8)
	else
		fs:SetShadowOffset(0, 0)
	end
	fs:ClearAllPoints()
	fs:SetPoint(anchor, self, anchor, ax, ay)
	fs:SetJustifyH('CENTER')
	fs:Hide()

	-- Store config for live updates
	fs._config = config

	self.FramedStatusText = fs
end
