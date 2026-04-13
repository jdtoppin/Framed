local addonName, Framed = ...
-- luacheck: ignore 211
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

F.OverviewIllustrations = {}
local M = F.OverviewIllustrations

-- ============================================================
-- Illustration builders
-- Each accepts (host, w, h) and returns a frame parented to
-- `host`. Failures (nil deps) return nil — caller hides the
-- left column.
-- ============================================================

function M.BuildWelcome(host, w, _h)
	if(not F.Preview or not F.Preview.GetFakeUnits or not F.Preview.CreatePreviewFrame) then
		return nil
	end

	local container = CreateFrame('Frame', nil, host)

	local units = F.Preview.GetFakeUnits(3)
	if(not units or #units == 0) then return nil end

	local unitW = w - 8
	local unitH = 32
	local gap = 4
	for i, unit in next, units do
		local pf = F.Preview.CreatePreviewFrame(container, 'party', unitW, unitH)
		pf:ClearAllPoints()
		Widgets.SetPoint(pf, 'TOP', container, 'TOP', 0, -((i - 1) * (unitH + gap)))
		F.Preview.ApplyUnitToFrame(pf, unit)
		pf:Show()
	end

	return container
end

function M.BuildAtlas(host, atlasName, iconSize)
	local container = CreateFrame('Frame', nil, host)

	local tex = container:CreateTexture(nil, 'ARTWORK')
	tex:SetSize(iconSize or 96, iconSize or 96)
	tex:SetPoint('CENTER', container, 'CENTER', 0, 0)

	-- BUG: SetAtlas can raise on missing/renamed atlases in some client
	-- builds; no query-before-set API exists. Guard the call so a bad
	-- atlas name degrades to an empty illustration instead of a hard error.
	local ok = pcall(tex.SetAtlas, tex, atlasName, false)
	if(not ok) then
		container:Hide()
		return nil
	end
	return container
end

function M.BuildCards(host, w, _h)
	if(not F.AppearanceCards or not F.AppearanceCards.Tooltips) then
		return M.BuildAtlas(host, 'Garr_BuildingIcon-Barracks', 96)
	end

	local container = CreateFrame('Frame', nil, host)

	local cardConfig = {
		tooltipEnabled = true,
		tooltipHideInCombat = false,
		tooltipMode = 'frame',
		tooltipAnchor = 'RIGHT',
		tooltipOffsetX = 0,
		tooltipOffsetY = 0,
	}
	local function getConfig(key) return cardConfig[key] end
	local function setConfig(key, value) cardConfig[key] = value end
	local function fireChange() end
	local function onResize() end

	local card = F.AppearanceCards.Tooltips(container, w, getConfig, setConfig, fireChange, onResize)
	if(not card) then
		container:Hide()
		return nil
	end

	card:ClearAllPoints()
	card:SetPoint('TOP', container, 'TOP', 0, 0)
	return container
end

function M.BuildIndicators(host, _w, _h)
	local container = CreateFrame('Frame', nil, host)

	local iconSize = 48
	local gap = C.Spacing.normal

	local leftBg = CreateFrame('Frame', nil, container, 'BackdropTemplate')
	local dispelColor = C.Colors.dispel.Magic
	Widgets.ApplyBackdrop(leftBg, C.Colors.widget, { dispelColor[1], dispelColor[2], dispelColor[3], 1 })
	Widgets.SetSize(leftBg, iconSize, iconSize)
	leftBg:ClearAllPoints()
	Widgets.SetPoint(leftBg, 'CENTER', container, 'CENTER', -(iconSize + gap) / 2, 0)
	local leftIcon = leftBg:CreateTexture(nil, 'ARTWORK')
	leftIcon:SetTexture(F.Media.GetIcon('Fluent_Color_Yes'))
	leftIcon:SetPoint('CENTER', leftBg, 'CENTER', 0, 0)
	leftIcon:SetSize(iconSize - 4, iconSize - 4)

	local rightBg = CreateFrame('Frame', nil, container, 'BackdropTemplate')
	Widgets.ApplyBackdrop(rightBg, C.Colors.widget, C.Colors.accent)
	Widgets.SetSize(rightBg, iconSize, iconSize)
	rightBg:ClearAllPoints()
	Widgets.SetPoint(rightBg, 'CENTER', container, 'CENTER', (iconSize + gap) / 2, 0)
	local rightIcon = rightBg:CreateTexture(nil, 'ARTWORK')
	rightIcon:SetTexture(F.Media.GetIcon('Star'))
	rightIcon:SetPoint('CENTER', rightBg, 'CENTER', 0, 0)
	rightIcon:SetSize(iconSize - 4, iconSize - 4)

	return container
end

function M.BuildDefensives(host, _w, _h)
	local container = CreateFrame('Frame', nil, host)

	local iconSize = 64
	local bg = CreateFrame('Frame', nil, container, 'BackdropTemplate')
	Widgets.ApplyBackdrop(bg, C.Colors.widget, C.Colors.accent)
	Widgets.SetSize(bg, iconSize, iconSize)
	bg:ClearAllPoints()
	Widgets.SetPoint(bg, 'CENTER', container, 'CENTER', 0, 0)

	local icon = bg:CreateTexture(nil, 'ARTWORK')
	icon:SetTexture(F.Media.GetIcon('Mark'))
	icon:SetPoint('CENTER', bg, 'CENTER', 0, 0)
	icon:SetSize(iconSize - 6, iconSize - 6)

	local glow = bg:CreateTexture(nil, 'OVERLAY')
	glow:SetTexture(F.Media.GetIcon('Circle'))
	glow:SetPoint('CENTER', bg, 'CENTER', 0, 0)
	glow:SetSize(iconSize + 12, iconSize + 12)
	local ac = C.Colors.accent
	glow:SetVertexColor(ac[1], ac[2], ac[3], 0.5)

	return container
end
