local addonName, Framed = ...

local Widgets = Framed.Widgets
local C = Framed.Constants

-- ============================================================
-- BorderedFrame
-- A backdrop-enabled container with pixel-perfect sizing.
-- Used as the base building block for all other containers.
-- ============================================================

--- Create a bordered frame with the standard Framed backdrop.
--- @param parent Frame Parent frame
--- @param width number Logical width
--- @param height number Logical height
--- @param bgColor? table {r, g, b, a} Background color (defaults to C.Colors.panel)
--- @param borderColor? table {r, g, b, a} Border color (defaults to C.Colors.border)
--- @return Frame
function Widgets.CreateBorderedFrame(parent, width, height, bgColor, borderColor)
	local frame = CreateFrame('Frame', nil, parent, 'BackdropTemplate')

	frame._bgColor = bgColor or C.Colors.panel
	frame._borderColor = borderColor or C.Colors.border

	Widgets.ApplyBackdrop(frame, frame._bgColor, frame._borderColor)
	Widgets.SetSize(frame, width, height)
	Widgets.ApplyBaseMixin(frame)

	return frame
end

-- ============================================================
-- HeaderedFrame
-- A movable bordered frame with a 24px drag-handle header bar
-- and a title FontString left-anchored in the header.
-- ============================================================

local HEADER_HEIGHT = 24

--- Create a bordered frame with a titled, draggable header bar.
--- @param parent Frame Parent frame
--- @param title string Header title text
--- @param width number Logical width
--- @param height number Logical height
--- @return Frame frame, Frame headerFrame, FontString titleText
function Widgets.CreateHeaderedFrame(parent, title, width, height)
	local frame = Widgets.CreateBorderedFrame(parent, width, height)
	frame:SetFrameStrata('HIGH')
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)

	-- Header bar sits at the top of the frame, full width, fixed height
	local header = Widgets.CreateBorderedFrame(frame, width, HEADER_HEIGHT, C.Colors.widget, C.Colors.border)
	header:ClearAllPoints()
	Widgets.SetPoint(header, 'TOPLEFT', frame, 'TOPLEFT', 0, 0)
	Widgets.SetPoint(header, 'TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
	header:SetHeight(HEADER_HEIGHT)

	-- Title text: left-anchored with normal padding
	local titleText = Widgets.CreateFontString(header, C.Font.sizeTitle, C.Colors.textActive)
	titleText:ClearAllPoints()
	Widgets.SetPoint(titleText, 'LEFT', header, 'LEFT', C.Spacing.normal, 0)
	titleText:SetText(title)

	-- Make the header the drag handle
	header:EnableMouse(true)
	header:RegisterForDrag('LeftButton')

	header:SetScript('OnDragStart', function(self)
		frame:StartMoving()
	end)

	header:SetScript('OnDragStop', function(self)
		frame:StopMovingOrSizing()
	end)

	return frame, header, titleText
end

-- ============================================================
-- Card
-- A subtle rounded background used to visually group a bundle
-- of related settings widgets. Call StartCard to begin, then
-- place widgets using yOffset, then call EndCard to set height.
-- ============================================================

local CARD_PADDING = 12
Widgets.CARD_PADDING = CARD_PADDING
local CARD_BACKDROP = {
	bgFile   = [[Interface\BUTTONS\WHITE8x8]],
	edgeFile = [[Interface\BUTTONS\WHITE8x8]],
	edgeSize = 1,
	insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

--- Start a card background at the current yOffset.
--- Returns a transparent inner content frame with built-in padding.
--- Callers swap their content reference to the returned frame — all
--- subsequent placeWidget / SetPoint calls use it at x=0 and the
--- padding is automatic. EndCard restores the outer yOffset.
---
--- Usage:
---   local card, inner, yOff = Widgets.StartCard(content, width, yOffset)
---   -- place widgets into `inner` at yOff, same as before
---   yOffset = Widgets.EndCard(card, content, yOff)
---
--- @param parent  Frame  Scroll content frame the card sits on
--- @param width   number Available content width
--- @param yOffset number Current yOffset on the parent
--- @return Frame card, Frame innerContent, number innerYOffset
function Widgets.StartCard(parent, width, yOffset)
	local card = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	card:SetBackdrop(CARD_BACKDROP)
	local bg = C.Colors.card
	local border = C.Colors.cardBorder
	card:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	card:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
	card:ClearAllPoints()
	Widgets.SetPoint(card, 'TOPLEFT', parent, 'TOPLEFT', 0, yOffset)
	card:SetWidth(width)
	card:SetFrameLevel(parent:GetFrameLevel())
	card:SetClipsChildren(true)

	-- Inner content frame: inset from card edges on all sides
	local inner = CreateFrame('Frame', nil, card)
	inner:SetPoint('TOPLEFT', card, 'TOPLEFT', CARD_PADDING, -CARD_PADDING)
	inner:SetPoint('TOPRIGHT', card, 'TOPRIGHT', -CARD_PADDING, -CARD_PADDING)
	card.content = inner

	card._startY = yOffset
	return card, inner, 0
end

--- End a card by setting its height based on how far the inner yOffset moved.
--- @param card       Frame  The card frame from StartCard
--- @param parent     Frame  The original scroll content frame
--- @param innerYOff  number Current yOffset inside the inner frame
--- @return number nextYOffset  yOffset on the parent, below the card + spacing
function Widgets.EndCard(card, parent, innerYOff)
	local innerH = math.abs(innerYOff)
	-- Size the inner content frame so children are visible
	card.content:SetHeight(innerH)
	-- Account for CardGrid title height if present (title shifts inner down)
	local titleH = card._cardGridTitleH or 0
	card:SetHeight(innerH + CARD_PADDING * 2 + titleH)
	-- Advance the parent yOffset past the card
	return card._startY - innerH - CARD_PADDING * 2 - titleH - C.Spacing.normal
end

-- ============================================================
-- TitledPane
-- A transparent grouping container with an accent-colored title
-- and a 1px separator line below. Height grows with content.
-- ============================================================

local SEPARATOR_HEIGHT = 1

--- Create a transparent pane with a small accent-colored title and separator.
--- Height is not set — the pane grows to fit its content.
--- @param parent Frame Parent frame
--- @param title string Label text (rendered uppercase)
--- @param width number Logical width
--- @return Frame pane, FontString titleText
function Widgets.CreateTitledPane(parent, title, width)
	local pane = CreateFrame('Frame', nil, parent)
	Widgets.ApplyBaseMixin(pane)

	-- Only set width; height is driven by content
	pane._width = width
	local scale = pane:GetEffectiveScale()
	pane:SetWidth(Widgets.GetNearestPixelSize(width, scale, 1))

	-- Title FontString: accent-colored, small, uppercase
	local titleText = Widgets.CreateFontString(pane, C.Font.sizeSmall, C.Colors.accent)
	titleText:ClearAllPoints()
	Widgets.SetPoint(titleText, 'TOPLEFT', pane, 'TOPLEFT', 0, 0)
	titleText:SetText(title:upper())

	-- 1px separator line anchored below the title text
	local separator = pane:CreateTexture(nil, 'ARTWORK')
	separator:SetHeight(SEPARATOR_HEIGHT)
	separator:SetColorTexture(
		C.Colors.accent[1],
		C.Colors.accent[2],
		C.Colors.accent[3],
		C.Colors.accent[4] or 1)
	separator:ClearAllPoints()
	Widgets.SetPoint(separator, 'TOPLEFT', titleText, 'BOTTOMLEFT', 0, -(C.Spacing.base / 2))
	Widgets.SetPoint(separator, 'TOPRIGHT', pane, 'TOPRIGHT', 0, -(C.Font.sizeSmall + C.Spacing.base / 2))

	-- Expose the separator top as a layout anchor so callers know where content starts
	pane.separatorBottom = separator

	return pane, titleText
end

-- ============================================================
-- Heading
-- A simple text heading at one of three levels. Intended for
-- labelling groups of widgets inside settings panels.
--   Level 1: sizeTitle, accent, UPPERCASE, separator line (same look as TitledPane)
--   Level 2: sizeNormal, textSecondary, normal case, no separator
--   Level 3: sizeSmall, textSecondary, normal case, no separator
-- ============================================================

local HEADING_CONFIG = {
	[1] = { size = C.Font.sizeTitle,  color = C.Colors.accent,        upper = true,  separator = true  },
	[2] = { size = C.Font.sizeNormal, color = C.Colors.textNormal,    upper = false, separator = false },
	[3] = { size = C.Font.sizeSmall,  color = C.Colors.textNormal,    upper = false, separator = false },
	[4] = { size = C.Font.sizeSmall,  color = C.Colors.textSecondary, upper = false, separator = false },
}

--- Create a heading font string at the given level.
--- @param parent Frame  Parent frame (usually scroll content)
--- @param text   string Heading text
--- @param level  number 1, 2, or 3
--- @param width? number Width for separator (level 1 only)
--- @return FontString heading, number height  The heading and total height consumed
function Widgets.CreateHeading(parent, text, level, width)
	local cfg = HEADING_CONFIG[level] or HEADING_CONFIG[3]

	local heading = Widgets.CreateFontString(parent, cfg.size, cfg.color)
	heading:SetText(cfg.upper and text:upper() or text)

	local height = cfg.size + 2  -- font size + small padding

	if(cfg.separator and width) then
		local sep = parent:CreateTexture(nil, 'ARTWORK')
		sep:SetHeight(SEPARATOR_HEIGHT)
		sep:SetColorTexture(
			C.Colors.accent[1],
			C.Colors.accent[2],
			C.Colors.accent[3],
			C.Colors.accent[4] or 1)
		sep:ClearAllPoints()
		Widgets.SetPoint(sep, 'TOPLEFT', heading, 'BOTTOMLEFT', 0, -(C.Spacing.base / 2))
		sep:SetWidth(width)
		height = height + SEPARATOR_HEIGHT + C.Spacing.base / 2
	end

	return heading, height
end

-- ============================================================
-- ResizeButton
-- An 8x8 grip anchored to BOTTOMRIGHT of a frame. Enables
-- live resize callbacks and a completion callback on mouse-up.
-- ============================================================

local RESIZE_BUTTON_SIZE = 8

--- Create a resize grip button anchored to the bottom-right of a frame.
--- @param frame Frame The frame to make resizable
--- @param minWidth number Minimum resize width
--- @param minHeight number Minimum resize height
--- @param maxWidth number Maximum resize width
--- @param maxHeight number Maximum resize height
--- @param onResize? function Called each tick while resizing: onResize(frame, w, h)
--- @param onResizeComplete? function Called on mouse-up: onResizeComplete(frame, w, h)
--- @return Button resizeButton
function Widgets.CreateResizeButton(frame, minWidth, minHeight, maxWidth, maxHeight, onResize, onResizeComplete)
	local button = CreateFrame('Button', nil, frame)
	button:SetFrameLevel(frame:GetFrameLevel() + 10)
	Widgets.SetSize(button, RESIZE_BUTTON_SIZE, RESIZE_BUTTON_SIZE)
	button:ClearAllPoints()
	Widgets.SetPoint(button, 'BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)

	-- Grip texture: a small square, starts hidden
	local grip = button:CreateTexture(nil, 'OVERLAY')
	grip:SetAllPoints(button)
	grip:SetColorTexture(
		C.Colors.textSecondary[1],
		C.Colors.textSecondary[2],
		C.Colors.textSecondary[3],
		C.Colors.textSecondary[4] or 1)
	button:SetAlpha(0)

	-- Manual resize state
	button._resizing = false
	local startCursorX, startCursorY
	local startW, startH

	local function doResize()
		local scale = frame:GetEffectiveScale()
		local curX, curY = GetCursorPosition()
		curX = curX / scale
		curY = curY / scale

		local dx = curX - startCursorX
		local dy = startCursorY - curY  -- Y is inverted (dragging down = larger)

		local newW = math.max(minWidth, math.min(startW + dx, maxWidth))
		local newH = math.max(minHeight, math.min(startH + dy, maxHeight))

		frame:SetSize(newW, newH)

		if(onResize) then
			onResize(frame, newW, newH)
		end
	end

	local function stopResize()
		button._resizing = false
		local w, h = frame:GetWidth(), frame:GetHeight()
		if(onResizeComplete) then
			onResizeComplete(frame, w, h)
		end
	end

	-- Fade helpers
	local fadeTimer
	local function fadeIn()
		if(fadeTimer) then fadeTimer:Cancel(); fadeTimer = nil end
		local elapsed = 0
		local startAlpha = button:GetAlpha()
		button:SetScript('OnUpdate', function(self, dt)
			if(self._resizing) then doResize() end
			if(startAlpha < 1) then
				elapsed = elapsed + dt
				local t = math.min(elapsed / 0.15, 1)
				self:SetAlpha(startAlpha + (1 - startAlpha) * t)
				if(t >= 1) then startAlpha = 1 end
			end
		end)
	end

	local function fadeOut()
		if(fadeTimer) then fadeTimer:Cancel() end
		fadeTimer = C_Timer.NewTimer(0.6, function()
			fadeTimer = nil
			local elapsed = 0
			local startAlpha = button:GetAlpha()
			button:SetScript('OnUpdate', function(self, dt)
				if(self._resizing) then doResize() end
				elapsed = elapsed + dt
				local t = math.min(elapsed / 0.3, 1)
				self:SetAlpha(startAlpha * (1 - t))
				if(t >= 1) then
					self:SetScript('OnUpdate', function(s)
						if(s._resizing) then doResize() end
					end)
				end
			end)
		end)
	end

	-- Full-screen click catcher so mouse release is captured even when
	-- the cursor moves beyond the resize grabber
	local catcher = CreateFrame('Frame', nil, UIParent)
	catcher:SetFrameStrata('TOOLTIP')
	catcher:SetAllPoints(UIParent)
	catcher:EnableMouse(true)
	catcher:Hide()

	catcher:SetScript('OnMouseUp', function(self, mouseButton)
		if(mouseButton == 'LeftButton' and button._resizing) then
			self:Hide()
			stopResize()
		end
	end)

	button:SetScript('OnMouseDown', function(self, mouseButton)
		if(mouseButton == 'LeftButton') then
			local scale = frame:GetEffectiveScale()
			startCursorX, startCursorY = GetCursorPosition()
			startCursorX = startCursorX / scale
			startCursorY = startCursorY / scale
			startW, startH = frame:GetSize()
			self._resizing = true
			catcher:Show()
		end
	end)

	button:SetScript('OnMouseUp', function(self, mouseButton)
		if(mouseButton == 'LeftButton' and self._resizing) then
			catcher:Hide()
			stopResize()
		end
	end)

	-- Live resize via OnUpdate (handles case where no fade is active)
	button:SetScript('OnUpdate', function(self)
		if(self._resizing) then doResize() end
	end)

	-- Show on hover, fade out on leave
	button:SetScript('OnEnter', function(self)
		fadeIn()
		grip:SetColorTexture(
			C.Colors.accent[1],
			C.Colors.accent[2],
			C.Colors.accent[3],
			C.Colors.accent[4] or 1)
	end)

	button:SetScript('OnLeave', function(self)
		if(not self._resizing) then
			fadeOut()
		end
		grip:SetColorTexture(
			C.Colors.textSecondary[1],
			C.Colors.textSecondary[2],
			C.Colors.textSecondary[3],
			C.Colors.textSecondary[4] or 1)
	end)

	return button
end

-- ============================================================
-- AnimateHeight
-- OnUpdate-based linear interpolation of a frame's height.
-- ============================================================

--- Animate a frame's height from current to target over duration.
--- @param frame Frame     The frame to animate
--- @param targetHeight number  Target height
--- @param duration number     Duration in seconds
--- @param onDone? function    Called when animation completes
function Widgets.AnimateHeight(frame, targetHeight, duration, onDone)
	local startHeight = frame:GetHeight()
	if(math.abs(startHeight - targetHeight) < 0.5) then
		frame:SetHeight(targetHeight)
		if(onDone) then onDone() end
		return
	end
	local elapsed = 0
	frame._heightAnimOnDone = onDone
	frame:SetScript('OnUpdate', function(self, dt)
		elapsed = elapsed + dt
		local t = math.min(elapsed / duration, 1)
		local h = startHeight + (targetHeight - startHeight) * t
		self:SetHeight(math.max(h, 0.001))
		if(t >= 1) then
			self:SetScript('OnUpdate', nil)
			self:SetHeight(targetHeight)
			if(self._heightAnimOnDone) then
				self._heightAnimOnDone()
				self._heightAnimOnDone = nil
			end
		end
	end)
end
