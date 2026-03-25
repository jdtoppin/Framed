local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

F.Preview = {}
local Preview = F.Preview

-- ============================================================
-- Fake Unit Data
-- Used exclusively by the settings preview — never live data.
-- ============================================================

local FAKE_UNITS = {
	{ name = 'Tankadin',   class = 'PALADIN', role = 'TANK',    healthPct = 0.85, powerPct = 0.7  },
	{ name = 'Healbot',    class = 'PRIEST',  role = 'HEALER',  healthPct = 0.92, powerPct = 0.95 },
	{ name = 'Stabsworth', class = 'ROGUE',   role = 'DAMAGER', healthPct = 0.65, powerPct = 0.4  },
	{ name = 'Frostbolt',  class = 'MAGE',    role = 'DAMAGER', healthPct = 0.78, powerPct = 0.9  },
	{ name = 'Deadshot',   class = 'HUNTER',  role = 'DAMAGER', healthPct = 0,    powerPct = 0,    isDead = true },
}

-- Class colors for the health bar tint (normalized RGB).
-- These are static approximations; in live frames we use RAID_CLASS_COLORS.
local CLASS_COLORS = {
	WARRIOR    = { 0.78, 0.61, 0.43 },
	PALADIN    = { 0.96, 0.55, 0.73 },
	HUNTER     = { 0.67, 0.83, 0.45 },
	ROGUE      = { 1.00, 0.96, 0.41 },
	PRIEST     = { 1.00, 1.00, 1.00 },
	DEATHKNIGHT = { 0.77, 0.12, 0.23 },
	SHAMAN     = { 0.00, 0.44, 0.87 },
	MAGE       = { 0.41, 0.80, 0.94 },
	WARLOCK    = { 0.58, 0.51, 0.79 },
	MONK       = { 0.00, 1.00, 0.59 },
	DRUID      = { 1.00, 0.49, 0.04 },
	DEMONHUNTER = { 0.64, 0.19, 0.79 },
	EVOKER     = { 0.20, 0.58, 0.50 },
}

-- Power bar is a muted secondary color regardless of power type.
local POWER_BAR_COLOR = { 0.30, 0.52, 0.90, 1 }

-- Dead overlay color (dark red tint).
local DEAD_OVERLAY_COLOR = { 0.60, 0.10, 0.10, 0.75 }

-- Layout constants for the mini preview frame.
local HEALTH_BAR_HEIGHT = 14
local POWER_BAR_HEIGHT  = 6
local BAR_SPACING       = 2
local TEXT_OFFSET_X     = 4
local TEXT_OFFSET_Y     = -2

-- ============================================================
-- State
-- ============================================================

local active = false

-- ============================================================
-- Enable / Disable / IsActive
-- ============================================================

--- Enable preview mode. Callers should refresh their preview frames.
function Preview.Enable()
	active = true
end

--- Disable preview mode.
function Preview.Disable()
	active = false
end

--- Returns true while preview mode is active.
--- @return boolean
function Preview.IsActive()
	return active
end

-- ============================================================
-- GetFakeUnits
-- ============================================================

--- Return the first `count` fake unit entries.
--- @param count number
--- @return table Array of fake unit info tables (up to count entries).
function Preview.GetFakeUnits(count)
	local result = {}
	local max = math.min(count, #FAKE_UNITS)
	for i = 1, max do
		result[i] = FAKE_UNITS[i]
	end
	return result
end

-- ============================================================
-- CreatePreviewFrame
-- ============================================================

--- Apply fake unit data to an existing preview frame.
--- @param frame Frame  The preview frame returned by CreatePreviewFrame
--- @param unit  table  A fake unit table from FAKE_UNITS / GetFakeUnits
local function ApplyUnitToFrame(frame, unit)
	-- Name text
	frame._nameText:SetText(unit.name or '')

	-- Health bar color (class-colored)
	local classColor = CLASS_COLORS[unit.class] or { 0.5, 0.5, 0.5 }
	frame._healthBar:SetStatusBarColor(classColor[1], classColor[2], classColor[3], 1)
	frame._healthBar:SetValue(unit.healthPct or 0)

	-- Power bar
	frame._powerBar:SetValue(unit.powerPct or 0)

	-- Dead overlay
	if(unit.isDead) then
		frame._deadOverlay:Show()
	else
		frame._deadOverlay:Hide()
	end
end

--- Create a simplified preview frame representing one unit.
--- Displays a health bar (class-colored), power bar, name text,
--- and a "DEAD" overlay when the unit is dead.
--- Does NOT use oUF — this is a lightweight visual-only widget.
--- @param parent   Frame  Parent frame
--- @param unitType string  Hint for future callers (e.g. 'player', 'raid'); unused internally
--- @param width    number  Logical width
--- @param height   number  Logical height
--- @return Frame  previewFrame  Positioned by the caller
function Preview.CreatePreviewFrame(parent, unitType, width, height)
	-- Outer bordered container
	local frame = Widgets.CreateBorderedFrame(parent, width, height, C.Colors.widget, C.Colors.border)

	-- ── Health bar ────────────────────────────────────────────
	local healthWrapper = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
	Widgets.ApplyBackdrop(healthWrapper, C.Colors.panel, C.Colors.border)
	healthWrapper:ClearAllPoints()
	Widgets.SetPoint(healthWrapper, 'TOPLEFT',  frame, 'TOPLEFT',  1, -1)
	Widgets.SetPoint(healthWrapper, 'TOPRIGHT', frame, 'TOPRIGHT', -1, -1)
	healthWrapper:SetHeight(HEALTH_BAR_HEIGHT)

	local healthBar = CreateFrame('StatusBar', nil, healthWrapper)
	healthBar:SetPoint('TOPLEFT',     healthWrapper, 'TOPLEFT',      1, -1)
	healthBar:SetPoint('BOTTOMRIGHT', healthWrapper, 'BOTTOMRIGHT', -1,  1)
	healthBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
	healthBar:GetStatusBarTexture():SetHorizTile(false)
	healthBar:GetStatusBarTexture():SetVertTile(false)
	healthBar:SetMinMaxValues(0, 1)
	healthBar:SetValue(1)
	local accent = C.Colors.accent
	healthBar:SetStatusBarColor(accent[1], accent[2], accent[3], 1)
	frame._healthBar = healthBar

	-- ── Power bar ─────────────────────────────────────────────
	local powerWrapper = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
	Widgets.ApplyBackdrop(powerWrapper, C.Colors.panel, C.Colors.border)
	powerWrapper:ClearAllPoints()
	Widgets.SetPoint(powerWrapper, 'TOPLEFT',  healthWrapper, 'BOTTOMLEFT',  0, -BAR_SPACING)
	Widgets.SetPoint(powerWrapper, 'TOPRIGHT', healthWrapper, 'BOTTOMRIGHT', 0, -BAR_SPACING)
	powerWrapper:SetHeight(POWER_BAR_HEIGHT)

	local powerBar = CreateFrame('StatusBar', nil, powerWrapper)
	powerBar:SetPoint('TOPLEFT',     powerWrapper, 'TOPLEFT',      1, -1)
	powerBar:SetPoint('BOTTOMRIGHT', powerWrapper, 'BOTTOMRIGHT', -1,  1)
	powerBar:SetStatusBarTexture([[Interface\BUTTONS\WHITE8x8]])
	powerBar:GetStatusBarTexture():SetHorizTile(false)
	powerBar:GetStatusBarTexture():SetVertTile(false)
	powerBar:SetMinMaxValues(0, 1)
	powerBar:SetValue(1)
	powerBar:SetStatusBarColor(
		POWER_BAR_COLOR[1], POWER_BAR_COLOR[2], POWER_BAR_COLOR[3], POWER_BAR_COLOR[4])
	frame._powerBar = powerBar

	-- ── Name text (overlaid on health bar) ───────────────────
	local nameText = Widgets.CreateFontString(frame, C.Font.sizeSmall, C.Colors.textActive)
	nameText:ClearAllPoints()
	Widgets.SetPoint(nameText, 'TOPLEFT', frame, 'TOPLEFT', TEXT_OFFSET_X, TEXT_OFFSET_Y)
	nameText:SetText('')
	frame._nameText = nameText

	-- ── Dead overlay ──────────────────────────────────────────
	local deadOverlay = frame:CreateTexture(nil, 'OVERLAY')
	deadOverlay:SetAllPoints(frame)
	deadOverlay:SetColorTexture(
		DEAD_OVERLAY_COLOR[1],
		DEAD_OVERLAY_COLOR[2],
		DEAD_OVERLAY_COLOR[3],
		DEAD_OVERLAY_COLOR[4])
	deadOverlay:Hide()
	frame._deadOverlay = deadOverlay

	-- ── Dead label ────────────────────────────────────────────
	local deadText = Widgets.CreateFontString(frame, C.Font.sizeSmall, C.Colors.textNormal)
	deadText:ClearAllPoints()
	deadText:SetPoint('CENTER', frame, 'CENTER', 0, 0)
	deadText:SetText('DEAD')
	deadText:Hide()
	frame._deadText = deadText

	-- Show the dead text in sync with the overlay
	local originalSetTexture = deadOverlay.Show
	hooksecurefunc(deadOverlay, 'Show', function() deadText:Show() end)
	hooksecurefunc(deadOverlay, 'Hide', function() deadText:Hide() end)

	-- ── Unit type tag (stored for callers) ────────────────────
	frame._unitType = unitType

	-- ── Apply first fake unit as default visual state ─────────
	ApplyUnitToFrame(frame, FAKE_UNITS[1])

	--- Refresh this preview frame with a specific fake unit table.
	--- @param unit table A fake unit info table
	function frame:SetFakeUnit(unit)
		ApplyUnitToFrame(self, unit)
	end

	return frame
end
