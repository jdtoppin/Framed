local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local EditMode = F.EditMode
local EditCache = F.EditCache

-- ============================================================
-- Edit Mode Dialogs
-- ============================================================

-- ── Keyboard conflict prevention ────────────────────────────
-- When a dialog is open, disable the overlay's Escape handler
-- so the dialog consumes Escape exclusively.
local function SuppressOverlayKeyboard()
	local overlay = EditMode.GetOverlay()
	if(overlay) then overlay:EnableKeyboard(false) end
end

local function RestoreOverlayKeyboard()
	local overlay = EditMode.GetOverlay()
	if(overlay and EditMode.IsActive()) then overlay:EnableKeyboard(true) end
end

-- ── Save Dialog ─────────────────────────────────────────────
F.EventBus:Register('EDIT_MODE_SHOW_SAVE_DIALOG', function()
	SuppressOverlayKeyboard()
	Widgets.ShowThreeButtonDialog(
		'Save Changes',
		'How would you like to save your edit mode changes?',
		'Save + Exit',
		'Save + Menu',
		'Continue Editing',
		function() RestoreOverlayKeyboard() EditMode.Save(false) end,
		function() RestoreOverlayKeyboard() EditMode.Save(true) end,
		function() RestoreOverlayKeyboard() end
	)
end, 'EditMode.Dialogs')

-- ── Cancel Dialog ───────────────────────────────────────────
F.EventBus:Register('EDIT_MODE_SHOW_CANCEL_DIALOG', function()
	SuppressOverlayKeyboard()
	Widgets.ShowThreeButtonDialog(
		'Discard Changes?',
		'You have unsaved changes. What would you like to do?',
		'Discard + Exit',
		'Discard + Menu',
		'Continue Editing',
		function() RestoreOverlayKeyboard() EditMode.Discard(false) end,
		function() RestoreOverlayKeyboard() EditMode.Discard(true) end,
		function() RestoreOverlayKeyboard() end
	)
end, 'EditMode.Dialogs')

-- ── Preset Swap Dialog ──────────────────────────────────────
F.EventBus:Register('EDIT_MODE_PRESET_SWAP_REQUESTED', function(newPreset)
	if(not EditCache.HasAnyEdits()) then
		-- No edits, just switch
		EditMode.SetSessionPreset(newPreset)
		F.Settings.SetEditingPreset(newPreset)
		F.EventBus:Fire('EDIT_MODE_PRESET_SWITCHED', newPreset)
		return
	end

	SuppressOverlayKeyboard()
	Widgets.ShowThreeButtonDialog(
		'Switch Preset',
		'You have unsaved changes to the current preset. What would you like to do?',
		'Save + Switch',
		'Discard + Switch',
		'Continue Editing',
		function()
			-- Save current, then switch
			RestoreOverlayKeyboard()
			EditCache.Commit()
			EditCache.Activate()
			EditMode.SetSessionPreset(newPreset)
			F.Settings.SetEditingPreset(newPreset)
			F.EventBus:Fire('EDIT_MODE_PRESET_SWITCHED', newPreset)
		end,
		function()
			-- Discard current, then switch
			RestoreOverlayKeyboard()
			EditCache.Discard()
			EditCache.Activate()
			EditMode.SetSessionPreset(newPreset)
			F.Settings.SetEditingPreset(newPreset)
			F.EventBus:Fire('EDIT_MODE_PRESET_SWITCHED', newPreset)
		end,
		function()
			-- Continue Editing — revert dropdown to current preset
			RestoreOverlayKeyboard()
			F.EventBus:Fire('EDIT_MODE_PRESET_SWAP_CANCELLED')
		end
	)
end, 'EditMode.Dialogs')
