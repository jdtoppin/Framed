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

-- Build a small overlay with a per-role icon (and optionally a party leader
-- badge) on top of a preview frame. PreviewFrame's own BuildStatusIcons uses
-- a hardcoded healer-quadrant placeholder for role, so we overlay our own
-- role-aware icons here instead.
local function addWelcomeBadges(pf, unit, isLeader)
	local overlay = CreateFrame('Frame', nil, pf)
	overlay:SetAllPoints(pf)
	if(pf._healthBar) then
		overlay:SetFrameLevel(pf._healthBar:GetFrameLevel() + 5)
	end

	local roleIcon
	if(F.Elements and F.Elements.RoleIcon and unit.role) then
		local tc = F.Elements.RoleIcon.TEXCOORDS[unit.role]
		if(tc) then
			local style = (F.Config and F.Config:Get('general.roleIconStyle')) or 2
			roleIcon = overlay:CreateTexture(nil, 'OVERLAY')
			roleIcon:SetTexture(F.Elements.RoleIcon.GetTexturePath(style))
			roleIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
			roleIcon:SetSize(12, 12)
			roleIcon:SetPoint('TOPLEFT', pf, 'TOPLEFT', 2, -2)
		end
	end

	if(isLeader) then
		local leader = overlay:CreateTexture(nil, 'OVERLAY')
		leader:SetAtlas('UI-HUD-UnitFrame-Player-Group-LeaderIcon')
		leader:SetSize(12, 12)
		if(roleIcon) then
			leader:SetPoint('LEFT', roleIcon, 'RIGHT', 2, 0)
		else
			leader:SetPoint('TOPLEFT', pf, 'TOPLEFT', 2, -2)
		end
	end
end

-- Find a party unit config to render the welcome sample with. Prefer the
-- active/editing preset so the illustration reflects the user's current
-- styling; fall back to any preset that has party configured.
local function findPartyConfig()
	if(not F.Config or not F.Config.Get) then return nil end

	local presetName = F.Settings and F.Settings.GetEditingPreset and F.Settings.GetEditingPreset()
	if(presetName) then
		local cfg = F.Config:Get('presets.' .. presetName .. '.unitConfigs.party')
		if(cfg) then return cfg end
	end

	local presets = F.Config:Get('presets')
	if(presets) then
		for _, p in next, presets do
			if(p.unitConfigs and p.unitConfigs.party) then
				return p.unitConfigs.party
			end
		end
	end
	return nil
end

function M.BuildWelcome(host, w, h)
	if(not F.PreviewFrame or not F.PreviewFrame.Create) then return nil end
	if(not F.Preview or not F.Preview.GetFakeUnits) then return nil end

	local partyConfig = findPartyConfig()
	if(not partyConfig) then return nil end

	-- Deep-copy so we can sanitize without mutating the user's real config.
	-- Strip status icons because the preview builder draws them as always-on
	-- placeholders, which looks odd when the same "summon" / "party leader"
	-- icon repeats across all three welcome rows.
	partyConfig = F.DeepCopy(partyConfig)
	partyConfig.statusIcons = nil

	-- Pick one fake unit per role so the welcome shows a representative
	-- Tank / Healer / DPS trio, independent of FAKE_UNITS array ordering.
	local pool = F.Preview.GetFakeUnits(20)
	if(not pool or #pool == 0) then return nil end
	local byRole = {}
	for _, u in next, pool do
		if(not byRole[u.role]) then byRole[u.role] = u end
	end
	local units = {}
	for _, role in next, { 'TANK', 'HEALER', 'DAMAGER' } do
		if(byRole[role]) then
			units[#units + 1] = byRole[role]
		end
	end
	if(#units == 0) then return nil end

	local count = #units
	local frameW = partyConfig.width
	local frameH = partyConfig.height
	local gap = C.Spacing.tight

	local stackW = frameW
	local stackH = count * frameH + (count - 1) * gap

	-- Uniform downscale so the whole stack fits inside the illustration host.
	-- Cap at 1 so small frames stay at native size rather than upscaling.
	local scale = math.min(w / stackW, h / stackH, 1)

	local container = CreateFrame('Frame', nil, host)
	container:SetScale(scale)

	for i, unit in next, units do
		-- nil realFrame: no live reference, so PreviewFrame.Create pins its
		-- internal scale to UIParent. We override with SetScale(1) below so
		-- the preview inherits the container's downscale instead of defeating
		-- it. nil auraConfig keeps the welcome illustration uncluttered
		-- regardless of the user's party aura setup.
		local pf = F.PreviewFrame.Create(container, partyConfig, unit, nil, nil)
		pf:SetScale(1)
		pf:ClearAllPoints()
		Widgets.SetPoint(pf, 'TOP', container, 'TOP', 0, -((i - 1) * (frameH + gap)))
		-- Tank (first in TANK/HEALER/DAMAGER order) gets the leader badge.
		addWelcomeBadges(pf, unit, i == 1)
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

-- Build a single miniature "layout card" — a backdropped frame with a
-- drop-shadow frame behind it at (card level - 1). Using a dedicated frame
-- rather than a container-level BACKGROUND texture is necessary: container
-- textures draw below every child frame, so a later card's shadow would
-- end up under the earlier card's tiles. Per-frame shadows slot neatly into
-- the frame-level stack between each pair of cards.
local function buildLayoutCard(container, x, y, cw, ch, frameLevel, alpha, isFront)
	local baseLevel = container:GetFrameLevel() + frameLevel

	local shadow = CreateFrame('Frame', nil, container)
	shadow:SetSize(cw, ch)
	shadow:ClearAllPoints()
	Widgets.SetPoint(shadow, 'TOPLEFT', container, 'TOPLEFT', x + 3, y - 3)
	shadow:SetFrameLevel(math.max(0, baseLevel - 1))
	local shadowTex = shadow:CreateTexture(nil, 'ARTWORK')
	shadowTex:SetColorTexture(0, 0, 0, 0.55)
	shadowTex:SetAllPoints(shadow)

	local card = CreateFrame('Frame', nil, container, 'BackdropTemplate')
	-- Front card keeps the accent border to draw the eye; back cards use the
	-- muted default border so the composition has a clear focal point.
	local borderColor = isFront and C.Colors.accent or C.Colors.border
	Widgets.ApplyBackdrop(card, C.Colors.widget, borderColor)
	Widgets.SetSize(card, cw, ch)
	card:ClearAllPoints()
	Widgets.SetPoint(card, 'TOPLEFT', container, 'TOPLEFT', x, y)
	card:SetFrameLevel(baseLevel)
	card:SetAlpha(alpha)
	return card
end

-- Fill a card with a grid of small tiles. Used for the raid back-card:
-- 5x4 muted rectangles read as "lots of frames" at a glance.
local function fillRaidGrid(card, cols, rows, pad, gap)
	local cw, ch = card:GetSize()
	local tileW = (cw - pad * 2 - gap * (cols - 1)) / cols
	local tileH = (ch - pad * 2 - gap * (rows - 1)) / rows
	local ac = C.Colors.accent
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local tile = card:CreateTexture(nil, 'ARTWORK')
			tile:SetColorTexture(0.25, 0.25, 0.25, 1)
			tile:SetSize(tileW, tileH)
			tile:SetPoint('TOPLEFT', card, 'TOPLEFT', pad + c * (tileW + gap), -(pad + r * (tileH + gap)))

			-- Thin accent stripe along the left edge of each tile — reads as
			-- a health bar without needing secondary elements.
			local bar = card:CreateTexture(nil, 'OVERLAY')
			bar:SetColorTexture(ac[1] * 0.6, ac[2] * 0.6, ac[3] * 0.6, 0.9)
			bar:SetSize(math.max(1, tileW * 0.15), tileH)
			bar:SetPoint('TOPLEFT', tile, 'TOPLEFT', 0, 0)
		end
	end
end

-- Fill a card with a vertical stack of rows. Used for the party middle-card:
-- 5 stacked rectangles with accent health bar stripes.
local function fillPartyColumn(card, rows, pad, gap)
	local cw, ch = card:GetSize()
	local rowW = cw - pad * 2
	local rowH = (ch - pad * 2 - gap * (rows - 1)) / rows
	local ac = C.Colors.accent
	for r = 0, rows - 1 do
		local row = card:CreateTexture(nil, 'ARTWORK')
		row:SetColorTexture(0.3, 0.3, 0.3, 1)
		row:SetSize(rowW, rowH)
		row:SetPoint('TOPLEFT', card, 'TOPLEFT', pad, -(pad + r * (rowH + gap)))

		local bar = card:CreateTexture(nil, 'OVERLAY')
		-- Vary fill width per row so it looks like live health values.
		local fill = 0.45 + ((r * 0.17) % 0.55)
		bar:SetColorTexture(ac[1] * 0.8, ac[2] * 0.8, ac[3] * 0.8, 1)
		bar:SetSize(rowW * fill, rowH - 2)
		bar:SetPoint('TOPLEFT', row, 'TOPLEFT', 0, -1)
	end
end

-- Fill a card with a single unit frame: name line + prominent health bar.
local function fillSoloFrame(card, pad)
	local cw, ch = card:GetSize()
	local ac = C.Colors.accent

	local nameLine = card:CreateTexture(nil, 'ARTWORK')
	nameLine:SetColorTexture(0.6, 0.6, 0.6, 0.9)
	nameLine:SetSize((cw - pad * 2) * 0.55, 3)
	nameLine:SetPoint('TOPLEFT', card, 'TOPLEFT', pad, -pad)

	local healthBg = card:CreateTexture(nil, 'ARTWORK')
	healthBg:SetColorTexture(0.2, 0.2, 0.2, 1)
	healthBg:SetSize(cw - pad * 2, ch - pad * 2 - 6)
	healthBg:SetPoint('BOTTOMLEFT', card, 'BOTTOMLEFT', pad, pad)

	local health = card:CreateTexture(nil, 'OVERLAY')
	health:SetColorTexture(ac[1], ac[2], ac[3], 1)
	health:SetSize((cw - pad * 2) * 0.72, ch - pad * 2 - 8)
	health:SetPoint('BOTTOMLEFT', healthBg, 'BOTTOMLEFT', 1, 1)
end

function M.BuildLayouts(host, w, h)
	local container = CreateFrame('Frame', nil, host)
	container:SetSize(w, h)

	-- Three cards fanned across the 180x220 host. Positions chosen so each
	-- card overlaps the next along a diagonal (top-left → bottom-right), with
	-- frame levels forcing the intended stacking order (raid back, solo front).
	local raid  = buildLayoutCard(container,   6,  -14, 108, 76,  0, 0.75, false)
	local party = buildLayoutCard(container,  44,  -58,  50, 112, 5, 0.92, false)
	local solo  = buildLayoutCard(container,  72, -148,  86, 36, 10, 1.00, true)

	fillRaidGrid(raid, 5, 4, 4, 2)
	fillPartyColumn(party, 5, 4, 2)
	fillSoloFrame(solo, 4)

	return container
end

function M.BuildEditMode(host, w, h)
	local container = CreateFrame('Frame', nil, host)
	container:SetSize(w, h)

	-- Ghost (original) frame and active (dragged-to) frame. The ghost is
	-- low-alpha with the muted border to read as "the frame was here"; the
	-- active copy sits offset down-right with the accent border and full
	-- opacity to read as "dragged to here". A three-dot trail between them
	-- supplies the directional motion cue.
	local ghostW, ghostH = 94, 38
	local ghost  = buildLayoutCard(container, 14,  -32, ghostW, ghostH, 0, 0.32, false)
	local active = buildLayoutCard(container, 60, -132, ghostW, ghostH, 5, 1.00, true)

	fillSoloFrame(ghost, 4)
	fillSoloFrame(active, 4)

	-- Dot trail between the two cards along a straight diagonal. Positions
	-- precomputed from card centers rather than animated; we just need the
	-- eye to read left-top → right-bottom motion.
	local ac = C.Colors.accent
	local dots = { { 78, -86, 0.35 }, { 88, -102, 0.55 }, { 98, -118, 0.8 } }
	for _, d in next, dots do
		local dot = container:CreateTexture(nil, 'OVERLAY')
		dot:SetColorTexture(ac[1], ac[2], ac[3], d[3])
		dot:SetSize(5, 5)
		dot:SetPoint('TOPLEFT', container, 'TOPLEFT', d[1], d[2])
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
	if(not F.PreviewIndicators) then return nil end

	local container = CreateFrame('Frame', nil, host)
	local PI = F.PreviewIndicators

	local iconSize = 56
	local gap = C.Spacing.normal

	-- Reuse the same preview builders the settings panels use, so the animation
	-- and styling match what appears on real frames — no hand-rolled variants.
	-- Looping animations self-terminate via IsShown() checks, so when the
	-- overview closes and reparents the container to the trash frame, the
	-- animation halts with no explicit cleanup.

	-- Buff: vertical depletion bar (topToBottom fill matches Buffs element default).
	local buffIcons = PI.GetFakeIcons('buffs')
	local buff = PI.CreateIcon(container, buffIcons[1], iconSize, iconSize,
		{ fillDirection = 'topToBottom' }, true)
	buff:ClearAllPoints()
	Widgets.SetPoint(buff, 'CENTER', container, 'CENTER', -(iconSize + gap) / 2, 0)

	-- Debuff: pure red border matching Elements/Auras/Debuffs.lua's default
	-- harmful color (SetBorderColor(1, 0, 0, 1)) — used when a debuff has no
	-- specific dispel type assigned.
	local debuffIcons = PI.GetFakeIcons('debuffs')
	local debuff = PI.CreateBorderIcon(container, debuffIcons[1], iconSize, 3, nil,
		{ showStacks = false, showDuration = false }, true, { 1, 0, 0 })
	debuff:ClearAllPoints()
	Widgets.SetPoint(debuff, 'CENTER', container, 'CENTER', (iconSize + gap) / 2, 0)

	return container
end

function M.BuildDefensives(host, _w, _h)
	if(not F.PreviewIndicators) then return nil end

	local container = CreateFrame('Frame', nil, host)
	local PI = F.PreviewIndicators

	local iconSize = 56
	local gap = C.Spacing.normal

	-- Two border icons demonstrating the player-vs-other distinction that
	-- Defensives and Externals make. Colors match Presets/AuraDefaults.lua:
	-- playerColor = { 0, 0.8, 0 } (green), otherColor = { 1, 0.85, 0 } (yellow).
	-- Left: defensive cast by the player on themselves (green).
	local defIcons = PI.GetFakeIcons('defensives')
	local own = PI.CreateBorderIcon(container, defIcons[1], iconSize, 3, nil,
		{ showStacks = false, showDuration = false }, true, { 0, 0.8, 0 })
	own:ClearAllPoints()
	Widgets.SetPoint(own, 'CENTER', container, 'CENTER', -(iconSize + gap) / 2, 0)

	-- Right: external cast by another player on you (yellow).
	local extIcons = PI.GetFakeIcons('externals')
	local other = PI.CreateBorderIcon(container, extIcons[1], iconSize, 3, nil,
		{ showStacks = false, showDuration = false }, true, { 1, 0.85, 0 })
	other:ClearAllPoints()
	Widgets.SetPoint(other, 'CENTER', container, 'CENTER', (iconSize + gap) / 2, 0)

	return container
end
