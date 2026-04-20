local _, Framed = ...
local F = Framed
local C = F.Constants
local A = F.AuraDefaults

F.PresetDefaults = {}

-- ============================================================
-- Unit config templates (NO aura fields — those live in preset.auras)
-- ============================================================

--- Base config shared by all unit types. Each unit config function calls this
--- and overrides unit-specific values. Every key that any consumer reads must
--- exist here or in the unit-specific override.
local function baseUnitConfig()
	return {
		width  = 200,
		height = 40,
		showName     = true,
		showPower    = true,
		showCastBar  = true,
		position = { x = 0, y = 0, anchor = 'CENTER' },
		health = {
			colorMode          = 'class',
			colorThreat        = false,
			smooth             = true,
			customColor        = { 0.2, 0.8, 0.2, 1 },
			gradientColor1     = { 0.2, 0.8, 0.2, 1 },
			gradientThreshold1 = 95,
			gradientColor2     = { 0.9, 0.6, 0.1, 1 },
			gradientThreshold2 = 50,
			gradientColor3     = { 0.8, 0.1, 0.1, 1 },
			gradientThreshold3 = 5,
			lossColorMode      = 'dark',
			lossCustomColor    = { 0.15, 0.15, 0.15, 1 },
			lossGradientColor1     = { 0.1, 0.4, 0.1, 1 },
			lossGradientThreshold1 = 95,
			lossGradientColor2     = { 0.4, 0.25, 0.05, 1 },
			lossGradientThreshold2 = 50,
			lossGradientColor3     = { 0.4, 0.05, 0.05, 1 },
			lossGradientThreshold3 = 5,
			showText           = false,
			textFormat         = 'percent',
			textColorMode      = 'white',
			textCustomColor    = { 1, 1, 1, 1 },
			fontSize           = C.Font.sizeSmall,
			textAnchor         = 'CENTER',
			textAnchorX        = 0,
			textAnchorY        = 0,
			outline            = '',
			shadow             = true,
			attachedToName     = false,
			healPrediction     = true,
			healPredictionMode = 'all',
			healPredictionColor = { 0.6, 0.6, 0.6, 0.4 },
			damageAbsorb       = true,
			damageAbsorbColor  = { 1, 1, 1, 0.6 },
			healAbsorb         = true,
			healAbsorbColor    = { 0.7, 0.1, 0.1, 0.5 },
			overAbsorb         = true,
		},
		power = {
			height        = 2,
			position      = 'bottom',
			showText      = false,
			textFormat    = 'current',
			textColorMode = 'white',
			textCustomColor = { 1, 1, 1, 1 },
			fontSize      = C.Font.sizeSmall,
			textAnchor    = 'CENTER',
			textAnchorX   = 0,
			textAnchorY   = 0,
			outline       = '',
			shadow        = true,
		},
		name = {
			colorMode   = 'class',
			customColor = { 1, 1, 1, 1 },
			fontSize    = C.Font.sizeNormal,
			anchor      = 'CENTER',
			anchorX     = 0,
			anchorY     = 0,
			outline     = '',
			shadow      = true,
		},
		range = { outsideAlpha = 0.4 },
		statusIcons = {
			role       = true,
			rolePoint  = 'TOPLEFT',     roleX  = 2,   roleY  = -2, roleSize  = 12,
			leader     = true,
			leaderPoint = 'TOPLEFT',    leaderX = 16,  leaderY = -2, leaderSize = 12,
			readyCheck = true,
			readyCheckPoint = 'CENTER', readyCheckX = 0, readyCheckY = 0, readyCheckSize = 16,
			raidIcon   = true,
			raidIconPoint = 'TOP',      raidIconX = 0,  raidIconY = -2, raidIconSize = 16,
			combat     = false,
			combatPoint = 'TOPRIGHT',   combatX = -2,  combatY = -2, combatSize = 12,
			resting    = false,
			restingPoint = 'BOTTOMLEFT', restingX = 2, restingY = 2, restingSize = 12,
			phase      = true,
			phasePoint = 'CENTER',      phaseX = 0,    phaseY = 0,  phaseSize = 16,
			resurrect  = true,
			resurrectPoint = 'CENTER',  resurrectX = 0, resurrectY = 0, resurrectSize = 16,
			summon     = true,
			summonPoint = 'CENTER',     summonX = 0,   summonY = 0, summonSize = 16,
			raidRole   = true,
			raidRolePoint = 'BOTTOMRIGHT', raidRoleX = -2, raidRoleY = 2, raidRoleSize = 12,
			pvp        = false,
			pvpPoint   = 'BOTTOMLEFT',  pvpX = 2,    pvpY = 2,   pvpSize = 16,
		},
		statusText = {
			enabled  = true,
			fontSize = 7,
			outline  = 'OUTLINE',
			shadow   = false,
			position = 'bottom',
		},
		targetHighlight    = true,
		mouseoverHighlight = true,
		elementStrata = {
			healthBar      = 0,
			healPrediction = 1,
			damageAbsorb   = 2,
			healAbsorb     = 3,
			overAbsorb     = 4,
			nameText       = 5,
			statusIcons    = 6,
			statusText     = 7,
			castBar        = 8,
			portrait       = 9,
		},
	}
end

-- Pinned frames: shared style across up to 9 slots, per-slot name-tracking.
-- Opt-in by default (enabled = false). Solo preset omits this block entirely.
local function pinnedConfig()
	local cfg = baseUnitConfig()
	cfg.enabled  = false
	cfg.count    = 9
	cfg.columns  = 3
	cfg.width    = 160
	cfg.height   = 40
	cfg.spacing  = 2
	cfg.slots    = {}  -- keys 1..9; nil = unassigned
	cfg.position = { x = 0, y = 0, anchor = 'CENTER' }
	return cfg
end

local function defaultCastbar(frameWidth)
	return {
		height         = 16,
		sizeMode       = 'attached',
		width          = frameWidth,
		backgroundMode = 'always',
		showIcon       = true,
		showText       = true,
		showTime       = true,
	}
end

local function defaultPortrait()
	return { type = '2D' }
end

local function defaultThreat()
	return { aggroBlink = false }
end

local function playerConfig()
	local c = baseUnitConfig()
	c.position = { x = -200, y = -200, anchor = 'CENTER' }
	c.castbar  = defaultCastbar(c.width)
	c.portrait = defaultPortrait()
	c.threat   = defaultThreat()
	c.statusIcons.combat  = true
	c.statusIcons.resting = true
	c.statusIcons.phase   = false
	c.statusIcons.resurrect = false
	c.statusIcons.summon    = false
	c.statusIcons.raidRole  = false
	return c
end

local function targetConfig()
	local c = baseUnitConfig()
	c.position = { x = 200, y = -200, anchor = 'CENTER' }
	c.health.healPrediction = false
	c.health.damageAbsorb   = false
	c.health.healAbsorb     = false
	c.health.overAbsorb     = false
	c.castbar  = defaultCastbar(c.width)
	c.portrait = defaultPortrait()
	c.threat   = defaultThreat()
	c.statusIcons.combat  = false
	c.statusIcons.resting = false
	c.statusIcons.phase   = true
	c.statusIcons.resurrect = false
	c.statusIcons.summon    = false
	c.statusIcons.raidRole  = false
	return c
end

local function targettargetConfig()
	local c = baseUnitConfig()
	c.width    = 120
	c.height   = 24
	c.position = { x = 200, y = -260, anchor = 'CENTER' }
	c.health.healPrediction = false
	c.health.damageAbsorb   = false
	c.health.healAbsorb     = false
	c.health.overAbsorb     = false
	c.name.fontSize = C.Font.sizeSmall
	c.statusIcons.role       = false
	c.statusIcons.leader     = false
	c.statusIcons.readyCheck = false
	c.statusIcons.combat     = false
	c.statusIcons.resting    = false
	c.statusIcons.phase      = false
	c.statusIcons.resurrect  = false
	c.statusIcons.summon     = false
	c.statusIcons.raidRole   = false
	c.statusText.enabled = false
	return c
end

local function focusConfig()
	local c = baseUnitConfig()
	c.width    = 160
	c.height   = 30
	c.position = { x = -300, y = -100, anchor = 'CENTER' }
	c.health.healPrediction = false
	c.health.damageAbsorb   = false
	c.health.healAbsorb     = false
	c.health.overAbsorb     = false
	c.name.fontSize = C.Font.sizeSmall
	c.castbar = defaultCastbar(c.width)
	c.statusIcons.role       = false
	c.statusIcons.leader     = false
	c.statusIcons.readyCheck = false
	c.statusIcons.combat     = false
	c.statusIcons.resting    = false
	c.statusIcons.phase      = false
	c.statusIcons.resurrect  = false
	c.statusIcons.summon     = false
	c.statusIcons.raidRole   = false
	c.statusText.enabled = false
	return c
end

local function petConfig()
	local c = baseUnitConfig()
	c.width    = 120
	c.height   = 20
	c.position = { x = -200, y = -260, anchor = 'CENTER' }
	c.health.healPrediction = false
	c.health.damageAbsorb   = false
	c.health.healAbsorb     = false
	c.health.overAbsorb     = false
	c.name.fontSize = C.Font.sizeSmall
	c.statusIcons.role       = false
	c.statusIcons.leader     = false
	c.statusIcons.readyCheck = false
	c.statusIcons.raidIcon   = false
	c.statusIcons.combat     = false
	c.statusIcons.resting    = false
	c.statusIcons.phase      = false
	c.statusIcons.resurrect  = false
	c.statusIcons.summon     = false
	c.statusIcons.raidRole   = false
	c.statusText.enabled  = false
	c.targetHighlight     = false
	return c
end

local function bossConfig()
	local c = baseUnitConfig()
	c.width       = 160
	c.height      = 30
	c.position    = { x = 300, y = 100, anchor = 'CENTER' }
	c.spacing     = 4
	c.orientation = 'vertical'
	c.anchorPoint = 'TOPLEFT'
	c.unitsPerColumn = 4
	c.maxColumns     = 1
	c.health.showText       = true
	c.health.textFormat     = 'current'
	c.health.healPrediction = false
	c.health.damageAbsorb   = false
	c.health.healAbsorb     = false
	c.health.overAbsorb     = false
	c.name.fontSize = C.Font.sizeSmall
	c.castbar = defaultCastbar(c.width)
	c.statusIcons.role       = false
	c.statusIcons.leader     = false
	c.statusIcons.readyCheck = false
	c.statusIcons.combat     = false
	c.statusIcons.resting    = false
	c.statusIcons.phase      = false
	c.statusIcons.resurrect  = false
	c.statusIcons.summon     = false
	c.statusIcons.raidRole   = false
	c.statusText.enabled = false
	return c
end

local function partyConfig()
	local c = baseUnitConfig()
	c.width       = 120
	c.height      = 36
	c.spacing     = 2
	c.orientation = 'vertical'
	c.anchorPoint = 'TOPLEFT'
	c.position    = { x = 40, y = -48, anchor = 'TOPLEFT' }
	c.unitsPerColumn = 5
	c.maxColumns     = 1
	c.sortMode  = 'index'
	c.roleOrder = 'HEALER,TANK,DAMAGER'
	c.health.showText   = true
	c.health.textFormat = 'percent'
	c.name.fontSize = C.Font.sizeSmall
	c.threat = defaultThreat()
	c.statusIcons.combat  = false
	c.statusIcons.resting = false
	c.statusIcons.raidRole = false
	return c
end

local function raidConfig()
	local c = baseUnitConfig()
	c.width       = 72
	c.height      = 36
	c.spacing     = 2
	c.orientation = 'vertical'
	c.anchorPoint = 'TOPLEFT'
	c.position    = { x = 40, y = -48, anchor = 'TOPLEFT' }
	c.unitsPerColumn = 5
	c.maxColumns     = 8
	c.sortMode    = 'group'
	c.roleOrder   = 'TANK,HEALER,DAMAGER'
	c.health.showText   = true
	c.health.textFormat = 'percent'
	c.name.fontSize = C.Font.sizeSmall
	c.statusIcons.combat  = false
	c.statusIcons.resting = false
	c.statusIcons.raidRole = false
	return c
end

local function arenaConfig()
	local c = baseUnitConfig()
	c.width       = 160
	c.height      = 30
	c.position    = { x = 300, y = 100, anchor = 'CENTER' }
	c.spacing     = 4
	c.orientation = 'vertical'
	c.anchorPoint = 'TOPLEFT'
	c.unitsPerColumn = 3
	c.maxColumns     = 1
	c.health.showText       = true
	c.health.textFormat     = 'current'
	c.health.healPrediction = false
	c.health.damageAbsorb   = false
	c.health.healAbsorb     = false
	c.health.overAbsorb     = false
	c.name.fontSize = C.Font.sizeSmall
	c.castbar = defaultCastbar(c.width)
	c.statusIcons.role       = false
	c.statusIcons.leader     = false
	c.statusIcons.readyCheck = false
	c.statusIcons.combat     = false
	c.statusIcons.resting    = false
	c.statusIcons.phase      = false
	c.statusIcons.resurrect  = false
	c.statusIcons.summon     = false
	c.statusIcons.raidRole   = false
	c.statusIcons.pvp        = true
	c.statusText.enabled = false
	return c
end

-- ============================================================
-- Shared aura size tables
-- ============================================================

local PARTY_AURA_SIZES = {
	iconSize = 16, bigIconSize = 22,
	raidDebuffIcon = 16, raidDebuffBigIcon = 20,
	externalsIcon = 16, defensivesIcon = 16,
	targetedSpellsIcon = 16, dispellableIcon = 16,
	privateAurasIcon = 16, missingBuffsIcon = 12,
}

local RAID_AURA_SIZES = {
	iconSize = 14, bigIconSize = 18,
	raidDebuffIcon = 14, raidDebuffBigIcon = 18,
	externalsIcon = 14, defensivesIcon = 14,
	externalsMax = 1, defensivesMax = 1,
	debuffMax = 1, raidDebuffMax = 1,
	targetedSpellsIcon = 14, dispellableIcon = 14,
	privateAurasIcon = 14, missingBuffsIcon = 12,
}

-- ============================================================
-- Shared solo unit aura set (player, target, focus, etc.)
-- ============================================================

local function soloUnitAuras()
	return {
		player       = A.Solo(14, 6),
		target       = A.Solo(14, 6),
		targettarget = A.Solo(14, 3),
		focus        = A.Solo(14, 6),
		pet          = A.Minimal(),
		boss         = A.Boss(),
	}
end

-- ============================================================
-- GetAll — returns complete default preset table
-- ============================================================

function F.PresetDefaults.GetAll()
	local presets = {}

	-- Solo
	-- Note: no `pinned` block — pinned frames are a group-only feature. The
	-- sidebar / EditMode / Spawn paths gate on the presence of unitConfigs.pinned,
	-- so omitting it here hides pinned entirely while Solo is the editing preset.
	presets['Solo'] = {
		isBase    = true,
		positions = {},
		unitConfigs = {
			player       = playerConfig(),
			target       = targetConfig(),
			targettarget = targettargetConfig(),
			focus        = focusConfig(),
			pet          = petConfig(),
			boss         = bossConfig(),
		},
		auras = soloUnitAuras(),
	}

	-- Party
	local partyAuras = soloUnitAuras()
	partyAuras.party   = A.Group(PARTY_AURA_SIZES)
	partyAuras.pinned  = A.Group(PARTY_AURA_SIZES)

	presets['Party'] = {
		isBase    = true,
		positions = {},
		unitConfigs = {
			player       = playerConfig(),
			target       = targetConfig(),
			targettarget = targettargetConfig(),
			focus        = focusConfig(),
			pet          = (function()
				local p = petConfig()
				p.width  = 72
				p.height = 18
				return p
			end)(),
			boss   = bossConfig(),
			party  = partyConfig(),
			pinned = pinnedConfig(),
		},
		partyPets = {
			enabled            = true,
			spacing            = 2,
			showHealthText     = true,
			healthTextFormat   = 'percent',
			healthTextFontSize = C.Font.sizeSmall,
			healthTextColor    = 'white',
			healthTextOutline  = '',
			healthTextShadow   = true,
			healthTextAnchor   = 'CENTER',
			healthTextOffsetX  = 0,
			healthTextOffsetY  = 2,
			showName           = true,
			nameFontSize       = C.Font.sizeSmall,
			nameOutline        = '',
			nameShadow         = true,
			nameAnchor         = 'TOP',
			nameOffsetX        = 0,
			nameOffsetY        = -2,
		},
		auras = partyAuras,
	}

	-- Raid
	local raidAuras = soloUnitAuras()
	raidAuras.raid   = A.Group(RAID_AURA_SIZES)
	raidAuras.pinned = A.Group(RAID_AURA_SIZES)

	presets['Raid'] = {
		isBase    = true,
		positions = {},
		unitConfigs = {
			player       = playerConfig(),
			target       = targetConfig(),
			targettarget = targettargetConfig(),
			focus        = focusConfig(),
			pet          = petConfig(),
			boss         = bossConfig(),
			raid         = raidConfig(),
			pinned       = pinnedConfig(),
		},
		auras = raidAuras,
	}

	-- Arena
	local arenaAuras = soloUnitAuras()
	arenaAuras.party = (function()
		local a = A.Group(PARTY_AURA_SIZES)
		if(a.debuffs and a.debuffs.indicators and a.debuffs.indicators['Raid Debuffs']) then
			a.debuffs.indicators['Raid Debuffs'].enabled = false
		end
		return a
	end)()
	arenaAuras.arena   = A.Arena()
	arenaAuras.pinned  = A.Group(PARTY_AURA_SIZES)

	presets['Arena'] = {
		isBase    = true,
		positions = {},
		unitConfigs = {
			player = (function()
				local p = playerConfig()
				p.portrait = false
				return p
			end)(),
			target = (function()
				local t = targetConfig()
				t.portrait = false
				return t
			end)(),
			targettarget = targettargetConfig(),
			focus        = focusConfig(),
			pet          = petConfig(),
			boss         = bossConfig(),
			party        = partyConfig(),
			arena        = arenaConfig(),
			pinned       = pinnedConfig(),
		},
		auras = arenaAuras,
	}

	-- Derived presets (copy from Raid, mark as not customized)
	for _, name in next, { 'Mythic Raid', 'World Raid', 'Battleground' } do
		local info = C.PresetInfo[name]
		presets[name] = F.DeepCopy(presets[info.fallback])
		presets[name].isBase     = nil
		presets[name].customized = false
		presets[name].fallback   = info.fallback
	end

	return presets
end

-- ============================================================
-- Aura config backfill
-- ============================================================

-- Keys that represent user-owned collections inside an aura sub-table.
-- We must NOT recurse into these during backfill — a user who removed
-- an indicator would otherwise have it restored from defaults.
local AURA_USER_COLLECTIONS = {
	indicators = true,
	spells     = true,
}

--- Fill missing keys in `target` from `defaults`, recursing into
--- nested tables except the user-owned collection keys above.
--- Never overwrites existing values.
local function backfillAuraConfig(target, defaults)
	for k, v in next, defaults do
		if(target[k] == nil) then
			target[k] = F.DeepCopy(v)
		elseif(type(v) == 'table' and type(target[k]) == 'table' and not AURA_USER_COLLECTIONS[k]) then
			backfillAuraConfig(target[k], v)
		end
	end
end

-- ============================================================
-- EnsureDefaults — populate FramedDB.presets on first run
-- ============================================================

function F.PresetDefaults.EnsureDefaults()
	if(not FramedDB) then FramedDB = {} end
	if(not FramedDB.presets) then
		FramedDB.presets = F.PresetDefaults.GetAll()
		return
	end

	-- Ensure each preset exists (don't overwrite user data)
	local defaults = F.PresetDefaults.GetAll()
	for name, preset in next, defaults do
		if(not FramedDB.presets[name]) then
			FramedDB.presets[name] = preset
		else
			-- Backfill missing keys inside existing unitConfigs
			local savedUC = FramedDB.presets[name].unitConfigs
			local defaultUC = preset.unitConfigs
			if(savedUC and defaultUC) then
				for unitType, defaultConf in next, defaultUC do
					if(savedUC[unitType]) then
						-- Backfill / migrate statusText (was boolean, now table)
						local saved = savedUC[unitType].statusText
						if(saved == nil) then
							savedUC[unitType].statusText = defaultConf.statusText
						elseif(type(saved) == 'boolean') then
							savedUC[unitType].statusText = { enabled = saved }
						end
						-- statusText detail keys are backfilled by F.DeepMerge below
						-- Migrate growthDirection → anchorPoint
						if(savedUC[unitType].growthDirection) then
							local map = {
								topToBottom  = 'TOPLEFT',
								bottomToTop  = 'BOTTOMLEFT',
								leftToRight  = 'TOPLEFT',
								rightToLeft  = 'TOPRIGHT',
							}
							savedUC[unitType].anchorPoint = map[savedUC[unitType].growthDirection] or 'TOPLEFT'
							savedUC[unitType].growthDirection = nil
						end
					end
				end
				-- Migrate raidRole: was inherited as true from base config
				-- for party/raid before it was explicitly disabled
				for _, ut in next, { 'party', 'raid' } do
					if(savedUC[ut] and savedUC[ut].statusIcons) then
						savedUC[ut].statusIcons.raidRole = false
					end
				end

				-- Migrate pinned.count: old default was 3, new is 9. Bump any
				-- save that still matches the old default so existing users
				-- don't get stuck with 3 slots and no UI control to change it.
				if(savedUC.pinned and savedUC.pinned.count == 3) then
					savedUC.pinned.count = 9
				end

				-- Strip pinned from Solo. An earlier default incorrectly seeded
				-- Solo with a pinnedConfig, which made the sidebar / EditMode
				-- treat Solo as pinned-capable. Pinned is a group-only feature.
				if(name == 'Solo') then
					savedUC.pinned = nil
				end

				-- General backfill: deep-merge any missing keys from defaults
				-- into existing unit configs. This handles all new keys added
				-- by the canonical defaults expansion.
				for unitType, defaultConf in next, defaultUC do
					if(savedUC[unitType]) then
						F.DeepMerge(savedUC[unitType], defaultConf)
					else
						savedUC[unitType] = F.DeepCopy(defaultConf)
					end
				end
			end
			-- Backfill partyPets config
			if(preset.partyPets and not FramedDB.presets[name].partyPets) then
				FramedDB.presets[name].partyPets = preset.partyPets
			end
			-- Backfill buffs.enabled (was missing in earlier versions)
			-- Migrate aura config keys
			local savedAuras = FramedDB.presets[name].auras
			if(savedAuras) then
				for unitType, auraSet in next, savedAuras do
					if(auraSet.buffs and auraSet.buffs.indicators and auraSet.buffs.enabled == nil) then
						auraSet.buffs.enabled = true
					end
					-- Migrate hideUnimportantBuffs → buffFilterMode
					if(auraSet.buffs) then
						if(not auraSet.buffs.buffFilterMode) then
							if(unitType == 'party' or unitType == 'raid') then
								auraSet.buffs.buffFilterMode = (auraSet.buffs.hideUnimportantBuffs ~= false) and 'raidCombat' or 'all'
							else
								auraSet.buffs.buffFilterMode = 'raidCombat'
							end
						end
						auraSet.buffs.hideUnimportantBuffs = nil
					end
					-- Migrate onlyDispellableByMe → filterMode
					if(auraSet.debuffs and not auraSet.debuffs.filterMode) then
						if(auraSet.debuffs.onlyDispellableByMe) then
							auraSet.debuffs.filterMode = 'dispellable'
						else
							auraSet.debuffs.filterMode = 'all'
						end
						auraSet.debuffs.onlyDispellableByMe = nil
					end
				end

				-- Backfill missing aura sub-tables and missing scalar keys
				-- inside existing sub-tables from canonical defaults. Skips
				-- user-owned collections (indicators, spells) so a user
				-- who removed an indicator doesn't have it restored.
				local defaultAuras = preset.auras
				if(defaultAuras) then
					for unitType, defaultSet in next, defaultAuras do
						local savedSet = savedAuras[unitType]
						if(not savedSet) then
							savedAuras[unitType] = F.DeepCopy(defaultSet)
						else
							for auraType, defaultCfg in next, defaultSet do
								local savedCfg = savedSet[auraType]
								if(savedCfg == nil) then
									savedSet[auraType] = F.DeepCopy(defaultCfg)
								elseif(type(savedCfg) == 'table' and type(defaultCfg) == 'table') then
									backfillAuraConfig(savedCfg, defaultCfg)
								end
							end
						end
					end
				end
			end
		end
	end
end
