local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Name = {}

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

	-- Native C-level auto-ellipsis on overflow. Avoid Lua-side string
	-- truncation here: UnitName can be identity-restricted, and native
	-- bounded FontString rendering keeps restricted text out of Lua logic.
	--
	-- Bounded width is skipped in attach-to-name mode: StyleBuilder anchors
	-- Health.text to Name's RIGHT edge and Health.PostUpdate shifts the
	-- pair left to center them. A fixed-width Name FontString with default
	-- JustifyH='CENTER' renders as a wide box with the name parked in the
	-- middle, which puts the Health text at the far-right frame edge and
	-- defeats the centering shift. SetWidth(0) releases the constraint so
	-- the FontString tracks its text content width.
	nameText:SetWordWrap(false)
	local function updateNameWidth()
		local w = self:GetWidth() or 0
		if(w <= 8) then return end
		if(self.Health and self.Health._attachedToName) then
			nameText:SetWidth(0)
		else
			nameText:SetWidth(w - 8)
		end
	end
	self._updateNameWidth = updateNameWidth
	updateNameWidth()
	self:HookScript('OnSizeChanged', updateNameWidth)

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
	-- PostUpdate: apply class color.
	-- oUF calls this whenever the unit's info refreshes.
	-- --------------------------------------------------------

	-- Store config on nameText so the closure captures it cleanly
	nameText._config = config

	-- Register a post-update hook on the frame's OnAttributeChanged
	-- to recolor and truncate whenever the unit changes.
	-- We also hook UpdateAllElements via oUF's PostUpdateElement if available.

	local function ApplyNameUpdate(unit)
		if(not unit) then return end

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
