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
local overlayFrame = nil
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

-- Forward declarations (defined after nav bar section)
local updateNav

local function showStep(n)
	local oldFrame = stepFrames[currentStep]
	local newFrame = stepFrames[n]

	-- Hide all other step frames (except the one we're fading out)
	for i = 1, TOTAL_STEPS do
		if(stepFrames[i] and i ~= currentStep and i ~= n) then
			stepFrames[i]:Hide()
		end
	end

	currentStep = n

	-- CrossFade between old and new step
	if(oldFrame and newFrame and oldFrame ~= newFrame) then
		newFrame:SetAlpha(0)
		newFrame:Show()
		Widgets.CrossFade(oldFrame, newFrame, C.Animation.durationNormal)
	elseif(newFrame) then
		newFrame:SetAlpha(1)
		newFrame:Show()
	end

	updateNav(n)
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
-- Shared Nav Bar (persistent, outside step frames)
-- ============================================================

local navLeftBtn   = nil  -- Skip Setup / Back / "I'm Good"
local navRightBtn  = nil  -- Let's Go / Next / Take the Tour

--- Update the shared nav bar buttons for the given step.
updateNav = function(step)
	if(not navLeftBtn or not navRightBtn) then return end

	if(step == 1) then
		-- Left: Skip Setup, Right: Let's Go
		navLeftBtn:SetText('Skip Setup')
		navLeftBtn:SetOnClick(function() skipSetup() end)
		navLeftBtn:Show()
		navRightBtn:SetText('Next')
		navRightBtn:SetOnClick(function() goNext() end)
	elseif(step == TOTAL_STEPS) then
		-- Left: Back, Right: Let's Go!
		navLeftBtn:SetText('Back')
		navLeftBtn:SetOnClick(function() goBack() end)
		navLeftBtn:Show()
		navRightBtn:SetText("Let's Go!")
		navRightBtn:SetOnClick(function()
			ApplyChoices()
			Onboarding.HideWizard()
		end)
	else
		-- Left: Back, Right: Next
		navLeftBtn:SetText('Back')
		navLeftBtn:SetOnClick(function() goBack() end)
		navLeftBtn:Show()
		navRightBtn:SetText('Next')
		navRightBtn:SetOnClick(function() goNext() end)
	end
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
	local specName, class, detectedRole = GetAutoDetectedSpec()
	local specText = Widgets.CreateFontString(frame, C.Font.sizeNormal, C.Colors.textSecondary)
	specText:ClearAllPoints()
	Widgets.SetPoint(specText, 'TOPLEFT', title, 'BOTTOMLEFT', 0, -C.Spacing.base)
	specText:SetText('Detected: ' .. specName .. ' (' .. class .. ')')

	-- Role buttons (multi-select toggle, centered)
	local roleLabels = { 'Tank', 'Healer', 'DPS' }
	local roleValues = { 'tank', 'healer', 'dps' }
	choices.roles = choices.roles or {}
	local roleButtons = {}
	local roleBtnW = 96
	local roleBtnGap = C.Spacing.base
	local roleTotalW = #roleLabels * roleBtnW + (#roleLabels - 1) * roleBtnGap
	local roleStartX = (WIZARD_W - CONTENT_PAD * 2 - roleTotalW) / 2

	for i, label in next, roleLabels do
		local btn = Widgets.CreateButton(frame, label, 'widget', roleBtnW, BTN_H)
		btn.value = roleValues[i]
		btn:ClearAllPoints()
		local xOff = roleStartX + (i - 1) * (roleBtnW + roleBtnGap)
		Widgets.SetPoint(btn, 'TOPLEFT', specText, 'BOTTOMLEFT', xOff, -C.Spacing.normal)
		roleButtons[#roleButtons + 1] = btn
	end

	local roleGroup = Widgets.CreateMultiSelectButtonGroup(roleButtons, function(selected)
		choices.roles = selected
	end)

	-- Pre-select detected role
	local roleMap = { TANK = 'tank', HEALER = 'healer', DAMAGER = 'dps' }
	local mappedRole = detectedRole and roleMap[detectedRole]
	if(mappedRole) then
		roleGroup:SetValues({ [mappedRole] = true })
		choices.roles = { [mappedRole] = true }
	end

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

	-- Content buttons (multi-select toggle, two rows of two, centered)
	local contentLabels = { 'M+ Dungeons', 'Raiding', 'PvP / Arena', 'Casual / Solo' }
	local contentValues = { 'mythicplus', 'raiding', 'pvp', 'casual' }
	local contentBtnW = 110
	local contentBtnGap = C.Spacing.base
	local contentButtons = {}
	local contentRowW = 2 * contentBtnW + contentBtnGap
	local contentStartX = (WIZARD_W - CONTENT_PAD * 2 - contentRowW) / 2

	for i, label in next, contentLabels do
		local btn = Widgets.CreateButton(frame, label, 'widget', contentBtnW, BTN_H)
		btn.value = contentValues[i]
		btn:ClearAllPoints()
		local col = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		local xOff = contentStartX + col * (contentBtnW + contentBtnGap)
		local yOff = -(C.Spacing.normal + row * (BTN_H + contentBtnGap))
		Widgets.SetPoint(btn, 'TOPLEFT', sub, 'BOTTOMLEFT', xOff, yOff)
		contentButtons[#contentButtons + 1] = btn
	end

	Widgets.CreateMultiSelectButtonGroup(contentButtons, function(selected)
		choices.content = selected
	end)

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
	local presetTotalW = #presets * mockW + (#presets - 1) * mockGap
	local presetStartX = (WIZARD_W - CONTENT_PAD * 2 - presetTotalW) / 2

	for i, preset in next, presets do
		-- Mini mockup frame (bordered, acts as the button)
		local mock = Widgets.CreateBorderedFrame(frame, mockW, mockH, C.Colors.background, C.Colors.border)
		mock:ClearAllPoints()
		local xOff = presetStartX + (i - 1) * (mockW + mockGap)
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
		local roleParts = {}
		if(choices.roles) then
			for k, _ in next, choices.roles do
				roleParts[#roleParts + 1] = k
			end
		end
		local roleLabel = (#roleParts > 0) and table.concat(roleParts, ', ') or 'no role selected'
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

	return frame
end

-- ============================================================
-- Wizard Frame Construction
-- ============================================================

local function buildWizardFrame()
	if(wizardFrame) then return end

	-- Full-screen dark overlay behind the wizard
	overlayFrame = CreateFrame('Frame', nil, UIParent)
	overlayFrame:SetFrameStrata('DIALOG')
	overlayFrame:SetFrameLevel(0)
	overlayFrame:SetAllPoints(UIParent)
	overlayFrame:Hide()
	local overlayBg = overlayFrame:CreateTexture(nil, 'BACKGROUND')
	overlayBg:SetAllPoints()
	overlayBg:SetColorTexture(0, 0, 0, 0.6)

	-- Outer dialog frame
	local frame = Widgets.CreateBorderedFrame(overlayFrame, WIZARD_W, WIZARD_H, C.Colors.panel, C.Colors.border)
	frame:SetFrameStrata('DIALOG')
	frame:SetFrameLevel(10)
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

	-- ── Shared nav bar (bottom of content, outside step frames) ──
	navLeftBtn = Widgets.CreateButton(content, 'Back', 'widget', BTN_W, BTN_H)
	navLeftBtn:ClearAllPoints()
	Widgets.SetPoint(navLeftBtn, 'BOTTOMLEFT', content, 'BOTTOMLEFT', 0, 0)

	navRightBtn = Widgets.CreateButton(content, 'Next', 'accent', BTN_W, BTN_H)
	navRightBtn:ClearAllPoints()
	Widgets.SetPoint(navRightBtn, 'BOTTOMRIGHT', content, 'BOTTOMRIGHT', 0, 0)

	-- ── Step area (above the nav bar) ─────────────────────────
	local stepArea = CreateFrame('Frame', nil, content)
	stepArea:ClearAllPoints()
	Widgets.SetPoint(stepArea, 'TOPLEFT',     content,  'TOPLEFT',     0, 0)
	Widgets.SetPoint(stepArea, 'BOTTOMRIGHT', content,  'BOTTOMRIGHT', 0, BTN_H + C.Spacing.normal)

	-- Build each step frame
	stepFrames[1] = buildStep1(stepArea)
	stepFrames[2] = buildStep2(stepArea)
	stepFrames[3] = buildStep3(stepArea)
	stepFrames[4] = buildStep4(stepArea)
	stepFrames[5] = buildStep5(stepArea)

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
	choices.roles     = {}
	choices.content   = {}
	choices.position  = nil

	showStep(1)

	-- Update step counter
	if(wizardFrame._stepCounter) then
		wizardFrame._stepCounter:SetText('1 of ' .. TOTAL_STEPS)
	end

	-- Fade in overlay and wizard together
	if(overlayFrame) then
		Widgets.FadeIn(overlayFrame)
	end
	Widgets.FadeIn(wizardFrame)
end

--- Hide the wizard.
function Onboarding.HideWizard()
	if(overlayFrame) then
		Widgets.FadeOut(overlayFrame)
	end
	if(wizardFrame) then
		Widgets.FadeOut(wizardFrame)
	end
end
