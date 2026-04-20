local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.RoleIcon = {}

-- ============================================================
-- RoleIcon Element Setup
-- Uses AF's RoleIcons texture atlas strips. Each TGA is a
-- 4-quadrant horizontal strip: Tank | Healer | DPS | None.
-- The user selects a style (2-7) via settings.
-- ============================================================

local ROLE_TEXCOORDS = {
	TANK    = { 0, 0.25, 0, 1 },
	HEALER  = { 0.25, 0.5, 0, 1 },
	DAMAGER = { 0.5, 0.75, 0, 1 },
	NONE    = { 0.75, 1, 0, 1 },
}

-- Per-style overrides for TGAs that don't follow the canonical
-- Tank | Healer | DPS | None quadrant order.
local STYLE_TEXCOORD_OVERRIDES = {
	[3] = {
		TANK    = { 0, 0.25, 0, 1 },
		DAMAGER = { 0.25, 0.5, 0, 1 },
		HEALER  = { 0.5, 0.75, 0, 1 },
		NONE    = { 0.75, 1, 0, 1 },
	},
}

local function getTexCoord(style, role)
	local override = STYLE_TEXCOORD_OVERRIDES[style]
	if(override and override[role]) then
		return override[role]
	end
	return ROLE_TEXCOORDS[role]
end

local ICON_PATH = [[Interface\AddOns\Framed\Media\Icons\]]

--- Build the texture path for a given style number.
--- @param style number 2-7
--- @return string
local function getRoleTexturePath(style)
	return ICON_PATH .. 'RoleIcons' .. style
end

--- Get the configured role icon style, defaulting to 2.
--- @return number
local function getConfiguredStyle()
	if(F.Config) then
		return F.Config:Get('general.roleIconStyle')
	end
	return 2
end

--- Resolve the role to display for a unit.
--- UnitGroupRolesAssigned returns the LFG-assigned role, which is the role
--- the player queued as — it's sticky in follower dungeons and certain
--- manually-formed groups and does not follow spec swaps. For the player
--- unit specifically we can do better: GetSpecializationRole() reflects
--- the current spec and updates synchronously with PLAYER_SPECIALIZATION_CHANGED.
--- Other units have no queryable spec, so we fall back to the LFG role.
local function resolveRole(unit)
	if(unit == 'player') then
		local specIndex = GetSpecialization()
		local specRole = specIndex and GetSpecializationRole(specIndex)
		if(specRole == 'TANK' or specRole == 'HEALER' or specRole == 'DAMAGER') then
			return specRole
		end
	end
	return UnitGroupRolesAssigned(unit)
end

--- Override for oUF's GroupRoleIndicator update.
--- Sets the texture and tex coords based on the unit's assigned role.
--- @param self Frame  The oUF unit frame
local function Override(self, event)
	local element = self.GroupRoleIndicator

	if(element.PreUpdate) then
		element:PreUpdate()
	end

	local role = resolveRole(self.unit)
	if(role == 'TANK' or role == 'HEALER' or role == 'DAMAGER') then
		local style = getConfiguredStyle()
		element:SetTexture(getRoleTexturePath(style))
		local tc = getTexCoord(style, role)
		element:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
		element:Show()
	else
		element:Hide()
	end

	if(element.PostUpdate) then
		return element:PostUpdate(role)
	end
end

--- Configure oUF's built-in GroupRoleIndicator element on a unit frame.
--- Uses AF's role icon texture strips with configurable style.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.RoleIcon.Setup(self, config)

	-- --------------------------------------------------------
	-- Icon texture
	-- --------------------------------------------------------

	local icon = (self._iconOverlay or self):CreateTexture(nil, 'OVERLAY')
	Widgets.SetSize(icon, config.size, config.size)

	local p = config.point
	Widgets.SetPoint(icon, p[1], p[2], p[3], p[4], p[5])

	-- Set initial texture so oUF doesn't apply default atlas
	local style = getConfiguredStyle()
	icon:SetTexture(getRoleTexturePath(style))

	-- Use Override to apply our texture + tex coords
	icon.Override = Override

	-- --------------------------------------------------------
	-- Assign to oUF — activates the GroupRoleIndicator element
	-- --------------------------------------------------------

	self.GroupRoleIndicator = icon
end

-- ============================================================
-- Expose for settings UI
-- ============================================================

--- Available role icon styles (2-7).
F.Elements.RoleIcon.STYLES = { 2, 3, 4, 5, 6, 7 }

--- Get the texture path for a given style (for preview).
--- @param style number
--- @return string
F.Elements.RoleIcon.GetTexturePath = getRoleTexturePath

--- Tex coords for each role (for preview).
F.Elements.RoleIcon.TEXCOORDS = ROLE_TEXCOORDS

--- Get the tex coord for a specific style+role combination,
--- honoring any per-style overrides.
--- @param style number
--- @param role string  'TANK' | 'HEALER' | 'DAMAGER' | 'NONE'
--- @return table
F.Elements.RoleIcon.GetTexCoord = getTexCoord

-- ============================================================
-- Live update on style change
-- Override() re-reads the config on every update, so we just
-- need to kick oUF into re-running it on every frame that owns
-- a GroupRoleIndicator.
-- ============================================================

local function forceUpdateAll()
	local oUF = F.oUF
	if(not oUF or not oUF.objects) then return end
	for _, frame in next, oUF.objects do
		local element = frame.GroupRoleIndicator
		if(element and element.ForceUpdate) then
			element:ForceUpdate()
		end
	end
end

F.EventBus:Register('CONFIG_CHANGED', function(path)
	if(path ~= 'general.roleIconStyle') then return end
	forceUpdateAll()
end, 'RoleIcon.StyleLiveUpdate')

-- ============================================================
-- Live update on spec change
-- oUF's GroupRoleIndicator only subscribes to PLAYER_ROLES_ASSIGNED
-- (LFG system) and GROUP_ROSTER_UPDATE (join/leave), neither of which
-- fires when a player respecs mid-dungeon. UnitGroupRolesAssigned
-- returns the new role immediately, so we just force a re-query.
-- ============================================================

local specWatcher = CreateFrame('Frame')
specWatcher:RegisterEvent('PLAYER_SPECIALIZATION_CHANGED')
specWatcher:SetScript('OnEvent', forceUpdateAll)
