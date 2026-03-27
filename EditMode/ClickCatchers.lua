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
	label:SetText(def.label .. ' - Click to edit')
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
	-- Restore movable state on all frames
	for _, def in next, EditMode.FRAME_KEYS do
		local frame = def.getter()
		if(frame) then
			frame:SetMovable(false)
		end
	end
	DestroyCatchers()
end, 'ClickCatchers')

--- Convert a catcher into a drag proxy for the selected frame.
--- The catcher overlay becomes transparent and draggable; moving it
--- repositions the real unit frame underneath.
local function ConvertToDragProxy(catcher, def)
	local frame = def.getter()
	if(not frame) then return end

	-- Visual: hide label and dim overlay so the live frame shows through
	catcher._label:SetText('')
	catcher._dimTex:SetAlpha(0)
	catcher:SetScript('OnEnter', nil)
	catcher:SetScript('OnLeave', nil)
	catcher:SetScript('OnClick', nil)
	catcher._isDragProxy = true

	-- Wire drag on the catcher (which lives in the overlay strata).
	-- The catcher captures drag events; StartMoving/StopMoving act on the real frame.
	local frameKey = def.key
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	catcher:RegisterForDrag('LeftButton')

	catcher:SetScript('OnDragStart', function(self)
		frame:StartMoving()
		F.EventBus:Fire('EDIT_MODE_DRAG_STARTED', frameKey)
		-- OnUpdate for alignment guides (tracks real frame position)
		self._prevOnUpdate = self:GetScript('OnUpdate')
		self:SetScript('OnUpdate', function()
			EditMode.UpdateAlignmentGuides(frame)
		end)
	end)

	catcher:SetScript('OnDragStop', function(self)
		frame:StopMovingOrSizing()
		-- Restore OnUpdate
		self:SetScript('OnUpdate', self._prevOnUpdate or nil)
		self._prevOnUpdate = nil
		-- Snap & reposition
		local _, _, _, x, y = frame:GetPoint()
		x, y = EditMode.SnapToGrid(x, y)
		frame:ClearAllPoints()
		frame:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', x, y)
		-- Re-anchor catcher to follow frame
		self:ClearAllPoints()
		self:SetAllPoints(frame)
		-- Save to edit cache
		EditCache.Set(frameKey, 'position.x', x)
		EditCache.Set(frameKey, 'position.y', y)
		EditMode.HideAlignmentGuides()
		F.EventBus:Fire('EDIT_MODE_DRAG_STOPPED', frameKey)
	end)
end

--- Restore a catcher from drag-proxy mode back to its default click-to-select state.
local function RestoreCatcher(catcher, def)
	if(not catcher._isDragProxy) then return end
	catcher._isDragProxy = nil

	catcher:RegisterForDrag()  -- unregister drag
	catcher:SetScript('OnDragStart', nil)
	catcher:SetScript('OnDragStop', nil)
	catcher:SetScript('OnUpdate', nil)

	-- Restore label and visuals
	catcher._label:SetText(def.label .. ' - Click to edit')
	catcher._dimTex:SetAlpha(DIM_OVERLAY_ALPHA)

	catcher:SetScript('OnEnter', function(self)
		self._dimTex:SetAlpha(DIM_OVERLAY_ALPHA * 0.5)
		self._label:SetTextColor(1, 1, 1, 1)
	end)
	catcher:SetScript('OnLeave', function(self)
		self._dimTex:SetAlpha(DIM_OVERLAY_ALPHA)
		local tn = C.Colors.textNormal
		self._label:SetTextColor(tn[1], tn[2], tn[3], tn[4] or 1)
	end)

	catcher._frameKey = def.key
	catcher:SetScript('OnClick', function(self)
		EditMode.SetSelectedFrameKey(self._frameKey)
	end)
end

F.EventBus:Register('EDIT_MODE_FRAME_SELECTED', function(frameKey)
	-- Restore all catchers to default state first
	for _, def in next, EditMode.FRAME_KEYS do
		local catcher = catchers[def.key]
		if(catcher) then
			RestoreCatcher(catcher, def)
			catcher:Show()
		end
	end

	-- Convert the selected catcher into a drag proxy
	if(frameKey) then
		for _, def in next, EditMode.FRAME_KEYS do
			if(def.key == frameKey) then
				local catcher = catchers[def.key]
				if(catcher) then
					ConvertToDragProxy(catcher, def)
				end
				break
			end
		end
	end
end, 'ClickCatchers')
