local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.ReadyCheck = {}

-- ============================================================
-- ReadyCheck Element Setup
-- Uses AF's Fluent textures for ready/not-ready/waiting states.
-- ============================================================

local READY_TEXTURE   = F.Media.GetIcon('Fluent_Color_Yes')
local NOTREADY_TEXTURE = F.Media.GetIcon('Fluent_Color_No')
local WAITING_TEXTURE  = F.Media.GetIcon('Fluent_Alert')

--- Override for oUF's ReadyCheckIndicator update.
--- Uses our custom Fluent textures instead of the Blizzard atlases.
--- @param self Frame  The oUF unit frame
local function Override(self, event)
	local element = self.ReadyCheckIndicator
	local unit = self.unit

	if(element.PreUpdate) then
		element:PreUpdate()
	end

	local status = GetReadyCheckStatus(unit)
	if(UnitExists(unit) and status) then
		if(status == 'ready') then
			element:SetTexture(READY_TEXTURE)
		elseif(status == 'notready') then
			element:SetTexture(NOTREADY_TEXTURE)
		else
			element:SetTexture(WAITING_TEXTURE)
		end
		element:SetTexCoord(0, 1, 0, 1)

		element.status = status
		element:Show()
	elseif(event ~= 'READY_CHECK_FINISHED') then
		element.status = nil
		element:Hide()
	end

	if(event == 'READY_CHECK_FINISHED') then
		if(element.status == 'waiting') then
			element:SetTexture(NOTREADY_TEXTURE)
			element:SetTexCoord(0, 1, 0, 1)
		end

		-- Play the fade-out animation created by oUF's Enable
		if(element.Animation) then
			element.Animation:Play()
		end
	end

	if(element.PostUpdate) then
		return element:PostUpdate(status)
	end
end

--- Configure oUF's built-in ReadyCheckIndicator element on a unit frame.
--- Uses AF's Fluent icons for a higher quality ready check display.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.ReadyCheck.Setup(self, config)

	-- --------------------------------------------------------
	-- Icon texture
	-- --------------------------------------------------------

	local icon = (self._iconOverlay or self):CreateTexture(nil, 'OVERLAY')
	Widgets.SetSize(icon, config.size, config.size)

	local p = config.point
	Widgets.SetPoint(icon, p[1], p[2], p[3], p[4], p[5])

	-- Use Override to apply our custom textures
	icon.Override = Override

	-- --------------------------------------------------------
	-- Assign to oUF — activates the ReadyCheckIndicator element
	-- --------------------------------------------------------

	self.ReadyCheckIndicator = icon
end
