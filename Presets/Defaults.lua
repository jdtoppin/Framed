local addonName, Framed = ...
local F = Framed
local C = F.Constants
local A = F.AuraDefaults

F.PresetDefaults = {}

-- ============================================================
-- Unit config templates (NO aura fields — those live in preset.auras)
-- ============================================================

local function playerConfig()
	return {
		width  = 200,
		height = 40,
		position = { x = -200, y = -200 },
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = false,
			textFormat     = 'none',
			healPrediction = true,
		},
		power = { height = 2, showText = false },
		name = {
			colorMode = 'class',
			fontSize  = C.Font.sizeNormal,
		},
		castbar = {
			height   = 16,
			showIcon = true,
			showText = true,
			showTime = true,
		},
		portrait = { type = '2D' },
		threat   = { aggroBlink = false },
		range    = { outsideAlpha = 0.4 },
		statusIcons = {
			role       = true,
			leader     = true,
			readyCheck = true,
			raidIcon   = true,
			combat     = true,
			resting    = true,
			phase      = false,
			resurrect  = false,
			summon     = false,
			raidRole   = false,
			pvp        = false,
		},
		statusText         = { enabled = true },
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

local function targetConfig()
	return {
		width  = 200,
		height = 40,
		position = { x = 200, y = -200 },
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = false,
			textFormat     = 'none',
			healPrediction = false,
			damageAbsorb   = false,
			healAbsorb     = false,
			overAbsorb     = false,
		},
		power = { height = 2, showText = false },
		name = {
			colorMode = 'class',
			fontSize  = C.Font.sizeNormal,
		},
		castbar = {
			height   = 16,
			showIcon = true,
			showText = true,
			showTime = true,
		},
		portrait = { type = '2D' },
		threat   = { aggroBlink = false },
		range    = { outsideAlpha = 0.4 },
		statusIcons = {
			role       = true,
			leader     = true,
			readyCheck = true,
			raidIcon   = true,
			combat     = false,
			resting    = false,
			phase      = true,
			resurrect  = false,
			summon     = false,
			raidRole   = false,
			pvp        = false,
		},
		statusText         = { enabled = true },
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

local function targettargetConfig()
	return {
		width  = 120,
		height = 24,
		position = { x = 200, y = -240 },
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = false,
			textFormat     = 'none',
			healPrediction = false,
			damageAbsorb   = false,
			healAbsorb     = false,
			overAbsorb     = false,
		},
		power = { height = 2, showText = false },
		name  = { colorMode = 'class', fontSize = C.Font.sizeSmall },
		range = { outsideAlpha = 0.4 },
		statusIcons = {
			role = false, leader = false, readyCheck = false,
			raidIcon = true, combat = false,
			resting = false, phase = false, resurrect = false,
			summon = false, raidRole = false, pvp = false,
		},
		statusText         = { enabled = false },
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

local function focusConfig()
	return {
		width  = 150,
		height = 30,
		position = { x = -300, y = -100 },
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = false,
			textFormat     = 'none',
			healPrediction = false,
			damageAbsorb   = false,
			healAbsorb     = false,
			overAbsorb     = false,
		},
		power   = { height = 2, showText = false },
		name    = { colorMode = 'class', fontSize = C.Font.sizeSmall },
		castbar = { height = 14, showIcon = true, showText = true, showTime = true },
		range   = { outsideAlpha = 0.4 },
		statusIcons = {
			role = false, leader = false, readyCheck = false,
			raidIcon = true, combat = false,
			resting = false, phase = false, resurrect = false,
			summon = false, raidRole = false, pvp = false,
		},
		statusText         = { enabled = false },
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

local function petConfig()
	return {
		width  = 120,
		height = 24,
		position = { x = -200, y = -260 },
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = false,
			textFormat     = 'none',
			healPrediction = false,
			damageAbsorb   = false,
			healAbsorb     = false,
			overAbsorb     = false,
		},
		power  = { height = 2, showText = false },
		name   = { colorMode = 'class', fontSize = C.Font.sizeSmall },
		range  = { outsideAlpha = 0.4 },
		statusIcons = {
			role = false, leader = false, readyCheck = false,
			raidIcon = false, combat = false,
			resting = false, phase = false, resurrect = false,
			summon = false, raidRole = false, pvp = false,
		},
		statusText         = { enabled = false },
		targetHighlight    = false,
		mouseoverHighlight = true,
	}
end

local function bossConfig()
	return {
		width  = 150,
		height = 30,
		position = { x = 300, y = 0 },
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = true,
			textFormat     = 'current',
			healPrediction = false,
			damageAbsorb   = false,
			healAbsorb     = false,
			overAbsorb     = false,
		},
		power   = { height = 2, showText = false },
		name    = { colorMode = 'class', fontSize = C.Font.sizeSmall },
		castbar = { height = 14, showIcon = true, showText = true, showTime = true },
		range   = { outsideAlpha = 0.4 },
		statusIcons = {
			role = false, leader = false, readyCheck = false,
			raidIcon = true, combat = false,
			resting = false, phase = false, resurrect = false,
			summon = false, raidRole = false, pvp = false,
		},
		statusText         = { enabled = false },
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

local function partyConfig()
	return {
		width  = 120,
		height = 36,
		spacing          = 2,
		orientation      = 'vertical',
		anchorPoint      = 'TOPLEFT',
		position         = { x = 20, y = -200 },
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = true,
			textFormat     = 'percent',
			healPrediction = true,
		},
		power = { height = 2, showText = false },
		name  = { colorMode = 'class', fontSize = C.Font.sizeSmall },
		threat = { aggroBlink = false },
		range  = { outsideAlpha = 0.4 },
		statusIcons = {
			role       = true,
			leader     = true,
			readyCheck = true,
			raidIcon   = true,
			combat     = false,
			resting    = false,
			phase      = true,
			resurrect  = true,
			summon     = true,
			raidRole   = true,
			pvp        = false,
		},
		statusText         = { enabled = true },
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

local function raidConfig()
	return {
		width  = 72,
		height = 36,
		spacing          = 2,
		orientation      = 'vertical',
		anchorPoint      = 'TOPLEFT',
		position         = { x = 20, y = -200 },
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = true,
			textFormat     = 'percent',
			healPrediction = true,
		},
		power = { height = 2, showText = false },
		name  = { colorMode = 'class', fontSize = C.Font.sizeSmall },
		range = { outsideAlpha = 0.4 },
		statusIcons = {
			role       = true,
			leader     = true,
			readyCheck = true,
			raidIcon   = true,
			combat     = false,
			resting    = false,
			phase      = true,
			resurrect  = true,
			summon     = true,
			raidRole   = true,
			pvp        = false,
		},
		statusText         = { enabled = true },
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

local function arenaConfig()
	return {
		width  = 150,
		height = 30,
		position = { x = 300, y = 0 },
		spacing          = 2,
		orientation      = 'vertical',
		anchorPoint      = 'TOPLEFT',
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = true,
			textFormat     = 'current',
			healPrediction = false,
			damageAbsorb   = false,
			healAbsorb     = false,
			overAbsorb     = false,
		},
		power = { height = 2, showText = false },
		name  = { colorMode = 'class', fontSize = C.Font.sizeSmall },
		castbar = { height = 14, showIcon = true, showText = true, showTime = true },
		range   = { outsideAlpha = 0.4 },
		statusIcons = {
			role = false, leader = false, readyCheck = false,
			raidIcon = true, combat = false,
			resting = false, phase = false, resurrect = false,
			summon = false, raidRole = false, pvp = true,
		},
		statusText         = { enabled = false },
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
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
		targettarget = A.Minimal(),
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
	partyAuras.party = A.Group(PARTY_AURA_SIZES)

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
			boss  = bossConfig(),
			party = partyConfig(),
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
			healthTextOffsetX  = 0,
			healthTextOffsetY  = 2,
		},
		auras = partyAuras,
	}

	-- Raid
	local raidAuras = soloUnitAuras()
	raidAuras.raid = A.Group(RAID_AURA_SIZES)

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
		},
		auras = raidAuras,
	}

	-- Arena
	local arenaAuras = soloUnitAuras()
	arenaAuras.party = (function()
		local a = A.Group(PARTY_AURA_SIZES)
		a.raidDebuffs.enabled = false
		return a
	end)()
	arenaAuras.arena = A.Arena()

	presets['Arena'] = {
		isBase    = true,
		positions = {},
		unitConfigs = {
			player = (function()
				local p = playerConfig()
				p.portrait = nil
				return p
			end)(),
			target = (function()
				local t = targetConfig()
				t.portrait = nil
				return t
			end)(),
			targettarget = targettargetConfig(),
			focus        = focusConfig(),
			pet          = petConfig(),
			boss         = bossConfig(),
			party        = partyConfig(),
			arena        = arenaConfig(),
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
						-- Backfill statusIcons keys
						if(defaultConf.statusIcons) then
							if(not savedUC[unitType].statusIcons) then
								savedUC[unitType].statusIcons = {}
							end
							for key, val in next, defaultConf.statusIcons do
								if(savedUC[unitType].statusIcons[key] == nil) then
									savedUC[unitType].statusIcons[key] = val
								end
							end
						end
						-- Backfill / migrate statusText (was boolean, now table)
						local saved = savedUC[unitType].statusText
						if(saved == nil) then
							savedUC[unitType].statusText = defaultConf.statusText
						elseif(type(saved) == 'boolean') then
							savedUC[unitType].statusText = { enabled = saved }
						end
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
			end
			-- Backfill partyPets config
			if(preset.partyPets and not FramedDB.presets[name].partyPets) then
				FramedDB.presets[name].partyPets = preset.partyPets
			end
			-- Backfill buffs.enabled (was missing in earlier versions)
			-- Backfill hideUnimportantBuffs for group unit types
			local savedAuras = FramedDB.presets[name].auras
			if(savedAuras) then
				for unitType, auraSet in next, savedAuras do
					if(auraSet.buffs and auraSet.buffs.indicators and auraSet.buffs.enabled == nil) then
						auraSet.buffs.enabled = true
					end
					if(auraSet.buffs and (unitType == 'party' or unitType == 'raid') and auraSet.buffs.hideUnimportantBuffs == nil) then
						auraSet.buffs.hideUnimportantBuffs = true
					end
				end
			end
		end
	end
end
