local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local Settings = F.Settings

-- ============================================================
-- Sidebar Constants
-- ============================================================

local SIDEBAR_W          = 170
local SIDEBAR_SECTION_H  = 20
local SIDEBAR_BTN_H      = 22
local SIDEBAR_BTN_GAP    = 6
local HEADER_HEIGHT       = 24
local SUB_HEADER_H        = 32
local WINDOW_MIN_H        = 450
local WINDOW_MAX_H        = 900

local GRADIENT_TEXTURE = F.Media.GetTexture('GradientH')

-- Dim / hover / active colors (matching KeySorter exactly)
local DIM_ICON_R,   DIM_ICON_G,   DIM_ICON_B   = 0.5, 0.5, 0.5
local DIM_TEXT_R,   DIM_TEXT_G,   DIM_TEXT_B   = 0.6, 0.6, 0.6
local HOVER_R,      HOVER_G,      HOVER_B      = 1, 1, 1

-- ============================================================
-- AnimateWidth
-- OnUpdate-based linear interpolation of a texture's width.
-- ============================================================

local function AnimateWidth(texture, targetWidth, duration, onDone)
	local parentBtn = texture:GetParent()
	local startWidth = texture:GetWidth()
	if(startWidth < 1) then startWidth = 1 end
	local elapsed = 0
	parentBtn._widthAnimOnDone = onDone
	parentBtn:SetScript('OnUpdate', function(self, dt)
		elapsed = elapsed + dt
		local t = math.min(elapsed / duration, 1)
		local w = startWidth + (targetWidth - startWidth) * t
		texture:SetWidth(math.max(w, 1))
		if(t >= 1) then
			self:SetScript('OnUpdate', nil)
			if(self._widthAnimOnDone) then
				self._widthAnimOnDone()
				self._widthAnimOnDone = nil
			end
		end
	end)
end

-- ============================================================
-- Sidebar Selection
-- ============================================================

--- Animate a sidebar button to its selected or deselected state.
local function setSidebarSelected(btn, selected)
	if(selected) then
		btn._highlight:Show()
		btn._highlight:SetVertexColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
		AnimateWidth(btn._highlight, btn:GetWidth(), C.Animation.durationNormal)
		if(btn._icon) then
			btn._icon:SetVertexColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3])
		end
		if(btn._label) then
			btn._label:SetTextColor(HOVER_R, HOVER_G, HOVER_B)
		end
	else
		AnimateWidth(btn._highlight, 1, C.Animation.durationNormal, function()
			btn._highlight:Hide()
		end)
		if(btn._icon) then
			btn._icon:SetVertexColor(DIM_ICON_R, DIM_ICON_G, DIM_ICON_B)
		end
		if(btn._label) then
			btn._label:SetTextColor(DIM_TEXT_R, DIM_TEXT_G, DIM_TEXT_B)
		end
	end
end

-- Register with Framework so SetActivePanel can update sidebar selection
Settings._setSidebarSelected = setSidebarSelected

-- ============================================================
-- Button Factory
-- ============================================================

--- Create a single sidebar navigation button (KeySorter style).
--- @param parent Frame  The sidebar frame
--- @param panelInfo table  Panel registration info
--- @param yOffset number  Vertical offset from sidebar top
--- @return Button, number  The button frame and the next yOffset
local function createNavButton(parent, panelInfo, yOffset)
	local btn = CreateFrame('Button', nil, parent)
	btn:SetHeight(SIDEBAR_BTN_H)
	btn:ClearAllPoints()
	btn:SetPoint('TOPLEFT', parent, 'TOPLEFT', 2, yOffset)
	btn:SetPoint('TOPRIGHT', parent, 'TOPRIGHT', -3, yOffset)

	-- Gradient highlight (hidden by default, anchored left)
	local highlight = btn:CreateTexture(nil, 'BORDER')
	highlight:SetPoint('TOPLEFT', 0, 0)
	highlight:SetPoint('BOTTOMLEFT', 0, 0)
	highlight:SetWidth(1)
	highlight:SetTexture(GRADIENT_TEXTURE)
	highlight:SetVertexColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3], 1)
	highlight:Hide()
	btn._highlight = highlight

	-- Icon (optional — only shown if panel provides one)
	local labelLeftAnchor = btn
	local labelLeftOffset = 8
	if(panelInfo.icon) then
		local icon = btn:CreateTexture(nil, 'ARTWORK')
		icon:SetSize(14, 14)
		icon:SetPoint('LEFT', 6, 0)
		icon:SetTexture(panelInfo.icon)
		icon:SetVertexColor(DIM_ICON_R, DIM_ICON_G, DIM_ICON_B)
		btn._icon = icon
		labelLeftAnchor = icon
		labelLeftOffset = 8
	end

	-- Label
	local label = btn:CreateFontString(nil, 'OVERLAY')
	label:SetFont(F.Media.GetActiveFont(), C.Font.sizeSmall, '')
	label:SetShadowOffset(1, -1)
	label:SetTextColor(C.Colors.textNormal[1], C.Colors.textNormal[2], C.Colors.textNormal[3])
	if(panelInfo.icon) then
		label:SetPoint('LEFT', labelLeftAnchor, 'RIGHT', labelLeftOffset, 0)
	else
		label:SetPoint('LEFT', btn, 'LEFT', 8, 0)
	end
	label:SetText(panelInfo.label)
	label:SetTextColor(DIM_TEXT_R, DIM_TEXT_G, DIM_TEXT_B)
	btn._label = label

	-- Push effect
	local origOffsetY = 0
	btn:SetScript('OnMouseDown', function(self)
		if(self._icon) then
			local point, rel, relPoint, x, _ = self._icon:GetPoint()
			self._icon:SetPoint(point, rel, relPoint, x, -1)
		end
	end)
	btn:SetScript('OnMouseUp', function(self)
		if(self._icon) then
			local point, rel, relPoint, x, _ = self._icon:GetPoint()
			self._icon:SetPoint(point, rel, relPoint, x, 0)
		end
	end)

	-- Hover
	btn:SetScript('OnEnter', function(self)
		if(self.value ~= Settings._activePanelId) then
			AnimateWidth(highlight, 7, C.Animation.durationFast)
			highlight:Show()
			if(self._icon) then
				self._icon:SetVertexColor(HOVER_R, HOVER_G, HOVER_B)
			end
			label:SetTextColor(HOVER_R, HOVER_G, HOVER_B)
		end
	end)

	btn:SetScript('OnLeave', function(self)
		if(self.value ~= Settings._activePanelId) then
			AnimateWidth(highlight, 1, C.Animation.durationFast, function()
				if(self.value ~= Settings._activePanelId) then
					highlight:Hide()
				end
			end)
			if(self._icon) then
				self._icon:SetVertexColor(DIM_ICON_R, DIM_ICON_G, DIM_ICON_B)
			end
			label:SetTextColor(DIM_TEXT_R, DIM_TEXT_G, DIM_TEXT_B)
		end
	end)

	-- Click → switch panel
	local panelId = panelInfo.id
	btn.value = panelId
	btn:SetScript('OnClick', function()
		Settings.SetActivePanel(panelId)
	end)

	return btn
end

-- ============================================================
-- Sub-heading Heights
-- ============================================================

local SUBHEADING_H    = 16   -- vertical space consumed by a sub-heading label
local EDITING_LABEL_H = 16   -- vertical space consumed by the editing preset label

-- ============================================================
-- Dynamic Group Frame Label
-- ============================================================

--- Return the sidebar label for the group frame button based on the
--- current editing preset, or nil if the preset has no group frames.
local function getGroupFrameLabel()
	local info = C.PresetInfo[Settings.GetEditingPreset()]
	return info and info.groupLabel or nil
end

-- ============================================================
-- Sidebar Builder
-- ============================================================

--- Build the sidebar panel buttons. Called once on first show.
--- @param sidebar Frame
local function buildSidebarContent(sidebar)
	local registeredPanels = Settings._panels
	local sectionOrder = Settings._sectionOrder
	local SECTIONS = Settings._SECTIONS

	-- Sort panels: section order first, then panel order within section
	table.sort(registeredPanels, function(a, b)
		local sa = sectionOrder[a.section] or 99
		local sb = sectionOrder[b.section] or 99
		if(sa ~= sb) then return sa < sb end
		return (a.order or 0) < (b.order or 0)
	end)

	-- Group panels by section (preserving sort order)
	local sectionPanels = {}
	local orderedSections = {}

	for _, panel in next, registeredPanels do
		local sid = panel.section or 'GLOBAL'
		if(not sectionPanels[sid]) then
			sectionPanels[sid] = {}
			orderedSections[#orderedSections + 1] = sid
		end
		sectionPanels[sid][#sectionPanels[sid] + 1] = panel
	end

	local yOffset = -8

	-- References for dynamic elements updated by EDITING_PRESET_CHANGED
	local editingLabel
	local groupFrameBtn

	for _, sectionId in next, orderedSections do
		-- Find section definition
		local sectionLabel = sectionId
		local isBottomSection = false
		local isPresetScoped = false
		for _, s in next, SECTIONS do
			if(s.id == sectionId) then
				sectionLabel = s.label
				if(s.id == 'BOTTOM') then
					isBottomSection = true
				end
				if(s.id == 'PRESET_SCOPED') then
					isPresetScoped = true
				end
				break
			end
		end

		-- Separator line before BOTTOM section (and between sections)
		if(isBottomSection or yOffset < -8) then
			local sep = sidebar:CreateTexture(nil, 'ARTWORK')
			sep:SetHeight(1)
			sep:SetColorTexture(0.25, 0.25, 0.25, 1)
			sep:ClearAllPoints()
			sep:SetPoint('TOPLEFT',  sidebar, 'TOPLEFT',  6, yOffset - 4)
			sep:SetPoint('TOPRIGHT', sidebar, 'TOPRIGHT', -6, yOffset - 4)
			yOffset = yOffset - 10
		end

		-- ── PRESET_SCOPED section: custom rendering ──────────────
		if(isPresetScoped) then
			local panels = sectionPanels[sectionId]

			-- Split panels into frames vs auras sub-groups
			local framePanels = {}
			local auraPanels = {}
			for _, panel in next, panels do
				if(panel.subSection == 'auras') then
					auraPanels[#auraPanels + 1] = panel
				else
					framePanels[#framePanels + 1] = panel
				end
			end

			-- "Editing: X Frame Preset" accent label
			editingLabel = sidebar:CreateFontString(nil, 'OVERLAY')
			editingLabel:SetFont(F.Media.GetActiveFont(), C.Font.sizeSmall, '')
			editingLabel:SetTextColor(C.Colors.accent[1], C.Colors.accent[2], C.Colors.accent[3])
			editingLabel:SetText('Editing: ' .. Settings.GetEditingPreset() .. ' Frame Preset')
			editingLabel:ClearAllPoints()
			editingLabel:SetPoint('TOPLEFT', sidebar, 'TOPLEFT', 12, yOffset)
			yOffset = yOffset - EDITING_LABEL_H

			-- FRAMES sub-heading
			local framesHeading = sidebar:CreateFontString(nil, 'OVERLAY')
			framesHeading:SetFont(F.Media.GetActiveFont(), C.Font.sizeSmall, '')
			framesHeading:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3])
			framesHeading:SetText('FRAMES')
			framesHeading:ClearAllPoints()
			framesHeading:SetPoint('TOPLEFT', sidebar, 'TOPLEFT', 12, yOffset)
			yOffset = yOffset - SUBHEADING_H

			-- Frame panel buttons
			for _, panel in next, framePanels do
				local btn = createNavButton(sidebar, panel, yOffset)
				Settings._sidebarButtons[panel.id] = btn

				-- Group frame button — dynamic label & visibility per preset
				if(panel.id == 'party') then
					groupFrameBtn = btn
					local groupLabel = getGroupFrameLabel()
					if(groupLabel) then
						btn._label:SetText(groupLabel)
						btn:Show()
					else
						btn:Hide()
					end
				end

				-- Boss button is always visible regardless of preset
				-- (no special handling needed — it stays shown)

				yOffset = yOffset - SIDEBAR_BTN_H - SIDEBAR_BTN_GAP
			end

			-- AURAS sub-heading (only if there are aura panels)
			if(#auraPanels > 0) then
				local aurasHeading = sidebar:CreateFontString(nil, 'OVERLAY')
				aurasHeading:SetFont(F.Media.GetActiveFont(), C.Font.sizeSmall, '')
				aurasHeading:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3])
				aurasHeading:SetText('AURAS')
				aurasHeading:ClearAllPoints()
				aurasHeading:SetPoint('TOPLEFT', sidebar, 'TOPLEFT', 12, yOffset)
				yOffset = yOffset - SUBHEADING_H

				-- Aura panel buttons
				for _, panel in next, auraPanels do
					local btn = createNavButton(sidebar, panel, yOffset)
					Settings._sidebarButtons[panel.id] = btn
					yOffset = yOffset - SIDEBAR_BTN_H - SIDEBAR_BTN_GAP
				end
			end
		else
			-- ── Standard section rendering ───────────────────────────

			-- Section header text (skip empty label for BOTTOM)
			if(sectionLabel ~= '' and sectionId ~= 'FRAME_PRESETS') then
				local headerText = sidebar:CreateFontString(nil, 'ARTWORK')
				headerText:SetFont(F.Media.GetActiveFont(), C.Font.sizeSmall, '')
				headerText:SetShadowOffset(1, -1)
				headerText:ClearAllPoints()
				headerText:SetPoint('TOPLEFT', sidebar, 'TOPLEFT', 8, yOffset)
				headerText:SetText(sectionLabel)
				headerText:SetTextColor(C.Colors.textSecondary[1], C.Colors.textSecondary[2], C.Colors.textSecondary[3])
				yOffset = yOffset - SIDEBAR_SECTION_H
			end

			-- Panel buttons for this section
			local panels = sectionPanels[sectionId]
			for _, panel in next, panels do
				local btn = createNavButton(sidebar, panel, yOffset)
				Settings._sidebarButtons[panel.id] = btn
				yOffset = yOffset - SIDEBAR_BTN_H - SIDEBAR_BTN_GAP
			end
		end
	end

	-- ── EDITING_PRESET_CHANGED listener ──────────────────────
	F.EventBus:Register('EDITING_PRESET_CHANGED', function(presetName)
		if(editingLabel) then
			editingLabel:SetText('Editing: ' .. presetName .. ' Frame Preset')
		end
		if(groupFrameBtn) then
			local groupLabel = getGroupFrameLabel()
			if(groupLabel) then
				groupFrameBtn:Show()
				groupFrameBtn._label:SetText(groupLabel)
			else
				groupFrameBtn:Hide()
			end
		end
	end, 'Sidebar')

	-- Deferred highlight fix — button widths aren't final until first layout
	C_Timer.After(0, function()
		if(Settings._activePanelId and Settings._sidebarButtons[Settings._activePanelId]) then
			local activeBtn = Settings._sidebarButtons[Settings._activePanelId]
			activeBtn._highlight:SetWidth(activeBtn:GetWidth())
		end
	end)

	-- Return total sidebar content height (positive value)
	return math.abs(yOffset) + 8
end

-- ============================================================
-- Sidebar Build (deferred to first show)
-- ============================================================

--- Build sidebar content and resize the window to fit.
function Settings.BuildSidebar()
	if(Settings._sidebarBuilt or not Settings._mainFrame) then return end
	Settings._sidebarBuilt = true

	local sidebarHeight = buildSidebarContent(Settings._mainFrame._sidebar)

	-- Resize window to fit sidebar content + header + padding
	local neededH = sidebarHeight + HEADER_HEIGHT + C.Spacing.tight
	neededH = math.max(neededH, WINDOW_MIN_H)
	neededH = math.min(neededH, WINDOW_MAX_H)

	local WINDOW_H = 600
	if(neededH ~= WINDOW_H) then
		Settings._mainFrame:SetHeight(neededH)
		if(Settings._contentParent) then
			local contentH = neededH - HEADER_HEIGHT - SUB_HEADER_H
			Settings._contentParent:SetHeight(contentH)
			Settings._contentParent._explicitHeight = contentH
		end
	end

	-- Auto-select first registered panel
	local registeredPanels = Settings._panels
	if(#registeredPanels > 0) then
		Settings.SetActivePanel(registeredPanels[1].id)
	end
end
