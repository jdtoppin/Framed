local addonName, Framed = ...
local F = Framed

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
	frame:SetResizable(true)
	frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)

	local button = CreateFrame('Button', nil, frame)
	Widgets.SetSize(button, RESIZE_BUTTON_SIZE, RESIZE_BUTTON_SIZE)
	button:ClearAllPoints()
	Widgets.SetPoint(button, 'BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)

	-- Grip texture: a small square tinted in the secondary text color
	local grip = button:CreateTexture(nil, 'OVERLAY')
	grip:SetAllPoints(button)
	grip:SetColorTexture(
		C.Colors.textSecondary[1],
		C.Colors.textSecondary[2],
		C.Colors.textSecondary[3],
		C.Colors.textSecondary[4] or 1)

	-- Resize state flag
	button._resizing = false

	button:SetScript('OnMouseDown', function(self, mouseButton)
		if(mouseButton == 'LeftButton') then
			self._resizing = true
			frame:StartSizing('BOTTOMRIGHT')
		end
	end)

	button:SetScript('OnMouseUp', function(self, mouseButton)
		if(mouseButton == 'LeftButton' and self._resizing) then
			self._resizing = false
			frame:StopMovingOrSizing()
			local w, h = frame:GetWidth(), frame:GetHeight()
			if(onResizeComplete) then
				onResizeComplete(frame, w, h)
			end
		end
	end)

	-- Live resize callbacks via OnUpdate
	button:SetScript('OnUpdate', function(self)
		if(self._resizing and onResize) then
			onResize(frame, frame:GetWidth(), frame:GetHeight())
		end
	end)

	-- Highlight on hover to signal interactivity
	button:SetScript('OnEnter', function(self)
		grip:SetColorTexture(
			C.Colors.accent[1],
			C.Colors.accent[2],
			C.Colors.accent[3],
			C.Colors.accent[4] or 1)
	end)

	button:SetScript('OnLeave', function(self)
		grip:SetColorTexture(
			C.Colors.textSecondary[1],
			C.Colors.textSecondary[2],
			C.Colors.textSecondary[3],
			C.Colors.textSecondary[4] or 1)
	end)

	return button
end
