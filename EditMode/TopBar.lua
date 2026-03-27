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

	-- ── Grid Snap toggle ────────────────────────────────────
	local snapBtn = Widgets.CreateButton(topBar, 'Grid Snap', 'widget', 80, BUTTON_HEIGHT)
	topBar._snapBtn = snapBtn
	topBar._gridSnap = true

	local function UpdateSnapButton()
		if(topBar._gridSnap) then
			local accent = C.Colors.accent
			snapBtn:SetBackdropColor(C.Colors.accentDim[1], C.Colors.accentDim[2], C.Colors.accentDim[3], C.Colors.accentDim[4] or 1)
			snapBtn:SetBackdropBorderColor(accent[1], accent[2], accent[3], accent[4] or 1)
			snapBtn._label:SetTextColor(1, 1, 1, 1)
		else
			local s = snapBtn._scheme
			snapBtn:SetBackdropColor(s.bg[1], s.bg[2], s.bg[3], s.bg[4] or 1)
			local bc = s.border
			snapBtn:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
			local tc = s.textColor
			snapBtn._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
	end

	snapBtn:SetOnClick(function()
		topBar._gridSnap = not topBar._gridSnap
		UpdateSnapButton()
		F.EventBus:Fire('EDIT_MODE_GRID_SNAP_CHANGED', topBar._gridSnap)
	end)
	UpdateSnapButton()

	-- ── Grid Style selector ─────────────────────────────────
	local gridStyleSwitch = Widgets.CreateSwitch(topBar, 100, BUTTON_HEIGHT, {
		{ text = 'Lines', value = 'lines' },
		{ text = 'Dots',  value = 'dots' },
	})
	gridStyleSwitch:SetValue('lines')
	gridStyleSwitch:SetOnSelect(function(value)
		F.EventBus:Fire('EDIT_MODE_GRID_STYLE_CHANGED', value)
	end)
	topBar._gridStyleSwitch = gridStyleSwitch

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
	local allItems = { presetDD, editLabel, snapBtn, gridStyleSwitch, saveBtn, cancelBtn }
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
	return topBar and topBar._gridSnap or false
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
