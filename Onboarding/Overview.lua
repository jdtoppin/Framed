local addonName, Framed = ...
-- luacheck: ignore 211
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

F.Onboarding = F.Onboarding or {}
local Onboarding = F.Onboarding

local Illus = F.OverviewIllustrations

-- ============================================================
-- Constants
-- ============================================================

local MODAL_W        = 540
local MODAL_H        = 380
local HEADER_H       = 40
local FOOTER_H       = 44
local CONTENT_PAD    = C.Spacing.loose
local ILLUSTRATION_W = 180
local ILLUSTRATION_H = 220
local PIP_W          = 140
local PIP_H          = 32
local PROGRESS_SLOTS = 6
local PROGRESS_SIZE  = 16
local PROGRESS_GAP   = 6
local BTN_W          = 110
local BTN_H          = 26
local CLOSE_BTN_SIZE = 20

-- ============================================================
-- State
-- ============================================================

local modalFrame  = nil
local pipFrame    = nil
local currentStep = 1
local isMinimized = false -- luacheck: ignore 231

-- ============================================================
-- Modal frame construction (lazy)
-- ============================================================

local headerTitle, headerProgress, headerCloseBtn, headerMinimizeBtn
local bodyIllustrationHost, bodyTitle, bodyCopy
local footerBackBtn, footerSkipBtn, footerNextBtn

local showPage
-- forward declaration, defined below

-- ============================================================
-- Page registry
-- ============================================================

local PAGES = {
	{
		id = 'welcome',
		title = 'Welcome to Framed',
		body = 'Modern unit frames and raid frames, built around live previews, presets, and per-unit settings cards. Use this overview to get oriented — you can relaunch it anytime from Appearance → Setup Wizard.',
		buildIllustration = Illus.BuildWelcome,
	},
	{
		id = 'layouts',
		title = 'Layouts & Auto-Switch',
		body = 'Framed ships layouts for Solo, Party, Raid, Mythic Raid, World Raid, Battleground, and Arena — and swaps them automatically when content changes. You can still edit any layout manually from the Layouts sidebar.',
		buildIllustration = function(host, _w, _h)
			return Illus.BuildAtlas(host, 'groupfinder-eye-frame', 96)
		end,
	},
	{
		id = 'editmode',
		title = 'Edit Mode',
		body = 'Drag any frame to reposition it. The inline panel jumps you to that frame\'s settings, and edits stay live until you click Save or Discard.',
		buildIllustration = function(host, _w, _h)
			return Illus.BuildAtlas(host, 'editmode-new-icon', 96)
		end,
	},
	{ id = 'cards',      title = 'Settings Cards',           body = 'Each unit has a grid of focused cards — Position, Health, Power, Auras, and more. Pin the ones you use most so they stick to the top of the grid.',                                                                      buildIllustration = Illus.BuildCards      },
	{ id = 'indicators', title = 'Buffs, Debuffs & Dispels', body = 'Build custom indicators for specific spells — borders, overlays, or icons. Dispellable debuffs get their own highlight system so healers can spot them instantly.',                                                     buildIllustration = Illus.BuildIndicators },
	{ id = 'defensives', title = 'Defensives & Externals',   body = 'Track raid cooldowns cast on units — personal defensives on yourself, externals cast on someone else. Same indicator builder UX as buffs and debuffs.', buildIllustration = Illus.BuildDefensives },
}

-- ============================================================
-- Page switcher
-- ============================================================

local illustrationTrash = CreateFrame('Frame')
illustrationTrash:Hide()

local activeIllustration = nil

local function clearActiveIllustration()
	if(activeIllustration) then
		activeIllustration:Hide()
		activeIllustration:SetParent(illustrationTrash)
		activeIllustration:ClearAllPoints()
		activeIllustration = nil
	end
end

local function updateProgressRail()
	if(not headerProgress or not headerProgress._slots) then return end
	local ac = C.Colors.accent
	for i = 1, PROGRESS_SLOTS do
		local slot = headerProgress._slots[i]
		if(i < currentStep) then
			-- Completed: full color, full alpha
			slot:SetVertexColor(1, 1, 1, 1)
		elseif(i == currentStep) then
			-- Current: accent tinted
			slot:SetVertexColor(ac[1], ac[2], ac[3], 1)
		else
			-- Future: desaturated, low alpha
			slot:SetVertexColor(0.6, 0.6, 0.6, 0.3)
		end
	end
end

showPage = function(n)
	if(not modalFrame) then return end
	if(n < 1 or n > #PAGES) then return end

	currentStep = n
	local page = PAGES[n]

	clearActiveIllustration()
	if(page.buildIllustration) then
		activeIllustration = page.buildIllustration(bodyIllustrationHost, ILLUSTRATION_W, ILLUSTRATION_H)
		if(activeIllustration) then
			activeIllustration:ClearAllPoints()
			activeIllustration:SetAllPoints(bodyIllustrationHost)
			activeIllustration:Show()
		end
	end

	bodyTitle:SetText(page.title)
	bodyCopy:SetText(page.body)

	-- Footer button state
	footerBackBtn:SetEnabled(n > 1)
	local isLast = (n == #PAGES)
	footerNextBtn:SetText(isLast and 'Done' or 'Next →')

	updateProgressRail()
end

local function buildModalFrame()
	if(modalFrame) then return end

	-- Outer bordered dialog frame
	local frame = Widgets.CreateBorderedFrame(UIParent, MODAL_W, MODAL_H, C.Colors.panel, C.Colors.border)
	frame:SetFrameStrata('FULLSCREEN_DIALOG')
	frame:SetFrameLevel(10)
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
	frame:EnableMouse(true)
	frame:Hide()

	-- Accent top border (3px) — matches wizard styling
	local accentBorder = frame:CreateTexture(nil, 'OVERLAY')
	accentBorder:SetHeight(3)
	local ac = C.Colors.accent
	accentBorder:SetColorTexture(ac[1], ac[2], ac[3], ac[4] or 1)
	accentBorder:ClearAllPoints()
	accentBorder:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
	accentBorder:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)

	-- ── Header row ────────────────────────────────────────────
	local header = CreateFrame('Frame', nil, frame)
	header:ClearAllPoints()
	Widgets.SetPoint(header, 'TOPLEFT',  frame, 'TOPLEFT',  CONTENT_PAD, -CONTENT_PAD)
	Widgets.SetPoint(header, 'TOPRIGHT', frame, 'TOPRIGHT', -CONTENT_PAD, -CONTENT_PAD)
	Widgets.SetSize(header, MODAL_W - CONTENT_PAD * 2, HEADER_H)

	headerTitle = Widgets.CreateFontString(header, C.Font.sizeTitle, C.Colors.accent)
	headerTitle:ClearAllPoints()
	Widgets.SetPoint(headerTitle, 'LEFT', header, 'LEFT', 0, 0)
	headerTitle:SetText('Framed Overview')

	headerCloseBtn = Widgets.CreateIconButton(header, F.Media.GetIcon('Close'), CLOSE_BTN_SIZE)
	headerCloseBtn:ClearAllPoints()
	Widgets.SetPoint(headerCloseBtn, 'RIGHT', header, 'RIGHT', 0, 0)
	headerCloseBtn:SetWidgetTooltip('Close')
	headerCloseBtn:SetBackdrop(nil)
	Widgets.SetupAccentHover(headerCloseBtn, headerCloseBtn._icon, true)
	headerCloseBtn:SetOnClick(function()
		Onboarding.CloseOverview()
	end)

	headerMinimizeBtn = Widgets.CreateIconButton(header, F.Media.GetIcon('WindowMinimize'), CLOSE_BTN_SIZE)
	headerMinimizeBtn:ClearAllPoints()
	Widgets.SetPoint(headerMinimizeBtn, 'RIGHT', headerCloseBtn, 'LEFT', -C.Spacing.tight, 0)
	headerMinimizeBtn:SetWidgetTooltip('Minimize')
	headerMinimizeBtn:SetBackdrop(nil)
	Widgets.SetupAccentHover(headerMinimizeBtn, headerMinimizeBtn._icon, true)
	headerMinimizeBtn:SetOnClick(function()
		Onboarding.MinimizeOverview()
	end)

	-- Progress rail slot host
	headerProgress = CreateFrame('Frame', nil, header)
	headerProgress:ClearAllPoints()
	Widgets.SetPoint(headerProgress, 'RIGHT', headerMinimizeBtn, 'LEFT', -C.Spacing.normal, 0)
	Widgets.SetSize(headerProgress, PROGRESS_SLOTS * PROGRESS_SIZE + (PROGRESS_SLOTS - 1) * PROGRESS_GAP, PROGRESS_SIZE)

	-- Build 6 slot textures stored on headerProgress._slots
	headerProgress._slots = {}
	for i = 1, PROGRESS_SLOTS do
		local slot = headerProgress:CreateTexture(nil, 'ARTWORK')
		slot:SetTexture(F.Media.GetIcon('Fluent_Color_Yes'))
		slot:SetSize(PROGRESS_SIZE, PROGRESS_SIZE)
		slot:ClearAllPoints()
		slot:SetPoint('LEFT', headerProgress, 'LEFT', (i - 1) * (PROGRESS_SIZE + PROGRESS_GAP), 0)
		headerProgress._slots[i] = slot
	end

	-- ── Footer row ────────────────────────────────────────────
	local footer = CreateFrame('Frame', nil, frame)
	footer:ClearAllPoints()
	Widgets.SetPoint(footer, 'BOTTOMLEFT',  frame, 'BOTTOMLEFT',  CONTENT_PAD, CONTENT_PAD)
	Widgets.SetPoint(footer, 'BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -CONTENT_PAD, CONTENT_PAD)
	Widgets.SetSize(footer, MODAL_W - CONTENT_PAD * 2, FOOTER_H)

	footerBackBtn = Widgets.CreateButton(footer, '← Back', 'widget', BTN_W, BTN_H)
	footerBackBtn:ClearAllPoints()
	Widgets.SetPoint(footerBackBtn, 'LEFT', footer, 'LEFT', 0, 0)
	footerBackBtn:SetOnClick(function()
		if(currentStep > 1) then
			showPage(currentStep - 1)
		end
	end)

	footerSkipBtn = Widgets.CreateButton(footer, 'Skip Overview', 'widget', BTN_W, BTN_H)
	footerSkipBtn:ClearAllPoints()
	Widgets.SetPoint(footerSkipBtn, 'CENTER', footer, 'CENTER', 0, 0)
	footerSkipBtn:SetOnClick(function()
		F.Config:Set('general.overviewCompleted', true)
		Onboarding.CloseOverview()
	end)

	footerNextBtn = Widgets.CreateButton(footer, 'Next →', 'accent', BTN_W, BTN_H)
	footerNextBtn:ClearAllPoints()
	Widgets.SetPoint(footerNextBtn, 'RIGHT', footer, 'RIGHT', 0, 0)
	footerNextBtn:SetOnClick(function()
		if(currentStep >= #PAGES) then
			-- Done on last page → mark completed + close
			F.Config:Set('general.overviewCompleted', true)
			Onboarding.CloseOverview()
		else
			showPage(currentStep + 1)
		end
	end)

	-- ── Body ──────────────────────────────────────────────────
	local body = CreateFrame('Frame', nil, frame)
	body:ClearAllPoints()
	Widgets.SetPoint(body, 'TOPLEFT',     header, 'BOTTOMLEFT',  0, -C.Spacing.normal)
	Widgets.SetPoint(body, 'BOTTOMRIGHT', footer, 'TOPRIGHT',    0,  C.Spacing.normal)

	bodyIllustrationHost = CreateFrame('Frame', nil, body)
	bodyIllustrationHost:ClearAllPoints()
	Widgets.SetPoint(bodyIllustrationHost, 'TOPLEFT', body, 'TOPLEFT', 0, 0)
	Widgets.SetSize(bodyIllustrationHost, ILLUSTRATION_W, ILLUSTRATION_H)

	bodyTitle = Widgets.CreateFontString(body, C.Font.sizeTitle, C.Colors.accent)
	bodyTitle:ClearAllPoints()
	Widgets.SetPoint(bodyTitle, 'TOPLEFT', bodyIllustrationHost, 'TOPRIGHT', C.Spacing.normal, 0)

	bodyCopy = Widgets.CreateFontString(body, C.Font.sizeNormal, C.Colors.textNormal)
	bodyCopy:ClearAllPoints()
	Widgets.SetPoint(bodyCopy, 'TOPLEFT', bodyTitle, 'BOTTOMLEFT', 0, -C.Spacing.normal)
	local rightColumnW = MODAL_W - CONTENT_PAD * 2 - ILLUSTRATION_W - C.Spacing.normal
	bodyCopy:SetWidth(rightColumnW)
	bodyCopy:SetWordWrap(true)
	bodyCopy:SetJustifyH('LEFT')
	bodyCopy:SetJustifyV('TOP')

	-- Keyboard handling placeholder (Escape consumes event — minimize wired in Task 9)
	frame:EnableKeyboard(true)
	frame:SetScript('OnKeyDown', function(self, key)
		if(key == 'ESCAPE') then
			self:SetPropagateKeyboardInput(false)
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)

	Widgets.RegisterForUIScale(frame)

	modalFrame = frame
end

-- ============================================================
-- Minimize pip
-- ============================================================

local pipLabel
local pipIcon

local function buildPipFrame()
	if(pipFrame) then return end

	local pip = Widgets.CreateBorderedFrame(UIParent, PIP_W, PIP_H, C.Colors.panel, C.Colors.border)
	pip:SetFrameStrata('FULLSCREEN_DIALOG')
	pip:SetFrameLevel(20)
	pip:ClearAllPoints()
	pip:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -20, -20)
	pip:EnableMouse(true)
	pip:Hide()

	pipIcon = pip:CreateTexture(nil, 'ARTWORK')
	pipIcon:SetTexture(F.Media.GetIcon('Fluent_Color_Yes'))
	pipIcon:SetSize(16, 16)
	pipIcon:ClearAllPoints()
	pipIcon:SetPoint('LEFT', pip, 'LEFT', 8, 0)

	pipLabel = Widgets.CreateFontString(pip, C.Font.sizeSmall, C.Colors.textNormal)
	pipLabel:ClearAllPoints()
	Widgets.SetPoint(pipLabel, 'LEFT', pipIcon, 'RIGHT', 6, 0)
	pipLabel:SetText('Framed Overview — 1/6')

	pip:SetScript('OnMouseUp', function(_, button)
		if(button == 'LeftButton') then
			Onboarding.RestoreOverview()
		end
	end)

	pip:SetScript('OnEnter', function(self)
		if(Widgets.ShowTooltip) then
			Widgets.ShowTooltip(self, 'Framed Overview', 'Click to resume walkthrough')
		end
	end)
	pip:SetScript('OnLeave', function()
		if(Widgets.HideTooltip) then Widgets.HideTooltip() end
	end)

	pipFrame = pip
end

local function updatePipLabel()
	if(pipLabel) then
		pipLabel:SetText('Framed Overview — ' .. currentStep .. '/' .. PROGRESS_SLOTS)
	end
end

-- ============================================================
-- Public API
-- ============================================================

function Onboarding.ShowOverview()
	if(InCombatLockdown()) then
		if(DEFAULT_CHAT_FRAME) then
			DEFAULT_CHAT_FRAME:AddMessage('|cff00ccffFramed:|r Framed Overview cannot be opened in combat.')
		end
		return
	end

	if(not modalFrame) then
		buildModalFrame()
	end

	currentStep = 1
	isMinimized = false
	if(pipFrame) then pipFrame:Hide() end
	Widgets.FadeIn(modalFrame)

	showPage(1)
end

function Onboarding.MinimizeOverview()
	if(not modalFrame or not modalFrame:IsShown()) then return end
	if(not pipFrame) then
		buildPipFrame()
	end
	isMinimized = true
	modalFrame:Hide()
	updatePipLabel()
	pipFrame:Show()
end

function Onboarding.RestoreOverview()
	if(not pipFrame or not pipFrame:IsShown()) then return end
	isMinimized = false
	pipFrame:Hide()
	if(not modalFrame) then
		buildModalFrame()
	end
	modalFrame:Show()
	if(showPage) then showPage(currentStep) end
end

function Onboarding.CloseOverview()
	if(modalFrame) then
		Widgets.FadeOut(modalFrame)
	end
	if(pipFrame) then
		pipFrame:Hide()
	end
	isMinimized = false
end

function Onboarding.IsOverviewActive()
	return (modalFrame and modalFrame:IsShown()) or (pipFrame and pipFrame:IsShown()) or false
end
