local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode
local EditCache = F.EditCache

-- ============================================================
-- ClickCatchers — transparent frames over unit frames for
-- click-to-select in edit mode.
-- ============================================================

local catchers = {}
local DIM_OVERLAY_ALPHA = 0.7

local function DestroyCatchers()
	for _, catcher in next, catchers do
		catcher:Hide()
		catcher:SetParent(EditMode._trashFrame)
	end
	catchers = {}
end

local function CreateCatcher(def, overlay)
	local frame = def.getter()
	if(not frame) then return end

	local catcher = CreateFrame('Button', nil, overlay)
	catcher:SetFrameLevel(overlay:GetFrameLevel() + 10)
	catcher:SetAllPoints(frame)

	-- Dark accent overlay
	local dimTex = catcher:CreateTexture(nil, 'ARTWORK')
	dimTex:SetAllPoints(catcher)
	local accent = C.Colors.accent
	dimTex:SetColorTexture(accent[1] * 0.15, accent[2] * 0.15, accent[3] * 0.15, DIM_OVERLAY_ALPHA)
	catcher._dimTex = dimTex

	-- "Click to edit" label
	local label = Widgets.CreateFontString(catcher, C.Font.sizeSmall, C.Colors.textNormal)
	label:SetPoint('CENTER', catcher, 'CENTER', 0, 0)
	label:SetText('Click to edit')
	catcher._label = label

	-- Hover highlight
	catcher:SetScript('OnEnter', function(self)
		self._dimTex:SetAlpha(DIM_OVERLAY_ALPHA * 0.5)
		self._label:SetTextColor(1, 1, 1, 1)
	end)
	catcher:SetScript('OnLeave', function(self)
		self._dimTex:SetAlpha(DIM_OVERLAY_ALPHA)
		local tn = C.Colors.textNormal
		self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)
	end)

	-- Click → select this frame
	catcher._frameKey = def.key
	catcher._isGroup = def.isGroup
	catcher:SetScript('OnClick', function(self)
		EditMode.SetSelectedFrameKey(self._frameKey)
	end)

	catchers[def.key] = catcher
	return catcher
end

local function CreateAllCatchers()
	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	DestroyCatchers()
	for _, def in next, EditMode.FRAME_KEYS do
		CreateCatcher(def, overlay)
	end
end

--- Hide a specific catcher (when its frame is selected for editing).
local function HideCatcher(frameKey)
	if(catchers[frameKey]) then
		catchers[frameKey]:Hide()
	end
end

--- Show all catchers (deselect state).
local function ShowAllCatchers()
	for _, catcher in next, catchers do
		catcher:Show()
	end
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_ENTERED', function()
	CreateAllCatchers()
end, 'ClickCatchers')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyCatchers()
	-- Restore original drag handlers on all frames
	for _, def in next, EditMode.FRAME_KEYS do
		local frame = def.getter()
		if(frame and frame._editModeSavedHandlers) then
			frame:SetScript('OnDragStart', frame._editModeSavedHandlers.onDragStart)
			frame:SetScript('OnDragStop', frame._editModeSavedHandlers.onDragStop)
			frame._editModeSavedHandlers = nil
			frame._editModeDragWired = nil
		end
	end
end, 'ClickCatchers')

F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
	-- Show all catchers first, then hide the selected one
	ShowAllCatchers()
	if(frameKey) then
		HideCatcher(frameKey)
	end

	-- Wire dragging on the selected frame
	if(frameKey) then
		for _, def in next, EditMode.FRAME_KEYS do
			if(def.key == frameKey) then
				local frame = def.getter()
				if(frame) then
					-- Skip drag wiring if already set up for this frame
					if(frame._editModeDragWired) then break end
					frame._editModeDragWired = true
					-- Save original handlers for restoration
					if(not frame._editModeSavedHandlers) then
						frame._editModeSavedHandlers = {
							onDragStart = frame:GetScript('OnDragStart'),
							onDragStop = frame:GetScript('OnDragStop'),
						}
					end
					Widgets.MakeDraggable(frame,
						function(f) -- onDragStart
							F.EventBus:Fire('EDIT_MODE_DRAG_STARTED', frameKey)
						end,
						function(f, x, y) -- onDragStop
							-- Snap to grid
							x, y = EditMode.SnapToGrid(x, y)
							f:ClearAllPoints()
							f:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', x, y)
							-- Save to edit cache
							EditCache.Set(frameKey, 'position.x', x)
							EditCache.Set(frameKey, 'position.y', y)
							-- Hide alignment guides
							EditMode.HideAlignmentGuides()
							F.EventBus:Fire('EDIT_MODE_DRAG_STOPPED', frameKey)
						end,
						true, -- clampToParent
						function(f, x, y) -- onMove
							EditMode.UpdateAlignmentGuides(f)
						end
					)
				end
				break
			end
		end
	end
end, 'ClickCatchers')
