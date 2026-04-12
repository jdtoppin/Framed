local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local B = F.FrameSettingsBuilder

F.SettingsCards = F.SettingsCards or {}

-- ============================================================
-- Sort mode dropdown labels per unit type
-- ============================================================

local MODE_ITEMS = {
	raid = {
		{ text = 'By group', value = 'group' },
		{ text = 'By role',  value = 'role'  },
	},
	party = {
		{ text = 'Default',  value = 'index' },
		{ text = 'By role',  value = 'role'  },
	},
}

-- ============================================================
-- Role-order presets — text label + ordered role tokens
-- ============================================================

local ROLE_ORDER_PRESETS = {
	{ text = 'Tank, Healer, DPS', value = 'TANK,HEALER,DAMAGER',   roles = { 'TANK',    'HEALER',  'DAMAGER' } },
	{ text = 'Tank, DPS, Healer', value = 'TANK,DAMAGER,HEALER',   roles = { 'TANK',    'DAMAGER', 'HEALER'  } },
	{ text = 'Healer, Tank, DPS', value = 'HEALER,TANK,DAMAGER',   roles = { 'HEALER',  'TANK',    'DAMAGER' } },
	{ text = 'Healer, DPS, Tank', value = 'HEALER,DAMAGER,TANK',   roles = { 'HEALER',  'DAMAGER', 'TANK'    } },
	{ text = 'DPS, Tank, Healer', value = 'DAMAGER,TANK,HEALER',   roles = { 'DAMAGER', 'TANK',    'HEALER'  } },
	{ text = 'DPS, Healer, Tank', value = 'DAMAGER,HEALER,TANK',   roles = { 'DAMAGER', 'HEALER',  'TANK'    } },
}

-- ============================================================
-- Build dropdown items with inline role-icon previews
-- ============================================================

local function buildRoleOrderItems()
	local style = F.Config:Get('general.roleIconStyle') or 2
	local texturePath = F.Elements.RoleIcon.GetTexturePath(style)
	local texCoords   = F.Elements.RoleIcon.TEXCOORDS

	local items = {}
	for i, preset in next, ROLE_ORDER_PRESETS do
		local icons = {}
		for j, role in next, preset.roles do
			icons[j] = {
				texture  = texturePath,
				texCoord = texCoords[role],
			}
		end
		items[i] = {
			text  = preset.text,
			value = preset.value,
			icons = icons,
		}
	end
	return items
end

-- ============================================================
-- Card builder
-- ============================================================

function F.SettingsCards.Sorting(parent, width, unitType, getConfig, setConfig)
	local card, inner, cardY = Widgets.StartCard(parent, width, 0)
	local widgetW = width - Widgets.CARD_PADDING * 2

	-- Sort mode dropdown
	cardY = B.PlaceHeading(inner, 'Sort Mode', 4, cardY)

	local modeDropdown = Widgets.CreateDropdown(inner, widgetW)
	modeDropdown:SetItems(MODE_ITEMS[unitType] or MODE_ITEMS.raid)
	modeDropdown:SetValue(getConfig('sortMode'))
	cardY = B.PlaceWidget(modeDropdown, inner, cardY, B.DROPDOWN_H)

	-- Role order dropdown (icon row variant)
	cardY = B.PlaceHeading(inner, 'Role Order', 4, cardY)

	local orderDropdown = Widgets.CreateIconRowDropdown(inner, widgetW, 3)
	orderDropdown:SetItems(buildRoleOrderItems())
	orderDropdown:SetValue(getConfig('roleOrder'))
	cardY = B.PlaceWidget(orderDropdown, inner, cardY, B.DROPDOWN_H)

	-- Enable / disable the role-order dropdown based on mode.
	local function refreshOrderEnabled()
		orderDropdown:SetEnabled(getConfig('sortMode') == 'role')
	end
	refreshOrderEnabled()

	modeDropdown:SetOnSelect(function(value)
		setConfig('sortMode', value)
		refreshOrderEnabled()
	end)
	orderDropdown:SetOnSelect(function(value)
		setConfig('roleOrder', value)
	end)

	Widgets.EndCard(card, inner, cardY)
	return card
end
