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

-- ============================================================
-- LibSharedMedia registration
-- ============================================================

local LSM = LibStub and LibStub('LibSharedMedia-3.0', true)
if(LSM) then
	-- Fonts
	LSM:Register('font', 'Expressway',              F.Media.GetFont('Expressway.ttf'),              255)
	LSM:Register('font', 'Accidental Presidency',   F.Media.GetFont('Accidental_Presidency.ttf'),   255)

	-- Statusbar textures
	LSM:Register('statusbar', 'Framed Plain',             F.Media.GetPlainTexture())
	LSM:Register('statusbar', 'Framed Plain Half Top',    F.Media.GetTexture('White_Half_Top'))
	LSM:Register('statusbar', 'Framed Plain Half Bottom', F.Media.GetTexture('White_Half_Bottom'))
	LSM:Register('statusbar', 'Framed',                   F.Media.GetTexture('Bar_AF'))
	LSM:Register('statusbar', 'Framed Underline',         F.Media.GetTexture('Bar_Underline'))
	LSM:Register('statusbar', 'pfUI-S',                   F.Media.GetTexture('Bar_pfUI_S'))
	LSM:Register('statusbar', 'pfUI-U',                   F.Media.GetTexture('Bar_pfUI_U'))
end
