local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.LayoutDefaults = {}

-- ============================================================
-- Deep Copy
-- ============================================================

local function deepCopy(src)
	if(type(src) ~= 'table') then return src end
	local copy = {}
	for k, v in next, src do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- ============================================================
-- Base unit config templates
-- ============================================================

local function playerBase()
	return {
		width  = 200,
		height = 40,
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = false,
			textFormat     = 'none',
			healPrediction = true,
		},
		power = {
			height   = 2,
			showText = false,
		},
		name = {
			colorMode = 'class',
			truncate  = 12,
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
		},
		buffs   = { maxIcons = 6, iconSize = 14, growDirection = 'RIGHT' },
		debuffs = { maxIcons = 6, iconSize = 14, growDirection = 'RIGHT' },
		statusText         = true,
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

local function targetBase()
	return {
		width  = 200,
		height = 40,
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = false,
			textFormat     = 'none',
			healPrediction = false,
		},
		power = {
			height   = 2,
			showText = false,
		},
		name = {
			colorMode = 'class',
			truncate  = 12,
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
		},
		buffs   = { maxIcons = 6, iconSize = 14, growDirection = 'RIGHT' },
		debuffs = { maxIcons = 6, iconSize = 14, growDirection = 'RIGHT' },
		statusText         = true,
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

local function partyBase()
	return {
		width  = 120,
		height = 36,
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = true,
			textFormat     = 'percent',
			healPrediction = true,
		},
		power = {
			height   = 2,
			showText = false,
		},
		name = {
			colorMode = 'class',
			truncate  = 10,
			fontSize  = C.Font.sizeSmall,
		},
		threat   = { aggroBlink = false },
		range    = { outsideAlpha = 0.4 },
		statusIcons = {
			role       = true,
			leader     = true,
			readyCheck = true,
			raidIcon   = true,
			combat     = false,
		},
		raidDebuffs  = { iconSize = 18, filterMode = C.DebuffFilterMode.RAID, minPriority = C.DebuffPriority.NORMAL },
		dispellable  = { glowType = C.GlowType.PIXEL },
		buffs        = { maxIcons = 4, iconSize = 12, growDirection = 'RIGHT', anchor = {'TOPLEFT', nil, 'TOPLEFT', 2, -2} },
		debuffs      = { maxIcons = 3, iconSize = 12, growDirection = 'RIGHT', anchor = {'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2} },
		missingBuffs = { iconSize = 12 },
		privateAuras = { iconSize = 16 },
		statusText         = true,
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

local function raidBase()
	return {
		width  = 72,
		height = 36,
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = true,
			textFormat     = 'percent',
			healPrediction = true,
		},
		power = {
			height   = 2,
			showText = false,
		},
		name = {
			colorMode = 'class',
			truncate  = 6,
			fontSize  = C.Font.sizeSmall,
		},
		range    = { outsideAlpha = 0.4 },
		statusIcons = {
			role       = true,
			leader     = true,
			readyCheck = true,
			raidIcon   = true,
			combat     = false,
		},
		raidDebuffs  = { iconSize = 16, filterMode = C.DebuffFilterMode.RAID, minPriority = C.DebuffPriority.NORMAL },
		dispellable  = { glowType = C.GlowType.PIXEL },
		privateAuras = { iconSize = 14 },
		statusText         = true,
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

local function arenaEnemyBase()
	return {
		width  = 150,
		height = 30,
		health = {
			colorMode      = 'class',
			smooth         = true,
			showText       = true,
			textFormat     = 'current',
			healPrediction = false,
		},
		power = {
			height   = 2,
			showText = false,
		},
		name = {
			colorMode = 'class',
			truncate  = 10,
			fontSize  = C.Font.sizeSmall,
		},
		castbar = {
			height   = 14,
			showIcon = true,
			showText = true,
			showTime = true,
		},
		range    = { outsideAlpha = 0.4 },
		statusIcons = {
			role       = false,
			leader     = false,
			readyCheck = false,
			raidIcon   = true,
			combat     = false,
		},
		debuffs      = { maxIcons = 4, iconSize = 14, growDirection = 'RIGHT' },
		dispellable  = { glowType = C.GlowType.PIXEL },
		statusText         = false,
		targetHighlight    = true,
		mouseoverHighlight = true,
	}
end

-- ============================================================
-- GetAll — returns table of 7 default layout configs
-- ============================================================

function F.LayoutDefaults.GetAll()
	-- --------------------------------------------------------
	-- Default Solo
	-- --------------------------------------------------------
	local solo = {
		isDefault   = true,
		unitConfigs = {
			player = playerBase(),
			target = targetBase(),
			targettarget = {
				width  = 120,
				height = 24,
				health = {
					colorMode      = 'class',
					smooth         = true,
					showText       = false,
					textFormat     = 'none',
					healPrediction = false,
				},
				power = { height = 2, showText = false },
				name  = { colorMode = 'class', truncate = 10, fontSize = C.Font.sizeSmall },
				range = { outsideAlpha = 0.4 },
				statusIcons = {
					role = false, leader = false, readyCheck = false, raidIcon = true, combat = false,
				},
				statusText         = false,
				targetHighlight    = true,
				mouseoverHighlight = true,
			},
			focus = {
				width  = 150,
				height = 30,
				health = {
					colorMode      = 'class',
					smooth         = true,
					showText       = false,
					textFormat     = 'none',
					healPrediction = false,
				},
				power   = { height = 2, showText = false },
				name    = { colorMode = 'class', truncate = 10, fontSize = C.Font.sizeSmall },
				castbar = { height = 14, showIcon = true, showText = true, showTime = true },
				range   = { outsideAlpha = 0.4 },
				statusIcons = {
					role = false, leader = false, readyCheck = false, raidIcon = true, combat = false,
				},
				buffs   = { maxIcons = 6, iconSize = 14, growDirection = 'RIGHT' },
				debuffs = { maxIcons = 6, iconSize = 14, growDirection = 'RIGHT' },
				statusText         = false,
				targetHighlight    = true,
				mouseoverHighlight = true,
			},
			pet = {
				width  = 120,
				height = 24,
				health = {
					colorMode      = 'class',
					smooth         = true,
					showText       = false,
					textFormat     = 'none',
					healPrediction = false,
				},
				power  = { height = 2, showText = false },
				name   = { colorMode = 'class', truncate = 10, fontSize = C.Font.sizeSmall },
				range  = { outsideAlpha = 0.4 },
				statusIcons = {
					role = false, leader = false, readyCheck = false, raidIcon = false, combat = false,
				},
				statusText         = false,
				targetHighlight    = false,
				mouseoverHighlight = true,
			},
		},
		positions = {},
	}

	-- --------------------------------------------------------
	-- Default Party
	-- --------------------------------------------------------
	local party = {
		isDefault   = true,
		unitConfigs = {
			player = playerBase(),
			target = targetBase(),
			party  = partyBase(),
			pet    = {
				width  = 72,
				height = 18,
				health = {
					colorMode      = 'class',
					smooth         = true,
					showText       = false,
					textFormat     = 'none',
					healPrediction = false,
				},
				power  = { height = 2, showText = false },
				name   = { colorMode = 'class', truncate = 6, fontSize = C.Font.sizeSmall },
				range  = { outsideAlpha = 0.4 },
				statusIcons = {
					role = false, leader = false, readyCheck = false, raidIcon = false, combat = false,
				},
				statusText         = false,
				targetHighlight    = false,
				mouseoverHighlight = true,
			},
		},
		positions = {},
	}

	-- --------------------------------------------------------
	-- Default Raid
	-- --------------------------------------------------------
	local raid = {
		isDefault   = true,
		unitConfigs = {
			player = playerBase(),
			target = targetBase(),
			raid   = raidBase(),
		},
		positions = {},
	}

	-- --------------------------------------------------------
	-- Default Mythic Raid (tuned for 20 players — encounter debuffs only)
	-- --------------------------------------------------------
	local mythicRaid = {
		isDefault   = true,
		unitConfigs = {
			player = playerBase(),
			target = targetBase(),
			raid   = (function()
				local r = raidBase()
				r.raidDebuffs.filterMode   = C.DebuffFilterMode.ENCOUNTER_ONLY
				r.raidDebuffs.minPriority  = C.DebuffPriority.IMPORTANT
				return r
			end)(),
			boss = {
				width  = 150,
				height = 30,
				health = {
					colorMode      = 'class',
					smooth         = true,
					showText       = true,
					textFormat     = 'current',
					healPrediction = false,
				},
				power   = { height = 2, showText = false },
				name    = { colorMode = 'class', truncate = 12, fontSize = C.Font.sizeSmall },
				castbar = { height = 14, showIcon = true, showText = true, showTime = true },
				range   = { outsideAlpha = 0.4 },
				statusIcons = {
					role = false, leader = false, readyCheck = false, raidIcon = true, combat = false,
				},
				buffs   = { maxIcons = 6, iconSize = 14, growDirection = 'RIGHT' },
				debuffs = { maxIcons = 4, iconSize = 14, growDirection = 'RIGHT' },
				statusText         = false,
				targetHighlight    = true,
				mouseoverHighlight = true,
			},
		},
		positions = {},
	}

	-- --------------------------------------------------------
	-- Default World Raid (flexible, minimal indicators)
	-- --------------------------------------------------------
	local worldRaid = {
		isDefault   = true,
		unitConfigs = {
			player = playerBase(),
			target = targetBase(),
			raid   = (function()
				local r = raidBase()
				-- World raid: keep raid debuffs but drop encounter filter
				r.raidDebuffs.filterMode  = C.DebuffFilterMode.RAID
				r.raidDebuffs.minPriority = C.DebuffPriority.LOW
				-- Slightly wider to accommodate mixed content
				r.width = 80
				return r
			end)(),
		},
		positions = {},
	}

	-- --------------------------------------------------------
	-- Default Battleground (compact, PvP indicators)
	-- --------------------------------------------------------
	local battleground = {
		isDefault   = true,
		unitConfigs = {
			player = (function()
				local p = playerBase()
				-- Remove portrait to save space in PvP
				p.portrait = nil
				return p
			end)(),
			target = (function()
				local t = targetBase()
				t.portrait = nil
				t.debuffs  = { maxIcons = 4, iconSize = 14, growDirection = 'RIGHT' }
				return t
			end)(),
			party = (function()
				local p = partyBase()
				-- BG: skip raid debuffs, show dispellable only
				p.raidDebuffs = nil
				p.dispellable = { glowType = C.GlowType.PIXEL }
				p.width  = 100
				return p
			end)(),
		},
		positions = {},
	}

	-- --------------------------------------------------------
	-- Default Arena (enemy arena frames + party, CC tracking)
	-- --------------------------------------------------------
	local arena = {
		isDefault   = true,
		unitConfigs = {
			player = (function()
				local p = playerBase()
				p.portrait = nil
				return p
			end)(),
			target = (function()
				local t = targetBase()
				t.portrait = nil
				return t
			end)(),
			party = (function()
				local p = partyBase()
				p.raidDebuffs = nil
				p.dispellable = { glowType = C.GlowType.PIXEL }
				return p
			end)(),
			arena = arenaEnemyBase(),
		},
		positions = {},
	}

	return {
		['Default Solo']        = solo,
		['Default Party']       = party,
		['Default Raid']        = raid,
		['Default Mythic Raid'] = mythicRaid,
		['Default World Raid']  = worldRaid,
		['Default Battleground'] = battleground,
		['Default Arena']       = arena,
	}
end

-- ============================================================
-- EnsureDefaults
-- Populates FramedDB.layouts with any missing default layouts.
-- Existing user layouts are never overwritten.
-- ============================================================

function F.LayoutDefaults.EnsureDefaults()
	if(not FramedDB) then return end
	if(not FramedDB.layouts) then
		FramedDB.layouts = {}
	end

	local defaults = F.LayoutDefaults.GetAll()
	for name, layout in next, defaults do
		if(FramedDB.layouts[name] == nil) then
			FramedDB.layouts[name] = deepCopy(layout)
		end
	end
end
