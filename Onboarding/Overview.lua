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
local CONTENT_PAD    = 16
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
local isMinimized = false

-- ============================================================
-- Public API (stubs — implemented in later tasks)
-- ============================================================

function Onboarding.ShowOverview()
end

function Onboarding.MinimizeOverview()
end

function Onboarding.RestoreOverview()
end

function Onboarding.CloseOverview()
end

function Onboarding.IsOverviewActive()
	return (modalFrame and modalFrame:IsShown()) or (pipFrame and pipFrame:IsShown()) or false
end
