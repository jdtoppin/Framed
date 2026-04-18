local _, Framed = ...
local F = Framed
local oUF = F.oUF

F.Units        = F.Units        or {}
F.Units.Pinned = F.Units.Pinned or {}

local MAX_SLOTS = 9

-- ============================================================
-- Config accessor
-- ============================================================
function F.Units.Pinned.GetConfig()
	local presetName = F.PresetManager and F.PresetManager.GetActive()
	if(not presetName) then return nil end
	return F.Config:Get('presets.' .. presetName .. '.unitConfigs.pinned')
end

-- ============================================================
-- Style
-- ============================================================
local function Style(self, unit)
	self:SetFrameStrata('LOW')
	self:RegisterForClicks('AnyUp')
	self._framedUnitType = 'pinned'

	local config = F.Units.Pinned.GetConfig()
	if(config) then
		F.Widgets.SetSize(self, config.width or 160, config.height or 40)
		F.StyleBuilder.Apply(self, config, 'pinned')
	else
		F.Widgets.SetSize(self, 160, 40)
	end

	F.Widgets.RegisterForUIScale(self)
end

-- ============================================================
-- Position
-- ============================================================
function F.Units.Pinned.ApplyPosition()
	local anchor = F.Units.Pinned.anchor
	if(not anchor) then return end
	local config = F.Units.Pinned.GetConfig()
	local pos = (config and config.position) or { x = 0, y = 0, anchor = 'CENTER' }
	anchor:ClearAllPoints()
	anchor:SetPoint(pos.anchor or 'CENTER', UIParent, pos.anchor or 'CENTER', pos.x or 0, pos.y or 0)
end

-- ============================================================
-- Layout (grid)
-- ============================================================
function F.Units.Pinned.Layout()
	local anchor = F.Units.Pinned.anchor
	local frames = F.Units.Pinned.frames
	if(not anchor or not frames) then return end

	local config = F.Units.Pinned.GetConfig()
	if(not config or not config.enabled) then
		anchor:Hide()
		return
	end
	anchor:Show()

	local count   = math.max(1, math.min(config.count   or 3, MAX_SLOTS))
	local columns = math.max(1, math.min(config.columns or 3, count))
	local width   = config.width   or 160
	local height  = config.height  or 40
	local spacing = config.spacing or 2

	for i = 1, MAX_SLOTS do
		local f = frames[i]
		if(f) then
			if(i <= count) then
				local row = math.ceil(i / columns) - 1
				local col = ((i - 1) % columns)
				f:ClearAllPoints()
				f:SetPoint('TOPLEFT', anchor, 'TOPLEFT',
					col * (width + spacing),
					-(row * (height + spacing)))
				F.Widgets.SetSize(f, width, height)
				f:Show()
			else
				f:Hide()
			end
		end
	end

	local rows = math.ceil(count / columns)
	F.Widgets.SetSize(anchor,
		columns * width + (columns - 1) * spacing,
		rows    * height + (rows    - 1) * spacing)
end

-- ============================================================
-- Spawn
-- ============================================================
function F.Units.Pinned.Spawn()
	oUF:RegisterStyle('FramedPinned', Style)
	oUF:SetActiveStyle('FramedPinned')

	local anchor = CreateFrame('Frame', 'FramedPinnedAnchor', UIParent)
	F.Widgets.SetSize(anchor, 1, 1)
	F.Units.Pinned.anchor = anchor
	F.Units.Pinned.ApplyPosition()

	local frames = {}
	for i = 1, MAX_SLOTS do
		local frame = oUF:Spawn('player', 'FramedPinnedFrame' .. i)
		frame:SetParent(anchor)
		frames[i] = frame
	end
	F.Units.Pinned.frames = frames

	F.Units.Pinned.Layout()
end
