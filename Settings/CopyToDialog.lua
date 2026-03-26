local addonName, Framed = ...
local F = Framed
local Widgets = F.Widgets
local C = F.Constants
local Settings = F.Settings

-- ============================================================
-- CopyToDialog — Copy aura config from one unit type to others
-- ============================================================

local DIALOG_WIDTH  = 360
local DIALOG_HEIGHT = 200
local BTN_W         = 90
local BTN_H         = 22
local BTN_GAP       = 6

local dialog     -- the dialog frame (created once, reused)
local toggleBtns = {}
local multiGroup

-- ── Deep clone ──────────────────────────────────────────────

local function deepClone(src)
	if(type(src) ~= 'table') then return src end
	local copy = {}
	for k, v in next, src do
		copy[k] = deepClone(v)
	end
	return copy
end

-- ── Build / rebuild dialog contents ─────────────────────────

local function buildDialog(configKey, panelLabel, panelId)
	if(not dialog) then
		dialog = CreateFrame('Frame', nil, UIParent, 'BackdropTemplate')
		dialog:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
		dialog:SetPoint('CENTER')
		dialog:SetFrameStrata('FULLSCREEN_DIALOG')
		dialog:SetBackdrop({
			bgFile   = [[Interface\Buttons\WHITE8x8]],
			edgeFile = [[Interface\Buttons\WHITE8x8]],
			edgeSize = 1,
		})
		dialog:SetBackdropColor(C.Colors.panel[1], C.Colors.panel[2], C.Colors.panel[3], C.Colors.panel[4] or 0.95)
		dialog:SetBackdropBorderColor(C.Colors.border[1], C.Colors.border[2], C.Colors.border[3], 1)
		dialog:EnableMouse(true)
		dialog:EnableKeyboard(true)
		dialog:SetScript('OnKeyDown', function(self, key)
			if(key == 'ESCAPE') then
				self:SetPropagateKeyboardInput(false)
				Widgets.FadeOut(self, 0.15, function() self:Hide() end)
			else
				self:SetPropagateKeyboardInput(true)
			end
		end)

		-- Title
		dialog._title = Widgets.CreateFontString(dialog, C.Font.sizeLarge, C.Colors.textNormal)
		dialog._title:SetPoint('TOP', dialog, 'TOP', 0, -C.Spacing.normal)

		-- Subtitle
		dialog._subtitle = Widgets.CreateFontString(dialog, C.Font.sizeSmall, C.Colors.textSecondary)
		dialog._subtitle:SetPoint('TOP', dialog._title, 'BOTTOM', 0, -4)

		-- Cancel button
		dialog._cancelBtn = Widgets.CreateButton(dialog, 'Cancel', 'widget', BTN_W, BTN_H)
		dialog._cancelBtn:SetPoint('BOTTOMRIGHT', dialog, 'BOTTOMRIGHT', -C.Spacing.normal, C.Spacing.normal)
		dialog._cancelBtn:SetScript('OnClick', function()
			Widgets.FadeOut(dialog, 0.15, function() dialog:Hide() end)
		end)

		-- Confirm button
		dialog._confirmBtn = Widgets.CreateButton(dialog, 'Confirm', 'accent', BTN_W, BTN_H)
		dialog._confirmBtn:SetPoint('RIGHT', dialog._cancelBtn, 'LEFT', -BTN_GAP, 0)
	end

	-- Update text
	dialog._title:SetText('Copy ' .. panelLabel .. ' Settings')

	local sourceUnit = Settings.GetEditingUnitType()
	local sourceLabel = sourceUnit
	local items = Settings._getUnitTypeItems()
	for _, item in next, items do
		if(item.value == sourceUnit) then
			sourceLabel = item.text
			break
		end
	end
	dialog._subtitle:SetText('From: ' .. sourceLabel)

	-- Hide all existing toggle buttons
	for _, btn in next, toggleBtns do
		btn:Hide()
	end

	-- Create toggle buttons for each target unit type (excluding source)
	local targets = {}
	for _, item in next, items do
		if(item.value ~= sourceUnit) then
			targets[#targets + 1] = item
		end
	end

	local btnsPerRow = math.floor((DIALOG_WIDTH - C.Spacing.normal * 2 + BTN_GAP) / (BTN_W + BTN_GAP))
	local startX = C.Spacing.normal
	local startY = -60

	for i, item in next, targets do
		local btn = toggleBtns[i]
		if(not btn) then
			btn = Widgets.CreateButton(dialog, item.text, 'widget', BTN_W, BTN_H)
			toggleBtns[i] = btn
		else
			btn._label:SetText(item.text)
		end
		btn.value = item.value
		local row = math.floor((i - 1) / btnsPerRow)
		local col = (i - 1) % btnsPerRow
		btn:ClearAllPoints()
		Widgets.SetPoint(btn, 'TOPLEFT', dialog, 'TOPLEFT',
			startX + col * (BTN_W + BTN_GAP),
			startY - row * (BTN_H + BTN_GAP))
		btn:Show()
	end

	-- Build the active buttons array for the multi-select group
	local activeBtns = {}
	for i = 1, #targets do
		activeBtns[i] = toggleBtns[i]
	end

	-- Wire multi-select group
	multiGroup = Widgets.CreateMultiSelectButtonGroup(activeBtns, function(selected)
		-- Enable confirm only when at least one target is selected
		local hasSelection = false
		for _ in next, selected do
			hasSelection = true
			break
		end
		if(hasSelection) then
			dialog._confirmBtn:Enable()
		else
			dialog._confirmBtn:Disable()
		end
	end)

	-- Disable confirm initially
	dialog._confirmBtn:Disable()

	-- Build a value→label lookup for friendly print output
	local labelLookup = {}
	for _, item in next, items do
		labelLookup[item.value] = item.text
	end

	-- Wire confirm action
	dialog._confirmBtn:SetScript('OnClick', function()
		local presetName = Settings.GetEditingPreset()
		local sourcePath = 'presets.' .. presetName .. '.auras.' .. sourceUnit .. '.' .. configKey
		local sourceData = F.Config:Get(sourcePath)

		local copiedTo = {}
		for targetUnit in next, multiGroup._selected do
			local targetPath = 'presets.' .. presetName .. '.auras.' .. targetUnit .. '.' .. configKey
			F.Config:Set(targetPath, deepClone(sourceData))
			copiedTo[#copiedTo + 1] = labelLookup[targetUnit] or targetUnit
		end

		if(F.PresetManager) then
			F.PresetManager.MarkCustomized(presetName)
		end

		-- Invalidate cached panel so it rebuilds with new config
		Settings._panelFrames[panelId] = nil

		Widgets.FadeOut(dialog, 0.15, function() dialog:Hide() end)

		if(#copiedTo > 0) then
			print('Framed: Copied ' .. panelLabel .. ' settings from ' .. sourceLabel .. ' to ' .. table.concat(copiedTo, ', '))
		end
	end)

	-- Adjust dialog height based on number of rows
	local numRows = math.ceil(#targets / btnsPerRow)
	local neededH = 60 + numRows * (BTN_H + BTN_GAP) + BTN_H + C.Spacing.normal * 2 + 10
	dialog:SetHeight(math.max(DIALOG_HEIGHT, neededH))
end

-- ── Public API ──────────────────────────────────────────────

function Settings.ShowCopyToDialog(configKey, panelLabel, panelId)
	buildDialog(configKey, panelLabel, panelId)
	dialog:Show()
	Widgets.FadeIn(dialog, 0.15)
end
