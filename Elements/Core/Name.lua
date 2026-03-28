local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Name = {}

-- ============================================================
-- Name Truncation Helper
-- ============================================================

--- Truncate a UTF-8 string to maxChars codepoints, appending '...' if cut.
--- @param str string
--- @param maxChars number
--- @return string
local function TruncateUTF8(str, maxChars)
	if(not str) then return '' end
	local chars = 0
	local bytePos = 1
	local len = #str
	while(bytePos <= len and chars < maxChars) do
		local byte = str:byte(bytePos)
		if(byte < 128) then
			bytePos = bytePos + 1
		elseif(byte < 224) then
			bytePos = bytePos + 2
		elseif(byte < 240) then
			bytePos = bytePos + 3
		else
			bytePos = bytePos + 4
		end
		chars = chars + 1
	end
	if(bytePos <= len) then
		return str:sub(1, bytePos - 1) .. '...'
	end
	return str
end

-- ============================================================
-- Name Element Setup
-- ============================================================

--- Set up a name text element on a unit frame using oUF tags.
--- @param self Frame  The oUF unit frame
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.Name.Setup(self, config)

	-- --------------------------------------------------------
	-- Config defaults
	-- --------------------------------------------------------

	config = config or {}
	config.colorMode   = config.colorMode or 'class'       -- 'class', 'white', 'custom'
	config.customColor = config.customColor or {1, 1, 1}
	config.fontSize    = config.fontSize or C.Font.sizeNormal
	config.outline     = config.outline or ''               -- '', 'OUTLINE', 'MONOCHROME'
	config.shadow      = (config.shadow == nil) and true or config.shadow
	config.anchor      = config.anchor or {'CENTER', self, 'CENTER', 0, 0}

	-- --------------------------------------------------------
	-- Text overlay frame — sits above the health bar wrapper
	-- so that name text is not occluded by sub-frames.
	-- --------------------------------------------------------

	local overlay = self._textOverlay
	if(not overlay) then
		overlay = CreateFrame('Frame', nil, self)
		overlay:SetAllPoints(self)
		overlay:SetFrameLevel(self:GetFrameLevel() + 5)
		self._textOverlay = overlay
	end

	-- --------------------------------------------------------
	-- Font string
	-- --------------------------------------------------------

	local nameText = Widgets.CreateFontString(overlay, config.fontSize, C.Colors.textActive, config.outline, config.shadow)

	-- --------------------------------------------------------
	-- Positioning via anchor config
	-- anchor = {point, relativeTo, relativePoint, x, y}
	-- --------------------------------------------------------

	local anchor = config.anchor
	Widgets.SetPoint(nameText, anchor[1], anchor[2], anchor[3], anchor[4] or 0, anchor[5] or 0)

	-- Store anchor info for live config updates
	nameText._anchorPoint = anchor[1]
	nameText._anchorX     = anchor[4] or 0
	nameText._anchorY     = anchor[5] or 0

	-- --------------------------------------------------------
	-- Apply initial color for non-class modes
	-- (class color is applied in PostUpdate after unit is known)
	-- --------------------------------------------------------

	if(config.colorMode == 'white') then
		local tc = C.Colors.textActive
		nameText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
	elseif(config.colorMode == 'dark') then
		nameText:SetTextColor(0.25, 0.25, 0.25, 1)
	elseif(config.colorMode == 'custom') then
		local cc = config.customColor
		nameText:SetTextColor(cc[1], cc[2], cc[3], cc[4] or 1)
	end

	-- --------------------------------------------------------
	-- oUF tag: [name] auto-updates nameText on unit change.
	-- --------------------------------------------------------

	self:Tag(nameText, '[name]')

	-- --------------------------------------------------------
	-- PostUpdate: apply class color and truncation.
	-- oUF calls this whenever the unit's info refreshes.
	-- --------------------------------------------------------

	-- Store config on nameText so the closure captures it cleanly
	nameText._config = config

	-- Register a post-update hook on the frame's OnAttributeChanged
	-- to recolor and truncate whenever the unit changes.
	-- We also hook UpdateAllElements via oUF's PostUpdateElement if available.

	local function ApplyNameUpdate(unit)
		if(not unit) then return end

		-- Auto-truncate: fit name to available frame width
		local raw = nameText:GetText() or ''
		local availableWidth = (self:GetWidth() or 0) - 8  -- 4px padding each side
		nameText:SetText(raw)
		if(availableWidth > 0 and nameText:GetStringWidth() > availableWidth) then
			local len = #raw
			for i = len, 1, -1 do
				local truncated = TruncateUTF8(raw, i)
				nameText:SetText(truncated)
				if(nameText:GetStringWidth() <= availableWidth) then
					break
				end
			end
		end

		-- Class coloring
		if(config.colorMode == 'class') then
			local _, class = UnitClass(unit)
			if(class) then
				local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
				if(classColor) then
					nameText:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
				else
					-- Fallback: white if class color unavailable
					local tc = C.Colors.textActive
					nameText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
				end
			end
		end
	end

	-- Hook into the frame's OnAttributeChanged to catch unit changes
	self:HookScript('OnAttributeChanged', function(frame, name, value)
		if(name == 'unit' and value) then
			ApplyNameUpdate(value)
		end
	end)

	-- Also hook oUF's PostUpdate cycle through a custom element callback.
	-- oUF fires PostUpdateElement for custom registered tags; we attach
	-- our refresh to the frame's existing UpdateAllElements path.
	if(self.PostUpdateElement) then
		hooksecurefunc(self, 'PostUpdateElement', function(frame, element)
			if(element == nameText) then
				local unit = frame:GetAttribute('unit')
				ApplyNameUpdate(unit)
			end
		end)
	end

	-- --------------------------------------------------------
	-- Store reference — not a standard oUF element name;
	-- name display is driven by oUF tags rather than an element.
	-- --------------------------------------------------------

	self.Name = nameText
end
