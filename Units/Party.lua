local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local Widgets = F.Widgets
local C = F.Constants

F.Units = F.Units or {}
F.Units.Party = {}

-- ============================================================
-- Style
-- ============================================================

local function Style(self, unit)
	local config = F.StyleBuilder.GetConfig('party')
	F.StyleBuilder.Apply(self, unit, config, 'party')
end

-- ============================================================
-- Pet Style
-- Uses the PARTY frame's width/height so it matches the owner.
-- ============================================================

local function PetStyle(self, unit)
	local config = F.StyleBuilder.GetConfig('party')
	local petCfg = F.Units.Party.GetPetConfig()
	local w = config.width
	local h = config.height

	-- Store unit type BEFORE Health.Setup (used inside for NPC detection)
	self._framedUnitType = 'partypet'

	self:RegisterForClicks('AnyUp')
	Widgets.SetSize(self, w, h)

	-- Unit tooltip on hover
	self:SetScript('OnEnter', function(frame)
		if(F.Config:Get('general.tooltipEnabled') == false) then return end
		if(F.Config:Get('general.tooltipHideInCombat') and InCombatLockdown()) then return end
		local mode = F.Config:Get('general.tooltipMode') or 'frame'
		local anchor = F.Config:Get('general.tooltipAnchor') or 'RIGHT'
		local offX = F.Config:Get('general.tooltipOffsetX') or 0
		local offY = F.Config:Get('general.tooltipOffsetY') or 0
		if(mode == 'cursor') then
			GameTooltip:SetOwner(frame, 'ANCHOR_CURSOR')
		elseif(mode == 'screen') then
			GameTooltip:SetOwner(frame, 'ANCHOR_NONE')
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint(anchor, UIParent, anchor, offX, offY)
		else
			GameTooltip:SetOwner(frame, 'ANCHOR_' .. anchor, offX, offY)
		end
		GameTooltip:SetUnit(frame.unit)
		GameTooltip:Show()
	end)
	self:SetScript('OnLeave', function()
		if(not GameTooltip:IsForbidden()) then
			GameTooltip:Hide()
		end
	end)

	-- Dark background
	local bg = self:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(self)
	bg:SetTexture([[Interface\BUTTONS\WHITE8x8]])
	local bgC = C.Colors.background
	bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4])

	-- Health bar fills the whole frame (same path as regular party frames)
	local healthCfg = {
		colorMode      = 'class',
		smooth         = true,
		showText       = petCfg.showHealthText ~= false,
		textFormat     = petCfg.healthTextFormat,
		fontSize       = petCfg.healthTextFontSize,
		textColorMode  = petCfg.healthTextColor,
		textAnchor     = petCfg.healthTextAnchor or 'CENTER',
		textAnchorX    = petCfg.healthTextOffsetX,
		textAnchorY    = petCfg.healthTextOffsetY,
		outline        = petCfg.healthTextOutline,
		shadow         = petCfg.healthTextShadow ~= false,
		attachedToName = false,
	}
	F.Elements.Health.Setup(self, w, h, healthCfg)

	-- Name at top of frame
	if(petCfg.showName ~= false) then
		local nameOverlay = CreateFrame('Frame', nil, self)
		nameOverlay:SetAllPoints(self)
		nameOverlay:SetFrameLevel(self:GetFrameLevel() + 5)
		local nameAnchor  = petCfg.nameAnchor or 'TOP'
		local nameOutline = petCfg.nameOutline or ''
		local nameShadow  = petCfg.nameShadow ~= false
		local name = Widgets.CreateFontString(nameOverlay, petCfg.nameFontSize or C.Font.sizeSmall, C.Colors.textActive, nameOutline, nameShadow)
		name:SetPoint(nameAnchor, self, nameAnchor, petCfg.nameOffsetX or 0, petCfg.nameOffsetY or -2)
		self:Tag(name, '[name]')
		self.Name = name
	end


	-- Aura elements (share party aura config)
	local buffsConfig = F.StyleBuilder.GetAuraConfig('party', 'buffs')
	if(buffsConfig and buffsConfig.enabled and F.Elements.Buffs) then
		F.Elements.Buffs.Setup(self, buffsConfig)
	end

	local debuffsConfig = F.StyleBuilder.GetAuraConfig('party', 'debuffs')
	if(debuffsConfig and debuffsConfig.enabled and F.Elements.Debuffs) then
		F.Elements.Debuffs.Setup(self, debuffsConfig)
	end

	-- Target highlight
	local thColor = F.Config:Get('general.targetHighlightColor')
	local thWidth = F.Config:Get('general.targetHighlightWidth')
	F.Elements.TargetHighlight.Setup(self, { color = thColor, thickness = thWidth })

	-- Mouseover highlight
	local moColor = F.Config:Get('general.mouseoverHighlightColor')
	local moWidth = F.Config:Get('general.mouseoverHighlightWidth')
	F.Elements.MouseoverHighlight.Setup(self, { color = moColor, thickness = moWidth })

	-- Store unit type for live config
	self._framedUnitType = 'partypet'
end

-- ============================================================
-- Get pet config from active preset
-- ============================================================

function F.Units.Party.GetPetConfig()
	-- partyPets config only lives on presets that have party frames.
	-- Check the current preset first, then fall back to 'Party'.
	local presetName = F.AutoSwitch.GetCurrentPreset()
	local cfg = F.Config:Get('presets.' .. presetName .. '.partyPets')
	if(not cfg) then
		cfg = F.Config:Get('presets.Party.partyPets')
	end
	return cfg or { enabled = true, spacing = 2 }
end

-- ============================================================
-- Compute pet anchor relative to owner frame
-- ============================================================

local function computePetAnchorToOwner(orient, anchor, gap)
	if(orient == 'vertical') then
		-- Vertical: pets go beside owners (left or right)
		local onLeft = (anchor == 'TOPRIGHT' or anchor == 'BOTTOMRIGHT')
		if(onLeft) then
			return 'RIGHT', 'LEFT', -gap, 0
		else
			return 'LEFT', 'RIGHT', gap, 0
		end
	else
		-- Horizontal: pets go above or below owners
		local above = (anchor == 'BOTTOMLEFT' or anchor == 'BOTTOMRIGHT')
		if(above) then
			return 'BOTTOM', 'TOP', 0, gap
		else
			return 'TOP', 'BOTTOM', 0, -gap
		end
	end
end

-- ============================================================
-- Spawn
-- ============================================================

function F.Units.Party.Spawn()
	oUF:RegisterStyle('FramedParty', Style)
	oUF:SetActiveStyle('FramedParty')

	-- Read layout from saved config so spawn matches user settings
	local config = F.StyleBuilder.GetConfig('party')
	local orient  = config.orientation
	local anchor  = config.anchorPoint
	local spacing = config.spacing

	local point, xOff, yOff, colAnchor
	if(orient == 'vertical') then
		local goDown = (anchor == 'TOPLEFT' or anchor == 'TOPRIGHT')
		point     = goDown and 'TOP' or 'BOTTOM'
		yOff      = goDown and -spacing or spacing
		xOff      = 0
		colAnchor = (anchor == 'TOPLEFT' or anchor == 'BOTTOMLEFT') and 'LEFT' or 'RIGHT'
	else
		local goRight = (anchor == 'TOPLEFT' or anchor == 'BOTTOMLEFT')
		point     = goRight and 'LEFT' or 'RIGHT'
		xOff      = goRight and spacing or -spacing
		yOff      = 0
		colAnchor = (anchor == 'TOPLEFT' or anchor == 'TOPRIGHT') and 'TOP' or 'BOTTOM'
	end

	local header = oUF:SpawnHeader(
		'FramedPartyHeader',
		nil,
		'showParty', true,
		'showPlayer', true,
		'showSolo', false,
		'point', point,
		'xOffset', xOff,
		'yOffset', yOff,
		'columnAnchorPoint', colAnchor,
		'maxColumns', 1,
		'unitsPerColumn', 5,
		'sortMethod', 'INDEX',
		'initial-width', config.width,
		'initial-height', config.height
	)

	-- Set visibility separately via the header mixin
	header:SetVisibility('party')
	local posX = config.position.x
	local posY = config.position.y
	header:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', posX, posY)
	Widgets.RegisterForUIScale(header)

	F.Units.Party.header = header

	-- ── Individual party pet frames ───────────────────────────
	F.Units.Party.SpawnPetFrames()
end

-- ============================================================
-- Spawn individual pet frames (partypet1 – partypet4)
-- Each is an oUF:Spawn with RegisterUnitWatch for auto show/hide.
-- ============================================================

function F.Units.Party.SpawnPetFrames()
	if(F.Units.Party.petFrames) then return end

	local petCfg = F.Units.Party.GetPetConfig()

	oUF:RegisterStyle('FramedPartyPet', PetStyle)
	oUF:SetActiveStyle('FramedPartyPet')

	local frames = {}
	for i = 1, 4 do
		local petFrame = oUF:Spawn('partypet' .. i, 'FramedPartyPet' .. i)
		Widgets.RegisterForUIScale(petFrame)
		frames[i] = petFrame

		-- Hide if pets are disabled
		if(petCfg.enabled == false) then
			petFrame._petDisabled = true
			UnregisterUnitWatch(petFrame)
			petFrame:Hide()
		end
	end

	F.Units.Party.petFrames = frames

	-- Anchor pets to owners once the party header has created children.
	-- GROUP_ROSTER_UPDATE fires when party composition changes.
	F.Units.Party.AnchorPetFrames()

	F.EventBus:Register('GROUP_ROSTER_UPDATE', function()
		F.Units.Party.AnchorPetFrames()
	end, 'Party.PetAnchor')
end

-- ============================================================
-- Find the party header child that represents a given unit
-- ============================================================

local function findOwnerFrame(header, unitId)
	for i = 1, header:GetNumChildren() do
		local child = select(i, header:GetChildren())
		local childUnit = child:GetAttribute('unit')
		if(childUnit == unitId) then
			return child
		end
	end
	return nil
end

-- ============================================================
-- Anchor each pet frame to its owner's party frame
-- ============================================================

function F.Units.Party.AnchorPetFrames()
	local frames = F.Units.Party.petFrames
	local header = F.Units.Party.header
	if(not frames or not header) then return end

	local config  = F.StyleBuilder.GetConfig('party')
	local petCfg  = F.Units.Party.GetPetConfig()
	local orient  = config.orientation
	local anchor  = config.anchorPoint
	local gap     = petCfg.spacing

	local petPt, ownerPt, dx, dy = computePetAnchorToOwner(orient, anchor, gap)

	for i = 1, 4 do
		local petFrame = frames[i]
		local ownerFrame = findOwnerFrame(header, 'party' .. i)

		if(ownerFrame) then
			petFrame:ClearAllPoints()
			Widgets.SetPoint(petFrame, petPt, ownerFrame, ownerPt, dx, dy)
		end
	end
end

-- ============================================================
-- Enable / disable pet frames (live toggle)
-- ============================================================

function F.Units.Party.SetPetsEnabled(enabled)
	local frames = F.Units.Party.petFrames
	if(not frames) then return end

	for i = 1, 4 do
		local petFrame = frames[i]
		if(enabled) then
			petFrame._petDisabled = nil
			RegisterUnitWatch(petFrame)
		else
			petFrame._petDisabled = true
			UnregisterUnitWatch(petFrame)
			petFrame:Hide()
		end
	end
end
