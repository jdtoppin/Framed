local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local EditMode = F.EditMode

-- ============================================================
-- TopBar — preset dropdown, editing label, grid controls,
-- save/cancel buttons. Centered at top of screen.
-- ============================================================

local TOP_BAR_HEIGHT  = 40
local BUTTON_HEIGHT   = 22
local DROPDOWN_W      = 140
local ITEM_GAP        = C.Spacing.normal  -- gap between top bar items

local topBar = nil

local function BuildTopBar()
	local overlay = EditMode.GetOverlay()
	if(not overlay) then return end

	topBar = Widgets.CreateBorderedFrame(overlay, 100, TOP_BAR_HEIGHT, C.Colors.panel, C.Colors.border)
	topBar:SetFrameLevel(overlay:GetFrameLevel() + 50)
	topBar:EnableMouse(true)  -- consume clicks so they don't deselect via bgCatcher

	-- Build all items, then measure total width to center the bar.
	-- Items are chained left-to-right with ITEM_GAP between them.

	-- ── Preset dropdown ─────────────────────────────────────
	local presetDD = Widgets.CreateDropdown(topBar, DROPDOWN_W)
	local ddItems = {}
	for _, name in next, C.PresetOrder do
		ddItems[#ddItems + 1] = { text = name, value = name }
	end
	presetDD:SetItems(ddItems)
	presetDD:SetValue(EditMode.GetSessionPreset())
	presetDD:SetOnSelect(function(value)
		F.EventBus:Fire('EDIT_MODE_PRESET_SWAP_REQUESTED', value)
	end)
	topBar._presetDD = presetDD

	-- ── "Editing: X" label ──────────────────────────────────
	local editLabel = Widgets.CreateFontString(topBar, C.Font.sizeNormal, { 0.2, 0.8, 0.2, 1 })
	editLabel:SetText('Editing: ' .. EditMode.GetSessionPreset())
	topBar._editLabel = editLabel

	-- ── Helper: toggle button visual state ──────────────────
	local function ApplyToggleVisuals(btn, active)
		if(active) then
			local accent = C.Colors.accent
			btn:SetBackdropColor(C.Colors.accentDim[1], C.Colors.accentDim[2], C.Colors.accentDim[3], C.Colors.accentDim[4] or 1)
			btn:SetBackdropBorderColor(accent[1], accent[2], accent[3], accent[4] or 1)
			btn._label:SetTextColor(1, 1, 1, 1)
			btn._groupSelected = true
		else
			btn._groupSelected = false
			local s = btn._scheme
			btn:SetBackdropColor(s.bg[1], s.bg[2], s.bg[3], s.bg[4] or 1)
			local bc = s.border
			btn:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
			local tc = s.textColor
			btn._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
	end

	-- ── Grid Snap toggle ────────────────────────────────────
	local snapBtn = Widgets.CreateButton(topBar, 'Grid Snap', 'widget', 80, BUTTON_HEIGHT)
	topBar._snapBtn = snapBtn

	snapBtn:SetOnClick(function()
		local newVal = not F.Config:Get('general.editModeGridSnap')
		F.Config:Set('general.editModeGridSnap', newVal)
		ApplyToggleVisuals(snapBtn, newVal)
		F.EventBus:Fire('EDIT_MODE_GRID_SNAP_CHANGED', newVal)
	end)
	ApplyToggleVisuals(snapBtn, F.Config:Get('general.editModeGridSnap'))

	-- ── Animate toggle ──────────────────────────────────────
	local animBtn = Widgets.CreateButton(topBar, 'Animate', 'widget', 80, BUTTON_HEIGHT)
	topBar._animBtn = animBtn

	animBtn:SetOnClick(function()
		local newVal = not F.Config:Get('general.editModeAnimate')
		F.Config:Set('general.editModeAnimate', newVal)
		ApplyToggleVisuals(animBtn, newVal)
		F.PreviewManager.SetAnimationEnabled(newVal)
	end)
	ApplyToggleVisuals(animBtn, F.Config:Get('general.editModeAnimate'))

	-- ── Save button ─────────────────────────────────────────
	local saveBtn = Widgets.CreateButton(topBar, 'Save', 'accent', 70, BUTTON_HEIGHT)
	saveBtn:SetOnClick(function()
		EditMode.RequestSave()
	end)

	-- ── Cancel button ───────────────────────────────────────
	local cancelBtn = Widgets.CreateButton(topBar, 'Cancel', 'widget', 70, BUTTON_HEIGHT)
	cancelBtn:SetOnClick(function()
		EditMode.RequestCancel()
	end)

	-- ── Layout: chain items left-to-right, measure, size bar ──
	local allItems = { presetDD, editLabel, snapBtn, animBtn, saveBtn, cancelBtn }
	local totalW = ITEM_GAP  -- left padding

	for _, item in next, allItems do
		local w = item.GetWidth and item:GetWidth() or 0
		totalW = totalW + w + ITEM_GAP
	end

	Widgets.SetSize(topBar, totalW, TOP_BAR_HEIGHT)
	topBar:ClearAllPoints()
	topBar:SetPoint('TOP', UIParent, 'TOP', 0, -C.Spacing.tight)

	-- Anchor items left-to-right
	local prev = nil
	for _, item in next, allItems do
		item:ClearAllPoints()
		if(not prev) then
			item:SetPoint('LEFT', topBar, 'LEFT', ITEM_GAP, 0)
		else
			item:SetPoint('LEFT', prev, 'RIGHT', ITEM_GAP, 0)
		end
		prev = item
	end
end

local function DestroyTopBar()
	if(topBar) then
		topBar:Hide()
		topBar:SetParent(EditMode._trashFrame)
		topBar = nil
	end
end

--- Update the "Editing: X" label text.
local function UpdateEditingLabel(presetName)
	if(topBar and topBar._editLabel) then
		topBar._editLabel:SetText('Editing: ' .. presetName)
	end
end

--- Get current grid snap state.
function EditMode.IsGridSnapEnabled()
	return F.Config:Get('general.editModeGridSnap')
end

-- ============================================================
-- Event Listeners
-- ============================================================

F.EventBus:Register('EDIT_MODE_ENTERED', function()
	BuildTopBar()
end, 'TopBar')

F.EventBus:Register('EDIT_MODE_EXITED', function()
	DestroyTopBar()
end, 'TopBar')

F.EventBus:Register('EDITING_PRESET_CHANGED', function(presetName)
	UpdateEditingLabel(presetName)
end, 'TopBar.EditingLabel')

F.EventBus:Register('EDIT_MODE_PRESET_SWAP_CANCELLED', function()
	-- Revert dropdown to the current preset when user cancels a swap
	if(topBar and topBar._presetDD) then
		topBar._presetDD:SetValue(EditMode.GetSessionPreset())
	end
end, 'TopBar.PresetSwapCancel')
