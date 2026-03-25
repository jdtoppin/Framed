local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

F.Onboarding = F.Onboarding or {}
local Onboarding = F.Onboarding

-- ============================================================
-- Constants
-- ============================================================

local WIZARD_W    = 450
local WIZARD_H    = 400
local TOTAL_STEPS = 5

local CONTENT_PAD = C.Spacing.loose
local BTN_H       = 26
local BTN_W       = 110

-- ============================================================
-- State
-- ============================================================

local wizardFrame  = nil
local currentStep  = 1
local choices      = { role = nil, content = {}, position = nil }

-- Step content frames (one per step, swapped in/out)
local stepFrames   = {}

-- ============================================================
-- Class-Aware Helpers
-- ============================================================

local function CanDispel()
	local _, class = UnitClass('player')
	local dispelClasses = {
		PALADIN = true,
		PRIEST  = true,
		SHAMAN  = true,
		MONK    = true,
		DRUID   = true,
		MAGE    = true,
		EVOKER  = true,
	}
	return dispelClasses[class] == true
end

local function GetAutoDetectedSpec()
	local specIndex = GetSpecialization() or 1
	local _, specName, _, _, _, role = GetSpecializationInfo(specIndex)
	local _, class = UnitClass('player')
	specName = specName or 'Unknown'
	class    = class    or 'Unknown'
	return specName, class, role
end

-- ============================================================
-- Apply Choices (called on Skip or Done)
-- ============================================================

local function ApplyChoices()
	-- Role → position emphasis + indicator defaults
	-- Content → enable relevant layout presets
	-- Position → set frame positions

	-- Class-aware: enable dispel indicators if applicable
	if(CanDispel()) then
		F.Config:Set('buffsanddebuffs.dispellable.enabled', true)
	end

	-- Mark wizard completed
	F.Config:Set('general.wizardCompleted', true)
end

-- ============================================================
-- Navigation Helpers
-- ============================================================

local function showStep(n)
	for i = 1, TOTAL_STEPS do
		if(stepFrames[i]) then
			stepFrames[i]:Hide()
		end
	end
	if(stepFrames[n]) then
		stepFrames[n]:Show()
	end
	currentStep = n
end

local function goNext()
	if(currentStep < TOTAL_STEPS) then
		showStep(currentStep + 1)
	end
end

local function goBack()
	if(currentStep > 1) then
		showStep(currentStep - 1)
	end
end

local function skipSetup()
	ApplyChoices()
	Onboarding.HideWizard()
end

-- ============================================================
-- Shared Nav Button Row Builder
-- ============================================================

--- Build Back/Next buttons at the bottom of a step frame.
--- @param parent Frame  Step content frame
--- @param showBack boolean  Whether to show Back
--- @param nextLabel string  Label for the forward button (default 'Next')
--- @param onNext function|nil  Override for next action (nil → goNext)
--- @return Frame backBtn, Frame nextBtn
local function buildNavRow(parent, showBack, nextLabel, onNext)
	local nextBtn = Widgets.CreateButton(parent, nextLabel or 'Next', 'accent', BTN_W, BTN_H)
	nextBtn:ClearAllPoints()
	Widgets.SetPoint(nextBtn, 'BOTTOMRIGHT', parent, 'BOTTOMRIGHT', 0, 0)
	nextBtn:SetOnClick(function()
		if(onNext) then
			onNext()
		else
			goNext()
		end
	end)

	local backBtn = nil
	if(showBack) then
		backBtn = Widgets.CreateButton(parent, 'Back', 'widget', BTN_W, BTN_H)
		backBtn:ClearAllPoints()
		Widgets.SetPoint(backBtn, 'BOTTOMLEFT', parent, 'BOTTOMLEFT', 0, 0)
		backBtn:SetOnClick(function()
			goBack()
		end)
	end

	return backBtn, nextBtn
end

-- ============================================================
-- Step Builders
-- ============================================================

--- Step 1: Welcome
local function buildStep1(parent)
	local frame = CreateFrame('Frame', nil, parent)
	frame:SetAllPoints(parent)
	frame:Hide()

	-- Title
	local title = Widgets.CreateFontString(frame, C.Font.sizeTitle, C.Colors.accent)
	title:ClearAllPoints()
	Widgets.SetPoint(title, 'TOPLEFT', frame, 'TOPLEFT', 0, 0)
	title:SetText('Welcome to Framed')

	-- Description
	local desc = Widgets.CreateFontString(frame, C.Font.sizeNormal, C.Colors.textNormal)
	desc:ClearAllPoints()
	Widgets.SetPoint(desc, 'TOPLEFT', title, 'BOTTOMLEFT', 0, -C.Spacing.normal)
	desc:SetWidth(WIZARD_W - CONTENT_PAD * 2)
	desc:SetWordWrap(true)
	desc:SetText(
		'Framed is a modern, customizable unit and raid frame addon.\n\n' ..
		'This quick setup will configure Framed based on your role and ' ..
		'preferred content — it only takes a moment.')

	-- "Let's Go" button
	local goBtn = Widgets.CreateButton(frame, "Let's Go", 'accent', BTN_W, BTN_H)
	goBtn:ClearAllPoints()
	Widgets.SetPoint(goBtn, 'BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
	goBtn:SetOnClick(function()
		goNext()
	end)

	-- "Skip Setup" button
	local skipBtn = Widgets.CreateButton(frame, 'Skip Setup', 'widget', BTN_W, BTN_H)
	skipBtn:ClearAllPoints()
	Widgets.SetPoint(skipBtn, 'BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
	skipBtn:SetOnClick(function()
		skipSetup()
	end)

	return frame
end

--- Step 2: Your Role
local function buildStep2(parent)
	local frame = CreateFrame('Frame', nil, parent)
	frame:SetAllPoints(parent)
	frame:Hide()

	-- Title
	local title = Widgets.CreateFontString(frame, C.Font.sizeTitle, C.Colors.textActive)
	title:ClearAllPoints()
	Widgets.SetPoint(title, 'TOPLEFT', frame, 'TOPLEFT', 0, 0)
	title:SetText('Your Role')

	-- Auto-detected spec
	local specName, class = GetAutoDetectedSpec()
	local specText = Widgets.CreateFontString(frame, C.Font.sizeNormal, C.Colors.textSecondary)
	specText:ClearAllPoints()
	Widgets.SetPoint(specText, 'TOPLEFT', title, 'BOTTOMLEFT', 0, -C.Spacing.base)
	specText:SetText('Detected: ' .. specName .. ' (' .. class .. ')')

	-- Role buttons
	local roleLabels = { 'Tank', 'Healer', 'DPS', 'Multiple Roles' }
	local roleValues = { 'tank', 'healer', 'dps', 'multi' }
	local roleButtons = {}
	local btnW = 96
	local btnGap = C.Spacing.base

	for i, label in next, roleLabels do
		local btn = Widgets.CreateButton(frame, label, 'widget', btnW, BTN_H)
		btn.value = roleValues[i]
		btn:ClearAllPoints()
		local xOff = (i - 1) * (btnW + btnGap)
		Widgets.SetPoint(btn, 'TOPLEFT', specText, 'BOTTOMLEFT', xOff, -C.Spacing.normal)
		roleButtons[#roleButtons + 1] = btn
	end

	-- Button group for radio selection
	local roleGroup = Widgets.CreateButtonGroup(roleButtons, function(value)
		choices.role = value
	end)

	buildNavRow(frame, true)

	return frame
end

--- Step 3: Content Focus
local function buildStep3(parent)
	local frame = CreateFrame('Frame', nil, parent)
	frame:SetAllPoints(parent)
	frame:Hide()

	-- Title
	local title = Widgets.CreateFontString(frame, C.Font.sizeTitle, C.Colors.textActive)
	title:ClearAllPoints()
	Widgets.SetPoint(title, 'TOPLEFT', frame, 'TOPLEFT', 0, 0)
	title:SetText('What do you play?')

	-- Sub-text
	local sub = Widgets.CreateFontString(frame, C.Font.sizeNormal, C.Colors.textSecondary)
	sub:ClearAllPoints()
	Widgets.SetPoint(sub, 'TOPLEFT', title, 'BOTTOMLEFT', 0, -C.Spacing.base)
	sub:SetText('Select all that apply.')

	local options = {
		{ key = 'mythicplus', label = 'M+ Dungeons',   desc = 'Mythic+ and regular dungeon content.' },
		{ key = 'raiding',    label = 'Raiding',        desc = 'Normal, Heroic, and Mythic raids.' },
		{ key = 'pvp',        label = 'PvP / Arena',    desc = 'Arenas, battlegrounds, and rated PvP.' },
		{ key = 'casual',     label = 'Casual / Solo',  desc = 'World quests, open world, and solo play.' },
	}

	local checkYBase = sub
	local checkYOff  = -C.Spacing.normal

	for _, opt in next, options do
		local cbKey  = opt.key
		local cbFrame = Widgets.CreateCheckButton(frame, opt.label, function(checked)
			choices.content[cbKey] = checked or nil
		end)
		cbFrame:ClearAllPoints()
		Widgets.SetPoint(cbFrame, 'TOPLEFT', checkYBase, 'BOTTOMLEFT', 0, checkYOff)

		local descText = Widgets.CreateFontString(frame, C.Font.sizeSmall, C.Colors.textSecondary)
		descText:ClearAllPoints()
		Widgets.SetPoint(descText, 'TOPLEFT', cbFrame, 'BOTTOMLEFT', 20, -C.Spacing.base)
		descText:SetText(opt.desc)

		checkYBase = descText
		checkYOff  = -C.Spacing.tight
	end

	buildNavRow(frame, true)

	return frame
end

--- Step 4: Frame Position
local function buildStep4(parent)
	local frame = CreateFrame('Frame', nil, parent)
	frame:SetAllPoints(parent)
	frame:Hide()

	-- Title
	local title = Widgets.CreateFontString(frame, C.Font.sizeTitle, C.Colors.textActive)
	title:ClearAllPoints()
	Widgets.SetPoint(title, 'TOPLEFT', frame, 'TOPLEFT', 0, 0)
	title:SetText('Frame Position')

	-- Recommendation text (role-aware)
	local recText = Widgets.CreateFontString(frame, C.Font.sizeNormal, C.Colors.textSecondary)
	recText:ClearAllPoints()
	Widgets.SetPoint(recText, 'TOPLEFT', title, 'BOTTOMLEFT', 0, -C.Spacing.base)
	recText:SetWidth(WIZARD_W - CONTENT_PAD * 2)
	recText:SetWordWrap(true)
	recText:SetText('Choose where you want your unit frames on screen.')

	-- Mini preset buttons (bordered frames with a colored dot showing position)
	local presets = {
		{ key = 'bottom_center', label = 'Bottom Center', dotX = 0.5,  dotY = 0.1  },
		{ key = 'left_side',     label = 'Left Side',     dotX = 0.05, dotY = 0.5  },
		{ key = 'top_left',      label = 'Top Left',      dotX = 0.05, dotY = 0.9  },
		{ key = 'center',        label = 'Center',        dotX = 0.5,  dotY = 0.5  },
	}

	local mockW   = 90
	local mockH   = 60
	local mockGap = C.Spacing.tight
	local dotSize = 8

	local presetBtns = {}

	for i, preset in next, presets do
		-- Mini mockup frame (bordered, acts as the button)
		local mock = Widgets.CreateBorderedFrame(frame, mockW, mockH, C.Colors.background, C.Colors.border)
		mock:ClearAllPoints()
		local xOff = (i - 1) * (mockW + mockGap)
		Widgets.SetPoint(mock, 'TOPLEFT', recText, 'BOTTOMLEFT', xOff, -C.Spacing.normal)
		mock:EnableMouse(true)
		mock.value = preset.key

		-- Colored dot showing position
		local dot = mock:CreateTexture(nil, 'OVERLAY')
		dot:SetSize(dotSize, dotSize)
		dot:SetColorTexture(
			C.Colors.accent[1],
			C.Colors.accent[2],
			C.Colors.accent[3],
			C.Colors.accent[4] or 1)
		-- Position dot relative to mockup extents
		local dotRelX = (preset.dotX * mockW) - dotSize / 2
		local dotRelY = -((1 - preset.dotY) * mockH) + dotSize / 2
		dot:ClearAllPoints()
		dot:SetPoint('TOPLEFT', mock, 'TOPLEFT', dotRelX, dotRelY)

		-- Label below mockup
		local lbl = Widgets.CreateFontString(frame, C.Font.sizeSmall, C.Colors.textNormal)
		lbl:ClearAllPoints()
		Widgets.SetPoint(lbl, 'TOP', mock, 'BOTTOM', 0, -C.Spacing.base)
		lbl:SetText(preset.label)

		-- Wrap it in a Button so CreateButtonGroup works
		local btn = Widgets.CreateButton(frame, '', 'widget', mockW, mockH)
		btn:ClearAllPoints()
		btn:SetPoint('TOPLEFT', mock, 'TOPLEFT', 0, 0)
		btn:SetSize(mockW, mockH)
		btn:SetFrameLevel(mock:GetFrameLevel() + 2)
		btn.value = preset.key
		-- Keep the mock visible behind
		btn:SetBackdropColor(0, 0, 0, 0)
		btn:SetBackdropBorderColor(0, 0, 0, 0)

		presetBtns[#presetBtns + 1] = btn
	end

	local posGroup = Widgets.CreateButtonGroup(presetBtns, function(value)
		choices.position = value
	end)

	-- Role-based recommendation text (shown after a role is selected)
	local roleRecText = Widgets.CreateFontString(frame, C.Font.sizeSmall, C.Colors.accent)
	roleRecText:ClearAllPoints()
	local firstMock = presetBtns[1]
	Widgets.SetPoint(roleRecText, 'TOPLEFT', firstMock, 'BOTTOMLEFT', 0, -(C.Spacing.normal + C.Font.sizeSmall + C.Spacing.normal))
	roleRecText:SetWidth(WIZARD_W - CONTENT_PAD * 2)
	roleRecText:SetWordWrap(true)

	-- Update recommendation based on chosen role
	local function updateRoleRec()
		local role = choices.role
		if(role == 'healer') then
			roleRecText:SetText('Recommended for healers: Bottom Center')
			posGroup:SetValue('bottom_center')
		elseif(role == 'tank') then
			roleRecText:SetText('Recommended for tanks: Left Side')
			posGroup:SetValue('left_side')
		elseif(role == 'dps') then
			roleRecText:SetText('Recommended for DPS: Bottom Center')
			posGroup:SetValue('bottom_center')
		elseif(role == 'multi') then
			roleRecText:SetText('Multiple roles: Bottom Center works for most content.')
			posGroup:SetValue('bottom_center')
		else
			roleRecText:SetText('')
		end
	end

	-- Refresh recommendation each time this step is shown
	frame:SetScript('OnShow', function()
		updateRoleRec()
	end)

	buildNavRow(frame, true)

	return frame
end

--- Step 5: Done
local function buildStep5(parent)
	local frame = CreateFrame('Frame', nil, parent)
	frame:SetAllPoints(parent)
	frame:Hide()

	-- Title
	local title = Widgets.CreateFontString(frame, C.Font.sizeTitle, C.Colors.accent)
	title:ClearAllPoints()
	Widgets.SetPoint(title, 'TOPLEFT', frame, 'TOPLEFT', 0, 0)
	title:SetText("You're All Set")

	-- Summary (built dynamically when shown)
	local summaryText = Widgets.CreateFontString(frame, C.Font.sizeNormal, C.Colors.textNormal)
	summaryText:ClearAllPoints()
	Widgets.SetPoint(summaryText, 'TOPLEFT', title, 'BOTTOMLEFT', 0, -C.Spacing.normal)
	summaryText:SetWidth(WIZARD_W - CONTENT_PAD * 2)
	summaryText:SetWordWrap(true)

	local function buildSummary()
		local roleLabel    = choices.role or 'no role selected'
		local contentParts = {}
		for k, _ in next, choices.content do
			contentParts[#contentParts + 1] = k
		end
		local contentLabel = (#contentParts > 0) and table.concat(contentParts, ', ') or 'no content selected'
		local posLabel     = choices.position or 'default'

		summaryText:SetText(
			'Configured as ' .. roleLabel ..
			' doing ' .. contentLabel ..
			'. Frames positioned ' .. posLabel .. '.')
	end

	frame:SetScript('OnShow', function()
		buildSummary()
	end)

	-- "Take the Tour" button
	local tourBtn = Widgets.CreateButton(frame, 'Take the Tour', 'accent', BTN_W, BTN_H)
	tourBtn:ClearAllPoints()
	Widgets.SetPoint(tourBtn, 'BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
	tourBtn:SetOnClick(function()
		ApplyChoices()
		Onboarding.HideWizard()
		if(Onboarding.StartTour) then
			Onboarding.StartTour()
		end
	end)

	-- "I'm Good" button
	local doneBtn = Widgets.CreateButton(frame, "I'm Good", 'widget', BTN_W, BTN_H)
	doneBtn:ClearAllPoints()
	Widgets.SetPoint(doneBtn, 'BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
	doneBtn:SetOnClick(function()
		ApplyChoices()
		Onboarding.HideWizard()
	end)

	-- Back button
	local backBtn = Widgets.CreateButton(frame, 'Back', 'widget', BTN_W, BTN_H)
	backBtn:ClearAllPoints()
	Widgets.SetPoint(backBtn, 'BOTTOM', frame, 'BOTTOM', 0, 0)
	backBtn:SetOnClick(function()
		goBack()
	end)

	return frame
end

-- ============================================================
-- Wizard Frame Construction
-- ============================================================

local function buildWizardFrame()
	if(wizardFrame) then return end

	-- Outer dialog frame
	local frame = Widgets.CreateBorderedFrame(UIParent, WIZARD_W, WIZARD_H, C.Colors.panel, C.Colors.border)
	frame:SetFrameStrata('DIALOG')
	frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
	frame:Hide()

	-- Accent top border (3px)
	local accentBorder = frame:CreateTexture(nil, 'OVERLAY')
	accentBorder:SetHeight(3)
	accentBorder:SetColorTexture(
		C.Colors.accent[1],
		C.Colors.accent[2],
		C.Colors.accent[3],
		C.Colors.accent[4] or 1)
	accentBorder:ClearAllPoints()
	accentBorder:SetPoint('TOPLEFT',  frame, 'TOPLEFT',  0, 0)
	accentBorder:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)

	-- Step counter text (top-right)
	local stepCounter = Widgets.CreateFontString(frame, C.Font.sizeSmall, C.Colors.textSecondary)
	stepCounter:ClearAllPoints()
	Widgets.SetPoint(stepCounter, 'TOPRIGHT', frame, 'TOPRIGHT', -CONTENT_PAD, -CONTENT_PAD)
	frame._stepCounter = stepCounter

	local function updateStepCounter()
		frame._stepCounter:SetText(currentStep .. ' of ' .. TOTAL_STEPS)
	end

	-- Content area (padded inside the dialog)
	local content = CreateFrame('Frame', nil, frame)
	content:ClearAllPoints()
	Widgets.SetPoint(content, 'TOPLEFT',     frame, 'TOPLEFT',     CONTENT_PAD, -CONTENT_PAD)
	Widgets.SetPoint(content, 'BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -CONTENT_PAD, CONTENT_PAD)

	-- Build each step frame
	stepFrames[1] = buildStep1(content)
	stepFrames[2] = buildStep2(content)
	stepFrames[3] = buildStep3(content)
	stepFrames[4] = buildStep4(content)
	stepFrames[5] = buildStep5(content)

	-- Intercept goNext/goBack to also update counter
	local _goNext = goNext
	local _goBack = goBack
	goNext = function()
		_goNext()
		updateStepCounter()
	end
	goBack = function()
		_goBack()
		updateStepCounter()
	end

	wizardFrame = frame
	updateStepCounter()
end

-- ============================================================
-- Public API
-- ============================================================

--- Show the wizard, resetting to step 1.
function Onboarding.ShowWizard()
	if(not wizardFrame) then
		buildWizardFrame()
	end

	-- Reset state
	currentStep       = 1
	choices.role      = nil
	choices.content   = {}
	choices.position  = nil

	showStep(1)

	-- Update step counter
	if(wizardFrame._stepCounter) then
		wizardFrame._stepCounter:SetText('1 of ' .. TOTAL_STEPS)
	end

	wizardFrame:Show()
end

--- Hide the wizard.
function Onboarding.HideWizard()
	if(wizardFrame) then
		wizardFrame:Hide()
	end
end
