local addonName, Framed = ...
local F = Framed

-- ============================================================
-- Media paths
-- ============================================================

local MEDIA_PATH   = [[Interface\AddOns\Framed\Media\]]
local ICON_PATH    = MEDIA_PATH .. [[Icons\]]
local TEXTURE_PATH = MEDIA_PATH .. [[Textures\]]
local FONT_PATH    = MEDIA_PATH .. [[Fonts\]]

F.Media = {}

--- Get full path to a media icon.
--- @param name string Icon filename (without extension)
--- @return string
function F.Media.GetIcon(name)
	return ICON_PATH .. name
end

--- Get full path to a media texture.
--- @param name string Texture filename (without extension)
--- @return string
function F.Media.GetTexture(name)
	return TEXTURE_PATH .. name
end

--- Get full path to a media font.
--- @param name string Font filename (with extension)
--- @return string
function F.Media.GetFont(name)
	return FONT_PATH .. name
end

--- Default font bundled with Framed (ElvUI-proof).
F.Media.DefaultFont = FONT_PATH .. 'Expressway.ttf'

--- Get the user's configured font path, falling back to the bundled default.
--- This should be used everywhere instead of STANDARD_TEXT_FONT.
--- @return string
function F.Media.GetActiveFont()
	if(F.Config) then
		local name = F.Config:Get('general.font')
		if(name) then
			local LSM = LibStub and LibStub('LibSharedMedia-3.0', true)
			if(LSM) then
				local path = LSM:Fetch('font', name)
				if(path) then return path end
			end
		end
	end
	return F.Media.DefaultFont
end

--- Plain white 1x1 texture for statusbars.
--- @return string
function F.Media.GetPlainTexture()
	return TEXTURE_PATH .. 'White'
end

--- Get the user's configured statusbar texture path, falling back to plain white.
--- @return string
function F.Media.GetActiveBarTexture()
	if(F.Config) then
		local name = F.Config:Get('general.barTexture')
		if(name) then
			local LSM = LibStub and LibStub('LibSharedMedia-3.0', true)
			if(LSM) then
				local path = LSM:Fetch('statusbar', name)
				if(path) then return path end
			end
		end
	end
	return [[Interface\BUTTONS\WHITE8x8]]
end

-- ============================================================
-- LibSharedMedia registration
-- ============================================================

local LSM = LibStub and LibStub('LibSharedMedia-3.0', true)
if(LSM) then
	-- Fonts
	LSM:Register('font', 'Expressway',              F.Media.GetFont('Expressway.ttf'),              255)
	LSM:Register('font', 'Accidental Presidency',   F.Media.GetFont('Accidental_Presidency.ttf'),   255)
	LSM:Register('font', 'Google Sans',              F.Media.GetFont('GoogleSans-Regular.ttf'),       255)
	LSM:Register('font', 'Google Sans Medium',       F.Media.GetFont('GoogleSans-Medium.ttf'),        255)
	LSM:Register('font', 'Google Sans Bold',          F.Media.GetFont('GoogleSans-Bold.ttf'),          255)
	LSM:Register('font', 'Lato',                     F.Media.GetFont('Lato-Regular.ttf'),             255)
	LSM:Register('font', 'Lato Medium',              F.Media.GetFont('Lato-Medium.ttf'),              255)
	LSM:Register('font', 'Lato Bold',                F.Media.GetFont('Lato-Bold.ttf'),                255)
	LSM:Register('font', 'Miranda Sans',             F.Media.GetFont('MirandaSans-Regular.ttf'),      255)
	LSM:Register('font', 'Miranda Sans Medium',      F.Media.GetFont('MirandaSans-Medium.ttf'),       255)
	LSM:Register('font', 'Miranda Sans Bold',        F.Media.GetFont('MirandaSans-Bold.ttf'),         255)
	LSM:Register('font', 'Montserrat',               F.Media.GetFont('Montserrat-Regular.ttf'),       255)
	LSM:Register('font', 'Montserrat Medium',        F.Media.GetFont('Montserrat-Medium.ttf'),        255)
	LSM:Register('font', 'Montserrat Bold',           F.Media.GetFont('Montserrat-Bold.ttf'),          255)
	LSM:Register('font', 'Noto Sans',                F.Media.GetFont('NotoSans-Regular.ttf'),         255)
	LSM:Register('font', 'Noto Sans Medium',         F.Media.GetFont('NotoSans-Medium.ttf'),          255)
	LSM:Register('font', 'Noto Sans Bold',            F.Media.GetFont('NotoSans-Bold.ttf'),            255)
	LSM:Register('font', 'Open Sans',                F.Media.GetFont('OpenSans-Regular.ttf'),         255)
	LSM:Register('font', 'Open Sans SemiBold',       F.Media.GetFont('OpenSans-SemiBold.ttf'),        255)
	LSM:Register('font', 'Open Sans Bold',            F.Media.GetFont('OpenSans-Bold.ttf'),            255)
	LSM:Register('font', 'Roboto',                   F.Media.GetFont('Roboto-Regular.ttf'),           255)
	LSM:Register('font', 'Roboto Medium',            F.Media.GetFont('Roboto-Medium.ttf'),            255)
	LSM:Register('font', 'Roboto Bold',              F.Media.GetFont('Roboto-Bold.ttf'),              255)
	LSM:Register('font', 'Roboto Condensed',         F.Media.GetFont('RobotoCondensed-Regular.ttf'),  255)
	LSM:Register('font', 'Roboto Condensed Medium',  F.Media.GetFont('RobotoCondensed-Medium.ttf'),   255)
	LSM:Register('font', 'Roboto Condensed Bold',    F.Media.GetFont('RobotoCondensed-Bold.ttf'),     255)
	LSM:Register('font', 'Space Grotesk Medium',     F.Media.GetFont('SpaceGrotesk-Medium.ttf'),      255)

	-- Statusbar textures
	LSM:Register('statusbar', 'Framed Plain',             F.Media.GetPlainTexture())
	LSM:Register('statusbar', 'Framed Plain Half Top',    F.Media.GetTexture('White_Half_Top'))
	LSM:Register('statusbar', 'Framed Plain Half Bottom', F.Media.GetTexture('White_Half_Bottom'))
	LSM:Register('statusbar', 'Framed',                   F.Media.GetTexture('Bar_AF'))
	LSM:Register('statusbar', 'Framed Underline',         F.Media.GetTexture('Bar_Underline'))
	LSM:Register('statusbar', 'pfUI-S',                   F.Media.GetTexture('Bar_pfUI_S'))
	LSM:Register('statusbar', 'pfUI-U',                   F.Media.GetTexture('Bar_pfUI_U'))
end
