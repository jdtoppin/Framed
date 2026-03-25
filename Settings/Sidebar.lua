local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants
local Settings = F.Settings

-- ============================================================
-- Sidebar Constants
-- ============================================================

local SIDEBAR_W          = 170
local SIDEBAR_SECTION_H  = 22
local SIDEBAR_BTN_H      = 26
local SIDEBAR_ACCENT_W   = 2
local HEADER_HEIGHT       = 24
local SUB_HEADER_H        = 32
local WINDOW_MIN_H        = 450
local WINDOW_MAX_H        = 900

-- ============================================================
-- Sidebar Accent Border Helper
-- ============================================================

--- Draw or clear the 2px left accent border on a sidebar button.
local function setSidebarSelected(btn, selected)
	if(selected) then
		btn:SetBackdropColor(
			C.Colors.accentDim[1],
			C.Colors.accentDim[2],
			C.Colors.accentDim[3],
			C.Colors.accentDim[4] or 1)
		btn:SetBackdropBorderColor(0, 0, 0, 1)
		if(btn._label) then
			btn._label:SetTextColor(1, 1, 1, 1)
		end
		if(btn._accentBar) then
			btn._accentBar:Show()
		end
	else
		btn:SetBackdropColor(
			C.Colors.widget[1],
			C.Colors.widget[2],
			C.Colors.widget[3],
			C.Colors.widget[4] or 1)
		btn:SetBackdropBorderColor(0, 0, 0, 1)
		if(btn._label) then
			local tc = C.Colors.textNormal
			btn._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
		if(btn._accentBar) then
			btn._accentBar:Hide()
		end
	end
end

-- Register with Framework so SetActivePanel can update sidebar selection
Settings._setSidebarSelected = setSidebarSelected

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
		local sid = panel.section or 'GENERAL'
		if(not sectionPanels[sid]) then
			sectionPanels[sid] = {}
			orderedSections[#orderedSections + 1] = sid
		end
		sectionPanels[sid][#sectionPanels[sid] + 1] = panel
	end

	local yOffset = -C.Spacing.tight

	for _, sectionId in next, orderedSections do
		-- Find section definition
		local sectionLabel = sectionId
		local isBottomSection = false
		for _, s in next, SECTIONS do
			if(s.id == sectionId) then
				sectionLabel = s.label
				if(s.id == 'BOTTOM') then
					isBottomSection = true
				end
				break
			end
		end

		-- Separator line before BOTTOM section
		if(isBottomSection) then
			local sep = sidebar:CreateTexture(nil, 'ARTWORK')
			sep:SetHeight(1)
			sep:SetColorTexture(
				C.Colors.border[1],
				C.Colors.border[2],
				C.Colors.border[3],
				C.Colors.border[4] or 1)
			sep:ClearAllPoints()
			Widgets.SetPoint(sep, 'TOPLEFT',  sidebar, 'TOPLEFT',  0, yOffset)
			Widgets.SetPoint(sep, 'TOPRIGHT', sidebar, 'TOPRIGHT', 0, yOffset)
			yOffset = yOffset - C.Spacing.tight
		end

		-- Section header text (skip empty label for BOTTOM)
		if(sectionLabel ~= '') then
			local headerText = Widgets.CreateFontString(sidebar, C.Font.sizeSmall, C.Colors.textSecondary)
			headerText:ClearAllPoints()
			Widgets.SetPoint(headerText, 'TOPLEFT', sidebar, 'TOPLEFT', C.Spacing.normal, yOffset)
			headerText:SetText(sectionLabel)
			yOffset = yOffset - SIDEBAR_SECTION_H
		end

		-- Panel buttons for this section
		local panels = sectionPanels[sectionId]
		for _, panel in next, panels do
			local btn = Widgets.CreateButton(sidebar, panel.label, 'widget', SIDEBAR_W, SIDEBAR_BTN_H)
			btn:ClearAllPoints()
			Widgets.SetPoint(btn, 'TOPLEFT',  sidebar, 'TOPLEFT',  0, yOffset)
			Widgets.SetPoint(btn, 'TOPRIGHT', sidebar, 'TOPRIGHT', 0, yOffset)

			-- Left-align the label
			if(btn._label) then
				btn._label:ClearAllPoints()
				Widgets.SetPoint(btn._label, 'LEFT', btn, 'LEFT', C.Spacing.normal + SIDEBAR_ACCENT_W + C.Spacing.base, 0)
				btn._label:SetJustifyH('LEFT')
			end

			-- 2px accent left bar (hidden by default)
			local accentBar = btn:CreateTexture(nil, 'OVERLAY')
			accentBar:SetWidth(SIDEBAR_ACCENT_W)
			accentBar:SetPoint('TOPLEFT',    btn, 'TOPLEFT',    0, 0)
			accentBar:SetPoint('BOTTOMLEFT', btn, 'BOTTOMLEFT', 0, 0)
			accentBar:SetColorTexture(
				C.Colors.accent[1],
				C.Colors.accent[2],
				C.Colors.accent[3],
				C.Colors.accent[4] or 1)
			accentBar:Hide()
			btn._accentBar = accentBar

			-- Hover: highlight non-active buttons
			btn:SetScript('OnEnter', function(self)
				if(self.value ~= Settings._activePanelId) then
					Widgets.SetBackdropHighlight(self, true)
				end
				if(Widgets.ShowTooltip and self._tooltipTitle) then
					Widgets.ShowTooltip(self, self._tooltipTitle, self._tooltipBody)
				end
			end)

			btn:SetScript('OnLeave', function(self)
				if(self.value ~= Settings._activePanelId) then
					Widgets.SetBackdropHighlight(self, false)
				end
				if(Widgets.HideTooltip) then
					Widgets.HideTooltip()
				end
			end)

			local panelId = panel.id
			btn.value = panelId
			btn:SetOnClick(function()
				Settings.SetActivePanel(panelId)
			end)

			Settings._sidebarButtons[panel.id] = btn
			yOffset = yOffset - SIDEBAR_BTN_H
		end

		-- Gap after each section
		yOffset = yOffset - C.Spacing.tight
	end

	-- Return total sidebar content height (positive value)
	return math.abs(yOffset) + C.Spacing.tight
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
