local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

F.Onboarding = F.Onboarding or {}
local Onboarding = F.Onboarding

-- ============================================================
-- Tour Stop Definitions
-- ============================================================

local TOUR_STOPS = {
	{
		title     = 'Sidebar Navigation',
		body      = 'Navigate between frame types and settings categories.',
		getTarget = function() return F.Settings._sidebar end,
	},
	{
		title     = 'Settings Area',
		body      = 'Frame settings and configuration options live here.',
		getTarget = function() return F.Settings._contentArea end,
	},
	{
		title     = 'Live Preview',
		body      = 'See changes in real-time as you adjust settings.',
		getTarget = function() return F.Settings._previewArea end,
	},
	{
		title     = 'Edit Mode',
		body      = 'Drag frames around your screen to position them.',
		getTarget = function() return F.Settings._editModeBtn end,
	},
	{
		title     = 'Preview Toggle',
		body      = 'Show fake data to test your settings without being in a group.',
		getTarget = function() return F.Settings._previewToggle end,
	},
	{
		title     = 'Layouts',
		body      = 'Create and manage frame layouts for different content types.',
		getTarget = function()
			return F.Settings._sidebarButtons and F.Settings._sidebarButtons['layouts']
		end,
	},
	{
		title     = 'Context Info',
		body      = 'Shows your current layout and specialization.',
		getTarget = function() return F.Settings._headerBar end,
	},
}

local TOTAL_STOPS = #TOUR_STOPS

-- ============================================================
-- Tour State
-- ============================================================

local tourActive   = false
local currentStop  = 1

-- Dimmer frames (top, bottom, left, right)
local dimmers      = {}
local calloutFrame = nil

-- ============================================================
-- Dimmer Helpers
-- ============================================================

local function ensureDimmers()
	if(#dimmers == 4) then return end

	for i = 1, 4 do
		local d = CreateFrame('Frame', nil, UIParent)
		d:SetFrameStrata('FULLSCREEN_DIALOG')
		local tex = d:CreateTexture(nil, 'BACKGROUND')
		tex:SetAllPoints(d)
		tex:SetColorTexture(0, 0, 0, 0.6)
		d:Hide()
		dimmers[i] = d
	end
end

--- Position the four dimmer rectangles around the target frame,
--- leaving a "hole" where the target sits.
local function positionDimmers(target)
	ensureDimmers()

	if(not target or not target:IsShown()) then
		-- No valid target: dim the entire screen
		local d = dimmers[1]
		d:ClearAllPoints()
		d:SetAllPoints(UIParent)
		d:Show()
		for i = 2, 4 do
			dimmers[i]:Hide()
		end
		return
	end

	local screenW = GetScreenWidth()
	local screenH = GetScreenHeight()

	local left   = target:GetLeft()   or 0
	local right  = target:GetRight()  or screenW
	local top    = target:GetTop()    or screenH
	local bottom = target:GetBottom() or 0

	-- Clamp
	left   = math.max(0, left)
	right  = math.min(screenW, right)
	top    = math.min(screenH, top)
	bottom = math.max(0, bottom)

	-- Top dimmer (above target)
	local topD = dimmers[1]
	topD:ClearAllPoints()
	topD:SetPoint('TOPLEFT',     UIParent, 'BOTTOMLEFT',  0, screenH)
	topD:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMLEFT',  screenW, screenH - (screenH - top))
	topD:Show()

	-- Bottom dimmer (below target)
	local botD = dimmers[2]
	botD:ClearAllPoints()
	botD:SetPoint('TOPLEFT',     UIParent, 'BOTTOMLEFT', 0,       screenH - bottom)
	botD:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMLEFT', screenW, screenH)
	botD:Show()

	-- Left dimmer (left of target, vertically between top and bottom dimmers)
	local leftD = dimmers[3]
	leftD:ClearAllPoints()
	leftD:SetPoint('TOPLEFT',     UIParent, 'BOTTOMLEFT', 0,    screenH - bottom)
	leftD:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMLEFT', left, screenH - top)
	leftD:Show()

	-- Right dimmer (right of target)
	local rightD = dimmers[4]
	rightD:ClearAllPoints()
	rightD:SetPoint('TOPLEFT',     UIParent, 'BOTTOMLEFT', right,   screenH - bottom)
	rightD:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMLEFT', screenW, screenH - top)
	rightD:Show()
end

local function hideDimmers()
	for _, d in next, dimmers do
		d:Hide()
	end
end

-- ============================================================
-- Callout Frame Builder
-- ============================================================

local CALLOUT_W = 280
local CALLOUT_H = 140
local PAD       = C.Spacing.normal

local function ensureCallout()
	if(calloutFrame) then return end

	local frame = Widgets.CreateBorderedFrame(UIParent, CALLOUT_W, CALLOUT_H, C.Colors.panel, C.Colors.border)
	frame:SetFrameStrata('FULLSCREEN_DIALOG')
	frame:SetFrameLevel(10)
	frame:Hide()

	-- Accent top border
	local accentLine = frame:CreateTexture(nil, 'OVERLAY')
	accentLine:SetHeight(2)
	accentLine:SetColorTexture(
		C.Colors.accent[1],
		C.Colors.accent[2],
		C.Colors.accent[3],
		C.Colors.accent[4] or 1)
	accentLine:ClearAllPoints()
	accentLine:SetPoint('TOPLEFT',  frame, 'TOPLEFT',  0, 0)
	accentLine:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)

	-- Title
	local titleFS = Widgets.CreateFontString(frame, C.Font.sizeTitle, C.Colors.textActive)
	titleFS:ClearAllPoints()
	Widgets.SetPoint(titleFS, 'TOPLEFT', frame, 'TOPLEFT', PAD, -PAD)
	titleFS:SetWidth(CALLOUT_W - PAD * 2)
	titleFS:SetWordWrap(false)
	frame._title = titleFS

	-- Body
	local bodyFS = Widgets.CreateFontString(frame, C.Font.sizeNormal, C.Colors.textNormal)
	bodyFS:ClearAllPoints()
	Widgets.SetPoint(bodyFS, 'TOPLEFT', titleFS, 'BOTTOMLEFT', 0, -C.Spacing.base)
	bodyFS:SetWidth(CALLOUT_W - PAD * 2)
	bodyFS:SetWordWrap(true)
	frame._body = bodyFS

	-- Counter ("N of 8")
	local counterFS = Widgets.CreateFontString(frame, C.Font.sizeSmall, C.Colors.textSecondary)
	counterFS:ClearAllPoints()
	Widgets.SetPoint(counterFS, 'BOTTOMLEFT', frame, 'BOTTOMLEFT', PAD, PAD)
	frame._counter = counterFS

	-- "Next →" button
	local nextBtn = Widgets.CreateButton(frame, 'Next \226\134\146', 'accent', 80, 22)
	nextBtn:ClearAllPoints()
	Widgets.SetPoint(nextBtn, 'BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -PAD, PAD)
	nextBtn:SetOnClick(function()
		Onboarding.NextStop()
	end)
	frame._nextBtn = nextBtn

	-- "Skip" text button (plain widget style, small)
	local skipBtn = Widgets.CreateButton(frame, 'Skip', 'widget', 55, 22)
	skipBtn:ClearAllPoints()
	Widgets.SetPoint(skipBtn, 'BOTTOMRIGHT', nextBtn, 'BOTTOMLEFT', -C.Spacing.base, 0)
	skipBtn:SetOnClick(function()
		Onboarding.StopTour()
	end)
	frame._skipBtn = skipBtn

	calloutFrame = frame
end

--- Position callout near the target frame, preferring below then above.
local function positionCallout(target)
	if(not calloutFrame) then return end

	calloutFrame:ClearAllPoints()

	if(not target or not target:IsShown()) then
		calloutFrame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
		return
	end

	local screenH = GetScreenHeight()
	local bottom  = target:GetBottom() or 0
	local top     = target:GetTop()    or screenH

	-- Prefer placing callout below target; if not enough room, place above
	if(bottom - CALLOUT_H - C.Spacing.normal > 0) then
		calloutFrame:SetPoint('TOP', target, 'BOTTOM', 0, -C.Spacing.normal)
	elseif(top + CALLOUT_H + C.Spacing.normal < screenH) then
		calloutFrame:SetPoint('BOTTOM', target, 'TOP', 0, C.Spacing.normal)
	else
		-- Fallback: right of target
		calloutFrame:SetPoint('LEFT', target, 'RIGHT', C.Spacing.normal, 0)
	end
end

--- Update callout text and counter for the given stop index.
local function updateCallout(stopIndex)
	if(not calloutFrame) then return end

	local stop = TOUR_STOPS[stopIndex]
	if(not stop) then return end

	calloutFrame._title:SetText(stop.title)
	calloutFrame._body:SetText(stop.body)
	calloutFrame._counter:SetText(stopIndex .. ' of ' .. TOTAL_STOPS)

	-- Last stop: rename Next button to Done
	if(stopIndex >= TOTAL_STOPS) then
		calloutFrame._nextBtn._label:SetText('Done')
	else
		calloutFrame._nextBtn._label:SetText('Next \226\134\146')
	end

	-- Position near target
	local target = stop.getTarget and stop.getTarget()
	positionDimmers(target)
	positionCallout(target)
end

-- ============================================================
-- Public API
-- ============================================================

--- Check whether the tour is currently active.
--- @return boolean
function Onboarding.IsTourActive()
	return tourActive
end

--- Start the guided tour from the first stop (or resume from saved state).
function Onboarding.StartTour()
	-- Make sure settings window is open
	if(F.Settings) then
		F.Settings.Show()
	end

	ensureDimmers()
	ensureCallout()

	-- Resume from saved character state if available
	local saved = F.Config:GetChar('tourState')
	if(saved and saved.lastStep and not saved.completed) then
		currentStop = saved.lastStep
	else
		currentStop = 1
	end

	tourActive = true

	updateCallout(currentStop)
	calloutFrame:Show()
end

--- Advance to the next tour stop, or finish the tour on the last stop.
function Onboarding.NextStop()
	if(not tourActive) then return end

	currentStop = currentStop + 1

	if(currentStop > TOTAL_STOPS) then
		Onboarding.StopTour()
		return
	end

	-- Persist progress
	F.Config:SetChar('tourState', { completed = false, lastStep = currentStop })

	updateCallout(currentStop)
end

--- Stop and clean up the tour.
function Onboarding.StopTour()
	tourActive = false

	hideDimmers()

	if(calloutFrame) then
		calloutFrame:Hide()
	end

	-- Mark tour as completed in character-scoped config
	F.Config:SetChar('tourState', { completed = true, lastStep = currentStop })
end
