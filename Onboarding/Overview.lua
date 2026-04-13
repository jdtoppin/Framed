local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

F.Onboarding = F.Onboarding or {}
local Onboarding = F.Onboarding

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
-- luacheck: push ignore 211
local PIP_W          = 140
local PIP_H          = 32
-- luacheck: pop
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
-- Illustration builders
-- Each returns a frame parented to `host`, positioned and sized.
-- Failures (nil deps) return nil — caller hides the left column.
-- ============================================================

local illustrationTrash = CreateFrame('Frame')
illustrationTrash:Hide()

local function buildWelcomeIllustration(host, w, _h)
	if(not F.Preview or not F.Preview.GetFakeUnits or not F.Preview.CreatePreviewFrame) then
		return nil
	end

	local container = CreateFrame('Frame', nil, host)
	container:ClearAllPoints()
	container:SetAllPoints(host)

	local units = F.Preview.GetFakeUnits(3)
	if(not units or #units == 0) then return nil end

	local unitW = w - 8
	local unitH = 32
	local gap = 4
	for i, unit in next, units do
		local pf = F.Preview.CreatePreviewFrame(container, 'party', unitW, unitH)
		pf:ClearAllPoints()
		Widgets.SetPoint(pf, 'TOP', container, 'TOP', 0, -((i - 1) * (unitH + gap)))
		-- Apply fake unit data using Preview's public helper if available,
		-- else inline a minimal fallback (name only).
		if(F.Preview.ApplyUnitToFrame) then
			F.Preview.ApplyUnitToFrame(pf, unit)
		else
			if(pf._nameText) then pf._nameText:SetText(unit.name or '') end
		end
		pf:Show()
	end

	return container
end

-- ============================================================
-- Page registry
-- ============================================================

local PAGES = {
	{
		id = 'welcome',
		title = 'Welcome to Framed',
		body = 'Modern unit frames and raid frames, built around live previews, presets, and per-unit settings cards. Use this overview to get oriented — you can relaunch it anytime from Appearance → Setup Wizard.',
		buildIllustration = buildWelcomeIllustration,
	},
}

-- ============================================================
-- Page switcher
-- ============================================================

local activeIllustration = nil

local function clearActiveIllustration()
	if(activeIllustration) then
		activeIllustration:Hide()
		activeIllustration:SetParent(illustrationTrash)
		activeIllustration:ClearAllPoints()
		activeIllustration = nil
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

	-- Minimize button placeholder — uses Close icon temporarily until
	-- WindowMinimize.tga lands in Task 8. Tooltip already says 'Minimize'.
	headerMinimizeBtn = Widgets.CreateIconButton(header, F.Media.GetIcon('Close'), CLOSE_BTN_SIZE)
	headerMinimizeBtn:ClearAllPoints()
	Widgets.SetPoint(headerMinimizeBtn, 'RIGHT', headerCloseBtn, 'LEFT', -C.Spacing.tight, 0)
	headerMinimizeBtn:SetWidgetTooltip('Minimize')
	headerMinimizeBtn:SetBackdrop(nil)
	Widgets.SetupAccentHover(headerMinimizeBtn, headerMinimizeBtn._icon, true)
	-- Click wiring added in Task 8

	-- Progress rail slot host — populated in Task 7
	headerProgress = CreateFrame('Frame', nil, header)
	headerProgress:ClearAllPoints()
	Widgets.SetPoint(headerProgress, 'RIGHT', headerMinimizeBtn, 'LEFT', -C.Spacing.normal, 0)
	Widgets.SetSize(headerProgress, PROGRESS_SLOTS * PROGRESS_SIZE + (PROGRESS_SLOTS - 1) * PROGRESS_GAP, PROGRESS_SIZE)

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

	-- Page content wired in Task 4
	if(showPage) then showPage(1) end
end

function Onboarding.MinimizeOverview()
end

function Onboarding.RestoreOverview()
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
