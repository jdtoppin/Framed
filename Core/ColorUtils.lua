local addonName, Framed = ...
local F = Framed

-- ============================================================
-- Color conversion utilities
-- Ported from AbstractFramework (GPL v3) by enderneko
-- ============================================================

local ColorUtils = {}
F.ColorUtils = ColorUtils

local floor = math.floor
local abs = math.abs
local max = math.max
local min = math.min
local format = string.format
local Round = Round or function(v) return floor(v + 0.5) end

-- ============================================================
-- RGB 0-1 <-> 0-255
-- ============================================================

--- Convert RGBA from 0-255 range to 0-1 range.
--- @param r number [0, 255]
--- @param g number [0, 255]
--- @param b number [0, 255]
--- @param a? number [0, 255]
--- @return number r [0, 1]
--- @return number g [0, 1]
--- @return number b [0, 1]
--- @return number? a [0, 1]
function ColorUtils.ToNormalized(r, g, b, a)
	r = r / 255
	g = g / 255
	b = b / 255
	a = a and (a / 255)
	return r, g, b, a
end

--- Convert RGBA from 0-1 range to 0-255 range.
--- @param r number [0, 1]
--- @param g number [0, 1]
--- @param b number [0, 1]
--- @param a? number [0, 1]
--- @return number r [0, 255]
--- @return number g [0, 255]
--- @return number b [0, 255]
--- @return number? a [0, 255]
function ColorUtils.To256(r, g, b, a)
	r = Round(r * 255)
	g = Round(g * 255)
	b = Round(b * 255)
	a = a and Round(a * 255)
	return r, g, b, a
end

-- ============================================================
-- Hex conversions
-- ============================================================

--- Convert RGB 0-255 to hex string.
--- @param r number [0, 255]
--- @param g number [0, 255]
--- @param b number [0, 255]
--- @return string hex rrggbb
function ColorUtils.RGB256ToHex(r, g, b)
	return format('%02x%02x%02x', r, g, b)
end

--- Convert RGB 0-1 to hex string.
--- @param r number [0, 1]
--- @param g number [0, 1]
--- @param b number [0, 1]
--- @return string hex rrggbb
function ColorUtils.RGBToHex(r, g, b)
	return ColorUtils.RGB256ToHex(Round(r * 255), Round(g * 255), Round(b * 255))
end

--- Convert hex string to RGB 0-255.
--- @param hex string rrggbb or #rrggbb
--- @return number r [0, 255]
--- @return number g [0, 255]
--- @return number b [0, 255]
function ColorUtils.HexToRGB256(hex)
	hex = hex:gsub('#', '')
	return tonumber('0x' .. hex:sub(1, 2)),
		tonumber('0x' .. hex:sub(3, 4)),
		tonumber('0x' .. hex:sub(5, 6))
end

--- Convert hex string to RGB 0-1.
--- @param hex string rrggbb or #rrggbb
--- @return number r [0, 1]
--- @return number g [0, 1]
--- @return number b [0, 1]
function ColorUtils.HexToRGB(hex)
	return ColorUtils.ToNormalized(ColorUtils.HexToRGB256(hex))
end

-- ============================================================
-- HSB (Hue, Saturation, Brightness) conversions
-- From ColorPickerAdvanced by Feyawen-Llane
-- ============================================================

--- Convert RGB 0-1 to HSB.
--- @param r number [0, 1]
--- @param g number [0, 1]
--- @param b number [0, 1]
--- @return number h [0, 360] hue
--- @return number s [0, 1] saturation
--- @return number v [0, 1] brightness/value
function ColorUtils.RGBToHSB(r, g, b)
	local colorMax = max(r, g, b)
	local colorMin = min(r, g, b)
	local delta = colorMax - colorMin
	local H, S, B

	-- WoW Lua floating point workaround
	colorMax = tonumber(format('%f', colorMax))
	r = tonumber(format('%f', r))
	g = tonumber(format('%f', g))
	b = tonumber(format('%f', b))

	if(delta > 0) then
		if(colorMax == r) then
			H = 60 * (((g - b) / delta) % 6)
		elseif(colorMax == g) then
			H = 60 * (((b - r) / delta) + 2)
		elseif(colorMax == b) then
			H = 60 * (((r - g) / delta) + 4)
		end

		if(colorMax > 0) then
			S = delta / colorMax
		else
			S = 0
		end

		B = colorMax
	else
		H = 0
		S = 0
		B = colorMax
	end

	if(H < 0) then
		H = H + 360
	end

	return H, S, B
end

--- Convert HSB to RGB 0-1.
--- @param h number [0, 360] hue
--- @param s number [0, 1] saturation
--- @param b number [0, 1] brightness/value
--- @return number r [0, 1]
--- @return number g [0, 1]
--- @return number b [0, 1]
function ColorUtils.HSBToRGB(h, s, b)
	local chroma = b * s
	local prime = (h / 60) % 6
	local X = chroma * (1 - abs((prime % 2) - 1))
	local M = b - chroma
	local R, G, B

	if(prime < 1) then
		R, G, B = chroma, X, 0
	elseif(prime < 2) then
		R, G, B = X, chroma, 0
	elseif(prime < 3) then
		R, G, B = 0, chroma, X
	elseif(prime < 4) then
		R, G, B = 0, X, chroma
	elseif(prime < 5) then
		R, G, B = X, 0, chroma
	elseif(prime < 6) then
		R, G, B = chroma, 0, X
	else
		R, G, B = 0, 0, 0
	end

	R = tonumber(format('%.3f', R + M))
	G = tonumber(format('%.3f', G + M))
	B = tonumber(format('%.3f', B + M))

	return R, G, B
end
