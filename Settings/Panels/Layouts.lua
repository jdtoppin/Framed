local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Constants
-- ============================================================

local ROW_H        = 28
local PANE_TITLE_H = 20
local DROPDOWN_H   = 22
local BUTTON_H     = 22
local WIDGET_W     = 220

local CONTENT_TYPES = {
	{ id = C.ContentType and C.ContentType.SOLO         or 'Solo',         label = 'Solo' },
	{ id = C.ContentType and C.ContentType.PARTY        or 'Party',        label = 'Party' },
	{ id = C.ContentType and C.ContentType.RAID         or 'Raid',         label = 'Raid' },
	{ id = C.ContentType and C.ContentType.MYTHIC_RAID  or 'MythicRaid',   label = 'Mythic Raid' },
	{ id = C.ContentType and C.ContentType.WORLD_RAID   or 'WorldRaid',    label = 'World Raid' },
	{ id = C.ContentType and C.ContentType.BATTLEGROUND or 'Battleground', label = 'Battleground' },
	{ id = C.ContentType and C.ContentType.ARENA        or 'Arena',        label = 'Arena' },
}

-- ============================================================
-- Helpers
-- ============================================================

local function createSection(content, title, width, yOffset)
	local pane = Widgets.CreateTitledPane(content, title, width)
	pane:ClearAllPoints()
	Widgets.SetPoint(pane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return pane, yOffset - PANE_TITLE_H - C.Spacing.normal
end

--- Return a list of {text, value} items for all known layouts.
local function getLayoutItems()
	local items = {}
	if(F.LayoutManager and F.LayoutManager.GetAll) then
		local layouts = F.LayoutManager.GetAll()
		for _, layout in next, layouts do
			items[#items + 1] = { text = layout.name, value = layout.name }
		end
	end
	if(#items == 0) then
		-- Fallback when LayoutManager is not yet initialised
		items[#items + 1] = { text = 'Default Solo',        value = 'Default Solo' }
		items[#items + 1] = { text = 'Default Party',       value = 'Default Party' }
		items[#items + 1] = { text = 'Default Raid',        value = 'Default Raid' }
		items[#items + 1] = { text = 'Default Mythic Raid', value = 'Default Mythic Raid' }
		items[#items + 1] = { text = 'Default World Raid',  value = 'Default World Raid' }
		items[#items + 1] = { text = 'Default Battleground', value = 'Default Battleground' }
		items[#items + 1] = { text = 'Default Arena',       value = 'Default Arena' }
	end
	return items
end

--- Return whether a layout is a built-in (non-deletable / non-renameable).
local function isBuiltIn(layoutName)
	if(F.LayoutManager and F.LayoutManager.IsBuiltIn) then
		return F.LayoutManager.IsBuiltIn(layoutName)
	end
	-- Heuristic fallback
	return layoutName and layoutName:find('^Default') ~= nil
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'layouts',
	label   = 'Layouts',
	section = 'GENERAL',
	order   = 20,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		-- ── Outer scroll frame ─────────────────────────────────
		local scroll = Widgets.CreateScrollFrame(
			parent, nil,
			parentW,
			parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ── Config helpers ─────────────────────────────────────
		local function getAutoSwitch(contentTypeId)
			return F.Config and F.Config:Get('autoSwitch.' .. contentTypeId)
		end
		local function setAutoSwitch(contentTypeId, layoutName)
			if(F.Config) then
				F.Config:Set('autoSwitch.' .. contentTypeId, layoutName)
			end
			if(F.EventBus) then
				F.EventBus:Fire('CONFIG_CHANGED:autoSwitch')
			end
		end
		local function getSpecOverrides()
			return (F.Config and F.Config:Get('specOverrides')) or {}
		end
		local function setSpecOverride(specName, layoutName)
			local overrides = getSpecOverrides()
			overrides[specName] = layoutName
			if(F.Config) then
				F.Config:Set('specOverrides', overrides)
			end
			if(F.EventBus) then
				F.EventBus:Fire('CONFIG_CHANGED:specOverrides')
			end
		end
		local function removeSpecOverride(specName)
			local overrides = getSpecOverrides()
			overrides[specName] = nil
			if(F.Config) then
				F.Config:Set('specOverrides', overrides)
			end
			if(F.EventBus) then
				F.EventBus:Fire('CONFIG_CHANGED:specOverrides')
			end
		end

		-- ============================================================
		-- Section 1: Your Layouts
		-- ============================================================
		local layoutsPane
		layoutsPane, yOffset = createSection(content, 'Your Layouts', width, yOffset)

		-- "New Layout" button at the top of the section
		local newBtn = Widgets.CreateButton(content, 'New Layout', 'accent', 120, BUTTON_H)
		newBtn:ClearAllPoints()
		Widgets.SetPoint(newBtn, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - BUTTON_H - C.Spacing.normal

		-- Scrollable area for the layout list
		local listHeight = 200
		local listScroll = Widgets.CreateScrollFrame(content, nil, width, listHeight)
		listScroll:ClearAllPoints()
		Widgets.SetPoint(listScroll, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		local listContent = listScroll:GetContentFrame()
		listContent:SetWidth(width)
		yOffset = yOffset - listHeight - C.Spacing.normal

		-- ── Build layout list rows ─────────────────────────────

		local layoutRowPool = {}

		local function buildLayoutRow(parent, layoutName, rowY)
			local row = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
			row._bgColor     = C.Colors.widget
			row._borderColor = C.Colors.border
			Widgets.ApplyBackdrop(row, C.Colors.widget, C.Colors.border)
			row:ClearAllPoints()
			Widgets.SetPoint(row, 'TOPLEFT', parent, 'TOPLEFT', 0, rowY)
			row:SetPoint('TOPRIGHT', parent, 'TOPRIGHT', 0, rowY)
			row:SetHeight(ROW_H)

			-- Name label
			local nameFS = Widgets.CreateFontString(row, C.Font.sizeNormal, C.Colors.textNormal)
			nameFS:ClearAllPoints()
			Widgets.SetPoint(nameFS, 'LEFT', row, 'LEFT', C.Spacing.tight, 0)
			nameFS:SetText(layoutName)

			-- Tag label ("built-in" or "custom")
			local builtIn = isBuiltIn(layoutName)
			local tagFS = Widgets.CreateFontString(row, C.Font.sizeSmall, C.Colors.textSecondary)
			tagFS:ClearAllPoints()
			Widgets.SetPoint(tagFS, 'LEFT', nameFS, 'RIGHT', C.Spacing.normal, 0)
			tagFS:SetText(builtIn and 'built-in' or 'custom')

			-- Right-side button container
			local btnX = -C.Spacing.tight

			-- Delete button (custom only, red)
			if(not builtIn) then
				local deleteBtn = Widgets.CreateButton(row, 'Delete', 'red', 60, ROW_H - 6)
				deleteBtn:ClearAllPoints()
				Widgets.SetPoint(deleteBtn, 'RIGHT', row, 'RIGHT', btnX, 0)
				local capturedName = layoutName
				deleteBtn:SetOnClick(function()
					Widgets.ShowConfirmDialog(
						'Delete Layout',
						'Delete "' .. capturedName .. '"? This cannot be undone.',
						function()
							if(F.LayoutManager and F.LayoutManager.Delete) then
								F.LayoutManager.Delete(capturedName)
							end
							-- Refresh is triggered by CONFIG_CHANGED event from LayoutManager
						end)
				end)
				btnX = btnX - 60 - C.Spacing.base

				-- Rename button (custom only)
				local renameBtn = Widgets.CreateButton(row, 'Rename', 'widget', 60, ROW_H - 6)
				renameBtn:ClearAllPoints()
				Widgets.SetPoint(renameBtn, 'RIGHT', row, 'RIGHT', btnX, 0)
				local capturedRename = layoutName
				renameBtn:SetOnClick(function()
					if(F.LayoutManager and F.LayoutManager.Rename) then
						-- Show input dialog (handled by LayoutManager.Rename)
						F.LayoutManager.Rename(capturedRename)
					end
				end)
				btnX = btnX - 60 - C.Spacing.base
			end

			-- Duplicate button (always)
			local dupBtn = Widgets.CreateButton(row, 'Duplicate', 'widget', 75, ROW_H - 6)
			dupBtn:ClearAllPoints()
			Widgets.SetPoint(dupBtn, 'RIGHT', row, 'RIGHT', btnX, 0)
			local capturedDup = layoutName
			dupBtn:SetOnClick(function()
				if(F.LayoutManager and F.LayoutManager.Duplicate) then
					F.LayoutManager.Duplicate(capturedDup)
				end
			end)

			return row
		end

		local function refreshLayoutList()
			-- Hide all pooled rows
			for _, r in next, layoutRowPool do
				r:Hide()
				r:SetParent(nil)
			end
			layoutRowPool = {}

			local items = getLayoutItems()
			local rowY = 0
			for _, item in next, items do
				local row = buildLayoutRow(listContent, item.value, rowY)
				layoutRowPool[#layoutRowPool + 1] = row
				rowY = rowY - ROW_H - 1
			end

			listContent:SetHeight(math.abs(rowY) + 1)
			listScroll:UpdateScrollRange()

			-- Also refresh auto-switch dropdowns (layout names may have changed)
			if(F.EventBus) then
				F.EventBus:Fire('LAYOUTS_REFRESHED')
			end
		end

		-- New Layout — prompt for name then create
		newBtn:SetOnClick(function()
			if(F.LayoutManager and F.LayoutManager.Create) then
				-- Show an input dialog for the layout name
				Widgets.ShowMessageDialog(
					'New Layout',
					'Enter a name in chat and type /framed layout create <name>.\n(UI input coming in a future update.)')
			end
		end)

		-- Initial population
		refreshLayoutList()

		-- ============================================================
		-- Section 2: Auto-Switch Assignments
		-- ============================================================
		local autoPane
		autoPane, yOffset = createSection(content, 'Auto-Switch Assignments', width, yOffset)

		-- Track all assignment dropdowns so they can be refreshed
		local assignDropdowns = {}

		for _, ct in next, CONTENT_TYPES do
			-- Row label
			local rowLabel = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textNormal)
			rowLabel:ClearAllPoints()
			Widgets.SetPoint(rowLabel, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
			rowLabel:SetText(ct.label)

			-- Assignment dropdown
			local dd = Widgets.CreateDropdown(content, WIDGET_W)
			dd:ClearAllPoints()
			Widgets.SetPoint(dd, 'TOPLEFT', content, 'TOPLEFT', 120, yOffset)
			dd:SetItems(getLayoutItems())

			local currentAssignment = getAutoSwitch(ct.id)
			if(currentAssignment) then
				dd:SetValue(currentAssignment)
			end

			local capturedId = ct.id
			dd:SetOnSelect(function(value)
				setAutoSwitch(capturedId, value)
			end)

			assignDropdowns[ct.id] = dd
			yOffset = yOffset - DROPDOWN_H - C.Spacing.normal

			-- ── Spec overrides for this content type ──────────
			local overrides = getSpecOverrides()
			local specKey = ct.id .. '_specs'
			if(overrides[specKey]) then
				for specName, layoutName in next, overrides[specKey] do
					local specRow = CreateFrame('Frame', nil, content)
					specRow:ClearAllPoints()
					Widgets.SetPoint(specRow, 'TOPLEFT', content, 'TOPLEFT', C.Spacing.loose, yOffset)
					specRow:SetHeight(DROPDOWN_H)

					local specLabel = Widgets.CreateFontString(specRow, C.Font.sizeSmall, C.Colors.textSecondary)
					specLabel:ClearAllPoints()
					Widgets.SetPoint(specLabel, 'LEFT', specRow, 'LEFT', 0, 0)
					specLabel:SetText(specName)

					local specDD = Widgets.CreateDropdown(content, 160)
					specDD:ClearAllPoints()
					Widgets.SetPoint(specDD, 'LEFT', specRow, 'LEFT', 100, 0)
					specDD:SetItems(getLayoutItems())
					specDD:SetValue(layoutName)

					local capturedSpec = specName
					local capturedCT   = ct.id
					specDD:SetOnSelect(function(value)
						local key2 = capturedCT .. '_specs'
						setSpecOverride(key2, value)
					end)

					-- Remove button
					local removeBtn = Widgets.CreateButton(content, '\xC3\x97', 'widget', 22, DROPDOWN_H)
					removeBtn:ClearAllPoints()
					Widgets.SetPoint(removeBtn, 'LEFT', specDD, 'RIGHT', C.Spacing.base, 0)
					removeBtn:SetOnClick(function()
						removeSpecOverride(capturedCT .. '_specs')
					end)

					yOffset = yOffset - DROPDOWN_H - C.Spacing.base
				end
			end

			-- "Add spec override" link
			local addSpecBtn = Widgets.CreateButton(content, '+ Add spec override', 'widget', 140, DROPDOWN_H - 4)
			addSpecBtn:ClearAllPoints()
			Widgets.SetPoint(addSpecBtn, 'TOPLEFT', content, 'TOPLEFT', C.Spacing.loose, yOffset)
			local capturedCTAdd = ct.id
			addSpecBtn:SetOnClick(function()
				-- Placeholder: in Phase 8 this opens a spec picker dropdown
				if(DEFAULT_CHAT_FRAME) then
					DEFAULT_CHAT_FRAME:AddMessage('|cff00ccffFramed:|r Spec override picker coming in a future update.')
				end
			end)
			yOffset = yOffset - (DROPDOWN_H - 4) - C.Spacing.normal
		end

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
