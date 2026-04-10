local addonName, Framed = ...
local F = Framed
local C = F.Constants
local Widgets = F.Widgets

local Shared = F.LiveUpdate.FrameConfigShared
local ForEachFrame = Shared.ForEachFrame

-- ============================================================
-- Party Pets live update
-- partyPets config lives at presets.<name>.partyPets, not inside
-- unitConfigs, so it needs its own CONFIG_CHANGED handler.
-- ============================================================

F.EventBus:Register('CONFIG_CHANGED', function(path)
	local presetName, petKey = path:match('presets%.([^%.]+)%.partyPets%.?(.*)$')
	if(not presetName) then return end
	if(presetName ~= F.AutoSwitch.GetCurrentPreset()) then return end

	local petCfg = F.Units.Party.GetPetConfig()

	-- Enabled toggle
	if(petKey == 'enabled') then
		F.Units.Party.SetPetsEnabled(petCfg.enabled ~= false)
		return
	end

	-- Spacing: re-anchor pet frames to owners
	if(petKey == 'spacing') then
		F.Units.Party.AnchorPetFrames()
		return
	end

	-- Name text changes (show, fontSize, outline, shadow, anchor, offsets)
	if(petKey:match('^name') or petKey == 'showName') then
		local show     = petCfg.showName ~= false
		local fontSize = petCfg.nameFontSize or C.Font.sizeSmall
		local outline  = petCfg.nameOutline or ''
		local shadow   = petCfg.nameShadow ~= false
		local anchor   = petCfg.nameAnchor or 'TOP'
		local offX     = petCfg.nameOffsetX or 0
		local offY     = petCfg.nameOffsetY or -2

		ForEachFrame('partypet', function(frame)
			if(show and not frame.Name) then
				-- Create name text on first enable
				local nameOverlay = CreateFrame('Frame', nil, frame)
				nameOverlay:SetAllPoints(frame)
				nameOverlay:SetFrameLevel(frame:GetFrameLevel() + 5)
				local name = Widgets.CreateFontString(nameOverlay, fontSize, C.Colors.textActive, outline, shadow)
				name:SetPoint(anchor, frame, anchor, offX, offY)
				frame:Tag(name, '[name]')
				frame.Name = name
			end

			if(frame.Name) then
				frame.Name:SetShown(show)
				local fontPath = frame.Name:GetFont()
				if(fontPath) then
					frame.Name:SetFont(fontPath, fontSize, outline)
				end
				if(shadow) then
					frame.Name:SetShadowOffset(1, -1)
					frame.Name:SetShadowColor(0, 0, 0, 1)
				else
					frame.Name:SetShadowOffset(0, 0)
				end
				frame.Name:ClearAllPoints()
				frame.Name:SetPoint(anchor, frame, anchor, offX, offY)
			end
		end)
		return
	end

	-- Health text changes (show, format, fontSize, color, outline, shadow, anchor, offsets)
	if(petKey:match('^healthText') or petKey == 'showHealthText') then
		local show     = petCfg.showHealthText ~= false
		local format   = petCfg.healthTextFormat
		local fontSize = petCfg.healthTextFontSize
		local outline  = petCfg.healthTextOutline
		local shadow   = petCfg.healthTextShadow ~= false
		local colorMode = petCfg.healthTextColor
		local anchor   = petCfg.healthTextAnchor or 'CENTER'
		local offX     = petCfg.healthTextOffsetX
		local offY     = petCfg.healthTextOffsetY

		ForEachFrame('partypet', function(frame)
			if(not frame.Health) then return end
			frame.Health._textFormat    = format
			frame.Health._textColorMode = colorMode

			if(show and not frame.Health.text) then
				-- Create health text on first enable
				local textOverlay = frame._textOverlay
				if(not textOverlay) then
					textOverlay = CreateFrame('Frame', nil, frame)
					textOverlay:SetAllPoints(frame)
					textOverlay:SetFrameLevel(frame:GetFrameLevel() + 5)
					frame._textOverlay = textOverlay
				end
				local text = Widgets.CreateFontString(textOverlay, fontSize, C.Colors.textActive, outline, shadow)
				text:SetPoint(anchor, frame.Health._wrapper or frame.Health, anchor, offX, offY)
				frame.Health.text = text
			end

			-- Update font properties and position on existing text
			if(frame.Health.text) then
				frame.Health.text:SetShown(show)
				local fontPath = frame.Health.text:GetFont()
				if(fontPath) then
					frame.Health.text:SetFont(fontPath, fontSize, outline)
				end
				if(shadow) then
					frame.Health.text:SetShadowOffset(1, -1)
					frame.Health.text:SetShadowColor(0, 0, 0, 1)
				else
					frame.Health.text:SetShadowOffset(0, 0)
				end
				-- Reposition for anchor/offset changes
				frame.Health.text:ClearAllPoints()
				frame.Health.text:SetPoint(anchor, frame.Health._wrapper or frame.Health, anchor, offX, offY)
			end
			if(frame.Health.ForceUpdate) then frame.Health:ForceUpdate() end
		end)
		return
	end
end, 'LiveUpdate.PartyPets')
