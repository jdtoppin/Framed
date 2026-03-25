local addonName, Framed = ...
local F = Framed
local C = F.Constants

F.LayoutDefaults = {}

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
		buffs = {
			enabled    = true,
			indicators = {},
		},
		debuffs = {
			enabled              = true,
			iconSize             = 14,
			bigIconSize          = 18,
			maxDisplayed         = 6,
			showDuration         = true,
			showAnimation        = true,
			orientation          = 'RIGHT',
			anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
			frameLevel           = 5,
			onlyDispellableByMe  = false,
			stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
			                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                         color = { 1, 1, 1, 1 } },
			durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
		},
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
		buffs = {
			enabled    = true,
			indicators = {},
		},
		debuffs = {
			enabled              = true,
			iconSize             = 14,
			bigIconSize          = 18,
			maxDisplayed         = 6,
			showDuration         = true,
			showAnimation        = true,
			orientation          = 'RIGHT',
			anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
			frameLevel           = 5,
			onlyDispellableByMe  = false,
			stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
			                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                         color = { 1, 1, 1, 1 } },
			durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
		},
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
		buffs = {
			enabled    = true,
			indicators = {},
		},
		debuffs = {
			enabled              = true,
			iconSize             = 16,
			bigIconSize          = 22,
			maxDisplayed         = 3,
			showDuration         = true,
			showAnimation        = true,
			orientation          = 'RIGHT',
			anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
			frameLevel           = 5,
			onlyDispellableByMe  = false,
			stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
			                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                         color = { 1, 1, 1, 1 } },
			durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		raidDebuffs = {
			enabled        = true,
			iconSize       = 16,
			bigIconSize    = 20,
			maxDisplayed   = 1,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel     = 6,
			stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
			                   anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                   color = { 1, 1, 1, 1 } },
			durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		targetedSpells = {
			enabled       = true,
			displayMode   = 'Both',
			iconSize      = 16,
			borderColor   = { 1, 0, 0, 1 },
			maxDisplayed  = 1,
			anchor        = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel    = 8,
			glow          = {
				type      = 'Pixel',
				color     = { 1, 0, 0, 1 },
				lines     = 8,
				frequency = 0.25,
				length    = 4,
				thickness = 2,
			},
		},
		dispellable = {
			enabled              = true,
			onlyDispellableByMe  = false,
			highlightType        = 'gradient_half',
			iconSize             = 16,
			anchor               = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel           = 7,
		},
		externals = {
			enabled        = true,
			iconSize       = 16,
			maxDisplayed   = 2,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'TOPRIGHT', nil, 'TOPRIGHT', -2, -2 },
			frameLevel     = 5,
			stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
			                   anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                   color = { 1, 1, 1, 1 } },
			durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		defensives = {
			enabled        = true,
			iconSize       = 16,
			maxDisplayed   = 2,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 },
			frameLevel     = 5,
			stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
			                   anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                   color = { 1, 1, 1, 1 } },
			durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
		},
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
		buffs = {
			enabled    = true,
			indicators = {},
		},
		debuffs = {
			enabled              = true,
			iconSize             = 14,
			bigIconSize          = 18,
			maxDisplayed         = 1,
			showDuration         = true,
			showAnimation        = true,
			orientation          = 'RIGHT',
			anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
			frameLevel           = 5,
			onlyDispellableByMe  = false,
			stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
			                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                         color = { 1, 1, 1, 1 } },
			durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		raidDebuffs = {
			enabled        = true,
			iconSize       = 14,
			bigIconSize    = 18,
			maxDisplayed   = 1,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel     = 6,
			stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
			                   anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                   color = { 1, 1, 1, 1 } },
			durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		targetedSpells = {
			enabled       = true,
			displayMode   = 'Both',
			iconSize      = 14,
			borderColor   = { 1, 0, 0, 1 },
			maxDisplayed  = 1,
			anchor        = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel    = 8,
			glow          = {
				type      = 'Pixel',
				color     = { 1, 0, 0, 1 },
				lines     = 8,
				frequency = 0.25,
				length    = 4,
				thickness = 2,
			},
		},
		dispellable = {
			enabled              = true,
			onlyDispellableByMe  = false,
			highlightType        = 'gradient_half',
			iconSize             = 14,
			anchor               = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel           = 7,
		},
		externals = {
			enabled        = true,
			iconSize       = 14,
			maxDisplayed   = 1,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'TOPRIGHT', nil, 'TOPRIGHT', -2, -2 },
			frameLevel     = 5,
			stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
			                   anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                   color = { 1, 1, 1, 1 } },
			durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		defensives = {
			enabled        = true,
			iconSize       = 14,
			maxDisplayed   = 1,
			showDuration   = true,
			showAnimation  = true,
			orientation    = 'RIGHT',
			anchor         = { 'TOPLEFT', nil, 'TOPLEFT', 2, -2 },
			frameLevel     = 5,
			stackFont      = { size = 10, outline = 'OUTLINE', shadow = false,
			                   anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                   color = { 1, 1, 1, 1 } },
			durationFont   = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		missingBuffs = { iconSize = 12 },
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
		debuffs = {
			enabled              = true,
			iconSize             = 14,
			bigIconSize          = 18,
			maxDisplayed         = 4,
			showDuration         = true,
			showAnimation        = true,
			orientation          = 'RIGHT',
			anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
			frameLevel           = 5,
			onlyDispellableByMe  = false,
			stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
			                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
			                         color = { 1, 1, 1, 1 } },
			durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
		},
		dispellable = {
			enabled              = true,
			onlyDispellableByMe  = false,
			highlightType        = 'gradient_half',
			iconSize             = 14,
			anchor               = { 'CENTER', nil, 'CENTER', 0, 0 },
			frameLevel           = 7,
		},
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
				buffs = {
					enabled    = true,
					indicators = {},
				},
				debuffs = {
					enabled              = true,
					iconSize             = 14,
					bigIconSize          = 18,
					maxDisplayed         = 6,
					showDuration         = true,
					showAnimation        = true,
					orientation          = 'RIGHT',
					anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
					frameLevel           = 5,
					onlyDispellableByMe  = false,
					stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
					                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
					                         color = { 1, 1, 1, 1 } },
					durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
				},
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
				-- Mythic raid: encounter debuffs only (filter applied at element level)
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
				buffs = {
					enabled    = true,
					indicators = {},
				},
				debuffs = {
					enabled              = true,
					iconSize             = 14,
					bigIconSize          = 18,
					maxDisplayed         = 4,
					showDuration         = true,
					showAnimation        = true,
					orientation          = 'RIGHT',
					anchor               = { 'BOTTOMLEFT', nil, 'BOTTOMLEFT', 2, 2 },
					frameLevel           = 5,
					onlyDispellableByMe  = false,
					stackFont            = { size = 10, outline = 'OUTLINE', shadow = false,
					                         anchor = 'BOTTOMRIGHT', xOffset = 0, yOffset = 0,
					                         color = { 1, 1, 1, 1 } },
					durationFont         = { size = 10, outline = 'OUTLINE', shadow = false },
				},
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
				-- World raid: slightly wider to accommodate mixed content
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
				t.debuffs.maxDisplayed = 4
				return t
			end)(),
			party = (function()
				local p = partyBase()
				-- BG: disable raid debuffs, keep dispellable highlight
				p.raidDebuffs.enabled = false
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
				-- Arena: disable raid debuffs, keep dispellable highlight
				p.raidDebuffs.enabled = false
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
			FramedDB.layouts[name] = F.DeepCopy(layout)
		end
	end
end
